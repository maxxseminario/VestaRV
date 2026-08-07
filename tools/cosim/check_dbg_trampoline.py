#!/usr/bin/python3.6
# =============================================================================
# check_dbg_trampoline.py -- THE D4 DUAL-TRUTH GATE (d4_spec section 2).
#
#   /usr/bin/python3.6 tools/cosim/check_dbg_trampoline.py
#   /usr/bin/python3.6 tools/cosim/check_dbg_trampoline.py --vhdl X --words Y
#
#   rc 0  the two sources agree, word for word
#   rc 1  they DISAGREE -- the word index and BOTH values are quoted
#   rc 2  an input is missing or unparseable.  NEVER a silent skip.
#
# WHAT IT COMPARES, AND WHY THE COMPARISON HAS TO EXIST AT ALL
#   Since D4 the Debug Module plants the 40-word entry trampoline itself, out of
#   a constant table `TRAMP` in hdl/common/debug_module.vhd.  That table is a
#   COPY of a compiled artifact: software/dbg_trampoline/dbg_trampoline.S is
#   assembled and linked by a separate toolchain into bin/dbg_trampoline.words,
#   and the VHDL carries the same 40 words a second time.  Two sources of truth
#   for one instruction stream is a defect waiting for a maintainer, and the
#   failure is silent in the worst way: a stale table plants CODE THAT ALMOST
#   WORKS, and the symptom surfaces as a debugger that hangs on one command in
#   twenty.  R-DD5 made mechanising this a condition of choosing option B, so
#   this file is not a convenience -- it is the other half of the decision.
#
#   The coupling is tighter than "same bytes", too: the trampoline's dispatch
#   ends in `jal x0, _start + 4*40`, so its LENGTH is wired to the DM's
#   W_ABST = W_ENTRY + TRAMP_WORDS.  A table of 39 or 41 words jumps into the
#   wrong place.  So the count is checked as its own condition, before content.
#
# WHY rc 2 AND NOT A SKIP WHEN THE BUILD IS ABSENT
#   software/*/bin/ is gitignored, so the .words file is a build product that a
#   fresh clone does not have -- exactly like the images check_image_polarity.py
#   needs.  A checker that returns 0 when it cannot find its input is worse than
#   no checker, because rc 0 gets quoted as evidence.  Missing input is rc 2 and
#   says which file and how to build it.
#
# THE .words FORMAT is the one dbg_bfm.tcl's planter has always read: one line
# per word of the 64-word entry page, ascending from DEBUG_ENTRY_ADDR; a line of
# exactly 32 '0'/'1' characters is a planted word, and ANY other line (the 24
# `-   word NN: DM-written, MUST stay writable` lines) means "not part of the
# trampoline".  This file reads it the same way, on purpose: a third reading of
# the same format would be a third thing to keep in step.
#
# INPUT RESOLUTION, in order: explicit --vhdl/--words; else $VESTA_ROOT; else
# the repository root derived from this file's own location (the
# check_mcu_vhd.py idiom), so a copy of this checker dropped into a mirror tree
# checks THAT tree.
# =============================================================================
from __future__ import print_function
import os
import re
import sys

USAGE = 'usage: check_dbg_trampoline.py [--vhdl <debug_module.vhd>] [--words <dbg_trampoline.words>]'


def say(*a):
    print(*a)
    sys.stdout.flush()


def resolve():
    vhdl = None
    words = None
    argv = sys.argv[1:]
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--vhdl' and i + 1 < len(argv):
            vhdl = argv[i + 1]
            i += 2
            continue
        if a == '--words' and i + 1 < len(argv):
            words = argv[i + 1]
            i += 2
            continue
        if a in ('-h', '--help'):
            say(USAGE)
            sys.exit(2)
        say('check_dbg_trampoline: unknown argument %r' % a)
        say(USAGE)
        sys.exit(2)
    root = os.environ.get('VESTA_ROOT')
    if not root:
        root = os.path.abspath(os.path.join(
            os.path.dirname(os.path.abspath(__file__)), '..', '..'))
    if vhdl is None:
        vhdl = os.path.join(root, 'hdl', 'common', 'debug_module.vhd')
    if words is None:
        words = os.path.join(root, 'software', 'dbg_trampoline', 'bin',
                             'dbg_trampoline.words')
    return vhdl, words


def strip_comment(line):
    """Drop a VHDL end-of-line comment.

    The table carries a disassembly comment per word, and several of those name
    hex values, so comment text MUST NOT be scanned for word literals.  There is
    no string literal on these lines that could contain '--', so the naive cut
    is exact here; it is deliberately not a general VHDL lexer.
    """
    return re.sub(r'--.*$', '', line)


