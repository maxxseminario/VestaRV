# Vesta theme adoption guide

How to restyle a VestaRV showcase page onto the canonical **ember, dark-first**
design system without breaking the cross-page theme contract.

Source of truth: [`vesta_theme.css`](./vesta_theme.css). Reference implementation
(copy from it if in doubt): [`index.html`](./index.html).

> **Hard rule: every page stays fully self-contained.** No page may `<link>` a
> stylesheet, load an external font, script, or remote image at runtime. The site
> is served as static islands (some in sandboxed iframes / `file://`). You inline
> the theme, you do not reference it.

---

## 1. Inline the token + component block

In `vesta_theme.css` everything between the two markers

```
/* VESTA_THEME_BEGIN */
   ... tokens + shared components ...
/* VESTA_THEME_END */
```

is the canonical copy-in block. Paste it **verbatim** into the page's own
`<style>` element. Keep the two marker comments in place — automation re-splices
updates by replacing whatever sits between them. Add page-specific CSS *after*
`VESTA_THEME_END`, never inside the block.

The block defines: colour tokens for both themes (`--bg`, `--surface*`,
`--text*`, `--accent`, `--amber`, semantic `--ok/--warn/--err`, soft fills),
a type scale (`--fs-*`), spacing (`--sp-*`), radii (`--r-*`), shadows, and the
component primitives `.vesta-header / .vesta-nav / .vesta-brand / .vesta-logo /
.vesta-toggle / .vesta-btn* / .vesta-card* / .vesta-badge* / .vesta-table* /
.vesta-footer`. Style everything through the tokens so both themes come for free.

---

## 2. The theme contract (must match across all pages)

This matches the mechanism already in `chip_configurator.html`, so a visitor's
choice follows them from page to page.

| Item | Value |
|------|-------|
| Default theme | **dark** (no attribute on `<html>`) |
| Light opt-in | `<html data-theme="light">` |
| Persistence | `localStorage["vesta-theme"]` = `"light"` or `""` |
| First visit (nothing stored) | honour `prefers-color-scheme` |

- Store `"light"` when the user picks light; store `""` (empty) when they pick
  dark. An empty/absent value means "use the default", i.e. dark unless the OS
  prefers light. Never store `"dark"` — `chip_configurator.html`'s reader does
  `if(saved) setAttribute("data-theme", saved)`, and `data-theme="dark"` there is
  a no-op that happens to render dark, but keep the values clean: `"light"` / `""`.
- `chip_configurator.html` does **not** itself honour `prefers-color-scheme`; the
  newer pages do. That is a compatible superset — the stored value always wins.

### Boot snippet (put in `<head>`, before first paint, to avoid a flash)

```html
<script>
(function(){
  try{
    var saved = localStorage.getItem("vesta-theme");
    if(saved){ document.documentElement.setAttribute("data-theme", saved); }
    else if(window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches){
      document.documentElement.setAttribute("data-theme","light");
    }
  }catch(e){}
})();
</script>
```

### Toggle snippet (near end of `<body>`)

```html
<script>
(function(){
  var root = document.documentElement;
  var btn  = document.getElementById("themeToggle");
  function isLight(){
    var a = root.getAttribute("data-theme");
    if(a === "light") return true;
    if(a === "dark")  return false;
    return !!(window.matchMedia && matchMedia("(prefers-color-scheme: light)").matches);
  }
  btn.addEventListener("click", function(){
    var next = isLight() ? "" : "light";
    if(next){ root.setAttribute("data-theme","light"); }
    else    { root.removeAttribute("data-theme"); }
    try{ localStorage.setItem("vesta-theme", next); }catch(e){}
  });
})();
</script>
```

---

## 3. Shared header / nav markup

Drop this in as the first element of `<body>`. Set `aria-current="page"` on the
current page's link. Both logo data-URIs are already embedded in `index.html` —
copy the two `<img ... base64,...>` tags from there (they are large; do not
retype them). The CSS swaps them by theme automatically.

```html
<header class="vesta-header">
  <div class="vesta-header-inner">
    <a class="vesta-brand" href="index.html" aria-label="VestaRV home">
      <img class="vesta-logo is-dark"  alt="Vesta logo" src="data:image/png;base64,...DARK...">
      <img class="vesta-logo is-light" alt="Vesta logo" src="data:image/png;base64,...LIGHT...">
      <span class="vesta-brand-name">Vesta<b>RV</b></span>
    </a>
    <nav class="vesta-nav" aria-label="Primary">
      <a href="index.html">Home</a>
      <a href="vestarv_core.html">Core</a>
      <a href="castalia_soc.html">SoC</a>
      <a href="castalia_full.html">SoC&#8202;&middot;&#8202;Lens</a>
      <a href="chip_configurator.html">Configurator</a>
      <a href="register_browser.html">Registers</a>
      <a href="vestarv_roadmap.html">Roadmap</a>
    </nav>
    <button class="vesta-toggle" id="themeToggle" type="button" aria-label="Toggle colour theme" title="Toggle light / dark">
      <span class="icon-moon" aria-hidden="true">&#9789;</span>
      <span class="icon-sun"  aria-hidden="true">&#9788;</span>
      <span class="label">Theme</span>
    </button>
  </div>
</header>
```

- Logo mapping: `vesta_logo_dark.png` is the light-on-dark logo shown in **dark**
  theme (`.is-dark`); `vesta_logo_light.png` is shown in **light** theme
  (`.is-light`). The CSS handles the swap for `data-theme` and for the
  first-visit `prefers-color-scheme` case.
- The toggle button **must** have `id="themeToggle"` for the snippet in §2 to bind.

---

## 4. Special case: `castalia_full.html` drives an iframe

`castalia_full.html` embeds `vestarv_core.html?embed=1` in a "lens" iframe and
**syncs theme to the child via `postMessage`**. This must keep working when you
restyle either file:

- Parent computes a theme string and posts it:
  `coreframe.contentWindow.postMessage({ vestaTheme: "dark" | "light" }, "*")`
  on load and on every toggle.
- Child (`vestarv_core.html`) listens for `message` events and applies
  `e.data.vestaTheme`. It also accepts an initial `?theme=dark|light` query param.

Rules when restyling these two:
1. Keep the `{ vestaTheme: "dark" | "light" }` message shape and the
   `?embed=1` / `?theme=` query handling intact.
2. Keep calling the sync on load **and** on toggle.
3. Note the legacy convention in this pair is **light-first** with
   `data-theme="dark"` for dark — the opposite attribute polarity from the
   canonical dark-first block. When you migrate them to the ember tokens, either
   normalise them to the canonical `data-theme="light"` polarity **and** update
   the `frameTheme()` / message logic to match, or leave the polarity but make
   sure the posted `vestaTheme` string still reflects the actual displayed theme.
   Do not half-migrate: the parent's computed theme and the child's applied theme
   must agree, or the lens will show the wrong theme.

---

## 5. Checklist before you call a page done

- [ ] Theme block inlined verbatim between the two markers; page-specific CSS after the END marker.
- [ ] Boot script in `<head>`; toggle script bound to `#themeToggle`.
- [ ] Both logo `<img>` tags present; swap correctly on toggle and on OS preference.
- [ ] Correct nav link carries `aria-current="page"`.
- [ ] `grep -nE 'https?://'` shows only intended external links (ideally none but the GitHub footer).
- [ ] No external font / script / stylesheet / remote image at runtime.
- [ ] Renders correctly in **both** dark and light.
- [ ] (castalia_full only) iframe theme sync still works after a toggle.
