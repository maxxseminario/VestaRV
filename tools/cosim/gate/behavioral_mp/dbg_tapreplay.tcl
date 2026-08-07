# =============================================================================
# dbg_tapreplay.tcl -- D3 instrument T4: THE WHOLE-STACK PROOF.
# The D2 conformance list -- dbg_conf.tcl's 38 checks -- REPLAYED THROUGH THE
# JTAG TAP.  Same file, same checks, same order, same expected answers; the
# only thing that changes is that every DM access now travels TCK/TMS/TDI/TDO
# through the DTM instead of being forced onto the raw DMI port.
#
#   ./xrun_dbg.sh xxxxxxrv32ui-p-add dbg_tapreplay.tcl
#
# BLIND-AUTHORED 2026-08-06 against d3_spec.md 6 (FROZEN).
#
# ---------------------------------------------------------------------------
# WHY THIS IS A REPLAY AND NOT A REWRITE, AND WHY THAT DISTINCTION IS THE
# WHOLE VALUE
#   d3_spec 6 asks for "dbg_conf's 38 checks driven via JTAG DR scans instead
#   of raw DMI".  A hand-written JTAG version of those checks would prove that
#   SOMEBODY'S 38 checks pass over JTAG -- and would drift from the canonical
#   list the first time either file is edited.  This file instead executes
#   tools/cosim/gate/behavioral_mp/dbg_conf.tcl ITSELF, byte for byte, with a
#   different transport underneath.  If the two ever disagree, the disagreement
#   is in the transport, which is exactly the question D3 asks.
#
#   The mechanism is one proc.  dbg_bfm.tcl funnels every DM access through
#   `dmi_xact` (:179-215); dmi_read/dmi_write are three-line wrappers (:219-230)
#   and everything above them -- dm_select, dm_haltreq, dm_poll_status,
#   dm_wait_notbusy, ac_read_reg, and all 38 of dbg_conf's checks -- is written
#   in terms of those two.  Replace `dmi_xact` and the entire stack re-points.
#
#   THE ONE UGLY PART, STATED RATHER THAN HIDDEN: dbg_conf.tcl's line 64
#   re-sources dbg_bfm.tcl, which would restore the force-based dmi_xact and
#   silently un-do the replay -- the run would pass, over the wrong transport,
#   and say nothing.  So `source` is temporarily wrapped to swallow exactly one
#   filename (dbg_bfm.tcl, already loaded here) and pass everything else
#   through.  It is restored immediately afterwards.  This is deliberate and
#   auditable; the alternative -- copying dbg_conf.tcl and editing line 64 --
#   would make the replay a fork, which is the one thing it must not be.
#
# WHAT A PASS MEANS, AND WHAT IT DOES NOT
#   PASS = the DM's register map behaves identically through the DTM as it does
#   through the raw port, for all 38 checks, including the halt of hart 1 and
#   its per-hart consequences (K16-K18).  It does NOT prove anything about TAP
#   graph conformance (T2 owns that), the sticky machine (T3), or a running
#   hart (T5) -- and it cannot, because dbg_conf never provokes any of them.
#
# THE COST IS REPORTED, NOT HIDDEN.  A DMI transaction over JTAG is two 41-bit
# DR scans plus an idle dwell -- of order 110 TCK cycles where the raw port
# needs a handful of mclk.  The TAPCOST line at the end prints the TCK cycles,
# the scan count and the number of dmiresets the transport needed.  A replay
# that passes while having issued hundreds of dmiresets is a finding about the
# crossing even though every check reads ok.
#
# AT UNIMPLEMENTED HEAD tap_present prints TAP_PORT_ABSENT / INSTRUMENT_DEAD
# and the replay is not attempted (sourcing dbg_conf.tcl over a dead transport
# would produce 38 misattributed failures).  That is the part-1 seen-to-FAIL
# leg for this instrument.
#
# NEVER pipe the runner through `head`.
# =============================================================================
source ../../disable_x_warnings.tcl
if {[file exists dbg_bfm.tcl]} { source dbg_bfm.tcl } else { source ../behavioral_mp/dbg_bfm.tcl }
if {[file exists dbg_tap.tcl]} { source dbg_tap.tcl } else { source ../behavioral_mp/dbg_tap.tcl }

