################################################################################
# READ-ONLY READINESS PROBE (2026-08-26).  NOT a harden.  NOT a cut.
#
# Purpose: measure, rather than predict, whether the staged penta netlist still
# matches the CURRENT hart_tile abstract, and quantify what the tile's re-LEF
# changed for this assembly.  Stops immediately after init_design.  Writes no
# DB, no DEF, no GDS, no report file.  Its own log stem is deliberately NOT
# MCU_castalia_penta, so it cannot clobber log/MCU_castalia_penta.log.
#
# Every line it emits goes out through $PUTS_STRING (Innovus `Puts`), because a
# bare `puts` in this flow reaches the terminal and NOT the log file.
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

proc P {text} { global PUTS_STRING ; $PUTS_STRING "### PROBE ### $text" }

set DESIGN_NAME MCU_castalia_penta

set init_verilog   "$INPUT_DIR/MCU_castalia_penta.v in/MCU_PENTA_hier.pnr.v"
set init_top_cell  "$DESIGN_NAME"
set init_pwr_net   "VDD"
set init_gnd_net   "VSS"
set init_mmmc_file "$SCRIPT_DIR/viewdefinition_MCU_castalia_penta.tcl"

set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

set init_lef_file "$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef \
                   $STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
                   $IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
                   $IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
                   $IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef \
                   $IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
                   $IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
                   $IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
                   ../hart_tile/out/hart_tile.lef \
                   $IO_PAD_LEF"

P "hart_tile.lef mtime = [clock format [file mtime ../hart_tile/out/hart_tile.lef] -format %Y-%m-%d_%H:%M:%S]"
P "in/MCU_PENTA_hier.pnr.v mtime = [clock format [file mtime in/MCU_PENTA_hier.pnr.v] -format %Y-%m-%d_%H:%M:%S]"
P "etm_ss.lib mtime = [clock format [file mtime ../hart_tile/out/hart_tile.etm_ss.lib] -format %Y-%m-%d_%H:%M:%S]"

set init_design_uniquify 1
init_design
P "init_design RETURNED (it did not abort)"

# ---- 1. does the netlist's hart_tile port list still exist on the abstract? --
set cellpins {}
catch { set cellpins [dbGet [dbGetCellByName hart_tile].terms.name] }
P "LEF macro hart_tile terminal count = [llength $cellpins]"
set tcm {}
foreach t $cellpins { if {[string match "tcm_ext_addr*" $t]} { lappend tcm $t } }
P "LEF macro hart_tile tcm_ext_addr terminals = [llength $tcm] : [lsort $tcm]"

# ---- 2. per-instance unbound-pin census (the actual interface question) ------
foreach h {hart1 hart2 hart3 hart4} {
    set ip [dbGetInstByName mcu0/$h]
    if {$ip == "0x0" || $ip eq ""} { P "INSTANCE mcu0/$h NOT FOUND"; continue }
    set n_terms 0 ; set n_open 0 ; set opens {}
    foreach it [dbGet $ip.instTerms] {
        incr n_terms
        set nn ""
        catch { set nn [dbGet $it.net.name] }
        if {$nn eq "" || $nn eq "0x0"} { incr n_open ; if {[llength $opens] < 12} { lappend opens [dbGet $it.name] } }
    }
    P "mcu0/$h : $n_terms instTerms, $n_open with no net -- [join $opens {, }]"
}

# ---- 3. PG pin geometry the sroute -blockPin useLef passes will see ---------
foreach pg {VDD VSS} {
    set trm ""
    catch { set trm [dbGet [dbGetCellByName hart_tile].terms.name $pg -p] }
    if {$trm eq "" || $trm eq "0x0"} { P "hart_tile has no $pg terminal"; continue }
    set nrect 0 ; array unset bylay ; array set bylay {}
    foreach pp [dbGet $trm.pins] {
        foreach pr [dbGet $pp.allShapes] {
            set l ""
            catch { set l [dbGet $pr.layer.name] }
            incr nrect
            if {[info exists bylay($l)]} { incr bylay($l) } else { set bylay($l) 1 }
        }
    }
    set s {}
    foreach l [lsort [array names bylay]] { lappend s "$l=$bylay($l)" }
    P "hart_tile PIN $pg : $nrect shapes -- [join $s { }]"
}

# ---- 4. did anything in the import log land as an ERROR? -------------------
P "probe complete -- no database written"
exit
