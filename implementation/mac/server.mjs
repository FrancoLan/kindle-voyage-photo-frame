#!/usr/bin/env node

import { createReadStream } from 'node:fs';
import { randomBytes, timingSafeEqual } from 'node:crypto';
import { mkdir, readFile, rename, stat, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { dirname, extname, join, resolve } from 'node:path';

const configPath = process.argv[2];
if (!configPath) throw new Error('usage: server.mjs /path/to/config.json');
const config = JSON.parse(await readFile(configPath, 'utf8'));
const publicDir = resolve(config.dataDir, 'public');
const controlDir = resolve(config.dataDir, 'control');
const tokenPath = resolve(config.authTokenFile);
const MAX_STATUS_BYTES = 16 * 1024;
const MAX_DIAGNOSTIC_BYTES = 1024 * 1024;

async function loadAuthToken() {
  try {
    const token = (await readFile(tokenPath, 'utf8')).trim();
    if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('invalid token');
    return token;
  } catch (error) {
    if (error.code !== 'ENOENT') throw new Error(`Invalid auth token file: ${tokenPath}`);
    await mkdir(dirname(tokenPath), { recursive: true });
    const token = randomBytes(32).toString('hex');
    try { await writeFile(tokenPath, `${token}\n`, { mode: 0o600, flag: 'wx' }); } catch (writeError) {
      if (writeError.code !== 'EEXIST') throw writeError;
      return loadAuthToken();
    }
    return token;
  }
}

const authToken = await loadAuthToken();

async function atomicWrite(path, contents, mode = 0o600) {
  await mkdir(dirname(path), { recursive: true });
  const temp = `${path}.tmp.${process.pid}`;
  await writeFile(temp, contents, { mode });
  await rename(temp, path);
}

async function readRequestBytes(request, limit) {
  const chunks = [];
  let bytes = 0;
  for await (const chunk of request) {
    bytes += chunk.length;
    if (bytes > limit) throw new Error('request body is too large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function readRequestBody(request, limit) {
  return (await readRequestBytes(request, limit)).toString('utf8');
}

function cleanStatusField(value, maxLength = 200) {
  return String(value ?? '').replace(/[\t\r\n\0]/g, ' ').trim().slice(0, maxLength);
}

function parseStatus(body, remoteAddress) {
  const values = {};
  for (const line of body.split(/\r?\n/)) {
    if (!line || line.startsWith('#')) continue;
    const split = line.indexOf('\t');
    if (split < 1) throw new Error('invalid status line');
    const key = line.slice(0, split);
    if (!['device', 'commandId', 'action', 'result', 'appState', 'appVersion', 'detail'].includes(key)) {
      throw new Error('unknown status field');
    }
    values[key] = cleanStatusField(line.slice(split + 1));
  }
  if (!/^[A-Za-z0-9._-]{1,64}$/.test(values.device || '')) throw new Error('invalid device');
  if (values.commandId && !/^[a-f0-9-]{36}$/.test(values.commandId)) throw new Error('invalid command id');
  if (values.action && !/^(heartbeat|restart|disable|enable|update|uninstall|diagnose)$/.test(values.action)) throw new Error('invalid action');
  if (!/^(ok|error|running)$/.test(values.result || '')) throw new Error('invalid result');
  if (values.appState && !/^(running|stopped|missing)$/.test(values.appState)) throw new Error('invalid app state');
  return {
    schemaVersion: 1,
    receivedAt: new Date().toISOString(),
    remoteAddress,
    device: values.device,
    commandId: values.commandId || null,
    action: values.action || 'heartbeat',
    result: values.result,
    appState: values.appState || null,
    appVersion: values.appVersion || null,
    detail: values.detail || '',
  };
}

function authorized(request) {
  const supplied = request.headers.authorization || '';
  const expected = `Bearer ${authToken}`;
  const left = Buffer.from(supplied);
  const right = Buffer.from(expected);
  return left.length === right.length && timingSafeEqual(left, right);
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url || '/', 'http://localhost');
  if (!authorized(request)) {
    response.writeHead(401, { 'WWW-Authenticate': 'Bearer', 'Cache-Control': 'no-store' }).end('Unauthorized\n');
    return;
  }
  const diagnosticMatch = url.pathname.match(/^\/v1\/control\/diagnostics\/([a-f0-9-]{36})$/);
  if (request.method === 'POST' && diagnosticMatch) {
    try {
      const bytes = await readRequestBytes(request, MAX_DIAGNOSTIC_BYTES);
      if (bytes.length < 3 || bytes[0] !== 0x1f || bytes[1] !== 0x8b || bytes[2] !== 0x08) throw new Error('diagnostic is not gzip data');
      await atomicWrite(join(controlDir, 'diagnostics', `${diagnosticMatch[1]}.tar.gz`), bytes);
      response.writeHead(204, { 'Cache-Control': 'no-store' }).end();
    } catch (error) {
      response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' }).end(`${error.message}\n`);
    }
    return;
  }
  if (request.method === 'POST' && url.pathname === '/v1/control/status') {
    try {
      const body = await readRequestBody(request, MAX_STATUS_BYTES);
      const status = parseStatus(body, request.socket.remoteAddress || '');
      await atomicWrite(join(controlDir, 'status.json'), `${JSON.stringify(status, null, 2)}\n`);
      response.writeHead(204, { 'Cache-Control': 'no-store' }).end();
    } catch (error) {
      response.writeHead(400, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' }).end(`${error.message}\n`);
    }
    return;
  }
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, { Allow: 'GET, HEAD, POST' }).end();
    return;
  }
  let path;
  if (url.pathname === '/health') path = resolve(config.dataDir, 'health.json');
  else if (url.pathname === '/v1/manifest') path = join(publicDir, 'v1', 'manifest.tsv');
  else if (/^\/v1\/images\/[a-f0-9]{64}\.png$/.test(url.pathname)) path = join(publicDir, url.pathname);
  else if (url.pathname === '/v1/control/command') path = join(controlDir, 'command.tsv');
  else if (/^\/v1\/control\/packages\/[a-f0-9]{64}\.tar\.gz$/.test(url.pathname)) path = join(controlDir, url.pathname.slice('/v1/control/'.length));
  else {
    response.writeHead(404).end('Not found\n');
    return;
  }
  try {
    const info = await stat(path);
    const type = extname(path) === '.png' ? 'image/png' : path.endsWith('.json') ? 'application/json' : path.endsWith('.tar.gz') ? 'application/gzip' : 'text/tab-separated-values; charset=utf-8';
    response.writeHead(200, {
      'Content-Type': type,
      'Content-Length': info.size,
      'Cache-Control': extname(path) === '.png' || path.endsWith('.tar.gz') ? 'private, max-age=31536000, immutable' : 'no-store',
      'X-Content-Type-Options': 'nosniff',
    });
    if (request.method === 'HEAD') response.end();
    else createReadStream(path).pipe(response);
    if (url.pathname.startsWith('/v1/control/packages/')) {
      console.log(`Package request ${request.socket.remoteAddress || ''} ${url.pathname} 200 ${info.size}`);
    }
  } catch (error) {
    if (url.pathname.startsWith('/v1/control/packages/')) {
      console.error(`Package request ${request.socket.remoteAddress || ''} ${url.pathname} 503 ${error.code || error.message}`);
    }
    response.writeHead(503).end('Not ready\n');
  }
});

server.listen(Number(config.port || 8787), config.listenHost || '127.0.0.1', () => {
  const address = server.address();
  console.log(`Kindle photoframe server listening on ${address.address}:${address.port}`);
});
