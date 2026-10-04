#!/usr/bin/env node
import { readFile, writeFile, appendFile, rename, mkdir, rm } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { run } from './charge-exec.mjs';
import { decide } from './charge-policy.mjs';
import { logRecord, observeCharging } from './charge-log.mjs';

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
  const saveState = async () => {
    const temp = `${statePath}.tmp`;
    await writeFile(temp, JSON.stringify(state, null, 2) + '\n', { mode: 0o600 });
    await rename(temp, statePath);
  };
  for (const [name, device] of Object.entries(config.devices)) {
    if (!/^[a-z0-9_-]+$/i.test(name)) throw new Error('Invalid device log name');
    const record = async (event, battery, receivedAt, extra = {}) => {
      if (mode !== '--apply') return;
      const logsDir = join(config.controlDir, 'charge-logs');
      await mkdir(logsDir, { recursive: true, mode: 0o700 });
      await appendFile(join(logsDir, `${name}.jsonl`), JSON.stringify(logRecord(device.device, event, battery, receivedAt, Date.now(), extra)) + '\n', { mode: 0o600 });
    };
    let status;
    try { status = JSON.parse(await readFile(join(config.controlDir, device.statusFile), 'utf8')); }
    catch { status = null; }
    const decision = decide(status, { ...config, device: device.device });
    if (mode === '--apply') {
      const observation = observeCharging(status, decision, state[name]);
      for (const event of observation.events) {
        const { event: kind, ...extra } = event;
        await record(kind, decision.battery, decision.reason === 'fresh' ? status.receivedAt : null, extra);
      }
      state[name] = observation.next;
      await saveState();
    }
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
      await record('switch-command-completed', decision.battery, status.receivedAt, { switch: decision.desired, shortcut });
      state[name] = { ...state[name], desired: decision.desired, appliedAt: Date.now(), receivedAt: status.receivedAt };
      await saveState();
      console.log(JSON.stringify({ ...report, applied: true }));
    } catch (error) {
      await record('switch-command-failed', decision.battery, status.receivedAt, { switch: decision.desired, shortcut, code: error.killed ? 'timeout' : error.code || 'unknown', signal: error.signal || null, detail: String(error.stderr || error.message || '').slice(0, 1000) });
      console.log(JSON.stringify({ ...report, reason: 'shortcut-failed', code: error.code || 'unknown' }));
    }
  }
} finally { await rm(lock, { recursive: true }); }
