#!/usr/bin/env python3
"""VestaRV: guard the frozen mask-ROM link environment against silent drift.

tools/build/linker-scripts/ is the environment the taped-out rom2k_hvt_pg plate was compiled
from and bootrom_mp links against by path, not a copy of generator output. It has diverged
from the generator's current set, which is expected; this recomputes the divergence and
compares it against a reviewed baseline, so the next memory-map move is announced. Exit 0 passes.
"""

import argparse
import difflib
import sys

# The generator stamps a wall-clock line into every file it writes.
# It carries no memory-map information, so it is dropped before comparing.
STAMP = "Generated on "

HEADER = [
    "# Divergence between the frozen mask-ROM link environment in",
    "# tools/build/linker-scripts/ and the current chip generator output",
    "# (//platform/common:castalia_linker_scripts).",
    "#",
    "# Regenerate with tools/build:rom_plate_link_env_test's --update mode.",
    "# See tools/build/BUILD.bazel for why the two are allowed to differ and",
    "# what has to happen before they are allowed to be reconciled.",
    "#",
    "# The 'Generated on' stamp line is dropped from both sides before diffing.",
]


def readLines(path):
    """The file's lines, stamp line dropped, newline terminated."""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    keep = [ln for ln in text.splitlines() if STAMP not in ln]
    return [ln + "\n" for ln in keep]


def divergence(pairs):
    """The full divergence report for every (name, tracked, generated) triple."""
    out = list(HEADER)
    for name, tracked, generated in pairs:
        out.append("")
        out.append("=== %s ===" % name)
        diff = difflib.unified_diff(
            readLines(tracked),
            readLines(generated),
            fromfile="tracked/" + name,
            tofile="generated/" + name,
            n=2,
        )
        body = [ln.rstrip("\n") for ln in diff]
        if not body:
            body = ["(identical)"]
        out.extend(body)
    return "\n".join(out) + "\n"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--baseline", required=True)
    p.add_argument(
        "--file",
        nargs=3,
        action="append",
        metavar=("NAME", "TRACKED", "GENERATED"),
        required=True,
    )
    p.add_argument("--update", action="store_true")
    args = p.parse_args()

    actual = divergence(args.file)

    if args.update:
        with open(args.baseline, "w", encoding="utf-8") as f:
            f.write(actual)
        print("wrote %s (%d lines)" % (args.baseline, actual.count("\n")))
        return 0

    with open(args.baseline, "r", encoding="utf-8") as f:
        expected = f.read()

    if actual == expected:
        print(
            "PASS: the frozen mask-ROM link environment diverges from the "
            "generated chip map exactly as recorded in %s" % args.baseline
        )
        return 0

    print("FAIL: the mask-ROM link environment divergence changed.")
    print("")
    print("tools/build/linker-scripts/ is the link environment the taped-out")
    print("rom2k_hvt_pg plate was compiled from.  Either the chip memory map")
    print("moved again, or somebody edited the frozen copy.  Neither is wrong")
    print("on its own, but both need a decision:")
    print("")
    print("  * chip map moved   -> review the new divergence below, and if the")
    print("                        plate is still the part that ships, re-record")
    print("                        the baseline.  If the plate is being re-cut,")
    print("                        the boot image, its two goldens and the mask")
    print("                        plate all move together.")
    print("  * frozen copy edited -> software/bootrom_mp's image moves with it.")
    print("                        //software/bootrom_mp:rom_rcf_reproducibility_test")
    print("                        is the gate that catches that.")
    print("")
    for line in difflib.unified_diff(
        expected.splitlines(),
        actual.splitlines(),
        fromfile="recorded divergence",
        tofile="divergence now",
        lineterm="",
        n=3,
    ):
        print(line)
    return 1


if __name__ == "__main__":
    sys.exit(main())
