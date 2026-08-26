# Library sets
create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p1k_hvt_pg/sram1p1k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p1k_hvt_pg/sram1p1k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p1k_hvt_pg/sram1p1k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
		] 
# RC corners
create_rc_corner \
    -name best_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
    #-cap_table "$CAPTBL_DIR/cmos8rf_8MA_32_FuncCmin.CapTbl" \
#create_rc_corner \
#    -name typical_rc_corner \
#    -cap_table "$CAPTBL_DIR/cmos8rf_8MA_32_nm.CapTbl" \
#    -qx_tech_file "$QXTECH_FILE"
create_rc_corner \
    -name worst_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
    #-cap_table "$CAPTBL_DIR/cmos8rf_8MA_32_FuncCmax.CapTbl" \
# Constraint modes
create_constraint_mode \
    -name prelayout_constraint_mode \
    -sdc_files "$GENUS_DIR/out/$DESIGN_NAME.genus.sdc"
# Generate corners.  At least two are required.
create_delay_corner \
    -name max_delay_corner \
    -library_set max_library_set \
    -rc_corner worst_rc_corner
create_delay_corner \
    -name min_delay_corner \
    -library_set min_library_set \
    -rc_corner best_rc_corner
# Analysis views for setup and hold timing.
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




