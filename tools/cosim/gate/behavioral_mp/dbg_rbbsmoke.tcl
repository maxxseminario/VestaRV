# =============================================================================
# dbg_rbbsmoke.tcl -- the BRIDGE's own smoke leg.  Stands the remote_bitbang
# server up, serves ONE client, and reports.  No OpenOCD, no gdb: the client is
# a 60-line python script that speaks the real byte protocol, so this leg
# separates "the bridge works" from "the debugger stack works" -- which are two
# different claims and the first one has to be true first.
#
#   D5_PORTFILE=/path/to/portfile ./xrun_dbg_verify.sh \
#       verify_castaliadebug ../kba/xrv32ua-p-dbgtrpmp.rcf dbg_rbbsmoke.tcl
#
# WHAT IT PROVES, and the one that matters is the third:
#   1. xmsim's embedded Tcl can listen on a TCP socket in a REAL elaboration of
#      the actual design (the ipc probe measured this on a toy; F8 downgraded
#      it to CIRCUMSTANTIAL for xmsim proper).
#   2. The pin-set / 'R' / reply loop drives the five JTAG formals.
#   3. THE PHASE IS RIGHT.  The client reads IDCODE and compares against
#      0x1CA57EEF / 0x1A265EEF selected by D2_NHARTS.  A one-phase-late sample
#      returns the whole stream shifted by one bit -- 0x0E52BF77 -- which looks
#      structured and reads as an RTL problem.  The client prints BOTH the
#      value and the shifted-by-one value so the failure names itself.
# =============================================================================

if {[llength [info procs rbb_session]] == 0} {
    if {[file exists dbg_rbb_bridge.tcl]} {
        source dbg_rbb_bridge.tcl
    } else {
        source ../behavioral_mp/dbg_rbb_bridge.tcl
    }
}

set NH [expr {[info exists ::env(D2_NHARTS)] ? $::env(D2_NHARTS) : 4}]
puts "DMILOG dbg_rbbsmoke: NHARTS=$NH expected IDCODE = [expr {$NH == 18 ? $::TAP_IDCODE_ARGUS : $::TAP_IDCODE_CASTALIA}]"
flush stdout

rbb_session

puts "DMILOG dbg_rbbsmoke: session returned -- the interpreter is BACK (Q does not exit)."
puts "DMILOG   tck=$::RBB_TCK bytes_in=$::RBB_BYTES_IN bytes_out=$::RBB_BYTES_OUT dmi_xact=$::RBB_DMI_XACT dmiresets=$::RBB_DMIRESETS"
puts "DMILOG   sim advanced by this bridge: ${::RBB_SIMNS} ns"
flush stdout
exit
