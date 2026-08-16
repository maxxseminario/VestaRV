library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

/* ===========================================================================
   EVFAB: event/trigger fabric, a PPI-style crossbar; ONE instance, EVFAB0 @ 0x6B00, zero pins, vectorless (irq_evfab is a hard constant '0').
   TWO CLOCKS, ONE FAMILY: free-running `clk` (mclk) hosts the front-ends, the crossbar, the output register, the stickies and the action path, while `ClkMem` hosts ONLY the register-file storage and the registered read mux.
   ClkMem's edges are a SUBSET of clk's at the same phase (they are the same net at integration), so every hand-off between the two is a bare held level, never a toggle and never a 2-FF sync.
   EVFAB0 sits in the always-on shared domain: WFI keeps mclk alive, field power only slows it and the power controller never gates it, so chains fire with the bus idle, which is the point of the block.
   -V200X only: no VHDL-2008, every process infers exactly ONE edge of ONE clock, no latch, no clock gate, no falling_edge of anything (least of all EnMemPeriph), and no async clear other than `resetn`.
   =========================================================================== */

entity EVFAB is
    generic (
        N_CH        : natural := 8;     -- LIVE channels (register array is 16 addresses)
        N_EV        : natural := 16;    -- LIVE event lines = ev_in width (encode space 32)
        N_TASK      : natural := 10;    -- LIVE task lines = task_pulse/task_busy width
                                        --   (encode space 16)
        EV_GPIO_IDX : natural := 15;    -- event ID served by the GPIO0 front-end
        EV_MODE_TGL : std_logic_vector(31 downto 0) := X"00000370";  -- T inputs: EV 4,5,6,8,9
        EV_MODE_LVL : std_logic_vector(31 downto 0) := X"00002000";  -- L inputs: EV 13
                                        -- (bit clear in BOTH masks = P, pulse pass-through)
        VER         : natural := 1      -- CAP.VER
    );
    port (
        clk         : in  std_logic;                     -- FREE-RUNNING mclk: front-ends,
                                                         -- crossbar, output reg, stickies,
                                                         -- ACTION path
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_evfab   : out std_logic;                     -- vectorless: constant '0'

        -- register-file slave port (house idiom)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read, no bridge

        -- Producer taps, ONE line per EVSEL ID with its mode set by EV_MODE_*; ev_in(EV_GPIO_IDX) is IGNORED, that event being generated internally from gpio0_evin.
        -- INTEGRATION TIE-OFF: every unused ev_in / gpio0_evin / task_busy bit MUST be tied '0' in MCU.vhd, never left open.
        ev_in       : in  std_logic_vector(N_EV-1 downto 0)   := (others => '0');
        gpio0_evin  : in  std_logic_vector(7 downto 0)        := (others => '0');

        -- consumer interface: levels IN (OVR only, never backpressure), one-mclk pulses OUT
        task_busy   : in  std_logic_vector(N_TASK-1 downto 0) := (others => '0');
        task_pulse  : out std_logic_vector(N_TASK-1 downto 0)  -- REGISTERED
    );
end EVFAB;

