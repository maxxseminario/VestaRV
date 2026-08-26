# PG3: regenerate the hart_tile LVS netlist (WITH power/ground) from the
# signoff DB. Standalone batch run:
#   cd ~/vestarv/signoff_mp && innovus -no_gui -batch -files tcl/hart_tile_lvs_netlist.tcl
#
# The flow's saveNetlist writes xsim.v only (no PG pins -- saveNetlist
# default). LVS needs VDD / VSS / VDD_SW / VDDG / VNW / VPW visible, so:
#   -includePowerGround  : emit PG nets + pin connections
#   -phys                : include physical-only insts (HEADBUF switches,
#                          FILLBIAS well taps, GPGBUF repeaters, well straps)
#                          -- these ARE the power-gating structure under test
#   -excludeCellInst     : plain tapless FILL* fillers (no devices worth
#                          netlisting; Myshkin tapeout precedent) PLUS
#                          FILLBIASA10TH: its CDL subckt is EMPTY (pure well
#                          straps, zero devices), so 7072 source instances can
#                          never match anything -- Pegasus reports every one
#                          as an unmatched instance. Their well-tie function
#                          is checked geometrically (softchk/LUP), not by LVS.
#                          The ANTENNA diodes are KEPT (real devices).
#
# FILLBIASNWA10TH ADDED TO THE EXCLUDE LIST, 2026-08-25.  The PG1 LUP.6 flow fix
# places four of these (one n-well tap abutting each pgaorep_* AO repeater), and
# the post-harden DRC ECO's note that "the master is a real 20 KB cell, not a
# shell" is TRUE OF THE GDS AND FALSE OF THE CDL.  Measured, in
# sc-ad10-pmk/lvs_netlist/tsmc65_hvt_sc_adv10_pmk.cdl:
#
#     .SUBCKT FILLBIASNWA10TH VDD VSS VNW
#     .ENDS FILLBIASNWA10TH
#
# ZERO DEVICES, exactly like FILLBIASA10TH two lines above it -- so every source
# instance is unmatchable and Pegasus would report all four.  It also has NO VPW
# PIN, and signoff_mp/lvs.sh line 116 appends " VNW=VDD VPW=VSS" to every
# `^X... *A10TH $PINS` line unconditionally; on this cell that produced a
# duplicate VNW plus a VPW the master does not have, and Pegasus aborted outright
# (NVN-13300, "Pin 'VPW' ... cannot be found in instance master").  That sed is
# still a live trap for any other A10TH cell lacking VNW or VPW -- FILLBIASPWA10TH
# has no VNW -- so narrow it there if such a cell ever reaches a netlist.
#   -excludeLeafCell     : leaf .SUBCKT definitions come from the kit CDLs at
#                          LVS time, not from verilog stubs
# -flat is NOT used: the tile is already a single level below leaf cells, and
# flat explodes the ram0 macro reference we want boxed.
#
# G0 (2026-07-22): this tcl now ALSO re-dumps pvs/hart_tile.lvslabels — the
# VDD_SW piece-center virtual-connect texts — so the netlist/labels/GDS triple
# always comes from the SAME cut (the A7 invalidation rule extended to labels).
# The Stage-F re-harden regenerated the netlist but left the Jul-11 PG4 labels
# in place; the moved cells put stale "VDD_SW:" texts on foreign nets and
# manufactured the 5:5-device tile LVS phantom (tie HI / PSO enable repeater
# correspondence). Dump block mirrors tcl/hart_tile_argus_lvs_netlist.tcl.
#
# 2026-08-24, TWO ADDITIONS.
#
# 1. SHORT SENTINELS.  Until now this dump emitted 407 "VDD_SW:" texts and
#    NOTHING ELSE, so the tile's shorts file has always been empty for a reason
#    that has nothing to do with the tile being short-free: with no CONFLICTING
#    power texts, FIND_SHORTS is text-blind and reports an empty file whether or
#    not a short exists.  That is not a theory -- in Stage J a REAL PDB3A
#    VDD-VSS ring short, invisible to Innovus, to the PG wrapper and to Calibre
#    DRC, produced exactly that empty file, and only conflicting texts caught
#    it.  Every tile "0 shorts" recorded before today is an ARTIFACT.  The chip
#    dump has done this correctly since Stage J
#    (pvs/MCU_castalia_penta.lvslabels ends in a VDD: / VSS: pair); this brings
#    the tile up to the same standard.  The two points are DERIVED from this DB
#    and VERIFIED to sit on M1 follow-pin rails of their own nets before they
#    are written -- writing coordinates blind would leave the check text-blind
#    in a way that looks armed.
#    NB the VSS: text also arms VDD_SW-vs-VSS detection on its own, because the
#    407 VDD_SW: texts are already there to conflict with it.
#
# 2. LABELS_ONLY MODE.  pvs/hart_tile.lvs.v is SHARED collateral (the penta chip
#    concatenates it) and re-writing it re-stamps a file other lineages depend
#    on.  Set LABELS_ONLY=1 in the environment to refresh ONLY the labels file
#    from the same DB.  The netlist keeps its mtime, and the labels come out
#    NEWER than it, which is the direction lvs.sh's G0 staleness gate wants.

