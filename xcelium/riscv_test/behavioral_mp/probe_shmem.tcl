source ../../disable_x_warnings.tcl

# Headless waveform probe -> writes each step to probe_trace.txt with an explicit
# flush (Xcelium buffers stdout, so we watch the FILE live). Prints from a few
# steps before the first 0x10000 access (sh_sel=1) through the arbiter handshake.

set STEP "50 ns"
set MAXSTEP 1200
set POSTMAX 80

set fh [open "probe_trace.txt" w]

proc v {path} {
    set r "?"
    catch { set r [value $path] }
    return $r
}

set ctx {}
set seen 0
set post 0

for {set i 0} {$i < $MAXSTEP} {incr i} {
    run $STEP
    set line [format "s%-4d sel=%s ack=%s req=%s gnt=%s done=%s cmr=%s cmrg=%s st=%s addr=%s en=%s we=%s shrd=%s" \
        $i \
        [v :uut:dut:sh_sel] [v :uut:dut:sh_acked] \
        [v :uut:dut:arb_req] [v :uut:dut:arb_gnt] [v :uut:dut:arb_done] \
        [v :uut:dut:core_mem_ready] [v :uut:dut:core_mem_ready_g] \
        [v :uut:dut:core:current_state] [v :uut:dut:data_addr] \
        [v :uut:dut:sh_en] [v :uut:dut:sh_we] [v :uut:dut:sh_rdata_reg]]

    set selv [v :uut:dut:sh_sel]

    if {!$seen} {
        lappend ctx $line
        if {[llength $ctx] > 6} { set ctx [lrange $ctx end-5 end] }
        # heartbeat every 40 steps so we know it's progressing through boot
        if {$i % 40 == 0} { puts $fh "..progress $line"; flush $fh }
        if {[string match *1* $selv]} {
            set seen 1
            puts $fh "==== context before first sh_sel=1 ===="
            foreach l $ctx { puts $fh $l }
            puts $fh "==== from first sh_sel=1 (handshake window) ===="
            flush $fh
        }
    } else {
        puts $fh $line
        flush $fh
        incr post
        if {$post > $POSTMAX} { puts $fh "==== POSTMAX reached ===="; break }
    }
}
puts $fh "==== probe done (seen=$seen) ===="
flush $fh
close $fh
exit
