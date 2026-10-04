import test from 'node:test';
import assert from 'node:assert/strict';
import { decide } from './charge-policy.mjs';
const now = Date.now();
const options = { device: 'kindle-voyage', low: 40, high: 80, maxAgeSeconds: 600 };
const status = n => ({ device: options.device, receivedAt: new Date(now).toISOString(), detail: `Online; battery=${n}; power=discharging; plugged=0` });
test('strict thresholds with hysteresis', () => {
  for (const [n, desired] of [[0,'on'],[39,'on'],[40,null],[60,null],[80,null],[81,'off'],[100,'off']]) assert.equal(decide(status(n), options, now).desired, desired);
});
test('unknown and impossible battery values never switch power', () => {
  for (const n of ['unknown',101,-1,'20.5','20junk','']) assert.equal(decide(status(n), options, now).desired, undefined);
});
test('stale, future, invalid time and wrong device never switch power', () => {
  for (const receivedAt of [new Date(now-601_000).toISOString(),new Date(now+31_000).toISOString(),'invalid']) assert.equal(decide({...status(100),receivedAt},options,now).desired,undefined);
  assert.equal(decide({...status(10),device:'boox-n96'},options,now).desired,undefined);
});
