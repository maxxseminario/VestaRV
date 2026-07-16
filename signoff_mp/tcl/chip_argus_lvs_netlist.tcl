# Argus A6: chip-top LVS netlist WITH power/ground, from the chip_top_argus
# signoff DB. Same recipe as tcl/chip_lvs_netlist.tcl (the Castalia C0 chip) --
# see there for the option rationale. Deltas: the ARGUS chip DB (.dat dir is
# named chip_top_argus.final but the DESIGN/TOPCELL inside is "chip_top", a FLAT
# run whose MCU hierarchy is physically flattened) + argus-namespaced output.
#
# The chip DB re-asserts setCheckMode -tapeOut true at restore and FATALs on the
# 3 timing-less analog abstracts inherited through mcu0 -- the .mode is patched
# -tapeOut false on disk (accept_chip preflight / manual) + restore_db_file_check 0.
set restore_db_file_check 0
restoreDesign /home/mseminario2/vestarv/innovus/common/dbs/chip_top_argus.final.innovus.dat chip_top

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_argus.lvs.v

# --- confirm mcu0 origin (MCU coords == chip coords iff mcu0 at 0,0) ---------
foreach cand {mcu0 hart0 mcu0/hart0} {
    set ip [dbGet top.insts.name $cand -p]
    if {$ip != 0} {
        puts "### ORG ### inst $cand  pt=[dbGet ${ip}.pt]  orient=[dbGet ${ip}.orient]  box=[dbGet ${ip}.box]"
    } else {
        puts "### ORG ### inst $cand : (not a physical inst)"
    }
}

exit
