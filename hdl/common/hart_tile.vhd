-- =============================================================================
-- hart_tile.vhd  (M3b; M11 memory-map rework; M12 single-ROM boot; M13 tile)
-- =============================================================================
-- One self-contained hart with PRIVATE memory: a vesta core + its own address
-- decoder + private TCM (RAM0, 0x8000-0xBFFF). M11 retired the tile's dead
-- boot ROM and its private RAM1 (0xC000 is now the SHARED NPU staging RAM
-- behind the arbiter); M12 retired the preloaded-TCM boot fiction: every
-- hart resets to PC 0x0 and fetches the SHARED boot ROM through the
-- arbiter (mhartid dispatch in the bootrom parks tiles until hart 0
-- ignites them via CLINT msip). Everything except the TCM reaches the MCU
-- control plane through the shared-window master port below.
--
-- M13 TILE EXTRACTION: this entity is now THE hart tile for ALL FOUR harts —
-- hart 0 included (MCU.vhd's inline hart-0 core/adddec/ram0/sh-machinery was
-- this file's mirror since M3c; it is folded in here and deleted there). All
-- four instances are STRUCTURALLY IDENTICAL (one netlist -> one hardened
-- tile in M14); every per-instance difference is expressed by WIRING only:
--   * hart_id      — mhartid CSR value, a PORT (the vesta HARTID generic is
--                    retired for the same one-netlist reason).
--   * flash/XIP    — the adddec >=0x20000 extended-flash decode is enabled
--                    in EVERY tile; hart 0 wires flash_mem_en/flash_clk_mem/
--                    flash_mab/flash_dout to SPI0 and sleep to SPI0's
--                    disable_clk_cpu (XIP stall). Tiles 1-3 leave the
--                    outputs open and the inputs at their defaults: a tile
--                    access >=0x20000 then reads ZEROS and never stalls
--                    (the XIP stall is SPI0's sleep, not adddec) — same
--                    "undefined on unmapped" class as always. The flash
--                    ports and sleep are NOT boundary-registered:
--                    flash_clk_mem is a GATED CLOCK, and a one-cycle-late
--                    sleep would let the core consume garbage flash_dout
--                    (they become hart-0 tile timing-budget pins in M14).
--   * IRQ source   — M19: IDENTICAL on every hart (hart 0 included — the
--                    SYSTEM0 vectored path and hw_clint_en are retired).
--                    Three per-hart level wires cross the boundary: msip/
--                    mtip from the CLINT and meip from the irq_router's
--                    claim/complete stage (IVT slot 85 = IRQB_EXT_MEIP).
--                    All three slots are hardwire-enabled; ALL routing/
--                    masking lives in the router's per-hart rows @0x7000
--                    (reset all-masked — the old SYS_IRQ_EN reset semantics
--                    hold chip-wide by construction). Priority/recursion
--                    are tied off: with three live slots the in-core
--                    priority machinery constant-propagates away.
--   * tcm_pgen     — hart 0's TCM keeps its BLOCKPWR software power gating
--                    (pgen_mem(1)); tiles tie '0'.
--   * pd_sleep/pd_iso_en (M17) — MTCMOS power-gating controls from pwr_ctrl
--                    for tiles 1-3; hart 0 ties both '0' (always-on). CPF
--                    hooks only — see the port comment.
-- The M2 wait_inj0 stall exerciser on hart 0's mem_ready is RETIRED here:
-- its latency-tolerance job is done (M10 proved the protocol at boundary
-- depths 0/1/2; the M12 boot fetch exercises it every run).
--
-- Each tile replicates the *unchanged* single-core core<->adddec<->RAM path,
-- so there is NO cross-hart grant-switching hazard on the fetch/load pipeline
-- (see ~/vesta_docs/multicore_plan.md, "GRANT-SWITCHING HAZARD").
--
-- M3c.4: the tile is a REAL master of the MCU-level shared window (behind
-- mp_arbiter on the free-running mclk), per the M3c wiring proven on hart 0
-- (see the M3c.3 post-mortem in ~/vesta_docs/multicore_plan.md):
--   * sh_sel   = decode of the SHARED regions (M11/M12): boot ROM 0x0-0x3FFF,
--                the peripheral window 0x4000-0x7FFF, the NPU staging RAM
--                0xC000-0xFFFF and the bulk RAM 0x10000-0x1FFFF = addr(31:17)=0
--                AND region /= "010". Exact upper-bit qualification (31:17)=0
--                keeps >=0x20000 extended-flash addresses OUT of the window (a
--                loose decode aliases flash back into it - bug 2 class).
--   * sh_acked = one-shot handshake flop on MCLK (the stall source must run
--                free; a hart gated off can't clock its own release).
--   * sh_dphase= sh_sel registered on the tile's own gated clk_cpu - BY
--                DESIGN: vesta's unified bus uses read_data as the INSTRUCTION
--                during decode, and data_addr/sh_sel derive combinationally
--                from it, so a raw-sh_sel read-data mux is a zero-delay
--                oscillation (bug 4). The registered select is '1' exactly
--                during the MEMORY_WAIT data phase.
--   * mem_ready = (not sh_sel) or sh_ack_ok - freezes the core (clk_cpu gate)
--                for the whole arbiter transaction, inside the EXECUTE cycle.
-- M4a: sh_we carries the 4 byte-lane strobes (active-high), so sub-word
-- shared stores (sb/sh) work — write_word is lane-positioned by the core.
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
        SH_AW          : natural := 15;  -- shared-window word-address width (must match mp_arbiter;
                                         -- M11 default 15 covers 0x00000-0x1FFFF. A2: also DRIVES the
                                         -- sh_sel window decode and adddec's complementary flash
                                         -- decode below — 16 = the Argus shape, window 0x0-0x3FFFF,
                                         -- flash from 0x40000)

        -- Core ISA feature switches, passed straight down to vesta (see
        -- vesta.vhd). Config-driven from generate.py via the MemoryMap
        -- package constants in the hartN generic maps; defaults keep every
        -- existing instantiation (testbenches, genus tile hardening) on the
        -- full RV32IMAC+Zb* core. NOTE: all four tile instances must get the
        -- SAME values — the tile is hardened once (M14, one netlist).
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- X0 ISA-extension scaffolding: all default false, routed straight to
        -- the vesta core. Decode/logic consumed from each generic's phase on.
        ENABLE_ZICOND     : boolean := false;  -- X1 (Zicond)
        ENABLE_ZCB        : boolean := false;  -- X1 (Zcb)
        ENABLE_ZIMOP      : boolean := false;  -- X1 (Zimop/Zcmop)
        ENABLE_ZIHINT     : boolean := false;  -- X1 (Zihintpause/ntl)
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm)
        ENABLE_ZAWRS      : boolean := false;  -- X1 (Zawrs)
        ENABLE_ZABHA      : boolean := false;  -- X2 (Zabha)
        ENABLE_ZACAS      : boolean := false;  -- X2 (Zacas)
        ENABLE_ZBKB       : boolean := false;  -- X3 (Zbkb)
        ENABLE_ZBKC       : boolean := false;  -- X3 (Zbkc)
        ENABLE_ZBKX       : boolean := false;  -- X3 (Zbkx)
        ENABLE_ZKN        : boolean := false;  -- X3 (Zkn = Zknd+Zkne+Zknh)
        ENABLE_ZFINX      : boolean := false   -- X4 (Zfinx)
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        -- hart 0: SPI0's disable_clk_cpu (freezes the core across an XIP
        -- flash access). Tiles: default '0'. NOT boundary-registered — see
        -- the flash/XIP note in the header.
        sleep     : in  std_logic := '0';

        -- M13: mhartid CSR value (was the HARTID generic — a port keeps all
        -- four tile instances one netlist). Static per instance.
        hart_id   : in  std_logic_vector(31 downto 0);

        -- M5b: per-hart CLINT level interrupts (mclk domain -- same domain as
        -- this vesta's free-running clk, and its irq_handler clocks on clk, so
        -- msip/mtip can wake a hart whose gated clk_cpu is OFF in SLEEPING).
        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';

        -- M19: the external (peripheral) interrupt wire — the irq_router's
        -- registered per-hart claim/complete output. Lands on IVT slot 85
        -- (IRQB_EXT_MEIP); the ISR discovers the source by READING the
        -- router's CLAIM word. Replaces the M7a wide fan-out (irq_ext/
        -- irq_en_ext/irq_prio_ext/irq_recursion_en/hw_clint_en/isr_ret
        -- ports are RETIRED — ~255 boundary flops and the per-tile 85-bit
        -- priority bank with them).
        meip_in   : in  std_logic := '0';

        -- M13: extended-flash / XIP port (adddec's >=0x20000 decode, enabled
        -- in every tile). Hart 0 wires SPI0 here; tiles leave outputs open,
        -- flash_dout at its zeros default. NOT boundary-registered (gated
        -- clock + sleep race — see header).
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- M3c.4: shared-window master port -> one mp_arbiter master slice in
        -- MCU.vhd. req/we/addr/wdata out; gnt/done/rdata back. req is held
        -- until done (1-cycle pulse); addr/wdata are stable across the wait
        -- because the core's clk_cpu is gated off while stalled.
        sh_req    : out std_logic;
        sh_we     : out std_logic_vector(3 downto 0);  -- active-high byte-lane strobes (M4a)
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');
        -- M4b: global LR/SC — txn tag out ("01" LR read / "10" SC write
        -- attempt), resv_unit SC verdict in (valid with sh_done; latched here)
        sh_lrsc   : out std_logic_vector(1 downto 0);
        sh_scfail : in  std_logic := '0';
        -- M8: grant-lock request to mp_arbiter — the core's amo_lock, high
        -- for the whole AMO read-modify-write flow so the arbiter pins the
        -- grant to this hart between the AMO's read and write transactions.
        sh_lock   : out std_logic;

        -- M13: TCM macro power gate. Hart 0: BLOCKPWR's RAMOFF via
        -- pgen_mem(1) (software power gating preserved); tiles: '0'.
        tcm_pgen  : in  std_logic := '0';

        -- PG1 (2026-07-10): TCM retention control, strapped '1' (retention
        -- disabled) from the ALWAYS-ON MCU top. Was an in-tile TIEHI on the
        -- switched rail — but the macro's RETN receiver is on the always-on
        -- rail (PG1 finding F2: a dying tie meant sleep-long crowbar in the
        -- macro plus uncommanded retention-mode entry). A port also gives a
        -- future retention stage (M18) its sequencing hook for free.
        tcm_retn  : in  std_logic := '1';

        -- M17: MTCMOS domain controls — no tile RTL logic consumes them.
        -- pd_sleep is the CPF hook (cpf/hart_tile.cpf): it drives the HEAD
        -- switch fabric's SLEEP daisy chain (pmk sense: ACTIVE-HIGH =
        -- switched rail OFF). pd_iso_en is RESERVED at tile level (in-tile
        -- iso is the M17b option): the M17a output clamps are EXPLICIT RTL
        -- AND gates on the ALWAYS-ON MCU side of the boundary (genus cannot
        -- insert location-to iso for a block whose 'to' domain is the
        -- outside world — CPI-319), keyed by the same pwr_ctrl row. Driven
        -- per tile by pwr_ctrl (slot 11, 0x4B00); hart 0 ties both '0'
        -- (always-on) — all four instances stay ONE netlist (M13 wiring-only
        -- rule). NOT boundary-registered: always-on-domain controls must
        -- stay valid while every flop in the switched domain is dark. The
        -- accompanying cold-gate reset arrives through the ordinary resetn
        -- port (pwr_ctrl's pd_rstn ANDed in at the top), which is what makes
        -- reset values == clamp-0 values on every outbound signal.
        pd_sleep  : in  std_logic := '0';
        pd_iso_en : in  std_logic := '0';

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of hart_tile is

    -- vesta core (M13: hart_id is a port, HARTID generic retired)
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
            ENABLE_ZBKB       : boolean := false;
            ENABLE_ZBKC       : boolean := false;
            ENABLE_ZBKX       : boolean := false;
            ENABLE_ZKN        : boolean := false;
            ENABLE_ZFINX      : boolean := false
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
            amo_lock         : out std_logic;

            irq_vector      : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_priority    : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_en          : in  std_logic_vector(NUM_IRQS-1 downto 0);
            irq_recursion_en: in  std_logic;
            isr_ret         : out std_logic;

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
    -- SH_WIN_ZERO qualifies the whole window (addr(31:SH_AW+2) = 0);
    -- SH_TCM_ZERO qualifies the TCM carve-out's upper bits (addr(SH_AW+1:16)
    -- = 0 — one bit at the Castalia SH_AW=15, two at the Argus SH_AW=16).
    constant SH_WIN_ZERO : std_logic_vector(31 downto SH_AW+2) := (others => '0');
    constant SH_TCM_ZERO : std_logic_vector(SH_AW+1 downto 16) := (others => '0');

    -- M19: exactly three live IVT slots — meip (85) + the CLINT pair
    -- (83/84) — all hardwire-enabled; every other slot is constant '0' in
    -- BOTH the vector and the enables, so synthesis prunes the core's
    -- NUM_IRQS-wide priority encoder and in-service tracking down to the
    -- three live sources. Routing/masking lives in the irq_router rows.
    constant TILE_IRQ_EN : std_logic_vector(NUM_IRQS-1 downto 0) :=
        (IRQB_EXT_MEIP => '1', IRQB_CLINT_MSIP => '1', IRQB_CLINT_MTIP => '1',
         others => '0');
    -- priority all-low / recursion off: fixed (the SYSTEM0 knobs are retired)
    constant TILE_IRQ_PRI : std_logic_vector(NUM_IRQS-1 downto 0) := (others => '0');

    signal tile_irq_vec  : std_logic_vector(NUM_IRQS-1 downto 0);

    -- M9b/M12: delayed core reset release — held until the boot fetch has
    -- landed in the clk_cpu consumption stage (see core_rst_stretch below)
    signal boot_fetched   : std_logic := '0';
    signal resetn_core    : std_logic;

    -- core <-> adddec private bus
    signal clk_cpu     : std_logic;
    signal data_addr   : std_logic_vector(31 downto 0);
    signal wen_re      : std_logic_vector(3 downto 0);
    signal write_word  : std_logic_vector(31 downto 0);
    signal read_data   : std_logic_vector(31 downto 0);
    signal mask        : std_logic_vector(1 downto 0);

    -- adddec <-> private memory bus
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
    -- M10: clk_cpu-STAGED copy of sh_rdata_reg — the value the core actually
    -- consumes. sh_rdata_reg is an mclk landing register: when the core
    -- EXECUTES FROM the shared window it is frozen in EXECUTE consuming
    -- sh_rdata_reg as its INSTRUCTION while the next transaction (data load
    -- or next fetch) completes and overwrites it MID-CYCLE — the executing
    -- instruction flips under the core's feet (found by shexec; the private
    -- RAM never does this because its Q only updates at the core's own gated
    -- memory-clock edges). The clk_cpu stage replicates exactly that Q
    -- contract: it freezes with the core and picks up the landed value at
    -- the stall-ending edge — cycle-identical to the old direct consumption
    -- for all data-only traffic (one completion per stretched cycle).
    signal sh_rdata_cpu   : std_logic_vector(31 downto 0) := (others => '0');
    signal sh_scfail_reg  : std_logic := '0';   -- resv_unit SC verdict, latched at done (M4b)
                                                -- (NOT staged: SC_CHECK consumes the verdict
                                                -- in its own stretched cycle, at the end edge)
    signal core_read_data : std_logic_vector(31 downto 0);
    signal mem_ready_sh   : std_logic;
    signal lr_sc_bus      : std_logic_vector(1 downto 0);

    -- =========================================================================
    -- M13 REGISTERED TILE BOUNDARY (depth 1, mclk). Every shared-bus signal
    -- and every IRQ/CLINT level crosses the tile edge through EXACTLY ONE
    -- register stage — outbound req/we/addr/wdata/lrsc/lock, inbound
    -- gnt/done/rdata/scfail (+ msip/mtip/meip — M19: the inbound IRQ stage
    -- shrank from the 3xNUM_IRQS-wide vector/enable/priority banks to these
    -- three level wires). ONE depth for ALL of them: skew between req and
    -- addr/wdata/lrsc corrupts the arbiter's IDLE sample (arb_lat_tb
    -- BREAK_MODE=2 is the proof), and rdata/scfail must stay aligned with
    -- done (value-with-pulse). The arbiter protocol is proven
    -- latency-insensitive at depths 0/1/2 (M10 wait-for-release masking);
    -- the M12 wait-for-boot-fetch reset release is latency-insensitive by
    -- construction. NOT registered (see header): sleep + the flash/XIP
    -- ports (gated clock; sleep race), hart_id (static strap),
    -- trap_flag/a0 (quasi-static observation).
    -- =========================================================================
    -- internal (pre-boundary) nets for signals that used to drive ports
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
    signal bnd_msip_r     : std_logic := '0';
    signal bnd_mtip_r     : std_logic := '0';
    signal bnd_meip_r     : std_logic := '0';

