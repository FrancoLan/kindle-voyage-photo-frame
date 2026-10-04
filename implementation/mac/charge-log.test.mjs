import test from 'node:test';
import assert from 'node:assert/strict';
import { observeCharging, logRecord } from './charge-log.mjs';
const now = Date.parse('2026-10-04T06:00:00Z');
const status = (time, power = 'charging') => ({ receivedAt: new Date(time).toISOString(), detail: `battery=50; power=${power}` });
const fresh = { reason: 'fresh', battery: 50 };
test('five minute sampling needs fresh new readings and persists across runs', () => {
  let result = observeCharging(status(now), fresh, {}, now);
  assert.deepEqual(result.events.map(x => x.event), ['charging-observed', 'charging-sample']);
  let prev = result.next;
  assert.equal(observeCharging(status(now), fresh, prev, now + 300_000).events.length, 0);
  assert.equal(observeCharging(status(now + 240_000), fresh, prev, now + 240_000).events.length, 0);
  result = observeCharging(status(now + 300_000), fresh, prev, now + 300_000);
  assert.equal(result.events[0].event, 'charging-sample');
  result = observeCharging(status(now + 360_000, 'not-charging'), fresh, result.next, now + 360_000);
  assert.equal(result.events[0].event, 'not-charging-observed');
  assert.equal(result.next.sampledAt, undefined);
});
test('stale telemetry never generates a battery sample', () => {
  const first = observeCharging(null, { reason: 'stale-or-invalid-time' }, { charging: true }, now);
  assert.equal(first.events[0].event, 'telemetry-unavailable');
  assert.equal(observeCharging(null, { reason: 'unknown-battery' }, first.next, now + 60_000).events.length, 0);
});
test('log includes second precision local time and source timestamp', () => {
  const row = logRecord('kindle-voyage', 'switch-command-completed', 39, status(now).receivedAt, now, { switch: 'on' });
  assert.equal(row.timestamp, '2026-10-04T06:00:00.000Z');
  assert.match(row.localTime, /17:00:00/);
  assert.equal(row.battery, 39);
  assert.equal(row.switch, 'on');
});

test('a reading observed before the deadline remains eligible at sampling time', () => {
 const first = observeCharging(status(now), fresh, {}, now);
 const early = observeCharging(status(now + 240_000), fresh, first.next, now + 240_000);
 const due = observeCharging(status(now + 240_000), fresh, early.next, now + 300_000);
 assert.equal(due.events[0].event, 'charging-sample');
 assert.equal(observeCharging(status(now + 240_000), fresh, due.next, now + 600_000).events.length, 0);
});
