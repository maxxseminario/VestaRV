// F3 — register browser. Peripheral tree -> register detail with field editors.
// Reads/writes via /api/register/{periph}/{reg}; write is readback-verified by
// the backend and we display the verified value it returns.

import { api } from './api.js';
import { store } from './store.js';
import { el, clear, hex, parseNum } from './dom.js';

class Registers {
  constructor(root) {
    this.root = root;
    this.sel = null;        // {periph, reg}
    this.values = new Map(); // "PERIPH.REG" -> last-read raw value (chip truth)
    this.built = false;
  }

  mount() {
    if (this.built) return;
    store.onRegisters(() => this._build());
  }

  _build() {
    if (!store.registers) return;
    this.built = true;
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Register Browser' }));
    this.root.appendChild(el('p.view-desc', { text: 'Live view of the Myshkin peripheral register map. Edit fields, then Write (readback-verified).' }));

    const tree = el('div.reg-tree');
    const detail = el('div.reg-detail', { id: 'reg-detail' });
    this.detail = detail;

    const periphs = store.registers.peripherals;
    for (const [pn, p] of Object.entries(periphs)) {
      const det = el('details.reg-periph');
      det.appendChild(el('summary', null, [
        document.createTextNode(pn),
        el('span.reg-base', { text: hex(p.base_addr, 4) }),
      ]));
      const regNames = Object.keys(p.registers).sort((a, b) => p.registers[a].addr - p.registers[b].addr);
      for (const rn of regNames) {
        const r = p.registers[rn];
        const row = el('div.reg-reg', {
          dataset: { key: `${pn}.${rn}` },
          onclick: () => this._select(pn, rn),
        }, [
          document.createTextNode(rn),
          el('span.a', { text: hex(r.addr, 4) }),
        ]);
        det.appendChild(row);
      }
      tree.appendChild(det);
    }

    this.root.appendChild(el('div.reg-layout', null, [tree, detail]));
    detail.appendChild(el('p.hint', { text: 'Select a register from the tree.' }));
  }

  _select(pn, rn) {
    this.sel = { periph: pn, reg: rn };
    for (const n of this.root.querySelectorAll('.reg-reg.sel')) n.classList.remove('sel');
    const node = this.root.querySelector(`.reg-reg[data-key="${pn}.${rn}"]`);
    if (node) { node.classList.add('sel'); node.closest('details').open = true; }
    this._renderDetail();
  }

  _renderDetail() {
    const { periph, reg } = this.sel;
    const r = store.registers.peripherals[periph].registers[reg];
    const d = this.detail;
    clear(d);

    d.appendChild(el('div.reg-head', null, [
      el('span.rname', { text: `${periph}.${reg}` }),
      el('span.pill', { text: hex(r.addr, 4) }),
      el('span.pill', { text: `${r.size} byte${r.size === 1 ? '' : 's'}` }),
      r.type ? el('span.pill', { text: r.type }) : null,
      el('span.rdesc', { text: r.description || '' }),
    ]));

    // Raw hex value row.
    const rawInput = el('input', { type: 'text', value: '', 'aria-label': 'raw value', spellcheck: 'false' });
    this.rawInput = rawInput;
    rawInput.addEventListener('input', () => { this._syncFieldsFromRaw(); this._markDirty(); });
    d.appendChild(el('div.rawline', null, [
      el('span.hint', { text: 'Raw value' }),
      rawInput,
      el('button.btn.small', { onclick: () => this.read() }, 'Read'),
      el('button.btn.small.primary', { onclick: () => this.write() }, 'Write'),
      el('button.btn.small', { onclick: () => this.readAll() }, 'Read all in ' + periph),
    ]));

    // Field editors.
    const fields = r.fields || {};
    const names = Object.keys(fields).sort((a, b) => fields[a].lsb - fields[b].lsb);
    if (names.length) {
      const tbl = el('table.field-table');
      tbl.appendChild(el('thead', null, el('tr', null, [
        el('th', { text: 'Field' }), el('th', { text: 'Bits' }),
        el('th', { text: 'Value' }), el('th', { text: 'Description' }),
      ])));
      const tb = el('tbody');
      this.fieldEls = {};
      for (const fn of names) {
        const f = fields[fn];
        const bits = f.width === 1 ? `[${f.lsb}]` : `[${f.lsb + f.width - 1}:${f.lsb}]`;
        let editor;
        if (f.values) {
          editor = el('select', { 'aria-label': fn });
          for (const [v, label] of Object.entries(f.values)) {
            editor.appendChild(el('option', { value: v }, `${v} — ${label}`));
          }
        } else {
          editor = el('input', { type: 'text', 'aria-label': fn, spellcheck: 'false' });
        }
        editor.addEventListener('input', () => { this._syncRawFromFields(); this._markDirty(); });
        editor.addEventListener('change', () => { this._syncRawFromFields(); this._markDirty(); });
        this.fieldEls[fn] = editor;
        tb.appendChild(el('tr', { dataset: { field: fn } }, [
          el('td.fname', { text: fn }), el('td.fbits', { text: bits }),
          el('td', null, editor), el('td.fdesc', { text: f.desc || '' }),
        ]));
      }
      tbl.appendChild(tb);
      d.appendChild(tbl);
    } else {
      this.fieldEls = {};
      d.appendChild(el('p.hint', { text: 'No decoded fields — treat as a raw data register.' }));
    }

    this.resultBox = el('div.result', { style: 'display:none' });
    d.appendChild(this.resultBox);

    // Seed from last-known value if we have one.
    const known = this.values.get(`${periph}.${reg}`);
    if (known !== undefined) this._loadValue(known);
    else this._loadValue(0);
    this._clearDirty();
  }

