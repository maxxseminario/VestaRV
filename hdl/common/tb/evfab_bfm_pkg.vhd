-- Bench-support helpers for the EVFAB0 event/trigger fabric testbench (tb/EVFAB_tb.vhd).
-- The slot/CR/SR/CAP/CHnCFG field positions below are LOCAL to this bench and are NOT shared MemoryMap.vhd constants; EVFAB0 lives at 0x6B00 and MemoryMap.vhd carries no EVFAB0 slot constants.
-- Besides bus plumbing and bounded polls, this package holds a TB SHADOW MODEL of the whole matrix (event front-end including GPIO0, crossbar, output register, OVR, stickies), built ONLY from what the TB commands and drives and NEVER from a DUT-internal signal.
-- SHADOW-MODEL TIMING CONTRACT: call evfab_shadow_tick EXACTLY ONCE PER clk PERIOD, right after the rising edge, passing the ev_in/gpio0_evin/task_busy values the TB holds into the DUT for THAT SAME period.
-- It therefore carries one extra lag register per T/L/GPIO bit (`raw_prev`) than the DUT's real 3-flop chain; that lag is an artifact of this call convention, NOT a claim about silicon flop count.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package evfab_bfm_pkg is

    -- Register word-slot map, base 0x6B00.
    constant EVFAB_SLOT_CR       : natural := 0;   -- rw:  CR.EN
    constant EVFAB_SLOT_SR       : natural := 1;   -- ro:  FIREDIF/OVRIF
    constant EVFAB_SLOT_IE       : natural := 2;   -- reserved, r0/wI
    constant EVFAB_SLOT_CAP      : natural := 3;   -- ro:  NCH/NEV/NTASK/VER
    constant EVFAB_SLOT_CHEN     : natural := 4;   -- rw:  channel enables
    constant EVFAB_SLOT_CHENSET  : natural := 5;   -- w1s/r
    constant EVFAB_SLOT_CHENCLR  : natural := 6;   -- w1c/r
    constant EVFAB_SLOT_CHTRIG   : natural := 7;   -- w1-inject, reads 0
    constant EVFAB_SLOT_FIRED    : natural := 8;   -- W1C sticky
    constant EVFAB_SLOT_OVR      : natural := 9;   -- W1C sticky
    constant EVFAB_SLOT_EVSTAT   : natural := 10;  -- W1C sticky, ungated
    constant EVFAB_SLOT_EVTRIG   : natural := 11;  -- w1-inject, reads 0
    constant EVFAB_SLOT_RSVD12   : natural := 12;  -- reserved r0 (TKSTAT)
    constant EVFAB_SLOT_RSVD13   : natural := 13;  -- reserved r0 (FIREDIE)
    constant EVFAB_SLOT_RSVD14   : natural := 14;  -- reserved r0 (OVRIE)
    constant EVFAB_SLOT_GPIOMASK : natural := 15;  -- rw:  EVGPIOMASK[7:0]
    constant EVFAB_SLOT_CH0CFG   : natural := 16;  -- CHnCFG = 16+n, n=0..15
    -- CHnCFG REGISTER ARRAY size: 16 addresses independent of the LIVE N_CH count, and slots for n >= N_CH read 0 and ignore writes.
    constant EVFAB_CHCFG_SLOTS   : natural := 16;

    -- Convenience: the CHnCFG slot for channel n.
    function evfab_slot_ch(n : natural) return natural;

    -- EVFCR bit positions (slot 0).
    constant EVFAB_CR_EN : natural := 0;

    -- EVFSR bit positions (slot 1).
    constant EVFAB_SR_FIREDIF : natural := 0;
    constant EVFAB_SR_OVRIF   : natural := 1;

    -- EVFCAP field positions (slot 3).
    constant EVFAB_CAP_NCH_LO   : natural := 0;   -- [7:0]
    constant EVFAB_CAP_NEV_LO   : natural := 8;   -- [15:8]
    constant EVFAB_CAP_NTASK_LO : natural := 16;  -- [23:16]
    constant EVFAB_CAP_VER_LO   : natural := 24;  -- [31:24]

    -- EVFCHnCFG field positions (slots 16+n).
    constant EVFAB_CHCFG_EVSEL_LO   : natural := 0;   -- [4:0]
    constant EVFAB_CHCFG_TASKSEL_LO : natural := 8;   -- [11:8]
    constant EVFAB_CHCFG_ENR        : natural := 31;  -- ro mirror of CHEN(n)

    -- Live line counts (v1 defaults).
    constant EVFAB_N_CH        : natural := 8;
    constant EVFAB_N_EV        : natural := 16;
    constant EVFAB_N_TASK      : natural := 10;
    constant EVFAB_EV_GPIO_IDX : natural := 15;
    constant EVFAB_VER         : natural := 1;

    -- EVFCAP read-only constant at v1 defaults: VER=01, NTASK=0A, NEV=10, NCH=08.
    constant EVFAB_CAP_EXPECT : std_logic_vector(31 downto 0) := x"010A1008";

    -- EV_MODE_* generic defaults: TGL = EV4/5/6/8/9, LVL = EV13.
    constant EVFAB_MODE_TGL : std_logic_vector(31 downto 0) := x"00000370";
    constant EVFAB_MODE_LVL : std_logic_vector(31 downto 0) := x"00002000";

    function evfab_ev_is_tgl(e : natural) return boolean;
    function evfab_ev_is_lvl(e : natural) return boolean;

    -- Guard bound for register-bit polls: ~20000 bus_read-class iterations trips far inside the 100 ms tb watchdog.
    constant EVFAB_POLL_GUARD : natural := 20000;
    -- Guard bound for direct task_pulse-signal polls, counted in clk edges.
    constant EVFAB_PULSE_GUARD : natural := 4096;

    -- Build an EVFCHnCFG write word (EVSEL[4:0], TASKSEL[11:8]), leaving reserved bits and ENR at 0.
    -- ENR is read-only and a write to it is ignored by the DUT.
    function evfab_mk_cfg(evsel   : natural range 0 to 31;
                          tasksel : natural range 0 to 15)
        return std_logic_vector;

    -- Action-visibility settle: 4 clk, one above the 3-clk contract, between an action write (CHTRIG/EVTRIG/W1C) and the read that checks it.
    procedure evfab_settle(signal clk : in std_logic);

    -- Bounded poll of one bit of a given register slot until it reads exp_val.
    procedure evfab_wait_reg_bit(signal clk       : in    std_logic;
                                 signal b         : inout periph_bus_t;
                                 signal read_data : in    std_logic_vector(31 downto 0);
                                 slot             : in    natural;
                                 bit_idx          : in    natural;
                                 exp_val          : in    std_logic;
                                 done_ok          : out   boolean);

    -- Bounded direct wait on a task_pulse bit, which is a DUT port signal and not a register.
    -- It counts clk edges taken so callers can assert exact latency: 1 clk for P mode, 3 for T/L.
    procedure evfab_wait_task_pulse(signal clk : in  std_logic;
                                    signal tp  : in  std_logic_vector;
                                    idx        : in  natural;
                                    max_cyc    : in  natural;
                                    cyc_taken  : out natural;
                                    done_ok    : out boolean);

    -- TB SHADOW MODEL: it mirrors the event and GPIO0 front ends, the crossbar plus output register and the stickies, purely from TB-commanded config and TB-driven stimulus.
    -- See the file header for the call-timing contract.

    -- One event or GPIO bit's front-end state.
    -- `raw_prev` is a TB bookkeeping lag stage (see the header's timing-contract note); s1/s2/prv mirror the DUT's uniform 3-flop chain.
    type evfab_fe_t is record
        raw_prev : std_logic;
        s1       : std_logic;
        s2       : std_logic;
        prv      : std_logic;
    end record;
    constant EVFAB_FE_ZERO : evfab_fe_t := (raw_prev => '0', s1 => '0', s2 => '0', prv => '0');

    type evfab_ev_fe_arr_t is array (0 to EVFAB_N_EV - 1) of evfab_fe_t;
    type evfab_gp_fe_arr_t is array (0 to 7) of evfab_fe_t;

    -- One channel's live config: the CHnCFG EVSEL/TASKSEL fields.
    type evfab_ch_cfg_t is record
        evsel   : natural range 0 to 31;
        tasksel : natural range 0 to 15;
    end record;
    constant EVFAB_CH_CFG_ZERO : evfab_ch_cfg_t := (evsel => 0, tasksel => 0);
    type evfab_ch_cfg_arr_t is array (0 to EVFAB_N_CH - 1) of evfab_ch_cfg_t;

    -- Per-task same-cycle firing-collision counts, the OVR merge term.
    type evfab_taskcnt_arr_t is array (0 to EVFAB_N_TASK - 1) of natural;

    -- The whole shadow state: commanded config plus the modelled front-end and sticky state.
    type evfab_shadow_t is record
        cr_en     : std_logic;
        chen      : std_logic_vector(EVFAB_N_CH - 1 downto 0);
        cfg       : evfab_ch_cfg_arr_t;
        gpiomask  : std_logic_vector(7 downto 0);
        ev_fe     : evfab_ev_fe_arr_t;
        gp_fe     : evfab_gp_fe_arr_t;
        fired     : std_logic_vector(EVFAB_N_CH - 1 downto 0);
        ovr       : std_logic_vector(EVFAB_N_CH - 1 downto 0);
        evstat    : std_logic_vector(EVFAB_N_EV - 1 downto 0);
        pend_task : std_logic_vector(EVFAB_N_TASK - 1 downto 0);  -- Output register
    end record;

    procedure evfab_shadow_reset(variable sh : inout evfab_shadow_t);

    procedure evfab_shadow_set_cr_en(variable sh : inout evfab_shadow_t;
                                     val         : in    std_logic);

    procedure evfab_shadow_set_chen(variable sh : inout evfab_shadow_t;
                                    val         : in    std_logic_vector(EVFAB_N_CH - 1 downto 0));

    procedure evfab_shadow_set_cfg(variable sh : inout evfab_shadow_t;
                                   ch          : in    natural;
                                   evsel       : in    natural;
                                   tasksel     : in    natural);

    procedure evfab_shadow_set_gpiomask(variable sh : inout evfab_shadow_t;
                                        val         : in    std_logic_vector(7 downto 0));

    -- ONE call per clk period (see the header's timing contract).
    -- It returns the task_pulse vector expected to be observed on the DUT for THIS period, and folds this period's traffic into the running FIRED/OVR/EVSTAT sticky shadows (set wins, no clears modeled; see the header).
    procedure evfab_shadow_tick(variable sh    : inout evfab_shadow_t;
                                ev_in           : in    std_logic_vector(EVFAB_N_EV - 1 downto 0);
                                gpio0_evin      : in    std_logic_vector(7 downto 0);
                                task_busy       : in    std_logic_vector(EVFAB_N_TASK - 1 downto 0);
                                task_pulse_exp  : out   std_logic_vector(EVFAB_N_TASK - 1 downto 0));

end package evfab_bfm_pkg;


package body evfab_bfm_pkg is

    function evfab_slot_ch(n : natural) return natural is
    begin
        return EVFAB_SLOT_CH0CFG + n;
    end function;

    function evfab_ev_is_tgl(e : natural) return boolean is
    begin
        return EVFAB_MODE_TGL(e) = '1';
    end function;

    function evfab_ev_is_lvl(e : natural) return boolean is
    begin
        return EVFAB_MODE_LVL(e) = '1';
    end function;

    function evfab_mk_cfg(evsel   : natural range 0 to 31;
                          tasksel : natural range 0 to 15)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(EVFAB_CHCFG_EVSEL_LO + 4 downto EVFAB_CHCFG_EVSEL_LO) :=
            std_logic_vector(to_unsigned(evsel, 5));
        v(EVFAB_CHCFG_TASKSEL_LO + 3 downto EVFAB_CHCFG_TASKSEL_LO) :=
            std_logic_vector(to_unsigned(tasksel, 4));
        return v;
    end function;

    procedure evfab_settle(signal clk : in std_logic) is
    begin
        for i in 1 to 4 loop
            wait until clk = '1';
        end loop;
    end procedure;

    procedure evfab_wait_reg_bit(signal clk       : in    std_logic;
                                 signal b         : inout periph_bus_t;
                                 signal read_data : in    std_logic_vector(31 downto 0);
                                 slot             : in    natural;
                                 bit_idx          : in    natural;
                                 exp_val          : in    std_logic;
                                 done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, slot, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > EVFAB_POLL_GUARD;   -- Bounded, so the poll never hangs.
        end loop;
    end procedure;

    procedure evfab_wait_task_pulse(signal clk : in  std_logic;
                                    signal tp  : in  std_logic_vector;
                                    idx        : in  natural;
                                    max_cyc    : in  natural;
                                    cyc_taken  : out natural;
                                    done_ok    : out boolean) is
    begin
        done_ok   := false;
        cyc_taken := 0;
        for i in 1 to max_cyc loop
            wait until clk = '1';
            cyc_taken := i;
            if to_X01(tp(idx)) = '1' then
                done_ok := true;
                exit;
            end if;
        end loop;
    end procedure;

    -- TB shadow model bodies.

    -- Put the shadow back into its reset state: no config, no stickies, cleared front ends.
    procedure evfab_shadow_reset(variable sh : inout evfab_shadow_t) is
    begin
        sh.cr_en     := '0';
        sh.chen      := (others => '0');
        sh.gpiomask  := (others => '0');
        sh.fired     := (others => '0');
        sh.ovr       := (others => '0');
        sh.evstat    := (others => '0');
        sh.pend_task := (others => '0');
        for e in 0 to EVFAB_N_EV - 1 loop
            sh.ev_fe(e) := EVFAB_FE_ZERO;
        end loop;
        for g in 0 to 7 loop
            sh.gp_fe(g) := EVFAB_FE_ZERO;
        end loop;
        for n in 0 to EVFAB_N_CH - 1 loop
            sh.cfg(n) := EVFAB_CH_CFG_ZERO;
        end loop;
    end procedure;

    procedure evfab_shadow_set_cr_en(variable sh : inout evfab_shadow_t;
                                     val         : in    std_logic) is
    begin
        sh.cr_en := val;
    end procedure;

    procedure evfab_shadow_set_chen(variable sh : inout evfab_shadow_t;
                                    val         : in    std_logic_vector(EVFAB_N_CH - 1 downto 0)) is
    begin
        sh.chen := val;
    end procedure;

    procedure evfab_shadow_set_cfg(variable sh : inout evfab_shadow_t;
                                   ch          : in    natural;
                                   evsel       : in    natural;
                                   tasksel     : in    natural) is
    begin
        sh.cfg(ch).evsel   := evsel;
        sh.cfg(ch).tasksel := tasksel;
    end procedure;

    procedure evfab_shadow_set_gpiomask(variable sh : inout evfab_shadow_t;
                                        val         : in    std_logic_vector(7 downto 0)) is
    begin
        sh.gpiomask := val;
    end procedure;

    procedure evfab_shadow_tick(variable sh    : inout evfab_shadow_t;
                                ev_in           : in    std_logic_vector(EVFAB_N_EV - 1 downto 0);
                                gpio0_evin      : in    std_logic_vector(7 downto 0);
                                task_busy       : in    std_logic_vector(EVFAB_N_TASK - 1 downto 0);
                                task_pulse_exp  : out   std_logic_vector(EVFAB_N_TASK - 1 downto 0)) is
        variable ev_front  : std_logic_vector(EVFAB_N_EV - 1 downto 0) := (others => '0');
        variable gp_front  : std_logic_vector(7 downto 0)              := (others => '0');
        variable gp15      : std_logic;
        variable ch_fire   : std_logic_vector(EVFAB_N_CH - 1 downto 0) := (others => '0');
        variable ev_hit    : std_logic;
        variable task_hit  : std_logic_vector(EVFAB_N_TASK - 1 downto 0) := (others => '0');
        variable cnt       : evfab_taskcnt_arr_t := (others => 0);
        variable ovr_this  : std_logic_vector(EVFAB_N_CH - 1 downto 0) := (others => '0');
        variable ns1, ns2, nprv : std_logic;
    begin
        -- Uniform event front-end mirror; see the header's timing contract for why `raw_prev` exists.
        for e in 0 to EVFAB_N_EV - 1 loop
            ns1  := sh.ev_fe(e).raw_prev;
            ns2  := sh.ev_fe(e).s1;
            nprv := sh.ev_fe(e).s2;
            if evfab_ev_is_tgl(e) then
                ev_front(e) := ns2 xor nprv;
            elsif evfab_ev_is_lvl(e) then
                ev_front(e) := ns2 and (not nprv);
            else
                ev_front(e) := ev_in(e);   -- P mode: pass-through, no flop.
            end if;
            sh.ev_fe(e).s1       := ns1;
            sh.ev_fe(e).s2       := ns2;
            sh.ev_fe(e).prv      := nprv;
            sh.ev_fe(e).raw_prev := ev_in(e);
        end loop;

        -- GPIO0 front-end mirror: the 8-bit edge path is AND-masked then OR-reduced into event 15, overriding the per-event select at that index.
        gp15 := '0';
        for g in 0 to 7 loop
            ns1  := sh.gp_fe(g).raw_prev;
            ns2  := sh.gp_fe(g).s1;
            nprv := sh.gp_fe(g).s2;
            gp_front(g) := (ns2 and (not nprv)) and sh.gpiomask(g);
            gp15 := gp15 or gp_front(g);
            sh.gp_fe(g).s1       := ns1;
            sh.gp_fe(g).s2       := ns2;
            sh.gp_fe(g).prv      := nprv;
            sh.gp_fe(g).raw_prev := gpio0_evin(g);
        end loop;
        ev_front(EVFAB_EV_GPIO_IDX) := gp15;

        -- Crossbar mirror: the one-hot EVSEL match behind the channel-arm gate.
        for n in 0 to EVFAB_N_CH - 1 loop
            ev_hit := '0';
            for e in 0 to EVFAB_N_EV - 1 loop
                if sh.cfg(n).evsel = e then
                    ev_hit := ev_hit or ev_front(e);
                end if;
            end loop;
            ch_fire(n) := (sh.cr_en and sh.chen(n)) and ev_hit;
        end loop;

        -- Per-task OR-reduce and the same-cycle collision counts for OVR.
        for t in 0 to EVFAB_N_TASK - 1 loop
            cnt(t) := 0;
            for n in 0 to EVFAB_N_CH - 1 loop
                if ch_fire(n) = '1' and sh.cfg(n).tasksel = t then
                    cnt(t) := cnt(t) + 1;
                end if;
            end loop;
            if cnt(t) > 0 then
                task_hit(t) := '1';
            else
                task_hit(t) := '0';
            end if;
        end loop;

        -- OVR set term: consumer busy OR a same-cycle same-task merge.
        -- A reserved TASKSEL >= N_TASK never contributes.
        for n in 0 to EVFAB_N_CH - 1 loop
            if ch_fire(n) = '1' and sh.cfg(n).tasksel < EVFAB_N_TASK then
                if task_busy(sh.cfg(n).tasksel) = '1' or cnt(sh.cfg(n).tasksel) >= 2 then
                    ovr_this(n) := '1';
                end if;
            end if;
        end loop;

        -- Output register: this call emits the PREVIOUS call's task_hit, and this call's own task_hit becomes visible on the next call.
        task_pulse_exp := sh.pend_task;
        sh.pend_task    := task_hit;

        -- Stickies: set wins and no clears are modeled here, since the bench exercises W1C directly against the real DUT.
        sh.fired  := sh.fired or ch_fire;
        sh.ovr    := sh.ovr or ovr_this;
        sh.evstat := sh.evstat or ev_front;
    end procedure;

end package body evfab_bfm_pkg;
