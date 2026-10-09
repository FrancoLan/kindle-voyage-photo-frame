#!/usr/bin/env node
import { readFile, writeFile, mkdir, rename, appendFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { assess } from './battery-alert-policy.mjs';
import { run } from './charge-exec.mjs';
import { logRecord } from './charge-log.mjs';
const config = JSON.parse(await readFile(process.argv[2], 'utf8'));
const lock = join(config.controlDir, 'battery-monitor.lock');
await mkdir(config.controlDir, { recursive: true });
try { await mkdir(lock); } catch (e) { if(e.code === 'EEXIST') process.exit(0); throw e; }
try {
  const path = join(config.controlDir, 'battery-monitor-state.json');
  let state = {};
  try { state = JSON.parse(await readFile(path, 'utf8')); } catch(e) { if(e.code !== 'ENOENT') throw e; }
  for(const [name, device] of Object.entries(config.devices)) {
    if(!/^[a-z0-9_-]+$/i.test(name)) throw new Error('Invalid device name');
    let status; try { status = JSON.parse(await readFile(join(config.controlDir, device.statusFile), 'utf8')); } catch { status = null; }
    const result = assess(status, device.device, state[name]);
    const logs = join(config.controlDir, 'charge-logs'); await mkdir(logs, { recursive: true, mode: 0o700 });
    for(const event of result.events) {
      const { event: type, ...extra } = event;
      await appendFile(join(logs, name + '.jsonl'), JSON.stringify(logRecord(device.device, type, event.battery, status?.receivedAt, Date.now(), extra)) + '\n', { mode: 0o600 });
      if(type === 'battery-alert') {
        try {
          await run('/usr/bin/osascript', ['-e', 'on run argv\ndisplay notification (item 1 of argv) with title (item 2 of argv)\nend run', `${name}: ${event.message}`, '相框电池提醒'], {timeout:10_000,maxBuffer:4096});
        } catch(error) {
          await appendFile(join(logs, name + '.jsonl'), JSON.stringify(logRecord(device.device, 'battery-notification-failed', event.battery, status?.receivedAt, Date.now(), {detail:String(error.message).slice(0,200)})) + '\n', { mode: 0o600 });
          // Retry notification next minute, while preserving the monitoring history.
          delete result.next.active[event.kind];
        }
      }
    }
    state[name] = result.next;
  }
  await writeFile(path+'.tmp', JSON.stringify(state,null,2)+'\n',{mode:0o600}); await rename(path+'.tmp',path);
} finally {await rm(lock,{recursive:true});}
