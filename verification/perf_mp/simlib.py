"""Shared plumbing for verification/perf_mp: snapshot setup, image build, one-sim runner, parallel pool.

Everything transient lives under <worktree>/xcelium/riscv_test/perf_mp (gitignored). Python 3.6: the host has no newer one.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
RUN = os.path.join(ROOT, "xcelium", "riscv_test", "perf_mp")
SIMHDL_SRC = os.path.expanduser("~/vestarv/hdl/common/sim")  # ARM_IP_* models are gitignored there; read-only use
PY = "/usr/bin/python3.6"
MAX_PARALLEL = int(os.environ.get("MAX_PARALLEL", "4"))
MARCH_H0 = "rv32imac_zicsr_zba_zbb_zbc_zbs"   # hart 0 orchestrator: shipped CORE_ENABLE_* set
MARCH_TILE = "rv32iac_zicsr"                  # harts 1-4: shipped TILE_ENABLE_* set


def sh(cmd, **kw):
    try:
        return subprocess.check_output(cmd, stderr=subprocess.STDOUT, universal_newlines=True, **kw)
    except subprocess.CalledProcessError as e:
        raise RuntimeError("%s\n%s" % (" ".join(cmd)[:300], e.output[-1500:]))


def setup(stalls=(0, 3)):
    """Prepare the run dir and elaborate one snapshot per negative-control stall value."""
    os.makedirs(os.path.join(RUN, "hdl"), exist_ok=True)
    for f in ("ARM_IP_RAM.vhd", "ARM_IP_ROM.vhd"):
        s = open(os.path.join(SIMHDL_SRC, f)).read()
        s = s.replace("/home/mseminario2/vestarv/software/bootrom_mp/bin/rom.rcf",
                      os.path.join(ROOT, "tools/cosim/gate/bootrom_mp_rom.rcf"))
        open(os.path.join(RUN, "hdl", f), "w").write(s)
    tb = open(os.path.join(ROOT, "hdl/common/tb/riscv_tb.vhd")).read()
    n = tb.count("constant SIMULATION_TIMEOUT : time := 100000 us;")
    m = tb.count("RamSizeBytes => 16#8100#")
    assert n == 1 and m == 1, "riscv_tb.vhd moved; re-check the two test-side patches"
    tb = tb.replace("constant SIMULATION_TIMEOUT : time := 100000 us;", "constant SIMULATION_TIMEOUT : time := 3600 sec;")
    tb = tb.replace("RamSizeBytes => 16#8100#", "RamSizeBytes => 16#20000#")
    open(os.path.join(RUN, "hdl", "riscv_tb_perf.vhd"), "w").write(tb)
    shutil.copy(os.path.join(HERE, "cell_list.txt"), RUN)
    shutil.copy(os.path.join(ROOT, "tools/cosim/gate/disable_x_warnings.tcl"), os.path.join(ROOT, "xcelium"))
    env = dict(os.environ, SNAP_D=" ".join(str(s) for s in stalls))
    print(sh(["bash", os.path.join(HERE, "build.sh"), RUN], env=env))


def gcc(args):
    return sh(["riscv-none-elf-gcc"] + args)


def compose(out, *specs):
    return sh([PY, os.path.join(HERE, "compose.py"), out] + list(specs))


class SimResult:
    def __init__(self, name, log, wall, passed, simlog, killed):
        self.name, self.log, self.wall, self.passed, self.simlog, self.killed = name, log, wall, passed, simlog, killed


def sim(name, rcf, stall=0, budget_s=600):
    """One xmsim run. budget_s is the computed estimate times a margin: past it the run is declared hung and killed."""
    d = os.path.join(RUN, "runs", name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d + "/rcf")
    os.makedirs(d + "/sim")
    shutil.copy(rcf, d + "/rcf/xxxxxxxxxxxxxxperf.rcf")
    t0 = time.time()
    p = subprocess.Popen(["bash", os.path.join(HERE, "xmsim1.sh"), RUN, "perf_d%d" % stall], cwd=d + "/sim",
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, preexec_fn=os.setsid)
    killed = False
    simlog = d + "/sim/xmsim.log"
    last_hb, last_t = None, time.time()
    while p.poll() is None:
        time.sleep(5)
        # A run is hung when the heartbeat's retire counts stop moving (perf_mon reports every 4M cycles), not when a
        # clock runs out; budget_s is only the outer bound from the recorded cycle estimate.
        hbp = d + "/sim/heartbeat.log"
        if os.path.exists(hbp):
            hb = open(hbp, errors="replace").readlines()
            if hb:
                nums = hb[-1].split()[1:]
                if last_hb is None or nums != last_hb:
                    last_hb, last_t = nums, time.time()
        if time.time() - t0 > budget_s or (last_hb is not None and time.time() - last_t > 1200):
            killed = True
            os.killpg(p.pid, 9)
            break
    p.wait()
    txt = open(simlog, errors="replace").read() if os.path.exists(simlog) else ""
    passed = "TEST PASSED" in txt
    return SimResult(name, d + "/sim/perf_mon.log", time.time() - t0, passed, simlog, killed)


def pool(jobs):
    """jobs: list of (fn, args). Runs at most MAX_PARALLEL at once; returns results in order."""
    def one(j):
        try:
            return j[0](*j[1])
        except Exception as e:      # one bad job must not lose the others' results
            print("JOB FAILED:", e, flush=True)
            return None
    with ThreadPoolExecutor(MAX_PARALLEL) as ex:
        return list(ex.map(one, jobs))


def parse_w(path):
    """W records grouped by byte address."""
    out = {}
    for ln in open(path):
        if ln.startswith("W "):
            _, cyc, m, a, v = ln.split()
            out.setdefault(int(a, 16), []).append((int(cyc), int(m), int(v, 16)))
    return out
