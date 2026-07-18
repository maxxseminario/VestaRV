// F2 — interactive terminal. Renders WS serial events (tx/rx/info/error/state),
// sends input as {type:"input", data}, history, Tab-completion, Ctrl-L, export.

import { ws } from './ws.js';
import { store } from './store.js';
import { el, clear, download } from './dom.js';

// On-chip Forth word set — ROM, never changes.
// Source: software/rv4th/src/rv4th.c lines 134-160 (cmdListBi + cmdListBi2).
export const FORTH_WORDS = [
  'bye', '+', '-', '*', '/%', '.', 'dup', 'drop', 'swap', '<',
  '>', '==', 'hb.', 'gw', 'dfn', 'abs', ',', 'p@', 'p!', 'not',
  'list', 'if', 'then', 'else', 'begin', 'until', 'depth', 'h.', ']', 'num',
  'push0', 'goto', 'exec', 'lu', 'pushn', 'over', 'push1', 'pwrd', 'emit', ';',
  '@', '!', 'h@', 'do', 'loop', '+loop', 'i', 'j', 'k', '~',
  '^', '&', '|', '*/', 'key', 'cr', '*2', '/2', 'call0', 'call1',
  'call2', 'call3', 'call4', 'ndrop', 'swpb', '+!', 'roll', 'pick', 'tuck', 'max',
  'min', 's.', 'sh.', 'neg', 'echo', 'init', 'o2w', 'o2p', 'rst', 'clk',
  'fr', 'fw', 'fe', 'sbi', 'cbi', 'mask', 'and', 'or', 'swphw', 'sll',
  'srl', 'mr', 'mw', 'me', 'wadc',
  '[', ':', 'var',
];

const MAX_LINES = 4000;

class Terminal {
  constructor() {
    this.scroll = document.getElementById('term-scroll');
    this.input = document.getElementById('term-input');
    this.completeBox = document.getElementById('term-complete');
    this.drawer = document.getElementById('terminal-drawer');

    this.history = [];
    this.histIdx = -1;      // -1 = editing a fresh line
    this.draft = '';
    this.buffer = [];       // {ts, type, data} for export
    this.completion = null; // {items, idx, base}
    this.recordSink = null; // fn(cmd) set by macros "record" mode

    this._wire();
    this._wireWs();
  }

  _wire() {
    const inp = this.input;
    inp.addEventListener('keydown', (e) => this._onKey(e));

    document.getElementById('term-clear').addEventListener('click', () => this.clear());
    document.getElementById('term-export').addEventListener('click', () => this.export());

    // Drawer: click anywhere in it focuses the input (keyboard focus discipline).
    this.drawer.addEventListener('mousedown', (e) => {
      if (e.target.closest('button, a, input, .drawer-grip')) return;
      this.input.focus();
    });

    this._setupDrawer();
  }

  _wireWs() {
    ws.on('tx', (m) => this.append('tx', m.data, m.ts));
    ws.on('rx', (m) => this.append('rx', m.data, m.ts));
    ws.on('info', (m) => this.append('info', m.data, m.ts));
    ws.on('error', (m) => this.append('error', m.data, m.ts));
    ws.on('state', (m) => this.append('state', typeof m.data === 'string' ? m.data : JSON.stringify(m.data), m.ts));

    ws.on('link', (up) => {
      this.input.disabled = false; // input always allowed; server buffers/echoes state
      if (!up) this.append('info', '-- link to backend lost, reconnecting --', Date.now() / 1000);
      else this.append('info', '-- connected to dashboard backend --', Date.now() / 1000);
    });
  }

  // ---------------- rendering ----------------
  append(type, data, ts) {
    if (data === undefined || data === null) data = '';
    const rec = { ts: ts || Date.now() / 1000, type, data: String(data) };
    this.buffer.push(rec);
    if (this.buffer.length > MAX_LINES * 2) this.buffer.splice(0, this.buffer.length - MAX_LINES);

    const atBottom = this.scroll.scrollHeight - this.scroll.scrollTop - this.scroll.clientHeight < 40;
    const line = el(`div.term-line.tl-${type}`, null, [
      el('span.ts', { text: fmtTs(rec.ts) }),
      document.createTextNode(rec.data),
    ]);
    this.scroll.appendChild(line);
    while (this.scroll.childElementCount > MAX_LINES) this.scroll.removeChild(this.scroll.firstChild);
    if (atBottom) this.scroll.scrollTop = this.scroll.scrollHeight;
  }

  clear() { clear(this.scroll); }

  export() {
    const lines = this.buffer.map((r) => `${fmtTs(r.ts)} [${r.type}] ${r.data}`);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    download(`forth-session-${stamp}.log`, new Blob([lines.join('\n') + '\n'], { type: 'text/plain' }));
  }

  // ---------------- input handling ----------------
  send(text) {
    // Send a raw line to the chip via WS; local echo of intent is the chip's job,
    // but we still record for macro capture.
    if (!ws.send({ type: 'input', data: text })) {
      this.append('error', '-- not connected: cannot send --', Date.now() / 1000);
      return false;
    }
    if (this.recordSink && text.trim()) this.recordSink(text);
    return true;
  }

