# =============================================================================
# dbg_w2probe.tcl -- the D5 section-5.4-5 provocation shape, measured on the
# CHIP side so the implementer knows exactly what OpenOCD is about to meet.
#
#   ./xrun_dbg_verify.sh verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_w2probe.tcl
#
# BLIND-AUTHORED 2026-08-10 against d5_spec.md 5.4-5 (FROZEN).
#
# WHAT W2 IS (tree probe C26, verified in the RTL by this author):
#   debug_module.vhd sets `busy_r` ONLY on an accepted abstract `command`
#   and clears it in S_FIN.  A RESUME runs S_IDLE -> S_WAITH -> S_RESUME ->
#   S_RESWAIT and never touches `busy_r`.  During those states `mst_free` is
#   0, so a `command` write answers cmderr = BUSY and a data0/progbuf access
#   answers cmderr = BUSY with rsp_data 0 -- while `abstractcs.busy` (bit 12 =
#   busy_r) reads 0.  A debugger that polls `busy` correctly can therefore
#   have its next command refused with no way to know why.
#
# WHY THIS LEG EXISTS AT ALL
#   d5_spec 5.4-5 asks D5 to PROVOKE the wart through gdb and classify the
#   result.  That half needs the bridge and is review-at-implementation.  What
#   does NOT need the bridge is the shape itself: this file walks into the
#   window on the raw DMI port and prints the exact register values OpenOCD
#   will see, so the implementer is comparing a gdb symptom against a measured
#   signature instead of against a paragraph.  It is an OBSERVATION leg, and
#   it says so.
#
# WHAT IS GRADED AND WHAT IS ONLY REPORTED -- the distinction is the point:
#   GRADED (the instrument-liveness clauses; a leg that cannot reach the
#   window has measured nothing and must not print a classification):
#     P1 the victim halted
#     P2 an abstract command works BEFORE the provocation (so a later refusal
#        is attributable to the resume and not to a chip that never worked)
#     P3 a resumereq was accepted
#   REPORTED, never graded -- the classification:
#     W2-SEEN      cmderr = BUSY(1) while abstractcs.busy = 0   <- the wart
#     W2-BUSY-HONEST cmderr = BUSY(1) with abstractcs.busy = 1  <- benign
#     W2-ABSENT    cmderr = NONE(0)                             <- absorbed
#     W2-OTHER     anything else, printed verbatim
#
# NO DURATION ANYWHERE.  The provocation is "the very next DMI transaction
# after the resumereq write", which is an ORDERING over transactions.  It is
# not "within N microseconds of the resume", which would be a calibration and
# would stop covering anything the moment the DM's timing moved.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tramp_lib.tcl]} { source dbg_tramp_lib.tcl } else { source ../behavioral_mp/dbg_tramp_lib.tcl }

set VICTIM 1

puts "DMILOG ================ dbg_w2probe: the 5.4-5 dropped-resume shape ================"
flush stdout
if {![dmi_present]} { puts "DMILOG dbg_w2probe VERDICT=INSTRUMENT_DEAD" ; flush stdout ; exit }

d4_wait_ready

# ---- P1: halt the victim ----------------------------------------------------
dm_select $VICTIM
dm_haltreq $VICTIM
set s [dm_poll_status $VICTIM dms_allhalted 400 $::HALTREQ_BIT]
d2_chk [expr {$s >= 0}] "P1: hart $VICTIM halted on haltreq (dmstatus [format 0x%08X $s])"
dm_clr_haltreq $VICTIM

# ---- P2: an abstract command works BEFORE the provocation -------------------
d4_settle
# d4_abs_read returns a LIST {value cmderr}, not a bare value.  Measured
# defect, first run of this file: `format 0x%08X` on the list produced
# `expected integer but got "0 0"`, the check was never executed at all, and
# the run reported 2 checks against a floor of 3 -- caught by the floor and
# by nothing else, which is the R-D3-4(5) guard doing its job one level up.
set pre_r [d4_abs_read $::D4_R_A7]
set pre_v [lindex $pre_r 0]
set pre_e [lindex $pre_r 1]
set pre_acs [dmi_read $::DM_ABSTRACTCS]
d2_chk [expr {$pre_e == 0 && [acs_cmderr $pre_acs] == 0}] \
    "P2: an abstract GPR read completes cleanly BEFORE the provocation (a7=[format 0x%08X $pre_v], read-cmderr=$pre_e, abstractcs=[format 0x%08X $pre_acs], cmderr=[acs_cmderr $pre_acs]).  Without this a refusal after the resume would be unattributable"

# ---- P3 + the provocation ---------------------------------------------------
# resumereq, then the VERY NEXT DMI transaction is an abstract command.  No
# poll, no settle, no wait: that ordering IS the provocation.
dm_resumereq $VICTIM
set prov_acs0 [dmi_read $::DM_ABSTRACTCS]
dmi_write $::DM_COMMAND [ac_cmd $::D4_R_A7 0 1 0]
set prov_acs1 [dmi_read $::DM_ABSTRACTCS]
set ce [acs_cmderr $prov_acs1]
set bz [acs_busy   $prov_acs1]
puts "DMILOG W2 PROVOCATION: abstractcs immediately after resumereq = [format 0x%08X $prov_acs0]"
puts "DMILOG W2 PROVOCATION: abstractcs after the command           = [format 0x%08X $prov_acs1]  cmderr=$ce busy=$bz"

set klass "W2-OTHER"
if {$ce == 1 && $bz == 0} { set klass "W2-SEEN" } \
elseif {$ce == 1 && $bz == 1} { set klass "W2-BUSY-HONEST" } \
elseif {$ce == 0} { set klass "W2-ABSENT" }
puts "DMILOG W2 CLASSIFICATION = $klass"
puts "DMILOG   W2-SEEN         cmderr=BUSY(1) with abstractcs.busy=0 -- the wart is live on"
puts "DMILOG                   this chip.  A debugger polling `busy` correctly still gets"
puts "DMILOG                   its next command refused, with no register that explains it."
puts "DMILOG   W2-BUSY-HONEST  cmderr=BUSY(1) with busy=1 -- benign; a retry loop is right."
puts "DMILOG   W2-ABSENT       cmderr=NONE -- the command was accepted; no wart in this shape."
puts "DMILOG   This line is an OBSERVATION.  It is not a pass, it is not a failure, and"
puts "DMILOG   it is the input to the 5.4-5 disposition, which is Fable's to rule."
flush stdout

# Did the resume actually take?  Reported alongside, because "the command was
# refused" means something different depending on whether the hart resumed.
set s2 [dm_poll_status_ro dms_allrunning 400]
puts "DMILOG W2 resume outcome: [expr {$s2 >= 0 ? {the hart resumed} : {the resume was DROPPED (resumeack never set)}}] (dmstatus [format 0x%08X $s2])"
d2_chk [expr {$s2 >= 0 || $ce != 0}] \
    "P3: the resumereq either took effect or the provoking command was refused -- i.e. the leg really entered the window it exists to observe (resumed=[expr {$s2>=0}], cmderr=$ce)"

ac_clear_cmderr
set verdict [d2_run_to_verdict 800 "25 us"]
d2_report_verdict "dbg_w2probe" $verdict
d2_summary "dbg_w2probe" 3
flush stdout
exit
