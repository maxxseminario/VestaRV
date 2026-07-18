// F9 — macros. Named Forth snippet library (CRUD via /api/macros), run streams
// through the terminal, and a "record from terminal" toggle captures typed
// commands into a new macro.

import { api } from './api.js';
import { terminal } from './terminal.js';
import { el, clear } from './dom.js';

class Macros {
  constructor(root) {
    this.root = root;
    this.list = [];        // [{name, body}]
    this.selected = null;  // name
    this.recording = false;
    this.recorded = [];
    this._build();
    this._wireRecordButton();
    this.reload();
  }

  _build() {
    clear(this.root);
    this.root.appendChild(el('h2.view-title', { text: 'Macros' }));
    this.root.appendChild(el('p.view-desc', { text: 'Named Forth snippets. Run streams line-by-line through the terminal. Record captures what you type.' }));

    this.listEl = el('div.macro-list');
    this.nameIn = el('input', { type: 'text', placeholder: 'macro name', style: 'width:100%', spellcheck: 'false' });
    this.bodyEl = el('textarea', { placeholder: 'one Forth command per line…', spellcheck: 'false' });
    this.editMsg = el('span.hint');

    const editor = el('div.macro-edit', null, [
      el('div.row', { style: 'margin-bottom:8px' }, [this.nameIn]),
      this.bodyEl,
      el('div.row', { style: 'margin-top:8px' }, [
        el('button.btn.primary', { onclick: () => this.save() }, 'Save'),
        el('button.btn', { onclick: () => this.run() }, 'Run ▸'),
        el('button.btn.danger', { onclick: () => this.remove() }, 'Delete'),
        el('button.btn.ghost', { onclick: () => this.newMacro() }, 'New'),
        this.editMsg,
      ]),
    ]);

    this.root.appendChild(el('div.macro-layout', null, [
      el('div', null, [
        el('div.row', { style: 'margin-bottom:6px' }, [
          el('button.btn.small', { onclick: () => this.reload() }, '↻ Reload'),
        ]),
        this.listEl,
      ]),
      editor,
    ]));
  }

  _wireRecordButton() {
    this.recBtn = document.getElementById('term-record');
    this.recBtn.addEventListener('click', () => this.toggleRecord());
  }

  toggleRecord() {
    this.recording = !this.recording;
    this.recBtn.classList.toggle('recording', this.recording);
    if (this.recording) {
      this.recorded = [];
      terminal.setRecordSink((cmd) => this.recorded.push(cmd));
      terminal.append('info', '-- macro recording started --', Date.now() / 1000);
    } else {
      terminal.setRecordSink(null);
      terminal.append('info', `-- macro recording stopped (${this.recorded.length} lines) --`, Date.now() / 1000);
      if (this.recorded.length) {
        this.selected = null;
        this.nameIn.value = 'recorded_' + new Date().toISOString().slice(11, 19).replace(/:/g, '');
        this.bodyEl.value = this.recorded.join('\n');
        this._msg(`${this.recorded.length} lines captured — name it and Save.`);
        this._select();
      }
    }
  }

  async reload() {
    try {
      const data = await api.get('/api/macros');
      this.list = normalize(data);
      this._renderList();
    } catch (e) {
      this.listEl.innerHTML = '';
      this.listEl.appendChild(el('p.hint', { style: 'padding:10px', text: 'macros unavailable: ' + e.message }));
    }
  }

  _renderList() {
    clear(this.listEl);
    if (!this.list.length) { this.listEl.appendChild(el('p.hint', { style: 'padding:10px', text: 'no macros yet' })); return; }
    for (const m of this.list) {
      this.listEl.appendChild(el('div.macro-item' + (m.name === this.selected ? '.sel' : ''), {
        onclick: () => this.select(m.name),
      }, [el('span', { text: m.name }), el('span.pill', { text: (m.body || '').split('\n').length + 'L' })]));
    }
  }

  select(name) {
    const m = this.list.find((x) => x.name === name);
    if (!m) return;
    this.selected = name;
    this.nameIn.value = m.name;
    this.bodyEl.value = m.body || '';
    this._select();
  }
  _select() { this._renderList(); }

  newMacro() { this.selected = null; this.nameIn.value = ''; this.bodyEl.value = ''; this._msg(''); this._renderList(); }

  async save() {
    const name = this.nameIn.value.trim();
    const body = this.bodyEl.value;
    if (!name) { this._msg('name required'); return; }
    try {
      await api.post('/api/macros', { name, body });
      this.selected = name;
      this._msg('saved');
      await this.reload();
    } catch (e) { this._msg('save failed: ' + e.message); }
  }

  async remove() {
    const name = this.nameIn.value.trim();
    if (!name) return;
    if (!confirm(`Delete macro "${name}"?`)) return;
    try {
      await api.del('/api/macros/' + encodeURIComponent(name));
      if (this.selected === name) this.newMacro();
      await this.reload();
    } catch (e) { this._msg('delete failed: ' + e.message); }
  }

  run() {
    const body = this.bodyEl.value;
    const lines = body.split('\n').map((l) => l.trim()).filter((l) => l !== '');
    if (!lines.length) { this._msg('nothing to run'); return; }
    terminal.append('info', `-- running macro (${lines.length} lines) --`, Date.now() / 1000);
    for (const line of lines) terminal.send(line);
    this._msg(`sent ${lines.length} lines to terminal`);
  }

  _msg(t) { this.editMsg.textContent = t; }
}

// The macros endpoint may return an array or an object map; normalize to a list.
function normalize(data) {
  if (Array.isArray(data)) return data.map((m) => ({ name: m.name, body: m.body != null ? m.body : (m.commands || '') }));
  if (data && typeof data === 'object') {
    if (Array.isArray(data.macros)) return normalize(data.macros);
    return Object.entries(data).map(([name, body]) => ({ name, body: typeof body === 'string' ? body : (body && body.body) || '' }));
  }
  return [];
}

export function initMacros(root) { return new Macros(root); }
