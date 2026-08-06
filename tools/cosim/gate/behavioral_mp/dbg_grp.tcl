# =============================================================================
# dbg_grp.tcl -- the D2 HALT-GROUP harness (d2_spec 3 `dmcs2`, grouptype 0).
#
#   ./xrun_dbg.sh rv32ua-p-dbggrpmp dbg_grp.tcl
#
# Group assignment is DMI-only -- no software on any hart can reach dmcs2 --
# so this harness owns it entirely: harts 1 and 2 join group 1, hart 3 keeps
# group 0 (the reset value, "no group") and is the non-member BY DEFAULT
# rather than by anything the test did.  Then hart 1 alone gets haltreq.
#
# CHECKS (DMILOG; the runner greps for FAILED):
#   G1  the group field READS BACK per selected hart -- writing hart 1's
#       membership must not change hart 3's.  A DM with one global group
#       register passes every other check here and fails this one.
#   G2  haltreq on hart 1 halts hart 1
#   G3  ...and hart 2 halts too, WITHOUT its own haltreq
#   G4  ...and hart 3 does NOT
#   G5  haltsum0 = 0b0110 exactly -- the second register naming the same set
#   G6  resume of hart 1 does NOT resume hart 2: d2_spec 3 says same-group
#       resume broadcast is OUT at D2 (halt groups only), so this asserts the
#       SCOPE of the feature and not merely its presence.  A DM that
#       broadcasts resume as well is out of spec and this is the only check
#       that sees it.
#   G7  hart 2 resumes when IT is asked
#
# The image measures forward progress (see dbggrpmp.S); this file measures the
# DM's own reporting.  Both are required.
# =============================================================================
source ../../disable_x_warnings.tcl
# dbg_bfm.tcl lives beside this file in behavioral_mp/, but a harness is also
# run from the mutation scratch dir (d2mut/), whose CWD is one level across.
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set CNT1 0x10054
set CNT2 0x10058
set CNT3 0x1005C
set GROUP 1

# dmcs2: hgselect [0] = 0 (harts), hgwrite [1], group [6:2]
proc dmcs2_w {group} { return [expr {(($group & 0x1F) << 2) | 0x2}] }

set PRESENT [dmi_present]

# ---- 1. wait for all three victims to be counting --------------------------
set started 0
set p1 [sh_get $CNT1] ; set p2 [sh_get $CNT2] ; set p3 [sh_get $CNT3]
for {set i 0} {$i < 200} {incr i} {
    run 200 us
    set n1 [sh_get $CNT1] ; set n2 [sh_get $CNT2] ; set n3 [sh_get $CNT3]
    if {$n1 > $p1 && $n2 > $p2 && $n3 > $p3} { set started 1 ; break }
    set p1 $n1 ; set p2 $n2 ; set p3 $n3
}
puts "DMILOG boot i=$i started=$started"
flush stdout

dbg_plant_trampoline

if {$PRESENT} {
    # ---- 2. membership ----------------------------------------------------
    dm_select 1 ; dmi_write $::DM_DMCS2 [dmcs2_w $GROUP]
    dm_select 2 ; dmi_write $::DM_DMCS2 [dmcs2_w $GROUP]
    dm_select 1 ; set g1 [d2_fld [dmi_read $::DM_DMCS2] 6 2]
    dm_select 2 ; set g2 [d2_fld [dmi_read $::DM_DMCS2] 6 2]
    dm_select 3 ; set g3 [d2_fld [dmi_read $::DM_DMCS2] 6 2]
    d2_chk [expr {$g1 == $GROUP && $g2 == $GROUP && $g3 == 0}] \
        "G1: group membership is PER HART (hart1=$g1 hart2=$g2 hart3=$g3; want $GROUP/$GROUP/0)"

    # ---- 3. halt ONE member ----------------------------------------------
    dm_haltreq 1
    set s1 [dm_poll_status 1 dms_allhalted 400 $::HALTREQ_BIT]
    d2_chk [expr {$s1 >= 0}] "G2: haltreq halted the requested member (hart 1)"
    dm_clr_haltreq 1

    set s2 [dm_poll_status 2 dms_allhalted 400]
    d2_chk [expr {$s2 >= 0}] \
        "G3: hart 2 halted THROUGH THE GROUP -- it never received a haltreq"

    dm_select 3
    set s3 [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allhalted $s3] == 0 && [dms_allrunning $s3] == 1}] \
        "G4: the non-member (hart 3) is still RUNNING"

    set hs [dmi_read $::DM_HALTSUM0]
    d2_chk [expr {$hs == 0x6}] \
        "G5: haltsum0 = 0x6 exactly (got [format 0x%08X $hs]) -- the same set, named by a different register"

    # ---- 4. resume is NOT broadcast at D2 --------------------------------
    dm_resumereq 1
    set r1 [dm_poll_status 1 dms_allrunning 400]
    d2_chk [expr {$r1 >= 0}] "G6a: hart 1 resumed when asked"
    dm_select 2
    set s2b [dmi_read $::DM_DMSTATUS]
    d2_chk [expr {[dms_allhalted $s2b] == 1}] \
        "G6b: hart 2 is STILL HALTED -- d2_spec 3 puts same-group resume broadcast OUT at D2, so a DM that resumes it too is out of spec"

    dm_resumereq 2
    set r2 [dm_poll_status 2 dms_allrunning 400]
    d2_chk [expr {$r2 >= 0}] "G7: hart 2 resumed when IT was asked"
}

set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbggrpmp" $verdict
puts "DMILOG FLATMAP=[format 0x%08X [sh_get 0x10060]] ADV3=[sh_get 0x10064] PHASE=[sh_get 0x10050]"
puts "DMILOG final CNT=[format {%d %d %d} [sh_get $CNT1] [sh_get $CNT2] [sh_get $CNT3]]"
d2_summary "dbggrpmp"
flush stdout
exit
