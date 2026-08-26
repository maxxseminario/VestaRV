# MMMC view definition -- MCU_hart, the single-hart block assembly.
#
# CLONE of ../MCU_MP/tcl/viewdefinition_top.tcl with two deltas:
#   1. rom2k_hvt_pg joins rom_hvt_pg.  BOTH are listed and they are not
#      alternatives: the staged single-hart config decides which entity rom0
#      binds to, and a library set that is missing the one actually used gives
#      an untimed macro rather than a loud error.
#   2. sram1p8k_hvt_pg joins sram1p16k_hvt_pg.  The 8 KiB macro is the PRIVATE
#      TCM inside hart_tile; it is sealed in the tile LEF/ETM here, but listing
#      it costs nothing and makes this file correct if the tile is ever read
#      flat, or if a future config puts an 8 KiB macro at the top level.
#
# The tile itself enters as an ETM (../hart_tile/out/hart_tile.etm_{ss,ff}.lib),
# not an ILM.  The ILM route was tried on MCU_MP and abandoned: after
# specifyIlm the rebuilt session comes up with no clocks when the clocks are
# defined on hierarchical pins (system0/mclk_out et al., the house style since
# Myshkin), and create_ccopt_clock_tree_spec then finds no clock roots
# (IMPCCOPT-4082).
#
# View names MATCH the tile run (setup_analysis_view / hold_analysis_view).
#
# NOTE the typical set deliberately carries the SS tile ETM: the tile harden
# emits only ss and ff models, and the MCU_MP / penta viewdefinitions both make
# the same substitution.  Kept identical so a corner-by-corner comparison
# against those lineages stays meaningful.

create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/rom2k_hvt_pg/rom2k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "../hart_tile/out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/rom2k_hvt_pg/rom2k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "../hart_tile/out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/rom2k_hvt_pg/rom2k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "../hart_tile/out/hart_tile.etm_ff.lib" \
		]

create_rc_corner \
    -name best_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
create_rc_corner \
    -name worst_rc_corner \
    -qx_tech_file "$QXTECH_FILE"

create_constraint_mode \
    -name prelayout_constraint_mode \
    -sdc_files "$GENUS_DIR/out/MCU_hart_hier.genus.sdc"

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