set CONF "dbg_conf.tcl"
if {![file exists $CONF]} { set CONF "../behavioral_mp/dbg_conf.tcl" }

# Provenance: print what is about to be replayed.  The runner prints the md5 of
# the same path; between them the log names exactly which conformance list ran.
if {[file exists $CONF]} {
    set f [open $CONF r] ; set body [read $f] ; close $f
    set nl [llength [split $body "\n"]]
    set nchk [regexp -all {d2_chk} $body]
    puts "DMILOG REPLAY source=$CONF bytes=[file size $CONF] lines=$nl d2_chk_sites=$nchk"
} else {
    puts "DMILOG REPLAY_SOURCE_ABSENT $CONF"
}
flush stdout

set PRESENT [tap_present]

if {$PRESENT} {
    tap_init
    tap_calibrate_idle 8

    # Prove the transport works BEFORE handing it 38 checks.  Without this a
    # dead crossing produces 38 failures that all look like DM defects.
    set s [dmi_read_tap $::DM_DMSTATUS]
    set ok [expr {$::TAPROP == $::TAPRSP_SUCCESS && [dms_version $s] == 3}]
    d2_chk $ok \
        "T4-pre: the TAP transport reaches the DM before the replay starts (dmstatus [format 0x%08X $s], op $::TAPROP)"

    if {$ok} {
        tap_install_dmi_backend

        # ---- the source AND exit wrappers; see the header -----------------
        # dbg_conf.tcl's LAST LINE is `exit` (instrument defect I-2), which
        # tears the simulator down before this wrapper can print its own
        # verdict -- REPLAY END, T4-count, TAPCOST and tap_summary were all
        # unreachable.  The graded content was never in doubt (dbg_conf's own
        # `ALL CHECKS PASSED (38 checks)` banner is emitted first and IS the
        # signal), but a wrapper whose verdict never prints cannot be graded
        # by a runner, and "solve it without forking the canonical file" is
        # the constraint that matters: dbg_conf.tcl must execute byte for
        # byte or this stops being a replay.
        #
        # So `exit` is intercepted for the duration of the source, exactly as
        # `source` already is, and `return -code return` makes it do the ONE
        # thing it should do here -- end the sourced script -- instead of
        # ending the simulation.  Both are restored immediately afterwards.
        rename exit _tapreplay_real_exit
        proc exit {args} {
            puts "DMILOG REPLAY intercepted dbg_conf.tcl's terminal `exit` -- the replay wrapper's own verdict follows"
            flush stdout
            return -code return
        }
        rename source _tapreplay_real_source
        proc source {args} {
            set f [lindex $args end]
            if {[file tail $f] eq "dbg_bfm.tcl"} {
                puts "DMILOG REPLAY suppressed a re-source of dbg_bfm.tcl (the TAP backend stays installed)"
                flush stdout
                return
            }
            return [uplevel 1 [linsert $args 0 _tapreplay_real_source]]
        }

        set ::D2_CHECKS 0
        set ::D2_FAILS 0
        puts "DMILOG REPLAY BEGIN -- dbg_conf.tcl over TCK/TMS/TDI/TDO"
        flush stdout
        set rc [catch {_tapreplay_real_source $CONF} err]

        rename source {}
        rename _tapreplay_real_source source
        rename exit {}
        rename _tapreplay_real_exit exit

        if {$rc} {
            puts "DMILOG REPLAY_ERROR $err"
            d2_chk 0 "T4: the replay of dbg_conf.tcl raised a tcl error -- $err"
        }
        puts "DMILOG REPLAY END checks=$::D2_CHECKS fails=$::D2_FAILS"
        d2_chk [expr {$::D2_CHECKS >= 38}] \
            "T4-count: the replay executed $::D2_CHECKS checks, want >= 38 (a replay that ran short is not the D2 list)"
        flush stdout
    } else {
        puts "DMILOG REPLAY_SKIPPED -- the TAP transport did not reach the DM, so the"
        puts "DMILOG   38 checks would all fail for one reason and misattribute it."
        flush stdout
    }
}

tap_cost "dbg_tapreplay"
tap_summary "dbg_tapreplay" $PRESENT 39
flush stdout
