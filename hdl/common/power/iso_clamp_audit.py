#!/usr/bin/env python3
"""VestaRV: the isolation-clamp completeness gate.

hart_tile sits in a switchable MTCMOS power domain (cpf/hart_tile.cpf). Its
isolation is NOT a CPF isolation rule and therefore NOT tool-inserted: Genus
reports `CPI-502 No isolation rules defined` / `CPI-517 0 isolation cells
inserted` and Xcelium reports `LPNOISO`, both correctly. Every gated-to-always-on
crossing is instead clamped by an explicit RTL AND gate on the ALWAYS-ON MCU side
of the boundary, written by platform/common/python/mcu_vhd.py into the generated
MCU.vhd. No tool checks that the set of those clamps is COMPLETE. This does.

An output of a gated hart_tile instance that nobody clamps is a floating pin of a
dark domain sampled by always-on logic: X in simulation, an indeterminate level on
silicon. It passes synthesis, P&R, LVS and the whole functional regression,
because none of them power the domain down.

The rule, per hart_tile instance:

  * an instance whose `pd_iso_en` actual is the literal '0' is ALWAYS-ON. It never
    gates, so its outputs are not crossings. Such an instance must be named in the
    allowlist's `always_on_instances`, so that tying a gateable tile's pd_iso_en
    low by accident is a failure and not a silent exemption.
  * an instance whose `pd_iso_en` actual is a bare identifier is a PASS-THROUGH
    wrapper: the boundary is its parent's, not its own. It must be named in the
    allowlist's `wrapper_instances`, checked the same way.
  * testbenches (any path with a /tb/ component) are skipped: a bench drives the
    tile directly and has no always-on side to protect. The count is reported.
  * otherwise the actual must be `pd_iso_en(h)`, and for every OUT port of
    hdl/common/hart_tile.vhd either
      - the port is unassociated or associated with `open`, in which case the port
        must carry a reason in the allowlist's `unconnected_outputs` AND that
        entry's `files` list must name this file (an output nothing reads is not
        a crossing, but which outputs those are is a property of the
        configuration, so the exemption is scoped to the file it was checked in),
        or
      - the actual expression appears verbatim as the value arm of a clamp
        assignment in the same file:
            <target> <= <actual> when pd_iso_en(h) = '0' else <zero>;
        with a ZERO else arm, because clamp-0 is what equals the tile's boundary
        register reset values (cpf/hart_tile.cpf).

Reads text, like //hdl/common/cdc:cdc_manifest_test, so it sees the emitter's
output and not a synthesised structure. The structural counterpart is the gate
netlist clamp audit recorded in docs/vestarv_roadmap.html (PG1).

    iso_clamp_audit.py --files-from <list> --entity hdl/common/hart_tile.vhd \
                       --allowlist hdl/common/power/iso_clamp_allowlist.json
"""

import argparse
import json
import os
import re
import sys

ENTITY = 'hart_tile'

# Zero-valued else arms. Anything else is a clamp to a non-reset value, which is a
# defect in its own right: the arbiter's IDLE sampler has to see a released master.
ZERO_ARMS = {"'0'", "(others => '0')", '"00"', '"0000"'}

_COMMENT = re.compile(r'--.*$', re.M)
_BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.S)
_INST = re.compile(r'^[ \t]*(?P<label>\w+)[ \t]*:[ \t]*entity[ \t]+work\.' + ENTITY + r'\b',
                   re.M | re.I)
_CLAMP = re.compile(
    r"^[ \t]*(?P<tgt>[^<\n]+?)[ \t]*<=[ \t]*(?P<val>.+?)"
    r"[ \t]+when[ \t]+pd_iso_en\((?P<h>\d+)\)[ \t]*=[ \t]*'0'"
    r"[ \t]+else[ \t]+(?P<els>.+?);[ \t]*$", re.M | re.I)
_ISO_ACTUAL = re.compile(r"^pd_iso_en\((\d+)\)$", re.I)
_BARE_ID = re.compile(r'^\w+$')
_TB_PATH = re.compile(r'(^|/)tb/')


def norm(text):
	"""Collapse whitespace so an actual and a clamp value arm compare textually."""
	return ' '.join(text.split())


