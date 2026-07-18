// F4 — memory tools. Hex-dump viewer (paged), poke/peek single word,
// region erase (confirmed), dump-to-file. Backed by /api/memory/*.

import { api } from './api.js';
import { el, clear, hex, parseNum, download } from './dom.js';

// The /api/memory/read response shape is abstracted by the backend; be tolerant
// of the common encodings so the UI degrades gracefully. Returns Uint8Array.
export function decodeMemPayload(res) {
  if (!res) return new Uint8Array(0);
  if (Array.isArray(res.bytes)) return Uint8Array.from(res.bytes.map((b) => b & 0xff));
  if (Array.isArray(res.words)) {
    const out = new Uint8Array(res.words.length * 4);
    res.words.forEach((w, i) => { const v = w >>> 0; out[i*4]=v&0xff; out[i*4+1]=(v>>8)&0xff; out[i*4+2]=(v>>16)&0xff; out[i*4+3]=(v>>24)&0xff; });
    return out;
  }
  const raw = res.hex !== undefined ? res.hex : res.data;
  const enc = res.encoding || (res.hex !== undefined ? 'hex' : 'base64');
  if (typeof raw !== 'string') return new Uint8Array(0);
  if (enc === 'hex') {
    const clean = raw.replace(/[^0-9a-fA-F]/g, '');
    const out = new Uint8Array(clean.length >> 1);
    for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i*2, 2), 16);
    return out;
  }
  try {
    const bin = atob(raw);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  } catch (_) { return new Uint8Array(0); }
}

