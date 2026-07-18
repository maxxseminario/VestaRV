#!/usr/bin/env python3
"""web_export.py -- emit out/web/chip_data.js, a single machine-readable bundle
of everything docs/chip_configurator.html (and the register browser) needs to
SELF-CONFIGURE from the generator instead of re-transcribing it (WP S2,
2026-07-16; audit_findings.md sec 4.1-4.4).

`ChipGenerator.Generate()` calls `writeWebData(self, out/web/chip_data.js)` on a
real build (next to generateMemoryMapJson). The output is:

    const VESTA_DATA = { ...one JSON object... };

with top-level keys:
    meta           provenance (chip name, source config, generator note)
    schema         every _CONFIG_SCHEMA key: description + machine-readable
                   constraints (type, min/max/step, enum, default)
    defaults       schema key -> default value (flat, dotted keys)
    packages       every _PACKAGE_MODELS model -> its full pad ring (pin, side,
                   name, io type, power domain, gpio/af table)
    derivedPresets castalia / argus / cq derived geometry (isa string, shared-
                   window width, banks, flash base, CLINT layout, ...)
    verifiedHarts  {values:[4,18], note:...} -- the sim-proven hart counts
    memoryRegions  region-level address map (ROM, peripheral window, shared
                   window sections, TCM, flash)

Everything is read from the generator objects that generate.py already builds
(gen.ConfigMeta / ConfigDefaults / ConfigSchemaDoc / PackageModels /
ResolvedConfig / SharedWindowSections) -- NO pin numbers, ranges, or formulas
are transcribed a second time. The one exception is the derived-geometry math
for the OTHER preset configs (argus/cq), which is computed here by `_derived()`
and CROSS-CHECKED against gen.ResolvedConfig['derived'] for the current build so
it can never silently drift from generate.py's authoritative computation.

Python 3.6 compatible. Deterministic (no timestamps) so the file byte-diffs
cleanly across identical builds.
"""

import json
import os


# ---------------------------------------------------------------------------
# Pure derived-geometry math (mirrors generate.py's A2/A0 formulas). Used ONLY
# for the argus/cq presets; a cross-check against the authoritative
# gen.ResolvedConfig['derived'] guards it from drifting.
# ---------------------------------------------------------------------------
def _clog2(n):
	w = 0
	while (1 << w) < n:
		w += 1
	return w


def _isaString(isa):
	s = 'rv32i'
	if isa.get('mul') or isa.get('div'):
		s += 'm'
	if isa.get('atomics'):
		s += 'a'
	if isa.get('compressed'):
		s += 'c'
	if isa.get('bitmanip'):
		s += '_zba_zbb_zbs'
	if isa.get('counters'):
		s += '_zicntr'
	# X1 extensions (2026-07-17). Keep IDENTICAL to generate.py._isaString().
	if isa.get('zihpm'):
		s += '_zihpm'
	if isa.get('zicond'):
		s += '_zicond'
	if isa.get('zicboz'):
		s += '_zicboz'
	if isa.get('zcmp'):
		s += '_zcmp'
	if isa.get('zcmt'):
		s += '_zcmt'
	if isa.get('zihint'):
		s += '_zihintpause_zihintntl'
	if isa.get('zimop'):
		s += '_zimop'
		if isa.get('compressed'):
			s += '_zcmop'
	if isa.get('zcb') and isa.get('compressed'):
		s += '_zca_zcb'
	if isa.get('zawrs'):
		s += '_zawrs'
	if isa.get('zabha'):
		s += '_zabha'
	if isa.get('zacas'):
		s += '_zacas'
	# X3 Stage B scalar-crypto bit-manip (keep IDENTICAL to generate.py._isaString).
	if isa.get('zbkb'):
		s += '_zbkb'
	if isa.get('zbkc'):
		s += '_zbkc'
	if isa.get('zbkx'):
		s += '_zbkx'
	# X3 AES+SHA (keep IDENTICAL to generate.py._isaString).
	if isa.get('zkn'):
		s += '_zknd_zkne_zknh'
		if isa.get('zbkb') and isa.get('zbkc') and isa.get('zbkx'):
			s += '_zkn'
	return s


