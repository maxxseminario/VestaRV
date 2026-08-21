#!/usr/bin/env python3
"""Guard the "THIS LIST MUST STAY IN SYNC" comment on the vesta source order.

Four places name the curated vesta source list, and the comments in three of
them say so out loud:

  opensource_sim/isa/run_isa.sh   SOURCES array          (simulation, Zfinx on)
  opensource_sim/isa/defs.bzl     VESTA_ISA_RTL          (this bazel port)
  sky130/synth.sh                 FILES array            (yosys synthesis)
  sky130/sim/Makefile             VHDL_SOURCES           (cocotb smoke test)

The order is load bearing (three `regfile` entities, two `ClkGate` entities),
so drift here is a real defect, not a style nit. The two sky130 lists are the
same sequence MINUS the Zfinx FPU pair, which only the ISA testbench enables;
that difference is asserted explicitly rather than ignored.

Plain runner: exit 0 means pass. No pytest.
"""

import re
import sys

FPU_PAIR = ["hdl/common/vesta/fpu_simple.vhd", "hdl/common/vesta/fpu.vhd"]

# Files each list carries that are not part of the shared RTL sequence.
NOT_RTL = ("vesta_isa_tb.vhd", "vesta_harness.vhd", "$TB")


def normalize(raw):
    """Turn one list entry into a workspace-relative hdl/common/... path."""
    raw = raw.strip().strip('"').strip("'")
    raw = raw.replace("${COMMON}", "hdl/common")
    raw = raw.replace("../hdl/common", "hdl/common")
    raw = raw.replace("$(COMMON)", "hdl/common")
    raw = raw.replace("$COMMON", "hdl/common")
    return raw


def extract_shell_array(path, name):
    """Pull `name=( ... )` out of a bash script, dropping comments."""
    text = open(path).read()
    m = re.search(r"^%s=\(\s*(.*?)^\)" % re.escape(name), text,
                  re.MULTILINE | re.DOTALL)
    if not m:
        return None
    out = []
    for line in m.group(1).split("\n"):
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        out.append(normalize(line))
    return out


def extract_make_list(path, name):
    """Pull a backslash-continued `name = a \\ b \\ c` make variable."""
    text = open(path).read()
    m = re.search(r"^%s\s*=\s*((?:.*\\\n)*.*)$" % re.escape(name), text,
                  re.MULTILINE)
    if not m:
        return None
    body = m.group(1).replace("\\\n", " ")
    out = []
    for tok in body.split():
        tok = normalize(tok)
        if tok:
            out.append(tok)
    return out


def rtl_only(entries):
    return [e for e in entries
            if not any(e.endswith(x) for x in NOT_RTL)]


def main(argv):
    if len(argv) != 5:
        print("usage: source_list_sync_test.py <run_isa.sh> <defs.bzl> "
              "<synth.sh> <sim/Makefile>")
        return 2
    run_isa, defs_bzl, synth_sh, sim_makefile = argv[1:5]

    errors = []

    bzl_text = open(defs_bzl).read()
    m = re.search(r"VESTA_ISA_RTL\s*=\s*\[(.*?)\]", bzl_text, re.DOTALL)
    if not m:
        print("FAIL: VESTA_ISA_RTL not found in %s" % defs_bzl)
        return 1
    bazel_list = [normalize(x) for x in re.findall(r'"([^"]+)"', m.group(1))]

    shell_list = extract_shell_array(run_isa, "SOURCES")
    if shell_list is None:
        errors.append("SOURCES array not found in %s" % run_isa)
        shell_list = []
    shell_rtl = rtl_only(shell_list)

    synth_list = extract_shell_array(synth_sh, "FILES")
    if synth_list is None:
        errors.append("FILES array not found in %s" % synth_sh)
        synth_list = []
    synth_rtl = rtl_only(synth_list)

    sim_list = extract_make_list(sim_makefile, "VHDL_SOURCES")
    if sim_list is None:
        errors.append("VHDL_SOURCES not found in %s" % sim_makefile)
        sim_list = []
    sim_rtl = rtl_only(sim_list)

    if bazel_list != shell_rtl:
        errors.append("VESTA_ISA_RTL != run_isa.sh SOURCES\n  bazel:   %s\n  run_isa: %s"
                      % (bazel_list, shell_rtl))

    expected_sky = [p for p in bazel_list if p not in FPU_PAIR]
    if synth_rtl != expected_sky:
        errors.append("sky130/synth.sh SOURCES != VESTA_ISA_RTL minus the Zfinx FPU pair\n"
                      "  synth.sh: %s\n  expected: %s" % (synth_rtl, expected_sky))
    if sim_rtl != expected_sky:
        errors.append("sky130/sim/Makefile VHDL_SOURCES != VESTA_ISA_RTL minus the Zfinx FPU pair\n"
                      "  Makefile: %s\n  expected: %s" % (sim_rtl, expected_sky))

    if FPU_PAIR[0] not in bazel_list or FPU_PAIR[1] not in bazel_list:
        errors.append("the Zfinx FPU pair is missing from VESTA_ISA_RTL; without it "
                      "the fpu instances are unbound and every FP op hangs the "
                      "multicycle FSM")

    print("checked %d RTL entries against 3 other lists" % len(bazel_list))
    if errors:
        for e in errors:
            print("FAIL: %s" % e)
        return 1
    print("PASS: all four vesta source lists agree")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
