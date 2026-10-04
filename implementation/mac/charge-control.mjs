#!/usr/bin/env node
import { readFile, writeFile, rename, mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { decide } from './charge-policy.mjs';

const run = promisify(execFile);
const [configPath, mode = '--dry-run'] = process.argv.slice(2);
if (!configPath || !['--dry-run', '--apply'].includes(mode)) throw new Error('usage: charge-control.mjs CONFIG --dry-run|--apply');
const config = JSON.parse(await readFile(configPath, 'utf8'));
if (!(config.low >= 0 && config.low < config.high && config.high <= 100)
    || !(config.maxAgeSeconds >= 60 && config.maxAgeSeconds <= 900)
    || !(config.reassertSeconds >= 60 && config.reassertSeconds <= 3600)) throw new Error('Invalid charge thresholds or freshness settings');
const statePath = join(config.controlDir, 'charge-state.json');
const lock = join(config.controlDir, 'charge-control.lock');
await mkdir(config.controlDir, { recursive: true });
try { await mkdir(lock); } catch (error) {
  if (error.code !== 'EEXIST') throw error;
  // Never break an active controller lock. A leftover lock must be cleared manually.
  console.log(JSON.stringify({ reason: 'already-running-or-leftover-lock' }));
  process.exit(0);
}
try {
  let state = {};
  try { state = JSON.parse(await readFile(statePath, 'utf8')); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  for (const [name, device] of Object.entries(config.devices)) {
    let status;
    try { status = JSON.parse(await readFile(join(config.controlDir, device.statusFile), 'utf8')); }
    catch { console.log(JSON.stringify({ name, reason: 'unreadable-status' })); continue; }
    const decision = decide(status, { ...config, device: device.device });
    const report = { name, ...decision, applied: false };
    if (!decision.desired) { console.log(JSON.stringify(report)); continue; }
    if (mode !== '--apply' || config.enabled !== true || device.verified !== true) {
      console.log(JSON.stringify({ ...report, reason: 'dry-run-or-not-verified' })); continue;
    }
    const previous = state[name];
    if (previous?.desired === decision.desired && Date.now() - previous.appliedAt < config.reassertSeconds * 1000) {
      console.log(JSON.stringify({ ...report, reason: 'already-applied' })); continue;
    }
    const shortcut = device.shortcuts[decision.desired];
    if (typeof shortcut !== 'string' || !shortcut.trim()) throw new Error('Missing shortcut name');
    try {
      await run('/usr/bin/shortcuts', ['run', shortcut], { timeout: 30_000, maxBuffer: 64 * 1024 });
      state[name] = { desired: decision.desired, appliedAt: Date.now(), receivedAt: status.receivedAt };
      const temp = `${statePath}.tmp`;
      await writeFile(temp, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
      await rename(temp, statePath);
      console.log(JSON.stringify({ ...report, applied: true }));
    } catch (error) {
      console.log(JSON.stringify({ ...report, reason: 'shortcut-failed', code: error.code || 'unknown' }));
    }
  }
} finally { await rm(lock, { recursive: true }); }
