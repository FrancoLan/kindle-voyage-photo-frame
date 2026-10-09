import test from 'node:test';
import assert from 'node:assert/strict';
import { assess } from './battery-alert-policy.mjs';
const t = Date.parse('2026-10-06T00:00:00Z');
const sample = (min,battery=40,power='charging') => ({device:'test',receivedAt:new Date(t+min*60_000).toISOString(),detail:`battery=${battery}; power=${power}`});
test('offline alert deduplicates and recovers',()=>{
 const a=assess(sample(0), 'test',{},t+16*60_000);assert.equal(a.events[0].kind,'offline');
 assert.equal(assess(sample(0),'test',a.next,t+17*60_000).events.length,0);
 assert.equal(assess(sample(18),'test',a.next,t+18*60_000).events[0].event,'battery-alert-recovered');
});
test('stall requires 45 minutes of fresh charging samples; progress recovers',()=>{
 let state={};for(let m=0;m<=40;m+=5) state=assess(sample(m),'test',state,t+m*60_000).next;
 const a=assess(sample(45,41),'test',state,t+45*60_000);assert.equal(a.events[0].kind,'stalled');
 assert.equal(assess(sample(50,42),'test',a.next,t+50*60_000).events[0].event,'battery-alert-recovered');
});
test('repeated telemetry and gaps cannot fabricate a stalled interval',()=>{
 const a=assess(sample(0),'test',{},t);
 assert.equal(assess(sample(0),'test',a.next,t+10*60_000).events.length,0);
 assert.equal(assess(sample(45),'test',a.next,t+45*60_000).events.length,0);
});
test('normal charging and disconnect reset progress',()=>{
 let state={};for(let m=0;m<=60;m+=5){const r=assess(sample(m,40+m/5*2),'test',state,t+m*60_000);assert.equal(r.events.length,0);state=r.next;}
 assert.equal(assess(sample(65,64,'discharging'),'test',state,t+65*60_000).next.progress,undefined);
});
test('wrong device and invalid battery cannot become healthy telemetry',()=>{
 const a=assess(sample(0),'other',{},t);assert.equal(a.events.length,0);
 assert.equal(assess(sample(16),'other',a.next,t+16*60_000).events[0].kind,'offline');
 const b=assess(sample(0,101),'test',{},t);assert.equal(b.events.length,0);
 assert.equal(assess(sample(16,101),'test',b.next,t+16*60_000).events[0].kind,'offline');
});
