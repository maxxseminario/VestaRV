# M5a shspin diagnosis: chunked run printing per-hart a0, hart0 pc/state, and
# the shared-window mailbox/lock words straight out of the behavioral shram.
# Word index = (addr - 0x10000) >> 2:
#   GO[1..3]=65..67  ENTRY[1..3]=69..71  DONE[1..3]=73..75
#   LOCK=80  CTR=81  OWNER=82
source ../../disable_x_warnings.tcl
puts "SPINDIAG START"
flush stdout
for {set i 1} {$i <= 50} {incr i} {
    run 2 ms
    puts "SPINDIAG t=[expr $i*2]ms pc0=[value :dut:core:pc] st0=[value :dut:core:current_state] a0=[value :a0] a1=[value :a0_1] a2=[value :a0_2] a3=[value :a0_3]"
    puts "SPINDIAG    GO1=[value :dut:shram(65)] DONE1=[value :dut:shram(73)] DONE2=[value :dut:shram(74)] DONE3=[value :dut:shram(75)] LOCK=[value :dut:shram(80)] CTR=[value :dut:shram(81)] OWNER=[value :dut:shram(82)]"
    flush stdout
}
puts "SPINDIAG DONE"
exit
