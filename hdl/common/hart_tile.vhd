/* =============================================================================
   hart_tile.vhd
   =============================================================================
   One self-contained hart: a vesta core, its own address decoder and its private TCM (RAM0, 0x8000-0xBFFF).
   Everything except the TCM is reached through the shared-window master port below, behind mp_arbiter on the free-running mclk; the core resets to PC 0x0 and boots out of the shared ROM.
   EVERY hart on the chip instantiates this entity and all instances are STRUCTURALLY IDENTICAL, one netlist for one hardened tile: the only per-instance differences are wiring (hart_id, the flash/XIP hookup, tcm_pgen, the power-domain controls).
   The whole tile edge is registered at depth 1 on mclk, and the TCM carries a second, read-only slave port through which the management hart reads this tile's memory.
   Each tile replicates the unchanged single-core core-to-adddec-to-RAM path, so there is no cross-hart grant-switching hazard on the fetch/load pipeline.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;      -- word, word_array
use work.MemoryMap.all;      -- NUM_IRQS

entity hart_tile is
    generic (
        -- Every hart resets to 0x0, the shared boot ROM.
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00000000";
        SH_AW          : natural := 16;  -- Shared-window word-address width; must match mp_arbiter.
                                         -- 16 gives the window 0x0-0x3FFFF with flash from 0x40000; 15 gives 0x0-0x1FFFF with flash from 0x20000.
                                         -- It drives BOTH the sh_sel window decode and adddec's complementary flash decode below, which must stay strict complements.

        -- Core ISA feature switches, passed straight down to vesta; every tile instance must get the SAME values, since they share one netlist.
        -- THE DEFAULTS BELOW ARE LOAD-BEARING: a bare `elaborate hart_tile` for tile hardening, and any top that names no priv generics, both take them as written.
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- Optional ISA extensions, all default false and routed straight to the vesta core.
        ENABLE_ZICOND     : boolean := false;  -- Zicond
        ENABLE_ZCB        : boolean := false;  -- Zcb
        ENABLE_ZIMOP      : boolean := false;  -- Zimop/Zcmop
        ENABLE_ZIHINT     : boolean := false;  -- Zihintpause/ntl
        ENABLE_ZIHPM      : boolean := false;  -- Zihpm
        ENABLE_ZAWRS      : boolean := false;  -- Zawrs
        ENABLE_ZABHA      : boolean := false;  -- Zabha
        ENABLE_ZACAS      : boolean := false;  -- Zacas
        ENABLE_ZICBOZ     : boolean := false;  -- Zicboz cbo.zero
        ENABLE_ZCMP       : boolean := false;  -- Zcmp push/pop + moves
        ENABLE_ZCMT       : boolean := false;  -- Zcmt table jump
        ENABLE_ZBKB       : boolean := false;  -- Zbkb
        ENABLE_ZBKC       : boolean := false;  -- Zbkc
        ENABLE_ZBKX       : boolean := false;  -- Zbkx
        ENABLE_ZKN        : boolean := false;  -- Zkn = Zknd+Zkne+Zknh
        ENABLE_ZFINX      : boolean := false;  -- Zfinx
        -- Privileged architecture, routed straight to the vesta core; the trap CSRs are on by default because the shipped chip has them.
        ENABLE_TRAPCSR    : boolean := true;   -- standard M-mode trap CSRs + MRET
        ENABLE_UMODE      : boolean := false;  -- U-mode; requires TRAPCSR
        ENABLE_PMP        : boolean := false;  -- PMP/Smpmp; requires UMODE
        PMP_ENTRIES       : integer := 16;     -- PMP entry count {8,16}
        -- Core-side debug mode, routed straight to the vesta core.
        -- FLIPPED TO TRUE 2026-08-16, and it is now load-bearing in the SAME WAY ENABLE_TRAPCSR is: debug.enable became a SHIPPED DEFAULT (USER directive; generate.py, both of its two literals), so the tile the shipped chip instantiates is a debug-ON tile and the bare `elaborate hart_tile` that hardens the macro MUST agree with it.
        -- THE OLD `false` WAS MEASURED WRONG HERE, not merely stale: with MCU.vhd passing ENABLE_DEBUG => CORE_ENABLE_DEBUG (true) while a bare elaborate took this default, genus/hart_tile produced a netlist BYTE-FOR-BYTE identical to the pre-flip tile (15,096 cells, 2,464 sequential -- verified by comparing area/gates reports before and after the flip). The hardened macro would have been debug-OFF while the assembly wired it as debug-ON: the M14 hw_clint_en VHDL-default-lost-at-netlist-boundary silicon bug, exactly.
        -- The prior rationale (a debug interface silently present is an area and attack-surface surprise) is NOT discarded -- it now belongs to the knob-OFF row config/castalia_nodbgnfc.json, which is where a debug-free chip is built and proven.
        ENABLE_DEBUG      : boolean := true;   -- debug mode; requires TRAPCSR
        -- Debug entry vector, passed through unchanged; see the vesta entity for the memory-map argument for 0xBE00.
        DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00"
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        -- SPI0's disable_clk_cpu on the flash-boot hart, which freezes the core across an XIP flash access; other tiles default '0'.
        -- NOT boundary-registered: a one-cycle-late sleep would let the core consume garbage flash_dout.
        sleep     : in  std_logic := '0';

        -- mhartid CSR value, static per instance; a port rather than a generic keeps every tile one netlist.
        hart_id   : in  std_logic_vector(31 downto 0);

        -- Per-hart CLINT level interrupts, in the mclk domain, the same domain as this vesta's free-running clk.
        -- Its irq_handler clocks on clk, so msip/mtip can wake a hart whose gated clk_cpu is OFF in SLEEPING.
        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';

        -- External (peripheral) interrupt wire, the irq_router's registered per-hart claim/complete output.
        -- It lands on IVT slot 85 (IRQB_EXT_MEIP), and the ISR discovers the source by READING the router's CLAIM word.
        meip_in   : in  std_logic := '0';

        -- Core-side debug interface: mclk domain, boundary-registered at the SAME depth 1 as the req/gnt set, with no exemption of the kind `sleep` and the flash ports get.
        -- BOTH INPUTS DEFAULT '0', the fail-safe direction: a top with no Debug Module leaves all three unconnected and every tile boots exactly as it would without them, where a '1' default would halt the chip out of reset.
        dbg_haltreq      : in  std_logic := '0';
        dbg_resethaltreq : in  std_logic := '0';
        dbg_halted       : out std_logic;

        /* Extended-flash / XIP port (adddec's extended-flash decode, enabled in every tile so the netlists match).
           Only the flash-boot hart wires SPI0 here; other tiles leave the outputs open and flash_dout at its zeros default, so their extended-flash accesses read ZEROS and never stall.
           NOT boundary-registered: flash_clk_mem is a GATED CLOCK. */
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- Shared-window master port, feeding one mp_arbiter master slice in MCU.vhd.
        -- req is held until done (a 1-cycle pulse); addr/wdata are stable across the wait because the core's clk_cpu is gated off while stalled.
        sh_req    : out std_logic;
        sh_we     : out std_logic_vector(3 downto 0);  -- active-high byte-lane strobes, so sub-word shared stores work
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');
        -- Global LR/SC: transaction tag out ("01" LR read, "10" SC write attempt), resv_unit SC verdict in (valid with sh_done, latched here).
        sh_lrsc   : out std_logic_vector(1 downto 0);
        sh_scfail : in  std_logic := '0';
        -- This hart's GLOBAL reservation-valid level from resv_unit, valid every cycle and boundary-registered like sh_scfail.
        -- The Zawrs wait wakes when it drops to '0', meaning a foreign store killed the LR; it defaults '1' so a single-master top is a no-op.
        sh_resv_valid : in std_logic := '1';
        -- Grant-lock request to mp_arbiter, the core's amo_lock, held high for the whole AMO read-modify-write flow so the arbiter pins the grant to this hart between the AMO's read and write transactions.
        sh_lock   : out std_logic;

        -- TCM macro power gate: the management hart takes BLOCKPWR's RAMOFF here for software power gating, other tiles tie '0'.
        tcm_pgen  : in  std_logic := '0';

        -- TCM retention control, strapped '1' (retention disabled) from the ALWAYS-ON MCU top, because the macro's RETN receiver sits on the always-on rail.
        -- An in-tile tie on the switched rail would die in sleep, crowbarring the macro and entering retention mode uncommanded.
        tcm_retn  : in  std_logic := '1';

        /* =====================================================================
           READ-ONLY EXTERNAL TCM SLAVE PORT: mclk domain, boundary-registered at the SAME depth 1 as the req/gnt set, but its OWN transaction set, since the one-depth rule is about skew between signals of ONE transaction.
           PROTOCOL, deliberately the sh_done shape: tcm_ext_req is held until tcm_ext_done, a ONE-mclk PULSE with tcm_ext_rdata valid alongside it and holding until the next completion; tcm_ext_addr is a TCM WORD index (12 bits = the ram0 A bus = data_addr(13:2)), so word i is byte address 0x8000 + 4*i.
           AFTER done, tcm_ext_req MUST RETURN LOW FOR AT LEAST ONE mclk: the sequencer's one-shot rearms on req being low, so a requester holding req high across two transactions gets ONE done and then waits forever.
           All three inputs default to the FAIL-SAFE direction, req = '0' being "nobody is asking", which leaves the stall term constant '0' and the ram0 mux constant on the core side, so a top naming none of these ports behaves bit-identically; the port is memory architecture, not a knob-gated feature.
           ===================================================================== */
        tcm_ext_req   : in  std_logic := '0';
        tcm_ext_addr  : in  std_logic_vector(11 downto 0) := (others => '0');
        tcm_ext_rdata : out std_logic_vector(31 downto 0);
        tcm_ext_done  : out std_logic;

        /* MTCMOS domain controls from pwr_ctrl; no tile RTL consumes them, and an always-on tile ties both '0' so every instance stays ONE netlist.
           pd_sleep is the CPF hook driving the HEAD switch fabric's SLEEP daisy chain, ACTIVE-HIGH meaning the switched rail is OFF; pd_iso_en is RESERVED, because the output clamps are explicit AND gates on the ALWAYS-ON MCU side of the boundary.
           NOT boundary-registered, since always-on controls must stay valid while every flop in the switched domain is dark; the cold-gate reset arrives through the ordinary resetn port, which is what makes reset values equal clamp-0 values on every outbound signal. */
        pd_sleep  : in  std_logic := '0';
        pd_iso_en : in  std_logic := '0';

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of hart_tile is

    -- The vesta core; hart_id is a port, so every tile instance is one netlist.
    component vesta
        generic (
            PC_RST_VAL : std_logic_vector(31 downto 0);
            NUM_IRQS  : natural;
            ENABLE_MUL        : boolean := true;
            ENABLE_DIV        : boolean := true;
            ENABLE_ATOMICS    : boolean := true;
            ENABLE_COMPRESSED : boolean := true;
            ENABLE_BITMANIP   : boolean := true;
            -- optional ISA extensions (all default false)
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
            -- privileged architecture (all default false / 16)
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

            -- debug interface (inert defaults; see the vesta entity)
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

    -- SH_AW-derived all-zero comparators for the sh_sel decode below.
    -- SH_WIN_ZERO qualifies the whole window (addr(31:SH_AW+2) = 0); SH_TCM_ZERO qualifies the TCM carve-out's upper bits (addr(SH_AW+1:16) = 0).
    constant SH_WIN_ZERO : std_logic_vector(31 downto SH_AW+2) := (others => '0');
    constant SH_TCM_ZERO : std_logic_vector(SH_AW+1 downto 16) := (others => '0');

    -- Exactly three live IVT slots, meip (85) plus the CLINT pair (83/84), all hardwire-enabled; routing and masking live in the irq_router rows.
    -- Every other slot is constant '0' in BOTH the vector and the enables, so synthesis prunes the core's NUM_IRQS-wide priority encoder and in-service tracking down to the three live sources.
    constant TILE_IRQ_EN : std_logic_vector(NUM_IRQS-1 downto 0) :=
        (IRQB_EXT_MEIP => '1', IRQB_CLINT_MSIP => '1', IRQB_CLINT_MTIP => '1',
         others => '0');
    -- Priority all-low and recursion off, both fixed.
    constant TILE_IRQ_PRI : std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');

    signal tile_irq_vec  : std_logic_vector(NUM_IRQS-1 downto 0);

    -- Delayed core reset release, held until the boot fetch has landed in the clk_cpu consumption stage (see core_rst_stretch below).
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

    -- unused decoder outputs: there is no private peripheral page
    signal mem_en_periph : std_logic_vector(15 downto 0);
    signal clk_periph    : std_logic_vector(15 downto 0);

    -- shared-window master state
    signal sh_sel         : std_logic;
    signal sh_dphase      : std_logic := '0';  -- clk_cpu-domain: shared access in data phase
    signal sh_acked       : std_logic := '0';
    signal sh_acked_we    : std_logic_vector(3 downto 0) := (others => '0'); -- lanes of the acked txn
    signal sh_acked_addr  : std_logic_vector(SH_AW-1 downto 0) := (others => '0'); -- word addr of the acked txn
    signal sh_ack_ok      : std_logic;          -- ack valid FOR THE CURRENT ACCESS TYPE
    signal sh_we_lanes    : std_logic_vector(3 downto 0);
    signal sh_rdata_reg   : std_logic_vector(31 downto 0) := (others => '0');
    -- clk_cpu-STAGED copy of sh_rdata_reg, the value the core actually consumes: KEEP IT, because sh_rdata_reg is an mclk landing register and a core executing FROM the shared window would otherwise have its in-flight INSTRUCTION overwritten mid-cycle by the next completion.
    -- The stage replicates the private RAM's Q contract: it freezes with the core and picks up the landed value at the stall-ending edge, one completion per stretched cycle.
    signal sh_rdata_cpu   : std_logic_vector(31 downto 0) := (others => '0');
    signal sh_scfail_reg  : std_logic := '0';   -- resv_unit SC verdict, latched at done
                                                -- NOT staged: SC_CHECK consumes the verdict in its own stretched cycle, at the end edge.
    signal core_read_data : std_logic_vector(31 downto 0);
    signal mem_ready_sh   : std_logic;
    signal lr_sc_bus      : std_logic_vector(1 downto 0);

    /* =========================================================================
       REGISTERED TILE BOUNDARY (depth 1, mclk): outbound req/we/addr/wdata/lrsc/lock, inbound gnt/done/rdata/scfail plus msip/mtip/meip.
       ONE depth for ALL of them, and do not change one alone: skew between req and addr/wdata/lrsc corrupts the arbiter's IDLE sample, and rdata/scfail must stay aligned with done (value-with-pulse).
       NOT registered: sleep and the flash/XIP ports (gated clock, sleep race), hart_id (static strap), trap_flag/a0 (quasi-static observation).
       =========================================================================
       Internal (pre-boundary) nets for signals that used to drive ports. */
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
    signal bnd_resvvld_r  : std_logic := '1';   -- registered resv-valid level for Zawrs
    signal bnd_msip_r     : std_logic := '0';
    signal bnd_mtip_r     : std_logic := '0';
    signal bnd_meip_r     : std_logic := '0';
    -- Debug interface, same depth-1 boundary; inbound requests reset '0' (fail-safe: no halt is being asked for) and the outbound halted level resets '0'.
    signal bnd_haltreq_r  : std_logic := '0';
    signal bnd_rsthalt_r  : std_logic := '0';
    signal dbg_halted_int : std_logic;
    signal bnd_halted_r   : std_logic := '0';

    /* =========================================================================
       State for the external TCM slave port, all in the FREE-RUNNING mclk domain, which is the point: the requester must make progress while this tile's clk_cpu is gated off underneath it.
       No synchronisers here and none are wanted, since clk_cpu is a GATED SUBSET of clk and they are the same clock; NEVER put a set_clock_groups on the pair, which deletes real paths.
       =========================================================================
       Depth-1 inbound boundary stage. */
    signal tx_req_r      : std_logic := '0';
    signal tx_addr_r     : std_logic_vector(11 downto 0) := (others => '0');
    -- Depth-1 outbound boundary stage.
    -- tx_rdata_r is SIMULTANEOUSLY the Q landing register and the boundary register, ONE flop and not two: that identity is what keeps rdata aligned with the done pulse, since the same edge of the same process writes both.
    signal tx_rdata_r    : std_logic_vector(31 downto 0) := (others => '0');
    signal tx_done_r     : std_logic := '0';

    -- The four-state sequencer.
    -- std_logic_vector rather than an enum, so the state can be dumped into an SHM waveform DB from tcl; enum and integer signals cannot.
    constant TX_IDLE   : std_logic_vector(1 downto 0) := "00";
    constant TX_SETTLE : std_logic_vector(1 downto 0) := "01";
    constant TX_READ   : std_logic_vector(1 downto 0) := "11";
    constant TX_LATCH  : std_logic_vector(1 downto 0) := "10";
    signal tx_state      : std_logic_vector(1 downto 0) := TX_IDLE;

    -- tx_sel is THE MUX SELECT and it is a REGISTER, never the raw request: an asynchronous requester can raise its bit at an mclk edge where the core that owns this SRAM port has an access in flight, and switching the port on the raw bit eats that access.
    signal tx_sel        : std_logic := '0';
    signal tx_served     : std_logic := '0';   -- one-shot (req is held until done)
    -- Raw-OR-delayed stall term: high one full cycle BEFORE the mux switches to the external side, and one full cycle AFTER it switches back.
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

    -- THE Q SHADOW (see the comment at the shadow process).
    -- The vendor SRAM's Q is a continuous function of its LATCHED address, so an external read DESTROYS whatever the frozen core was still holding on mem_dout(1); these signals give the core its own value back across the window.
    signal tcm_q_shadow  : std_logic_vector(31 downto 0) := (others => '0');
    -- The hold is a TWO-FLOP HANDSHAKE across the two clocks, one mclk flop that ARMS and one clk_cpu flop that DISARMS, and tcm_q_hold is their inequality.
    signal tcm_q_arm     : std_logic := '0';   -- mclk domain: an external read happened
    signal tcm_q_ack     : std_logic := '0';   -- clk_cpu domain: the core has resumed
    signal tcm_q_hold    : std_logic;

begin

    -- Boundary registers.
    -- Both stages clock on the free-running mclk and reset with the chip resetn, because the boot fetch must flow while the CORE reset is still stretched.
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

    /* =========================================================================
       Debug boundary stage: SAME clock, SAME reset, SAME depth 1 as bnd_in/bnd_out, and its own transaction set, unrelated to req/gnt.
       IN ITS OWN GENERATE PAIR because a boundary register has no ENABLE_ term to fold it away, so ungated these three flops would be the one part of the debug interface a knob-OFF build still paid for.
       When OFF, dbg_halted is a hard constant '0': a chip with no debug interface never reports itself halted.
       ========================================================================= */
    gen_dbg_bnd: if ENABLE_DEBUG generate
        -- dbg_resethaltreq crosses this flop too, so it is one mclk late at the tile reset edge, and that is fine: the core samples it ONCE at its own reset release, which cannot happen until the boot fetch has crossed the arbiter and landed, strictly after this flop has settled.
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

    /* =========================================================================
       External-TCM-port INBOUND boundary stage, same clock, reset and depth 1 as bnd_in/bnd_out, and its own transaction set: req/addr are one transaction, rdata/done are one value-with-pulse pair.
       The OUTBOUND stage is tx_rdata_r/tx_done_r in tx_port_fsm below, which are the boundary registers AND the landing registers, deliberately the same flops.
       Reset drives tx_req_r to '0', which makes "a request during reset is IGNORED" structural: the sequencer cannot see a request, and the SRAM is never clocked from this side, while resetn is low.
       ========================================================================= */
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

    -- Three live slots, meip (the router's claim/complete stage) plus this hart's own CLINT pair; everything else is constant '0' and the enables are the hardwired TILE_IRQ_EN constant.
    tile_irq_proc: process(bnd_meip_r, bnd_msip_r, bnd_mtip_r)
    begin
        tile_irq_vec <= (others => '0');
        tile_irq_vec(IRQB_EXT_MEIP)   <= bnd_meip_r;
        tile_irq_vec(IRQB_CLINT_MSIP) <= bnd_msip_r;
        tile_irq_vec(IRQB_CLINT_MTIP) <= bnd_mtip_r;
    end process;

    -- The reset vector 0x0 is the SHARED boot ROM, so the first fetch is a multi-cycle arbiter transaction and no fixed-length reset release can guarantee a primed instruction bus.
    -- The core is instead held in reset until its boot fetch has LANDED in the clk_cpu consumption stage, i.e. until sh_dphase = '1' means "the boot instruction is on the core's read bus"; the release is sticky and latency-insensitive by construction.
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
            resetn      => resetn_core,   -- delayed release: the boot fetch must be primed first
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
            resv_valid_ext => bnd_resvvld_r,   -- registered resv-valid level for Zawrs
            amo_lock     => amo_lock_int,

            irq_vector       => tile_irq_vec,
            irq_priority     => TILE_IRQ_PRI,
            irq_en           => TILE_IRQ_EN,
            irq_recursion_en => '0',
            isr_ret          => open,

            -- boundary-registered request levels in, halted level out at the same depth
            dbg_haltreq      => bnd_haltreq_r,
            dbg_resethaltreq => bnd_rsthalt_r,
            dbg_halted       => dbg_halted_int,

            trap_flag    => trap_flag,
            a0           => a0
        );

    -- The extended-flash decode is enabled in EVERY tile so the netlists stay identical; only the flash-boot hart has SPI0 behind the flash ports.
    adddec0: adddec
        generic map (
            ENABLE_FLASH_EXTENDED_MEM => true,
            -- The flash decode must stay the strict complement of this tile's SH_AW-derived sh_sel window, or the two decoders double-claim an address and deadlock.
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

    /* =========================================================================
       SHARED-WINDOW MASTER, tile-internal.
       =========================================================================
       Everything in the window except the private TCM (0x8000-0xBFFF) is shared: the boot ROM, the peripheral window, the NPU staging RAM and the bulk RAM, i.e. 0x0 to 2**(SH_AW+2)-1 minus the TCM.
       The upper-bit qualification must stay EXACT: a loose decode aliases extended-flash addresses back into the window, and adddec asserts no enable for any shared region, so the two decoders can never double-claim an address. */
    sh_sel <= '1' when data_addr(31 downto SH_AW+2) = SH_WIN_ZERO
                   and not (data_addr(SH_AW+1 downto 16) = SH_TCM_ZERO
                            and data_addr(15 downto 14) = "10")
                   else '0';

    /* One-shot handshake on the FREE-RUNNING clk: request until this access completes, then hold off re-request until the core steps off the shared address.
       The stall source must run free, because a hart gated off cannot clock its own release; clk_cpu is gated while stalled, so data_addr/wen/write_word are stable across the wait.

       The ack is qualified by BOTH the LANE STROBES and the WORD ADDRESS of the completed transaction, and both qualifications are load-bearing.
       Without the lanes an SC loses its conditional write, absorbed by its own EXECUTE-cycle read's ack at the same address; without the address, code executing FROM the shared window absorbs sequential fetches into one stale sh_rdata_reg and re-executes one instruction forever.
       Same-word, same-lane re-access still holds the ack, which is what a compressed pair in one word, a `j .` self-loop and an AMO's re-read of its EXECUTE-cycle word rely on. */
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
                -- done/rdata/scfail arrive through the inbound boundary stage, keeping their value-with-pulse alignment because they share a depth.
                sh_acked      <= '1';
                sh_acked_we   <= sh_we_lanes;
                sh_acked_addr <= data_addr(SH_AW+1 downto 2);
                sh_rdata_reg  <= bnd_rdata_r;   -- capture shared read data
                sh_scfail_reg <= bnd_scfail_r;  -- capture resv_unit SC verdict
            end if;
        end if;
    end process;

    -- wen is ACTIVE-LOW per byte lane and the arbiter's we is active-high per lane; write_word is lane-positioned by the core's store extender, which is what makes sb/sh work.
    -- The lanes feed BOTH the outbound boundary stage and the ack comparison below, and the comparison stays on the RAW lanes: it is the frozen core comparing its own current access against the acked one.
    sh_we_lanes <= (not wen_re) when sh_sel = '1' else (others => '0');

    sh_ack_ok <= '1' when sh_acked = '1' and sh_acked_we = sh_we_lanes
                      and sh_acked_addr = data_addr(SH_AW+1 downto 2) else '0';

    -- The chip resetn masks the power-on settle window from the arbiter, and the request must still flow during the stretched priming window (resetn high, resetn_core low) because it IS the boot fetch.
    -- Its inputs are defined there by construction: the nop-forced read bus keeps decode defined and the core's reset arm pins data_addr at PC_RST_VAL; these are the PRE-boundary nets, the ports carry their registered copies.
    sh_req_int  <= sh_sel and not sh_ack_ok and resetn;
    sh_lrsc_int <= lr_sc_bus when sh_sel = '1' else "00";

    /* Back-pressure into the core: two independent stall sources ANDed, the shared-window transaction (an identity while sh_sel = '0') and the external TCM read (an identity while nobody asks).
       mem_ready is the ONLY hook either may use, and NEVER `sleep`: the core's clock gate ranks mem_ready top but puts sleep below irq_active / std_irq_take / std_wfi_wake / dbg_halt_pend, any of which would un-freeze the core mid external SRAM access with the ram0 mux pointed the other way.
       `sleep` is also unregistered by contract, which is the second reason it can never carry this. */
    mem_ready_sh <= ((not sh_sel) or sh_ack_ok) and (not tx_busy);

    -- Read-data mux, DATA-PHASE ONLY, with the select registered on the tile's own gated clk_cpu BY DESIGN: a raw-sh_sel mux on read_data is a zero-delay oscillation, because read_data is the instruction during decode and sh_sel derives combinationally from it.
    -- sh_dphase is '1' exactly during the MEMORY_WAIT cycle, where read_data is consumed as LOAD DATA and the instruction comes from the held instr_curr_prev.
    sh_dphase_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            sh_dphase   <= '0';
            sh_rdata_cpu <= (others => '0');
        elsif rising_edge(clk_cpu) then
            sh_dphase   <= sh_sel;
            -- Consumption stage: re-latching a stale landing value is harmless, what matters is that this register can NEVER change inside a stretched core cycle.
            sh_rdata_cpu <= sh_rdata_reg;
        end if;
    end process;

    -- Nop-force the instruction bus until the STRETCHED core reset releases: adddec's own nop arm uses the early chip resetn and drops a couple of cycles sooner, exposing a memory whose Q has never been clocked.
    -- Without this, that X instruction feeds pc_next, then data_addr, then decode, then the select, a self-sustaining X loop on the unified bus.
    core_read_data <= nop          when resetn_core = '0' else
                      sh_rdata_cpu when sh_dphase = '1'   else read_data;

    -- The TCM is the tile's only private memory: region 000 is the SHARED boot ROM and 0xC000-0xFFFF the SHARED NPU staging RAM, both reached via sh_sel through the arbiter.
    -- adddec asserts no enable for either, so its slots 0 and 2 read zeros.
    mem_dout(0) <= (others => '0');
    mem_dout(2) <= (others => '0');

    /* =========================================================================
       THE EXTERNAL TCM READ SEQUENCER: four states, one SRAM read, everything on the free-running mclk.
       Timing from E, the mclk edge at which the inbound boundary register first sees the request: SETTLE at E+1 switches the mux, READ at E+2 holds CEN low, the read happens at E+3, and E+4 latches Q into tx_rdata_r with the done pulse and returns the mux.
       Latency is therefore FIVE mclk from E to the requester sampling done, six from the requester's own drive edge, and the core loses seven clk_cpu edges per transaction.

       tx_busy is raw-OR-delayed rather than just tx_sel, which buys the LEAD and the LAG around the mux switch, and both are required: it rises a full cycle before tx_sel, so the core's last edge is strictly before the mux moves, and it stays high until tx_req_r falls, so the core's first edge back is well after the mux returned.
       NO DEADLOCK, including a tile reading its own aperture address while already stalled on the shared window, because NEITHER SIDE EVER WAITS ON THE CORE: tx_state, tx_sel and the SRAM clock are all on the free-running clk and reach LATCH in four edges regardless.
       A back-to-back request stream costs THROUGHPUT, not liveness: tx_busy must go low for a full cycle before tx_req_r can be re-registered high, so the core still gets one clk_cpu edge per request.
       tx_served is the one-shot, set at LATCH and cleared whenever tx_req_r is low, because req is held until done and the sequencer must not re-trigger on the tail of the request it already answered.
       ========================================================================= */
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
                    -- The mux moved on the edge that entered this state, and the SRAM is deliberately NOT clocked during it.
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
            -- One-shot rearm, written after the case on purpose: at LATCH the request is still high, so the case arm's '1' must win, and a request that has already dropped by then simply rearms a cycle earlier.
            if tx_req_r = '0' then
                tx_served <= '0';
            end if;
        end if;
    end process;

    -- Raw-OR-delayed stall term; see the lead/lag note above.
    tx_busy <= tx_req_r or tx_sel;

    /* The external side's SRAM clock is a GATED mclk, not raw mclk, and that is not a power optimisation: it is what makes the clock MUX below glitch-free.
       tx_ext_clk pulses exactly once, at the edge leaving TX_READ, so at both switch instants BOTH mux inputs are low (clk_mem(1) because the core's clk_cpu has been gated off since the lead cycle) and the mux cannot glitch.
       Switching a raw mclk in on a rising edge would instead manufacture a spurious SRAM clock edge at the switch instant. */
    tx_clk_en <= '1' when tx_state = TX_READ else '0';
    tx_cen    <= '0' when tx_state = TX_READ else '1';

    cg_tcm_ext: entity work.ClkGate
        port map (
            ClkIn  => clk,
            En     => tx_clk_en,
            ClkOut => tx_ext_clk
        );

    /* -------------------------------------------------------------------------
       THE 6-PIN ram0 MUX {CLK, CEN, WEN, GWEN, A, D}, selected by tx_sel, REGISTERED, never the raw request.
       READ-ONLY IS ENFORCED HERE AND ONLY HERE, structurally: on the external side WEN is the all-inactive "1111" constant and GWEN the '1' constant, so no state of this port, no value of tcm_ext_addr and no fault on tcm_ext_req can produce a write.
       D is a don't-care there and is driven to zeros rather than left on write_data, so a waveform shows unambiguously that nothing was offered to the array; the tool constant-folds these arms, which is fine, because the constants are the specification.
       ------------------------------------------------------------------------- */
    ram_clk  <= tx_ext_clk when tx_sel = '1' else clk_mem(1);
    ram_cen  <= tx_cen     when tx_sel = '1' else mem_en(1);
    ram_wen  <= "1111"     when tx_sel = '1' else wen_fe;      -- READ-ONLY
    ram_gwen <= '1'        when tx_sel = '1' else GWEN;        -- READ-ONLY
    ram_a    <= tx_addr_r  when tx_sel = '1' else mem_addr;
    ram_d    <= (others => '0') when tx_sel = '1' else write_data;

    /* -------------------------------------------------------------------------
       THE Q SHADOW, and why the mux above is not sufficient on its own.
       The vendor SRAM's Q is not a per-access strobe but a CONTINUOUS function of the address latched by the last access, and the core relies on that: it issues a TCM read at clk_cpu edge k and consumes Q combinationally through adddec's out_buff at edge k+1.
       Freezing the core is therefore not enough, because an external request is asynchronous and can land on edge k: the external read relatches the address, Q changes underneath the frozen core, and at its resume edge the core consumes THE EXTERNAL WORD as its own load result or instruction.

       INVARIANT, the whole specification of this block: WHILE THE CORE IS FROZEN, mem_dout(1) MUST NOT CHANGE, which is what an undisturbed SRAM does on its own.
       tcm_q_shadow tracks Q every mclk while the port is idle and tcm_q_hold selects it while the core is frozen with that word still owed to it; at the resume edge the core samples the pre-edge value, the shadow, and the same edge re-issues its own access and refreshes the real Q.

       THE HOLD MUST BE RELEASED BY EVIDENCE THAT THE CORE TOOK AN EDGE, NEVER BY A COUNT: a hart reading its OWN TCM window stays frozen on mem_ready_sh for the whole arbiter transaction, strictly longer than tx_busy, and a timer would leave it staring at live Q holding the EXTERNAL address.
       tcm_q_arm (mclk) toggles when tx_busy is seen and the hold is not already up, so re-arming while armed is a deliberate no-op, while tcm_q_ack (clk_cpu) copies it on every core edge and so disarms at the first core edge after the freeze, however long it was.
       The two can never move on the same edge, which is what makes the handshake safe without a synchroniser: arming needs tx_busy = '1' in the cycle before the edge, which is exactly when the ClkGate has already killed that clk_cpu edge.

       IT CANNOT WEDGE: tcm_q_hold feeds ONE mux on the core's read data and sits in no handshake, ready or request, so a core that never takes another edge simply keeps being shown the last word it read while the port keeps completing transactions out of tx_rdata_r.
       ------------------------------------------------------------------------- */
    tcm_q_shadow_reg: process(clk, resetn)
    begin
        if resetn = '0' then
            tcm_q_arm    <= '0';
            tcm_q_shadow <= (others => '0');
        elsif rising_edge(clk) then
            -- ARM: `tcm_q_arm = tcm_q_ack` means "not currently held", and re-arming while held would cancel the hold, the one thing this handshake must never do.
            if tx_busy = '1' and tcm_q_arm = tcm_q_ack then
                tcm_q_arm <= not tcm_q_arm;
            end if;
            -- The shadow tracks Q whenever it is not the thing being shown.
            -- Reading the PRE-edge hold is what puts its LAST capture one edge INSIDE the freeze, where Q is still the core's own word, two edges before the external read.
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

    -- A power-gated tile's outputs are iso-clamped to 0 on the always-on MCU side, so its window reads ZEROS by design and, because the SAME clamp zeroes done, the tile NEVER COMPLETES A TRANSACTION.
    -- An MCU aperture slave must therefore synthesise its own zero-completion from the pwr_ctrl row that drives the clamp, rather than waiting on a wire held low on purpose.
    tcm_ext_rdata <= tx_rdata_r;
    tcm_ext_done  <= tx_done_r;

    /* -------------------------------------------------------------------------
       Private TCM (RAM0, based at RamStartAddress): IVT, code, data and stack, NOT preloaded.
       Like silicon it powers up unknown and software owns write-before-read; every pin except EMA/RETN/PGEN arrives through the external read port's mux above, and Q leaves through the shadow.

       THE MACRO IS SELECTED BY RamSize (MemoryMap.vhd), not hardcoded -- 2026-08-16, when the shipped default TCM dropped from 16 KiB to 8 KiB (USER directive: "make each tile as small as possible"). The two vendor macros are pin-identical apart from the address bus and, usefully, THE SAME WIDTH:
           sram1p16k_hvt_pg  4096 x 32  A(11:0)  319.65 x 383.085 um
           sram1p8k_hvt_pg   2048 x 32  A(10:0)  319.65 x 208.675 um
       so the swap is 174.41 um of HEIGHT out of the tile and nothing off its X axis -- which is why the U-notch floorplan's width survives it.
       Selecting on the constant rather than editing the entity name keeps ONE authority for the TCM size: memory.tcmSizePerHart -> RamSize -> this generate. Hardcoding the 8 KiB macro would have let a 16 KiB configuration emit a memory map promising 0x8000-0xBFFF over an array that answers only half of it.
       A configuration that asks for neither size fails ELABORATION here rather than quietly picking one; the sizes the knob permits and the macros the kit provides are not the same set (the knob allows any 1 KiB multiple up to 0x4000), so this is a real guard, not a formality.

       ADDRESS ALIASING, stated because the map depends on it: mem_addr and tx_addr_r are 12 bits either way. At 8 KiB the top bit is simply not connected, so the array repeats twice across the 16 KiB the decode still routes here -- which is exactly what makes the 16 KiB read-only aperture at 0x20000 + 0x4000*h show an 8 KiB TCM MIRRORED, the behaviour generate.py documents and the TRM draws.
       ------------------------------------------------------------------------- */
    gen_tcm_16k: if RamSize = 16384 generate
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
    end generate;

    gen_tcm_8k: if RamSize = 8192 generate
        ram0: entity work.sram1p8k_hvt_pg
            port map (
                Q     => tcm_q,
                CLK   => ram_clk,
                CEN   => ram_cen,
                WEN   => ram_wen,
                A     => ram_a(10 downto 0),   -- ram_a(11) unused: the array mirrors across the 16 KiB the decode routes here
                D     => ram_d,
                EMA   => "000",
                GWEN  => ram_gwen,
                RETN  => tcm_retn,
                PGEN  => tcm_pgen
            );
    end generate;

    -- No macro for this RamSize: fail at elaboration, never silently.
    assert RamSize = 16384 or RamSize = 8192
        report "hart_tile: RamSize = " & integer'image(RamSize) & " has no TCM macro (kit provides sram1p16k_hvt_pg and sram1p8k_hvt_pg only)"
        severity failure;

end architecture;
