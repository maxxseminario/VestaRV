-- VestaRV: UART register package
-- Full-duplex Universal Asynchronous Receiver/Transmitter with hardware parity support
-- Generated from hdl/common/regs/rdl/uart.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package uart_regs_pkg is

    -- UARTxCR: UART control register
    constant UARTxCR_WORD             : natural := 0;
    constant UARTxCR_ADDR             : natural := 0;
    constant UARTxCR_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant UARTxCR_IMPL             : std_logic_vector(7 downto 0) := "00111111";
    constant UEN_MSB                  : natural := 5;
    constant UEN_LSB                  : natural := 5;
    constant UEN_RESET                : std_logic_vector(0 downto 0) := "0";
    constant UPEN_MSB                 : natural := 4;
    constant UPEN_LSB                 : natural := 4;
    constant UPEN_RESET               : std_logic_vector(0 downto 0) := "0";
    constant PSEL_MSB                 : natural := 3;
    constant PSEL_LSB                 : natural := 3;
    constant PSEL_RESET               : std_logic_vector(0 downto 0) := "0";
    constant CIE_MSB                  : natural := 2;
    constant CIE_LSB                  : natural := 2;
    constant CIE_RESET                : std_logic_vector(0 downto 0) := "0";
    constant TEIE_MSB                 : natural := 1;
    constant TEIE_LSB                 : natural := 1;
    constant TEIE_RESET               : std_logic_vector(0 downto 0) := "0";
    constant TCIE_MSB                 : natural := 0;
    constant TCIE_LSB                 : natural := 0;
    constant TCIE_RESET               : std_logic_vector(0 downto 0) := "0";

    -- UARTxSR: UART status register
    constant UARTxSR_WORD             : natural := 1;
    constant UARTxSR_ADDR             : natural := 4;
    constant UARTxSR_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant UARTxSR_IMPL             : std_logic_vector(7 downto 0) := "00000000";
    constant RXBF_MSB                 : natural := 7;
    constant RXBF_LSB                 : natural := 7;
    constant RXBF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant TXBF_MSB                 : natural := 6;
    constant TXBF_LSB                 : natural := 6;
    constant TXBF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant FEF_MSB                  : natural := 5;
    constant FEF_LSB                  : natural := 5;
    constant FEF_RESET                : std_logic_vector(0 downto 0) := "0";
    constant PEF_MSB                  : natural := 4;
    constant PEF_LSB                  : natural := 4;
    constant PEF_RESET                : std_logic_vector(0 downto 0) := "0";
    constant OVF_MSB                  : natural := 3;
    constant OVF_LSB                  : natural := 3;
    constant OVF_RESET                : std_logic_vector(0 downto 0) := "0";
    constant RCIF_MSB                 : natural := 2;
    constant RCIF_LSB                 : natural := 2;
    constant RCIF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant TEIF_MSB                 : natural := 1;
    constant TEIF_LSB                 : natural := 1;
    constant TEIF_RESET               : std_logic_vector(0 downto 0) := "0";
    constant TCIF_MSB                 : natural := 0;
    constant TCIF_LSB                 : natural := 0;
    constant TCIF_RESET               : std_logic_vector(0 downto 0) := "0";

    -- UARTxBR: UART baud rate register
    constant UARTxBR_WORD             : natural := 2;
    constant UARTxBR_ADDR             : natural := 8;
    constant UARTxBR_RESET            : std_logic_vector(15 downto 0) := "0000000000000000";
    constant UARTxBR_IMPL             : std_logic_vector(15 downto 0) := "0000111111111111";
    constant BR_MSB                   : natural := 11;
    constant BR_LSB                   : natural := 0;
    constant BR_RESET                 : std_logic_vector(11 downto 0) := "000000000000";

    -- UARTxRX: UART receive buffer register
    constant UARTxRX_WORD             : natural := 3;
    constant UARTxRX_ADDR             : natural := 12;
    constant UARTxRX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant UARTxRX_IMPL             : std_logic_vector(7 downto 0) := "00000000";
    constant RX_MSB                   : natural := 7;
    constant RX_LSB                   : natural := 0;
    constant RX_RESET                 : std_logic_vector(7 downto 0) := "00000000";

    -- UARTxTX: UART transmit buffer register
    constant UARTxTX_WORD             : natural := 4;
    constant UARTxTX_ADDR             : natural := 16;
    constant UARTxTX_RESET            : std_logic_vector(7 downto 0) := "00000000";
    constant UARTxTX_IMPL             : std_logic_vector(7 downto 0) := "11111111";
    constant TX_MSB                   : natural := 7;
    constant TX_LSB                   : natural := 0;
    constant TX_RESET                 : std_logic_vector(7 downto 0) := "00000000";

    -- UART.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant RegSlotUARTxCR           : natural := 0;
    constant RegSlotUARTxSR           : natural := 1;
    constant RegSlotUARTxBR           : natural := 2;
    constant RegSlotUARTxRX           : natural := 3;
    constant RegSlotUARTxTX           : natural := 4;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR
    -- and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 5;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"0000003F",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000FFF",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"000000FF"    -- UARTxTX
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000007",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"00000000",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"00000000",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- UARTxCR
        x"000000FF",   -- UARTxSR
        x"00000000",   -- UARTxBR
        x"000000FF",   -- UARTxRX
        x"00000000"    -- UARTxTX
    );

end package uart_regs_pkg;
