source ../../disable_x_warnings.tcl
set cafe "\"11001010111111101011101010111110\""
set fp [open shboot_prog.txt w]
for {set i 1} {$i <= 12} {incr i} {
    run 10 ms
    set n 0
    for {set h 1} {$h <= 17} {incr h} {
        if {[value :uut:a0_$h] eq $cafe} { incr n }
    }
    puts $fp "t=[expr $i*10]ms  tiles_PASS=$n / 17"
    flush $fp
}
close $fp
exit
