// Read-only battery monitoring. No plug control or device commands.
export function assess(status, expectedDevice, previous = {}, now = Date.now()) {
  const next = { ...previous };
  const received = Date.parse(status?.receivedAt);
  const match = String(status?.detail || '').match(/(?:^|;\s*)battery=(\d+)(?:;|$)/);
  const battery = match ? Number(match[1]) : NaN;
  const valid = status?.device === expectedDevice && Number.isInteger(battery) && battery >= 0 && battery <= 100
    && Number.isFinite(received) && received <= now + 30_000;
  const stale = !valid || now - received > 900_000;
  const events = [];
  const issues = {};
  if (stale) {
    next.invalidSince = previous.invalidSince ?? now;
    if ((valid && now - received > 900_000) || now - (previous.lastValidAt ?? next.invalidSince) > 900_000) {
      issues.offline = '超过15分钟没有有效电量回报，请检查设备与 Mac 网络。';
    }
    delete next.progress;
  } else {
    delete next.invalidSince;
    next.lastValidAt = received;
    const charging = /(?:^|;\s*)power=charging(?:;|$)/.test(status.detail);
    if (!charging) delete next.progress;
    else {
      let progress = next.progress;
      if (!progress || received < progress.lastReceived || received - progress.lastReceived > 900_000) {
        progress = { since: received, baseline: battery, lastReceived: received };
      }
      if (received > progress.lastReceived) {
        progress.lastReceived = received;
        if (battery >= progress.baseline + 2) progress = { since: received, baseline: battery, lastReceived: received };
      }
      next.progress = progress;
      // Require device samples covering the full window; repeatedly reading an old sample cannot trigger this.
      if (received - progress.since >= 2_700_000) {
        issues.stalled = `持续充电45分钟，电量未增加至少2个百分点（当前${battery}%），请检查充电线、插座和设备。`;
      }
    }
  }
  const active = { ...(previous.active || {}) };
  for (const kind of Object.keys(active)) {
    if (!issues[kind]) { events.push({ event: 'battery-alert-recovered', kind }); delete active[kind]; }
  }
  for (const [kind, message] of Object.entries(issues)) {
    if (!active[kind] || now - active[kind].at >= 21_600_000) {
      events.push({ event: 'battery-alert', kind, message, battery: stale ? null : battery });
      active[kind] = { at: now };
    }
  }
  next.active = active;
  return { next, events };
}
