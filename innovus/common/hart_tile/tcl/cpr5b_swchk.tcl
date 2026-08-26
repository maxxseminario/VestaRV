# CPR5b: prove the -10 sWire delta is shields, not PG fabric.
proc hist {db} {
	restoreDesign $db hart_tile
	array set h {}
	foreach sw [dbGet -e top.sNets.sWires] {
		set k "[dbGet $sw.net.name]/[dbGet $sw.layer.name]/[dbGet $sw.status]/[dbGet $sw.shape]"
		if {[info exists h($k)]} { incr h($k) } else { set h($k) 1 }
	}
	foreach k [lsort [array names h]] { puts "SWHIST $db $k $h($k)" }
	puts "SWTOT $db [llength [dbGet -e top.sNets.sWires]]"
}
hist dbs/hart_tile.signoff.innovus.dat
exit
