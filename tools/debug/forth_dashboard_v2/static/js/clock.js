// F8 — clock / system panel. Frequency measurement matrix via /api/clk
// {clock_sel, time_sel}, plus chip reset. The one concretely-known select from
// v1 is "3 1 clk" (time_sel=3, clock_sel=1) = MCLK; the rest are exposed as a
// generic clock_sel matrix so any mux input can be measured.

import { api } from './api.js';
import { el, clear, parseNum } from './dom.js';

// clock_sel labels; MCLK(1) is the one v1 documented. Others are best-guess mux
// inputs and are safe to measure regardless.
const CLOCKS = [
  { sel: 1, name: 'MCLK',  note: 'main clock (v1: 3 1 clk)' },
  { sel: 0, name: 'clk 0', note: 'mux input 0' },
  { sel: 2, name: 'clk 2', note: 'mux input 2' },
  { sel: 3, name: 'clk 3', note: 'mux input 3' },
];

function fmtHz(hz) {
  if (hz === null || Number.isNaN(hz)) return '—';
  if (hz >= 1e6) return (hz / 1e6).toFixed(3).replace(/\.?0+$/, '') + ' MHz';
  if (hz >= 1e3) return (hz / 1e3).toFixed(3).replace(/\.?0+$/, '') + ' kHz';
  return hz + ' Hz';
}
function coerceHz(res) {
  const cand = res && (res.freq !== undefined ? res.freq : (res.value !== undefined ? res.value : (res.hz !== undefined ? res.hz : res)));
  if (typeof cand === 'number') return cand;
  if (typeof cand === 'string') { const n = parseInt(cand, 10); return Number.isNaN(n) ? null : n; }
  return null;
}

class Clock {
  constructor(root) {
    this.root = root;
    this.timeSel = 3;
    this.cards = {};
    this._build();
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Clock / System' }));
    this.root.appendChild(el('p.view-desc', { text: 'Measure clock-mux inputs (clk) and issue a chip reset.' }));

    this.timeIn = el('select', null, [0, 1, 2, 3].map((t) =>
      el('option', { value: String(t), selected: t === 3 }, `${t}${t === 3 ? ' (longest gate)' : ''}`)));
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Measurement' }),
      el('div.row', null, [
        el('label.inl', null, ['Time select (gate)', this.timeIn]),
        el('button.btn', { onclick: () => this.measureAll() }, 'Measure all'),
        el('span.hint', { text: 'Longer gate = more accurate, slower.' }),
      ]),
    ]));

    const grid = el('div.clk-grid');
    for (const c of CLOCKS) {
      const val = el('div.clk-val', { text: '—' });
      this.cards[c.sel] = val;
      grid.appendChild(el('div.clk-card', null, [
        el('div.clk-name', { text: c.name }),
        el('div.clk-sel', { text: `clock_sel ${c.sel} · ${c.note}` }),
        val,
        el('button.btn.small.primary', { onclick: () => this.measure(c.sel) }, 'Measure'),
      ]));
    }
    this.root.appendChild(grid);

    // Custom + reset
    this.customSel = el('input', { type: 'text', value: '1', style: 'width:80px' });
    this.customTime = el('input', { type: 'text', value: '3', style: 'width:80px' });
    this.customOut = el('div.result', { style: 'display:none' });
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Custom measurement' }),
      el('div.row', null, [
        el('label.inl', null, ['clock_sel', this.customSel]),
        el('label.inl', null, ['time_sel', this.customTime]),
        el('button.btn', { onclick: () => this.measureCustom() }, 'Measure'),
      ]),
      this.customOut,
    ]));

    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'System' }),
      el('div.row', null, [
        el('button.btn.warn', { onclick: () => this.reset() }, 'Chip reset'),
        (this.resetOut = el('span.hint')),
      ]),
    ]));
  }

  async measure(sel) {
    const time = Number(this.timeIn.value);
    const card = this.cards[sel];
    if (card) card.textContent = '…';
    try {
      const res = await api.post('/api/clk', { clock_sel: sel, time_sel: time });
      const hz = coerceHz(res);
      if (card) card.textContent = fmtHz(hz);
      return hz;
    } catch (e) {
      if (card) card.textContent = 'err';
      return null;
    }
  }

  async measureAll() { for (const c of CLOCKS) await this.measure(c.sel); }

  async measureCustom() {
    const sel = parseNum(this.customSel.value); const time = parseNum(this.customTime.value);
    if (sel === null || time === null) { this._out('invalid select values', 'err'); return; }
    try {
      const res = await api.post('/api/clk', { clock_sel: sel, time_sel: time });
      const hz = coerceHz(res);
      this._out(`clock_sel=${sel} time_sel=${time} -> ${fmtHz(hz)} (${hz} Hz)`, 'ok');
    } catch (e) { this._out('measure failed: ' + e.message, 'err'); }
  }
  _out(t, k) { this.customOut.style.display = 'block'; this.customOut.className = 'result ' + k; this.customOut.textContent = t; }

  async reset() {
    if (!confirm('Pulse the chip reset line?')) return;
    this.resetOut.textContent = 'resetting…';
    try { await api.post('/api/reset', {}); this.resetOut.textContent = 'reset pulse sent'; }
    catch (e) { this.resetOut.textContent = 'reset failed: ' + e.message; }
  }
}

export function initClock(root) { return new Clock(root); }