set LABELS_ONLY [expr {[info exists ::env(LABELS_ONLY)] && $::env(LABELS_ONLY) ne "0"}]

restoreDesign /home/mseminario2/vestarv/innovus/common/hart_tile/dbs/hart_tile.signoff.innovus.dat hart_tile

if {$LABELS_ONLY} {
    puts "### VDDSW ### LABELS_ONLY=1 -- pvs/hart_tile.lvs.v is NOT rewritten"
} else {
saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLBIASNWA10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile.lvs.v
}

# --- VDD_SW M1 piece-center dump (PG4 item 22, now tracked + same-cut) ------
#
# LAYER 231, NOT 131, SINCE 2026-08-25.  READ THIS BEFORE CHANGING IT BACK.
#
# The tile presents exactly TWO supply ports, VDD and VSS.  VDD_SW is INTERNAL:
# it is made inside the tile by the 727 HEADBUF16MA10TH header switches and is
# not a boundary supply.  These texts exist only to (a) unify the 407 M1 pieces
# of that internal net under VIRTUAL_CONNECT -COLON YES and (b) give
# LVS_FIND_SHORTS a name that conflicts with the VSS: sentinel below, which at
# tile level is the ONLY instrument that can see a power short (the whole core
# is on switched power, so VDD-vs-VSS is not the pair that matters here).
#
# They used to go out on GDS layer 131, and the TSMC deck says of that layer
# BOTH of these things:
#     LAYER_MAP 131 -TEXTTYPE -lege 0 255 3227;
#     TEXT_LAYER       metal1_text;   // name the net
#     PORT -TEXT_LAYER metal1_text;   // AND declare a top-cell PORT
# so every VDD_SW: text also declared a port, and the layout compared 284 pins
# against the schematic's 283.  That single phantom pin was the last thing
# standing between this tile and an LVS MATCH.  Deleting the texts would have
# balanced it and BLINDED FIND_SHORTS; declaring VDD_SW a schematic port would
# have balanced it and been a lie about the tile boundary.
#
# Pegasus keeps the two roles on separate rules -- pegasusref, `port`: "Text
# ports processing does not depend on the text_layer command" -- so the texts
# now go out on layer 231, which signoff_mp/pvs/lvs_tile_ctl declares as
#     layer_def vddsw_net_text 231;
#     text_layer vddsw_net_text;     // name the net
#     attach     vddsw_net_text metal1;
# and deliberately does NOT list in any `port -text_layer`.  Connectivity,
# virtual connect and FIND_SHORTS see the texts exactly as before; the port
# list does not.  MEASURED, not assumed: with a real M1 bridge injected between
# the VDD_SW rail at (330.000,5.000) and the VSS rail at (330.000,3.000),
# lvs.rep.shorts still reports
#     SHORT 2. VDD_SW: - VSS: in hart_tile
#     "VDD_SW:" at (330.000, 5.000) on layer "231 vddsw_net_text"
#     "VSS:"    at (330.000, 3.000) on layer "3227 metal1_text"
# (pvs/hart_tile_poscontrol/run_poscontrol.sh regenerates that).
#
# THE LAYER AND THE CONTROL FILE ARE ONE FACT IN TWO PLACES.  A run of this
# tile that does not pass  pvs/lvs_tile_ctl  to lvs.sh gets 407 texts on a
# layer the deck has never heard of, which means NO virtual connect and NO
# sentinel -- silently.  signoff_mp/Makefile sets hart_tile_CTL for exactly
# this reason; keep them together.
#
# The two SENTINEL texts below stay on 131/13N on purpose: VDD and VSS ARE
# boundary ports of this tile, so their texts declaring ports is correct.
# pvs/hart_tile_vddsw.lvslabels (the chip-level tile-struct injection) also
# stays on 131 -- at chip level those texts sit below the primary cell and
# PORT -DEPTH -PRIMARY already keeps them out of the chip port list.
set fp [open /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile.lvslabels w]
set netp [dbGet top.nets.name VDD_SW -p]
if {$netp == 0} { puts "### VDDSW ### FATAL: no VDD_SW net in tile"; exit 1 }
array set lyrcnt {}
set cnt 0
foreach sw [dbGet ${netp}.sWires] {
    set lyr [dbGet ${sw}.layer.name]
    if {[info exists lyrcnt($lyr)]} { incr lyrcnt($lyr) } else { set lyrcnt($lyr) 1 }
    if {$lyr ne "M1"} { continue }
    set box [join [dbGet ${sw}.box]]
    set x1 [lindex $box 0]; set y1 [lindex $box 1]
    set x2 [lindex $box 2]; set y2 [lindex $box 3]
    set cx [expr {($x1 + $x2) / 2.0}]
    set cy [expr {($y1 + $y2) / 2.0}]
    puts $fp [format "231 %.3f %.3f VDD_SW:" $cx $cy]
    incr cnt
}
# --- SHORT SENTINELS, derived and verified against THIS DB ------------------
# The text layer for metalN is 130+N (pvs.lvs: LAYER_MAP 131..139 -TEXTTYPE,
# ATTACH metalN_text metalN).  So a sentinel is not restricted to M1 -- it just
# has to sit on real geometry of its own net, on the matching text layer.
#
# MEASURED ON THIS TILE, 2026-08-24: VDD has ZERO M1 shapes.  The whole core is
# on VDD_SW; VDD exists only as the always-on ring and straps that feed the 727
# HEADBUF switches.  A first version of this block demanded an M1 VDD rail and
# FATALed.  That failure is itself the useful measurement: at TILE level the
# short that matters is VDD_SW against VSS, not VDD against VSS.
#
# So this writes up to THREE sentinels and requires at least the first:
#   VSS: on an M1 VSS follow-pin rail
#           -- alone, this already arms VDD_SW-vs-VSS detection, because the
#              407 VDD_SW: texts above are there to conflict with it.
#   VDD: on the lowest layer where VDD actually has geometry
#           -- arms VDD-vs-VSS and VDD-vs-VDD_SW.
proc __rails {net wantlayer} {
    set out {}
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { return {} }
    foreach w [dbGet $netp.sWires] {
        set lay ""
        catch { set lay [dbGet $w.layer.name] }
        if {$wantlayer ne "" && $lay ne $wantlayer} { continue }
        set b {}
        catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b bx1 by1 bx2 by2
        if {($bx2 - $bx1) < 2.0 && ($by2 - $by1) < 2.0} { continue }
        lappend out [list $lay $bx1 $by1 $bx2 $by2]
    }
    return $out
}
proc __hist {net} {
    array set h {}
    set netp [dbGet -p top.nets.name $net]
    if {$netp eq "0x0" || $netp eq ""} { return "<no net>" }
    foreach w [dbGet $netp.sWires] {
        set lay ""
        catch { set lay [dbGet $w.layer.name] }
        if {[info exists h($lay)]} { incr h($lay) } else { set h($lay) 1 }
    }
    return [array get h]
}
puts "### SENTINEL ### VDD    sWire layers: [__hist VDD]"
puts "### SENTINEL ### VSS    sWire layers: [__hist VSS]"
puts "### SENTINEL ### VDD_SW sWire layers: [__hist VDD_SW]"

