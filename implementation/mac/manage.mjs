#!/usr/bin/env node

import { createHash, randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { access, cp, mkdir, mkdtemp, readFile, rename, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);
const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const PROJECT_DIR = resolve(SCRIPT_DIR, '..', '..');
const PACKAGE_FILES = [
  ['implementation/kindle', 'kindle-photoframe'],
  ['implementation/kindle-manager', 'kindle-manager'],
];

async function atomicWrite(path, contents, mode = 0o600) {
  await mkdir(dirname(path), { recursive: true });
  const temp = `${path}.tmp.${process.pid}`;
  await writeFile(temp, contents, { mode });
  await rename(temp, path);
}

async function sha256File(path) {
  return createHash('sha256').update(await readFile(path)).digest('hex');
}

async function findPackageSource(config) {
  const candidates = [
    config.packageSourceDir && resolve(config.packageSourceDir),
    PROJECT_DIR,
    join(SCRIPT_DIR, 'package-source'),
  ].filter(Boolean);
  for (const root of candidates) {
    try {
      await access(join(root, 'implementation', 'kindle', 'config.sh'));
      await access(join(root, 'implementation', 'kindle-manager', 'manager.sh'));
      return root;
    } catch {}
  }
  throw new Error('Kindle update source is missing');
}

async function packageUpdate(controlDir, sourceRoot, managerBootstrap = false) {
  const work = await mkdtemp(join(tmpdir(), 'kindle-photoframe-update-'));
  const root = join(work, 'package');
  const payload = join(root, 'payload');
  await mkdir(payload, { recursive: true });
  try {
    const packageFiles = managerBootstrap ? [['implementation/kindle-manager', 'kindle-manager']] : PACKAGE_FILES;
    for (const [source, target] of packageFiles) {
      await cp(join(sourceRoot, source), join(payload, target), {
        recursive: true,
      filter: (path) => !path.includes('/state/') && !path.includes('/cache/') && !path.endsWith('/auth-token') && !path.endsWith('/config.sh'),
      });
    }
    if (managerBootstrap) {
      await mkdir(join(payload, 'kindle-photoframe'), { recursive: true });
      await writeFile(join(payload, 'kindle-photoframe', 'wireless-bootstrap.txt'), 'manager updater bootstrap\n');
    }
    await writeFile(join(payload, 'kindle-manager', 'restart-required'), 'restart wireless manager after update\n');
    await mkdir(join(payload, 'documents'), { recursive: true });
    await cp(join(sourceRoot, 'implementation/kindle/photoframe-start-launcher.sh'), join(payload, 'documents/Photoframe Start.sh'));
    await cp(join(sourceRoot, 'implementation/kindle/photoframe-stop-launcher.sh'), join(payload, 'documents/Photoframe Exit.sh'));

    const { stdout } = await execFileAsync('/usr/bin/find', [payload, '-type', 'f', '-print']);
    const paths = stdout.trim().split('\n').filter(Boolean).sort();
    const rows = ['# kindle-photoframe-update-v1'];
    for (const path of paths) {
      const relative = path.slice(`${payload}/`.length);
      const info = await stat(path);
      rows.push(`${await sha256File(path)}\t${info.size}\t${relative}`);
    }
    rows.push('');
    await writeFile(join(root, 'manifest.tsv'), rows.join('\n'), { mode: 0o600 });
    const archive = join(work, 'update.tar.gz');
    await execFileAsync('/usr/bin/tar', ['-czf', archive, '-C', root, 'manifest.tsv', 'payload']);
    const sha256 = await sha256File(archive);
    const bytes = (await stat(archive)).size;
    const packageDir = join(controlDir, 'packages');
    await mkdir(packageDir, { recursive: true });
    const finalPath = join(packageDir, `${sha256}.tar.gz`);
    try { await stat(finalPath); } catch { await cp(archive, finalPath); }
    return { sha256, bytes, path: `/v1/control/packages/${sha256}.tar.gz` };
  } finally {
    await rm(work, { recursive: true, force: true });
  }
}

function commandText(command) {
  const rows = [
    '# kindle-photoframe-control-v1',
    `id\t${command.id}`,
    `action\t${command.action}`,
    `created\t${command.created}`,
    `expires\t${command.expires}`,
  ];
  if (command.package) {
    rows.push(`packageSha256\t${command.package.sha256}`);
    rows.push(`packageBytes\t${command.package.bytes}`);
    rows.push(`packagePath\t${command.package.path}`);
  }
  rows.push('');
  return rows.join('\n');
}

async function main() {
  const [configPath, action, ...args] = process.argv.slice(2);
  if (!configPath || !action) {
    throw new Error('usage: manage.mjs /path/to/config.json status|restart|disable|enable|update|diagnose|cleanup|uninstall|clear');
  }
  const config = JSON.parse(await readFile(configPath, 'utf8'));
  const controlDir = join(resolve(config.dataDir), 'control');
  await mkdir(controlDir, { recursive: true });
  if (action === 'status') {
    try {
      const status = JSON.parse(await readFile(join(controlDir, 'status.json'), 'utf8'));
      console.log(JSON.stringify(status, null, 2));
    } catch (error) {
      if (error.code === 'ENOENT') console.log(JSON.stringify({ online: false, detail: 'No Kindle status has been received yet.' }, null, 2));
      else throw error;
    }
    return;
  }
  if (action === 'clear') {
    await atomicWrite(join(controlDir, 'command.tsv'), '# kindle-photoframe-control-v1\naction\tnone\n');
    console.log('Pending wireless command cleared.');
    return;
  }
  if (!['restart', 'disable', 'enable', 'update', 'diagnose', 'cleanup', 'uninstall'].includes(action)) throw new Error(`unsupported action: ${action}`);
  if (action === 'uninstall' && !args.includes('--confirm-uninstall')) {
    throw new Error('uninstall requires --confirm-uninstall');
  }
  const now = Math.floor(Date.now() / 1000);
  const command = { id: randomUUID(), action, created: now, expires: now + 24 * 60 * 60 };
  if (action === 'update') command.package = await packageUpdate(controlDir, await findPackageSource(config), args.includes('--manager-bootstrap'));
  await atomicWrite(join(controlDir, 'command.tsv'), commandText(command));
  console.log(JSON.stringify(command, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