architecture behavioral of EVFAB is

    -- ---- ABI constants (NOT generics: the encode spaces never move) --------
    constant EVSEL_W   : natural := 5;
    constant TASKSEL_W : natural := 4;

    /* ---- word-slot map (base 0x6B00, slot n @ 0x6B00 + 4n, off MABPart(7:2))
          0 EVFCR       rw  [0] EN global kill (reset 0); 31:1 reserved r0
          1 EVFSR       ro  [0] FIREDIF = OR(FIRED); [1] OVRIF = OR(OVR); 31:2 r0
          2 EVFIE       reserved: reads 0, writes ignored (vectorless)
          3 EVFCAP      ro  [7:0] N_CH [15:8] N_EV [23:16] N_TASK [31:24] VER
          4 EVFCHEN     rw  [N_CH-1:0] channel enables (reset 0)
          5 EVFCHENSET  w1s, READS CHEN     6 EVFCHENCLR  w1c, READS CHEN
          7 EVFCHTRIG   w1-inject at the CHANNEL, honors EN+CHEN; reads 0
          8 EVFFIRED    W1C sticky "channel n fired"            (set wins)
          9 EVFOVR      W1C sticky overrun                      (set wins)
         10 EVFEVSTAT   W1C sticky raw-event record, UNGATED by EN/CHEN
         11 EVFEVTRIG   w1-inject a RAW EVENT; reads 0
         12-14 reserved r0 (earmarked TKSTAT / FIREDIE / OVRIE)
         15 EVFGPIOMASK rw  [7:0] per-bit enable for the GPIO0 edge path
         16+n EVFCHnCFG rw  [4:0] EVSEL (31 = NONE); [11:8] TASKSEL;
                            [31] ENR = RO mirror of CHEN(n); other bits r0
         32-63 reserved r0
       Every write is lane-0 qualified (WEn(0)='0'); reserved bits ignore writes and read 0; CHnCFG slots with n >= N_CH read 0 and ignore writes; EVSTAT bits >= N_EV read 0. */
    constant SLOT_CR       : natural := 0;
    constant SLOT_SR       : natural := 1;
    constant SLOT_IE       : natural := 2;
    constant SLOT_CAP      : natural := 3;
    constant SLOT_CHEN     : natural := 4;
    constant SLOT_CHENSET  : natural := 5;
    constant SLOT_CHENCLR  : natural := 6;
    constant SLOT_CHTRIG   : natural := 7;
    constant SLOT_FIRED    : natural := 8;
    constant SLOT_OVR      : natural := 9;
    constant SLOT_EVSTAT   : natural := 10;
    constant SLOT_EVTRIG   : natural := 11;
    constant SLOT_GPIOMASK : natural := 15;
    constant SLOT_CH0CFG   : natural := 16;   -- CHnCFG = 16+n, n = 0 .. 15
    constant CHCFG_SLOTS   : natural := 16;   -- register-array size, NOT N_CH

    -- EVFCAP RO constant: VER & N_TASK & N_EV & N_CH, LIVE line counts.
    constant CAP_CONST : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(VER,    8)) &
        std_logic_vector(to_unsigned(N_TASK, 8)) &
        std_logic_vector(to_unsigned(N_EV,   8)) &
        std_logic_vector(to_unsigned(N_CH,   8));

    -- ---- register-file storage (ClkMem domain) -----------------------------
    type evsel_arr_t   is array (0 to N_CH-1) of std_logic_vector(EVSEL_W-1   downto 0);
    type tasksel_arr_t is array (0 to N_CH-1) of std_logic_vector(TASKSEL_W-1 downto 0);

    signal cr_en       : std_logic;                       -- CR.EN, the global kill
    signal chen        : std_logic_vector(N_CH-1 downto 0);
    signal gpiomask    : std_logic_vector(7 downto 0);    -- EVGPIOMASK
    signal cfg_evsel   : evsel_arr_t;
    signal cfg_tasksel : tasksel_arr_t;

    signal slot : natural range 0 to 63;                  -- decoded word slot (level)

    -- ---- ACTION path (clk domain) ------------------------------------------
    signal bus_wr_lvl  : std_logic;                       -- comb, pure DATA (never a clock)
    signal bus_wdata_q : std_logic_vector(31 downto 0);   -- payload snapshot
    signal bus_slot_q  : std_logic_vector(7 downto 2);    -- slot snapshot (SLV: X-safe compare)
    signal wr_s1, wr_s2, wr_prev : std_logic;
    signal wr_pulse    : std_logic;                       -- ONE clk pulse per select window

    signal act_chtrig, act_evtrig  : std_logic;
    signal act_fired, act_ovr, act_evstat : std_logic;

    signal chtrig_pulse : std_logic_vector(N_CH-1 downto 0);
    signal ev_inject    : std_logic_vector(N_EV-1 downto 0);
    signal clr_fired    : std_logic_vector(N_CH-1 downto 0);
    signal clr_ovr      : std_logic_vector(N_CH-1 downto 0);
    signal clr_evstat   : std_logic_vector(N_EV-1 downto 0);

    -- ---- event front-end (clk domain) --------------------------------------
    -- Uniform 3-flop chain for EVERY event input; the mode select downstream is elaboration-static, so the P-mode chains lose their reader and are constant-folded away by synthesis.
    signal ev_s1, ev_s2, ev_prev : std_logic_vector(N_EV-1 downto 0);
    signal ev_front              : std_logic_vector(N_EV-1 downto 0);
    signal ev_eff                : std_logic_vector(N_EV-1 downto 0);

    -- ---- GPIO0 front-end (clk domain) --------------------------------------
    signal gp_s1, gp_s2, gp_prev : std_logic_vector(7 downto 0);
    signal gp_masked             : std_logic_vector(7 downto 0);   -- edge AND mask, PER BIT
    signal gp_event              : std_logic;             -- OR-reduced, drives event EV_GPIO_IDX

    -- ---- crossbar (clk domain) ---------------------------------------------
    signal ch_fire   : std_logic_vector(N_CH-1 downto 0);
    signal task_hit  : std_logic_vector(N_TASK-1 downto 0);
    signal ovr_set   : std_logic_vector(N_CH-1 downto 0);

    -- ---- stickies + SR reductions (clk domain) -----------------------------
    signal fired     : std_logic_vector(N_CH-1 downto 0);
    signal ovr       : std_logic_vector(N_CH-1 downto 0);
    signal evstat    : std_logic_vector(N_EV-1 downto 0);

    -- OR-reduction helper (-V200X has no unary reduce operator).
    function or_red(v : std_logic_vector) return std_logic is
        variable r : std_logic := '0';
    begin
        for i in v'range loop
            r := r or v(i);
        end loop;
        return r;
    end function;

