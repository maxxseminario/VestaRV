-------------------------------------------------------------------------------
-- UART_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the UART peripheral: drives the peripheral memory bus and the RX pad while observing the TX pad, status flags, interrupt lines and the evt_rx event tap.
-- Support packages: periph_tb_pkg (scoreboard and register-bus BFM) and uart_bfm_pkg (pad-level TX capture and RX drive); the scoreboard prints a single PASS/FAIL banner at the end.
-- Bus contract: en_mem and wen are ACTIVE-LOW, SR and RX read back a snapshot taken on the falling edge of en_mem, and reading the RX slot also clears the RX status flags (OVF/FEF/PEF/RCIF).
-- Baud timing: one UART bit lasts 16*(BR+1) core-clock periods.
-- clk_mem must FREE-RUN here: all flag/status logic lives in the clk_mem domain and synchronizes the serial-side events in through a toggle plus 3-stage synchronizer, which a gated clk_mem starves (TX corruption, RCIF/irq_rc never seen, framing/parity/overflow flags never observed).
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

    -- ---- event tap (GROUP EV) ---------------------------------------------
    signal evt_rx : std_logic;

    -- ---- evt_rx pulse monitor (checker independence, GROUP EV) ------------
    -- Counts pulse STARTS and total HIGH samples at clk_mem rising edges since the last evt_mon_clear, reading only the exported evt_rx port, so N one-clk_mem-wide pulses satisfy starts=N and highs=N.
    -- Also tracks whether irq_rc was EVER seen high in the window, for the masked-IRQ discipline check.
    signal evt_rx_starts, evt_rx_highs : natural := 0;
    signal evt_rx_prev   : std_logic := '0';
    signal evt_mon_clear : std_logic := '0';
    signal irq_rc_seen_high : boolean := false;

    shared variable sb : scoreboard;

