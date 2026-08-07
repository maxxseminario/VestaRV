#!/usr/bin/env python3.6
# =============================================================================
# d4_check_trampoline_validate.py -- the VALIDATION INSTRUMENT for the D4
# dual-truth gate `tools/cosim/check_dbg_trampoline.py` (d4_spec section 2).
#
# BLIND-AUTHORED 2026-08-07 against d4_spec.md (FROZEN) by an agent that has
# not seen and will never see the D4 implementation.  The checker it validates
# DOES NOT EXIST YET; at 286921d this script exits 2 and says so, and that is
# its FAIL leg.
#
#   /usr/bin/python3.6 tools/cosim/d4_check_trampoline_validate.py
#
#   rc 0  the checker exists and behaved correctly in EVERY case below
#   rc 1  the checker exists and got a case wrong (the case is named)
#   rc 2  the checker (or an input it needs) is missing/unusable
#
# WHY IT EXISTS.  d4_spec 2 requires the checker to be "validated against a
# known NONZERO before its rc 0 is load-bearing (method rule 4)".  A checker
# that always returns 0 -- because its parser silently matched nothing, or
# because it skipped when the gitignored build was absent -- is worse than no
# checker: `rc 0` reads as evidence.  The F-series measured this exact class
# (a naive census returned a plausible 44 for a true 57).  So the validation is
# not a manual one-bit experiment done once and written in a report; it is a
# script, and it can be re-run whenever the checker or the deliverable moves.
#
# THE INTERFACE CONTRACT THIS SCRIPT REQUIRES OF THE CHECKER, and it is a
# requirement, not a preference: the checker MUST offer at least one way to be
# pointed at inputs other than the live tree's, because otherwise no
# perturbation experiment is possible without editing the real
# hdl/common/debug_module.vhd -- and an acceptance instrument that has to
# modify tracked RTL to run is not one.  Any ONE of these satisfies it:
#     (a) `--vhdl <path> --words <path>` command-line overrides;
#     (b) honouring $VESTA_ROOT as the repository root;
#     (c) resolving both inputs relative to a repository root derived from the
#         checker's own __file__ (the check_mcu_vhd.py idiom), so that a copy
#         of the checker placed in a mirror tree reads that tree.
# This script tries all three, in that order, and names the one that worked.
#
# WHAT IT CHECKS
#   V0  CONTENT FREEZE (d4_spec 4: "the trampoline .words/binary content itself
#       DOES NOT CHANGE at D4").  md5 of dbg_trampoline.S, its Makefile and the
#       built .words, pinned here at 286921d.  A miss is a STOP-AND-REPORT, not
#       a checker failure -- so it is reported separately and loudly.
#   V1  pristine inputs           -> rc 0
#   V2  ONE BIT flipped in the VHDL table -> rc 1, and the output must NAME the
#       word index and quote BOTH values (d4_spec 2, verbatim)
#   V3  ONE BIT flipped in the .words file instead -> rc 1.  The symmetry
#       matters: a checker that only ever notices RTL drift will bless a
#       trampoline rebuilt behind its back.
#   V4  the .words file ABSENT    -> rc 2, and NOT rc 0.  d4_spec 2: "NEVER a
#       silent skip".
#   V5  the VHDL table one word SHORT (39) -> anything but rc 0.  The whole
#       mechanism is coupled to 40 (W_ABST = W_ENTRY + 40).
#   V6  the checker's interpreter is /usr/bin/python3.6 (d4_spec 2), because
#       this machine's bare `python3` is Calibre's quote-stripping wrapper.
# =============================================================================
from __future__ import print_function
import hashlib
import os
import re
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
CHECKER = os.path.join(REPO, 'tools', 'cosim', 'check_dbg_trampoline.py')
VHDL = os.path.join(REPO, 'hdl', 'common', 'debug_module.vhd')

