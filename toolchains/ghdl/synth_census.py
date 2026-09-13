#!/usr/bin/env python3
"""VestaRV: the hermetic GHDL synthesizability gate and its census.

Subcommands run (synthesize one entity; exits 0 even on a GHDL failure, recording
status=error in the census), gate (PASS/FAIL a census) and freeze (against synth_census.json).
GHDL has no --latches=off, so run always passes --latches and a latch is fatal unless the
target's allow_latches fnmatches the lowercased `<entity>_B<architecture>` module name.
"""

import argparse
import collections
import fnmatch
import json
import os
import re
import subprocess
import sys
import tempfile

# Raw-netlist parsing
#
# `ghdl --synth --out=raw` emits a flat list of module bodies nested inside a
# single `$top` container, each introduced at indent 2:
#
#     module {m2} $top
#       module {m102} \TIMER
#         input \mclk;
#         ...
#         .$i{p49}: %812:$q{n798w8} := $dff{i781} (
#         ...
#         .$i{p87}: \clock_gate_timer:\clkout{n134w1} := \clkgate_Bbehavioral{i117} (
#       module {m104} \clkgate_Bbehavioral
#
# A flop is `$q{n<net>w<width>} := $dff{i<id>}`; the width is on the OUTPUT
# NET, and a scalar output carries no `w` field at all (width 1).  An
# instance of another module is `:= \<module>{i<id>}`, and the same instance
# can appear on several lines when more than one of its outputs is named, so
# instances are counted as DISTINCT ids.

_MODULE = re.compile(r"^  module \{m\d+\} (\S+)\s*$")
_FLOP = re.compile(r"\$q\{n\d+(?:w(\d+))?\}\s*:=\s*\$(i?a?dff)\{i(\d+)\}")
_LATCH = re.compile(r"\$q\{n\d+(?:w(\d+))?\}\s*:=\s*\$(a?dlatch)\{i(\d+)\}")
_INST = re.compile(r":=\s*\\([^\s{]+)\{i(\d+)\}")
_PRIM = re.compile(r":=\s*\$([a-z_0-9]+)\{i(\d+)\}")

# $signal and $port are naming markers, not cells: GHDL emits one per named
# VHDL signal so the netlist stays readable.  Counting them would make the
# cell number track comment-level RTL edits.
_NON_CELLS = frozenset(["signal", "port", "output", "input", "inout"])


class Module(object):
    def __init__(self, name):
        self.name = name
        self.flop_bits = 0
        self.latch_bits = 0
        self.cells = 0
        self.children = collections.Counter()   # module name -> instance count


def parse_netlist(path):
    """Every module body in a raw netlist with its own non-recursive counts, as (modules, top). The
    top module is the first declared: GHDL puts the synthesized entity there and the submodules it
    reached after it.
    """
    modules = []
    by_name = {}
    cur = None
    seen_inst = set()
    handle = open(path, "r")
    try:
        for line in handle:
            match = _MODULE.match(line)
            if match:
                name = match.group(1).lstrip("\\")
                cur = Module(name)
                modules.append(cur)
                by_name[name] = cur
                continue
            if cur is None:
                continue
            for width, _kind, ident in _FLOP.findall(line):
                if (cur.name, "f", ident) in seen_inst:
                    continue
                seen_inst.add((cur.name, "f", ident))
                cur.flop_bits += int(width) if width else 1
            for width, _kind, ident in _LATCH.findall(line):
                if (cur.name, "l", ident) in seen_inst:
                    continue
                seen_inst.add((cur.name, "l", ident))
                cur.latch_bits += int(width) if width else 1
            for child, ident in _INST.findall(line):
                if (cur.name, "i", ident) in seen_inst:
                    continue
                seen_inst.add((cur.name, "i", ident))
                cur.children[child] += 1
                cur.cells += 1
            for kind, ident in _PRIM.findall(line):
                if kind in _NON_CELLS:
                    continue
                if (cur.name, "p", ident) in seen_inst:
                    continue
                seen_inst.add((cur.name, "p", ident))
                cur.cells += 1
    finally:
        handle.close()

    # `$top` is a namespace, not a design: it has no body of its own.
    modules = [m for m in modules if m.name != "$top"]
    top = modules[0].name if modules else None
    return modules, by_name, top