def strip_comments(text):
	return _COMMENT.sub('', _BLOCK_COMMENT.sub('', text))


def entity_outputs(path):
	"""OUT port names of the hart_tile entity, in declaration order."""
	src = open(path, encoding='utf-8').read()
	m = re.search(r'^entity[ \t]+' + ENTITY + r'[ \t]+is\b(.*?)^end[ \t]+entity[ \t]*;',
	              src, re.M | re.S | re.I)
	if not m:
		raise SystemExit('iso_clamp_audit: no entity ' + ENTITY + ' in ' + path)
	body = strip_comments(m.group(1))
	pm = re.search(r'\bport[ \t]*\((.*)\)[ \t]*;', body, re.S | re.I)
	if not pm:
		raise SystemExit('iso_clamp_audit: no port clause in ' + path)
	outs = []
	depth = 0
	item = ''
	for ch in pm.group(1):
		if ch == '(':
			depth += 1
		elif ch == ')':
			depth -= 1
		if ch == ';' and depth == 0:
			outs += _decl_outs(item)
			item = ''
		else:
			item += ch
	outs += _decl_outs(item)
	return outs


def _decl_outs(item):
	if ':' not in item:
		return []
	names, rest = item.split(':', 1)
	rest = rest.split(':=')[0].strip()
	if not re.match(r'\bout\b', rest, re.I):
		return []
	return [n.strip() for n in names.split(',') if n.strip()]


def instances(path, src):
	"""Every hart_tile instantiation as (label, line, {formal: actual-or-None})."""
	found = []
	lines = src.split('\n')
	for m in _INST.finditer(src):
		start = src.count('\n', 0, m.start())
		i = start
		while i < len(lines) and not re.search(r'\bport\s+map\s*\(', lines[i], re.I):
			i += 1
			if i - start > 400:
				raise SystemExit('iso_clamp_audit: no port map for ' + m.group('label')
				                 + ' in ' + path)
		assoc = {}
		i += 1
		while i < len(lines):
			line = _COMMENT.sub('', lines[i]).strip()
			if line == ');':
				break
			if line:
				body = line[:-1].rstrip() if line.endswith(',') else line
				if '=>' in body:
					formal, actual = body.split('=>', 1)
					formal = formal.strip()
					if formal.count('(') == formal.count(')'):
						assoc[formal.lower()] = norm(actual)
			i += 1
		else:
			raise SystemExit('iso_clamp_audit: unterminated port map for '
			                 + m.group('label') + ' in ' + path)
		found.append((m.group('label'), start + 1, assoc))
	return found


def clamps(path, src):
	"""hart index -> {normalised value arm}, and the bad-else-arm failures found."""
	table, bad = {}, []
	for m in _CLAMP.finditer(src):
		h = int(m.group('h'))
		els = norm(m.group('els'))
		if els not in ZERO_ARMS:
			bad.append('%s:%d: clamp of %s for hart %d has a NON-ZERO else arm %s; '
			           'clamp-0 is what equals the tile boundary registers\' reset values'
			           % (path, src.count('\n', 0, m.start()) + 1,
			              norm(m.group('tgt')), h, els))
			continue
		table.setdefault(h, set()).add(norm(m.group('val')))
	return table, bad


