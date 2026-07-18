// F10 — session log. Captures every WS event with timestamps; filter by type +
// text; download. Independent buffer so it survives terminal clears.

import { ws } from './ws.js';
import { el, clear, download } from './dom.js';

const MAX = 8000;
const TYPES = ['tx', 'rx', 'info', 'error', 'state'];

class SessionLog {
  constructor(root) {
    this.root = root;
    this.entries = [];  // {ts, type, data}
    this.filters = new Set(TYPES);
    this.query = '';
    this._build();
    ws.on('*', (m) => this._capture(m));
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Session Log' }));
    this.root.appendChild(el('p.view-desc', { text: 'Every serial/WS event this session. Filter and download.' }));

    const toolbar = el('div.log-toolbar');
    for (const t of TYPES) {
      const cb = el('input', { type: 'checkbox', checked: true });
      cb.addEventListener('change', () => { cb.checked ? this.filters.add(t) : this.filters.delete(t); this._render(); });
      toolbar.appendChild(el('label.chk', null, [cb, t]));
    }
    const q = el('input', { type: 'text', placeholder: 'filter text…', 'aria-label': 'filter text' });
    q.addEventListener('input', () => { this.query = q.value.toLowerCase(); this._render(); });
    toolbar.appendChild(q);
    toolbar.appendChild(el('span.sp'));
    this.countEl = el('span.hint');
    toolbar.appendChild(this.countEl);
    toolbar.appendChild(el('button.btn.small', { onclick: () => this.download() }, 'Download'));
    toolbar.appendChild(el('button.btn.small', { onclick: () => this.clearLog() }, 'Clear'));
    this.root.appendChild(toolbar);

    this.view = el('div.log-view');
    this.root.appendChild(this.view);
  }

  _capture(m) {
    this.entries.push({ ts: m.ts || Date.now() / 1000, type: m.type, data: stringify(m.data) });
    if (this.entries.length > MAX) this.entries.splice(0, this.entries.length - MAX);
    if (this.root.classList.contains('active')) this._render();
  }

  _match(e) {
    if (!this.filters.has(e.type)) return false;
    if (this.query && !(e.data.toLowerCase().includes(this.query) || e.type.includes(this.query))) return false;
    return true;
  }

  _render() {
    const rows = this.entries.filter((e) => this._match(e));
    clear(this.view);
    const atBottom = this.view.scrollHeight - this.view.scrollTop - this.view.clientHeight < 40;
    for (const e of rows.slice(-2000)) {
      this.view.appendChild(el(`div.lg.tl-${e.type}`, { text: `${fmtTs(e.ts)} [${e.type}] ${e.data}` }));
    }
    this.countEl.textContent = `${rows.length}/${this.entries.length} events`;
    if (atBottom) this.view.scrollTop = this.view.scrollHeight;
  }

  onShow() { this._render(); }

  download() {
    const rows = this.entries.filter((e) => this._match(e)).map((e) => `${fmtTs(e.ts)} [${e.type}] ${e.data}`);
    const stamp = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    download(`session-log-${stamp}.txt`, new Blob([rows.join('\n') + '\n'], { type: 'text/plain' }));
  }

  clearLog() { this.entries = []; this._render(); }
}

function stringify(d) { return typeof d === 'string' ? d : JSON.stringify(d); }
function fmtTs(ts) {
  const d = new Date(ts * 1000);
  const p = (n, w) => String(n).padStart(w || 2, '0');
  return `${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}.${p(d.getMilliseconds(), 3)}`;
}

export function initLog(root) { return new SessionLog(root); }
