-------------------------------------------------------------------------------
-- rtc_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the RTC (real-time clock) peripheral testbench (tb/RTC_tb.vhd).
-- Mirrors nfc_bfm_pkg.vhd and i3c_bfm_pkg.vhd: RTC.vhd is being written in parallel against the same FROZEN design this bench targets (~/vesta_docs/digperiphs/rtc_design.md, D1-D17 plus A1-A4).
-- The slot numbers, CR/SR field positions and packing helper below are therefore LOCAL to this bench, not shared MemoryMap.vhd constants.
-- RTC0 lives at 0x6500, and MemoryMap.vhd has no RTC slot constants until the generator knob is turned on (D17).
--
-- CHECKER INDEPENDENCE (the task's binding instruction, and the I3C/NFC lesson): this package provides ONLY bus-level plumbing and TB-side reference-counter helpers (rtc_combined, rtc_within).
-- It NEVER reads a DUT internal.
-- The bench keeps its own wall-clock reference by counting lfxt_in edges in TB code and hand-computes the expected alarm and tick instants; these helpers only format and compare that independent reference against the DUT's coherent snapshot read.
--
-- Frozen register map (word slots @0x6500, design doc D5):
--   0 RTC0CR   1 RTC0SEC  2 RTC0SUB  3 RTC0ALM  4 RTC0PER  5 RTC0SR
--   6 RTC0TRIM (reserved, reads 0)   7+ read 0
--
-- Calling convention for the bounded polls copies nfc_bfm_pkg exactly:
--   (signal clk, signal b, signal read_data, [args], done_ok : out boolean).
-- The caller turns done_ok into a scoreboard pass/fail (sb.check_true), so a poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package rtc_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5) -------------------
    constant RTC_SLOT_CR   : natural := 0;
    constant RTC_SLOT_SEC  : natural := 1;
    constant RTC_SLOT_SUB  : natural := 2;
    constant RTC_SLOT_ALM  : natural := 3;
    constant RTC_SLOT_PER  : natural := 4;
    constant RTC_SLOT_SR   : natural := 5;
    constant RTC_SLOT_TRIM : natural := 6;   -- reserved (D16): reads 0

    -- ---- RTC0CR bit positions (design doc D5, slot 0) ---------------------
    constant RTC_CR_RTCEN  : natural := 0;   -- enable seconds counter and prescaler (crosses to LFXT)
    constant RTC_CR_ALMEN  : natural := 1;   -- enable alarm compare              (crosses to LFXT)
    constant RTC_CR_TICKEN : natural := 2;   -- enable periodic-tick down-counter (crosses to LFXT)
    constant RTC_CR_ALMIE  : natural := 3;   -- alarm interrupt enable            (mclk)
    constant RTC_CR_TICKIE : natural := 4;   -- periodic-tick interrupt enable    (mclk)

    -- ---- RTC0SR bit positions (design doc D5, slot 5) ---------------------
    constant RTC_SR_SYNC   : natural := 0;   -- r    : a SEC/ALM/PER commit is in flight (BUSY)
    constant RTC_SR_ALMF   : natural := 1;   -- w1c  : alarm fired (mclk sticky, D10/D11)
    constant RTC_SR_TICKF  : natural := 2;   -- w1c  : periodic tick fired (mclk sticky, D10/D12)

    -- ---- geometry of the combined wall-clock counter (D6) -----------------
    -- {sec_cnt[31:0], sub_cnt[14:0]} is ONE 47-bit binary counter that increments by 1 on every lfxt_in rising edge.
    -- The subsecond prescaler rolls at 32768 = 2^15 exactly, and SEC is its carry-out.
    constant RTC_SUB_BITS  : natural := 15;
    constant RTC_SEC_BITS  : natural := 32;
    constant RTC_CNT_BITS  : natural := RTC_SEC_BITS + RTC_SUB_BITS;   -- 47
    constant RTC_SUB_MOD   : natural := 32768;                          -- 2^15

    -- Build a full 32-bit RTC0CR word (D5 field layout).
    -- IE bits stay in the mclk domain and gate irq_rtc combinationally (D13); EN bits cross to LFXT (D9).
    function rtc_mk_cr(rtcen, almen, ticken, almie, tickie : std_logic)
        return std_logic_vector;

    -- Reference-counter helper (checker-independent): assemble the TB's OWN 47-bit combined value {SEC[31:0], SUB[14:0]} from a SEC read word and a SUB read word.
    -- The result is compared against the free-running lfxt-edge reference the bench maintains.
    function rtc_combined(sec, sub : std_logic_vector(31 downto 0))
        return unsigned;

    -- True when the absolute difference of two 47-bit combined counter values is at most bound.
    -- Used to bound the DUT snapshot's staleness (about one lfxt period plus a few clk, D7) against the TB reference window.
    function rtc_within(a, b : unsigned; bound : natural) return boolean;

    -- Bounded poll of RTC0SR.SYNC (bit 0) until it reads '0' (D8: the commit has crossed into the LFXT domain).
    -- done_ok comes back false (the poll never hangs) if SYNC has not cleared within the guard count, mirroring nfc_wait_busy_clear.
    procedure rtc_wait_sync_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of a single RTC0SR flag bit until it reads exp_val.
    -- done_ok comes back false (the poll never hangs) if the bit has not reached exp_val within the guard count.
    -- Mirrors nfc_wait_sr_bit_set, generalized to a target value so it can wait for a flag to SET or confirm it stays CLEAR.
    procedure rtc_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean);

    -- Guard bound for the SR polls.
    -- The longest legitimate wait is an alarm programmed one prescaler-wrap away, at most 32768 lfxt ticks in the worst case, but the bench always compresses that to roughly 256 or fewer via the set-time trick.
    -- Each poll iteration is one bus_read (about 4 clk, roughly 0.8 lfxt period), so 8000 iterations is about 6400 lfxt ticks: bounded and well inside the watchdog.
    constant RTC_POLL_GUARD : natural := 8000;

end package rtc_bfm_pkg;


package body rtc_bfm_pkg is

    function rtc_mk_cr(rtcen, almen, ticken, almie, tickie : std_logic)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(RTC_CR_RTCEN)  := rtcen;
        v(RTC_CR_ALMEN)  := almen;
        v(RTC_CR_TICKEN) := ticken;
        v(RTC_CR_ALMIE)  := almie;
        v(RTC_CR_TICKIE) := tickie;
        return v;
    end function;

    function rtc_combined(sec, sub : std_logic_vector(31 downto 0))
        return unsigned is
    begin
        return unsigned(sec) & unsigned(sub(RTC_SUB_BITS - 1 downto 0));
    end function;

    function rtc_within(a, b : unsigned; bound : natural) return boolean is
    begin
        if a >= b then
            return (a - b) <= to_unsigned(bound, a'length);
        else
            return (b - a) <= to_unsigned(bound, b'length);
        end if;
    end function;

    procedure rtc_wait_sync_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, RTC_SLOT_SR, s);
            if to_X01(s(RTC_SR_SYNC)) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > RTC_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure rtc_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, RTC_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > RTC_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body rtc_bfm_pkg;