def audit(files, entity_path, allow):
	outs = entity_outputs(entity_path)
	unconnected_ok = allow.get('unconnected_outputs', {})
	always_on_ok = allow.get('always_on_instances', {})
	wrapper_ok = allow.get('wrapper_instances', {})
	failures, checked, skipped_tb = [], 0, 0
	seen_always_on, seen_wrapper, used_unconnected = set(), set(), set()

	for path in files:
		src = open(path, encoding='utf-8').read()
		if not _INST.search(src):
			continue
		if _TB_PATH.search(path):
			skipped_tb += 1
			continue
		table, bad = clamps(path, src)
		failures += bad
		for label, line, assoc in instances(path, src):
			key = path + '::' + label
			iso = assoc.get('pd_iso_en')
			if iso is None:
				failures.append('%s:%d: instance %s leaves pd_iso_en unassociated; an '
				                'always-on tile must strap it \'0\' explicitly'
				                % (path, line, label))
				continue
			if iso == "'0'":
				seen_always_on.add(key)
				if key not in always_on_ok:
					failures.append('%s:%d: instance %s straps pd_iso_en to \'0\' (never '
					                'gates) but is not in the allowlist\'s '
					                'always_on_instances; add it with a reason, or the '
					                'tile\'s outputs are exempted from clamping by accident'
					                % (path, line, label))
				continue
			if _BARE_ID.match(iso):
				seen_wrapper.add(key)
				if key not in wrapper_ok:
					failures.append('%s:%d: instance %s passes pd_iso_en straight through '
					                'as %s but is not in the allowlist\'s '
					                'wrapper_instances; a wrapper moves the isolation '
					                'boundary to its parent and that has to be written down'
					                % (path, line, label, iso))
				continue
			im = _ISO_ACTUAL.match(iso)
			if not im:
				failures.append('%s:%d: instance %s has an unrecognised pd_iso_en actual '
				                '%s; expected \'0\' or pd_iso_en(h)'
				                % (path, line, label, iso))
				continue
			h = int(im.group(1))
			for port in outs:
				checked += 1
				actual = assoc.get(port.lower())
				if actual is None or actual.lower() == 'open':
					entry = unconnected_ok.get(port)
					scope = entry.get('files', []) if isinstance(entry, dict) else None
					if scope is None or not ('*' in scope or path in scope):
						failures.append('%s:%d: instance %s leaves gated output %s '
						                'unconnected, and the allowlist\'s '
						                'unconnected_outputs does not exempt it for this '
						                'file' % (path, line, label, port))
					else:
						used_unconnected.add((port, path))
					continue
				if actual not in table.get(h, ()):
					failures.append('%s:%d: instance %s output %s => %s crosses from the '
					                'gated domain to the always-on side with NO isolation '
					                'clamp (no "%s when pd_iso_en(%d) = \'0\' else <zero>" '
					                'assignment in this file)'
					                % (path, line, label, port, actual, actual, h))

	for port, entry in sorted(unconnected_ok.items()):
		scope = entry.get('files', []) if isinstance(entry, dict) else []
		for f in scope:
			if f != '*' and (port, f) not in used_unconnected:
				failures.append('allowlist: unconnected_outputs[%s] exempts %s, but no '
				                'gated hart_tile instance there leaves %s unconnected; a '
				                'stale exemption is a hole' % (port, f, port))

	for key in sorted(always_on_ok):
		if key not in seen_always_on:
			failures.append('allowlist: always_on_instances has %s, but no such '
			                'hart_tile instance straps pd_iso_en to \'0\'; a stale '
			                'allowlist entry is a hole' % key)
	for key in sorted(wrapper_ok):
		if key not in seen_wrapper:
			failures.append('allowlist: wrapper_instances has %s, but no such hart_tile '
			                'instance passes pd_iso_en through; a stale allowlist entry '
			                'is a hole' % key)
	return failures, checked, skipped_tb


def main(argv=None):
	ap = argparse.ArgumentParser()
	ap.add_argument('--files-from', required=True)
	ap.add_argument('--entity', required=True)
	ap.add_argument('--allowlist', required=True)
	args = ap.parse_args(argv)

	root = os.environ.get('BUILD_WORKSPACE_DIRECTORY', '')
	resolve = (lambda p: p if os.path.exists(p) or not root
	           else os.path.join(root, p))

	with open(args.files_from, encoding='utf-8') as fh:
		files = [resolve(l.strip()) for l in fh if l.strip().endswith(('.vhd', '.vhdl'))]
	allow = json.load(open(resolve(args.allowlist), encoding='utf-8'))

	failures, checked, skipped_tb = audit(files, resolve(args.entity), allow)
	if failures:
		print('ISOLATION CLAMP AUDIT FAILED (%d)' % len(failures))
		for f in failures:
			print('  ' + f)
		print('\nEvery output of a gated hart_tile instance must be clamped by '
		      'pd_iso_en(h) on the always-on side, or declared unconnected with a '
		      'reason in ' + args.allowlist + '.')
		return 1
	print('isolation clamp audit OK: %d gated hart_tile output crossings checked, '
	      '%d testbench file(s) skipped' % (checked, skipped_tb))
	return 0


if __name__ == '__main__':
	sys.exit(main())
