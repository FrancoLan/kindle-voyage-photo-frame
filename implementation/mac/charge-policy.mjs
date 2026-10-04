export function decide(status, options, now = Date.now()) {
  if (!status || status.device !== options.device) return { reason: 'wrong-or-missing-device' };
  const received = Date.parse(status.receivedAt);
  const age = now - received;
  if (!Number.isFinite(age) || age < -30_000 || age > options.maxAgeSeconds * 1000) return { reason: 'stale-or-invalid-time' };
  const match = String(status.detail || '').match(/(?:^|;\s*)battery=(\d{1,3})(?=;|$)/);
  if (!match || Number(match[1]) > 100) return { reason: 'unknown-battery' };
  const battery = Number(match[1]);
  return { battery, desired: battery < options.low ? 'on' : battery > options.high ? 'off' : null, reason: 'fresh' };
}
