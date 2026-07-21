-------------------------------------------------------------------------------
-- pwm_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the PWM buffered-PWM-generator peripheral
-- testbench (tb/PWM_tb.vhd). Mirrors rtc_bfm_pkg.vhd / nfc_bfm_pkg.vhd:
-- PWM.vhd is being written in parallel against the same FROZEN design
-- (~/vesta_docs/digperiphs/pwm_design.md, D1-D21 + orchestrator A1-A7) this
-- bench targets, so the slot numbers and CR/POL/SR field positions below are
-- LOCAL to this bench, not shared MemoryMap.vhd constants (PWM0 lives at
-- 0x6600; MemoryMap.vhd has no PWM0 slot constants until the generator knob
-- is turned on, D17).
--
-- CHECKER INDEPENDENCE (the task's binding instruction): this package
-- provides ONLY bus-level plumbing, register-field packing, bounded SR
-- polls, and a single ATOMIC output-measurement primitive
-- (pwm_wait_transition) that counts `clk` edges in TB code between observed
-- `pwm_out` transitions. It NEVER reads a DUT internal (no pwm_cnt,
-- dty_active, per_active, psc_cnt, etc.) -- period/duty/boundary MATH is done
-- by the bench (PWM_tb.vhd) from the PER/DTY/PSC values it programmed,
-- consuming this primitive's elapsed-edge counts. The CONTINUOUS
-- min-pulse-width glitch monitor (G2, the headline check) lives directly in
-- PWM_tb.vhd as a background process -- it needs persistent per-channel
-- accumulator state across the whole run and is not a natural fit for a
-- stateless package procedure; this package's pwm_wait_transition is the
-- on-demand sibling used by the stimulus process itself for G1/G3/G4.
--
-- Frozen register map (word slots @0x6600, design doc D5):
--   0 PWM0CR   1 PWM0PER  2 PWM0DTY0  3 PWM0DTY1  4 PWM0DTY2 (rsvd)
--   5 PWM0DTY3 (rsvd)     6 PWM0POL   7 PWM0DT (rsvd)        8 PWM0SR
--   9+ read 0.
--
-- Calling convention for the bounded polls copies rtc_bfm_pkg exactly:
--   (signal clk, signal b, signal read_data, [args], done_ok : out boolean).
-- The caller turns done_ok into a scoreboard pass/fail (sb.check_true), so a
-- poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package pwm_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5) -------------------
    constant PWM_SLOT_CR   : natural := 0;
    constant PWM_SLOT_PER  : natural := 1;
    constant PWM_SLOT_DTY0 : natural := 2;
    constant PWM_SLOT_DTY1 : natural := 3;
    constant PWM_SLOT_DTY2 : natural := 4;   -- reserved (D16): reads 0, writes ignored
    constant PWM_SLOT_DTY3 : natural := 5;   -- reserved (D16): reads 0, writes ignored
    constant PWM_SLOT_POL  : natural := 6;
    constant PWM_SLOT_DT   : natural := 7;   -- reserved (D16): reads 0, writes ignored
    constant PWM_SLOT_SR   : natural := 8;

    -- ---- PWM0CR bit positions (design doc D5, slot 0) ----------------------
    constant PWM_CR_PWMEN   : natural := 0;    -- master enable                    (->clk)
    constant PWM_CR_CH0EN   : natural := 1;    -- CH0 output enable                (->clk)
    constant PWM_CR_CH1EN   : natural := 2;    -- CH1 output enable                (->clk)
    constant PWM_CR_CH2EN   : natural := 3;    -- reserved (4-ch bolt-on, D16)
    constant PWM_CR_CH3EN   : natural := 4;    -- reserved (4-ch bolt-on, D16)
    constant PWM_CR_CNTMODE : natural := 5;    -- reserved (center-aligned, D19)
    constant PWM_CR_DTEN    : natural := 6;    -- reserved (deadtime bolt-on, D16)
    constant PWM_CR_PEVIE   : natural := 7;    -- period-event interrupt enable    (clk)
    constant PWM_CR_FLTIE   : natural := 8;    -- fault interrupt enable           (clk)
    constant PWM_CR_FLTEN   : natural := 12;   -- fault system enable              (->clk)
    constant PWM_CR_FLTPOL  : natural := 13;   -- reserved (HW fault polarity, D16)
    constant PWM_CR_FLTTRIG : natural := 14;   -- write-1 software trip, reads 0   (->clk)
    constant PWM_CR_PSC_LO  : natural := 16;   -- PSC[3:0] field lo
    constant PWM_CR_PSC_HI  : natural := 19;   -- PSC[3:0] field hi

    -- ---- PWM0POL bit positions (design doc D5, slot 6; immediate, D11) -----
    constant PWM_POL_POL0  : natural := 0;
    constant PWM_POL_POL1  : natural := 1;
    constant PWM_POL_SAFE0 : natural := 4;
    constant PWM_POL_SAFE1 : natural := 5;

    -- ---- PWM0SR bit positions (design doc D5, slot 8) ----------------------
    constant PWM_SR_FLTF : natural := 0;   -- w1c
    constant PWM_SR_PEVF : natural := 1;   -- w1c
    constant PWM_SR_UPDF : natural := 2;   -- r
    constant PWM_SR_DIR  : natural := 3;   -- r, reserved (D19)

    -- Build a full 32-bit PWM0CR word (D5 field layout). EN/FLTEN/FLTTRIG/PSC
    -- cross to the `clk` engine (D2.2/D2.4); PEVIE/FLTIE stay `clk`-domain
    -- and gate the IRQs combinationally (D18).
    function pwm_mk_cr(pwmen, ch0en, ch1en, pevie, fltie, flten, flttrig : std_logic;
                        psc : std_logic_vector(3 downto 0) := "0000")
        return std_logic_vector;

    -- Build a full 32-bit PWM0POL word (D5 field layout, D11 absolute safe
    -- level).
    function pwm_mk_pol(pol0, pol1, safe0, safe1 : std_logic) return std_logic_vector;

    -- guard bound for every bounded poll/wait in this package: the largest
    -- legitimate wait in this bench is one PWM period, which the bench keeps
    -- to at most a few tens of clk edges (compressed timing, small PSC/PER) --
    -- 4000 clk edges is generous headroom while staying bounded.
    constant PWM_POLL_GUARD : natural := 4000;

    -- Bounded poll of a single PWM0SR bit until it reads exp_val. done_ok is
    -- false (never hangs) if the bit has not reached exp_val within the guard
    -- count -- mirrors rtc_wait_flag.
    procedure pwm_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean);

    -- Specialized bounded poll of PWM0SR.UPDF (bit 2) until it reads '0'
    -- (D9: the staged waveform has been absorbed at a period boundary).
    procedure pwm_wait_updf_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- CHECKER-INDEPENDENT output-measurement primitive (mandatory, D8/G1-G4):
    -- waits for the NEXT change of pwm_out(ch) (to_X01-normalized) away from
    -- its level at call time, counting `clk` RISING edges elapsed. Returns
    -- the elapsed edge count and the new level. done_ok is false (never
    -- hangs) if no transition is observed within PWM_POLL_GUARD clk edges --
    -- this is also how the bench proves a CONSTANT output (G4 duty=0 /
    -- duty>=PER+1 corners): a bounded, expected timeout.
    --
    -- This procedure reads ONLY the bench-visible pwm_out port -- never a DUT
    -- internal -- so every period/duty figure the bench checks is derived by
    -- the bench's OWN arithmetic on the PER/DTY/PSC values it programmed.
    procedure pwm_wait_transition(signal clk      : in  std_logic;
                                  signal pwm_out  : in  std_logic_vector(1 downto 0);
                                  ch              : in  natural range 0 to 1;
                                  elapsed         : out natural;
                                  new_level       : out std_logic;
                                  done_ok         : out boolean);

