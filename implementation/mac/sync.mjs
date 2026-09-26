#!/usr/bin/env node

import { createHash } from 'node:crypto';
import { execFile } from 'node:child_process';
import { mkdir, open, readFile, rename, stat, unlink, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';
import { extractPhotos, fetchAllZoneRecords, resolvePublicShare } from './icloud-source.mjs';

const execFileAsync = promisify(execFile);
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const RENDER_VERSION = 'voyage-1072x1448-gray-face-edge-fill-detailed-address-v6';
const MAX_SOURCE_BYTES = 100 * 1024 * 1024;

async function atomicWrite(path, contents, mode = 0o644) {
  const temp = `${path}.tmp.${process.pid}`;
  await writeFile(temp, contents, { mode });
  await rename(temp, path);
}

async function acquireLock(path) {
  for (let attempt = 0; attempt < 2; attempt += 1) {
    try {
      const handle = await open(path, 'wx', 0o600);
      await handle.writeFile(`${process.pid}\n`);
      await handle.close();
      return async () => { try { await unlink(path); } catch {} };
    } catch (error) {
      if (error.code !== 'EEXIST') throw error;
      let active = false;
      try {
        const pid = Number((await readFile(path, 'utf8')).trim());
        if (Number.isInteger(pid) && pid > 1) {
          process.kill(pid, 0);
          active = true;
        }
      } catch (lockError) {
        if (lockError.code === 'EPERM') active = true;
      }
      if (active) return undefined;
      try { await unlink(path); } catch {}
    }
  }
  throw new Error('Unable to acquire synchronization lock');
}

function safeAssetURL(raw) {
  const url = new URL(raw);
  if (url.protocol !== 'https:' || !/(^|\.)icloud-content\.com$/i.test(url.hostname)) {
    throw new Error(`Rejected unexpected asset host: ${url.hostname}`);
  }
  return url;
}

async function downloadPhoto(photo, path) {
  if (photo.resource.size > MAX_SOURCE_BYTES) throw new Error(`Source ${photo.id} exceeds 100 MiB`);
  const response = await fetch(safeAssetURL(photo.resource.downloadURL), {
    signal: AbortSignal.timeout(60_000),
  });
  if (!response.ok) throw new Error(`Photo download failed with HTTP ${response.status}`);
  const contentType = (response.headers.get('content-type') || '').toLowerCase();
  if (!contentType.startsWith('image/') && !contentType.includes('octet-stream')) {
    throw new Error(`Photo download returned ${contentType || 'no content type'}`);
  }
  const bytes = Buffer.from(await response.arrayBuffer());
  if (bytes.length === 0 || bytes.length > MAX_SOURCE_BYTES) throw new Error('Photo download size is invalid');
  if (Number(photo.resource.size) && bytes.length !== Number(photo.resource.size)) {
    throw new Error(`Photo download was truncated: expected ${photo.resource.size}, received ${bytes.length}`);
  }
  await writeFile(path, bytes, { mode: 0o600 });
}

async function imageDimensions(path) {
  const { stdout } = await execFileAsync('/usr/bin/sips', ['-g', 'pixelWidth', '-g', 'pixelHeight', path]);
  const width = Number(stdout.match(/pixelWidth:\s*(\d+)/)?.[1]);
  const height = Number(stdout.match(/pixelHeight:\s*(\d+)/)?.[1]);
  if (!width || !height) throw new Error(`Unable to read dimensions for ${path}`);
  return { width, height };
}

async function renderForVoyage(source, output, workDir, metadataLabel, renderMode = 'auto') {
  const decoded = join(workDir, 'decoded.png');
  const normalized = join(workDir, 'normalized.png');
  const { stdout: orientationOutput } = await execFileAsync(join(SCRIPT_DIR, 'metadata-overlay'), ['--orientation', source]);
  const orientation = Number(orientationOutput.trim()) || 1;
  await execFileAsync('/usr/bin/sips', ['-s', 'format', 'png', source, '-o', decoded]);
  let renderInput = decoded;
  if (orientation === 3 || orientation === 6 || orientation === 8) {
    const degrees = orientation === 3 ? 180 : orientation === 6 ? 90 : 270;
    await execFileAsync('/usr/bin/sips', ['-r', String(degrees), decoded, '-o', normalized]);
    renderInput = normalized;
  }
  const annotated = join(workDir, 'annotated.png');
  await execFileAsync(join(SCRIPT_DIR, 'metadata-overlay'), [renderInput, annotated, metadataLabel, renderMode]);
  await execFileAsync('/usr/bin/sips', [
    '-m', '/System/Library/ColorSync/Profiles/Generic Gray Gamma 2.2 Profile.icc',
    '-s', 'format', 'png', annotated, '-o', output,
  ]);
  const finalDimensions = await imageDimensions(output);
  if (finalDimensions.width !== 1072 || finalDimensions.height !== 1448) {
    throw new Error(`Rendered image has wrong dimensions: ${finalDimensions.width}x${finalDimensions.height}`);
  }
}

async function sha256File(path) {
  const bytes = await readFile(path);
  return createHash('sha256').update(bytes).digest('hex');
}

async function loadPriorManifest(path) {
  try { return JSON.parse(await readFile(path, 'utf8')); } catch { return undefined; }
}

async function decodeLocation(encoded, workDir) {
  if (!encoded) return undefined;
  const path = join(workDir, 'location.bplist');
  try {
    await writeFile(path, Buffer.from(encoded, 'base64'), { mode: 0o600 });
    const [{ stdout: latitudeRaw }, { stdout: longitudeRaw }] = await Promise.all([
      execFileAsync('/usr/bin/plutil', ['-extract', 'lat', 'raw', '-o', '-', path], { timeout: 5_000 }),
      execFileAsync('/usr/bin/plutil', ['-extract', 'lon', 'raw', '-o', '-', path], { timeout: 5_000 }),
    ]);
    const latitude = Number(latitudeRaw.trim());
    const longitude = Number(longitudeRaw.trim());
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude) || Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return undefined;
    return { latitude, longitude };
  } catch {
    return undefined;
  }
}

