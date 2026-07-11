#!/usr/bin/env python3
"""check_configurator_sync.py -- guard against docs/chip_configurator.html
drifting from the generator (G3, 2026-07-11).

The configurator HTML deliberately embeds TRANSCRIBED copies of three things
whose authority lives in platform_castalia:
  (a) the CONFIG= schema (_CONFIG_SCHEMA in generate.py) as its DEFAULTS /
      configObject() JS,
  (b) the QFN-44 package model (config/PadRing.json) as its PADS table,
  (c) the derived-geometry math (A2 shared-window + A0 CLINT formulas) as its
      derived() JS.
This script re-checks all three so the "keep in sync" comment is a CHECK:

  a. configObject() export keys  ==  _CONFIG_SCHEMA keys (both directions)
     DEFAULTS values             ==  the resolved DEFAULT build values
                                     (skipped when out/ holds a CONFIG= build)
  b. PADS rows (pin/name/type)   ==  config/PadRing.json pins
  c. derived() spot values for the Castalia and Argus geometries (shAw 15/16,
     flash 0x20000/0x40000, CLINT mtime 0x5010/0x5050) against the ledger and
     against config/ChipConfig.resolved.json for the current build; plus
     formula-fragment presence in the JS so silent math edits are caught.

Wired into `make generate` as a WARNING, not a hard failure -- the HTML lives
outside platform_castalia/ and must never block a chip build.
Exit 0 = in sync; exit 1 = drift (details on stdout). Python 3.6 compatible.
"""

import json
import os
import re
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)
REPO = os.path.dirname(PC_ROOT)
HTML = os.path.join(REPO, 'docs', 'chip_configurator.html')
GENERATE = os.path.join(HERE, 'generate.py')
PADRING = os.path.join(PC_ROOT, 'config', 'PadRing.json')
RESOLVED = os.path.join(PC_ROOT, 'config', 'ChipConfig.resolved.json')

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
# (a) schema keys
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


# Mapping from the JS DEFAULTS knob names to schema dotted keys, as
# configObject() writes them. Changes here always ride a schema change, which
# the key check above flags first.
DEFAULTS_TO_SCHEMA = {
    'chipName': 'chipName',
    'numHarts': 'numHarts',
    'numMutexes': 'numMutexes',
    'ENABLE_REGS_DUALPORT': 'registerFileDualPort',
    'ENABLE_MUL': 'isa.mul',
    'ENABLE_FAST_MUL': 'isa.fastMul',
    'ENABLE_DIV': 'isa.div',
    'ENABLE_ATOMICS': 'isa.atomics',
    'COMPRESSED_ISA': 'isa.compressed',
    'ENABLE_BITMANIP': 'isa.bitmanip',
    'ENABLE_COUNTERS': 'isa.counters',
    'ENABLE_COUNTERS64': 'isa.counters64',
    'romSize': 'memory.romSize',
    'tcmSize': 'memory.tcmSizePerHart',
    'sharedRamSize': 'memory.sharedBulkRamSize',
    'npuRamSize': 'memory.npuStagingRamSize',
    'npu': 'peripherals.npu',
    'i2c1': 'peripherals.i2c1',
    'uart1': 'peripherals.uart1',
    'spi1': 'peripherals.spi1',
    'timer1': 'peripherals.timer1',
    'packageModel': 'package.model',
    'packagePreliminary': 'package.preliminary',
}
PLANNING_ONLY = {'gpio', 'uart', 'spi', 'timer', 'i2c'}  # pills, not exported


def defaults_from_html(html):
    block = js_block(html, 'const DEFAULTS = {', '\n};')
    vals = {}
    for m in re.finditer(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*("([^"]*)"|true|false|[0-9]+)\s*,', block, re.M):
        k, raw, s = m.group(1), m.group(2), m.group(3)
        if raw.startswith('"'):
            vals[k] = s
        elif raw in ('true', 'false'):
            vals[k] = (raw == 'true')
        else:
            vals[k] = int(raw)
    return vals


def resolved_lookup(resolved, dotted):
    node = resolved
    for part in dotted.split('.'):
        if not isinstance(node, dict) or part not in node:
            return None
        node = node[part]
    return node


# --------------------------------------------------------------------------
# (b) PADS table
# --------------------------------------------------------------------------
IO_TO_JS = {
    'Input/Output': 'io',
    'Input': 'in',
    'Output': 'out',
    'Power Input': 'pwr',
    'NC': 'nc',
}


def norm_name(name):
    return re.sub(r'\(GPIO\d+\)', '', name).replace(' ', '')


