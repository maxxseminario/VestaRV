# irqctx diagnosis: coarse 1us timeline of hart 0 through the irqctx test.
# Prints pc / core state / CLINT msip(0) / a0 so we can see (a) whether the
# msip IRQ ever fires, (b) whether the ISR runs, (c) which check fails.
# Landmarks (build/rv32ui/rv32ui-p-irqctx.dump):
#   ipi1_go=0x832a  spin_done=0x8348  reg checks 0x8348-0x84xx
#   p2_wait~0x84c8  redirect_target~0x84d4  fail spin=0x84ea  pass=0x84e6
#   msip_isr=0x84f6-0x8534
source ../../disable_x_warnings.tcl
set dead_q "\"11011110101011011011111011101111\""
puts "DIAG START"
flush stdout
run 8 ms
for {set i 0} {$i < 6000} {incr i} {
    run 1 us
    puts "T[expr 8000+$i]us pc0=[value :dut:core:pc] st0=[value :dut:core:current_state] msip0=[value :dut:clint0:msip_reg] a0=[value :a0]"
    if {[value :a0] eq $dead_q} { puts "DIAG: a0=DEADBEEF at T[expr 8000+$i]us"; break }
    flush stdout
}
puts "DIAG DONE"
flush stdout
exit
