// Reconnecting WebSocket client for /ws.
// Server->client events: {type: tx|rx|state|info|error, data, ts}
// Client->server:        {type: "input", data}
//
// Exposes a tiny event bus:
//   bus.on('rx', fn)       serial event of that type
//   bus.on('*', fn)        every serial event
//   bus.on('link', fn)     socket link status: fn(true|false)
//   bus.send({...})        send once connected (dropped silently if not)

function makeBus() {
  const listeners = new Map(); // key -> Set<fn>
  return {
    on(key, fn) {
      if (!listeners.has(key)) listeners.set(key, new Set());
      listeners.get(key).add(fn);
      return () => listeners.get(key).delete(fn);
    },
    emit(key, payload) {
      const s = listeners.get(key);
      if (s) for (const fn of s) { try { fn(payload); } catch (e) { console.warn('bus handler', e); } }
    },
  };
}

class WsClient {
  constructor() {
    this.bus = makeBus();
    this.sock = null;
    this.linked = false;
    this.backoff = 500;          // ms, doubles up to max
    this.maxBackoff = 8000;
    this.timer = null;
    this.stopped = false;
  }

  url() {
    const proto = location.protocol === 'https:' ? 'wss' : 'ws';
    return `${proto}://${location.host}/ws`;
  }

  connect() {
    this.stopped = false;
    this._open();
  }

  _open() {
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    let sock;
    try {
      sock = new WebSocket(this.url());
    } catch (_) {
      return this._scheduleReconnect();
    }
    this.sock = sock;

    sock.onopen = () => {
      this.linked = true;
      this.backoff = 500;
      this.bus.emit('link', true);
    };
    sock.onclose = () => {
      if (this.linked) this.bus.emit('link', false);
      this.linked = false;
      this.sock = null;
      this._scheduleReconnect();
    };
    sock.onerror = () => { try { sock.close(); } catch (_) {} };
    sock.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (_) { return; }
      if (!msg || !msg.type) return;
      this.bus.emit(msg.type, msg);
      this.bus.emit('*', msg);
    };
  }

  _scheduleReconnect() {
    if (this.stopped || this.timer) return;
    this.timer = setTimeout(() => { this.timer = null; this._open(); }, this.backoff);
    this.backoff = Math.min(this.backoff * 2, this.maxBackoff);
  }

  send(obj) {
    if (this.sock && this.linked && this.sock.readyState === WebSocket.OPEN) {
      this.sock.send(JSON.stringify(obj));
      return true;
    }
    return false;
  }

  on(key, fn) { return this.bus.on(key, fn); }
}

export const ws = new WsClient();
