-------------------------------------------------------------------------------
-- periph_tb_pkg.vhd
-------------------------------------------------------------------------------
-- Shared support for the VestaRV peripheral testbenches (standalone benches in
-- tb/ and, going forward, the full-MCU / integration tests). Collects the parts
-- that were copy-pasted into every standalone bench:
--
--   * img / crc16_byte          -- SLV formatting + CRC16 reference model
--   * scoreboard (protected type) -- self-checking check_bit/check_slv/check_true
--                                    with an internal error tally + PASS/FAIL banner
--   * periph_bus_t + BFM         -- the narrow peripheral register bus
--                                    (en_mem/wen active-low, word-slot addr)
--
-- The gated memory-bus clock stays in each TB architecture (it depends on that
-- bench's reference clock), driven from the record's select line:
--     clk_mem <= clk when b.en_mem = '0' else '0';
-- and the record members map onto the DUT's bus ports (whose names vary per
-- peripheral): en_mem => b.en_mem, wen => b.wen, addr_periph => b.addr_periph,
-- write_data => b.write_data, read_data => read_data.
--
-- See tb/CLAUDE.md for the sharp edges of this bus (gated clk_mem, snapshot-on-
-- select SR reads, clear-pulses that stick until the next access).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package periph_tb_pkg is

    -- ---- formatting / reference models -----------------------------------
    -- Decimal image of an SLV, or "X" if it holds metavalues.
    function img(v : std_logic_vector) return string;

    -- One byte through the CRC16 engine in commune/CRC16.vhd (MSB-first, no
    -- reflection, no final xor). Default polynomial matches the SYSTEM block.
    function crc16_byte(d       : std_logic_vector(7 downto 0);
                        crc_old : std_logic_vector(15 downto 0);
                        poly    : std_logic_vector(15 downto 0) := x"C857")
        return std_logic_vector;

    -- ---- self-checking scoreboard ----------------------------------------
    -- Encapsulates the running error count. Failures report severity WARNING
    -- (so the whole suite runs); the tally drives one PASS/FAIL banner at the
    -- end. Declare one per bench: `shared variable sb : scoreboard;`.
    type scoreboard is protected
        procedure check_bit (tag : in string; got : in std_logic;        exp : in std_logic);
        procedure check_slv (tag : in string; got : in std_logic_vector; exp : in std_logic_vector);
        procedure check_true(tag : in string; cond : in boolean);
        impure function errors return natural;
        procedure report_summary(name : in string);
    end protected scoreboard;

    -- ---- peripheral register-bus BFM -------------------------------------
    -- TB-driven side of the bus (all active-low; addr_periph is the word-slot
    -- index, bits 7..2). read_data is observed separately (DUT drives it).
    type periph_bus_t is record
        en_mem      : std_logic;
        wen         : std_logic_vector(3 downto 0);
        addr_periph : std_logic_vector(7 downto 2);
        write_data  : std_logic_vector(31 downto 0);
    end record;

    constant PERIPH_BUS_IDLE : periph_bus_t :=
        (en_mem => '1', wen => (others => '1'),
         addr_periph => (others => '0'), write_data => (others => '0'));

    -- Single-cycle write: select on a falling clk, capture on the rising clk,
    -- deselect on the next falling clk.
    procedure bus_write(signal clk : in    std_logic;
                        signal b   : inout periph_bus_t;
                        slot : in natural;
                        data : in std_logic_vector(31 downto 0));

    -- Read: select, let read_data register on the rising clk, sample after the
    -- following falling clk so it has settled.
    procedure bus_read (signal clk       : in    std_logic;
                        signal b         : inout periph_bus_t;
                        signal read_data : in    std_logic_vector(31 downto 0);
                        slot : in  natural;
                        data : out std_logic_vector(31 downto 0));

    -- Multi-cycle write: holds the select low across `ncyc` bus clocks. Needed
    -- to clear flags whose clear pulse is consumed synchronously on a different
    -- (peripheral) clock and must overlap one of its edges -- e.g. SYSTEM's
    -- wdt_if. See tb/CLAUDE.md.
    procedure bus_write_hold(signal clk : in    std_logic;
                             signal b   : inout periph_bus_t;
                             slot : in natural;
                             data : in std_logic_vector(31 downto 0);
                             ncyc : in natural);

end package periph_tb_pkg;


