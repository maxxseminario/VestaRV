-- VestaRV: periph_regs testbench
-- Self-checking unit bench for the shared peripheral register file. It exercises every mask class the .rdl can produce (IMPL, W1C, WOSET, WOT, PULSE, RCLR, HWOWN) and the three RTL-side generics (RDTHRU, WIDEWR, STROBE_HOLD), each byte lane on its own, the two strobe retirements side by side, and the three unregistered hooks (acc_hit, rd_hit, wr_hit) against a negative control that raises acc_hit and neither of the other two.
-- Two instances run off one bus with one synthetic table: dut_p at STROBE_HOLD false, dut_h at true. Everything but the strobe width is checked on dut_p, because the two differ in nothing else.
-- The bus is driven here rather than through periph_tb_pkg.bus_write, which always asserts all four lanes and therefore cannot test a lane at all.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.constants.all;
use work.periph_tb_pkg.all;

entity periph_regs_tb is
end entity periph_regs_tb;

architecture sim of periph_regs_tb is

    constant PERIOD : time := 20 ns;
    constant NW     : natural := 7;

    subtype tab_t is word_array(0 to NW-1);

    -- The synthetic table. One word per mask class, so a failure names the class.
    --   0 CTRL   plain storage, 16 bits implemented, non-zero reset, two hardware-owned bits
    --   1 FLAGS  no storage: hardware owns it, and a written 1 arms w1c_hit
    --   2 CMD    no storage: write-1 strobes, a write-one-to-set and a write-one-to-toggle
    --   3 DATA   no storage, read-consume (onread = rclr)
    --   4 VAL    storage that does not read back (RDTHRU) and has no byte lanes (WIDEWR)
    --   5 WIDE   plain 32-bit storage, byte lanes
    --   6 PASS   plain 32-bit storage that only a FOUR-LANE write reaches (FULLWR)
    constant W_WIDE_C : natural := 5;

    constant T_RSTVAL : tab_t := (x"00001234", x"00000000", x"00000000",
                                  x"00000000", x"00000000", x"00000000", x"00000000");
    constant T_IMPL   : tab_t := (x"0000FFFF", x"00000000", x"00000000",
                                  x"00000000", x"FFFFFFFF", x"FFFFFFFF", x"FFFFFFFF");
    constant T_W1C    : tab_t := (x"00000000", x"0000000F", x"00000000",
                                  x"00000000", x"00000000", x"00000000", x"00000000");
    constant T_WOSET  : tab_t := (x"00000000", x"00000000", x"00000010",
                                  x"00000000", x"00000000", x"00000000", x"00000000");
    constant T_WOT    : tab_t := (x"00000000", x"00000000", x"00000020",
                                  x"00000000", x"00000000", x"00000000", x"00000000");
    constant T_PULSE  : tab_t := (x"00000000", x"00000000", x"00000003",
                                  x"00000000", x"00000000", x"00000000", x"00000000");
    constant T_RCLR   : tab_t := (x"00000000", x"00000000", x"00000000",
                                  x"FFFFFFFF", x"00000000", x"00000000", x"00000000");
    constant T_HWOWN  : tab_t := (x"00000003", x"000000FF", x"00000000",
                                  x"FFFFFFFF", x"FFFFFFFF", x"00000000", x"00000000");
    -- Word 4 reads its hardware copy and takes a whole word from any enabled lane.
    constant T_RDTHRU : std_logic_vector(0 to NW-1) := "0000100";
    constant T_WIDEWR : std_logic_vector(0 to NW-1) := "0000100";
    -- CTRL bit 2 is software storage that the description does not call hardware
    -- owned (T_HWOWN(0) = 0x3) but which an ALIAS WORD of this same block drives.
    -- Without this row the hook on it would reach no logic at all, so GROUP 8b is
    -- the whole proof that HWALIAS is load-bearing.
    constant T_HWALIAS : tab_t := (0 => x"00000004", others => (others => '0'));

    -- Word 5's reset is the table's 0 OR-ed with a per-instance generic, which is
    -- how I2C's default slave address and GPIO's RstValPxOUT reach their flops.
    constant T_RSTOR  : tab_t := (W_WIDE_C => x"000000F0", others => (others => '0'));
    -- Word 6 takes a write only from WEn = "0000".
    constant T_FULLWR : std_logic_vector(0 to NW-1) := "0000001";

    constant W_CTRL  : natural := 0;
    constant W_FLAGS : natural := 1;
    constant W_CMD   : natural := 2;
    constant W_DATA  : natural := 3;
    constant W_VAL   : natural := 4;
    constant W_WIDE  : natural := 5;
    constant W_PASS  : natural := 6;

    constant ZEROW : word := (others => '0');

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal en_n  : std_logic := '1';
    signal wen   : std_logic_vector(3 downto 0) := (others => '1');
    signal addr  : std_logic_vector(7 downto 2) := (others => '0');
    signal wdata : word := (others => '0');

    -- Hardware side, driven by the bench.
    signal hw_rd    : tab_t := (others => (others => '0'));
    signal hw_we    : tab_t := (others => (others => '0'));
    signal hw_wdata : tab_t := (others => (others => '0'));
    signal hw_set   : tab_t := (others => (others => '0'));
    signal hw_clr   : tab_t := (others => (others => '0'));

    signal p_rdata : word;
    signal p_regs  : tab_t;
    signal p_acc, p_rdh, p_wrh : std_logic_vector(0 to NW-1);
    signal p_rds, p_wrs : std_logic_vector(0 to NW-1);
    signal p_pulse, p_w1c, p_woset, p_wot, p_rdclr : tab_t;

    signal h_rdata : word;
    signal h_regs  : tab_t;
    signal h_rds, h_wrs : std_logic_vector(0 to NW-1);
    signal h_pulse, h_w1c, h_woset, h_wot, h_rdclr : tab_t;

    -- The third instance differs from dut_p in ONE generic, REGISTERED_READ, so
    -- a difference between c_rdata and p_rdata is that generic and nothing else.
    signal c_rdata : word;

    -- Per-word write inhibit, driven by the bench.
    signal inh : std_logic_vector(0 to NW-1) := (others => '0');

    signal tb_done : boolean := false;

    shared variable sb : scoreboard;