# --- the mandatory VSS sentinel, on an M1 follow-pin rail ---
set VSS_M1 [__rails VSS M1]
if {[llength $VSS_M1] == 0} {
    close $fp
    file delete -force /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile.lvslabels
    puts "### SENTINEL ### FATAL: no M1 VSS geometry -- cannot arm FIND_SHORTS at all."
    exit 1
}
# Pick the widest M1 VSS rail, deterministically (widest, then lowest y, then x).
set best {}
set bestw -1
foreach r $VSS_M1 {
    lassign $r lay bx1 by1 bx2 by2
    set w [expr {$bx2 - $bx1}]
    if {$w > $bestw} { set bestw $w ; set best $r }
}
lassign $best _l gx1 gy1 gx2 gy2
set SGX [expr {($gx1 + $gx2) / 2.0}]
set SGY [expr {($gy1 + $gy2) / 2.0}]
puts $fp [format "131 %.3f %.3f VSS:" $SGX $SGY]
set nsent 1
puts "### SENTINEL ### VSS: on M1 at ([format %.3f $SGX],[format %.3f $SGY]) -- arms VDD_SW-vs-VSS"

# --- the VDD sentinel, on the lowest layer where VDD has geometry ---
set VDD_PICK {}
foreach lyr {M1 M2 M3 M4 M5 M6 M7 M8} {
    set c [__rails VDD $lyr]
    if {[llength $c] > 0} {
        set bw -1
        foreach r $c {
            lassign $r lay bx1 by1 bx2 by2
            set a [expr {($bx2 - $bx1) * ($by2 - $by1)}]
            if {$a > $bw} { set bw $a ; set VDD_PICK $r }
        }
        break
    }
}
if {[llength $VDD_PICK] == 5} {
    lassign $VDD_PICK vlay vx1 vy1 vx2 vy2
    set SVX [expr {($vx1 + $vx2) / 2.0}]
    set SVY [expr {($vy1 + $vy2) / 2.0}]
    set tl [expr {130 + [string range $vlay 1 end]}]
    puts $fp [format "%d %.3f %.3f VDD:" $tl $SVX $SVY]
    incr nsent
    puts "### SENTINEL ### VDD: on $vlay (text layer $tl) at ([format %.3f $SVX],[format %.3f $SVY])"
} else {
    puts "### SENTINEL ### WARNING: VDD has no usable geometry in this cut."
    puts "### SENTINEL ###          VDD-vs-VSS is NOT armed; only VDD_SW-vs-VSS is."
}
close $fp
puts "### SENTINEL ### wrote $nsent sentinel text(s)"
puts "### VDDSW ### M1 VDD_SW pieces dumped: $cnt (+$nsent short sentinels)"
puts "### VDDSW ### sWire layer histogram: [array get lyrcnt]"
puts "### VDDSW ### tile fPlan.box:  [dbGet top.fPlan.box]"
puts "### VDDSW ### tile fPlan.coreBox: [dbGet top.fPlan.coreBox]"

exit