# LIVENESS-CONTROL OVERRIDES.  `--checker <path>` and `--vhdl-base <path>` let
# this script be pointed at a reference implementation and a synthetic VHDL
# that already carries a TRAMP table, so that V1-V5 can be shown to be
# SATISFIABLE and not merely unsatisfied.  An instrument that has only ever
# been seen to fail has not been shown capable of passing (the D2/D3
# precedent).  Neither option is used by the standing invocation.
for _i, _a in enumerate(sys.argv):
    if _a == '--checker' and _i + 1 < len(sys.argv):
        CHECKER = os.path.abspath(sys.argv[_i + 1])
    if _a == '--vhdl-base' and _i + 1 < len(sys.argv):
        VHDL = os.path.abspath(sys.argv[_i + 1])
WORDS = os.path.join(REPO, 'software', 'dbg_trampoline', 'bin', 'dbg_trampoline.words')
TRAMP_S = os.path.join(REPO, 'software', 'dbg_trampoline', 'dbg_trampoline.S')
TRAMP_MK = os.path.join(REPO, 'software', 'dbg_trampoline', 'Makefile')

# Pinned at d-series 286921d, 2026-08-07, by the D4 blind acceptance author.
#
# THE .S PIN WAS RE-PINNED ONCE, 2026-08-07, BY THE VALIDATION WAVE UNDER THE
# INSTRUMENT-OWNER PATTERN (R-D4-2(3), option (a); F-K2b-1 via succession).
# WHY, because a moved pin with no reason attached is exactly the "quietly
# widened prediction" method rule 3 forbids:
#
#   d4_spec 4 bullet 3 ORDERS the dbg_trampoline.S prose edit (the KNOWN-LIMIT
#   paragraph asserted "nobody plants this on silicon", which D4 falsifies --
#   rule 12: a wrong rationale outlives a wrong line).  V0's .S md5 pinned that
#   file byte-for-byte, so the spec and this instrument could not both be
#   satisfied.  The invariant d4_spec 4 bullet 4 actually freezes is the
#   TRAMPOLINE CONTENT, and that is PROVEN unmoved: the implementer rebuilt
#   .words from the edited source in a scratch tree and got
#   c68684893f11b506ef7adea43b813377 -- EXACTLY the pin below, unchanged -- with
#   the .bin byte-identical too.  So the old .S pin was TIGHTER THAN THE CLAUSE
#   IT ENFORCED: a comment-only edit moved it without moving one instruction.
#
#   Re-pinned .S  8695823e38ee557a4741f97f53d805aa -> 2f9d8ef4dac39f0511a8aba0426ae1cc
#   NOT re-pinned: the Makefile and the .words pins.  They are the ones that
#   carry the clause, and if either ever moves it is still a STOP.
FREEZE = {
    TRAMP_S: '2f9d8ef4dac39f0511a8aba0426ae1cc',
    TRAMP_MK: '0e0be0ae4f1e2494de3d45f6c550c899',
    WORDS: 'c68684893f11b506ef7adea43b813377',
}

FAILS = []
NOTES = []


def md5(path):
    h = hashlib.md5()
    with open(path, 'rb') as f:
        h.update(f.read())
    return h.hexdigest()


def say(*a):
    print(*a)
    sys.stdout.flush()


def freeze_check():
    ok = True
    for path, want in sorted(FREEZE.items()):
        if not os.path.exists(path):
            say('V0 FREEZE MISSING %s' % path)
            ok = False
            continue
        got = md5(path)
        if got != want:
            say('V0 FREEZE MOVED %s\n     got  %s\n     want %s' % (path, got, want))
            ok = False
    if ok:
        say('V0 ok: the trampoline source, its Makefile and the built .words are'
            ' byte-identical to the D4 baseline')
    else:
        say('V0 FAILED -- d4_spec 4 freezes this content for the whole phase.'
            '  STOP AND REPORT; do not "fix" the pins.')
    return ok


