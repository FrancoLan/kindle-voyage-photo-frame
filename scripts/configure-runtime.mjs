#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const [inputConfig, outputConfig, supportDir, runtimeDir, dataDir, packageSourceDir, nodePath, logDir, templateDir, launchAgentDir] = process.argv.slice(2);
if (!launchAgentDir) {
  throw new Error('configure-runtime.mjs received incomplete arguments');
}

const config = JSON.parse(await readFile(inputConfig, 'utf8'));
if (!/^https:\/\/photos\.icloud\.com\/shared\/album\//.test(config.publicAlbumURL || '')) {
  throw new Error('publicAlbumURL must be an iCloud Shared Album public URL');
}
config.dataDir = resolve(dataDir);
config.authTokenFile = resolve(dataDir, 'server-token');
config.packageSourceDir = resolve(packageSourceDir);
config.listenHost = config.listenHost || '0.0.0.0';
config.port = Number(config.port || 8787);
if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) throw new Error('port is invalid');
await writeFile(outputConfig, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });

function xml(value) {
  return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
}

for (const kind of ['server', 'sync']) {
  const source = resolve(templateDir, `io.github.francolan.kindle-voyage-photo-frame.${kind}.plist.template`);
  const target = resolve(launchAgentDir, `io.github.francolan.kindle-voyage-photo-frame.${kind}.plist`);
  let body = await readFile(source, 'utf8');
  const replacements = {
    __NODE__: nodePath,
    __RUNTIME__: runtimeDir,
    __SUPPORT__: supportDir,
    __LOGS__: logDir,
  };
  for (const [key, value] of Object.entries(replacements)) body = body.replaceAll(key, xml(value));
  await writeFile(target, body);
}
