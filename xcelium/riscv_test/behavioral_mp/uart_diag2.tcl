# M6 shuart diagnosis 2: hart 1's TX write lands (start_tx=1) but the frame
# never starts. Trace the UART baud/TX clock chain from the token release.
puts "UARTDIAG2 START"
flush stdout
set zero_q "\"00000000000000000000000000000000\""
run 15 ms
set released 0
for {set i 0} {$i < 30000} {incr i} {
    run 1 us
    if {[value :dut:shram(92)] ne $zero_q} { set released 1; break }
}
puts "UARTDIAG2 released=$released t=[time]"
flush stdout
if {$released} {
    for {set c 0} {$c < 2000} {incr c} {
        run 42 ns
        puts "CHN $c stx=[value :dut:uart0:start_tx] txip=[value :dut:uart0:tx_in_progress] rxip=[value :dut:uart0:rx_in_progress] crxip=[value :dut:uart0:clr_rx_in_progress] enb=[value :dut:uart0:en_baud_clk_src] bsrc=[value :dut:uart0:baud_clk_src] bcnt=[value :dut:uart0:baud_cntr] encb=[value :dut:uart0:en_clk_baud] cb=[value :dut:uart0:clk_baud] txc=[value :dut:uart0:tx_clk_cntr] entx=[value :dut:uart0:en_clk_tx] ctx=[value :dut:uart0:clk_tx] smclk=[value :dut:smclk] tcif=[value :dut:uart0:USR_UTCIF]"
    }
}
puts "UARTDIAG2 DONE"
flush stdout
exit