def mirror_tree(dest, vhdl_text, words_text, drop_words=False):
    """Build a minimal repo-shaped mirror and copy the checker into it."""
    os.makedirs(os.path.join(dest, 'hdl', 'common'))
    os.makedirs(os.path.join(dest, 'software', 'dbg_trampoline', 'bin'))
    os.makedirs(os.path.join(dest, 'tools', 'cosim'))
    with open(os.path.join(dest, 'hdl', 'common', 'debug_module.vhd'), 'w') as f:
        f.write(vhdl_text)
    if not drop_words:
        with open(os.path.join(dest, 'software', 'dbg_trampoline', 'bin',
                               'dbg_trampoline.words'), 'w') as f:
            f.write(words_text)
    shutil.copy2(CHECKER, os.path.join(dest, 'tools', 'cosim',
                                       'check_dbg_trampoline.py'))
    return (os.path.join(dest, 'hdl', 'common', 'debug_module.vhd'),
            os.path.join(dest, 'software', 'dbg_trampoline', 'bin',
                         'dbg_trampoline.words'),
            os.path.join(dest, 'tools', 'cosim', 'check_dbg_trampoline.py'))


def run(argv, cwd=None, env=None):
    p = subprocess.Popen(argv, cwd=cwd, env=env, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT)
    out, _ = p.communicate()
    try:
        out = out.decode('utf-8', 'replace')
    except Exception:
        out = str(out)
    return p.returncode, out


MECHANISM = [None]


def _try(how, vhdl_path, words_path, checker_copy, root):
    py = '/usr/bin/python3.6'
    if how == 'args':
        rc, out = run([py, CHECKER, '--vhdl', vhdl_path, '--words', words_path])
        low = out.lower()
        if 'unrecognized' in low or 'unrecognised' in low or 'usage:' in low:
            return None                      # the checker has no such option
        return rc, out
    if how == 'vestaroot':
        env = dict(os.environ)
        env['VESTA_ROOT'] = root
        return run([py, CHECKER], env=env)
    return run([py, checker_copy], cwd=root)


def invoke(vhdl_path, words_path, checker_copy, root):
    """Run the checker against the given inputs; returns (rc, out, how).

    The FIRST successful mechanism is remembered and reused for every later
    case, so all six cases are measured through one interface rather than
    silently through three.
    """
    if MECHANISM[0] is not None:
        r = _try(MECHANISM[0], vhdl_path, words_path, checker_copy, root)
        return r[0], r[1], MECHANISM[0]
    for how in ('args', 'vestaroot', 'mirror'):
        r = _try(how, vhdl_path, words_path, checker_copy, root)
        if r is None:
            continue
        MECHANISM[0] = how
        return r[0], r[1], how
    FAILS.append('INTERFACE')
    return -1, ('the checker offers no way to be pointed at alternative inputs '
                '(no --vhdl/--words, no VESTA_ROOT, no repo-root-from-__file__), '
                'so no perturbation experiment is possible'), 'none'


def tramp_decl_offset(text):
    """Character offset of the TRAMP *declaration* line in `text`, or -1.

    MEASURED DEFECT, fixed 2026-08-07 by this script's own liveness-control
    arm: the first draft searched for the bare substring 'TRAMP', which matches
    the word TRAMPOLINE in debug_module.vhd's header comment at line 15.  The
    perturbation then landed on the first 32-bit literal AFTER that comment --
    the DATA0_ADDR generic default x"00010680" -- so V2 changed a generic, the
    reference checker correctly reported the tables equal, and V2 read as a
    checker failure when it was a harness failure.  A perturbation experiment
    that perturbs the wrong thing is the exact shape of a false pass, and it
    was invisible until the instrument was run in the direction where it is
    supposed to succeed.
    """
    off = 0
    for ln in text.split('\n'):
        code = re.sub(r'--.*$', '', ln)
        if re.search(r'\bTRAMP\b\s*:', code):
            return off
        off += len(ln) + 1
    off = 0
    for ln in text.split('\n'):
        code = re.sub(r'--.*$', '', ln)
        if re.search(r'\bTRAMP\b', code):
            return off
        off += len(ln) + 1
    return -1


