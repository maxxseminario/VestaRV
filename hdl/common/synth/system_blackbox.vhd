-- VestaRV: synthesis black box for SYSTEM, stubbed for a tool defect
-- ghdl --synth 6.0.0 dies in its own front end on hdl/common/periph/SYSTEM.vhd:496, the individual association ClkEn(1) => open (CONSTRAINT_ERROR in vhdl-nodes.adb:407). ghdl -a -frelaxed accepts the same line, so only synthesis crashes, and //hdl/common/synth:SYSTEM is a documented skip.
-- Without the stub the crash propagates through MCU.vhd to the chip top and the gate loses 29130 flop bits of coverage to protect a block that is already ungraded.
-- The clock outputs are NOT tied off: SYSTEM is the chip's clock monarch, and a constant mclk_out would clock every flop in the MCU from a constant and census a design nothing resembles. mclk_out and smclk_out pass clk_hfxt_in through, resetn_sys passes resetn_in through, every other output is a constant.
-- Ports, names, directions and widths are otherwise SYSTEM.vhd's exactly. Retire this file when GHDL is fixed or the ClkEn(1) => open association is rewritten: delete it, drop blackbox_srcs from the MCU target, and un-skip //hdl/common/synth:SYSTEM.

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
