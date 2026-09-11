#!/usr/bin/env python3
"""check_configurator_sync.py -- guard against docs/chip_configurator.html
drifting from the generator (G3, 2026-07-11; reworked for the web-export
consumption model, WP S7, 2026-07-16).

Since S2/S7 the configurator no longer TRANSCRIBES the generator's data: it
CONSUMES `out/web/chip_data.js` (the `const VESTA_DATA = {...}` bundle) spliced
into the page between

    /*VESTA_DATA_BEGIN*/ ... /*VESTA_DATA_END*/

by `python/splice_web_data.py`. So the old DEFAULTS-value and PADS-table
transcription checks are gone (those hand tables no longer exist in the HTML).
What this script now verifies:

  (a) configObject() export keys  ==  _CONFIG_SCHEMA keys (both directions).
      The page still hand-assembles the export object, so its dotted keys must
      still match the schema. This catches a new/renamed knob that the export
      forgot.
  (b) The spliced VESTA_DATA region is PRESENT and NON-STALE vs
      out/web/chip_data.js (splice_web_data.py --check semantics). On any drift
      it parses both sides and NAMES the differing VESTA_DATA paths -- so a
      changed generate.py default surfaces by name. (Default builds only: a
      CONFIG= build legitimately emits different data.)
  (c) derived() formula fragments + the Castalia/Argus geometry spot values +
      the current resolved build's derived block -- the JS still keeps its own
      derived() math (cross-checked in-page against VESTA_DATA.derivedPresets),
      so this catches a silent edit to those formulas.

Modes:
  default   WARN -- print any DRIFT lines but exit 0 (never blocks a build).
  --strict  GATE -- exit 1 on any drift (for CI / a deliberate sync gate).
Python 3.6 compatible.
"""

import json
import os
import re
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(PC_ROOT))
HTML = os.path.join(REPO, 'docs', 'chip_configurator.html')
GENERATE = os.path.join(HERE, 'generate.py')
RESOLVED = os.path.join(PC_ROOT, 'config', 'ChipConfig.resolved.json')
WEBDATA = os.path.join(PC_ROOT, 'out', 'web', 'chip_data.js')

BEGIN = '/*VESTA_DATA_BEGIN*/'
END = '/*VESTA_DATA_END*/'

PROBLEMS = []


def problem(msg):
    PROBLEMS.append(msg)
    print('  DRIFT: ' + msg)


def js_block(html, start_marker, end_marker):
    i = html.find(start_marker)
    if i < 0:
        raise SystemExit('marker not found in configurator HTML: ' + start_marker)
    j = html.find(end_marker, i)
    if j < 0:
        raise SystemExit('end marker not found after %s: %s' % (start_marker, end_marker))
    return html[i:j]


# --------------------------------------------------------------------------
# (a) schema keys  <->  configObject() export keys
# --------------------------------------------------------------------------
def schema_keys_from_generate():
    src = open(GENERATE).read()
    block = js_block(src, '_CONFIG_SCHEMA = {', '\n}')
    return set(re.findall(r"^\t'([A-Za-z0-9_.]+)':", block, re.M))


def export_keys_from_html(html):
    """Reconstruct the dotted keys configObject() exports (incl. the
    conditional o.<dotted> = ... assignments). _comment is schema-exempt."""
    fn = js_block(html, 'function configObject(){', '\nfunction ')
    keys = set()
    prefix = []
    body = js_block(fn, 'const o = {', '\n  };')
    for line in body.split('\n')[1:]:
        line = line.strip()
        if line.startswith('_comment'):
            continue    # free-form string; may contain colons
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\{([^}]*)\},?\s*$', line)
        if m:           # one-line nested object, e.g. peripherals: { npu: cfg.npu },
            for mm in re.finditer(r'([A-Za-z_][A-Za-z0-9_]*)\s*:', m.group(2)):
                keys.add(m.group(1) + '.' + mm.group(1))
            continue
        m = re.match(r'([A-Za-z_][A-Za-z0-9_]*)\s*:\s*\{\s*$', line)
        if m:
            prefix.append(m.group(1))
            continue
        if line.startswith('},') or line == '}':
            if prefix:
                prefix.pop()
            continue
        for m in re.finditer(r'(?:^|[{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:', line):
            keys.add('.'.join(prefix + [m.group(1)]))
    for m in re.finditer(r'\bo\.([A-Za-z0-9_.]+)\s*=', fn):
        keys.add(m.group(1))
    return keys


# --------------------------------------------------------------------------
# (b) spliced VESTA_DATA region: present + non-stale (names the drift)
# --------------------------------------------------------------------------
def _region(html):
    i = html.find(BEGIN)
    if i < 0:
        problem('the /*VESTA_DATA_BEGIN*/ marker is MISSING from the HTML '
                '(the page no longer consumes the generator export -- run the splice)')
        return None
    j = html.find(END, i + len(BEGIN))
    if j < 0:
        problem('the /*VESTA_DATA_END*/ marker is MISSING from the HTML')
        return None
    return html[i + len(BEGIN):j]