package body periph_tb_pkg is

    function img(v : std_logic_vector) return string is
    begin
        if is_x(v) then return "X";
        else return integer'image(to_integer(unsigned(v))); end if;
    end function;

    function crc16_byte(d       : std_logic_vector(7 downto 0);
                        crc_old : std_logic_vector(15 downto 0);
                        poly    : std_logic_vector(15 downto 0) := x"C857")
        return std_logic_vector is
        variable lfsr : std_logic_vector(15 downto 0);
    begin
        lfsr := (crc_old(15 downto 8) xor d) & crc_old(7 downto 0);
        for i in 0 to 7 loop
            if lfsr(15) = '1' then lfsr := (lfsr(14 downto 0) & '0') xor poly;
            else                   lfsr := (lfsr(14 downto 0) & '0'); end if;
        end loop;
        return lfsr;
    end function;

    type scoreboard is protected body
        variable err : natural := 0;

        procedure check_bit(tag : in string; got : in std_logic; exp : in std_logic) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                err := err + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & std_logic'image(exp) &
                    ", got " & std_logic'image(got) & ")" severity warning;
            end if;
        end procedure;

        procedure check_slv(tag : in string; got : in std_logic_vector; exp : in std_logic_vector) is
        begin
            if got = exp then report "PASS: " & tag severity note;
            else
                err := err + 1;
                assert false report "FAIL: " & tag &
                    " (expected " & img(exp) & ", got " & img(got) & ")"
                    severity warning;
            end if;
        end procedure;

        procedure check_true(tag : in string; cond : in boolean) is
        begin
            if cond then report "PASS: " & tag severity note;
            else
                err := err + 1;
                assert false report "FAIL: " & tag severity warning;
            end if;
        end procedure;

        impure function errors return natural is
        begin
            return err;
        end function;

        procedure report_summary(name : in string) is
        begin
            if err = 0 then
                report LF & LF &
                    "    ##################################################" & LF &
                    "    ##   " & name & ":  ALL CHECKS PASSED" & LF &
                    "    ##################################################" & LF
                    severity note;
            else
                report LF & LF &
                    "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF &
                    "    !!   " & name & ":  " & integer'image(err) & " CHECK(S) FAILED" & LF &
                    "    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" & LF
                    severity warning;
            end if;
        end procedure;

    end protected body scoreboard;

    -- NOTE: these use value-based waits (`wait until clk = '0'/'1'`) rather than
    -- rising_edge/falling_edge. For a clean 2-value TB clock they are equivalent,
    -- but they avoid a signal-parameter 'event/'last_value attribute quirk seen in
    -- Xcelium 20.09 where falling_edge(<in signal param>) as a process's first
    -- edge-wait after resuming off the clock grid never fires.

    procedure bus_write(signal clk : in    std_logic;
                        signal b   : inout periph_bus_t;
                        slot : in natural;
                        data : in std_logic_vector(31 downto 0)) is
    begin
        wait until clk = '0';
        b.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
        b.write_data  <= data;
        b.wen         <= (others => '0');
        b.en_mem      <= '0';
        wait until clk = '1';
        wait until clk = '0';
        b.en_mem <= '1';
        b.wen    <= (others => '1');
    end procedure;

    procedure bus_read(signal clk       : in    std_logic;
                       signal b         : inout periph_bus_t;
                       signal read_data : in    std_logic_vector(31 downto 0);
                       slot : in  natural;
                       data : out std_logic_vector(31 downto 0)) is
    begin
        wait until clk = '0';
        b.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
        b.en_mem      <= '0';
        wait until clk = '1';
        wait until clk = '0';
        data     := read_data;
        b.en_mem <= '1';
    end procedure;

    procedure bus_write_hold(signal clk : in    std_logic;
                             signal b   : inout periph_bus_t;
                             slot : in natural;
                             data : in std_logic_vector(31 downto 0);
                             ncyc : in natural) is
    begin
        wait until clk = '0';
        b.addr_periph <= std_logic_vector(to_unsigned(slot, 6));
        b.write_data  <= data;
        b.wen         <= (others => '0');
        b.en_mem      <= '0';
        for i in 1 to ncyc loop
            wait until clk = '1';
        end loop;
        wait until clk = '0';
        b.en_mem <= '1';
        b.wen    <= (others => '1');
    end procedure;

end package body periph_tb_pkg;
