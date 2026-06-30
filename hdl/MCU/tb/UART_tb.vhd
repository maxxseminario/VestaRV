-------------------------------------------------------------------------------
-- UART_tb.vhd
-------------------------------------------------------------------------------
-- Standalone, self-checking testbench for the UART peripheral
-- (hdl/MCU/periph/UART.vhd).
--
-- Unlike the assembly UART.S test (which drives the UART through the core's
-- load/store path), this bench instantiates the UART entity directly and drives
-- its peripheral memory bus + RX pad while observing the TX pad, status flags
-- and interrupt lines. All checks are VHDL assertions; a running error counter
-- prints a single PASS/FAIL banner at the end so the sim runs to completion
-- instead of stopping on the first failure.
--
-- Bus contract recap (see periph/UART.vhd):
--   * en_mem is ACTIVE-LOW   ('0' => peripheral selected)
--   * wen    is ACTIVE-LOW   ('0' => that byte lane is written)
--   * clk_mem = clk while en_mem='0' ; writes/reads register on rising_edge
--   * SR and RX read back a snapshot taken on the falling edge of en_mem
--   * Reading the RX slot also clears the RX status flags (OVF/FEF/PEF/RCIF)
--
-- Baud timing: one UART bit lasts 16*(BR+1) core-clock periods.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;            -- env.stop / env.finish (clean simulation halt)
use work.constants.all;
use work.MemoryMap.all;

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

    signal en_mem      : std_logic := '1';                       -- inactive high
    signal wen         : std_logic_vector(3 downto 0) := (others => '1');
    signal addr_periph : std_logic_vector(7 downto 2) := (others => '0');
    signal write_data  : word := (others => '0');
    signal read_data   : word;

    -- Pad interface
    signal TX_OUT      : std_logic;
    signal TX_DIR      : std_logic;
    signal TX_REN      : std_logic;
    signal RX_IN       : std_logic := '1';                       -- idle = mark
    signal RX_OUT      : std_logic;
    signal RX_DIR      : std_logic;
    signal RX_REN      : std_logic;

    -----------------------------------------------------------------------
    -- Small helper: human-readable value for failure messages
    -----------------------------------------------------------------------
    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then
            return "X";
        else
            return integer'image(to_integer(unsigned(v)));
        end if;
    end function;

