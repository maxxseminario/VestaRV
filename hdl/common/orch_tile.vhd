-- =============================================================================
-- orch_tile.vhd  (CP2 — Castalia-Penta orchestrator hart wrapper;
--                 renumbered to HART 0 at CPR3/R2)
-- =============================================================================
-- A THIN WRAPPER around hart_tile: same generics, same ports, and an
-- architecture that is a single bare instantiation of `entity work.hart_tile`.
-- It adds NO logic, NO registers and NO wiring difference — behaviourally an
-- orch_tile IS a hart_tile, and a behavioural simulation cannot tell them
-- apart (that is the point: the orchestrator is ISA/config-identical to the
-- tiles, CP1 decision D5).
--
-- CPR3/R2 RENUMBER: the orchestrator is HART 0, and the channel tiles are
-- harts 1..numHarts-1. Nothing in this file depends on the index — it never
-- had one — but every sentence below that says "the corner harts" now means
-- harts 1-4 rather than 0-3, and the instance MCU.vhd binds to this entity is
-- `hart0`.
--
-- WHY IT EXISTS AT ALL (CP1 decision D6) — it is a MODULE-NAMESPACE device,
-- not an RTL feature:
--
--   The four corner harts are a HARDENED MACRO. `genus/hart_tile` elaborates
--   hart_tile once and the resulting netlist (hart_tile.genus.v) is the one
--   physical tile placed four times; the assembly flow reads that netlist and
--   the strip step deletes exactly the modules it names, from a module list
--   extracted out of that same file. The orchestrator is the OPPOSITE kind of
--   object: SOFT logic, flat-synthesized into the centre band of the same
--   die, from the SAME source RTL.
--
--   Elaborating that soft copy as `hart_tile` would emit a second netlist
--   whose module names (hart_tile, vesta, adddec, ...) collide with the
--   hardened tile's, and the collision is load-bearing in two places at once:
--   (a) the strip script's module list would match the orchestrator's subtree
--   and delete it out of the flat P&R netlist, and (b) a gate simulation would
--   see two different definitions of the same module name. Giving the soft
--   core its own TOP entity gives it its own genus block (genus/orch_tile),
--   which elaborates `orch_tile` and prefix-renames every module below the top
--   (vesta -> orch_vesta, ...). The invariant CP4 must preserve: NO module
--   name is shared between the tile netlist and the orchestrator netlist, and
--   the flat netlist retains the orchestrator subtree after the strip step.
--
-- So: nothing here is for simulation, and nothing here may grow logic. If a
-- future orchestrator-only feature is wanted (a bigger TCM, a different
-- reset), it belongs in hart_tile behind a generic — this file stays a bare
-- pass-through so the two netlists keep sharing ONE source of truth.
--
-- POWER/RESET SHAPE (CP1 decision D2, enforced by the GENERATOR, not here):
-- the orchestrator is ALWAYS-ON. There is no chip-level power intent in the
-- centre band (the MTCMOS headers exist only inside the hardened tile), so a
-- gateable-in-RTL orchestrator would be a hardware lie of exactly the
-- hw_clint_en class. MCU.vhd therefore wires this instance the way it wires
-- hart 0: resetn = resetn and pgood_rstn, no pwr_ctrl row, no isolation
-- clamps, sh_* straight into its arbiter master slice, pd_sleep/pd_iso_en
-- strapped '0', tcm_pgen '0', tcm_retn '1'. The pd_* ports below exist only
-- because the port list is hart_tile's; they are inert on this instance.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;      -- word, word_array
use work.MemoryMap.all;      -- NUM_IRQS

