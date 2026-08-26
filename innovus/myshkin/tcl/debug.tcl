# Save the GDSII geometry for Virtuoso.
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile $INPUT_DIR/innovus2gds.map
 
# Save the SDF timing for the post-layout simulation.
printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf
                     
# Save a verilog file for post-layout simulation.  To speed this up, leave it
# hierarchical and don't include any power/ground nets or physical instances.
# Also remove the antenna cells, which are not classified as physical cells by
# the command.
printStatus "Writing verilog file for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA
 
# Save a verilog file for LVS.  To this end, include power/ground nets.
printStatus "Writing verilog file for LVS"
saveNetlist \
    -excludeLeafCell $OUTPUT_DIR/$DESIGN_NAME.lvs.v \
    -flat \
    -phys

# Save an interface logic model for use during top-level timing.  This contains
# accurate timing information for the design.
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

# Save an LEF abstract for top-level routing.  This includes pins and blockages.
# If extraction is up-to-date, it also includes antenna geometries.
lefOut \
    -StripePin \
    -PGpinLayers 2 3 \
    -specifyTopLayer 3 \
    $OUTPUT_DIR/$DESIGN_NAME.lef
   
################################################################################
# End of Encounter Digital Implementation Script
################################################################################
 
saveDesign $DATABASE_DIR/$DESIGN_NAME.final.enc -def -netlist -rc -tcon 
toc
printStatus "Script complete"
#exit
