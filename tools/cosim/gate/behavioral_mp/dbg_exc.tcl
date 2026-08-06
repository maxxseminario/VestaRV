# =============================================================================
# dbg_exc.tcl -- the F-D2-0 harness: a synchronous exception taken IN DEBUG
# MODE must re-enter debug mode, in BOTH delivery polarities.
#
#   ./xrun_dbg.sh rv32ua-p-dbgexcmp dbg_exc.tcl
#
# It is the debugger, and it is the D1 mechanism: no Debug Module exists and
# none is needed -- the harness forces the tiles' `dbg_haltreq` ports, exactly
# as dbg_halt.tcl does, which is why this detector can join the debug row's
# instrument set today rather than after D2's DM.
#
# WHAT THE HARNESS SEES THAT THE IMAGE CANNOT
#   The image measures the ARCHITECTURAL contract: two entries, dpc/dcsr/mepc/
#   mcause intact, both victims back out and running.  Three of the contract's
#   clauses are STRUCTURAL and have no in-band expression at all, and they are
#   this file's:
#     X1  `trap_flag` must NEVER latch on either victim.  It is a tile output
#         with no software-visible mirror; a build that re-enters debug mode
#         correctly but still pulses trap_flag has told the outside world the
#         chip trapped, and only a port read can see it.
#     X2  cpu_state must NEVER be TRAP_STATE on a victim.  On the legacy
#         polarity that IS the failure -- the terminal wedge -- and naming it
#         turns a bare "the second entry never came" into a diagnosis.
#     X3  THE UNRECOVERABLE-PARK CLASS: a victim sitting in SLEEPING (or any
#         parked state) with `dbg_halted` STILL ASSERTED.  That hart can never
#         be halted again -- the core's halt-take requires debug_mode = '0' --
#         so it is lost, and no a0 anywhere can say so.
#     X4  after the `dret`, `dbg_halted` must go LOW again: the hart really
#         left debug mode rather than merely resuming inside it.
#
# EVERY CHECK IS AN ORDERING OR A NEVER, not a duration.  X1-X3 are "never,
# across a window bounded by an EVENT the image publishes" (READY -> ENTRIES
# == 2 or the budget), and X4 is "after POST".  The one bound that is a count
# is the sampling budget itself, and its expiry is reported as its own
# classification (EXC_TIMEOUT) rather than folded into a verdict.
#
# AT UNIMPLEMENTED HEAD both defects are LIVE, so this harness is expected to
# print findings.  That is the seen-to-FAIL leg; read the EXCLOG lines beside
# the image's a1.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }

set VICTIMS {1 2}
set BYSTANDER 3
set BLK(1) 0x10880
set BLK(2) 0x108C0
set O_ENTRIES 0
set O_TRIP    40
set O_READY   44
set O_POST    52
set O_EXTRA   56

proc port {h n} { return ":dut:hart${h}:${n}" }
proc bit1 {p} {
    if {[catch {value $p} v]} { return -1 }
    if {[string match {*1*} $v]} { return 1 }
    return 0
}

# ---- 0. do the D1 debug ports exist at all? --------------------------------
set PORTS 1
foreach h $VICTIMS {
    if {[catch {value [port $h dbg_halted]} e]} {
        puts "EXCLOG PORT_ABSENT hart=$h path=[port $h dbg_halted] err=$e"
        puts "EXCLOG VERDICT=INSTRUMENT_DEAD (no D1 debug interface in this build)"
        flush stdout
        set PORTS 0
        break
    }
}

# trap_flag is a tile OUTPUT; if the name does not resolve, X1 is reported as
# UNCHECKED rather than silently passing (an absent probe is not a clean one).
set TF_OK 1
foreach h $VICTIMS {
    if {[catch {value [port $h trap_flag]} e]} { set TF_OK 0 }
}
if {!$TF_OK} { puts "EXCLOG X1 UNCHECKED -- trap_flag does not resolve on a victim" }

# ---- 1. wait for both victims to publish READY -----------------------------
set ready 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get [expr {$BLK(1)+$O_READY}]] == 1 && [sh_get [expr {$BLK(2)+$O_READY}]] == 1} {
        set ready 1 ; break
    }
}
puts "EXCLOG victims READY=$ready after i=$i"
flush stdout
if {!$ready} { puts "EXCLOG VICTIMS_NEVER_READY -- a test-side finding, not an RTL one" }

# ---- 2. halt both victims --------------------------------------------------
array set halted {1 0 2 0}
array set tf_seen {1 0 2 0}
array set trap_seen {1 0 2 0}
array set park_seen {1 0 2 0}
if {$PORTS && $ready} {
    foreach h $VICTIMS {
        if {[catch {force [port $h dbg_haltreq] '1'} e]} {
            puts "EXCLOG FORCE_REFUSED hart=$h err=$e"
        }
    }
    puts "EXCLOG haltreq forced on harts $VICTIMS"
    flush stdout
}

