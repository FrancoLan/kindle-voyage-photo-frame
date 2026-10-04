export function logRecord(device, event, battery, receivedAt, now = Date.now(), extra = {}) {
  return {
    timestamp: new Date(now).toISOString(),
    localTime: new Intl.DateTimeFormat('sv-SE', { timeZone: 'Australia/Sydney', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', timeZoneName: 'shortOffset', hour12: false }).format(now),
    device, event, battery: battery ?? null, batteryReceivedAt: receivedAt ?? null, ...extra,
  };
}

export function observeCharging(status, decision, previous = {}, now = Date.now()) {
  const next = { ...previous };
  const events = [];
  if (decision.reason !== 'fresh') {
    if (!previous.unavailableAt || now - previous.unavailableAt >= 300_000) {
      events.push({ event: 'telemetry-unavailable', reason: decision.reason });
      next.unavailableAt = now;
    }
    return { next, events };
  }
  delete next.unavailableAt;
  // Only new device telemetry can confirm charging or provide a new sample.
  const isNewObservation = previous.observedReceivedAt !== status.receivedAt;
  next.observedReceivedAt = status.receivedAt;
  const power = String(status.detail || '').match(/(?:^|;\s*)power=([^;]+)/)?.[1]?.trim();
  const charging = power === 'charging' ? true : ['not-charging', 'discharging', 'full'].includes(power) ? false : null;
  if (charging === null) return { next, events };
  if (isNewObservation && previous.charging !== charging) events.push({ event: charging ? 'charging-observed' : 'not-charging-observed', power });
  next.charging = charging;
  if (charging && previous.sampleReceivedAt !== status.receivedAt && (!previous.sampledAt || now - previous.sampledAt >= 300_000)) {
    events.push({ event: 'charging-sample', power });
    next.sampledAt = now;
    next.sampleReceivedAt = status.receivedAt;
  }
  if (!charging) delete next.sampledAt;
  return { next, events };
}
