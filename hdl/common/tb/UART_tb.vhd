-------------------------------------------------------------------------------
-- UART_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the UART peripheral
-- (hdl/myshkin/periph/UART.vhd).
--
-- Uses the shared support packages: tb/periph_tb_pkg.vhd (scoreboard +
-- register-bus BFM) and tb/uart_bfm_pkg.vhd (pad-level TX capture / RX drive).
--
-- Instantiates the UART entity directly and drives its peripheral memory bus +
-- RX pad while observing the TX pad, status flags and interrupt lines. A running
-- error counter (the scoreboard) prints a single PASS/FAIL banner at the end.
--
-- Bus contract recap (see periph/UART.vhd):
--   * en_mem / wen ACTIVE-LOW ; clk_mem = clk while en_mem='0'
--   * SR and RX read back a snapshot taken on the falling edge of en_mem
--   * Reading the RX slot also clears the RX status flags (OVF/FEF/PEF/RCIF)
-- Baud timing: one UART bit lasts 16*(BR+1) core-clock periods.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.MemoryMap.all;
use work.periph_tb_pkg.all;
use work.uart_bfm_pkg.all;

entity UART_tb is
end entity UART_tb;

architecture sim of UART_tb is

    -----------------------------------------------------------------------
    -- Timing
    -----------------------------------------------------------------------
    constant CLK_PERIOD : time    := 50 ns;            -- 20 MHz core clock
    constant BAUD_DIV   : integer := 1;                -- value written to UART_BR
    constant BIT_PERIOD : time    := 16 * (BAUD_DIV + 1) * CLK_PERIOD; -- 1.6 us

    -----------------------------------------------------------------------
    -- Control-register field encodings (UART_CR(5 downto 0))
    --   bit5 EN | bit4 PEN | bit3 PSEL(0=even,1=odd)
    --   bit2 CIE(rx) | bit1 TEIE | bit0 TCIE
    -----------------------------------------------------------------------
    constant CR_EN_NOPAR  : std_logic_vector(5 downto 0) := "100000"; -- enable, 8N1
    constant CR_EN_RXIE   : std_logic_vector(5 downto 0) := "100100"; -- enable + RX irq
    constant CR_EN_TXIE   : std_logic_vector(5 downto 0) := "100011"; -- enable + TE+TC irq
    constant CR_EN_EVEN   : std_logic_vector(5 downto 0) := "110000"; -- enable, even parity
    constant CR_EN_ODD    : std_logic_vector(5 downto 0) := "111000"; -- enable, odd parity

    -----------------------------------------------------------------------
    -- DUT bus / system signals
    -----------------------------------------------------------------------
    signal clk         : std_logic := '0';
    signal clk_mem     : std_logic := '0';
    signal resetn      : std_logic := '0';

    signal irq_rc      : std_logic;
    signal irq_te      : std_logic;
    signal irq_tc      : std_logic;

    -- register bus (BFM record + observed read_data)
    signal pbus        : periph_bus_t := PERIPH_BUS_IDLE;
    signal read_data   : std_logic_vector(31 downto 0);

    -- Pad interface
    signal TX_OUT      : std_logic;
    signal TX_DIR      : std_logic;
    signal TX_REN      : std_logic;
    signal RX_IN       : std_logic := '1';                       -- idle = mark
    signal RX_OUT      : std_logic;
    signal RX_DIR      : std_logic;
    signal RX_REN      : std_logic;

    shared variable sb : scoreboard;

