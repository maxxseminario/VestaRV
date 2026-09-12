-- VestaRV: SYSTEM register package
-- Controls the entire system, including the clocking and power state
-- Generated from hdl/common/regs/rdl/system.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package system_regs_pkg is

    -- SYSCLKCR: System clock control register
    constant SYSCLKCR_WORD            : natural := 0;
    constant SYSCLKCR_ADDR            : natural := 0;
    constant SYSCLKCR_RESET           : std_logic_vector(15 downto 0) := "0000000000000000";
    constant SYSCLKCR_IMPL            : std_logic_vector(15 downto 0) := "0000000111111111";
    constant DCO1ON_MSB               : natural := 8;
    constant DCO1ON_LSB               : natural := 8;
    constant DCO1ON_RESET             : std_logic_vector(0 downto 0) := "0";
    constant DCO0ON_MSB               : natural := 7;
    constant DCO0ON_LSB               : natural := 7;
    constant DCO0ON_RESET             : std_logic_vector(0 downto 0) := "0";
    constant HFXTOFF_MSB              : natural := 6;
    constant HFXTOFF_LSB              : natural := 6;
    constant HFXTOFF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant LFXTOFF_MSB              : natural := 5;
    constant LFXTOFF_LSB              : natural := 5;
    constant LFXTOFF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SMCLKOFF_MSB             : natural := 4;
    constant SMCLKOFF_LSB             : natural := 4;
    constant SMCLKOFF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant SMCLKSEL_MSB             : natural := 3;
    constant SMCLKSEL_LSB             : natural := 2;
    constant SMCLKSEL_RESET           : std_logic_vector(1 downto 0) := "00";
    constant MCLKSEL_MSB              : natural := 1;
    constant MCLKSEL_LSB              : natural := 0;
    constant MCLKSEL_RESET            : std_logic_vector(1 downto 0) := "00";

    -- CLKDIVCR: MCLK and SMCLK clock divider control register
    constant CLKDIVCR_WORD            : natural := 1;
    constant CLKDIVCR_ADDR            : natural := 4;
    constant CLKDIVCR_RESET           : std_logic_vector(7 downto 0) := "00000000";
    constant CLKDIVCR_IMPL            : std_logic_vector(7 downto 0) := "00111111";
    constant SYSSMCLKDIV_MSB          : natural := 5;
    constant SYSSMCLKDIV_LSB          : natural := 3;
    constant SYSSMCLKDIV_RESET        : std_logic_vector(2 downto 0) := "000";
    constant SYSMCLKDIV_MSB           : natural := 2;
    constant SYSMCLKDIV_LSB           : natural := 0;
    constant SYSMCLKDIV_RESET         : std_logic_vector(2 downto 0) := "000";

    -- BLOCKPWR: Block power control register
    constant BLOCKPWR_WORD            : natural := 2;
    constant BLOCKPWR_ADDR            : natural := 8;
    constant BLOCKPWR_RESET           : std_logic_vector(7 downto 0) := "00000000";
    constant BLOCKPWR_IMPL            : std_logic_vector(7 downto 0) := "01111111";
    constant SYSSHB3OFF_MSB           : natural := 6;
    constant SYSSHB3OFF_LSB           : natural := 6;
    constant SYSSHB3OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSSHB2OFF_MSB           : natural := 5;
    constant SYSSHB2OFF_LSB           : natural := 5;
    constant SYSSHB2OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSSHB1OFF_MSB           : natural := 4;
    constant SYSSHB1OFF_LSB           : natural := 4;
    constant SYSSHB1OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSSHB0OFF_MSB           : natural := 3;
    constant SYSSHB0OFF_LSB           : natural := 3;
    constant SYSSHB0OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSRAM1OFF_MSB           : natural := 2;
    constant SYSRAM1OFF_LSB           : natural := 2;
    constant SYSRAM1OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSRAM0OFF_MSB           : natural := 1;
    constant SYSRAM0OFF_LSB           : natural := 1;
    constant SYSRAM0OFF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant SYSROMOFF_MSB            : natural := 0;
    constant SYSROMOFF_LSB            : natural := 0;
    constant SYSROMOFF_RESET          : std_logic_vector(0 downto 0) := "0";

    -- CRCDATA: CRC input data register
    constant CRCDATA_WORD             : natural := 3;
    constant CRCDATA_ADDR             : natural := 12;
    constant CRCDATA_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant CRCDATA_IMPL             : std_logic_vector(7 downto 0) := "11111111";
    constant SYSCRCDATA_MSB           : natural := 7;
    constant SYSCRCDATA_LSB           : natural := 0;
    constant SYSCRCDATA_RESET         : std_logic_vector(7 downto 0) := "00000000";

    -- CRCSTATE: CRC state register
    constant CRCSTATE_WORD            : natural := 4;
    constant CRCSTATE_ADDR            : natural := 16;
    constant CRCSTATE_RESET           : std_logic_vector(15 downto 0) := "0000000000000000";
    constant CRCSTATE_IMPL            : std_logic_vector(15 downto 0) := "1111111111111111";
    constant SYSCRCSTATE_MSB          : natural := 15;
    constant SYSCRCSTATE_LSB          : natural := 0;
    constant SYSCRCSTATE_RESET        : std_logic_vector(15 downto 0) := "0000000000000000";

    -- WDTPASS: Watchdog timer password register
    constant WDTPASS_WORD             : natural := 12;
    constant WDTPASS_ADDR             : natural := 48;
    constant WDTPASS_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant WDTPASS_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SYSWDTPASS_MSB           : natural := 31;
    constant SYSWDTPASS_LSB           : natural := 0;
    constant SYSWDTPASS_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- WDTCR: Watchdog timer control register
    constant WDTCR_WORD               : natural := 13;
    constant WDTCR_ADDR               : natural := 52;
    constant WDTCR_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant WDTCR_IMPL               : std_logic_vector(7 downto 0) := "10111111";
    constant SYSWDTEN_MSB             : natural := 7;
    constant SYSWDTEN_LSB             : natural := 7;
    constant SYSWDTEN_RESET           : std_logic_vector(0 downto 0) := "0";
    constant SYSWDTCDIV_MSB           : natural := 5;
    constant SYSWDTCDIV_LSB           : natural := 2;
    constant SYSWDTCDIV_RESET         : std_logic_vector(3 downto 0) := "0000";
    constant SYSWDTIE_MSB             : natural := 1;
    constant SYSWDTIE_LSB             : natural := 1;
    constant SYSWDTIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant SYSWDTHWRST_MSB          : natural := 0;
    constant SYSWDTHWRST_LSB          : natural := 0;
    constant SYSWDTHWRST_RESET        : std_logic_vector(0 downto 0) := "0";

    -- WDTSR: Watchdog timer status register
    constant WDTSR_WORD               : natural := 14;
    constant WDTSR_ADDR               : natural := 56;
    constant WDTSR_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant WDTSR_IMPL               : std_logic_vector(7 downto 0) := "00000000";
    constant SYSWDTIF_MSB             : natural := 1;
    constant SYSWDTIF_LSB             : natural := 1;
    constant SYSWDTIF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant SYSWDTRF_MSB             : natural := 0;
    constant SYSWDTRF_LSB             : natural := 0;
    constant SYSWDTRF_RESET           : std_logic_vector(0 downto 0) := "0";

    -- WDTVAL: Watchdog timer value register
    constant WDTVAL_WORD              : natural := 15;
    constant WDTVAL_ADDR              : natural := 60;
    constant WDTVAL_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant WDTVAL_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SYSWDTVAL_MSB            : natural := 23;
    constant SYSWDTVAL_LSB            : natural := 0;
    constant SYSWDTVAL_RESET          : std_logic_vector(23 downto 0) := "000000000000000000000000";

    -- DCO0BIAS: Digitally controlled oscillator 0 bias register
    constant DCO0BIAS_WORD            : natural := 16;
    constant DCO0BIAS_ADDR            : natural := 64;
    constant DCO0BIAS_RESET           : std_logic_vector(15 downto 0) := "0000100000000000";
    constant DCO0BIAS_IMPL            : std_logic_vector(15 downto 0) := "0000111111111111";
    constant SYSDCO0BIAS_MSB          : natural := 11;
    constant SYSDCO0BIAS_LSB          : natural := 0;
    constant SYSDCO0BIAS_RESET        : std_logic_vector(11 downto 0) := "100000000000";

    -- DCO1BIAS: Digitally controlled oscillator 1 bias register
    constant DCO1BIAS_WORD            : natural := 17;
    constant DCO1BIAS_ADDR            : natural := 68;
    constant DCO1BIAS_RESET           : std_logic_vector(15 downto 0) := "0000100000000000";
    constant DCO1BIAS_IMPL            : std_logic_vector(15 downto 0) := "0000111111111111";
    constant SYSDCO1BIAS_MSB          : natural := 11;
    constant SYSDCO1BIAS_LSB          : natural := 0;
    constant SYSDCO1BIAS_RESET        : std_logic_vector(11 downto 0) := "100000000000";

    -- SYSTEM.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant RegSlotSYS_CLK_CR        : natural := 0;
    constant RegSlotSYS_CLK_DIV_CR    : natural := 1;
    constant RegSlotSYS_BLOCK_PWR     : natural := 2;
    constant RegSlotSYS_CRC_DATA      : natural := 3;
    constant RegSlotSYS_CRC_STATE     : natural := 4;
    constant RegSlotSYS_WDT_PASS      : natural := 12;
    constant RegSlotSYS_WDT_CR        : natural := 13;
    constant RegSlotSYS_WDT_SR        : natural := 14;
    constant RegSlotSYS_WDT_VAL       : natural := 15;
    constant RegSlotDCO0_BIAS         : natural := 16;
    constant RegSlotDCO1_BIAS         : natural := 17;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    -- The table is SPARSE: words 5-11 carry no register here, and the
    -- all-zero _reserved_<word> row is what makes it read 0, store nothing
    -- and take no hook, which is the `when others` arm it replaces.
    constant NWORDS                   : natural := 18;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000800",   -- DCO0BIAS
        x"00000800"    -- DCO1BIAS
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"000001FF",   -- SYSCLKCR
        x"0000003F",   -- CLKDIVCR
        x"0000007F",   -- BLOCKPWR
        x"000000FF",   -- CRCDATA
        x"0000FFFF",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"000000BF",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000FFF",   -- DCO0BIAS
        x"00000FFF"    -- DCO1BIAS
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000003",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"00000000",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000000",   -- WDTSR
        x"00000000",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- SYSCLKCR
        x"00000000",   -- CLKDIVCR
        x"00000000",   -- BLOCKPWR
        x"00000000",   -- CRCDATA
        x"0000FFFF",   -- CRCSTATE
        x"00000000",   -- _reserved_5
        x"00000000",   -- _reserved_6
        x"00000000",   -- _reserved_7
        x"00000000",   -- _reserved_8
        x"00000000",   -- _reserved_9
        x"00000000",   -- _reserved_10
        x"00000000",   -- _reserved_11
        x"00000000",   -- WDTPASS
        x"00000000",   -- WDTCR
        x"00000003",   -- WDTSR
        x"00FFFFFF",   -- WDTVAL
        x"00000000",   -- DCO0BIAS
        x"00000000"    -- DCO1BIAS
    );

end package system_regs_pkg;
