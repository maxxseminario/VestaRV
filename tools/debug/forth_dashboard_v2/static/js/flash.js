// F6 — flash programmer. Page-oriented erase/write/read-verify.
// NOTE: the API contract does not expose flash page size/count, so this panel
// takes an explicit page size + start page (friction flagged in the WP3 report).
// Endpoints: /api/flash/erase {page}, /api/flash/write {page, data (base64)},
//            /api/flash/read {addr, length}.

import { api } from './api.js';
import { decodeMemPayload } from './memory.js';
import { el, clear, hex, parseNum } from './dom.js';

function toB64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s);
}

class Flash {
  constructor(root) {
    this.root = root;
    this.image = null;   // Uint8Array
    this.pageSize = 256;
    this.startPage = 0;
    this._build();
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Flash Programmer' }));
    this.root.appendChild(el('p.view-desc', { text: 'Page erase / write / read-verify over the SPI flash (fe / fw / fr). Erase confirmation key is applied server-side.' }));
    this.root.appendChild(el('div.notice', { text: 'The API does not report flash page size/count — set the page size for your device below (default 256 B). Pages are addressed by index from the start page.' }));

    const fileIn = el('input', { type: 'file', accept: '.bin,application/octet-stream' });
    fileIn.addEventListener('change', (e) => this._onFile(e.target.files[0]));
    this.fileInfo = el('span.hint', { text: 'no image loaded' });

    this.pageSizeIn = el('input', { type: 'text', value: '256' });
    this.startPageIn = el('input', { type: 'text', value: '0' });

    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Image' }),
      el('div.row', null, [fileIn, this.fileInfo]),
      el('div.row', null, [
        el('label.inl', null, ['Page size (bytes)', this.pageSizeIn]),
        el('label.inl', null, ['Start page', this.startPageIn]),
      ]),
    ]));

    this.eraseChk = el('input', { type: 'checkbox', checked: true });
    this.verifyChk = el('input', { type: 'checkbox', checked: true });
    this.progBar = el('span');
    this.progMsg = el('span.hint');
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Program' }),
      el('div.row', null, [
        el('label.chk', null, [this.eraseChk, 'Erase each page first']),
        el('label.chk', null, [this.verifyChk, 'Read-back verify']),
        el('span.sp'),
        el('button.btn.primary', { onclick: () => this.program() }, 'Program image…'),
      ]),
      el('div.progress', { style: 'margin-top:10px' }, this.progBar),
      this.progMsg,
    ]));

    // Per-page status
    this.statusBody = el('tbody');
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Per-page status' }),
      el('table.data', null, [
        el('thead', null, el('tr', null, [
          el('th', { text: 'Page' }), el('th', { text: 'Bytes' }),
          el('th', { text: 'Erase' }), el('th', { text: 'Write' }), el('th', { text: 'Verify' }),
        ])),
        this.statusBody,
      ]),
    ]));

    // Standalone erase/read
    this.singlePage = el('input', { type: 'text', value: '0' });
    this.readAddr = el('input', { type: 'text', value: '0x0' });
    this.readLen = el('input', { type: 'text', value: '256' });
    this.miscOut = el('div.result', { style: 'display:none' });
    this.root.appendChild(el('div.card', null, [
      el('h3', { text: 'Single-page tools' }),
      el('div.row', null, [
        el('label.inl', null, ['Page', this.singlePage]),
        el('button.btn.danger', { onclick: () => this.erasePage() }, 'Erase page…'),
        el('span.sp'),
        el('label.inl', null, ['Read addr', this.readAddr]),
        el('label.inl', null, ['Length', this.readLen]),
        el('button.btn', { onclick: () => this.readBack() }, 'Read'),
      ]),
      this.miscOut,
    ]));
  }

  async _onFile(file) {
    if (!file) return;
    this.image = new Uint8Array(await file.arrayBuffer());
    this.fileInfo.textContent = `${file.name} — ${this.image.length} bytes`;
  }

  _params() {
    const ps = parseNum(this.pageSizeIn.value); const sp = parseNum(this.startPageIn.value);
    if (ps === null || ps <= 0 || sp === null) return null;
    this.pageSize = ps; this.startPage = sp >>> 0;
    return true;
  }

  async program() {
    if (!this.image) { this._misc('load an image first', 'err'); return; }
    if (!this._params()) { this._misc('invalid page size / start page', 'err'); return; }
    const npages = Math.ceil(this.image.length / this.pageSize);
    if (!confirm(`Program ${npages} page(s) of ${this.pageSize} B starting at page ${this.startPage}?`)) return;
    clear(this.statusBody);
    let done = 0;
    for (let i = 0; i < npages; i++) {
      const page = this.startPage + i;
      const slice = this.image.subarray(i * this.pageSize, (i + 1) * this.pageSize);
      const row = el('tr', null, [
        el('td', { text: String(page) }), el('td', { text: String(slice.length) }),
        el('td', { text: '—' }), el('td', { text: '—' }), el('td', { text: '—' }),
      ]);
      this.statusBody.appendChild(row);
      const cells = row.children;
      try {
        if (this.eraseChk.checked) { await api.post('/api/flash/erase', { page }); cells[2].textContent = 'ok'; }
        await api.post('/api/flash/write', { page, data: toB64(slice) });
        cells[3].textContent = 'ok';
        if (this.verifyChk.checked) {
          const res = await api.post('/api/flash/read', { addr: page * this.pageSize, length: slice.length });
          const got = decodeMemPayload(res);
          cells[4].textContent = bytesEqual(got, slice) ? 'PASS' : 'FAIL';
          cells[4].style.color = bytesEqual(got, slice) ? 'var(--ok)' : 'var(--err)';
        }
      } catch (e) {
        cells[3].textContent = 'ERR'; cells[3].style.color = 'var(--err)';
        cells[4].textContent = e.message;
      }
      done++;
      this.progBar.style.width = Math.round(done / npages * 100) + '%';
      this.progMsg.textContent = `${done}/${npages} pages`;
    }
    this.progMsg.textContent = `done — ${npages} pages`;
  }

  async erasePage() {
    const p = parseNum(this.singlePage.value);
    if (p === null) { this._misc('invalid page', 'err'); return; }
    if (!confirm(`Erase flash page ${p}?`)) return;
    try { await api.post('/api/flash/erase', { page: p >>> 0 }); this._misc(`erased page ${p}`, 'ok'); }
    catch (e) { this._misc('erase failed: ' + e.message, 'err'); }
  }

  async readBack() {
    const a = parseNum(this.readAddr.value); const l = parseNum(this.readLen.value);
    if (a === null || l === null || l <= 0) { this._misc('invalid addr/length', 'err'); return; }
    try {
      const res = await api.post('/api/flash/read', { addr: a >>> 0, length: l });
      const b = decodeMemPayload(res);
      const preview = Array.from(b.subarray(0, 32)).map((x) => x.toString(16).padStart(2, '0')).join(' ');
      this._misc(`${b.length} bytes @ ${hex(a)}\n${preview}${b.length > 32 ? ' …' : ''}`, 'ok');
    } catch (e) { this._misc('read failed: ' + e.message, 'err'); }
  }

  _misc(text, kind) { this.miscOut.style.display = 'block'; this.miscOut.className = 'result ' + kind; this.miscOut.textContent = text; }
}

function bytesEqual(a, b) {
  if (a.length < b.length) return false;
  for (let i = 0; i < b.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

export function initFlash(root) { return new Flash(root); }
