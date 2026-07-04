# M6 shuart diagnosis 3: is smclk really frozen? Sub-clock (7ns) sampling of
# the whole smclk generation chain right after the token release.
puts "UARTDIAG3 START"
flush stdout
set zero_q "\"00000000000000000000000000000000\""
run 15 ms
set released 0
for {set i 0} {$i < 30000} {incr i} {
    run 1 us
    if {[value :dut:shram(92)] ne $zero_q} { set released 1; break }
}
puts "UARTDIAG3 released=$released t=[time]"
flush stdout
if {$released} {
    for {set c 0} {$c < 120} {incr c} {
        run 7 ns
        puts "SUB $c hfxt=[value :dut:clk_hfxt] und=[value :dut:system0:smclk_undiv] smi=[value :dut:system0:smclk] smo=[value :dut:smclk] off=[value :dut:system0:smclk_off] sel=[value :dut:system0:smclk_sel] div=[value :dut:system0:smclk_div] mclk=[value :dut:mclk]"
    }
}
puts "UARTDIAG3 DONE"
flush stdout
exit
