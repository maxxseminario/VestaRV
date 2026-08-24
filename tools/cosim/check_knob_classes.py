#!/usr/bin/python3.6
"""check_knob_classes.py -- the CORE_ENABLE_* classification tripwire (2026-08-23).

WHAT IT GUARDS.

Two independent readers decide whether an RTL `constant CORE_ENABLE_<X> :
boolean := true` is COMPARABLE against an image set's `.imgset` stamp:
verify_stage.memorymap_on_knobs (the suite half) and the polarity guard in
tools/cosim/gate/xrun_cosim.sh (the lockstep half). Both now read ONE
classification -- verify_stage.DEFINE_KNOBS (stampable) and
verify_stage.NON_DEFINE_KNOBS (exempt) -- and both REFUSE a constant that is in
neither list.

That refusal makes a NEW knob loud. It does not make a knob already on the
exempt list stay correct, and one of them is on that list conditionally:

  * IF_AHEAD is exempt PERMANENTLY. The generator emits no
    `#define CORE_ENABLE_IF_AHEAD` at all -- microarchitecture only, nothing in
    software can dispatch on it -- so no image can carry the polarity even in
    principle.
  * DEBUG is exempt DEFERRED. The define EXISTS (ChipGenerator emits it into
    MemoryMap.h and core_features.h); what does not exist is any test that
    dispatches on it, because every D-series debug instrument needs a tcl
    harness and no CATALOG row can carry the `debug` tag. Admitting it today
    would put `-DCORE_ENABLE_DEBUG` on every image of every config -- debug
    defaults TRUE -- and rebuild the whole canonical set at a new polarity, to
    buy zero #ifdef arms.
  * the five base-ISA knobs are exempt for the reason measured in
    verify_stage.DEFINE_KNOBS, with ONE known #ifdef named there.

"No test dispatches on it" is a MEASUREMENT, and a measurement that nothing
re-runs is an assumption within a week. This script re-runs it. The day someone
writes a live `#ifdef CORE_ENABLE_DEBUG` into a test source, this FAILS and says
to move `debug` into DEFINE_KNOBS and pay the rebuild deliberately -- instead of
the gate quietly comparing an OFF-arm image against ON-polarity RTL, which is
the PASS-shaped failure the whole polarity apparatus exists to prevent.

WHAT IT CHECKS.

  1. TOTALITY. Every CORE_ENABLE_<X> constant ChipGenerator.py can emit into
     MemoryMap.vhd is classified, in exactly one of the two lists. This is the
     check that would have caught CORE_ENABLE_IF_AHEAD on the day it landed.
  2. NO BUILD-TIME DISPATCH ON AN EXEMPT KNOB. Sweeping every ISA test source
     for a real preprocessor conditional (not a comment, not prose) on an
     exempt knob. The one KNOWN hit is allowed BY NAME and by file, and the
     allowance is checked to still be there -- if it moves or disappears, that
     is reported too, because a stale allowance is a stale rationale.
  3. A KNOWN-NONZERO CONTROL, because a sweep validated only by finding nothing
     has not been validated. The sweep must find the stampable knobs it is
     supposed to find (TRAPCSR, UMODE and PMP all dispatch heavily); if it does
     not, the file set is wrong or mis-staged and this FATALs rather than
     reporting a clean result.

EXIT CODES
  0  the classification is total and no exempt knob is dispatched on
  1  a finding -- an unclassified knob, or an exempt knob with a live #ifdef
  2  the check could not be run (missing input, or the nonzero control failed)

USAGE
  /usr/bin/python3.6 tools/cosim/check_knob_classes.py
  /usr/bin/python3.6 tools/cosim/check_knob_classes.py --files-from <manifest>

--files-from is the STRICT mode the bazel test uses: one workspace-relative
path per line, and an unreadable manifest is exit 2 so a mis-staged sandbox
cannot pass here as an empty scan reported as OK.

Python 3.6 compatible. Reads only; changes nothing.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))

# The one KNOWN preprocessor conditional on an exempt knob, allowed by name.
# verify_stage.DEFINE_KNOBS measured it and explains why COMPRESSED stays out
# of the stamp anyway: the guarded tail is two Zcmop instructions INSIDE an
# already-Zimop-gated ON arm, in a test that is in neither the standing suite
# list nor the verify CATALOG, so no runner selects it.
# It is allowed HERE rather than silently skipped so that the allowance is
# visible, counted, and reported when it stops matching.
KNOWN_DISPATCH = {
    ('rv32ua/extzimop.S', 'COMPRESSED'):
        'a two-instruction Zcmop tail inside the already-Zimop-gated ON arm of '
        'a test no runner selects (verify_stage.DEFINE_KNOBS measured it)',
}

# The sweep must find these, or it is not looking at the right files.
NONZERO_CONTROL = ('TRAPCSR', 'UMODE', 'PMP')

CPP_COND = re.compile(
    r'^\s*#\s*(?:if|ifdef|ifndef|elif)\b.*?\bCORE_ENABLE_([A-Z0-9_]+)\b')

# `t.AddRow(['#define CORE_ENABLE_ZCB'])` and the core_features.h `('ZCB', ...)`
# list -- the two places ChipGenerator can name a knob's C define.
GEN_DEFINE = re.compile(r"#define CORE_ENABLE_([A-Z0-9_]+)")
# `constant CORE_ENABLE_ZCB` in the MemoryMap.vhd emitter.
GEN_CONSTANT = re.compile(r"constant CORE_ENABLE_([A-Z0-9_]+)")


def fail(msg):
    print('check_knob_classes: FATAL -- %s' % msg)
    sys.exit(2)


def load_classes():
    """(stampable, exempt) out of verify_stage.py, as RTL constant suffixes."""
    pc_py = os.path.join(ROOT, 'platform', 'common', 'python')
    if not os.path.isfile(os.path.join(pc_py, 'verify_stage.py')):
        fail('no verify_stage.py under %s' % pc_py)
    sys.path.insert(0, pc_py)
    try:
        import verify_stage as V   # import-safe: main() is guarded (R-K1-3)
    except ImportError as e:
        fail('cannot import verify_stage: %s' % e)
    if not hasattr(V, 'knob_classes'):
        fail('verify_stage.py has no knob_classes() -- this check and the '
             'polarity guard both read it, so its absence means the '
             'classification has moved and BOTH need re-pointing')
    return V.knob_classes()


def generator_knobs():
    """Every CORE_ENABLE_<X> ChipGenerator.py can emit, and whether it also
    emits a matching C #define for it.

    Read out of the generator SOURCE rather than out of a generated file: the
    question is what the generator CAN produce for some configuration, not what
    today's resolved config happened to switch on.
    """
    path = os.path.join(ROOT, 'platform', 'common', 'python', 'ChipGenerator.py')
    if not os.path.isfile(path):
        fail('no ChipGenerator.py at %s -- cannot establish the full set of '
             'CORE_ENABLE_* constants, so totality cannot be checked' % path)
    with open(path) as f:
        src = f.read()
    constants = set(GEN_CONSTANT.findall(src))
    defines = set(GEN_DEFINE.findall(src))
    if not constants:
        fail('ChipGenerator.py names no `constant CORE_ENABLE_*` at all -- the '
             'emitter has moved and this check is reading the wrong thing')
    return constants, defines


def source_files(manifest):
    if manifest:
        if not os.path.isfile(manifest):
            fail('--files-from %s is not readable' % manifest)
        out = []
        with open(manifest) as f:
            for line in f:
                p = line.strip()
                if p:
                    out.append(p)
        if not out:
            fail('--files-from %s is empty' % manifest)
        return out
    out = []
    for base in ('verification', 'software'):
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
            for fn in files:
                if fn.endswith(('.S', '.s', '.c', '.h')):
                    out.append(os.path.join(dirpath, fn))
    if not out:
        fail('found no test sources under verification/ or software/')
    return out


def sweep(paths):
    """{knob: [(shortpath, lineno, text)]} for every real cpp conditional."""
    hits = {}
    read = 0
    for p in paths:
        try:
            with open(p, 'r', errors='replace') as f:
                lines = f.read().split('\n')
        except (IOError, OSError):
            continue
        read += 1
        for i, line in enumerate(lines, 1):
            m = CPP_COND.match(line)
            if m:
                hits.setdefault(m.group(1), []).append((p, i, line.strip()))
    if read == 0:
        fail('none of the %d listed source files could be read -- a mis-staged '
             'tree must not pass here as a clean sweep' % len(paths))
    return hits, read


def short(p):
    """`.../verification/isa/tests/rv32ua/extzimop.S` -> `rv32ua/extzimop.S`."""
    parts = p.replace('\\', '/').split('/')
    return '/'.join(parts[-2:])


def main():
    manifest = None
    argv = sys.argv[1:]
    if argv and argv[0] == '--files-from':
        if len(argv) < 2:
            fail('--files-from needs a path')
        manifest = argv[1]
    elif argv:
        fail('unknown argument %r' % argv[0])

    stampable, exempt = load_classes()
    constants, defines = generator_knobs()
    findings = []

    # --- 1. TOTALITY ------------------------------------------------------
    classified = set(stampable) | set(exempt)
    both = set(stampable) & set(exempt)
    unclassified = sorted(constants - classified)
    if both:
        findings.append(
            'CLASSIFIED TWICE: %s is in BOTH verify_stage.DEFINE_KNOBS and '
            'NON_DEFINE_KNOBS. The two lists are a partition; a knob in both '
            'means the guard\'s positive filter and its refusal disagree.'
            % ', '.join(sorted(both)))
    for k in unclassified:
        findings.append(
            'UNCLASSIFIED: ChipGenerator.py can emit `constant CORE_ENABLE_%s` '
            'into MemoryMap.vhd, and verify_stage.py classifies it neither\n'
            '    STAMPABLE (DEFINE_KNOBS) nor EXEMPT (NON_DEFINE_KNOBS).\n'
            '    Classify it, with the measurement, in the commit that adds it.\n'
            '    It is STAMPABLE only if all three hold: the generator emits a\n'
            '    matching `#define CORE_ENABLE_%s` (it %s), some test source\n'
            '    dispatches on that define at build time, and the constant is\n'
            '    readable in MemoryMap.vhd.'
            % (k, k, 'DOES' if k in defines else 'DOES NOT'))

    # --- 2/3. THE SWEEP, AND ITS CONTROL ----------------------------------
    paths = source_files(manifest)
    hits, nread = sweep(paths)

    missing_control = [k for k in NONZERO_CONTROL if k not in hits]
    if missing_control:
        fail('the known-nonzero control failed: %s dispatched on in NO source '
             'of the %d read. Those knobs are #ifdef-ed on heavily, so finding '
             'none means this sweep is looking at the wrong files, and a clean '
             'result from it would mean nothing.'
             % (', '.join(missing_control), nread))

    allowed_seen = set()
    for k in sorted(exempt):
        for (p, ln, text) in hits.get(k, []):
            key = (short(p), k)
            if key in KNOWN_DISPATCH:
                allowed_seen.add(key)
                continue
            findings.append(
                'EXEMPT KNOB IS DISPATCHED ON: %s:%d\n'
                '    %s\n'
                '    CORE_ENABLE_%s is on verify_stage.NON_DEFINE_KNOBS, so no\n'
                '    image set can carry its polarity and neither the suite\n'
                '    gate nor the lockstep gate compares it. This #ifdef\n'
                '    therefore compiles ONE arm regardless of what the RTL\n'
                '    ships, and the failure mode is a PASS.\n'
                '    Either move this knob into verify_stage.DEFINE_KNOBS and\n'
                '    pay the image-set rebuild deliberately, or delete the\n'
                '    conditional. Do not leave it here.'
                % (short(p), ln, text, k))

    for key, why in sorted(KNOWN_DISPATCH.items()):
        if key not in allowed_seen:
            findings.append(
                'STALE ALLOWANCE: %s no longer has a #ifdef on CORE_ENABLE_%s.\n'
                '    It was allowed here because: %s\n'
                '    Delete the KNOWN_DISPATCH entry -- an allowance whose\n'
                '    rationale no longer describes the tree is the R-W2-3\n'
                '    failure: the next reader trusts it.'
                % (key[0], key[1], why))

    print('check_knob_classes: %d CORE_ENABLE_* constant(s) the generator can '
          'emit; %d stampable, %d exempt' % (len(constants), len(stampable),
                                             len(exempt)))
    print('  exempt      : %s' % ' '.join(exempt))
    print('  swept       : %d source file(s); control knobs %s all found'
          % (nread, '/'.join(NONZERO_CONTROL)))
    print('  dispatch on : %s'
          % ' '.join('%s(%d)' % (k, len(v)) for k, v in sorted(hits.items())))
    print('  allowed     : %s'
          % (', '.join('%s:%s' % (p, k) for (p, k) in sorted(allowed_seen))
             or '(none)'))

    if findings:
        print('')
        for f in findings:
            print('  * %s' % f)
        print('')
        print('check_knob_classes: %d finding(s)' % len(findings))
        return 1
    print('check_knob_classes: OK')
    return 0


if __name__ == '__main__':
    sys.exit(main())