begin

    -----------------------------------------------------------------------
    -- Clocks. clk_mem only runs while the peripheral is selected.
    -----------------------------------------------------------------------
    clk     <= not clk after CLK_PERIOD / 2;
    clk_mem <= clk when pbus.en_mem = '0' else '0';

    -----------------------------------------------------------------------
    -- DUT
    -----------------------------------------------------------------------
    dut : entity work.UART
        port map (
            clk         => clk,
            resetn      => resetn,
            irq_rc      => irq_rc,
            irq_te      => irq_te,
            irq_tc      => irq_tc,
            clk_mem     => clk_mem,
            en_mem      => pbus.en_mem,
            wen         => pbus.wen,
            addr_periph => pbus.addr_periph,
            write_data  => pbus.write_data,
            read_data   => read_data,
            TX_OUT      => TX_OUT,
            TX_DIR      => TX_DIR,
            TX_REN      => TX_REN,
            RX_IN       => RX_IN,
            RX_OUT      => RX_OUT,
            RX_DIR      => RX_DIR,
            RX_REN      => RX_REN
        );

    -----------------------------------------------------------------------
    -- Stimulus + checking
    -----------------------------------------------------------------------
    stim_proc : process

        variable rdw      : std_logic_vector(31 downto 0);
        variable cap_data : std_logic_vector(7 downto 0);
        variable cap_par  : std_logic;
        variable cap_stop : std_logic;

        -- Convenience: write a small control/baud value (zero-extended).
        procedure bus_write_small(slot : in natural; val : in std_logic_vector) is
            variable w : std_logic_vector(31 downto 0) := (others => '0');
        begin
            w(val'length - 1 downto 0) := val;
            bus_write(clk, pbus, slot, w);
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        RX_IN  <= '1';
        pbus   <= PERIPH_BUS_IDLE;
        wait for 4 * CLK_PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / idle state
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & idle state ===" severity note;

        sb.check_bit("TX pad idle high",              TX_OUT, '1');
        sb.check_bit("TX_DIR drives output",          TX_DIR, '1');
        sb.check_bit("TX_REN pull disabled",          TX_REN, '0');
        sb.check_bit("RX_DIR is input",               RX_DIR, '0');
        sb.check_bit("RX_REN pull disabled",          RX_REN, '0');
        sb.check_bit("RX_OUT unused low",             RX_OUT, '0');
        sb.check_bit("irq_rc deasserted at reset",    irq_rc, '0');
        sb.check_bit("irq_te deasserted at reset",    irq_te, '0');
        sb.check_bit("irq_tc deasserted at reset",    irq_tc, '0');

        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);
        sb.check_slv("CR resets to 0", rdw(5 downto 0), "000000");
        bus_read(clk, pbus, read_data, RegSlotUARTxBR, rdw);
        sb.check_slv("BR resets to 0", rdw(11 downto 0), x"000");
        bus_read(clk, pbus, read_data, RegSlotUARTxTX, rdw);
        sb.check_slv("TX reg resets to 0", rdw(7 downto 0), x"00");
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX reg resets to 0", rdw(7 downto 0), x"00");
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_slv("SR resets to 0", rdw(7 downto 0), x"00");

        ----------------------------------------------------------------
        -- GROUP 2: register read/write
        ----------------------------------------------------------------
        report "=== GROUP 2: register read / write ===" severity note;

        bus_write_small(RegSlotUARTxBR, std_logic_vector(to_unsigned(BAUD_DIV, 12)));
        bus_read(clk, pbus, read_data, RegSlotUARTxBR, rdw);
        sb.check_slv("BR readback", rdw(11 downto 0),
                     std_logic_vector(to_unsigned(BAUD_DIV, 12)));

        bus_write_small(RegSlotUARTxBR, x"ABC");
        bus_read(clk, pbus, read_data, RegSlotUARTxBR, rdw);
        sb.check_slv("BR readback (12-bit pattern)", rdw(11 downto 0), x"ABC");

        bus_write_small(RegSlotUARTxCR, CR_EN_RXIE);
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);
        sb.check_slv("CR readback honours 6-bit field", rdw(5 downto 0), CR_EN_RXIE);
        sb.check_slv("CR upper bits read as 0", rdw(31 downto 6), (31 downto 6 => '0'));

        -- restore a sane baud and disable for a clean start
        bus_write_small(RegSlotUARTxBR, std_logic_vector(to_unsigned(BAUD_DIV, 12)));
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 3: transmit (8N1), two distinct payloads
        ----------------------------------------------------------------
        report "=== GROUP 3: TX 8N1 ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("TX not busy before write", rdw(6), '0');

        bus_write_small(RegSlotUARTxTX, x"55");
        uart_capture_tx(BIT_PERIOD, TX_OUT, false, cap_data, cap_par, cap_stop);
        sb.check_slv("TX byte 0x55 on the wire", cap_data, x"55");
        sb.check_bit("TX stop bit high (0x55)",  cap_stop, '1');

        -- After completion the TX-empty and TX-complete flags should be set
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("TX empty flag after send",    rdw(1), '1');
        sb.check_bit("TX complete flag after send", rdw(0), '1');
        sb.check_bit("TX busy cleared after send",  rdw(6), '0');

        bus_write_small(RegSlotUARTxTX, x"A3");
        uart_capture_tx(BIT_PERIOD, TX_OUT, false, cap_data, cap_par, cap_stop);
        sb.check_slv("TX byte 0xA3 on the wire", cap_data, x"A3");
        sb.check_bit("TX stop bit high (0xA3)",  cap_stop, '1');

        ----------------------------------------------------------------
        -- GROUP 4: TX-complete / TX-empty interrupt lines + flag clear
        ----------------------------------------------------------------
        report "=== GROUP 4: TX interrupts ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_TXIE);   -- enable, TEIE+TCIE
        bus_write_small(RegSlotUARTxTX, x"0F");
        uart_capture_tx(BIT_PERIOD, TX_OUT, false, cap_data, cap_par, cap_stop);
        sb.check_slv("TX byte 0x0F (irq cfg)", cap_data, x"0F");
        sb.check_bit("irq_te asserted (UTEIF & TEIE)", irq_te, '1');
        sb.check_bit("irq_tc asserted (UTCIF & TCIE)", irq_tc, '1');

        -- Clear TX-complete flag (SR bit0) and TX-empty flag (SR bit1)
        bus_write_small(RegSlotUARTxSR, "011");        -- write 1s to clear TC+TE
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("TX complete flag cleared", rdw(0), '0');
        sb.check_bit("TX empty flag cleared",    rdw(1), '0');
        sb.check_bit("irq_tc deasserted after clear", irq_tc, '0');
        sb.check_bit("irq_te deasserted after clear", irq_te, '0');

        ----------------------------------------------------------------
        -- GROUP 5: receive (8N1)
        ----------------------------------------------------------------
        report "=== GROUP 5: RX 8N1 ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"3C", false, '0', false, true);

        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX complete flag set",   rdw(2), '1');
        sb.check_bit("no parity error (8N1)",  rdw(4), '0');
        sb.check_bit("no framing error (8N1)", rdw(5), '0');

        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX byte 0x3C received", rdw(7 downto 0), x"3C");

        -- reading RX must clear the RX status flags
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RCIF cleared by RX read", rdw(2), '0');

        -- a second, different payload
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"96", false, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX byte 0x96 received", rdw(7 downto 0), x"96");

        ----------------------------------------------------------------
        -- GROUP 6: RX-complete interrupt line
        ----------------------------------------------------------------
        report "=== GROUP 6: RX interrupt ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_RXIE);   -- enable + CIE
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"5A", false, '0', false, true);
        sb.check_bit("irq_rc asserted (RCIF & CIE)", irq_rc, '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX byte 0x5A received", rdw(7 downto 0), x"5A");
        sb.check_bit("irq_rc deasserted after RX read", irq_rc, '0');

        ----------------------------------------------------------------
        -- GROUP 7: framing error (bad stop bit)
        ----------------------------------------------------------------
        report "=== GROUP 7: framing error ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"7E", false, '0', false, false);  -- stop bit low
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("framing error flag set", rdw(5), '1');
        -- clear by reading RX
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("framing error cleared by RX read", rdw(5), '0');

        ----------------------------------------------------------------
        -- GROUP 8: parity generation (TX) and checking (RX)
        ----------------------------------------------------------------
        report "=== GROUP 8: parity ===" severity note;

        -- TX even parity: parity bit = XOR of data bits
        bus_write_small(RegSlotUARTxCR, CR_EN_EVEN);
        bus_write_small(RegSlotUARTxTX, x"C5");          -- popcount(0xC5)=4 -> even par=0
        uart_capture_tx(BIT_PERIOD, TX_OUT, true, cap_data, cap_par, cap_stop);
        sb.check_slv("TX(even) data 0xC5", cap_data, x"C5");
        sb.check_bit("TX(even) parity bit for 0xC5", cap_par, '0');
        sb.check_bit("TX(even) stop bit",  cap_stop, '1');

        bus_write_small(RegSlotUARTxTX, x"07");          -- popcount=3 -> even par=1
        uart_capture_tx(BIT_PERIOD, TX_OUT, true, cap_data, cap_par, cap_stop);
        sb.check_slv("TX(even) data 0x07", cap_data, x"07");
        sb.check_bit("TX(even) parity bit for 0x07", cap_par, '1');

        -- RX even parity, correct. Use 0x07 (odd # of ones) so the parity
        -- bit is DECISIVE.
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"07", true, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX(even) good parity -> PEF=0", rdw(4), '0');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX(even) data 0x07", rdw(7 downto 0), x"07");

        -- RX even parity, corrupted -> parity error flag. Reset the UART first
        -- (disable->enable) so this frame is judged from a clean state.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_EVEN);
        wait for 2 * CLK_PERIOD;
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"07", true, '0', true, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX(even) bad parity -> PEF=1", rdw(4), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);     -- clear
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("PEF cleared by RX read", rdw(4), '0');

        -- RX odd parity, correct -> no parity error
        bus_write_small(RegSlotUARTxCR, CR_EN_ODD);
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"3C", true, '1', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX(odd) good parity -> PEF=0", rdw(4), '0');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX(odd) data 0x3C", rdw(7 downto 0), x"3C");

        ----------------------------------------------------------------
        -- GROUP 9: RX overflow (two frames, first never read)
        --   Receiving a second byte before the first is read sets the overflow
        --   flag (SR bit3). clr_SR_RX (from reading RX) is a gated pulse that
        --   sticks until the next UART access, so a dummy non-RX access is
        --   issued to retire it before setting up the overflow. See tb/CLAUDE.md.
        ----------------------------------------------------------------
        report "=== GROUP 9: RX overflow ===" severity note;

        -- (a) Two unread RX bytes -> overflow.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);   -- clear stale RX flags
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- dummy access: retire clr_SR_RX
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"11", false, '0', false, true);   -- byte A, unread
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"22", false, '0', false, true);   -- byte B -> overflow
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("overflow flag set on unread 2nd byte", rdw(3), '1');
        sb.check_bit("RCIF still set during overflow",       rdw(2), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("overflow cleared by RX read", rdw(3), '0');

        -- (b) Regression guard: a TX completion sets UTCIF; a subsequent SINGLE
        --     (non-overrunning) RX must NOT raise OVF.
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_write_small(RegSlotUARTxTX, x"5A");          -- sets UTCIF on completion
        uart_capture_tx(BIT_PERIOD, TX_OUT, false, cap_data, cap_par, cap_stop);
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX from prior RX read
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"33", false, '0', false, true);   -- single byte
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("no false overflow after TX + single RX", rdw(3), '0');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX data 0x33 readable", rdw(7 downto 0), x"33");

        ----------------------------------------------------------------
        -- GROUP 10: disable clears activity / outputs return to idle
        ----------------------------------------------------------------
        report "=== GROUP 10: disable behaviour ===" severity note;

        bus_write_small(RegSlotUARTxCR, "000000");       -- UART disabled
        wait for 4 * CLK_PERIOD;
        sb.check_bit("TX idle high when disabled", TX_OUT, '1');
        sb.check_bit("irq_rc low when disabled",   irq_rc, '0');
        sb.check_bit("irq_te low when disabled",   irq_te, '0');
        sb.check_bit("irq_tc low when disabled",   irq_tc, '0');

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("UART TB");
        stop;
        wait;
    end process;

end architecture sim;
