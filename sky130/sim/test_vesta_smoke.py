"""Cocotb smoke test for the VestaRV `vesta` core (via vesta_harness).

The harness pre-loads a 3-instruction RV32I program into a behavioral RAM on
the core's unified bus and exports the core's a0 (x10), trap_flag and gated
clk_cpu. This test only drives clk/resetn and observes those outputs.

Program (PC_RST_VAL = 0), full 32-bit encodings (no compressed forms):
    0x00: CAFEB537  lui  a0, 0xCAFEB     ; a0 = 0xCAFEB000
    0x04: 0BA50513  addi a0, a0, 0x0BA   ; a0 = 0xCAFEB0BA
    0x08: 0000006F  jal  x0, 0           ; self-loop (halts execution here)

Success = a0 reaches the magic value, trap_flag never asserts, and the gated
clock actually runs (clk_cpu toggles after reset).
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, ReadOnly

MAGIC = 0xCAFEB0BA
CLK_PERIOD_NS = 10
RESET_CYCLES = 5
RUN_CYCLES = 60  # multicycle core: a handful of cycles per instr + margin


async def _reset(dut):
    """Hold async active-low reset, then release on a clean edge."""
    dut.resetn.value = 0
    await ClockCycles(dut.clk, RESET_CYCLES)
    await RisingEdge(dut.clk)
    dut.resetn.value = 1


@cocotb.test()
async def a0_reaches_magic(dut):
    """Core executes lui/addi and lands the magic value in a0, no trap."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    got_magic = False
    for _ in range(RUN_CYCLES):
        await RisingEdge(dut.clk)
        await ReadOnly()
        # trap_flag must never assert during the whole run
        assert dut.trap_flag.value == 0, (
            f"trap_flag asserted (a0={dut.a0.value})"
        )
        if dut.a0.value.is_resolvable and int(dut.a0.value) == MAGIC:
            got_magic = True
            break

    assert got_magic, (
        f"a0 never reached 0x{MAGIC:08X}; "
        f"last a0={dut.a0.value!r}"
    )

    # a0 must be stable in the self-loop: check it holds for a while longer.
    for _ in range(10):
        await RisingEdge(dut.clk)
        await ReadOnly()
        assert int(dut.a0.value) == MAGIC, (
            f"a0 drifted off magic in self-loop: {dut.a0.value!r}"
        )
        assert dut.trap_flag.value == 0, "trap_flag asserted in self-loop"


@cocotb.test()
async def clk_cpu_toggles_after_reset(dut):
    """The gated core clock (clk_cpu) actually runs once out of reset."""
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())
    await _reset(dut)

    seen = set()
    for _ in range(8):
        await RisingEdge(dut.clk)
        await ReadOnly()
        if dut.clk_cpu.value.is_resolvable:
            seen.add(int(dut.clk_cpu.value))
        # sample again mid-period to catch the low phase
        await cocotb.triggers.Timer(CLK_PERIOD_NS // 2, unit="ns")
        await ReadOnly()
        if dut.clk_cpu.value.is_resolvable:
            seen.add(int(dut.clk_cpu.value))

    assert seen == {0, 1}, (
        f"clk_cpu did not toggle after reset (observed levels: {seen})"
    )
