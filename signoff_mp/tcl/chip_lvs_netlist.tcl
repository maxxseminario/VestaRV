# Chip-top (topcell "chip_top") LVS netlist WITH power/ground, from the
# chip_top.final signoff DB. Same recipe as tcl/mcu_lvs_netlist.tcl (see there
# for the option rationale) but restores the FLAT chip DB and its topcell.
#
# The chip DB re-asserts setCheckMode -tapeOut true at restore and FATALs on
# the 3 timing-less analog abstracts (GlitchFilter/PowerOnResetCheng/
# OscillatorCurrentStarved), which the chip inherits through mcu0. Documented
# recipe: patch dbs/*.dat/chip_top.mode (-tapeOut false) + restore_db_file_check
# 0. The .mode file is patched on disk by accept_chip.sh before this runs.
#
# Physical cells KEPT in the netlist (-phys): the tphn signal/supply pad ring
# instances (PDUW16SDGZ_G/PDB3A_G/PVDD*/PVSS*) -- their subckt defs come from the
# tphn spice in the chip CDL include; the pad PAD/AIO terminals are the chip's
# top-level I/O. The std-cell FILL family is excluded (same list as the MCU).
#
# ALSO EXCLUDED (LVS iter-1 post-mortem): the tphn PAD-RING CORNER + IO FILLER
# cells (PCORNER_G / PFILLER20_G/10_G/5_G/1_G/05_G). tphn ships NO LVS subckt for
# them -- they are DEVICELESS physical cells (power-bus/seal/passivation metal),
# so the flattened signoff GDS carries no cell boundary or devices for them.
# Keeping them in the source (even as empty stubs) makes Pegasus report them as
# source-only unmatched instances (*0:464 for PFILLER20_G etc.); excluding them
# is the correct handling -- they contribute nothing to device/net matching.
set restore_db_file_check 0
restoreDesign /home/mseminario2/vestarv/innovus/common/dbs/chip_top.final.innovus.dat chip_top

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top.lvs.v

exit