  _onKey(e) {
    if (this.completion && (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter' || e.key === 'Tab' || e.key === 'Escape')) {
      if (this._completeNav(e)) return;
    }

    if (e.key === 'Enter') {
      const text = this.input.value;
      this.input.value = '';
      this._hideComplete();
      if (text.trim() !== '') {
        this.history.push(text);
        if (this.history.length > 500) this.history.shift();
      }
      this.histIdx = -1;
      this.draft = '';
      this.send(text);
      return;
    }

    if (e.key === 'l' && e.ctrlKey) { e.preventDefault(); this.clear(); return; }

    if (e.key === 'Tab') { e.preventDefault(); this._complete(); return; }

    if (e.key === 'ArrowUp') { e.preventDefault(); this._histNav(-1); return; }
    if (e.key === 'ArrowDown') { e.preventDefault(); this._histNav(1); return; }

    if (e.key === 'Escape') { this._hideComplete(); return; }

    // Any other key invalidates a stale completion popup.
    if (this.completion) this._hideComplete();
  }

  _histNav(dir) {
    if (!this.history.length) return;
    if (this.histIdx === -1) {
      if (dir < 0) { this.draft = this.input.value; this.histIdx = this.history.length - 1; }
      else return;
    } else {
      this.histIdx += dir;
      if (this.histIdx >= this.history.length) { this.histIdx = -1; this.input.value = this.draft; return; }
      if (this.histIdx < 0) this.histIdx = 0;
    }
    this.input.value = this.history[this.histIdx];
    this.input.setSelectionRange(this.input.value.length, this.input.value.length);
  }

  // ---------------- completion ----------------
  _candidates(prefix) {
    const words = FORTH_WORDS.concat(store.regNames());
    const p = prefix.toLowerCase();
    return words.filter((w) => w.toLowerCase().startsWith(p)).slice(0, 40);
  }

  _complete() {
    const val = this.input.value;
    const caret = this.input.selectionStart;
    const left = val.slice(0, caret);
    const m = left.match(/(\S+)$/);
    const base = m ? m[1] : '';
    if (base === '') { return; }
    const items = this._candidates(base);
    if (items.length === 0) { this._hideComplete(); return; }
    if (items.length === 1) { this._applyCompletion(items[0], base, caret); this._hideComplete(); return; }
    this.completion = { items, idx: 0, base, caret };
    this._renderComplete();
  }

  _applyCompletion(word, base, caret) {
    const val = this.input.value;
    const before = val.slice(0, caret - base.length);
    const after = val.slice(caret);
    const insert = word + (after.startsWith(' ') || after === '' ? '' : ' ');
    this.input.value = before + insert + after;
    const pos = (before + insert).length;
    this.input.setSelectionRange(pos, pos);
  }

  _renderComplete() {
    const box = this.completeBox;
    clear(box);
    this.completion.items.forEach((w, i) => {
      box.appendChild(el('div.c-item' + (i === this.completion.idx ? '.active' : ''), {
        onmousedown: (e) => { e.preventDefault(); this._chooseCompletion(i); },
      }, w));
    });
    box.hidden = false;
  }

  _completeNav(e) {
    if (e.key === 'Escape') { e.preventDefault(); this._hideComplete(); return true; }
    if (e.key === 'ArrowDown') { e.preventDefault(); this.completion.idx = (this.completion.idx + 1) % this.completion.items.length; this._renderComplete(); return true; }
    if (e.key === 'ArrowUp') { e.preventDefault(); this.completion.idx = (this.completion.idx - 1 + this.completion.items.length) % this.completion.items.length; this._renderComplete(); return true; }
    if (e.key === 'Enter' || e.key === 'Tab') { e.preventDefault(); this._chooseCompletion(this.completion.idx); return true; }
    return false;
  }

  _chooseCompletion(i) {
    const c = this.completion;
    this._applyCompletion(c.items[i], c.base, c.caret);
    this._hideComplete();
    this.input.focus();
  }

  _hideComplete() { this.completion = null; this.completeBox.hidden = true; }

  // ---------------- drawer (collapse + resize + remember) ----------------
  _setupDrawer() {
    const toggle = document.getElementById('drawer-toggle');
    const grip = document.getElementById('drawer-grip');
    const KEY_H = 'fdash.drawerH';
    const KEY_C = 'fdash.drawerCollapsed';

    const savedH = parseInt(localStorage.getItem(KEY_H) || '', 10);
    if (savedH && savedH > 120 && savedH < window.innerHeight - 120) {
      document.body.style.setProperty('--drawer-h', savedH + 'px');
    }
    if (localStorage.getItem(KEY_C) === '1') document.body.classList.add('drawer-collapsed');

    toggle.addEventListener('click', () => {
      const collapsed = document.body.classList.toggle('drawer-collapsed');
      localStorage.setItem(KEY_C, collapsed ? '1' : '0');
      toggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
      if (!collapsed) this.input.focus();
    });

    let dragging = false;
    grip.addEventListener('mousedown', (e) => { dragging = true; e.preventDefault(); document.body.style.userSelect = 'none'; });
    window.addEventListener('mousemove', (e) => {
      if (!dragging) return;
      const h = Math.min(Math.max(window.innerHeight - e.clientY, 120), window.innerHeight - 140);
      document.body.style.setProperty('--drawer-h', h + 'px');
    });
    window.addEventListener('mouseup', () => {
      if (!dragging) return;
      dragging = false;
      document.body.style.userSelect = '';
      const h = parseInt(getComputedStyle(document.body).getPropertyValue('--drawer-h'), 10);
      if (h) localStorage.setItem(KEY_H, String(h));
    });
  }

  // Macro record hook wiring (used by macros.js).
  setRecordSink(fn) { this.recordSink = fn; }
  focus() { this.input.focus(); }
}

function fmtTs(ts) {
  const d = new Date(ts * 1000);
  const p = (n, w) => String(n).padStart(w || 2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

export const terminal = new Terminal();