begin

    -- ------------------------- Signal Routing -------------------------------
    -- Slot decode: an EnMemPeriph-qualified LEVEL, never an edge, parked at 0 while deselected so no stale slot can leak into either domain.
    slot <= to_integer(unsigned(MABPart)) when EnMemPeriph = '0' else 0;

    -- Vectorless: the IRQ net is a hard constant; spending a vector later means implementing slot 2 (IE), driving this net and sweeping the router.
    irq_evfab <= '0';

    /* ------------------------- register write (ClkMem) ----------------------
       Rising ClkMem, EnMemPeriph='0' AND lane-0 qualified; EVERY slot handled here is IDEMPOTENT (plain store / w1s / w1c), so the repeated edges of a held select window are harmless, and that is the whole reason these stay out of the clk action path.
       Slots 7-11 (the action set) and 1/2/3/12/13/14/32-63 fall through as no-ops here; CHnCFG slots with n >= N_CH match nothing and are ignored. */
    reg_write : process(resetn, ClkMem)
    begin
        if resetn = '0' then
            cr_en    <= '0';                    -- global kill asserted out of reset
            chen     <= (others => '0');        -- second, independent gate
            gpiomask <= (others => '0');        -- GPIO0 path inert AND X-absorbing
            for n in 0 to N_CH-1 loop
                cfg_evsel(n)   <= (others => '0');   -- harmless: double-gated
                cfg_tasksel(n) <= (others => '0');
            end loop;
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' and WEn(0) = '0' then
                case slot is
                    when SLOT_CR =>
                        cr_en <= wdata(0);                          -- 31:1 reserved
                    when SLOT_CHEN =>
                        chen <= wdata(N_CH-1 downto 0);
                    when SLOT_CHENSET =>
                        chen <= chen or wdata(N_CH-1 downto 0);     -- w1s; write 0 = no-op
                    when SLOT_CHENCLR =>
                        chen <= chen and not wdata(N_CH-1 downto 0);-- w1c; write 0 = no-op
                    when SLOT_GPIOMASK =>
                        gpiomask <= wdata(7 downto 0);
                    when others =>
                        -- CHnCFG array: equality decode per channel, never an integer index.
                        -- ENR(31) is a RO mirror and is NOT writable; bits 7:5 and 30:12 are reserved.
                        for n in 0 to N_CH-1 loop
                            if slot = SLOT_CH0CFG + n then
                                cfg_evsel(n)   <= wdata(EVSEL_W-1 downto 0);
                                cfg_tasksel(n) <= wdata(8+TASKSEL_W-1 downto 8);
                            end if;
                        end loop;
                end case;
            end if;
        end if;
    end process reg_write;

    /* ------------------------- register read (ClkMem) -----------------------
       Registered read mux on rising ClkMem; the clk-domain flags (FIRED / OVR / EVSTAT and the SR reductions) are sampled BARE, which is a plain timed path and not a CDC because ClkMem and clk are the same net at integration.
       Reserved slots and bits read 0; CHENSET/CHENCLR both mirror CHEN; CHTRIG/EVTRIG read 0; no read has any side effect. */
    reg_read : process(resetn, ClkMem)
        variable rd : std_logic_vector(31 downto 0);
    begin
        if resetn = '0' then
            rdata_out <= (others => '0');
        elsif rising_edge(ClkMem) then
            rd := (others => '0');
            case slot is
                when SLOT_CR =>
                    rd(0) := cr_en;
                when SLOT_SR =>
                    -- LIVE RO reductions so firmware polls ONE word; neither FIREDIF nor OVRIF is state.
                    -- Reduced HERE inside the read mux rather than through an intermediate net, which keeps SR bit-consistent with the FIRED/OVR words sampled by this same edge however ClkMem is derived from clk.
                    rd(0) := or_red(fired);
                    rd(1) := or_red(ovr);
                when SLOT_CAP =>
                    rd := CAP_CONST;
                when SLOT_CHEN | SLOT_CHENSET | SLOT_CHENCLR =>
                    rd(N_CH-1 downto 0) := chen;
                when SLOT_FIRED =>
                    rd(N_CH-1 downto 0) := fired;
                when SLOT_OVR =>
                    rd(N_CH-1 downto 0) := ovr;
                when SLOT_EVSTAT =>
                    rd(N_EV-1 downto 0) := evstat;
                when SLOT_GPIOMASK =>
                    rd(7 downto 0) := gpiomask;
                when others =>
                    -- CHnCFG array read, same equality decode as the write side.
                    for n in 0 to N_CH-1 loop
                        if slot = SLOT_CH0CFG + n then
                            rd(EVSEL_W-1 downto 0)          := cfg_evsel(n);
                            rd(8+TASKSEL_W-1 downto 8)      := cfg_tasksel(n);
                            rd(31)                          := chen(n);   -- ENR mirror
                        end if;
                    end loop;
            end case;
            rdata_out <= rd;
        end if;
    end process reg_read;

    /* ------------------------- ACTION path (clk) ----------------------------
       Slots 7-11 are NON-IDEMPOTENT, so one write must produce EXACTLY ONE injection or clear however long the select is held, which is why they are decoded here in the free-running clk domain instead of on ClkMem.
       An arm flop on ClkMem could not re-arm between two back-to-back writes to the same slot, since no ClkMem edge exists while deselected, and would silently swallow the second one.
       The decoded-write LEVEL is pure DATA: combinational, EnMemPeriph-and-lane-0 qualified, and NEVER used as a clock or an edge; a read leaves WEn = "1111" so reads never enter this path. */
    bus_wr_lvl <= '1' when (EnMemPeriph = '0' and WEn(0) = '0') else '0';

    /* ONE shared bus snapshot plus ONE rising-edge detector, giving exactly one action per select window: a held write is one action however long the level holds, and back-to-back writes in SEPARATE accesses are one action each because the level drops while deselected and clk keeps running.
       PAYLOAD BEFORE FLAG: the snapshot is taken at the FIRST clk edge that sees the level and the pulse arrives two edges later, so an action never samples a raw `wdata` the arbiter has already re-driven for the next master.
       Hence the visible latency is 3 clk edges from the opening of the select window, and a read issued sooner sees STALE state; two writes with NO intervening deselect would collapse to one action carrying the last payload, which the MCU fabric never produces. */
    action_path : process(resetn, clk)
    begin
        if resetn = '0' then
            bus_wdata_q <= (others => '0');
            bus_slot_q  <= (others => '0');
            wr_s1       <= '0';
            wr_s2       <= '0';
            wr_prev     <= '0';
        elsif rising_edge(clk) then
            if bus_wr_lvl = '1' then
                bus_wdata_q <= wdata;             -- payload snapshot
                bus_slot_q  <= MABPart;           -- slot snapshot, kept as SLV
            end if;
            wr_s1   <= bus_wr_lvl;
            wr_s2   <= wr_s1;
            wr_prev <= wr_s2;
        end if;
    end process action_path;

    -- The one-clk action strobe: the rising edge of the synchronized write level.
    wr_pulse <= wr_s2 and not wr_prev;

    -- Action slot decode: equality compares on the SNAPSHOTTED slot, kept as a std_logic_vector so a metavalue yields FALSE (no action) rather than an index fault.
    act_chtrig <= wr_pulse when bus_slot_q = std_logic_vector(to_unsigned(SLOT_CHTRIG, 6)) else '0';
    act_fired  <= wr_pulse when bus_slot_q = std_logic_vector(to_unsigned(SLOT_FIRED,  6)) else '0';
    act_ovr    <= wr_pulse when bus_slot_q = std_logic_vector(to_unsigned(SLOT_OVR,    6)) else '0';
    act_evstat <= wr_pulse when bus_slot_q = std_logic_vector(to_unsigned(SLOT_EVSTAT, 6)) else '0';
    act_evtrig <= wr_pulse when bus_slot_q = std_logic_vector(to_unsigned(SLOT_EVTRIG, 6)) else '0';

    -- Per-bit action strobes, each ONE clk wide.
    -- The clears being one-cycle PULSES rather than the held write level is what stops a held W1C eating an event that arrives mid-write.
    gen_act_ch : for n in 0 to N_CH-1 generate
        chtrig_pulse(n) <= act_chtrig and bus_wdata_q(n);
        clr_fired(n)    <= act_fired  and bus_wdata_q(n);
        clr_ovr(n)      <= act_ovr    and bus_wdata_q(n);
    end generate gen_act_ch;

    gen_act_ev : for e in 0 to N_EV-1 generate
        ev_inject(e)  <= act_evtrig and bus_wdata_q(e);
        clr_evstat(e) <= act_evstat and bus_wdata_q(e);
    end generate gen_act_ev;

    /* ------------------------- input front-ends (clk) -----------------------
       ONE uniform 3-flop chain per event input AND per GPIO0 pad bit, with no if-generate on mode; ev_in/gpio0_evin are PURE DATA here, never a clock and never an async clear.
       All chains reset to 0, so a T input already HIGH at reset release produces NO phantom pulse: s2 = prev = 0 makes the XOR 0, and the first genuine flip fires. */
    front_end : process(resetn, clk)
    begin
        if resetn = '0' then
            ev_s1   <= (others => '0');
            ev_s2   <= (others => '0');
            ev_prev <= (others => '0');
            gp_s1   <= (others => '0');
            gp_s2   <= (others => '0');
            gp_prev <= (others => '0');
        elsif rising_edge(clk) then
            ev_s1   <= ev_in;
            ev_s2   <= ev_s1;
            ev_prev <= ev_s2;
            gp_s1   <= gpio0_evin;
            gp_s2   <= gp_s1;
            gp_prev <= gp_s2;
        end if;
    end process front_end;

    -- The GPIO0 path is a per-bit rising edge ANDed with EVGPIOMASK, then OR-reduced into event EV_GPIO_IDX; gpio0_evin carries RAW PRE-MASK pad levels and PxIE is never consulted.
    -- AND-BEFORE-OR IS LOAD-BEARING: an unbonded or undriven GPIO0 pad is X at chip level, and '0' and 'X' is '0', so a masked-off bit ABSORBS the X before the OR tree, and EVGPIOMASK resets to 0 so the whole path is inert out of reset.
    gen_gpio_edge : for g in 0 to 7 generate
        gp_masked(g) <= (gp_s2(g) and not gp_prev(g)) and gpiomask(g);
    end generate gen_gpio_edge;

    -- Any masked-in GPIO0 edge becomes the single internal event line.
    gp_event <= or_red(gp_masked);

    /* Mode select, elaboration-static: EV_MODE_TGL(e)/EV_MODE_LVL(e) with `e` a generate constant is a globally static condition, so exactly one arm survives per index at synthesis.
         T: one pulse per FLIP, both directions (XOR of the last two samples)
         L: one pulse on the RISING edge only; a level that stays high forever fires exactly once
         P: pass-through, NO flop, latency 1 preserved; a P input MUST be a ONE-mclk pulse in the clk domain, because a 2-cycle P input fires its channels twice by design
       TGL wins over LVL if a bit is set in both, which is an illegal configuration and is not checked; index EV_GPIO_IDX is overridden by the GPIO0 path above and its ev_in bit is ignored entirely. */
    gen_front : for e in 0 to N_EV-1 generate
        -- The internally generated GPIO0 event replaces its tap entirely.
        gen_gpio_ev : if e = EV_GPIO_IDX generate
            ev_front(e) <= gp_event;
        end generate gen_gpio_ev;
        -- Every other event line takes its configured T / L / P shaping.
        gen_tap_ev : if e /= EV_GPIO_IDX generate
            ev_front(e) <= (ev_s2(e) xor ev_prev(e))     when EV_MODE_TGL(e) = '1' else
                           (ev_s2(e) and not ev_prev(e)) when EV_MODE_LVL(e) = '1' else
                           ev_in(e);
        end generate gen_tap_ev;
    end generate gen_front;

    -- An EVTRIG-injected event is indistinguishable from a real tap: recorded by EVSTAT even with CR.EN=0 (upstream of the gate) and reaching the crossbar exactly like a producer pulse.
    -- That makes the whole matrix testable from firmware with no producer hardware.
    ev_eff <= ev_front or ev_inject;

    /* ------------------------- crossbar (clk) -------------------------------
       ONE-HOT EQUALITY DECODE plus AND-OR reduction throughout, NEVER a `case` or an integer index on EVSEL/TASKSEL, and that is an X-safety decision: VHDL '=' on a metavalue returns FALSE, so an X in EVSEL/TASKSEL yields an all-zero one-hot (the channel goes inert, with no index range error and no X on task_pulse) and an X on an unselected input line is killed by the AND before it reaches the OR tree.
       EVSEL=31 (NONE), reserved EVSEL 16..30 and TASKSEL >= N_TASK need no special case: they structurally match nothing, and the `inrange` term is why an out-of-range TASKSEL still sets FIRED but raises no pulse and no phantom OVR.
       Input-side gating: ch_arm = CR.EN and CHEN(n) is applied BEFORE the task OR and before FIRED/OVR, so a disabled channel is COMPLETELY inert; EVSTAT is upstream of this gate and still records, and CHTRIG enters INSIDE it so a CHTRIG fire is indistinguishable downstream from an event fire. */
    crossbar : process(cr_en, chen, cfg_evsel, cfg_tasksel, ev_eff,
                       chtrig_pulse, task_busy)
        variable ev_hit_v  : std_logic;
        variable fire_v    : std_logic_vector(N_CH-1 downto 0);
        variable hit_v     : std_logic_vector(N_TASK-1 downto 0);
        variable inrange_v : std_logic;
        variable busy_v    : std_logic;
        variable merge_v   : std_logic;
    begin
        -- per channel: one-hot EVSEL match, then the arm gate
        for n in 0 to N_CH-1 loop
            ev_hit_v := '0';
            for e in 0 to N_EV-1 loop
                if cfg_evsel(n) = std_logic_vector(to_unsigned(e, EVSEL_W)) then
                    ev_hit_v := ev_hit_v or ev_eff(e);
                end if;
            end loop;
            fire_v(n) := (cr_en and chen(n)) and (ev_hit_v or chtrig_pulse(n));
        end loop;

        -- per task: one-hot TASKSEL reduce; several channels selecting the same task in the same cycle produce ONE merged pulse.
        for t in 0 to N_TASK-1 loop
            hit_v(t) := '0';
            for n in 0 to N_CH-1 loop
                if cfg_tasksel(n) = std_logic_vector(to_unsigned(t, TASKSEL_W)) then
                    hit_v(t) := hit_v(t) or fire_v(n);
                end if;
            end loop;
        end loop;

        -- Per channel: the OVR set term, meaning "the pulse was DEGRADED" and never backpressure, since task_busy is a bare-sampled LEVEL that never gates, delays or suppresses task_pulse.
        -- It is consumer busy OR a same-cycle same-task merge, symmetric across all colliding channels because the fabric cannot say which one won.
        for n in 0 to N_CH-1 loop
            inrange_v := '0';
            busy_v    := '0';
            for t in 0 to N_TASK-1 loop
                if cfg_tasksel(n) = std_logic_vector(to_unsigned(t, TASKSEL_W)) then
                    inrange_v := '1';
                    busy_v    := busy_v or task_busy(t);
                end if;
            end loop;
            merge_v := '0';
            for m in 0 to N_CH-1 loop
                if m /= n and cfg_tasksel(m) = cfg_tasksel(n) then
                    merge_v := merge_v or fire_v(m);
                end if;
            end loop;
            ovr_set(n) <= fire_v(n) and inrange_v and (busy_v or merge_v);
        end loop;

        -- publish the two reductions the stickies and the output register consume
        ch_fire  <= fire_v;
        task_hit <= hit_v;
    end process crossbar;

    /* ------------------------- output register (clk) ------------------------
       THE single flop between ev_eff and the consumer: in-fabric latency is exactly 1 mclk and task_pulse is a registered one-mclk pulse BY CONSTRUCTION, so consumers for which a held level is hazardous are protected structurally rather than by contract.
       NO second stage, NO handshake, NO rate limit, NEVER a bus master. */
    out_reg : process(resetn, clk)
    begin
        if resetn = '0' then
            task_pulse <= (others => '0');      -- glitch-free out of reset
        elsif rising_edge(clk) then
            task_pulse <= task_hit;
        end if;
    end process out_reg;

    /* ------------------------- sticky flags (clk) ---------------------------
       SET WINS over the W1C clear, and the clear is the one-cycle action pulse in the domain that OWNS the flop, never an async clear from a decode.
       Comparing against '1' rather than OR-ing the term in keeps a metavalue on an unselected input line from ever poisoning a flag.
       FIRED/OVR are gated by ch_arm; EVSTAT is UNGATED by EN/CHEN and records every raw event, which is what makes a post-mask tap violation testable. */
    stickies : process(resetn, clk)
    begin
        if resetn = '0' then
            fired  <= (others => '0');
            ovr    <= (others => '0');
            evstat <= (others => '0');
        elsif rising_edge(clk) then
            for n in 0 to N_CH-1 loop
                if ch_fire(n) = '1' then
                    fired(n) <= '1';
                elsif clr_fired(n) = '1' then
                    fired(n) <= '0';
                end if;
                if ovr_set(n) = '1' then
                    ovr(n) <= '1';
                elsif clr_ovr(n) = '1' then
                    ovr(n) <= '0';
                end if;
            end loop;
            for e in 0 to N_EV-1 loop
                if ev_eff(e) = '1' then
                    evstat(e) <= '1';
                elsif clr_evstat(e) = '1' then
                    evstat(e) <= '0';
                end if;
            end loop;
        end if;
    end process stickies;

end architecture behavioral;
