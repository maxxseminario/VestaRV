################################################################################
# Makefile for ASIC
#
# Notes:
#
# 	Makefile commands involving subdirectories use concatenated commands on a
# 	single line.  Using && requires the previous command to succeed before
# 	running the next.  Using ; executes the next regardless.  Commands that
# 	fail under normal circumstances (such as rm'ing files that don't exist) use
# 	the ;.  Commands that must execute (such as cd) to prevent rm'ing the wrong 
# 	data use the &&.
################################################################################

ASIC_NAME=myshkin
LIB_NAME=$(ASIC_NAME)
TOP_CELL=ASIC

IC_DIR=ic
GENUS_DIR=genus
INNOVUS_DIR=innovus
IP_DIR=ip
HDL_DIR=hdl

ROM_BASENAME=rom_hvt_pg
RAM16K_BASENAME=sram1p16k_hvt_pg
RAM8K_BASENAME=sram1p8k_hvt_pg
RAM1K_BASENAME=sram1p1k_hvt_pg

# Remote sync variables
REMOTE_USER=mseminario2
REMOTE_HOST=poseidon
REMOTE_DIR_RISCV=/home/mseminario2/chips/dynamiser/riscv-tests
LOCAL_DIR_RISCV=riscv-tests


.PHONY: all

.PHONY: default
default:
	@echo "Please specify a precise target from the Makefile."
	@exit 1


# Sync RISC-V tests from remote server
# .PHONY: sync-tests
# sync-tests:
# 	@echo "Syncing RISC-V test files from $(REMOTE_HOST)..."
# 	@mkdir -p $(LOCAL_DIR_RISCV)
# 	scp -r "$(REMOTE_USER)@$(REMOTE_HOST):$(REMOTE_DIR_RISCV)/*" "$(LOCAL_DIR_RISCV)/"
# 	@echo "Sync complete!"

.PHONY: sync-tests
sync-tests:
	@echo "Syncing RISC-V test files from $(REMOTE_HOST)..."
	@mkdir -p "$(LOCAL_DIR_RISCV)"
	rsync -a --delete --progress -e ssh \
		"$(REMOTE_USER)@$(REMOTE_HOST):$(REMOTE_DIR_RISCV)/" \
		"$(LOCAL_DIR_RISCV)/"
	@echo "Sync complete!"

# Analog Design Environment and Virtuoso
#
# Use -noblink flag to disable blinking layers.  This create lag and delay when 
# selecting objects in schematics and opening property windows.
.PHONY: ic
ic:
	cd $(IC_DIR) && virtuoso -noblink -log cds.log &
	
# Run cell DRC using Calibre on the MCU
.PHONY: MCU.drc
MCU.drc:
	cd $(IC_DIR) && calibre/drc MCU MCU celldrc -turbo

# Run LVS using PVS on the MCU
.PHONY: MCU.lvs
MCU.lvs:
	cd $(IC_DIR) && pvs/lvs MCU MCU -turbo

# Create CDL view from schematic using si
# Usage: make cdl <library> <cell>
.PHONY: cdl
cdl:
	@if [ -z "$(word 2,$(MAKECMDGOALS))" ] || [ -z "$(word 3,$(MAKECMDGOALS))" ]; then \
		echo "Usage: make cdl <library> <cell>"; \
		exit 1; \
	fi
	cd $(IC_DIR) && si -batch -command "simulator auCdl; netlist -lib $(word 2,$(MAKECMDGOALS)) -cell $(word 3,$(MAKECMDGOALS))"

# Run all DRCs using Calibre on the *_tapeout cell
.PHONY: tapeout.drc
tapeout.drc:
	cd $(IC_DIR) && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final wb -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final mim25 -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final ant25 -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final main -turbo


# # Run all DRCs using Calibre on the *_tapeout cell
# .PHONY: tapeout.drc
# tapeout.drc:
# 	cd $(IC_DIR) && \
# 	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final wb -turbo && \
# 	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final mim -turbo && \
# 	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final ant -turbo && \
# 	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final chipdrc -turbo

# Run LVS using PVS on the *_tapeout cell
.PHONY: tapeout.lvs
tapeout.lvs:
	cd $(IC_DIR) && pvs/lvs $(LIB_NAME)_tapeout $(TOP_CELL)_final $(LIB_NAME) $(TOP_CELL) -turbo

# Run cell DRC using Calibre
.PHONY: %.drc
%.drc: %.drc.cell
	@echo "Calibre DRC complete"

