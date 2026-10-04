import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { bindInterfaces } from './bind-interfaces.mjs';

test('reject wildcard binding', () => {
 assert.throws(() => bindInterfaces(createServer(), ['0.0.0.0'], 0));
 assert.throws(() => bindInterfaces(createServer(), ['::'], 0));
});
test('explicit endpoints retain request handling and recover after interface return', {timeout:10000}, async () => {
 const template=createServer((request,response)=>response.writeHead(401).end('auth required'));
 const assigned=new Set(['127.0.0.1','::1']);
 const ready=new Map(); let notify;
 const next=()=>new Promise(resolve=>{notify=resolve;});
 const first=next();
 const group=bindInterfaces(template,[...assigned],0,{available:()=>assigned,onListen:address=>{ready.set(address.address,address.port);if(ready.size===2)notify();},onError:(address,error)=>{notify(Promise.reject(error));}});
 try {
  await first;
  for(const [address,port] of ready) assert.equal((await fetch(`http://${address.includes(":") ? `[${address}]` : address}:${port}`)).status,401);
  assigned.delete('127.0.0.1');group.refresh();ready.delete('127.0.0.1');
  assert.equal((await fetch(`http://[::1]:${ready.get('::1')}`)).status,401);
  const returned=next();assigned.add('127.0.0.1');group.refresh();await returned;
  assert.equal((await fetch(`http://127.0.0.1:${ready.get('127.0.0.1')}`)).status,401);
 } finally {group.close();}
});
