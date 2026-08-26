###############################################################################
# MCU_DP_hier_s3_vcd_power.tcl
#
# VCD-annotated power analysis for the MCU_DP_hier_s3 gate netlist (Genus 19.15).
# Rerunnable.  Drive with env vars:
#   NEGCTRL=1   -> negative control (deliberately wrong -vcd_scope)
#   (default)   -> full annotated flow + DP-blocks-zeroed variant + macro rows
#
# The tool-verbatim annotation coverage comes from read_vcd's own
# "Annotation Report" (captured in the genus log).  Genus 19.15 reads VCD via
# the Joules engine in STATIC mode: it annotates average toggle_rate/probability
# onto design objects, then discards the transient stim frame ("Removing all
# stims from SDB") -- report_power afterwards uses the annotated attributes.
#
# Prereq: source ~/vestarv/cdspaths.sh  BEFORE launching genus.
# Invoke:  genus -no_gui -overwrite -batch -files tcl/MCU_DP_hier_s3_vcd_power.tcl \
#                -log log/<name>
###############################################################################

set NETLIST out/MCU_DP_hier_s3.genus.v
set SDC     out/MCU_DP_hier_s3.genus.sdc
set VCD     /home/mseminario2/vestarv/xcelium/riscv_test/behavioral_mp/harvested_parked.vcd
set TOP     MCU
set GOODSCOPE riscv_tb/dut
set DPBLOCKS {qspi0 rtc0 pwm0 dma0}

set NEGCTRL 0
if {[info exists ::env(NEGCTRL)] && $::env(NEGCTRL)==1} { set NEGCTRL 1 }

###############################################################################
# 1. Libraries (from the s3 synth: tcl lines 90-107 + the .g search path)
###############################################################################
set_db information_level 3
set_db hdl_error_on_blackbox false
set_db init_lib_search_path [list \
    /home/mseminario2/chips/myshkin/ip/rom_hvt_pg \
    /home/mseminario2/chips/myshkin/ip/sram1p16k_hvt_pg \
    in/ \
    /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/ecsm-timing/ \
    /opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/synopsys/ ]
set_db library [list \
    rom_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
    sram1p16k_hvt_pg_nldm_tt_1p00v_1p00v_25c_syn.lib \
    scadv10_cln65gp_hvt_tt_1p0v_25c.lib \
    scadv10pmk_tsmc65gp_hvt_tt_1p0v_25c.lib]

###############################################################################
# 2. Read the mapped netlist (hart_tile is inline; top = MCU) + constraints
###############################################################################
read_netlist $NETLIST -top $TOP
read_sdc $SDC
puts "@@@DESIGN_LOADED@@@ top=[get_db current_design .name]"

###############################################################################
# 3. Baseline statistical power (sanity: ~11.95 mW).  Scratch only.
###############################################################################
report_power -by_hierarchy -levels 1 -unit mW > scratch/baseline_statistical.rpt

# proc: total power at the top design (tries several attribute spellings)
proc top_power_w {} {
    foreach a {.power.total .power_total .total_power} {
        if {![catch {set v [get_db [current_design] $a]}] && $v ne ""} { return "$a=$v" }
    }
    return "UNKNOWN"
}
puts "@@@BASELINE_TOTAL@@@ [top_power_w]"

###############################################################################
# Per-DP-block sequential flop census (explains the annotation gap; the 4 DP
# blocks have NO VCD scope so their flops are unasserted).  Pure netlist query.
###############################################################################
proc dp_flop_census {blocks} {
    set allseq [get_db insts -if {.is_sequential==true}]
    puts "@@@SEQ_CENSUS@@@ total_sequential_insts=[llength $allseq]"
    set sum 0
    foreach b $blocks {
        # object .name is RELATIVE to the top design (no "MCU/" prefix)
        set n [llength [get_db insts -if ".is_sequential==true && .name=~$b/*"]]
        puts "DP_SEQ $b = $n"
        incr sum $n
    }
    puts "DP_SEQ_TOTAL_4BLOCKS = $sum"
    # full per-top-block sequential census (localizes the annotation gap)
    puts "@@@FULL_SEQ_CENSUS@@@"
    array set cnt {}
    foreach s $allseq {
        set nm [get_db $s .name]
        set top [lindex [split $nm /] 0]
        if {[info exists cnt($top)]} { incr cnt($top) } else { set cnt($top) 1 }
    }
    foreach k [lsort [array names cnt]] { puts "TOPSEQ $k = $cnt($k)" }
    # dump every sequential inst: name + base libcell (for name-match diffing)
    set df [open scratch/design_seq.txt w]
    foreach s $allseq {
        puts $df "[get_db $s .name]\t[get_db $s .base_cell.name]"
    }
    close $df
    puts "@@@FULL_SEQ_CENSUS_END@@@"
    # any OTHER hierarchy that might be unmapped: top-level children present
    puts "@@@TOPLEVEL_CHILDREN@@@"
    foreach h [get_db [current_design] .hinsts] {
        puts "HINST [get_db $h .name]"
    }
}

if {$NEGCTRL==0} { dp_flop_census $DPBLOCKS }