end package pwm_bfm_pkg;


package body pwm_bfm_pkg is

    function pwm_mk_cr(pwmen, ch0en, ch1en, pevie, fltie, flten, flttrig : std_logic;
                        psc : std_logic_vector(3 downto 0) := "0000")
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(PWM_CR_PWMEN)   := pwmen;
        v(PWM_CR_CH0EN)   := ch0en;
        v(PWM_CR_CH1EN)   := ch1en;
        v(PWM_CR_PEVIE)   := pevie;
        v(PWM_CR_FLTIE)   := fltie;
        v(PWM_CR_FLTEN)   := flten;
        v(PWM_CR_FLTTRIG) := flttrig;
        v(PWM_CR_PSC_HI downto PWM_CR_PSC_LO) := psc;
        return v;
    end function;

    function pwm_mk_pol(pol0, pol1, safe0, safe1 : std_logic) return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(PWM_POL_POL0)  := pol0;
        v(PWM_POL_POL1)  := pol1;
        v(PWM_POL_SAFE0) := safe0;
        v(PWM_POL_SAFE1) := safe1;
        return v;
    end function;

    procedure pwm_wait_flag(signal clk       : in    std_logic;
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
            bus_read(clk, b, read_data, PWM_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > PWM_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure pwm_wait_updf_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean) is
    begin
        pwm_wait_flag(clk, b, read_data, PWM_SR_UPDF, '0', done_ok);
    end procedure;

    procedure pwm_wait_transition(signal clk      : in  std_logic;
                                  signal pwm_out  : in  std_logic_vector(1 downto 0);
                                  ch              : in  natural range 0 to 1;
                                  elapsed         : out natural;
                                  new_level       : out std_logic;
                                  done_ok         : out boolean) is
        variable start_lvl : std_logic;
        variable cnt       : natural := 0;
    begin
        start_lvl := to_X01(pwm_out(ch));
        done_ok   := false;
        elapsed   := 0;
        new_level := start_lvl;
        loop
            wait until clk = '1';
            cnt := cnt + 1;
            if to_X01(pwm_out(ch)) /= start_lvl then
                elapsed   := cnt;
                new_level := to_X01(pwm_out(ch));
                done_ok   := true;
                exit;
            end if;
            exit when cnt > PWM_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body pwm_bfm_pkg;
