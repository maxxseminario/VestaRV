"""Analysis order for the boot-ROM Forth monitor bench, hdl/common/tb/rv4th_tb.vhd.

RV4TH_RTL is VESTA_MCU_RTL -- the same MCU spine //opensource_sim/mcu
elaborates -- with the four files the testbench itself needs added around it.
It is DERIVED and not copied, so //opensource_sim/isa:source_list_sync_test
stays the single authority on the shared core sequence and this package cannot
drift away from it.

The four additions, and why each one is here:

  * hdl/common/macros/macros.vhd. rv4th_tb has `use work.macros.all`. No
    synthesizable unit reads it, which is why the MCU list leaves it out; it
    goes FIRST because it depends on nothing but ieee.
  * hdl/common/tb/tb_defs.vhd and hdl/common/tb/TestbenchLibrary.vhd. The
    latter carries UartSendStrNToRX / UartReceiveStringFromTX, which are the
    whole UART transactor. Both are in the xcelium cell list for this bench.
  * hdl/common/tb/rv4th_tb.vhd, the bench itself, last.

macros.vhd and constants.vhd BOTH declare sl, slv, word and word_array. Two
homographs made potentially visible by two use clauses are ambiguous rather
than doubly visible, so nothing may reference those names through a scope that
opens both. rv4th_tb opens both and spells every signal std_logic_vector,
which is what keeps that legal; TestbenchLibrary opens only constants.

NOT in this list, and deliberately:

  * the TSMC pad library. rv4th_tb instantiates PDUW16SDGZ_G on all 33 pads,
    and the signoff model is Verilog in a directory outside this repository.
    opensource_sim/rv4th/pads_sim.vhd is the tracked VHDL stand-in and is
    prepended at the consumer, the same way the memory macro model is.
  * hdl/common/sim/ARM_IP_ROM.vhd and ARM_IP_RAM.vhd, replaced by
    //opensource_sim/mcu:mem_macros_sim.vhd, which reaches the real boot image
    through a generated path package instead of an absolute /home/... open.
  * hdl/common/tb/serial_flash.vhd. rv4th_tb holds BOOT low, so the monitor
    never touches the SPI flash and nothing instantiates the model. riscv_tb
    needs it; this bench does not.
"""

load("//opensource_sim/mcu:defs.bzl", "VESTA_MCU_RTL")

_MACROS = "hdl/common/macros/macros.vhd"

_TB = [
    "hdl/common/tb/tb_defs.vhd",
    "hdl/common/tb/TestbenchLibrary.vhd",
    "hdl/common/tb/rv4th_tb.vhd",
]

def _derive():
    for f in [_MACROS] + _TB:
        if f in VESTA_MCU_RTL:
            fail("opensource_sim/rv4th/defs.bzl: %s is now in VESTA_MCU_RTL as " % f +
                 "well as this list; analyzing one file twice redefines its " +
                 "design units. Drop it from here.")
    return [_MACROS] + VESTA_MCU_RTL + _TB

RV4TH_RTL = _derive()
