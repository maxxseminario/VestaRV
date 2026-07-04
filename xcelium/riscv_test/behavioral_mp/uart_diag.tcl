# M6 shuart diagnosis: hart 0's UART dance PASSES (it writes TOKEN=1) but
# hart 1 latches FAIL soon after unparking. Coarse-poll until TOKEN (shram
# word 92 = 0x10170) becomes nonzero, then per-42ns trace of the shared-UART
# slave port + UART core state + hart 1 until a0_1 = DEADBEEF.
# (xmsim `value` returns bit-strings WITH literal quote chars.)
puts "UARTDIAG START"
flush stdout
set zero_q "\"00000000000000000000000000000000\""
set dead_q "\"11011110101011011011111011101111\""
run 15 ms
set released 0
for {set i 0} {$i < 30000} {incr i} {
    run 1 us
    if {[value :dut:shram(92)] ne $zero_q} { set released 1; break }
}
puts "UARTDIAG released=$released t=[time]"
flush stdout
if {$released} {
    for {set c 0} {$c < 4000} {incr c} {
        run 42 ns
        puts "CYC $c pc1=[value :dut:hart1:core:pc] uen=[value :dut:shslv_uart_en] a=[value :dut:sh_addr] we=[value :dut:sh_we] wd=[value :dut:sh_wdata] urd=[value :dut:uart0_sh_rdata] rdu=[value :dut:shslv_rd_uart] BR=[value :dut:uart0:UART_BR] CR=[value :dut:uart0:UART_CR] stx=[value :dut:uart0:start_tx] txip=[value :dut:uart0:tx_in_progress] tcif=[value :dut:uart0:USR_UTCIF] a1=[value :a0_1]"
        if {[value :a0_1] eq $dead_q} { puts "UARTDIAG HART1 FAILED at cyc $c"; break }
    }
}
puts "UARTDIAG DONE"
flush stdout
exit
