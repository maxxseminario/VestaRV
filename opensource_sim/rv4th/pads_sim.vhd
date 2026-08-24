/* Tracked behavioural model of the one TSMC pad cell the MCU-level testbenches instantiate.
   The signoff model is PDUW16SDGZ_G in tsmc/pads/tphn65gpgv2od3_sl/verilog/tphn65gpgv2od3_sl.v, which lives in the shared IP tree outside this repository and is Verilog, so GHDL can neither reach it nor read it.
   This is the same substitution hdl/common/sim/ClkGate.vhd makes for the technology clock gate: one tracked behavioural VHDL unit that the open-source tier names in place of a cell library it cannot have.
   It deliberately does NOT live under hdl/common/sim, because that directory is globbed into //hdl:vhdl_sources and every xcelium cell list reads the real .v; keeping it here means no cell list can pick up both and declare the cell twice. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

/* The bidirectional pad with a programmable pull-up.
   OEN is the active-low output enable: PAD is driven from I while OEN is low and released to Z while it is high.
   REN is the active-low pull enable, and the pull acts on the RECEIVER, not on the pad, exactly as the Verilog does. */
entity PDUW16SDGZ_G is
    port (
        I   : in    std_logic;
        OEN : in    std_logic;
        REN : in    std_logic;
        PAD : inout std_logic;
        C   : out   std_logic
    );
end PDUW16SDGZ_G;

architecture behavioural of PDUW16SDGZ_G is
begin
    -- bufif0 (PAD, I, OEN): the output driver, released to high impedance when the pad is configured as an input.
    PAD <= I when OEN = '0' else 'Z';

    /* The receiver, transcribed from the Verilog gate net rather than invented.
       pmos (C_buf, PAD, 1'b0) passes the pad level to the receiver node, bufif1 (weak0,weak1) drives that node weakly high while the pull is enabled, and buf (C, C_buf) restores a full-strength level on the core side.
       The pull only engages on a floating pad, so a pad held at a weak level by the board model still wins, and To_X01 is the buf: a weak driven level reaches the core as a strong one and an undriven pad with no pull reaches it as X. */
    C <= '1' when (REN = '0' and PAD = 'Z') else To_X01(PAD);
end behavioural;