begin

    -----------------------------------------------------------------------
    -- Clocks. clk_mem only runs while the peripheral is selected, exactly
    -- as the SoC drives it.
    -----------------------------------------------------------------------
    clk     <= not clk after CLK_PERIOD / 2;
    clk_mem <= clk when en_mem = '0' else '0';

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
            en_mem      => en_mem,
            wen         => wen,
            addr_periph => addr_periph,
            write_data  => write_data,
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

        variable error_count : natural := 0;
        variable rdw         : word;
        variable cap_data    : std_logic_vector(7 downto 0);
        variable cap_par     : std_logic;
        variable cap_stop    : std_logic;

        --------------------------------------------------------------
        -- Assertion helpers (update the enclosing error_count)
        --------------------------------------------------------------
        procedure check_slv(tag : in string;
                            got : in std_logic_vector;
                            exp : in std_logic_vector) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                -- severity warning (not error) so the whole suite still runs;
                -- the final banner reports the overall verdict.
                assert false
                    report "FAIL: " & tag &
                           " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_bit(tag : in string;
                            got : in std_logic;
                            exp : in std_logic) is
        begin
            if got = exp then
                report "PASS: " & tag severity note;
            else
                error_count := error_count + 1;
                assert false
                    report "FAIL: " & tag &
                           " (expected " & std_logic'image(exp) &
                           ", got " & std_logic'image(got) & ")"
                    severity warning;
            end if;
        end procedure;

        --------------------------------------------------------------
        -- Peripheral-bus write (all byte lanes asserted)
        --------------------------------------------------------------
        procedure bus_write(slot : in natural;
                            data : in std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            write_data  <= data;
            wen         <= (others => '0');     -- active low: write every lane
            en_mem      <= '0';                 -- select peripheral
            wait until rising_edge(clk);        -- clk_mem rising edge captures write
            wait until falling_edge(clk);
            en_mem      <= '1';
            wen         <= (others => '1');
        end procedure;

        -- Convenience: write a small control/baud value
        procedure bus_write_small(slot : in natural;
                                  val  : in std_logic_vector) is
            variable w : word := (others => '0');
        begin
            w(val'length - 1 downto 0) := val;
            bus_write(slot, w);
        end procedure;

        --------------------------------------------------------------
        -- Peripheral-bus read. Asserting en_mem ('1'->'0') snapshots the
        -- SR/RX latches; the rising clk_mem edge registers read_data.
        --------------------------------------------------------------
        procedure bus_read(slot : in natural;
                           data : out std_logic_vector(31 downto 0)) is
        begin
            wait until falling_edge(clk);
            addr_periph <= std_logic_vector(to_unsigned(slot, 6));
            en_mem      <= '0';
            wait until rising_edge(clk);        -- read_data registers here
            wait until falling_edge(clk);       -- let it settle, then sample
            data := read_data;
            en_mem      <= '1';
        end procedure;

        --------------------------------------------------------------
        -- Capture one frame off the TX pad. Self-syncs on the start bit,
        -- samples each bit at its centre. Works for 8N1 and 8-data+parity.
        --------------------------------------------------------------
        procedure uart_capture_tx(parity_en : in  boolean;
                                  data_o    : out std_logic_vector(7 downto 0);
                                  parity_o  : out std_logic;
                                  stop_o    : out std_logic) is
            variable d : std_logic_vector(7 downto 0);
        begin
            wait until TX_OUT = '0';                    -- start bit (mark->space)
            wait for BIT_PERIOD + BIT_PERIOD / 2;       -- centre of data bit 0
            for i in 0 to 7 loop                        -- LSB first
                d(i) := TX_OUT;
                wait for BIT_PERIOD;
            end loop;
            if parity_en then
                parity_o := TX_OUT;
                wait for BIT_PERIOD;
            else
                parity_o := '0';
            end if;
            stop_o := TX_OUT;
            data_o := d;
            -- The TX FSM raises the TX-complete flag (and drops TX-busy) about
            -- one bit period after the stop bit begins. Wait past that so a
            -- subsequent SR read sees the settled completion/interrupt state.
            wait for 2 * BIT_PERIOD;
        end procedure;

        --------------------------------------------------------------
        -- Drive one frame onto the RX pad. Parity bit is computed to match
        -- the receiver's convention (init = psel, XOR all data bits);
        -- corrupt_parity / good_stop inject error conditions.
        --------------------------------------------------------------
        procedure uart_drive_rx(data           : in std_logic_vector(7 downto 0);
                                parity_en      : in boolean;
                                psel           : in std_logic;
                                corrupt_parity : in boolean;
                                good_stop      : in boolean) is
            variable p : std_logic;
        begin
            p := psel;
            for i in 0 to 7 loop
                p := p xor data(i);
            end loop;
            if corrupt_parity then
                p := not p;
            end if;

            wait until falling_edge(clk);
            RX_IN <= '0';                       -- start bit
            wait for BIT_PERIOD;
            for i in 0 to 7 loop                -- data, LSB first
                RX_IN <= data(i);
                wait for BIT_PERIOD;
            end loop;
            if parity_en then
                RX_IN <= p;
                wait for BIT_PERIOD;
            end if;
            if good_stop then
                RX_IN <= '1';
            else
                RX_IN <= '0';                   -- framing error
            end if;
            wait for BIT_PERIOD;
            RX_IN <= '1';                       -- back to idle
            wait for 2 * BIT_PERIOD;            -- guard / let RCIF settle
        end procedure;

    begin
        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        resetn <= '0';
        RX_IN  <= '1';
        en_mem <= '1';
        wen    <= (others => '1');
        wait for 4 * CLK_PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 4 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 1: reset / idle state
        ----------------------------------------------------------------
        report "=== GROUP 1: reset & idle state ===" severity note;

        check_bit("TX pad idle high",              TX_OUT, '1');
        check_bit("TX_DIR drives output",          TX_DIR, '1');
        check_bit("TX_REN pull disabled",          TX_REN, '0');
        check_bit("RX_DIR is input",               RX_DIR, '0');
        check_bit("RX_REN pull disabled",          RX_REN, '0');
        check_bit("RX_OUT unused low",             RX_OUT, '0');
        check_bit("irq_rc deasserted at reset",    irq_rc, '0');
        check_bit("irq_te deasserted at reset",    irq_te, '0');
        check_bit("irq_tc deasserted at reset",    irq_tc, '0');

        bus_read(RegSlotUARTxCR, rdw);
        check_slv("CR resets to 0", rdw(5 downto 0), "000000");
        bus_read(RegSlotUARTxBR, rdw);
        check_slv("BR resets to 0", rdw(11 downto 0), x"000");
        bus_read(RegSlotUARTxTX, rdw);
        check_slv("TX reg resets to 0", rdw(7 downto 0), x"00");
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX reg resets to 0", rdw(7 downto 0), x"00");
        bus_read(RegSlotUARTxSR, rdw);
        check_slv("SR resets to 0", rdw(7 downto 0), x"00");

        ----------------------------------------------------------------
        -- GROUP 2: register read/write
        ----------------------------------------------------------------
        report "=== GROUP 2: register read / write ===" severity note;

        bus_write_small(RegSlotUARTxBR, std_logic_vector(to_unsigned(BAUD_DIV, 12)));
        bus_read(RegSlotUARTxBR, rdw);
        check_slv("BR readback", rdw(11 downto 0),
                  std_logic_vector(to_unsigned(BAUD_DIV, 12)));

        bus_write_small(RegSlotUARTxBR, x"ABC");
        bus_read(RegSlotUARTxBR, rdw);
        check_slv("BR readback (12-bit pattern)", rdw(11 downto 0), x"ABC");

        bus_write_small(RegSlotUARTxCR, CR_EN_RXIE);
        bus_read(RegSlotUARTxCR, rdw);
        check_slv("CR readback honours 6-bit field", rdw(5 downto 0), CR_EN_RXIE);
        check_slv("CR upper bits read as 0", rdw(31 downto 6), (31 downto 6 => '0'));

        -- restore a sane baud and disable for a clean start
        bus_write_small(RegSlotUARTxBR, std_logic_vector(to_unsigned(BAUD_DIV, 12)));
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;

        ----------------------------------------------------------------
        -- GROUP 3: transmit (8N1), two distinct payloads
        ----------------------------------------------------------------
        report "=== GROUP 3: TX 8N1 ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("TX not busy before write", rdw(6), '0');

        bus_write_small(RegSlotUARTxTX, x"55");
        uart_capture_tx(false, cap_data, cap_par, cap_stop);
        check_slv("TX byte 0x55 on the wire", cap_data, x"55");
        check_bit("TX stop bit high (0x55)",  cap_stop, '1');

        -- After completion the TX-empty and TX-complete flags should be set
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("TX empty flag after send",    rdw(1), '1');
        check_bit("TX complete flag after send", rdw(0), '1');
        check_bit("TX busy cleared after send",  rdw(6), '0');

        bus_write_small(RegSlotUARTxTX, x"A3");
        uart_capture_tx(false, cap_data, cap_par, cap_stop);
        check_slv("TX byte 0xA3 on the wire", cap_data, x"A3");
        check_bit("TX stop bit high (0xA3)",  cap_stop, '1');

        ----------------------------------------------------------------
        -- GROUP 4: TX-complete / TX-empty interrupt lines + flag clear
        ----------------------------------------------------------------
        report "=== GROUP 4: TX interrupts ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_TXIE);   -- enable, TEIE+TCIE
        bus_write_small(RegSlotUARTxTX, x"0F");
        uart_capture_tx(false, cap_data, cap_par, cap_stop);
        check_slv("TX byte 0x0F (irq cfg)", cap_data, x"0F");
        check_bit("irq_te asserted (UTEIF & TEIE)", irq_te, '1');
        check_bit("irq_tc asserted (UTCIF & TCIE)", irq_tc, '1');

        -- Clear TX-complete flag (SR bit0) and TX-empty flag (SR bit1)
        bus_write_small(RegSlotUARTxSR, "011");        -- write 1s to clear TC+TE
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("TX complete flag cleared", rdw(0), '0');
        check_bit("TX empty flag cleared",    rdw(1), '0');
        check_bit("irq_tc deasserted after clear", irq_tc, '0');
        check_bit("irq_te deasserted after clear", irq_te, '0');

        ----------------------------------------------------------------
        -- GROUP 5: receive (8N1)
        ----------------------------------------------------------------
        report "=== GROUP 5: RX 8N1 ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        uart_drive_rx(x"3C", false, '0', false, true);

        bus_read(RegSlotUARTxSR, rdw);
        check_bit("RX complete flag set",   rdw(2), '1');
        check_bit("no parity error (8N1)",  rdw(4), '0');
        check_bit("no framing error (8N1)", rdw(5), '0');

        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX byte 0x3C received", rdw(7 downto 0), x"3C");

        -- reading RX must clear the RX status flags
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("RCIF cleared by RX read", rdw(2), '0');

        -- a second, different payload
        uart_drive_rx(x"96", false, '0', false, true);
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX byte 0x96 received", rdw(7 downto 0), x"96");

        ----------------------------------------------------------------
        -- GROUP 6: RX-complete interrupt line
        ----------------------------------------------------------------
        report "=== GROUP 6: RX interrupt ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_RXIE);   -- enable + CIE
        uart_drive_rx(x"5A", false, '0', false, true);
        check_bit("irq_rc asserted (RCIF & CIE)", irq_rc, '1');
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX byte 0x5A received", rdw(7 downto 0), x"5A");
        check_bit("irq_rc deasserted after RX read", irq_rc, '0');

        ----------------------------------------------------------------
        -- GROUP 7: framing error (bad stop bit)
        ----------------------------------------------------------------
        report "=== GROUP 7: framing error ===" severity note;

        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        uart_drive_rx(x"7E", false, '0', false, false);  -- stop bit driven low
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("framing error flag set", rdw(5), '1');
        -- clear by reading RX
        bus_read(RegSlotUARTxRX, rdw);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("framing error cleared by RX read", rdw(5), '0');

        ----------------------------------------------------------------
        -- GROUP 8: parity generation (TX) and checking (RX)
        ----------------------------------------------------------------
        report "=== GROUP 8: parity ===" severity note;

        -- TX even parity: parity bit = XOR of data bits
        bus_write_small(RegSlotUARTxCR, CR_EN_EVEN);
        bus_write_small(RegSlotUARTxTX, x"C5");          -- popcount(0xC5)=4 -> even par=0
        uart_capture_tx(true, cap_data, cap_par, cap_stop);
        check_slv("TX(even) data 0xC5", cap_data, x"C5");
        check_bit("TX(even) parity bit for 0xC5", cap_par, '0');
        check_bit("TX(even) stop bit",  cap_stop, '1');

        bus_write_small(RegSlotUARTxTX, x"07");          -- popcount=3 -> even par=1
        uart_capture_tx(true, cap_data, cap_par, cap_stop);
        check_slv("TX(even) data 0x07", cap_data, x"07");
        check_bit("TX(even) parity bit for 0x07", cap_par, '1');

        -- RX even parity, correct. Use 0x07 (odd # of ones) so the parity
        -- bit is DECISIVE: a receiver that ignores the received parity bit
        -- would mis-flag this good frame.
        uart_drive_rx(x"07", true, '0', false, true);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("RX(even) good parity -> PEF=0", rdw(4), '0');
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX(even) data 0x07", rdw(7 downto 0), x"07");

        -- RX even parity, corrupted -> parity error flag.
        -- Reset the UART first (disable->enable) so this frame is judged from a
        -- clean state, isolated from earlier TX/flag activity.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_EVEN);
        wait for 2 * CLK_PERIOD;
        uart_drive_rx(x"07", true, '0', true, true);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("RX(even) bad parity -> PEF=1", rdw(4), '1');
        bus_read(RegSlotUARTxRX, rdw);     -- clear
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("PEF cleared by RX read", rdw(4), '0');

        -- RX odd parity, correct -> no parity error
        bus_write_small(RegSlotUARTxCR, CR_EN_ODD);
        uart_drive_rx(x"3C", true, '1', false, true);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("RX(odd) good parity -> PEF=0", rdw(4), '0');
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX(odd) data 0x3C", rdw(7 downto 0), x"3C");

        ----------------------------------------------------------------
        -- GROUP 9: RX overflow (two frames, first never read)
        --
        --   SPEC: receiving a second byte before the first is read sets the
        --   overflow flag (SR bit3 = USR_OVF). UART.vhd keys this off
        --   USR_RCIF: a still-pending RX-complete flag at the next RX
        --   completion means the earlier byte was overrun.
        --
        --   SEQUENCING NOTE: clr_SR_RX (asserted by reading the RX slot) is a
        --   pulse that only self-clears on the next clk_mem edge -- and
        --   clk_mem is gated off between bus accesses (adddec.vhd clock-gates
        --   clk_periph by mem_en_periph). So immediately after reading RX,
        --   clr_SR_RX stays high and holds RCIF cleared until the UART is
        --   touched again. To set up a real overflow we therefore (1) clear
        --   stale flags, (2) issue one dummy non-RX UART access to retire the
        --   gated clr_SR_RX pulse, then (3) drive two frames without reading
        --   RX in between.
        ----------------------------------------------------------------
        report "=== GROUP 9: RX overflow ===" severity note;

        -- (a) Two unread RX bytes -> overflow.
        bus_write_small(RegSlotUARTxCR, "000000");
        wait for 2 * CLK_PERIOD;
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_read(RegSlotUARTxRX, rdw);                   -- clear stale RX flags
        bus_read(RegSlotUARTxCR, rdw);                   -- dummy access: retire clr_SR_RX
        uart_drive_rx(x"11", false, '0', false, true);   -- byte A, left unread
        uart_drive_rx(x"22", false, '0', false, true);   -- byte B -> overflow
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("overflow flag set on unread 2nd byte", rdw(3), '1');
        check_bit("RCIF still set during overflow",       rdw(2), '1');
        bus_read(RegSlotUARTxRX, rdw);
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("overflow cleared by RX read", rdw(3), '0');

        -- (b) Regression guard for the old bug: a TX completion sets UTCIF;
        --     a subsequent SINGLE (non-overrunning) RX must NOT raise OVF.
        --     (The pre-fix RTL keyed overflow off UTCIF and failed here.)
        bus_write_small(RegSlotUARTxCR, CR_EN_NOPAR);
        bus_write_small(RegSlotUARTxTX, x"5A");          -- sets UTCIF on completion
        uart_capture_tx(false, cap_data, cap_par, cap_stop);
        bus_read(RegSlotUARTxCR, rdw);                   -- retire clr_SR_RX from any prior RX read
        uart_drive_rx(x"33", false, '0', false, true);   -- single, non-overflowing byte
        bus_read(RegSlotUARTxSR, rdw);
        check_bit("no false overflow after TX + single RX", rdw(3), '0');
        bus_read(RegSlotUARTxRX, rdw);
        check_slv("RX data 0x33 readable", rdw(7 downto 0), x"33");

        ----------------------------------------------------------------
        -- GROUP 10: disable clears activity / outputs return to idle
        ----------------------------------------------------------------
        report "=== GROUP 10: disable behaviour ===" severity note;

        bus_write_small(RegSlotUARTxCR, "000000");       -- UART disabled
        wait for 4 * CLK_PERIOD;
        check_bit("TX idle high when disabled", TX_OUT, '1');
        check_bit("irq_rc low when disabled",   irq_rc, '0');
        check_bit("irq_te low when disabled",   irq_te, '0');
        check_bit("irq_tc low when disabled",   irq_tc, '0');

        ----------------------------------------------------------------
        -- Final verdict
        ----------------------------------------------------------------
        wait for 1 us;
        if error_count = 0 then
            report LF & LF &
                "    ##################################################" & LF &
                "    ##                                              ##" & LF &
                "    ##        UART TB:  ALL CHECKS PASSED           ##" & LF &
                "    ##                                              ##" & LF &
                "    ##################################################" & LF
                severity note;
        else
            report LF & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                "    !!                                              !!" & LF &
                "    !!   UART TB:  " & integer'image(error_count) &
                       " CHECK(S) FAILED" & LF &
                "    !!                                              !!" & LF &
                "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                severity warning;
        end if;

        stop;          -- clean halt (no failure assertion)
        wait;
    end process;

end architecture sim;