function hexdumpHtml(addr, bytes) {
  const lines = [];
  for (let off = 0; off < bytes.length; off += 16) {
    const row = bytes.subarray(off, off + 16);
    const hexCells = [];
    let asc = '';
    for (let i = 0; i < 16; i++) {
      if (i < row.length) {
        hexCells.push(row[i].toString(16).padStart(2, '0'));
        asc += (row[i] >= 32 && row[i] < 127) ? String.fromCharCode(row[i]) : '.';
      } else { hexCells.push('  '); asc += ' '; }
      if (i === 7) hexCells.push('');
    }
    lines.push(
      `<span class="off">${(addr + off >>> 0).toString(16).toUpperCase().padStart(8,'0')}</span>  ` +
      hexCells.join(' ') + `  <span class="asc">|${escapeHtml(asc)}|</span>`);
  }
  return lines.join('\n');
}
function escapeHtml(s) { return s.replace(/[&<>]/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;' }[c])); }

class Memory {
  constructor(root) {
    this.root = root;
    this.addr = 0x8000;
    this.length = 256;
    this.mode = 0;
    this.lastBytes = new Uint8Array(0);
    this.lastAddr = 0;
    this._build();
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Memory Tools' }));
    this.root.appendChild(el('p.view-desc', { text: 'Bulk read (mr), single-word peek/poke (@ / !), region erase (me).' }));

    // Dump controls
    const addrIn = el('input', { type: 'text', value: hex(this.addr, 4), spellcheck: 'false' });
    const lenIn = el('input', { type: 'text', value: String(this.length) });
    const modeSel = el('select', null, [
      el('option', { value: '0' }, '0 — ASCII hex'),
      el('option', { value: '1' }, '1 — binary'),
      el('option', { value: '2' }, '2 — compressed'),
    ]);
    this.addrIn = addrIn; this.lenIn = lenIn; this.modeSel = modeSel;

    const dumpCard = el('div.card', null, [
      el('h3', { text: 'Hex dump' }),
      el('div.row', null, [
        el('label.inl', null, ['Address', addrIn]),
        el('label.inl', null, ['Length (bytes)', lenIn]),
        el('label.inl', null, ['Mode', modeSel]),
        el('button.btn.primary', { onclick: () => this.read() }, 'Read'),
        el('span.sp'),
        el('button.btn.small', { onclick: () => this.page(-1) }, '← Prev'),
        el('button.btn.small', { onclick: () => this.page(1) }, 'Next →'),
        el('button.btn.small', { onclick: () => this.saveBin() }, 'Save .bin'),
        el('button.btn.small', { onclick: () => this.saveHex() }, 'Save .hex'),
      ]),
      (this.dumpOut = el('div.hexdump', { html: '<span class="asc">no data — press Read</span>' })),
      (this.dumpMsg = el('p.hint')),
    ]);
    this.root.appendChild(dumpCard);

    // Peek / poke
    const pkAddr = el('input', { type: 'text', value: hex(this.addr, 4), spellcheck: 'false' });
    const pkVal = el('input', { type: 'text', value: '0x00000000', spellcheck: 'false' });
    this.pkAddr = pkAddr; this.pkVal = pkVal;
    const pokeCard = el('div.card', null, [
      el('h3', { text: 'Peek / Poke (single word)' }),
      el('div.row', null, [
        el('label.inl', null, ['Address', pkAddr]),
        el('button.btn', { onclick: () => this.peek() }, 'Peek'),
        el('label.inl', null, ['Value', pkVal]),
        el('button.btn.primary', { onclick: () => this.poke() }, 'Poke'),
      ]),
      (this.pkOut = el('div.result', { style: 'display:none' })),
    ]);
    this.root.appendChild(pokeCard);

    // Erase
    const erAddr = el('input', { type: 'text', value: hex(this.addr, 4), spellcheck: 'false' });
    const erLen = el('input', { type: 'text', value: '256' });
    this.erAddr = erAddr; this.erLen = erLen;
    const eraseCard = el('div.card', null, [
      el('h3', { text: 'Region erase (zero-fill)' }),
      el('div.row', null, [
        el('label.inl', null, ['Address', erAddr]),
        el('label.inl', null, ['Length (bytes)', erLen]),
        el('button.btn.danger', { onclick: () => this.erase() }, 'Erase…'),
      ]),
      (this.erOut = el('div.result', { style: 'display:none' })),
    ]);
    this.root.appendChild(eraseCard);
  }

  _readInputs() {
    const a = parseNum(this.addrIn.value); const l = parseNum(this.lenIn.value);
    if (a === null || l === null || l <= 0) { this.dumpMsg.textContent = 'Invalid address or length.'; return false; }
    this.addr = a >>> 0; this.length = l; this.mode = Number(this.modeSel.value);
    return true;
  }

  async read() {
    if (!this._readInputs()) return;
    this.dumpMsg.textContent = 'reading…';
    try {
      const res = await api.post('/api/memory/read', { addr: this.addr, length: this.length, mode: this.mode });
      const bytes = decodeMemPayload(res);
      this.lastBytes = bytes; this.lastAddr = this.addr;
      this.dumpOut.innerHTML = bytes.length ? hexdumpHtml(this.addr, bytes) : '<span class="asc">(empty)</span>';
      this.dumpMsg.textContent = `${bytes.length} bytes @ ${hex(this.addr, 4)}`;
    } catch (e) {
      this.dumpMsg.textContent = 'read failed: ' + e.message;
    }
  }

  page(dir) {
    if (!this._readInputs()) return;
    this.addr = (this.addr + dir * this.length) >>> 0;
    if (this.addr < 0) this.addr = 0;
    this.addrIn.value = hex(this.addr, 4);
    this.read();
  }

  async peek() {
    const a = parseNum(this.pkAddr.value);
    if (a === null) { this._pk('invalid address', 'err'); return; }
    try {
      const res = await api.post('/api/memory/read', { addr: a >>> 0, length: 4, mode: 0 });
      const b = decodeMemPayload(res);
      const v = (b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)) >>> 0;
      this.pkVal.value = hex(v, 8);
      this._pk(`@ ${hex(a, 4)} = ${hex(v, 8)}`, 'ok');
    } catch (e) { this._pk('peek failed: ' + e.message, 'err'); }
  }

  async poke() {
    const a = parseNum(this.pkAddr.value); const v = parseNum(this.pkVal.value);
    if (a === null || v === null) { this._pk('invalid address or value', 'err'); return; }
    try {
      const res = await api.post('/api/memory/write', { addr: a >>> 0, words: [v >>> 0], verify: true });
      const ok = !res || res.verified !== false;
      this._pk(`! ${hex(v, 8)} -> ${hex(a, 4)} ${ok ? '(verified)' : '(VERIFY MISMATCH)'}`, ok ? 'ok' : 'err');
    } catch (e) { this._pk('poke failed: ' + e.message, 'err'); }
  }
  _pk(text, kind) { this.pkOut.style.display = 'block'; this.pkOut.className = 'result ' + kind; this.pkOut.textContent = text; }

  async erase() {
    const a = parseNum(this.erAddr.value); const l = parseNum(this.erLen.value);
    if (a === null || l === null || l <= 0) { this._er('invalid address or length', 'err'); return; }
    if (!confirm(`Erase ${l} bytes at ${hex(a, 4)}? This zero-fills RAM.`)) return;
    try {
      await api.post('/api/memory/erase', { addr: a >>> 0, length: l });
      this._er(`erased ${l} bytes @ ${hex(a, 4)}`, 'ok');
    } catch (e) { this._er('erase failed: ' + e.message, 'err'); }
  }
  _er(text, kind) { this.erOut.style.display = 'block'; this.erOut.className = 'result ' + kind; this.erOut.textContent = text; }

  saveBin() {
    if (!this.lastBytes.length) return;
    download(`mem_${hex(this.lastAddr, 4).slice(2)}.bin`, new Blob([this.lastBytes], { type: 'application/octet-stream' }));
  }
  saveHex() {
    if (!this.lastBytes.length) return;
    download(`mem_${hex(this.lastAddr, 4).slice(2)}.hex`, new Blob([hexdumpHtml(this.lastAddr, this.lastBytes).replace(/<[^>]+>/g, '')], { type: 'text/plain' }));
  }
}

export function initMemory(root) { return new Memory(root); }
