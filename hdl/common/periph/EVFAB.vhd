library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ===========================================================================
-- EVFAB: event/trigger fabric (PPI-style crossbar).
-- Peripheral #12 of the digital-peripheral library, ONE instance, EVFAB0 @ 0x6B00.
-- Zero pins, vectorless v1 (irq_evfab is a constant '0', D20).
-- FROZEN design: ~/vesta_docs/digperiphs/event_fabric_design.md (decisions D1-D25 plus the FABLE ADJUDICATION rulings, ALL BINDING; a ruling overrides any conflicting Dn text).
-- Structural template = TRNG/RTC/OneWire (bus + register-file idiom).
-- The NEW mechanism this block introduces is the D3 ACTION PATH: a once-per-select-window write decoder living in the `clk` domain instead of the register file's `ClkMem` domain.
-- -V200X only: NO VHDL-2008 (no process(all), no unary reduce, no reading of an out port, no external names).
-- Every process infers exactly ONE edge of ONE clock; no latch, no clock gate, no falling_edge of anything (least of all EnMemPeriph), no async clear other than `resetn` in each process's own reset branch, no `case`/integer index on any select field.
--
-- D1/D2: ONE clock family.
-- `clk` (MCLK at integration) is FREE-RUNNING and hosts the WHOLE fabric: the event front-end, the GPIO0 front-end, the crossbar, the single output register, every sticky flag AND the D3 action path.
-- `ClkMem` hosts ONLY the register-file storage and the registered read mux.
-- At integration ClkMem IS mclk (MCU.vhd drives ClkMem from mclk, with select = the EnMemPeriph strobe); the binding assumption is only that ClkMem's edges are a SUBSET of clk's, same phase, which holds trivially.
-- Hence every hand-off between the ClkMem and clk domains here is a bare held level (quasi-static config out, clk-domain flags into the read mux), never a toggle, never a 2-FF sync: they are the same net (FABLE ADJUDICATION, Q4).
-- EVFAB0 sits in the always-on shared domain: WFI keeps mclk alive, DP-S3 field-power only slows it, PWRCTRL never gates it, so chains fire with the bus idle, which is the entire point of the block (proven by the bench's frozen-ClkMem G9 leg).
--
-- D3: ACTION PARTITION, the subtlest thing in this block. Two disjoint slot sets, no overlap:
--   * ClkMem register file  : slots 0 CR, 4 CHEN, 5 CHENSET, 6 CHENCLR, 15 EVGPIOMASK, 16-31 CHnCFG.
--     Plain synchronous writes, EnMemPeriph- and lane-0-qualified.
--     A held select window spans MULTIPLE live ClkMem edges, so these writes REPEAT every edge, harmless ONLY because every one of them is idempotent by construction (w1s / w1c / plain store).
--   * clk ACTION path (B5)  : slots 7 CHTRIG, 8 FIRED(W1C), 9 OVR(W1C), 10 EVSTAT(W1C), 11 EVTRIG.
--     These are non-idempotent: one write must produce EXACTLY ONE injection or clear however long the select is held, so they are decoded ONCE per select window by a rising-edge detector on the decoded-write LEVEL, in the free-running clk domain.
--     An arm flop on ClkMem could NOT re-arm between two back-to-back writes to the same slot (no ClkMem edge exists while deselected) and would silently swallow the second injection; clk keeps running, so it re-arms.
--     The payload is snapshotted at the FIRST clk edge that sees the level, two edges before the pulse, because at integration the arbiter re-drives sh_wdata for the next master as soon as the access retires.
--
-- D4: bus contract, xcollapse-clean by construction (xcollapse_findings.md ROOT-1/2/3).
-- EnMemPeriph is consumed ONLY as an ACTIVE-LOW LEVEL, sampled on rising ClkMem (register file) and on rising clk (action path).
-- It is never a clock and never an edge; the EVFAB SDC has NO EnMemPeriph clock.
-- Registered read on rising ClkMem, no pre-latch, no MCU-side bridge, NOT in the CAPTURE_CLOCK shim set.
-- No clock gate anywhere in the block, so nothing the fabric samples can ever reach a clock-gate enable (ROOT-3).
-- No read side effects anywhere: no clear-by-read, no claim-on-read.
--
-- D5: action-visibility latency (driver + bench contract).
-- A CHTRIG/EVTRIG/W1C write takes effect 3 clk edges after its select window opens (2 sync + 1 apply), and a read issued sooner sees STALE state.
-- At integration a shared-window access costs ~5 mclk, so this is unobservable; the standalone bench inserts evfab_settle (4 clk).
-- Documented in the TRM driver section.
--
-- Register map (D18; base 0x6B00, slot n @ 0x6B00 + 4n, off MABPart(7:2)):
--    0 EVFCR       rw  [0] EN global kill (reset 0); 31:1 reserved r0
--    1 EVFSR       ro  [0] FIREDIF = OR(FIRED); [1] OVRIF = OR(OVR); 31:2 r0
--    2 EVFIE       reserved: reads 0, writes ignored (vectorless v1, D20)
--    3 EVFCAP      ro  [7:0] N_CH [15:8] N_EV [23:16] N_TASK [31:24] VER (D19)
--    4 EVFCHEN     rw  [N_CH-1:0] channel enables (reset 0)
--    5 EVFCHENSET  w1s, READS CHEN     6 EVFCHENCLR  w1c, READS CHEN
--    7 EVFCHTRIG   w1-inject at the CHANNEL, honors EN+CHEN (D16); reads 0
--    8 EVFFIRED    W1C sticky "channel n fired"            (set wins, D14)
--    9 EVFOVR      W1C sticky overrun                      (set wins, D15)
--   10 EVFEVSTAT   W1C sticky raw-event record, UNGATED by EN/CHEN (D14)
--   11 EVFEVTRIG   w1-inject a RAW EVENT (D17); reads 0
--   12-14 reserved r0 (earmarked TKSTAT / FIREDIE / OVRIE)
--   15 EVFGPIOMASK rw  [7:0] per-bit enable for the GPIO0 edge path (D10)
--   16+n EVFCHnCFG rw  [4:0] EVSEL (31 = NONE); [11:8] TASKSEL;
--                      [31] ENR = RO mirror of CHEN(n); other bits r0
--   32-63 reserved r0
-- Every write is lane-0 qualified (WEn(0)='0', house idiom); reserved bits ignore writes and read 0; CHnCFG slots with n >= N_CH read 0 and ignore writes; EVSTAT bits >= N_EV read 0.
--
-- Architecture (block summary, B1-B6, matching the design doc's grouping):
--   B1 register file (ClkMem) : slot decode, the D3-ClkMem write process, the
--      registered read mux (CR/SR/CAP/CHEN/FIRED/OVR/EVSTAT/EVGPIOMASK/CHnCFG).
--   B2 event front-end (clk)  : the uniform 3-flop chain plus mode select (D9).
--   B3 GPIO0 front-end (clk)  : 8x 2-FF plus rising edge, AND EVGPIOMASK,
--      OR-reduced into event EV_GPIO_IDX (D10). AND-BEFORE-OR is load-bearing.
--   B4 crossbar + output register (clk) : one-hot equality decode plus AND-OR
--      reduction, the ch_arm gate, the SINGLE task_pulse flop (D11-D13).
--   B5 ACTION path (clk)      : bus snapshot, wr_pulse and slot decode (D3).
--   B6 stickies (clk)         : FIRED / OVR / EVSTAT, set-wins (D14/D15).
--
-- D11: the crossbar is a ONE-HOT EQUALITY DECODE plus AND-OR reduction and NEVER a `case` or integer index.
-- That is an X-safety decision, not a style one: VHDL '=' on a metavalue returns FALSE, so an X in EVSEL/TASKSEL yields an ALL-ZERO one-hot (the channel is simply inert, with no index range error and no X on task_pulse), and an X on an UNSELECTED input line is killed by the AND with that zero one-hot bit before it reaches the OR tree.
-- EVSEL=31 (NONE), any reserved EVSEL 16..30 and any TASKSEL >= N_TASK need NO special case: they structurally match nothing.
--
-- D23: integration tie-off. Every unused ev_in / gpio0_evin / task_busy bit MUST be tied '0' in MCU.vhd (generator emission), never left open.
-- ===========================================================================

entity EVFAB is
    generic (
        N_CH        : natural := 8;     -- LIVE channels (register array is 16 addresses, D18)
        N_EV        : natural := 16;    -- LIVE event lines = ev_in width (encode space 32, D11)
        N_TASK      : natural := 10;    -- LIVE task lines = task_pulse/task_busy width
                                        --   (encode space 16, D11)
        EV_GPIO_IDX : natural := 15;    -- event ID served by the GPIO0 front-end (D10)
        EV_MODE_TGL : std_logic_vector(31 downto 0) := X"00000370";  -- T inputs: EV 4,5,6,8,9
        EV_MODE_LVL : std_logic_vector(31 downto 0) := X"00002000";  -- L inputs: EV 13
                                        -- (bit clear in BOTH masks = P, pulse pass-through; D7)
        VER         : natural := 1      -- CAP.VER
    );
    port (
        clk         : in  std_logic;                     -- FREE-RUNNING mclk (D1): front-end,
                                                         -- crossbar, output reg, stickies,
                                                         -- ACTION path
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_evfab   : out std_logic;                     -- vectorless v1: constant '0' (D20)

        -- register-file slave port (RTC/DMA/TRNG house idiom, D4)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read (no bridge, D4)

        -- producer taps: ONE line per EVSEL ID (D8); mode per EV_MODE_* (D7).
        -- ev_in(EV_GPIO_IDX) is IGNORED (event 15 is generated internally, D10).
        ev_in       : in  std_logic_vector(N_EV-1 downto 0)   := (others => '0');
        gpio0_evin  : in  std_logic_vector(7 downto 0)        := (others => '0');

        -- consumer interface: levels IN (OVR only, never backpressure), one-mclk pulses OUT
        task_busy   : in  std_logic_vector(N_TASK-1 downto 0) := (others => '0');
        task_pulse  : out std_logic_vector(N_TASK-1 downto 0)  -- REGISTERED (D12)
    );
end EVFAB;

architecture behavioral of EVFAB is

    -- ---- ABI constants (NOT generics: the encode spaces never move, D6) ----
    constant EVSEL_W   : natural := 5;
    constant TASKSEL_W : natural := 4;

    -- ---- word-slot map (frozen, D18) ---------------------------------------
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
    constant CHCFG_SLOTS   : natural := 16;   -- register-array size (D18), NOT N_CH

    -- EVFCAP RO constant (D19): VER & N_TASK & N_EV & N_CH, LIVE line counts.
    constant CAP_CONST : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(VER,    8)) &
        std_logic_vector(to_unsigned(N_TASK, 8)) &
        std_logic_vector(to_unsigned(N_EV,   8)) &
        std_logic_vector(to_unsigned(N_CH,   8));

    -- ---- B1 register-file storage (ClkMem domain, D3) ----------------------
    type evsel_arr_t   is array (0 to N_CH-1) of std_logic_vector(EVSEL_W-1   downto 0);
    type tasksel_arr_t is array (0 to N_CH-1) of std_logic_vector(TASKSEL_W-1 downto 0);

    signal cr_en       : std_logic;                       -- CR.EN, the global kill (D13)
    signal chen        : std_logic_vector(N_CH-1 downto 0);
    signal gpiomask    : std_logic_vector(7 downto 0);    -- EVGPIOMASK (D10)
    signal cfg_evsel   : evsel_arr_t;
    signal cfg_tasksel : tasksel_arr_t;

    signal slot : natural range 0 to 63;                  -- decoded word slot (level, D4)

    -- ---- B5 ACTION path (clk domain, D3) -----------------------------------
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

    -- ---- B2 event front-end (clk domain, D9) -------------------------------
    -- Uniform 3-flop chain for EVERY event input.
    -- The mode select downstream is elaboration-static, so the P-mode chains lose their reader and are constant-folded away by synthesis (~30 of the 48 declared flops).
    signal ev_s1, ev_s2, ev_prev : std_logic_vector(N_EV-1 downto 0);
    signal ev_front              : std_logic_vector(N_EV-1 downto 0);
    signal ev_eff                : std_logic_vector(N_EV-1 downto 0);

    -- ---- B3 GPIO0 front-end (clk domain, D10) ------------------------------
    signal gp_s1, gp_s2, gp_prev : std_logic_vector(7 downto 0);
    signal gp_masked             : std_logic_vector(7 downto 0);   -- edge AND mask, PER BIT
    signal gp_event              : std_logic;             -- OR-reduced, drives event EV_GPIO_IDX

    -- ---- B4 crossbar (clk domain, D11-D13) ---------------------------------
    signal ch_fire   : std_logic_vector(N_CH-1 downto 0);
    signal task_hit  : std_logic_vector(N_TASK-1 downto 0);
    signal ovr_set   : std_logic_vector(N_CH-1 downto 0);

    -- ---- B6 stickies + SR reductions (clk domain, D14/D15/D20) -------------
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
    -- Slot decode: an EnMemPeriph-qualified LEVEL (D4), never an edge.
    -- Parked at 0 while deselected so no stale slot can leak into either domain.
    slot <= to_integer(unsigned(MABPart)) when EnMemPeriph = '0' else 0;

    -- D20, vectorless v1: the IRQ net is a hard constant.
    -- Spending a vector later means implementing slot 2 (IE), driving this net, and sweeping the router.
    irq_evfab <= '0';

    -- ------------------------- B1: register write (ClkMem, D3) --------------
    -- Rising ClkMem, EnMemPeriph='0' AND lane-0 qualified (D4/D18).
    -- EVERY slot handled here is IDEMPOTENT (plain store / w1s / w1c), so the repeated edges of a held select window are harmless, and that idempotence is the whole justification for keeping these out of the B5 action path.
    -- Slots 7-11 (the action set) and 1/2/3/12/13/14/32-63 fall through as no-ops here; CHnCFG slots with n >= N_CH match nothing and are ignored.
    reg_write : process(resetn, ClkMem)
    begin
        if resetn = '0' then
            cr_en    <= '0';                    -- global kill asserted out of reset (D21)
            chen     <= (others => '0');        -- second, independent gate (D21)
            gpiomask <= (others => '0');        -- GPIO0 path inert AND X-absorbing (D10/D21)
            for n in 0 to N_CH-1 loop
                cfg_evsel(n)   <= (others => '0');   -- harmless: double-gated (D21/Q5)
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

    -- ------------------------- B1: register read (ClkMem, D4) ---------------
    -- Registered read mux on rising ClkMem.
    -- The clk-domain flags (FIRED / OVR / EVSTAT and the SR reductions) are sampled BARE: ClkMem and clk are the same net at integration, so this is a plain timed path, not a CDC (D2/Q4).
    -- Reserved slots and bits read 0; CHENSET/CHENCLR both mirror CHEN; CHTRIG/EVTRIG read 0; no read has any side effect.
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
                    -- LIVE RO reductions so firmware polls ONE word (D20).
                    -- Reduced HERE, inside the read mux, rather than through an intermediate combinational net: that keeps SR bit-consistent with the FIRED/OVR words sampled by this same edge no matter how the ClkMem net is derived from clk (raw at integration, gated in the bench).
                    -- Neither FIREDIF nor OVRIF is state.
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

    -- ------------------------- B5: ACTION path (clk, D3) --------------------
    -- The decoded-write LEVEL.
    -- Pure DATA: combinational, EnMemPeriph-and-lane-0 qualified, and NEVER used as a clock or an edge (D4).
    -- A read leaves WEn = "1111", so reads never enter this path.
    bus_wr_lvl <= '1' when (EnMemPeriph = '0' and WEn(0) = '0') else '0';

    -- ONE shared bus snapshot plus ONE rising-edge detector in the FREE-RUNNING clk domain (D3), giving exactly one action per select window:
    --   * held write  = exactly ONE action, however long the level holds;
    --   * back-to-back writes in SEPARATE accesses = one action EACH, because the level drops while deselected and clk keeps running so the detector re-arms, the property a ClkMem-clocked arm flop cannot provide;
    --   * PAYLOAD BEFORE FLAG: the snapshot is taken at the FIRST clk edge that sees the level and the pulse arrives two edges later, so the action never samples a raw `wdata` that the arbiter has already re-driven for the next master.
    -- Limitation, never produced by the MCU fabric: two writes with NO intervening deselect collapse to ONE action carrying the LAST payload.
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
                bus_wdata_q <= wdata;             -- payload snapshot (D3)
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

    -- Per-bit action strobes, each ONE clk wide (D3).
    -- The clears being one-cycle PULSES rather than the held write level is exactly what makes a held W1C unable to eat an event that arrives mid-write (D14).
    gen_act_ch : for n in 0 to N_CH-1 generate
        chtrig_pulse(n) <= act_chtrig and bus_wdata_q(n);   -- D16
        clr_fired(n)    <= act_fired  and bus_wdata_q(n);
        clr_ovr(n)      <= act_ovr    and bus_wdata_q(n);
    end generate gen_act_ch;

    gen_act_ev : for e in 0 to N_EV-1 generate
        ev_inject(e)  <= act_evtrig and bus_wdata_q(e);     -- D17
        clr_evstat(e) <= act_evstat and bus_wdata_q(e);
    end generate gen_act_ev;

    -- ------------------------- B2/B3: input front-ends (clk, D9/D10) --------
    -- ONE uniform 3-flop chain per event input AND per GPIO0 pad bit, with no if-generate on mode, so the RTL is one loop; the P-mode chains lose their reader after the elaboration-static mode select below and are removed by synthesis.
    -- All chains reset to 0, so a T input already HIGH at reset release produces NO phantom pulse (s2 = prev = 0, so the XOR is 0, and the first genuine flip fires).
    -- ev_in/gpio0_evin are PURE DATA here: never a clock, never an async clear (ROOT-3).
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

    -- B3 (D10): the GPIO0 path is a per-bit rising edge, ANDed with EVGPIOMASK, then OR-reduced into event EV_GPIO_IDX.
    -- gpio0_evin carries RAW PRE-MASK pad levels (clk_if_comb) and PxIE is never consulted.
    -- AND-BEFORE-OR IS LOAD-BEARING (ROOT-3): at chip level an unbonded or undriven GPIO0 pad is X, and '0' and 'X' is '0', so a masked-off bit ABSORBS the X before the OR tree.
    -- EVGPIOMASK resets to 0, so the whole path is inert and X-absorbing out of reset.
    gen_gpio_edge : for g in 0 to 7 generate
        gp_masked(g) <= (gp_s2(g) and not gp_prev(g)) and gpiomask(g);
    end generate gen_gpio_edge;

    -- Any masked-in GPIO0 edge becomes the single internal event line.
    gp_event <= or_red(gp_masked);

    -- B2 (D9/D7): mode select, elaboration-static.
    -- EV_MODE_TGL(e)/EV_MODE_LVL(e) with `e` a generate constant is a globally static condition, so exactly one arm survives per index at synthesis:
    --   T: one pulse per FLIP, both directions (XOR of the last two samples)
    --   L: one pulse on the RISING edge only; a level that stays high forever fires exactly once
    --   P: pass-through, NO flop, latency 1 preserved. CONTRACT: a P input MUST be a ONE-mclk pulse in the clk domain, since a 2-cycle P input fires its channels twice, by design.
    -- TGL wins over LVL if a bit is set in both (illegal config; documented, not checked).
    -- Index EV_GPIO_IDX is OVERRIDDEN by the B3 path above and its ev_in bit is ignored entirely (tie '0' at MCU, D10/D23).
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

    -- D17: an EVTRIG-injected event is indistinguishable from a real tap.
    -- It is recorded by EVSTAT even with CR.EN=0 (upstream of the gate) and reaches the crossbar exactly like a producer pulse, which makes the whole matrix testable from firmware with no producer hardware.
    ev_eff <= ev_front or ev_inject;

    -- ------------------------- B4: crossbar (clk, D11-D15) ------------------
    -- One-hot EQUALITY decode plus AND-OR reduction throughout; NEVER a `case` or an integer index on EVSEL/TASKSEL (D11; see the header for why this is an X-safety decision).
    -- Input-side gating (D13): ch_arm = CR.EN and CHEN(n) is applied BEFORE the task OR and before FIRED/OVR, so a disabled channel is COMPLETELY inert, with no pulse, no FIRED and no OVR.
    -- EVSTAT is upstream of this gate and still records (D14).
    -- CHTRIG (D16) enters INSIDE the arm gate, so a CHTRIG to a disabled channel does nothing and a CHTRIG fire is indistinguishable downstream from an event fire.
    -- OVR (D15) means "the pulse was DEGRADED", never backpressure: task_busy is a clk-domain LEVEL sampled bare and NEVER gates, delays or suppresses task_pulse.
    -- Its set term is consumer busy OR a same-cycle same-task merge, symmetric across all colliding channels (the fabric cannot say which one "won").
    -- The `inrange` term implements D15 corner 5: TASKSEL >= N_TASK decodes to no line, so FIRED still sets but there is no pulse and no phantom OVR (no busy line exists to overrun).
    crossbar : process(cr_en, chen, cfg_evsel, cfg_tasksel, ev_eff,
                       chtrig_pulse, task_busy)
        variable ev_hit_v  : std_logic;
        variable fire_v    : std_logic_vector(N_CH-1 downto 0);
        variable hit_v     : std_logic_vector(N_TASK-1 downto 0);
        variable inrange_v : std_logic;
        variable busy_v    : std_logic;
        variable merge_v   : std_logic;
    begin
        -- per channel: one-hot EVSEL match, then the arm gate (D11/D13/D16)
        for n in 0 to N_CH-1 loop
            ev_hit_v := '0';
            for e in 0 to N_EV-1 loop
                if cfg_evsel(n) = std_logic_vector(to_unsigned(e, EVSEL_W)) then
                    ev_hit_v := ev_hit_v or ev_eff(e);
                end if;
            end loop;
            fire_v(n) := (cr_en and chen(n)) and (ev_hit_v or chtrig_pulse(n));
        end loop;

        -- per task: one-hot TASKSEL reduce (D11).
        -- Several channels selecting the same task in the same cycle produce ONE merged pulse.
        for t in 0 to N_TASK-1 loop
            hit_v(t) := '0';
            for n in 0 to N_CH-1 loop
                if cfg_tasksel(n) = std_logic_vector(to_unsigned(t, TASKSEL_W)) then
                    hit_v(t) := hit_v(t) or fire_v(n);
                end if;
            end loop;
        end loop;

        -- per channel: the D15 OVR set term.
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

    -- ------------------------- B4: output register (clk, D12) ---------------
    -- THE single flop between ev_eff and the consumer: in-fabric latency is exactly 1 mclk and task_pulse is a clean registered one-mclk pulse BY CONSTRUCTION, so consumers where a held level is hazardous are protected structurally rather than by contract.
    -- NO second stage, NO handshake, NO rate limit, NEVER a bus master.
    out_reg : process(resetn, clk)
    begin
        if resetn = '0' then
            task_pulse <= (others => '0');      -- glitch-free out of reset (D21)
        elsif rising_edge(clk) then
            task_pulse <= task_hit;
        end if;
    end process out_reg;

    -- ------------------------- B6: sticky flags (clk, D14/D15) --------------
    -- SET WINS over the W1C clear, and the clear is the ONE-cycle B5 pulse in the domain that OWNS the flop, never an async clear from a decode (ROOT-2).
    -- Comparing against '1' rather than OR-ing the term in keeps a metavalue on an unselected input line from ever poisoning a flag.
    -- FIRED/OVR are gated by ch_arm (D13); EVSTAT is UNGATED by EN/CHEN (D14) and records every raw event, which is what makes a post-mask tap violation testable.
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