def _rendered(data_text):
    return '\n' + data_text.strip('\n') + '\n'


def load_vesta(js_text):
    """Parse `const VESTA_DATA = {...};` (from the file or the HTML region) to a dict."""
    m = re.search(r'const\s+VESTA_DATA\s*=\s*(\{.*\})\s*;', js_text.strip(), re.S)
    if not m:
        return None
    try:
        return json.loads(m.group(1))
    except ValueError:
        return None


def json_diff(a, b, path=''):
    diffs = []
    if type(a) != type(b):
        return [(path or '(root)', a, b)]
    if isinstance(a, dict):
        for k in sorted(set(a) | set(b)):
            p = (path + '.' + k) if path else k
            if k not in a:
                diffs.append((p, '<absent-in-HTML>', b[k]))
            elif k not in b:
                diffs.append((p, a[k], '<absent-in-export>'))
            else:
                diffs += json_diff(a[k], b[k], p)
    elif isinstance(a, list):
        if len(a) != len(b):
            diffs.append((path + '[length]', len(a), len(b)))
        else:
            for i, (x, y) in enumerate(zip(a, b)):
                diffs += json_diff(x, y, '%s[%d]' % (path, i))
    else:
        if a != b:
            diffs.append((path or '(root)', a, b))
    return diffs


def check_vesta_region(html):
    between = _region(html)
    if between is None:
        return
    file_text = open(WEBDATA).read()
    if between == _rendered(file_text):
        return   # up to date
    # stale -- try to name the drift by diffing the two bundles
    html_data = load_vesta(between)
    file_data = load_vesta(file_text)
    if html_data is None or file_data is None:
        problem('spliced VESTA_DATA region is STALE vs out/web/chip_data.js '
                '(could not parse for a field-level diff -- re-run make web + splice)')
        return
    diffs = json_diff(html_data, file_data)
    if not diffs:
        problem('spliced VESTA_DATA region is STALE (whitespace only) vs '
                'out/web/chip_data.js -- re-run the splice')
        return
    for (p, hv, fv) in diffs[:15]:
        problem('spliced VESTA_DATA.%s = %r but the generator now emits %r '
                '(stale splice -- re-run make web + splice_web_data.py)' % (p, hv, fv))
    if len(diffs) > 15:
        problem('...and %d more VESTA_DATA field(s) differ' % (len(diffs) - 15))


