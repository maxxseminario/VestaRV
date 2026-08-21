#!/usr/bin/env python3
"""Prepend the SPI-flash load/execute header to an RCF image, out of place.

Python port of verification/isa/flash_prepend.sh's transform, byte-compatible
with its output, but pure input -> output (no in-place rename, no glob):
  * emit the command header for the interrupt vector area at 0x8000
    (0x10adbeef, start 0x8000, end 0x8200, 128 zero words),
  * split the program into load regions: only a run of >= GAP_MIN zero words
    separates regions, and every region carries REGION_PAD trailing zero
    words (the M19c straddled-IRET fix; both rules only ever ADD words),
  * each region becomes 0x10adbeef, start, end (exclusive), data words,
  * final word 0xcafebabe (execute).

Refuses an input that already starts with the command word (K5 guard).

Usage: rcf_flash.py INPUT.rcf OUTPUT.rcf [--basename-len N]

--basename-len asserts OUTPUT's basename is exactly N characters (the VHDL
TEST_FILE : string(1 to 29) contract is "../rcf/" + a 22-char x-padded name);
the caller chooses the padded name, this only enforces the contract.
"""

import argparse
import os
import sys

CMD_LOAD = format(0x10ADBEEF, "032b")
CMD_EXEC = format(0xCAFEBABE, "032b")
ZERO = "0" * 32
PROGRAM_START = 0x8000
GAP_MIN = 8
REGION_PAD = 2


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--basename-len", type=int, default=None)
    args = p.parse_args()

    if args.basename_len is not None:
        base = os.path.basename(args.output)
        if len(base) != args.basename_len:
            sys.exit(
                "rcf_flash: output basename %r is %d chars, contract needs %d"
                % (base, len(base), args.basename_len)
            )

    with open(args.input) as f:
        lines = [ln.rstrip("\n") for ln in f]

    if lines and lines[0] == CMD_LOAD:
        sys.exit("rcf_flash: input already carries the flash header: %s" % args.input)

    out = [CMD_LOAD, format(PROGRAM_START, "032b"), format(PROGRAM_START + 0x200, "032b")]
    out.extend([ZERO] * 128)

    total = len(lines)
    regions = []
    in_region = False
    region_start = region_end = 0
    zero_run = 0
    for i, ln in enumerate(lines):
        if ln == ZERO:
            zero_run += 1
            if in_region and zero_run >= GAP_MIN:
                regions.append((region_start, region_end))
                in_region = False
        else:
            if not in_region:
                region_start = i
                in_region = True
            region_end = i
            zero_run = 0
    if in_region:
        regions.append((region_start, region_end))

    for start, end in regions:
        pend = min(end + REGION_PAD, total - 1)
        out.append(CMD_LOAD)
        out.append(format(PROGRAM_START + 4 * start, "032b"))
        out.append(format(PROGRAM_START + 4 * (pend + 1), "032b"))
        out.extend(lines[start : pend + 1])

    out.append(CMD_EXEC)

    with open(args.output, "w", newline="\n") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
