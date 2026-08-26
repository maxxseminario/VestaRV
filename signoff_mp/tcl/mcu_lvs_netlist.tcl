# PG3: regenerate the MCU_MP (top cell "MCU") LVS netlist WITH power/ground
# from the signoff DB. Same recipe as hart_tile_lvs_netlist.tcl (see there
# for the option rationale). The kickoff warns the MCU restore can hit a
# tapeOut-mode fatal on the 3 untimed analog macros -- if that fires, the
# fallback is setCheckMode -netlist false / regenerating during a flow run.
# The MCU signoff DB re-asserts setCheckMode -tapeOut true at restore and
# FATALs on the 3 timing-less analog abstracts (GlitchFilter/
# PowerOnResetCheng/OscillatorCurrentStarved). setCheckMode BEFORE restore
# does NOT help (the DB's own .mode file wins). The documented recipe
# (M14/M16 devlogs) is: patch dbs/*.dat/MCU.mode (-tapeOut false) +
# set restore_db_file_check 0. The .mode file is patched on disk.
set restore_db_file_check 0
restoreDesign /home/mseminario2/vestarv/innovus/common/MCU_MP/dbs/MCU_MP.signoff.innovus.dat MCU

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/MCU.lvs.v

exit
