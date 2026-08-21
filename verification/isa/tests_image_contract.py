#!/usr/bin/env python3
"""Assert the RCF image contract on a sample of the generated ISA images.

There is no tracked golden for these images: .gitignore ignores *.rcf globally
and re-includes only tools/cosim/gate/*.rcf, whose single member is the MP
bootrom image, not an ISA test image.  Byte identity against the on-disk
verification/isa/rcf/ set is therefore a hand measurement.  What is testable
here without an untracked input is the contract every consumer depends on, and
it is the contract a stale or double-staged image breaks first:

  * an unflashed image is exactly WORD_COUNT lines of 32 '0'/'1' characters
    (the Makefile's `wc -l` guard, MEM_SIZE 0x14000 / 4),
  * a flashed image starts with the 0x10adbeef command word, then the 0x8000
    and 0x8200 vector-area bounds, then 128 zero words,
  * a flashed image ends with the 0xcafebabe execute word,
  * a flashed image carries exactly ONE vector-area header; a second one is
    the K5 double-prepend that traps at 0x8200 with instr_curr = 0,
  * the flashed file name is exactly 22 characters, the TARGET_RCF_NAMELEN the
    29-character TEST_FILE generic of riscv_tb requires.

Plain runner, no pytest: exit 0 is a pass.
"""

import os
import sys

WORD_COUNT = 0x14000 // 4
RCF_BASENAME_LEN = 22

CMD_LOAD = format(0x10ADBEEF, "032b")
CMD_EXEC = format(0xCAFEBABE, "032b")
VEC_START = format(0x8000, "032b")
VEC_END = format(0x8200, "032b")
ZERO = "0" * 32


def collect():
    """Find the sampled images in the runfiles tree.

    Returns:
      (unflashed, flashed) lists of paths.
    """
    unflashed = []
    flashed = []
    for root, _dirs, files in os.walk("."):
        norm = root.replace(os.sep, "/")
        # The images live under the package directory of the runfiles tree;
        # the flashed ones sit in its flash/ subdirectory.
        if "/verification/isa" not in norm and not norm.endswith("verification/isa"):
            continue
        for f in sorted(files):
            if not f.endswith(".rcf"):
                continue
            path = os.path.join(root, f)
            if norm.endswith("/flash"):
                flashed.append(path)
            else:
                unflashed.append(path)
    return sorted(unflashed), sorted(flashed)


def check_unflashed(path, fails):
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    if len(lines) != WORD_COUNT:
        fails.append("%s: %d words, expected %d" % (path, len(lines), WORD_COUNT))
        return
    for i, ln in enumerate(lines):
        if len(ln) != 32 or ln.strip("01") != "":
            fails.append("%s: line %d is not 32 binary digits: %r" % (path, i + 1, ln))
            return
    if lines[0] == CMD_LOAD:
        fails.append("%s: unflashed image already carries the flash header" % path)


def check_flashed(path, fails):
    base = os.path.basename(path)
    if len(base) != RCF_BASENAME_LEN:
        fails.append("%s: name is %d chars, contract needs %d" % (base, len(base), RCF_BASENAME_LEN))
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    if len(lines) < 132:
        fails.append("%s: only %d lines, too short to hold the header" % (path, len(lines)))
        return
    if lines[0] != CMD_LOAD or lines[1] != VEC_START or lines[2] != VEC_END:
        fails.append("%s: vector-area header is %r" % (path, lines[0:3]))
    for i in range(3, 131):
        if lines[i] != ZERO:
            fails.append("%s: vector-area word %d is not zero" % (path, i - 3))
            break
    if lines[-1] != CMD_EXEC:
        fails.append("%s: last word is %r, expected the execute word" % (path, lines[-1]))
    # A second vector-area header means the image took the flash prepend twice.
    for i in range(1, len(lines) - 2):
        if lines[i] == CMD_LOAD and lines[i + 1] == VEC_START and lines[i + 2] == VEC_END:
            fails.append("%s: a second vector-area header at line %d" % (path, i + 1))
            break


def main():
    unflashed, flashed = collect()
    if not unflashed or not flashed:
        print("FAIL: found %d unflashed and %d flashed images in the runfiles"
              % (len(unflashed), len(flashed)))
        return 1

    fails = []
    for p in unflashed:
        check_unflashed(p, fails)
    for p in flashed:
        check_flashed(p, fails)

    if fails:
        for f in fails:
            print("FAIL: %s" % f)
        return 1

    print("OK: %d unflashed and %d flashed images meet the RCF contract"
          % (len(unflashed), len(flashed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
