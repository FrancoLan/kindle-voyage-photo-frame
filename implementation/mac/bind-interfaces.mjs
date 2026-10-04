import { createServer } from 'node:http';
import { networkInterfaces } from 'node:os';
import { isIP } from 'node:net';

export function bindInterfaces(template, addresses, port, options = {}) {
  if (!Array.isArray(addresses) || !addresses.length || addresses.some(address => !isIP(address) || address === '0.0.0.0' || address === '::')) throw new Error('Explicit interface addresses required');
  const listeners = new Map();
  const available = options.available || (() => new Set(Object.values(networkInterfaces()).flat().map(info => info.address)));
  const refresh = () => {
    const assigned = available();
    for (const address of new Set(addresses)) {
      if (!assigned.has(address)) {
        const old = listeners.get(address);
        if (old) { old.close(); old.closeAllConnections(); listeners.delete(address); }
        continue;
      }
      if (listeners.has(address)) continue;
      const listener = createServer(template.listeners('request')[0]);
      for (const callback of template.listeners('clientError')) listener.on('clientError', callback);
      listeners.set(address, listener);
      listener.on('error', error => { listeners.delete(address); listener.close(); options.onError?.(address, error); });
      listener.listen(port, address, () => options.onListen?.(listener.address()));
    }
  };
  refresh();
  const timer = setInterval(refresh, options.interval || 10_000);
  return { refresh, close() { clearInterval(timer); for (const listener of listeners.values()) { listener.close(); listener.closeAllConnections(); } listeners.clear(); } };
}
