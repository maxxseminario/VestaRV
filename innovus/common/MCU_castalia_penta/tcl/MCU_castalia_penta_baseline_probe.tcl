################################################################################
# BASELINE PROBE -- READ-ONLY on the 2026-08-15 CPR7ECO cut (16 KiB TCM, the
# pre-change cut of record, after its own closure ECO).
#
# WHY: the CPR6 8 KiB cut was measured by tcl/MCU_castalia_penta_tcm8k_probe.tcl
# and came back at 1759 real DRC violations.  That number is only meaningful
# against a baseline measured THE SAME WAY, and every CPR7 report on disk was
# either overwritten or taken with a different method (default 1000-violation
# cap, or with the die-wide M7/M8 route blockages still installed).  So the same
# three-step recipe is replayed here against the surviving CPR7ECO database:
#
#   setCheckMode -tapeOut false
#   deleteAllRouteBlks     -- the flow installs die-wide M7/M8 route blockages ON
#                             PURPOSE; leaving them in floods the report with
#                             "... & Routing Blockage" OVERLAP/SHORT artifacts.
#   verifyGeometry -error 100000 -warning 100000 -antenna
#                          -- the default error limit is 1000 and it TRUNCATES
#                             SILENTLY (IMPVFG-103, buried in ~600k warnings).
#
# Also dumped first: a DB-identity block (macro inventory, inst/net counts, die
# box).  If this DB is not the 16 KiB-TCM design at a comparable flow stage, the
# DRC number is not a baseline and must not be reported as one.
#
# READ-ONLY: no saveDesign, no streamOut, no edits that outlive the session.
# (deleteAllRouteBlks mutates the in-memory DB only -- nothing is written back.)
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_baseline_probe -overwrite \
#              -files tcl/MCU_castalia_penta_baseline_probe.tcl
################################################################################
source ../shared/constants.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set RPTFILE     $REPORT_DIR/$BASENAME.verifyGeometry.baseline_cpr7.rpt

################################################################################
# WHICH DB.  NOT dbs/MCU_castalia_penta.cpr7eco.innovus.dat directly:
#
# An Innovus .innovus.dat does not embed its libraries, it SYMLINKS them, with
# ABSOLUTE paths.  cpr7eco's libs/lef/hart_tile.lef and libs/mmmc/hart_tile.etm_*
# .lib point at ~/vestarv/innovus/common/hart_tile/out/, the SHARED live tile
# output dir -- and the 8 KiB TCM re-harden overwrote all three on 2026-08-17
# 02:20.  Restoring cpr7eco as it sits therefore binds the OLD chip's placement
# and routing to the NEW tile abstract (old LEF 217064 B, new 206592 B; old tile
# outline 1050 um tall, new 880 um), and Innovus says so: IMPIMEX-7024 x3, then
# restoreDesign ERRORS OUT.  Forcing it through with restore_db_file_check 0
# would produce a number, and the number would be fiction.
#
# The original three files survive untouched in hart_tile/pre_dbgnfc_bak/out/,
# and this is PROVEN, not assumed: the cpr7eco DB's own manifest
# (MCU_castalia_penta.dbinfo) records an md5 + byte size per library file, and
# the backup copies match all three exactly --
#     hart_tile.lef        d45803cfb4421df21dfbd6babb7bff99   217064 B
#     hart_tile.etm_ss.lib 6a1a9b239b8d6b357bb93fdef4c561af  1280807 B
#     hart_tile.etm_ff.lib 04d30cfde9b4b6d9f3690f578a2a6063  1271145 B
#
# So: a byte-for-byte COPY of the cpr7eco DB was made in scratch and only those
# three symlinks re-pointed at the backup.  The DB in dbs/ is never touched, and
# because the restored collateral is md5-identical to what was saved, Innovus's
# own manifest check passes on the shadow -- which is the proof that this is the
# real CPR7ECO design and not an approximation of it.
################################################################################
set SHADOW /tmp/claude-1019/-home-mseminario2/efb17ff8-d56e-4455-a253-9474918186fc/scratchpad/MCU_castalia_penta.cpr7eco_shadow.innovus.dat

if {![file isdirectory $SHADOW]} {
    puts "### BASE ### FATAL: no shadow DB at $SHADOW"
    exit 1
}
restoreDesign $SHADOW $DESIGN_NAME
setCheckMode -tapeOut false
puts "### BASE ### restored cut = cpr7eco (shadow of dbs/MCU_castalia_penta.cpr7eco.innovus.dat)"

################################################################################
# DB IDENTITY -- is this really the 16 KiB cut, and at what stage?
################################################################################
puts "### BASE ### ---- DB IDENTITY ----"
puts "### BASE ### design      = [dbGet top.name]"
puts "### BASE ### insts       = [llength [dbGet top.insts.name -e]]"
puts "### BASE ### nets        = [llength [dbGet top.nets.name -e]]"
puts "### BASE ### die box     = [dbGet top.fPlan.box]"
puts "### BASE ### core box    = [dbGet top.fPlan.coreBox]"
puts "### BASE ### routeBlks   = [llength [dbGet top.fPlan.rBlkgs -e]]"

# The whole point of the shadow: confirm the tile abstract actually in use is
# the OLD one (1050 um tall), not the re-hardened 660x880 one.
foreach __lc [dbGet head.libCells.name hart_tile -p2 -e] {
    puts "### BASE ### hart_tile libCell size = [dbGet $__lc.size -e] (old cut expects ~660 x 1050)"
}
foreach __ti [dbGet top.insts.cell.name hart_tile -p2 -e] {
    puts "### BASE ### tile inst   = [dbGet $__ti.name] @ [dbGet $__ti.pt -e] orient [dbGet $__ti.orient -e] box [dbGet $__ti.box -e]"
}

# Macro inventory: which SRAM flavour, and how many.
array unset __macro
foreach __c [dbGet top.insts.cell.name -e] {
    if {[string match "sram1p*" $__c] || [string match "*rom*" $__c]} {
        if {[info exists __macro($__c)]} { incr __macro($__c) } else { set __macro($__c) 1 }
    }
}
set __nsram 0
foreach __k [lsort [array names __macro]] {
    puts "### BASE ### macro       = $__k x $__macro($__k)"
    if {[string match "sram1p*" $__k]} { incr __nsram $__macro($__k) }
}
puts "### BASE ### total sram1p* instances = $__nsram"
if {$__nsram == 0} {
    puts "### BASE ### WARNING: no sram1p* instances found -- macros may be inside"
    puts "### BASE ###          hierarchy this query does not reach; not fatal for DRC."
}

# Route status -- a post-route DB should report essentially no unrouted nets.
puts "### BASE ### ---- ROUTE STATUS ----"
catch {puts "### BASE ### [summaryReport -noHtml -outfile $REPORT_DIR/$BASENAME.baseline_cpr7.summary.rpt]"} __e
puts "### BASE ### summaryReport rc/msg = $__e"

################################################################################
# DRC, identical method to the CPR6 probe.
################################################################################
puts "### BASE ### ---- DRC (route blockages removed, limit 100000) ----"
deleteAllRouteBlks
verifyGeometry \
    -error 100000 \
    -warning 100000 \
    -antenna \
    -report $RPTFILE

puts "### BASE ### probe complete -- see $RPTFILE"
exit