def perturb_vhdl(text):
    """Flip ONE bit of ONE word of the TRAMP table, whatever its spelling.

    The table's literal form is the implementer's choice (d4_spec 1 gives FSM
    and encoding latitude), so this looks for either spelling inside the TRAMP
    declaration: a 32-character binary string literal, or an 8-digit hex
    literal x"........".  It refuses rather than guesses if it finds neither --
    a perturbation that silently changed nothing would make V2 a false pass,
    which is the very failure mode this script exists to prevent.
    """
    start = tramp_decl_offset(text)
    if start < 0:
        return None, 'no TRAMP declaration in the VHDL'
    tail = text[start:]
    b = re.search(r'"([01]{32})"', tail)
    h = re.search(r'[xX]"([0-9a-fA-F]{8})"', tail)
    pick = None
    if b and (not h or b.start() < h.start()):
        lit = b.group(1)
        flipped = ('1' if lit[31] == '0' else '0')
        new = lit[:31] + flipped
        pick = (b.start(), b.group(0), '"%s"' % new)
    elif h:
        lit = h.group(1)
        flipped = '%X' % (int(lit[7], 16) ^ 1)
        new = lit[:7] + flipped
        pick = (h.start(), h.group(0), h.group(0).replace(lit, new))
    if pick is None:
        return None, ('found no 32-bit word literal after the TRAMP declaration '
                      '(neither "01..." nor x"........")')
    off = start + pick[0]
    return text[:off] + text[off:].replace(pick[1], pick[2], 1), \
        'flipped one bit: %s -> %s' % (pick[1], pick[2])


def perturb_words(text):
    lines = text.split('\n')
    for i, ln in enumerate(lines):
        s = ln.strip()
        if re.match(r'^[01]{32}$', s):
            flipped = ('1' if s[31] == '0' else '0')
            lines[i] = s[:31] + flipped
            return '\n'.join(lines), 'flipped one bit of .words line %d' % (i + 1)
    return None, 'no 32-character binary line in the .words file'


def shorten_vhdl(text):
    """Delete the LAST word literal of the TRAMP table (39 words left)."""
    start = tramp_decl_offset(text)
    if start < 0:
        return None, 'no TRAMP declaration'
    tail = text[start:]
    lits = list(re.finditer(r'"[01]{32}"|[xX]"[0-9a-fA-F]{8}"', tail))
    if len(lits) < 2:
        return None, 'fewer than two word literals found after the TRAMP declaration'
    last = lits[min(39, len(lits) - 1)]
    off = start
    return text[:off + last.start()] + text[off + last.end():], \
        'removed one word literal from the table'


def expect(tag, rc, want, out, extra_ok=None, why=''):
    ok = (rc == want) if extra_ok is None else (rc == want and extra_ok)
    if ok:
        say('%s ok: rc=%d %s' % (tag, rc, why))
    else:
        FAILS.append(tag)
        say('%s FAILED: rc=%d (want %d) %s' % (tag, rc, want, why))
        say('    checker said:')
        for ln in out.strip().split('\n')[:12]:
            say('      | %s' % ln)
    return ok