# Run cell DRC using Calibre on the desired cell
.PHONY: %.drc.cell
%.drc.cell:
	cd $(IC_DIR) && calibre/drc $(LIB_NAME) $* celldrc

# Run chip DRC using Calibre on the desired cell
.PHONY: %.drc.chip
%.drc.chip:
	cd $(IC_DIR) && calibre/drc $(LIB_NAME) $* chipdrc -turbo

# Run antenna violation DRC using Calibre on the desired cell
.PHONY: %.drc.ant
%.drc.ant:
	cd $(IC_DIR) && calibre/drc $(LIB_NAME) $* ant

# Run MIM capacitor violation DRC using Calibre on the desired cell
.PHONY: %.drc.mim
%.drc.mim:
	cd $(IC_DIR) && calibre/drc $(LIB_NAME) $* mim

# Run wire bond violation DRC using Calibre on the desired cell
.PHONY: %.drc.wb
%.drc.wb:
	cd $(IC_DIR) && calibre/drc $(LIB_NAME) $* wb

# Run all DRC checks
.PHONY: %.drc.all
%.drc.all: %.drc.mim %.drc.ant %.drc.cell
	@echo ""

# Run LVS using PVS on the desired cell
.PHONY: %.lvs
%.lvs:
	cd $(IC_DIR) && pvs/lvs $(LIB_NAME) $*

.PHONY: %.lvs.turbo
%.lvs.turbo:
	cd $(IC_DIR) && pvs/lvs $(LIB_NAME) $* -turbo

# Run QRC physical extraction using PVS on the desired cell
.PHONY: %.qrc
%.qrc:
	cd $(IC_DIR) && pvs/qrc $(LIB_NAME) $*

# Run all physical checks and extraction
.PHONY: %.phys
%.phys: %.drc %.lvs %.qrc
	@echo ""

# Stream in GDSII files from Innovus into IC.
.PHONY: %.streamin
%.streamin:
	cd $(IC_DIR) && \
	strmin/strmin.sh $* $* "../$(INNOVUS_DIR)/out/$*.gds2" overwrite
	@echo ""
	@echo "          -------------------- FRIENDLY REMINDER -------------------          "
	@echo "          Open layout and use tools -> convert labels to pins to "
	@echo "          create drawing purpose rectangle pins for Layout XL"

# Import LEF abstracts geneerated from EDI for use in IC.
.PHONY: %.lefin
%.lefin:
	cd $(IC_DIR) && \
	lefin -lef ../$(INNOVUS_DIR)/out/$*.lef -lib $(LIB_NAME) -overwrite -log log/$*.lefin.log -view abstract -pnrLibDataOnly -techRefs tsmcN65

# # Stream in GDSII files from EDI into IC.
# .PHONY: MCU.import
# #MCU.import: rom
# MCU.import: rom
# 	cd $(IC_DIR) && \
# 	rm -rf MCU/MCU/abstract; \
# 	lefin -lef ../$(INNOVUS_DIR)/out/MCU.lef -lib MCU -overwrite -log log/MCU.lefin.log -view abstract -pnrLibDataOnly -techRefs tsmcN65; \
# 	rm -rf MCU/MCU_VIA*; \
# 	rm -rf MCU/MCU/layout; \
# 	echo "" && echo "Importing schematic from Verilog file..." && echo "" &&\
# 	verilogin/verilogin MCU MCU && \
# 	echo "Streaming in MCU layout..." && \
# 	strmin/strmin.sh MCU MCU "../$(INNOVUS_DIR)/out/MCU.gds2" overwrite && \
# 	echo "Adding VDD and VSS netsets to MCU schematic and extracting netlist..." && \
# 	virtuoso -nograph -replay skill/addMCUNetSets.il && \
# 	echo "Convert MCU layout label delimeters from square brackets to angular brackets and creating VDD and VSS pins..." && \
# 	virtuoso -nograph -replay skill/fixMCULabels.il && \
# 	cd .. && make MCU.createpins && \
# 	echo "" && \
# 	echo "-------------------- FRIENDLY REMINDER -------------------" && \
# 	echo "Make sure that the VDD and VSS labels have been created in the proper positions in the MCU layout" && \
# 	echo "Make sure that all needed libraries are in the strmin/reflib.list file"

