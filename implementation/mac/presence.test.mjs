import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {matchPresenceEvent,readPresence,writePresence} from './presence.mjs';
test('scoped token only accepts home or away event routes',()=>{
 const token='a'.repeat(64);
 assert.equal(matchPresenceEvent('/v1/presence/event/'+token+'/home',token),'home');
 assert.equal(matchPresenceEvent('/v1/presence/event/'+token+'/away',token),'away');
 assert.equal(matchPresenceEvent('/v1/presence/event/'+token+'/restart',token),null);
 assert.equal(matchPresenceEvent('/v1/presence/event/'+'b'.repeat(64)+'/home',token),null);
});
test('disabled mode and missing state do not invent occupancy; persistence logs events',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'presence-test-'));
 try {
  assert.equal(await readPresence(dir,false),'disabled');assert.equal(await readPresence(dir,true),'unknown');
  await writePresence(dir,'home');assert.equal(await readPresence(dir,true),'home');
  await writePresence(dir,'away');assert.equal(await readPresence(dir,true),'away');
  assert.equal((await readFile(join(dir,'presence-events.jsonl'),'utf8')).trim().split('\n').length,2);
  await assert.rejects(writePresence(dir,'restart'));
 }finally{await rm(dir,{recursive:true});}
});
