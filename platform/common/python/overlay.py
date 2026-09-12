#!/usr/bin/env python3
"""overlay.py -- the chip generator's one out-of-tree extension point.

WHY IT EXISTS. Some chips in the VestaRV family carry blocks whose register
descriptions, RTL, package models and testbench models are not distributable
with the public tree (an analog front end under NDA, a customer macro, a
partner's pad ring). Before this module the only way to build such a chip was
to carry its plumbing in generate.py / mcu_vhd.py / tb_vhd.py, which put the
private block's names, port lists and pad maps in the public repository.

WHAT IT IS. A directory OUTSIDE the repository that MIRRORS the repository
layout and contributes four kinds of content:

  <overlay>/platform/common/python/vesta_overlay.py   the hook module
  <overlay>/platform/common/config/*.json             extra configurations
  <overlay>/hdl/common/regs/rdl/*.rdl                 extra register sources
  <overlay>/platform/common/config/rdl.json           extra .rdl registry rows
  <overlay>/platform/common/latex/PeripheralIntroductions/*.tex
  <overlay>/hdl/...                                   extra RTL, read by the
                                                      out-of-tree flows

HOW IT IS SELECTED. Either

  VESTA_OVERLAY=/abs/path/to/overlay   in the environment (wins), or
  "overlay": "../../.."                in the CONFIG= json, resolved relative
                                       to that json file's own directory.

With neither set every entry point below is inert and the public tree generates
exactly what it generates today. That is the invariant the public gates hold:
no overlay present, nothing changes.

THE HOOK MODULE. `vesta_overlay.py` defines, for each stage it cares about, a
function `stage_<name>(**kw)`. The public tree calls `overlay.call('<name>',
...)` at the fixed points listed in OVERLAY_STAGES below and uses the return
value; a stage the overlay does not define returns the caller's `default`. The
overlay may keep its own state between stages in `overlay.state`; the public
tree never reads it.

Stage names are contract. Adding one is a public-tree change; what a stage DOES
is entirely the overlay's business, and no block name, port name or pad number
of a private block appears on this side of the boundary.
"""

import os
import sys

# The fixed points the public tree calls, in the order a full generation hits
# them. Documented here rather than in each caller so the whole contract can be
# read in one place.
OVERLAY_STAGES = (
	# platform/common/python/generate.py
	'packageModels',      # (models=tuple) -> tuple; extra package model names
	'configSchema',       # (schema=dict, meta=dict) -> None; extra config knobs
	'configResolve',      # (cfg=callable, vals=dict) -> None; derive + check knobs
	'libraryTailVectors', # (rows=list, vals=dict) -> list; extra IRQ tail rows
	'peripheralTemplates',# (m, vals, PeripheralTemplate, rdlRegisters) -> None
	'peripheralInstances',# (m, vals) -> None; extra CreatePeripheral calls
	'packageData',        # (model, package, PackageData, vals) -> PackageData|None
	'gpioPinMap',         # (maps=dict) -> None; extra package -> ball maps
	'irqNames',           # (rows=list, vals=dict) -> list; extra IRQB_* names
	'irqFirstVector',     # (firstVector=dict, vals=dict) -> None
	'mcuGeometry',        # (geo=dict, vals=dict) -> None; knobs for the emitters
	'resolvedConfig',     # (rows=list, vals=dict) -> list
	# platform/common/python/LatexUserGuide.py
	'trmKeyOrder',        # (keyOrder=list) -> list; where an overlay's knobs sit in the TRM table
	# platform/common/python/web_export.py
	'webTailVectors',     # (rows=list, peripherals=dict) -> list; the same tail rows, resolved-config side
	# platform/common/python/rdl_cheader_regs.py
	'cheaderOverlays',    # (rows=tuple) -> tuple; blocks overlaid on another block's sub-slot
	# platform/common/python/rdl_vhdl.py
	'rtlPackages',        # (rows=tuple) -> tuple; extra generated VHDL register packages
	# platform/common/python/mcu_vhd.py
	'mcuInit',            # (emitter, geo) -> None
	'mcuSlaves',          # (emitter) -> None; extend shslv / nativeOrder
	'mcuSubdecode',       # (emitter, indent, pageBits) -> [str]
	'mcuEntityTail',      # (emitter) -> bool; more entity ports follow
	'mcuRegion',          # (emitter, region) -> [str]; the three overlay markers
	'mcuIsoClamps',       # (emitter, hart) -> [row]; extra clamp rows
	'mcuTileEntity',      # (emitter) -> str; the channel-tile entity
	'mcuTileGenerics',    # (emitter, hart) -> [str]
	'mcuTilePorts',       # (emitter, hart) -> [str]
	# platform/common/python/tb_vhd.py
	'tbInit',             # (emitter, geo) -> None
	'tbPorts',            # (emitter, indent, decl) -> [str]
	'tbRegion',           # (emitter, region) -> [str]; the two overlay markers
)