MCU.import: rom
	cd $(IC_DIR) && \
	rm -rf MCU/MCU/abstract; \
	lefin -lef ../$(INNOVUS_DIR)/out/MCU.lef -lib MCU -overwrite -log log/MCU.lefin.log -view abstract -pnrLibDataOnly -techRefs tsmcN65; \
	rm -rf MCU/MCU/layout; \
	echo "" && echo "Importing schematic from Verilog file..." && echo "" &&\
	verilogin/verilogin MCU MCU && \
	echo "Streaming in MCU layout..." && \
	strmin/strmin.sh MCU MCU "../$(INNOVUS_DIR)/out/MCU.gds2" overwrite && \
	echo "Adding VDD and VSS netsets to MCU schematic and extracting netlist..." && \
	virtuoso -nograph -replay skill/addMCUNetSets.il && \
	echo "Convert MCU layout label delimeters from square brackets to angular brackets..." && \
	virtuoso -nograph -replay skill/fixMCULabels.il 2>&1 | tee log/fixMCULabels.log && \
	cd .. && make MCU.createpins && \
	echo "" && \
	echo "-------------------- FRIENDLY REMINDER -------------------" && \
	echo "Make sure that the VDD and VSS labels have been created in the proper positions in the MCU layout" && \
	echo "Make sure that all needed libraries are in the strmin/reflib.list file" && \
	echo "Check log/fixMCULabels.log for label conversion details"

	

.PHONY: %.createpins
%.createpins:
	echo "Creating pins on layout $*..." && \
	cd $(IC_DIR) && \
	sed -e "s/LIBRARY_NAME/$*/g" < skill/createpins.il > skill/createpins_$*.il && \
	virtuoso -nograph -replay skill/createpins_$*.il

# Runs GENUS synthesis on a given HDL design.  This creates a verilog netlist for EDI.
.PHONY: %.genus
%.genus:
	cd $(GENUS_DIR) && \
	genus -overwrite -log log/$*.log -files tcl/$*.genus.tcl

# Creates a GDSII file from the verilog netlist generated by Genus.
.PHONY: %.innovus
%.innovus:
	cd $(INNOVUS_DIR) && \
	innovus -overwrite -log log/$*.log -cmd log/$*.cmd -win -init tcl/$*.innovus.tcl

# Used to run Innovus to review existing database files.
.PHONY: %.innovus.open
%.innovus.open:
	cd $(INNOVUS_DIR) && \
	innovus -overwrite -log log/innovus.log -cmd log/innovus.cmd -win -init dbs/$*.final.innovus


.PHONY: fill
fill:
	cd $(IC_DIR) && \
	calibre/dummyfill $(LIB_NAME) $(TOP_CELL)

# .PHONY: finalize
# finalize:
# 	@echo "Starting finalize process..."
# 	@echo "load \"skill/clearCellview.il\"" > $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "load \"skill/createInstInCell.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "load \"skill/copyLayoutPinsToLayout.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "load \"skill/copyLayoutLabelsToLayout.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "clearCellview(\"$(LIB_NAME)\" \"$(TOP_CELL)_final\" \"layout\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "createInstInCell(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "createInstInCell(\"$(LIB_NAME)_fill_metal\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "createInstInCell(\"$(LIB_NAME)_fill_dodpo\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "copyLayoutPinsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	echo "copyLayoutLabelsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il && \
# 	cd $(IC_DIR) && \
# 	virtuoso -nograph -replay skill/finalize_ASIC.il

.PHONY: finalize
finalize:
	@echo "Starting finalize process..."
	@echo "Writing Skill script: clearCellview.il"
	@echo "load \"skill/clearCellview.il\"" > $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill script: createInstInCell.il"
	@echo "load \"skill/createInstInCell.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill script: copyLayoutPinsToLayout.il"
	@echo "load \"skill/copyLayoutPinsToLayout.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill script: copyLayoutLabelsToLayout.il"
	@echo "load \"skill/copyLayoutLabelsToLayout.il\"" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: clearCellview"
	@echo "clearCellview(\"$(LIB_NAME)\" \"$(TOP_CELL)_final\" \"layout\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: createInstInCell (ASIC)"
	@echo "createInstInCell(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: createInstInCell (fill_metal)"
	@echo "createInstInCell(\"$(LIB_NAME)_fill_metal\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: createInstInCell (fill_dodpo)"
	@echo "createInstInCell(\"$(LIB_NAME)_fill_dodpo\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: copyLayoutPinsToLayout"
	@echo "copyLayoutPinsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Appending Skill command: copyLayoutLabelsToLayout"
	@echo "copyLayoutLabelsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)\" \"$(TOP_CELL)_final\")" >> $(IC_DIR)/skill/finalize_ASIC.il
	@echo "Changing directory to $(IC_DIR)"
	cd $(IC_DIR)
	@echo "Running Virtuoso to execute finalize_ASIC.il"
	virtuoso -nograph -replay skill/finalize_ASIC.il


	

