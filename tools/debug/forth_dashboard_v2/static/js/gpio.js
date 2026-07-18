// F7 — GPIO panel. 4 ports x 8 pins. Live PIN dots (polled via register reads
// only while the panel is visible, ~2 Hz). PDIR direction toggles, click-toggle
// output via POUTT, PSEL/PREN quick controls. All I/O through /api/register.

import { api } from './api.js';
import { store } from './store.js';
import { el, clear } from './dom.js';

const POLL_MS = 500; // ~2 Hz

class Gpio {
  constructor(root) {
    this.root = root;
    this.ports = [];         // discovered GPIOn peripherals
    this.pinDots = {};       // "GPIOn" -> [8 dot elements]
    this.cache = {};         // "GPIOn.REG" -> value
    this.active = false;
    this.timer = null;
    this.built = false;
    store.onRegisters(() => this._build());
  }

  _build() {
    if (this.built || !store.registers) return;
    this.built = true;
    this.ports = Object.keys(store.registers.peripherals).filter((n) => /^GPIO\d+$/.test(n)).sort();
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'GPIO' }));
    this.root.appendChild(el('p.view-desc', { text: 'Live pin state (polled while visible). Toggle direction, drive outputs (POUTT), and set select / pull-resistor per pin.' }));

    const grid = el('div.gpio-grid');
    for (const port of this.ports) grid.appendChild(this._buildPort(port));
    this.root.appendChild(grid);
  }

  _buildPort(port) {
    const dots = [];
    const rows = [];
    for (let i = 0; i < 8; i++) {
      const dot = el('span.pin-dot.unk', { title: 'PIN state' });
      dots.push(dot);
      const dir = el('input', { type: 'checkbox', 'aria-label': `${port} P${i} output` });
      dir.addEventListener('change', () => this._writeBit(port, 'PDIR', i, dir.checked));
      const sel = el('input', { type: 'checkbox', 'aria-label': `${port} P${i} sel` });
      sel.addEventListener('change', () => this._writeBit(port, 'PSEL', i, sel.checked));
      const ren = el('input', { type: 'checkbox', 'aria-label': `${port} P${i} pull` });
      ren.addEventListener('change', () => this._writeBit(port, 'PREN', i, ren.checked));

      this.cache[`${port}.dir${i}`] = dir;
      this.cache[`${port}.sel${i}`] = sel;
      this.cache[`${port}.ren${i}`] = ren;

      rows.push(el('div.pin-row', null, [
        dot,
        el('span.pin-name', { text: `P${i}` }),
        el('label.toggle', { title: 'Toggle output (POUTT)' }, [
          el('button.btn.small', { onclick: () => this._toggleOut(port, i) }, 'tgl'),
        ]),
        el('span.row.tight', null, [
          el('label.toggle', { title: 'Direction: checked = output' }, [dir, 'out']),
          el('label.toggle', { title: 'PSEL alt function' }, [sel, 'sel']),
          el('label.toggle', { title: 'PREN pull enable' }, [ren, 'ren']),
        ]),
      ]));
    }
    this.pinDots[port] = dots;
    return el('div.gpio-port', null, [el('h3', { text: port }), ...rows]);
  }

  // ---- lifecycle: app.js calls setActive on view show/hide ----
  setActive(on) {
    // Always clear any pending poll first so re-selecting the view (or a rapid
    // toggle) can never stack overlapping poll loops.
    if (this.timer) { clearTimeout(this.timer); this.timer = null; }
    this.active = on;
    if (on) {
      this._refreshConfig();
      this._poll();
    }
  }

  async _poll() {
    if (!this.active) return;
    if (store.chipReady()) {
      for (const port of this.ports) {
        try {
          const res = await api.get(`/api/register/${port}/PIN`);
          this._setDots(port, coerce(res.value));
        } catch (_) { this._setDots(port, null); }
        if (!this.active) return;
      }
    } else {
      for (const port of this.ports) this._setDots(port, null);
    }
    this.timer = setTimeout(() => this._poll(), POLL_MS);
  }

  _setDots(port, val) {
    const dots = this.pinDots[port];
    if (!dots) return;
    for (let i = 0; i < 8; i++) {
      const d = dots[i];
      if (val === null) { d.className = 'pin-dot unk'; continue; }
      d.className = 'pin-dot' + (((val >> i) & 1) ? ' hi' : '');
    }
  }

  async _refreshConfig() {
    if (!store.chipReady()) return;
    for (const port of this.ports) {
      for (const reg of ['PDIR', 'PSEL', 'PREN']) {
        try {
          const res = await api.get(`/api/register/${port}/${reg}`);
          const v = coerce(res.value);
          const key = { PDIR: 'dir', PSEL: 'sel', PREN: 'ren' }[reg];
          for (let i = 0; i < 8; i++) this.cache[`${port}.${key}${i}`].checked = ((v >> i) & 1) === 1;
        } catch (_) { /* leave unchanged */ }
      }
    }
  }

  async _writeBit(port, reg, bit, on) {
    try {
      const res = await api.get(`/api/register/${port}/${reg}`);
      let v = coerce(res.value);
      v = on ? (v | (1 << bit)) : (v & ~(1 << bit));
      await api.post(`/api/register/${port}/${reg}`, { value: v >>> 0 });
    } catch (e) { console.warn('gpio write', e); }
  }

  async _toggleOut(port, bit) {
    // POUTT toggles the output latch bit written to it.
    try { await api.post(`/api/register/${port}/POUTT`, { value: (1 << bit) >>> 0 }); }
    catch (e) { console.warn('gpio toggle', e); }
  }
}

function coerce(v) {
  if (typeof v === 'number') return v >>> 0;
  if (typeof v === 'string') { const n = /^0x/i.test(v) ? parseInt(v, 16) : parseInt(v, 10); return Number.isNaN(n) ? 0 : n >>> 0; }
  return 0;
}

export function initGpio(root) { return new Gpio(root); }