begin

    -- M13 boundary registers. Both stages clock on the free-running mclk and
    -- reset with the chip resetn (the boot fetch must flow while the CORE
    -- reset is still stretched — same qualifier rationale as sh_req_int).
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

    bnd_in: process(clk, resetn)
    begin
        if resetn = '0' then
            bnd_gnt_r      <= '0';
            bnd_done_r     <= '0';
            bnd_rdata_r    <= (others => '0');
            bnd_scfail_r   <= '0';
            bnd_msip_r     <= '0';
            bnd_mtip_r     <= '0';
            bnd_meip_r     <= '0';
        elsif rising_edge(clk) then
            bnd_gnt_r      <= sh_gnt;
            bnd_done_r     <= sh_done;
            bnd_rdata_r    <= sh_rdata;
            bnd_scfail_r   <= sh_scfail;
            bnd_msip_r     <= msip_in;
            bnd_mtip_r     <= mtip_in;
            bnd_meip_r     <= meip_in;
        end if;
    end process;

    -- M19: three live slots — meip (router claim/complete stage) + this
    -- hart's own CLINT pair. Everything else is constant '0'; the enables
    -- are the hardwired TILE_IRQ_EN constant (masking lives in the router).
    tile_irq_proc: process(bnd_meip_r, bnd_msip_r, bnd_mtip_r)
    begin
        tile_irq_vec <= (others => '0');
        tile_irq_vec(IRQB_EXT_MEIP)   <= bnd_meip_r;
        tile_irq_vec(IRQB_CLINT_MSIP) <= bnd_msip_r;
        tile_irq_vec(IRQB_CLINT_MTIP) <= bnd_mtip_r;
    end process;

    -- M9b/M12: the reset vector (0x0) is the SHARED boot ROM since M12 — the
    -- first fetch is a multi-cycle arbiter transaction, so the M9b fixed
    -- two-edge release can no longer guarantee a primed instruction bus.
    -- Instead the core is held in reset until its boot fetch has LANDED in
    -- the clk_cpu consumption stage: during reset the core presents
    -- data_addr = PC_RST_VAL (pc_next_trad's reset arm; nop-forced decode
    -- keeps everything defined), sh_req runs the fetch through the arbiter,
    -- mem_ready stays low so clk_cpu's FIRST edge is the stall-ending edge
    -- after the ack — which stages the fetched instruction into
    -- sh_rdata_cpu and raises sh_dphase. sh_dphase='1' therefore means
    -- "the boot instruction is on the core's read bus": the exact
    -- private-ROM priming contract (M9b), replicated through the arbiter.
    -- Sticky: releases once, stays released. Latency-insensitive by
    -- construction (M12) — unchanged by the M13 boundary registers.
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
            ENABLE_ZBKB       => ENABLE_ZBKB,
            ENABLE_ZBKC       => ENABLE_ZBKC,
            ENABLE_ZBKX       => ENABLE_ZBKX,
            ENABLE_ZKN        => ENABLE_ZKN,
            ENABLE_ZFINX      => ENABLE_ZFINX
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
            read_data    => core_read_data, -- adddec data, or shared-window data in the data phase
            mask         => mask,
            mem_ready    => mem_ready_sh,   -- '1' except during a shared-window transaction

            lr_sc_bus    => lr_sc_bus,
            sc_fail_ext  => sh_scfail_reg,
            amo_lock     => amo_lock_int,

            irq_vector       => tile_irq_vec,
            irq_priority     => TILE_IRQ_PRI,
            irq_en           => TILE_IRQ_EN,
            irq_recursion_en => '0',
            isr_ret          => open,

            trap_flag    => trap_flag,
            a0           => a0
        );

    -- M13: the extended-flash decode is enabled in EVERY tile (identical
    -- netlists); only hart 0 has SPI0 behind the flash ports (see header).
    adddec0: adddec
        generic map (
            ENABLE_FLASH_EXTENDED_MEM => true,
            -- A2: the flash decode is the strict complement of this tile's
            -- SH_AW-derived sh_sel window (M3c.3 double-claim lesson)
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
    -- M11/M12 decode: EVERYTHING in the shared window except the private TCM
    -- (0x8000-0xBFFF) is shared -- boot ROM (M12), peripheral window, NPU
    -- staging RAM, bulk RAM -- under an exact (31:SH_AW+2)=0 qualification
    -- (a loose decode aliases extended-flash addresses back into the window
    -- - bug 2 class / the M3c.3 double-claim deadlock). adddec asserts no
    -- enable for any shared region, so the two decoders can never
    -- double-claim an address.
    -- A2 (Argus): the decode is derived from SH_AW — the window is
    -- 0x0..2^(SH_AW+2)-1 minus the TCM. At the Castalia default (SH_AW=15,
    -- window 0x0-0x1FFFF) this is bit-for-bit the original
    -- (31:17)=0 and (16:14)/="010" decode; at SH_AW=16 (Argus, window
    -- 0x0-0x3FFFF, flash from 0x40000) it is (31:18)=0 and (17:14)/="0010".
    sh_sel <= '1' when data_addr(31 downto SH_AW+2) = SH_WIN_ZERO
                   and not (data_addr(SH_AW+1 downto 16) = SH_TCM_ZERO
                            and data_addr(15 downto 14) = "10")
                   else '0';

    -- one-shot handshake on the FREE-RUNNING clk (mclk): request until this
    -- access completes (done), then hold off re-request until the core steps
    -- off the shared address (clk_cpu is gated while stalled, so
    -- data_addr/wen/write_word are stable across the wait).
    --
    -- M4b: the ack additionally remembers the LANE STROBES of the completed
    -- txn (sh_acked_we) and only satisfies an access with the SAME strobes
    -- (sh_ack_ok, combinational). WHY: an SC keeps data_addr on the shared
    -- address across two back-to-back accesses with different types — a read
    -- in EXECUTE, then the conditional WRITE in SC_CHECK. With an
    -- address-only ack the write would never issue (silently lost SC). The
    -- lane change drops sh_ack_ok inside the SC_CHECK cycle => the core
    -- re-stalls and the write runs as a fresh arbiter transaction.
    --
    -- M10: the ack also remembers the WORD ADDRESS (sh_acked_addr) and only
    -- satisfies an access to the SAME word. WHY: executing FROM the shared
    -- window (the M12 boot shape) produces back-to-back same-lane READS at
    -- DIFFERENT addresses with sh_sel never dropping — sequential fetches,
    -- and the fetch after a shared load. The lanes-only ack absorbed them
    -- all into one stale sh_rdata_reg (the core re-executed instruction k
    -- forever). Address change now drops sh_ack_ok => every new word
    -- re-arbitrates. Same-word re-access still holds the ack — a compressed
    -- pair in one word or a `j .` self-loop correctly re-uses the held word,
    -- and repeated-identical-access absorption (AMO_READ consuming its
    -- EXECUTE-cycle read) is unchanged.
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
                -- M13: done/rdata/scfail arrive through the inbound boundary
                -- stage — value-with-pulse alignment preserved (same depth).
                sh_acked      <= '1';
                sh_acked_we   <= sh_we_lanes;
                sh_acked_addr <= data_addr(SH_AW+1 downto 2);
                sh_rdata_reg  <= bnd_rdata_r;   -- capture shared read data
                sh_scfail_reg <= bnd_scfail_r;  -- capture resv_unit SC verdict
            end if;
        end if;
    end process;

    -- wen is ACTIVE-LOW per byte lane; arbiter we is active-high per lane (M4a).
    -- write_word is lane-positioned by the core's store extender => sb/sh work.
    -- (The lanes feed BOTH the outbound boundary stage and the local ack
    -- comparison below — the comparison stays on the RAW lanes: it is the
    -- frozen core comparing its own current access against the acked one.)
    sh_we_lanes <= (not wen_re) when sh_sel = '1' else (others => '0');

    sh_ack_ok <= '1' when sh_acked = '1' and sh_acked_we = sh_we_lanes
                      and sh_acked_addr = data_addr(SH_AW+1 downto 2) else '0';

    -- M9b/M12: the chip resetn masks the power-on settle window from the
    -- arbiter. During the stretched priming window (resetn high,
    -- resetn_core still low) the request MUST flow — it IS the boot fetch —
    -- and its inputs are defined there by construction: the nop-forced
    -- read bus keeps the core's decode defined, and pc_next_trad's reset
    -- arm pins data_addr at PC_RST_VAL (M9b round-2.5 analysis).
    -- M13: these are the PRE-boundary nets; the ports carry their
    -- one-stage-registered copies (bnd_out above).
    sh_req_int  <= sh_sel and not sh_ack_ok and resetn;
    sh_lrsc_int <= lr_sc_bus when sh_sel = '1' else "00";

    -- back-pressure into the core (identity while sh_sel='0')
    mem_ready_sh <= (not sh_sel) or sh_ack_ok;

    -- Read-data mux, DATA-PHASE ONLY, select registered on the tile's own gated
    -- clk_cpu — BY DESIGN (bug 4: a raw-sh_sel mux on read_data oscillates,
    -- because read_data is the instruction during decode). sh_dphase is '1'
    -- exactly during the MEMORY_WAIT cycle, where read_data is consumed as
    -- LOAD DATA and the instruction comes from the held instr_curr_prev.
    sh_dphase_reg: process(clk_cpu, resetn)
    begin
        if resetn = '0' then
            sh_dphase   <= '0';
            sh_rdata_cpu <= (others => '0');
        elsif rising_edge(clk_cpu) then
            sh_dphase   <= sh_sel;
            -- M10 consumption stage (see the signal declaration): re-latching
            -- a stale landing value is harmless; what matters is that this
            -- register can NEVER change inside a stretched core cycle.
            sh_rdata_cpu <= sh_rdata_reg;
        end if;
    end process;

    -- M9b: nop-force the instruction bus until the STRETCHED core reset
    -- releases. adddec's own nop arm uses the early chip resetn, which in the
    -- gate netlist releases ~2 cycles before resetn_core — in that window the
    -- select staging points at a memory whose Q has never been clocked, and
    -- the X instruction feeds pc_next -> data_addr -> decode -> select: a
    -- self-sustaining X loop on the unified bus. A defined nop keeps
    -- pc_next/data_addr/decode defined while the fetch pipeline primes.
    core_read_data <= nop          when resetn_core = '0' else
                      sh_rdata_cpu when sh_dphase = '1'   else read_data;

    -- M11/M12: the tile's private memories besides the TCM are RETIRED —
    -- region 000 is the SHARED boot ROM (M12) and 0xC000-0xFFFF the SHARED
    -- NPU staging RAM (M11), both reached via sh_sel through the arbiter;
    -- adddec asserts no enable for either, so its slots 0/2 read zeros.
    mem_dout(0) <= (others => '0');
    mem_dout(2) <= (others => '0');

    -- Private TCM (RAM0, 0x8000-0xBFFF): IVT + code + data + stack. M12: NOT
    -- preloaded — like silicon, the TCM powers up unknown, and software owns
    -- write-before-read (the bootrom's tile loader fills it before use).
    -- M13: PGEN is a port — hart 0 keeps BLOCKPWR software gating, tiles '0'.
    ram0: entity work.sram1p16k_hvt_pg
        port map (
            Q     => mem_dout(1),
            CLK   => clk_mem(1),
            CEN   => mem_en(1),
            WEN   => wen_fe,
            A     => mem_addr,
            D     => write_data,
            EMA   => "000",
            GWEN  => GWEN,
            RETN  => tcm_retn,
            PGEN  => tcm_pgen
        );

end architecture;