begin

    clk <= not clk after PERIOD / 2 when not tb_done else '0';

    dut_p : entity work.periph_regs
        generic map (
            NWORDS => NW, RSTVAL => T_RSTVAL, RSTVAL_OR => T_RSTOR,
            IMPL => T_IMPL, W1C => T_W1C,
            WOSET => T_WOSET, WOT => T_WOT, PULSE => T_PULSE, RCLR => T_RCLR,
            HWOWN => T_HWOWN, HWALIAS => T_HWALIAS,
            RDTHRU => T_RDTHRU, WIDEWR => T_WIDEWR,
            FULLWR => T_FULLWR, STROBE_HOLD => false)
        port map (
            ClkMem => clk, resetn => resetn, EnMemPeriph => en_n, WEn => wen,
            MABPart => addr, wdata => wdata, rdata_out => p_rdata, regs => p_regs,
            wr_inhibit => inh, hw_rd => hw_rd, hw_we => hw_we, hw_wdata => hw_wdata,
            hw_set => hw_set, hw_clr => hw_clr,
            acc_hit => p_acc, rd_hit => p_rdh, wr_hit => p_wrh,
            rd_strobe => p_rds, wr_strobe => p_wrs, wr_pulse => p_pulse,
            w1c_hit => p_w1c, woset_hit => p_woset, wot_hit => p_wot, rd_clr => p_rdclr);

    dut_h : entity work.periph_regs
        generic map (
            NWORDS => NW, RSTVAL => T_RSTVAL, RSTVAL_OR => T_RSTOR,
            IMPL => T_IMPL, W1C => T_W1C,
            WOSET => T_WOSET, WOT => T_WOT, PULSE => T_PULSE, RCLR => T_RCLR,
            HWOWN => T_HWOWN, HWALIAS => T_HWALIAS,
            RDTHRU => T_RDTHRU, WIDEWR => T_WIDEWR,
            FULLWR => T_FULLWR, STROBE_HOLD => true)
        port map (
            ClkMem => clk, resetn => resetn, EnMemPeriph => en_n, WEn => wen,
            MABPart => addr, wdata => wdata, rdata_out => h_rdata, regs => h_regs,
            wr_inhibit => inh, hw_rd => hw_rd, hw_we => hw_we, hw_wdata => hw_wdata,
            hw_set => hw_set, hw_clr => hw_clr,
            rd_strobe => h_rds, wr_strobe => h_wrs, wr_pulse => h_pulse,
            w1c_hit => h_w1c, woset_hit => h_woset, wot_hit => h_wot, rd_clr => h_rdclr);

    -- REGISTERED_READ = false: rdata_out is the read mux itself. Everything else
    -- is dut_p's.
    dut_c : entity work.periph_regs
        generic map (
            NWORDS => NW, RSTVAL => T_RSTVAL, RSTVAL_OR => T_RSTOR,
            IMPL => T_IMPL, W1C => T_W1C,
            WOSET => T_WOSET, WOT => T_WOT, PULSE => T_PULSE, RCLR => T_RCLR,
            HWOWN => T_HWOWN, HWALIAS => T_HWALIAS,
            RDTHRU => T_RDTHRU, WIDEWR => T_WIDEWR,
            FULLWR => T_FULLWR, STROBE_HOLD => false, REGISTERED_READ => false)
        port map (
            ClkMem => clk, resetn => resetn, EnMemPeriph => en_n, WEn => wen,
            MABPart => addr, wdata => wdata, rdata_out => c_rdata, regs => open,
            wr_inhibit => inh, hw_rd => hw_rd, hw_we => hw_we, hw_wdata => hw_wdata,
            hw_set => hw_set, hw_clr => hw_clr,
            rd_strobe => open, wr_strobe => open, wr_pulse => open,
            w1c_hit => open, woset_hit => open, wot_hit => open, rd_clr => open);

    watchdog : process
    begin
        wait for 1 ms;
        if not tb_done then
            report LF & "    !!   PERIPH_REGS_TB FAIL (WATCHDOG TIMEOUT)" & LF
                severity warning;
            stop;
        end if;
        wait;
    end process;

    stim : process
        variable rd : word;

        -- One bus cycle. Select on a falling edge, capture on the rising edge,
        -- deselect on the next falling edge, which is the house access shape.
        -- Sampling happens 1 ns after the capture edge, while the peripheral is
        -- still selected, so a held strobe is observable in both modes.
        procedure access_word(slot  : in natural;
                              lanes : in std_logic_vector(3 downto 0);
                              data  : in word) is
        begin
            wait until clk = '0';
            addr  <= std_logic_vector(to_unsigned(slot, 6));
            wdata <= data;
            wen   <= lanes;
            en_n  <= '0';
            wait until clk = '1';
            wait for 1 ns;
        end procedure;

        procedure release_bus is
        begin
            wait until clk = '0';
            en_n <= '1';
            wen  <= (others => '1');
        end procedure;

        procedure wr(slot : in natural; lanes : in std_logic_vector(3 downto 0);
                     data : in word) is
        begin
            access_word(slot, lanes, data);
            release_bus;
        end procedure;

        procedure rdw(slot : in natural; data : out word) is
        begin
            access_word(slot, "1111", (others => '0'));
            data := p_rdata;
            release_bus;
        end procedure;

    begin
        resetn <= '0';
        hw_rd  <= (W_FLAGS => x"000000A5", W_DATA => x"DEADBEEF",
                   W_VAL => x"CAFEBABE", others => (others => '0'));
        wait for 4 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 2 * PERIOD;

        -- GROUP 1: reset values, the implemented-bit mask and the read source.
        report "=== GROUP 1: reset, IMPL mask, read source ===" severity note;
        rdw(W_CTRL, rd);
        sb.check_slv("CTRL reads its reset word", rd, x"00001234");
        rdw(W_WIDE, rd);
        sb.check_slv("RSTVAL_OR: WIDE resets to the OR of the table and the generic",
                     rd, x"000000F0");
        rdw(W_FLAGS, rd);
        sb.check_slv("FLAGS holds no flop and reads hw_rd", rd, x"000000A5");
        rdw(W_DATA, rd);
        sb.check_slv("DATA holds no flop and reads hw_rd", rd, x"DEADBEEF");
        rdw(W_VAL, rd);
        sb.check_slv("VAL is RDTHRU and reads hw_rd, not its storage", rd, x"CAFEBABE");
        access_word(7, "1111", ZEROW);
        sb.check_slv("a slot past the window reads 0", p_rdata, ZEROW);
        release_bus;

        -- GROUP 2: storage, byte lanes and the unimplemented bits.
        report "=== GROUP 2: storage and byte lanes ===" severity note;
        wr(W_WIDE, "0000", x"11223344");
        rdw(W_WIDE, rd);
        sb.check_slv("WIDE takes a four-lane write", rd, x"11223344");

        wr(W_WIDE, "1110", x"AABBCCDD");
        rdw(W_WIDE, rd);
        sb.check_slv("lane 0 alone moves bits 7:0", rd, x"112233DD");
        wr(W_WIDE, "1101", x"AABBCCDD");
        rdw(W_WIDE, rd);
        sb.check_slv("lane 1 alone moves bits 15:8", rd, x"1122CCDD");
        wr(W_WIDE, "1011", x"AABBCCDD");
        rdw(W_WIDE, rd);
        sb.check_slv("lane 2 alone moves bits 23:16", rd, x"11BBCCDD");
        wr(W_WIDE, "0111", x"AABBCCDD");
        rdw(W_WIDE, rd);
        sb.check_slv("lane 3 alone moves bits 31:24", rd, x"AABBCCDD");

        wr(W_CTRL, "0000", x"FFFFFFFF");
        rdw(W_CTRL, rd);
        sb.check_slv("a write outside IMPL is dropped and those bits read 0", rd, x"0000FFFF");

        wr(W_FLAGS, "0000", x"FFFFFFFF");
        rdw(W_FLAGS, rd);
        sb.check_slv("a word with IMPL = 0 stores nothing", rd, x"000000A5");

        -- GROUP 3: WIDEWR, and that RDTHRU storage really is written.
        report "=== GROUP 3: WIDEWR and RDTHRU storage ===" severity note;
        wr(W_VAL, "1110", x"0F0E0D0C");
        sb.check_slv("WIDEWR: one enabled lane writes all 32 bits",
                     p_regs(W_VAL), x"0F0E0D0C");
        rdw(W_VAL, rd);
        sb.check_slv("RDTHRU: the read still comes from hw_rd", rd, x"CAFEBABE");

        -- GROUP 4: the write-1 arms. None of them stores anything.
        report "=== GROUP 4: W1C / WOSET / WOT / PULSE arms ===" severity note;
        access_word(W_FLAGS, "1110", x"0000000F");
        sb.check_slv("W1C arms the bits a 1 was written to", p_w1c(W_FLAGS), x"0000000F");
        sb.check_bit("a W1C write raises wr_strobe", p_wrs(W_FLAGS), '1');
        release_bus;

        access_word(W_FLAGS, "1110", x"00000005");
        sb.check_slv("W1C arms only the bits carrying a 1", p_w1c(W_FLAGS), x"00000005");
        release_bus;

        access_word(W_FLAGS, "1101", x"FFFFFFFF");
        sb.check_slv("a disabled lane arms nothing", p_w1c(W_FLAGS), ZEROW);
        release_bus;

        access_word(W_FLAGS, "1111", ZEROW);
        sb.check_slv("a read arms no W1C bit", p_w1c(W_FLAGS), ZEROW);
        sb.check_bit("a read raises rd_strobe", p_rds(W_FLAGS), '1');
        sb.check_bit("a read does not raise wr_strobe", p_wrs(W_FLAGS), '0');
        release_bus;

        access_word(W_CMD, "1110", x"00000033");
        sb.check_slv("PULSE strobes the singlepulse bits",  p_pulse(W_CMD), x"00000003");
        sb.check_slv("WOSET arms its own bit only",         p_woset(W_CMD), x"00000010");
        sb.check_slv("WOT arms its own bit only",           p_wot(W_CMD),   x"00000020");
        release_bus;

        -- GROUP 5: the read-consume arm.
        report "=== GROUP 5: onread = rclr ===" severity note;
        access_word(W_DATA, "1111", ZEROW);
        sb.check_slv("a read arms rd_clr on an rclr word", p_rdclr(W_DATA), x"FFFFFFFF");
        release_bus;
        access_word(W_DATA, "1110", x"FFFFFFFF");
        sb.check_slv("a write does not arm rd_clr", p_rdclr(W_DATA), ZEROW);
        release_bus;

        -- GROUP 6: the hardware hooks and their priority.
        report "=== GROUP 6: hw_set / hw_clr / hw_we ===" severity note;
        wr(W_CTRL, "0000", x"00000000");
        hw_set <= (W_CTRL => x"00000001", others => (others => '0'));
        wait until clk = '1';
        wait for 1 ns;
        hw_set <= (others => (others => '0'));
        rdw(W_CTRL, rd);
        sb.check_slv("hw_set sets a stored bit", rd, x"00000001");

        hw_clr <= (W_CTRL => x"00000001", others => (others => '0'));
        wait until clk = '1';
        wait for 1 ns;
        hw_clr <= (others => (others => '0'));
        rdw(W_CTRL, rd);
        sb.check_slv("hw_clr clears a stored bit", rd, ZEROW);

        hw_we    <= (W_CTRL => x"00000003", others => (others => '0'));
        hw_wdata <= (W_CTRL => x"00000002", others => (others => '0'));
        wait until clk = '1';
        wait for 1 ns;
        hw_we <= (others => (others => '0'));
        rdw(W_CTRL, rd);
        sb.check_slv("hw_we writes the bits it enables", rd, x"00000002");

        -- A CPU write and a hardware clear on the same edge: the clear wins,
        -- which is the safe direction for an enable bit.
        hw_clr <= (W_CTRL => x"00000002", others => (others => '0'));
        access_word(W_CTRL, "0000", x"00000003");
        hw_clr <= (others => (others => '0'));
        release_bus;
        rdw(W_CTRL, rd);
        sb.check_slv("hw_clr beats a coincident CPU write", rd, x"00000001");

        -- GROUP 7: the two strobe retirements, on one stimulus.
        report "=== GROUP 7: STROBE_HOLD ===" severity note;
        -- Hold the select low across two capture edges.
        wait until clk = '0';
        addr  <= std_logic_vector(to_unsigned(W_CMD, 6));
        wdata <= x"00000003";
        wen   <= "1110";
        en_n  <= '0';
        wait until clk = '1';
        wait for 1 ns;
        sb.check_bit("pulse mode: wr_strobe is up on the capture edge", p_wrs(W_CMD), '1');
        sb.check_bit("hold mode: wr_strobe is up on the capture edge",  h_wrs(W_CMD), '1');
        wait until clk = '1';
        wait for 1 ns;
        sb.check_bit("pulse mode: still up while the select is held", p_wrs(W_CMD), '1');
        sb.check_bit("hold mode: still up while the select is held",  h_wrs(W_CMD), '1');
        wait until clk = '0';
        en_n <= '1';
        wen  <= (others => '1');
        wait for 1 ns;
        sb.check_bit("hold mode: retires asynchronously on deselect", h_wrs(W_CMD), '0');
        sb.check_bit("pulse mode: survives the deselect until the next edge",
                     p_wrs(W_CMD), '1');
        wait until clk = '1';
        wait for 1 ns;
        sb.check_bit("pulse mode: retires on the next ClkMem edge", p_wrs(W_CMD), '0');

        -- GROUP 8: reset returns the storage to RSTVAL.
        report "=== GROUP 8: reset ===" severity note;
        wr(W_WIDE, "0000", x"5A5A5A5A");
        resetn <= '0';
        wait for 2 * PERIOD;
        wait for 1 ns;
        resetn <= '1';
        wait for 2 * PERIOD;
        rdw(W_WIDE, rd);
        sb.check_slv("reset returns WIDE to its reset word, generic included",
                     rd, x"000000F0");
        rdw(W_CTRL, rd);
        sb.check_slv("reset returns CTRL to its reset word", rd, x"00001234");

        -- GROUP 8b: HWALIAS, the hook mask beyond HWOWN.
        report "=== GROUP 8b: HWALIAS ===" severity note;
        wr(W_CTRL, "0000", x"00000000");
        hw_set <= (W_CTRL => x"00000004", others => (others => '0'));
        wait until clk = '1';
        wait for 1 ns;
        hw_set <= (others => (others => '0'));
        rdw(W_CTRL, rd);
        sb.check_slv("HWALIAS: a bit outside HWOWN takes the hook once it is aliased",
                     rd, x"00000004");
        hw_clr <= (W_CTRL => x"00000004", others => (others => '0'));
        wait until clk = '1';
        wait for 1 ns;
        hw_clr <= (others => (others => '0'));
        rdw(W_CTRL, rd);
        sb.check_slv("HWALIAS: and the same bit takes the clear", rd, ZEROW);
        wr(W_CTRL, "0000", x"00001234");   -- back to the reset word for GROUP 11

        -- GROUP 9: FULLWR, the full-word-writes-only mask.
        report "=== GROUP 9: FULLWR ===" severity note;
        wr(W_PASS, "1110", x"2ABBCCDD");
        rdw(W_PASS, rd);
        sb.check_slv("FULLWR: a one-lane write is dropped whole", rd, ZEROW);
        access_word(W_PASS, "1110", x"2ABBCCDD");
        sb.check_bit("FULLWR: a partial write raises no wr_strobe", p_wrs(W_PASS), '0');
        sb.check_bit("FULLWR: a partial write is not a read either", p_rds(W_PASS), '0');
        release_bus;
        wr(W_PASS, "0000", x"2ABBCCDD");
        rdw(W_PASS, rd);
        sb.check_slv("FULLWR: a four-lane write stores all 32 bits", rd, x"2ABBCCDD");
        access_word(W_PASS, "0000", x"12345678");
        sb.check_bit("FULLWR: a four-lane write raises wr_strobe", p_wrs(W_PASS), '1');
        release_bus;
        rdw(W_PASS, rd);
        sb.check_slv("FULLWR: and stored the second four-lane write", rd, x"12345678");
        -- The mask is per word: its neighbour still takes a single lane.
        wr(W_WIDE, "0000", x"00000000");
        wr(W_WIDE, "1110", x"000000AB");
        rdw(W_WIDE, rd);
        sb.check_slv("FULLWR is per word: WIDE still takes one lane", rd, x"000000AB");

        -- GROUP 10: wr_inhibit, the per-word write qualifier.
        report "=== GROUP 10: wr_inhibit ===" severity note;
        inh <= (W_WIDE => '1', others => '0');
        wait until clk = '1';
        wr(W_WIDE, "0000", x"5EADC0DE");
        rdw(W_WIDE, rd);
        sb.check_slv("wr_inhibit: the write is refused", rd, x"000000AB");
        access_word(W_WIDE, "0000", x"5EADC0DE");
        sb.check_bit("wr_inhibit: an inhibited write raises no wr_strobe", p_wrs(W_WIDE), '0');
        sb.check_bit("wr_inhibit: and is not a read either", p_rds(W_WIDE), '0');
        release_bus;
        access_word(W_WIDE, "1111", ZEROW);
        sb.check_bit("wr_inhibit: a read of the same word is unaffected", p_rds(W_WIDE), '1');
        sb.check_slv("wr_inhibit: and returns the stored word", p_rdata, x"000000AB");
        release_bus;

        -- The arms go with the write: a refused write arms nothing.
        inh <= (W_FLAGS => '1', others => '0');
        wait until clk = '1';
        access_word(W_FLAGS, "1110", x"0000000F");
        sb.check_slv("wr_inhibit: the W1C arm is suppressed with the write",
                     p_w1c(W_FLAGS), ZEROW);
        release_bus;
        inh <= (others => '0');
        wait until clk = '1';
        access_word(W_FLAGS, "1110", x"0000000F");
        sb.check_slv("wr_inhibit released: the W1C arm arms again",
                     p_w1c(W_FLAGS), x"0000000F");
        release_bus;
        wr(W_WIDE, "0000", x"5EADC0DE");
        rdw(W_WIDE, rd);
        sb.check_slv("wr_inhibit released: the write lands", rd, x"5EADC0DE");

        -- GROUP 11: REGISTERED_READ. dut_c differs from dut_p in that generic
        -- alone, so the two read paths can be compared on one access.
        report "=== GROUP 11: REGISTERED_READ ===" severity note;
        wr(W_WIDE, "0000", x"40FFEE01");
        wait until clk = '0';
        addr <= std_logic_vector(to_unsigned(W_WIDE, 6));
        wen  <= (others => '1');
        en_n <= '0';
        wait for PERIOD / 4;   -- decode settled, still before the capture edge
        sb.check_slv("combinational read: the word is on the bus BEFORE the capture edge",
                     c_rdata, x"40FFEE01");
        rd := c_rdata;
        wait until clk = '1';
        wait for 1 ns;
        sb.check_slv("registered read: the SAME word one edge later", p_rdata, rd);
        sb.check_slv("combinational read: unchanged across the capture edge", c_rdata, rd);
        release_bus;
        wait until clk = '1';
        wait for 1 ns;
        sb.check_slv("combinational read: collapses to word 0 on deselect",
                     c_rdata, x"00001234");
        sb.check_slv("registered read: holds word 0 on deselect too", p_rdata, x"00001234");

        -- GROUP 12: rd_hit / wr_hit, the unregistered direction-split hooks.
        -- They are what a block whose ClkMem is GATED by EnMemPeriph must use:
        -- one access is one rising edge, so a strobe flopped on it is sampled a
        -- whole bus access late. Every check below is taken BEFORE or ON the
        -- capture edge, where the registered strobe is still down.
        report "=== GROUP 12: rd_hit / wr_hit ===" severity note;
        wait until clk = '0';
        addr <= std_logic_vector(to_unsigned(W_WIDE, 6));
        wen  <= (others => '1');
        en_n <= '0';
        wait for PERIOD / 4;   -- decode settled, still before the capture edge
        sb.check_bit("rd_hit is up on a read BEFORE the capture edge", p_rdh(W_WIDE), '1');
        sb.check_bit("wr_hit stays down on a read",                   p_wrh(W_WIDE), '0');
        sb.check_bit("acc_hit is up in either direction",             p_acc(W_WIDE), '1');
        sb.check_bit("the registered rd_strobe is still down",        p_rds(W_WIDE), '0');
        sb.check_bit("a neighbouring word is not hit",                p_rdh(W_CTRL), '0');
        wait until clk = '1';
        wait for 1 ns;
        sb.check_bit("rd_hit holds across the capture edge",     p_rdh(W_WIDE), '1');
        sb.check_bit("and the registered strobe has caught up",  p_rds(W_WIDE), '1');
        release_bus;
        wait until clk = '1';
        wait for 1 ns;

        access_word(W_WIDE, "1110", x"000000C3");
        sb.check_bit("wr_hit is up on a one-lane write", p_wrh(W_WIDE), '1');
        sb.check_bit("rd_hit stays down on a write",     p_rdh(W_WIDE), '0');
        release_bus;

        -- NEGATIVE CONTROL, both halves: an access that acc_hit reports and that
        -- is NEITHER a read nor a write. Wiring rd_hit or wr_hit to acc_hit, or
        -- forgetting either qualifier, fails exactly here.
        access_word(W_PASS, "1110", x"11111111");
        sb.check_bit("negative control: a FULLWR partial write raises acc_hit",
                     p_acc(W_PASS), '1');
        sb.check_bit("negative control: but not wr_hit", p_wrh(W_PASS), '0');
        sb.check_bit("negative control: and not rd_hit either", p_rdh(W_PASS), '0');
        release_bus;
        access_word(W_PASS, "0000", x"0BADF00D");
        sb.check_bit("FULLWR: the four-lane write does raise wr_hit", p_wrh(W_PASS), '1');
        release_bus;

        inh <= (W_WIDE => '1', others => '0');
        wait until clk = '1';
        access_word(W_WIDE, "0000", x"5EADC0DE");
        sb.check_bit("negative control: an inhibited write raises acc_hit",
                     p_acc(W_WIDE), '1');
        sb.check_bit("negative control: but not wr_hit", p_wrh(W_WIDE), '0');
        sb.check_bit("negative control: and not rd_hit either", p_rdh(W_WIDE), '0');
        release_bus;
        inh <= (others => '0');
        wait until clk = '1';

        wait until clk = '0';
        wait for 1 ns;
        sb.check_bit("deselected: acc_hit is down", p_acc(W_WIDE), '0');
        sb.check_bit("deselected: rd_hit is down",  p_rdh(W_WIDE), '0');
        sb.check_bit("deselected: wr_hit is down",  p_wrh(W_WIDE), '0');

        wait for 2 * PERIOD;
        sb.report_summary("PERIPH_REGS TB");
        tb_done <= true;
        stop;
        wait;
    end process stim;

end architecture sim;