# Scratch space for the overlay module across stages. The public tree writes
# nothing here and reads nothing from it.
state = {}

_root = None
_rootResolved = False
_module = None
_moduleLoaded = False


def setRoot(path, relativeTo=None):
	"""Point the overlay at `path`, which may be relative to `relativeTo`
	   (the directory of the configuration file that named it). Ignored when
	   VESTA_OVERLAY is already set: the environment wins, so a flow can force
	   an overlay onto a configuration that does not name one."""
	global _root, _rootResolved, _module, _moduleLoaded
	if os.environ.get('VESTA_OVERLAY', '').strip():
		return
	path = (path or '').strip()
	if not path:
		return
	if not os.path.isabs(path) and relativeTo:
		path = os.path.join(relativeTo, path)
	path = os.path.abspath(path)
	if not os.path.isdir(path):
		raise Exception('overlay: "' + path + '" is not a directory. An overlay '
			'root mirrors the repository layout; see platform/common/python/overlay.py.')
	_root, _rootResolved = path, True
	_module, _moduleLoaded = None, False
	os.environ['VESTA_OVERLAY'] = path


def root():
	"""The overlay directory, or None. Cached; VESTA_OVERLAY is read once."""
	global _root, _rootResolved
	if not _rootResolved:
		env = os.environ.get('VESTA_OVERLAY', '').strip()
		if env:
			env = os.path.abspath(env)
			if not os.path.isdir(env):
				raise Exception('VESTA_OVERLAY="' + env + '" is not a directory.')
			_root = env
		_rootResolved = True
	return _root


def has():
	return root() is not None


def path(*parts):
	"""An absolute path under the overlay root, or None with no overlay."""
	r = root()
	return os.path.join(r, *parts) if r else None


def file(*parts):
	"""The overlay path if that file exists, else None. The public tree's own
	   copy always wins; this is a FALLBACK, never an override."""
	p = path(*parts)
	return p if (p and os.path.isfile(p)) else None


def dir(*parts):
	p = path(*parts)
	return p if (p and os.path.isdir(p)) else None


def module():
	"""Import <overlay>/platform/common/python/vesta_overlay.py, once."""
	global _module, _moduleLoaded
	if _moduleLoaded:
		return _module
	_moduleLoaded = True
	p = file('platform', 'common', 'python', 'vesta_overlay.py')
	if p is None:
		return None
	d = os.path.dirname(p)
	if d not in sys.path:
		sys.path.insert(0, d)
	import importlib
	_module = importlib.import_module('vesta_overlay')
	return _module


def call(stage, default=None, **kw):
	"""Run one overlay stage. Returns `default` with no overlay, or with an
	   overlay that does not define this stage."""
	if stage not in OVERLAY_STAGES:
		raise Exception('overlay: unknown stage "' + stage + '". The stage list is '
			'the contract; see OVERLAY_STAGES in platform/common/python/overlay.py.')
	m = module()
	if m is None:
		return default
	fn = getattr(m, 'stage_' + stage, None)
	if fn is None:
		return default
	return fn(**kw)


def lines(stage, **kw):
	"""`call` for the stages that emit VHDL: always a list of strings."""
	out = call(stage, default=None, **kw)
	return list(out) if out else []