# --------------------------------------------------------------------------
# (c) derived() geometry
# --------------------------------------------------------------------------
def geometry(num_harts, shared_ram_size, orchestrator=False):
    """The A2/A0 formulas, transcribed once more FOR THE CHECK (generate.py is
    the authority; the JS mirrors it; this catches either side moving alone).

    CPR3/R3: `orchestrator` is shAw's SECOND input -- the read-only TCM
    apertures at 0x20000 + 0x4000*h need pages 1000..1100, so the shared window
    is forced to 16 bits of word address (0x0-0x3FFFF) and extended flash moves
    to the strict complement 0x40000."""
    sh_aw = 0
    while (1 << sh_aw) < (0x10000 + shared_ram_size):
        sh_aw += 1
    sh_aw -= 2
    if orchestrator and sh_aw < 16:
        sh_aw = 16
    flash = 1 << (sh_aw + 2)
    mtime_slot = ((4 * num_harts + 15) // 16) * 4
    mtime = 0x5000 + 4 * mtime_slot
    return {'shAw': sh_aw, 'banks': shared_ram_size // 0x4000,
            'flash': flash, 'mtime': mtime, 'mtimecmp': mtime + 0x10}


# The ledger spot values the kickoff pins down (multicore_plan / CLAUDE.md).
# (name, numHarts, sharedBulkRamSize, orchestrator, expected)
SPOTS = [
    ('Castalia', 4, 0x10000, False, {'shAw': 15, 'flash': 0x20000, 'mtime': 0x5010, 'mtimecmp': 0x5020}),
    ('Argus', 18, 0x20000, False, {'shAw': 16, 'flash': 0x40000, 'mtime': 0x5050, 'mtimecmp': 0x5060}),
    # CPR3/R3: the penta shape. SAME bulk RAM as Castalia (64 KiB -> derived
    # shAw 15), but the orchestrator term lifts it to 16 and flash to 0x40000 --
    # which is exactly the term this row exists to pin. The CLINT layout shift
    # is the N=5 hart-count effect and is independent of it.
    ('Castalia-Penta', 5, 0x10000, True, {'shAw': 16, 'flash': 0x40000, 'mtime': 0x5020, 'mtimecmp': 0x5030}),
]

# Formula fragments that must survive in the JS derived() -- a silent edit to
# the math there escapes the numeric spot checks (we can't execute JS).
DERIVED_FRAGMENTS = [
    'cfg.sharedRamSize / 0x4000',
    'while ((1 << shAw) < (0x10000 + cfg.sharedRamSize)) shAw++',
    'shAw -= 2',
    # CPR3/R3: the orchestrator term, and the aperture list it implies. A silent
    # edit that drops either would leave the JS drawing a 0x20000 flash base on
    # a penta configuration while the generator emits 0x40000.
    'if (cfg.orchestrator && shAw < 16) shAw = 16;',
    '0x20000 + 0x4000*h',
    '1 << (shAw + 2)',
    'Math.floor((4*cfg.numHarts + 15) / 16) * 4',
    'mtime + 0x10',
    'loaderBase: 0x10500',
    'spInit: 0xC000',
    # DP-SG (2026-07-22): derived() now mirrors _LIBRARY_TAIL_SPEC (the A5
    # GLOBAL VECTOR RULE) instead of a hardcoded 114 — pin the tail rows AND
    # the high-water computation so a silent edit still trips this gate.
    '[cfg.rtc, 1]',
    '[cfg.pwm, 2]',
    '[cfg.onewire, 1]',
    '[cfg.dma, 2]',
    '[cfg.npu, 1]',
    '[cfg.trng, 1]',
    '[cfg.i2ctarget, 2]',
    'vtail += c; if (p) vhigh = vtail;',
    'vectors: vhigh, msipVec: 83, mtipVec: 84',
]


def check_derived(html, resolved):
    fn = js_block(html, 'function derived(){', '\nfunction ')
    for frag in DERIVED_FRAGMENTS:
        if frag not in fn:
            problem('derived() formula fragment missing from configurator JS: "%s"' % frag)
    for (name, harts, ram, orch, expect) in SPOTS:
        got = geometry(harts, ram, orch)
        for k in expect:
            if got[k] != expect[k]:
                problem('%s geometry %s: formula gives 0x%X, ledger says 0x%X'
                        % (name, k, got[k], expect[k]))
    # and the CURRENT build's resolved derived block
    d = resolved.get('derived', {})
    got = geometry(int(resolved['numHarts']), int(resolved['memory']['sharedBulkRamSize']),
                   bool(resolved.get('orchestrator', False)))
    checks = [
        ('sharedWindowAddrWidth', got['shAw'], d.get('sharedWindowAddrWidth')),
        ('sharedRamBanks', got['banks'], d.get('sharedRamBanks')),
        ('flashBaseAddress', got['flash'], int(str(d.get('flashBaseAddress', '0')), 16)),
        ('clintLayout.mtimeAddress', got['mtime'],
         int(str(d.get('clintLayout', {}).get('mtimeAddress', '0')), 16)),
    ]
    for (k, mine, theirs) in checks:
        if mine != theirs:
            problem('resolved derived.%s = %s but the geometry formulas give %s'
                    % (k, theirs, mine))


# --------------------------------------------------------------------------
def main(strict=False):
    for path in (HTML, GENERATE, RESOLVED, WEBDATA):
        if not os.path.isfile(path):
            print('  SKIP: %s not found (run make web first?)' % path)
            return 0
    html = open(HTML).read()
    resolved = json.load(open(RESOLVED))

    # (a) keys both directions
    schema = schema_keys_from_generate()
    exported = export_keys_from_html(html)
    for k in sorted(schema - exported):
        problem('schema key %s is not exported by configObject() in the HTML' % k)
    for k in sorted(exported - schema):
        problem('configObject() exports %s which is NOT a _CONFIG_SCHEMA key' % k)

    # (b) spliced VESTA_DATA region present + non-stale (default builds only;
    #     a CONFIG= build legitimately emits different data than the page's
    #     default Castalia bundle).
    if resolved.get('configFile') is None:
        check_vesta_region(html)
    else:
        print('  note: out/ holds CONFIG=%s -- VESTA_DATA region staleness check skipped '
              '(the HTML carries the default bundle)' % resolved['configFile'])

    # (c) derived() math
    check_derived(html, resolved)

    if PROBLEMS:
        print('  %d sync problem(s) between the generator and docs/chip_configurator.html' % len(PROBLEMS))
        if strict:
            print('  (--strict) exiting non-zero on drift.')
            return 1
        print('  (WARN mode) not failing the build -- pass --strict to gate on this.')
        return 0
    print('  configurator sync: OK (schema keys, spliced VESTA_DATA region, derived geometry)')
    return 0


if __name__ == '__main__':
    sys.exit(main(strict=('--strict' in sys.argv)))
