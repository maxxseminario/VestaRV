/* -----------------------------------------------------------------------------
   rtc_bfm_pkg.vhd
   -----------------------------------------------------------------------------
   Bench-support helpers for the RTC peripheral testbench (tb/RTC_tb.vhd).
   The slot numbers, CR/SR field positions and packing helper are LOCAL to this bench: RTC0 sits at 0x6500 and MemoryMap.vhd carries no RTC constants.
   Bus plumbing plus TB-side reference helpers (rtc_combined, rtc_within) only; no DUT internal is ever read.
   The bench keeps its own wall-clock reference by counting lfxt_in edges and hand-computes the expected alarm and tick instants; these helpers only compare that reference against the DUT's coherent snapshot read.
   Bounded polls end with done_ok, which the caller turns into a scoreboard check, so a poll that never satisfies its condition fails the run instead of hanging.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package rtc_bfm_pkg is

    -- ---- register word-slot map -------------------------------------------
    constant RTC_SLOT_CR   : natural := 0;
    constant RTC_SLOT_SEC  : natural := 1;
    constant RTC_SLOT_SUB  : natural := 2;
    constant RTC_SLOT_ALM  : natural := 3;
    constant RTC_SLOT_PER  : natural := 4;
    constant RTC_SLOT_SR   : natural := 5;
    constant RTC_SLOT_TRIM : natural := 6;   -- reserved: reads 0

    -- ---- RTC0CR bit positions (slot 0) ------------------------------------
    constant RTC_CR_RTCEN  : natural := 0;   -- enable seconds counter and prescaler (crosses to LFXT)
    constant RTC_CR_ALMEN  : natural := 1;   -- enable alarm compare              (crosses to LFXT)
    constant RTC_CR_TICKEN : natural := 2;   -- enable periodic-tick down-counter (crosses to LFXT)
    constant RTC_CR_ALMIE  : natural := 3;   -- alarm interrupt enable            (mclk)
    constant RTC_CR_TICKIE : natural := 4;   -- periodic-tick interrupt enable    (mclk)

    -- ---- RTC0SR bit positions (slot 5) ------------------------------------
    constant RTC_SR_SYNC   : natural := 0;   -- r    : a SEC/ALM/PER commit is in flight (BUSY)
    constant RTC_SR_ALMF   : natural := 1;   -- w1c  : alarm fired (mclk sticky)
    constant RTC_SR_TICKF  : natural := 2;   -- w1c  : periodic tick fired (mclk sticky)

    /* ---- geometry of the combined wall-clock counter ----------------------
       {sec_cnt[31:0], sub_cnt[14:0]} is ONE 47-bit binary counter that increments by 1 on every lfxt_in rising edge.
       The subsecond prescaler rolls at 32768 = 2^15 exactly, and SEC is its carry-out. */
    constant RTC_SUB_BITS  : natural := 15;
    constant RTC_SEC_BITS  : natural := 32;
    constant RTC_CNT_BITS  : natural := RTC_SEC_BITS + RTC_SUB_BITS;   -- 47
    constant RTC_SUB_MOD   : natural := 32768;                          -- 2^15

    -- Build a full 32-bit RTC0CR word.
    -- IE bits stay in the mclk domain and gate irq_rtc combinationally; EN bits cross to LFXT.
    function rtc_mk_cr(rtcen, almen, ticken, almie, tickie : std_logic)
        return std_logic_vector;

    -- Assemble the 47-bit combined value {SEC[31:0], SUB[14:0]} from a SEC read word and a SUB read word.
    -- The result is compared against the free-running lfxt-edge reference the bench maintains.
    function rtc_combined(sec, sub : std_logic_vector(31 downto 0))
        return unsigned;

    -- True when the absolute difference of two 47-bit combined counter values is at most bound.
    -- Bounds the DUT snapshot's staleness, about one lfxt period plus a few clk, against the TB reference window.
    function rtc_within(a, b : unsigned; bound : natural) return boolean;

    -- Bounded poll of RTC0SR.SYNC (bit 0) until it reads '0', i.e. the commit has crossed into the LFXT domain.
    -- done_ok comes back false, never a hang, if SYNC has not cleared within the guard count.
    procedure rtc_wait_sync_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of a single RTC0SR flag bit until it reads exp_val, so it can wait for a flag to set or confirm one stays clear.
    -- done_ok comes back false, never a hang, if the bit has not reached exp_val within the guard count.
    procedure rtc_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean);

    -- Guard bound for the SR polls; the bench compresses every wait to a few hundred lfxt ticks by presetting the time.
    -- One iteration is a bus_read of about 4 clk, so 8000 iterations is roughly 6400 lfxt ticks: bounded and well inside the watchdog.
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
