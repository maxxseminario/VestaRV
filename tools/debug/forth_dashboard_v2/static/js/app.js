// Entry point. Boots the WS + register map, owns the connection manager (F1) and
// the state badge, routes the left-nav views, and wires every feature module.

import { ws } from './ws.js';
import { api } from './api.js';
import { store } from './store.js';
import { terminal } from './terminal.js';
import { initRegisters } from './registers.js';
import { initMemory } from './memory.js';
import { initCodeRunner } from './coderunner.js';
import { initFlash } from './flash.js';
import { initGpio } from './gpio.js';
import { initClock } from './clock.js';
import { initMacros } from './macros.js';
import { initLog } from './log.js';

const STATES = ['DISCONNECTED', 'CONNECTING', 'IDLE', 'BUSY', 'UNRESPONSIVE'];

class App {
  constructor() {
    this.views = {};       // name -> module instance (lazy)
    this.gpio = null;
    this.log = null;
    this.currentView = 'registers';
    // Order matters: assign DOM refs (badge) BEFORE anything that can render.
    // store.onStatus() fires its callback synchronously on subscribe, so
    // _wireConnManager -> _renderConn -> _renderBadge runs during wiring.
    this._wireStatusBadge();
    this._wireNav();
    this._wireConnManager();
    this._boot();
  }

  // ---------------- boot ----------------
  async _boot() {
    // WS link drives live traffic + backend up/down.
    ws.on('link', () => this._renderBadge());
    ws.on('state', (m) => this._onStateEvent(m));
    ws.connect();

    // Load the register map (needed by several views). Retry quietly if backend
    // is still starting.
    this._loadRegisters();
    // Poll status as a backstop to the WS state stream.
    this._pollStatus();
    this._refreshPorts();

    // Instantiate the default view immediately; others lazily on first show.
    this._showView('registers');
    setTimeout(() => terminal.focus(), 50);
  }

  async _loadRegisters(attempt = 0) {
    try {
      const data = await api.get('/api/registers');
      store.setRegisters(data);
    } catch (e) {
      if (attempt < 30) setTimeout(() => this._loadRegisters(attempt + 1), 2000);
    }
  }

  async _pollStatus() {
    try {
      const s = await api.get('/api/status');
      store.setStatus(s);
    } catch (_) { /* backend down; badge already shows OFFLINE via link */ }
    this._renderConn();
    setTimeout(() => this._pollStatus(), 2000);
  }

  // ---------------- navigation ----------------
  _wireNav() {
    for (const btn of document.querySelectorAll('.nav-item')) {
      btn.addEventListener('click', () => this._showView(btn.dataset.view));
    }
  }

  _showView(name) {
    this.currentView = name;
    for (const btn of document.querySelectorAll('.nav-item')) btn.classList.toggle('active', btn.dataset.view === name);
    for (const v of document.querySelectorAll('.view')) v.classList.toggle('active', v.id === 'view-' + name);
    this._ensureView(name);
    // GPIO polls only while visible.
    if (this.gpio) this.gpio.setActive(name === 'gpio');
    if (name === 'log' && this.log) this.log.onShow();
  }

  _ensureView(name) {
    if (this.views[name]) return;
    const root = document.getElementById('view-' + name);
    switch (name) {
      case 'registers': this.views[name] = initRegisters(root); break;
      case 'memory':    this.views[name] = initMemory(root); break;
      case 'code':      this.views[name] = initCodeRunner(root); break;
      case 'flash':     this.views[name] = initFlash(root); break;
      case 'gpio':      this.views[name] = this.gpio = initGpio(root); break;
      case 'clock':     this.views[name] = initClock(root); break;
      case 'macros':    this.views[name] = initMacros(root); break;
      case 'log':       this.views[name] = this.log = initLog(root); break;
    }
  }

  // ---------------- F1 connection manager ----------------
  _wireConnManager() {
    this.portSel = document.getElementById('port-select');
    this.baudSel = document.getElementById('baud-select');
    this.connectBtn = document.getElementById('connect-btn');
    this.resetBtn = document.getElementById('reset-btn');

    document.getElementById('ports-refresh').addEventListener('click', () => this._refreshPorts());
    this.connectBtn.addEventListener('click', () => this._toggleConnect());
    this.resetBtn.addEventListener('click', () => this._reset());

    store.onStatus(() => this._renderConn());
  }