def parse_vhdl_table(path):
    """Return (words, error).  words is a list of ints in table order."""
    try:
        with open(path) as f:
            lines = f.read().split('\n')
    except IOError as e:
        return None, 'cannot read %s (%s)' % (path, e)

    start = None
    for n, ln in enumerate(lines):
        if re.search(r'\bconstant\s+TRAMP\s*:', strip_comment(ln)):
            start = n
            break
    if start is None:
        return None, ('no `constant TRAMP :` declaration in %s -- the D4 plant '
                      'table is absent or has been renamed' % path)

    body = []
    closed = False
    for ln in lines[start:]:
        code = strip_comment(ln)
        body.append(code)
        if ');' in code:
            closed = True
            break
    if not closed:
        return None, ('the TRAMP aggregate starting at line %d is never closed '
                      'with `);`' % (start + 1))

    text = '\n'.join(body)
    # Everything after the ':=' is the aggregate; the declaration itself carries
    # the range (0 to TRAMP_WORDS-1) and must not be scanned for literals.
    cut = text.find(':=')
    if cut < 0:
        return None, 'the TRAMP declaration has no `:=` initialiser'
    text = text[cut + 2:]

    out = []
    for m in re.finditer(r'[xX]"([0-9a-fA-F]{8})"|"([01]{32})"', text):
        if m.group(1) is not None:
            out.append(int(m.group(1), 16))
        else:
            out.append(int(m.group(2), 2))
    if not out:
        return None, 'the TRAMP aggregate contains no 32-bit word literals'
    return out, None


def parse_words(path):
    """Return (words, error).  Only 32-char binary lines are trampoline words."""
    if not os.path.exists(path):
        return None, ('the built trampoline is ABSENT: %s\n'
                      '  software/*/bin/ is gitignored, so this is a build\n'
                      '  product, not a tracked file.  Build it with:\n'
                      '      make -C software/dbg_trampoline\n'
                      '  This is rc 2 and NOT a pass: with no deliverable there\n'
                      '  is nothing to compare the VHDL table against.' % path)
    try:
        with open(path) as f:
            lines = f.read().split('\n')
    except IOError as e:
        return None, 'cannot read %s (%s)' % (path, e)
    out = []
    for ln in lines:
        s = ln.strip()
        if re.match(r'^[01]{32}$', s):
            out.append(int(s, 2))
    if not out:
        return None, ('%s contains no 32-character binary lines -- it is not a '
                      'built .words deliverable' % path)
    return out, None


def main():
    vhdl, words = resolve()
    say('check_dbg_trampoline (fmt=d4-chk-1)')
    say('  VHDL  %s' % vhdl)
    say('  words %s' % words)

    tv, err = parse_vhdl_table(vhdl)
    if err:
        say('')
        say('UNPARSEABLE (rc 2): %s' % err)
        return 2

    tw, err = parse_words(words)
    if err:
        say('')
        say('MISSING/UNPARSEABLE (rc 2): %s' % err)
        return 2

    # The count is its own condition and it is checked FIRST: the trampoline's
    # own `jal x0, _start + 4*40` is wired to the DM's W_ABST, so a table of the
    # wrong length is a structural fault and not a content mismatch.  Reporting
    # it as a content mismatch would send the next reader looking at the wrong
    # word.
    if len(tv) != len(tw):
        say('')
        say('LENGTH MISMATCH (rc 2): the VHDL TRAMP table has %d word(s), the '
            'built .words has %d.' % (len(tv), len(tw)))
        say('  W_ABST = W_ENTRY + TRAMP_WORDS couples the DM to this number, and')
        say('  the trampoline dispatches with `jal x0, _start + 4*TRAMP_WORDS`.')
        say('  A table of the wrong length jumps into the wrong code.')
        return 2

    bad = [i for i in range(len(tv)) if tv[i] != tw[i]]
    if bad:
        say('')
        say('MISMATCH (rc 1): %d of %d word(s) differ between the VHDL TRAMP '
            'table and the built trampoline.' % (len(bad), len(tv)))
        for i in bad[:16]:
            say('  word %2d:  vhdl 0x%08X   words 0x%08X' % (i, tv[i], tw[i]))
        if len(bad) > 16:
            say('  ... and %d more' % (len(bad) - 16))
        say('')
        say('  These are two spellings of ONE instruction stream and they have')
        say('  drifted.  Do not hand-patch whichever one looks wrong: edit')
        say('  software/dbg_trampoline/dbg_trampoline.S, rebuild it, and copy')
        say('  the new words into debug_module.vhd -- the .S is the original.')
        return 1

    say('')
    say('check_dbg_trampoline: OK -- all %d trampoline words are identical in '
        'the VHDL TRAMP table and the built deliverable.' % len(tv))
    return 0


if __name__ == '__main__':
    sys.exit(main())
