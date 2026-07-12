################################################################################
# check_padring_vs_castalia.tcl -- C0 pad-ring diff-check (Flavor A vs the
# generated platform_castalia ring).
#
# Compares the hand-maintained Flavor A DIE-ring lists
# (tcl/chip_top_padlists.tcl, Myshkin die reference: 55 die pads) against the
# generated QFN-44 PACKAGE-ring lists
# (platform_castalia/out/pnr/chip_top_padring.tcl, from the package model in
# generate.py). The two are NOT expected to be identical -- the package ring
# has 43 pads and different side assignments (the bond map absorbs the
# difference) -- so this check separates:
#   FAIL  a package signal/supply pad with NO die pad at all (real drift:
#         the generator and the PnR stub disagree on what pads exist)
#   WARN  a pad present on both rings but on different sides / different
#         relative order (the known die-ring-vs-package-order question --
#         placement semantics stay Flavor A's until that is reconciled)
#   INFO  die-only pads (poc, duplicated supplies, unbonded aio electrodes)
#         and analog package signals whose die electrode is bond-map defined
#
# Usage:
#   standalone:  tclsh tcl/check_padring_vs_castalia.tcl [generated.tcl]
#                (default ../platform_castalia/out/pnr/chip_top_padring.tcl,
#                 relative to the innovus_mp run dir)
#   in-flow:     source tcl/check_padring_vs_castalia.tcl
#                check_padring_vs_castalia $file   ;# returns #FAILs, never errors
################################################################################

# Captured at SOURCE time: [info script] inside the proc would resolve to the
# CALLER's script at call time, not this file.
set _padx_dir [file dirname [file normalize [info script]]]

# Translate a generated (package-model) pad instance name to the die (RTL
# port) naming used by the Flavor A stub netlist. Generated GPIO ports are
# 0-indexed (P0-P3); the RTL/die ports are 1-indexed (prt1-prt4).
proc _padx_xlate {name} {
    regsub {^PAD_} $name {} n
    if {[regexp {^P([0-3])_([0-7])$} $n -> port bit]} {
        return "prt[expr {$port + 1}]_$bit"
    }
    switch -- $n {
        RESETN  { return resetn }
        VDD     { return vdd }
        VSS     { return vss }
        VDDPST  { return vddio }
        VSSPST  { return vssio }
        AVDD    { return avdd }
        AVSS    { return avss }
        RE - CE - ATP_IN - ATP_OUT { return "analog:$n" }
        default { return "unknown:$n" }
    }
}

# Normalize a die pad instance name to its base signal (vdd_0 -> vdd, ...).
proc _padx_dienorm {name} {
    regsub {^PAD_} $name {} n
    regsub {^(vdd|vss|vddio|vssio)_[0-9]+$} $n {\1} n
    return $n
}

proc check_padring_vs_castalia {{genFile ""}} {
    if {$genFile eq ""} {
        set genFile "../platform_castalia/out/pnr/chip_top_padring.tcl"
    }
    set dieFile [file join $::_padx_dir chip_top_padlists.tcl]

    if {![file readable $genFile]} {
        puts "PADCHECK: generated ring not found ($genFile) -- skipping"
        return 0
    }

    # Load both rings in throwaway interps (no variable spill into the flow).
    set ip [interp create]
    $ip eval [list source $dieFile]
    foreach side {LEFT BOTTOM RIGHT TOP} {
        set die($side) [$ip eval [list set $side]]
    }
    interp delete $ip
    set ip [interp create]
    $ip eval [list source $genFile]
    foreach side {LEFT BOTTOM RIGHT TOP} {
        set gen($side) [$ip eval [list set PADRING_$side]]
    }
    interp delete $ip

    # Index the die ring: base signal -> side(s)
    array set dieside {}
    foreach side {LEFT BOTTOM RIGHT TOP} {
        foreach inst $die($side) {
            lappend dieside([_padx_dienorm $inst]) $side
        }
    }

    set nfail 0
    set nwarn 0
    set ninfo 0
    puts "PADCHECK: Flavor A die ring vs generated package ring ($genFile)"
    puts [format "  %-14s %-14s %-8s %-8s %s" PACKAGE_PAD DIE_NAME PKG_SIDE DIE_SIDE VERDICT]
    foreach side {LEFT BOTTOM RIGHT TOP} {
        foreach inst $gen($side) {
            set dn [_padx_xlate $inst]
            if {[string match analog:* $dn]} {
                puts [format "  %-14s %-14s %-8s %-8s %s" $inst $dn $side aio "INFO (electrode = bond map)"]
                incr ninfo
                continue
            }
            if {[string match unknown:* $dn]} {
                puts [format "  %-14s %-14s %-8s %-8s %s" $inst $dn $side - "FAIL (no translation -- new package pad?)"]
                incr nfail
                continue
            }
            if {![info exists dieside($dn)]} {
                puts [format "  %-14s %-14s %-8s %-8s %s" $inst $dn $side - "FAIL (no die pad)"]
                incr nfail
            } elseif {[lsearch -exact $dieside($dn) $side] < 0} {
                puts [format "  %-14s %-14s %-8s %-8s %s" $inst $dn $side [join $dieside($dn) ,] "WARN (side differs)"]
                incr nwarn
            } else {
                puts [format "  %-14s %-14s %-8s %-8s %s" $inst $dn $side $side "ok"]
            }
        }
    }

    # Die-only pads (expected: poc, supply duplicates, unbonded electrodes).
    set genset {}
    foreach side {LEFT BOTTOM RIGHT TOP} {
        foreach inst $gen($side) {
            set dn [_padx_xlate $inst]
            if {![string match analog:* $dn]} { lappend genset $dn }
        }
    }
    set dieonly {}
    foreach base [lsort [array names dieside]] {
        if {[string match aio_* $base]} { continue }
        if {[lsearch -exact $genset $base] < 0} { lappend dieonly $base }
    }
    if {[llength $dieonly]} {
        puts "  INFO: die-only pads (no package pin): [join $dieonly {, }]"
        incr ninfo
    }
    puts "  INFO: die analog electrodes: avss + 12x aio + avdd on BOTTOM; package bonds AVSS/RE/CE/ATP_IN/ATP_OUT/AVDD"

    puts "PADCHECK: $nfail FAIL, $nwarn WARN (side/order -- placement stays Flavor A), $ninfo INFO"
    return $nfail
}

# Standalone driver (tclsh); inert when sourced inside Innovus.
if {[info exists argv0] && [file tail [info script]] eq [file tail $argv0]} {
    set f [expr {[llength $argv] ? [lindex $argv 0] : ""}]
    exit [expr {[check_padring_vs_castalia $f] > 0 ? 1 : 0}]
}
