# MMMC view definition -- MCU_castalia_penta CONNECTED chip (CASTALIA-PENTA
# wound SoC: four hardened corner tiles + the SOFT always-on orchestrator hart0 (CPR6 renumber)
# in the centre band, LQFP-100). CLONE of viewdefinition_MCU_castalia.tcl with
# exactly ONE delta: the constraint_mode SDC is in/MCU_castalia_penta.sdc
# (produced by ../gen_MCU_castalia_penta_sdc.sh from
# genus/MCU_PENTA/out/MCU_PENTA_hier.genus.sdc). MMMC is timing collateral and
# knows nothing about floorplans.
#
# WHY NO NEW LIBRARY ENTRY FOR THE ORCHESTRATOR: hart0 is SOFT -- flat std
# cells + one sram1p16k_hvt_pg TCM, both already covered by the scadv10 and
# sram libs below. Only the four HARDENED tiles need an ETM. If the
# orchestrator is ever hardened into its own macro (it is not, and CP1 D6 says
# it must not be), this file gains an orch_tile ETM entry.
#
#
# TILE_OUT (2026-08-26): the hart_tile ETM libraries below are TILE-lineage
# products and are re-written by every tile harden, so a frozen chip cut that
# re-reads them is re-timed -- and, worse, re-INTERFACED -- against a tile it
# was never built with. On 2026-08-26 the cpr8 LVS-netlist regen died in
# init_design with
#   **ERROR: (IMPDB-2163): Cell 'hart_tile' has inconsistent pin definitions
#            between timing library and LEF ... 'tcm_ext_addr[11]'
#   **ERROR: (IMPDB-2160): Bus 'tcm_ext_addr' ... timing library ([10:0]) and
#            LEF ([11:11])
# because the LEF had been pinned to the cut's own tile while these libs still
# followed the current one. Pin BOTH together:
#   TILE_OUT=../hart_tile/out.pre_tcm11   (the cpr8-vintage tile)
# Default is unchanged, so the P&R flow behaves exactly as before.
set TILE_OUT [expr {[info exists ::env(TILE_OUT)] ? $::env(TILE_OUT) : "../hart_tile/out"}]

create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$TILE_OUT/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$TILE_OUT/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$TILE_OUT/hart_tile.etm_ff.lib" \
		]

create_rc_corner \
    -name best_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
create_rc_corner \
    -name worst_rc_corner \
    -qx_tech_file "$QXTECH_FILE"

create_constraint_mode \
    -name prelayout_constraint_mode \
    -sdc_files "in/MCU_castalia_penta.sdc"

create_delay_corner \
    -name max_delay_corner \
    -library_set max_library_set \
    -rc_corner worst_rc_corner
create_delay_corner \
    -name min_delay_corner \
    -library_set min_library_set \
    -rc_corner best_rc_corner

create_analysis_view \
    -name setup_analysis_view \
    -constraint_mode prelayout_constraint_mode \
    -delay_corner max_delay_corner
create_analysis_view \
    -name hold_analysis_view \
    -constraint_mode prelayout_constraint_mode \
    -delay_corner min_delay_corner

set_analysis_view \
    -setup [list setup_analysis_view] \
    -hold [list hold_analysis_view]
