// Shared, single-source-of-truth application state. One object; modules read it
// and subscribe to changes. No scattered DOM flags.

function makeEmitter() {
  const subs = new Set();
  return {
    sub(fn) { subs.add(fn); return () => subs.delete(fn); },
    fire(v) { for (const fn of subs) { try { fn(v); } catch (e) { console.warn(e); } } },
  };
}

export const store = {
  // /api/registers payload {generated_from, chip, peripherals:{...}}
  registers: null,
  // last known /api/status {connected, state, port, baud, banner_seen, uptime}
  status: { connected: false, state: 'DISCONNECTED', port: null, baud: null, banner_seen: false },
  // websocket link to the backend itself (backend up/down)
  link: false,

  _regEv: makeEmitter(),
  _statusEv: makeEmitter(),

  setRegisters(data) { this.registers = data; this._regEv.fire(data); },
  onRegisters(fn) { if (this.registers) fn(this.registers); return this._regEv.sub(fn); },

  setStatus(s) { this.status = Object.assign({}, this.status, s); this._statusEv.fire(this.status); },
  onStatus(fn) { fn(this.status); return this._statusEv.sub(fn); },

  setLink(up) { this.link = up; this._statusEv.fire(this.status); },

  // True only when the chip is in a state that accepts commands.
  chipReady() {
    return this.link && (this.status.state === 'IDLE' || this.status.state === 'BUSY');
  },

  // Flat list of every "PERIPH.REG" name plus every register address (hex),
  // for terminal completion. Built lazily from the register map.
  regNames() {
    const out = [];
    if (!this.registers) return out;
    for (const [pn, p] of Object.entries(this.registers.peripherals)) {
      for (const [rn, r] of Object.entries(p.registers)) {
        out.push(`${pn}.${rn}`);
        out.push('0x' + (r.addr >>> 0).toString(16).toUpperCase());
      }
    }
    return out;
  },
};