function captureTimeLabel(photo) {
  const capturedAt = Number(photo.capturedAt);
  const offset = Number(photo.timeZoneOffset);
  if (!Number.isFinite(capturedAt) || capturedAt <= 0) return '';
  const safeOffset = Number.isFinite(offset) && Math.abs(offset) <= 18 * 60 * 60 ? offset : 0;
  return new Date(capturedAt + safeOffset * 1000).toISOString().slice(0, 16).replace('T', ' ');
}

async function reverseGeocode(location, cache) {
  const key = `address-v2:${location.latitude.toFixed(4)},${location.longitude.toFixed(4)}`;
  if (typeof cache[key] === 'string' && cache[key]) return cache[key];
  try {
    const { stdout } = await execFileAsync(
      join(SCRIPT_DIR, 'reverse-geocode'),
      [String(location.latitude), String(location.longitude)],
      { timeout: 20_000 },
    );
    const label = stdout.trim().replace(/\s+/g, ' ').slice(0, 80);
    if (label) {
      cache[key] = label;
      return label;
    }
  } catch {}
  return '';
}

async function metadataForPhoto(photo, stagingDir, geocodeCache) {
  const metadataKey = createHash('sha256').update(photo.locationEncoded || photo.id).digest('hex');
  const metadataDir = join(stagingDir, `metadata-${metadataKey}`);
  await mkdir(metadataDir, { recursive: true });
  const location = await decodeLocation(photo.locationEncoded, metadataDir);
  const locationText = location ? await reverseGeocode(location, geocodeCache) : '';
  const capturedAtText = captureTimeLabel(photo) || 'Time unavailable';
  return {
    locationText,
    capturedAtText,
    label: [locationText, capturedAtText].filter(Boolean).join('  ·  '),
  };
}