begin

    -----------------------------------------------------------------------
    -- Clocks: clk_mem free-runs, which the flag CDC needs to synchronize the serial-side events in.
    -----------------------------------------------------------------------
    clk     <= not clk after CLK_PERIOD / 2;
    clk_mem <= clk;

    -----------------------------------------------------------------------
    -- evt_rx pulse monitor.
    -----------------------------------------------------------------------
    evt_mon_proc : process(clk_mem)
        variable r_lvl : std_logic;
    begin
        if rising_edge(clk_mem) then
            r_lvl := to_X01(evt_rx);
            if evt_mon_clear = '1' then
                -- Start a fresh window: zero the tallies, re-baseline the level and the irq_rc sighting.
                evt_rx_starts    <= 0;
                evt_rx_highs     <= 0;
                evt_rx_prev      <= r_lvl;
                irq_rc_seen_high <= false;
            else
                -- Accumulate: every high sample counts, and a low-to-high step counts as a pulse start.
                if r_lvl = '1' then
                    evt_rx_highs <= evt_rx_highs + 1;
                    if evt_rx_prev /= '1' then
                        evt_rx_starts <= evt_rx_starts + 1;
                    end if;
                end if;
                evt_rx_prev <= r_lvl;
                if to_X01(irq_rc) = '1' then
                    irq_rc_seen_high <= true;
                end if;
            end if;
        end if;
    end process;

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
            RX_REN      => RX_REN,
            evt_rx      => evt_rx
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

        -- ---- GROUP EV helper -----------------------------------------------
        -- Clear the evt_rx pulse monitor's accumulators; call only outside a timing-critical window.
        procedure evt_mon_reset is
        begin
            wait until clk_mem = '0';
            evt_mon_clear <= '1';
            wait until clk_mem = '1';
            wait until clk_mem = '0';
            evt_mon_clear <= '0';
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
        -- clr_SR_RX is a registered clk_mem pulse consumed on the FOLLOWING clk_mem edge, so USR_RCIF and irq_rc clear one clk_mem cycle after the RX read that triggers them.
        -- The settle wait lets that clear land before the check.
        wait for 2 * CLK_PERIOD;
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

        -- TX even parity: the parity bit is the XOR of the data bits.
        bus_write_small(RegSlotUARTxCR, CR_EN_EVEN);
        bus_write_small(RegSlotUARTxTX, x"C5");          -- popcount(0xC5)=4, so even parity bit = 0
        uart_capture_tx(BIT_PERIOD, TX_OUT, true, cap_data, cap_par, cap_stop);
        sb.check_slv("TX(even) data 0xC5", cap_data, x"C5");
        sb.check_bit("TX(even) parity bit for 0xC5", cap_par, '0');
        sb.check_bit("TX(even) stop bit",  cap_stop, '1');

        bus_write_small(RegSlotUARTxTX, x"07");          -- popcount=3, so even parity bit = 1
        uart_capture_tx(BIT_PERIOD, TX_OUT, true, cap_data, cap_par, cap_stop);
        sb.check_slv("TX(even) data 0x07", cap_data, x"07");
        sb.check_bit("TX(even) parity bit for 0x07", cap_par, '1');

        -- RX even parity, correct: use 0x07 (an odd number of ones) so the parity bit is DECISIVE.
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"07", true, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX(even) good parity -> PEF=0", rdw(4), '0');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX(even) data 0x07", rdw(7 downto 0), x"07");

        -- RX even parity, corrupted: expect the parity error flag.
        -- Reset the UART first (disable, then enable) so this frame is judged from a clean state.
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

        -- RX odd parity, correct: expect no parity error.
        bus_write_small(RegSlotUARTxCR, CR_EN_ODD);
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"3C", true, '1', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("RX(odd) good parity -> PEF=0", rdw(4), '0');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("RX(odd) data 0x3C", rdw(7 downto 0), x"3C");

        ----------------------------------------------------------------
        -- GROUP 9: RX overflow, two frames with the first never read: the second byte sets the overflow flag (SR bit3).
        -- clr_SR_RX from reading RX is a gated pulse that sticks until the next UART access, so a dummy non-RX access retires it before the overflow is set up.
        ----------------------------------------------------------------
        report "=== GROUP 9: RX overflow ===" severity note;

        -- (a) Two unread RX bytes must raise overflow.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);   -- clear stale RX flags
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- dummy access: retire clr_SR_RX
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"11", false, '0', false, true);   -- byte A, unread
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"22", false, '0', false, true);   -- byte B, causes overflow
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("overflow flag set on unread 2nd byte", rdw(3), '1');
        sb.check_bit("RCIF still set during overflow",       rdw(2), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("overflow cleared by RX read", rdw(3), '0');

        -- (b) Regression guard: a TX completion sets UTCIF, and a subsequent SINGLE (non-overrunning) RX must NOT raise OVF.
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
        -- GROUP EV: evt_rx is the RCIF SET condition itself, PRE-MASK: one clk_mem pulse per set edge, on every received frame regardless of CIE, and again on an overrun.
        -- Checked by the background pulse monitor over evt_mon_reset-bounded windows, sampling only the exported evt_rx/irq_rc ports.
        ----------------------------------------------------------------
        report "=== GROUP EV: EVFAB tap (evt_rx) ===" severity note;

        -- EV-a: three clean frames, each read and its clr_SR_RX pulse retired by a dummy CR access before the next frame arrives, so no overrun.
        -- Expect exactly 3 evt_rx pulse starts, each one clk_mem wide, with RCIF and RX readback unchanged.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);   -- clear stale RX flags
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- dummy access: retire clr_SR_RX

        evt_mon_reset;

        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"11", false, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-a1: RCIF set after frame 1 (unchanged by the tap)", rdw(2), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("EV-a1: RX byte 0x11 received", rdw(7 downto 0), x"11");
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX

        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"22", false, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-a2: RCIF set after frame 2 (unchanged by the tap)", rdw(2), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("EV-a2: RX byte 0x22 received", rdw(7 downto 0), x"22");
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX

        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"33", false, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-a3: RCIF set after frame 3 (unchanged by the tap)", rdw(2), '1');
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("EV-a3: RX byte 0x33 received", rdw(7 downto 0), x"33");

        sb.check_true("EV-a4: evt_rx pulses exactly 3 times for 3 received frames",
                      evt_rx_starts = 3);
        sb.check_true("EV-a5: every evt_rx pulse is exactly one clk_mem wide (highs = starts)",
                      evt_rx_highs = evt_rx_starts);

        -- EV-b: the discipline check, with the RX interrupt masked (CR_EN_NOPAR is EN=1, CIE=0).
        -- evt_rx must STILL pulse because the tap sits ahead of the CIE gate that drives irq_rc, and irq_rc must never be seen high across the whole frame.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);          -- EN=1, CIE=0 (masked)
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);   -- clear stale RX flags
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX

        evt_mon_reset;
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"44", false, '0', false, true);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-b1: RCIF still sets with CIE=0 (RCIF is IRQ-enable-independent)",
                     rdw(2), '1');
        sb.check_true("EV-b2: evt_rx pulses exactly once despite CIE=0 (pre-mask tap)",
                      evt_rx_starts = 1 and evt_rx_highs = 1);
        sb.check_true("EV-b3: irq_rc never asserted while CIE=0 (masked, unlike evt_rx)",
                      not irq_rc_seen_high);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        sb.check_slv("EV-b4: RX byte 0x44 received", rdw(7 downto 0), x"44");
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX

        -- EV-c: overrun, with the first frame left UNREAD so RCIF stays set.
        -- The RCIF set is unconditional (it raises USR_OVF when USR_RCIF is already 1, then sets USR_RCIF anyway), so evt_rx must pulse a SECOND time and OVF must set.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);   -- clear stale RX flags
        bus_read(clk, pbus, read_data, RegSlotUARTxCR, rdw);   -- retire clr_SR_RX

        evt_mon_reset;
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"55", false, '0', false, true);   -- byte A, unread
        uart_drive_rx(BIT_PERIOD, clk, RX_IN, x"66", false, '0', false, true);   -- byte B, causes the overrun
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-c1: overflow flag set on unread 2nd byte (unchanged by the tap)",
                     rdw(3), '1');
        sb.check_bit("EV-c2: RCIF still set during overflow (unchanged by the tap)",
                     rdw(2), '1');
        sb.check_true("EV-c3: evt_rx pulses TWICE (fires again on the overrun set, even "
                     & "though RCIF was already 1)", evt_rx_starts = 2);
        sb.check_true("EV-c4: both evt_rx pulses are exactly one clk_mem wide",
                      evt_rx_highs = 2);
        bus_read(clk, pbus, read_data, RegSlotUARTxRX, rdw);
        bus_read(clk, pbus, read_data, RegSlotUARTxSR, rdw);
        sb.check_bit("EV-c5: overflow cleared by RX read (unchanged by the tap)", rdw(3), '0');

        -- EV-d: a quiet window with no RX traffic at all, where evt_rx must never pulse.
        evt_mon_reset;
        wait for 40 * CLK_PERIOD;   -- bounded quiet window, no stimulus
        sb.check_true("EV-d1: evt_rx never pulses during a quiet window (no RX traffic)",
                      evt_rx_starts = 0 and evt_rx_highs = 0);

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        sb.report_summary("UART TB");
        stop;
        wait;
    end process;

end architecture sim;
