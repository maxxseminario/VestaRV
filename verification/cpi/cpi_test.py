#!/usr/bin/env python3
"""Run one CPI image under vesta_cpi_tb and assert its counts against expected.json.

The verdict is an EXACT match on all four counters (whole-program cycles and
retired instructions, and the same pair over the setStats() kernel window),
not a tolerance. The simulation is deterministic: the same RTL, the same
image and the same testbench produce the same counts every time, so any
difference is a real change in what the core does, and a tolerance would only
hide small ones.

Everything is hermetic. The simulator is @ghdl//:ghdl with its pre-analyzed
VHDL-2008 std/ieee libraries, the RTL comes from //hdl:vhdl_sources through a
vhdl_source_set, and the image was built by //verification/cpi's genrules on
the pinned @xpack_riscv_gcc toolchain. The host contributes the Python
interpreter and nothing else.

Analysis order is load bearing (three conflicting `regfile` entities in the
tree, two `ClkGate` entities), so the source list arrives as an ordered argv
tail rather than as a filegroup.
"""

import argparse
import json
import os
import re
import subprocess
import sys

_RESULT = re.compile(
    r"CPIRESULT (?P<name>\S+) status=(?P<status>\w+) "
    r"cyc_total=(?P<cyc_total>\d+) ins_total=(?P<ins_total>\d+) "
    r"cyc_kernel=(?P<cyc_kernel>\d+) ins_kernel=(?P<ins_kernel>\d+)"
)

_COUNTERS = ("cyc_total", "ins_total", "cyc_kernel", "ins_kernel")

_ENTITY = "vesta_cpi_tb"

_GHDL_FLAGS = ["--std=08", "-fsynopsys"]


def _runfiles_root():
    """The directory $(rlocationpath ...) values are relative to."""
    cwd = os.getcwd()
    if os.path.basename(cwd) == "_main":
        return os.path.dirname(cwd)
    return os.environ.get("RUNFILES_DIR", cwd)


def _resolve(path):
    """Find a runfile given either an rlocationpath or a workspace path."""
    for cand in (
        os.path.join(_runfiles_root(), path),
        os.path.join(os.getcwd(), path),
        path,
    ):
        if os.path.exists(cand):
            return os.path.abspath(cand)
    sys.exit("cpi_test: cannot find runfile %r (cwd %s)" % (path, os.getcwd()))


def _lib_root(ghdl):
    """The -P directory holding std/v08 and ieee/v08, staged beside the binary."""
    root = os.path.join(os.path.dirname(ghdl), "vhdl_libs_v08")
    marker = os.path.join(root, "std", "v08", "std-obj08.cf")
    if not os.path.exists(marker):
        sys.exit("cpi_test: no compiled std library at %s" % marker)
    return root


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--image", required=True)
    ap.add_argument("--expected", required=True)
    ap.add_argument("--ghdl", required=True)
    ap.add_argument("--sim-timeout", type=int, default=600)
    ap.add_argument("sources", nargs="+")
    args = ap.parse_args()

    ghdl = _resolve(args.ghdl)
    image = _resolve(args.image)
    sources = [_resolve(s) for s in args.sources]
    lib_root = _lib_root(ghdl)

    with open(_resolve(args.expected)) as f:
        expected = json.load(f)
    if args.name not in expected["images"]:
        sys.exit(
            "cpi_test: expected.json has no entry for image %r. "
            "A new image must be recorded before it can be gated." % args.name
        )
    want = expected["images"][args.name]

    work = os.path.join(os.environ.get("TEST_TMPDIR", "/tmp"), "ghdl_work")
    os.makedirs(work, exist_ok=True)

    base = [ghdl] + _GHDL_FLAGS + ["-P" + lib_root, "--workdir=" + work]

    analyze = subprocess.run(
        base[:1] + ["-a"] + base[1:] + sources,
        capture_output=True,
        text=True,
    )
    if analyze.returncode != 0:
        print("FAIL %s: ghdl analysis failed" % args.name)
        print(analyze.stdout)
        print(analyze.stderr)
        return 1

    try:
        run = subprocess.run(
            base[:1] + ["-r"] + base[1:] + [
                _ENTITY,
                "-gTEST_FILE=" + image,
                "-gTEST_NAME=" + args.name,
            ],
            capture_output=True,
            text=True,
            timeout=args.sim_timeout,
        )
    except subprocess.TimeoutExpired:
        print(
            "FAIL %s: wall-clock timeout after %ds"
            % (args.name, args.sim_timeout)
        )
        return 1

    log = run.stdout + run.stderr
    match = None
    for line in log.splitlines():
        m = _RESULT.match(line.strip())
        if m and m.group("name") == args.name:
            match = m
    if match is None:
        print("FAIL %s: no CPIRESULT line in the simulation output" % args.name)
        print(log[-4000:])
        return 1

    got = {"status": match.group("status")}
    got.update({k: int(match.group(k)) for k in _COUNTERS})

    diffs = []
    if got["status"] != want["status"]:
        diffs.append(
            "status: expected %s, measured %s"
            % (want["status"], got["status"])
        )
    for k in _COUNTERS:
        if got[k] != want[k]:
            diffs.append(
                "%s: expected %d, measured %d (delta %+d)"
                % (k, want[k], got[k], got[k] - want[k])
            )

    if diffs:
        print("FAIL %s: measurement does not match expected.json" % args.name)
        for d in diffs:
            print("  " + d)
        print("")
        print("  measured  : " + " ".join("%s=%d" % (k, got[k]) for k in _COUNTERS))
        print("  expected  : " + " ".join("%s=%d" % (k, want[k]) for k in _COUNTERS))
        if got["ins_kernel"]:
            print("  kernel CPI: measured %.4f, expected %.4f" % (
                got["cyc_kernel"] / float(got["ins_kernel"]),
                want["cyc_kernel"] / float(want["ins_kernel"]),
            ))
        print("")
        print(
            "If this is a DELIBERATE core change, re-record expected.json in "
            "the SAME commit as the RTL change and update the affected tables "
            "of TRM Section 12 (s:cpi) with it. See verification/cpi/README.md."
        )
        return 1

    print(
        "PASS %s: %s"
        % (args.name, " ".join("%s=%d" % (k, got[k]) for k in _COUNTERS))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
