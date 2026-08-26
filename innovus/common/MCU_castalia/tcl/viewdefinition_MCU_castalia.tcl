# MMMC view definition -- MCU_castalia CONNECTED chip (wound-patch SoC
# on the quadrant-symmetric Castalia-Quad floorplan, LQFP-100). Cloned from
# viewdefinition_chip_wound.tcl; ONLY the constraint_mode SDC file name
# changes -- MMMC is timing collateral and knows nothing about floorplans, and
# the macro/library set is identical (same tile ETM, same SRAM/ROM/analog IP).
# That file was itself cloned from viewdefinition_chip_dp.tcl; ONLY the
# constraint_mode SDC changed. The library sets are IDENTICAL to the DP chip's because the
# macro set is identical (rom_hvt_pg, sram1p16k_hvt_pg, hardened hart_tile ETM,
# LEF-only tphn pads + analog abstracts) -- every wound delta (QSPI/I3C/NFC/OW/
# I2CT/TRNG/EVFAB, 4ch DMA) is std-cell logic covered by the scadv10 libs.
#
# The SDC is the mcu0/-prefixed chip transform in/MCU_castalia.sdc,
# produced by ../gen_MCU_castalia_sdc.sh from
# genus/out/MCU_WOUND_hier.genus.sdc -- the SAME source SDC the Stage-I wound
# chip uses, the SAME transform, differing ONLY in the `current_design` line
# (verified by diff against in/chip_top_wound.sdc at staging). Port
# load/driver lines are dropped (real pads are the loads now). It additionally
# carries the TRNG ring-oscillator `set_dont_touch [get_cells
# {mcu0/...u_ro/...}]` block; the load-bearing DB-side dontTouch is set in
# tcl/MCU_castalia.innovus.tcl.
#
# The tphn pad cells enter LEF-only (timing-less, like the analog abstracts --
# same IMPVL-366 rule: no dummy libs). The tile enters as a per-corner ETM
# (../hart_tile/out/hart_tile.etm_{ss,ff}.lib); view names MATCH the tile/assembly run so
# the mapping is automatic.

create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "../hart_tile/out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "../hart_tile/out/hart_tile.etm_ss.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/rom_hvt_pg/rom_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
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
    -sdc_files "in/MCU_castalia.sdc"

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
