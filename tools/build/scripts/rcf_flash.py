#!/usr/bin/env python3
"""VestaRV: prepend the SPI-flash load and execute header to an RCF image, out of place.

Byte-compatible with flash_prepend.sh but pure input to output. Emits the 0x8000 vector-area
header, then one load region per program run, splitting only on a gap of at least GAP_MIN zero
words and padding each region with REGION_PAD trailing zeros, then 0xcafebabe. Refuses an input
that already starts with the command word. --basename-len asserts the 22-char padded name.
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
