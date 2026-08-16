/* -----------------------------------------------------------------------------
   pwm_bfm_pkg.vhd
   -----------------------------------------------------------------------------
   Bench-support helpers for the PWM peripheral testbench (tb/PWM_tb.vhd).
   The slot numbers and CR/POL/SR field positions are LOCAL to this bench: PWM0 sits at 0x6600 and MemoryMap.vhd carries no PWM0 constants.
   Provides bus plumbing, register-field packing, bounded SR polls, and pwm_wait_transition, which counts clk edges between observed pwm_out changes.
   No DUT internal is ever read: period, duty and boundary math is done by the bench from the PER/DTY/PSC values it programmed.
   Bounded polls end with done_ok, which the caller turns into a scoreboard check, so a poll that never satisfies its condition fails the run instead of hanging.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package pwm_bfm_pkg is

    -- ---- register word-slot map -------------------------------------------
    constant PWM_SLOT_CR   : natural := 0;
    constant PWM_SLOT_PER  : natural := 1;
    constant PWM_SLOT_DTY0 : natural := 2;
    constant PWM_SLOT_DTY1 : natural := 3;
    constant PWM_SLOT_DTY2 : natural := 4;   -- reserved: reads 0, writes ignored
    constant PWM_SLOT_DTY3 : natural := 5;   -- reserved: reads 0, writes ignored
    constant PWM_SLOT_POL  : natural := 6;
    constant PWM_SLOT_DT   : natural := 7;   -- reserved: reads 0, writes ignored
    constant PWM_SLOT_SR   : natural := 8;

    -- ---- PWM0CR bit positions (slot 0) ------------------------------------
    constant PWM_CR_PWMEN   : natural := 0;    -- master enable                    (crosses to clk)
    constant PWM_CR_CH0EN   : natural := 1;    -- CH0 output enable                (crosses to clk)
    constant PWM_CR_CH1EN   : natural := 2;    -- CH1 output enable                (crosses to clk)
    constant PWM_CR_CH2EN   : natural := 3;    -- reserved (4-channel bolt-on)
    constant PWM_CR_CH3EN   : natural := 4;    -- reserved (4-channel bolt-on)
    constant PWM_CR_CNTMODE : natural := 5;    -- reserved (center-aligned mode)
    constant PWM_CR_DTEN    : natural := 6;    -- reserved (deadtime bolt-on)
    constant PWM_CR_PEVIE   : natural := 7;    -- period-event interrupt enable    (clk)
    constant PWM_CR_FLTIE   : natural := 8;    -- fault interrupt enable           (clk)
    constant PWM_CR_FLTEN   : natural := 12;   -- fault system enable              (crosses to clk)
    constant PWM_CR_FLTPOL  : natural := 13;   -- reserved (HW fault polarity)
    constant PWM_CR_FLTTRIG : natural := 14;   -- write-1 software trip, reads 0   (crosses to clk)
    constant PWM_CR_PSC_LO  : natural := 16;   -- PSC[3:0] field lo
    constant PWM_CR_PSC_HI  : natural := 19;   -- PSC[3:0] field hi

    -- ---- PWM0POL bit positions (slot 6; takes effect immediately) ---------
    constant PWM_POL_POL0  : natural := 0;
    constant PWM_POL_POL1  : natural := 1;
    constant PWM_POL_SAFE0 : natural := 4;
    constant PWM_POL_SAFE1 : natural := 5;

    -- ---- PWM0SR bit positions (slot 8) ------------------------------------
    constant PWM_SR_FLTF : natural := 0;   -- w1c
    constant PWM_SR_PEVF : natural := 1;   -- w1c
    constant PWM_SR_UPDF : natural := 2;   -- r
    constant PWM_SR_DIR  : natural := 3;   -- r, reserved

    -- Build a full 32-bit PWM0CR word.
    -- EN/FLTEN/FLTTRIG/PSC cross to the clk engine; PEVIE/FLTIE stay in the clk domain and gate the IRQs combinationally.
    function pwm_mk_cr(pwmen, ch0en, ch1en, pevie, fltie, flten, flttrig : std_logic;
                        psc : std_logic_vector(3 downto 0) := "0000")
        return std_logic_vector;

    -- Build a full 32-bit PWM0POL word; SAFEn is an absolute output level, not a polarity.
    function pwm_mk_pol(pol0, pol1, safe0, safe1 : std_logic) return std_logic_vector;

    -- Guard bound for every bounded poll or wait here; the longest legitimate wait is one PWM period, a few tens of clk edges at this bench's compressed PSC/PER.
    constant PWM_POLL_GUARD : natural := 4000;

    -- Bounded poll of a single PWM0SR bit until it reads exp_val.
    -- done_ok comes back false, never a hang, if the bit has not reached exp_val within the guard count.
    procedure pwm_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean);

    -- Bounded poll of PWM0SR.UPDF (bit 2) until it reads '0', i.e. the staged waveform was absorbed at a period boundary.
    procedure pwm_wait_updf_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Waits for the next change of pwm_out(ch) away from its level at call time, counting elapsed clk rising edges, and returns that count plus the new level.
    -- done_ok comes back false on a bounded timeout, which is also how the bench proves a constant output at the duty=0 and duty>=PER+1 corners.
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