  async _refreshPorts() {
    try {
      const ports = await api.get('/api/ports');
      const list = Array.isArray(ports) ? ports : (ports && ports.ports) || [];
      const cur = this.portSel.value;
      this.portSel.innerHTML = '';
      for (const p of list) {
        const val = typeof p === 'string' ? p : (p.device || p.port || p.name);
        const label = typeof p === 'string' ? p : (p.description ? `${val} — ${p.description}` : val);
        const opt = document.createElement('option');
        opt.value = val; opt.textContent = label;
        this.portSel.appendChild(opt);
      }
      if (cur && list.some((p) => (typeof p === 'string' ? p : (p.device || p.port || p.name)) === cur)) this.portSel.value = cur;
      else if (store.status.port) this.portSel.value = store.status.port;
      if (!list.length) {
        const opt = document.createElement('option');
        opt.textContent = 'no ports'; opt.value = '';
        this.portSel.appendChild(opt);
      }
    } catch (_) { /* leave as-is */ }
  }

  async _toggleConnect() {
    if (store.status.connected) {
      this.connectBtn.disabled = true;
      try { await api.post('/api/disconnect', {}); } catch (e) { this._flashConnErr(e); }
      this.connectBtn.disabled = false;
    } else {
      const port = this.portSel.value || undefined;
      const baud = parseInt(this.baudSel.value, 10) || undefined;
      this.connectBtn.disabled = true;
      store.setStatus({ state: 'CONNECTING' });
      this._renderBadge();
      try { await api.post('/api/connect', { port, baud }); } catch (e) { this._flashConnErr(e); }
      this.connectBtn.disabled = false;
    }
    this._pollStatusOnce();
  }

  async _reset() {
    this.resetBtn.disabled = true;
    try { await api.post('/api/reset', {}); } catch (e) { this._flashConnErr(e); }
    setTimeout(() => { this.resetBtn.disabled = false; }, 300);
  }

  async _pollStatusOnce() {
    try { store.setStatus(await api.get('/api/status')); } catch (_) {}
    this._renderConn();
  }

  _flashConnErr(e) {
    terminal.append('error', `-- ${e.message} --`, Date.now() / 1000);
  }

  _renderConn() {
    if (!this.connectBtn) return; // may fire before conn manager is wired
    const connected = store.status.connected;
    this.connectBtn.textContent = connected ? 'Disconnect' : 'Connect';
    this.connectBtn.classList.toggle('primary', !connected);
    this.connectBtn.classList.toggle('warn', connected);
    const banner = document.getElementById('banner-dot');
    banner.classList.toggle('seen', !!store.status.banner_seen);
    this._renderBadge();
  }

  // ---------------- state badge ----------------
  _wireStatusBadge() { this.badge = document.getElementById('state-badge'); }

  _onStateEvent(m) {
    let state = null;
    if (typeof m.data === 'string') state = m.data.toUpperCase();
    else if (m.data && m.data.state) state = String(m.data.state).toUpperCase();
    const patch = {};
    if (state && STATES.includes(state)) patch.state = state;
    if (m.data && typeof m.data === 'object') {
      if ('connected' in m.data) patch.connected = m.data.connected;
      if ('banner_seen' in m.data) patch.banner_seen = m.data.banner_seen;
    }
    store.setStatus(patch);
    this._renderConn();
  }

  _renderBadge() {
    const b = this.badge;
    if (!b) return; // never let a render throw before the badge ref exists
    if (!ws.linked) {
      b.textContent = 'OFFLINE';
      b.className = 'badge state-unknown';
      b.title = 'Dashboard backend unreachable';
      return;
    }
    const state = store.status.state || 'DISCONNECTED';
    b.textContent = state;
    b.className = 'badge state-' + state;
    b.title = store.status.port ? `${store.status.port} @ ${store.status.baud || '?'}` : 'no port';
  }
}

// Kick off once the DOM is parsed (module scripts are deferred, so it is).
new App();