  // ---- value <-> field syncing ----
  _loadValue(v) {
    this.rawInput.value = hex(v, this._hexDigits());
    this._syncFieldsFromRaw();
  }
  _hexDigits() {
    const r = store.registers.peripherals[this.sel.periph].registers[this.sel.reg];
    return r.size * 2;
  }
  _currentRaw() {
    const v = parseNum(this.rawInput.value);
    return v === null ? 0 : (v >>> 0);
  }
  _syncFieldsFromRaw() {
    const raw = this._currentRaw();
    const r = store.registers.peripherals[this.sel.periph].registers[this.sel.reg];
    for (const [fn, f] of Object.entries(r.fields || {})) {
      const mask = f.width >= 32 ? 0xffffffff : ((1 << f.width) - 1);
      const fv = (raw >>> f.lsb) & mask;
      const ed = this.fieldEls[fn];
      if (!ed) continue;
      if (ed.tagName === 'SELECT') {
        if ([...ed.options].some((o) => Number(o.value) === fv)) ed.value = String(fv);
      } else {
        ed.value = hex(fv, Math.ceil(f.width / 4));
      }
    }
  }
  _syncRawFromFields() {
    const r = store.registers.peripherals[this.sel.periph].registers[this.sel.reg];
    let raw = this._currentRaw();
    for (const [fn, f] of Object.entries(r.fields || {})) {
      const ed = this.fieldEls[fn];
      if (!ed) continue;
      const mask = f.width >= 32 ? 0xffffffff : ((1 << f.width) - 1);
      let fv = ed.tagName === 'SELECT' ? Number(ed.value) : (parseNum(ed.value) || 0);
      fv &= mask;
      raw = (raw & ~(mask << f.lsb)) | (fv << f.lsb);
    }
    this.rawInput.value = hex(raw >>> 0, this._hexDigits());
  }

  _markDirty() {
    const known = this.values.get(`${this.sel.periph}.${this.sel.reg}`);
    const cur = this._currentRaw();
    const dirty = known === undefined || (known >>> 0) !== cur;
    this.rawInput.classList.toggle('dirty', dirty);
    // per-field dirty rows
    const r = store.registers.peripherals[this.sel.periph].registers[this.sel.reg];
    for (const [fn, f] of Object.entries(r.fields || {})) {
      const row = this.detail.querySelector(`tr[data-field="${fn}"]`);
      if (!row) continue;
      if (known === undefined) { row.classList.remove('dirty'); continue; }
      const mask = f.width >= 32 ? 0xffffffff : ((1 << f.width) - 1);
      const a = (cur >>> f.lsb) & mask;
      const b = ((known >>> 0) >>> f.lsb) & mask;
      row.classList.toggle('dirty', a !== b);
    }
  }
  _clearDirty() {
    this.rawInput.classList.remove('dirty');
    for (const n of this.detail.querySelectorAll('tr.dirty')) n.classList.remove('dirty');
  }

  _showResult(text, kind) {
    this.resultBox.style.display = 'block';
    this.resultBox.className = 'result' + (kind ? ' ' + kind : '');
    this.resultBox.textContent = text;
  }

  // ---- backend ops ----
  async read() {
    const { periph, reg } = this.sel;
    try {
      const res = await api.get(`/api/register/${periph}/${reg}`);
      const v = coerceInt(res.value);
      this.values.set(`${periph}.${reg}`, v >>> 0);
      this._loadValue(v);
      this._markDirty();
      this._showResult(`READ ${periph}.${reg} = ${hex(v, this._hexDigits())}`, 'ok');
    } catch (e) {
      this._showResult(`READ failed: ${e.message}`, 'err');
    }
  }

  async write() {
    const { periph, reg } = this.sel;
    const value = this._currentRaw();
    try {
      const res = await api.post(`/api/register/${periph}/${reg}`, { value });
      const verified = res && res.value !== undefined ? coerceInt(res.value) : value;
      this.values.set(`${periph}.${reg}`, verified >>> 0);
      this._loadValue(verified);
      this._markDirty();
      const ok = res && res.verified === false ? false : true;
      this._showResult(
        `WROTE ${hex(value, this._hexDigits())} -> readback ${hex(verified, this._hexDigits())}` +
        (ok ? ' (verified)' : ' (VERIFY MISMATCH)'),
        ok ? 'ok' : 'err');
    } catch (e) {
      this._showResult(`WRITE failed: ${e.message}`, 'err');
    }
  }

  async readAll() {
    const { periph } = this.sel;
    const regs = store.registers.peripherals[periph].registers;
    const lines = [];
    for (const rn of Object.keys(regs).sort((a, b) => regs[a].addr - regs[b].addr)) {
      try {
        const res = await api.get(`/api/register/${periph}/${rn}`);
        const v = coerceInt(res.value);
        this.values.set(`${periph}.${rn}`, v >>> 0);
        lines.push(`${rn.padEnd(14)} ${hex(regs[rn].addr, 4)}  ${hex(v, regs[rn].size * 2)}`);
      } catch (e) {
        lines.push(`${rn.padEnd(14)} ERROR ${e.message}`);
      }
    }
    if (this.sel.reg && regs[this.sel.reg]) this._loadValue(this.values.get(`${periph}.${this.sel.reg}`) || 0);
    this._markDirty();
    this._showResult(lines.join('\n'), 'ok');
  }
}

function coerceInt(v) {
  if (typeof v === 'number') return v >>> 0;
  if (typeof v === 'string') return (parseNum(v) || 0) >>> 0;
  return 0;
}

export function initRegisters(root) {
  const r = new Registers(root);
  r.mount();
  return r;
}