.PHONY: tapeout
tapeout:
	@cd $(IC_DIR) && \
	mkdir -p tapeout_upload && \
	echo "Streaming out final GDS..." && \
	strmout/strmout.sh $(LIB_NAME) $(TOP_CELL)_final tapeout_upload/$(LIB_NAME).$(TOP_CELL)_final.gds -convertPin && \
	echo "Streaming final GDS back into the $(LIB_NAME)_tapeout library..." && \
	strmin \
		-library "$(LIB_NAME)_tapeout" \
		-topCell "$(TOP_CELL)_final" \
		-strmFile "tapeout_upload/$(LIB_NAME).$(TOP_CELL)_final.gds" \
		-layerMap "strmin/gds2cds.map" \
		-refLibList "calibre/reflib.calibre.dummyfill.list" \
		-techRefs "tsmcN65" \
		-writeMode overwrite \
		-scaleTextHeight 0.025 \
		-skipUndefinedLPP \
		-noWarn "75 84 107 174 316 363 81000 80043" \
		-logfile "strmin/$(LIB_NAME)_tapeout.$(TOP_CELL)_final.strmin.log" > /dev/null && \
	echo "Copying pins into tapeout layout..." && \
	echo "load \"skill/copyLayoutPinsToLayout.il\"" > skill/tapeout_ASIC.il && \
	echo "load \"skill/copyLayoutLabelsToLayout.il\"" >> skill/tapeout_ASIC.il && \
	echo "copyLayoutPinsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)_tapeout\" \"$(TOP_CELL)_final\")" >> skill/tapeout_ASIC.il && \
	echo "copyLayoutLabelsToLayout(\"$(LIB_NAME)\" \"$(TOP_CELL)\" \"$(LIB_NAME)_tapeout\" \"$(TOP_CELL)_final\")" >> skill/tapeout_ASIC.il && \
	virtuoso -nograph -replay skill/tapeout_ASIC.il && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final chipdrc -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final mim -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final ant -turbo && \
	calibre/drc $(LIB_NAME)_tapeout $(TOP_CELL)_final wb -turbo && \
	cp calibre/$(LIB_NAME)_tapeout/$(TOP_CELL)_final/results/chipdrc.rpt tapeout_upload/ && \
	cp calibre/chipdrc.rul tapeout_upload/ && \
	cp calibre/$(LIB_NAME)_tapeout/$(TOP_CELL)_final/results/mim.rpt tapeout_upload/ && \
	cp calibre/mim.rul tapeout_upload/ && \
	cp calibre/$(LIB_NAME)_tapeout/$(TOP_CELL)_final/results/ant.rpt tapeout_upload/ && \
	cp calibre/ant.rul tapeout_upload/ && \
	cp calibre/$(LIB_NAME)_tapeout/$(TOP_CELL)_final/results/wb.rpt tapeout_upload/ && \
	cp calibre/wb.rul tapeout_upload/ && \
	pvs/lvs $(LIB_NAME)_tapeout $(TOP_CELL)_final $(LIB_NAME) $(TOP_CELL) -turbo


# Maxx Seminario - Streamout of a gds file 
.PHONY: strmout
strmout:
	cd $(IC_DIR) && strmout/strmout.sh $(LIB_NAME) $(TOP_CELL)

# Added abstracts to the ip target to ensure they are imported before MCU
# Maxx Seminario 2024-09-21:
.PHONY: ip
ip: rom ram 
	@echo ""


# 	------------------------------------ ROM and RAM Targets ----------------------------------- #


.PHONY: rom
#rom: rom_artisan rom_streamin $(ROM_BASENAME).createpins
rom: rom_streamin $(ROM_BASENAME).createpins
	@ip/check_RCFs.sh

.PHONY: ram
ram: ram16k ram8k ram1k

.PHONY: ram16k
ram16k: $(RAM16K_BASENAME).spram
	@echo ""

.PHONY: ram8k
ram8k: $(RAM8K_BASENAME).spram
	@echo ""