def _hx(v):
	return '0x' + format(int(v), 'X')


def _derived(cfg):
	"""Derived geometry for a resolved-shape config dict (numHarts / isa{} /
	memory{}). Keys + hex formatting match generate.py's _resolvedConfig
	'derived' section exactly (minus peripheralCount, which is peripheral-set
	dependent)."""
	numHarts = int(cfg['numHarts'])
	sharedRam = int(cfg['memory']['sharedBulkRamSize'])
	shAw = _clog2(0x10000 + sharedRam) - 2
	banks = sharedRam // 0x4000
	flash = 1 << (shAw + 2)
	mtimeSlot = ((4 * numHarts + 15) // 16) * 4
	mtimecmpSlot = mtimeSlot + 4
	return {
		'isaString': _isaString(cfg['isa']),
		'sharedWindowAddrWidth': shAw,
		'sharedRamBanks': banks,
		'flashBaseAddress': _hx(flash),
		'sharedRamEndAddress': _hx(0x10000 + sharedRam - 1),
		'vectorsCount': 85,
		'clintMsipVector': 83,
		'clintMtipVector': 84,
		'clintLayout': {
			'msipAddress': '0x5000 + 4*hartid',
			'mtimeAddress': _hx(0x5000 + 4 * mtimeSlot),
			'mtimecmpBaseAddress': _hx(0x5000 + 4 * mtimecmpSlot),
		},
		'bootromLoaderRowBase': '0x10500 + 0x10*hartid',
		'stackPointerInit': _hx(0xC000),
	}


# ---------------------------------------------------------------------------
# Config merge helpers (defaults overlaid with a shipped preset JSON).
# ---------------------------------------------------------------------------
def _nest(flatDefaults):
	"""Flat dotted defaults -> nested dict (resolved shape)."""
	out = {}
	for dotted in flatDefaults:
		parts = dotted.split('.')
		node = out
		for p in parts[:-1]:
			node = node.setdefault(p, {})
		node[parts[-1]] = flatDefaults[dotted]
	return out


def _deepMerge(base, override):
	"""Recursive dict merge (override wins); leading-underscore keys ignored."""
	out = dict((k, v) for k, v in base.items())
	for k in override:
		if k.startswith('_'):
			continue
		if isinstance(override[k], dict) and isinstance(out.get(k), dict):
			out[k] = _deepMerge(out[k], override[k])
		else:
			out[k] = override[k]
	return out


def _loadPreset(configDir, name, defaultsNested):
	path = os.path.join(configDir, name)
	if not os.path.isfile(path):
		return None
	with open(path) as f:
		cfg = json.load(f)
	return _deepMerge(defaultsNested, cfg)


# ---------------------------------------------------------------------------
# Region-level memory map (from the resolved config + gen.SharedWindowSections).
# ---------------------------------------------------------------------------
def _memoryRegions(gen):
	resolved = gen.ResolvedConfig
	mem = resolved['memory']
	derived = resolved['derived']
	romSize = int(mem['romSize'])
	tcm = int(mem['tcmSizePerHart'])
	flashBase = int(str(derived['flashBaseAddress']), 16)
	regions = []
	regions.append(('Boot ROM', 0x0, romSize - 1,
		'Shared boot ROM (all harts reset to 0x0 and dispatch on mhartid)', 'shared'))
	regions.append(('Peripheral window', 0x4000, 0x4FFF,
		'Page 0: 16x256B peripheral register slots (legacy Myshkin addressing, all shared)', 'shared'))
	for (nm, s, e, d) in gen.SharedWindowSections:
		regions.append((nm, s, e, d, 'shared'))
	regions.append(('Private TCM', 0x8000, 0x8000 + tcm - 1,
		'Per-hart private tightly-coupled memory (the only private address region)', 'private'))
	regions.append(('Extended flash (XIP)', flashBase, None,
		'Hart-0 SPI flash execute-in-place window (decodes at the strict shared-window complement)', 'flash'))
	regions.sort(key=lambda r: r[1])
	out = []
	for (nm, s, e, d, kind) in regions:
		out.append({
			'name': nm,
			'start': _hx(s),
			'end': (_hx(e) if e is not None else None),
			'kind': kind,
			'description': d,
		})
	return out


# ---------------------------------------------------------------------------
def buildWebData(gen):
	"""Assemble the VESTA_DATA dict from the generator's own objects."""
	resolved = gen.ResolvedConfig

	# schema: description + declarative constraints, per key.
	schema = {}
	for k in gen.ConfigSchemaDoc:
		entry = {'description': gen.ConfigSchemaDoc[k]}
		entry.update(gen.ConfigMeta[k])   # type, default, min/max/step, enum
		schema[k] = entry

	defaults = dict(gen.ConfigDefaults)
	defaultsNested = _nest(defaults)

	# Derived presets: castalia = the defaults; argus/cq = defaults + their JSON.
	configDir = os.path.join(gen.ChipRootDirectory, 'config')
	presets = {'castalia': _derived(defaultsNested)}
	argus = _loadPreset(configDir, 'argus.json', defaultsNested)
	if argus is not None:
		presets['argus'] = _derived(argus)
	cq = _loadPreset(configDir, 'cq.json', defaultsNested)
	if cq is not None:
		presets['cq'] = _derived(cq)

	# Cross-check the pure formula against generate.py's authoritative derived
	# block for THIS build (so _derived() can never silently drift from it).
	authoritative = resolved.get('derived', {})
	mine = _derived({
		'numHarts': resolved['numHarts'],
		'isa': resolved['isa'],
		'memory': resolved['memory'],
	})
	for k in ('sharedWindowAddrWidth', 'sharedRamBanks', 'flashBaseAddress',
			'sharedRamEndAddress', 'isaString'):
		if k in authoritative and mine[k] != authoritative[k]:
			raise Exception('web_export._derived() disagrees with generate.py on "%s": %r vs %r'
				% (k, mine[k], authoritative[k]))
	authClint = authoritative.get('clintLayout', {})
	for k in ('mtimeAddress', 'mtimecmpBaseAddress'):
		if k in authClint and mine['clintLayout'][k] != authClint[k]:
			raise Exception('web_export._derived() disagrees with generate.py on clintLayout.%s' % k)

	data = {
		'meta': {
			'chipName': resolved.get('chipName'),
			'configFile': resolved.get('configFile'),
			'generatedBy': 'platform/common/python/web_export.py (make web)',
			'note': 'Machine-readable chip data emitted from the generator single source of '
				'truth. Do not hand-edit; regenerate with `make web`.',
		},
		'schema': schema,
		'defaults': defaults,
		'packages': gen.PackageModels,
		'derivedPresets': presets,
		'verifiedHarts': {
			'values': [4, 18],
			'note': 'Only 4 (Castalia golden master, byte-identical drop-in RTL) and 18 '
				'(Argus, boots in simulation) are verified hart counts. Other values emit '
				'well-formed but unproven RTL.',
		},
		'memoryRegions': _memoryRegions(gen),
	}
	return data


def writeWebData(gen, outPath):
	data = buildWebData(gen)
	outDir = os.path.dirname(outPath)
	if not os.path.isdir(outDir):
		os.makedirs(outDir)
	body = json.dumps(data, indent=2, sort_keys=False)
	with open(outPath, 'w') as f:
		f.write('const VESTA_DATA = ' + body + ';\n')
	print('Web data bundle saved to ' + outPath)
	return outPath