# ---- 3. the window: sample until BOTH victims reach ENTRIES == 2 -----------
# 500 ns per sample (~12 mclk), the D1 dbg_halt.tcl rate -- fine enough to
# land inside a halt window that wait-for-release makes microseconds long.
set done 0
for {set i 0} {$i < 8000} {incr i} {
    run 500 ns
    foreach h $VICTIMS {
        if {$PORTS} {
            if {[bit1 [port $h dbg_halted]] == 1} {
                if {!$halted($h)} {
                    set halted($h) 1
                    catch {release [port $h dbg_haltreq]}
                    puts "EXCLOG halted hart=$h at sample $i -- request released"
                    flush stdout
                }
            }
        }
        if {$TF_OK && [bit1 [port $h trap_flag]] == 1} { set tf_seen($h) 1 }
        set st [d2_state $h]
        if {$st eq "TRAP_STATE"} { set trap_seen($h) 1 }
        if {$PORTS && $st eq "SLEEPING" && [bit1 [port $h dbg_halted]] == 1} {
            set park_seen($h) 1
        }
    }
    if {[sh_get [expr {$BLK(1)+$O_ENTRIES}]] >= 2 && [sh_get [expr {$BLK(2)+$O_ENTRIES}]] >= 2} {
        set done 1 ; break
    }
}
puts "EXCLOG window i=$i reentered_both=$done"
if {!$done} { puts "EXCLOG EXC_TIMEOUT -- at least one victim never re-entered inside the sampling window" }
flush stdout

foreach h $VICTIMS {
    d2_chk [expr {!$tf_seen($h)}] \
        "X1.$h: trap_flag NEVER latched on hart $h (a debug-mode exception must not tell the outside world the chip trapped)"
    d2_chk [expr {!$trap_seen($h)}] \
        "X2.$h: hart $h was NEVER in TRAP_STATE (on the legacy polarity that terminal wedge IS the finding)"
    d2_chk [expr {!$park_seen($h)}] \
        "X3.$h: hart $h never parked with dbg_halted still asserted -- the UNRECOVERABLE-PARK class, which no a0 can see"
    puts "EXCLOG   hart$h state=[d2_state $h] halted=[expr {$PORTS ? [bit1 [port $h dbg_halted]] : {n/a}}] ENTRIES=[sh_get [expr {$BLK($h)+$O_ENTRIES}]] TRIP=[format 0x%08X [sh_get [expr {$BLK($h)+$O_TRIP}]]] EXTRA=[sh_get [expr {$BLK($h)+$O_EXTRA}]]"
}
puts "EXCLOG   bystander hart$BYSTANDER state=[d2_state $BYSTANDER] CNT=[sh_get 0x10924]"
flush stdout

# ---- 4. after the image releases them, debug mode must be OVER ------------
set posted 0
for {set i 0} {$i < 400} {incr i} {
    run 200 us
    if {[sh_get [expr {$BLK(1)+$O_POST}]] != 0 && [sh_get [expr {$BLK(2)+$O_POST}]] != 0} {
        set posted 1 ; break
    }
}
if {$PORTS && $posted} {
    foreach h $VICTIMS {
        d2_chk [expr {[bit1 [port $h dbg_halted]] == 0}] \
            "X4.$h: dbg_halted went LOW after the dret -- hart $h really left debug mode"
    }
} elseif {$PORTS} {
    puts "EXCLOG X4 UNREACHED -- a victim never published POST, so there was no dret to check."
    foreach h $VICTIMS {
        puts "EXCLOG   hart$h state=[d2_state $h] halted=[bit1 [port $h dbg_halted]]"
    }
}

set verdict [d2_run_to_verdict 2400 "25 us"]
d2_report_verdict "dbgexcmp" $verdict
foreach h $VICTIMS {
    set b $BLK($h)
    puts "EXCLOG hart$h ENTRIES=[sh_get [expr {$b+$O_ENTRIES}]] DPC1=[format 0x%08X [sh_get [expr {$b+4}]]] DPC2=[format 0x%08X [sh_get [expr {$b+8}]]] DCSR1=[format 0x%08X [sh_get [expr {$b+12}]]] DCSR2=[format 0x%08X [sh_get [expr {$b+16}]]]"
    puts "EXCLOG hart$h MEPC1=[format 0x%08X [sh_get [expr {$b+20}]]] MEPC2=[format 0x%08X [sh_get [expr {$b+24}]]] MCAUSE1=[format 0x%08X [sh_get [expr {$b+28}]]] MCAUSE2=[format 0x%08X [sh_get [expr {$b+32}]]] CNT=[sh_get [expr {$b+36}]] POST=[format 0x%08X [sh_get [expr {$b+52}]]]"
}
d2_summary "dbgexcmp"
flush stdout
exit
