#!/usr/bin/env python3
"""Flat one-cycle-memory ceiling for CoreMark/Dhrystone: what the score would be if everything fit a TCM-speed memory.

verification/cpi/vesta_cpi_tb.vhd under Xcelium instead of GHDL. The two edits below are test-side and mechanical (this
Xcelium rejects external-name aliases and std.env). It is the single-hart, no-arbiter reference the shipped placements
are compared against; it does NOT model Castalia's memory map.
  run_flat.py setup | run_flat.py all
"""
import json
import os
import subprocess
import sys

import simlib
from simlib import RUN, HERE, ROOT, MARCH_H0, MARCH_TILE, sh
import run_bench as rb

FLAT = os.path.join(RUN, "flat")
CPI = os.path.join(ROOT, "verification/cpi")
WIN = 0x14000


def setup():
    os.makedirs(FLAT, exist_ok=True)
    s = open(os.path.join(CPI, "vesta_cpi_tb.vhd")).read()
    a = "alias inst_retired_x is << signal dut.inst_retired : std_logic >>;"
    assert s.count(a) == 1
    s = s.replace(a, "")
    s = s.replace("    signal stats_en : std_logic := '0';\n", "    signal stats_en : std_logic := '0';\n    signal inst_retired_x : std_logic;\n", 1)
    s = s.replace("    mask <= data_addr(1 downto 0);\n",
                  "    mask <= data_addr(1 downto 0);\n    inst_retired_x <= << signal .vesta_cpi_tb.dut.inst_retired : std_logic >>;\n", 1)
    s = s.replace("use std.env.all;\n", "")
    s = s.replace("finish(0);", "assert false report \"END\" severity failure;")
    s = s.replace("finish(1);", "assert false report \"END\" severity failure;")
    # This Xcelium segfaults inside the bench's in_ram()/ram_idx() subprograms; the same decode written inline in the
    # process does not crash. Behaviour is unchanged for defined addresses, and a metavalued address is out of window.
    x = "            idx := ram_idx(data_addr);\n"
    assert s.count(x) == 1
    s = s.replace(x, """            if is_x(data_addr) then
                inwin := false; idx := 0;
            else
                inwin := unsigned(data_addr) >= x"00008000" and unsigned(data_addr) < x"0001C000";
                idx := (to_integer(unsigned(data_addr(23 downto 2))) - 8192) mod RAM_WORDS;
            end if;
""")
    assert s.count("if in_ram(data_addr) then") == 1
    s = s.replace("if in_ram(data_addr) then", "if inwin then")
    s = s.replace("        variable idx : natural;\n", "        variable idx : natural;\n        variable inwin : boolean;\n", 1)
    open(os.path.join(FLAT, "flat_tb.vhd"), "w").write(s)
    cl = [ln.strip() for ln in open(os.path.join(HERE, "cell_list.txt"))]
    names = [c for c in cl if "/vesta/" in c or c.endswith(("constants.vhd", "MemoryMap.vhd", "ClkGate.vhd"))
             or "fixed" in c or "regs_pkg" in c and "csr" in c]
    open(os.path.join(FLAT, "cells.txt"), "w").write("\n".join("../" + n for n in names) + "\nflat_tb.vhd\n")
    print(sh(["bash", os.path.join(HERE, "build_flat.sh"), FLAT]))


def image(tag, objs, march, hot=None):
    d = os.path.join(FLAT, tag)
    elf, b, rcf = d + ".elf", d + ".bin", d + ".rcf"
    lm = "rv32imac_zicsr" if "zba" in march else march
    simlib.gcc(["-march=" + lm] + rb.BASE + ["-Wl,--no-warn-rwx-segments", "-T", os.path.join(CPI, "link_bmark.ld"),
                                            "-o", elf] + objs + ["-lgcc"])
    sh(["riscv-none-elf-objcopy", "-O", "binary", "--gap-fill=0", elf, b])
    data = open(b, "rb").read()
    assert len(data) <= WIN, len(data)
    data += bytes(WIN - len(data))
    with open(rcf, "w") as f:
        for i in range(0, WIN, 4):
            f.write("{:032b}\n".format(int.from_bytes(data[i:i + 4], "little")))
    return rcf


def run(tag, rcf):
    d = os.path.join(FLAT, "r_" + tag)
    os.makedirs(d, exist_ok=True)
    out = subprocess.run(["bash", os.path.join(HERE, "xmsim_flat.sh"), FLAT, rcf, tag], cwd=d, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, universal_newlines=True).stdout
    for ln in out.splitlines():
        if ln.startswith("CPIRESULT"):
            kv = dict(x.split("=") for x in ln.split()[2:])
            return kv
    raise SystemExit(out[-2000:])


def coremark(march, cls, iters):
    d = os.path.join(FLAT, "o_cm_" + cls)
    opts = rb.CM_OPTS + ["-DCPI_TB", "-I" + rb.CM, "-I" + os.path.join(HERE, "coremark"), "-DPERFORMANCE_RUN=1",
                         "-DITERATIONS=%d" % iters, '-DFLAGS_STR="x"', "-DTOTAL_DATA_SIZE=2000"]
    srcs = [os.path.join(rb.CM, f) for f in ("core_list_join.c", "core_main.c", "core_matrix.c", "core_state.c", "core_util.c")]
    srcs += [os.path.join(HERE, "coremark/core_portme.c"), os.path.join(HERE, "rt/port.c")]
    objs = rb.compile_objs(d, march, srcs, opts) + rb.compile_objs(d, march, [os.path.join(CPI, "crt_bmark.S")], [])
    kv = run("cm_" + cls, image("cm_" + cls, objs, march))
    c, i = int(kv["cyc_kernel"]), int(kv["ins_kernel"])
    return {"status": kv["status"], "iters": iters, "cycles": c, "instret": i, "cpi": c / i, "coremark_per_mhz": iters * 1e6 / c}


def dhry(march, cls):
    d = os.path.join(FLAT, "o_dh_" + cls)
    # verification/cpi's exact flags and object order, so hart 0's row reproduces expected.json's dhrystone counters.
    # Order matters: it sets which branch targets straddle a word, which moved this benchmark by 23 cycles per run.
    opts = [o for o in rb.DH_OPTS if o != "-fdata-sections"]
    opts += ["-I" + rb.ENV, "-I" + os.path.join(rb.BM, "common"), "-I" + os.path.join(rb.BM, "dhrystone")]
    srcs = [os.path.join(CPI, "bmark_stubs.c"), os.path.join(rb.BM, "dhrystone/dhrystone.c"),
            os.path.join(rb.BM, "dhrystone/dhrystone_main.c")]
    objs = rb.compile_objs(d, march, [os.path.join(CPI, "crt_bmark.S")], []) + rb.compile_objs(d, march, srcs, opts)
    kv = run("dh_" + cls, image("dh_" + cls, objs, march))
    c, i = int(kv["cyc_kernel"]), int(kv["ins_kernel"])
    return {"status": kv["status"], "cycles": c, "instret": i, "cpi": c / i, "cyc_per_run": c / 500,
            "dmips_per_mhz": 1e6 / (c / 500) / 1757}


def main():
    if sys.argv[1] == "setup":
        setup()
        return
    res = {}
    for cls, m in (("tile", MARCH_TILE), ("h0", MARCH_H0)):
        res["coremark_" + cls] = coremark(m, cls, 10)
        res["dhrystone_" + cls] = dhry(m, cls)
    json.dump(res, open(os.path.join(HERE, "results", "flat.json"), "w"), indent=0, sort_keys=True)
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main()
