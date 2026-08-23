/* =============================================================================
   orch_tile.vhd: the orchestrator hart (hart 0), a thin wrapper around hart_tile.
   =============================================================================
   The architecture is one bare `entity work.hart_tile` instance with the same generics and ports and no added logic, so an orch_tile is behaviourally a hart_tile.
   It exists as a module-namespace device: the channel tiles are placed from one hardened netlist while the orchestrator is soft logic synthesized from the same RTL, and its own top entity prefix-renames every module below it.
   No module name may be shared between the two netlists: a collision lets the strip step delete the orchestrator subtree out of the flat netlist and gives a gate simulation two definitions of one module.
   Never add logic here; an orchestrator-only feature belongs in hart_tile behind a generic so both netlists keep one source of truth.
   The orchestrator is ALWAYS-ON: there is no power intent in the centre band, so pd_sleep, pd_iso_en and tcm_pgen are inert on this instance.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

library work;
use work.constants.all;      -- word, word_array
use work.MemoryMap.all;      -- NUM_IRQS

entity orch_tile is
    generic (
        -- EXACTLY hart_tile's generics, in hart_tile's order, with hart_tile's defaults.
        -- Any divergence is a silent configuration split between the orchestrator and the tiles, so transcribe this list, never tidy it.
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00000000";
        SH_AW          : natural := 16;   -- Tracks hart_tile's default.

        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- Fetch-ahead for straddling 32-bit instructions; the default tracks hart_tile's, which tracks vesta's.
        ENABLE_IF_AHEAD   : boolean := false;
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
        ENABLE_TRAPCSR    : boolean := true;   -- Tracks hart_tile's default.
        ENABLE_UMODE      : boolean := false;
        ENABLE_PMP        : boolean := false;
        PMP_ENTRIES       : integer := 16;
        -- The wrapper default tracks the shipped chip, as in hart_tile; the core-side default in vesta.vhd stays FALSE, so an omitted association still inherits an inert core there.
        ENABLE_DEBUG      : boolean := true;   -- Tracks hart_tile's default (flipped 2026-08-16 with the debug.enable shipped-default flip; a bare `elaborate orch_tile` must harden the same debug-ON core the assembly wires).
        DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00"
    );
    port (
        clk       : in  std_logic;   -- Free-running mclk.
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

        -- Extended-flash / XIP port; the flash quartet is wired to the boot tile, so these stay open or at their defaults here.
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- Shared-window master port, feeding the orchestrator's mp_arbiter slice.
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

        -- Own 16 KiB TCM, never gated: tcm_pgen is '0' and tcm_retn is '1'.
        tcm_pgen  : in  std_logic := '0';
        tcm_retn  : in  std_logic := '1';

        -- Read-only external TCM slave port, passed straight through to hart_tile; the orchestrator's TCM gets the h=0 aperture at 0x20000 so the indexing stays uniform.
        -- This is the one aperture that is never gated: no power domain, no clamp, no zero-completion bypass. Defaults match hart_tile's declaration.
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

    -- The whole architecture: ONE hart_tile, with every generic and every port passed straight through.
    -- No logic may be added between these two entities: a difference here is a difference between the orchestrator and the tiles that no test can see.
    tile: entity work.hart_tile
        generic map (
            PC_RST_VAL        => PC_RST_VAL,
            SH_AW             => SH_AW,
            ENABLE_MUL        => ENABLE_MUL,
            ENABLE_DIV        => ENABLE_DIV,
            ENABLE_ATOMICS    => ENABLE_ATOMICS,
            ENABLE_COMPRESSED => ENABLE_COMPRESSED,
            ENABLE_BITMANIP   => ENABLE_BITMANIP,
            ENABLE_IF_AHEAD   => ENABLE_IF_AHEAD,
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