def check_pads(html):
    block = js_block(html, 'const PADS = [', '\n];')
    js_pads = {}
    for m in re.finditer(r'\[(\d+),"([^"]+)","(\w+)"\]', block):
        js_pads[int(m.group(1))] = (m.group(2), m.group(3))
    ring = json.load(open(PADRING))
    pins = dict((p['pin'], p) for p in ring['pins'])
    if set(js_pads) != set(pins):
        problem('PADS pin numbers %s != PadRing.json pins %s'
                % (sorted(set(js_pads) ^ set(pins)), len(pins)))
        return
    for n in sorted(pins):
        jname, jtype = js_pads[n]
        p = pins[n]
        if norm_name(jname) != norm_name(p['name']):
            problem('PADS pin %d name "%s" != PadRing.json "%s"' % (n, jname, p['name']))
        expect = IO_TO_JS.get(p['io'])
        analog_ok = (jtype == 'ana' and p.get('powerDomain') == 'Analog')
        if jtype != expect and not analog_ok:
            problem('PADS pin %d type "%s" != PadRing.json io "%s" (expected "%s")'
                    % (n, jtype, p['io'], expect))


# --------------------------------------------------------------------------
# (c) derived() geometry
# --------------------------------------------------------------------------
def geometry(num_harts, shared_ram_size):
    """The A2/A0 formulas, transcribed once more FOR THE CHECK (generate.py is
    the authority; the JS mirrors it; this catches either side moving alone)."""
    sh_aw = 0
    while (1 << sh_aw) < (0x10000 + shared_ram_size):
        sh_aw += 1
    sh_aw -= 2
    flash = 1 << (sh_aw + 2)
    mtime_slot = ((4 * num_harts + 15) // 16) * 4
    mtime = 0x5000 + 4 * mtime_slot
    return {'shAw': sh_aw, 'banks': shared_ram_size // 0x4000,
            'flash': flash, 'mtime': mtime, 'mtimecmp': mtime + 0x10}


# The ledger spot values the kickoff pins down (multicore_plan / CLAUDE.md).
SPOTS = [
    ('Castalia', 4, 0x10000, {'shAw': 15, 'flash': 0x20000, 'mtime': 0x5010, 'mtimecmp': 0x5020}),
    ('Argus', 18, 0x20000, {'shAw': 16, 'flash': 0x40000, 'mtime': 0x5050, 'mtimecmp': 0x5060}),
]

# Formula fragments that must survive in the JS derived() -- a silent edit to
# the math there escapes the numeric spot checks (we can't execute JS).
DERIVED_FRAGMENTS = [
    'cfg.sharedRamSize / 0x4000',
    'while ((1 << shAw) < (0x10000 + cfg.sharedRamSize)) shAw++',
    'shAw -= 2',
    '1 << (shAw + 2)',
    'Math.floor((4*cfg.numHarts + 15) / 16) * 4',
    'mtime + 0x10',
    'loaderBase: 0x10500',
    'spInit: 0xC000',
    'vectors: 85, msipVec: 83, mtipVec: 84',
]


def check_derived(html, resolved):
    fn = js_block(html, 'function derived(){', '\nfunction ')
    for frag in DERIVED_FRAGMENTS:
        if frag not in fn:
            problem('derived() formula fragment missing from configurator JS: "%s"' % frag)
    for (name, harts, ram, expect) in SPOTS:
        got = geometry(harts, ram)
        for k in expect:
            if got[k] != expect[k]:
                problem('%s geometry %s: formula gives 0x%X, ledger says 0x%X'
                        % (name, k, got[k], expect[k]))
    # and the CURRENT build's resolved derived block
    d = resolved.get('derived', {})
    got = geometry(int(resolved['numHarts']), int(resolved['memory']['sharedBulkRamSize']))
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
def main():
    for path in (HTML, GENERATE, PADRING, RESOLVED):
        if not os.path.isfile(path):
            print('  SKIP: %s not found (run make generate first?)' % path)
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

    # (a) DEFAULTS values vs the resolved DEFAULT build
    defaults = defaults_from_html(html)
    unmapped = set(defaults) - set(DEFAULTS_TO_SCHEMA) - PLANNING_ONLY
    for k in sorted(unmapped):
        problem('JS DEFAULTS has unmapped knob "%s" (update DEFAULTS_TO_SCHEMA here + the schema)' % k)
    if resolved.get('configFile') is None:
        for jsk, dotted in sorted(DEFAULTS_TO_SCHEMA.items()):
            if jsk not in defaults:
                problem('JS DEFAULTS is missing knob "%s" (%s)' % (jsk, dotted))
                continue
            rv = resolved_lookup(resolved, dotted)
            if rv is None:
                problem('resolved config has no value for %s' % dotted)
            elif rv != defaults[jsk]:
                problem('JS DEFAULTS.%s = %r but the default build resolves %s = %r'
                        % (jsk, defaults[jsk], dotted, rv))
    else:
        print('  note: out/ holds CONFIG=%s -- DEFAULTS value comparison skipped'
              % resolved['configFile'])

    # (b) PADS mirrors the DEFAULT package model; a CONFIG build may rename
    # pins (a dropped peripheral's pads revert to plain GPIO), so only compare
    # on default builds -- same rule as the DEFAULTS values above.
    if resolved.get('configFile') is None:
        check_pads(html)
    # (c)
    check_derived(html, resolved)

    if PROBLEMS:
        print('  %d sync problem(s) between the generator and docs/chip_configurator.html' % len(PROBLEMS))
        return 1
    print('  configurator sync: OK (schema keys, DEFAULTS, PADS, derived geometry)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
