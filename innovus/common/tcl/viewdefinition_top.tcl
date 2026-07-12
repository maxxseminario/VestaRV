# MMMC view definition -- MCU_MP top-level assembly (M14).
# Same three PVT corners as the tile harden; the tile itself enters as an
# ILM (specifyIlm in the main script), so its libs are NOT needed here --
# only the control-plane macros (boot ROM + 5 shared sram1p16k). View names
# MATCH the tile run (setup_analysis_view/hold_analysis_view) so the ILM
# view mapping is automatic.

create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "out/hart_tile.etm_ff.lib" \
		]

create_rc_corner \
    -name best_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
create_rc_corner \
    -name worst_rc_corner \
    -qx_tech_file "$QXTECH_FILE"

create_constraint_mode \
    -name prelayout_constraint_mode \
    -sdc_files "$GENUS_DIR/out/MCU_MP_hier.genus.sdc"

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
