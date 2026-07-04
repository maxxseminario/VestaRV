# irqctx diagnosis 2: per-mclk trace of hart 0 from just before the IRQ
# through the failing register check. Watches the regfile write port to
# catch any phantom write during IRQ entry (IRQ_SV/IRQ_JUMP) or iret
# (IRQ_REST). registers(1)=ra, (3)=gp, (4)=tp.
source ../../disable_x_warnings.tcl
set fail_pc_q "\"00000000000000001000010011101010\""
puts "DIAG2 START"
flush stdout
run 11088 us
set RF :dut:core:datapath_inst:rf
for {set c 0} {$c < 4000} {incr c} {
    run 42 ns
    puts "CYC $c pc=[value :dut:core:pc] st=[value :dut:core:current_state] we3=[value $RF:we3] a3=[value $RF:a3] wd3=[value $RF:wd3] ra=[value $RF:registers(1)] gp=[value $RF:registers(3)] tp=[value $RF:registers(4)] sp=[value :dut:core:stack_pointer]"
    if {[value :dut:core:pc] eq $fail_pc_q} { puts "DIAG2: reached fail label at cyc $c"; break }
}
for {set c 0} {$c < 20} {incr c} {
    run 42 ns
    puts "POST $c pc=[value :dut:core:pc] a0=[value :a0]"
}
puts "DIAG2 DONE"
flush stdout
exit
