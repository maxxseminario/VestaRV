# M6 shuart diagnosis 4: WHEN does smclk_sel leave its reset value ("00"=HFXT)?
# Coarse 50us sweep from t=0; report first change, then stop.
puts "UARTDIAG4 START"
flush stdout
set sel0 "\"00\""
for {set i 0} {$i < 700} {incr i} {
    run 50 us
    set s [value :dut:system0:smclk_sel]
    if {$s ne $sel0} {
        puts "UARTDIAG4 sel=$s at t=[time] (i=$i)"
        flush stdout
        break
    }
}
puts "UARTDIAG4 final sel=[value :dut:system0:smclk_sel] clkcr=[value :dut:system0:SYS_CLK_CR] t=[time]"
flush stdout
exit
