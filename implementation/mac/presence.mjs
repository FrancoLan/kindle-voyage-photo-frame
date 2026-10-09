import { readFile, writeFile, rename, appendFile } from 'node:fs/promises';
import { join } from 'node:path';
import { randomUUID, timingSafeEqual } from 'node:crypto';
export function matchPresenceEvent(path, token) {
  const m = path.match(/^\/v1\/presence\/event\/([a-f0-9]{64})\/(home|away)$/);
  return m && /^[a-f0-9]{64}$/.test(token || '') && timingSafeEqual(Buffer.from(m[1]), Buffer.from(token)) ? m[2] : null;
}
export function presenceValue(value) { return ['home','away'].includes(value) ? value : 'unknown'; }
export async function readPresence(controlDir, enabled) {
  if (!enabled) return 'disabled';
  try { return presenceValue(JSON.parse(await readFile(join(controlDir,'presence.json'),'utf8')).state); }
  catch (e) { if(e.code === 'ENOENT') return 'unknown'; throw e; }
}
export async function writePresence(controlDir, state) {
  if(!['home','away'].includes(state)) throw new Error('Invalid presence');
  const row={state,receivedAt:new Date().toISOString()};
  const path=join(controlDir,'presence.json'), temp=path+'.tmp.'+randomUUID();
  await writeFile(temp,JSON.stringify(row)+'\n',{mode:0o600});await rename(temp,path);
  await appendFile(join(controlDir,'presence-events.jsonl'),JSON.stringify(row)+'\n',{mode:0o600});
}
