# MMMC view definition -- hart_tile block harden (M14).
# Same three PVT corners as the Myshkin tape-out; tile macros = the TCM
# sram1p8k only (no ROM inside a tile). SWAPPED FROM sram1p16k 2026-08-16 WITH
# THE MACRO, and it was MISSED at the swap: the design instantiated the 8 KiB
# macro while these three corners still loaded the 16 KiB .lib, so Innovus had
# NO TIMING MODEL for the tile TCM at all. It said so once (IMPSYC-2 "Timing
# information is not defined for cell sram1p8k_hvt_pg") and CARRIED ON, because
# that is a WARN -- so three consecutive hardens reported setup/hold slack with
# every path through the TCM silently untimed. Only a restore session, which
# runs the tape-out-mode library check, escalated it to a FATAL and exposed it. Constraints = the tile-only Genus
# SDC (clk_cpu is a GENERATED clock of mclk there -- the M9c fix).

# M17: the ARM pmk (HEADBUF switches / A2ISO clamps / GPG AO cells) joins
# every corner. NLDM only — no ECSM view exists for the pmk in any Vt flavor
# (M17 recon); Innovus accepts the ECSM+NLDM mix, with reduced SI accuracy
# on the handful of pmk instances.
set PMK_DIR "/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys"

create_library_set \
    -name max_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ss_0p9v_125c.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ss_0p90v_0p90v_125c_syn.lib" \
        "$PMK_DIR/scadv10pmk_tsmc65gp_hvt_ss_0p9v_125c.lib" \
		]
create_library_set \
    -name typical_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_tt_1p0v_25c.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib" \
        "$PMK_DIR/scadv10pmk_tsmc65gp_hvt_tt_1p0v_25c.lib" \
		]
create_library_set \
    -name min_library_set \
    -timing [list \
        "$STD_CELL_DIR/ecsm-timing/scadv10_cln65gp_hvt_ff_1p1v_m40c.lib" \
        "$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg_nldm_ff_1p10v_1p10v_m40c_syn.lib" \
        "$PMK_DIR/scadv10pmk_tsmc65gp_hvt_ff_1p1v_m40c.lib" \
		]

create_rc_corner \
    -name best_rc_corner \
    -qx_tech_file "$QXTECH_FILE"
create_rc_corner \
    -name worst_rc_corner \
    -qx_tech_file "$QXTECH_FILE"

create_constraint_mode \
    -name prelayout_constraint_mode \
    -sdc_files "$GENUS_DIR/out/hart_tile.genus.sdc"

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
