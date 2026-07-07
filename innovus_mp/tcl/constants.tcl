################################################################################
# Library and Directory Constants -- MCU_MP physical flow (M14, tsmc65nm)
#
# Derived from the frozen Myshkin ~/vestarv/innovus/tcl/constants.tcl. The
# Myshkin scripts referenced ../ip and ../ic relative to the run dir; those
# siblings no longer exist under ~/vestarv -- the real IP/analog-abstract
# source tree is /home/mseminario2/chips/myshkin/{ip,ic} (absolute here).
################################################################################

set KIT_DIR         "/opt/design_kits/TSMC65-PDK"
set STD_CELL_DIR    "/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10"
set IO_PAD_DIR      "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tpfn65gpgv2od3_200c/mt_2/9lm/lef"
set QXTECH_FILE     "/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/voltagestorm/tsmc65_hvt_sc_adv10_9lm_2thick.cl/icecaps.tch"

set GENUS_DIR    "../genus"
set IC_DIR       "/home/mseminario2/chips/myshkin/ic"
set HDL_DIR      "../hdl"
set SCRIPT_DIR   tcl
set INPUT_DIR    in
set IP_DIR       "/home/mseminario2/chips/myshkin/ip"
set OUTPUT_DIR   out
set LOG_DIR      log
set TMP_DIR      "../.tmp"
set REPORT_DIR   rpt
set DATABASE_DIR dbs

# Standard cell library constants
set PIN_GRID_SPACING_X 0.20
set PIN_GRID_SPACING_Y 0.20
set STD_CELL_HEIGHT    2.00