.PHONY: ram1k
ram1k: $(RAM1K_BASENAME).spram
	@echo ""

.PHONY: %.spram
#%.spram: %.spram_artisan %.spram_streamin %.createpins
%.spram: %.spram_streamin %.createpins
	@echo ""

.PHONY: rom_artisan
rom_artisan:
	[ -d "$(IP_DIR)" ] && mkdir -p $(IP_DIR)/$(ROM_BASENAME)
	cd $(IP_DIR)/$(ROM_BASENAME) && \
	/mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/rom_via_hde_hvt_rvt_hvt/r0p0-00eac0/bin/rom_via_hde_hvt_rvt_hvt all -spec ../$(ROM_BASENAME).spec && \
	find -name '*.ps' -exec ps2pdf {} \; && \
	mkdir -p doc && \
	mv *.pdf doc && \
	find -name '*.ps' -delete && \
	cp /mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/rom_via_hde_hvt_rvt_hvt/r0p0-00eac0/doc/user_guide/* doc && \
	cp /mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/rom_via_hde_hvt_rvt_hvt/r0p0-00eac0/doc/app_notes/* doc

.PHONY: %.spram_artisan
%.spram_artisan:
	[ -d "$(IP_DIR)" ] && mkdir -p $(IP_DIR)/$*
	cd $(IP_DIR)/$* && \
	/mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/sram_sp_hdc_svt_rvt_hvt/r0p0-00eac0/bin/sram_sp_hdc_svt_rvt_hvt verilog synopsys vclef-fp gds2 tmax postscript ascii lvs -spec ../$*.spec && \
	find -name '*.ps' -exec ps2pdf {} \; && \
	mkdir -p doc && \
	mv *.pdf doc && \
	find -name '*.ps' -delete && \
	cp /mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/sram_sp_hdc_svt_rvt_hvt/r0p0-00eac0/doc/user_guide/* doc && \
	cp /mnt/aegean/backup/opt/design_kits/artisan_full/CLN65GPLUS/sram_sp_hdc_svt_rvt_hvt/r0p0-00eac0/doc/app_notes/* doc

.PHONY: rom_streamin
rom_streamin:
	cd $(IC_DIR) && \
	rm -rf $(ROM_BASENAME)/$(ROM_BASENAME)/abstract; \
	lefin -lef ../$(IP_DIR)/$(ROM_BASENAME)/$(ROM_BASENAME).lef -lib $(ROM_BASENAME) -overwrite -log log/$(ROM_BASENAME).lefin.log -view abstract -pnrLibDataOnly -techRefs tsmcN65; \
	rm -rf $(ROM_BASENAME)/*/layout; \
	strmin/strmin.sh $(ROM_BASENAME) $(ROM_BASENAME) ../$(IP_DIR)/$(ROM_BASENAME)/$(ROM_BASENAME).gds2 overwrite
	@echo ""
	@echo "          -------------------- FRIENDLY REMINDER -------------------          "
	@echo "          Open layout and use tools -> convert labels to pins to "
	@echo "          create drawing purpose rectangle pins for Layout XL"

.PHONY: %.spram_streamin
%.spram_streamin:
	cd $(IC_DIR) && \
	rm -rf $*/$*/abstract; \
	lefin -lef ../$(IP_DIR)/$*/$*.vclef -lib $* -overwrite -log log/$*.lefin.log -view abstract -pnrLibDataOnly -techRefs tsmcN65; \
	rm -rf $*/*/layout; \
	strmin/strmin.sh $* $* ../$(IP_DIR)/$*/$*.gds2 overwrite
	@echo ""
	@echo "          -------------------- FRIENDLY REMINDER -------------------          "
	@echo "          Open layout and use tools -> convert labels to pins to "
	@echo "          create drawing purpose rectangle pins for Layout XL"

.PHONY: rom.verilogin
rom.verilogin:
	cd $(IC_DIR) && \
	verilogin/verilogin $(ROM_BASENAME) $(ROM_BASENAME) $(IP_DIR)/$(ROM_BASENAME)/$(ROM_BASENAME).v

.PHONY: %.ip_verilogin
%.ip_verilogin:
	cd $(IC_DIR) && \
	verilogin/verilogin $* $* $(IP_DIR)/$*/$*.v verilogin/ihdl_parameter.norefs.template

# Delete all CDS file locks.
.PHONY: clean.ic
clean.ic:
	find $(IC_DIR) -name "*cdslck*" -delete
