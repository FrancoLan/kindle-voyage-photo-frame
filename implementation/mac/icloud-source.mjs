#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { basename } from 'node:path';

const PHOTOS_CONTAINER = 'com.apple.photos.cloud';
const DEFAULT_TIMEOUT_MS = 30_000;

export function sharingKeyFromURL(value) {
  const url = new URL(value);
  const match = url.pathname.match(/^\/shared\/album\/([A-Za-z0-9_-]+)$/);
  if (!match) throw new Error('Expected an iCloud URL ending in /shared/album/<key>');
  return match[1];
}

async function cloudKitRequest(url, body, timeoutMs = DEFAULT_TIMEOUT_MS) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'text/plain',
      origin: 'https://photos.icloud.com',
      referer: 'https://photos.icloud.com/',
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!response.ok) throw new Error(`CloudKit request failed with HTTP ${response.status}`);
  const contentType = response.headers.get('content-type') || '';
  if (!contentType.toLowerCase().includes('json')) {
    throw new Error(`CloudKit returned unexpected content type: ${contentType || 'missing'}`);
  }
  return response.json();
}

export async function resolvePublicShare(publicURL) {
  const sharingKey = sharingKeyFromURL(publicURL);
  const url = new URL(
    `https://ckdatabasews.icloud.com/database/1/${PHOTOS_CONTAINER}/production/public/records/resolve`,
  );
  url.searchParams.set('remapEnums', 'true');
  url.searchParams.set('getCurrentSyncToken', 'true');
  url.searchParams.set('sharing_url_key', sharingKey);
  const payload = await cloudKitRequest(url, { shortGUIDs: [{ value: sharingKey }] });
  const resolved = payload?.results?.[0];
  if (!resolved || resolved.serverErrorCode) {
    throw new Error(`Unable to resolve public share: ${resolved?.reason || 'invalid response'}`);
  }
  const access = resolved.anonymousPublicAccess;
  if (!access?.databasePartition || !access?.token || !resolved.zoneID) {
    throw new Error('Public share response is missing its partition, token, or zone');
  }
  return {
    albumName: resolved.share?.fields?.['cloudkit.title']?.value || 'Untitled album',
    sharingKey,
    zoneID: resolved.zoneID,
    partition: access.databasePartition,
    token: access.token,
    tokenTTL: access.tokenTTL,
  };
}

function authenticatedURL(share, endpoint) {
  const url = new URL(
    `/database/1/${PHOTOS_CONTAINER}/production/shared/${endpoint}`,
    share.partition,
  );
  url.searchParams.set('remapEnums', 'true');
  url.searchParams.set('getCurrentSyncToken', 'true');
  url.searchParams.set('sharing_url_key', share.sharingKey);
  url.searchParams.set('publicAccessAuthToken', share.token);
  return url;
}

export async function fetchAllZoneRecords(share) {
  const records = [];
  let syncToken;
  for (let page = 0; page < 100; page += 1) {
    const zoneRequest = { zoneID: share.zoneID, resultsLimit: 200 };
    if (syncToken) zoneRequest.syncToken = syncToken;
    const payload = await cloudKitRequest(authenticatedURL(share, 'changes/zone'), {
      zones: [zoneRequest],
    });
    const result = payload?.zones?.[0];
    if (!result || result.serverErrorCode) {
      throw new Error(`Unable to enumerate shared collection: ${result?.reason || 'invalid response'}`);
    }
    if (Array.isArray(result.records)) records.push(...result.records);
    if (!result.moreComing) return records;
    if (!result.syncToken || result.syncToken === syncToken) {
      throw new Error('CloudKit pagination stopped making progress');
    }
    syncToken = result.syncToken;
  }
  throw new Error('CloudKit pagination exceeded 100 pages');
}

function field(record, name) {
  return record?.fields?.[name]?.value;
}

function chooseResource(asset, master) {
  const candidates = [
    ['asset-full', field(asset, 'resJPEGFullRes')],
    ['master-full', field(master, 'resJPEGFullRes')],
    ['master-large', field(master, 'resJPEGLargeRes')],
    ['asset-medium', field(asset, 'resJPEGMedRes')],
    ['master-medium', field(master, 'resJPEGMedRes')],
    ['master-original', field(master, 'resOriginalRes')],
  ];
  for (const [kind, resource] of candidates) {
    if (resource?.downloadURL && Number(resource.size) > 0) return { kind, ...resource };
  }
  return undefined;
}

export function extractPhotos(records) {
  const masters = new Map(
    records.filter((record) => record.recordType === 'CPLMaster').map((record) => [record.recordName, record]),
  );
  const photos = [];
  for (const asset of records.filter((record) => record.recordType === 'CPLAsset')) {
    if (Number(field(asset, 'isHidden') || 0) !== 0) continue;
    const masterID = field(asset, 'masterRef')?.recordName;
    const master = masters.get(masterID);
    if (!master) continue;
    const itemType = String(field(master, 'itemType') || '');
    if (itemType.includes('movie') || itemType.includes('video')) continue;
    const resource = chooseResource(asset, master);
    if (!resource) continue;
    photos.push({
      id: asset.recordName,
      masterID,
      capturedAt: Number(field(asset, 'assetDate') || field(master, 'originalCreationDate') || 0),
      locationEncoded: String(field(asset, 'locationEnc') || ''),
      timeZoneNameEncoded: String(field(asset, 'timeZoneNameEnc') || ''),
      timeZoneOffset: Number(field(asset, 'timeZoneOffset') || 0),
      orientation: Number(field(asset, 'orientation') || field(master, 'originalOrientation') || 1),
      sourceWidth: Number(field(asset, 'resJPEGFullWidth') || field(master, 'resOriginalWidth') || 0),
      sourceHeight: Number(field(asset, 'resJPEGFullHeight') || field(master, 'resOriginalHeight') || 0),
      resource,
    });
  }
  return photos.sort((a, b) => b.capturedAt - a.capturedAt || a.id.localeCompare(b.id));
}

function describeRecord(record) {
  return {
    recordName: record.recordName,
    recordType: record.recordType,
    fieldKeys: Object.keys(record.fields || {}).sort(),
  };
}

async function main() {
  const [command, configPath] = process.argv.slice(2);
  if (command !== 'probe' || !configPath) {
    console.error(`usage: ${basename(process.argv[1])} probe /path/to/config.json`);
    process.exit(2);
  }
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const share = await resolvePublicShare(config.publicAlbumURL);
  const records = await fetchAllZoneRecords(share);
  const summary = {
    albumName: share.albumName,
    recordCount: records.length,
    recordTypes: [...new Set(records.map((record) => record.recordType))].sort(),
    records: records.map(describeRecord),
  };
  if (config.probeOutput) {
    await writeFile(config.probeOutput, `${JSON.stringify(summary, null, 2)}\n`, { mode: 0o600 });
  }
  if (config.rawProbeOutput) {
    await writeFile(config.rawProbeOutput, `${JSON.stringify({ records }, null, 2)}\n`, { mode: 0o600 });
  }
  console.log(JSON.stringify({ albumName: summary.albumName, recordCount: summary.recordCount, recordTypes: summary.recordTypes }));
}

if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exit(1);
  });
}