def main():
    say('d4_check_trampoline_validate (fmt=d4-val-1) repo=%s' % REPO)
    frozen = freeze_check()

    if not os.path.exists(CHECKER):
        say('')
        say('CHECKER_ABSENT: %s' % CHECKER)
        say('  d4_spec 2 makes check_dbg_trampoline.py a deliverable of this')
        say('  phase.  Until it exists there is no dual-truth gate at all: the')
        say('  40-word VHDL table and the built .words file are two independent')
        say('  sources of truth for the same instruction stream, and nothing')
        say('  compares them.  This is the FAIL leg of this instrument and it')
        say('  is expected at 286921d.')
        return 2
    if not os.path.exists(WORDS):
        say('WORDS_ABSENT: %s -- build it (make -C software/dbg_trampoline)' % WORDS)
        return 2

    with open(CHECKER) as f:
        first = f.readline()
    # d4_spec 2 says "/usr/bin/python3.6".  What that clause is really about is
    # CLAUDE.md's trap: this machine's BARE `python3` is Calibre's aoj_cal
    # wrapper, which re-evaluates its arguments and strips quotes.  A shebang of
    # `#!/usr/bin/env python3.6` names a real 3.6 interpreter and is not that
    # trap, so it passes with a note; a shebang naming plain `python3` is the
    # failure.  (Widened 2026-08-07 by this script's own control arm, which
    # false-failed a conforming reference checker -- method rule 13: a criterion
    # that rejects a correct implementation is a wrong criterion.)
    sb = first.strip()
    if '/usr/bin/python3.6' in sb:
        say('V6 ok: the checker names /usr/bin/python3.6 (%s)' % sb)
    elif 'python3.6' in sb:
        say('V6 ok (note): the shebang is %r -- a real 3.6, not the bare-python3'
            ' Calibre wrapper.  The gate invokes it as /usr/bin/python3.6'
            ' anyway.' % sb)
    else:
        FAILS.append('V6')
        say('V6 FAILED: shebang is %r -- this machine\'s bare python3 is'
            ' Calibre\'s quote-stripping wrapper (CLAUDE.md).' % sb)

    vhdl_text = open(VHDL).read()
    words_text = open(WORDS).read()

    tmp = tempfile.mkdtemp(prefix='d4val_')
    try:
        # ---- V1 pristine -------------------------------------------------
        root = os.path.join(tmp, 'v1')
        v, w, c = mirror_tree(root, vhdl_text, words_text)
        rc, out, how = invoke(v, w, c, root)
        say('    (override mechanism in use: %s)' % how)
        expect('V1', rc, 0, out, why='pristine inputs must compare equal')

        # ---- V2 one bit flipped in the VHDL ------------------------------
        newv, note = perturb_vhdl(vhdl_text)
        if newv is None:
            FAILS.append('V2')
            say('V2 FAILED: could not perturb the VHDL table -- %s' % note)
            say('    A perturbation that changes nothing would make this a FALSE'
                ' PASS, so it is reported as a failure rather than skipped.')
        else:
            root = os.path.join(tmp, 'v2')
            v, w, c = mirror_tree(root, newv, words_text)
            rc, out, how = invoke(v, w, c, root)
            named = bool(re.search(r'\b(word|index)\b', out, re.I)) and \
                len(re.findall(r'(0x[0-9a-fA-F]{8}|[01]{32})', out)) >= 2
            expect('V2', rc, 1, out, extra_ok=named,
                   why='%s; the report must name the word index and quote BOTH'
                       ' values (named=%s)' % (note, named))

        # ---- V3 one bit flipped in the .words ----------------------------
        neww, note = perturb_words(words_text)
        if neww is None:
            FAILS.append('V3')
            say('V3 FAILED: could not perturb the .words file -- %s' % note)
        else:
            root = os.path.join(tmp, 'v3')
            v, w, c = mirror_tree(root, vhdl_text, neww)
            rc, out, how = invoke(v, w, c, root)
            expect('V3', rc, 1, out, why=note + ' (drift on the SOFTWARE side)')

        # ---- V4 the .words absent ----------------------------------------
        root = os.path.join(tmp, 'v4')
        v, w, c = mirror_tree(root, vhdl_text, words_text, drop_words=True)
        rc, out, how = invoke(v, w, c, root)
        expect('V4', rc, 2, out,
               why='a missing build is rc 2, NEVER a silent rc 0')

        # ---- V5 the table one word short ---------------------------------
        shortv, note = shorten_vhdl(vhdl_text)
        if shortv is None:
            FAILS.append('V5')
            say('V5 FAILED: could not shorten the table -- %s' % note)
        else:
            root = os.path.join(tmp, 'v5')
            v, w, c = mirror_tree(root, shortv, words_text)
            rc, out, how = invoke(v, w, c, root)
            if rc != 0:
                say('V5 ok: rc=%d -- %s; a 39-word table never compares equal'
                    % (rc, note))
            else:
                FAILS.append('V5')
                say('V5 FAILED: rc=0 on a table with %s.  The mechanism is'
                    ' coupled to exactly 40 words (W_ABST = W_ENTRY + 40).'
                    % note)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    say('')
    if FAILS:
        say('VALIDATION FAILED: %s' % ', '.join(FAILS))
        return 1
    if not frozen:
        say('VALIDATION: the checker behaved correctly, but the FROZEN'
            ' trampoline content has MOVED (V0).  That is a spec-level stop.')
        return 1
    say('VALIDATION PASSED: the checker returned 0 on equal inputs, 1 on a'
        ' one-bit perturbation of EITHER source, 2 on a missing build, and'
        ' non-zero on a short table.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
