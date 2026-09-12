/* Synthesis BLACK BOX for SYSTEM, the one cell here stubbed for a TOOL defect.

   `ghdl --synth` 6.0.0 dies inside its own front end on
   hdl/common/periph/SYSTEM.vhd:496, `ClkEn(1) => open` in an individual
   association:

       ******************** GHDL Bug occurred ********************
       Exception CONSTRAINT_ERROR raised
       raised CONSTRAINT_ERROR : vhdl-nodes.adb:407 index check failed

   `ghdl -a -frelaxed` accepts the same line (warning -Wopen-assoc, the waiver
   xcelium's -relax gives and the reason SYSTEM_tb carries -frelaxed); only
   synthesis crashes.  //hdl/common/synth:SYSTEM has been a documented skip
   for it since the suite was built, and --out=none and the file-list form
   were both measured to crash identically.

   WITHOUT THIS STUB THE WHOLE MCU GOES WITH IT.  MCU.vhd instantiates SYSTEM,
   so the crash propagates to the chip top and the gate loses 29130 flop bits
   of coverage to protect one block that is already ungraded.  With it, MCU
   synthesizes and everything else in the MCU is graded; SYSTEM stays exactly
   as ungraded as its own skip row already says it is.

   THE CLOCK OUTPUTS ARE NOT TIED OFF, and that is the one place this stub is
   not a plain constant driver.  SYSTEM is the chip's clock monarch: tying
   mclk_out low would clock every flop in the MCU from a constant, and the
   census would then measure a design nothing resembles.  mclk_out and
   smclk_out pass clk_hfxt_in through, resetn_sys passes resetn_in through,
   and every other output is a constant.  Ports, names, directions and widths
   are otherwise SYSTEM.vhd's exactly, so an MCU that names a pin SYSTEM does
   not have still fails at analysis.

   WHAT RETIRES THIS FILE: a GHDL fix, or rewriting the `ClkEn(1) => open`
   association in SYSTEM.vhd.  On either day, delete this file, drop
   blackbox_srcs from the MCU target, and un-skip //hdl/common/synth:SYSTEM. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity SYSTEM is
    port (
        -- Clock inputs
        clk_lfxt_in      : in  std_logic;
        clk_hfxt_in      : in  std_logic;
        clk_dco0_in      : in  std_logic;
        clk_dco1_in      : in  std_logic;

        -- Reset
        resetn_in        : in  std_logic;
        resetn_por       : in  std_logic;
        resetn_sys       : out std_logic;

        -- Watchdog interrupt and its delivery handshake
        irq_sys_wdt      : out std_logic;
        wdt_irq_routed   : in  std_logic := '0';
        wdt_irq_complete : in  std_logic := '0';

        -- Register bus
        clk_mem          : in  std_logic;
        en_mem           : in  std_logic;
        wen              : in  std_logic_vector(3 downto 0);
        addr_periph      : in  std_logic_vector(7 downto 2);
        write_data       : in  std_logic_vector(31 downto 0);
        read_data        : out std_logic_vector(31 downto 0);

        -- Clock outputs
        mclk_out         : out std_logic;
        smclk_out        : out std_logic;
        clk_lfxt_out     : out std_logic;
        clk_hfxt_out     : out std_logic;

        -- DCO controls
        en_dco0_out      : out std_logic;
        DCO0_BIAS        : out std_logic_vector(11 downto 0);
        en_dco1_out      : out std_logic;
        DCO1_BIAS        : out std_logic_vector(11 downto 0);

        -- Memory power gating, one bit per block
        PGEN_mem         : out std_logic_vector(6 downto 0)
    );
end SYSTEM;

architecture blackbox of SYSTEM is
begin
    -- Clocks and reset pass through: see the header for why these are not
    -- constants.
    mclk_out     <= clk_hfxt_in;
    smclk_out    <= clk_hfxt_in;
    clk_lfxt_out <= clk_lfxt_in;
    clk_hfxt_out <= clk_hfxt_in;
    resetn_sys   <= resetn_in;

    irq_sys_wdt  <= '0';
    read_data    <= (others => '0');
    en_dco0_out  <= '0';
    DCO0_BIAS    <= (others => '0');
    en_dco1_out  <= '0';
    DCO1_BIAS    <= (others => '0');
    PGEN_mem     <= (others => '0');
end architecture blackbox;