async function sync(config) {
  const dataDir = resolve(config.dataDir);
  const stagingDir = join(dataDir, 'staging');
  const imageDir = join(dataDir, 'public', 'v1', 'images');
  const publicDir = join(dataDir, 'public');
  await Promise.all([mkdir(stagingDir, { recursive: true }), mkdir(imageDir, { recursive: true })]);

  const share = await resolvePublicShare(config.publicAlbumURL);
  const records = await fetchAllZoneRecords(share);
  const photos = extractPhotos(records);
  if (photos.length === 0) throw new Error('The album contains no supported static photos');

  const prior = await loadPriorManifest(join(publicDir, 'v1', 'manifest.json'));
  const geocodeCache = await loadPriorManifest(join(dataDir, 'geocode-cache.json')) || {};
  const items = [];
  for (const photo of photos) {
    const metadata = await metadataForPhoto(photo, stagingDir, geocodeCache);
    const renderMode = Array.isArray(config.fitPhotoIds) && config.fitPhotoIds.includes(photo.id) ? 'fit' : 'auto';
    const cacheKey = createHash('sha256').update(`${photo.id}\0${photo.resource.fileChecksum || photo.resource.referenceChecksum || photo.resource.size}\0${RENDER_VERSION}\0${renderMode}\0${metadata.label}`).digest('hex');
    const priorItem = prior?.items?.find((item) => item.cacheKey === cacheKey);
    if (priorItem) {
      try {
        const existing = join(imageDir, `${priorItem.sha256}.png`);
        const info = await stat(existing);
        if (info.size === priorItem.bytes && await sha256File(existing) === priorItem.sha256) {
          items.push(priorItem);
          continue;
        }
      } catch {}
    }
    const workDir = join(stagingDir, cacheKey);
    await mkdir(workDir, { recursive: true });
    const source = join(workDir, 'source.image');
    const rendered = join(workDir, 'rendered.png');
    await downloadPhoto(photo, source);
    await renderForVoyage(source, rendered, workDir, metadata.label, renderMode);
    const sha256 = await sha256File(rendered);
    const bytes = (await stat(rendered)).size;
    const finalPath = join(imageDir, `${sha256}.png`);
    try { await stat(finalPath); } catch { await rename(rendered, finalPath); }
    items.push({
      id: photo.id,
      cacheKey,
      sha256,
      bytes,
      capturedAt: photo.capturedAt,
      capturedAtDisplay: metadata.capturedAtText,
      locationDisplay: metadata.locationText,
      renderMode,
      width: 1072,
      height: 1448,
      path: `/v1/images/${sha256}.png`,
    });
  }

  const version = createHash('sha256').update(items.map((item) => item.sha256).join('\n')).digest('hex').slice(0, 16);
  const manifest = {
    schemaVersion: 1,
    albumName: share.albumName,
    version,
    generatedAt: new Date().toISOString(),
    renderVersion: RENDER_VERSION,
    items,
  };
  const manifestJSON = `${JSON.stringify(manifest, null, 2)}\n`;
  const manifestTSV = [
    `# kindle-photoframe-manifest-v1\t${version}\t${items.length}`,
    ...items.map((item) => `${item.sha256}\t${item.bytes}\t${item.path}`),
    '',
  ].join('\n');
  await mkdir(join(publicDir, 'v1'), { recursive: true });
  await atomicWrite(join(publicDir, 'v1', 'manifest.json'), manifestJSON);
  await atomicWrite(join(publicDir, 'v1', 'manifest.tsv'), manifestTSV);
  await atomicWrite(join(dataDir, 'geocode-cache.json'), `${JSON.stringify(geocodeCache, null, 2)}\n`, 0o600);
  await atomicWrite(join(dataDir, 'health.json'), `${JSON.stringify({ ok: true, albumName: share.albumName, version, photoCount: items.length, lastSyncAt: manifest.generatedAt }, null, 2)}\n`);
  return manifest;
}

async function main() {
  const configPath = process.argv[2];
  if (!configPath) throw new Error('usage: sync.mjs /path/to/config.json');
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  await mkdir(resolve(config.dataDir), { recursive: true });
  const releaseLock = await acquireLock(join(resolve(config.dataDir), 'sync.lock'));
  if (!releaseLock) {
    console.log('Synchronization already running; skipped this invocation');
    return;
  }
  try {
    const manifest = await sync(config);
    console.log(`Published ${manifest.items.length} photos as manifest ${manifest.version}`);
  } finally {
    await releaseLock();
  }
}

main().catch(async (error) => {
  const configPath = process.argv[2];
  try {
    if (configPath) {
      const config = JSON.parse(await readFile(configPath, 'utf8'));
      const healthPath = join(resolve(config.dataDir), 'health.json');
      await mkdir(dirname(healthPath), { recursive: true });
      await atomicWrite(healthPath, `${JSON.stringify({ ok: false, lastErrorAt: new Date().toISOString(), error: error.message }, null, 2)}\n`);
    }
  } catch {}
  console.error(error.message);
  process.exit(1);
});