def rollup(modules, by_name, top):
    """Multiply each module's own counts by how many times it is instantiated, which is what a
    hierarchical cell count means. Depth-first over a DAG, a synthesis netlist being acyclic, and
    memoized on the module name.
    """
    multiplicity = collections.Counter()

    def visit(name, factor):
        node = by_name.get(name)
        if node is None:
            return
        multiplicity[name] += factor
        for child, count in node.children.items():
            visit(child, factor * count)

    if top is not None:
        visit(top, 1)

    total = {"flop_bits": 0, "latch_bits": 0, "cells": 0}
    flat = {"flop_bits": 0, "latch_bits": 0, "cells": 0}
    rows = []
    for module in modules:
        factor = multiplicity.get(module.name, 0)
        rows.append({
            "module": module.name,
            "instances": factor,
            "flop_bits": module.flop_bits,
            "latch_bits": module.latch_bits,
            "cells": module.cells,
        })
        for key in total:
            total[key] += getattr(module, key) * factor
            flat[key] += getattr(module, key)
    return total, flat, rows


# What counts as fatal in the GHDL log
#
# GHDL's synth diagnostics carry a warning class in brackets.  Three of them
# say "this will not build the hardware you wrote" and are treated as errors
# here; the rest are noise this tree has on purpose.
#
#   -Wnowrite      a port or signal is never assigned.  In synthesis that is
#                  a dangling output, which Genus resolves to a constant.
#                  NOT fatal on an internal signal slice, because
#                  periph_regs.vhd legitimately leaves whole words of its
#                  we_m/set_m/clr_m masks unwritten for registers a block does
#                  not implement -- so only the "port" spelling is graded.
#   -Wruntime-error   a constant index outside its array bound.  GHDL folds
#                  it to X and carries on; Genus does not.
#   (unclassed) "cannot be at the top of a design", "is not a design unit",
#                  any line containing ":error:", and any GHDL internal
#                  exception (CONSTRAINT_ERROR and friends).
#
# DELIBERATELY NOT FATAL:
#   -Wbinding      vesta.vhd:3565 instantiates vesta_tracer inside
#                  `if TRACE_ENABLE generate`, which is FALSE in every build.
#                  GHDL warns about the unbound component before it discards
#                  the block, so this class fires on a design that is correct.
#   -Wunhandled-attribute   sync.vhd's DONT_TOUCH / ASYNC_REG / KEEP are for
#                  the downstream synthesizer, not for GHDL.
#   -Wopen-assoc   `ClkEn(1) => open`, the -frelaxed waiver the benches
#                  already carry.
#   -Whide, -Wdelayed-checks, -Wshared, -Wspecs, and the
#   "ieee library directory ... not found" line, which is GHDL looking for a
#                  system install it does not need because -P is supplied.

FATAL_WARNING_CLASSES = ("-Wruntime-error",)

_FATAL_TEXT = (
    "cannot be at the top of a design",
    "GHDL Bug occurred",
    "Exception CONSTRAINT_ERROR",
    "raised CONSTRAINT_ERROR",
    "raised STORAGE_ERROR",
    "raised PROGRAM_ERROR",
)


def fatal_lines(log_text):
    """The diagnostics that must turn the target red, in order."""
    out = []
    for line in log_text.splitlines():
        if ":error:" in line or line.startswith("error:"):
            out.append(line)
            continue
        if any(cls in line for cls in FATAL_WARNING_CLASSES):
            out.append(line)
            continue
        if "[-Wnowrite]" in line and 'port "' in line:
            out.append(line)
            continue
        if any(text in line for text in _FATAL_TEXT):
            out.append(line)
    return out


# run

