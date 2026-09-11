-- VestaRV: channel tile (topology B)
-- A thin wrapper around hart_tile, exactly as orch_tile.vhd is: one bare `entity work.hart_tile` instance with the same generics and ports, plus one analog channel. There is NO logic here and none may be added; a difference between this wrapper and hart_tile is a difference between the channel tiles and the orchestrator that no test can see.
-- It exists so topology B can put one anatop_ch macro inside each corner tile, in the notch the tile already has, instead of running a site's 63 digital signals across the chip to a central anatop_quad. The tile is the boundary those signals cross, and this wrapper is that boundary.
-- SIM_CHANNEL true instantiates sar_macro_model, the behavioural converter every RTL simulation binds, and is the default because MCU.vhd, the only VHDL that instantiates this wrapper, names no value. The synthesis flow MUST pass false, which selects the anatop_ch black box resolved from its .lib; it fails closed, since sar_macro_model.vhd is not in that flow's read list and a true would stop the run at check_design.
-- The five pass-through ports carry 63 bits and no logic. afe_ctl(49:0) is the anatop_pixel symbol order, MSB first: 49:44 ResEn, 43:40 ThEn, 39:28 A_Dac_Vp, 27 En_Dac_Vp, 26:15 A_Dac_Vcm, 14 En_Dac_Vcm, 13:8 Bias_Adj, 7:4 SARADC_SEL, 3:0 ATP_SEL. All 63 are 1.0 V CMOS; the 1.0 V to 2.5 V shifters for afe_ctl are inside anatop_ch.
-- bn/bnc/bp/bpc and CE/RE/WE/ATP are ANALOG pins, declared std_logic INOUT for port-list completeness only: nothing in this file or below it reads or drives them, and at chip level they reach the shared anatop_biasgen_g and their pads. Inout is load-bearing, because an in port would take a default wherever it went unassociated and let synthesis tie a driver onto an analog rail; declaring them at all is what keeps the hardened block's LEF and Verilog in agreement.

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity hart_tile_pt is
    generic (
        -- EXACTLY hart_tile's generics, in hart_tile's order, with hart_tile's defaults.
        -- Any divergence is a silent configuration split between the channel tiles and the orchestrator, so transcribe this list, never tidy it.
        PC_RST_VAL     : std_logic_vector(31 downto 0) := x"00000000";
        SH_AW          : natural := 16;   -- Tracks hart_tile's default.

        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- Fetch-ahead for straddling 32-bit instructions; the wrapper default tracks the shipped CORE_ENABLE_IF_AHEAD, as in hart_tile, while the core-side default in vesta.vhd stays FALSE so an omitted association still inherits an inert core.
        ENABLE_IF_AHEAD   : boolean := true;
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
        ENABLE_DEBUG      : boolean := true;   -- Tracks hart_tile's default.
        DEBUG_ENTRY_ADDR  : std_logic_vector(31 downto 0) := x"0000BE00";

        -- The analog channel: behavioural model (simulation) or the anatop_ch black box (silicon). See the header.
        SIM_CHANNEL       : boolean := true;
        -- Site index 0-3, passed to the model so each channel returns a distinct code (0x155 + SITE). Documentation only on the silicon arm.
        AFE_SITE          : natural := 0
    );
    port (
        clk       : in  std_logic;   -- Free-running mclk.
        resetn    : in  std_logic;
        -- Strapped '0' on a channel tile (no SPI0/XIP behind it).
        sleep     : in  std_logic := '0';

        hart_id   : in  std_logic_vector(31 downto 0);

        msip_in   : in  std_logic := '0';
        mtip_in   : in  std_logic := '0';
        meip_in   : in  std_logic := '0';

        dbg_haltreq      : in  std_logic := '0';
        dbg_resethaltreq : in  std_logic := '0';
        dbg_halted       : out std_logic;

        -- Extended-flash / XIP port; the flash quartet is wired to the boot hart, so these stay open or at their defaults here.
        flash_mem_en  : out std_logic;
        flash_clk_mem : out std_logic;
        flash_mab     : out std_logic_vector(31 downto 0);
        flash_dout    : in  std_logic_vector(31 downto 0) := (others => '0');

        -- Shared-window master port, feeding this tile's mp_arbiter slice.
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

        -- TCM macro power gate and retention strap; defaults match hart_tile's declaration.
        tcm_pgen  : in  std_logic := '0';
        tcm_retn  : in  std_logic := '1';

        -- Read-only external TCM slave port, passed straight through to hart_tile.
        tcm_ext_req   : in  std_logic := '0';
        tcm_ext_addr  : in  std_logic_vector(10 downto 0) := (others => '0');
        tcm_ext_rdata : out std_logic_vector(31 downto 0);
        tcm_ext_done  : out std_logic;

        -- MTCMOS domain controls from pwr_ctrl.
        pd_sleep  : in  std_logic := '0';
        pd_iso_en : in  std_logic := '0';

        trap_flag : out std_logic;
        a0        : out std_logic_vector(31 downto 0);

        /* ANALOG CHANNEL, digital half: the 63 signals of one AFE2 site, straight wires to the macro. 1.0 V CMOS.
           afe_ctl is the anatop_pixel symbol order (see the header); afe_sar_clk / afe_sar_rst are SARADC_clk / SARADC_rst (reset active high), afe_sar_rdy / afe_sar_d are SARADC_rdy / SARADC_d<9:0>.
           The two outputs are clamped at the MCU boundary with every other output of a gateable tile, so a dark channel reads as "no conversion" rather than as a result. */
        afe_ctl      : in  std_logic_vector(49 downto 0) := (others => '0');
        afe_sar_clk  : in  std_logic := '0';
        afe_sar_rst  : in  std_logic := '1';
        afe_sar_rdy  : out std_logic;
        afe_sar_d    : out std_logic_vector(9 downto 0);

        /* ANALOG CHANNEL, analog half: the four wide-swing cascode bias rails from the chip-level anatop_biasgen_g.
           std_logic for PORT-LIST COMPLETENESS ONLY -- nothing in the RTL reads or drives them and in simulation they stay 'U'. INOUT so that leaving them unassociated cannot tie a synthesized driver onto an analog net. */
        bn        : inout std_logic;
        bnc       : inout std_logic;
        bp        : inout std_logic;
        bpc       : inout std_logic;

        /* ANALOG CHANNEL, electrodes: the three-terminal cell plus the analog test point, straight from the macro to their pads on this block's die-facing edge.
           std_logic for PORT-LIST COMPLETENESS ONLY, on the same terms as the bias rails: inout, no RTL reads or drives them, 'U' in simulation. Declared so the block netlist and the block abstract agree (report B6-2). */
        CE        : inout std_logic;
        RE        : inout std_logic;
        WE        : inout std_logic;
        ATP       : inout std_logic
    );