###############################################################################
# MAIN
###############################################################################
if {$NEGCTRL==1} {
    #############################################################
    # NEGATIVE CONTROL: deliberately wrong vcd_scope -> ~0 coverage
    #############################################################
    puts "@@@NEGCTRL_READVCD@@@"
    catch { read_vcd $VCD -vcd_scope riscv_tb/dutX } rv
    puts "READVCD_MSG: $rv"
    puts "@@@NEGCTRL_TOTAL_W@@@ [top_power_w]"
    report_power -by_hierarchy -levels 4 -unit mW > rpt/MCU_DP_hier_s3_vcd_negctrl.power.rpt
    puts "@@@NEGCTRL_DONE@@@"
} else {
    #############################################################
    # FULL annotated flow
    #############################################################
    puts "@@@READVCD_BEGIN@@@"
    read_vcd $VCD -vcd_scope $GOODSCOPE
    puts "@@@READVCD_END@@@"
    puts "@@@ANNOTATED_TOTAL_W@@@ [top_power_w]"

    # ---- attribute discovery + mclk toggle-rate probe (report_obj -all) ----
    # prove the /8 clock is load-bearing: mclk net toggle_rate ~3 MHz not 24 MHz.
    puts "@@@MCLK_PROBE_BEGIN@@@"
    # names are RELATIVE (no MCU/ prefix). Find the mclk net(s) and dump every
    # activity-ish attribute so the load-bearing /8 clock is on record.
    catch {
        set mnets [get_db nets -if {.name=~*mclk* || .name==system0/mclk_out}]
        puts "mclk_candidate_nets=[llength $mnets]"
        foreach mn $mnets {
            set nm [get_db $mn .name]
            set tr  "?" ; catch { set tr  [get_db $mn .toggle_rate] }
            set pr  "?" ; catch { set pr  [get_db $mn .probability] }
            set ttr "?" ; catch { set ttr [get_db $mn .total_toggle_rate] }
            puts "MCLK_NET $nm toggle_rate=$tr probability=$pr total_toggle_rate=$ttr"
        }
    } m ; puts "mclk_probe_msg: $m"
    # write_tcf: dump genus-native post-annotation toggle rates (mclk proof +
    # per-object activity for gap localization).  -computed = final activity.
    catch { write_tcf scratch/annotated.tcf -computed } wt
    puts "write_tcf_msg: $wt"
    puts "@@@MCLK_PROBE_END@@@"

    # ---- annotated hierarchical report (deliverable) ----
    report_power -by_hierarchy -levels 4 -unit mW > rpt/MCU_DP_hier_s3_vcd.power.rpt
    puts "@@@ANNOTATED_REPORT_WRITTEN@@@"

    # ---- per-instance rows for the six memory macros ----
    # Memory macros are LEAF library cells -> use -by_leaf_instance and grep.
    report_power -by_leaf_instance -unit mW > scratch/leaf_power.rpt
    set fh [open rpt/MCU_DP_hier_s3_vcd_macros.rpt w]
    puts $fh "# Annotated per-instance power for the six memory macros (unit mW)"
    puts $fh "# source VCD: $VCD  scope: $GOODSCOPE"
    puts $fh "# extracted from report_power -by_leaf_instance"
    close $fh
    set want {/rom0 /npuram0 /shbank0 /shbank1 /shbank2 /shbank3 hart0/ram0}
    set lf [open scratch/leaf_power.rpt r]
    set lines [split [read $lf] "\n"]
    close $lf
    set of [open rpt/MCU_DP_hier_s3_vcd_macros.rpt a]
    foreach ln $lines {
        foreach w $want {
            if {[string match "*$w *" "$ln "] || [string match "*$w" $ln]} { puts $of $ln ; break }
        }
    }
    close $of
    puts "@@@MACROS_WRITTEN@@@"

    #############################################################
    # DP-blocks-zeroed variant: force qspi0/rtc0/pwm0/dma0 activity ~0.
    # No VCD scope -> genus used statistical fallback for them.  Assert 0 on
    # every net + pin under each block, then re-report.
    #############################################################
    puts "@@@ZERO_DP_BEGIN@@@"
    foreach blk $DPBLOCKS {
        set insts [get_db insts -if ".name=~$blk/*"]
        set nets  [get_db nets  -if ".name=~$blk/*"]
        set np 0
        foreach n $nets {
            if {![catch { set_db $n .lp_asserted_probability 0.0 }]} { incr np }
            catch { set_db $n .lp_asserted_toggle_rate 0.0 }
        }
        set pp 0
        foreach i $insts {
            foreach p [get_db $i .pins] {
                if {![catch { set_db $p .lp_asserted_probability 0.0 }]} { incr pp }
                catch { set_db $p .lp_asserted_toggle_rate 0.0 }
            }
        }
        puts "DP_ZERO $blk nets=[llength $nets] (prob_set=$np) insts=[llength $insts] pins_set=$pp"
    }
    puts "@@@ZERO_DP_APPLIED@@@ total_after=[top_power_w]"
    report_power -by_hierarchy -levels 4 -unit mW > rpt/MCU_DP_hier_s3_vcd_zeroed.power.rpt
    puts "@@@ZEROED_REPORT_WRITTEN@@@"
}

puts "@@@ALL_DONE@@@"
exit
