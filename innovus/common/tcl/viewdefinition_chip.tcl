# MMMC view definition -- M15 chip_top pad-ring floorplan prototype (Flavor A).
#
# Geometry-only run: there is no core logic and the pad cells ship no timing
# .lib in this flow, so timing is irrelevant here. This defines ONE trivial
# analysis view (std-cell tt lib + empty SDC) purely so init_design has a valid
# MMMC to load. Nothing in chip_top.innovus.tcl runs timing.

create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        ]

create_rc_corner \
    -name typical_rc_corner \
    -qx_tech_file "$QXTECH_FILE"

create_constraint_mode \
    -name chip_constraint_mode \
    -sdc_files "$INPUT_DIR/chip_top.sdc"

create_delay_corner \
    -name typical_delay_corner \
    -library_set typical_library_set \
    -rc_corner typical_rc_corner

create_analysis_view \
    -name typical_analysis_view \
    -constraint_mode chip_constraint_mode \
    -delay_corner typical_delay_corner

set_analysis_view \
    -setup [list typical_analysis_view] \
    -hold [list typical_analysis_view]
