# M5a shspin diagnosis 2 (fixed): xmsim `value` returns the bit-string WITH
# literal quote chars — compare against quoted literals. Coarse-poll until
# GO1 (shram word 65) is written, then per-mclk trace of hart1 through its
# first critical section until a0_1 = DEADBEEF.
source ../../disable_x_warnings.tcl
puts "DIAG2 START"
flush stdout
set zero_q "\"00000000000000000000000000000000\""
set dead_q "\"11011110101011011011111011101111\""
run 8 ms
set released 0
for {set i 0} {$i < 4000} {incr i} {
    run 1 us
    if {[value :dut:shram(65)] ne $zero_q} { set released 1; break }
}
puts "DIAG2 released=$released"
flush stdout
if {$released} {
    for {set c 0} {$c < 4000} {incr c} {
        run 42 ns
        puts "CYC $c pc1=[value :dut:hart1:core:pc] st1=[value :dut:hart1:core:current_state] da1=[value :dut:hart1:data_addr] wen1=[value :dut:hart1:wen_re] req=[value :dut:hart1:sh_req] gnt=[value :dut:hart1:sh_gnt] done=[value :dut:hart1:sh_done] acked=[value :dut:hart1:sh_acked] ackwe=[value :dut:hart1:sh_acked_we] ackok=[value :dut:hart1:sh_ack_ok] dph=[value :dut:hart1:sh_dphase] rreg=[value :dut:hart1:sh_rdata_reg] GO1=[value :dut:shram(65)] LOCK=[value :dut:shram(80)] CTR=[value :dut:shram(81)] OWN=[value :dut:shram(82)] a1=[value :a0_1]"
        if {[value :a0_1] eq $dead_q} { puts "DIAG2 HART1 FAILED at cyc $c"; break }
    }
    # a few extra cycles of context after the failure
    for {set c 0} {$c < 60} {incr c} {
        run 42 ns
        puts "POST $c pc1=[value :dut:hart1:core:pc] LOCK=[value :dut:shram(80)] CTR=[value :dut:shram(81)] OWN=[value :dut:shram(82)]"
    }
}
puts "DIAG2 DONE"
flush stdout
exit