entity orch_tile is
    generic (
        -- EXACTLY hart_tile's generics, in hart_tile's order, with hart_tile's
        -- defaults. Any divergence here is a silent configuration split
        -- between the orchestrator and the tiles (the F-K7-4 shape), so this
        -- list is transcribed, never "tidied".
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00000000";
        SH_AW          : natural := 16;   -- CPR8/R6: tracks hart_tile's default (15 -> 16)

        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
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
        ENABLE_TRAPCSR    : boolean := true;   -- tracks hart_tile (K7/R-DK3)
        ENABLE_UMODE      : boolean := false;
        ENABLE_PMP        : boolean := false;
        PMP_ENTRIES       : integer := 16;
        -- DEFAULT FALSE, for hart_tile's reason verbatim: a debug interface
        -- inherited by an omitted generic is an area and attack-surface
        -- surprise, not a convenience (method rule 15).
        ENABLE_DEBUG      : boolean := false;
        DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00"
    );
    port (
        clk       : in  std_logic;   -- free-running mclk
        resetn    : in  std_logic;
        -- Strapped '0' on the orchestrator (no SPI0/XIP behind it).
        sleep     : in  std_logic := '0';

        hart_id   : in  std_logic_vector(31 downto 0);

        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';
        meip_in   : in  std_logic := '0';

        dbg_haltreq      : in  std_logic := '0';
        dbg_resethaltreq : in  std_logic := '0';
        dbg_halted       : out std_logic;

        -- Extended-flash / XIP port. The flash quartet is physically wired to
        -- hart 0's tile (CP1 D3: boot mastership does not move), so these are
        -- left open / at their defaults on the orchestrator.
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- Shared-window master port -> the orchestrator's mp_arbiter slice.
        sh_req    : out std_logic;
        sh_we     : out std_logic_vector(3 downto 0);
        sh_addr   : out std_logic_vector(SH_AW-1 downto 0);
        sh_wdata  : out std_logic_vector(31 downto 0);
        sh_gnt    : in  std_logic := '0';
        sh_done   : in  std_logic := '0';
        sh_rdata  : in  std_logic_vector(31 downto 0) := (others => '0');
        sh_lrsc   : out std_logic_vector(1 downto 0);
        sh_scfail : in  std_logic := '0';
        sh_resv_valid : in std_logic := '1';
        sh_lock   : out std_logic;

        -- Own 16 KiB TCM, never gated (D2): tcm_pgen '0', tcm_retn '1'.
        tcm_pgen  : in  std_logic := '0';
        tcm_retn  : in  std_logic := '1';

        -- CPR3/R3: the READ-ONLY external TCM slave port, passed straight
        -- through to hart_tile (CPR2 R4). The orchestrator's own TCM gets an
        -- aperture like every other hart's -- 0x20000, the h=0 window -- for
        -- uniform indexing, and R4-A2 names this instance as the one aperture
        -- that is never gated (no power domain, no clamp, no zero-completion
        -- bypass). Same defaults as hart_tile's declaration, so an
        -- instantiation that does not name these ports is unchanged.
        tcm_ext_req   : in  std_logic := '0';
        tcm_ext_addr  : in  std_logic_vector(11 downto 0) := (others => '0');
        tcm_ext_rdata : out std_logic_vector(31 downto 0);
        tcm_ext_done  : out std_logic;

        -- Inert on this instance (no power domain in the centre band).
        pd_sleep  : in  std_logic := '0';
        pd_iso_en : in  std_logic := '0';

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0)
    );
end entity;

architecture behav of orch_tile is
begin

    -- The whole architecture: ONE hart_tile, every generic and every port
    -- passed straight through. No logic may be added between these two
    -- entities (see the header) — a difference here would be a difference
    -- between the orchestrator and the tiles that no test could see.
    tile: entity work.hart_tile
        generic map (
            PC_RST_VAL        => PC_RST_VAL,
            SH_AW             => SH_AW,
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
            clk       => clk,
            resetn    => resetn,
            sleep     => sleep,
            hart_id   => hart_id,
            msip_in   => msip_in,
            mtip_in   => mtip_in,
            meip_in   => meip_in,
            dbg_haltreq      => dbg_haltreq,
            dbg_resethaltreq => dbg_resethaltreq,
            dbg_halted       => dbg_halted,
            flash_mem_en  => flash_mem_en,
            flash_clk_mem => flash_clk_mem,
            flash_mab     => flash_mab,
            flash_dout    => flash_dout,
            sh_req    => sh_req,
            sh_we     => sh_we,
            sh_addr   => sh_addr,
            sh_wdata  => sh_wdata,
            sh_gnt    => sh_gnt,
            sh_done   => sh_done,
            sh_rdata  => sh_rdata,
            sh_lrsc   => sh_lrsc,
            sh_scfail => sh_scfail,
            sh_resv_valid => sh_resv_valid,
            sh_lock   => sh_lock,
            tcm_pgen  => tcm_pgen,
            tcm_retn  => tcm_retn,
            tcm_ext_req   => tcm_ext_req,
            tcm_ext_addr  => tcm_ext_addr,
            tcm_ext_rdata => tcm_ext_rdata,
            tcm_ext_done  => tcm_ext_done,
            pd_sleep  => pd_sleep,
            pd_iso_en => pd_iso_en,
            trap_flag => trap_flag,
            a0        => a0
        );

end architecture;
