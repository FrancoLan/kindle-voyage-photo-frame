import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomBytes} from 'node:crypto';
import {spawn} from 'node:child_process';
import {createServer} from 'node:net';
import {once} from 'node:events';
test('HTTP event credential is restricted to occupancy writes',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'presence-http-'));
 const auth=randomBytes(32).toString('hex'),event=randomBytes(32).toString('hex');
 const probe=createServer();probe.listen(0,'127.0.0.1');await once(probe,'listening');
 const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
 await writeFile(join(dir,'auth'),auth);await writeFile(join(dir,'event'),event);
 await writeFile(join(dir,'config.json'),JSON.stringify({dataDir:join(dir,'data'),authTokenFile:join(dir,'auth'),listenHosts:['127.0.0.1'],port,presenceEnabled:true,presenceTokenFile:join(dir,'event')}));
 const child=spawn(process.execPath,[fileURLToPath(new URL('./server.mjs',import.meta.url)),join(dir,'config.json')],{stdio:['ignore','pipe','pipe']});
 let timer;
 try {
  await new Promise((resolve,reject)=>{
   timer=setTimeout(()=>reject(new Error('Server startup timeout')),10000);
   child.stdout.on('data',data=>{if(String(data).includes('listening')){clearTimeout(timer);resolve();}});
   child.once('error',reject);child.once('exit',code=>reject(new Error('Server exited '+code)));
  });
  const base='http://127.0.0.1:'+port;
  const get=(token)=>fetch(base+'/v1/presence',{headers:token?{Authorization:'Bearer '+token}:{}});
  assert.equal((await get()).status,401);assert.equal((await get(event)).status,401);
  assert.equal(await (await get(auth)).text(),'unknown\n');
  const path=base+'/v1/presence/event/'+event;
  assert.equal((await fetch(path+'/home')).status,405);
  assert.equal((await fetch(path+'/home',{method:'POST'})).status,204);
  assert.equal(await (await get(auth)).text(),'home\n');
  assert.equal((await fetch(path+'/away',{method:'POST'})).status,204);
  assert.equal(await (await get(auth)).text(),'away\n');
  assert.equal((await fetch(path+'/restart',{method:'POST'})).status,401);
  assert.equal((await fetch(base+'/v1/presence/event/'+auth+'/home',{method:'POST'})).status,401);
 }finally{
  clearTimeout(timer);if(child.exitCode===null){child.kill();await once(child,'exit');}
  await rm(dir,{recursive:true});
 }
});
