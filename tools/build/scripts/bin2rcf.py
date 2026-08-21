#!/usr/bin/env python3
"""Convert a padded binary image to the RCF text format the VHDL ROMs read.

RCF format: one line per 32-bit word, 32 ASCII '0'/'1' characters, MSB first.
Word N comes from bytes [4N, 4N+4) of the input, little-endian.

This is the single canonical replacement for the od+awk nibble-table pipeline
that historically existed in five divergent copies across the makefiles.
Stdlib only, so it runs under the hermetic bazel interpreter with no pip deps.

Usage: bin2rcf.py INPUT.bin OUTPUT.rcf [--expect-words N]

--expect-words asserts the exact output line count (the makefiles' `wc -l`
guard, e.g. 4096 for the 16KB boot ROM).
"""

import argparse
import sys


def main():
    p = argparse.ArgumentParser()
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--expect-words", type=int, default=None)
    args = p.parse_args()

    with open(args.input, "rb") as f:
        data = f.read()

    if len(data) % 4 != 0:
        sys.exit("bin2rcf: input length %d is not a multiple of 4" % len(data))

    words = len(data) // 4
    if args.expect_words is not None and words != args.expect_words:
        sys.exit(
            "bin2rcf: expected %d words, input holds %d"
            % (args.expect_words, words)
        )

    with open(args.output, "w", newline="\n") as out:
        for i in range(words):
            w = int.from_bytes(data[4 * i : 4 * i + 4], "little")
            out.write(format(w, "032b") + "\n")


if __name__ == "__main__":
    main()
