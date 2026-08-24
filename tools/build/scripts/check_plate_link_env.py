#!/usr/bin/env python3
"""Guard the frozen mask-ROM link environment against silent drift.

tools/build/linker-scripts/{memory.x,periph.x,*_START.txt,*_SIZE.txt} are NOT a
convenience copy of generator output.
They are the link environment the taped-out rom2k_hvt_pg plate was compiled
from, and software/bootrom_mp links against them by path.
The chip generator emits its own current set under
platform/common/out/linker-scripts/, and the two have diverged as the chip
changed underneath the plate.

That divergence is expected, but it must never grow in silence.
This check recomputes it and compares it to a reviewed baseline, so the next
time the chip memory map moves the build says so instead of leaving a stale
file with a comment on it.

Plain runner, no test framework: exit 0 passes, non zero fails.
That is the repository convention for python tests here.

Usage:
  check_plate_link_env.py --baseline FILE --file NAME TRACKED GENERATED ...
  check_plate_link_env.py --update   ... same arguments, rewrites the baseline
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
