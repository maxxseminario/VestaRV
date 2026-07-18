// Minimal DOM helpers — keeps modules terse without a framework.

// el('div.card', {id:'x'}, [child, 'text']) -> HTMLElement
export function el(spec, attrs, children) {
  const [tag, ...classes] = spec.split('.');
  const node = document.createElement(tag || 'div');
  if (classes.length) node.className = classes.join(' ');
  if (attrs) {
    for (const [k, v] of Object.entries(attrs)) {
      if (v === null || v === undefined || v === false) continue;
      if (k === 'text') node.textContent = v;
      else if (k === 'html') node.innerHTML = v;
      else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
      else if (k === 'dataset') Object.assign(node.dataset, v);
      else if (v === true) node.setAttribute(k, '');
      else node.setAttribute(k, v);
    }
  }
  if (children != null) {
    const arr = Array.isArray(children) ? children : [children];
    for (const c of arr) {
      if (c == null || c === false) continue;
      node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
    }
  }
  return node;
}

export function clear(node) { while (node.firstChild) node.removeChild(node.firstChild); }
export function $(sel, root) { return (root || document).querySelector(sel); }

// Format an integer as 0x-prefixed hex, min `pad` digits.
export function hex(n, pad) {
  if (n === null || n === undefined || Number.isNaN(n)) return '?';
  const s = (n >>> 0).toString(16).toUpperCase();
  return '0x' + (pad ? s.padStart(pad, '0') : s);
}

// Parse a user-typed number: 0x.. hex, or decimal. Returns null on bad input.
export function parseNum(s) {
  if (typeof s !== 'string') return null;
  s = s.trim();
  if (s === '') return null;
  let v;
  if (/^0x[0-9a-f]+$/i.test(s)) v = parseInt(s, 16);
  else if (/^-?\d+$/.test(s)) v = parseInt(s, 10);
  else return null;
  return Number.isNaN(v) ? null : v;
}

// Trigger a client-side download of a Blob.
export function download(filename, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