end entity;

architecture behav of hart_tile_pt is

    /* The hardened analog channel: one anatop_pixel_xb (bias rails as input pins), 50 level shifters, the ATP pass gate and the SAR converter, all inside one macro (topology B contract B.1).
       No VHDL entity implements it. On the silicon arm it resolves from innovus/common/shared/anatop_ch/anatop_ch.lib and is carried as a black box through synthesis, placement and routing.
       Declared here: the 63 AFE bits, the four bias rails and the four electrodes -- every pin that has to appear on this block's boundary. The supplies (VDD/VSS, AVDD/AVSS) live in the LEF and are connected by the power router, not by a port map. */
    component anatop_ch is
        port (
            afe_ctl     : in  std_logic_vector(49 downto 0);
            afe_sar_clk : in  std_logic;
            afe_sar_rst : in  std_logic;
            afe_sar_rdy : out std_logic;
            afe_sar_d   : out std_logic_vector(9 downto 0);
            bn          : inout std_logic;
            bnc         : inout std_logic;
            bp          : inout std_logic;
            bpc         : inout std_logic;
            CE          : inout std_logic;
            RE          : inout std_logic;
            WE          : inout std_logic;
            ATP         : inout std_logic
        );
    end component;

begin

    -- One hart_tile, every generic and every port passed straight through. No logic between the two entities.
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

    -- SIMULATION arm: the behavioural converter, one per channel. Site h returns code 0x155 + h, and with SARADC_SEL = 14 it returns the 10-bit afe_ctl window ATP_SEL selects, which is the only path by which software can read the 50 control bits back.
    gen_sim_channel : if SIM_CHANNEL generate
        chan_model : entity work.sar_macro_model
            generic map (SITE => AFE_SITE)
            port map (
                ctl     => afe_ctl,
                sar_clk => afe_sar_clk,
                sar_rst => afe_sar_rst,
                sar_rdy => afe_sar_rdy,
                sar_d   => afe_sar_d
            );
    end generate;

    -- SILICON arm: the anatop_ch macro, a black box from its .lib / LEF. The bias rails pass through untouched.
    gen_macro_channel : if not SIM_CHANNEL generate
        chan : component anatop_ch
            port map (
                afe_ctl     => afe_ctl,
                afe_sar_clk => afe_sar_clk,
                afe_sar_rst => afe_sar_rst,
                afe_sar_rdy => afe_sar_rdy,
                afe_sar_d   => afe_sar_d,
                bn          => bn,
                bnc         => bnc,
                bp          => bp,
                bpc         => bpc,
                CE          => CE,
                RE          => RE,
                WE          => WE,
                ATP         => ATP
            );
    end generate;

end architecture;
