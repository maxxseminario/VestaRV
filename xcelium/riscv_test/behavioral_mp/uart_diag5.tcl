# M6 shuart diagnosis 5: catch the writer of SYS_CLK_CR=0x04 (~8.2ms).
# Sample SYSTEM's register bus every 42ns from 8.19ms; print only accesses.
puts "UARTDIAG5 START"
flush stdout
run 8.19 ms
set n 0
for {set c 0} {$c < 2000} {incr c} {
    run 42 ns
    if {[value :dut:system0:en_mem] eq "'0'"} {
        puts "ACC $c t=[time] pc0=[value :dut:core:pc] ap=[value :dut:system0:addr_periph] wen=[value :dut:system0:wen] wd=[value :dut:system0:write_data] clkcr=[value :dut:system0:SYS_CLK_CR]"
        incr n
    }
    if {[value :dut:system0:SYS_CLK_CR] ne "\"000000000\""} {
        puts "HIT $c t=[time] pc0=[value :dut:core:pc] ap=[value :dut:system0:addr_periph] wen=[value :dut:system0:wen] wd=[value :dut:system0:write_data] clkcr=[value :dut:system0:SYS_CLK_CR]"
        break
    }
}
puts "UARTDIAG5 DONE n=$n clkcr=[value :dut:system0:SYS_CLK_CR] t=[time]"
flush stdout
exit
