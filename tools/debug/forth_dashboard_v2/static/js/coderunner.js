// F5 — code runner. Load a .bin, write it word-wise into RAM with a real
// (client-chunked) progress bar, then jump the PC via /api/exec (call0..call4).

import { api } from './api.js';
import { el, clear, hex, parseNum } from './dom.js';

const CHUNK_WORDS = 64; // words per /api/memory/write request -> real progress

class CodeRunner {
  constructor(root) {
    this.root = root;
    this.words = null;      // Uint32Array of the loaded image
    this.fileName = '';
    this.loadAddr = 0x8000;
    this._build();
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Code Runner' }));
    this.root.appendChild(el('p.view-desc', { text: 'Load a .bin, write it into RAM (word-wise, verified), then jump the PC to run it.' }));
    this.root.appendChild(el('div.notice', { text: 'Flow: 1) pick a .bin  2) set the RAM load address  3) Write to RAM  4) set the entry address + args  5) Run.' }));

    // Step 1 — file
    const fileIn = el('input', { type: 'file', accept: '.bin,application/octet-stream' });
    fileIn.addEventListener('change', (e) => this._onFile(e.target.files[0]));
    this.fileInfo = el('span.hint', { text: 'no file loaded' });
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: '1 · Image' }),
      el('div.row', null, [fileIn, this.fileInfo]),
    ]));

    // Step 2 — write to RAM
    this.loadIn = el('input', { type: 'text', value: hex(this.loadAddr, 4), spellcheck: 'false' });
    this.progBar = el('span');
    this.writeMsg = el('span.hint');
    this.writeBtn = el('button.btn.primary', { onclick: () => this.writeToRam(), disabled: true }, 'Write to RAM');
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: '2 · Write to RAM' }),
      el('div.row', null, [
        el('label.inl', null, ['Load address', this.loadIn]),
        this.writeBtn, this.writeMsg,
      ]),
      el('div.progress', { style: 'margin-top:10px' }, this.progBar),
    ]));

    // Step 3 — run
    this.entryIn = el('input', { type: 'text', value: hex(this.loadAddr, 4), spellcheck: 'false' });
    this.argEls = [];
    const argRow = el('div.row.tight');
    for (let i = 0; i < 4; i++) {
      const a = el('input', { type: 'text', value: '', placeholder: `arg${i}`, style: 'width:110px' });
      this.argEls.push(a);
      argRow.appendChild(el('label.inl', null, [`arg${i}`, a]));
    }
    this.runOut = el('div.result', { style: 'display:none' });
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: '3 · Run (jump the PC)' }),
      el('div.row', null, [el('label.inl', null, ['Entry address', this.entryIn])]),
      el('p.hint', { text: 'Args are passed left-to-right; used count picks call0..call4 (leave blank to omit).' }),
      argRow,
      el('div.row', { style: 'margin-top:8px' }, el('button.btn.primary', { onclick: () => this.run() }, 'Run')),
      this.runOut,
    ]));
  }

  async _onFile(file) {
    if (!file) return;
    const buf = new Uint8Array(await file.arrayBuffer());
    const nwords = Math.ceil(buf.length / 4);
    const words = new Uint32Array(nwords);
    for (let i = 0; i < nwords; i++) {
      words[i] = ((buf[i*4] || 0) | ((buf[i*4+1] || 0) << 8) | ((buf[i*4+2] || 0) << 16) | ((buf[i*4+3] || 0) << 24)) >>> 0;
    }
    this.words = words;
    this.fileName = file.name;
    this.fileInfo.textContent = `${file.name} — ${buf.length} bytes, ${nwords} words`;
    this.writeBtn.disabled = false;
    this._setProgress(0);
  }

  _setProgress(frac) { this.progBar.style.width = Math.round(frac * 100) + '%'; }

  async writeToRam() {
    if (!this.words) return;
    const base = parseNum(this.loadIn.value);
    if (base === null) { this.writeMsg.textContent = 'invalid load address'; return; }
    this.loadAddr = base >>> 0;
    this.entryIn.value = hex(this.loadAddr, 4);
    this.writeBtn.disabled = true;
    const total = this.words.length;
    let written = 0, mismatch = false;
    try {
      for (let i = 0; i < total; i += CHUNK_WORDS) {
        const slice = Array.from(this.words.subarray(i, i + CHUNK_WORDS));
        const res = await api.post('/api/memory/write', {
          addr: (this.loadAddr + i * 4) >>> 0, words: slice, verify: true,
        });
        if (res && res.verified === false) mismatch = true;
        written += slice.length;
        this._setProgress(written / total);
        this.writeMsg.textContent = `${written}/${total} words`;
      }
      this.writeMsg.textContent = mismatch
        ? `wrote ${total} words — VERIFY MISMATCH`
        : `wrote ${total} words to ${hex(this.loadAddr, 4)} (verified)`;
    } catch (e) {
      this.writeMsg.textContent = 'write failed: ' + e.message;
    } finally {
      this.writeBtn.disabled = false;
    }
  }

  async run() {
    const entry = parseNum(this.entryIn.value);
    if (entry === null) { this._out('invalid entry address', 'err'); return; }
    const args = [];
    for (const a of this.argEls) {
      if (a.value.trim() === '') break; // first blank ends the arg list
      const v = parseNum(a.value);
      if (v === null) { this._out('invalid arg: ' + a.value, 'err'); return; }
      args.push(v >>> 0);
    }
    this._out(`running call${args.length} @ ${hex(entry, 4)}…`, null);
    try {
      const res = await api.post('/api/exec', { addr: entry >>> 0, args });
      const rv = res && res.value !== undefined ? res.value : (res && res.ret !== undefined ? res.ret : res);
      const rvNum = typeof rv === 'number' ? rv : parseNum(String(rv));
      this._out(`call${args.length}(${hex(entry, 4)}${args.length ? ', ' + args.map((x) => hex(x)).join(', ') : ''}) = ` +
        (rvNum !== null ? `${hex(rvNum)}  (${rvNum | 0})` : JSON.stringify(rv)), 'ok');
    } catch (e) {
      this._out('exec failed: ' + e.message, 'err');
    }
  }
  _out(text, kind) { this.runOut.style.display = 'block'; this.runOut.className = 'result' + (kind ? ' ' + kind : ''); this.runOut.textContent = text; }
}

export function initCodeRunner(root) { return new CodeRunner(root); }
