# M3c.3 debug: bounded, chunked sim with live progress + waveform DB.
# Runs 60 x 20us chunks (1.2 ms sim total), printing PC / cpu_ticks / data_addr
# after each chunk so a hang is visible (and killable) within seconds.

puts "SHDBG_STARTUP_DONE [clock seconds]"
flush stdout
for {set i 1} {$i <= 60} {incr i} {
    run 2 us
    puts "CHUNK $i t=[expr $i*2]us ticks=[value :uut:dut:dbg_cpu_ticks] pc=[value :uut:dut:core:pc] addr=[value :uut:dut:data_addr] state=[value :uut:dut:core:current_state] a0=[value :uut:dut:a0]"
    flush stdout
}
puts "SHDBG_TCL_DONE"
exit
