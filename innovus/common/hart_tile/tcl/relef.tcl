# One-off: re-emit the tile LEF abstract from the SAME final cut, WITH the
# per-pin antenna model.  See the note at g0_eco.tcl's lefOut for why this was
# needed: every post-harden ECO in this flow (tcm11_eco, drc_eco, and g0_eco
# before this fix) called lefOut with no verifyProcessAntenna in front of it and
# silently dropped the antenna properties the P&R flow's abstract carries.
# Nothing else is written -- same DB, same cut, one file.
set DESIGN_NAME hart_tile
source ../shared/procedures.tcl
proc logPuts {text} { global PUTS_STRING ; $PUTS_STRING $text }
restoreDesign dbs/hart_tile.signoff.innovus.dat $DESIGN_NAME
verifyProcessAntenna
lefOut -StripePin -PGpinLayers 7 8 -specifyTopLayer 8 out/$DESIGN_NAME.lef
logPuts "### RELEF ### out/$DESIGN_NAME.lef re-emitted with antenna data"
exit
