-- =============================================================================
-- hart_tile.vhd  (M3b; M11 memory-map rework; M12 single-ROM boot; M13 tile)
-- =============================================================================
-- One self-contained hart with PRIVATE memory: a vesta core, its own address decoder and its private TCM (RAM0, 0x8000-0xBFFF).
-- M11 retired the tile's dead boot ROM and its private RAM1 (0xC000 is now the SHARED NPU staging RAM behind the arbiter).
-- M12 retired the preloaded-TCM boot fiction: every hart resets to PC 0x0 and fetches the SHARED boot ROM through the arbiter, and the bootrom's mhartid dispatch parks tiles until hart 0 ignites them via CLINT msip.
-- Everything except the TCM reaches the MCU control plane through the shared-window master port below.
--
-- M13 TILE EXTRACTION: this entity is now THE hart tile for ALL FOUR harts, hart 0 included.
-- MCU.vhd's inline hart-0 core/adddec/ram0/sh-machinery was this file's mirror since M3c; it is folded in here and deleted there.
-- All four instances are STRUCTURALLY IDENTICAL (one netlist becomes one hardened tile in M14); every per-instance difference is expressed by WIRING only:
--   * hart_id      mhartid CSR value, now a PORT (the vesta HARTID generic is
--                  retired for the same one-netlist reason).
--   * flash/XIP    the adddec >=0x20000 extended-flash decode is enabled in EVERY tile.
--                  Hart 0 wires flash_mem_en/flash_clk_mem/flash_mab/flash_dout to SPI0, and sleep to SPI0's disable_clk_cpu (XIP stall).
--                  Tiles 1-3 leave the outputs open and the inputs at their defaults, so a tile access >=0x20000 reads ZEROS and never stalls (the XIP stall is SPI0's sleep, not adddec), the same "undefined on unmapped" class as always.
--                  The flash ports and sleep are NOT boundary-registered: flash_clk_mem is a GATED CLOCK, and a one-cycle-late sleep would let the core consume garbage flash_dout (they become hart-0 tile timing-budget pins in M14).
--   * IRQ source   M19: IDENTICAL on every hart, hart 0 included, since the SYSTEM0 vectored path and hw_clint_en are retired.
--                  Three per-hart level wires cross the boundary: msip and mtip from the CLINT, and meip from the irq_router's claim/complete stage (IVT slot 85 = IRQB_EXT_MEIP).
--                  All three slots are hardwire-enabled; ALL routing and masking lives in the router's per-hart rows @0x7000, which reset all-masked, so the old SYS_IRQ_EN reset semantics hold chip-wide by construction.
--                  Priority and recursion are tied off: with three live slots the in-core priority machinery constant-propagates away.
--   * tcm_pgen     hart 0's TCM keeps its BLOCKPWR software power gating (pgen_mem(1)); tiles tie '0'.
--   * pd_sleep / pd_iso_en (M17)  MTCMOS power-gating controls from pwr_ctrl for tiles 1-3; hart 0 ties both '0' (always-on).
--                  CPF hooks only, see the port comment.
-- The M2 wait_inj0 stall exerciser on hart 0's mem_ready is RETIRED here: its latency-tolerance job is done (M10 proved the protocol at boundary depths 0/1/2, and the M12 boot fetch exercises it every run).
--
-- Each tile replicates the *unchanged* single-core core-to-adddec-to-RAM path, so there is NO cross-hart grant-switching hazard on the fetch/load pipeline (see ~/vesta_docs/multicore_plan.md, "GRANT-SWITCHING HAZARD").
--
-- M3c.4: the tile is a REAL master of the MCU-level shared window (behind mp_arbiter on the free-running mclk), per the M3c wiring proven on hart 0 (see the M3c.3 post-mortem in ~/vesta_docs/multicore_plan.md):
--   * sh_sel   = decode of the SHARED regions (M11/M12): boot ROM 0x0-0x3FFF,
--                the peripheral window 0x4000-0x7FFF, the NPU staging RAM
--                0xC000-0xFFFF and the bulk RAM 0x10000-0x1FFFF = addr(31:17)=0
--                AND region /= "010".
--                Exact upper-bit qualification (31:17)=0 keeps >=0x20000 extended-flash addresses OUT of the window; a loose decode aliases flash back into it, the bug 2 class.
--   * sh_acked = one-shot handshake flop on MCLK; the stall source must run free, because a hart gated off cannot clock its own release.
--   * sh_dphase= sh_sel registered on the tile's own gated clk_cpu, BY DESIGN.
--                vesta's unified bus uses read_data as the INSTRUCTION during decode, and data_addr/sh_sel derive combinationally from it, so a raw-sh_sel read-data mux is a zero-delay oscillation (bug 4).
--                The registered select is '1' exactly during the MEMORY_WAIT data phase.
--   * mem_ready = (not sh_sel) or sh_ack_ok, which freezes the core (clk_cpu gate) for the whole arbiter transaction, inside the EXECUTE cycle.
-- M4a: sh_we carries the 4 byte-lane strobes (active-high), so sub-word shared stores (sb/sh) work; write_word is lane-positioned by the core.
--
-- CPR2 EXTERNAL TCM SLAVE PORT (R4, ~/vesta_docs/castalia_penta/cpr_architecture.md): a READ-ONLY window into this tile's TCM for the management hart, so hart 0 can read every tile's memory at a distinct chip address.
-- tcm_ext_req/addr in, tcm_ext_rdata/done out, its OWN M13 transaction set at its own depth-1 mclk boundary.
-- Full detail at the implementation below; the two contracts a READER of this file needs are:
--   * READ-ONLY IS STRUCTURAL, not a convention.
--     The external side of the ram0 mux forces WEN="1111"/GWEN='1' and drives D with zeros, so there is no encoding of the port that writes a live core's memory.
--     The user asked for reads; a write path is a coherence hazard we refuse.
--   * GATED-TILE CONTRACT (frozen as-built).
--     A power-gated tile's TCM is OFF and this port's outputs are ISO-CLAMPED TO 0 on the always-on MCU side (M17a explicit clamps, same rows as every other tile output).
--     Reads from a sleeping tile return ZEROS by design, not by accident; there is no always-on carve-out, and the management hart checks PWRSR before trusting a word.
--     AND THE PART THAT IS AN OBLIGATION ON THE MCU SIDE, NOT ON THIS FILE (CPR3, read this before wiring the aperture slaves): the SAME clamp that zeroes tcm_ext_rdata also zeroes tcm_ext_done, so a gated tile NEVER COMPLETES A TRANSACTION.
--     This is the first tile port whose transaction is initiated from OUTSIDE; every existing outbound signal (sh_req and friends) clamps to a benign "not asking", which is why the class has not come up before.
--     An aperture slave that simply waits for tcm_ext_done therefore HANGS on a sleeping tile, with the management hart stalled on the shared bus behind it.
--     The aperture slave must synthesise its own zero-completion from the pwr_ctrl row it already has (the same bit that drives the clamp), rather than waiting on a wire that is being held low on purpose.
--   * THE SELF-APERTURE CASE IS THE HARD ONE, and it is handled HERE (CPR3b, amendment A3).
--     A hart reading its OWN window issues an ordinary shared-bus load, and the MCU aperture sequencer answers it by driving THIS tile's tcm_ext_* port while holding the arbiter in LATCH (mp_arbiter s_stall).
--     The requesting core is therefore frozen on mem_ready_sh for the WHOLE arbiter transaction, which is STRICTLY LONGER than the port's own 7-mclk tx_busy window.
--     Liveness is fine (nothing in the sequencer waits on the core, see the no-deadlock note at the FSM), but the DATA is not fine unless the Q shadow is held for the whole freeze: CPR2's `tx_busy + 1` timer expired mid-freeze and the still-frozen core consumed the aperture word off live Q as its next INSTRUCTION (measured: PC 0x83E0 becoming 0x842E).
--     The hold is now released by evidence that the core has actually taken a clk_cpu edge, not by a count; full argument at THE Q SHADOW below.
--     Nothing outside this file has to know: the port protocol, the latency and the pin list are all unchanged by the fix.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;      -- word, word_array
use work.MemoryMap.all;      -- NUM_IRQS

entity hart_tile is
    generic (
        -- M12: every hart resets to 0x0 = the shared boot ROM.
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00000000";
        SH_AW          : natural := 16;  -- Shared-window word-address width; must match mp_arbiter.
                                         -- CPR8/R6: the DEFAULT moved from 15 to 16 with the promotion of the orchestrator chip (memory map v2: window 0x0-0x3FFFF, five TCM apertures, flash from 0x40000, which is also the Argus shape).
                                         -- 15 is the pre-CPR8 map (window 0x00000-0x1FFFF, flash from 0x20000), still reachable via config/castalia4.json, which BINDS the generic explicitly like every other MCU.vhd does.
                                         -- A2: this generic also DRIVES the sh_sel window decode and adddec's complementary flash decode below.

        -- Core ISA feature switches, passed straight down to vesta (see vesta.vhd).
        -- Config-driven from generate.py via the MemoryMap package constants in the hartN generic maps.
        -- THE DEFAULTS BELOW ARE LOAD-BEARING: the genus tile hardening (a bare `elaborate hart_tile`) and hdl/argus/MCU.vhd's 18 tiles pass no priv generics and take them.
        -- NOTE: all four tile instances must get the SAME values (M14).
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- X0 ISA-extension scaffolding: all default false, routed straight to the vesta core.
        -- Decode and logic are consumed from each generic's phase onward.
        ENABLE_ZICOND     : boolean := false;  -- X1 (Zicond)
        ENABLE_ZCB        : boolean := false;  -- X1 (Zcb)
        ENABLE_ZIMOP      : boolean := false;  -- X1 (Zimop/Zcmop)
        ENABLE_ZIHINT     : boolean := false;  -- X1 (Zihintpause/ntl)
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm)
        ENABLE_ZAWRS      : boolean := false;  -- X1 (Zawrs)
        ENABLE_ZABHA      : boolean := false;  -- X2 (Zabha)
        ENABLE_ZACAS      : boolean := false;  -- X2 (Zacas)
        ENABLE_ZICBOZ     : boolean := false;  -- X3 (Zicboz cbo.zero)
        ENABLE_ZCMP       : boolean := false;  -- X3 (Zcmp push/pop + moves)
        ENABLE_ZCMT       : boolean := false;  -- X3 (Zcmt table jump)
        ENABLE_ZBKB       : boolean := false;  -- X3 (Zbkb)
        ENABLE_ZBKC       : boolean := false;  -- X3 (Zbkc)
        ENABLE_ZBKX       : boolean := false;  -- X3 (Zbkx)
        ENABLE_ZKN        : boolean := false;  -- X3 (Zkn = Zknd+Zkne+Zknh)
        ENABLE_ZFINX      : boolean := false;  -- X4 (Zfinx)
        -- P-series privileged architecture, routed straight to the vesta core.
        -- All three are IMPLEMENTED (P1/P2/P3, 2026-07-28/29).
        -- K7/R-DK3 (2026-08-04) makes TRAPCSR the SHIPPED default on both chips, so the default below tracks it; see the LOAD-BEARING note above.
        ENABLE_TRAPCSR    : boolean := true;   -- P1 (standard M-mode trap CSRs + MRET)
        ENABLE_UMODE      : boolean := false;  -- P2 (U-mode; requires TRAPCSR)
        ENABLE_PMP        : boolean := false;  -- P3 (PMP/Smpmp; requires UMODE)
        PMP_ENTRIES       : integer := 16;     -- P3 (PMP entry count {8,16})
        -- D1 core-side debug mode, routed straight to the vesta core.
        -- DEFAULT FALSE, DELIBERATELY UNLIKE ENABLE_TRAPCSR ABOVE.
        -- That knob's default tracks the shipped chip; this one must NOT, because the frozen hdl/argus/ snapshot instantiates hart_tile WITHOUT naming the priv generics and therefore inherits whatever this entity says.
        -- That is exactly how the Argus suite ran TRAPCSR-ON for two days with no way to say so (F-K7-4).
        -- A debug interface silently present on a snapshot is an area and attack-surface surprise, not a convenience (method rule 15).
        -- tools/python/check_entity_defaults.py polices this.
        ENABLE_DEBUG      : boolean := false;  -- D1 (debug mode; requires TRAPCSR)
        -- Frozen debug entry vector (d1_spec.md 1), passed through unchanged.
        -- See the vesta entity for the memory-map argument for 0xBE00.
        DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00"
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        -- Hart 0: SPI0's disable_clk_cpu, which freezes the core across an XIP flash access; tiles default '0'.
        -- NOT boundary-registered, see the flash/XIP note in the header.
        sleep     : in  std_logic := '0';

        -- M13: mhartid CSR value, formerly the HARTID generic; a port keeps all four tile instances one netlist.
        -- Static per instance.
        hart_id   : in  std_logic_vector(31 downto 0);

        -- M5b: per-hart CLINT level interrupts, in the mclk domain, the same domain as this vesta's free-running clk.
        -- Its irq_handler clocks on clk, so msip/mtip can wake a hart whose gated clk_cpu is OFF in SLEEPING.
        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';

        -- M19: the external (peripheral) interrupt wire, the irq_router's registered per-hart claim/complete output.
        -- It lands on IVT slot 85 (IRQB_EXT_MEIP), and the ISR discovers the source by READING the router's CLAIM word.
        -- Replaces the M7a wide fan-out: the irq_ext / irq_en_ext / irq_prio_ext / irq_recursion_en / hw_clint_en / isr_ret ports are RETIRED, taking ~255 boundary flops and the per-tile 85-bit priority bank with them.
        meip_in   : in  std_logic := '0';

        -- D1 core-side debug interface: mclk domain, boundary-registered at the SAME depth 1 as the req/gnt set (the M13 one-depth skew rule).
        -- BOTH INPUTS DEFAULT '0' and that is the fail-safe direction: at D1 no Debug Module exists, so MCU.vhd leaves all three unconnected and every tile boots and runs exactly as it did.
        -- A '1' default would halt the chip out of reset.
        -- NOT exempted from boundary registration the way `sleep` and the flash/XIP ports are: that exception exists for a gated-clock race and must not be copied.
        dbg_haltreq      : in  std_logic := '0';
        dbg_resethaltreq : in  std_logic := '0';
        dbg_halted       : out std_logic;

        -- M13: extended-flash / XIP port (adddec's >=0x20000 decode, enabled in every tile).
        -- Hart 0 wires SPI0 here; tiles leave the outputs open and flash_dout at its zeros default.
        -- NOT boundary-registered, because of the gated clock and the sleep race (see header).
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- M3c.4: shared-window master port, feeding one mp_arbiter master slice in MCU.vhd.
        -- req/we/addr/wdata go out; gnt/done/rdata come back.
        -- req is held until done (a 1-cycle pulse); addr/wdata are stable across the wait because the core's clk_cpu is gated off while stalled.
        sh_req    : out std_logic;
        sh_we     : out std_logic_vector(3 downto 0);  -- active-high byte-lane strobes (M4a)
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');
        -- M4b: global LR/SC. Transaction tag out ("01" LR read, "10" SC write attempt), resv_unit SC verdict in (valid with sh_done, latched here).
        sh_lrsc   : out std_logic_vector(1 downto 0);
        sh_scfail : in  std_logic := '0';
        -- X1 Zawrs: this hart's GLOBAL reservation-valid level from resv_unit, a level valid every cycle, boundary-registered like sh_scfail.
        -- The Zawrs wait wakes when it drops to '0', meaning a foreign store killed the LR.
        -- Defaults '1' so a single-master top is a no-op.
        sh_resv_valid : in std_logic := '1';
        -- M8: grant-lock request to mp_arbiter, the core's amo_lock, held high for the whole AMO read-modify-write flow so the arbiter pins the grant to this hart between the AMO's read and write transactions.
        sh_lock   : out std_logic;

        -- M13: TCM macro power gate.
        -- Hart 0 takes BLOCKPWR's RAMOFF via pgen_mem(1), preserving software power gating; tiles tie '0'.
        tcm_pgen  : in  std_logic := '0';

        -- PG1 (2026-07-10): TCM retention control, strapped '1' (retention disabled) from the ALWAYS-ON MCU top.
        -- It was an in-tile TIEHI on the switched rail, but the macro's RETN receiver is on the always-on rail (PG1 finding F2: a dying tie meant a sleep-long crowbar in the macro plus uncommanded retention-mode entry).
        -- A port also gives a future retention stage (M18) its sequencing hook for free.
        tcm_retn  : in  std_logic := '1';

        -- =====================================================================
        -- CPR2 (R4): READ-ONLY EXTERNAL TCM SLAVE PORT.
        -- mclk domain, boundary-registered at the SAME depth 1 as the req/gnt set, but it is its OWN transaction set, exactly like the D1 debug trio.
        -- The M13 one-depth rule is about SKEW BETWEEN SIGNALS IN ONE TRANSACTION, and nothing here shares a transaction with sh_*.
        --
        -- PROTOCOL (the sh_done shape, deliberately): tcm_ext_req is held until tcm_ext_done; tcm_ext_done is a ONE-mclk PULSE and tcm_ext_rdata is VALID WITH IT (value-with-pulse, like sh_rdata / sh_scfail), then HOLDS until the next completion.
        -- tcm_ext_addr is a TCM WORD index (12 bits = the ram0 A bus = data_addr(13:2)), so word i is the core's byte address 0x8000 + 4*i.
        --   AND THE HALF OF THAT CONTRACT THAT IS EASY TO DROP: after done, tcm_ext_req MUST RETURN LOW FOR AT LEAST ONE mclk before the next request.
        --   The sequencer's one-shot (tx_served) rearms on req being low, exactly the relationship sh_acked has with sh_sel, so a requester that holds req high across two transactions gets ONE done and then waits forever.
        --   CPR3's aperture slave must deassert between accesses; tcm_port_tb's T5d is the standing check that one idle cycle is enough.
        --
        -- ALL THREE INPUTS CARRY DEFAULTS AND THE DEFAULTS ARE THE FAIL-SAFE DIRECTION (hard rule 4, cpr_architecture.md 3): every EXISTING hart_tile instantiation, meaning MCU.vhd's four tiles, the frozen hdl/argus/ snapshot's eighteen and dbg_iface_tb's two, names none of these ports and must keep compiling and behaving BIT-IDENTICALLY until CPR3 wires them.
        -- tcm_ext_req = '0' is "nobody is asking", which leaves the stall term below constant '0' and the ram0 mux constant on the core side.
        --
        -- NOT knob-gated: this is the memory architecture, not a feature (R4).
        -- Its boundary flops move the genus `sequential` pin ONCE, at the CPR5 re-harden, and the pin is re-measured there.
        -- =====================================================================
        tcm_ext_req   : in  std_logic := '0';
        tcm_ext_addr  : in  std_logic_vector(11 downto 0) := (others => '0');
        tcm_ext_rdata : out std_logic_vector(31 downto 0);
        tcm_ext_done  : out std_logic;

        -- M17: MTCMOS domain controls; no tile RTL logic consumes them.
        -- pd_sleep is the CPF hook (cpf/hart_tile.cpf) and drives the HEAD switch fabric's SLEEP daisy chain (pmk sense: ACTIVE-HIGH means the switched rail is OFF).
        -- pd_iso_en is RESERVED at tile level (in-tile iso is the M17b option): the M17a output clamps are EXPLICIT RTL AND gates on the ALWAYS-ON MCU side of the boundary, keyed by the same pwr_ctrl row, because genus cannot insert location-to iso for a block whose 'to' domain is the outside world (CPI-319).
        -- Driven per tile by pwr_ctrl (slot 11, 0x4B00); hart 0 ties both '0' (always-on), so all four instances stay ONE netlist (the M13 wiring-only rule).
        -- NOT boundary-registered: always-on-domain controls must stay valid while every flop in the switched domain is dark.
        -- The accompanying cold-gate reset arrives through the ordinary resetn port (pwr_ctrl's pd_rstn ANDed in at the top), which is what makes reset values equal clamp-0 values on every outbound signal.
        pd_sleep  : in  std_logic := '0';
        pd_iso_en : in  std_logic := '0';

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of hart_tile is

    -- The vesta core (M13: hart_id is a port, the HARTID generic is retired).
    component vesta
        generic (
            PC_RST_VAL : std_logic_vector(31 downto 0);
            NUM_IRQS  : natural;
            ENABLE_MUL        : boolean := true;
            ENABLE_DIV        : boolean := true;
            ENABLE_ATOMICS    : boolean := true;
            ENABLE_COMPRESSED : boolean := true;
            ENABLE_BITMANIP   : boolean := true;
            -- X0 ISA-extension scaffolding (all default false)
            ENABLE_ZICOND     : boolean := false;
            ENABLE_ZCB        : boolean := false;
            ENABLE_ZIMOP      : boolean := false;
            ENABLE_ZIHINT     : boolean := false;
            ENABLE_ZIHPM      : boolean := false;
            ENABLE_ZAWRS      : boolean := false;
            ENABLE_ZABHA      : boolean := false;
            ENABLE_ZACAS      : boolean := false;
            ENABLE_ZICBOZ     : boolean := false;
            ENABLE_ZCMP       : boolean := false;
            ENABLE_ZCMT       : boolean := false;
            ENABLE_ZBKB       : boolean := false;
            ENABLE_ZBKC       : boolean := false;
            ENABLE_ZBKX       : boolean := false;
            ENABLE_ZKN        : boolean := false;
            ENABLE_ZFINX      : boolean := false;
            -- P0 privileged-architecture scaffolding (all default false / 16)
            ENABLE_TRAPCSR    : boolean := false;
            ENABLE_UMODE      : boolean := false;
            ENABLE_PMP        : boolean := false;
            PMP_ENTRIES       : integer := 16;
            ENABLE_DEBUG      : boolean := false;
            DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00"
        );
        port (
            clk              : in  std_logic;
            resetn           : in  std_logic;
            sleep            : in  std_logic;
            clk_cpu          : out std_logic;
            hart_id          : in  std_logic_vector(31 downto 0);

            data_addr        : out std_logic_vector(31 downto 0);
            wen              : out std_logic_vector(3 downto 0);
            write_data       : out std_logic_vector(31 downto 0);
            read_data        : in  std_logic_vector(31 downto 0);
            mask             : in  std_logic_vector(1 downto 0);
            mem_ready        : in  std_logic := '1';

            lr_sc_bus        : out std_logic_vector(1 downto 0);
            sc_fail_ext      : in  std_logic := '0';
            resv_valid_ext   : in  std_logic := '1';
            amo_lock         : out std_logic;

            irq_vector      : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_priority    : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_en          : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_recursion_en: in  std_logic;
            isr_ret         : out std_logic;

            -- D1 debug interface (inert defaults; see the vesta entity)
            dbg_haltreq      : in  std_logic := '0';
            dbg_resethaltreq : in  std_logic := '0';
            dbg_halted       : out std_logic;

            trap_flag        : out  std_logic;

            a0               : out std_logic_vector(31 downto 0)
        );
    end component;

    component adddec is
        generic (
            ENABLE_FLASH_EXTENDED_MEM : boolean := false;
            SH_AW                     : natural := 15
        );
        port (
            clk               : in  std_logic;
            resetn            : in  std_logic;

            wen               : in  std_logic_vector(3 downto 0);
            data_addr         : in  std_logic_vector(31 downto 0);
            write_word        : in  std_logic_vector(31 downto 0);
            mask              : out std_logic_vector(1 downto 0);

            write_data        : out std_logic_vector(31 downto 0);
            read_data         : out std_logic_vector(31 downto 0);
            mem_addr          : out std_logic_vector(11 downto 0);
            addr_periph       : out std_logic_vector(7 downto 2);
            mab_out           : out std_logic_vector(31 downto 0);
            wen_fe            : out std_logic_vector(3 downto 0);
            GWEN              : out std_logic;

            mem_en            : out std_logic_vector(2 downto 0);
            mem_en_periph     : out std_logic_vector(15 downto 0);
            clk_mem           : out std_logic_vector(2 downto 0);
            clk_periph        : out std_logic_vector(15 downto 0);

            mem_en_flash      : out std_logic;
            clk_mem_flash     : out std_logic;

            mem_dout          : in word_array(0 to 2);
            periph_dout       : in word_array(0 to 15);
            flash_dout        : in std_logic_vector(31 downto 0)
        );
    end component;

    -- constant tie-offs
    constant zero_periph : word_array(0 to 15)                  := (others => (others => '0'));

    -- A2: SH_AW-derived all-zero comparators for the sh_sel decode below.
    -- SH_WIN_ZERO qualifies the whole window (addr(31:SH_AW+2) = 0).
    -- SH_TCM_ZERO qualifies the TCM carve-out's upper bits (addr(SH_AW+1:16) = 0), one bit at the Castalia SH_AW=15 and two at the Argus SH_AW=16.
    constant SH_WIN_ZERO : std_logic_vector(31 downto SH_AW+2) := (others => '0');
    constant SH_TCM_ZERO : std_logic_vector(SH_AW+1 downto 16) := (others => '0');

    -- M19: exactly three live IVT slots, meip (85) plus the CLINT pair (83/84), all hardwire-enabled.
    -- Every other slot is constant '0' in BOTH the vector and the enables, so synthesis prunes the core's NUM_IRQS-wide priority encoder and in-service tracking down to the three live sources.
    -- Routing and masking live in the irq_router rows.
    constant TILE_IRQ_EN : std_logic_vector(NUM_IRQS-1 downto 0) :=
        (IRQB_EXT_MEIP => '1', IRQB_CLINT_MSIP => '1', IRQB_CLINT_MTIP => '1',
         others => '0');
    -- Priority all-low and recursion off, both fixed (the SYSTEM0 knobs are retired).
    constant TILE_IRQ_PRI : std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');

    signal tile_irq_vec  : std_logic_vector(NUM_IRQS-1 downto 0);

    -- M9b/M12: delayed core reset release, held until the boot fetch has landed in the clk_cpu consumption stage (see core_rst_stretch below).
    signal boot_fetched   : std_logic := '0';
    signal resetn_core    : std_logic;

    -- Private bus between the core and adddec.
    signal clk_cpu     : std_logic;
    signal data_addr   : std_logic_vector(31 downto 0);
    signal wen_re      : std_logic_vector(3 downto 0);
    signal write_word  : std_logic_vector(31 downto 0);
    signal read_data   : std_logic_vector(31 downto 0);
    signal mask        : std_logic_vector(1 downto 0);

    -- Bus between adddec and the private memory.
    signal write_data  : std_logic_vector(31 downto 0);
    signal mem_addr    : std_logic_vector(11 downto 0);
    signal addr_periph : std_logic_vector(7 downto 2);
    signal wen_fe      : std_logic_vector(3 downto 0);
    signal GWEN        : std_logic;
    signal mem_en      : std_logic_vector(2 downto 0);
    signal clk_mem     : std_logic_vector(2 downto 0);
    signal mem_dout    : word_array(0 to 2);

    -- unused decoder outputs (private peripheral side, dead since M11)
    signal mem_en_periph : std_logic_vector(15 downto 0);
    signal clk_periph    : std_logic_vector(15 downto 0);

    -- M3c.4: shared-window master state
    signal sh_sel         : std_logic;
    signal sh_dphase      : std_logic := '0';  -- clk_cpu-domain: shared access in data phase
    signal sh_acked       : std_logic := '0';
    signal sh_acked_we    : std_logic_vector(3 downto 0) := (others => '0'); -- lanes of the acked txn (M4b)
    signal sh_acked_addr  : std_logic_vector(SH_AW-1 downto 0) := (others => '0'); -- word addr of the acked txn (M10)
    signal sh_ack_ok      : std_logic;          -- ack valid FOR THE CURRENT ACCESS TYPE
    signal sh_we_lanes    : std_logic_vector(3 downto 0);
    signal sh_rdata_reg   : std_logic_vector(31 downto 0) := (others => '0');
    -- M10: clk_cpu-STAGED copy of sh_rdata_reg, the value the core actually consumes.
    -- sh_rdata_reg is an mclk landing register: when the core EXECUTES FROM the shared window it is frozen in EXECUTE consuming sh_rdata_reg as its INSTRUCTION while the next transaction (data load or next fetch) completes and overwrites it MID-CYCLE, so the executing instruction flips under the core's feet.
    -- Found by shexec; the private RAM never does this because its Q only updates at the core's own gated memory-clock edges.
    -- The clk_cpu stage replicates exactly that Q contract: it freezes with the core and picks up the landed value at the stall-ending edge, cycle-identical to the old direct consumption for all data-only traffic (one completion per stretched cycle).
    signal sh_rdata_cpu   : std_logic_vector(31 downto 0) := (others => '0');
    signal sh_scfail_reg  : std_logic := '0';   -- resv_unit SC verdict, latched at done (M4b)
                                                -- NOT staged: SC_CHECK consumes the verdict in its own stretched cycle, at the end edge.
    signal core_read_data : std_logic_vector(31 downto 0);
    signal mem_ready_sh   : std_logic;
    signal lr_sc_bus      : std_logic_vector(1 downto 0);

    -- =========================================================================
    -- M13 REGISTERED TILE BOUNDARY (depth 1, mclk).
    -- Every shared-bus signal and every IRQ/CLINT level crosses the tile edge through EXACTLY ONE register stage: outbound req/we/addr/wdata/lrsc/lock, inbound gnt/done/rdata/scfail plus msip/mtip/meip (M19 shrank the inbound IRQ stage from the 3xNUM_IRQS-wide vector/enable/priority banks to these three level wires).
    -- ONE depth for ALL of them: skew between req and addr/wdata/lrsc corrupts the arbiter's IDLE sample (arb_lat_tb BREAK_MODE=2 is the proof), and rdata/scfail must stay aligned with done (value-with-pulse).
    -- The arbiter protocol is proven latency-insensitive at depths 0/1/2 (M10 wait-for-release masking), and the M12 wait-for-boot-fetch reset release is latency-insensitive by construction.
    -- NOT registered (see header): sleep and the flash/XIP ports (gated clock, sleep race), hart_id (static strap), trap_flag/a0 (quasi-static observation).
    -- =========================================================================
    -- Internal (pre-boundary) nets for signals that used to drive ports.
    signal sh_req_int     : std_logic;
    signal sh_lrsc_int    : std_logic_vector(1 downto 0);
    signal amo_lock_int   : std_logic;
    -- outbound stage
    signal bnd_req_r      : std_logic := '0';
    signal bnd_we_r       : std_logic_vector(3 downto 0) := (others => '0');
    signal bnd_addr_r     : std_logic_vector(SH_AW-1 downto 0) := (others => '0');
    signal bnd_wdata_r    : std_logic_vector(31 downto 0) := (others => '0');
    signal bnd_lrsc_r     : std_logic_vector(1 downto 0) := "00";
    signal bnd_lock_r     : std_logic := '0';
    -- inbound stage
    signal bnd_gnt_r      : std_logic := '0';   -- registered for uniformity; no tile logic consumes gnt
    signal bnd_done_r     : std_logic := '0';
    signal bnd_rdata_r    : std_logic_vector(31 downto 0) := (others => '0');
    signal bnd_scfail_r   : std_logic := '0';
    signal bnd_resvvld_r  : std_logic := '1';   -- X1 Zawrs: registered resv-valid level
    signal bnd_msip_r     : std_logic := '0';
    signal bnd_mtip_r     : std_logic := '0';
    signal bnd_meip_r     : std_logic := '0';
    -- D1 debug interface, same depth-1 boundary.
    -- Inbound requests reset '0' (fail-safe: no halt is being asked for), and the outbound halted level resets '0'.
    signal bnd_haltreq_r  : std_logic := '0';
    signal bnd_rsthalt_r  : std_logic := '0';
    signal dbg_halted_int : std_logic;
    signal bnd_halted_r   : std_logic := '0';

    -- =========================================================================
    -- CPR2 (R4): state for the external TCM slave port.
    -- Everything here is in the FREE-RUNNING mclk domain, which is the whole point: the requester must make progress while this tile's clk_cpu is gated off underneath it.
    -- No synchronisers anywhere in this block and none are wanted, because clk_cpu is a GATED SUBSET of clk (M9c) and they are therefore the same clock.
    -- NEVER put a set_clock_groups on the pair (the M9c bug: it deletes real paths).
    -- =========================================================================
    -- Depth-1 inbound boundary stage.
    signal tx_req_r      : std_logic := '0';
    signal tx_addr_r     : std_logic_vector(11 downto 0) := (others => '0');
    -- Depth-1 outbound boundary stage.
    -- tx_rdata_r is SIMULTANEOUSLY the Q landing register and the boundary register, ONE flop and not two, and that identity is load-bearing: it is what keeps rdata aligned with the done pulse, since both are written by the same edge of the same process.
    signal tx_rdata_r    : std_logic_vector(31 downto 0) := (others => '0');
    signal tx_done_r     : std_logic := '0';

    -- The four-state sequencer.
    -- std_logic_vector rather than an enum, so the state is dumpable into an SHM waveform DB from tcl (the enum/integer SST2ER trap).
    constant TX_IDLE   : std_logic_vector(1 downto 0) := "00";
    constant TX_SETTLE : std_logic_vector(1 downto 0) := "01";
    constant TX_READ   : std_logic_vector(1 downto 0) := "11";
    constant TX_LATCH  : std_logic_vector(1 downto 0) := "10";
    signal tx_state      : std_logic_vector(1 downto 0) := TX_IDLE;

    -- tx_sel is THE MUX SELECT and it is a REGISTER, never the raw request.
    -- NPU.vhd:300-307 (NpuMuxSel) is the house precedent and its rationale is ours verbatim: an asynchronous requester can raise its bit at an mclk edge where the CPU that owns this SRAM port has an access in flight, and switching the port on the raw bit eats that access.
    signal tx_sel        : std_logic := '0';
    signal tx_served     : std_logic := '0';   -- one-shot (req is held until done)
    -- Raw-OR-delayed, the NpuActive shape: high one full cycle BEFORE the mux switches to the external side, and one full cycle AFTER it switches back.
    signal tx_busy       : std_logic;
    signal tx_ext_clk    : std_logic;          -- gated mclk, one pulse per read
    signal tx_clk_en     : std_logic;
    signal tx_cen        : std_logic;

    -- ram0 pins after the 6-pin mux.
    signal ram_clk       : std_logic;
    signal ram_cen       : std_logic;
    signal ram_wen       : std_logic_vector(3 downto 0);
    signal ram_gwen      : std_logic;
    signal ram_a         : std_logic_vector(11 downto 0);
    signal ram_d         : std_logic_vector(31 downto 0);
    signal tcm_q         : std_logic_vector(31 downto 0);

    -- THE Q SHADOW (see the long comment at the mux).
    -- The vendor SRAM's Q is a continuous function of its LATCHED address (ARM_IP_RAM.vhd:69), so an external read DESTROYS whatever the frozen core was still holding on mem_dout(1).
    -- These two signals give the core its own value back across the window.
    signal tcm_q_shadow  : std_logic_vector(31 downto 0) := (others => '0');
    -- CPR3b/A3: the hold is now a TWO-FLOP HANDSHAKE across the two clocks, one mclk flop that ARMS and one clk_cpu flop that DISARMS, instead of the CPR2 fixed `tx_busy delayed one mclk` timer.
    -- tcm_q_hold is their inequality.
    -- See the long comment at the shadow for why a timer cannot cover the self-aperture case.
    signal tcm_q_arm     : std_logic := '0';   -- mclk domain: an external read happened
    signal tcm_q_ack     : std_logic := '0';   -- clk_cpu domain: the core has resumed
    signal tcm_q_hold    : std_logic;

begin

    -- M13 boundary registers.
    -- Both stages clock on the free-running mclk and reset with the chip resetn, because the boot fetch must flow while the CORE reset is still stretched (the same qualifier rationale as sh_req_int).
    bnd_out: process(clk, resetn)
    begin
        if resetn = '0' then
            bnd_req_r     <= '0';
            bnd_we_r      <= (others => '0');
            bnd_addr_r    <= (others => '0');
            bnd_wdata_r   <= (others => '0');
            bnd_lrsc_r    <= "00";
            bnd_lock_r    <= '0';
        elsif rising_edge(clk) then
            bnd_req_r     <= sh_req_int;
            bnd_we_r      <= sh_we_lanes;
            bnd_addr_r    <= data_addr(SH_AW+1 downto 2);
            bnd_wdata_r   <= write_word;
            bnd_lrsc_r    <= sh_lrsc_int;
            bnd_lock_r    <= amo_lock_int;
        end if;
    end process;

    sh_req  <= bnd_req_r;
    sh_we   <= bnd_we_r;
    sh_addr <= bnd_addr_r;
    sh_wdata <= bnd_wdata_r;
    sh_lrsc <= bnd_lrsc_r;
    sh_lock <= bnd_lock_r;
    dbg_halted <= bnd_halted_r;

    -- Inbound stage: the arbiter's responses plus the three per-hart IRQ levels.
    bnd_in: process(clk, resetn)
    begin
        if resetn = '0' then
            bnd_gnt_r      <= '0';
            bnd_done_r     <= '0';
            bnd_rdata_r    <= (others => '0');
            bnd_scfail_r   <= '0';
            bnd_resvvld_r  <= '1';
            bnd_msip_r     <= '0';
            bnd_mtip_r     <= '0';
            bnd_meip_r     <= '0';
        elsif rising_edge(clk) then
            bnd_gnt_r      <= sh_gnt;
            bnd_done_r     <= sh_done;
            bnd_rdata_r    <= sh_rdata;
            bnd_scfail_r   <= sh_scfail;
            bnd_resvvld_r  <= sh_resv_valid;
            bnd_msip_r     <= msip_in;
            bnd_mtip_r     <= mtip_in;
            bnd_meip_r     <= meip_in;
        end if;
    end process;

    -- =========================================================================
    -- D1 debug boundary stage (ENABLE_DEBUG): SAME clock, SAME reset, SAME depth 1 as bnd_in/bnd_out above.
    -- The M13 one-depth rule is about SKEW between signals in one transaction set, and these three are their own set, unrelated to req/gnt.
    --
    -- IN ITS OWN GENERATE PAIR, and that is the whole reason it is not simply three more lines inside bnd_in/bnd_out: the three flops are the ONLY part of D1 that a knob-OFF build would otherwise still pay for, because a boundary register has no ENABLE_ term to fold it away.
    -- MEASURED, not argued: with them ungated the OFF build's genus `sequential` read 2398 against a 2395 pin, exactly +3, exactly these.
    -- The pin did its job; the fix is to make them structurally absent, the gen_trapcsr_wb pattern.
    -- When OFF, dbg_halted is a hard constant '0': a chip with no debug interface never reports itself halted.
    -- =========================================================================
    gen_dbg_bnd: if ENABLE_DEBUG generate
        -- NOTE dbg_resethaltreq crosses this flop too, so it is one mclk late at the tile reset edge, and that is FINE, which is the opposite of what this comment used to say.
        -- It argued the lateness forced the core-side arming to LEVEL-FOLLOW the request until the first debug entry; F-D2-2 (R-D2-6(3)) is what that cost, because a request raised on a RUNNING hart then halted it.
        -- vesta's dbg_rsthalt_proc now takes ONE sample at its own reset release, and the sample point is well defined precisely BECAUSE of the stretch this comment cited: the core leaves reset when resetn_core takes boot_fetched, which cannot latch until the M12 boot fetch has crossed the arbiter and landed, strictly after this flop has settled, by construction rather than by a tuned delay.
        bnd_dbg: process(clk, resetn)
        begin
            if resetn = '0' then
                bnd_haltreq_r <= '0';
                bnd_rsthalt_r <= '0';
                bnd_halted_r  <= '0';
            elsif rising_edge(clk) then
                bnd_haltreq_r <= dbg_haltreq;
                bnd_rsthalt_r <= dbg_resethaltreq;
                bnd_halted_r  <= dbg_halted_int;
            end if;
        end process;
    end generate;

    -- Debug OFF: tie the stage flat so the flops are structurally absent.
    gen_dbg_bnd_off: if not ENABLE_DEBUG generate
        bnd_haltreq_r <= '0';
        bnd_rsthalt_r <= '0';
        bnd_halted_r  <= '0';
    end generate;

    -- =========================================================================
    -- CPR2 (R4): external-TCM-port boundary stage, with the SAME clock, SAME reset and SAME depth 1 as bnd_in/bnd_out and gen_dbg_bnd, and, like the debug trio, IT IS ITS OWN TRANSACTION SET (the D1 precedent at gen_dbg_bnd above).
    -- The one-depth rule exists because skew BETWEEN SIGNALS OF ONE TRANSACTION corrupts a sampled handshake; req/addr are one transaction with each other and with nothing else here, and rdata/done are one value-with-pulse pair with each other.
    --
    -- INBOUND stage is this process; the OUTBOUND stage is tx_rdata_r/tx_done_r, written by tx_port_fsm below, which are boundary registers AND the landing registers, deliberately the same flops (see their declaration).
    --
    -- Reset drives tx_req_r to '0', which is why "a request during reset is IGNORED" is structural rather than a checked condition: the sequencer can never see a request while resetn is low, and the SRAM is never clocked from this side while resetn is low.
    --
    -- NOT in a generate: unlike D1 this port is not knob-gated (R4), so there is no OFF arm for it to be structurally absent from.
    -- =========================================================================
    bnd_tcm_ext: process(clk, resetn)
    begin
        if resetn = '0' then
            tx_req_r  <= '0';
            tx_addr_r <= (others => '0');
        elsif rising_edge(clk) then
            tx_req_r  <= tcm_ext_req;
            tx_addr_r <= tcm_ext_addr;
        end if;
    end process;

    -- M19: three live slots, meip (the router's claim/complete stage) plus this hart's own CLINT pair.
    -- Everything else is constant '0', and the enables are the hardwired TILE_IRQ_EN constant (masking lives in the router).
    tile_irq_proc: process(bnd_meip_r, bnd_msip_r, bnd_mtip_r)
    begin
        tile_irq_vec <= (others => '0');
        tile_irq_vec(IRQB_EXT_MEIP)   <= bnd_meip_r;
        tile_irq_vec(IRQB_CLINT_MSIP) <= bnd_msip_r;
        tile_irq_vec(IRQB_CLINT_MTIP) <= bnd_mtip_r;
    end process;

    -- M9b/M12: the reset vector (0x0) is the SHARED boot ROM since M12, so the first fetch is a multi-cycle arbiter transaction and the M9b fixed two-edge release can no longer guarantee a primed instruction bus.
    -- Instead the core is held in reset until its boot fetch has LANDED in the clk_cpu consumption stage: during reset the core presents data_addr = PC_RST_VAL (pc_next_trad's reset arm, with nop-forced decode keeping everything defined), sh_req runs the fetch through the arbiter, and mem_ready stays low so clk_cpu's FIRST edge is the stall-ending edge after the ack, which stages the fetched instruction into sh_rdata_cpu and raises sh_dphase.
    -- sh_dphase='1' therefore means "the boot instruction is on the core's read bus", the exact private-ROM priming contract (M9b) replicated through the arbiter.
    -- Sticky: it releases once and stays released.
    -- Latency-insensitive by construction (M12), and unchanged by the M13 boundary registers.
    core_rst_stretch: process(clk, resetn)
    begin
        if resetn = '0' then
            boot_fetched <= '0';
        elsif rising_edge(clk) then
            if sh_dphase = '1' then
                boot_fetched <= '1';
            end if;
        end if;
    end process;
    resetn_core <= boot_fetched;

    core: vesta
        generic map (
            PC_RST_VAL => PC_RST_VAL,
            NUM_IRQS   => NUM_IRQS,
            ENABLE_MUL        => ENABLE_MUL,
            ENABLE_DIV        => ENABLE_DIV,
            ENABLE_ATOMICS    => ENABLE_ATOMICS,
            ENABLE_COMPRESSED => ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => ENABLE_BITMANIP,
            ENABLE_ZICOND     => ENABLE_ZICOND,
            ENABLE_ZCB        => ENABLE_ZCB,
            ENABLE_ZIMOP      => ENABLE_ZIMOP,
            ENABLE_ZIHINT     => ENABLE_ZIHINT,
            ENABLE_ZIHPM      => ENABLE_ZIHPM,
            ENABLE_ZAWRS      => ENABLE_ZAWRS,
            ENABLE_ZABHA      => ENABLE_ZABHA,
            ENABLE_ZACAS      => ENABLE_ZACAS,
            ENABLE_ZICBOZ     => ENABLE_ZICBOZ,
            ENABLE_ZCMP       => ENABLE_ZCMP,
            ENABLE_ZCMT       => ENABLE_ZCMT,
            ENABLE_ZBKB       => ENABLE_ZBKB,
            ENABLE_ZBKC       => ENABLE_ZBKC,
            ENABLE_ZBKX       => ENABLE_ZBKX,
            ENABLE_ZKN        => ENABLE_ZKN,
            ENABLE_ZFINX      => ENABLE_ZFINX,
            ENABLE_TRAPCSR    => ENABLE_TRAPCSR,
            ENABLE_UMODE      => ENABLE_UMODE,
            ENABLE_PMP        => ENABLE_PMP,
            PMP_ENTRIES       => PMP_ENTRIES,
            ENABLE_DEBUG      => ENABLE_DEBUG,
            DEBUG_ENTRY_ADDR  => DEBUG_ENTRY_ADDR
        )
        port map (
            clk         => clk,
            resetn      => resetn_core,   -- M9b: delayed release (fetch priming)
            sleep       => sleep,
            clk_cpu     => clk_cpu,
            hart_id     => hart_id,

            data_addr    => data_addr,
            wen          => wen_re,
            write_data   => write_word,
            read_data    => core_read_data, -- adddec data, or shared-window data during the data phase
            mask         => mask,
            mem_ready    => mem_ready_sh,   -- '1' except during a shared-window transaction

            lr_sc_bus    => lr_sc_bus,
            sc_fail_ext  => sh_scfail_reg,
            resv_valid_ext => bnd_resvvld_r,   -- X1 Zawrs: registered resv-valid level
            amo_lock     => amo_lock_int,

            irq_vector       => tile_irq_vec,
            irq_priority     => TILE_IRQ_PRI,
            irq_en           => TILE_IRQ_EN,
            irq_recursion_en => '0',
            isr_ret          => open,

            -- D1: the boundary-registered request levels in, and the halted level out, registered on the way out at the same depth.
            dbg_haltreq      => bnd_haltreq_r,
            dbg_resethaltreq => bnd_rsthalt_r,
            dbg_halted       => dbg_halted_int,

            trap_flag    => trap_flag,
            a0           => a0
        );

    -- M13: the extended-flash decode is enabled in EVERY tile (identical netlists); only hart 0 has SPI0 behind the flash ports (see header).
    adddec0: adddec
        generic map (
            ENABLE_FLASH_EXTENDED_MEM => true,
            -- A2: the flash decode is the strict complement of this tile's SH_AW-derived sh_sel window (the M3c.3 double-claim lesson).
            SH_AW                     => SH_AW
        )
        port map (
            clk             => clk_cpu,
            resetn          => resetn,

            wen             => wen_re,
            data_addr       => data_addr,
            write_word      => write_word,
            mask            => mask,

            write_data      => write_data,
            read_data       => read_data,
            mem_addr        => mem_addr,
            addr_periph     => addr_periph,
            mab_out         => flash_mab,
            wen_fe          => wen_fe,
            GWEN            => GWEN,

            mem_en          => mem_en,
            mem_en_periph   => mem_en_periph,
            clk_mem         => clk_mem,
            clk_periph      => clk_periph,

            mem_en_flash    => flash_mem_en,
            clk_mem_flash   => flash_clk_mem,

            mem_dout       => mem_dout,
            periph_dout    => zero_periph,
            flash_dout     => flash_dout
        );

    -- =========================================================================
    -- M3c.4: shared-window master (proven M3c wiring, tile-internal).
    -- See the header comment for the design rationale of every piece.
    -- =========================================================================
    -- M11/M12 decode: EVERYTHING in the shared window except the private TCM (0x8000-0xBFFF) is shared, meaning the boot ROM (M12), the peripheral window, the NPU staging RAM and the bulk RAM, under an exact (31:SH_AW+2)=0 qualification.
    -- A loose decode aliases extended-flash addresses back into the window: the bug 2 class, and the M3c.3 double-claim deadlock.
    -- adddec asserts no enable for any shared region, so the two decoders can never double-claim an address.
    -- A2 (Argus): the decode is derived from SH_AW, so the window is 0x0..2^(SH_AW+2)-1 minus the TCM.
    -- At the Castalia default (SH_AW=15, window 0x0-0x1FFFF) this is bit-for-bit the original (31:17)=0 and (16:14)/="010" decode; at SH_AW=16 (Argus, window 0x0-0x3FFFF, flash from 0x40000) it is (31:18)=0 and (17:14)/="0010".
    sh_sel <= '1' when data_addr(31 downto SH_AW+2) = SH_WIN_ZERO
                   and not (data_addr(SH_AW+1 downto 16) = SH_TCM_ZERO
                            and data_addr(15 downto 14) = "10")
                   else '0';

    -- One-shot handshake on the FREE-RUNNING clk (mclk): request until this access completes (done), then hold off re-request until the core steps off the shared address.
    -- clk_cpu is gated while stalled, so data_addr/wen/write_word are stable across the wait.
    --
    -- M4b: the ack additionally remembers the LANE STROBES of the completed transaction (sh_acked_we) and only satisfies an access with the SAME strobes (sh_ack_ok, combinational).
    -- WHY: an SC keeps data_addr on the shared address across two back-to-back accesses with different types, a read in EXECUTE and then the conditional WRITE in SC_CHECK.
    -- With an address-only ack the write would never issue, a silently lost SC.
    -- The lane change drops sh_ack_ok inside the SC_CHECK cycle, so the core re-stalls and the write runs as a fresh arbiter transaction.
    --
    -- M10: the ack also remembers the WORD ADDRESS (sh_acked_addr) and only satisfies an access to the SAME word.
    -- WHY: executing FROM the shared window (the M12 boot shape) produces back-to-back same-lane READS at DIFFERENT addresses with sh_sel never dropping, namely sequential fetches and the fetch after a shared load.
    -- The lanes-only ack absorbed them all into one stale sh_rdata_reg, so the core re-executed instruction k forever.
    -- An address change now drops sh_ack_ok, so every new word re-arbitrates.
    -- Same-word re-access still holds the ack: a compressed pair in one word or a `j .` self-loop correctly re-uses the held word, and repeated-identical-access absorption (AMO_READ consuming its EXECUTE-cycle read) is unchanged.
    sh_handshake: process(clk, resetn)
    begin
        if resetn = '0' then
            sh_acked      <= '0';
            sh_acked_we   <= (others => '0');
            sh_acked_addr <= (others => '0');
            sh_rdata_reg  <= (others => '0');
            sh_scfail_reg <= '0';
        elsif rising_edge(clk) then
            if sh_sel = '0' then
                sh_acked      <= '0';
                sh_scfail_reg <= '0';
            elsif bnd_done_r = '1' then
                -- M13: done/rdata/scfail arrive through the inbound boundary stage, with value-with-pulse alignment preserved because they share a depth.
                sh_acked      <= '1';
                sh_acked_we   <= sh_we_lanes;
                sh_acked_addr <= data_addr(SH_AW+1 downto 2);
                sh_rdata_reg  <= bnd_rdata_r;   -- capture shared read data
                sh_scfail_reg <= bnd_scfail_r;  -- capture resv_unit SC verdict
            end if;
        end if;
    end process;

    -- wen is ACTIVE-LOW per byte lane; the arbiter's we is active-high per lane (M4a).
    -- write_word is lane-positioned by the core's store extender, which is what makes sb/sh work.
    -- The lanes feed BOTH the outbound boundary stage and the local ack comparison below, and the comparison stays on the RAW lanes: it is the frozen core comparing its own current access against the acked one.
    sh_we_lanes <= (not wen_re) when sh_sel = '1' else (others => '0');

    sh_ack_ok <= '1' when sh_acked = '1' and sh_acked_we = sh_we_lanes
                      and sh_acked_addr = data_addr(SH_AW+1 downto 2) else '0';

    -- M9b/M12: the chip resetn masks the power-on settle window from the arbiter.
    -- During the stretched priming window (resetn high, resetn_core still low) the request MUST flow, because it IS the boot fetch, and its inputs are defined there by construction: the nop-forced read bus keeps the core's decode defined, and pc_next_trad's reset arm pins data_addr at PC_RST_VAL (M9b round-2.5 analysis).
    -- M13: these are the PRE-boundary nets; the ports carry their one-stage-registered copies (bnd_out above).
    sh_req_int  <= sh_sel and not sh_ack_ok and resetn;
    sh_lrsc_int <= lr_sc_bus when sh_sel = '1' else "00";

    -- Back-pressure into the core.
    -- TWO independent stall sources are ANDed here, and mem_ready is the ONLY hook either of them is allowed to use.
    --   * the shared-window transaction (M3c.4, an identity while sh_sel='0');
    --   * CPR2's external TCM read (tx_busy, an identity while nobody asks).
    -- WHY mem_ready AND NOT `sleep` FOR THE SECOND ONE (R4, hard rule 3): vesta.vhd:1434's en_clk_cpu makes mem_ready the TOP priority term and puts `sleep` BELOW irq_active / std_irq_take / std_wfi_wake / dbg_halt_pend.
    -- An interrupt, a WFI wake or a debug halt request therefore OUTRANKS sleep and would un-freeze the core in the middle of an external SRAM access, at an arbitrary instant, with the ram0 mux pointed the other way.
    -- mem_ready has no such override.
    -- `sleep` is also unregistered by contract (the flash/XIP race, see the header), which is the second reason it can never carry this.
    mem_ready_sh <= ((not sh_sel) or sh_ack_ok) and (not tx_busy);

    -- Read-data mux, DATA-PHASE ONLY, with the select registered on the tile's own gated clk_cpu BY DESIGN (bug 4: a raw-sh_sel mux on read_data oscillates, because read_data is the instruction during decode).
    -- sh_dphase is '1' exactly during the MEMORY_WAIT cycle, where read_data is consumed as LOAD DATA and the instruction comes from the held instr_curr_prev.
    sh_dphase_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            sh_dphase   <= '0';
            sh_rdata_cpu <= (others => '0');
        elsif rising_edge(clk_cpu) then
            sh_dphase   <= sh_sel;
            -- M10 consumption stage (see the signal declaration): re-latching a stale landing value is harmless; what matters is that this register can NEVER change inside a stretched core cycle.
            sh_rdata_cpu <= sh_rdata_reg;
        end if;
    end process;

    -- M9b: nop-force the instruction bus until the STRETCHED core reset releases.
    -- adddec's own nop arm uses the early chip resetn, which in the gate netlist releases about 2 cycles before resetn_core; in that window the select staging points at a memory whose Q has never been clocked, and the X instruction feeds pc_next, then data_addr, then decode, then select, a self-sustaining X loop on the unified bus.
    -- A defined nop keeps pc_next, data_addr and decode defined while the fetch pipeline primes.
    core_read_data <= nop          when resetn_core = '0' else
                      sh_rdata_cpu when sh_dphase = '1'   else read_data;

    -- M11/M12: the tile's private memories besides the TCM are RETIRED.
    -- Region 000 is the SHARED boot ROM (M12) and 0xC000-0xFFFF is the SHARED NPU staging RAM (M11), both reached via sh_sel through the arbiter.
    -- adddec asserts no enable for either, so its slots 0 and 2 read zeros.
    mem_dout(0) <= (others => '0');
    mem_dout(2) <= (others => '0');

    -- =========================================================================
    -- CPR2 (R4): THE EXTERNAL TCM READ SEQUENCER.
    --
    -- Four states, one SRAM read, everything on the free-running mclk.
    -- Cycle by cycle, with E = the mclk edge at which the tile's inbound boundary register first sees the request (so the requester raised tcm_ext_req at E-1):
    --
    --   edge  tx_req_r tx_state  tx_sel tx_cen  ram0            core clk_cpu
    --   ----  -------- --------  ------ ------  --------------  ------------
    --   E     1        IDLE      0      1       core side       LAST EDGE
    --   E+1   1        SETTLE    1      1       mux switches    gated off
    --   E+2   1        READ      1      0       (no clock)      gated off
    --   E+3   1        LATCH     1      1       READ HAPPENS    gated off
    --   E+4   1        IDLE      0      1       mux switches    gated off
    --                            ^ tx_rdata_r takes Q, tx_done_r takes '1'
    --   E+5   1        IDLE      0      1                       gated off
    --                            ^ requester SAMPLES done here, drops req
    --   E+6   0        IDLE      0      1                       gated off
    --   E+7   0        IDLE      0      1                       RESUMES
    --
    -- LATENCY, exactly: FIVE mclk from the request being registered at the tile boundary (E) to the requester sampling done (E+5), and SIX from the requester's own drive edge (E-1).
    -- The core loses SEVEN clk_cpu edges per transaction (E+1..E+7), of which two are the deliberate lead/lag margin and two more are the requester's own hold-until-done tail.
    --
    -- THE LEAD AND THE LAG, which is the whole reason tx_busy is raw-OR-delayed (NPU.vhd:364-366, NpuActive) rather than just tx_sel:
    --   * LEAD.  tx_busy rises at E, one full cycle before tx_sel rises at E+1.
    --     The ClkGate latches its enable during the LOW phase (ClkGate.vhd:25-30), so busy-at-E kills the clk_cpu edge at E+1 and the core's last edge is E, strictly before the mux moves.
    --   * LAG.  tx_sel falls at E+4 but tx_busy stays high until tx_req_r falls, so the core's first edge back is E+7 at the earliest, three cycles after the mux returned.
    --     Even a PROTOCOL-VIOLATING one-cycle request (req not held to done) still gets a full cycle of lag, because tx_busy = tx_req_r or tx_sel is continuous across the handover.
    --
    -- NO DEADLOCK, INCLUDING THE SELF-ACCESS CASE (R3's "a tile reading its own aperture address").
    -- Suppose the core is stalled on a shared-window transaction (mem_ready_sh low via sh_sel) at the moment a request arrives, which is exactly what happens when this tile reads its own window through the arbiter.
    -- Nothing in this sequencer waits on the core: tx_state, tx_sel and the SRAM clock are all on the free-running clk, the core's TCM clock gate is CLOSED (clk_mem(1) follows the gated clk_cpu), and the mux owns the SRAM meanwhile.
    -- The sequencer reaches LATCH in four edges and drops tx_sel unconditionally.
    -- Symmetrically, the shared handshake (sh_handshake, sh_req_int, mem_ready_sh) is also entirely on clk and completes underneath the freeze, so sh_ack_ok is already high when tx_busy releases.
    -- Neither side can be waiting on the other because NEITHER SIDE EVER WAITS ON THE CORE.
    -- What a back-to-back stream of requests costs is THROUGHPUT, not liveness: the core still gets one clk_cpu edge per request, because tx_busy must go low for a full cycle before tx_req_r can be re-registered high, so forward progress is bounded and never zero.
    -- tcm_port_tb's T3 measures exactly that.
    -- LIVENESS IS NOT DATA INTEGRITY, and this paragraph only ever claimed the first: in the self-access case the core stays frozen for the whole arbiter transaction, i.e. PAST the end of tx_busy, and what it is shown on mem_dout(1) during that tail is amendment A3's subject.
    -- See THE Q SHADOW below; nothing in THIS block changed.
    --
    -- tx_served is the one-shot.
    -- tcm_ext_req is held until done, so the sequencer must not re-trigger on the tail of the request it already answered; tx_served is set at LATCH and cleared whenever tx_req_r is low.
    -- Same shape as sh_acked (sh_handshake above).
    -- =========================================================================
    tx_port_fsm: process(clk, resetn)
    begin
        if resetn = '0' then
            tx_state   <= TX_IDLE;
            tx_sel     <= '0';
            tx_served  <= '0';
            tx_rdata_r <= (others => '0');
            tx_done_r  <= '0';
        elsif rising_edge(clk) then
            tx_done_r <= '0';                 -- default: done is a 1-cycle pulse
            case tx_state is
                when TX_SETTLE =>
                    -- The mux moved on the edge that entered this state, and the SRAM is deliberately NOT clocked during it (see the clock-mux note at tx_ext_clk below).
                    tx_state <= TX_READ;
                when TX_READ =>
                    -- tx_cen is low across THIS cycle, so the single tx_ext_clk pulse at the edge leaving it performs the read.
                    tx_state <= TX_LATCH;
                when TX_LATCH =>
                    -- Q is valid now, since the read happened at the edge that entered this state.
                    -- ONE edge writes both outputs, which is what makes rdata valid-with-pulse by construction.
                    tx_rdata_r <= tcm_q;
                    tx_done_r  <= '1';
                    tx_sel     <= '0';
                    tx_served  <= '1';
                    tx_state   <= TX_IDLE;
                when others =>                -- TX_IDLE
                    tx_sel <= '0';
                    if tx_req_r = '1' and tx_served = '0' then
                        tx_state <= TX_SETTLE;
                        tx_sel   <= '1';
                    end if;
            end case;
            -- One-shot rearm, written after the case on purpose: at LATCH the request is still high, so the case arm's '1' must win, and a request that has ALREADY dropped by then simply rearms a cycle earlier.
            -- Either order is safe; this one is the readable one.
            if tx_req_r = '0' then
                tx_served <= '0';
            end if;
        end if;
    end process;

    -- Raw-OR-delayed stall term (the NpuActive shape); see the lead/lag note above.
    tx_busy <= tx_req_r or tx_sel;

    -- The external side's SRAM clock is a GATED mclk, not raw mclk, and that is not a power optimisation: it is what makes the clock MUX below glitch-free.
    -- tx_ext_clk is LOW except for exactly one pulse, at the edge leaving TX_READ.
    -- Both mux switch instants (entering TX_SETTLE and leaving TX_LATCH) therefore have BOTH mux inputs low: tx_ext_clk is low by construction, and clk_mem(1) is low because the core's clk_cpu has been gated off since the lead cycle.
    -- A mux whose two inputs are both low cannot glitch its output when the select moves.
    -- Switching a raw mclk in on a rising edge would manufacture a spurious SRAM clock edge at the switch instant; an inactive CEN would make it harmless, but "harmless" is not what you want on a memory clock.
    tx_clk_en <= '1' when tx_state = TX_READ else '0';
    tx_cen    <= '0' when tx_state = TX_READ else '1';

    cg_tcm_ext: entity work.ClkGate
        port map (
            ClkIn  => clk,
            En     => tx_clk_en,
            ClkOut => tx_ext_clk
        );

    -- -------------------------------------------------------------------------
    -- THE 6-PIN ram0 MUX {CLK, CEN, WEN, GWEN, A, D} (R4, the pre-M11 NpuMuxSel shape, NPU.vhd:293-298).
    -- The select is tx_sel, REGISTERED, never the raw request.
    --
    -- READ-ONLY IS ENFORCED HERE AND ONLY HERE, structurally: on the external side WEN is the all-inactive "1111" CONSTANT and GWEN the '1' CONSTANT, so no state of this port, no value of tcm_ext_addr and no fault on tcm_ext_req can produce a write.
    -- D is a don't-care in that state and is driven to zeros rather than left on write_data, so a waveform showing the external window shows unambiguously that nothing was offered to the array.
    -- The tool will constant-fold the WEN/GWEN arms into a plain 2-input mux per bit and the D arm into an AND; that is intended, because the constants are the specification, not the implementation.
    -- -------------------------------------------------------------------------
    ram_clk  <= tx_ext_clk when tx_sel = '1' else clk_mem(1);
    ram_cen  <= tx_cen     when tx_sel = '1' else mem_en(1);
    ram_wen  <= "1111"     when tx_sel = '1' else wen_fe;      -- READ-ONLY
    ram_gwen <= '1'        when tx_sel = '1' else GWEN;        -- READ-ONLY
    ram_a    <= tx_addr_r  when tx_sel = '1' else mem_addr;
    ram_d    <= (others => '0') when tx_sel = '1' else write_data;

    -- -------------------------------------------------------------------------
    -- THE Q SHADOW, and why the mux above is NOT sufficient on its own.
    --
    -- This is the one piece R4 does not name, and it is not optional.
    -- The vendor SRAM's read data is NOT a per-access strobe: ARM_IP_RAM.vhd:69 assigns Q from mem(conv_integer(AdrLat)), a CONTINUOUS function of the address latched by the last access.
    -- The core relies on that: it issues a TCM read at clk_cpu edge k (clk_mem(1) rises, AdrLat takes mem_addr) and CONSUMES Q combinationally through adddec's out_buff at edge k+1.
    --
    -- Freezing the core is therefore NOT enough to protect it.
    -- The freeze can land on edge k, because an external request is asynchronous to whatever the core is doing, unlike every pre-existing stall in this tile (sh_sel fires only on a SHARED address and `sleep` only on a FLASH one, so neither can ever freeze the core mid-TCM-read).
    -- When it does, the external read at E+3 relatches AdrLat, Q changes underneath the frozen core, and at its resume edge the core consumes THE EXTERNAL WORD as its own load result or instruction: silent data corruption in the victim tile, caused by a read from another hart.
    --
    -- The fix is one register and one mux on mem_dout(1):
    --   * tcm_q_shadow tracks Q every mclk while the port is idle, so it always holds "what the core last read";
    --   * tcm_q_hold selects it for exactly as long as the core is frozen with that word still owed to it (see THE HOLD WINDOW below);
    --   * at the resume edge the core samples the PRE-edge value of read_data, i.e. the shadow, while the same edge re-issues its own access and refreshes the real Q, so the hold may drop exactly there, and does.
    -- The core's address is held across the freeze (data_addr only changes on clk_cpu edges, and adddec's falling-edge staging re-presents it), which is what makes that refresh automatic rather than something we have to replay.
    --
    -- INVARIANT, and it is the whole specification of this block: WHILE THE CORE IS FROZEN, mem_dout(1) MUST NOT CHANGE.
    -- That is what an undisturbed SRAM does on its own, since Q is a function of AdrLat and AdrLat can only move on a core-side clk_mem(1) edge, which is a gated clk_cpu edge.
    -- The shadow's only job is to reproduce that constant while the external port moves AdrLat underneath it.
    --
    -- THE HOLD WINDOW (CPR3b, amendment A3, and the CPR2 timer form was the bug).
    -- CPR2 keyed the hold on `tx_busy delayed one mclk`, i.e. the interval (E+1, E+7], which is exactly right for the ONE freeze shape CPR2 could produce: a core frozen BY THIS PORT, which by construction resumes at E+7.
    -- It is wrong for every LONGER freeze, and CPR3 built the one that matters:
    --
    --   THE SELF-APERTURE CASE.
    --   A hart reads its OWN TCM window (0x20000 + 0x4000*h) as an ordinary shared-bus load.
    --   The MCU's aperture sequencer answers it by driving THIS tile's tcm_ext_* port and holding the arbiter in LATCH (mp_arbiter s_stall) until the tile answers.
    --   So the core is frozen on sh_sel/mem_ready_sh for the WHOLE arbiter transaction, strictly longer than tx_busy, which is only the inner 7 mclk of it.
    --   With the timer, the shadow deselected at E+7 and the still-frozen core spent the remaining cycles staring at LIVE Q, which is now a continuous function of the EXTERNAL address.
    --   What it consumed at its real resume edge was the aperture word: measured at CPR3 as hart 0's PC going from 0x83E0 to 0x842E, i.e. the foreign payload decoded as an instruction.
    --   A TCM-executing core's INSTRUCTION bus is this same mem_dout(1), combinationally live through adddec's out_buff while the core is frozen, because freezing a core does not disconnect it.
    --   The load flavour of the same window is what tcm_port_tb's T6 drives.
    --
    -- So the release is no longer a count; it is EVIDENCE THAT THE CORE HAS ACTUALLY TAKEN AN EDGE.
    -- Two flops, one per clock, and the hold is their inequality:
    --   * tcm_q_arm (mclk) toggles when tx_busy is seen and the hold is not already up, so it ARMS on an external access, and re-arming while armed is a deliberate no-op (a second access inside one freeze must not cancel the first);
    --   * tcm_q_ack (clk_cpu) copies tcm_q_arm on every core edge, so it DISARMS at the first clk_cpu edge after the freeze, whatever ended the freeze and however long it was.
    -- The two can never move on the same edge, which is what makes the handshake safe without a synchroniser: arming requires tx_busy = '1' in the cycle before the edge, and that is exactly the condition under which the ClkGate has already killed that clk_cpu edge (the LEAD margin above).
    -- clk_cpu is a gated subset of clk, so a clk_cpu flop read at an mclk edge is the same shape as the sh_dphase-to-boot_fetched path this file already has.
    -- At the disarm edge the core samples the PRE-edge mux value (the shadow) and the same edge re-issues its own access, so the mux is back on live Q for the cycle in which that access's Q is valid.
    --
    -- IT CANNOT WEDGE.
    -- tcm_q_hold feeds ONE mux, on the core's read data; it is not in any handshake, any ready or any request, so not mem_ready_sh, not sh_req_int, not the tx FSM, not tcm_ext_done.
    -- A core that never takes another edge (parked, gated, held in reset) simply keeps being shown the last word it read, which is what it would have seen anyway, while the external port keeps completing transactions at full rate out of tx_rdata_r, which does not pass through here.
    -- And the arm is level-triggered on tx_busy, so no request can be "missed" into a stuck state.
    --
    -- tcm_port_tb's T4 is the negative control for the SHADOW: delete it, keep everything else, and T2 reports the victim core reading the external pattern.
    -- T6 is the negative control for THIS WINDOW: restore the CPR2 timer, driving tcm_q_hold from tx_busy, and T6 fails while T1/T2/T3/T5 stay green.
    -- -------------------------------------------------------------------------
    tcm_q_shadow_reg: process(clk, resetn)
    begin
        if resetn = '0' then
            tcm_q_arm    <= '0';
            tcm_q_shadow <= (others => '0');
        elsif rising_edge(clk) then
            -- ARM. `tcm_q_arm = tcm_q_ack` means "not currently held"; re-arming while held would cancel the hold, which is the one thing this handshake must never do.
            if tx_busy = '1' and tcm_q_arm = tcm_q_ack then
                tcm_q_arm <= not tcm_q_arm;
            end if;
            -- The shadow tracks Q whenever it is not the thing being shown.
            -- Reading the PRE-edge hold is what puts its LAST capture one edge INSIDE the freeze (E+1), where Q is still the core's own word, since the external read is at E+3.
            if tcm_q_hold = '0' then
                tcm_q_shadow <= tcm_q;
            end if;
        end if;
    end process;

    -- DISARM: the core took an edge, so it has consumed the shadow and refreshed the real Q with its own access on that same edge.
    tcm_q_ack_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            tcm_q_ack <= '0';
        elsif rising_edge(clk_cpu) then
            tcm_q_ack <= tcm_q_arm;
        end if;
    end process;

    tcm_q_hold <= tcm_q_arm xor tcm_q_ack;

    mem_dout(1) <= tcm_q_shadow when tcm_q_hold = '1' else tcm_q;

    tcm_ext_rdata <= tx_rdata_r;
    tcm_ext_done  <= tx_done_r;

    -- Private TCM (RAM0, 0x8000-0xBFFF): IVT, code, data and stack.
    -- M12: NOT preloaded. Like silicon, the TCM powers up unknown, and software owns write-before-read (the bootrom's tile loader fills it before use).
    -- M13: PGEN is a port, so hart 0 keeps BLOCKPWR software gating while tiles tie '0'.
    -- CPR2: every pin except EMA/RETN/PGEN now arrives through the external read port's mux above, and Q leaves through the shadow above.
    ram0: entity work.sram1p16k_hvt_pg
        port map (
            Q     => tcm_q,
            CLK   => ram_clk,
            CEN   => ram_cen,
            WEN   => ram_wen,
            A     => ram_a,
            D     => ram_d,
            EMA   => "000",
            GWEN  => ram_gwen,
            RETN  => tcm_retn,
            PGEN  => tcm_pgen
        );

end architecture;