def cmd_run(args):
    workdir = tempfile.mkdtemp(prefix="ghdl_synth_")
    log = []

    def ghdl(*rest):
        argv = [args.ghdl] + list(rest)
        log.append("$ " + " ".join(argv))
        proc = subprocess.Popen(argv, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        out = proc.communicate()[0].decode("utf-8", "replace")
        log.append(out)
        return proc.returncode, out

    common = ["--std=" + args.std] + args.flag + ["-P" + args.lib_root,
                                                  "--workdir=" + workdir]
    arc, _ = ghdl(*(["-a"] + common + args.src))

    src = 1
    if arc == 0:
        synth = ["--synth"] + common + ["--latches", "--out=raw"]
        for generic in args.generic:
            synth.append("-g" + generic)
        synth.append(args.entity)
        argv = [args.ghdl] + synth
        log.append("$ " + " ".join(argv))
        netlist = open(args.netlist, "wb")
        try:
            proc = subprocess.Popen(argv, stdout=netlist,
                                    stderr=subprocess.PIPE)
            err = proc.communicate()[1].decode("utf-8", "replace")
            src = proc.returncode
        finally:
            netlist.close()
        log.append(err)
    else:
        open(args.netlist, "w").close()

    text = "\n".join(log)
    open(args.log, "w").write(text)

    fatals = fatal_lines(text)
    census = {
        "entity": args.entity,
        "target": args.target,
        "generics": sorted(args.generic),
        "allow_latches": sorted(args.allow_latch),
        "blackboxes": sorted(args.blackbox),
        "analyze_rc": arc,
        "synth_rc": src,
        "fatal": fatals,
    }

    if arc != 0 or src != 0 or fatals:
        census["status"] = "error"
        census["flop_bits"] = None
        census["latch_bits"] = None
        census["cells"] = None
        census["latch_modules"] = []
        census["unallowed_latch_modules"] = []
        census["modules"] = []
    else:
        modules, by_name, top = parse_netlist(args.netlist)
        total, flat, rows = rollup(modules, by_name, top)
        latch_modules = sorted(m.name for m in modules if m.latch_bits)
        bad = [n for n in latch_modules
               if not any(fnmatch.fnmatch(n, p) for p in args.allow_latch)]
        census["status"] = "ok" if not bad else "latch"
        census["top_module"] = top
        census["flop_bits"] = total["flop_bits"]
        census["latch_bits"] = total["latch_bits"]
        census["cells"] = total["cells"]
        census["flat_flop_bits"] = flat["flop_bits"]
        census["latch_modules"] = latch_modules
        census["unallowed_latch_modules"] = sorted(bad)
        census["modules"] = rows

    handle = open(args.census, "w")
    try:
        json.dump(census, handle, indent=2, sort_keys=True)
        handle.write("\n")
    finally:
        handle.close()
    return 0


# gate

def cmd_gate(args):
    census = json.load(open(data_path(args.census)))
    name = census.get("target") or census["entity"]

    if census["status"] == "skipped":
        print("SKIP %s: %s" % (name, census["skip_reason"]))
        return 0

    if census["status"] == "error":
        print("FAIL %s: ghdl --synth rejected the design" % name)
        print("  analyze rc=%s  synth rc=%s"
              % (census["analyze_rc"], census["synth_rc"]))
        for line in census["fatal"][:40]:
            print("  %s" % line)
        if args.log:
            print("--- ghdl log (tail) ---")
            tail = open(data_path(args.log)).read().splitlines()[-60:]
            for line in tail:
                print("  %s" % line)
        return 1

    if census["status"] == "latch":
        print("FAIL %s: latch inferred outside the allowlist" % name)
        for module in census["unallowed_latch_modules"]:
            print("  module %s" % module)
        print("  allowlist: %s" % (census["allow_latches"] or "(empty)"))
        print("  An incomplete if/case in a combinational process infers a")
        print("  latch.  Assign every branch, or -- if this really is a clock")
        print("  cell -- add the module pattern to allow_latches with a reason.")
        return 1

    print("PASS %s: %d flop bits, %d latch bits (%s), %d cells"
          % (name, census["flop_bits"], census["latch_bits"],
             ", ".join(census["latch_modules"]) or "none", census["cells"]))
    return 0


# freeze

FROZEN_HEADER = {
    "_comment": [
        "toolchains/ghdl/synth_census.json -- the FROZEN synthesis census.",
        "",
        "One row per //hdl/common:synth target: the flop bits, latch bits and",
        "cell count ghdl --synth produces for that entity at its shipped",
        "generics.  //toolchains/ghdl:synth_census_test fails when any of them",
        "moves, so a register bank that silently doubles, a reset that stops",
        "reaching a flop, or a new latch is caught on the commit that does it.",
        "",
        "Regenerating this file is a DELIBERATE ACT.",
        "Run  tools/bin/bazel run //toolchains/ghdl:synth_census_update",
        "and commit the result in the SAME commit as the change it blesses, so",
        "the review sees the blessing next to the thing being blessed.",
        "",
        "A 'skipped' row records a block this tier cannot synthesize, with the",
        "reason; it is graded only on the reason still matching the BUILD file.",
    ],
}


def runfiles_root():
    """Where data dependencies live. A py_test runs with its working directory at the runfiles root,
    so a $(rootpath) argument resolves as-is; `bazel run` sets it to the workspace instead. Both
    are handled by trying the working directory first and the runfiles root second.
    """
    for var in ("RUNFILES_DIR", "TEST_SRCDIR"):
        base = os.environ.get(var)
        if base:
            return base
    guess = os.path.abspath(sys.argv[0]) + ".runfiles"
    if os.path.isdir(guess):
        return guess
    return None


def data_path(rel):
    if os.path.exists(rel):
        return rel
    root = runfiles_root()
    if root:
        for candidate in (os.path.join(root, "_main", rel),
                          os.path.join(root, rel)):
            if os.path.exists(candidate):
                return candidate
    return rel


def load_censuses(paths):
    out = {}
    for path in paths:
        census = json.load(open(data_path(path)))
        key = census.get("target") or census["entity"]
        out[key] = census
    return out


def census_row(census):
    if census.get("status") == "skipped":
        return {"skipped": census["skip_reason"]}
    row = {
        "cells": census["cells"],
        "flop_bits": census["flop_bits"],
        "latch_bits": census["latch_bits"],
        "latch_modules": census["latch_modules"],
    }
    # Emitted only when the target has black boxes, so the twenty-odd rows
    # that have none carry no empty field.  A black box hides real hierarchy
    # from the gate, which is exactly why the list is frozen: adding one is a
    # visible act.
    if census.get("blackboxes"):
        row["blackboxes"] = sorted(census["blackboxes"])
    return row


UPDATE_CMD = "tools/bin/bazel run //toolchains/ghdl:synth_census_update"


def cmd_freeze(args):
    paths = list(args.census)
    if args.census_from:
        handle = open(data_path(args.census_from))
        try:
            for line in handle:
                text = line.strip()
                if text:
                    paths.append(text)
        finally:
            handle.close()
    if not paths:
        sys.stderr.write("ERROR: no census files given; the manifest is empty.\n")
        return 2
    live = load_censuses(paths)
    rows = {}
    for name in sorted(live):
        rows[name] = census_row(live[name])

    if args.update:
        root = os.environ.get("BUILD_WORKSPACE_DIRECTORY")
        if not root:
            sys.stderr.write(
                "ERROR: --update must run under `bazel run`, which is what\n"
                "       sets BUILD_WORKSPACE_DIRECTORY.  Use:\n"
                "       %s\n" % UPDATE_CMD)
            return 2
        out = os.path.join(root, args.frozen)
        payload = dict(FROZEN_HEADER)
        payload["entities"] = rows
        handle = open(out, "w")
        try:
            json.dump(payload, handle, indent=2, sort_keys=True)
            handle.write("\n")
        finally:
            handle.close()
        print("wrote %s: %d entities" % (out, len(rows)))
        return 0

    frozen = json.load(open(data_path(args.frozen))).get("entities", {})

    failures = []
    for name in sorted(set(frozen) | set(rows)):
        want = frozen.get(name)
        got = rows.get(name)
        if want is None:
            failures.append("%s: not in the frozen census (new target)" % name)
            continue
        if got is None:
            failures.append("%s: frozen but no synth target produces it" % name)
            continue
        if "skipped" in want or "skipped" in got:
            if want.get("skipped") != got.get("skipped"):
                failures.append("%s: skip status changed\n    frozen: %s\n    now:    %s"
                                % (name, want.get("skipped"), got.get("skipped")))
            continue
        for field in ("flop_bits", "latch_bits", "cells"):
            if want.get(field) != got.get(field):
                failures.append("%s: %s %s -> %s"
                                % (name, field, want.get(field), got.get(field)))
        for field in ("latch_modules", "blackboxes"):
            if sorted(want.get(field, [])) != sorted(got.get(field, [])):
                failures.append("%s: %s %s -> %s"
                                % (name, field, want.get(field, []),
                                   got.get(field, [])))

    if failures:
        print("FAIL: the synthesis census moved.")
        for line in failures:
            print("  %s" % line)
        print("")
        print("A count that changed on purpose is blessed by regenerating the")
        print("frozen table IN THE SAME COMMIT as the RTL change:")
        print("  %s" % UPDATE_CMD)
        return 1

    graded = sum(1 for r in rows.values() if "skipped" not in r)
    print("OK: synthesis census unchanged - %d entities graded, %d skipped."
          % (graded, len(rows) - graded))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd")

    run = sub.add_parser("run")
    run.add_argument("--ghdl", required=True)
    run.add_argument("--lib-root", required=True)
    run.add_argument("--std", default="08")
    run.add_argument("--flag", action="append", default=[])
    run.add_argument("--src", action="append", default=[])
    run.add_argument("--generic", action="append", default=[])
    run.add_argument("--allow-latch", action="append", default=[])
    run.add_argument("--blackbox", action="append", default=[],
                     help="basename of a synthesis black-box stub analyzed "
                          "ahead of --src; recorded in the frozen census")
    run.add_argument("--entity", required=True)
    run.add_argument("--target", default="")
    run.add_argument("--netlist", required=True)
    run.add_argument("--census", required=True)
    run.add_argument("--log", required=True)
    run.set_defaults(func=cmd_run)

    gate = sub.add_parser("gate")
    gate.add_argument("--census", required=True)
    gate.add_argument("--log", default="")
    gate.set_defaults(func=cmd_gate)

    freeze = sub.add_parser("freeze")
    freeze.add_argument("--frozen", required=True)
    freeze.add_argument("--census", action="append", default=[])
    freeze.add_argument("--census-from", default="",
                        help="file holding one census path per line")
    freeze.add_argument("--update", action="store_true")
    freeze.set_defaults(func=cmd_freeze)

    args = parser.parse_args(argv)
    if not getattr(args, "func", None):
        parser.print_help()
        return 2
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
