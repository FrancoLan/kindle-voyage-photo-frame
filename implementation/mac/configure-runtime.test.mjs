import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
test('installer defaults to explicit loopback and rejects wildcard addresses',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'runtime-config-'));
 const script=fileURLToPath(new URL('../../scripts/configure-runtime.mjs',import.meta.url));
 const templates=fileURLToPath(new URL('./launchagents',import.meta.url));
 const args=[script,join(dir,'input.json'),join(dir,'output.json'),dir,dir,join(dir,'data'),dir,process.execPath,dir,templates,dir];
 const album='https://photos.icloud.com/shared/album/test';
 try {
  await writeFile(args[1],JSON.stringify({publicAlbumURL:album}));execFileSync(process.execPath,args);
  assert.deepEqual(JSON.parse(await readFile(args[2],'utf8')).listenHosts,['127.0.0.1']);
  await writeFile(args[1],JSON.stringify({publicAlbumURL:album,listenHosts:['0.0.0.0']}));
  assert.throws(()=>execFileSync(process.execPath,args,{stdio:'pipe'}));
 }finally{await rm(dir,{recursive:true});}
});
