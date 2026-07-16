# Argus A6: dump the ACTUAL placed box-LL + orient of all 18 tiles from the chip
# DB (authoritative -- the A6 re-cut / legalization can differ from the tcl
# constants; mcu0/hart0 landed at y=565.085 not the tcl's Y_R0=568.085). The
# 18-tile label generator consumes this table instead of re-deriving placements.
set restore_db_file_check 0
restoreDesign /home/mseminario2/vestarv/innovus/common/dbs/chip_top_argus.final.innovus.dat chip_top
for {set h 0} {$h < 18} {incr h} {
    set ip [dbGet top.insts.name mcu0/hart$h -p]
    if {$ip == 0} { puts "### PLACE ### h=$h MISSING"; continue }
    set box [join [dbGet ${ip}.box]]
    puts "### PLACE ### h=$h orient=[dbGet ${ip}.orient] box=$box"
}
exit
