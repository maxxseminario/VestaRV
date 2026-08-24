import datetime, os, pathlib, re
from shutil import copyfile, rmtree

def copytree(src, dst, dirs_exist_ok=True):
	# shutil.copytree(dirs_exist_ok=...) needs Python >= 3.8; this works on 3.6
	if not os.path.isdir(dst):
		os.makedirs(dst)
	for entry in os.listdir(src):
		s = os.path.join(src, entry)
		d = os.path.join(dst, entry)
		if os.path.isdir(s):
			copytree(s, d)
		else:
			copyfile(s, d)

from Peripheral import PeripheralTemplate, Peripheral
from Register import RegisterTemplate, Register
from BitField import BitField

def fmthex(num:int, minDigits:int=4, usePrefix:bool=True):
	fmtstr = '{:0' + str(minDigits) + 'x}'
	s = fmtstr.format(num).upper()
	if usePrefix:
		s = '0x' + s
	return s

def _numberWord(n:int):
	'''Small counts spelled out, for figure banner text ("four hardened channel
	   tiles"). Same table \\NumHartsWord uses; anything larger stays a numeral.'''
	return {1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six',
		7: 'seven', 8: 'eight'}.get(n, str(n))

def fmtbin(num:int, minDigits:int=8, usePrefix:bool=True):
	fmtstr = '{:0' + str(minDigits) + 'b}'
	if usePrefix:
		return '0b' + fmtstr.format(num)
	return fmtstr.format(num)

def fmttex(s:str):
	s = s.replace('_', '\\_').replace('|', '{\\textbar}').replace('&', '{\\&}').replace('~', '{\\textasciitilde}').replace('%', '{\\%}').replace('^', '{\\textasciicircum}')
	return s

class LatexUserGuide():
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())
	
	Gen = None	# ChipGenerator

	SaveDirectory = None	# {chip root directory}/latex/TRM
	IncludeDirectory = None	# {SaveDirectory}/include
	LatexSourceDirectory = None	# {chip root directory}/latex  -- the ONLY place TRM inputs are read from

	# CP6 ANALOG-CHAPTER LINEAGE (see CopyAnalogChapter).
	#   <lower-cased chipName>  ->  <lower-cased chipName whose analog/ it shares>
	# One entry = one deliberate statement that two chip configurations are the
	# SAME SILICON from the analog front-end's point of view. Castalia-Penta is a
	# digital re-configuration of Castalia (a fifth soft hart in the centre band);
	# the AFE/EIS front-end, the bias generator and every Monte-Carlo figure in
	# implementations/asic/castalia/analog/ describe it unchanged.
	# NEVER make this a prefix/substring rule: the whole point is that inheriting
	# measured analog data is an explicit, per-chip decision.
	AnalogChapterLineage = {
		'castaliapenta': 'castalia',
	}

	def __init__(self, gen, outDirectoryPath):
		self.Gen = gen
		if not os.path.isdir(outDirectoryPath):
			raise Exception('outDirectoryPath does not exist: ' + str(outDirectoryPath))
		self.SaveDirectory = outDirectoryPath
		self.IncludeDirectory = self.SaveDirectory + '/include'

		# CP7 PER-CHIP LATEX SOURCES (2026-08-20).
		#
		# Every TRM input -- figures, the master template, packages-commands and the
		# peripheral introductions -- USED TO be read as
		# `ThisFileDirectory + '/../latex/...'`, i.e. relative to the directory this
		# MODULE lives in rather than to the CHIP being built. That is only correct
		# while exactly one chip uses this module: the moment a second chip's
		# generator imports it, that chip's manual silently sources its figures out
		# of the first chip's store (this is how myshkin's TRM came to reference
		# `dualslopeupd.png`, a file that exists only under platform/common/).
		#
		# The path is now derived from the chip generator's own root, so a chip's
		# manual is built ONLY from that chip's directories. Shared content is
		# shared by having a COPY of the file in each chip's tree -- deliberately,
		# not by a cross-tree path -- so pruning one chip's figures can never break
		# the other's build.
		#
		# `ChipRootDirectory` is already absolute and slash-normalised by
		# ChipGenerator.__init__. For Castalia (platform/common) this resolves to
		# exactly the old path, so the existing build is unchanged.
		self.LatexSourceDirectory = os.path.abspath(self.Gen.ChipRootDirectory + '/latex').replace('\\', '/')
		if not os.path.isdir(self.LatexSourceDirectory):
			raise Exception('The chip\'s LaTeX source directory does not exist: '
				+ self.LatexSourceDirectory
				+ ' (expected <chip root>/latex for chip ' + str(self.Gen.AsicName) + ')')
		return
	
	def Generate(self):
		self.CopyTemplateTexFiles()
		self.CopyAnalogChapter()
		self.GenerateDefinesFile()
		self.GenerateSystemConfigurationListFile()
		self.GenerateFeaturesList()
		self.GenerateExtraIntroChapters()
		self.GenerateAfeSystemDiagram()
		self.GenerateCqAnalogChapter()
		self.GenerateAddressSpaceDiagram()
		self.GenerateChipConfigurationSection()
		# Still emitted, no longer printed: the TRM retired this figure on
		# 2026-08-16 (three drawings of one chip in four pages) and nothing
		# \input{}s include/SystemBlockDiagram.tex now. Kept generating so the
		# view can be taken back unchanged, and so the AFE/chip-system emitters
		# that copy its geometry keep a live reference to copy from.
		self.GenerateSystemBlockDiagram()	# W5
		# The whole-chip companion to the block diagram above: the bus, every
		# peripheral this configuration instantiates, and what leaves the die.
		# Ungated (both hart shapes live inside the emitter), so the master
		# template can \ref it from ungated prose in either polarity.
		self.GenerateChipSystemDiagram()
		# D-series figure J: the FLAT companion to the figure above, same
		# derived content on one bus bar in a landscape frame. Ungated like it
		# (both hart shapes and the degraded no-analog shape live inside the
		# emitter), so the master template can \ref it from ungated prose.
		self.GenerateChipSystemFlatDiagram()
		# The SYSTEM chapter's clock system, replacing a static vector
		# figure whose mux codes contradicted its own register tables.
		# Emitted unconditionally; the chapter \input{}s it ungated.
		self.GenerateClockSystemDiagram()  # W1
		# CPR3/R3 mechanism figure. Emitted unconditionally (the D-series
		# precedent): the multi-core chapter \input{}s it inside its own
		# \iforchpresent, so the gating rule lives in exactly one place.
		self.GenerateTcmApertureDiagram()
		self.GenerateBootFlowDiagram()
		self.GenerateSyncPrimitiveDecisionTree()
		self.GenerateTimerRolloverDiagram()
		self.GenerateTimerOutputCompareDiagram()
		self.GenerateArbiterHandshakeDiagram()
		# CPR3/R3 companion waveform: the same pins, stalled. Emitted
		# unconditionally like the aperture mechanism figure above; the
		# chapter's \input sits inside \iforchpresent.
		self.GenerateArbiterStallDiagram()
		# The NPU chapter's mechanism figure. Emitted unconditionally like the
		# two above; the chapter itself only exists when the peripheral does, so
		# a configuration with peripherals.npu = false never reaches the \input
		# and this writes a stub. # W4
		self.GenerateNpuDatapathDiagram()
		self.GenerateSpiFlashDiagram()  # W2
		self.GenerateSpiTimingDiagram()
		self.GenerateSpiByteOrderingDiagram()
		self.GenerateSpiBitOrderingDiagram()
		self.GenerateUartFrameDiagram()
		self.GenerateI2cTransactionDiagram()
		self.GenerateIrqClaimCompleteDiagram()
		# The interrupt-fabric overview: the source population, the router as
		# the spine, and the CLINT pair going round it. Emitted and \input
		# UNGATED (the interrupts section and the IRQROUTER chapter are both
		# ungated), so every \ref to it resolves in both polarities.
		self.GenerateIrqFabricDiagram()	# W3
		self.GenerateMutexClaimDiagram()
		# D-series: the PWRCTRL chapter's mechanism figure. Emitted
		# unconditionally — the switched-tile story is true on every multi-core
		# configuration; only hart 0's wording follows the orchestrator knob,
		# inside the emitter.
		self.GeneratePowerDomainDiagram()
		self.GenerateTimerCaptureDiagram()
		# D-series debug figures. Emitted unconditionally; the chapter decides
		# which of them render, by placing the gated \input inside its own
		# \ifdebugenable (an unused include costs nothing and keeps the gating
		# rule in exactly one place).
		self.GenerateDebugStackDiagram()
		self.GenerateTapStateDiagram()
		self.GenerateJtagScanDiagram()
		self.GenerateDmiCrossingDiagram()
		self.GenerateDebugSwimlaneDiagram()
		self.GenerateDmiFieldDiagram()
		self.GenerateDebugPageDiagram()
		self.GenerateDebugModeStateDiagram()
		self.GeneratePackagePinoutDiagram()
		self.GenerateInterruptsTable()
		self.GeneratePackagePinsConfigurationTable()
		self.GenerateGpioPinsConfigurationTable()
		self.GenerateGpioAltFunctionMatrixTable()
		self.GenerateForthCommandsItemized()
		self.GeneratePeripheralSections()
		self.GeneratePeripheralAndRegistersList()
		return
	
	def CopyTemplateTexFiles(self):
		# Get all the peripheral templates
		pts = []
		for p in self.Gen.Peripherals:
			if p.Template not in pts:
				pts.append(p.Template)
		
		# Copy all of the intro latex files for each peripheral that has one
		if not os.path.isdir(self.SaveDirectory + '/include'):
			os.makedirs(self.SaveDirectory + '/include')
		for pt in pts:
			if pt.LatexIntroFileName is None:
				continue
			path = self.LatexSourceDirectory + '/PeripheralIntroductions/' + pt.LatexIntroFileName
			if not os.path.isfile(path):
				raise Exception('The latex introduction for peripheral ' + pt.NameTemplate + ' does not exist at path ' + path)
			copyfile(path, self.SaveDirectory + '/include/' + pt.LatexIntroFileName)

		# Copy any extra intro tex files that the master template inputs directly (e.g. the multi-core chapter)
		if self.Gen.ExtraLatexIntroFiles is not None:
			for fileName in self.Gen.ExtraLatexIntroFiles:
				path = self.LatexSourceDirectory + '/PeripheralIntroductions/' + fileName
				if not os.path.isfile(path):
					raise Exception('The extra latex introduction file does not exist at path ' + path)
				copyfile(path, self.SaveDirectory + '/include/' + fileName)

		# Copy the master MCU User Guide template tex file
		path = self.LatexSourceDirectory + '/' + self.Gen.McuUserGuideLatexTemplateFileName
		copyfile(path, self.SaveDirectory + '/TRM.tex')

		# Copy the packages and commands tex file
		path = self.LatexSourceDirectory + '/packages-commands.template.tex'
		copyfile(path, self.SaveDirectory + '/packages-commands.tex')

		## Copy the tikzit.sty file
		#path = self.ThisFileDirectory + '/../latex/tikzit.template.sty'
		#copyfile(path, self.SaveDirectory + '/tikzit.sty')

		## Copy the tikzit style file
		#path = self.ThisFileDirectory + '/../latex/murray.template.tikzstyles'
		#copyfile(path, self.SaveDirectory + '/murray.tikzstyles')

		# Copy the figures directory -- from THIS CHIP's store, never another's.
		#
		# CP7. There is no fallback and there is no shared store: a chip that has
		# no latex/figures/ of its own is a build error, not an invitation to
		# borrow the neighbouring chip's images. A figure both chips genuinely
		# need exists as two files, one per tree. The error names the directory it
		# wanted so the fix is `mkdir` + copy the figures in, which is the intended
		# answer -- not re-pointing the generator across trees.
		path = self.LatexSourceDirectory + '/figures'
		if not os.path.isdir(path):
			raise Exception('No figures directory for chip ' + str(self.Gen.AsicName)
				+ ': expected ' + path + '. Each chip owns its own figures; create the'
				+ ' directory and copy in the figures its TRM references (shared figures'
				+ ' are duplicated per chip on purpose, never sourced across chip trees).')
		dst = self.SaveDirectory + '/figures'
		if not os.path.isdir(dst):
			os.makedirs(dst)
		copytree(path, dst, dirs_exist_ok=True)

		return

	def CopyAnalogChapter(self):
		# Per-implementation analog chapter. Every chip built from this platform
		# shares the digital chapters, but the analog content is per-silicon, so it
		# lives with the implementation rather than in the shared platform sources:
		#
		#     implementations/asic/<chip>/analog/AnalogChapter.tex   (hand-written)
		#     implementations/asic/<chip>/analog/{fig,tab}_*.tex, data/  (generated
		#                                          from Maestro by tools/maestro2tex)
		#
		# The whole directory is copied to latex/TRM/include/analog/ so that, like
		# every other TRM input, it is reachable as include/... from the build
		# directory. The master template guards the \input with \IfFileExists, so a
		# chip with no analog/ directory produces a TRM byte-identical to a build
		# without this feature -- the same "inert unless declared" discipline as the
		# \ifcqanalog chapter.
		#
		# The directory is keyed on the lower-cased chip name, which is the existing
		# implementations/asic/ naming convention (Castalia -> castalia).
		#
		# CP6 LINEAGE FALLBACK. That key is the chip NAME, and a chip config that
		# only changes the DIGITAL configuration is still the same silicon as far
		# as the analog front-end is concerned. Castalia-Penta is exactly that
		# case: `chipName: CastaliaPenta` looked for implementations/asic/
		# castaliapenta/analog/, found nothing, and dropped the analog chapter
		# SILENTLY -- 218 pages against Castalia's 243, with the only trace a
		# "no analog chapter" line in a build log nobody reads as a defect.
		#
		# The fallback is an EXPLICIT TABLE and deliberately not a prefix or
		# fuzzy match: inheriting somebody else's measured analog data is a claim
		# about silicon, so it is made once, by name, in this table -- a future
		# chip whose name merely begins with an existing one must NOT quietly
		# acquire that chip's bias-generator characterization. And it is never
		# silent: the inheritance prints its own build-time note below, naming
		# both the chip that asked and the lineage parent that answered.
		key = self.Gen.AsicName.lower()
		asicRoot = os.path.abspath(self.ThisFileDirectory + '/../../../implementations/asic')
		src = os.path.join(asicRoot, key, 'analog')
		inheritedFrom = None
		if not os.path.isdir(src) and key in self.AnalogChapterLineage:
			parent = self.AnalogChapterLineage[key]
			cand = os.path.join(asicRoot, parent, 'analog')
			if os.path.isdir(cand):
				inheritedFrom = parent
				src = cand
			else:
				print('[LatexUserGuide] NOTE: ' + self.Gen.AsicName + ' inherits its analog'
				      + ' chapter from lineage parent "' + parent + '", but ' + cand
				      + ' does not exist either - TRM built without one')
		dst = self.IncludeDirectory + '/analog'

		# Purge first, ALWAYS. latex/TRM/ is reused across chips (`make chip
		# CHIP_NAME=...`), so leaving a previous chip's analog directory in place
		# would silently splice its chapter into this chip's TRM -- exactly what
		# happened the first time this ran: Castalia's bias-generator chapter
		# appeared in Argus's manual. Removing it unconditionally is what makes the
		# "no analog/ directory => no analog chapter" guarantee actually hold.
		if os.path.isdir(dst):
			rmtree(dst)

		if not os.path.isdir(src):
			print('[LatexUserGuide] no analog chapter for ' + self.Gen.AsicName
			      + ' (looked in ' + src + ') - TRM built without one')
			return
		if not os.path.isdir(dst):
			os.makedirs(dst)
		copytree(src, dst, dirs_exist_ok=True)
		if inheritedFrom is None:
			print('[LatexUserGuide] analog chapter copied from ' + src)
		else:
			# CP6: the fallback announces itself. A build that silently borrows
			# another chip's analog measurements is the failure this exists to
			# prevent, so the note names both ends of the inheritance.
			print('[LatexUserGuide] analog chapter INHERITED: ' + self.Gen.AsicName
			      + ' has no implementations/asic/' + self.Gen.AsicName.lower()
			      + '/analog, so the chapter is taken from lineage parent "'
			      + inheritedFrom + '" (' + src + ') - explicit CP6 lineage mapping')

		return

	def GenerateDefinesFile(self):
		# Generate revision date string.
		#
		# K5 (F-K5-2).  This was `datetime.datetime.now()`, and that ONE call
		# made `make check-publish` structurally unpassable on any day after
		# the day the TRM was last published -- with ZERO content change.  The
		# Makefile has `verify: generate`, so every `make verify` silently
		# restamped the published-vs-rebuilt comparison, and the pre-commit
		# hook that runs check-publish therefore failed for a reason that had
		# nothing to do with what it guards.  It trained three waves to bypass
		# it with `--no-verify`.  A hook whose signal is not about the thing it
		# is guarding is worse than no hook: it spends the credibility that
		# makes the NEXT real failure get read.
		#
		# Measured at K5 queue item 6: the "stale" published TRM and a fresh
		# rebuild had 12,012 identical text lines and 609 of 613 byte-identical
		# content streams; the entire difference was `Revised July 31st` vs
		# `Revised August 3rd`.
		#
		# THE FIX IS CONTENT-DERIVED, and deliberately NOT the Makefile's
		# SOURCE_DATE_EPOCH.  That variable is documented in the Makefile as
		# "an ARBITRARY FIXED instant (2025-01-01 UTC), not the build time",
		# chosen so identical TRM.tex gives a byte-identical TRM.pdf.  Reusing
		# it for the VISIBLE revision date would make every TRM say "Revised
		# January 1st, 2025" forever -- a reproducible gate bought with a false
		# statement on the title page, which is method rule 12 with a wider
		# audience than usual.
		#
		# `VESTA_TRM_DATE_EPOCH` is set by the Makefile from the newest COMMIT
		# DATE of the TRM's own input set, so the date means what it says --
		# when the TRM's inputs last changed -- AND is identical for everyone
		# who checks out the same tree on any day.  That is what makes
		# check-publish a gate about content again.
		#
		# Precedence, and each fallback is a real case: the content-derived
		# epoch; then SOURCE_DATE_EPOCH, for a caller that has pinned time
		# deliberately; then `now()`, so a bare `python3 generate.py` outside
		# the Makefile still produces a dated document rather than a
		# mysterious fixed one.
		_ep = os.environ.get('VESTA_TRM_DATE_EPOCH') \
			or os.environ.get('SOURCE_DATE_EPOCH')
		if _ep and _ep.strip().isdigit():
			dt = datetime.datetime.utcfromtimestamp(int(_ep.strip()))
		else:
			dt = datetime.datetime.now()
		dts1 = dt.strftime('%B %d')
		if dts1.endswith('11') or dts1.endswith('12') or dts1.endswith('13'):
			dts1 += '$^\\textrm{th'
		elif dts1.endswith('1'):
			dts1 += '$^\\textrm{st'
		elif dts1.endswith('2'):
			dts1 += '$^\\textrm{nd'
		elif dts1.endswith('3'):
			dts1 += '$^\\textrm{rd'
		else:
			dts1 += '$^\\textrm{th'
		dts1 += '}$'
		revisionDateFullStr = dts1 + ', ' + dt.strftime('%Y')
		revisionDateFullStr = revisionDateFullStr.replace(' 0', ' ')
		
		# WARNING: Underscores are NOT allowed in the keys of this dict!!! This is because you cannot have underscores in a Latex command name
		defines = {
			'AsicName': self.Gen.AsicName,
			'AsicNameForUserGuide': self.Gen.AsicNameForUserGuide,
			'RevisionDateFull': revisionDateFullStr,
			'ProgaddrIrq': fmthex(self.Gen.PROGADDR_IRQ),
			'VectorsStartAddress': fmthex(self.Gen.VectorsStartAddress),
			'RamProgramStartAddress': fmthex(self.Gen.RamProgramStartAddress),
			'RamStartAddress': fmthex(self.Gen.RamStartAddress),
			'RamEndAddress': fmthex(self.Gen.RamEndAddress),
			'RamEndWordAddress': fmthex(self.Gen.RamEndAddress - 3),
			'RamNumPages': str(self.Gen.RamSize // 256),
			'PackageSize': str(self.Gen.Package.Dimensions[0]),
			'PackageTypeName': self.Gen.Package.PackageType,
			'PackagePinCount': str(self.Gen.Package.PinCount),
			'PackagePinPitch': str(self.Gen.Package.PinPitch),
			'PackagePinWidth': str(self.Gen.Package.PinWidth),
			'PackagePinDepth': str(self.Gen.Package.PinDepth),
			'PackageUnits': self.Gen.Package.Units,
			'SpiFlashProgramAddress': fmthex(self.Gen.SpiFlashProgramAddress),
		}

		# Configuration-driven defines: hart count, vector counts, shared-window bounds.
		# The master template selected by the chip config references only the defines its
		# configuration provides (e.g. a single-core template never uses \SharedWindow*).
		hartWords = {1: 'one', 2: 'two', 3: 'three', 4: 'four', 5: 'five', 6: 'six', 7: 'seven', 8: 'eight'}
		# Reset/boot address: every hart resets into the shared boot ROM, so the
		# address-space prose quotes this rather than a literal 0x00000.
		defines['RomStartAddress'] = fmthex(self.Gen.RomStartAddress, minDigits=5)
		defines['NumHarts'] = str(self.Gen.NumHarts)
		defines['NumHartsWord'] = hartWords.get(self.Gen.NumHarts, str(self.Gen.NumHarts))
		defines['MaxHartIndex'] = str(self.Gen.NumHarts - 1)
		# D-series: the PWRCR gate mask, so the PWRCTRL chapter can state the
		# blanket-gate constant instead of hardcoding one hart count's value
		# (0x1E at N=5, 0x3FFFE on Argus' eighteen). E17-style: the mask is READ
		# OFF the register model (generate.py's PWRGATE bit field, which is what
		# MemoryMap.h's PWRGATE_MASK and the register browser also come from) and
		# CROSS-CHECKED against the hart count, so a change to either side that
		# misses the other fails `make generate` instead of shipping a manual
		# whose mask and whose hart range disagree. Defined unconditionally (the
		# \PmpEntries precedent) so the macro can never dangle.
		_gateMask = None
		for _p in self.Gen.Peripherals:
			if _p.Name != 'PWRCTRL':
				continue
			for _r in _p.Registers:
				if _r.Name != 'PWRCR':
					continue
				for _bf in _r.BitFields:
					if _bf.Name == 'PWRGATE':
						_gateMask = _bf.BitMask
		if _gateMask is not None:
			_expect = ((1 << self.Gen.NumHarts) - 1) & ~1
			if _gateMask != _expect:
				raise Exception('PWRCR gate mask: the register model says 0x%X but %d harts '
					'imply 0x%X (bits 1..%d) — the PWRCTRL chapter would document a mask that '
					'does not match its own hart range.'
					% (_gateMask, self.Gen.NumHarts, _expect, self.Gen.NumHarts - 1))
		defines['PwrGateMask'] = fmthex(_gateMask if _gateMask is not None else 0, minDigits=2)
		defines['VectorsCount'] = str(self.Gen.VectorsCount)
		# D-series sweep (s4): \SharedWindowStartAddress / \SharedWindowEndAddress
		# are RETIRED. Both were min/max over SharedWindowSections -- the rows the
		# address-space FIGURE happens to draw -- and neither was the RTL shared
		# window they are named after. The window mp_arbiter decodes is
		# 0x0 (the boot ROM, where every hart resets) up to the strict complement
		# of sh_sel at (1 << (SH_AW+2)) - 1; the macros said 0x5000 (the CLINT, the
		# lowest row that happened to be listed) and 0x33FFF (the top TCM aperture).
		# A reader who believed either would place the shared window wrongly at both
		# ends. They also had ZERO consumers: the whole latex tree, both templates
		# and every intro chapter were grepped, and the only hits were this emitter
		# and a stale README sentence (fixed with them). Nothing derived here goes
		# unused and untrue: prose that needs those bounds should quote
		# \RomStartAddress and \FlashBaseAddress, which ARE the window's real edges.
		clint = None
		for p in self.Gen.Peripherals:
			if p.Name == 'CLINT':
				clint = p
		if clint is not None and clint.InterruptPriority is not None:
			# CLINT owns the last two vectors: msip at its interruptPriority, mtip right after
			defines['ClintMsipVector'] = str(clint.InterruptPriority)
			defines['ClintMtipVector'] = str(clint.InterruptPriority + 1)
			# NOTE (2026-08-17): this is the CLINT's OWN vector number, not a
			# count of peripheral vectors — the source list grew past it when
			# digperiphs added vectors 86..120, so \VectorsCount is no longer
			# \PeriphVectorsCount + 2. No prose quotes it any more (Section
			# \ref{s:interrupts} was rewritten to \RoutedVectorsCount below);
			# kept emitted only so an old chapter cannot dangle on it.
			defines['PeriphVectorsCount'] = str(clint.InterruptPriority)
			# W-merge (2026-08-17): the routed/hardwired split. Every vector but
			# the CLINT pair is delivered through the router; those two reach the
			# harts on dedicated per-hart wires and are never enabled, pended,
			# claimed or completed. GenerateIrqFabricDiagram derives and PRINTS
			# the same split, so the sentence in Section \ref{s:interrupts} and
			# the figure under it cannot disagree.
			defines['RoutedVectorsCount'] = str(self.Gen.VectorsCount - 2)
			# CLINT register-layout addresses (N-parameterized, matches clint.vhd):
			# MSIPh word-mapped from the base; the MTIME pair and per-hart MTIMECMP
			# pairs sit at slots that grow with the hart count (the roundup16
			# formula). Derived from the peripheral's own BaseAddress + register
			# offsets so the CLINT intro prose is configuration-driven.
			_clintMtimeOff = None
			_clintCmpOff = None
			for _r in clint.Registers:
				if _r.Name == 'MTIMEL':
					_clintMtimeOff = _r.Offset
				if _r.Name == 'MTIMECMP0L':
					_clintCmpOff = _r.Offset
			if _clintMtimeOff is not None and _clintCmpOff is not None:
				defines['ClintBaseAddress'] = fmthex(clint.BaseAddress)
				defines['ClintMtimeAddress'] = fmthex(clint.BaseAddress + _clintMtimeOff)
				defines['ClintMtimecmpBaseAddress'] = fmthex(clint.BaseAddress + _clintCmpOff)
				# alias span = 4 << clog2(number of decoded words)
				_clintSlotCount = _clintCmpOff // 4 + 2 * self.Gen.NumHarts
				_clintClog = (_clintSlotCount - 1).bit_length() if _clintSlotCount > 1 else 0
				defines['ClintAliasBytes'] = str(4 << _clintClog)

		# W-merge (2026-08-17): the interrupt-fabric numbers Section
		# \ref{s:interrupts} and the IRQROUTER chapter used to state as
		# LITERALS, and which had all silently moved:
		#   * meip's IVT slot is FROZEN at ChipGenerator.MeipVector (85) while
		#     the SOURCE count grows above it (digperiphs #2), so "vector 85"
		#     in prose is a coincidence of this build, not a rule.
		#   * the top vector is VectorsCount-1 (120 here, 84 when the chapters
		#     were written), and
		#   * generate.py packs the per-hart enable row into as many 32-bit
		#     words as the source count needs -- three below 96 sources, FOUR
		#     above -- so the chapter's "three registers ... vectors 0--84" and
		#     its "bit b of HxENU is vector 64+b for b = 0..20" were both a
		#     source-list growth out of date. The word count is READ BACK off
		#     the emitted register model (the H0EN* words) rather than
		#     recomputed, so the manual states the row this build actually has.
		defines['MeipVector'] = str(self.Gen.MeipVector if self.Gen.MeipVector is not None
			else self.Gen.VectorsCount)
		defines['TopVector'] = str(self.Gen.VectorsCount - 1)
		# HxENU covers vectors min(VectorsCount,96)-1 : 64, i.e. bits <IrqEnuMsb>:0.
		defines['IrqEnuTopVector'] = str(min(self.Gen.VectorsCount, 96) - 1)
		defines['IrqEnuMsb'] = str(31 if self.Gen.VectorsCount >= 96 else self.Gen.VectorsCount - 65)
		for _p in self.Gen.Peripherals:
			if _p.Name != 'IRQROUTER':
				continue
			_enWords = [_r for _r in _p.Registers if re.match('^H0EN', _r.Name)]
			if _enWords:
				defines['IrqEnableWords'] = str(len(_enWords))
				defines['IrqEnableWordsWord'] = _numberWord(len(_enWords))

		# A2 (Argus): shared-memory geometry + mutex-count defines so the
		# hand-written multi-core chapter is configuration-driven prose.
		npuPresent = True
		geo = getattr(self.Gen, 'McuMpGeometry', None)
		if geo:
			banks = geo['sharedRamBanks']
			npuPresent = geo['npu']
			defines['SharedRamSizeKiB'] = str(banks * 16)
			defines['SharedRamBanks'] = str(banks)
			# Start address too: the generated arbiter handshake diagram labels
			# its example transaction with it, so the figure follows the config.
			defines['SharedRamStartAddress'] = fmthex(0x10000)
			defines['SharedRamEndAddress'] = fmthex(0x10000 + banks * 0x4000 - 1)
			defines['FlashBaseAddress'] = fmthex(1 << (geo['shAw'] + 2))
		# Boot-ROM contracts + TCM geometry (used by the multi-core chapter and
		# the generated boot flow diagram). The loader mailbox base is the
		# N-agnostic Argus A3 value used by software/bootrom_mp on ALL builds.
		defines['BootMailboxBase'] = fmthex(0x10500)
		defines['TcmSizeKiB'] = str(self.Gen.RamMemorySlotSize // 1024)
		defines['TcmWords'] = str(self.Gen.RamMemorySlotSize // 4)
		# Watchdog passwords (single source: generate.py's wdt*Password, which
		# equal hdl/common/constants.vhd WDT_UNLCK_PASSWD / WDT_CLR_PASSWD).
		defines['WdtUnlockPassword'] = fmthex(getattr(self.Gen, 'WdtUnlockPassword', 0x5F3759DF), minDigits=8)
		defines['WdtClearPassword'] = fmthex(getattr(self.Gen, 'WdtClearPassword', 0xA0C8A620), minDigits=8)
		mutexP = None
		for p in self.Gen.Peripherals:
			if p.Name == 'MUTEX':
				mutexP = p
		if mutexP is not None:
			nMtx = len(mutexP.Registers)
			mtxWords = {16: 'sixteen', 32: 'thirty-two', 64: 'sixty-four'}
			defines['NumMutexes'] = str(nMtx)
			defines['NumMutexesWord'] = mtxWords.get(nMtx, str(nMtx))
			defines['MutexBaseAddress'] = fmthex(mutexP.BaseAddress)

		# P-series privileged architecture: the PMP entry count the
		# Privileged Architecture chapter quotes (only meaningful when
		# priv.pmp is set, but always defined so the macro never dangles).
		defines['PmpEntries'] = str(getattr(self.Gen, 'PMP_ENTRIES', 16))

		s = ''
		for item in defines:
			s += '\\newcommand{\\' + item + '}{' + defines[item] + '}\n'
		# NPU presence conditional (\ifnpupresent ... \else ... \fi) for the
		# multi-core chapter's NPU-dependent prose
		s += '\\newif\\ifnpupresent\n'
		s += ('\\npupresenttrue' if npuPresent else '\\npupresentfalse') + '\n'
		# G4: package "Preliminary" banner conditional — config-driven
		# (package.preliminary; True while the package is inherited from Myshkin)
		s += '\\newif\\ifpackagepreliminary\n'
		s += ('\\packagepreliminarytrue' if getattr(self.Gen, 'PackagePreliminary', True)
			else '\\packagepreliminaryfalse') + '\n'
		# CQ: analog front-end (AFE/EIS) chapter conditional. True only when the
		# config declares documentation sub-slot blocks (the CQ package model);
		# false (default) leaves the \input skipped so the default TRM is byte-
		# identical and the generated CqAnalog.tex chapter never renders.
		s += '\\newif\\ifcqanalog\n'
		s += ('\\cqanalogtrue' if getattr(self.Gen, 'DocSubSlotBlocks', None)
			else '\\cqanalogfalse') + '\n'
		# P-series privileged architecture (priv.trapCsr / priv.umode /
		# priv.pmp). The Privileged Architecture chapter itself always renders
		# — the legacy vectored trap mechanism it opens with is the shipping
		# default of every build — and these three conditionals wrap its
		# standard-mode, U-mode and PMP sections, so a build documents only the
		# privileged hardware it actually contains. All three are false at the
		# defaults, which is what keeps the default TRM honest.
		for _flag, _attr in (('privtrapcsr', 'ENABLE_TRAPCSR'),
				('privumode', 'ENABLE_UMODE'),
				('privpmp', 'ENABLE_PMP')):
			s += '\\newif\\if' + _flag + '\n'
			s += ('\\' + _flag + ('true' if getattr(self.Gen, _attr, False) else 'false')) + '\n'
		# D-series debug (debug.enable). The Debug Support chapter itself
		# ALWAYS renders -- what JTAG is and what the RISC-V debug stack does
		# are architecture-level material a reader of any build needs, and a
		# build WITHOUT the debug system still has something true to say (the
		# four 0x7Bx CSRs and DRET are illegal, and there is no debug port).
		# That is the same honesty argument as the Privileged Architecture
		# chapter's legacy-trap opening. This conditional wraps the
		# implementation sections, so a build documents only the debug
		# hardware it actually contains. False at the defaults.
		s += '\\newif\\ifdebugenable\n'
		s += ('\\debugenabletrue' if getattr(self.Gen, 'ENABLE_DEBUG', False)
			else '\\debugenablefalse') + '\n'
		# CPR3/R1 (Castalia-Penta rework): the soft ORCHESTRATOR hart. False at
		# the defaults, so every orchestrator sentence in the multi-core chapter
		# folds away and the default TRM is byte-identical — the same
		# "inert unless declared" discipline as \ifcqanalog above.
		# \OrchHartIndex is defined UNCONDITIONALLY (the \PmpEntries precedent)
		# so the macro can never dangle inside a folded branch, and it is now the
		# CONSTANT 0: the orchestrator IS hart 0 (R2). That also retires a latent
		# defect in the CP6 form — `\orchpresenttrue if _mgmtHart` was a
		# TRUTHINESS test on an index, so index 0 (exactly the shape CPR asks
		# for) would have read as "no orchestrator". A boolean knob cannot have
		# that bug.
		_orch = bool(getattr(self.Gen, 'Orchestrator', False))
		s += '\\newcommand{\\OrchHartIndex}{0}\n'
		s += '\\newif\\iforchpresent\n'
		s += ('\\orchpresenttrue' if _orch else '\\orchpresentfalse') + '\n'
		# Base of the read-only TCM aperture band (TCMWIN[0]), taken from the
		# resolved config's derived tcmWindowAddresses so the address-space
		# prose quotes the same arithmetic the figure draws. Defined
		# UNCONDITIONALLY (the \OrchHartIndex precedent) so it cannot dangle
		# inside a folded \iforchpresent branch; without an orchestrator there
		# are no apertures and nothing references it.
		_tcmWindows = ((getattr(self.Gen, 'ResolvedConfig', None) or {}).get('derived') or {}).get('tcmWindowAddresses') or []
		s += '\\newcommand{\\FirstTcmWindowAddress}{' + (str(_tcmWindows[0]) if _tcmWindows else '--') + '}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		definesPath = self.IncludeDirectory + '/defines.tex'
		with open(definesPath, 'w') as f:
			f.write(s)
		
		return
	
	def GenerateSystemConfigurationListFile(self):
		# Compile the system configuration list
		extensions = 'I'
		if self.Gen.ENABLE_MUL or self.Gen.ENABLE_FAST_MUL:
			extensions += '[M]'
		if self.Gen.ENABLE_ATOMICS:
			extensions += '[A]'
		if self.Gen.COMPRESSED_ISA:
			extensions += '[C]'
		if self.Gen.ENABLE_BITMANIP:
			extensions += '[Zba][Zbb][Zbs][Zbc]'
		
		singleDualPortRegisters = 'single'
		if self.Gen.ENABLE_REGS_DUALPORT:
			singleDualPortRegisters = 'dual'

		config = [
			'Chip name: ' + self.Gen.AsicNameForUserGuide,
			'Compatible with RISC-V compiler RV32' + extensions,
			'32-bit memory bus',
			'Contains 32 general purpose ' + singleDualPortRegisters + '-port CPU registers'
		]
		
		if self.Gen.COMPRESSED_ISA:
			config += ['Supports the RISC-V compressed instruction set and allows the use of the [C] compiler extension. Allowing the compiler to use the [C] extension reduces executable code size, but also takes the processor longer to fetch 32-bit long instructions that are aligned on a 2 but not 4 byte boundary from memory.']
		
		if self.Gen.BARREL_SHIFTER:
			config += ['Includes a barrel shifter in the ALU to produce fast bit shift operations']
		elif self.Gen.TWO_STAGE_SHIFT:
			config += ['Includes a two-stage shifter in the ALU to produce medium speed bit shift operations']
		else:
			config += ['Includes a multi-stage bit shifter in the ALU to save power and chip area for bit shift operations at the expense of speed']
		
		if self.Gen.ENABLE_FAST_MUL:
			config += ['Includes a fast 32-bit signed integer hardware multiplier in the ALU and allows the use of the [M] compiler extension']
		elif self.Gen.ENABLE_MUL:
			config += ['Includes a medium speed 32-bit signed integer hardware multiplier in the ALU and allows the use of the [M] compiler extension']
		
		if self.Gen.ENABLE_DIV and (self.Gen.ENABLE_MUL or self.Gen.ENABLE_FAST_MUL):
			config += ['Includes a medium speed 32-bit signed integer hardware divider and remainder calculator in the ALU']
		elif self.Gen.ENABLE_MUL or self.Gen.ENABLE_FAST_MUL:
			config[-1] += '. Note that this chip does not have a hardware divider, so all division operations must be handled in software.'

		if self.Gen.ENABLE_ATOMICS:
			config += ['Supports the RISC-V atomic instruction set (LR/SC and AMOs) and allows the use of the [A] compiler extension; on multi-hart configurations atomics are globally coherent across the shared window']

		if self.Gen.ENABLE_ATOMICS and self.Gen.ENABLE_ZABHA:
			config += ['Supports the RISC-V Zabha extension, adding byte (.b) and halfword (.h) atomic memory operations for all AMO functions; sub-word AMOs are globally coherent across the shared window like their word counterparts (LR/SC remain word-only)']

		if self.Gen.ENABLE_ATOMICS and self.Gen.ENABLE_ZACAS:
			config += ['Supports the RISC-V Zacas extension, adding word compare-and-swap (amocas.w), and, when Zabha is also present, byte/halfword compare-and-swap (amocas.b/.h); the CAS is a single globally-coherent read-compare-conditional-write transaction on the shared window (amocas.d is unsupported on RV32)']

		if self.Gen.ENABLE_ZICBOZ:
			config += ['Supports the RISC-V Zicboz extension, adding the cbo.zero instruction, which zeroes the naturally-aligned 64-byte block containing the addressed byte (16 word stores through the memory path); the cbo.clean/flush/inval management encodings are unsupported and trap illegal']

		if self.Gen.ENABLE_ZCMP:
			config += ['Supports the RISC-V Zcmp extension, adding the compressed push/pop stack-frame instructions (cm.push/cm.pop/cm.popret/cm.popretz) and the register-move pairs (cm.mvsa01/cm.mva01s); the push/pop run as an uninterruptible multi-cycle memory sequencer with the stack pointer committed last']

		if self.Gen.ENABLE_ZCMT:
			config += ['Supports the RISC-V Zcmt extension, adding the compressed table-jump instructions (cm.jt/cm.jalt) and the jvt CSR: the instruction indexes a 256-entry jump-vector table at the jvt base and redirects to the fetched target (cm.jalt also links the return address)']

		if self.Gen.ENABLE_BITMANIP:
			config += ['Supports the RISC-V bit-manipulation extensions Zba (address generation), Zbb (basic bit manipulation), Zbs (single-bit operations), and Zbc (carry-less multiplication)']

		config += ['The read-only misa CSR (0x301) advertises the enabled instruction-set extensions at run time']

		config += ['Supports maskable hardware interrupts generated by peripheral signals']

		if self.Gen.ENABLE_IRQ_QREGS:
			config += ['Four additional CPU registers are included to speed the execution of interrupt service routines']
		
		# Create the itemized list as a tex file
		#s = '\\begin{itemize}\n'
		#for c in config:
		#	s += '\\item ' + c + '\n'
		#s += '\\end{itemize}\n'
		s = ''
		for c in config:
			s += '\\item ' + c + '\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/SystemConfigurationList.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return
	
	def GenerateFeaturesList(self):
		# Build the System Configuration feature bullets from what the chip description
		# actually instantiates, so the TRM tracks the configuration (cores, peripherals,
		# shared-window blocks) instead of repeating a hand-maintained list.
		bullets = []

		# Multi-core bullets (hart count + the shared-window infrastructure blocks)
		if self.Gen.NumHarts > 1:
			bullets.append(str(self.Gen.NumHarts) + '$\\times$ VestaRV harts (cores), each with private RAM; hart ID readable via the \\register{mhartid} CSR')
			parts = []
			sharedRamBytes = 0
			if self.Gen.SharedWindowSections is not None:
				for sec in self.Gen.SharedWindowSections:
					if 'RAM' in sec[0].upper():
						sharedRamBytes += sec[2] - sec[1] + 1
			if sharedRamBytes > 0:
				if sharedRamBytes % 1024 == 0:
					parts.append(str(sharedRamBytes // 1024) + ' KiB of shared RAM')
				else:
					parts.append(str(sharedRamBytes) + ' bytes of shared RAM')
			clint = None
			mutex = None
			irqRouter = None
			for p in self.Gen.Peripherals:
				if p.Name == 'CLINT':
					clint = p
				elif p.Name == 'MUTEX':
					mutex = p
				elif p.Name == 'IRQROUTER':
					irqRouter = p
			if clint is not None:
				parts.append('a CLINT (inter-processor and per-hart timer interrupts)')
			if mutex is not None:
				parts.append(str(len(mutex.Registers)) + ' hardware mutexes')
			if irqRouter is not None:
				parts.append('a per-hart peripheral interrupt router')
			if len(parts) > 0:
				if len(parts) > 1:
					joined = ', '.join(parts[:-1]) + ', and ' + parts[-1]
				else:
					joined = parts[0]
				bullets.append('An arbitrated shared memory window with ' + joined)

		# One bullet (or bullet group) per instantiated peripheral template, in
		# description order, with the instance count folded in
		templates = []
		for p in self.Gen.Peripherals:
			if p.Template not in templates:
				templates.append(p.Template)
		for pt in templates:
			if pt.LatexFeatureSummary is None:
				continue
			count = 0
			for p in self.Gen.Peripherals:
				if p.Template == pt:
					count += 1
			for summary in pt.LatexFeatureSummary:
				if '{count}' in summary:
					bullets.append(summary.replace('{count}', str(count) + '$\\times$'))
				elif count > 1:
					bullets.append(str(count) + '$\\times$ ' + summary)
				else:
					bullets.append(summary)

		s = ''
		for b in bullets:
			s += '\\item ' + b + '\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/FeaturesList.tex'
		with open(path, 'w') as f:
			f.write(s)

		return

	def GenerateExtraIntroChapters(self):
		# Input list for the hand-written extra chapters (ChipGenerator.ExtraLatexIntroFiles,
		# e.g. the Multi-Core Architecture chapter). The master template inputs this file so
		# chapter filenames/revisions live in the chip description, not in the template.
		s = '% Generated from ChipGenerator.ExtraLatexIntroFiles, do not edit\n'
		if self.Gen.ExtraLatexIntroFiles is not None:
			for fileName in self.Gen.ExtraLatexIntroFiles:
				s += '\\input{include/' + fileName + '}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/ExtraIntroChapters.tex'
		with open(path, 'w') as f:
			f.write(s)

		return

	def GenerateAfeSystemDiagram(self):
		'''include/AfeSystemDiagram.tex — the analog-front-end companion to the
		   system block diagram (GenerateSystemBlockDiagram, whose figure was
		   retired from the manual on 2026-08-16, so the emitted prose now cites
		   Figure \\ref{fig:chip-system-diagram} instead), drawn
		   ONLY where the AFE bank exists (the CQ package model declares
		   DocSubSlotBlocks; \\ifcqanalog gates the chapter that \\inputs this).

		   IT IS THE SAME SHAPE AS THE SYSTEM BLOCK DIAGRAM ON PURPOSE — the same two banded
		   regions, the same five hart boxes, the same arbiter bar across the
		   bottom of them — because the reader has already learnt to read that
		   picture. What changes is the row UNDER the arbiter: instead of the
		   memory system it carries the five analog register sites, one per
		   column, so the ownership is a straight vertical column and needs no
		   arrow of its own. The memory-side slaves are simply not drawn; this
		   figure's subject is who reaches which front end, and what leaves the
		   die.

		   THREE THINGS IT IS CAREFUL NOT TO OVERCLAIM (the chapter's own
		   framing, Section \\ref{s:cqanalog}): what is on the die today is the
		   DIGITAL access path — a register stub per site — so every analog
		   stage is drawn in a DASHED compartment that says so; the ownership
		   gate is a comparison against the arbiter\'s granted-master index and
		   not a wire, so it is written in the box that enforces it; and the
		   electrode pads are real (the CQ pad ring bonds four per site), so
		   they are drawn crossing the boundary as solid pads.'''
		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		path = self.IncludeDirectory + '/AfeSystemDiagram.tex'
		blocks = getattr(self.Gen, 'DocSubSlotBlocks', None)
		if not blocks:
			with open(path, 'w') as f:
				f.write('% No analog front-end sub-slot blocks in this configuration (guarded by \\ifcqanalog).\n')
			return

		afe = [b for b in blocks if b['name'].startswith('AFE')]
		eis = [b for b in blocks if b['name'] == 'EIS']
		N = self.Gen.NumHarts

		# ---- E17-STYLE BUILD ASSERTIONS -------------------------------------
		# Everything enumerable in this drawing (four bases, five owners, twelve
		# electrode pads) is re-derived here from the two INDEPENDENT products
		# that hold it — the doc sub-slot block list and the package pin list —
		# so a map or pad-ring change that this layout does not cover fails
		# `make generate` instead of shipping a picture that disagrees with the
		# table on the facing page.
		if len(afe) != 4 or len(eis) != 1:
			raise Exception('AfeSystemDiagram: this drawing has one column per AFE site plus '
				'the EIS engine, and the configuration declares %d AFE blocks and %d EIS blocks'
				% (len(afe), len(eis)))
		for i, b in enumerate(afe):
			if b['base'] != 0x4C00 + 0x40 * i:
				raise Exception('AfeSystemDiagram: %s is based at 0x%X, not the uniform '
					'0x4C00 + %d*0x40 the figure draws' % (b['name'], b['base'], i))
		owners = [b['ownerHart'] for b in afe]
		if len(set(owners)) != len(owners):
			raise Exception('AfeSystemDiagram: two AFE sites name the same owner hart (%s); '
				'the figure draws one owning hart per column' % str(owners))
		for b in afe + eis:
			if not (0 <= b['ownerHart'] < N):
				raise Exception('AfeSystemDiagram: %s is owned by hart %d, which does not exist '
					'in a %d-hart configuration' % (b['name'], b['ownerHart'], N))
		if eis[0]['ownerHart'] != 0:
			raise Exception('AfeSystemDiagram: the EIS engine is drawn as the management hart\'s '
				'alone, but this configuration gives it to hart %d' % eis[0]['ownerHart'])
		# THE DRAWING IS THE ORCHESTRATOR CHIP'S, AND SAYS SO IN WORDS. Its hart
		# row is one management box captioned "hart 0: orchestrator" plus one
		# channel column per site, its banners read "the management hart" and
		# "the four channel harts", and the caption names the orchestrator. That
		# was safe while the CQ package model could only be reached through
		# config/cq.json, which is an orchestrator configuration. Since the CQ
		# QFN-64 became the DEFAULT package (2026-08-16) it is reachable by
		# inheritance from any config that does not name one, and MEASURED on
		# config/castalia4.json (numHarts=4, orchestrator=false) the figure
		# rendered two boxes both labelled "hart 0", a gate line reading
		# `s_master = 0 or 0', and a chapter sentence promising five harts on a
		# four-hart chip -- through a green build and a clean trm-lint. So the
		# three facts the drawing asserts about the hart row are now assertions:
		# a config that wants this chapter must be the shape the chapter
		# describes, or it must name a package model that does not carry it.
		if not bool((getattr(self.Gen, 'McuMpGeometry', None) or {}).get('orchestrator')):
			raise Exception('AfeSystemDiagram: this figure and its chapter describe the '
				'ORCHESTRATOR chip (a management hart 0 that is not a channel tile, named as '
				'the orchestrator in the hart box and in the caption), but this configuration '
				'has no orchestrator. Pin a package model without the AFE bank in this '
				'config, or generalize the drawing.')
		if eis[0]['ownerHart'] in owners:
			raise Exception('AfeSystemDiagram: hart %d is drawn BOTH as the management hart and '
				'as a channel tile, so the figure would carry two boxes with the same name; '
				'owners are %s' % (eis[0]['ownerHart'], str(owners)))
		if N != len(afe) + 1:
			raise Exception('AfeSystemDiagram: the figure draws every hart in the configuration '
				'(one management hart plus one channel tile per AFE site, %d in all), but this '
				'configuration has %d harts' % (len(afe) + 1, N))
		# The three-electrode group this figure draws per site, plus the fourth
		# pad it does NOT draw (RE2, the optional four-electrode/Kelvin sense
		# named in the caption): all four must be bonded by the package model,
		# or the figure is drawing pads this chip does not have.
		pinNames = set(p.Name for p in self.Gen.Package.Pins)
		electrodes = [('WE', 'working'), ('RE', 'reference'), ('CE', 'counter')]
		missing = [e + '_' + str(i) for i in range(4)
			for e in ('WE', 'RE', 'CE', 'RE2') if (e + '_' + str(i)) not in pinNames]
		if missing:
			raise Exception('AfeSystemDiagram: the package model does not bond the electrode '
				'pads %s that this figure draws crossing the chip boundary' % str(missing))

		def P(v):
			return '%.2f' % v

		# ---- geometry, in cm; the top half is the system block diagram's, to the millimetre
		# where it can be (band edges, tile width, the boundary/arbiter stack),
		# because the two figures are meant to be read as one drawing.
		aX0, aX1 = 0.00, 4.60          # band A: the always-on centre band
		bX0 = 5.10                     # band B: the hardened channel tiles
		tileW, gap = 2.75, 0.42
		col = [bX0 + tileW / 2.0 + i * (tileW + gap) for i in range(4)]
		bX1 = bX0 + 4 * tileW + 3 * gap
		mgmtX = (aX0 + aX1) / 2.0
		mgmtW = 4.20
		reachX = -0.85                 # the management reach, down the margin
		# EVERY BOX SETS `text width', NOT JUST `minimum width'. A minimum width
		# is a floor: a node whose contents are wider simply grows, and in a row
		# of five columns that is not a cosmetic problem, it is an overlap — the
		# first cut of this figure put `AFE0 register site' on one line at
		# \small, which is 2.8 cm of type in a 2.55 cm column, so each box grew
		# into its neighbour and the render showed clipped titles.
		siteTW = tileW - 0.25
		mgmtTW = mgmtW - 0.25

		yTop, yBan = 9.55, 8.85        # band top / banner strip floor
		yHart, hartH = 7.75, 1.80      # the hart row
		yBnd = 6.60                    # the registered tile boundary
		yArb, arbH = 5.65, 0.85        # the arbiter bar
		# The analog row's heights are TYPE HEIGHTS, not guesses: a TikZ node with
		# a `minimum height' smaller than its wrapped contents does not clip, it
		# SPILLS, and the first cuts of this figure spilled the gate line of every
		# site box straight through the dashed compartment underneath it. The
		# arithmetic is baselineskip x lines + 2 x inner sep: a site box is one
		# \small line (0.39) and three \scriptsize (0.33 each) = 1.38 + 0.24, so
		# it gets 1.70; a dashed compartment is three \scriptsize = 0.99 + 0.24,
		# so it gets 1.30. Height is the cheap axis here — the chapter scales
		# this drawing to the text WIDTH, so a taller figure costs nothing but
		# page height, while an overflowing box costs the reader the figure.
		bandT, bandB = 5.05, 0.70      # the analog row's own band
		regT, regB = 4.90, 3.20        # register-site boxes
		anaT, anaB = 3.20, 1.90        # the dashed analog compartments
		yRed = 0.32                    # the chip boundary
		cellT, cellB = -0.18, -1.52
		cellW = tileW
		dx = 0.92                      # electrode pitch within a site
		# THE PAD NAMES LIVE INSIDE THE CELL, UNDER THE STUB THEY NAME — never on
		# the wire. They used to be white-filled \tiny nodes sitting ON the twelve
		# electrode wires just above the boundary, and a white box punched through
		# a wire does not read as a label on a wire, it reads as an OPEN CIRCUIT:
		# the USER's word for the first cut of this figure. A filled square on a
		# wire is a pad (it stays); a filled box with words in it is a break. So
		# the wires now run unbroken from the analog compartment, through the red
		# boundary (where the pad square marks them), down to the electrode stub
		# inside the cell, and the name is printed BELOW that stub, in the cell's
		# own dead space, where it can be neither crossed nor mistaken for a part.
		yStub = cellT - 0.30           # the electrode stub bar, inside the cell
		yPad = yStub - 0.26            # its name, printed under it, clear of wire

		s = ('% Generated AFE connectivity diagram (sites=' + str(len(afe))
			+ ', owners=' + str(owners) + ', harts=' + str(N) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small},\n'
		s += '\ttile/.style={blk, fill=black!6},\n'
		s += '\torch/.style={blk, fill=black!12, line width=1.1pt},\n'
		s += '\tsite/.style={blk, fill=black!8},\n'
		s += '\tana/.style={draw, densely dashed, align=center, fill=white, font=\\sffamily\\scriptsize},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\treach/.style={->, >=Stealth, line width=1.3pt},\n'
		s += '\twire/.style={semithick},\n'
		s += '\tban/.style={font=\\sffamily\\scriptsize\\bfseries, black!65, align=center},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=center},\n'
		s += '\tpadlab/.style={font=\\sffamily\\tiny, align=center},\n'
		s += '\tredlab/.style={font=\\sffamily\\scriptsize\\bfseries, red!70!black, align=left}]\n'

		# ---- the two banded regions of the system block diagram, and their banners
		s += '\\fill[black!4] (' + P(aX0) + ', ' + P(yBnd) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!9] (' + P(bX0 - 0.20) + ', ' + P(yBnd) + ') rectangle (' + P(bX1 + 0.20) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!14] (' + P(aX0) + ', ' + P(yBan) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!20] (' + P(bX0 - 0.20) + ', ' + P(yBan) + ') rectangle (' + P(bX1 + 0.20) + ', ' + P(yTop) + ');\n'
		s += ('\\node[ban, text width=' + P(aX1 - aX0 - 0.30) + 'cm] at (' + P(mgmtX) + ', '
			+ P((yBan + yTop) / 2.0) + ') {the management hart\\\\ reaches every site};\n')
		s += ('\\node[ban, text width=' + P(bX1 - bX0 - 0.30) + 'cm] at (' + P((bX0 + bX1) / 2.0) + ', '
			+ P((yBan + yTop) / 2.0) + ') {the four channel harts, one analog site each};\n')

		# ---- the hart row: the system block diagram's five boxes, told what they own here
		s += ('\\node[orch, text width=' + P(mgmtTW) + 'cm, minimum width=' + P(mgmtW)
			+ 'cm, minimum height=' + P(hartH) + 'cm] (h0) at ('
			+ P(mgmtX) + ', ' + P(yHart) + ') {\\textbf{hart 0}: orchestrator\\\\ \\scriptsize soft logic, always on\\\\'
			+ ' \\scriptsize the management hart\\\\ \\scriptsize boots the chip, manages it};\n')
		for i, b in enumerate(afe):
			s += ('\\node[tile, text width=' + P(siteTW) + 'cm, minimum width=' + P(tileW)
				+ 'cm, minimum height=' + P(hartH)
				+ 'cm] (t' + str(i) + ') at (' + P(col[i]) + ', ' + P(yHart) + ') {\\textbf{hart '
				+ str(b['ownerHart']) + '}\\\\ \\scriptsize channel tile\\\\ \\scriptsize VestaRV core\\\\'
				+ ' \\scriptsize \\textbf{owns ' + b['name'] + '}};\n')

		# ---- the registered tile boundary and the arbiter, exactly as the system block diagram
		s += '\\draw[dashed, thick] (' + P(bX0 - 0.20) + ', ' + P(yBnd) + ') -- (' + P(bX1 + 0.20) + ', ' + P(yBnd) + ');\n'
		# \tiny, and that is a clearance decision, not a taste one: this label sits
		# in the lane between two masters' bus arrows (2.85 cm apart), and at
		# \scriptsize its white fill reached to within a millimetre of both.
		s += ('\\node[lab, font=\\sffamily\\tiny, fill=white, inner sep=1.5pt] at ('
			+ P((col[0] + col[1]) / 2.0) + ', '
			+ P((yBnd + yArb + arbH / 2.0) / 2.0) + ') {registered tile boundary\\\\ (1 cycle each way)};\n')
		s += ('\\node[blk, fill=black!15, minimum width=' + P(bX1 - aX0) + 'cm, minimum height=' + P(arbH)
			+ 'cm] (arb) at (' + P((aX0 + bX1) / 2.0) + ', ' + P(yArb)
			+ ') {\\textbf{mp\\_arbiter}: one transaction at a time; the granted master\'s index \\textbf{is} \\texttt{s\\_master}};\n')

		# ---- the analog row's band: one region, so hart 0's reach into ALL of
		# it is a property of the drawing rather than five more arrows.
		s += ('\\draw[fill=black!5, draw=black!45, thick, rounded corners=3pt] (' + P(reachX + 0.60) + ', '
			+ P(bandB) + ') rectangle (' + P(bX1 + 0.20) + ', ' + P(bandT) + ');\n')

		# the five masters onto the bar, the five column drops off it, and the
		# five register sites. THE COLUMN IS THE OWNERSHIP: site i sits directly
		# under the hart that owns it, so `hart 2 reaches AFE1' needs no arrow of
		# its own -- which matters, because there is no such wire. Every one of
		# these accesses is a shared-window transaction through the bar, and the
		# gate that admits it is a comparison inside the slave (printed in it).
		for x in [mgmtX] + col:
			s += ('\\draw[bus] (' + P(x) + ', ' + P(yHart - hartH / 2.0) + ') -- ('
				+ P(x) + ', ' + P(yArb + arbH / 2.0) + ');\n')

		def busDrop(x, yTo):
			return ('\\draw[bus] (' + P(x) + ', ' + P(yArb - arbH / 2.0) + ') -- ('
				+ P(x) + ', ' + P(yTo) + ');\n')

		def siteBox(x, w, tw, yb, title, base, gateLine):
			return ('\\node[site, text width=' + P(tw) + 'cm, minimum width=' + P(w)
				+ 'cm, minimum height=' + P(regT - yb) + 'cm, anchor=north] at (' + P(x) + ', '
				+ P(regT) + ') {' + title + '\\\\ \\scriptsize \\texttt{' + fmthex(base)
				+ '}, 64\\,B\\\\ \\scriptsize ' + gateLine + '};\n')

		def anaBox(x, w, tw, body):
			return ('\\node[ana, text width=' + P(tw) + 'cm, minimum width=' + P(w)
				+ 'cm, minimum height=' + P(anaT - anaB) + 'cm, anchor=north] at (' + P(x) + ', '
				+ P(anaT) + ') {' + body + '};\n')

		for i, b in enumerate(afe):
			s += busDrop(col[i], regT)
			s += siteBox(col[i], tileW, siteTW, regB, '\\textbf{' + b['name'] + '} site', b['base'],
				'gate:\\\\ \\texttt{s\\_master} = ' + str(b['ownerHart']) + ' \\emph{or} 0')
			s += anaBox(col[i], tileW, siteTW, 'potentiostat\\\\ TIA $+$ ADC\\\\ \\textit{not integrated}')
		s += busDrop(mgmtX, regT)
		s += siteBox(mgmtX, mgmtW, mgmtTW, regB, '\\textbf{' + eis[0]['name'] + '} sweep-engine site',
			eis[0]['base'], 'gate:\\\\ \\texttt{s\\_master} = 0 \\emph{only}')
		s += anaBox(mgmtX, mgmtW, mgmtTW, 'EIS sweep engine\\\\ $+$ analog multiplexer\\\\ \\textit{not integrated}')

		# ---- hart 0's reach: ONE arrow with a verb, into the row it opens. It
		# is deliberately not five arrows: the privilege is not five wires, it is
		# one comparison that every gate on the row makes.
		s += ('\\draw[reach] (h0.west) -- (' + P(reachX) + ', ' + P(yHart) + ') -- (' + P(reachX) + ', '
			+ P((regT + regB) / 2.0) + ') -- (' + P(reachX + 0.60) + ', ' + P((regT + regB) / 2.0) + ');\n')
		s += ('\\node[note, anchor=north west, text width=' + P(mgmtTW + 0.15) + 'cm] at ('
			+ P(aX0 + 0.10) + ', ' + P(anaB - 0.14)
			+ ') {\\textbf{Hart 0 reaches every block on this row}: \\texttt{s\\_master} = 0 '
			+ 'opens every gate.};\n')

		# ---- the chip boundary, the electrode pads, and the cells
		s += ('\\draw[red, densely dotted, line width=1.1pt] (' + P(reachX - 0.10) + ', ' + P(yRed)
			+ ') -- (' + P(bX1 + 0.40) + ', ' + P(yRed) + ');\n')
		s += ('\\node[redlab, anchor=north west, text width=4.60cm] at (' + P(aX0 + 0.10) + ', ' + P(yRed - 0.14)
			+ ') {chip boundary: twelve electrode pads, three per site, leave the die here};\n')
		for i, b in enumerate(afe):
			c = col[i]
			s += ('\\draw[thick, rounded corners=3pt, fill=black!3] (' + P(c - cellW / 2.0) + ', ' + P(cellB)
				+ ') rectangle (' + P(c + cellW / 2.0) + ', ' + P(cellT) + ');\n')
			s += ('\\node[lab, anchor=south, text width=' + P(cellW - 0.30) + 'cm] at (' + P(c) + ', '
				+ P(cellB + 0.05) + ') {three-electrode cell};\n')
			for k, (e, _long) in enumerate(electrodes):
				x = c + (k - 1) * dx
				# ONE unbroken wire per electrode: analog compartment -> boundary
				# -> stub. Nothing is drawn over it but the pad square.
				s += '\\draw[wire] (' + P(x) + ', ' + P(anaB) + ') -- (' + P(x) + ', ' + P(yStub) + ');\n'
				s += '\\draw[wire, line width=1.2pt] (' + P(x - 0.15) + ', ' + P(yStub) + ') -- (' + P(x + 0.15) + ', ' + P(yStub) + ');\n'
				s += ('\\fill[red!70!black] (' + P(x - 0.07) + ', ' + P(yRed - 0.07) + ') rectangle ('
					+ P(x + 0.07) + ', ' + P(yRed + 0.07) + ');\n')
				s += ('\\node[padlab, anchor=north, inner sep=1pt] at (' + P(x) + ', ' + P(yPad)
					+ ') {\\texttt{' + fmttex(e + '_' + str(i)) + '}};\n')
		s += '\\end{tikzpicture}\n'
		self._writeInclude('AfeSystemDiagram.tex', s)
		return

	def GenerateCqAnalogChapter(self):
		# Config-gated chapter for the CQ analog front-end (AFE0-3 + EIS). Rendered
		# ONLY when the config declares DocSubSlotBlocks (the CQ package model); the
		# master template guards the \input with \ifcqanalog, so for the default
		# build this file is a bare comment and the default TRM stays byte-identical.
		# The register table is emitted from the validated sub-slot block data — the
		# same single-source discipline as the rest of the TRM, but on a docs-only
		# path that never touches the peripheral / MemoryMap / MCU.vhd machinery.
		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		path = self.IncludeDirectory + '/CqAnalog.tex'

		blocks = getattr(self.Gen, 'DocSubSlotBlocks', None)
		if not blocks:
			with open(path, 'w') as f:
				f.write('% No analog front-end sub-slot blocks in this configuration (guarded by \\ifcqanalog).\n')
			return

		afeBlocks = [b for b in blocks if b['name'].startswith('AFE')]
		eisBlocks = [b for b in blocks if b['name'] == 'EIS']

		s = '% Generated from ChipGenerator.DocSubSlotBlocks, do not edit. Rendered only under \\ifcqanalog.\n'
		s += '\\section{Analog Front-End Subsystem} \\label{s:cqanalog}\n\n'
		s += ('This chip carries a bipolar-potentiostat analog front-end (AFE) for '
			'electrochemical impedance measurement, organised as four per-quadrant '
			'measurement \\emph{sites} plus one shared electrochemical-impedance-'
			'spectroscopy (EIS) sweep engine. Each site drives its own electrode group '
			'(counter/working/reference/RE2) brought out on the package (Section '
			'\\ref{s:pinsConfig}). The analog blocks themselves (the potentiostat, '
			'the transimpedance ADC path, and the shared EIS engine + analog multiplexer'
			') are analog IP that is not yet integrated; what \\emph{is} present is the '
			'complete \\emph{digital access path}: a register stub for each site and for '
			'the EIS engine, each a fully-functional shared-window arbiter slave with the '
			'ownership gate and interrupt path described below. Software (and the '
			'verification suite) programs and reads these exactly as it will the final '
			'analog blocks; the stubs hold placeholder storage and drive their interrupt '
			'from a software-settable flag until the analog IP replaces them.\n\n')

		# The connectivity figure. Its \label AND every \ref to it live inside
		# this generated chapter, which the master template \inputs only under
		# \ifcqanalog, so the two polarities cannot disagree and trm-lint never
		# sees a dangling reference (the both-polarity \ref rule).
		# W5 (2026-08-16): this used to cite the top-level block diagram
		# (fig:system-block-diagram), which was retired from TRM.template.tex.
		# It now cites the whole-chip portrait figure, which carries the same
		# hart band and the same arbiter bar and is the figure this one is
		# actually the companion to.
		s += ('Figure \\ref{fig:afe-system-diagram} is the arrangement: the same five harts '
			'and the same arbiter as Figure \\ref{fig:chip-system-diagram}, with the analog '
			'register sites in the row underneath and the electrodes leaving the die at the '
			'bottom.\n\n')
		s += '\\begin{figure}[htpb]\n\t\\centering\n'
		s += '\t\\resizebox{\\linewidth}{!}{\\input{include/AfeSystemDiagram.tex}}\n'
		s += ('\t\\caption[{Analog front-end connectivity: who reaches which site, and what leaves the die.}]'
			'{Analog front-end connectivity: who reaches which site, and what leaves the die. Each channel '
			'hart owns exactly one measurement site and reaches no other; hart 0, the orchestrator, opens '
			'every gate in the row, because the gate compares the arbiter\'s granted-master index against a '
			'single owner and against 0. The analog stages are drawn dashed because they are not yet '
			'integrated: what the chip carries today is the digital register site in front of each one '
			'(and the pads behind them). Each site brings out a three-electrode cell: \\texttt{WE} the '
			'working electrode, \\texttt{RE} the reference, \\texttt{CE} the counter. A fourth pad per site, '
			'\\texttt{RE2}\\textsubscript{$h$}, is bonded as well and is not drawn: it is the second sense '
			'electrode of the optional four-terminal (Kelvin) configuration.}\n')
		s += '\t\\label{fig:afe-system-diagram}\n\\end{figure}\n\n'

		# --- Address map + ownership table -------------------------------------
		s += '\\subsection{Blocks, addresses, and ownership} \\label{ss:cqanalog-map}\n\n'
		s += ('The five blocks live in otherwise-reserved shared-window space, so they '
			'do not disturb the peripheral memory map: the four AFE sites occupy the four '
			'64-byte sub-slots of the reserved page-0 slot 12 at \\texttt{0x4C00}, and the '
			'EIS engine occupies the top quarter of the IRQ-router page at \\texttt{0x7C00}. '
			'Every block is a 16-word (64-byte) register file reached through the multi-core '
			'arbiter like any other shared slave; access is qualified by the '
			'\\emph{ownership gate} (Section \\ref{ss:cqanalog-gate}).\n\n')
		s += '\\begin{tabularx}{\\textwidth}{ l l l X }\n'
		s += '\\textbf{Block} & \\textbf{Base} & \\textbf{IRQ source} & \\textbf{Access allowed when} \\\\ \\hline\n'
		for b in afeBlocks + eisBlocks:
			s += ('\\texttt{' + b['name'] + '} & \\texttt{' + fmthex(b['base']) + '} & '
				+ str(b['irqSource']) + ' & ' + b['gate'] + ' \\\\\n\\hline\n')
		s += '\\end{tabularx}\n\n'
		s += ('Here \\texttt{s\\_master} is the granted-master (hart) index that the '
			'multi-core arbiter attributes to the in-flight transaction, the same '
			'attribution the hardware mutex bank and the IRQ-router CLAIM use. Because '
			'each block decodes only its low four address bits, its 16 words fill its '
			'64-byte sub-slot exactly; the EIS block additionally aliases across the '
			'\\texttt{0x7C00}--\\texttt{0x7FFF} quarter it owns.\n\n')

		# --- Ownership / gating semantics --------------------------------------
		s += '\\subsection{Ownership gating} \\label{ss:cqanalog-gate}\n\n'
		# The owner mapping is READ OUT OF THE BLOCK DATA, never spelt as
		# "site AFE h answers hart h": on an orchestrator configuration hart 0 is
		# the orchestrator and the owners are the four CHANNEL harts, so the site
		# index and the owning hart differ by one (generate.py derives it from the
		# same knob mcu_vhd.afeStubsOrchOwners() does).
		ownerPairs = ', '.join('\\texttt{' + b['name'] + '} to hart ' + str(b['ownerHart'])
			for b in afeBlocks)
		s += ('Each AFE site is owned by one hart (' + ownerPairs + '), and it '
			'answers only when \\texttt{s\\_master} is that hart \\emph{or} \\texttt{s\\_master} = 0. '
			'Hart 0 is the management hart, so it reaches every site (this is what lets it '
			'demultiplex the shared interrupt, below); every other hart sees only its own '
			'site. The EIS engine is instantiated hart-0-only (\\texttt{s\\_master} = 0), so '
			'other harts request a sweep through a software mailbox convention rather than '
			'touching it directly. The gate is hardware-enforced inside the slave and keys '
			'off \\texttt{s\\_master} alone: there is no way to forge ownership, and no '
			'cross-hart data leaks. A \\emph{denied} read returns 0 and a \\emph{denied} '
			'write is silently dropped: no bus error, no stall, no change to the arbiter '
			'contract. All registers reset to 0, so a block is a provable no-op (interrupt '
			'low, reads 0) until its owner writes it.\n\n')

		# --- Register map -------------------------------------------------------
		s += '\\subsection{Register map (per block)} \\label{ss:cqanalog-regs}\n\n'
		s += ('All five blocks share one 16-word register layout (they are the same '
			'hardware entity, differing only in the ownership gate). Offsets are byte '
			'offsets from the block base; each word is 32 bits. Detailed bit fields for '
			'the placeholder registers are owned by the analog IP specification and will '
			'be filled in when that IP is integrated.\n\n')
		regs = afeBlocks[0]['registers']
		s += '\\begin{tabularx}{\\textwidth}{ l l l X }\n'
		s += '\\textbf{Offset} & \\textbf{Name} & \\textbf{Access} & \\textbf{Description} \\\\ \\hline\n'
		i = 0
		n = len(regs)
		while i < n:
			(woff, name, access, desc) = regs[i]
			# collapse a run of identical (name placeholder + access + desc) rows
			j = i
			while (j + 1 < n) and (regs[j + 1][1] == name) and (regs[j + 1][2] == access) and (regs[j + 1][3] == desc):
				j += 1
			loByte = regs[i][0] * 4
			hiByte = regs[j][0] * 4
			if j > i:
				offStr = '\\texttt{' + fmthex(loByte, 2) + '}--\\texttt{' + fmthex(hiByte, 2) + '}'
			else:
				offStr = '\\texttt{' + fmthex(loByte, 2) + '}'
			if name in ('—', '-', ''):
				nameStr = '\\textit{reserved}'
			else:
				nameStr = '\\texttt{' + name + '}'
			s += offStr + ' & ' + nameStr + ' & ' + access + ' & ' + desc + ' \\\\\n\\hline\n'
			i = j + 1
		s += '\\end{tabularx}\n\n'

		# --- Interrupt relay contract ------------------------------------------
		afeSrc = afeBlocks[0]['irqSource']
		eisSrc = eisBlocks[0]['irqSource'] if eisBlocks else None
		s += '\\subsection{Interrupt relay} \\label{ss:cqanalog-irq}\n\n'
		s += ('The AFE/EIS interrupts reuse two vector numbers that the digital-only '
			'respin left reserved, so nothing is renumbered: the four AFE sites are '
			'OR-combined onto a single shared interrupt at source ' + str(afeSrc)
			+ ' (formerly the AFE0 vector), and the EIS engine drives source '
			+ str(eisSrc) + ' (formerly the SARADC0 vector). Both are delivered through '
			'the IRQ router (Section \\ref{peripheralIRQROUTER}) like any other peripheral '
			'source, and both are routed, by software convention in the routing rows, '
			'to \\emph{hart 0 only}.\n\n')
		s += ('Routing source ' + str(afeSrc) + ' to hart 0 is forced, not merely chosen: '
			'because the ownership gate lets only hart 0 read all four AFE flag registers, '
			'hart 0 is the only hart that can tell which site fired. The relay is: hart 0 '
			'takes the external interrupt, CLAIMs source ' + str(afeSrc) + ' at the router, '
			'reads the four \\register{IF} words to demultiplex the originating site(s), '
			'clears the level at each firing site (write-1-to-clear on \\register{IF}), '
			'COMPLETEs source ' + str(afeSrc) + ', and then notifies the owning hart '
			'through the usual \\peripheral{CLINT} software-interrupt (msip) mailbox. '
			'Sensor-rate latency through this relay is immaterial. Source ' + str(eisSrc)
			+ ' (EIS) is intrinsically hart-0-only and needs no demultiplex.\n\n')
		s += ('Giving each AFE site its own interrupt identity (growing the source map, so '
			'a site can interrupt its quadrant hart directly without the hart-0 relay) is a '
			'deliberately deferred option: it would renumber the CLINT and external-'
			'interrupt vectors and disturb the boot-ROM park contract, so it is only worth '
			'doing if a future workload needs hart-local AFE interrupt latency.\n\n')

		with open(path, 'w') as f:
			f.write(s)
		return

	# ------------------------------------------------------------------
	# Address-space figure (TRM Section \ref{s:addressSpace}).
	#
	# THE MAP IS TWO OVERLAPPING VIEWS, and the figure draws them as ONE
	# monotonically increasing column with the views told apart by their
	# group braces:
	#   * the SHARED WINDOW 0x0..2^(SH_AW+2)-1, which every hart reaches
	#     through the mp_arbiter — hart_tile.vhd's sh_sel decode:
	#         sh_sel <= '1' when data_addr(31 downto SH_AW+2) = SH_WIN_ZERO
	#                        and not (data_addr(SH_AW+1 downto 16) = SH_TCM_ZERO
	#                                 and data_addr(15 downto 14) = "10")
	#   * the PRIVATE TCM band, which that same decode carves OUT of the
	#     window (the "10" region term), so at those addresses each hart
	#     sees its own RAM0 instead of the shared bus.
	# Above the window, extended flash decodes at exactly 2^(SH_AW+2) —
	# the STRICT COMPLEMENT of sh_sel (adddec.vhd gen_flash_detect:
	# data_addr(31 downto SH_AW+2) /= FLASH_ZERO; the M3c.3 double-claim
	# lesson) — and only hart 0 has that path.
	#
	# Everything drawn is DERIVED: the shared rows from
	# Gen.SharedWindowSections (including the per-hart TCM apertures),
	# ROM/peripheral/TCM geometry from the ChipGenerator memory objects,
	# the flash base from McuMpGeometry['shAw'] (same expression the
	# SPI_FLASH_MEM_ADDRESS header define uses). No literal addresses.
	#
	# THE DEFECT THIS STRUCTURE MAKES IMPOSSIBLE: the figure used to be
	# emitted as two independent columns (the private map, then the shared
	# sections) with the second one continuing from the FIRST one's running
	# end, so it shipped rows like \memsection{0x0C000}{0x04FFF} — start
	# above end — and printed 0x05000 and 0x08000 twice. The rows are now
	# built as one gapless, strictly increasing tiling of the whole 32-bit
	# space, and _AssertAddressSpaceTex() re-walks the EMITTED tex (not the
	# model that produced it) and raises before the file is written.
	# ------------------------------------------------------------------

	# Access-class labels for the figure's group braces. Each brace is one
	# access class, so the private carve-out visibly interrupts the shared
	# window instead of being hidden inside it.
	_ADDR_GROUP_SHARED = 'Shared window\\\\(all harts, arbitrated)'
	_ADDR_GROUP_PRIVATE = 'Private to each hart\\\\(not arbitrated)'
	_ADDR_GROUP_APERTURE = 'Shared window\\\\(hart 0\'s read-only view\\\\of each hart\'s TCM)'
	_ADDR_GROUP_FLASH = 'External SPI flash\\\\(hart 0 only)'
	_ADDR_TOP = 0xFFFFFFFF

	def _AddressSpaceSizeString(self, size):
		for unit, div in (('MiB', 1024 * 1024), ('KiB', 1024)):
			if size >= div and (size % div) == 0:
				return str(size // div) + ' ' + unit
		return str(size) + ' B'

	def _AddressSpaceRows(self):
		'''Build the figure's rows: an ordered list of (start, end, group, lines)
		   that TILES the 32-bit space — gapless, strictly increasing, by
		   construction. group is a brace label or None (no brace).'''
		gen = self.Gen
		unmappedLines = ['\\textit{\\color{lightgray}Unmapped}', '\\textit{\\color{lightgray}(reads zero)}']

		# --- which shared sections are the per-hart TCM apertures ----------
		# Read off the resolved config's derived geometry rather than matching
		# section names, so the classification follows the generator's own
		# arithmetic (0x20000 + 0x4000*h) and degrades to "no apertures" for
		# every non-orchestrator configuration.
		apertureStarts = set()
		rc = getattr(gen, 'ResolvedConfig', None) or {}
		for a in ((rc.get('derived') or {}).get('tcmWindowAddresses') or []):
			apertureStarts.add(int(str(a), 16))

		# --- the mapped regions, each from its generator object ------------
		regions = []
		regions.append((gen.RomStartAddress, gen.RomEndAddress, self._ADDR_GROUP_SHARED,
			['Boot ROM', 'Size = ' + self._AddressSpaceSizeString(1 + gen.RomEndAddress - gen.RomStartAddress)]))
		regions.append((gen.PeripheralMemoryStartAddress, gen.PeripheralMemoryEndAddress, self._ADDR_GROUP_SHARED,
			['Peripheral registers', 'Size = ' + self._AddressSpaceSizeString(gen.PeripheralMemorySize)]))
		for name, startAddr, endAddr, desc in (gen.SharedWindowSections or []):
			group = self._ADDR_GROUP_APERTURE if startAddr in apertureStarts else self._ADDR_GROUP_SHARED
			regions.append((startAddr, endAddr, group,
				[name, 'Size = ' + self._AddressSpaceSizeString(1 + endAddr - startAddr)]))

		# The private band: the ChipGenerator "RAM" object IS the per-hart TCM
		# on this chip (one slot per used SRAM), and it is the only private
		# region in the map.
		firstRamSlot = min(gen.RamMemorySlotsAvailable)	# same formula as generateMemoryX; the old hardcoded (ramSlot - 2) drew the RAM at the wrong addresses
		multiSlot = len(gen.RamMemorySlotsUsed) > 1
		for i, ramSlot in enumerate(gen.RamMemorySlotsUsed):
			if i == (len(gen.RamMemorySlotsUsed) - 1):
				thisSlotSize = gen.LastRamMemorySlotSize
			else:
				thisSlotSize = gen.RamMemorySlotSize
			addr = gen.RamStartAddress + ((ramSlot - firstRamSlot) * gen.RamMemorySlotSize)
			title = 'Private TCM'
			if multiSlot:
				title += ' (SRAM{:02d})'.format(ramSlot)
			lines = [title, 'Size = ' + self._AddressSpaceSizeString(thisSlotSize) + ' per hart']
			if ramSlot in gen.RamMemorySlotsMuxed:
				muxNote = '\\textit{Multiplexed'
				if type(gen.RamMemorySlotsMuxed) == dict:
					muxNote += ' with ' + gen.RamMemorySlotsMuxed[ramSlot]
				lines.append(muxNote + '}')
			regions.append((addr, addr + thisSlotSize - 1, self._ADDR_GROUP_PRIVATE, lines))

		# --- the window top and the flash base, both from SH_AW ------------
		flashRead = bool(gen.NativeSpiFlashMemoryReadAccess)
		flashWrite = bool(gen.NativeSpiFlashMemoryWriteAccess)
		geo = getattr(gen, 'McuMpGeometry', None)
		if geo:
			flashBase = 1 << (geo['shAw'] + 2)
		elif flashRead or flashWrite:
			raise Exception('AddressSpaceDiagram: the extended-flash window is enabled but the '
				'configuration has no McuMpGeometry to derive its base (2^(shAw+2)) from')
		else:
			flashBase = max([r[1] for r in regions]) + 1
		windowTop = flashBase - 1

		# --- assemble: sort, check, fill every gap -------------------------
		regions.sort(key=lambda r: r[0])
		rows = []
		cursor = 0
		for (start, end, group, lines) in regions:
			if end < start:
				raise Exception('AddressSpaceDiagram: region ' + lines[0] + ' has start 0x{:X} above end 0x{:X}'.format(start, end))
			if start < cursor:
				raise Exception('AddressSpaceDiagram: region ' + lines[0] + ' at 0x{:X} overlaps the region below it (which ends at 0x{:X})'.format(start, cursor - 1))
			if end > windowTop:
				raise Exception('AddressSpaceDiagram: region ' + lines[0] + ' ends at 0x{:X}, above the shared-window top 0x{:X}'.format(end, windowTop))
			if start > cursor:
				rows.append((cursor, start - 1, None, unmappedLines))
			rows.append((start, end, group, lines))
			cursor = end + 1
		if cursor <= windowTop:
			rows.append((cursor, windowTop, None, unmappedLines))
			cursor = windowTop + 1

		# --- above the window: the extended-flash window, or nothing -------
		if flashRead or flashWrite:
			flashLines = ['SPI flash (XIP)']
			if flashRead and not flashWrite:
				flashLines.append('\\textit{read only}')
			flashLines.append('\\textit{(addr + SPI0FOS) mod $2^{24}$}')
			rows.append((flashBase, self._ADDR_TOP, self._ADDR_GROUP_FLASH, flashLines))
		else:
			rows.append((cursor, self._ADDR_TOP, None, unmappedLines))
		return rows

	def _AssertAddressSpaceTex(self, tex):
		'''E17-style build-time assertion. Walks the rows the emitter ACTUALLY
		   drew — parsed back out of the emitted tex, not out of the model that
		   produced them — and raises unless they are a gapless, strictly
		   increasing tiling of the whole 32-bit space. An inverted or repeated
		   address column now fails `make generate` instead of shipping.'''
		pairs = re.findall(r'\\memsection\{0x([0-9A-Fa-f]+)\}\{0x([0-9A-Fa-f]+)\}', tex)
		if not pairs:
			raise Exception('AddressSpaceDiagram: no \\memsection rows were emitted')
		prevEnd = -1
		for i, (a, b) in enumerate(pairs):
			start = int(a, 16)
			end = int(b, 16)
			if end < start:
				raise Exception('AddressSpaceDiagram: drawn row {} runs BACKWARDS: start 0x{:X} is above end 0x{:X}'.format(i, start, end))
			if start != prevEnd + 1:
				raise Exception('AddressSpaceDiagram: drawn row {} starts at 0x{:X} but the row above it ended at 0x{:X}'
					' — the drawn column must be gapless and strictly increasing'.format(i, start, prevEnd))
			prevEnd = end
		if prevEnd != self._ADDR_TOP:
			raise Exception('AddressSpaceDiagram: the drawn column ends at 0x{:X}, not at the top of the 32-bit space 0x{:X}'.format(prevEnd, self._ADDR_TOP))

	def GenerateAddressSpaceDiagram(self):
		rows = self._AddressSpaceRows()

		# Emit one bytefield column, merging adjacent rows of the same access
		# class into a single right-hand brace.
		s = '\\begin{bytefield}{8}\n'
		i = 0
		while i < len(rows):
			group = rows[i][2]
			j = i
			if group is not None:
				while (j + 1) < len(rows) and rows[j + 1][2] == group:
					j += 1
			body = []
			for (start, end, g, lines) in rows[i:j + 1]:
				height = '4' if len(lines) >= 3 else '3'
				body.append('\\memsection{' + fmthex(start, minDigits=5) + '}{' + fmthex(end, minDigits=5)
					+ '}{' + height + '}{' + ' \\\\ '.join(lines) + '}')
			if group is None:
				for b in body:
					s += b + ' \\\\\n'
			else:
				s += '\\begin{rightwordgroup}{' + group + '}\n'
				s += ' \\\\\n'.join(body) + '\n'
				s += '\\end{rightwordgroup}\n'
				if (j + 1) < len(rows):
					s += '\\\\\n'
			i = j + 1
		s += '\\end{bytefield}\n'

		self._AssertAddressSpaceTex(s)

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/AddressSpaceDiagram.tex'
		with open(path, 'w') as f:
			f.write(s)

		return

	# -----------------------------------------------------------------
	# Unified-configuration section + generated diagrams (2026-07-11).
	# All of these render from the SAME records generate.py builds for
	# config/ChipConfig.resolved.json and config/PadRing.json, so the TRM,
	# the make chip schema, and the configurator HTML cannot drift apart.
	# -----------------------------------------------------------------

	def GenerateChipConfigurationSection(self):
		'''include/ChipConfigurationTable.tex — the make chip CONFIG= schema with
		   this build's resolved values, plus the derived-geometry table.'''
		rc = getattr(self.Gen, 'ResolvedConfig', None)
		doc = getattr(self.Gen, 'ConfigSchemaDoc', {})
		if rc is None:
			return

		def val(dotted):
			node = rc
			for part in dotted.split('.'):
				node = node.get(part) if isinstance(node, dict) else None
			return node

		def texdesc(s):
			# NO EM-DASHES IN THE TRM (user directive 2026-08-15). This used to
			# silently rewrite U+2014 into the LaTeX `---` ligature, which meant a
			# schema description string could reintroduce a rendered em-dash without
			# anyone noticing. Fail the build loudly instead; reword the offending
			# _CONFIG_SCHEMA description with a comma, colon or parentheses.
			if '—' in s or '---' in s:
				raise ValueError(
					'em-dash in a TRM schema description string (no em-dashes in '
					'the TRM: reword with a comma, colon or parentheses): ' + repr(s))
			return fmttex(s)

		def fmtval(dotted, v):
			if isinstance(v, bool):
				return '\\texttt{' + ('true' if v else 'false') + '}'
			if dotted.startswith('memory.') and isinstance(v, int):
				return '\\texttt{' + str(v) + '} (' + str(v // 1024) + '\\,KiB)'
			return '\\texttt{' + fmttex(str(v)) + '}'

		# Full schema coverage (2026-07-29 honesty fix: this list had been frozen
		# at the pre-X-series key set, so X-series ISA, priv, newer-peripheral and
		# package knobs never appeared in the TRM config table). Keep in sync with
		# generate.py _CONFIG_SCHEMA — grouped: core, isa, priv, memory, periph, pkg.
		keyOrder = ['chipName', 'numHarts', 'orchestrator', 'numMutexes', 'registerFileDualPort',
			'core.fetchAhead',
			'isa.mul', 'isa.fastMul', 'isa.div', 'isa.atomics', 'isa.compressed',
			'isa.bitmanip', 'isa.minimalTiles', 'isa.counters', 'isa.counters64',
			'isa.zicond', 'isa.zcb', 'isa.zimop', 'isa.zihint', 'isa.zihpm',
			'isa.zawrs', 'isa.zabha', 'isa.zacas', 'isa.zicboz', 'isa.zcmp',
			'isa.zcmt', 'isa.zbkb', 'isa.zbkc', 'isa.zbkx', 'isa.zkn', 'isa.zfinx',
			'priv.trapCsr', 'priv.umode', 'priv.pmp', 'priv.pmpEntries',
			'debug.enable',
			'memory.romSize', 'memory.tcmSizePerHart', 'memory.sharedBulkRamSize',
			'memory.npuStagingRamSize',
			'peripherals.npu', 'peripherals.i2c1', 'peripherals.uart1',
			'peripherals.spi1', 'peripherals.timer1', 'peripherals.cqAfeStubs',
			'peripherals.qspi', 'peripherals.i3c', 'peripherals.nfc',
			'peripherals.rtc', 'peripherals.pwm', 'peripherals.onewire',
			'peripherals.fieldPower', 'peripherals.dma', 'peripherals.dmaChannels',
			'peripherals.i2ctarget', 'peripherals.trng', 'peripherals.trngRings',
			'peripherals.eventFabric',
			'package.model', 'package.preliminary']

		# K2 (inventory probe §1.3): the list above is HAND-MAINTAINED and had
		# already silently drifted once -- it stayed frozen at the pre-X-series
		# key set, so the whole X-series ISA block, the priv block, the newer
		# peripherals and the package knobs were absent from the TRM's own
		# configuration table while the schema advertised them. It was corrected
		# by hand on 2026-07-29 and nothing stopped it happening again.
		# ConfigSchemaDoc is `dict((k, _CONFIG_SCHEMA[k][0]) for k in
		# _CONFIG_SCHEMA)` (generate.py), i.e. exactly the schema key set, so
		# this is the whole check: a knob added to the schema and forgotten here
		# now fails `make generate` instead of quietly vanishing from the manual.
		missing = sorted(set(doc) - set(keyOrder))
		extra = sorted(set(keyOrder) - set(doc))
		if missing or extra:
			raise Exception(
				'TRM chip-configuration table is out of sync with _CONFIG_SCHEMA.\n'
				'  in the schema but NOT in keyOrder (would be absent from the TRM): %s\n'
				'  in keyOrder but NOT in the schema (would render an empty row): %s\n'
				'  Fix: edit keyOrder in LatexUserGuide.GenerateChipConfigurationSection.'
				% (missing, extra))

		s = '% Generated: the make chip CONFIG= schema + the values of THIS build\n'
		s += '\\begin{longtable}[c]{ l l p{7.2cm} }\n'
		s += '\\caption{Chip configuration knobs (\\texttt{make chip CONFIG=config.json}) and the values of this build} \\label{t:chip-config} \\\\\n'
		s += '\\hline \\textbf{Configuration key} & \\textbf{This build} & \\textbf{Meaning / valid values} \\\\ \\hline \\endfirsthead\n'
		s += '\\multicolumn{3}{c}{\\textit{\\tablename\\ \\thetable\\ continued from previous page}} \\\\ \\hline\n'
		s += '\\textbf{Configuration key} & \\textbf{This build} & \\textbf{Meaning / valid values} \\\\ \\hline \\endhead\n'
		s += '\\hline \\multicolumn{3}{c}{\\textit{\\tablename\\ \\thetable\\ continued on next page}} \\\\ \\endfoot \\hline \\endlastfoot\n'
		rowColored = False
		for k in keyOrder:
			v = val(k)
			if v is None and k == 'memory.npuStagingRamSize':
				v = 0
			row = '\\texttt{' + fmttex(k) + '} & ' + fmtval(k, v) + ' & ' + texdesc(doc.get(k, '')) + ' \\\\\n'
			if rowColored:
				row = '\\rowcolor{tablehighlightcolor} ' + row
			rowColored = not rowColored
			s += row
		s = s[:-3] + '\\\\\n\\hline\n\\end{longtable}\n\n'

		drv = rc.get('derived', {})
		derivedRows = [
			('ISA string (march)', '\\texttt{' + fmttex(str(drv.get('isaString'))) + '}', 'Advertised in the read-only \\register{misa} CSR'),
			('Shared-window address width', '\\texttt{' + str(drv.get('sharedWindowAddrWidth')) + '} bits (words)', 'Arbiter/tile word-address width; the window is \\texttt{0x0}\\,--\\,$2^{w+2}-1$'),
			('Shared RAM banks', '\\texttt{' + str(drv.get('sharedRamBanks')) + '}' + ' $\\times$ 16\\,KiB', 'One SRAM macro per bank behind the arbiter'),
			('Extended flash base', '\\texttt{' + fmttex(str(drv.get('flashBaseAddress'))) + '}', 'First address decoded to the SPI-flash XIP path (hart 0 only); strictly the complement of the shared window'),
			('Interrupt vectors', '\\texttt{' + str(drv.get('vectorsCount')) + '}', 'Vectors ' + str(drv.get('clintMsipVector')) + '/' + str(drv.get('clintMtipVector')) + ' are the CLINT software/timer interrupts'),
			('CLINT \\register{MTIME}', '\\texttt{' + fmttex(str((drv.get('clintLayout') or {}).get('mtimeAddress'))) + '}', 'Layout is hart-count-derived: \\register{MSIPx} at \\texttt{0x5000}\\,+\\,4$h$, \\register{MTIMECMPx} from \\texttt{' + fmttex(str((drv.get('clintLayout') or {}).get('mtimecmpBaseAddress'))) + '}'),
			('Boot-loader mailbox rows', '\\texttt{' + fmttex(str(drv.get('bootromLoaderRowBase'))) + '}', 'Tile-loading rows \\{SRC, LEN, ENTRY\\} consumed by the boot ROM'),
			('Stack pointer at reset', '\\texttt{' + fmttex(str(drv.get('stackPointerInit'))) + '}', 'Top of each hart\'s private TCM, growing down'),
			('Peripheral count', '\\texttt{' + str(drv.get('peripheralCount')) + '}', 'Instantiated peripherals (including CLINT/MUTEX/IRQROUTER)'),
		]
		s += '% Derived geometry: computed by generate.py, NOT configurable\n'
		s += '\\begin{longtable}[c]{ l l p{6.6cm} }\n'
		s += '\\caption{Derived geometry of this configuration (computed, not configurable)} \\label{t:chip-config-derived} \\\\\n'
		s += '\\hline \\textbf{Derived value} & \\textbf{This build} & \\textbf{Notes} \\\\ \\hline \\endfirsthead\n'
		s += '\\multicolumn{3}{c}{\\textit{\\tablename\\ \\thetable\\ continued from previous page}} \\\\ \\hline\n'
		s += '\\textbf{Derived value} & \\textbf{This build} & \\textbf{Notes} \\\\ \\hline \\endhead\n'
		s += '\\hline \\multicolumn{3}{c}{\\textit{\\tablename\\ \\thetable\\ continued on next page}} \\\\ \\endfoot \\hline \\endlastfoot\n'
		rowColored = False
		for name, v, note in derivedRows:
			row = name + ' & ' + v + ' & ' + note + ' \\\\\n'
			if rowColored:
				row = '\\rowcolor{tablehighlightcolor} ' + row
			rowColored = not rowColored
			s += row
		s = s[:-3] + '\\\\\n\\hline\n\\end{longtable}\n'

		with open(self.IncludeDirectory + '/ChipConfigurationTable.tex', 'w') as f:
			f.write(s)
		return

	# ------------------------------------------------------------------
	# The top-level block diagram. TWO SHAPES, because the chip has two,
	# and the figure must not tell the wrong one:
	#
	#   * orchestrator OFF (castalia4, every Argus configuration) — N
	#     interchangeable hart tiles in a row over one registered
	#     boundary. This is the historical drawing, kept VERBATIM: it is
	#     the true picture of those chips, and the N > 5 elision path is
	#     what keeps the 18-hart Argus manual honest.
	#   * orchestrator ON (the shipped default since CPR8) — hart 0 is
	#     NOT one more tile. It is soft logic in the always-on centre
	#     band; harts 1..N-1 are hardened macros on switched rails with
	#     their own PWRCR gate bits. Drawing five identical boxes there
	#     asserts a chip that does not exist, so this shape gets its own
	#     drawing: two banded regions (always-on vs gateable), the
	#     registered boundary around the TILES only, and the read-only
	#     TCM apertures drawn as what they are — a shared-window slave
	#     that reaches BACK into the tiles.
	# ------------------------------------------------------------------

	def _SystemBlockSlaves(self, geo, nMtx):
		'''The shared-window slave boxes, as (label, width) pairs, DERIVED —
		   the aperture box comes from McuMpGeometry['tcmWindows'] cross-checked
		   against Gen.SharedWindowSections, never from a literal. Returns
		   (slaves, apertureIndex); apertureIndex is None without apertures.'''
		romKiB = self.Gen.RomSize // 1024
		tcmKiB = self.Gen.RamMemorySlotSize // 1024
		banks = geo['sharedRamBanks']
		slaves = [
			('Boot ROM\\\\ \\texttt{0x0} (' + str(romKiB) + '\\,KiB)\\\\ all harts reset here', 2.9),
			('Peripherals \\texttt{0x4000}\\\\ 16 slots $+$ CLINT\\\\ ' + str(nMtx) + ' mutexes $+$ IRQ router', 3.6),
		]
		if geo['npu']:
			slaves.append(('NPU staging RAM\\\\ \\texttt{0xC000} (16\\,KiB)', 2.9))
		slaves.append(('Shared RAM \\texttt{0x10000}\\\\ ' + str(banks) + ' $\\times$ 16\\,KiB banks', 3.3))

		apertureIndex = None
		windows = self._TcmApertureWindows()
		if windows:
			apertureIndex = len(slaves)
			slaves.append(('TCM apertures \\texttt{' + fmthex(windows[0]) + '}\\\\ '
				+ str(len(windows)) + ' $\\times$ ' + str(tcmKiB) + '\\,KiB, read-only\\\\ hart 0 only', 3.6))
		return slaves, apertureIndex

	def _TcmApertureWindows(self):
		'''The read-only TCM aperture bases, [] when the configuration has none.

		   E17-style: the geometry list (generate.py's tcmWindows, which is what
		   mcu_vhd.py decodes) and the address-space model (SharedWindowSections,
		   which is what the memory-map figure draws) are INDEPENDENT products of
		   the same arithmetic. Any figure that draws the apertures cross-checks
		   them here and raises, so a map change that misses one of the two fails
		   `make generate` instead of shipping a figure that disagrees with the
		   memory map two pages later.'''
		geo = getattr(self.Gen, 'McuMpGeometry', None) or {}
		windows = list(geo.get('tcmWindows') or [])
		sections = [sec for sec in (self.Gen.SharedWindowSections or [])
			if str(sec[0]).startswith('TCM aperture')]
		if [sec[1] for sec in sections] != windows:
			raise Exception('TCM apertures: McuMpGeometry tcmWindows %s do not match the '
				'SharedWindowSections aperture rows %s — the block diagram and the address-space '
				'figure would disagree.' % ([hex(w) for w in windows], [hex(sec[1]) for sec in sections]))
		# 2026-08-16: the aperture SPAN/STRIDE and the TCM SIZE were the same
		# number until memory.tcmSizePerHart dropped to 8 KiB, and this check
		# read RamMemorySlotSize for both. They are now separate quantities --
		# the stride is address space (fixed 0x4000, so the MCU sub-decode keeps
		# its 16 KiB s_addr(15:12) granularity) and the TCM is silicon. Checking
		# the aperture against the TCM size is what wrongly failed the 8 KiB
		# build, so the geometry's own aperture size is the authority here and
		# the TCM relationship is checked SEPARATELY below -- both still checked,
		# neither conflated.
		apertureBytes = geo.get('tcmApertureSize')
		if not apertureBytes:
			raise Exception('McuMpGeometry has no tcmApertureSize -- the aperture figure cannot '
				'be drawn against an unstated stride, and silently assuming the TCM size is the '
				'bug this check exists to catch.')
		tcmBytes = self.Gen.RamMemorySlotSize
		for h, (start, end) in enumerate((sec[1], sec[2]) for sec in sections):
			if end - start + 1 != apertureBytes:
				raise Exception('TCM aperture %d spans 0x%X bytes but the aperture stride is 0x%X'
					% (h, end - start + 1, apertureBytes))
			if start != windows[0] + h * apertureBytes:
				raise Exception('TCM aperture %d is at 0x%X, not the uniform 0x%X + %d*0x%X'
					% (h, start, windows[0], h, apertureBytes))
		# The mirror invariant: a TCM must tile its aperture a whole number of
		# times, or the aperture's last copy is a partial one and the figure's
		# "mirrored N times" caption is false.
		if tcmBytes > apertureBytes or apertureBytes % tcmBytes != 0:
			raise Exception('TCM 0x%X does not tile its 0x%X aperture a whole number of times, '
				'so the aperture mirror is ragged.' % (tcmBytes, apertureBytes))
		return windows

	def GenerateSystemBlockDiagram(self):
		'''include/SystemBlockDiagram.tex — configuration-driven top-level block
		   diagram. Orchestrator configurations get the centre-band/corner-tile
		   drawing; every other configuration gets the uniform-tile row.'''
		geo = getattr(self.Gen, 'McuMpGeometry', None)
		if geo is None:
			# There is no sensible fallback: the flash base, the bank count and
			# the aperture list all come from here, and the placeholder this
			# used to carry ({'shAw': 15, ...}) had been wrong for every shipped
			# configuration since CPR8 — it would have drawn a 0x20000 flash
			# window on a chip whose flash starts at 0x40000.
			raise Exception('SystemBlockDiagram: the configuration has no McuMpGeometry; '
				'generate.py must set it before the TRM is written.')
		nMtx = 0
		for p in self.Gen.Peripherals:
			if p.Name == 'MUTEX':
				nMtx = len(p.Registers)
		if geo.get('orchestrator') and self._TcmApertureWindows():
			s = self._SystemBlockDiagramOrchestrator(geo, nMtx)
		else:
			s = self._SystemBlockDiagramUniform(geo, nMtx)
		self._writeInclude('SystemBlockDiagram.tex', s)
		return

	def _SystemBlockDiagramUniform(self, geo, nMtx):
		'''The historical drawing: N interchangeable hart tiles in a row over one
		   registered boundary, the serializing arbiter, and the shared-window
		   slaves. This is the true picture of every configuration WITHOUT an
		   orchestrator (castalia4, and all three Argus configurations, where the
		   N > 5 elision keeps an 18-hart manual honest).'''
		N = self.Gen.NumHarts
		banks = geo['sharedRamBanks']
		npu = geo['npu']
		flashBase = fmthex(1 << (geo['shAw'] + 2))
		tcmKiB = self.Gen.RamMemorySlotSize // 1024

		# Tiles to draw: all of them up to 5, else 0,1,2,...,N-1 with an ellipsis
		if N <= 5:
			shown = list(range(N))
		else:
			shown = [0, 1, 2, None, N - 1]
		tileW = 3.0
		gap = 0.45
		xs = []
		x = 0.0
		for t in shown:
			w = 1.0 if t is None else tileW
			xs.append((t, x + w / 2.0, w))
			x += w + gap
		totalW = x - gap

		s = '% Generated system block diagram (configuration-driven: numHarts=' + str(N) + ', banks=' + str(banks) + ', npu=' + str(npu) + ')\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, font=\\sffamily\\small},\n'
		s += '\ttile/.style={blk, fill=black!4},\n'
		s += '\tslave/.style={blk, fill=black!8},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left}]\n'

		# Hart tiles
		for t, cx, w in xs:
			if t is None:
				s += '\\node[font=\\sffamily\\Large] at (' + '%.2f' % cx + ', 4.55) {$\\cdots$};\n'
				continue
			label = '\\textbf{hart ' + str(t) + '}\\\\ VestaRV core\\\\ ' + str(tcmKiB) + '\\,KiB TCM'
			extra = ''
			if t == 0:
				extra = '\\\\ \\scriptsize mgmt hart'
			s += '\\node[tile, minimum width=' + '%.2f' % w + 'cm, minimum height=1.9cm] (tile' + str(t) + ') at (' + '%.2f' % cx + ', 4.55) {' + label + extra + '};\n'

		# Registered tile boundary
		s += '\\draw[dashed] (-0.4, 3.30) -- (' + '%.2f' % (totalW + 0.4) + ', 3.30);\n'
		s += '\\node[note, anchor=west] at (' + '%.2f' % (totalW + 0.5) + ', 3.30) {registered tile boundary\\\\ (1 cycle each way)};\n'

		# Arbiter
		s += '\\node[blk, fill=black!15, minimum width=' + '%.2f' % totalW + 'cm, minimum height=0.85cm] (arb) at (' + '%.2f' % (totalW / 2.0) + ', 2.45) {\\textbf{mp\\_arbiter}: serializing round-robin, ' + str(N) + ' masters, grant-locked AMOs};\n'
		for t, cx, w in xs:
			if t is None:
				continue
			s += '\\draw[bus] (' + '%.2f' % cx + ', 3.60) -- (' + '%.2f' % cx + ', 2.88);\n'

		# Shared-window slaves
		slaves, _ = self._SystemBlockSlaves(geo, nMtx)
		sTotal = sum(w for _, w in slaves) + gap * (len(slaves) - 1)
		sx = (totalW - sTotal) / 2.0
		for txt, w in slaves:
			cx = sx + w / 2.0
			s += '\\node[slave, minimum width=' + '%.2f' % w + 'cm, minimum height=1.25cm] at (' + '%.2f' % cx + ', 0.75) {' + txt + '};\n'
			s += '\\draw[bus] (' + '%.2f' % cx + ', 2.02) -- (' + '%.2f' % cx + ', 1.40);\n'
			sx += w + gap

		# Hart 0's private flash path (XIP)
		s += '\\node[blk, dashed, minimum width=2.9cm, minimum height=1.25cm] (flash) at (-2.15, 4.55) {SPI flash (XIP)\\\\ $\\geq$ \\texttt{' + flashBase + '}\\\\ \\scriptsize hart 0 only};\n'
		s += '\\draw[bus, dashed] (flash.east) -- (tile0.west);\n'
		s += '\\end{tikzpicture}\n'
		return s

	def _SystemBlockDiagramOrchestrator(self, geo, nMtx):
		'''The five-core orchestrator chip. Two banded regions say the thing the
		   old uniform row could not: hart 0 is soft, central and always on
		   (generate.py orchestrator=True emits it as entity work.orch_tile, with
		   no pwr_ctrl row and no isolation clamps — MCU.vhd hart0: pd_sleep =>
		   '0', pd_iso_en => '0'), while harts 1..N-1 are copies of ONE hardened
		   hart_tile macro on switched rails, each with its own PWRCR gate bit
		   (PWRGATE_MASK 0x1E at N=5). The registered boundary is drawn around
		   the TILE band only, because that is where it is: hart 0's soft logic
		   sits inside the always-on fabric, not behind a macro boundary.

		   The fifth slave is the read-only TCM aperture band (MCU.vhd:592-656
		   + :3676-3755), and it is the one slave that reaches BACK across the
		   boundary — drawn as one summarising arrow into the tiles' TCM read
		   port, not as five wires.'''
		N = self.Gen.NumHarts
		banks = geo['sharedRamBanks']
		npu = geo['npu']
		flashBase = fmthex(1 << (geo['shAw'] + 2))
		tcmKiB = self.Gen.RamMemorySlotSize // 1024
		windows = self._TcmApertureWindows()

		def P(v):
			return '%.2f' % v

		# Channel tiles are harts 1..N-1. Draw them all up to four, else elide —
		# the same honesty rule the uniform drawing follows.
		tiles = list(range(1, N))
		if len(tiles) > 4:
			shown = [tiles[0], tiles[1], None, tiles[-1]]
		else:
			shown = tiles
		tileW, gap = 2.60, 0.42

		# ---- geometry, in cm (everything below derives from these anchors)
		aX0, aX1 = 0.00, 4.60          # band A: the always-on centre band
		bX0 = 5.10                     # band B: the hardened channel tiles
		x = bX0
		xs = []
		for t in shown:
			w = 0.90 if t is None else tileW
			xs.append((t, x + w / 2.0, w))
			x += w + gap
		bX1 = x - gap

		yTop = 9.00                    # top of both bands
		yBan = 8.05                    # banner strip floor
		yBnd = 4.00                    # band floor == the registered boundary
		yPort0, yPort1 = 7.05, 7.55    # the tiles' TCM read-port strip
		yTile, tileH = 5.75, 2.30      # tile row (4.60 .. 6.90)
		yArb, arbH = 2.85, 0.90        # arbiter bar (2.40 .. 3.30)
		ySlv, slvH = 1.15, 1.40        # slave row (0.45 .. 1.85)
		yH0, h0H = 5.40, 2.30          # hart 0 (4.25 .. 6.55)
		yFls, flsH = 7.35, 0.78        # the flash box (6.96 .. 7.74)
		# riserX (the aperture read-back riser) is NOT derivable from the tile band
		# alone and is computed after the slave row is laid out — see below.

		s = ('% Generated system block diagram: ORCHESTRATOR shape (numHarts=' + str(N)
			+ ', banks=' + str(banks) + ', npu=' + str(npu) + ', apertures=' + str(len(windows)) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small},\n'
		s += '\ttile/.style={blk, fill=black!6},\n'
		s += '\torch/.style={blk, fill=black!12, line width=1.1pt},\n'
		s += '\tslave/.style={blk, fill=black!8},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\tsig/.style={->, >=Stealth, thick},\n'
		s += '\tban/.style={font=\\sffamily\\scriptsize\\bfseries, black!65, align=center},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=center}]\n'

		# ---- the two banded regions, drawn first so everything sits on top
		s += '\\fill[black!4] (' + P(aX0) + ', ' + P(yBnd) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!9] (' + P(bX0 - 0.20) + ', ' + P(yBnd) + ') rectangle (' + P(bX1 + 0.20) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!14] (' + P(aX0) + ', ' + P(yBan) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!20] (' + P(bX0 - 0.20) + ', ' + P(yBan) + ') rectangle (' + P(bX1 + 0.20) + ', ' + P(yTop) + ');\n'
		s += ('\\node[ban, text width=' + P(aX1 - aX0 - 0.30) + 'cm] at (' + P((aX0 + aX1) / 2.0) + ', '
			+ P((yBan + yTop) / 2.0) + ') {the centre band\\\\ always on};\n')
		s += ('\\node[ban, text width=' + P(bX1 - bX0 - 0.30) + 'cm] at (' + P((bX0 + bX1) / 2.0) + ', '
			+ P((yBan + yTop) / 2.0) + ') {' + _numberWord(N - 1) + ' hardened channel tiles\\\\'
			+ ' switched rails, each with its own \\register{PWRCR} gate bit};\n')

		# ---- band A: the flash the orchestrator alone reaches, and hart 0
		s += ('\\node[blk, dashed, minimum width=4.10cm, minimum height=' + P(flsH) + 'cm] (flash) at ('
			+ P((aX0 + aX1) / 2.0) + ', ' + P(yFls) + ') {\\scriptsize external SPI flash (XIP) $\\geq$ \\texttt{' + flashBase + '}};\n')
		s += ('\\node[orch, minimum width=4.20cm, minimum height=' + P(h0H) + 'cm] (h0) at ('
			+ P((aX0 + aX1) / 2.0) + ', ' + P(yH0) + ') {\\textbf{hart 0}: orchestrator\\\\ \\scriptsize soft logic, always on\\\\'
			+ ' \\scriptsize VestaRV core $+$ ' + str(tcmKiB) + '\\,KiB TCM\\\\ \\scriptsize boots the chip, manages it};\n')
		s += '\\draw[sig] (flash.south) -- (h0.north);\n'

		# ---- band B: the tiles, and the read port the apertures come back through
		for t, cx, w in xs:
			if t is None:
				s += '\\node[font=\\sffamily\\Large] at (' + P(cx) + ', ' + P(yTile) + ') {$\\cdots$};\n'
				continue
			s += ('\\node[tile, minimum width=' + P(w) + 'cm, minimum height=' + P(tileH) + 'cm] (t' + str(t)
				+ ') at (' + P(cx) + ', ' + P(yTile) + ') {\\textbf{hart ' + str(t) + '}\\\\ \\scriptsize channel tile\\\\'
				+ ' \\scriptsize VestaRV core $+$\\\\ \\scriptsize ' + str(tcmKiB) + '\\,KiB TCM\\\\ \\scriptsize gateable};\n')
		s += ('\\node[blk, fill=black!18, minimum width=' + P(bX1 - bX0) + 'cm, minimum height=' + P(yPort1 - yPort0)
			+ 'cm, font=\\sffamily\\scriptsize] (port) at (' + P((bX0 + bX1) / 2.0) + ', ' + P((yPort0 + yPort1) / 2.0)
			+ ') {read-only TCM read port on every tile};\n')

		# ---- the registered boundary: around the TILES, and nothing else
		s += '\\draw[dashed, thick] (' + P(bX0 - 0.20) + ', ' + P(yBnd) + ') -- (' + P(bX1 + 0.20) + ', ' + P(yBnd) + ');\n'
		bndX = (xs[0][1] + xs[1][1]) / 2.0 if len(xs) > 1 else (bX0 + bX1) / 2.0
		s += ('\\node[lab, fill=white, inner sep=1.5pt] at (' + P(bndX) + ', ' + P((yBnd + yArb + arbH / 2.0) / 2.0)
			+ ') {registered tile boundary\\\\ (1 cycle each way)};\n')

		# ---- the arbiter, and the five masters on it
		s += ('\\node[blk, fill=black!15, minimum width=' + P(bX1 - aX0) + 'cm, minimum height=' + P(arbH)
			+ 'cm] (arb) at (' + P((aX0 + bX1) / 2.0) + ', ' + P(yArb) + ') {\\textbf{mp\\_arbiter}: serializing round-robin, '
			+ str(N) + ' masters, grant-locked AMOs};\n')
		s += ('\\draw[bus] (' + P((aX0 + aX1) / 2.0) + ', ' + P(yH0 - h0H / 2.0) + ') -- ('
			+ P((aX0 + aX1) / 2.0) + ', ' + P(yArb + arbH / 2.0) + ');\n')
		for t, cx, w in xs:
			if t is None:
				continue
			s += ('\\draw[bus] (' + P(cx) + ', ' + P(yTile - tileH / 2.0) + ') -- (' + P(cx) + ', '
				+ P(yArb + arbH / 2.0) + ');\n')

		# ---- the shared-window slaves
		slaves, apIdx = self._SystemBlockSlaves(geo, nMtx)
		sTotal = sum(w for _, w in slaves) + gap * (len(slaves) - 1)
		sx = (aX0 + bX1 - sTotal) / 2.0
		apCx, apX1 = None, None
		for i, (txt, w) in enumerate(slaves):
			cx = sx + w / 2.0
			s += ('\\node[slave, minimum width=' + P(w) + 'cm, minimum height=' + P(slvH) + 'cm] at ('
				+ P(cx) + ', ' + P(ySlv) + ') {' + txt + '};\n')
			s += ('\\draw[bus] (' + P(cx) + ', ' + P(yArb - arbH / 2.0) + ') -- (' + P(cx) + ', '
				+ P(ySlv + slvH / 2.0) + ');\n')
			if i == apIdx:
				apCx, apX1 = cx, sx + w
			sx += w + gap

		# ---- the aperture's reach: ONE arrow, with a verb. The slave answers
		# a management-hart read by driving the addressed tile's own read port
		# (MCU.vhd tcm_ext_req/addr -> tcm_ext_rdata/done), so the arrow leaves
		# the slave, climbs clear of the fabric and comes back INTO the tiles.
		#
		# THE RISER MUST CLEAR THE WIDEST THING BELOW THE TILES, not just the tile
		# band. The slave row is centred on the band but is WIDER than it (at N=5
		# the aperture box ends at x=17.37 against a band edge of 16.76), so a
		# riser pinned to the band alone (bX1 + 0.74 = 17.50) climbed 0.13 cm off
		# that box's right border — reading, correctly, as a line drawn ON the
		# slave it is supposed to leave. Anchor it to whichever edge is further
		# right and give it a real clearance.
		riserX = max(bX1 + 0.20, apX1) + 0.60
		s += ('\\draw[sig, rounded corners=4pt, line width=1.1pt] (' + P(apX1) + ', ' + P(ySlv) + ') -- ('
			+ P(riserX) + ', ' + P(ySlv) + ') -- (' + P(riserX) + ', ' + P((yPort0 + yPort1) / 2.0) + ') -- ('
			+ P(bX1 + 0.02) + ', ' + P((yPort0 + yPort1) / 2.0) + ');\n')
		s += ('\\node[note, anchor=west] at (' + P(riserX + 0.18) + ', ' + P(yTile - 0.30)
			+ ') {\\textbf{reads back} any hart\'s\\\\ private TCM through that\\\\ tile\'s own read port:\\\\'
			+ ' hart 0 only, never writes,\\\\ and a gated tile reads zero};\n')
		s += '\\end{tikzpicture}\n'
		return s

	# ------------------------------------------------------------------
	# WHOLE-CHIP SYSTEM DIAGRAM (TRM Section \ref{s:config}, Figure
	# \ref{fig:chip-system-diagram}).
	#
	# The system block diagram (GenerateSystemBlockDiagram, no longer printed in
	# the manual) answered one half of "what is this
	# chip": how N harts share one memory system. THIS figure answers the other
	# half — what is ON the die besides the harts, and what of it leaves the
	# package. Its subject is therefore the BUS and the peripherals, so the hart
	# band is compressed into one panel and the peripheral set gets the room.
	#
	# IT IS DRAWN IN THE HOUSE STYLE OF THIS PROJECT'S OWN HAND-MADE BLOCK
	# DIAGRAM (assets/ASIC_block_diagram.png, the Myshkin predecessor): one
	# strong horizontal bus with blocks hanging off it above and below, a
	# stacked box carrying an "x N" badge wherever an instance repeats, the RED
	# chip boundary with the outside world crossing it, and sub-compartments
	# inside the blocks that have parts (the clock generator's oscillators, the
	# interrupt/synchronisation trio, the shared memories).
	#
	# EVERYTHING DRAWN IS DERIVED, because a whole-chip picture is exactly the
	# figure a reader trusts against the configuration table two pages later:
	#   * the boxes are built by BUCKETING Gen.Peripherals, so a dropped second
	#     instance (uart1/spi1/timer1/i2c1) shrinks its box's badge and name
	#     list, and a dropped peripheral removes its box;
	#   * the instance names and counts are those instances';
	#   * the addresses are the generator's memory objects and McuMpGeometry;
	#   * the hart panel follows the orchestrator knob (the same two shapes
	#     GenerateSystemBlockDiagram draws), so ONE ungated figure is true for
	#     every configuration and its \ref never needs a polarity gate;
	#   * the OUTSIDE WORLD is read off the package model's AF0 function names
	#     and pad names — a package that does not bond a flash chip-select gets
	#     no flash box, and one that does not bond electrodes gets no cell.
	#
	# THE E17 ASSERTION: the emitter collects every peripheral instance NAME it
	# actually puts in a box and compares that set against Gen.Peripherals. A
	# peripheral added to generate.py that nobody placed in _CHIP_FIG_BUCKET
	# fails `make chip` instead of quietly vanishing from the chip picture.
	#
	# TWO TYPESETTING RULES THIS DRAWING PAID FOR, both in its first render:
	#   1. A BOX'S HEAD IS ONE NODE, never a title node plus a subtitle node at
	#      a fixed offset below it. The fixed offset assumes the title is one
	#      line; "serial flash memory" in a 2.95 cm box is two, and the subtitle
	#      printed straight through it. Every head here is a single node with
	#      explicit \\ breaks, and the box height is computed from the line
	#      count that node will actually have.
	#   2. NO TEXT ON A WIRE (the AFE figure's lesson, applied here to twelve
	#      more crossings): the pad names live inside the cell under their
	#      stubs, and what sits on a boundary crossing is a solid square, which
	#      is a pad — not a white label box, which reads as a break.
	# ------------------------------------------------------------------

	# Peripheral template -> the drawn box it belongs in. The value is a bucket
	# key from _CHIP_FIG_ABOVE / _CHIP_FIG_BELOW; "above" is the pin-facing half
	# of the chip (everything whose signals leave the die), "below" is the
	# inward-facing half (time, clocks, power, memory, engines).
	_CHIP_FIG_BUCKET = {
		'GPIOx':     'io',
		'SPIx':      'spi',
		'QSPIx':     'spi',
		'UARTx':     'uart',
		'I2Cx':      'i2c',
		'I2CTx':     'i2c',
		'I3Cx':      'i2c',
		'NFCx':      'nfc',
		'OWx':       'ow',
		'TIMERx':    'timer',
		'PWMx':      'timer',
		'RTCx':      'timer',
		'SYSTEM':    'system',
		'PWRCTRL':   'power',
		'CLINT':     'sync',
		'MUTEX':     'sync',
		'IRQROUTER': 'sync',
		'NPU':       'npu',
		'DMAx':      'engine',
		'TRNGx':     'engine',
		'EVFAB':     'engine',
	}
	_CHIP_FIG_ABOVE = ['io', 'spi', 'uart', 'i2c', 'nfc', 'ow', 'afe']
	_CHIP_FIG_BELOW = ['timer', 'system', 'power', 'sync', 'mem', 'npu', 'engine']

	def _chipFigNames(self, names):
		'''"GPIO0--GPIO5" for a contiguous numbered family, else a comma list.
		   Keeps a six-instance box one line wide instead of six.'''
		ms = [re.match(r'^([A-Za-z0-9]*?)(\d+)$', n) for n in names]
		if len(names) > 2 and all(ms) and len(set(m.group(1) for m in ms)) == 1:
			nums = sorted(int(m.group(2)) for m in ms)
			if nums == list(range(nums[0], nums[-1] + 1)):
				stem = ms[0].group(1)
				return fmttex(stem + str(nums[0])) + '--' + fmttex(stem + str(nums[-1]))
		# A mixed family (I2C0, I2C1, I3C0, I2CT0 on the wound configuration)
		# gets an EXPLICIT break every second name: the head's reserved height is
		# computed from the \\ count, so a line left to wrap on its own would
		# push the rest of the box's contents through its bottom border.
		out = ''
		for i, n in enumerate(names):
			if i:
				out += ',\\\\ ' if (i % 2) == 0 else ', '
			out += fmttex(n)
		return out

	@staticmethod
	def _chipFigLines(tex):
		return 0 if not tex else 1 + tex.count('\\\\')

	@staticmethod
	def _chipFigWidth(tex, unit=0.125):
		'''A deliberately crude width, in cm, for the widest line of a
		   \\scriptsize sans block. It exists for one reason: the height of every
		   box in this drawing is a LINE COUNT, and a line the box is too narrow
		   to hold does not clip, it WRAPS — adding a row nobody reserved and
		   spilling the box. MEASURED on the six-column band of the debug
		   configuration, where "behind the registered" and "owns EIS, reads
		   every site" each wrapped and pushed a line through the box floor.'''
		if not tex:
			return 0.0
		best = 0.0
		for line in tex.split('\\\\'):
			bold = ('textbf' in line) or ('bfseries' in line)
			t = re.sub(r'\\[a-zA-Z]+', '', line)
			for ch in '{}$\\':
				t = t.replace(ch, '')
			best = max(best, len(t.strip()) * (unit * 1.12 if bold else unit))
		return best

	def _ChipSystemBoxes(self):
		'''Build the drawn boxes (and their outside-world partners) from the
		   configuration. Returns (aboveBoxes, belowBoxes).'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None)
		if geo is None:
			raise Exception('ChipSystemDiagram: the configuration has no McuMpGeometry; '
				'generate.py must set it before the TRM is written.')
		pkg = gen.Package
		funcs = set(p.FuncName for p in pkg.Pins if p.FuncName is not None)
		padNames = set(p.Name for p in pkg.Pins)

		def padKey(p):
			m = re.match(r'^P(\d+)\.(\d+)$', p.Name)
			return (int(m.group(1)), int(m.group(2))) if m else (99, 99)
		gpioPads = sorted([p for p in pkg.Pins if p.Gpio is not None], key=padKey)

		buckets = {}
		for p in gen.Peripherals:
			t = p.Template.NameTemplate
			if t not in self._CHIP_FIG_BUCKET:
				raise Exception('ChipSystemDiagram: peripheral template "' + str(t) + '" (instance '
					+ str(p.Name) + ') has no place in the whole-chip figure. Add it to '
					'_CHIP_FIG_BUCKET and decide which side of the bus it hangs off — otherwise '
					'the picture would silently omit a peripheral this configuration carries.')
			buckets.setdefault(self._CHIP_FIG_BUCKET[t], []).append(p)
		for k in buckets:
			buckets[k].sort(key=lambda p: p.BaseAddress)

		drawn = set()

		def claim(key):
			ps = buckets.get(key, [])
			drawn.update(p.Name for p in ps)
			return ps

		def box(key, title, sub=None, note=None, rows=None, stack=1, w=2.75, ext=None,
				brief=None, parts=None):
			# `brief' and `parts' are the FLAT companion figure's view of the same
			# derived content, carried here so both whole-chip figures read one
			# bucketing pass: `brief' is the single subtitle line that figure
			# draws instead of the portrait one's sub+note+compartments, and
			# `parts' splits a box the flat figure draws as separate chips
			# (the memories) into (title, brief) pairs. The portrait figure
			# ignores both, so adding them cannot move one of its bytes.
			return {'key': key, 'title': title, 'sub': sub, 'note': note,
				'rows': rows or [], 'stack': stack, 'w': w, 'ext': ext,
				'brief': brief, 'parts': parts or []}

		def ext(title, sub=None, w=2.75, stubs=None):
			return {'title': title, 'sub': sub, 'w': w, 'stubs': stubs}

		def kiB(n):
			return str(n // 1024) + '\\,KiB'

		above, below = {}, {}

		# ---- above the bus: everything whose signals leave the die ---------
		ps = claim('io')
		if ps:
			e = None
			if gpioPads:
				e = ext('GPIO pins', str(len(gpioPads)) + ' bonded pads\\\\ '
					+ fmttex(gpioPads[0].Name) + '--' + fmttex(gpioPads[-1].Name), w=3.05)
			above['io'] = box('io', 'GPIO', self._chipFigNames([p.Name for p in ps]),
				str(len(ps[0].Pins)) + ' pins per port\\\\ AF0--AF7 planes',
				stack=len(ps), w=3.05, ext=e,
				brief=str(len(ps)) + ' ports $\\times$ ' + str(len(ps[0].Pins)) + ' pins')

		ps = claim('spi')
		if ps:
			note = 'full-duplex masters'
			e = None
			if 'CS_FLASH' in funcs:
				note = 'SPI0 boots the chip\\\\ XIP \\texttt{' + fmthex(1 << (geo['shAw'] + 2)) + '} and up'
				e = ext('serial flash', fmttex('CS/SCK') + '\\\\ ' + fmttex('MOSI/MISO'), w=3.05)
			above['spi'] = box('spi', 'SPI', self._chipFigNames([p.Name for p in ps]),
				note, stack=len(ps), w=3.05, ext=e,
				brief=('boots the chip' if 'CS_FLASH' in funcs else 'full-duplex masters'))

		ps = claim('uart')
		if ps:
			e = ext('host terminal', fmttex('TX0/RX0'), w=2.85) if 'TX0' in funcs else None
			above['uart'] = box('uart', 'UART', self._chipFigNames([p.Name for p in ps]),
				'asynchronous serial\\\\ boot console', stack=len(ps), w=2.85, ext=e,
				brief='asynchronous serial')

		ps = claim('i2c')
		if ps:
			e = ext('two-wire bus', fmttex('SDA/SCL'), w=2.85) if 'SDA0' in funcs else None
			hasTarget = any(p.Template.NameTemplate == 'I2CTx' for p in ps)
			above['i2c'] = box('i2c', 'I\\textsuperscript{2}C', self._chipFigNames([p.Name for p in ps]),
				'open-drain masters' + ('\\\\ $+$ autonomous target' if hasTarget else ''),
				stack=len(ps), w=2.85, ext=e,
				brief='open-drain masters' + (' $+$ target' if hasTarget else ''))

		ps = claim('nfc')
		if ps:
			above['nfc'] = box('nfc', 'NFC', self._chipFigNames([p.Name for p in ps]),
				'digital protocol core', stack=len(ps), w=2.70,
				ext=ext('NFC front end', '\\textit{off-die}', w=2.70),
				brief='digital protocol core')

		ps = claim('ow')
		if ps:
			above['ow'] = box('ow', '1-Wire', self._chipFigNames([p.Name for p in ps]),
				'open-drain master', stack=len(ps), w=2.45,
				ext=ext('1-Wire devices', fmttex('DQ'), w=2.45),
				brief='open-drain master')

		# The AFE sites are DOC SUB-SLOT blocks, not peripherals (they sit at
		# sub-slot bases a whole-slot arbiter slave is forbidden from), so they
		# come from their own model and never enter the peripheral assertion.
		blocks = getattr(gen, 'DocSubSlotBlocks', None) or []
		if blocks:
			sites = [b['name'] for b in blocks if b['name'].startswith('AFE')]
			rest = [b['name'] for b in blocks if not b['name'].startswith('AFE')]
			label = self._chipFigNames(sites)
			if rest:
				label += ' $+$ ' + ', '.join(fmttex(n) for n in rest)
			stubs = [e for e in ('WE', 'RE', 'CE')
				if all((e + '_' + str(i)) in padNames for i in range(len(sites)))]
			e = ext('electrode cell', '$\\times$' + str(len(sites)) + ' measurement sites',
				w=3.40, stubs=stubs) if stubs else None
			above['afe'] = box('afe', 'analog front end', label,
				'register sites\\\\ \\textit{analog IP not integrated}', w=3.40, ext=e,
				brief='$\\times$' + str(len(sites)) + ' register sites')
			# The per-site ownership the drawing needs to put each site in the
			# column of the hart that owns it. Taken from the SAME block model
			# the AFE chapter and Figure \ref{fig:afe-system-diagram} read, so a
			# re-assignment of an owner cannot move one figure and not the other.
			above['afe']['sites'] = [(b['name'], b['base'], b['ownerHart'],
				b.get('gate') or '') for b in blocks]

		# ---- below the bus: time, clocks, power, memory, engines -----------
		ps = claim('timer')
		if ps:
			below['timer'] = box('timer', 'timers', self._chipFigNames([p.Name for p in ps]), None,
				rows=[['capture / compare'], ['relocatable pins']], stack=len(ps), w=2.85,
				brief='capture / compare')

		ps = claim('system')
		if ps:
			bits = set()
			for p in ps:
				for r in p.Registers:
					for bf in r.BitFields:
						if bf.Name:
							bits.add(bf.Name)

			def has(b):
				return any(x.endswith(b) for x in bits)
			dco = [n for n, b in (('DCO0', 'DCO0ON'), ('DCO1', 'DCO1ON')) if has(b)]
			xtal = [n for n, b in (('LFXT', 'LFXTOFF'), ('HFXT', 'HFXTOFF')) if has(b)]
			rows = []
			if dco:
				rows.append([' / '.join(dco) + '\\\\ \\textit{internal oscillators}'])
			if xtal:
				rows.append([' / '.join(xtal) + '\\\\ \\textit{crystal oscillators}'])
			rows.append(['watchdog', 'CRC16'])
			e = None
			pins = [n for n in ('LFXT', 'HFXT') if n in funcs]
			if pins:
				e = ext('crystals', ', '.join(fmttex(n) for n in pins), w=3.20)
			below['system'] = box('system', 'SYSTEM', 'clock, power, reset\\\\ \\texttt{'
				+ fmthex(ps[0].BaseAddress) + '}', None, rows=rows, w=3.20, ext=e,
				brief='clocks, reset, watchdog')

		ps = claim('power')
		if ps:
			e = None
			rst = [n for n in ('RESETN', 'POC') if n in padNames]
			if rst:
				e = ext('external reset', ', '.join(fmttex(n) for n in rst), w=2.85)
			below['power'] = box('power', 'PWRCTRL', '\\texttt{' + fmthex(ps[0].BaseAddress) + '}',
				None, rows=[['tile power gating'], ['isolation clamps']], w=2.85, ext=e,
				brief='tile power gating')

		ps = claim('sync')
		if ps:
			rows = []
			for p in ps:
				tail = {'MUTEX': '\\\\ \\textit{' + str(len(p.Registers)) + ' hardware mutexes}',
					'CLINT': '\\\\ \\textit{msip mailboxes, mtime}',
					'IRQROUTER': '\\\\ \\textit{per-hart IRQ rows}'}.get(p.Name, '')
				rows.append([fmttex(p.Name) + ' \\texttt{' + fmthex(p.BaseAddress) + '}' + tail])
			below['sync'] = box('sync', 'inter-hart', 'synchronisation', None, rows=rows, w=3.35,
				brief=self._chipFigNames([p.Name for p in ps]))

		# The shared memories are not peripherals; they come straight off the
		# generator's memory objects and McuMpGeometry.
		rows = [['boot ROM \\texttt{' + fmthex(gen.RomStartAddress) + '}\\\\ \\textit{'
			+ kiB(gen.RomSize) + ', reset vector}']]
		# The same three memories the rows above carry, as the (title, brief)
		# chips the flat figure draws instead — one derivation, two drawings.
		memParts = [('boot ROM', kiB(gen.RomSize))]
		shared = [sec for sec in (gen.SharedWindowSections or []) if sec[0] == 'Shared RAM']
		if shared:
			rows.append(['shared RAM \\texttt{' + fmthex(shared[0][1]) + '}\\\\ \\textit{'
				+ str(geo['sharedRamBanks']) + ' $\\times$ ' + kiB(16384) + ' banks}'])
			memParts.append(('shared RAM',
				str(geo['sharedRamBanks']) + ' $\\times$ ' + kiB(16384)))
		windows = self._TcmApertureWindows()
		if windows:
			rows.append(['TCM apertures \\texttt{' + fmthex(windows[0]) + '}\\\\ \\textit{'
				+ str(len(windows)) + ' $\\times$ ' + kiB(gen.RamMemorySlotSize) + ', read-only}'])
			# NOT a `parts' compartment: the FLAT figure draws the TCM inside the
			# hart box it belongs to, and an aperture is a WINDOW onto that TCM,
			# not a third memory sitting behind the bar. It is drawn there, in
			# the tile's own compartment, and the memory box on that figure's
			# one rank is the two memories that really are behind the bar.
		below['mem'] = box('mem', 'shared memory', 'behind the bar', None, rows=rows, w=3.45,
			brief='behind the bar', parts=memParts)

		ps = claim('npu')
		if ps:
			rows = [['registers \\texttt{' + fmthex(ps[0].BaseAddress) + '}']]
			stage = [sec for sec in (gen.SharedWindowSections or []) if sec[0] == 'NPU staging RAM']
			if stage:
				rows.append(['staging RAM \\texttt{' + fmthex(stage[0][1]) + '}\\\\ \\textit{'
					+ kiB(1 + stage[0][2] - stage[0][1]) + ' vector store}'])
			below['npu'] = box('npu', 'NPU', 'inference engine', None, rows=rows, w=2.85,
				brief='inference engine')

		ps = claim('engine')
		if ps:
			rows = [[fmttex(p.Name) + ' \\texttt{' + fmthex(p.BaseAddress) + '}'] for p in ps]
			below['engine'] = box('engine', 'engines', 'autonomous', None, rows=rows, w=2.75,
				brief=self._chipFigNames([p.Name for p in ps]))

		# ---- E17: the drawn instance set must BE the configuration's --------
		configured = set(p.Name for p in gen.Peripherals)
		if drawn != configured:
			raise Exception('ChipSystemDiagram: the figure draws peripheral instances '
				+ str(sorted(drawn)) + ' but this configuration carries ' + str(sorted(configured))
				+ ' — the whole-chip picture and the peripheral table would disagree.')

		return ([above[k] for k in self._CHIP_FIG_ABOVE if k in above],
			[below[k] for k in self._CHIP_FIG_BELOW if k in below])

	def _ChipSystemMasters(self, brief=False):
		'''The master band, shared by BOTH whole-chip figures so a change to who
		   drives the bus cannot move one of them and not the other.

		   One column per hart where the configuration has few enough of them to
		   draw honestly; otherwise the stacked x N idiom, because an 18-hart
		   band of eighteen boxes is not a drawing, it is a wall.

		   `brief' trims every note to ONE line. The portrait figure takes the
		   full three; the flat companion's whole subject is a shorter drawing,
		   and a band of five three-line notes is 0.74 cm of height on the one
		   axis that figure is trying to spend nothing on.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None)
		N = gen.NumHarts
		orch = bool(geo.get('orchestrator'))
		tcmKiB = gen.RamMemorySlotSize // 1024
		masters = []
		# Three lines, not four: the fourth was "behind the registered / tile
		# boundary", whose 21 characters set the minimum width of every hart
		# column in the band -- and on a six-column band that minimum is what
		# the whole drawing ends up scaled by.
		tileNote = ('VestaRV core $+$\\\\ ' + str(tcmKiB) + '\\,KiB private TCM,'
			'\\\\ registered boundary')
		orchNote = ('soft logic, always on\\\\ boots and manages the chip'
			'\\\\ owns the XIP flash path')
		dmaNote, dbgNote = ('moves data\\\\ without a hart',
			'halts and resumes\\\\ harts, plants code')
		if brief:
			# ONE line each, and the shortest true one: the flat figure's columns
			# are as wide as their longest unbroken line, and five columns pay
			# for it. What a tile IS lives in the portrait figure and in the
			# text; what this band has to carry is who the masters are.
			tileNote = str(tcmKiB) + '\\,KiB private TCM'
			orchNote = 'boots and manages the chip'
			dmaNote, dbgNote = 'moves data without a hart', 'halts and resumes harts'
		if orch:
			masters.append({'title': 'hart 0', 'sub': 'orchestrator', 'harts': [0], 'stack': 1,
				'note': orchNote, 'weight': 1.30})
			if N <= 7:
				for h in range(1, N):
					masters.append({'title': 'hart ' + str(h), 'sub': 'channel tile',
						'harts': [h], 'stack': 1, 'note': tileNote, 'weight': 1.0})
			else:
				masters.append({'title': 'hart 1--' + str(N - 1), 'sub': 'channel tile',
					'harts': [], 'stack': N - 1, 'note': tileNote, 'weight': 2.4})
		elif N <= 6:
			for h in range(N):
				masters.append({'title': 'hart ' + str(h), 'sub': 'hart tile', 'harts': [h],
					'stack': 1, 'note': tileNote, 'weight': 1.0})
		else:
			masters.append({'title': 'hart 0--' + str(N - 1), 'sub': 'hart tile', 'harts': [],
				'stack': N, 'note': tileNote, 'weight': 3.2})
		if geo.get('dma'):
			masters.append({'title': 'DMA0', 'sub': 'engine master', 'harts': [], 'stack': 1,
				'note': dmaNote, 'weight': 0.90})
		if geo.get('debug'):
			masters.append({'title': 'dm0', 'sub': 'debug module', 'harts': [], 'stack': 1,
				'note': dbgNote, 'weight': 0.90})
		# The FLAT companion draws a hart as the two compartments the RTL builds
		# it from -- the VestaRV core and its private TCM -- instead of naming
		# the TCM in a note under it. The size is carried here, off the same
		# `tcmKiB' the note is written from, so ONE derivation feeds both
		# whole-chip figures and a TCM resize cannot move one and not the other.
		# The portrait figure never reads the key.
		for m in masters:
			m['tcm'] = (str(tcmKiB) + '\\,KiB TCM') if m['title'].startswith('hart') else None
		return masters

	def _ChipSystemAnalogRow(self, allBoxes, columns, orch, N):
		'''Is this configuration the shape an analog OWNERSHIP row asserts — an
		   orchestrator, one site per channel hart, and a column of its own for
		   every owner? Returns (afeBox or None, {ownerHart: site}); anything
		   else returns (None, {}) and the caller degrades to the compact box,
		   so neither whole-chip figure lies about ownership.

		   E17: the gate the figures print is re-derived here from the owner and
		   checked against the gate the block model carries, so an ownership
		   change that the drawings do not cover fails the build instead of
		   shipping figures that disagree with the table on the facing page.'''
		afe = None
		for b in allBoxes:
			if b['key'] == 'afe':
				afe = b
		if afe is None or not afe.get('sites'):
			return None, {}
		owners = [st[2] for st in afe['sites']]
		if not (orch and len(set(owners)) == len(owners)
				and set(owners) <= set(columns) and set(range(1, N)) <= set(owners)):
			return None, {}
		siteOf = dict((st[2], st) for st in afe['sites'])
		for h in sorted(siteOf):
			want = ('s\\_master = 0' if h == 0
				else 's\\_master = ' + str(h) + ' or s\\_master = 0')
			got = siteOf[h][3]
			if got and got != want:
				raise Exception('ChipSystemDiagram: block ' + str(siteOf[h][0])
					+ ' is owned by hart ' + str(h) + ' but its gate reads "' + str(got)
					+ '", not "' + want + '" — the ownership row would print a gate this '
					'configuration does not implement.')
		return afe, siteOf

	def GenerateChipSystemDiagram(self):
		'''include/ChipSystemDiagram.tex — the whole chip on one PORTRAIT page:
		   the masters in a band across the top (the arrangement of the system
		   block diagram and of the AFE figure), the arbiter
		   drawn as the bus bar under them, the analog ownership row directly
		   below that bar with each site in the column of the hart that owns it,
		   the rest of the peripherals on the shelves below, and the outside
		   world crossing the red package boundary at the top and the bottom.

		   WHY THE COLUMN AND NOT AN ARROW. Ownership here is not a wire: every
		   access is a shared-window transaction through the bar, and what makes
		   AFE0 hart 1's is a comparison against the arbiter's granted-master
		   index inside the slave. So the drawing says it the way the AFE figure
		   says it, and for the same reason — the site sits directly under its
		   owner, the owner's box names it, and the gate is printed inside the
		   site — and hart 0's reach is ONE arrow with a verb, because the
		   privilege is not four more wires, it is one comparison that every
		   gate on the row makes.

		   THE BUS IS ONE BAR. Three shelves cannot all touch a single bar
		   without a tap crossing a box, so the bar is drawn with a trunk down
		   the left margin and a rib along the shelf pair it cannot reach: one
		   connected grey figure, labelled once as one bar.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None)
		aboveBoxes, belowBoxes = self._ChipSystemBoxes()
		N = gen.NumHarts
		orch = bool(geo.get('orchestrator'))
		tcmKiB = gen.RamMemorySlotSize // 1024
		L = self._chipFigLines

		def P(v):
			return '%.2f' % v

		# ---- type metrics, in cm. Every height below is a LINE COUNT times a
		# baseline, never a guess: a TikZ node whose contents outgrow its box
		# does not clip, it spills, and a spilt line in a drawing this dense
		# costs the reader the figure.
		hTitle, hLine, pad = 0.44, 0.37, 0.13
		gap, cross, clear = 0.36, 0.80, 0.34
		stackStep, maxShadow = 0.15, 3
		riser, ribH, barH, trunkW = 0.54, 0.42, 1.02, 0.34
		xReach, xTrunk = 0.30, 0.68           # the two things that live in the
		xInset = xTrunk + trunkW + 0.24       # left margin, and what they cost
		xEdge = 0.26                          # margin for the shelves below them

		def headH(b):
			return pad + hTitle + hLine * (L(b.get('sub')) + L(b.get('note'))) + pad

		def rowsH(b):
			return sum(pad + hLine * max(L(c) for c in row) + pad for row in b['rows'])

		def boxH(b):
			return headH(b) + rowsH(b)

		def shelfW(bs):
			if not bs:
				return 0.0
			w = sum(b['w'] for b in bs) + gap * (len(bs) - 1)
			return w + (stackStep * (maxShadow - 1) if any(b['stack'] > 1 for b in bs) else 0.0)

		# ---- the master band ------------------------------------------------
		masters = self._ChipSystemMasters()
		columns = dict((m['harts'][0], m) for m in masters if m['harts'])

		# ---- the analog ownership row ---------------------------------------
		# Drawn as its own row under the bar ONLY when this configuration is the
		# shape the row asserts: an orchestrator, one site per channel hart, and
		# a column of its own for every owner. Anything else keeps the compact
		# shelf box, so the drawing degrades instead of lying about ownership.
		allBoxes = aboveBoxes + belowBoxes
		afeRow, siteOf = self._ChipSystemAnalogRow(allBoxes, columns, orch, N)
		if afeRow is not None:
			for h in sorted(siteOf):
				m = columns[h]
				if h == 0:
					m['note'] += ('\\\\ \\textbf{owns ' + fmttex(siteOf[h][0])
						+ ', reads every site}')
				else:
					m['note'] += '\\\\ \\textbf{owns ' + fmttex(siteOf[h][0]) + '}'

		# ---- the shelves ----------------------------------------------------
		# Everything whose signals leave the die goes on the shelf that touches
		# the boundary (one boundary crossing per block, all at one depth); what
		# is left goes on the shelves above it, five to a shelf.
		rest = [b for b in allBoxes if b is not afeRow]
		extB = [b for b in rest if b['ext']]
		plainB = [b for b in rest if not b['ext']]
		shelves = []
		if afeRow is not None:
			shelves.append({'kind': 'afe', 'boxes': []})
		for i in range(0, len(plainB), 5):
			shelves.append({'kind': 'plain', 'boxes': plainB[i:i + 5]})
		shelves.append({'kind': 'ext', 'boxes': extB})

		# Which grey bar each shelf taps. The first shelf taps the main bar from
		# below; the rest are paired around a rib, so no tap ever crosses a box.
		shelves[0]['bar'] = ('main', 0, 'above')
		i, nRib = 1, 0
		while i < len(shelves):
			if i + 1 < len(shelves):
				shelves[i]['bar'] = ('rib', nRib, 'below')
				shelves[i + 1]['bar'] = ('rib', nRib, 'above')
				i += 2
			else:
				shelves[i]['bar'] = ('rib', nRib, 'above')
				i += 1
			nRib += 1

		# ---- widths ---------------------------------------------------------
		laneR = 2.20 if afeRow is not None else 0.0
		maxCol = 5.00
		for m in masters:
			m['min'] = min(maxCol, 0.24 + max(
				self._chipFigWidth(m['title'], 0.135), self._chipFigWidth(m['sub']),
				self._chipFigWidth(m['note'])))
		bandMin = sum(m['min'] for m in masters) + gap * (len(masters) - 1)
		W = max([shelfW(extB) + 2 * xEdge, bandMin + xInset + xEdge + laneR]
			+ [shelfW(sh['boxes']) + xInset + xEdge for sh in shelves if sh['kind'] == 'plain'])
		xIn0, xIn1 = xInset, W - xEdge               # the trunk-clear inset span
		xTop1 = W - xEdge - laneR                    # band / ownership-row span

		# ---- heights --------------------------------------------------------
		hMaster = max(pad + hTitle + hLine * (L(m['sub']) + L(m['note'])) + pad for m in masters)
		mShadow = stackStep * (maxShadow - 1) if any(m['stack'] > 1 for m in masters) else 0.0
		hAfeHead = pad + hTitle + hLine * 2 + pad
		hAfeCell = pad + hLine * 3 + pad
		for sh in shelves:
			sh['h'] = ((hAfeHead + hAfeCell) if sh['kind'] == 'afe'
				else max([boxH(b) for b in sh['boxes']] or [1.40]))
		hExt = max([pad + hTitle + hLine * L(b['ext'].get('sub')) + pad
			for b in extB if not b['ext'].get('stubs')] or [0.90])
		hStub = hExt + 0.78
		hExtRow = max([hStub if b['ext'].get('stubs') else hExt for b in extB] or [0.90])
		cell = afeRow['ext'] if (afeRow is not None and afeRow['ext']) else None
		hCell = (pad + hTitle + hLine * L(cell.get('sub')) + pad + 0.78) if cell else 0.0

		ribYs = {}
		y = 0.0
		yCellT = y
		if cell:
			y -= hCell + cross
		yRedT = y
		y -= clear + mShadow
		yBandT = y
		y -= hMaster + 0.34
		yBarT = y
		y -= barH
		yBarB = y
		for sh in shelves:
			kind, idx, side = sh['bar']
			if kind == 'main':
				y -= clear if sh['kind'] == 'afe' else riser
			elif side == 'above':
				if idx in ribYs:
					y -= riser
				else:
					y -= clear
					ribYs[idx] = y
					y -= ribH + riser
			else:
				y -= clear
			sh['yT'] = y
			y -= sh['h']
			if kind == 'rib' and side == 'below':
				y -= riser
				ribYs[idx] = y
				y -= ribH
		yRedB = y - clear
		yExtT = yRedB - cross

		# ---- emission -------------------------------------------------------
		s = ('% Generated whole-chip system diagram (portrait; harts=' + str(N)
			+ ', orchestrator=' + str(orch) + ', ownershipRow=' + str(afeRow is not None)
			+ ', shelves=' + str([[b['key'] for b in sh['boxes']] for sh in shelves]) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\thd/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt, anchor=north},\n'
		s += '\tbc/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\tbadge/.style={font=\\sffamily\\small\\bfseries, align=center, inner sep=1pt},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\treach/.style={->, >=Stealth, line width=1.3pt},\n'
		s += '\tredlab/.style={font=\\sffamily\\small\\bfseries, red!70!black, align=left}]\n'

		def frame(cx, yTop, w, h, fill, opts='thick'):
			return ('\\draw[' + opts + ', fill=' + fill + '] (' + P(cx - w / 2.0) + ', '
				+ P(yTop - h) + ') rectangle (' + P(cx + w / 2.0) + ', ' + P(yTop) + ');\n')

		def head(cx, yTop, w, title, sub, note):
			tex = '{\\small\\bfseries ' + title + '}'
			for extra in (sub, note):
				if extra:
					tex += '\\\\[1pt] ' + extra
			return ('\\node[hd, text width=' + P(w - 0.20) + 'cm] at (' + P(cx) + ', '
				+ P(yTop - pad) + ') {' + tex + '};\n')

		def shadows(cx, yTop, w, h, n):
			out = ''
			for k in range(min(n, maxShadow) - 1, 0, -1):
				d = stackStep * k
				out += frame(cx + d, yTop + d, w, h, 'white')
			return out

		def drawBox(b, yTop, h, fill):
			cx, w = b['cx'], b['w']
			out = shadows(cx, yTop, w, h, b['stack'])
			out += frame(cx, yTop, w, h, fill)
			# The shelf is one height for every box on it (a ragged shelf reads
			# as an accident), so the height a short box does not need is given
			# BACK to its compartments — or, with no compartments, to the space
			# above and below its head.
			slack = h - boxH(b)
			if not b['rows']:
				out += head(cx, yTop - slack / 2.0, w, b['title'], b['sub'], b['note'])
				return out
			out += head(cx, yTop, w, b['title'], b['sub'], b['note'])
			share = slack / float(len(b['rows']))
			yy = yTop - headH(b)
			for row in b['rows']:
				hRow = pad + hLine * max(L(c) for c in row) + pad + share
				out += ('\\draw[semithick] (' + P(cx - w / 2.0) + ', ' + P(yy) + ') -- ('
					+ P(cx + w / 2.0) + ', ' + P(yy) + ');\n')
				cw = w / float(len(row))
				for j, c in enumerate(row):
					x0 = cx - w / 2.0 + j * cw
					out += ('\\node[bc, text width=' + P(cw - 0.18) + 'cm] at ('
						+ P(x0 + cw / 2.0) + ', ' + P(yy - hRow / 2.0) + ') {' + c + '};\n')
					if j > 0:
						out += ('\\draw[semithick] (' + P(x0) + ', ' + P(yy) + ') -- (' + P(x0)
							+ ', ' + P(yy - hRow) + ');\n')
				yy -= hRow
			return out

		# ---- the red package boundary, drawn first --------------------------
		s += ('\\draw[red!75!black, line width=1.2pt] (0.00, ' + P(yRedB) + ') rectangle ('
			+ P(W) + ', ' + P(yRedT) + ');\n')
		s += ('\\node[redlab, anchor=south west] at (0.00, ' + P(yRedT + 0.10)
			+ ') {chip boundary};\n')

		# ---- the master band ------------------------------------------------
		# Every column gets at least the width its longest line needs; what is
		# left over is shared by weight, and no column grows past maxCol — an
		# eighteen-hart configuration has two boxes in this band, and stretched
		# to the full width they are a hand's breadth of white with four words
		# in them. Whatever the cap leaves over, the band is centred in.
		avail = (xTop1 - xIn0) - gap * (len(masters) - 1)
		wsum = sum(m['weight'] for m in masters)
		spare = avail - sum(m['min'] for m in masters)
		for m in masters:
			m['w'] = min(maxCol, m['min'] + max(0.0, spare) * m['weight'] / wsum)
		x = xIn0 + max(0.0, (avail - sum(m['w'] for m in masters))) / 2.0
		for m in masters:
			m['cx'] = x + m['w'] / 2.0
			m['tx'] = m['cx'] - (0.22 * m['w'] if m['stack'] > 1 else 0.0)
			x += m['w'] + gap
		for m in masters:
			s += shadows(m['cx'], yBandT, m['w'], hMaster, m['stack'])
			s += frame(m['cx'], yBandT, m['w'], hMaster, 'black!8', 'thick, rounded corners=2pt')
			s += head(m['cx'], yBandT, m['w'], m['title'], m['sub'], m['note'])
			if m['stack'] > 1:
				s += ('\\node[badge, anchor=east] at (' + P(m['cx'] - m['w'] / 2.0 - 0.10) + ', '
					+ P(yBandT - hMaster / 2.0) + ') {$\\times$' + str(m['stack']) + '};\n')
			s += ('\\draw[bus] (' + P(m['tx']) + ', ' + P(yBandT - hMaster) + ') -- ('
				+ P(m['tx']) + ', ' + P(yBarT) + ');\n')

		# ---- THE BUS: one bar, a trunk down the margin, a rib per shelf pair -
		yTrunkB = min([yBarB] + [v - ribH for v in ribYs.values()])
		s += ('\\draw[thick, fill=black!15] (' + P(xTrunk) + ', ' + P(yTrunkB) + ') rectangle ('
			+ P(xTrunk + trunkW) + ', ' + P(yBarB) + ');\n')
		s += ('\\draw[thick, fill=black!15] (' + P(xTrunk) + ', ' + P(yBarB) + ') rectangle ('
			+ P(xTop1) + ', ' + P(yBarT) + ');\n')
		s += ('\\node[bc, text width=' + P(xTop1 - xTrunk - 0.40) + 'cm] at ('
			+ P((xTrunk + xTop1) / 2.0) + ', ' + P(yBarB + barH / 2.0)
			+ ') {{\\small\\bfseries mp\\_arbiter} \\quad one shared-window transaction at a time'
			' \\quad round-robin \\quad grant-locked AMOs\\\\ \\textit{every master reaches the '
			'whole shared window, and only through the bar}};\n')
		for k in sorted(ribYs):
			yr = ribYs[k]
			s += ('\\draw[thick, fill=black!15] (' + P(xTrunk) + ', ' + P(yr - ribH)
				+ ') rectangle (' + P(xIn1) + ', ' + P(yr) + ');\n')
			s += ('\\node[bc, font=\\sffamily\\scriptsize\\itshape] at ('
				+ P((xTrunk + xIn1) / 2.0) + ', ' + P(yr - ribH / 2.0)
				+ ') {the same bar, run along the shelves it cannot touch};\n')

		def barEdge(sh):
			kind, idx, side = sh['bar']
			if kind == 'main':
				return yBarB, 1
			return (ribYs[idx] - ribH, 1) if side == 'above' else (ribYs[idx], -1)

		# ---- the shelves ----------------------------------------------------
		def layout(bs, x0, x1):
			# Justified, up to a cap: a four-box shelf centred at its natural
			# width leaves a hand's width of nothing at each end of a drawing
			# that has no room to waste, and a shelf spread past the cap stops
			# reading as one shelf.
			g = gap
			if len(bs) > 1:
				g += max(0.0, min(((x1 - x0) - shelfW(bs)) / (len(bs) - 1), 0.85))
			x = x0 + ((x1 - x0) - (shelfW(bs) + (g - gap) * (len(bs) - 1))) / 2.0
			for b in bs:
				b['cx'] = x + b['w'] / 2.0
				# The bus tap and the boundary crossing leave the FRONT box, left
				# of the stack's shadows, so no wire is drawn over a stack.
				b['tx'] = b['cx'] - (0.25 * b['w'] if b['stack'] > 1 else 0.0)
				x += b['w'] + g

		for sh in shelves:
			if sh['kind'] == 'ext':
				layout(sh['boxes'], xEdge, W - xEdge)
			elif sh['boxes']:
				layout(sh['boxes'], xIn0, xIn1)

		for sh in shelves:
			if sh['kind'] == 'afe':
				continue
			yEdge, up = barEdge(sh)
			for b in sh['boxes']:
				s += drawBox(b, sh['yT'], sh['h'], 'black!5')
				y0 = sh['yT'] if up > 0 else sh['yT'] - sh['h']
				s += ('\\draw[bus] (' + P(b['tx']) + ', ' + P(y0) + ') -- (' + P(b['tx']) + ', '
					+ P(yEdge) + ');\n')
				if b['stack'] > 1:
					s += ('\\node[badge, anchor=west] at (' + P(b['tx'] + 0.12) + ', '
						+ P((y0 + yEdge) / 2.0) + ') {$\\times$' + str(b['stack']) + '};\n')

		# ---- the ownership row ----------------------------------------------
		xA0 = xA1 = 0.0
		if afeRow is not None:
			cols = sorted(siteOf)
			xA0 = columns[cols[0]]['cx'] - columns[cols[0]]['w'] / 2.0
			xA1 = columns[cols[-1]]['cx'] + columns[cols[-1]]['w'] / 2.0
			yA = shelves[0]['yT']
			s += ('\\draw[thick, fill=black!5] (' + P(xA0) + ', ' + P(yA - hAfeHead - hAfeCell)
				+ ') rectangle (' + P(xA1) + ', ' + P(yA) + ');\n')
			s += head((xA0 + xA1) / 2.0, yA, xA1 - xA0, 'analog front end',
				'one register site per hart, in the column of the hart that owns it',
				'\\textit{analog IP not integrated; the index under each site is the master '
				'it admits --- its own hart, or hart 0}')
			s += ('\\draw[semithick] (' + P(xA0) + ', ' + P(yA - hAfeHead) + ') -- ('
				+ P(xA1) + ', ' + P(yA - hAfeHead) + ');\n')
			edges = [xA0]
			for j in range(len(cols) - 1):
				edges.append((columns[cols[j]]['cx'] + columns[cols[j + 1]]['cx']) / 2.0)
			edges.append(xA1)
			for j, h in enumerate(cols):
				nm, base, owner, _gate = siteOf[h]
				cx = columns[h]['cx']
				if j:
					s += ('\\draw[semithick] (' + P(edges[j]) + ', ' + P(yA - hAfeHead) + ') -- ('
						+ P(edges[j]) + ', ' + P(yA - hAfeHead - hAfeCell) + ');\n')
				s += ('\\node[bc, text width=' + P(edges[j + 1] - edges[j] - 0.20) + 'cm] at ('
					+ P(cx) + ', ' + P(yA - hAfeHead - hAfeCell / 2.0) + ') {\\textbf{'
					+ fmttex(nm) + '} site\\\\ \\texttt{' + fmthex(base) + '}\\\\ '
					+ '\\texttt{s\\_master} = ' + str(h)
					+ (' \\emph{only}' if h == 0 else ' \\emph{or} 0') + '};\n')
				s += ('\\draw[bus] (' + P(cx) + ', ' + P(yBarB) + ') -- (' + P(cx) + ', '
					+ P(yA) + ');\n')
			# Hart 0's reach: ONE arrow with a verb, down the margin the trunk
			# does not use, into the row it opens.
			yMid = yA - hAfeHead / 2.0 - 0.10
			s += ('\\draw[reach] (' + P(columns[0]['cx'] - columns[0]['w'] / 2.0) + ', '
				+ P(yBandT - hMaster / 2.0) + ') -- (' + P(xReach) + ', '
				+ P(yBandT - hMaster / 2.0) + ') -- (' + P(xReach) + ', ' + P(yMid) + ') -- ('
				+ P(xA0) + ', ' + P(yMid) + ');\n')

		# ---- the outside world, below the boundary --------------------------
		def drawExt(b, yFromBox):
			'''The outside-world partner and the wire that crosses the boundary.
			   The wire is UNBROKEN and carries a solid pad square where it meets
			   the red line: a square on a wire is a pad, a white label box on a
			   wire is an open circuit.'''
			e = b['ext']
			stubs = e.get('stubs')
			h = hStub if stubs else hExt
			# The partner sits under the peripheral's CENTRE, not under its tap.
			# A stacked peripheral taps left of its own centre, and partners
			# centred on that tap both hung off the left edge of the figure (the
			# width of which every other box then paid for) and OVERLAPPED their
			# neighbour, because the shelf's boxes do not overlap but their taps
			# are not evenly spaced. The wire still leaves the tap, and lands on
			# the partner: the offset is a quarter of a box width, never half.
			cxE = min(max(b['cx'], e['w'] / 2.0), W - e['w'] / 2.0)
			out = frame(cxE, yExtT, e['w'], h, 'black!3')
			out += head(cxE, yExtT, e['w'], e['title'], e['sub'], None)
			if stubs:
				n = len(stubs)
				pitch = min(0.95, (e['w'] - 0.55) / (n - 1)) if n > 1 else 0.0
				yStub = yExtT - h + 0.30
				for k, nm in enumerate(stubs):
					xk = cxE + (k - (n - 1) / 2.0) * pitch
					out += ('\\draw[semithick] (' + P(xk) + ', ' + P(yStub) + ') -- (' + P(xk)
						+ ', ' + P(yFromBox) + ');\n')
					out += ('\\draw[line width=1.2pt] (' + P(xk - 0.16) + ', ' + P(yStub)
						+ ') -- (' + P(xk + 0.16) + ', ' + P(yStub) + ');\n')
					out += ('\\node[bc, anchor=south, inner sep=1.5pt] at (' + P(xk) + ', '
						+ P(yStub + 0.05) + ') {\\texttt{' + fmttex(nm) + '}};\n')
					out += ('\\fill[red!70!black] (' + P(xk - 0.07) + ', ' + P(yRedB - 0.07)
						+ ') rectangle (' + P(xk + 0.07) + ', ' + P(yRedB + 0.07) + ');\n')
				return out
			out += ('\\draw[bus] (' + P(b['tx']) + ', ' + P(yFromBox) + ') -- (' + P(b['tx'])
				+ ', ' + P(yExtT) + ');\n')
			out += ('\\fill[red!70!black] (' + P(b['tx'] - 0.07) + ', ' + P(yRedB - 0.07)
				+ ') rectangle (' + P(b['tx'] + 0.07) + ', ' + P(yRedB + 0.07) + ');\n')
			return out

		for sh in shelves:
			if sh['kind'] != 'ext':
				continue
			for b in sh['boxes']:
				if b['ext']:
					s += drawExt(b, sh['yT'] - sh['h'])

		# ---- the electrode cell, above the boundary -------------------------
		# It leaves the die at the TOP because the row it belongs to is at the
		# top: the ownership row has to sit under the harts, and a pad group
		# dragged the height of the drawing to reach the bottom band would be
		# eleven centimetres of wire for no reader's benefit.
		if cell:
			stubs = cell.get('stubs') or []
			n = max(1, len(stubs))
			pitch = 0.55
			cxCell = min(W - xEdge - laneR / 2.0 - 0.10, W - cell['w'] / 2.0)
			s += frame(cxCell, yCellT, cell['w'], hCell, 'black!3')
			s += head(cxCell, yCellT, cell['w'], cell['title'], cell['sub'], None)
			yStub = yCellT - hCell + 0.30
			yA = shelves[0]['yT']
			for k, nm in enumerate(stubs):
				xk = cxCell + (k - (n - 1) / 2.0) * pitch
				yk = yA - hAfeHead * (k + 1.0) / (n + 1.0)
				s += ('\\draw[semithick] (' + P(xk) + ', ' + P(yStub) + ') -- (' + P(xk) + ', '
					+ P(yk) + ') -- (' + P(xA1) + ', ' + P(yk) + ');\n')
				s += ('\\draw[line width=1.2pt] (' + P(xk - 0.16) + ', ' + P(yStub) + ') -- ('
					+ P(xk + 0.16) + ', ' + P(yStub) + ');\n')
				s += ('\\node[bc, font=\\sffamily\\tiny, anchor=south, inner sep=1.5pt] at ('
					+ P(xk) + ', ' + P(yStub + 0.04) + ') {\\texttt{' + fmttex(nm) + '}};\n')
				s += ('\\fill[red!70!black] (' + P(xk - 0.07) + ', ' + P(yRedT - 0.07)
					+ ') rectangle (' + P(xk + 0.07) + ', ' + P(yRedT + 0.07) + ');\n')

		s += '\\end{tikzpicture}\n'
		self._writeInclude('ChipSystemDiagram.tex', s)
		return

	def GenerateChipSystemFlatDiagram(self):
		'''include/ChipSystemFlatDiagram.tex — the FLAT companion to Figure
		   \\ref{fig:chip-system-diagram}: the same configuration, the same
		   derived content, drawn as a datasheet block diagram instead of a
		   portrait page. Five things differ, and each is the point:

		   ONE BAR, ONE RANK. The portrait figure runs the bus down the left
		   margin and back along a rib, because three shelves of tall boxes
		   cannot all touch one horizontal bar. Here every peripheral is cut to
		   a name and one line and hangs off ONE rank below the bar, each box
		   tapping it straight up. There is no trunk, no rib, no second bar
		   segment and no second rank whose taps have to find a lane: the two
		   ranks the first cut needed cost 2.7 cm of height and a bisection
		   search for a width at which every rank-2 tap could stay straight.

		   THE TILE IS DRAWN AS THE TILE. A hart box is split into the two
		   compartments the RTL builds it from — the VestaRV core and its
		   private TCM — instead of naming the TCM in a note and drawing its
		   shared-window apertures three metres away on the memory rank. That
		   is where the TCM physically is, and it takes the memory rank down to
		   the two memories that really are behind the bar.

		   THE SITE IS A HAT ON ITS HART. Each analog site is its own box,
		   sitting directly on the box of the hart that owns it and exactly as
		   wide, with air between channels: the pair reads as one channel. The
		   arrow between the two is thin, short and unlabelled, and it IS what
		   makes a site its hart's — the caption says
		   \\emph{owns} once, where five printings of it were five labels in the
		   one strip this row keeps clear. Hart 0's privilege is one comparison
		   against the granted-master index, so it is ONE heavy rail under the
		   row with a drop into every site — visibly reaching all of them, in
		   the room the old banner band used to take, and drawn with a real gap
		   wherever a column's ownership arrow passes through it so that no
		   crossing can be read as a junction. Those two marks are the WHOLE of the
		   access story, and now the only of it. Two things have come OUT of this
		   row by USER DIRECTIVE and both went for the same reason. The first was
		   the arbiter's own grey strip, run the length of the row behind the site
		   boxes with one drop down the right lane into the bar: only hart 0 or
		   the site's own hart may read a site and both are drawn already, so the
		   strip was buying the fact that the sites are ordinary arbiter slaves
		   reached only through the bar, which is true of every block in the
		   drawing and which the caption carries for nothing. The second
		   (2026-08-16) is the register-level GATE itself, which used to be
		   printed inside every site box (\\texttt{s\\_master} = its own hart
		   \\emph{or} 0) and again up the margin of hart 0's rail: five printings
		   of one signal name, in the one strip this row keeps clear, saying what
		   the two marks already draw. A site box is its NAME now, the identifier
		   belongs to the caption and to the analog chapter, and \\texttt{s\\_master}
		   appears nowhere in this drawing.

		   THE RANK IS GROUPED BY TYPE. Ten boxes in a line is a list; the same
		   ten under \\emph{Memory}, \\emph{Comms}, \\emph{Timing \\& Sync} and the
		   rest is an organisation. The idiom is the user's own Myshkin block
		   diagram's: the blocks of one kind stand together under a type label,
		   with a thin outline round them. The label is set BIG (user directive,
		   2026-08-16: \\large italic grey, bigger than the block titles under it,
		   because a heading is read before the things it heads) and in Title
		   Case, and where it will not fit its lane on one line the layout sets it
		   on two rather than the list shortening the English again. The outline
		   goes round EVERY type of more than one box, and a GLUED box of several
		   compartments counts as more than one (same directive): the emitter used
		   to give those types the label alone, on the argument that a rectangle
		   2 mm outside a rectangle is a doubled border rather than a group, and
		   at the bigger heading size the unframed types read as captions floating
		   over the rank while the framed ones read as groups. The outlines are cut
		   with a REAL GAP at every bus tap, every partner wire and the harvested
		   supply rail where it rises back through one, the same rule hart 0's
		   rail is drawn by. The FRAME is what gets dealt out along the rank now, so the
		   pin-facing types still spread their partners under themselves. What a
		   frame may never do is imply a block or drop one, and the emitter
		   asserts exactly that and nothing more — every frame member is a drawn
		   block and every drawn block is in one frame — because a frame is
		   decoration and decoration does not get to make claims.

		   THE DEBUG PATH IS DRAWN, AND DRAWN SOLID. The Debug
		   Module is a bus MASTER — Figure \\ref{fig:debug-stack-diagram} draws it
		   reading and writing memory as one more master on this bar — so it
		   belongs in the master band, at the end of it, with the five JTAG pins
		   coming down out of an off-chip probe across the boundary into it. On
		   a debug-enabled build the column carries the two derived names (dtm0,
		   the TAP and its transport; dm0, the Debug Module). It used to go DASHED
		   with the knob off — the analog-IP idiom, drawn and not in this build —
		   under a polarity ASSERTED against the knob, and by USER DIRECTIVE
		   (2026-08-16) it is SOLID in every configuration instead, the default
		   manual included. The assertion is not dropped, it is turned round: the
		   emitter now proves the column is solid EVERYWHERE and that the
		   knob-derived fact is carried in words, by the \\emph{debug builds only}
		   clause printed in the box, which the emitter also refuses to ship
		   missing. Whether those pins reach a BALL is a second and separate fact,
		   and a package one (the QFN-64 has no room for them; the LQFP-100 takes
		   five of its NC balls): the probe used to be dashed for that too, so
		   that clause is now printed whenever it is true rather than only on a
		   debug-enabled build.

		   NFC IS TWO PATHS, AND THE SECOND ONE IS THE SUPPLY. The digital core
		   reads the tag through the bar like any peripheral and its RF front end
		   is off-die, so the antenna is an off-chip partner — that half this
		   figure already had. The half it did not is that on a field-powered
		   board the harvested field is what RUNS the chip, and it does not
		   arrive through NFC0: \\texttt{peripherals.fieldPower} wires PWRCTRL's
		   supervision inputs to real pads (\\texttt{PGOOD} and the harvested-boot
		   strap, plain-GPIO direct taps readable before any software runs) and
		   the boot gate they hold is ANDed into every hart's outer reset. So the
		   supply is drawn as what it is — a board-level RAIL in the off-chip
		   band, heavier and greyer than any signal in the drawing, running from
		   the antenna to under PWRCTRL and crossing the boundary there, cut with
		   a real gap at every partner wire it passes — and never as a wire out
		   of the NFC block. The RAIL is the one stroke in this drawing that still
		   changes with the configuration: it is dashed where the chip is not run
		   off the field, and it has a third condition of its own besides the
		   block and the knob, because the two pads are GPIO46/47, which the QFN
		   packages do not bring out at all. The NFC BLOCK and its antenna do not:
		   by USER DIRECTIVE (2026-08-16, the directive that made the debug column
		   solid) they are drawn solid in every configuration, and what a build
		   really contains is the caption's to say. The rail's own label was
		   trimmed to what the rail IS, `harvested field power', in the same pass:
		   the pads it lands on are a PWRCTRL fact, they are in the pin table and
		   in the caption, and on a whole-chip overview they were two lines of
		   \\texttt{} in the one band the rail runs through.

		   THE BAR SAYS WHAT IT IS. It used to be labelled \\texttt{mp\\_arbiter},
		   which is the VHDL entity's name and not a name at all to a reader
		   meeting this chip on page 17. The bar now carries the English — the
		   multi-hart shared-bus arbiter — over the three facts a whole-chip
		   overview owes a reader who is about to assume a crossbar; the
		   identifier is explained once, in the caption, where the reader who
		   wants to grep the RTL will find it.

		   THE ROW IS THE CHANNELS, AND THE ENGINE IS NOT DRAWN. Every column of
		   this row is one channel — a three-electrode cell, the site that
		   measures it, the hart that owns it. The shared EIS sweep engine's
		   register site is hart 0's, and it is NOT one: it brings out no
		   electrodes, it is nobody's channel, and by user directive (2026-08-16)
		   it is left out of this overview altogether, because the central-engine
		   topology is being reworked to a per-channel EIS and this figure is not
		   to assert a shape that is on its way out. A cut of this figure drew
		   that engine's site as hart 0's hat with a dashed trapezoid selecting
		   one channel's electrodes into it; both are gone. The omission is
		   CURATION and is named as such in the emitter, checked by name against
		   the block model's own site list (a site that vanishes silently is a
		   site the figure forgot), and it changes nothing else: hart 0 keeps its
		   column and its reach over every site drawn, and the as-built EIS
		   register stub is still documented by the CQ analog chapter and still
		   drawn by the portrait figure.

		   ELECTRODES, DRAWN. Each site brings out its own WE/RE/CE triple
		   straight up out of its own box, on unbroken vertical wires that cross
		   the red boundary and carry a pad square where they cross it; the pad
		   name is printed inside the cell, above its stub, never on the wire (a
		   white label box on a wire reads as an open circuit — the AFE figure
		   was rejected for exactly that, and this reuses its cleaned pattern).
		   Every off-chip partner below the boundary is reached the same way: a
		   straight vertical wire down from the tap, entering the partner's top
		   edge off-centre where the partner had to be nudged aside, because a
		   jogged wire in a clear lane buys nothing and reads as a detour.

		   COUNT, TWICE. A block instantiated N times says $\\times N$ in its
		   title AND wears N offset squares: the numeral is the count exactly,
		   the squares are the count at a glance, and the two are read by
		   different passes over the page. Every square in a stack is the SAME
		   box — same fill, same border as the one in front — because N copies of
		   one peripheral is what it is counting; the white back copies of the
		   first cut drew a shadow, not a count. The one thing squares cannot do is sit
		   behind a GLUED compartment — a single stack behind a box whose
		   compartments have different instance counts is a lie with no way to
		   qualify it — so a multi-instance block is never glued, and the case
		   that proves it (config/penta\\_wound.json's five serial blocks, at 1,
		   2, 3 and 4 instances) is a build error rather than a drawing.

		   IT DEGRADES INSTEAD OF LYING. The electrode/site row is drawn only
		   where the configuration is the shape it asserts (the shared
		   _ChipSystemAnalogRow test: an orchestrator, one site per channel
		   hart, a column for every owner, and bonded pads). Anything else gets
		   a uniform hart band — still split core/TCM — and the analog block, if
		   any, back on the rank as an ordinary peripheral. The figure is
		   therefore emitted and \\input UNGATED in both polarities, and every
		   \\ref to it resolves in both.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None)
		aboveBoxes, belowBoxes = self._ChipSystemBoxes()
		allBoxes = aboveBoxes + belowBoxes
		N = gen.NumHarts
		orch = bool(geo.get('orchestrator'))
		L = self._chipFigLines
		padNames = set(p.Name for p in gen.Package.Pins)

		def P(v):
			return '%.2f' % v

		# THE STACKED-SHADOW EXPERIMENT, SECOND CUT. A block instantiated N times
		# is drawn as N offset squares AND says $\times N$ in its title: the
		# squares are the quantity at a glance, the numeral is the quantity
		# exactly, and neither is the other's spare. The first cut of this figure
		# dropped the squares because at stackStep 0.15 cm they read as a printing
		# slur and because the separate $\times N$ BADGE node collided with the
		# bar above the rank. Both faults were the badge's and the step's, not the
		# idiom's: the count now lives in the title (so `badge' emits nothing) and
		# the step is 0.22 cm, which is 1.8 mm on the page at this figure's own
		# scale. The one thing squares cannot do is sit behind a GLUED
		# compartment, so a multi-instance block is never glued (see `specs').
		SHADOWS = True
		# Whether the serial blocks are GLUED into one compartmented box or stand
		# as one slim box each. RENDERED BOTH WAYS (see the report): glued costs
		# 1.1 cm less width but cannot carry a stack, and a single stack behind a
		# box whose three compartments have three different instance counts is a
		# lie the drawing has no way to qualify. Split.
		SERIAL_SPLIT = True

		# ---- type metrics, in cm. Every height is a LINE COUNT times a
		# baseline, never a guess: a TikZ node whose contents outgrow its box
		# does not clip, it spills.
		hTitle, hLine, pad = 0.44, 0.37, 0.13
		xEdge, gapM = 0.30, 0.42
		gapRank, gapExt = 0.62, 0.18
		# The rank's two gaps, since it now has two: `gapIn' between the boxes
		# INSIDE one type frame (tight -- proximity is half of what says they
		# belong together) and the justified remainder BETWEEN frames, which is
		# never allowed below `gapRank'.
		gapIn = 0.22
		# The type frame: how far its outline stands off the boxes it encloses,
		# where its top edge sits above them (clear of a stacked box's squares,
		# which climb 0.40 cm), and how wide a gap it opens for every wire that
		# crosses it.
		frmPad, frmTop, frmBot, frmGap = 0.18, 0.78, 0.20, 0.13
		# The offset squares: 0.12 cm across, 0.20 cm up. The x step is the SMALL
		# one on purpose -- horizontally a stack eats the gap to the next block on a
		# justified rank, vertically it eats the 0.52 cm riser, which is dead space.
		stackDx, stackDy, maxShadow = 0.12, 0.20, 3
		# Two risers, not one: the band drops onto the bar in 0.52 cm, but the
		# rank has to get its type frames and their labels in under the bar as
		# well, and a label that shares a lane with the bus taps is a label on a
		# wire.
		barH, riser, riserR = 1.02, 0.52, 1.30
		hCmp = 0.24                    # the core|TCM compartment strip, plus its lines
		xReach = 0.42                  # hart 0's reach, up the left margin

		# _chipFigWidth's flat 0.125 cm/char was calibrated on the PORTRAIT
		# figure, every line of which is broken by hand. Nothing here is: a chip
		# carries one unbroken subtitle, and a subtitle that wraps does not clip,
		# it prints the extra line through the box floor. MEASURED across two
		# renders: "boots and manages the chip" needs ~0.145/char, but
		# "CLINT, MUTEX, IRQROUTER" needs ~0.185 -- ALL-CAPS instance names are
		# half again as wide as the lower-case prose the flat rule was fitted to,
		# and every one of this figure's derived name lists is all-caps. So the
		# rule here is per-character and knows three classes.
		def TWs(t, bold=1.0):
			best = 0.0
			for line in (t or '').split('\\\\'):
				u = re.sub(r'\\[a-zA-Z]+', '', line)
				for ch in '{}$\\':
					u = u.replace(ch, '')
				w = 0.0
				for ch in u.strip():
					w += (0.185 if (ch.isupper() or ch.isdigit())
						else 0.085 if ch in ' .,:;/|!\'ilj' else 0.145)
				best = max(best, w * bold)
			return best

		# A title is \small\bfseries and a body line is \scriptsize: 9 pt against
		# 7 pt, bold against roman. 1.40, measured -- at 1.10 "host terminal" and
		# "two-wire bus" both wrapped their own titles.
		tBold = 1.40
		# ...and a type heading is now \large italic against that same \scriptsize
		# body: 12 pt against 7, which TWs knows nothing about. Every width TWs
		# returns for a heading is therefore scaled by this, and the ONLY thing
		# those widths are used for is deciding which tap-free interval a heading
		# fits in -- so an under-estimate here does not make the drawing slightly
		# tight, it puts a white label box on a bus wire. 12/7 = 1.71, and the
		# extra 0.06 is the italic's own overhang plus the node's inner sep.
		tLab = 1.77

		def wOf(title, sub, minw=1.95, maxw=4.80):
			return min(maxw, max(minw, 0.36 + max(TWs(title, tBold), TWs(sub))))

		# ---- the masters, and the analog row's eligibility -------------------
		masters = self._ChipSystemMasters(brief=True)
		columns = dict((m['harts'][0], m) for m in masters if m['harts'])

		# ---- THE DEBUG PATH, AND WHY IT IS DASHED HERE -----------------------
		# The Debug Module is a BUS MASTER (Figure \ref{fig:debug-stack-diagram}:
		# "reads and writes memory as one more master on the bus"), so its place
		# in this drawing is the master band, not the rank -- and the shared
		# master pass already puts it there on a debug-enabled build. What this
		# figure adds is the rest of the path a reader looks for: the five JTAG
		# pins crossing the boundary from an off-chip probe.
		#
		# THE POLARITY IS ASSERTED, NOT ASSUMED. `debug' is one knob (D2/D3:
		# OFF emits no ports, no dtm0, no dm0, no arbiter master), so the column
		# is SOLID exactly where the configuration builds it and DASHED --- the
		# analog-IP idiom, "drawn, and not in this build" --- exactly where it
		# does not. Where the shared pass and the knob disagree the build fails
		# rather than shipping a picture of the wrong chip.
		dbgOn = bool(geo.get('debug'))
		dmCols = [m for m in masters if m['title'] == 'dm0']
		if bool(dmCols) != dbgOn:
			raise Exception('ChipSystemFlatDiagram: this configuration has debug='
				+ str(dbgOn) + ' but the master band ' + ('carries' if dmCols else 'carries no')
				+ ' dm0 column — the debug block would be drawn '
				+ ('solid' if dmCols else 'dashed') + ' against the knob.')
		# The five pins, TRANSCRIBED from generate.py:202-203 (the D3 port group
		# tck/tms/tdi/tdo/trstn, the last entity port group the debug knob adds)
		# and checked against the package model: a pad ring that bonds SOME of
		# them is a pad ring this drawing does not understand.
		JTAG_PINS = ('TCK', 'TMS', 'TDI', 'TDO', 'TRSTn')
		bondedJ = [n for n in JTAG_PINS if n in padNames]
		if bondedJ and len(bondedJ) != len(JTAG_PINS):
			raise Exception('ChipSystemFlatDiagram: this package model bonds ' + str(bondedJ)
				+ ' of the JTAG port ' + str(list(JTAG_PINS)) + ' — the debug figure would draw '
				'a probe on a port this package brings out only in part.')
		jtagBonded = len(bondedJ) == len(JTAG_PINS)
		# ONE clause, and it names the thing that is actually missing. On a
		# build without the knob nothing behind the pins exists at all; on a
		# build WITH it, whether the pins reach a ball is a PACKAGE fact (the
		# QFN-64 has no room for them; the LQFP-100 takes five of its NC balls),
		# and the clause printed in the box says so.
		if not dbgOn:
			dbgM = {'title': 'JTAG TAP', 'sub': 'debug module',
				'note': '\\textit{debug builds only}', 'harts': [], 'stack': 1, 'weight': 0.90,
				'tcm': None}
			masters.append(dbgM)
		else:
			# The derived names, both of them: the knob builds dtm0 (the TAP and
			# its transport) beside dm0 (the Debug Module), and the five pins
			# land on the first while the bus tap belongs to the second.
			dbgM = dmCols[0]
			dbgM['title'] = 'dtm0 \\& dm0'
			dbgM['sub'] = 'TAP \\& debug module'
		dbgM['debug'] = True
		# ---- USER DIRECTIVE, 2026-08-16: THE DEBUG COLUMN IS DRAWN SOLID ----
		# The dashed-optional idiom (drawn, and not built in THIS configuration)
		# used to own this column, and the emitter ASSERTED the stroke against the
		# `debug' knob so the drawing could not go solid on a chip with no debug
		# module in it. The USER has chosen the SOLID presentation for the JTAG /
		# debug column in every configuration, the default manual included, so
		# that polarity assertion is retired here. What replaces it is not
		# nothing: the column is asserted SOLID everywhere, and where the knob is
		# off the configuration-derived fact is carried in WORDS instead of in the
		# stroke, by the `debug builds only' clause printed in the box and by the
		# caption's own sentence. The check below is what keeps that clause from
		# going missing, because with the stroke retired it is the only thing left
		# saying this build has no debug module in it.
		dbgM['dash'] = False
		probeSub = ('\\texttt{TCK} \\texttt{TMS} \\texttt{TDI}\\\\ \\texttt{TDO} \\texttt{TRSTn}')
		# Whether the five pins reach a BALL is the second, separate, package
		# fact, and the probe stroke used to carry it too. Same directive, same
		# consequence: it is printed whenever it is true, not only on a
		# debug-enabled build.
		if not jtagBonded:
			probeSub += '\\\\ \\textit{no ball on this package}'
		dbgCols = [m for m in masters if m.get('debug')]
		if len(dbgCols) != 1 or dbgCols[0]['dash']:
			raise Exception('ChipSystemFlatDiagram: the debug column set ' + str(dbgCols)
				+ ' is not exactly one SOLID column (user directive 2026-08-16).')
		if not dbgOn and 'debug builds only' not in str(dbgM.get('note') or ''):
			raise Exception('ChipSystemFlatDiagram: debug=' + str(dbgOn) + ' and the solid JTAG '
				'column carries no "debug builds only" clause. With the dashed stroke retired by '
				'user directive that clause is the only thing in the drawing that says this '
				'configuration builds no debug module.')
		afeRow, siteOf = self._ChipSystemAnalogRow(allBoxes, columns, orch, N)
		stubs = list((afeRow['ext'].get('stubs') or []) if (afeRow and afeRow['ext']) else [])
		if not stubs:
			# No bonded electrode pads: there is no top row to draw, so the AFE
			# block goes back on the rank like any other peripheral.
			afeRow, siteOf = None, {}
		# AIR BETWEEN THE CHANNELS. A site is drawn as a HAT on its own hart --
		# same width, directly above it -- so what separates one channel from
		# the next has to be a gap wide enough to read as one. The band is
		# justified across a width the rank has already fixed, so this gap costs
		# the drawing nothing: it comes out of column width the columns do not
		# need.
		if afeRow is not None:
			gapM = 0.85

		# The electrode-bearing sites, in pad-suffix order, and the E17 check
		# over the twelve names this drawing prints: every one of them is
		# re-derived from the site list and looked up in the package model, so a
		# pad-ring change the figure does not cover fails `make generate`.
		padOf = {}
		if afeRow is not None:
			afeNames = [st[0] for st in afeRow['sites'] if st[0].startswith('AFE')]
			idxOf = dict((nm, i) for i, nm in enumerate(afeNames))
			for h, st in siteOf.items():
				if st[0] not in idxOf:
					continue
				names = [e + '_' + str(idxOf[st[0]]) for e in stubs]
				missing = [n for n in names if n not in padNames]
				if missing:
					raise Exception('ChipSystemFlatDiagram: the figure would draw electrode pads '
						+ str(missing) + ' for site ' + str(st[0]) + ', which this package model '
						'does not bond.')
				padOf[h] = names
			drawn = sorted(sum(padOf.values(), []))
			expect = sorted(e + '_' + str(i) for i in range(len(afeNames)) for e in stubs)
			if drawn != expect:
				raise Exception('ChipSystemFlatDiagram: the drawn electrode set ' + str(drawn)
					+ ' is not this configuration\'s ' + str(expect))

		# ---- THE ONE SITE THIS FIGURE DOES NOT DRAW --------------------------
		# CURATION, and named as such. The row this figure draws is the CHANNELS:
		# a three-electrode cell, the site that measures it and the hart that owns
		# it, one column each. The hart-0 site is not one of those -- it is the
		# register stub of the shared EIS sweep engine -- and by USER DIRECTIVE
		# (2026-08-16) it is left out of this overview entirely, because the
		# central-engine topology it belongs to is being reworked to a per-channel
		# EIS and this figure is not to assert the shape that is on its way out.
		# Nothing else moves: hart 0 keeps its column and its reach over every
		# site it may read, the as-built EIS register stub is still documented by
		# the CQ analog chapter (Section \ref{s:cqanalog}) and still drawn by the
		# portrait figure, and an earlier cut's shared engine + analog multiplexer
		# (a dashed trapezoid selecting one channel's electrodes) is gone with it.
		#
		# The exclusion is EXPLICIT, not a side effect of some other test: it is
		# this list, it is checked against the electrode set below, and the drawn
		# set is still proved against the block model's own site list further
		# down (see `reached'). A site that is dropped silently is a site the
		# figure forgot.
		cols = sorted(siteOf)
		omitOwners = [h for h in cols if h == 0]
		omitSites = [siteOf[h][0] for h in omitOwners]
		drawnCols = [h for h in cols if h not in omitOwners]
		for h in omitOwners:
			if h in padOf:
				raise Exception('ChipSystemFlatDiagram: the curated omission would drop site '
					+ str(siteOf[h][0]) + ', which brings out the bonded electrode group '
					+ str(padOf[h]) + ' -- this figure omits the shared engine\'s register '
					'site, never a channel.')
		if afeRow is not None and not drawnCols:
			# Every site this configuration has is the one that is omitted, so
			# there is no channel row left to draw at all: the AFE block goes back
			# on the rank as an ordinary peripheral, which is the same degrade a
			# configuration with no bonded electrode pads takes.
			afeRow, siteOf, padOf = None, {}, {}
			cols, omitOwners, omitSites, drawnCols = [], [], [], []

		# ---- the hart box, split into the two things a tile IS ---------------
		# The TCM stops being a note under the hart's name and becomes the
		# compartment beside its core, which is what the RTL builds (hart_tile =
		# VestaRV + one private TCM behind a registered boundary). E17: the size
		# in that compartment is re-derived here and checked against the same
		# generator field the memory map is built from, so a TCM resize that the
		# drawing does not cover fails `make generate`.
		wantTcm = str(gen.RamMemorySlotSize // 1024) + '\\,KiB TCM'
		# An aperture is a WINDOW onto that TCM, not a memory of its own, so it
		# leaves the rank (where the portrait figure's memory box, and this
		# figure's first cut, both put it) and is said in the caption, against
		# the compartment it windows. It is NOT a second line in that
		# compartment: MEASURED, "windowed read-only" is 2.5 cm of a hart column
		# and there are five to eighteen of them, which is 5 cm of figure width
		# and 5% off every letter in the drawing, for a fact the caption carries
		# for nothing.
		for m in masters:
			m['cells'] = ['VestaRV core', m['tcm']] if m.get('tcm') else []
			if m['cells']:
				# what the compartment now says, the note no longer has to
				m['note'] = ''
			isTile = m['title'].startswith('hart')
			if isTile != bool(m['cells']):
				raise Exception('ChipSystemFlatDiagram: master "' + str(m['title']) + '" is '
					+ ('' if isTile else 'not ') + 'a hart tile but '
					+ ('carries no' if isTile else 'carries a') + ' TCM compartment.')
			if m['cells'] and m['cells'][1] != wantTcm:
				raise Exception('ChipSystemFlatDiagram: the hart boxes would be drawn with a "'
					+ str(m['cells'][1]) + '" compartment, but this configuration\'s private TCM '
					'is ' + wantTcm + '.')

		# ---- the peripheral chips: a name and ONE line each -------------------
		def chip(key, title, sub, stack=1, ext=None):
			return {'key': key, 'title': title, 'sub': sub or '', 'stack': stack, 'ext': ext,
				'w': 0.0, 'cx': 0.0, 'tx': 0.0}

		rest = [b for b in allBoxes if b is not afeRow]
		byKey, order = {}, []
		for b in rest:
			cs = []
			if b['parts']:
				# One compartment per memory, glued into one box with one tap.
				for t, sub in b['parts']:
					cs.append(chip(b['key'], t, sub))
			else:
				cs.append(chip(b['key'], b['title'],
					b['brief'] or (b['sub'] or '').split('\\\\')[0], b['stack'], b['ext']))
			byKey[b['key']] = cs
			order.append(b['key'])

		# ---- NFC: THE TAG READS, AND THE FIELD FEEDS ------------------------
		# NFC0 is TWO paths and this figure used to draw one. The digital core is
		# on the die and its RF front end is off it (config/wound.json: "NFC's
		# digital AFE / RF interface is off-die"), so the antenna is an off-chip
		# partner like the serial flash — that half was already here. The half
		# that was not is the POWER: on a field-powered board the harvested
		# supply is what runs the chip, and it arrives at PWRCTRL, not at NFC0.
		#
		# TRANSCRIBED, from generate.py:798-808 and the PWRWAKE/PWRSTS templates
		# at :2225-2249 — peripherals.fieldPower wires pwr0's supervision inputs
		# to real pads (PGOOD on GPIO47, the harvested-boot strap on GPIO46, both
		# plain-GPIO DIRECT taps of the pad-input plane, readable before any
		# software runs) and adds NFC0's field_detect level as an optional
		# release source. The boot gate they control is pgood_rstn, ANDed into
		# every hart's outer reset. So the power path is drawn as what it is: a
		# board-level supply rail in the off-chip band that crosses the boundary
		# into PWRCTRL, in a heavier grey stroke than any signal in the drawing,
		# and NOT as a wire out of the NFC block.
		nfcOn = 'nfc' in byKey
		if bool(geo.get('nfc')) != nfcOn:
			raise Exception('ChipSystemFlatDiagram: this configuration has nfc='
				+ str(bool(geo.get('nfc'))) + ' but the bucketing pass '
				+ ('carries' if nfcOn else 'carries no') + ' NFC block.')
		fieldOn = bool(geo.get('fieldPower'))
		fieldPads = sorted(p.Name for p in gen.Package.Pins
			if p.Gpio is not None and p.Gpio.PrimaryName in ('GPIO46', 'GPIO47'))
		fieldBonded = len(fieldPads) == 2
		# The dashed-optional half of the rank: a block this configuration does
		# NOT build, drawn so the reader of the default manual can see where it
		# goes. It is tracked BY KEY so the drawn-set assertion below still holds
		# as an equality — a synthetic block that is not declared here would be
		# indistinguishable from a real one that the bucketing pass lost.
		synthKeys = set()
		if not nfcOn:
			byKey['nfc'] = [chip('nfc', 'NFC', 'digital protocol core', 1,
				{'title': 'NFC antenna', 'sub': None, 'w': 2.70})]
			# ---- USER DIRECTIVE, 2026-08-16: THE NFC BLOCK IS DRAWN SOLID ----
			# Same directive and same reasoning as the debug column above: the
			# USER has chosen the solid presentation for NFC and its antenna in
			# every configuration, the default manual included, so the block this
			# pass synthesises for a chip that does not build one is drawn like
			# every other block on the rank. The configuration-derived fact is
			# still stated, in the caption, which is where it now lives alone.
			byKey['nfc'][0]['dash'] = False
			order.append('nfc')
			synthKeys.add('nfc')
		nfcChip = byKey['nfc'][0]
		# ONE partner box, BOTH roles named in it. The antenna is where the tag
		# link and the harvested field both come from, and a reader who is told
		# that once does not need it labelled twice on two wires.
		nfcChip['ext']['title'] = 'NFC antenna'
		# Broken by hand, and short: this partner is the one box in the drawing
		# whose subtitle is a sentence, and on the narrow branch (maxw = 2.30,
		# config/penta_wound.json) a line the box cannot hold is a line set in
		# two -- which the height now counts, but which reads as "RF front / end,
		# off-die" and is nobody's idea of a caption.
		# The `field-powered builds' clause is GONE by user directive (2026-08-16):
		# it qualified the harvested half of this partner's job, the rail below
		# already carries that condition in its own stroke, and the caption says
		# it in a sentence. What is left is what the antenna IS.
		nfcChip['ext']['sub'] = ('RF front end\\\\ \\textit{off-die}\\\\ data readout \\&\\\\ '
			'harvested field')
		nfcChip['ext']['w'] = 3.30
		# The supply rail is SOLID only where the chip really runs off it: the
		# block built, the supervision inputs wired, and the two pads bonded on
		# this package (they are GPIO46/47, which the QFN models do not bring
		# out at all).
		powerSolid = nfcOn and fieldOn and fieldBonded

		# Related blocks are GLUED into one compartmented box (the portrait
		# figure's compartment idiom): fewer boxes on a rank that now carries
		# every peripheral on the chip, and one bus tap where the drawing would
		# otherwise carry three that say the same thing.
		serialKeys, clockKeys = ('spi', 'uart', 'i2c', 'nfc', 'ow'), ('system', 'power')
		# ...EXCEPT that a glued compartment cannot carry a stack of offset
		# squares, and the serial blocks are exactly the ones this chip
		# instantiates twice. RENDERED BOTH WAYS at 150 dpi (the report carries
		# both): glued is 1.1 cm narrower and its three names sit closer together,
		# but the only stack it can take is ONE behind the whole group, which
		# either says nothing (the group is not instantiated N times) or says the
		# wrong number the moment two compartments differ. Split wins on the
		# honesty, and the width it costs is width this rank has.
		serialSpec = [(k,) for k in serialKeys] if SERIAL_SPLIT else [serialKeys]
		specs = [('mem',), ('timer',), ('sync',), ('npu',), ('engine',), ('io',)]
		specs += serialSpec + [clockKeys]
		specs += [(k,) for k in order if not any(k in sp for sp in specs)]
		groups = []
		for sp in specs:
			ms = sum([byKey[k] for k in sp if k in byKey], [])
			if ms:
				groups.append({'members': ms, 'w': 0.0, 'cx': 0.0})
		# E17: nothing this configuration carries may fall out of the drawing on
		# its way from the shared bucketing pass into the rank.
		placed = set(c['key'] for g in groups for c in g['members'])
		placed |= set([afeRow['key']] if afeRow else [])
		if placed != set(b['key'] for b in allBoxes) | synthKeys:
			raise Exception('ChipSystemFlatDiagram: the drawn block set ' + str(sorted(placed))
				+ ' is not the bucketing pass\'s ' + str(sorted(b['key'] for b in allBoxes))
				+ ' plus the dashed not-in-this-build set ' + str(sorted(synthKeys)))

		# ---- THE RANK IS GROUPED BY TYPE ------------------------------------
		# A rank that carries every peripheral on the chip is ten boxes in a
		# line, which is a LIST, not an organisation. So the boxes of one kind
		# stand together under a small type label, in the idiom of the user's
		# own Myshkin block diagram: proximity first, then a thin outline round
		# them where there is more than one box to enclose.
		#
		# WHERE A TYPE IS ONE BOX THE LABEL IS THE WHOLE OF IT. A rectangle
		# 2.6 mm outside a rectangle is a doubled border, not a group, so the
		# glued memory box and the glued SYSTEM/PWRCTRL box get their type
		# label -- which is exactly the header the Myshkin diagram gives its own
		# compartmented boxes -- and no second outline. The outline is drawn
		# only where it is doing work, and it is drawn with a REAL GAP at every
		# bus tap and every partner wire that crosses it: the rule hart 0's rail
		# is already drawn by, for the same reason (a line that touches a wire
		# it does not join is a junction the drawing did not mean).
		#
		# The labels are also what the two ranks of the first cut lost when
		# their banner heads went: "serial interfaces" over SPI/UART/I2C cost
		# 0.70 cm of height as a banner band, and costs one line of small grey
		# text here.
		# The labels are SHORT because of where they have to sit, and SHORTER
		# again now that they are set BIGGER (user directive, 2026-08-16: the
		# headings were too small to read at the size this figure lands on the
		# page). A type label rides on its frame's top edge, in the same 1.3 cm
		# lane every bus tap on the rank rises through, so it goes in the
		# leftmost tap-free interval it FITS in -- and a label too long for any
		# of them has nowhere to stand that is not on a wire. Two consequences
		# of the bigger type, and each is written down where it is paid for:
		#   * `Communications' measures 3.16 cm at the heading size against its
		#     frame's widest tap-free interval of 2.29, and had nowhere to stand
		#     at all. The USER's own shortening, `Comms', is 1.35 and fits. That
		#     is the trade the size bought, and it is the only one: one word of
		#     formality for a heading a reader can actually read.
		#   * every OTHER label is left in full English, because a heading that
		#     does not fit its lane on one line is now SET IN TWO by `typeLabel'
		#     rather than shortened. Written here in one line, as it should be
		#     read; the break is the layout's business, not this list's.
		TYPES = [('Memory', ('mem',)),
			('Digital I/O', ('io',)),
			('Comms', tuple(k for k in serialKeys if k != 'nfc')),
			# NFC stands apart from the blocks that only move data: it is the one
			# block on this rank with TWO off-chip roles, and the harvested supply
			# rail starts under it.
			('NFC \\& Field Power', ('nfc',)),
			('Timing \\& Sync', ('timer', 'sync')),
			('Compute', ('npu', 'engine')),
			('Analog', ('afe',)),
			('System \\& Power', clockKeys)]
		typeOf = {}
		for lab, ks in TYPES:
			for k in ks:
				typeOf[k] = lab
		# E17, and the ONLY thing the frames are allowed to assert: every member
		# of every frame is a block this drawing actually draws, and every block
		# it draws is in exactly one frame. (The frames are decoration -- what
		# they may never do is imply a block, or quietly drop one.)
		unknown = sorted(set(c['key'] for g in groups for c in g['members']) - set(typeOf))
		if unknown:
			raise Exception('ChipSystemFlatDiagram: rank block(s) ' + str(unknown) + ' belong to '
				'no type frame. Add the key to TYPES and decide what kind of block it is — '
				'otherwise the rank would carry a box under no heading at all.')
		units = []
		for lab, ks in TYPES:
			gs = [g for g in groups if g['members'][0]['key'] in ks]
			if gs:
				units.append({'label': lab, 'groups': gs, 'w': 0.0, 'x0': 0.0, 'x1': 0.0})
		framed = [c['key'] for u in units for g in u['groups'] for c in g['members']]
		if sorted(framed) != sorted(c['key'] for g in groups for c in g['members']):
			raise Exception('ChipSystemFlatDiagram: the type frames cover ' + str(sorted(framed))
				+ ', which is not the rank\'s own block set '
				+ str(sorted(c['key'] for g in groups for c in g['members'])))

		# The off-chip partners are the reason the rank cannot simply be sorted
		# by function: a partner hangs on a STRAIGHT wire under its own
		# compartment, so a rank with all its pin-facing frames bunched at one
		# end cannot spread the partners under them. The pin-facing frames are
		# therefore dealt out evenly through the rank -- the FRAME is the unit
		# that moves now, because the boxes inside one may not be separated.
		def hasExt(u):
			return any(c['ext'] for g in u['groups'] for c in g['members'])
		A = [u for u in units if hasExt(u)]
		B = [u for u in units if not hasExt(u)]
		nAll = len(units)
		slot, taken = {}, set()
		for i, u in enumerate(A):
			j = min(nAll - 1, int((i + 0.5) * nAll / max(1, len(A))))
			while j in taken:
				j = (j + 1) % nAll
			taken.add(j)
			slot[j] = u
		it = iter(B)
		units = [slot.get(j) or next(it) for j in range(nAll)]
		groups = [g for u in units for g in u['groups']]

		# ---- widths -----------------------------------------------------------
		# WHICH SUBTITLES THE ONE RANK CAN PAY FOR. Its width is what sets the
		# type size of the WHOLE drawing, so a line that says what the name above
		# it already says is not free, it is 4% off every letter. Two rules, and
		# each names its own reason:
		#   * a glued box of four or more compartments keeps its NAMES and drops
		#     its subtitle lines (MEASURED on config/penta_wound.json, whose
		#     serial group is five blocks wide: with a subtitle each it is 12 cm
		#     of a rank that now has to hold every peripheral on the chip);
		#   * the serial blocks drop them at any size -- "asynchronous serial"
		#     under UART is a line the audience of a technical reference manual
		#     can afford to lose, and the count and the name are not.
		# `timer' and `npu' used to be muted with them, on the arithmetic that
		# "capture / compare" and "inference engine" were 1.8 cm of rank between
		# them. They are back: those two lines say what the block DOES, which a
		# timer called `timers' and an accelerator called `NPU' do not, and 1.8 cm
		# is 5% of a rank that the split serial boxes have already widened.
		# Everything else keeps its line too, because everything else is a DERIVED
		# fact (sizes, bank counts, port counts, instance names) that the reader
		# cannot get from the title.
		mute = serialKeys
		for u in units:
			cs = [c for g in u['groups'] for c in g['members']]
			if len(cs) >= 4 or all(c['key'] in mute for c in cs):
				for c in cs:
					c['sub'] = ''

		def titleOf(c, solo):
			# The numeral rides in the title AND the box wears its stack of
			# squares: one is read at a glance, the other is read exactly.
			if c['stack'] < 2:
				return c['title']
			return c['title'] + ' $\\times$' + str(c['stack'])

		# NO CORNER GLYPHS. A cut of this figure carried a hand-drawn pictogram in
		# the top-left corner of every block whose subject has an unambiguous one
		# (a stopwatch on `timers', a crystal on SYSTEM, a chip on the memories).
		# They were REJECTED on the render: at this figure's scale a 1.6 mm
		# silhouette is a smudge beside a name, and the width each one reserved --
		# a clear glyph cell at BOTH ends of a centred title -- was 1.42 cm of rank
		# bought for decoration. A box on this rank is a name and one line, and
		# nothing else is drawn in it.

		def measure():
			for g in groups:
				solo = len(g['members']) == 1
				for c in g['members']:
					c['w'] = c['wBase'] = max(c['w'], wOf(titleOf(c, solo), c['sub'],
						minw=(1.70 if not c['sub'] else 1.95)))
				g['w'] = sum(c['w'] for c in g['members'])
				# A STACK TAKES ROOM TO ITS RIGHT, and now that the rank is
				# grouped there is something for it to run into: 2.4 mm of offset
				# squares against the next box in the frame, or against the
				# frame's own edge. MEASURED at 300 dpi on the first cut of the
				# frames -- SPI's squares touched UART's box and I2C's touched
				# the outline.
				g['padR'] = (stackDx * (min(max(c['stack'] for c in g['members']),
					maxShadow) - 1)) if SHADOWS else 0.0
		measure()

		for m in masters:
			m['min'] = min(6.60, 0.30 + max(TWs(m['title'], tBold), TWs(m['sub']), TWs(m['note']),
				sum(TWs(t) for t in m['cells']) + 0.30 * len(m['cells'])))
		# The debug column also has to be wide enough for the probe box that
		# sits on it, because the probe is drawn AT the column's width.
		dbgM['min'] = max(dbgM['min'], 0.20 + TWs('debug probe', tBold), TWs(probeSub) + 0.24)
		exts = [c for g in groups for c in g['members'] if c['ext']]

		def sizeExts(maxw):
			'''The partner boxes, and HOW MANY LINES THEIR TITLES TAKE. A node
			   whose title is wider than its box does not clip, it wraps and
			   prints the extra line through the floor -- so a cap on the partner
			   width is only safe if the height knows about it.'''
			for c in exts:
				e = c['ext']
				e['dw'] = wOf(e['title'], e.get('sub'), minw=2.10, maxw=maxw)
				n, wt = 1, TWs(e['title'], tBold)
				while wt > n * (e['dw'] - 0.20) + 0.01:
					n += 1
				e['tl'] = n
				# ...and the SUB wraps too. It never used to matter, because
				# every partner subtitle was two short signal names; the NFC
				# antenna's is a sentence about what it does, and on the narrow
				# branch (maxw = 2.30) it wrapped and printed its last line
				# through the box floor. Same arithmetic, same reason: the height
				# of a box in this drawing is a line count, so the line count has
				# to be the one that will actually be set.
				e['sl'] = 0
				for line in (e.get('sub') or '').split('\\\\'):
					k, wl = 1, TWs(line)
					while wl > k * (e['dw'] - 0.20) + 0.01:
						k += 1
					e['sl'] += k

		# ONE reserved lane flanks the master band where the analog row exists,
		# and hart 0's reach goes up it. There used to be a second on the right,
		# for the row's own bus drop; that drop is gone (see the emission), and
		# the 0.78 cm it reserved goes back into the columns.
		xLane = 0.78 if afeRow is not None else 0.0
		xBandL = xEdge + xLane
		# (An earlier cut reserved 1.75 cm of extra air in ONE gap of the master
		# band, between hart 0's column and the first channel's, for the shared
		# engine's multiplexer to stand in. The multiplexer is gone with the
		# engine's site, and so is the reserve: the band is justified across a
		# width the rank fixes, so that 1.75 cm goes straight back into the
		# columns.)

		def rankWidth():
			return (sum(g['w'] + g['padR'] for g in groups)
				+ gapIn * (len(groups) - len(units))
				+ gapRank * (len(units) - 1) + 2 * xEdge)

		def widthNeeded():
			return max([sum(m['min'] for m in masters) + gapM * (len(masters) - 1)
					+ xBandL + xEdge,
				rankWidth(),
				sum(c['ext']['dw'] for c in exts) + gapExt * (len(exts) - 1) + 2 * xEdge])

		# ---- the rank, and the partners hanging straight off it ---------------
		def applyExtra():
			for c in exts:
				c['w'] = c['wBase'] + c['extra']
			for g in groups:
				g['w'] = sum(c['w'] for c in g['members'])

		def layoutRank(width):
			applyExtra()
			for u in units:
				u['w'] = (sum(g['w'] + g['padR'] for g in u['groups'])
					+ gapIn * (len(u['groups']) - 1))
			span = (width - 2 * xEdge) - sum(u['w'] for u in units)
			gp = span / float(len(units) - 1) if len(units) > 1 else 0.0
			x = xEdge
			for u in units:
				u['x0'] = x
				for g in u['groups']:
					g['cx'] = x + g['w'] / 2.0
					xc = x
					for c in g['members']:
						c['cx'] = c['tx'] = xc + c['w'] / 2.0
						xc += c['w']
					# THE TAP MUST NOT LAND ON A DIVIDER. A glued box's centre is
					# where two of its compartments meet as often as not (a
					# two-compartment group: always), and an arrowhead that lands
					# exactly on a rule reads as a drawing error, not as a tap. It
					# moves to the centre of the compartment it fell in.
					g['tx'] = g['cx']
					for c in g['members']:
						if abs(c['cx'] - c['w'] / 2.0 - g['cx']) < 0.25 or abs(
								c['cx'] + c['w'] / 2.0 - g['cx']) < 0.25:
							if abs(c['cx'] - g['cx']) < c['w'] / 2.0 + 0.26:
								g['tx'] = c['cx']
					x += g['w'] + g['padR'] + gapIn
				u['x1'] = x - gapIn
				x = u['x1'] + gp

		def placeExts(width):
			'''Minimum displacement under a separation constraint, the standard
			   two passes, then a third: a partner pushed left by the forward
			   sweep must not be shifted again (MEASURED on
			   config/penta_wound.json, eight partners: one sweep plus a global
			   shift piled the left three on top of each other).'''
			exts.sort(key=lambda c: c['tx'])
			sep = [0.0] + [(exts[i - 1]['ext']['dw'] + exts[i]['ext']['dw']) / 2.0 + gapExt
				for i in range(1, len(exts))]
			xs = [c['tx'] for c in exts]
			for _ in range(2):
				for i in range(len(exts)):
					xs[i] = max(xs[i], xEdge + exts[i]['ext']['dw'] / 2.0,
						(xs[i - 1] + sep[i]) if i else 0.0)
				for i in range(len(exts) - 1, -1, -1):
					xs[i] = min(xs[i], width - xEdge - exts[i]['ext']['dw'] / 2.0,
						(xs[i + 1] - sep[i + 1]) if i + 1 < len(exts) else width)
			return xs

		# THE WIRE IS STRAIGHT, SO THE BOX MOVES UNDER IT. A partner's wire drops
		# vertically out of its own compartment and enters the partner's top edge
		# wherever it lands -- off its centre is fine, off the box entirely is
		# not. Where a partner had to be nudged so far aside that its own wire
		# would miss it, the COMPARTMENT is widened (which spreads its
		# neighbours' taps too) and the rank re-laid.
		#
		# The widening is driven by the MEASURED miss, not by the difference
		# between a compartment and its partner: a partner may enter its box off
		# centre, so a run of partners wider than the compartments under them
		# needs only the SHORTFALL after that drift is spent. MEASURED on the
		# default configuration, the first cut's deficit-driven version paid the
		# whole difference and took the three serial compartments to 7.6 cm, a
		# drawing whose SPI box is as wide as its memory box because of where a
		# partner had to sit. The assertion below is what proves the fixed point
		# rather than the drawing shipping a wire into space.
		def entryMiss(c, xe):
			return abs(xe - c['tx']) - (c['ext']['dw'] / 2.0 - 0.10)

		def solve(maxw):
			sizeExts(maxw)
			for c in exts:
				c['extra'] = 0.0
			applyExtra()
			width = widthNeeded()
			# UNDER-RELAXED, and it has to be. Every partner's miss is measured
			# with all the OTHER partners still missing too, so paying each one
			# in full double-counts the same shortfall down a run of them:
			# MEASURED on config/penta_wound.json (eight partners, five of them
			# on one glued box) a full-payment step overshot 33.4 cm to 44.2 in
			# ONE pass and then converged there. Paying a fraction per pass and
			# iterating approaches the same fixed point from below.
			for _ in range(28):
				layoutRank(width)
				pos = placeExts(width)
				miss = [max(0.0, entryMiss(c, xe)) for c, xe in zip(exts, pos)]
				if max(miss + [0.0]) <= 0.0:
					break
				for c, ms in zip(exts, miss):
					if ms > 0.0:
						c['extra'] += 0.55 * ms + 0.02
				width = max(width, widthNeeded())
			layoutRank(width)
			return width, placeExts(width)
		W, xs = solve(3.40)
		# PAST A POINT THE PARTNERS GIVE INSTEAD. A one-line partner title is
		# worth its width until the drawing is so wide that every letter in it is
		# unreadable: MEASURED on config/penta_wound.json, whose rank carries
		# five serial blocks and eight partners, one-line titles put the figure
		# at 45.5 cm -- resized to the text width that is 2.5 pt type. Wrapping
		# the partner titles costs one line of height, once, and takes it to
		# 36 cm. The threshold is where the type crosses ~4.5 pt.
		if W > 34.0:
			W, xs = solve(2.30)
		for c, xe in zip(exts, xs):
			if entryMiss(c, xe) > 0.02:
				raise Exception('ChipSystemFlatDiagram: the straight wire under ' + str(c['title'])
					+ ' would enter "' + str(c['ext']['title']) + '" ' + P(abs(xe - c['tx']))
					+ ' cm from its centre, which is off the box.')

		# ---- heights ----------------------------------------------------------
		hCells = hCmp + hLine * max([L(t) for m in masters for t in m['cells']] or [0])
		hMaster = max(pad + hTitle * max(1, L(m['title'])) + hLine * (L(m['sub']) + L(m['note']))
			+ (hCells if m['cells'] else 0.0) + pad for m in masters)
		hRank = pad + hTitle + hLine * max(1, max(L(c['sub']) for g in groups
			for c in g['members'])) + pad
		hExt = max([pad + hTitle * c['ext']['tl'] + hLine * c['ext']['sl'] + pad
			for c in exts] or [0.90])
		# The site row is ONE line tall now that the gate line inside each box has
		# gone (user directive; see the emission), and nothing else runs inside
		# it: the depth an earlier cut kept there for the multiplexer's channel
		# lanes to pass BEHIND the site boxes went with the multiplexer. The line
		# is a TITLE line, not a body line, because what is left in the box is
		# the site's name.
		hSite = pad + hTitle + pad
		# The electrode cells carry the only pad names in the drawing and they
		# are what a board engineer opens this figure for, so they are drawn at
		# the body type size, not the tiny one, in a box with room around them.
		hCell, pitch, yStubOff = 1.46, 1.06, 0.26
		# The debug probe is an off-chip partner like any other, and it is drawn
		# in the row the electrode cells are in -- above the boundary, over the
		# column whose block its pins reach. Where there is no analog row that
		# row exists for the probe alone, which is why the top of this drawing
		# is no longer conditional on the analog front end.
		hProbe = pad + hTitle + hLine * L(probeSub) + pad
		jPitch = 0.50                  # the five pins, as a bundle

		y = 0.0
		yCellT = y
		yCellB = y - max(hCell if afeRow is not None else 0.0, hProbe)
		yRedT = yCellB - 0.55
		ySiteT = yRedT - 0.30
		ySiteB = ySiteT - hSite
		# Where there is no analog row the master band sits straight under the red
		# boundary, and a STACKED master's squares climb out of the top of it: the
		# clearance is the stack's own height, not a constant measured before the
		# squares came back.
		mShadow = (stackDy * (maxShadow - 1) + 0.14) if (SHADOWS
			and any(m['stack'] > 1 for m in masters)) else 0.0
		yBandT = ((ySiteB - 0.76) if afeRow is not None
			else (yRedT - max(0.34, mShadow)))
		yBandB = yBandT - hMaster
		yBarT = yBandB - riser
		yBarB = yBarT - barH
		yRankT = yBarB - riserR
		yRankB = yRankT - hRank
		yRedB = yRankB - 0.42
		# The off-chip band opens up to take the harvested supply rail and its
		# label: the rail runs along it, under the boundary and over the partner
		# boxes, with a real gap at every partner wire it crosses.
		yExtT = yRedB - 1.28
		yPwr = yExtT + 0.34

		# ---- emission ---------------------------------------------------------
		s = ('% Generated whole-chip system diagram, FLAT companion (harts=' + str(N)
			+ ', orchestrator=' + str(orch) + ', analogRow=' + str(afeRow is not None)
			+ ', shadows=' + str(SHADOWS)
			+ ', serialSplit=' + str(SERIAL_SPLIT) + ', sitesOmitted=' + str(omitSites)
			+ ', debug=' + str(dbgOn) + ', jtagBonded=' + str(jtagBonded)
			+ ', rank=' + str([(u['label'], [c['key'] for g in u['groups']
				for c in g['members']]) for u in units]) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\thd/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt, anchor=north},\n'
		s += '\tbc/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\tbadge/.style={font=\\sffamily\\small\\bfseries, align=center, inner sep=1pt},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\town/.style={->, >=Stealth, semithick},\n'
		s += '\treach/.style={->, >=Stealth, line width=1.4pt},\n'
		s += '\twire/.style={semithick},\n'
		s += '\tpadlab/.style={font=\\sffamily\\small, align=center, inner sep=1pt},\n'
		# (The `lane' style is retired with the rotated \texttt{s\_master}
		# annotation it was the only user of.)
		# The type label: BIG, grey, italic, roman weight. It was \scriptsize --
		# 7 pt in a drawing that lands on the page at 0.48 scale, which is 3.4 pt
		# of print and not a heading anybody reads -- and by user directive
		# (2026-08-16) it is now \large, which is bigger than the block titles
		# under it. That is deliberate and it is the ONE place in this figure
		# where a grey label outsizes a black one: a heading is read before the
		# things it heads. The hierarchy is kept by WEIGHT and COLOUR instead, as
		# it always was: the titles are bold black, this is roman grey italic, so
		# the rank still has exactly one kind of bold in it.
		s += ('\ttyp/.style={font=\\sffamily\\large\\itshape, black!55, align=left, '
			'fill=white, inner sep=1.5pt, anchor=west},\n')
		# The rail annotation keeps the size the type headings left behind: it is
		# a note on ONE wire in the off-chip band, not a heading over a row of
		# blocks, and it has to stay out of the partner boxes it runs above.
		s += ('\trail/.style={font=\\sffamily\\scriptsize\\itshape, black!55, align=left, '
			'fill=white, inner sep=1.5pt, anchor=west},\n')
		s += '\tredlab/.style={font=\\sffamily\\small\\bfseries, red!70!black, align=left}]\n'

		def frame(cx, yTop, w, h, fill, opts='thick'):
			return ('\\draw[' + opts + ', fill=' + fill + '] (' + P(cx - w / 2.0) + ', '
				+ P(yTop - h) + ') rectangle (' + P(cx + w / 2.0) + ', ' + P(yTop) + ');\n')

		def head(cx, yTop, w, title, sub, note=None):
			tex = '{\\small\\bfseries ' + title + '}'
			for extra in (sub, note):
				if extra:
					tex += '\\\\[1pt] ' + extra
			return ('\\node[hd, text width=' + P(w - 0.20) + 'cm] at (' + P(cx) + ', '
				+ P(yTop - pad) + ') {' + tex + '};\n')

		def shadows(cx, yTop, w, h, n, fill, opts='thick'):
			'''THE BACK COPIES ARE THE SAME BOX. The first cut filled them with
			   paper, on the reasoning that a white back copy cannot be mistaken for
			   a block with content in it. What it actually drew was N-1 EMPTY
			   outlines behind one grey block -- a shadow, or a ghost, but not a
			   count. Every layer now carries the FRONT box's own fill and the front
			   box's own border, so the stack reads as what it is: N identical chips
			   of the same kind, offset so you can see there are N.'''
			out = ''
			if not SHADOWS:
				return out
			for k in range(min(n, maxShadow) - 1, 0, -1):
				out += frame(cx + stackDx * k, yTop + stackDy * k, w, h, fill, opts)
			return out

		def badge(x, ymid, n, side='east'):
			# DEAD, and kept dead deliberately. A separate $\\times N$ node beside a
			# stacked box would be the THIRD place this figure says the same number
			# (the title says it, the squares show it), and on a single rank the only
			# room for it is the 0.52 cm riser between the rank and the bar, which is
			# where it collided with the bar the first time round.
			return ''
			if not SHADOWS:
				return ''
			dx = 0.12 if side == 'west' else -0.12
			return ('\\node[badge, anchor=' + side + ', fill=white, inner sep=1.5pt] at ('
				+ P(x + dx) + ', ' + P(ymid) + ') {$\\times$' + str(n) + '};\n')

		# ---- the red package boundary, drawn first ---------------------------
		s += ('\\draw[red!75!black, line width=1.2pt] (0.00, ' + P(yRedB) + ') rectangle ('
			+ P(W) + ', ' + P(yRedT) + ');\n')
		s += ('\\node[redlab, anchor=south west] at (0.00, ' + P(yRedT + 0.10)
			+ ') {chip boundary};\n')

		# ---- the master band --------------------------------------------------
		xBandR = W - xEdge - 0.40
		avail = (xBandR - xBandL) - gapM * (len(masters) - 1)
		wsum = sum(m['weight'] for m in masters)
		spare = avail - sum(m['min'] for m in masters)
		for m in masters:
			m['w'] = min(6.60, m['min'] + max(0.0, spare) * m['weight'] / wsum)
		x = xBandL + max(0.0, (avail - sum(m['w'] for m in masters))) / 2.0
		for m in masters:
			m['cx'] = x + m['w'] / 2.0
			m['tx'] = m['cx'] - (0.22 * m['w'] if (SHADOWS and m['stack'] > 1) else 0.0)
			x += m['w'] + gapM
		for m in masters:
			# A stacked master's title is a RANGE ("hart 1--17"), which already
			# counts the instances; it never takes the $\times N$ the rank's
			# stacked blocks take in place of their shadow squares.
			# DASHED IS NOT-IN-THIS-BUILD, and it takes the paper fill with it:
			# a dashed border round the band's own grey would read as one more
			# master with a decorated edge.
			mOpts = 'thick, rounded corners=2pt' + (', dashed' if m.get('dash') else '')
			mFill = 'white' if m.get('dash') else 'black!8'
			s += shadows(m['cx'], yBandT, m['w'], hMaster, m['stack'], mFill, mOpts)
			s += frame(m['cx'], yBandT, m['w'], hMaster, mFill, mOpts)
			s += head(m['cx'], yBandT, m['w'], m['title'], m['sub'], m['note'])
			if m['cells']:
				# the tile, drawn as the two things it is built from
				yD = yBandB + hCells
				s += ('\\draw[semithick] (' + P(m['cx'] - m['w'] / 2.0) + ', ' + P(yD) + ') -- ('
					+ P(m['cx'] + m['w'] / 2.0) + ', ' + P(yD) + ');\n')
				k = len(m['cells'])
				for i, t in enumerate(m['cells']):
					xL = m['cx'] - m['w'] / 2.0 + m['w'] * i / float(k)
					if i:
						s += ('\\draw[semithick] (' + P(xL) + ', ' + P(yD) + ') -- (' + P(xL)
							+ ', ' + P(yBandB) + ');\n')
					s += ('\\node[bc, text width=' + P(m['w'] / float(k) - 0.16) + 'cm] at ('
						+ P(xL + m['w'] / (2.0 * k)) + ', ' + P(yBandB + hCells / 2.0) + ') {' + t
						+ '};\n')
			if m['stack'] > 1:
				s += badge(m['cx'] - m['w'] / 2.0 - 0.22, yBandB + hMaster / 2.0, m['stack'], 'east')
			s += ('\\draw[bus' + (', dashed' if m.get('dash') else '') + '] (' + P(m['tx']) + ', '
				+ P(yBandB) + ') -- (' + P(m['tx']) + ', ' + P(yBarT) + ');\n')

		# ---- THE BUS: one bar, edge to edge, tapped from both sides -----------
		# THE BAR SAYS WHAT IT IS, IN WORDS. It used to be labelled mp\_arbiter,
		# which is the VHDL entity's name and not a name at all to a reader
		# meeting this chip on page 17: the identifier is explained once, in the
		# caption, where the reader who wants to grep the RTL will find it. The
		# bar itself carries the English -- and the three facts under it are the
		# ones a whole-chip overview owes a reader who is about to assume a
		# crossbar.
		s += ('\\draw[thick, fill=black!15] (' + P(xEdge) + ', ' + P(yBarB) + ') rectangle ('
			+ P(W - xEdge) + ', ' + P(yBarT) + ');\n')
		s += ('\\node[bc, text width=' + P(W - 2 * xEdge - 0.40) + 'cm] at (' + P(W / 2.0) + ', '
			+ P(yBarB + barH / 2.0)
			+ ') {{\\small\\bfseries multi-hart shared-bus arbiter} \\quad one shared-window '
			'transaction at a time \\quad round-robin \\quad grant-locked AMOs\\\\ \\textit{every '
			'master reaches the whole shared window, and only through the bar}};\n')

		# ---- THE TYPE FRAMES, drawn first so the boxes sit on top -------------
		def brokenLine(y, x0, x1, cuts, opts):
			'''One edge of a frame, with a real gap at every wire that crosses
			   it. The gaps are not cosmetic: this drawing has FOUR line weights
			   in it already, and a thin grey rule that touches a bus tap is a
			   junction until the reader gets close enough to see it is not.'''
			out, x = '', x0
			for cut in sorted(c for c in cuts if x0 + frmGap < c < x1 - frmGap):
				if cut - frmGap > x + 0.02:
					out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- ('
						+ P(cut - frmGap) + ', ' + P(y) + ');\n')
				x = cut + frmGap
			if x1 > x + 0.02:
				out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- (' + P(x1) + ', '
					+ P(y) + ');\n')
			return out

		def labelIvs(xL, xR, taps):
			'''The tap-free intervals of one label lane, left to right.'''
			ivs, lo = [], xL + 0.10
			for t in sorted(t for t in taps if xL < t < xR):
				ivs.append((lo, t - 0.10))
				lo = t + 0.10
			ivs.append((lo, xR - 0.10))
			return ivs

		def labelAt(xL, xR, taps, wLab, lab):
			'''WHERE A HEADING MAY STAND. The label lane is the riser, and every
			   box on the rank sends its bus tap straight up through it, so the
			   label goes in the leftmost gap BETWEEN taps that it fits in --
			   left where it can be (a heading belongs at the start of what it
			   heads), further along where the first box is too narrow. A label
			   that fits nowhere is not nudged, it fails the build: a white label
			   box sitting on a bus wire is the exact fault the AFE figure was
			   rejected for, and it must not be able to ship by accident.'''
			ivs = labelIvs(xL, xR, taps)
			fits = [iv for iv in ivs if iv[1] - iv[0] >= wLab]
			if not fits:
				raise Exception('ChipSystemFlatDiagram: the label "' + lab + '" is '
					+ P(wLab) + ' cm wide at its own type size and the widest tap-free interval '
					'of its lane is ' + P(max(iv[1] - iv[0] for iv in ivs)) + ' cm: it would sit '
					'on a wire.')
			return fits[0][0]

		def typeLabel(xL, xR, taps, lab):
			'''A TYPE HEADING, SET IN AS FEW LINES AS ITS LANE WILL TAKE. Returns
			   (x, text).

			   The headings were \\scriptsize when TYPES was written and every one
			   of them fitted its lane on one line. At \\large -- the size the USER
			   asked for, 1.77x the widths TWs measures -- some do not, and the
			   answer is not to keep shortening English until it does: a heading
			   may be SET IN TWO LINES, and the interval test cares only about the
			   widest of them, because both lines stand in one node and a bus tap
			   is vertical (so a lane that is clear is clear for the node's whole
			   height).

			   The break is tried, not written into TYPES, and it is tried in this
			   order: the label as written, then broken after its conjunction. One
			   line is preferred wherever one line fits, because a two-line node
			   is centred on the frame's top edge and its second line hangs into
			   the frame's own standoff -- room this figure has, but not room it
			   should spend where it does not have to. A label that fits nowhere
			   in either form still fails the build, by the rule above.'''
			ivs = labelIvs(xL, xR, taps)
			room = max(iv[1] - iv[0] for iv in ivs)
			forms = [lab]
			if '\\\\' not in lab and ' \\& ' in lab:
				forms.append(lab.replace(' \\& ', ' \\&\\\\ ', 1))
			for form in forms:
				if TWs(form) * tLab <= room:
					return labelAt(xL, xR, taps, TWs(form) * tLab, form), form
			# Neither form fits: report against the LAST one tried, which is the
			# narrowest, so the message names the real shortfall.
			return labelAt(xL, xR, taps, TWs(forms[-1]) * tLab, forms[-1]), forms[-1]

		# THE WIRES THAT CROSS A FRAME'S BOTTOM EDGE. Every partner hangs on a
		# straight wire dropped out of its own compartment, and the harvested
		# supply rail comes back UP into PWRCTRL on one of its own. Both cross
		# the rank, so both get a real gap where they pass a frame outline -- and
		# the rail's is easy to forget, because it is the only wire in the
		# drawing that crosses the rank from below. Its x is computed here, once,
		# and used again where the rail itself is drawn.
		pwrChip = None
		for g in groups:
			for c in g['members']:
				if c['key'] == 'power':
					pwrChip = c
		xPwrRise = (pwrChip['cx'] + max(0.50, pwrChip['w'] / 2.0 - 0.34)) if pwrChip else None

		yFrmT, yFrmB = yRankT + frmTop, yRankB - frmBot
		for u in units:
			cs = [c for g in u['groups'] for c in g['members']]
			xL, xR = u['x0'] - frmPad, u['x1'] + frmPad
			taps = [g['tx'] for g in u['groups']]
			# EVERY TYPE THAT HAS MORE THAN ONE BOX IS ENCLOSED, and a GLUED box
			# of several compartments counts (user directive, 2026-08-16). The
			# emitter used to give the glued types -- the memory box, the
			# SYSTEM/PWRCTRL box -- their heading and no outline, on the argument
			# that a rectangle 1.8 mm outside a rectangle is a doubled border
			# rather than a group. RENDERED: with the headings set big the
			# unframed types read as captions floating over the rank while the
			# framed ones read as groups, and the rank stopped looking like one
			# organisation. So the frame is now drawn wherever the heading is,
			# and the two say the same thing everywhere.
			if len(cs) > 1:
				fo = 'black!45, line width=0.5pt'
				s += brokenLine(yFrmT, xL, xR, taps, fo)
				bCuts = [c['tx'] for c in cs if c['ext']]
				if xPwrRise is not None and any(c['key'] == 'power' for c in cs):
					bCuts.append(xPwrRise)
				s += brokenLine(yFrmB, xL, xR, bCuts, fo)
				s += ('\\draw[' + fo + '] (' + P(xL) + ', ' + P(yFrmB) + ') -- (' + P(xL) + ', '
					+ P(yFrmT) + ');\n')
				s += ('\\draw[' + fo + '] (' + P(xR) + ', ' + P(yFrmB) + ') -- (' + P(xR) + ', '
					+ P(yFrmT) + ');\n')
			else:
				xL, xR = u['x0'] - 0.04, u['x1'] + 0.04
			# A HEADING OVER ONE BOX IS THAT BOX'S TITLE AGAIN. "Compute" over a
			# box called NPU, "Digital I/O" over a box called GPIO: the reader
			# has already read it, and the second printing is one more thing in
			# the one lane the bus taps have to get through (MEASURED: the GPIO
			# box is 2.50 cm, its tap halves it, and "Digital I/O" is 2.50 at the
			# heading size -- it does not fit beside its own wire, and at this
			# size nothing of that length would). The label is drawn where it is
			# doing work: over two or more blocks that are one kind of thing,
			# which is exactly where the frame is drawn too.
			if len(cs) > 1:
				xLab, tLabel = typeLabel(xL, xR, taps, u['label'])
				s += ('\\node[typ] at (' + P(xLab) + ', ' + P(yFrmT) + ') {' + tLabel + '};\n')

		# ---- THE RANK: every peripheral, one row, one straight tap each -------
		for g in groups:
			solo = len(g['members']) == 1
			# THE STACK BELONGS TO A BOX, AND A GLUED BOX IS ONE BOX. Squares
			# behind a compartmented group say "N of this group", which is true
			# only where every compartment in it has the same count -- and a lie
			# with no way to qualify it the moment two differ. Where they differ,
			# nothing is drawn rather than something wrong (and `specs' keeps the
			# multi-instance blocks unglued so it never comes to that).
			counts = set(c['stack'] for c in g['members'])
			if solo:
				nStack = g['members'][0]['stack']
			elif len(counts) == 1:
				nStack = g['members'][0]['stack']
			else:
				if max(counts) > 1:
					raise Exception('ChipSystemFlatDiagram: the glued box '
						+ str([c['key'] for c in g['members']]) + ' has compartments with '
						+ str(sorted(counts)) + ' instances, so no single stack of squares '
						'behind it is true. Ungroup it (see SERIAL_SPLIT).')
				nStack = 1
			gDash = any(c.get('dash') for c in g['members'])
			gOpts = 'thick, dashed' if gDash else 'thick'
			gFill = 'white' if gDash else 'black!5'
			s += shadows(g['cx'], yRankT, g['w'], hRank, nStack, gFill, gOpts)
			s += frame(g['cx'], yRankT, g['w'], hRank, gFill, gOpts)
			for j, c in enumerate(g['members']):
				if j:
					xL = c['cx'] - c['w'] / 2.0
					s += ('\\draw[semithick] (' + P(xL) + ', ' + P(yRankT) + ') -- (' + P(xL)
						+ ', ' + P(yRankB) + ');\n')
				s += head(c['cx'], yRankT, c['w'], titleOf(c, solo), c['sub'])
			s += ('\\draw[bus' + (', dashed' if gDash else '') + '] (' + P(g['tx']) + ', '
				+ P(yRankT) + ') -- (' + P(g['tx']) + ', ' + P(yBarB) + ');\n')
			if solo and g['members'][0]['stack'] > 1:
				s += badge(g['tx'], yRankT + stackDy * (maxShadow - 1) + 0.14,
					g['members'][0]['stack'])

		# ---- the outside world, below the boundary, on straight wires ---------
		xNfcExt = None
		for c, xe in zip(exts, xs):
			e = c['ext']
			cDash = ', dashed' if c.get('dash') else ''
			s += frame(xe, yExtT, e['dw'], hExt, 'white' if c.get('dash') else 'black!3',
				'thick' + cDash)
			s += head(xe, yExtT, e['dw'], e['title'], e.get('sub'))
			s += ('\\draw[bus' + cDash + '] (' + P(c['tx']) + ', ' + P(yRankB) + ') -- ('
				+ P(c['tx']) + ', ' + P(yExtT) + ');\n')
			s += ('\\fill[red!70!black] (' + P(c['tx'] - 0.07) + ', ' + P(yRedB - 0.07)
				+ ') rectangle (' + P(c['tx'] + 0.07) + ', ' + P(yRedB + 0.07) + ');\n')
			if c is nfcChip:
				xNfcExt = xe

		# ---- THE HARVESTED SUPPLY: the second thing the antenna does ---------
		# It is not a signal and it is not drawn like one. A field-powered board
		# rectifies the reader's field and that supply is what brings the chip
		# up: it reaches PWRCTRL's two supervision pads, and the boot gate they
		# hold releases every hart. So it is a RAIL -- heavier than any wire
		# here, grey, one arrowhead, running along the off-chip band from the
		# antenna to under PWRCTRL and crossing the boundary there -- and it is
		# cut with a real gap at every partner wire it passes, the same rule the
		# type frames and hart 0's rail are drawn by.
		# (`pwrChip' and its rise-in x are computed once, up where the type frames
		# needed a gap cut in the bottom edge the rail crosses.)
		if xNfcExt is not None and pwrChip is not None:
			pDash = '' if powerSolid else ', dashed'
			po = 'black!55, line width=1.5pt' + pDash
			x0 = xNfcExt + nfcChip['ext']['dw'] / 2.0 - 0.34
			x1 = xPwrRise
			s += ('\\draw[' + po + '] (' + P(x0) + ', ' + P(yExtT) + ') -- (' + P(x0) + ', '
				+ P(yPwr) + ');\n')
			s += brokenLine(yPwr, min(x0, x1), max(x0, x1),
				[c['tx'] for c in exts if abs(c['tx'] - x0) > 0.02], po)
			s += ('\\draw[' + po + ', ->, >=Stealth] (' + P(x1) + ', ' + P(yPwr) + ') -- ('
				+ P(x1) + ', ' + P(yRankB) + ');\n')
			s += ('\\fill[red!70!black] (' + P(x1 - 0.07) + ', ' + P(yRedB - 0.07)
				+ ') rectangle (' + P(x1 + 0.07) + ', ' + P(yRedB + 0.07) + ');\n')
			# The label goes where the rail is clear of the wires that cross it,
			# by the same rule the type headings are placed by. It names WHAT THE
			# RAIL IS and nothing else: the second line, which named the two
			# supervision pads it lands on, is gone by user directive
			# (2026-08-16). Those pad names are a PWRCTRL fact, they are in the
			# pin table and in the caption, and on a whole-chip overview they
			# were two lines of \texttt{} in the one band the rail runs through.
			lab = 'harvested field power'
			s += ('\\node[rail, text=black!60, anchor=south west] at ('
				+ P(labelAt(min(x0, x1), max(x0, x1), [c['tx'] for c in exts],
					TWs(lab), lab)) + ', ' + P(yPwr + 0.10) + ') {' + lab + '};\n')

		# ---- the analog sites, their electrodes, and who may reach them -------
		if afeRow is not None:
			# THE AIR BETWEEN THE CHANNELS STAYS AIR, AND SO DOES THE STRIP
			# BEHIND THEM. The first cut ran BOTH the bus and hart 0's reach
			# along the row at two heights, entering each site's left and right
			# edges: at 300 dpi that is two double-headed arrows in every gap,
			# and what it reads as is the sites wired to each other -- the one
			# thing the row must not say. The second cut kept the bus as a grey
			# strip running the length of the row behind the boxes, with one
			# drop down the right lane into the bar.
			#
			# That strip is GONE (USER). The access story the row has to tell is
			# WHO MAY READ A SITE, and it is told twice already and in full, by
			# the two things that are DRAWN: the thin arrow from a hart into its
			# own site, and hart 0's heavy rail underneath reaching all of them.
			# The sites are still ordinary arbiter slaves and are still reached
			# only through the bar -- that is a fact of the fabric, it is the same
			# fact for every block in the drawing, and it is now carried by the
			# caption rather than by a strip that put a second grey bar across
			# the one row this figure keeps clear.
			yReach = yBandT + 0.30
			xOwnGap, xReachDrop = 0.11, 1.00

			# Hart 0's reach: ONE heavy rail out of its own box, along the strip
			# under the row, with a drop into every site drawn. The privilege is one
			# comparison against the arbiter's granted-master index, so it is one
			# line and not four more wires. The rail is drawn with a REAL GAP where
			# each column's thin ownership arrow passes through it, so a crossing
			# cannot be read as a junction. It is unchanged by the curated omission
			# above: what hart 0 may read is every site on the row, and every site
			# on the row that this figure draws is a channel's.
			cuts = sorted([columns[h]['cx'] for h in drawnCols])
			xr = xReach
			s += ('\\draw[reach, -] (' + P(columns[0]['cx'] - columns[0]['w'] / 2.0) + ', '
				+ P(yBandT - hMaster / 2.0) + ') -- (' + P(xr) + ', '
				+ P(yBandT - hMaster / 2.0) + ') -- (' + P(xr) + ', ' + P(yReach) + ');\n')
			for cut in cuts:
				s += ('\\draw[reach, -] (' + P(xr) + ', ' + P(yReach) + ') -- ('
					+ P(cut - xOwnGap) + ', ' + P(yReach) + ');\n')
				xr = cut + xOwnGap
			s += ('\\draw[reach, -] (' + P(xr) + ', ' + P(yReach) + ') -- ('
				+ P(cuts[-1] + xReachDrop) + ', ' + P(yReach) + ');\n')
			# NO \texttt{s\_master} ANYWHERE IN THIS DRAWING (user directive,
			# 2026-08-16). The rail used to carry `s\_master = 0' rotated up its
			# own margin and every site box printed its own copy of the gate. The
			# ownership story is now told by the two things that are drawn: the
			# thin arrow from a hart into its own site, and this heavy rail out of
			# hart 0 reaching all of them. The signal's name, and what the gate
			# compares, are the caption's and Section \ref{ss:cqanalog-gate}'s --
			# a register-level identifier repeated five times across the one strip
			# this row keeps clear was five labels buying one fact.

			reached = []
			for h in drawnCols:
				nm = siteOf[h][0]
				m = columns[h]
				s += frame(m['cx'], ySiteT, m['w'], hSite, 'black!5')
				# The site box is its NAME, and that is the whole of it now that
				# the gate line has gone: one line, set at the same \small\bfseries
				# the hart under it is set in, because the pair is one channel and
				# the two halves of it should read as one weight.
				s += ('\\node[bc, text width=' + P(m['w'] - 0.30) + 'cm] at (' + P(m['cx']) + ', '
					+ P(ySiteB + hSite / 2.0) + ') {{\\small\\bfseries ' + fmttex(nm)
					+ '} site};\n')
				# THE OWNERSHIP MARK: a short direct arrow into the site from the
				# hart whose index the gate inside it admits. Thin, so it cannot
				# be read as one of the bus wires. It used to carry the word
				# `owns' beside it, once per column; the caption says it once, and
				# four repetitions of a word the reader has already met are four
				# labels in the one strip the row keeps clear.
				s += ('\\draw[own] (' + P(m['cx']) + ', ' + P(yBandT) + ') -- (' + P(m['cx'])
					+ ', ' + P(ySiteB) + ');\n')
				# and hart 0's reach, up into this site out of the rail below it
				s += ('\\draw[reach] (' + P(m['cx'] + xReachDrop) + ', ' + P(yReach) + ') -- ('
					+ P(m['cx'] + xReachDrop) + ', ' + P(ySiteB) + ');\n')
				reached.append(nm)

			# E17: the rail and the drop are drawn per site from the same list the
			# sites themselves come from, so a site the layout forgot cannot ship as
			# a site nothing reaches -- and the one site this figure deliberately
			# does NOT draw has to be accounted for BY NAME on the other side of the
			# same equality, so the omission stays a decision and can never become a
			# drop.
			if sorted(reached + omitSites) != sorted(st[0] for st in afeRow['sites']):
				raise Exception('ChipSystemFlatDiagram: the drawn site set ' + str(sorted(reached))
					+ ' plus the curated omission ' + str(sorted(omitSites))
					+ ' is not this configuration\'s '
					+ str(sorted(st[0] for st in afeRow['sites'])))

			# ---- the electrodes, one triple straight up out of its own site ---
			for h in sorted(padOf):
				names = padOf[h]
				cx = columns[h]['cx']
				n = len(names)
				wCell = pitch * (n - 1) + 1.60
				s += ('\\draw[thick, rounded corners=3pt, fill=black!3] (' + P(cx - wCell / 2.0)
					+ ', ' + P(yCellB) + ') rectangle (' + P(cx + wCell / 2.0) + ', '
					+ P(yCellT) + ');\n')
				# The caption of the cell is set at the PAD-LABEL size (user
				# directive, 2026-08-16): it was \scriptsize, which is 3.4 pt of
				# print at the scale this figure lands on the page, and it names
				# the one thing in the drawing that is not on the die at all.
				s += ('\\node[padlab, anchor=north] at (' + P(cx) + ', ' + P(yCellT - 0.10)
					+ ') {' + str(n) + '-electrode cell};\n')
				yStub = yCellB + yStubOff
				for k, nm in enumerate(names):
					xk = cx + (k - (n - 1) / 2.0) * pitch
					# ONE unbroken vertical wire: site box -> boundary -> stub.
					# Nothing is drawn over it but the pad square, and the name
					# sits above the stub inside the cell, never on the wire.
					s += ('\\draw[wire] (' + P(xk) + ', ' + P(ySiteT) + ') -- (' + P(xk) + ', '
						+ P(yStub) + ');\n')
					s += ('\\draw[wire, line width=1.4pt] (' + P(xk - 0.24) + ', ' + P(yStub)
						+ ') -- (' + P(xk + 0.24) + ', ' + P(yStub) + ');\n')
					s += ('\\node[padlab, anchor=south, inner sep=1.5pt] at (' + P(xk) + ', '
						+ P(yStub + 0.06) + ') {\\texttt{' + fmttex(nm) + '}};\n')
					s += ('\\fill[red!70!black] (' + P(xk - 0.07) + ', ' + P(yRedT - 0.07)
						+ ') rectangle (' + P(xk + 0.07) + ', ' + P(yRedT + 0.07) + ');\n')

		# ---- the debug probe, its five pins, and the boundary they cross ------
		# The partner idiom, upward: an off-chip box above the boundary, its
		# signal names printed INSIDE it (the serial flash's CS/SCK MOSI/MISO,
		# exactly), and straight vertical wires down into the block they reach,
		# each carrying a boundary square where it crosses the red line. Five
		# wires and not one, because five is the fact a reader opens a
		# whole-chip figure for.
		#
		# The probe is a HAT ON ITS BLOCK, the way a site is a hat on its hart:
		# same centre, no wider than the column, so the pair reads as one path
		# and nothing has to be labelled to say which block the pins reach.
		probeW = min(dbgM['w'], 3.60)
		yProbeB = yCellT - hProbe
		# SOLID, with the column it stands on (user directive, 2026-08-16; see
		# where dbgM['dash'] is set). The probe box and its five pin wires used to
		# be dashed on two separate conditions -- the knob, and whether the pins
		# reach a ball on this package -- and both of those facts are now printed
		# in the box in words instead.
		dashJ = ''
		s += ('\\draw[thick, rounded corners=3pt, fill=white' + dashJ + '] ('
			+ P(dbgM['cx'] - probeW / 2.0) + ', ' + P(yProbeB) + ') rectangle ('
			+ P(dbgM['cx'] + probeW / 2.0) + ', ' + P(yCellT) + ');\n')
		s += head(dbgM['cx'], yCellT, probeW, 'debug probe', probeSub)
		for k in range(len(JTAG_PINS)):
			xk = dbgM['cx'] + (k - (len(JTAG_PINS) - 1) / 2.0) * jPitch
			s += ('\\draw[wire' + dashJ + '] (' + P(xk) + ', ' + P(yBandT) + ') -- (' + P(xk)
				+ ', ' + P(yProbeB) + ');\n')
			s += ('\\fill[red!70!black] (' + P(xk - 0.07) + ', ' + P(yRedT - 0.07)
				+ ') rectangle (' + P(xk + 0.07) + ', ' + P(yRedT + 0.07) + ');\n')
		# E17: the probe is in the same row as the electrode cells, and a cell is
		# WIDER than the column it sits on. Two boxes that overlap in a row this
		# figure draws by construction is not something to find on a render.
		for h in sorted(padOf):
			cx = columns[h]['cx']
			wCell = pitch * (len(padOf[h]) - 1) + 1.60
			if abs(cx - dbgM['cx']) < (wCell + probeW) / 2.0 + 0.10:
				raise Exception('ChipSystemFlatDiagram: the debug probe box would overlap the '
					+ str(len(padOf[h])) + '-electrode cell of hart ' + str(h) + ' — the top row '
					'has no room for both at this width.')

		s += '\\end{tikzpicture}\n'
		# The drawn extent, in the figure's own centimetres, recorded in the file
		# it describes: this figure is \resizebox'd to the text width, so its
		# ASPECT is what decides how much page height it costs and how small its
		# type lands -- and neither is visible in any other artefact of the build.
		hAll = yCellT - yExtT + hExt
		s = (s.split('\n', 1)[0][:-1] + ', width=' + P(W) + 'cm, height=' + P(hAll)
			+ 'cm, aspect=' + P(W / hAll) + ')\n' + s.split('\n', 1)[1])
		self._writeInclude('ChipSystemFlatDiagram.tex', s)
		return

	def GenerateClockSystemDiagram(self):
		'''include/ClockSystemDiagram.tex — the MCU clock system, DRAWN FROM THE
		   REGISTER MODEL. It replaces a static vector figure
		   (figures/clocks-myshkin-2025-11) that had drifted off the chip it was
		   printed beside in five ways, every one of them contradicted by the
		   register tables on the facing pages:

		     * \\bitfield{SMCLKSEL} codes 01 and 10 were SWAPPED (the drawing fed
		       01 from DCO0 and 10 from LFXT; the register says 01 LFXT, 10
		       DCO0), so a reader who followed the picture selected the wrong
		       clock and got a 32.768 kHz chip where they wanted a DCO;
		     * code 11 was drawn CROSSED OUT on both muxes and DCO1 was absent
		       from the drawing altogether, though \\bitfield{DCO1ON},
		       \\register{DCO1BIAS} and the fourth input of both
		       \\texttt{ClockMuxGlitchFree} instances have always been there;
		     * the DCO trim was labelled \\texttt{DCO0FREQ}, which is not a
		       register this chip has (it is \\register{DCO0BIAS});
		     * the DCO enable was drawn as an active-low \\texttt{DCO0OFF}, where
		       the bit is \\bitfield{DCO0ON} and resets to 0, off;
		     * ONE "CPU Awake" switch fed ONE "CPU clock" output, on a chip whose
		       sleep gate lives INSIDE each core (\\texttt{cg\\_clk\\_cpu} in
		       vesta.vhd), one gate per hart.

		   THE FIX IS NOT A REDRAW, IT IS A DERIVATION. Every code, source,
		   ratio and consumer here is read off the generator's own model at
		   build time and ASSERTED against it:

		     * the mux legs are BUILT FROM the \\bitfield{MCLKSEL} /
		       \\bitfield{SMCLKSEL} value descriptions. The code order is the
		       register's own, and each leg is routed to the source its value
		       description NAMES (the \\texttt{\\_HFXT} / \\texttt{\\_LFXT} /
		       \\texttt{\\_DCO0} / \\texttt{\\_DCO1} / \\texttt{\\_SMCLK} suffix). The
		       swap cannot come back, because there is no hand-drawn wire left
		       to swap: the wire IS the table row;
		     * the SOURCE SET comes from bit-field PRESENCE (\\bitfield{HFXTOFF},
		       \\bitfield{LFXTOFF}, \\bitfield{DCO0ON}, \\bitfield{DCO1ON}) and is
		       cross-checked against the set the two selects reach. A
		       configuration without DCO1 drops the box, the leg and the code
		       together; it never draws a crossed-out stub;
		     * the divider ratios come from \\bitfield{SYSMCLKDIV} /
		       \\bitfield{SYSSMCLKDIV}, and the two must enumerate the same list;
		     * every peripheral is placed by its own \\texttt{clockDomain} (the
		       field generate.py sets at \\texttt{CreatePeripheral}), and the
		       drawn set is proved to BE the configured set (the E17 rule);
		     * the hart count is the master band's own
		       (\\texttt{\\_ChipSystemMasters}), so this figure and
		       Figure \\ref{fig:chip-system-flat-diagram} cannot disagree about how
		       many cores there are, and the gate is a COMPARTMENT of the hart
		       box under the stack: one gate per core, which is what the RTL
		       builds.

		   THE LAYOUT IS A MIRROR, and that is what makes it crossing-free. The
		   sources stand in ONE column, in the order \\bitfield{SMCLKSEL}
		   enumerates them. The SMCLK chain runs LEFT out of that column and
		   down; the MCLK chain runs RIGHT out of it and up. Every source-to-mux
		   leg is therefore a straight horizontal at its own row height, both
		   ways, and the two spines leave the block at opposite ends into their
		   own bars.

		   THE ONE WIRE THAT CANNOT BE STRAIGHT is \\bitfield{MCLKSEL} code 01,
		   because it is not a source at all: it is SMCLK, taken (SYSTEM.vhd,
		   \\texttt{mclk\\_mux ClkIn(1) => smclk}) AFTER the SMCLK divider and
		   BEFORE the \\bitfield{SMCLKOFF} gate, so stopping SMCLK does not stop
		   MCLK. It is drawn from that exact node, up the channel and into the
		   01 row, hopping the legs it crosses with a real gap. It is the fact
		   the retired figure was furthest from, and it is why every row here
		   prints its code AND the name of what that code selects.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None) or {}
		N = gen.NumHarts
		pkg = gen.Package
		padOfFunc = {}
		for pin in pkg.Pins:
			if pin.FuncName and pin.FuncName not in padOfFunc:
				padOfFunc[pin.FuncName] = pin.Name
		padNames = set(pin.Name for pin in pkg.Pins)

		def P(v):
			return '%.2f' % v

		# The per-character width rule of the flat whole-chip figure, and for
		# the same reason: every box height in this drawing is a LINE COUNT, and
		# a line the box is too narrow to hold does not clip, it prints through
		# the box floor.
		def TWs(t, bold=1.0):
			best = 0.0
			for line in (t or '').split('\\\\'):
				u = re.sub(r'\\[a-zA-Z]+', '', line)
				for ch in '{}$\\':
					u = u.replace(ch, '')
				w = 0.0
				for ch in u.strip():
					w += (0.185 if (ch.isupper() or ch.isdigit())
						else 0.085 if ch in ' .,:;/|!\'ilj' else 0.145)
				best = max(best, w * bold)
			return best

		tBold, tLab = 1.40, 1.77

		def wOf(title, subs, minw=2.10, maxw=5.60):
			w = TWs(title, tBold)
			for sub in subs:
				w = max(w, TWs(sub))
			return min(maxw, max(minw, 0.40 + w))

		# ---- THE REGISTER MODEL, LOOKED UP AND NEVER REMEMBERED --------------
		sysInsts = [p for p in gen.Peripherals if p.Template.NameTemplate == 'SYSTEM']
		if len(sysInsts) != 1:
			raise Exception('ClockSystemDiagram: this configuration carries '
				+ str(len(sysInsts)) + ' SYSTEM instances; the clock tree is drawn from '
				'exactly one clock monarch.')
		sysInst = sysInsts[0]
		regOf = dict((r.Name, r) for r in sysInst.Registers)
		sysBits = set(bf.Name for r in sysInst.Registers for bf in r.BitFields if bf.Name)

		def field(regName, fieldName):
			r = regOf.get(regName)
			if r is None:
				raise Exception('ClockSystemDiagram: this SYSTEM has no ' + str(regName)
					+ ' register, so the figure has nothing to draw the clock tree from.')
			for bf in r.BitFields:
				if bf.Name == fieldName:
					return bf
			raise Exception('ClockSystemDiagram: ' + str(regName) + ' carries no '
				+ str(fieldName) + ' bit field; it has '
				+ str(sorted(b.Name for b in r.BitFields if b.Name)) + '.')

		def codes(bf):
			'''(value, name suffix, description) for every code of a select, in
			   REGISTER ORDER, with the enumeration's completeness asserted: a
			   select whose codes the figure drew as a subset is a select the
			   figure would lie about.'''
			vds = list(bf.ValueDescriptions)
			if [v for v, d, n in vds] != sorted(v for v, d, n in vds):
				raise Exception('ClockSystemDiagram: ' + bf.Name + ' enumerates its codes out '
					'of value order; the figure prints them in the order the register table '
					'does, and the two would disagree.')
			if len(vds) != (1 << bf.Size) or [v for v, d, n in vds] != list(range(len(vds))):
				raise Exception('ClockSystemDiagram: ' + bf.Name + ' is ' + str(bf.Size)
					+ ' bits but enumerates ' + str([v for v, d, n in vds])
					+ '; the figure draws EVERY code of a select, so a gap in the enumeration '
					'is a leg it cannot route.')
			out = []
			for v, d, n in vds:
				if not n.startswith(bf.Name):
					raise Exception('ClockSystemDiagram: value description "' + str(n) + '" of '
						+ bf.Name + ' does not carry its own field name, so the figure cannot '
						'derive what the code selects.')
				out.append((v, n[len(bf.Name):], d))
			return out

		selM, selS = field('SYSCLKCR', 'MCLKSEL'), field('SYSCLKCR', 'SMCLKSEL')
		divM, divS = field('CLKDIVCR', 'SYSMCLKDIV'), field('CLKDIVCR', 'SYSSMCLKDIV')

		# ---- THE SOURCES, derived from BIT-FIELD PRESENCE --------------------
		# (key, printed name, its enable/disable bit, what the bit does, its
		# trim register if it is a programmable oscillator).
		_SRC_SPEC = [
			('hfxt', 'HFXT', 'HFXTOFF', 'off', None),
			('lfxt', 'LFXT', 'LFXTOFF', 'off', None),
			('dco0', 'DCO0', 'DCO0ON', 'on', 'DCO0BIAS'),
			('dco1', 'DCO1', 'DCO1ON', 'on', 'DCO1BIAS'),
		]
		_SUFFIX_SRC = dict(('_' + spec[1], spec[0]) for spec in _SRC_SPEC)
		specOf = dict((spec[0], spec) for spec in _SRC_SPEC if spec[2] in sysBits)

		# THE COLUMN ORDER IS THE SMCLKSEL CODE ORDER, not a list in this file:
		# that is what makes every SMCLK leg a straight horizontal, and it is
		# what makes a re-coded register REDRAW the picture instead of
		# mis-wiring it.
		smCodes, mcCodes = codes(selS), codes(selM)
		order = []
		for v, suf, d in smCodes:
			if suf not in _SUFFIX_SRC:
				raise Exception('ClockSystemDiagram: SMCLKSEL code ' + str(v) + ' names "'
					+ str(suf) + '", which is not a clock source this figure knows how to '
					'draw. Add it to _SRC_SPEC and give it a box, or the drawing routes a leg '
					'to nothing.')
			order.append(_SUFFIX_SRC[suf])
		if sorted(order) != sorted(specOf) or len(set(order)) != len(order):
			raise Exception('ClockSystemDiagram: SMCLKSEL selects ' + str(order)
				+ ' but the SYSCLKCR enable bits give this configuration the sources '
				+ str(sorted(specOf)) + '. The drawn source set must BE the configured one: a '
				'source with no code is a box wired to nothing, and a code with no source is '
				'the crossed-out stub this figure exists to retire.')
		rowOf = dict((k, i) for i, k in enumerate(order))

		# Every source MCLKSEL reaches must be one of those boxes; its own SMCLK
		# code is routed to the NODE, not to a source. Anything else fails here.
		mcLegs = []
		for v, suf, d in mcCodes:
			if suf == '_SMCLK':
				mcLegs.append((v, None, 'SMCLK'))
				continue
			if suf not in _SUFFIX_SRC or _SUFFIX_SRC[suf] not in specOf:
				raise Exception('ClockSystemDiagram: MCLKSEL code ' + str(v) + ' names "'
					+ str(suf) + '", which this configuration has no source box for.')
			k = _SUFFIX_SRC[suf]
			if rowOf[k] != v:
				raise Exception('ClockSystemDiagram: MCLKSEL code ' + str(v) + ' selects '
					+ specOf[k][1] + ', which SMCLKSEL puts in row ' + str(rowOf[k])
					+ '. This figure draws every source leg as a straight horizontal at its '
					'own row, so the two selects must agree on the order of the sources they '
					'share. Give the drawing a routing channel before re-coding either.')
			mcLegs.append((v, k, specOf[k][1]))
		if len([1 for v, k, nm in mcLegs if k is None]) != 1:
			raise Exception('ClockSystemDiagram: MCLKSEL takes the SMCLK node '
				+ str(len([1 for v, k, nm in mcLegs if k is None])) + ' times; the figure draws '
				'exactly one such wire, from the pre-gate node.')

		# ---- THE DIVIDERS: one ratio list, or no figure ----------------------
		def ratios(bf):
			out = []
			for v, suf, d in codes(bf):
				r = d.split(' ')[0]
				if not r.startswith('/'):
					raise Exception('ClockSystemDiagram: ' + bf.Name + ' code ' + str(v)
						+ ' is described as "' + str(d) + '", which the figure cannot read as '
						'a division ratio.')
				out.append(r)
			return out
		ratM, ratS = ratios(divM), ratios(divS)
		if ratM != ratS:
			raise Exception('ClockSystemDiagram: the MCLK divider offers ' + str(ratM)
				+ ' and the SMCLK divider ' + str(ratS) + '; the figure prints one ratio list '
				'per spine and would have to invent the difference.')
		ratTex = '\\texttt{' + '} \\texttt{'.join(ratM) + '}'

		# ---- the trim registers, by NAME from the model ----------------------
		# The retired figure printed DCO0FREQ, a register this chip has never
		# had. Nothing below is printed that was not looked up.
		for k in order:
			trim = specOf[k][4]
			if trim is not None and trim not in regOf:
				raise Exception('ClockSystemDiagram: source ' + specOf[k][1] + ' is present '
					'(its ' + specOf[k][2] + ' bit exists) but this configuration has no '
					+ trim + ' register for the figure to name as its trim.')

		# ---- THE CONSUMERS, placed by the model's own clockDomain ------------
		_GROUP = {
			'GPIOx':     ('GPIO', 'ports and their\\\\ alternate functions'),
			'SPIx':      ('SPI', 'shift engine and\\\\ baud divider'),
			'QSPIx':     ('QSPI', 'quad shift engine'),
			'UARTx':     ('UART', 'baud generator,\\\\ transmit and receive'),
			'I2Cx':      ('I\\textsuperscript{2}C', 'open-drain bit engine'),
			'I2CTx':     ('I\\textsuperscript{2}C target', 'autonomous target'),
			'I3Cx':      ('I3C', 'push-pull serial core'),
			'NFCx':      ('NFC', 'bus side and its\\\\ synchronisers'),
			'OWx':       ('1-Wire', 'bit-slot timing'),
			'TIMERx':    ('timers', 'counter, capture\\\\ and compare'),
			'PWMx':      ('PWM', 'free-running counter'),
			'RTCx':      ('RTC', 'registers, flags\\\\ and interrupt'),
			'SYSTEM':    ('SYSTEM', 'owns every register\\\\ on this page'),
			'PWRCTRL':   ('PWRCTRL', 'tile gate sequencer'),
			'CLINT':     ('CLINT', 'mtime and the\\\\ software interrupts'),
			'MUTEX':     ('MUTEX', 'claim in one\\\\ instruction'),
			'IRQROUTER': ('IRQROUTER', 'per-hart rows,\\\\ claim and complete'),
			'NPU':       ('NPU', 'inference engine'),
			'DMAx':      ('DMA', 'engine and\\\\ bus master'),
			'TRNGx':     ('TRNG', 'ring harvest and\\\\ health test'),
			'EVFAB':     ('EVFAB', 'event and trigger\\\\ fabric'),
		}
		_ALWAYS_ON = ('CLINT', 'MUTEX', 'IRQROUTER', 'PWRCTRL')
		groups = {}
		for p in gen.Peripherals:
			t = p.Template.NameTemplate
			if t not in _GROUP:
				raise Exception('ClockSystemDiagram: peripheral template "' + str(t)
					+ '" (instance ' + str(p.Name) + ') has no place in the clock figure. Add '
					'it to _GROUP, so the drawing says which clock it runs on.')
			if p.ClockDomain not in ('mclk', 'smclk', 'muxed'):
				raise Exception('ClockSystemDiagram: ' + str(p.Name) + ' declares clockDomain '
					+ str(p.ClockDomain) + '; this figure places a block by that field and '
					'would otherwise have to guess.')
			groups.setdefault((p.ClockDomain, t), []).append(p)
		drawn = set(p.Name for ps in groups.values() for p in ps)
		if drawn != set(p.Name for p in gen.Peripherals):
			raise Exception('ClockSystemDiagram: the drawn instance set ' + str(sorted(drawn))
				+ ' is not this configuration\'s ' + str(sorted(p.Name for p in gen.Peripherals))
				+ '; a clock figure that omits a block says that block has no clock.')

		def groupBox(key):
			dom, t = key
			ps = groups[key]
			title, sub = _GROUP[t]
			if len(ps) > 1:
				title += ' $\\times$' + str(len(ps))
			return {'title': title, 'subs': [sub], 'stack': len(ps), 'cells': [], 'key': key}

		fabric, mclkPer, smclkPer, muxed = [], [], [], []
		for key in sorted(groups, key=lambda k: min(p.BaseAddress for p in groups[k])):
			dom, t = key
			box = groupBox(key)
			if dom == 'muxed':
				muxed.append(box)
			elif dom == 'smclk':
				smclkPer.append(box)
			elif t in _ALWAYS_ON:
				fabric.append(box)
			else:
				mclkPer.append(box)

		# The bus arbiter is not a peripheral and never was: it IS the fabric,
		# on the free-running MCLK (MCU.vhd: mp_arb0 clk => mclk).
		fabric.insert(0, {'title': 'shared-bus arbiter', 'stack': 1, 'cells': [], 'key': None,
			'subs': ['\\texttt{mp\\_arbiter},\\\\ free-running']})
		# The Debug Module runs on that same free-running MCLK; its TAP does
		# not (see the independent domains). Both come off the ONE debug knob.
		dbgOn = bool(geo.get('debug'))
		if dbgOn:
			fabric.append({'title': 'dm0', 'stack': 1, 'cells': [], 'key': None,
				'subs': ['debug module, halts\\\\ and resumes harts']})

		# ---- the harts: the master band's count, one gate per core -----------
		masters = self._ChipSystemMasters(brief=True)
		nHartCols = sum(m['stack'] for m in masters if m['title'].startswith('hart'))
		if nHartCols != N:
			raise Exception('ClockSystemDiagram: the shared master band draws '
				+ str(nHartCols) + ' harts where this configuration has ' + str(N)
				+ '; this figure stacks one clock gate per hart and would count differently '
				'from the whole-chip figures.')
		harts = [{'title': 'harts' + (' $\\times$' + str(N) if N > 1 else ''), 'stack': N,
			'subs': ['each core gates its own clock,\\\\ and sleeps by closing it'],
			'cells': ['\\texttt{cg\\_clk\\_cpu}', 'VestaRV core'], 'key': None}]

		# ---- the independent domains: clocks that are on NEITHER spine -------
		# Derived from the knobs the blocks come from and cross-checked against
		# the peripheral list, because a domain drawn from a knob whose block is
		# absent is a clock going nowhere.
		hasTmpl = set(t for dom, t in groups)
		ind = []
		for knob, tmpl, title, sub, partner in (
				('nfc', 'NFCx', '\\texttt{rf\\_clk}',
					'the NFC0 protocol core runs on\\\\ the carrier, recovered off die',
					'NFC front end'),
				('rtc', 'RTCx', '\\texttt{lfxt\\_in}',
					'the RTC0 wall clock rides the\\\\ pad itself, ahead of every gate', None),
				('debug', None, '\\texttt{TCK}',
					'the dtm0 shift registers run on\\\\ the probe\'s own clock',
					'debug probe')):
			on = bool(geo.get(knob))
			if tmpl is not None and on != (tmpl in hasTmpl):
				raise Exception('ClockSystemDiagram: the ' + knob + ' knob says ' + str(on)
					+ ' but the peripheral list ' + ('carries' if tmpl in hasTmpl
						else 'carries no') + ' ' + tmpl + ' instance; the figure would draw a '
					'clock domain with no block in it.')
			if not on:
				continue
			subs = [sub]
			if knob == 'debug' and 'TCK' not in padNames:
				subs.append('\\textit{no ball on this package}')
			ind.append({'title': title, 'subs': subs, 'stack': 1, 'cells': [], 'key': None,
				'partner': partner})

		# ---- the timers' own select, printed in ITS register order -----------
		for box in muxed:
			dom, t = box['key']
			ssel = None
			for p in groups[box['key']]:
				for r in p.Registers:
					for bf in r.BitFields:
						if bf.Name == 'SSEL':
							ssel = bf
			if ssel is None:
				raise Exception('ClockSystemDiagram: ' + str(t) + ' declares clockDomain '
					'"muxed" but carries no SSEL select for the figure to enumerate; a block '
					'drawn between the two spines must say what it chooses between.')
			names = ['\\texttt{' + format(v, '0' + str(ssel.Size) + 'b') + '} ' + suf.lstrip('_')
				for v, suf, d in codes(ssel)]
			half = (len(names) + 1) // 2
			box['subs'] = ['\\bitfield{SSEL} picks its own source',
				', '.join(names[:half]) + ',\\\\ ' + ', '.join(names[half:])]

		# =====================================================================
		# GEOMETRY (cm). Every height is a LINE COUNT times a baseline, never a
		# guess: a TikZ node whose contents outgrow its box does not clip, it
		# prints the extra line through the floor.
		# =====================================================================
		hTitle, hLine, pad = 0.44, 0.34, 0.12
		gapIn, gapRank = 0.26, 0.62
		frmPad, frmTop, frmBot, frmGap = 0.18, 0.74, 0.22, 0.13
		stackDx, stackDy, maxShadow = 0.12, 0.20, 3
		hCells, tapLen, hRail = 0.32, 0.72, 0.84
		hPart = 1.34
		hMuxHd, gapRow = 0.72, 0.26

		def lines(subs):
			return sum(self._chipFigLines(x) for x in subs)

		def sizeBox(b):
			b['w'] = wOf(b['title'], b['subs'])
			b['h'] = hTitle + hLine * lines(b['subs']) + 2 * pad + (hCells if b['cells'] else 0.0)
			return b

		def sizeRank(rank):
			h = 0.0
			for g in rank:
				for b in g['boxes']:
					sizeBox(b)
					h = max(h, b['h'])
			for g in rank:
				g['w'] = (sum(b['w'] for b in g['boxes']) + gapIn * (len(g['boxes']) - 1)
					+ 2 * frmPad)
				for b in g['boxes']:
					b['h'] = h
			return h

		rankM = [g for g in ({'label': 'Harts', 'boxes': harts},
			{'label': 'Always-On Fabric', 'boxes': fabric},
			{'label': 'Peripherals on MCLK', 'boxes': mclkPer}) if g['boxes']]
		# `force' = frame and head this group even when it holds ONE box. The
		# house rule is that a heading over a single box is that box's title
		# again, and it holds for a type label; it does NOT hold for these two,
		# whose heading carries the whole claim (this block is on NEITHER bar /
		# this block chooses its own source). Rendered at castalia4, where the
		# lone rf_clk box lost its frame and read as a peripheral that had
		# simply missed its tap.
		rankS = [g for g in ({'label': 'Peripherals on SMCLK', 'boxes': smclkPer},
			{'label': 'Independent Domains', 'boxes': ind, 'force': True}) if g['boxes']]
		rankMid = [g for g in ({'label': 'Own Source Select', 'boxes': muxed,
			'force': True},) if g['boxes']]
		hBoxM, hBoxS = sizeRank(rankM), sizeRank(rankS)
		hBoxMid = sizeRank(rankMid) if rankMid else 0.0
		# A WOUND CONFIGURATION IS A WALL. At the digital-peripherals maximum
		# the MCLK rank is seventeen boxes, and one short line under each of
		# them is 13 cm of extra figure width -- which is 13 cm this drawing is
		# then scaled down by, taking every letter in it with them. Over the
		# budget, the two PERIPHERAL groups go to titles only (the count is
		# still in the title and still behind the box); the fabric and the harts
		# keep their lines, because what those blocks ARE is the thing this
		# figure is saying about them. MEASURED: penta_wound 58.2 cm -> 53.0 cm,
		# and the shipped default's rank is 5 cm under the budget, so the manual
		# this project ships never degrades (the budget was RAISED to 40 cm for
		# exactly that reason after the first cut stripped it). A wound rank is a wide drawing whatever is done to it; what
		# this buys is the 5 cm that come off every letter's size with it.
		briefRank = (sum(g['w'] for g in rankM) + gapRank * (len(rankM) - 1)) > 40.0
		if briefRank:
			for b in mclkPer + smclkPer:
				b['subs'] = []
			hBoxM, hBoxS = sizeRank(rankM), sizeRank(rankS)

		# ---- the generator block, left of both ranks -------------------------
		srcBoxes = []
		for k in order:
			key, name, bit, sense, trim = specOf[k]
			subs = (['\\texttt{' + fmttex(padOfFunc[name]) + '} pad function']
				if name in padOfFunc else ['on-die oscillator'])
			if trim:
				subs.append('\\register{' + trim + '} sets its frequency')
			subs.append('\\bitfield{' + bit + '} turns it ' + sense)
			srcBoxes.append(sizeBox({'title': name, 'subs': subs, 'stack': 1, 'cells': [],
				'key': k}))
		hRow = max(b['h'] for b in srcBoxes)
		wSrc = max(b['w'] for b in srcBoxes)
		for b in srcBoxes:
			b['h'], b['w'] = hRow, wSrc
		nSrc = len(order)
		hSrcCol = nSrc * hRow + (nSrc - 1) * gapRow

		divMBox = sizeBox({'title': 'MCLK divider', 'stack': 1, 'cells': [], 'key': None,
			'subs': ['\\bitfield{SYSMCLKDIV} of \\register{CLKDIVCR}', ratTex]})
		divSBox = sizeBox({'title': 'SMCLK divider', 'stack': 1, 'cells': [], 'key': None,
			'subs': ['\\bitfield{SYSSMCLKDIV} of \\register{CLKDIVCR}', ratTex]})
		gateBox = sizeBox({'title': '\\bitfield{SMCLKOFF}', 'stack': 1, 'cells': [], 'key': None,
			'subs': ['stops SMCLK for every\\\\ peripheral at once']})
		wMux = max(3.45, wSrc - 0.60)
		# THE CRYSTALS COME IN FROM THE SIDE, and they have to: the source column
		# is walled in by its own two selects, so the only edges it has left are
		# the top of its first row and the right of any row that feeds no select.
		# The off-chip partners therefore sit beyond the die's LEFT boundary at
		# the height of the routing band above both selects, and every pad wire
		# crosses that boundary on ONE straight horizontal with a pad square on
		# it. Nothing of this figure crosses a clock bar: a gap in a spine would
		# read as a break in the clock, which is the one thing a clock drawing
		# must never draw.
		xtalBoxes = []
		for i, k in enumerate(order):
			if specOf[k][1] not in padOfFunc:
				continue
			xtalBoxes.append(sizeBox({'title': specOf[k][1], 'stack': 1, 'cells': [],
				'key': k, 'row': i, 'subs': ['crystal or\\\\ oscillator']}))
		wXtal = max([b['w'] for b in xtalBoxes] + [0.0])
		hXtal = max([b['h'] for b in xtalBoxes] + [0.0])
		for b in xtalBoxes:
			b['w'], b['h'] = wXtal, hXtal

		# The channel between the source column and the MCLK select carries one
		# LANE per wire that cannot be a straight horizontal: the pad wire of
		# any crystal that is not the top row, and the SMCLK leg. Every lane
		# HOPS the legs it crosses instead of touching them.
		lanes = []
		for i, k in enumerate(order):
			if specOf[k][1] not in padOfFunc or i == 0:
				continue
			if any(kk == k for v, kk, nm in mcLegs):
				raise Exception('ClockSystemDiagram: ' + specOf[k][1] + ' arrives on a pad AND '
					'feeds MCLKSEL, but it is not the top row of the source column, so its pad '
					'wire and its mux leg would land on the same edge of the same box.')
			lanes.append({'kind': 'pad', 'row': i})
		lanes.append({'kind': 'smclk', 'row': [v for v, k, nm in mcLegs if k is None][0]})

		xDie0 = 0.20 + ((wXtal + 0.60) if xtalBoxes else 0.0)
		xGen0 = xDie0 + 0.50
		xMuxS = xGen0
		xSrc = xMuxS + wMux + 1.15
		xChan = xSrc + wSrc
		wChan = 0.46 + 0.60 * len(lanes) + 0.26
		xMuxM = xChan + wChan
		xGenR = xMuxM + wMux
		for i, ln in enumerate(lanes):
			ln['x'] = xChan + 0.46 + 0.60 * i

		# ---- widths: the ranks are justified across the die ------------------
		xRankL = xGen0
		wKey = 6.90
		wRankM = sum(g['w'] for g in rankM) + gapRank * (len(rankM) - 1)
		wRankS = sum(g['w'] for g in rankS) + gapRank * (len(rankS) - 1)
		wMid = (sum(g['w'] for g in rankMid) + gapRank * (len(rankMid) - 1)) if rankMid else 0.0
		W = max(xRankL + wRankM, xRankL + wRankS,
			xGenR + 1.10 + wMid + 0.90 + wKey) + 0.45

		# ---- vertical anchors, bottom up -------------------------------------
		yPartB = 0.00
		yPartT = yPartB + hPart
		yRedB = yPartT + 0.66
		yBoxSB = yRedB + 0.36
		yBoxST = yBoxSB + hBoxS
		yFrmST = yBoxST + frmTop
		yRailSB = yFrmST + 0.30
		yRailST = yRailSB + hRail
		yGateB = yRailST + 0.50
		yGateT = yGateB + gateBox['h']
		yNode = yGateT + 0.26          # the pre-gate SMCLK node the MCLK leg taps
		yDivSB = yNode + 0.26
		yDivST = yDivSB + divSBox['h']
		yMuxB = yDivST + 0.44
		ySrcB = yMuxB + 0.16
		ySrcT = ySrcB + hSrcCol
		yMuxT = ySrcT + hMuxHd
		# one horizontal routing lane per pad-fed source, above both selects and
		# clear of the MCLK divider above them
		# The lane pitch is the partner box's own height: the wires are what has
		# to clear the selects, but the boxes they come out of must not overlap
		# each other, and the first cut printed one crystal through the other.
		yXLane = [yMuxT + 0.30 + (hXtal + 0.30) * j for j in range(len(xtalBoxes))]
		yDivMB = (max(yXLane) if yXLane else yMuxT) + 0.44
		yDivMT = yDivMB + divMBox['h']
		yRailMB = yDivMT + 0.50
		yRailMT = yRailMB + hRail
		yBoxMB = yRailMT + tapLen
		yBoxMT = yBoxMB + hBoxM
		yFrmMT = yBoxMT + frmTop
		yRedT = yFrmMT + 0.52
		hAll = yRedT + 0.28

		yRowC = [ySrcT - hRow / 2.0 - i * (hRow + gapRow) for i in range(nSrc)]
		yMidC = (yRailST + yRailMB) / 2.0
		yMidT = yMidC + hBoxMid / 2.0
		yMidB = yMidT - hBoxMid

		# ---- x placement of the ranks ----------------------------------------
		def place(rank, xL, xR):
			if not rank:
				return
			spare = (xR - xL) - sum(g['w'] for g in rank)
			gap = max(gapRank, spare / float(len(rank) + 1))
			x = xL + max(0.0, (spare - gap * (len(rank) - 1)) / 2.0)
			for g in rank:
				g['x0'], g['x1'] = x, x + g['w']
				bx = x + frmPad
				for b in g['boxes']:
					b['cx'] = bx + b['w'] / 2.0
					b['tx'] = b['cx'] - (0.22 * b['w'] if b['stack'] > 1 else 0.0)
					bx += b['w'] + gapIn
				x += g['w'] + gap

		place(rankM, xRankL, W - 0.30)
		place(rankS, xRankL, W - 0.30)
		place(rankMid, xGenR + 1.10, W - 0.30)

		# =====================================================================
		# EMISSION
		# =====================================================================
		s = ('% Generated MCU clock system diagram (harts=' + str(N) + ', sources='
			+ str(order) + ', mclkSel=' + str([(nm if k is None else k)
				for v, k, nm in mcLegs]) + ', ratios=' + str(len(ratM)) + ', independent='
			+ str([b['title'] for b in ind]) + ', briefRank=' + str(briefRank) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\thd/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt, anchor=north},\n'
		s += '\tbc/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\tcode/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\twire/.style={->, >=Stealth, semithick},\n'
		s += '\tplain/.style={semithick},\n'
		s += '\tspine/.style={->, >=Stealth, thick},\n'
		s += ('\tnote/.style={font=\\sffamily\\scriptsize\\itshape, black!55, align=left, '
			'fill=white, inner sep=1.5pt},\n')
		s += ('\ttyp/.style={font=\\sffamily\\large\\itshape, black!55, align=left, '
			'fill=white, inner sep=1.5pt, anchor=west},\n')
		s += ('\tkey/.style={draw, thick, dashed, align=left, font=\\sffamily\\scriptsize, '
			'fill=white, inner sep=4pt},\n')
		s += '\tredlab/.style={font=\\sffamily\\small\\bfseries, red!70!black, align=left}]\n'

		def frame(cx, yTop, w, h, fill, opts='thick'):
			return ('\\draw[' + opts + ', fill=' + fill + '] (' + P(cx - w / 2.0) + ', '
				+ P(yTop - h) + ') rectangle (' + P(cx + w / 2.0) + ', ' + P(yTop) + ');\n')

		def head(cx, yTop, w, title, subs):
			tex = '{\\small\\bfseries ' + title + '}'
			for extra in subs:
				tex += '\\\\[1pt] ' + extra
			return ('\\node[hd, text width=' + P(w - 0.18) + 'cm] at (' + P(cx) + ', '
				+ P(yTop - pad) + ') {' + tex + '};\n')

		def drawBox(b, yTop, fill='black!8'):
			out = ''
			for k in range(min(b['stack'], maxShadow) - 1, 0, -1):
				out += frame(b['cx'] + stackDx * k, yTop + stackDy * k, b['w'], b['h'], fill,
					'thick, rounded corners=2pt')
			out += frame(b['cx'], yTop, b['w'], b['h'], fill, 'thick, rounded corners=2pt')
			out += head(b['cx'], yTop, b['w'], b['title'], b['subs'])
			if b['cells']:
				yD = yTop - b['h'] + hCells
				out += ('\\draw[semithick] (' + P(b['cx'] - b['w'] / 2.0) + ', ' + P(yD)
					+ ') -- (' + P(b['cx'] + b['w'] / 2.0) + ', ' + P(yD) + ');\n')
				n = len(b['cells'])
				for i, t in enumerate(b['cells']):
					xL = b['cx'] - b['w'] / 2.0 + b['w'] * i / float(n)
					if i:
						out += ('\\draw[semithick] (' + P(xL) + ', ' + P(yD) + ') -- (' + P(xL)
							+ ', ' + P(yTop - b['h']) + ');\n')
					out += ('\\node[bc, text width=' + P(b['w'] / float(n) - 0.14) + 'cm] at ('
						+ P(xL + b['w'] / (2.0 * n)) + ', ' + P(yTop - b['h'] + hCells / 2.0)
						+ ') {' + t + '};\n')
			return out

		def brokenH(y, x0, x1, cuts, opts='plain'):
			out, x = '', x0
			for cut in sorted(c for c in cuts if x0 + frmGap < c < x1 - frmGap):
				if cut - frmGap > x + 0.02:
					out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- ('
						+ P(cut - frmGap) + ', ' + P(y) + ');\n')
				x = cut + frmGap
			if x1 > x + 0.02:
				out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- (' + P(x1) + ', '
					+ P(y) + ');\n')
			return out

		def brokenV(x, y0, y1, cuts, opts='plain'):
			out, y = '', y0
			for cut in sorted(c for c in cuts if y0 + frmGap < c < y1 - frmGap):
				if cut - frmGap > y + 0.02:
					out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- (' + P(x)
						+ ', ' + P(cut - frmGap) + ');\n')
				y = cut + frmGap
			if y1 > y + 0.02:
				out += ('\\draw[' + opts + '] (' + P(x) + ', ' + P(y) + ') -- (' + P(x) + ', '
					+ P(y1) + ');\n')
			return out

		def labelIvs(xL, xR, taps):
			ivs, lo = [], xL + 0.10
			for t in sorted(t for t in taps if xL < t < xR):
				ivs.append((lo, t - 0.10))
				lo = t + 0.10
			ivs.append((lo, xR - 0.10))
			return ivs

		def typeLabel(xL, xR, taps, lab, y):
			'''A heading may not stand on a wire: it takes the widest tap-free
			   interval of its lane that will hold it, and the widest one there
			   is if none will.'''
			wLab = TWs(lab, tLab)
			best, room = None, -1.0
			for a, b in labelIvs(xL, xR, taps):
				if b - a >= wLab:
					return '\\node[typ] at (' + P(a) + ', ' + P(y) + ') {' + lab + '};\n'
				if b - a > room:
					best, room = (a, b), b - a
			return '\\node[typ] at (' + P(best[0]) + ', ' + P(y) + ') {' + lab + '};\n'

		def padSquare(x, y):
			return ('\\draw[fill=black] (' + P(x - 0.085) + ', ' + P(y - 0.085)
				+ ') rectangle (' + P(x + 0.085) + ', ' + P(y + 0.085) + ');\n')

		# ---- the package boundary, first --------------------------------------
		s += ('\\draw[red!75!black, line width=1.2pt] (' + P(xDie0) + ', ' + P(yRedB)
			+ ') rectangle (' + P(W) + ', ' + P(yRedT) + ');\n')
		s += ('\\node[redlab, anchor=north west] at (' + P(xDie0) + ', ' + P(yRedB - 0.12)
			+ ') {chip boundary};\n')

		# ---- the two spines ----------------------------------------------------
		# BOTH BARS RUN THE WHOLE RANK, and they have to: a bar that stopped
		# short of a consumer would leave that consumer's tap hanging in white
		# space (the first cut did exactly that to the hart box). Nothing else
		# in the drawing lives at their height, so the generator block below the
		# MCLK bar and above the SMCLK bar loses nothing to them.
		xRailM = xRailS = xGen0

		def rail(yB, yT, x0, title, note):
			out = ('\\draw[thick, fill=black!15] (' + P(x0) + ', ' + P(yB) + ') rectangle ('
				+ P(W - 0.30) + ', ' + P(yT) + ');\n')
			out += ('\\node[bc, text width=' + P(W - 0.60 - x0) + 'cm] at ('
				+ P((x0 + W - 0.30) / 2.0) + ', ' + P((yB + yT) / 2.0) + ') {{\\small\\bfseries '
				+ title + '} \\quad ' + note + '};\n')
			return out

		s += rail(yRailMB, yRailMT, xRailM, 'MCLK', 'the main clock: every hart, the shared-bus '
			'fabric and the always-on blocks \\quad it has no chip-wide off switch')
		s += rail(yRailSB, yRailST, xRailS, 'SMCLK', 'the submain clock: the serial engines of '
			'the peripherals \\quad \\bitfield{SMCLKOFF} stops all of them at once')

		# ---- the source column, and the crystals off the die -------------------
		xSrcC = xSrc + wSrc / 2.0
		for j, pb in enumerate(xtalBoxes):
			i = pb['row']
			yLane = yXLane[j]
			pb['cx'] = 0.20 + wXtal / 2.0
			s += drawBox(pb, yLane + hXtal / 2.0, 'white')
			lane = [ln for ln in lanes if ln['kind'] == 'pad' and ln['row'] == i]
			xw = lane[0]['x'] if lane else xSrcC
			# across the boundary on one straight horizontal, then down its own
			# lane to the one free edge its row has
			s += ('\\draw[plain] (' + P(0.20 + wXtal) + ', ' + P(yLane) + ') -- (' + P(xw)
				+ ', ' + P(yLane) + ');\n')
			s += padSquare(xDie0, yLane)
			if lane:
				cuts = [yRowC[rowOf[kk]] for v, kk, nm in mcLegs
					if kk is not None and yRowC[i] < yRowC[rowOf[kk]] < yLane]
				s += brokenV(xw, yRowC[i], yLane, cuts)
				s += ('\\draw[wire] (' + P(xw) + ', ' + P(yRowC[i]) + ') -- (' + P(xChan)
					+ ', ' + P(yRowC[i]) + ');\n')
			else:
				s += ('\\draw[wire] (' + P(xw) + ', ' + P(yLane) + ') -- (' + P(xw) + ', '
					+ P(yRowC[i] + hRow / 2.0) + ');\n')
		for i, b in enumerate(srcBoxes):
			b['cx'] = xSrcC
			s += drawBox(b, yRowC[i] + hRow / 2.0, 'white')
		# The heading sits in the band the two selects use for their own, and it
		# keeps out of the one wire that crosses that band (the top row's pad).
		s += typeLabel(xSrc - 0.10, xSrc + wSrc + 0.10, [xSrcC], 'Clock Sources',
			ySrcT + hMuxHd / 2.0)

		# ---- the two glitch-free selects -------------------------------------
		def muxBox(x0, w, title, sub, rows):
			out = frame(x0 + w / 2.0, yMuxT, w, yMuxT - yMuxB, 'black!4', 'thick')
			out += ('\\node[bc, text width=' + P(w - 0.20) + 'cm] at (' + P(x0 + w / 2.0) + ', '
				+ P(yMuxT - hMuxHd / 2.0) + ') {{\\small\\bfseries ' + title + '}\\\\[1pt] '
				+ sub + '};\n')
			for i, (codeTex, nameTex) in enumerate(rows):
				out += frame(x0 + w / 2.0, yRowC[i] + hRow / 2.0, w - 0.30, hRow, 'white',
					'semithick, rounded corners=1pt')
				out += ('\\node[code] at (' + P(x0 + w / 2.0) + ', ' + P(yRowC[i])
					+ ') {\\texttt{' + codeTex + '}\\\\[1pt] {\\bfseries ' + nameTex + '}};\n')
			return out

		def codeTex(bf, v):
			return format(v, '0' + str(bf.Size) + 'b')

		s += muxBox(xMuxS, wMux, 'SMCLK select', '\\bitfield{SMCLKSEL}, glitch-free',
			[(codeTex(selS, v), specOf[_SUFFIX_SRC[suf]][1]) for v, suf, d in smCodes])
		s += muxBox(xMuxM, wMux, 'MCLK select', '\\bitfield{MCLKSEL}, glitch-free',
			[(codeTex(selM, v), (nm if k is None else specOf[k][1])) for v, k, nm in mcLegs])

		# ---- the legs. Every source leg is a straight horizontal at its own
		# row, both ways: that is what the mirror layout buys.
		for i, k in enumerate(order):
			s += ('\\draw[wire] (' + P(xSrc) + ', ' + P(yRowC[i]) + ') -- ('
				+ P(xMuxS + wMux) + ', ' + P(yRowC[i]) + ');\n')
		legY = []
		for v, k, nm in mcLegs:
			if k is None:
				continue
			y = yRowC[rowOf[k]]
			legY.append(y)
			s += ('\\draw[wire] (' + P(xChan) + ', ' + P(y) + ') -- (' + P(xMuxM) + ', '
				+ P(y) + ');\n')

		# ---- THE ONE WIRE THAT IS NOT STRAIGHT -------------------------------
		# MCLKSEL's SMCLK code, from the node the RTL takes it from: after the
		# SMCLK divider, BEFORE the SMCLKOFF gate (SYSTEM.vhd, mclk_mux
		# ClkIn(1) => smclk), so stopping SMCLK never stops MCLK. Up its own
		# lane, hopping the legs it crosses.
		fbLane = [ln for ln in lanes if ln['kind'] == 'smclk'][0]
		yFb = yRowC[fbLane['row']]
		s += ('\\draw[plain] (' + P(xMuxS + wMux / 2.0) + ', ' + P(yNode) + ') -- ('
			+ P(fbLane['x']) + ', ' + P(yNode) + ');\n')
		s += brokenV(fbLane['x'], yNode, yFb, [y for y in legY if yNode < y < yFb])
		s += ('\\draw[wire] (' + P(fbLane['x']) + ', ' + P(yFb) + ') -- (' + P(xMuxM) + ', '
			+ P(yFb) + ');\n')
		# The note goes BESIDE the wire, never on it: a white label box sitting
		# on a wire reads as an open circuit (the AFE figure was rejected for
		# exactly that).
		s += ('\\node[note, anchor=south west] at (' + P(xMuxS + wMux / 2.0 + divSBox['w'] / 2.0
			+ 0.25) + ', ' + P(yNode + 0.10) + ') {the divided SMCLK, ahead of its gate};\n')

		# ---- the dividers, the gate, and the two spine risers -----------------
		divMBox['cx'] = xMuxM + wMux / 2.0
		divSBox['cx'] = xMuxS + wMux / 2.0
		gateBox['cx'] = xMuxS + wMux / 2.0
		s += drawBox(divMBox, yDivMT)
		s += drawBox(divSBox, yDivST)
		s += drawBox(gateBox, yGateT)
		xChain = xMuxM + wMux / 2.0
		s += ('\\draw[wire] (' + P(xChain) + ', ' + P(yMuxT) + ') -- (' + P(xChain) + ', '
			+ P(yDivMB) + ');\n')
		s += ('\\draw[spine] (' + P(xChain) + ', ' + P(yDivMT) + ') -- (' + P(xChain) + ', '
			+ P(yRailMB) + ');\n')
		xChainS = xMuxS + wMux / 2.0
		s += ('\\draw[wire] (' + P(xChainS) + ', ' + P(yMuxB) + ') -- (' + P(xChainS) + ', '
			+ P(yDivST) + ');\n')
		s += ('\\draw[wire] (' + P(xChainS) + ', ' + P(yDivSB) + ') -- (' + P(xChainS) + ', '
			+ P(yGateT) + ');\n')
		s += ('\\draw[spine] (' + P(xChainS) + ', ' + P(yGateB) + ') -- (' + P(xChainS) + ', '
			+ P(yRailST) + ');\n')

		# ---- the ranks -------------------------------------------------------
		fo = 'black!45, line width=0.5pt'

		def drawFrame(g, yB, yT, cutsB, cutsT, label, yLab):
			out = brokenH(yB, g['x0'], g['x1'], cutsB, fo)
			out += brokenH(yT, g['x0'], g['x1'], cutsT, fo)
			out += ('\\draw[' + fo + '] (' + P(g['x0']) + ', ' + P(yB) + ') -- (' + P(g['x0'])
				+ ', ' + P(yT) + ');\n')
			out += ('\\draw[' + fo + '] (' + P(g['x1']) + ', ' + P(yB) + ') -- (' + P(g['x1'])
				+ ', ' + P(yT) + ');\n')
			out += typeLabel(g['x0'], g['x1'], cutsT, label, yLab)
			return out

		yFrmMB = yBoxMB - frmBot
		for g in rankM:
			taps = [b['tx'] for b in g['boxes']]
			if len(g['boxes']) > 1 or g.get('force'):
				s += drawFrame(g, yFrmMB, yFrmMT, taps, [], g['label'], yFrmMT)
			for b in g['boxes']:
				s += ('\\draw[wire] (' + P(b['tx']) + ', ' + P(yRailMT) + ') -- (' + P(b['tx'])
					+ ', ' + P(yBoxMB) + ');\n')
				s += drawBox(b, yBoxMT)

		yFrmSB = yBoxSB - frmBot
		for g in rankS:
			taps = [b['tx'] for b in g['boxes'] if b.get('partner') is None]
			drops = [b['cx'] for b in g['boxes'] if b.get('partner')]
			if len(g['boxes']) > 1 or g.get('force'):
				s += drawFrame(g, yFrmSB, yFrmST, drops, taps, g['label'], yFrmST)
			for b in g['boxes']:
				if b.get('partner') is None and 'partner' not in b:
					s += ('\\draw[wire] (' + P(b['tx']) + ', ' + P(yRailSB) + ') -- ('
						+ P(b['tx']) + ', ' + P(yBoxST) + ');\n')
				s += drawBox(b, yBoxST)
				if b.get('partner'):
					pb = {'title': b['partner'], 'stack': 1, 'cells': [], 'key': None,
						'subs': ['\\textit{off die}']}
					sizeBox(pb)
					pb['h'], pb['cx'] = hPart, b['cx']
					s += drawBox(pb, yPartT, 'white')
					s += ('\\draw[wire] (' + P(b['cx']) + ', ' + P(yPartT) + ') -- ('
						+ P(b['cx']) + ', ' + P(yBoxSB) + ');\n')
					s += padSquare(b['cx'], yRedB)

		for g in rankMid:
			if len(g['boxes']) > 1 or g.get('force'):
				s += drawFrame(g, yMidB - frmBot, yMidT + frmTop, [], [], g['label'],
					yMidT + frmTop)
			for b in g['boxes']:
				s += drawBox(b, yMidT)
				s += ('\\draw[wire] (' + P(b['cx'] - 0.55) + ', ' + P(yRailMB) + ') -- ('
					+ P(b['cx'] - 0.55) + ', ' + P(yMidT) + ');\n')
				# UP FROM THE BAR'S TOP EDGE, never from inside it: a tap that
				# starts at the far edge is drawn straight through the clock it
				# is tapping.
				s += ('\\draw[wire] (' + P(b['cx'] + 0.55) + ', ' + P(yRailST) + ') -- ('
					+ P(b['cx'] + 0.55) + ', ' + P(yMidB) + ');\n')

		# ---- the key, in the dead space between the spines --------------------
		s += ('\\node[key, anchor=north east, text width=' + P(wKey - 0.40) + 'cm] at ('
			+ P(W - 0.40) + ', ' + P(yRailMB - 0.55) + ') {\\textbf{how to read this}\\\\[2pt] '
			'a grey bar is a clock, and every block on it taps it straight\\\\[1pt] '
			'a box on a wire is a real gate, named by the bit that opens it\\\\[1pt] '
			'$\\times N$ and the squares behind a box are $N$ copies of it, each with its own '
			'gate\\\\[1pt] '
			'a wire that hops another does not touch it};\n')

		s += '\\end{tikzpicture}\n'
		s = (s.split('\n', 1)[0][:-1] + ', width=' + P(W) + 'cm, height=' + P(hAll)
			+ 'cm, aspect=' + P(W / hAll) + ')\n' + s.split('\n', 1)[1])
		self._writeInclude('ClockSystemDiagram.tex', s)
		return

	def GenerateTcmApertureDiagram(self):
		'''include/TcmApertureDiagram.tex — what ONE read through a TCM aperture
		   actually does. Emitted unconditionally (the DEBUG-figure precedent);
		   the multi-core chapter \\input{}s it inside its own \\iforchpresent, so
		   a configuration without apertures never renders it. Three bands,
		   left to right, because that is the direction the transaction travels:
		   the shared fabric | the tile boundary | inside the tile.

		   DRAWN FROM THE RTL, with the lines it was transcribed from:
		     * the aperture slave and its three gates, the s_stall argument and
		       the dark-tile self-completion — hdl/common/MCU.vhd:592-656 (the
		       declaration block that states the contract) and :3676-3755 (the
		       decode, the launch term and the tcm_aperture process).
		     * s_stall itself — hdl/common/mp_arbiter.vhd:95-108 (the port and
		       why it exists) and :244-256 (LATCH holds while it is high).
		     * the tile-side port: 6 mclk request-to-done, the four-state
		       sequencer, the SRAM pin mux with its write side tied off, and the
		       Q shadow that covers the frozen core — hdl/common/hart_tile.vhd:
		       78-124 (the contract), :285-322 (the port + protocol), :1063-1180
		       (the sequencer and its cycle table), :1240-1355 (the Q shadow).
		     * the isolation clamp that zeroes rdata AND done — MCU.vhd:3245-3276.'''
		windows = self._TcmApertureWindows()
		tcmKiB = self.Gen.RamMemorySlotSize // 1024
		if not windows:
			# No apertures in this configuration. The chapter's \input sits
			# inside \iforchpresent so TeX never reaches it, but a stub keeps
			# the include set the same shape in both polarities.
			self._writeInclude('TcmApertureDiagram.tex',
				'% This configuration has no TCM apertures (no orchestrator).\n')
			return

		def P(v):
			return '%.2f' % v

		# ---- the window key, and the E17 assertion over it. Enumerable content
		# gets drawn AND checked: the pairs are parsed back out of the emitted
		# node, so a map change the key does not follow fails `make generate`.
		if len(windows) <= 5:
			keyHarts = list(range(len(windows)))
		else:
			keyHarts = [0, 1, None, len(windows) - 1]
		keyParts = []
		for h in keyHarts:
			if h is None:
				keyParts.append('$\\cdots$')
				continue
			keyParts.append('hart~' + str(h) + '~\\texttt{' + fmthex(windows[h]) + '}')
		keyTex = ('\\textbf{the ' + _numberWord(len(windows)) + ' windows, one per hart}\\\\ '
			+ ' \\quad '.join(keyParts))
		drawn = [(int(a), int(b, 16)) for a, b in re.findall(r'hart~(\d+)~\\texttt\{(0x[0-9A-F]+)\}', keyTex)]
		expected = [(h, windows[h]) for h in keyHarts if h is not None]
		if drawn != expected:
			raise Exception('TcmApertureDiagram: the drawn window key %s is not the configuration\'s '
				'aperture list %s' % (drawn, expected))

		# ---- geometry, in cm
		fX0, fX1 = 0.00, 9.20          # band 1: the shared fabric
		wX0, wX1 = 9.20, 12.00         # band 2: the tile boundary
		iX0, iX1 = 12.00, 21.40        # band 3: inside the tile
		yBot, yTop = -2.40, 9.95
		yBan = 9.10                    # banner strip floor
		fCx = (fX0 + fX1) / 2.0
		yKey, keyH = 8.30, 0.90
		yH0, h0H = 7.00, 1.05
		yArb, arbH = 5.40, 1.20
		ySlv, slvH = 3.30, 1.65
		yZero, zeroH = 0.15, 1.35      # dropped 0.55 cm: the two branch labels had
		                               # 0.15 cm of air above this box, and band 1's
		                               # bottom was dead space anyway
		xLoad = 3.60                   # the hart-0 -> arbiter arrow. NOT fCx: its label
		                               # is 4.4 cm wide and anchors east of the line, so
		                               # on the centre line it ran off the end of band 1.
		xAcc, xStall = 6.20, 2.40      # the two arrows between arbiter and slave
		xDenied, xDark = 2.30, 6.50    # the two branches into the zero answer
		yReq, yRsp = 3.80, 2.80        # the two crossings
		clCx, clW, clH = 10.60, 1.80, 0.95
		seqCx, ySeq, seqW, seqH = 15.30, 3.30, 5.60, 1.90
		muxCx, yMux, muxW, muxH = 16.00, 0.45, 7.20, 1.70
		yLeaf, leafH = -1.65, 0.95

		s = ('% Generated TCM aperture mechanism figure (' + str(len(windows))
			+ ' windows of ' + str(tcmKiB) + ' KiB from ' + fmthex(windows[0]) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small},\n'
		s += '\tunit/.style={blk, fill=black!12},\n'
		s += '\tzero/.style={blk, fill=black!20},\n'
		s += '\tsig/.style={->, >=Stealth, thick},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\tcross/.style={->, >=Stealth, line width=1.5pt},\n'
		s += '\tban/.style={font=\\sffamily\\scriptsize\\bfseries, black!65, align=center},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=center},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left}]\n'

		# ---- the three bands
		s += '\\fill[black!4] (' + P(fX0) + ', ' + P(yBot) + ') rectangle (' + P(fX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!11] (' + P(wX0) + ', ' + P(yBot) + ') rectangle (' + P(wX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!6] (' + P(iX0) + ', ' + P(yBot) + ') rectangle (' + P(iX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!14] (' + P(fX0) + ', ' + P(yBan) + ') rectangle (' + P(fX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!22] (' + P(wX0) + ', ' + P(yBan) + ') rectangle (' + P(wX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!18] (' + P(iX0) + ', ' + P(yBan) + ') rectangle (' + P(iX1) + ', ' + P(yTop) + ');\n'
		s += ('\\node[ban, text width=' + P(fX1 - fX0 - 0.30) + 'cm] at (' + P(fCx) + ', ' + P((yBan + yTop) / 2.0)
			+ ') {the shared fabric, always on};\n')
		s += ('\\node[ban, text width=' + P(wX1 - wX0 - 0.30) + 'cm] at (' + P((wX0 + wX1) / 2.0) + ', '
			+ P((yBan + yTop) / 2.0) + ') {the registered tile boundary};\n')
		s += ('\\node[ban, text width=' + P(iX1 - iX0 - 0.30) + 'cm] at (' + P((iX0 + iX1) / 2.0) + ', '
			+ P((yBan + yTop) / 2.0) + ') {inside hart $h$\'s tile};\n')

		# ---- band 1: who asks, what carries it, and what the slave decides
		s += ('\\node[lab, draw, thick, fill=white, minimum width=' + P(fX1 - fX0 - 0.60) + 'cm, minimum height='
			+ P(keyH) + 'cm, text width=' + P(fX1 - fX0 - 0.90) + 'cm] at (' + P(fCx) + ', ' + P(yKey) + ') {' + keyTex + '};\n')
		s += ('\\node[unit, minimum width=7.20cm, minimum height=' + P(h0H) + 'cm] (h0) at (' + P(fCx) + ', '
			+ P(yH0) + ') {\\textbf{hart 0}, the management hart\\\\ \\scriptsize \\texttt{lw} from window $h$, word $i$};\n')
		s += ('\\node[unit, minimum width=8.60cm, minimum height=' + P(arbH) + 'cm] (arb) at (' + P(fCx) + ', '
			+ P(yArb) + ') {\\textbf{mp\\_arbiter}\\\\ \\scriptsize \\textit{IDLE} $\\to$ \\textit{LATCH} $\\to$ \\textit{DATA}, the grant pinned to hart 0};\n')
		s += '\\draw[sig] (' + P(xLoad) + ', ' + P(yH0 - h0H / 2.0) + ') -- (' + P(xLoad) + ', ' + P(yArb + arbH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=west, fill=black!4, inner sep=1pt] at (' + P(xLoad + 0.18) + ', '
			+ P((yH0 - h0H / 2.0 + yArb + arbH / 2.0) / 2.0) + ') {one ordinary shared-window load};\n')
		s += ('\\node[blk, minimum width=8.60cm, minimum height=' + P(slvH) + 'cm] (slv) at (' + P(fCx) + ', '
			+ P(ySlv) + ') {\\textbf{the aperture slave}\\\\ \\scriptsize is the reader hart 0? is it a read?\\\\'
			+ ' \\scriptsize is the addressed tile awake?};\n')
		yMid1 = (yArb - arbH / 2.0 + ySlv + slvH / 2.0) / 2.0
		s += '\\draw[sig] (' + P(xAcc) + ', ' + P(yArb - arbH / 2.0) + ') -- (' + P(xAcc) + ', ' + P(ySlv + slvH / 2.0) + ');\n'
		s += ('\\node[lab, fill=white, inner sep=1.5pt] at (' + P(xAcc) + ', ' + P(yMid1) + ') {the access};\n')
		s += '\\draw[sig] (' + P(xStall) + ', ' + P(ySlv + slvH / 2.0) + ') -- (' + P(xStall) + ', ' + P(yArb - arbH / 2.0) + ');\n'
		s += ('\\node[lab, fill=white, inner sep=1.5pt] at (' + P(xStall) + ', ' + P(yMid1)
			+ ') {\\textbf{hold everything still} (\\register{s\\_stall})};\n')

		# ---- the two answers the slave gives itself, each a real branch
		s += ('\\node[zero, minimum width=8.60cm, minimum height=' + P(zeroH) + 'cm] (zro) at (' + P(fCx) + ', '
			+ P(yZero) + ') {\\textbf{the slave answers zeros itself}\\\\ \\scriptsize in the same three cycles every other slave takes,\\\\'
			+ ' \\scriptsize so the bus never waits on a word that is not coming};\n')
		yMid2 = (ySlv - slvH / 2.0 + yZero + zeroH / 2.0) / 2.0
		s += '\\draw[sig] (' + P(xDenied) + ', ' + P(ySlv - slvH / 2.0) + ') -- (' + P(xDenied) + ', ' + P(yZero + zeroH / 2.0) + ');\n'
		s += ('\\node[lab, fill=white, inner sep=1.5pt, text width=2.90cm] at (' + P(xDenied) + ', ' + P(yMid2)
			+ ') {another hart asks, or it is a write};\n')
		s += '\\draw[sig] (' + P(xDark) + ', ' + P(ySlv - slvH / 2.0) + ') -- (' + P(xDark) + ', ' + P(yZero + zeroH / 2.0) + ');\n'
		s += ('\\node[lab, fill=white, inner sep=1.5pt, text width=2.90cm] at (' + P(xDark) + ', ' + P(yMid2)
			+ ') {the \\textbf{target tile is powered off}};\n')

		# ---- band 2: the crossings, and the clamp that makes the branch real
		s += '\\draw[cross] (' + P(fX1 - 0.60) + ', ' + P(yReq) + ') -- (' + P(seqCx - seqW / 2.0) + ', ' + P(yReq) + ');\n'
		# Both band-2 captions are anchored to the EDGE they must clear, never
		# centred on a guessed midpoint: a centred node's height is whatever the
		# wrapped text turns out to be, and the response caption's fill=black!11
		# used to reach 0.05 cm INTO the clamp — repainting the band colour over
		# its bottom border and shipping a three-sided box. anchor=north/south
		# makes the clearance the thing that is specified.
		s += ('\\node[lab, fill=black!11, inner sep=2pt, text width=2.55cm, anchor=south] at ('
			+ P((wX0 + wX1) / 2.0) + ', ' + P(yReq + 0.30)
			+ ') {\\register{tcm\\_ext\\_req} and a 12-bit TCM word index};\n')
		s += '\\draw[cross] (' + P(seqCx - seqW / 2.0) + ', ' + P(yRsp) + ') -- (' + P(clCx + clW / 2.0) + ', ' + P(yRsp) + ');\n'
		s += ('\\node[unit, minimum width=' + P(clW) + 'cm, minimum height=' + P(clH) + 'cm, font=\\sffamily\\scriptsize] (clamp) at ('
			+ P(clCx) + ', ' + P(yRsp) + ') {isolation\\\\ clamp};\n')
		s += '\\draw[cross] (' + P(clCx - clW / 2.0) + ', ' + P(yRsp) + ') -- (' + P(fX1 - 0.60) + ', ' + P(yRsp) + ');\n'
		s += ('\\node[lab, fill=black!11, inner sep=2pt, text width=2.55cm, anchor=north] at ('
			+ P((wX0 + wX1) / 2.0) + ', ' + P(yRsp - clH / 2.0 - 0.35)
			+ ') {the word, six \\register{mclk} later, or nothing at all, because this clamp zeroes a dark tile\'s \\register{tcm\\_ext\\_done} too};\n')

		# ---- band 3: the port, the pins it borrows, and the memory
		s += ('\\node[unit, minimum width=' + P(seqW) + 'cm, minimum height=' + P(seqH) + 'cm] (seq) at ('
			+ P(seqCx) + ', ' + P(ySeq) + ') {\\textbf{the tile\'s own TCM read port}\\\\ \\scriptsize four states, one SRAM read:\\\\'
			+ ' \\scriptsize \\textit{SETTLE} $\\to$ \\textit{READ} $\\to$ \\textit{LATCH},\\\\'
			+ ' \\scriptsize then one \\register{mclk} of \\register{tcm\\_ext\\_done}\\\\ \\scriptsize with the word riding on it};\n')
		s += ('\\node[blk, minimum width=' + P(muxW) + 'cm, minimum height=' + P(muxH) + 'cm, text width='
			+ P(muxW - 0.40) + 'cm] (mux) at ('
			+ P(muxCx) + ', ' + P(yMux) + ') {\\textbf{either the core or the port drives the TCM\'s pins, never both}\\\\'
			+ ' \\scriptsize the port\'s side of the mux holds the write strobes off, so no state of it can write};\n')
		s += '\\draw[sig] (' + P(seqCx) + ', ' + P(ySeq - seqH / 2.0) + ') -- (' + P(seqCx) + ', ' + P(yMux + muxH / 2.0) + ');\n'
		s += ('\\node[note, anchor=west] at (' + P(seqCx + 0.18) + ', '
			+ P((ySeq - seqH / 2.0 + yMux + muxH / 2.0) / 2.0) + ') {takes the pins, and\\\\ stops the core\'s clock};\n')
		s += ('\\node[blk, minimum width=3.60cm, minimum height=' + P(leafH) + 'cm] (tcm) at (13.90, ' + P(yLeaf)
			+ ') {' + str(tcmKiB) + '\\,KiB TCM\\\\ \\scriptsize \\texttt{0x8000}--\\texttt{0xBFFF}};\n')
		s += ('\\node[blk, minimum width=3.20cm, minimum height=' + P(leafH) + 'cm] (cre) at (18.10, ' + P(yLeaf)
			+ ') {the VestaRV core};\n')
		s += '\\draw[bus] (13.90, ' + P(yMux - muxH / 2.0) + ') -- (13.90, ' + P(yLeaf + leafH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=east] at (13.72, ' + P((yMux - muxH / 2.0 + yLeaf + leafH / 2.0) / 2.0)
			+ ') {one read};\n')
		s += '\\draw[bus] (18.10, ' + P(yLeaf + leafH / 2.0) + ') -- (18.10, ' + P(yMux - muxH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=west] at (18.28, ' + P((yMux - muxH / 2.0 + yLeaf + leafH / 2.0) / 2.0)
			+ ') {its own loads\\\\ and stores};\n')
		s += ('\\node[note, text width=12.60cm, align=center] at (' + P((fX0 + iX1) / 2.0) + ', ' + P(yBot - 0.50)
			+ ') {\\textit{While the port has those pins the core\'s clock is gated off for seven edges, and the'
			+ ' Q shadow keeps showing it the word it last read, so the frozen core can never mistake'
			+ ' the aperture\'s word for its own.}};\n')
		s += '\\end{tikzpicture}\n'
		self._writeInclude('TcmApertureDiagram.tex', s)
		return

	# -----------------------------------------------------------------
	# NPU datapath figure (W4). Everything the drawing asserts is either
	# DERIVED from the configuration model or PARSED back out of the source
	# that owns it, and checked here so a change to the RTL, the register
	# descriptions or the memory map fails `make generate` instead of leaving
	# a wrong picture in the manual.
	#
	# SOURCES — do not edit these from memory:
	#   hdl/common/periph/NPU.vhd            (the port mux, its select flop,
	#                                         the six-state sequencer, the
	#                                         activation constants)
	#   hdl/common/commune/FPMac.vhd         (the accumulator: one sfixed
	#                                         resize per step, so fixed_pkg's
	#                                         default round-to-nearest and
	#                                         saturate apply at EVERY step)
	#   hdl_templates/MCU.template.npu.vhd   (the Q generics of THIS chip's
	#                                         instance, and the comment that
	#                                         says npu0_active sleeps nobody)
	#   generate.py NPUMODE / NPUACTF        (the mode and activation lists)
	#   Gen.SharedWindowSections             (the staging RAM's geometry)
	#   Gen.McuMpCompat['irqVectors']        (the think-done vector number)
	# -----------------------------------------------------------------

	# The mode and activation lists the figure DRAWS, as
	# (code, drawn label, a phrase that must appear in that code's own sentence
	# of the register description). The labels are the figure's English; the
	# phrases are the tie to the register model, checked below. A code added,
	# renumbered or reworded in generate.py therefore fails the build here
	# rather than shipping a four-way frame that has grown a fifth mode.
	_NPU_MODES = [
		(0, 'MLP',            'dense layer',        'multilayer-perceptron'),
		(1, '1-D convolution', 'taps and filters',  'one-dimensional convolution'),
		(2, 'XNOR-popcount',  'binary, 32 per word', 'XNOR-popcount'),
		(3, 'GEMM',           '$C = A \\times B$',  'general matrix-multiply'),
	]
	_NPU_ACTS = [
		(0, 'sigmoid', 'logistic sigmoid'),
		(1, 'ReLU',    'ReLU'),
		(2, 'tanh',    'tanh'),
		(3, 'clamp',   'clamp'),
		(4, 'exp',     'exponential approximation'),
	]
	# The sequencer states this figure names, in the order the RTL walks them.
	_NPU_STATES = ['NPU_BEGIN', 'NPU_GET_WEIGHT', 'NPU_GET_INPUT', 'NPU_MAC',
		'NPU_SET_OUTPUT', 'NPU_FINISH']

	def _NpuCodedList(self, field, drawn, what):
		'''Parse a `0 = ... 1 = ...` coded list back out of a BitField's own
		   description and check the figure's transcription against it. The
		   codes must be exactly the drawn ones, in order, and each drawn
		   entry's phrase must appear in that code's sentence.'''
		desc = field.Description
		hits = list(re.finditer(r'(?:^|\.\s+)([0-7]) = ', desc))
		parsed = {}
		for i, h in enumerate(hits):
			end = hits[i + 1].start() if i + 1 < len(hits) else len(desc)
			parsed[int(h.group(1))] = desc[h.end():end]
		want = [d[0] for d in drawn]
		if sorted(parsed.keys()) != want:
			raise Exception('NpuDatapathDiagram: %s draws codes %s but %s describes %s '
				'— the figure and the register table would disagree.'
				% (what, want, field.Name, sorted(parsed.keys())))
		for entry in drawn:
			code, phrase = entry[0], entry[-1]
			if phrase.lower() not in parsed[code].lower():
				raise Exception('NpuDatapathDiagram: %s code %d is drawn as %r, but %s\'s '
					'description of that code (%r) no longer says %r.'
					% (what, code, entry[1], field.Name, parsed[code][:80], phrase))
		return parsed

	def _NpuFacts(self):
		'''Every number and name the figure prints, derived and cross-checked.
		   Returns None when this configuration has no NPU.'''
		gen = self.Gen
		# The template is registered as `NPU', so the single instance is named
		# NPU (no index); match the template rather than a guessed spelling.
		npu = [p for p in gen.Peripherals if p.Template.NameTemplate == 'NPU']
		if not npu:
			return None
		npu = npu[0]

		def field(regName, fieldName):
			for r in npu.Registers:
				if r.Name != regName:
					continue
				for f in r.BitFields:
					if f.Name == fieldName:
						return f
			raise Exception('NpuDatapathDiagram: %s.%s is not in the generated register '
				'model any more.' % (regName, fieldName))

		# ---- the mode and activation lists, against their own descriptions
		modeField = field('NPUCR', 'NPUMODE')
		actField = field('NPUCR', 'NPUACTF')
		self._NpuCodedList(modeField, self._NPU_MODES, 'the mode frame')
		self._NpuCodedList(actField, self._NPU_ACTS, 'the activation frame')
		# The reserved tails are drawn as words, so they are checked as words.
		if 'Codes 4-7 are reserved' not in modeField.Description:
			raise Exception('NpuDatapathDiagram: NPUMODE no longer reserves codes 4-7; '
				'the drawn four-way frame would be incomplete.')
		if 'Codes 5-7 are reserved' not in actField.Description:
			raise Exception('NpuDatapathDiagram: NPUACTF no longer reserves codes 5-7; '
				'the drawn activation note would be wrong.')

		# ---- the staging RAM, from the address-space model, cross-checked
		# against the resolved configuration's own byte count (two independent
		# products of the same arithmetic, the _TcmApertureWindows pattern).
		stage = [sec for sec in (gen.SharedWindowSections or []) if sec[0] == 'NPU staging RAM']
		if len(stage) != 1:
			raise Exception('NpuDatapathDiagram: the NPU is instantiated but the shared '
				'window has %d staging-RAM rows — the figure could not place it.' % len(stage))
		base, last = int(stage[0][1]), int(stage[0][2])
		size = last - base + 1
		rc = getattr(gen, 'ResolvedConfig', None) or {}
		cfgSize = ((rc.get('memory') or {}).get('npuStagingRamSize'))
		if cfgSize is not None and int(cfgSize) != size:
			raise Exception('NpuDatapathDiagram: the shared window gives the staging RAM %d '
				'bytes but memory.npuStagingRamSize resolves to %d.' % (size, cfgSize))
		words = size // 4
		# The pointer registers hold WORD INDICES, so their width has to cover
		# the word count: a staging RAM the pointers cannot address is a figure
		# that draws a tap which cannot reach.
		ptrBits = field('NPUIVSAR', 'NPUIVSAR').Size
		if (1 << ptrBits) < words:
			raise Exception('NpuDatapathDiagram: the staging RAM holds %d words but the '
				'vector pointers are only %d bits wide.' % (words, ptrBits))

		# ---- the think-done vector, from the emitted IRQ source list
		vectors = [n for n, _ in (getattr(gen, 'McuMpCompat', {}) or {}).get('irqVectors', [])]
		if 'IRQB_NPU0_TD' not in vectors:
			raise Exception('NpuDatapathDiagram: the NPU is instantiated but IRQB_NPU0_TD is '
				'not in the emitted interrupt source list, so the figure has no vector to draw.')
		vector = vectors.index('IRQB_NPU0_TD')

		# ---- the Q formats, parsed from the generic map that builds THIS chip's
		# instance. Q0.24 x Q7.24 into a Q7.24 accumulator is a property of the
		# MCU template, not of the NPU entity's defaults, so it is read there.
		tplPath = self.ThisFileDirectory + '/../hdl_templates/MCU.template.npu.vhd'
		with open(tplPath) as f:
			tpl = f.read()
		gmap = {}
		for key in ('X_M_BITS', 'W_M_BITS', 'Y_M_BITS', 'N_BITS'):
			m = re.search(key + r'\s*=>\s*(\d+)', tpl)
			if m is None:
				raise Exception('NpuDatapathDiagram: %s is not in the npu0 generic map of '
					'MCU.template.npu.vhd any more.' % key)
			gmap[key] = int(m.group(1))
		if 'npu0_active does not sleep any hart' not in tpl:
			raise Exception('NpuDatapathDiagram: MCU.template.npu.vhd no longer says that '
				'npu0_active sleeps no hart — the figure\'s ownership note would be a guess.')

		# ---- the mechanism itself, read back out of the NPU RTL
		rtlPath = self.ThisFileDirectory + '/../../../hdl/common/periph/NPU.vhd'
		with open(rtlPath) as f:
			rtl = f.read()
		if not re.search(r'NpuMuxSel\s*<=\s*NPUTHINK;', rtl):
			raise Exception('NpuDatapathDiagram: NPU.vhd no longer registers NpuMuxSel from '
				'NPUTHINK, so the drawn select contract is wrong.')
		if not re.search(r'NPU_MUXSEL_REG:\s*process\(Clk,\s*ResetN\)', rtl):
			raise Exception('NpuDatapathDiagram: the NPU port-mux select is no longer a flop '
				'on the free-running Clk (NPU_MUXSEL_REG), so the drawn contract is wrong.')
		stateDecl = re.search(r'type\s+npu_state_type\s+is\s*\((.*?)\)\s*;', rtl, re.S)
		if stateDecl is None:
			raise Exception('NpuDatapathDiagram: npu_state_type is not declared in NPU.vhd.')
		states = [t.strip() for t in stateDecl.group(1).split(',')]
		if sorted(states) != sorted(self._NPU_STATES):
			raise Exception('NpuDatapathDiagram: the sequencer states drawn %s are not the '
				'RTL\'s %s.' % (sorted(self._NPU_STATES), sorted(states)))

		return {
			'base': base, 'last': last, 'size': size, 'words': words,
			'ptrBits': ptrBits, 'vector': vector,
			'xq': (gmap['X_M_BITS'], gmap['N_BITS']),
			'wq': (gmap['W_M_BITS'], gmap['N_BITS']),
			'aq': (gmap['Y_M_BITS'], gmap['N_BITS']),
			'sat': 1 << gmap['Y_M_BITS'],
		}

	def GenerateNpuDatapathDiagram(self):
		'''include/NpuDatapathDiagram.tex — what ONE computation does to the
		   staging RAM, and who owns that RAM while it happens. Emitted
		   unconditionally (the TCM-aperture precedent); the NPU chapter is
		   itself only assembled when the peripheral exists, so a configuration
		   without an NPU never reaches the \\input and gets a stub here.

		   THE FIGURE DRAWS THE SHAPE; THE CAPTION CARRIES THE CONTRACTS.
		   (USER review, 2026-08-17: the first cut was rejected as "too many
		   words".) Every box here is a BOLD TITLE plus AT MOST ONE short line,
		   which is the rule the pinout and clock-tree figures already keep. The
		   ownership rule, the one-cycle select registration, the per-step
		   rounding, the reserved code foldings, the five-wrappers-one-sigmoid
		   fact and what the completion pulse does are all still stated — in the
		   chapter\'s caption, where a reader who wants a sentence can find one
		   and a reader who wants the shape is not made to read past it. A
		   picture that has to be READ word by word is a paragraph with lines
		   drawn on it.

		   THE HOUSE THEME, NOT A THEME OF ITS OWN. The same review found the
		   figure off-house: it had three tinted bands under three darker banner
		   strips, which is a colour ladder no other figure in this manual uses.
		   It now uses the clock-tree figure\'s idiom exactly — white ground, one
		   light grey wash on the ONE band that needs emphasis, thin grey frames
		   with Title Case italic grey headings sitting on their top edge, grey
		   filled blocks, and one grey spine. There is NO red in it, and that is
		   deliberate: red is this manual\'s package/off-die idiom (the pinout,
		   SPI-flash and clock figures all spend it on a chip boundary), and the
		   NPU is entirely on-die, so a red line here would name a boundary that
		   does not exist.

		   THREE BANDS, LEFT TO RIGHT, BECAUSE OWNERSHIP IS WHAT SPLITS THEM.
		   The harts\' side, the staging RAM, and the engine. The RAM is in the
		   middle and is the only washed band because it is the contested thing:
		   it has ONE port, and the whole figure is about which side of it is
		   driving that port. The two outer bands never touch each other; every
		   line between them lands on something in the middle band.

		   THE MUX IS DRAWN AS A MUX, AND ITS SELECT IS A SECOND COMPARTMENT.
		   The select is not a decoration and not an arbitration: it is one flop,
		   NPUTHINK re-clocked on the free-running clock. The strip names the
		   flop; WHAT the extra cycle buys is the caption\'s sentence. It is a
		   glued compartment rather than a wire back to NPUCR because the wire
		   would have to cross the compute port to get there.

		   THE CONTRACT IS SOFTWARE\'S, AND THE FIGURE SAYS SO IN SIX WORDS.
		   Nothing in the hardware stops a hart reading the staging window during
		   a computation: npu0_active sleeps nobody (MCU.template.npu.vhd says so
		   in as many words, and _NpuFacts refuses to ship if it stops saying
		   it). A figure that drew a lock here would teach a protection this chip
		   does not have, so the key box states whose rule it is and names the
		   poll, and the caption explains why there is nothing else to name.

		   THE POINTERS ARE TAPS, NOT ADDRESSES. NPUIVSAR, NPUWVSAR and NPUOVSAR
		   are word indices into the RAM, so they are drawn as three arrows
		   landing on three stripes of the one word array. The stripes are
		   labelled by ROLE and are deliberately not to scale: where they sit and
		   how big they are is firmware\'s business, and the sequencer
		   bounds-checks none of it (caption).

		   ONE PORT, ONE SPINE. The engine reaches the RAM through exactly one
		   port, so there is exactly one bus between the middle band and the
		   engine, drawn as a grey spine down the engine\'s left edge that the
		   sequencer, the MAC and the activation each tap. Drawing a separate
		   write-back arrow from the activation to the RAM would draw a second
		   port this chip does not have.

		   EVERY DERIVED FACT STILL PRINTS. De-wording moved sentences, not
		   numbers: the staging window and its word count, the vector number, the
		   pointer width, the three Q formats and the saturation limit, the four
		   mode codes, the five activation codes and the sequencer\'s state count
		   are all still drawn, so every assertion in _NpuFacts still guards
		   something the reader can see.'''
		facts = self._NpuFacts()
		if facts is None:
			self._writeInclude('NpuDatapathDiagram.tex',
				'% This configuration has no NPU (peripherals.npu = false).\n')
			return

		def P(v):
			return '%.2f' % v

		def Q(mn):
			return 'Q%d.%d' % mn

		vec = facts['vector']
		kiB = facts['size'] // 1024

		# ---- geometry, in cm. Every box height here is a LINE COUNT times a
		# baseline plus padding, never a guess: a TikZ node whose contents
		# outgrow its box does not clip, it spills over its own border and over
		# whatever is under it. The first cut of this figure was drawn with
		# guessed heights and every second box bled. Two lines per block is now
		# the CEILING, so the heights below are small and the drawing is short
		# enough that \resizebox does not have to shrink the type.
		yBot, yTop = 0.15, 12.60
		# The three bands are FRAMES with a clear channel between them, not
		# abutting tinted columns: the wires that cross from one to the next
		# have to be seen leaving one frame and entering the next.
		bands = [(0.00, 4.70, 'white', 'The Harts\' Side'),
			(5.00, 11.20, 'black!6', 'The Staging RAM'),
			(11.50, 23.35, 'white', 'Inside the NPU')]
		hX1 = bands[0][1]
		mCx = (bands[1][0] + bands[1][1]) / 2.0
		hCx, hartW = 2.35, 4.20

		yReg, yPort = 11.60, 10.50     # the two lanes that leave the harts' box
		yHart, hartH = 11.05, 1.70
		yKey, keyH = 5.00, 1.70
		yIrq, irqH = 1.15, 1.30
		xOut = hCx + hartW / 2.0       # where every lane leaves the harts' band

		muxX0, muxX1 = 5.20, 11.00
		yMux, muxH = 10.50, 1.10
		ySel, selH = 9.58, 0.75        # glued under the mux, sharing its border
		ramX0, ramX1 = 5.65, 10.55
		ramY0, ramY1 = 2.30, 7.70
		ramCx = (ramX0 + ramX1) / 2.0
		stripeY = [5.90, 4.65, 3.40]   # the three tapped regions
		stripeW, stripeH = 4.30, 0.90

		regCx, regW = 13.30, 3.40
		yCr, crH = 11.60, 1.10
		ptrX0, ptrX1 = regCx - regW / 2.0, regCx + regW / 2.0
		ptrFrameY0, ptrFrameY1 = 2.30, 6.70
		spX0, spX1 = 15.20, 15.85      # the engine's one port
		spY0, spY1 = 3.60, 11.30
		engX0, engX1 = 16.15, 23.20
		engCx = (engX0 + engX1) / 2.0
		seqY0, seqY1 = 8.60, 11.60
		yMac, macH = 6.95, 1.30
		actY0, actY1 = 3.40, 5.60
		yDone, doneH = 1.15, 1.30
		ySeqTap = 10.20                # between the two mode rows

		s = ('% Generated NPU datapath figure: ' + str(kiB) + ' KiB staging RAM at '
			+ fmthex(facts['base']) + ' (' + str(facts['words']) + ' words), think-done vector '
			+ str(vec) + ', ' + Q(facts['xq']) + ' x ' + Q(facts['wq']) + ' into '
			+ Q(facts['aq']) + '\n')
		# NO HYPHENATION anywhere in this figure. Every text node here is a
		# narrow column, which is exactly where TeX starts breaking words, and
		# a register name split as `en-\\ables' in a block diagram reads as two
		# different identifiers. `nb' carries the switch and every text style
		# inherits it.
		s += '\\begin{tikzpicture}[\n'
		s += '\tnb/.style={execute at begin node={\\hyphenpenalty=10000\\relax}},\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small, nb},\n'
		s += '\tunit/.style={blk, fill=black!8},\n'
		s += '\tmuxb/.style={blk, fill=black!12, line width=1.1pt},\n'
		s += '\tsel/.style={blk, fill=black!18, font=\\sffamily\\scriptsize, line width=1.1pt},\n'
		s += '\tstripe/.style={blk, fill=black!8, font=\\sffamily\\scriptsize},\n'
		s += '\tsmallb/.style={blk, fill=black!8, font=\\sffamily\\scriptsize},\n'
		s += '\tsig/.style={->, >=Stealth, thick},\n'
		s += '\tbus/.style={<->, >=Stealth, line width=1.5pt},\n'
		s += '\tcross/.style={->, >=Stealth, line width=1.5pt},\n'
		# The frame-heading idiom of the clock-tree figure: Title Case, italic,
		# grey, sitting ON the frame's top edge. `ban' is the same thing one
		# step larger, for the three bands themselves.
		s += ('\tban/.style={font=\\sffamily\\small\\itshape, black!50, align=center, '
			+ 'inner sep=2pt},\n')
		s += ('\ttyp/.style={font=\\sffamily\\scriptsize\\itshape, black!55, align=center, '
			+ 'inner sep=1.5pt},\n')
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=center, nb},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize\\itshape, align=center, nb}]\n'

		# ---- the three bands: a wash on the contested one, a frame on each
		for x0, x1, fill, title in bands:
			if fill != 'white':
				s += ('\\fill[' + fill + '] (' + P(x0) + ', ' + P(yBot) + ') rectangle ('
					+ P(x1) + ', ' + P(yTop) + ');\n')
			s += ('\\draw[semithick, black!45] (' + P(x0) + ', ' + P(yBot) + ') rectangle ('
				+ P(x1) + ', ' + P(yTop) + ');\n')
			s += ('\\node[ban, fill=' + fill + '] at (' + P((x0 + x1) / 2.0) + ', ' + P(yTop)
				+ ') {' + title + '};\n')

		# ---- band 1: who asks, on which of the two wires, and under what rule
		s += ('\\node[unit, minimum width=' + P(hartW) + 'cm, minimum height=' + P(hartH)
			+ 'cm, text width=' + P(hartW - 0.40) + 'cm] (hart) at (' + P(hCx) + ', ' + P(yHart)
			+ ') {\\textbf{any hart}\\\\ \\scriptsize registers on one wire,'
			+ ' staging RAM on the other};\n')
		s += ('\\node[blk, minimum width=' + P(hartW) + 'cm, minimum height=' + P(keyH)
			+ 'cm, text width=' + P(hartW - 0.40) + 'cm] (key) at (' + P(hCx) + ', ' + P(yKey)
			+ ') {\\textbf{the ownership rule is software\'s}\\\\ \\scriptsize poll'
			+ ' \\bitfield{NPUTHINK} for 0 before touching \\texttt{' + fmthex(facts['base'])
			+ '}--\\texttt{' + fmthex(facts['last']) + '}};\n')
		s += ('\\node[unit, minimum width=' + P(hartW) + 'cm, minimum height=' + P(irqH)
			+ 'cm, text width=' + P(hartW - 0.40) + 'cm] (irq) at (' + P(hCx) + ', ' + P(yIrq)
			+ ') {\\textbf{interrupt vector ' + str(vec) + '}\\\\ \\scriptsize one more source'
			+ ' at the interrupt router};\n')

		# ---- the two lanes out of the harts' box
		s += '\\draw[cross] (' + P(xOut) + ', ' + P(yReg) + ') -- (' + P(ptrX0) + ', ' + P(yReg) + ');\n'
		s += ('\\node[lab, fill=' + bands[1][2] + ', inner sep=2pt, anchor=south] at (' + P(mCx)
			+ ', ' + P(yReg + 0.14) + ') {the register bus};\n')
		s += '\\draw[bus] (' + P(xOut) + ', ' + P(yPort) + ') -- (' + P(muxX0) + ', ' + P(yPort) + ');\n'

		# ---- band 2: the port multiplexer, its select strip, and the RAM
		s += ('\\node[muxb, minimum width=' + P(muxX1 - muxX0) + 'cm, minimum height=' + P(muxH)
			+ 'cm, text width=' + P(muxX1 - muxX0 - 0.40) + 'cm] (mux) at (' + P((muxX0 + muxX1) / 2.0) + ', '
			+ P(yMux) + ') {\\textbf{the port multiplexer}\\\\ \\scriptsize one side drives the'
			+ ' SRAM port, never both};\n')
		s += ('\\node[sel, minimum width=' + P(muxX1 - muxX0) + 'cm, minimum height=' + P(selH)
			+ 'cm, text width=' + P(muxX1 - muxX0 - 0.40) + 'cm] (sel) at (' + P((muxX0 + muxX1) / 2.0) + ', '
			+ P(ySel) + ') {\\textbf{select} $=$ \\bitfield{NPUTHINK}, registered on'
			+ ' \\register{mclk}};\n')

		# The RAM: one word array and three tapped regions. What firmware owns
		# and what the sequencer does not check is the caption's sentence.
		s += ('\\draw[thick, fill=white] (' + P(ramX0) + ', ' + P(ramY0) + ') rectangle ('
			+ P(ramX1) + ', ' + P(ramY1) + ');\n')
		s += ('\\node[lab, text width=' + P(ramX1 - ramX0 - 0.40) + 'cm, anchor=north] at (' + P(ramCx) + ', '
			+ P(ramY1 - 0.16) + ') {\\textbf{\\small NPU staging RAM}\\\\ \\texttt{' + fmthex(facts['base'])
			+ '}--\\texttt{' + fmthex(facts['last']) + '}, ' + str(facts['words']) + ' words};\n')
		stripeNames = ['input vector', 'weight matrix', 'output vector']
		for i, yS in enumerate(stripeY):
			s += ('\\node[stripe, minimum width=' + P(stripeW) + 'cm, minimum height=' + P(stripeH)
				+ 'cm] (st' + str(i) + ') at (' + P(ramCx) + ', ' + P(yS) + ') {' + stripeNames[i] + '};\n')
		s += ('\\draw[bus] (' + P(ramCx) + ', ' + P(ySel - selH / 2.0) + ') -- (' + P(ramCx) + ', '
			+ P(ramY1) + ');\n')
		s += ('\\node[lab, anchor=west, fill=' + bands[1][2] + ', inner sep=1.5pt] at ('
			+ P(ramCx + 0.14) + ', ' + P((ySel - selH / 2.0 + ramY1) / 2.0) + ') {the one port};\n')

		# ---- band 3, left column: the registers, and the three pointer taps
		s += ('\\node[unit, minimum width=' + P(regW) + 'cm, minimum height=' + P(crH) + 'cm, text width='
			+ P(regW - 0.34) + 'cm] (cr) at (' + P(regCx) + ', ' + P(yCr) + ') {\\textbf{\\small NPUCR}\\\\'
			+ ' \\scriptsize mode, counts, \\bitfield{NPUTHINK}};\n')
		s += ('\\draw[thin, black!55] (' + P(ptrX0) + ', ' + P(ptrFrameY0) + ') rectangle ('
			+ P(ptrX1) + ', ' + P(ptrFrameY1) + ');\n')
		s += ('\\node[typ, fill=white] at (' + P(regCx) + ', ' + P(ptrFrameY1)
			+ ') {The Vector Pointers};\n')
		ptrNames = ['NPUIVSAR', 'NPUWVSAR', 'NPUOVSAR']
		ptrRoles = ['inputs', 'weights', 'outputs']
		for i, yS in enumerate(stripeY):
			s += ('\\node[smallb, minimum width=' + P(regW - 0.34) + 'cm, minimum height=' + P(stripeH)
				+ 'cm] (pt' + str(i) + ') at (' + P(regCx) + ', ' + P(yS) + ') {\\textbf{'
				+ ptrNames[i] + '}\\\\ ' + ptrRoles[i] + '};\n')
			s += ('\\draw[sig] (' + P(ptrX0) + ', ' + P(yS) + ') -- (' + P(ramX1) + ', ' + P(yS) + ');\n')
		s += ('\\node[note, text width=' + P(regW - 0.26) + 'cm, anchor=north] at ('
			+ P(regCx) + ', ' + P(stripeY[-1] - stripeH / 2.0 - 0.14) + ') {'
			+ str(facts['ptrBits']) + '-bit word indices};\n')

		# ---- the one port between the RAM and the engine, drawn as a spine
		s += ('\\fill[black!15, draw=black, thick] (' + P(spX0) + ', ' + P(spY0) + ') rectangle ('
			+ P(spX1) + ', ' + P(spY1) + ');\n')
		s += ('\\node[lab, rotate=90] at (' + P((spX0 + spX1) / 2.0) + ', ' + P((spY0 + spY1) / 2.0)
			+ ') {\\textbf{the NPU\'s compute port}};\n')
		s += '\\draw[bus] (' + P(muxX1) + ', ' + P(yPort) + ') -- (' + P(spX0) + ', ' + P(yPort) + ');\n'
		s += ('\\node[lab, inner sep=2pt, anchor=north] at (' + P((muxX1 + spX0) / 2.0) + ', '
			+ P(yPort - 0.16) + ') {one word per access};\n')

		# ---- band 3, right column: the sequencer, the MAC, the activation
		s += ('\\draw[thin, black!55] (' + P(engX0) + ', ' + P(seqY0) + ') rectangle ('
			+ P(engX1) + ', ' + P(seqY1) + ');\n')
		s += ('\\node[typ, fill=white] at (' + P(engCx) + ', ' + P(seqY1)
			+ ') {The Mode Sequencer};\n')
		# 2 x 2, not a rank of four: at four across, a mode box is 1.7 cm wide and
		# `XNOR-popcount' hyphenates into three lines inside it.
		modeW, modeH = 3.30, 0.95
		modeXs = [engCx - modeW / 2.0 - 0.10, engCx + modeW / 2.0 + 0.10]
		modeYs = [10.75, 9.70]
		for i, (code, label, sub, _phrase) in enumerate(self._NPU_MODES):
			s += ('\\node[smallb, minimum width=' + P(modeW) + 'cm, minimum height=' + P(modeH)
				+ 'cm, text width=' + P(modeW - 0.26) + 'cm] at (' + P(modeXs[i % 2]) + ', '
				+ P(modeYs[i // 2]) + ') {\\textbf{' + str(code) + '\\quad ' + label + '}\\\\ ' + sub + '};\n')
		s += ('\\node[note, text width=' + P(engX1 - engX0 - 0.40) + 'cm, anchor=north] at ('
			+ P(engCx) + ', ' + P(modeYs[1] - modeH / 2.0 - 0.14) + ') {one mode per computation, '
			+ str(len(self._NPU_STATES)) + ' sequencer states};\n')

		s += ('\\node[unit, minimum width=' + P(engX1 - engX0) + 'cm, minimum height=' + P(macH)
			+ 'cm, text width=' + P(engX1 - engX0 - 0.40) + 'cm] (mac) at (' + P(engCx) + ', ' + P(yMac)
			+ ') {\\textbf{the multiply-accumulate step}\\\\ \\scriptsize ' + Q(facts['xq'])
			+ ' $\\times$ ' + Q(facts['wq']) + ' $\\to$ ' + Q(facts['aq'])
			+ ', saturating at $\\pm$' + str(facts['sat']) + ' every step};\n')

		s += ('\\draw[thin, black!55] (' + P(engX0) + ', ' + P(actY0) + ') rectangle ('
			+ P(engX1) + ', ' + P(actY1) + ');\n')
		s += ('\\node[typ, fill=white] at (' + P(engCx) + ', ' + P(actY1) + ') {The Activation Taps};\n')
		actW, actGap, actH = 1.30, 0.10, 0.95
		actSpan = len(self._NPU_ACTS) * actW + (len(self._NPU_ACTS) - 1) * actGap
		actX = engCx - actSpan / 2.0 + actW / 2.0
		yAct = 4.55
		for code, label, _phrase in self._NPU_ACTS:
			s += ('\\node[smallb, minimum width=' + P(actW) + 'cm, minimum height=' + P(actH)
				+ 'cm] at (' + P(actX) + ', ' + P(yAct) + ') {\\textbf{' + str(code) + '}\\\\ ' + label + '};\n')
			actX += actW + actGap
		s += ('\\node[note, text width=' + P(engX1 - engX0 - 0.40) + 'cm, anchor=north] at ('
			+ P(engCx) + ', ' + P(yAct - actH / 2.0 - 0.14) + ') {all '
			+ str(len(self._NPU_ACTS)) + ' share one sigmoid approximator};\n')

		# ---- the spine taps: what each block takes from, or gives to, the port
		s += '\\draw[sig] (' + P(spX1) + ', ' + P(ySeqTap) + ') -- (' + P(engX0) + ', ' + P(ySeqTap) + ');\n'
		s += '\\draw[sig] (' + P(spX1) + ', ' + P(yMac) + ') -- (' + P(engX0) + ', ' + P(yMac) + ');\n'
		s += '\\draw[sig] (' + P(engX0) + ', ' + P(yAct) + ') -- (' + P(spX1) + ', ' + P(yAct) + ');\n'

		# ---- the completion event, and the leg it turns into
		s += ('\\node[unit, minimum width=' + P(engX1 - engX0) + 'cm, minimum height=' + P(doneH)
			+ 'cm, text width=' + P(engX1 - engX0 - 0.40) + 'cm] (done) at (' + P(engCx) + ', ' + P(yDone)
			+ ') {\\textbf{the completion event}\\\\ \\scriptsize clears \\bitfield{NPUTHINK},'
			+ ' sets \\bitfield{NPUTHINKDONE}};\n')
		s += '\\draw[cross] (' + P(engX0) + ', ' + P(yDone) + ') -- (' + P(xOut) + ', ' + P(yDone) + ');\n'
		s += ('\\node[lab, fill=' + bands[1][2] + ', inner sep=2pt, anchor=south] at (' + P(mCx) + ', '
			+ P(yDone + 0.14) + ') {the think-done level};\n')

		s += '\\end{tikzpicture}\n'
		self._writeInclude('NpuDatapathDiagram.tex', s)
		return

	def GenerateBootFlowDiagram(self):
		'''include/BootFlowDiagram.tex — the M12 single-ROM boot flow chart
		   (mhartid dispatch, hart-0 SPI boot, tile WFI park + msip loader).

		   D-series sweep (s1): the CONTENT of the hart-0 branch is right on
		   both polarities (hart 0 is the boot/management hart either way), so
		   only its NAME is derived — on an orchestrator configuration the
		   reader meets that hart as "the orchestrator" everywhere else in the
		   manual, and an unnamed branch here is the one place it looks like a
		   fourth anonymous tile.'''
		N = self.Gen.NumHarts
		orch = bool((getattr(self.Gen, 'McuMpGeometry', None) or {}).get('orchestrator'))
		# SIZING CONTRACT (USER review, 2026-08-16 — the same treatment the TAP
		# state graph got). This picture is \input at NATURAL SIZE: the chapter
		# used to wrap it in \resizebox{0.95\linewidth}, and since the drawing was
		# only ~11.7 cm wide that SCALED IT UP by about 1.35, so \small node type
		# printed larger than the 11 pt body text and every box grew with it until
		# consecutive boxes abutted and the arrow between them was a black smudge
		# two millimetres tall. Measured in the render, not guessed.
		# The fix is not a smaller \resizebox: it is to draw the thing at the size
		# it should print at. Node type is \scriptsize (labels \tiny), inner sep
		# drops 5pt -> 3pt, the boxes narrow to 4.15 cm, and ALL of the space that
		# buys goes into SEPARATION — every consecutive pair of boxes now has
		# 0.6-1.0 cm of clear air with the arrow alone in it, and the two columns
		# stand 5 cm apart so the diamond's branches and the dashed msip arrow
		# each own an empty channel. Natural size lands ~13.6 x 12.0 cm against
		# the old print size of ~15.7 x 13.6 cm, i.e. smaller on both axes.
		# CONTENT AND EDGES ARE UNCHANGED — this is a layout and type change only.
		# Keep the natural width under \linewidth (16.5 cm) if the text ever grows.
		xL, xR, xC = 3.10, 12.30, 7.70     # left branch / right branch / spine
		s = '% Generated boot flow chart (M12 single-ROM boot, numHarts=' + str(N) + ')\n'
		s += '% Drawn at natural size: the chapter \\inputs this WITHOUT a \\resizebox.\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tstp/.style={draw, semithick, rounded corners=2pt, align=center, font=\\sffamily\\scriptsize, text width=4.15cm, inner sep=3pt},\n'
		s += '\tterm/.style={stp, fill=black!12},\n'
		s += '\tdec/.style={draw, semithick, diamond, aspect=2.6, align=center, font=\\sffamily\\scriptsize, inner sep=1pt},\n'
		s += '\tflow/.style={->, >=Stealth, semithick},\n'
		s += '\tlab/.style={font=\\sffamily\\tiny, align=center, fill=white, inner sep=1.2pt}]\n'
		s += '\\node[term, text width=9.0cm] (rst) at (' + str(xC) + ', 13.00) {\\textbf{Power-on / reset}\\\\ all ' + str(N) + ' harts: PC $=$ \\texttt{0x0}, fetching THE shared boot ROM through the arbiter};\n'
		s += '\\node[dec] (who) at (' + str(xC) + ', 11.05) {\\register{mhartid} $= 0$?};\n'
		# Hart 0 branch (left)
		s += '\\node[stp] (h0a) at (' + str(xL) + ', 9.00) {Configure \\peripheral{GPIO0}/\\peripheral{SPI0}, read the BOOT strap pin};\n'
		s += '\\node[stp] (h0b) at (' + str(xL) + ', 6.90) {Copy the program from SPI flash to \\texttt{0x8000}--\\texttt{0xFFFC}; zero the mailbox region \\texttt{0x10000}--\\texttt{0x107FF}};\n'
		s += '\\node[term] (h0c) at (' + str(xL) + ', 4.95) {Jump to \\texttt{\\SpiFlashProgramAddress}: application runs on hart 0};\n'
		s += '\\node[stp, dashed] (launch) at (' + str(xL) + ', 2.60) {\\textbf{Launching a tile $h$:} stage its image in shared RAM, write \\register{SRC[h]}/\\register{LEN[h]}/\\register{ENTRY[h]} at \\texttt{\\BootMailboxBase}$+16h$, then write $1$ to \\register{MSIPx} (\\texttt{0x5000}$+4h$)};\n'
		# Tile branch (right)
		s += '\\node[stp] (t1) at (' + str(xR) + ', 9.00) {Set $\\mathtt{sp}$ to the top of the private TCM; arm the software-interrupt vector};\n'
		s += '\\node[term] (t2) at (' + str(xR) + ', 6.85) {\\textbf{Park}: low-power sleep, waiting for a \\peripheral{CLINT} software interrupt};\n'
		s += '\\node[stp] (t3) at (' + str(xR) + ', 4.55) {ROM loader: clear the \\register{MSIPx} level, read \\register{SRC}/\\register{LEN}/\\register{ENTRY} at \\texttt{\\BootMailboxBase}$+16h$, copy \\register{LEN} words into the TCM at \\texttt{0x8000}};\n'
		s += '\\node[term] (t4) at (' + str(xR) + ', 2.30) {Enter \\register{ENTRY} with $\\mathtt{sp}$ at the top of the TCM: tile runs};\n'
		# Edges
		s += '\\draw[flow] (rst) -- (who);\n'
		# The two branch labels ride the MIDDLE of their own horizontal run, and
		# the run is drawn as an explicit two-segment path rather than `-|' so
		# that `pos' means what it says (the SyncPrimitiveDecisionTree idiom in
		# this same file). Each run is ~3 cm of empty lane, so the orchestrator
		# polarity's two-line label clears the diamond and the box below it
		# without any per-polarity nudging: only the WORDS differ now.
		if orch:
			yesLab = 'yes: hart 0\\\\ (orchestrator)'
		else:
			yesLab = 'yes: hart 0'
		s += '\\draw[flow] (who.west) -- node[lab] {' + yesLab + '} (h0a.north |- who.west) -- (h0a.north);\n'
		s += '\\draw[flow] (who.east) -- node[lab] {no: harts 1--' + str(N - 1) + '} (t1.north |- who.east) -- (t1.north);\n'
		s += '\\draw[flow] (h0a) -- (h0b);\n'
		s += '\\draw[flow] (h0b) -- (h0c);\n'
		s += '\\draw[flow, dashed] (h0c) -- (launch);\n'
		s += '\\draw[flow] (t1) -- (t2);\n'
		# Hung to the RIGHT of its arrow, not centred on it: the arrow is short
		# and a centred label with a white fill would swallow it.
		s += '\\draw[flow] (t2) -- node[lab, right=2pt] {\\register{MSIPx} interrupt} (t3);\n'
		s += '\\draw[flow] (t3) -- (t4);\n'
		s += '\\draw[flow, dashed] (launch.east) -- node[lab, above, sloped] {\\peripheral{CLINT} msip} (t2.south west);\n'
		s += '\\end{tikzpicture}\n'
		with open(self.IncludeDirectory + '/BootFlowDiagram.tex', 'w') as f:
			f.write(s)
		return

	def GenerateSyncPrimitiveDecisionTree(self):
		'''include/SyncPrimitiveDecisionTree.tex — which synchronization
		   primitive to use (HW mutex vs AMO vs LR/SC), as a decision tree.'''
		# Sizing contract: this picture is \input at NATURAL SIZE (no \resizebox in
		# the multi-core intro) — scaling it to \linewidth magnified every font past
		# the 11pt body text. Keep the natural width under \linewidth (16.5cm): the
		# widest elements are the rules box and the lrfree leaf, both ending ~15.4cm.
		# Node text is \scriptsize so it reads smaller than the body, and the
		# questions carry explicit line breaks so the diamonds stay compact enough
		# to contain them.
		s = '% Generated synchronization-primitive decision tree\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tdec/.style={draw, semithick, diamond, aspect=2.2, align=center, font=\\sffamily\\scriptsize, inner sep=1pt},\n'
		# Auto-hyphenation inside a 3.7cm box produces "in-struction"/"cy-cles"; the
		# leaves are short enough to wrap without it. The penalty MUST go in
		# `execute at begin node` — in `font=` its number scan swallows the
		# align=center skip assignments and "0pt plus2em" gets typeset into the box.
		s += '\tleaf/.style={draw, semithick, rounded corners=2pt, align=center, font=\\sffamily\\scriptsize, execute at begin node={\\hyphenpenalty=10000\\relax}, text width=3.7cm, inner sep=4pt, fill=black!8},\n'
		s += '\tflow/.style={->, >=Stealth, semithick},\n'
		# The yes/no labels anchor to the branch vertex itself (pos=0 + a corner
		# anchor) rather than riding the path at a fixed pos= — the six branch runs
		# have different lengths, so a midway/pos=0.3 label sat on the diamond's
		# text on the short ones and drifted far away on the long ones.
		s += '\tyeslab/.style={font=\\sffamily\\scriptsize, inner sep=1pt, pos=0, anchor=south east, xshift=-2pt, yshift=1pt},\n'
		s += '\tnolab/.style={font=\\sffamily\\scriptsize, inner sep=1pt, pos=0, anchor=south west, xshift=2pt, yshift=1pt}]\n'
		s += '\\node[dec] (q1) at (5.6, 8.9) {Single shared word\\\\to update atomically?\\\\[1pt](counter, swap, flag)};\n'
		s += '\\node[leaf] (amo) at (1.95, 6.5) {\\textbf{AMO}\\\\(\\asminline{amoadd}, \\asminline{amoswap}, \\ldots)\\\\[1pt]one-shot cross-hart RMW; the arbiter grant is held across the pair ($\\sim$5 cycles, pins the shared bus)};\n'
		s += '\\node[dec] (q2) at (9.7, 6.6) {Guarding a multi-word\\\\critical section?};\n'
		s += '\\node[dec] (q3) at (5.9, 4.1) {Hardware mutex free?\\\\[1pt](\\NumMutexes{} in the bank)};\n'
		s += '\\node[leaf] (lrfree) at (13.5, 4.1) {\\textbf{LR/SC} retry loop\\\\[1pt]lock-free structures; failed \\asminline{SC} never writes};\n'
		s += '\\node[leaf] (mtx) at (2.4, 1.6) {\\textbf{Hardware mutex}\\\\(preferred)\\\\[1pt]\\asminline{lw} claims (0 $=$ yours), \\asminline{sw 0} releases: one instruction, no retry state};\n'
		s += '\\node[leaf] (lrlock) at (9.3, 1.6) {\\textbf{LR/SC spinlock}\\\\in shared RAM\\\\[1pt]reservation-based lock};\n'
		# Each branch is an explicit two-segment path (out of the vertex, then down)
		# so the label sits on the horizontal run, clear of both shapes.
		s += '\\draw[flow] (q1.west) -- node[yeslab] {yes} (amo.north |- q1.west) -- (amo.north);\n'
		s += '\\draw[flow] (q1.east) -- node[nolab] {no} (q2.north |- q1.east) -- (q2.north);\n'
		s += '\\draw[flow] (q2.west) -- node[yeslab] {yes} (q3.north |- q2.west) -- (q3.north);\n'
		s += '\\draw[flow] (q2.east) -- node[nolab] {no} (lrfree.north |- q2.east) -- (lrfree.north);\n'
		s += '\\draw[flow] (q3.west) -- node[yeslab] {yes} (mtx.north |- q3.west) -- (mtx.north);\n'
		s += '\\draw[flow] (q3.east) -- node[nolab] {no} (lrlock.north |- q3.east) -- (lrlock.north);\n'
		s += '\\node[draw, semithick, dashed, align=left, font=\\sffamily\\scriptsize, text width=14.9cm, inner sep=5pt] at (7.75, -0.6) {'
		s += '\\textbf{Rules that apply to every branch:} never use \\asminline{LR}/\\asminline{SC} or AMO instructions on \\peripheral{MUTEX} bank addresses (the claim-on-read side effect fires); '
		s += 'every retry loop needs a hart-scaled backoff ($\\mathtt{delay} \\propto \\register{mhartid}+1$) and a bounded retry count, because identical harts on the fair round-robin arbiter can otherwise livelock.};\n'
		s += '\\end{tikzpicture}\n'
		with open(self.IncludeDirectory + '/SyncPrimitiveDecisionTree.tex', 'w') as f:
			f.write(s)
		return

	# -------------------------------------------------------------------------
	# Timing / waveform diagrams (tikz-timing + plain TikZ).
	#
	# These replaced three matplotlib .pgf figures. Two rules learned building
	# them, both of which fail SILENTLY:
	#   * \timing carries its OWN x unit (default ~1ex). timing/xunit MUST be set
	#     to the enclosing picture's x= or the digital rows do not line up with
	#     anything else drawn in the picture.
	#   * the clock char C is a HALF period per unit. One full cycle per unit is
	#     `2{0.5C}` — `C` alone draws half as many cycles as you counted.
	# Annotations are plain TikZ over \timing rows rather than a
	# tikztimingtable's \extracode: the table's row pitch is not 1 unit/row, so
	# overlay coordinates silently land on the wrong signal.
	# -------------------------------------------------------------------------

	# Waveform row geometry. _ROW_H is the high-to-low height of a signal and
	# therefore the height of a bus cell — it is what sets how large the text
	# inside a D{} cell can be. _ROW_PITCH must exceed it or rows collide.
	# The two track the D-cell font: _CELL_FONT is \small (10 pt against the
	# 11 pt body), so the rows are tall enough that a bus label reads at
	# essentially body size rather than as fine print.
	_ROW_H = '0.92cm'
	_ROW_PITCH = 1.38

	# Type sizes for the waveforms. Signal names and the text inside a bus cell
	# sit just under body size; explanatory notes hanging off the figure stay a
	# step smaller so the figure still reads as a figure.
	_CELL_FONT = '\\sffamily\\small'
	_LABEL_FONT = '\\sffamily\\small'
	_NOTE_FONT = '\\sffamily\\footnotesize'

	# THE TWO ARBITER FIGURES ARE ONE PAIR AND ARE SIZED AS ONE (2026-08-15,
	# USER review). At the house geometry each of them owned a whole page, and
	# figure 5's caption asks the reader to compare it PIN BY PIN with figure 4
	# — which only works if a row of one reads like a row of the other. So both
	# take the same reduced row height, row pitch and type sizes, and differ
	# only in xunit, because one draws 7 cycles and the other 13. The floor on
	# xunit is the widest single-cell string each figure has to hold (`LATCH`
	# in figure 4), not a width budget: a D{} cell clips nothing and shrinks
	# nothing, it just overflows its own outline.
	_ARB_ROW_H = '0.74cm'
	_ARB_ROW_PITCH = 1.11
	_ARB_FONTS = ('\\sffamily\\footnotesize', '\\sffamily\\footnotesize',
	              '\\sffamily\\scriptsize')

	def _timingPreamble(self, xunit, extra='', rowH=None, fonts=None):
		'''Shared tikzpicture options for the generated waveform figures.
		   rowH/fonts default to the house geometry above; a figure that needs
		   to be smaller than the house size passes its OWN pair (the two
		   arbiter figures do — see _ARB_ROW_H). Sizing goes through here, never
		   through a \\resizebox around the \\input: a resizebox scales the
		   drawn strokes AND the type, and on a figure narrower than the text
		   block it scales it UP (the Agent-C lesson).'''
		rowH = rowH or self._ROW_H
		cellFont, labelFont, noteFont = fonts or (self._CELL_FONT, self._LABEL_FONT, self._NOTE_FONT)
		s = '\\begin{tikzpicture}[\n'
		s += '\tx=' + xunit + ', y=1cm,\n'
		s += '\tlbl/.style={font=' + labelFont + ', anchor=east},\n'
		s += '\tguide/.style={densely dotted, gray!65},\n'
		s += '\tann/.style={font=' + noteFont + ', inner sep=1.5pt},\n'
		s += '\ttim/.style={timing/xunit=' + xunit + ', timing/yunit=' + rowH + ', semithick,\n'
		s += '\t            timing/d/text/.style={font=' + cellFont + '}}' + extra + ']\n'
		return s

	def GenerateTimerRolloverDiagram(self):
		'''include/TimerRolloverDiagram.tex — the free-running counter ramping to
		   TIMxCMP2 and rolling over. Pure line plot (the counter value is not a
		   digital signal), so this one is plain TikZ, NOT tikz-timing.'''
		s = '% Generated timer rollover diagram\n'
		s += self._timingPreamble('0.62cm')
		s += '\\def\\NPER{4}\\def\\PER{3}\\def\\HR{2.0}\\def\\CMPTWO{0.75}\n'
		s += '\\foreach \\k in {1,...,4} { \\draw[guide] ({\\k*\\PER}, {\\HR*\\CMPTWO}) -- ({\\k*\\PER}, -0.45); }\n'
		s += '\\draw[semithick] (0,0) -- (0,\\HR);\n'
		s += '\\draw[densely dashed] (0,{\\HR*\\CMPTWO}) -- ({\\NPER*\\PER},{\\HR*\\CMPTWO});\n'
		s += '\\foreach \\k in {0,...,3} {\n'
		s += '\t\\draw[red, semithick] ({\\k*\\PER},0) -- ({\\k*\\PER+\\PER},{\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER},0);\n'
		s += '}\n'
		s += '\\node[lbl] at (0,0) {0};\n'
		s += '\\node[lbl] at (0,{\\HR*\\CMPTWO}) {\\register{TIMxCMP2}};\n'
		s += '\\node[lbl] at (0,\\HR) {$2^{32}-1$ (max)};\n'
		s += '\\node[ann, rotate=90, anchor=south] at (-4.3,{\\HR/2}) {Timer Value};\n'
		s += '\\draw[<->, >=Stealth] (0,-0.45) -- (\\PER,-0.45);\n'
		s += '\\node[ann, below] at (1.5,-0.47) {rollover period};\n'
		s += '\\node[ann, anchor=west] at ({\\NPER*\\PER+0.4}, 0) {Time $\\rightarrow$};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('TimerRolloverDiagram.tex', s)
		return

	def GenerateTimerOutputCompareDiagram(self):
		'''include/TimerOutputCompareDiagram.tex — the counter ramp AND the two
		   TxCMP0 pin polarities in ONE picture on ONE x-axis, with dotted guides
		   tying each TIMxCMP0 crossing and each rollover to the pin edge it
		   causes. One timer period = 3 units so the crossing lands exactly on a
		   unit boundary (the old three-subplot matplotlib figure only LOOKED
		   aligned; nothing enforced it).'''
		s = '% Generated timer output-compare / PWM diagram\n'
		s += self._timingPreamble('0.62cm')
		# \ROWH is the pin rows' height, exported so that every coordinate that
		# has to sit at a signal LEVEL (the HIGH/LOW labels, the HIGH-time arrow
		# on the row's top edge) is derived from it. Hardcoding those was what
		# dropped the HIGH-time arrow onto the waveform when the row grew.
		s += '\\def\\NPER{4}\\def\\PER{3}\\def\\HR{2.0}\\def\\ROWH{' + self._ROW_H[:-2] + '}\n'
		s += '\\def\\CMPTWO{0.75}\\def\\CMPZERO{0.25}\\def\\YONE{-1.60}\\def\\YTWO{-3.00}\n'
		s += '\\foreach \\k in {0,...,3} {\n'
		s += '\t\\draw[guide] ({\\k*\\PER+1}, {\\HR*\\CMPZERO}) -- ({\\k*\\PER+1}, \\YTWO);\n'
		s += '\t\\draw[guide] ({\\k*\\PER+\\PER}, {\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER}, \\YTWO);\n'
		s += '}\n'
		s += '\\draw[semithick] (0,0) -- (0,\\HR);\n'
		s += '\\draw[densely dashed] (0,{\\HR*\\CMPTWO}) -- ({\\NPER*\\PER},{\\HR*\\CMPTWO});\n'
		s += '\\draw[densely dashed] (0,{\\HR*\\CMPZERO}) -- ({\\NPER*\\PER},{\\HR*\\CMPZERO});\n'
		s += '\\foreach \\k in {0,...,3} {\n'
		s += '\t\\draw[red, semithick] ({\\k*\\PER},0) -- ({\\k*\\PER+\\PER},{\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER},0);\n'
		s += '}\n'
		s += '\\node[lbl] at (0,0) {0};\n'
		s += '\\node[lbl] at (0,{\\HR*\\CMPZERO}) {\\register{TIMxCMP0}};\n'
		s += '\\node[lbl] at (0,{\\HR*\\CMPTWO}) {\\register{TIMxCMP2}};\n'
		s += '\\node[lbl] at (0,\\HR) {$2^{32}-1$ (max)};\n'
		s += '\\node[ann, rotate=90, anchor=south] at (-4.3,{\\HR/2}) {Timer Value};\n'
		# 1 unit LOW/HIGH then 2 units of the opposite level = the CMP0 crossing
		# at 1/3 of the period, matching the ramp above.
		s += '\\timing[tim] at (0,\\YONE) {4{1L 2H}};\n'
		s += '\\timing[tim] at (0,\\YTWO) {4{1H 2L}};\n'
		s += '\\node[lbl] at (0,\\YONE) {LOW};   \\node[lbl] at (0,{\\YONE+\\ROWH}) {HIGH};\n'
		s += '\\node[lbl] at (0,\\YTWO) {LOW};   \\node[lbl] at (0,{\\YTWO+\\ROWH}) {HIGH};\n'
		s += '\\node[lbl, align=right] at (-2.5,{\\YONE+0.5*\\ROWH}) {Pin \\pin{TxCMP0}\\\\\\register{TIMCMP0H} $=0$};\n'
		s += '\\node[lbl, align=right] at (-2.5,{\\YTWO+0.5*\\ROWH}) {Pin \\pin{TxCMP0}\\\\\\register{TIMCMP0H} $=1$};\n'
		s += '\\draw[<->, >=Stealth, red] (1,{\\YONE+\\ROWH}) -- (\\PER,{\\YONE+\\ROWH});\n'
		s += '\\node[ann, above, text=red] at (2,{\\YONE+\\ROWH+0.02}) {HIGH time};\n'
		s += '\\draw[<->, >=Stealth] (0,{\\YTWO-0.40}) -- (\\PER,{\\YTWO-0.40});\n'
		s += '\\node[ann, below] at (1.5,{\\YTWO-0.42}) {PWM period};\n'
		s += '\\node[ann, anchor=west] at ({\\NPER*\\PER+0.4}, {\\YONE+0.5*\\ROWH}) {Time $\\rightarrow$};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('TimerOutputCompareDiagram.tex', s)
		return

	def GenerateArbiterHandshakeDiagram(self):
		'''include/ArbiterHandshakeDiagram.tex — one uncontended shared-window
		   read at the mp_arbiter pins. CYCLE-ACCURATE against hdl/common/
		   mp_arbiter.vhd: IDLE -> LATCH -> DATA -> IDLE, with done/rdata
		   registered together at the edge leaving DATA (3 mclk from an
		   observed req to done; the depth-1 registered tile boundary adds one
		   more each way, which is the ~5 mclk a hart actually sees). If that
		   FSM changes, this figure must change with it.'''
		rows = [
			('14{0.5C}',                              '\\register{mclk}'),
			('L 5H L',                                '\\register{req(0)}'),
			('2L 3H 2L',                              '\\register{gnt(0)}'),
			('2D{IDLE} D{LATCH} D{DATA} 3D{IDLE}',    '\\textit{state}'),
			('2L H 4L',                               '\\register{s\\_en}'),
			('2U 5D{\\SharedRamStartAddress}',         '\\register{s\\_addr}'),
			('3U D{mem} 3U',                          '\\register{s\\_rdata}'),
			('4L H 2L',                               '\\register{done(0)}'),
			('4U 3D{mem}',                            '\\register{rdata}'),
		]
		ann = ''
		ann += '\\draw[<->, >=Stealth] (1,{\\YBOT-0.45}) -- (4,{\\YBOT-0.45});\n'
		ann += '\\node[ann, below] at (2.5,{\\YBOT-0.47}) {3 \\register{mclk}, arbiter pins (uncontended)};\n'
		# THE GHOST NOTE HANGS UNDER THE FIGURE, NOT OFF ITS RIGHT EDGE, AND
		# THAT IS WHAT CENTRES THE FIGURE (2026-08-15, USER: "centred on the
		# page"). \centering centres the tikzpicture's BOUNDING BOX, and this
		# note used to be a ~5 cm block anchored north WEST at x=6.15 — outside
		# the 7 cycles the waveform draws — so the box reached ~4 cm further
		# right than anything visible, and centring the box pushed the visible
		# waveform left of the text block by half of that. The note is now
		# centred on the figure's own mid-cycle on a second annotation row,
		# with a leader dropping from the shaded cycle it describes, so the box
		# is symmetric about the drawing and \centering does what it says.
		ann += '\\draw[gray!65] (5.5,\\YBOT) -- (5.5,{\\YBOT-0.95});\n'
		ann += '\\node[ann, align=center, anchor=north] at (3.5,{\\YBOT-0.97})\n'
		ann += '\t{\\textit{ghost window:} \\register{req} is stale-high for one cycle\\\\[-2pt]\n'
		ann += '\t after \\register{done}, masked by \\register{need\\_release}};\n'
		s = '% Generated mp_arbiter handshake diagram\n'
		s += self._cycleFigure('1.15cm', rows, 6, ann, shade=('5', '6'),
			rowH=self._ARB_ROW_H, pitch=self._ARB_ROW_PITCH, fonts=self._ARB_FONTS)
		self._writeInclude('ArbiterHandshakeDiagram.tex', s)
		return

	# =====================================================================
	# THE STALLED TRANSACTION (CPR3/R3). The companion to the handshake
	# figure above: the SAME pins, on the one slave in the design that cannot
	# answer in the three-cycle walk that figure draws.
	#
	# THE CYCLE TABLE BELOW IS A TRANSCRIPTION, and every row of it cites the
	# line that produced it. Cycles are mclk cycles, numbered as the figure
	# draws them (cycle c occupies x = c .. c+1); a signal listed in cycle c is
	# what the pin CARRIES during c, i.e. it was registered at the edge
	# ENTERING c. That is the same convention the handshake figure uses, and it
	# is the one thing to get right: s_en is registered at the edge LEAVING
	# IDLE (mp_arbiter.vhd:229-241), so it is high in the FIRST LATCH cycle,
	# not in the IDLE one.
	#
	#  c  state  what the RTL does at the edge ENTERING this cycle    source
	#  -- ------ ---------------------------------------------------- ------
	#  0  IDLE   nothing yet; req(0) rises during c0                  arbiter:216
	#  1  IDLE   the pick runs on this cycle's req                    arbiter:219-228
	#  2  LATCH  gnt(0)/s_en/s_addr/s_master registered here;         arbiter:229-241
	#            the decode is combinational on s_addr+s_en, so
	#            tcmw_launch — and therefore s_stall — is ALREADY
	#            high in this cycle, which is what the arbiter
	#            samples at the edge that would have taken it to
	#            DATA                                                 MCU:3696-3706
	#  3  LATCH  tcm_ext_req <= tcmw_target, tcmw_busy <= '1',        MCU:3720-3736
	#            tcmw_rdata <= 0 (the unconditional zeroing);
	#            s_stall now rides on busy, not on launch
	#  4  LATCH  the tile's inbound boundary register takes the       hart_tile:767-774
	#            request — THIS EDGE IS "E" in hart_tile's own
	#            cycle table (:1067-1080); tx_state still IDLE
	#  5  LATCH  tx_state = SETTLE  (E+1): the SRAM pin mux moves     hart_tile:1160-1165
	#  6  LATCH  tx_state = READ    (E+2): tx_cen low, the single     hart_tile:1166-1169
	#            tx_ext_clk pulse happens at the edge LEAVING c6
	#  7  LATCH  tx_state = LATCH   (E+3): Q is valid                 hart_tile:1170-1177
	#  8  LATCH  tcm_ext_done pulses for exactly one mclk with        hart_tile:1174-1176,
	#            tcm_ext_rdata valid ON it (E+4, one edge, both       :1357-1358
	#            outputs — that is what makes it value-with-pulse)
	#  9  LATCH  the aperture slave captured the word (E+5):          MCU:3738-3742
	#            tcmw_rdata <= tcmw_q, tcm_ext_req <= 0,
	#            tcmw_busy <= '0' — so s_stall is LOW during c9 and
	#            s_rdata carries the word. Six mclk of tcm_ext_req
	#            (c3..c8) = the "6 mclk request-to-done" of
	#            hart_tile:1082-1086 counted from the drive edge.
	# 10  DATA   the arbiter left LATCH at the edge entering c10      arbiter:250-256
	# 11  IDLE   done(0) pulses, rdata <= s_rdata, grant held         arbiter:258-268
	#            through the done cycle
	# 12  IDLE   grant released; req(0) is still stale-high (the
	#            ghost window the handshake figure annotates)         arbiter:150-172
	#
	# The 4-state tile sequencer is NOT drawn as its own row: at this xunit a
	# one-cycle D{} cell cannot hold the word "SETTLE" (tikz-timing does not
	# shrink cell text — the I2C figure's note), and the aperture mechanism
	# figure already draws that sequencer. It is named in the span annotation
	# instead.
	# =====================================================================
	_ARB_STALL_NCYC = 13          # cycles drawn, c0..c12
	_ARB_STALL_LATCH = (2, 9)     # first/last cycle the arbiter is held in LATCH
	_ARB_STALL_SSTALL = (2, 8)    # first/last cycle s_stall is high
	_ARB_STALL_EXTREQ = (3, 8)    # first/last cycle tcm_ext_req is high
	_ARB_STALL_EXTDONE = 8        # the one-cycle tcm_ext_done pulse
	_ARB_STALL_REQSEEN = 1        # the cycle the pick runs on
	_ARB_STALL_DONE = 11          # the done(0) pulse
	# An unstalled transaction is three mclk from an observed req to done —
	# mp_arbiter_tb.vhd:308-311 (BASE_LAT) and the handshake figure above.
	_ARB_BASE_LATENCY = 3
	# hart_tile.vhd:1082-1086: six mclk from the requester's own drive edge to
	# the edge it samples tcm_ext_done on.
	_TCM_EXT_LATENCY = 6

	@staticmethod
	def _timingRow(cells):
		'''Run-length-encode a per-cycle token list into a tikz-timing string.
		   Tokens are 'L', 'H', 'U' or ('D', text). Writing the rows this way
		   (rather than as literal char strings) is what lets the assertions
		   below check the DRAWN waveform against the transcribed cycle table
		   instead of checking a copy of itself.'''
		out = []
		for cell in cells:
			if out and out[-1][0] == cell:
				out[-1][1] += 1
			else:
				out.append([cell, 1])
		parts = []
		for cell, n in out:
			pre = '' if n == 1 else str(n)
			if isinstance(cell, tuple):
				parts.append(pre + 'D{' + cell[1] + '}')
			else:
				parts.append(pre + cell)
		return ' '.join(parts)

	@staticmethod
	def _timingUnits(chars):
		'''How many cycles a tikz-timing row actually draws. Used by the
		   assertions below: splitting on spaces does NOT work, because a D{}
		   cell may contain spaces and braces of its own.'''
		units, i, n = 0.0, 0, len(chars)
		while i < n:
			if chars[i] == ' ':
				i += 1
				continue
			m = re.match(r'\d*', chars[i:])
			mult = int(m.group(0)) if m.group(0) else 1
			i += len(m.group(0))
			if i >= n:
				break

			def skipBraces(j):
				depth = 0
				while j < n:
					if chars[j] == '{':
						depth += 1
					elif chars[j] == '}':
						depth -= 1
						if depth == 0:
							return j + 1
					j += 1
				return j

			if chars[i] == '{':
				# a repeated GROUP, as in the clock row's 26{0.5C}
				body = chars[i + 1:skipBraces(i) - 1]
				per = 0.0
				for tok in body.split():
					mm = re.match(r'^([\d.]*)', tok)
					per += float(mm.group(1)) if mm.group(1) else 1.0
				units += mult * per
				i = skipBraces(i)
			else:
				i += 1
				if i < n and chars[i] == '{':
					i = skipBraces(i)
				units += mult
		return units

	def GenerateArbiterStallDiagram(self):
		'''include/ArbiterStallDiagram.tex — the SAME arbiter pins as the
		   handshake figure, on the one slave that stalls them. Emitted
		   unconditionally (the D-series/aperture precedent): the multi-core
		   chapter \\input{}s it inside its own \\iforchpresent, so a
		   configuration without apertures never renders it.

		   Drawn from hdl/common/mp_arbiter.vhd (the FSM and the s_stall port),
		   hdl/common/MCU.vhd (the aperture decode and its sequencer) and
		   hdl/common/hart_tile.vhd (the tile-side read port) — the cycle-by-
		   cycle transcription, with a line citation per cycle, is the comment
		   block above this method. Nothing here is remembered: if any of those
		   three FSMs changes, this figure must change with it.'''
		windows = self._TcmApertureWindows()
		if not windows:
			# No apertures in this configuration, so no slave asserts s_stall
			# and there is nothing to draw. The chapter's \input sits inside
			# \iforchpresent so TeX never reaches this, but a stub keeps the
			# include set the same shape in both polarities.
			self._writeInclude('ArbiterStallDiagram.tex',
				'% This configuration has no TCM apertures (no orchestrator), so no\n'
				'% slave ever asserts the arbiter\'s s_stall input.\n')
			return

		N = self._ARB_STALL_NCYC
		lat0, lat1 = self._ARB_STALL_LATCH
		st0, st1 = self._ARB_STALL_SSTALL
		rq0, rq1 = self._ARB_STALL_EXTREQ
		# The window drawn is a CHANNEL tile's where there is one (hart 1), so
		# the figure shows the boundary crossing it is about; a one-window
		# configuration falls back to hart 0's own.
		h = 1 if len(windows) > 1 else 0
		addrTex = '\\texttt{' + fmthex(windows[h]) + '}'

		def span(a, b, hi='H', lo='L'):
			return [hi if a <= c <= b else lo for c in range(N)]

		state = []
		for c in range(N):
			if c < lat0:
				state.append(('D', 'IDLE'))
			elif c <= lat1:
				state.append(('D', '\\textit{LATCH}, held while \\register{s\\_stall} is high'))
			elif c == lat1 + 1:
				state.append(('D', 'DATA'))
			else:
				state.append(('D', 'IDLE'))
		rows = [
			('%d{0.5C}' % (2 * N),                            '\\register{mclk}'),
			# req is HELD until done and drops one mclk later (the ack flop):
			# mp_arbiter.vhd:132-150. The figure ends inside that tail.
			(self._timingRow(span(self._ARB_STALL_REQSEEN, N - 1)),
			                                                  '\\register{req(0)}'),
			# grant pinned from the pick to the done cycle inclusive:
			# mp_arbiter.vhd:229-241 (IDLE), :245-247 (LATCH), :266-267 (DATA).
			(self._timingRow(span(lat0, self._ARB_STALL_DONE)), '\\register{gnt(0)}'),
			(self._timingRow(state),                          '\\textit{state}'),
			# one-cycle enable strobe, self-clearing: mp_arbiter.vhd:205-206.
			(self._timingRow(span(lat0, lat0)),               '\\register{s\\_en}'),
			(self._timingRow([('D', addrTex) if c >= lat0 else 'U' for c in range(N)]),
			                                                  '\\register{s\\_addr}'),
			# MCU.vhd:3706 — combinational on launch, then registered via busy.
			(self._timingRow(span(st0, st1)),                 '\\register{s\\_stall}'),
			# MCU.vhd:3730-3741 (raised in the sequencer, dropped on done).
			(self._timingRow(span(rq0, rq1)),                 '\\register{tcm\\_ext\\_req}'),
			# hart_tile.vhd:1174-1176 — one mclk, rdata valid with it.
			(self._timingRow(span(self._ARB_STALL_EXTDONE, self._ARB_STALL_EXTDONE)),
			                                                  '\\register{tcm\\_ext\\_done}'),
			# The slave's read bus: zeroed at the edge entering c3 (MCU.vhd:
			# 3726-3728, the unconditional zeroing) and the word from c9
			# (MCU.vhd:3738-3739 through the registered select, MCU.vhd:2922).
			(self._timingRow(['U' if c < rq0 else
			                  ('D', '0') if c <= rq1 else
			                  ('D', 'the TCM word') for c in range(N)]),
			                                                  '\\register{s\\_rdata}'),
			(self._timingRow(span(self._ARB_STALL_DONE, self._ARB_STALL_DONE)),
			                                                  '\\register{done(0)}'),
			# two cells wide only, so this one carries the SHORT spelling of the
			# same value — a D{} cell does not shrink its text to fit.
			(self._timingRow(['U' if c < self._ARB_STALL_DONE else ('D', 'the word')
			                  for c in range(N)]),            '\\register{rdata}'),
		]

		# ---- E17-style build assertions over the DRAWN waveform. Two things
		# are enumerable here and both are checked, so a change to either the
		# map or the transcribed cycle table fails `make generate` rather than
		# shipping a figure that disagrees with the RTL:
		#   (a) the address in the s_addr cell IS this configuration's window;
		#   (b) the spans drawn add up to the two latencies the RTL states in
		#       words — six mclk of tcm_ext_req (hart_tile.vhd:1082-1086) and
		#       an unstalled walk lengthened by exactly the stall
		#       (mp_arbiter_tb.vhd's S1 property, :33-35).
		drawn = re.findall(r'D\{\\texttt\{(0x[0-9A-F]+)\}\}', rows[5][0])
		if len(drawn) != 1 or int(drawn[0], 16) != windows[h]:
			raise Exception('ArbiterStallDiagram: the drawn s_addr %s is not hart %d\'s '
				'aperture window %s' % (drawn, h, fmthex(windows[h])))
		for chars, label in rows:
			units = self._timingUnits(chars)
			if units != N:
				raise Exception('ArbiterStallDiagram: row %s draws %g cycles, not %d'
					% (label, units, N))
		if rq1 - rq0 + 1 != self._TCM_EXT_LATENCY:
			raise Exception('ArbiterStallDiagram: tcm_ext_req is drawn for %d mclk, but the '
				'tile port takes %d' % (rq1 - rq0 + 1, self._TCM_EXT_LATENCY))
		stallCycles = st1 - st0 + 1
		total = self._ARB_STALL_DONE - self._ARB_STALL_REQSEEN
		if total != self._ARB_BASE_LATENCY + stallCycles:
			raise Exception('ArbiterStallDiagram: %d mclk drawn from req to done, but an '
				'unstalled walk is %d and the stall is %d cycles'
				% (total, self._ARB_BASE_LATENCY, stallCycles))
		if lat1 - lat0 + 1 != stallCycles + 1:
			raise Exception('ArbiterStallDiagram: LATCH is drawn for %d cycles, but a stall of '
				'%d holds it for %d' % (lat1 - lat0 + 1, stallCycles, stallCycles + 1))

		ann = ''
		# where an UNSTALLED transaction would have completed: the pick in c1,
		# LATCH in c2, DATA in c3, done in c4 — on the zero s_rdata is holding.
		unst = self._ARB_STALL_REQSEEN + self._ARB_BASE_LATENCY
		ann += '\\draw[gray!65] (%d,\\YTOP) -- (%d,{\\YTOP+0.40});\n' % (unst, unst)
		ann += ('\\node[ann, above] at (%d,{\\YTOP+0.38}) {without \\register{s\\_stall} the arbiter '
			'would complete here, on that zero};\n' % unst)
		ann += '\\draw[<->, >=Stealth] (%d,{\\YBOT-0.45}) -- (%d,{\\YBOT-0.45});\n' % (st0, st1 + 1)
		ann += ('\\node[ann, below] at (%.1f,{\\YBOT-0.47}) {\\register{s\\_stall}, the tile read '
			'runs here: \\textit{SETTLE}, \\textit{READ}, \\textit{LATCH}, then one \\register{mclk} '
			'of \\register{tcm\\_ext\\_done} with the word on it};\n' % ((st0 + st1 + 1) / 2.0))
		ann += '\\draw[<->, >=Stealth] (%d,{\\YBOT-1.25}) -- (%d,{\\YBOT-1.25});\n' % (
			self._ARB_STALL_REQSEEN, self._ARB_STALL_DONE)
		ann += ('\\node[ann, below] at (%.1f,{\\YBOT-1.27}) {%d \\register{mclk} at the arbiter pins '
			'while every other shared-window slave still completes in %d};\n'
			% ((self._ARB_STALL_REQSEEN + self._ARB_STALL_DONE) / 2.0, total,
			   self._ARB_BASE_LATENCY))
		s = '%% Generated mp_arbiter stalled-transaction diagram (TCM aperture, window %s)\n' % fmthex(windows[h])
		s += self._cycleFigure('0.84cm', rows, N - 1, ann,
			shade=(str(lat0), str(lat1 + 1)),
			rowH=self._ARB_ROW_H, pitch=self._ARB_ROW_PITCH, fonts=self._ARB_FONTS)
		self._writeInclude('ArbiterStallDiagram.tex', s)
		return

	# House style for the tikztimingtable-based figures (SPI/UART/I2C). These
	# keep the table form — it gives row labels and grouping for free, and
	# \vertlines works correctly in \extracode (only ABSOLUTE-y overlays are
	# unreliable there, see the comment block above). The four SPI/UART figures
	# were hand-written in the intro .tex files in body-serif at body size;
	# moving them here put every waveform in the TRM on one style.
	# Height of one signal in the table figures. tikz-timing's default yunit is
	# 1.6ex — FONT-RELATIVE, so at a 10 pt label font a bus cell came out ~2.5 mm
	# and body-size text filled it edge to edge. An ABSOLUTE yunit decouples the
	# two: the row is tall enough for \small text to sit inside the cell rather
	# than against its outline. This is safe here (an earlier note in this file
	# claimed otherwise): the table places its rows at multiples of
	# rowdist*yunit and its row labels in the same coordinate system, so raising
	# yunit scales the waveforms, the row pitch and the label positions
	# together. What does NOT scale with it is an \extracode overlay written in
	# absolute units (mm/ex) — those are the coordinates to re-check after a
	# change here, not the rows.
	_TABLE_YUNIT = '3.8mm'

	# Row pitch, in yunits. The package default of 2 put the rows exactly one
	# waveform apart, so with the taller rows above, neighbouring bus cells
	# touched (and the two SCK polarity rows merged into a chain of lozenges).
	# 2.6 leaves a clear gap without making the figures loose. An \extracode
	# overlay that hangs BELOW the last row must derive its y from this — see
	# the I2C figure — because every row's y is a multiple of it.
	_TABLE_ROWDIST = 2.6

	_TIMING_TABLE_OPTS = ('timing/font=' + _LABEL_FONT + ', '
	                      'timing/d/text/.style={font=' + _CELL_FONT + '}, '
	                      'font=' + _LABEL_FONT + ', semithick, '
	                      'timing/slope=0.2, timing/dslope=0.2, '
	                      # ABSOLUTE units, both: the defaults are font-relative,
	                      # so the house label font would otherwise scale every
	                      # waveform along with it. Each figure overrides xunit
	                      # for its own cycle count / cell contents.
	                      'timing/yunit=' + _TABLE_YUNIT + ', '
	                      'timing/rowdist=' + str(_TABLE_ROWDIST) + ', '
	                      'timing/xunit=6mm')

	# WIDTH BUDGET (the figures are \input at the left margin, not centred, so an
	# over-wide one runs off the page rather than being obviously misplaced).
	# Total width = the row-label column + xunit * (number of units in the
	# longest row) + whatever an \extracode overlay sticks out to the left. The
	# text block is 6.5 in = 165.1 mm; every figure below is tuned to land at or
	# under _MAX_FIG_WIDTH_MM with a little slack for font-metric drift. Since
	# yunit is absolute now, xunit is free to shrink for width without making
	# the waveforms shorter — but a D{} cell does NOT shrink its text to fit, so
	# the floor on xunit is the widest string a single cell has to hold.
	_MAX_FIG_WIDTH_MM = 162.0

	def _timingTable(self, rows, extraOpts='', extracode=''):
		'''rows = list of (label, charstring). Emits a styled tikztimingtable.'''
		s = '\\begin{tikztimingtable}[' + self._TIMING_TABLE_OPTS
		if extraOpts:
			s += ', ' + extraOpts
		s += ']\n'
		for label, chars in rows:
			if label is None:
				s += '\t\\\\\n'
				continue
			s += '\t' + label + ' & ' + chars + ' \\\\\n'
		if extracode:
			s += '\\extracode\n' + extracode
		s += '\\end{tikztimingtable}\n'
		return s

	def GenerateSpiFlashDiagram(self):
		'''include/SpiFlashDiagram.tex — SPI0 AND THE BOOT FLASH, in the house
		   style of the flat whole-chip figure: a masters band, one grey spine,
		   one rank, a red package boundary, and the off-chip partners on straight
		   verticals below it.

		   WHAT IT REPLACES, AND WHY. The SPI chapter used to open on a textbook
		   connection diagram — a box marked \\emph{SPI Master}, two marked
		   \\emph{SPI Slave A/B}, five wires — drawn once, by hand, for a manual
		   that was not this chip\'s. Nothing in it was derived and nothing in it
		   was true of SPI0 in particular, while the eight pages of prose around it
		   carried the whole of the real story with no picture at all: that SPI0 is
		   the BOOT FLASH\'s master, that hart 0 reaches that flash by TWO different
		   routes, and that one of those routes does not touch the shared bus.

		   THE STORY IS THE TWO PATHS, AND THE DRAWING IS BUILT AROUND THEM.
		     * The ORDINARY path: hart 0, like every other hart, taps the arbiter
		       bar, and SPI0\'s registers hang off it as one more arbiter slave.
		       That is the path every SPI0TX write takes.
		     * The PRIVATE path: adddec inside hart 0\'s own tile decodes every
		       address at or above 2^(SH_AW+2) as an extended-flash access and
		       takes it out of the tile on the flash quartet instead. It never
		       reaches the bar and nothing arbitrates it (hdl/common/adddec.vhd:
		       85-92, gen_flash_detect: `data_addr(31 downto SH_AW+2) /=
		       FLASH_ZERO\', the STRICT COMPLEMENT of the sh_sel window;
		       hdl/common/hart_tile.vhd:90-96 and 581-622 for the port and the
		       enabled-in-every-tile rule; hdl/common/MCU.vhd:2513-2516 and
		       3779-3782 for hart 0\'s hookup into SPI0).
		   So the bar is drawn STOPPING SHORT of the left margin and hart 0\'s
		   private rail runs down the lane it leaves — past the END of the bar,
		   not under it. That is the one claim this figure makes with geometry
		   rather than with words, because a reader who takes the flash window for
		   one more arbiter slave will not understand a line of the XIP section.

		   THE OTHER HARTS ARE DRAWN, AND DRAWN HONESTLY. Every tile is the same
		   netlist, so harts 1..N-1 have the decoder and the port too — with
		   nothing behind them. hart_tile.vhd:90-96 states the contract in words:
		   `other tiles leave the outputs open and flash_dout at its zeros default,
		   so their extended-flash accesses read ZEROS and never stall\'. The
		   drawing says exactly that and no more: the same box, the same decoder
		   compartment, the same stub out of the bottom of it, and the stub ENDS
		   in a small OPEN CIRCLE — the unconnected-pin idiom — with the contract
		   printed in the box above it. Nothing is greyed out or dashed, because
		   nothing here is absent. (It ended in a heavy horizontal BAR until a
		   USER read that as a ground symbol on the other tiles\' decoders, which
		   is a connection this chip does not make; see the emission below.)

		   THE CHIP SELECT HAS TWO OWNERS AND THAT IS A MECHANISM, NOT A NOTE.
		   CS_FLASH is the AF0 function of a GPIO pad and its pad driver is chosen
		   by that port\'s PxSEL bit, which resets to 0 (generate.py\'s GPIO0 bit 0:
		   rstSEL=0, rstDIR=1, rstOUT=1 — a GPIO output driven HIGH out of reset),
		   so the boot ROM toggles it as a plain GPIO while it loads the image and
		   software hands it to SPI0 by setting the bit. On the SPI0 side the pin
		   is pulled low only by the flash read machine, which is held in
		   FlashStateCSHigh whenever SPIEN or SPIFEN is 0 (SPI.vhd:580-584, 659).
		   Both drivers are drawn and they meet in a PLAIN-WORDS BOX on the pin\'s
		   own lane — the idiom the debug-stack figure\'s `either master drives the
		   same port\' box established — and never in a mux glyph.

		   TRANSCRIBED, NOT REMEMBERED. The read command is the 0x0B the flash
		   machine sends in FlashStateWaitCmd (SPI.vhd:645-646); the address is
		   24 bits because SPIxFOS is (SPI.vhd:78) and the sum is taken over
		   mab(23 downto 0) (SPI.vhd:648); the flash base is 1 << (SH_AW + 2), the
		   one expression \\FlashBaseAddress, the address-space figure and adddec\'s
		   own decode all share.

		   E17 — WHAT THE BUILD ASSERTS ABOUT THIS DRAWING:
		     * every pad name drawn is re-derived from the package model and looked
		       up in it, and each pin group is all-or-nothing (a package that bonds
		       three of the four is a package this drawing does not understand);
		     * the flash base drawn equals the resolved configuration\'s own
		       derived.flashBaseAddress, so the two cannot drift apart;
		     * the number of SPI boxes equals the number of SPIx instances this
		       configuration builds, which equals 1 + peripherals.spi1;
		     * the driver-select box contains the two lanes it merges and NO other
		       lane, so it can never read as a third driver;
		     * every partner wire lands inside its own partner box, and no two
		       partner boxes overlap.

		   IT DEGRADES INSTEAD OF LYING. A configuration whose package bonds no
		   flash quartet, or that builds no extended-flash path, loses the private
		   rail, the driver-select box and the flash partner and keeps the rest; a
		   single-hart configuration loses the other-harts column. The figure is
		   emitted unconditionally and the chapter \\input{}s it ungated, so every
		   \\ref to it resolves in every polarity.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None)
		if geo is None:
			raise Exception('SpiFlashDiagram: the configuration has no McuMpGeometry; '
				'generate.py must set it before the TRM is written.')
		N = gen.NumHarts
		pkg = gen.Package
		rc = getattr(gen, 'ResolvedConfig', None) or {}
		L = self._chipFigLines

		def P(v):
			return '%.2f' % v

		# The per-character width rule of the flat whole-chip figure, and it is
		# here for the same reason: every box height in this drawing is a LINE
		# COUNT, so a line the box cannot hold does not clip — it wraps, and
		# prints the extra line through the box floor.
		def TWs(t, bold=1.0):
			best = 0.0
			for line in (t or '').split('\\\\'):
				u = re.sub(r'\\[a-zA-Z]+', '', line)
				for ch in '{}$\\':
					u = u.replace(ch, '')
				w = 0.0
				for ch in u.strip():
					w += (0.185 if (ch.isupper() or ch.isdigit())
						else 0.085 if ch in ' .,:;/|!\'ilj' else 0.145)
				best = max(best, w * bold)
			return best
		tBold = 1.40

		def wOf(parts, minw=2.00):
			w = 0.0
			for t, bold in parts:
				w = max(w, TWs(t, bold))
			return max(minw, w + 0.34)

		# ---- the SPI instances, and the count assertion ----------------------
		spis = sorted([p for p in gen.Peripherals if p.Template.NameTemplate == 'SPIx'],
			key=lambda p: p.BaseAddress)
		if not spis:
			raise Exception('SpiFlashDiagram: this configuration instantiates no SPIx '
				'peripheral, but the SPI chapter (and this figure) is emitted for it.')
		wantSpi1 = bool((rc.get('peripherals') or {}).get('spi1', True))
		if len(spis) != (2 if wantSpi1 else 1):
			raise Exception('SpiFlashDiagram: this configuration has peripherals.spi1='
				+ str(wantSpi1) + ' but builds ' + str([p.Name for p in spis]) + ' — the figure '
				'would draw a number of SPI boxes the configuration does not have.')
		spi0, spi1 = spis[0], (spis[1] if len(spis) > 1 else None)

		# ---- the pads, straight out of the package model ---------------------
		# Both pin groups are derived by FUNCTION NAME and then looked up, so a
		# pad-ring change this drawing does not cover fails `make generate`
		# instead of shipping a wire to a ball that is not there.
		funcOf = dict((p.FuncName, p) for p in pkg.Pins if p.FuncName is not None)

		def padGroup(names, what):
			'''All of them or none of them, in package-pin order.'''
			have = [n for n in names if n in funcOf]
			if have and len(have) != len(names):
				raise Exception('SpiFlashDiagram: this package model bonds ' + str(have)
					+ ' of the ' + what + ' group ' + str(list(names)) + ' — the figure would '
					'draw a partner on a port this package brings out only in part.')
			return sorted(have, key=lambda n: funcOf[n].PackagePinNumber)
		flashPads = padGroup(('CS_FLASH', 'MISO0', 'MOSI0', 'SCK0'), 'SPI0 boot-flash')
		spi1Pads = padGroup(('CS1', 'MISO1', 'MOSI1', 'SCK1'), 'SPI1 bus')
		# THE CHIP SELECT TAKES THE LANE NEAREST THE PORT IT SHARES. Everything
		# else on a partner hangs in package-pin order, which is the order a board
		# engineer reads a data sheet in; the flash chip select is the exception
		# because it is the one wire in this drawing with TWO drivers, and the box
		# where they meet has to reach the GPIO block WITHOUT swallowing the three
		# lanes that have nothing to do with it. MEASURED, and it is why the
		# select box asserts its own contents: on the myshkin-qfn44 pad ring
		# CS_FLASH is the LAST of the four by pin number, the box spanned the
		# whole group, and the build stopped rather than draw three wires through
		# a two-driver select.
		if flashPads:
			flashPads = ['CS_FLASH'] + [n for n in flashPads if n != 'CS_FLASH']
		if spi1 is None and spi1Pads:
			raise Exception('SpiFlashDiagram: there is no SPI1 in this configuration but the '
				'package model still bonds ' + str(spi1Pads) + '.')

		# ---- the flash base, derived once and checked against the resolved
		# configuration's own copy of it. \FlashBaseAddress, the address-space
		# figure and adddec's decode are all 1 << (SH_AW+2); two derivations of it
		# are allowed to exist, drifting apart is not.
		flashBase = 1 << (geo['shAw'] + 2)
		wantBase = (rc.get('derived') or {}).get('flashBaseAddress')
		if wantBase is not None and int(str(wantBase), 16) != flashBase:
			raise Exception('SpiFlashDiagram: the drawn extended-flash base '
				+ fmthex(flashBase) + ' is not this configuration\'s derived ' + str(wantBase))
		xipOn = bool(gen.NativeSpiFlashMemoryReadAccess) and bool(flashPads)

		# ---- who drives CS_FLASH, and which register decides ------------------
		selReg, csBit, gpioTitle, gpioSub = None, None, None, None
		if xipOn:
			csPin = funcOf['CS_FLASH']
			port = csPin.Gpio.ParentPeripheral
			selReg = 'P' + str(port.GetGPIOPortLabel()) + 'SEL'
			if selReg not in [r.Name for r in port.Registers]:
				raise Exception('SpiFlashDiagram: the driver-select box would name register '
					+ selReg + ', which ' + str(port.Name) + ' does not have.')
			csBit = csPin.Gpio.BitNumber
			gpioTitle = fmttex(port.Name)
			gpioSub = 'port ' + str(port.GetGPIOPortLabel()) + ' pads'

		# ---- type metrics, in cm ---------------------------------------------
		hTitle, hLine, pad = 0.44, 0.37, 0.13
		hCmp = 0.24                       # the compartment strip's own slack
		xEdge = 0.30
		xRail = 0.42                      # hart 0's private lane, LEFT of the bar
		barL = 1.05                       # ...and the bar starts here, clear of it
		gapM, gapRank, gapExt = 0.90, 0.90, 0.30
		barH, gap1 = 0.95, 0.95           # the bar, and the band-to-bar riser
		stubOpen = 0.46                   # the other harts' open flash port
		stubDot = 0.12                    # ...and the open circle that terminates it
		stackDx, stackDy, maxShadow = 0.12, 0.20, 3

		# ---- the masters ------------------------------------------------------
		orch = bool(geo.get('orchestrator'))
		cells = ['VestaRV core', 'address decoder']
		masters = [{'title': 'hart 0', 'sub': ('orchestrator' if orch else 'management hart'),
			'note': '\\textit{the chip\'s only flash path}', 'stack': 1, 'cells': list(cells)}]
		if N > 1:
			masters.append({'title': ('hart 1' if N == 2 else 'hart 1--' + str(N - 1)),
				'sub': 'the same tile', 'stack': N - 1, 'cells': list(cells),
				'note': ('\\textit{same port, nothing behind it:}\\\\ '
					'\\textit{reads zeros, never stalls}')})
		if not xipOn:
			# Both notes are about a port this configuration does not build.
			for m in masters:
				m['note'] = ''
		for m in masters:
			m['w'] = wOf([(m['title'], tBold), (m['sub'], 1.0), (m['note'], 1.0)],
				minw=max(2.60, 2 * (TWs(max(m['cells'], key=TWs)) + 0.24)))

		# ---- the rank: the GPIO port that owns the pin at reset, then the SPIs -
		def chip(key, title, sub, cells=None, pads=None):
			return {'key': key, 'title': title, 'sub': sub, 'cells': cells or [],
				'pads': pads or [], 'w': 0.0, 'cx': 0.0}
		# The shared alternate-function OUTPUT POOL, read off the pad ring once.
		# It answers two questions this figure and the prose beside it both put:
		# which of SPI1's signals can be moved, and (the half nothing in the build
		# was checking) that SPI0's cannot. The boot flash is wired to fixed pads,
		# and it has to be — the boot ROM clocks it before any PxAFS field has
		# been written.
		pool = set()
		for p in pkg.Pins:
			if p.Gpio is not None:
				for af in p.Gpio.AltFuncs:
					pool.add(af.Name)
		fixed = [n for n in flashPads if n in pool]
		if fixed:
			raise Exception('SpiFlashDiagram: the boot-flash pins ' + str(fixed)
				+ ' are members of the shared alternate-function pool on this pad ring, so '
				'they are relocatable — the figure and the chapter both say the boot flash '
				'is wired to fixed pads.')

		rank = []
		if xipOn:
			rank.append(chip('gpio', gpioTitle, gpioSub))
		rank.append(chip('spi0', fmttex(spi0.Name),
			# The second line is the OTHER half of the honesty the harts band
			# carries: the harts with no flash behind their port read zeros and
			# never stall, and the one hart that does have flash behind it is
			# frozen for the whole of every access (SPI.vhd:656 disable_clk_cpu <=
			# FlashActive, MCU.vhd:2464 sleep_cpu <= flash_ext_meming). The two
			# lines are ten centimetres apart in the drawing and they are the same
			# fact from the two ends of the same wire.
			('the boot-flash master\\\\ \\textit{stalls hart 0 while it reads}'
				if xipOn else 'full-duplex master'),
			cells=(['flash read machine', 'registers, shift engine'] if xipOn else []),
			pads=flashPads))
		if spi1 is not None:
			# WHICH of SPI1's signals can be moved, DERIVED. Some of them are
			# members of the pool above, so they can be relocated onto other pads
			# through PxAFS (see the GPIO chapter) -- and WHICH ones is a property
			# of the AF matrix, not of this figure's memory of it: a pad-ring pass
			# that adds or drops a plane moves this line with it. (It has already
			# moved once: the chapter's prose named two, and the matrix has
			# carried three since the pin-mux v2 io slot gave MISO1 one.)
			reloc = [n for n in spi1Pads if n in pool]
			sub = 'master or slave'
			if reloc:
				sub += ('\\\\ ' + ', '.join('\\texttt{' + fmttex(n) + '}' for n in reloc)
					+ ' relocatable')
			rank.append(chip('spi1', fmttex(spi1.Name), sub, pads=spi1Pads))
		byKey = dict((c['key'], c) for c in rank)
		gpioChip, spi0Chip = byKey.get('gpio'), byKey['spi0']
		spi1Chip = byKey.get('spi1')

		# The pad LANE PITCH is set by the widest name a lane has to carry: the
		# names are printed inside the partner box, one under each stub, and two
		# that touch are two names nobody can read. MEASURED: \texttt{CS\_FLASH}
		# is 1.44 cm at this figure's body size, against the 1.10 cm pitch a
		# four-pin group would otherwise be given.
		for c in rank:
			c['pitch'] = ((max([TWs(fmttex(n)) for n in c['pads']]) + 0.30)
				if c['pads'] else 0.0)
			c['span'] = c['pitch'] * (len(c['pads']) - 1) if c['pads'] else 0.0
			cellMin = (2 * (TWs(max(c['cells'], key=TWs)) + 0.24)) if c['cells'] else 0.0
			c['w'] = wOf([(c['title'], tBold), (c['sub'], 1.0)],
				minw=max(2.40, c['span'] + 0.80, cellMin))
			c['half'] = c['span'] / 2.0 + 0.65      # its partner box's half-width

		# ---- the driver-select box, and why it sets the rank's first gap ------
		# The box merges TWO lanes that are far apart on purpose: the pin's own
		# lane under SPI0, and the port's drop under the GPIO block. It is
		# therefore at least as wide as the distance between them, and the rank
		# gap in front of SPI0 is whatever that box's TEXT needs, and no more.
		selTitle, selLines, selText = None, [], 0.0
		if xipOn:
			selTitle = 'pad driver select'
			selLines = ['\\texttt{' + fmttex(selReg) + '} bit ' + str(csBit)
					+ ' picks the driver',
				'0 at reset: the boot ROM, as plain GPIO',
				'1: ' + fmttex(spi0.Name) + ', low only during a flash read']
			selText = max([TWs(selTitle, tBold)] + [TWs(t) for t in selLines]) + 0.24

		# ---- the rail annotation, and the lane it needs ----------------------
		# Broken by hand and SHORT, because the lane it stands in is bounded by
		# the two bus taps either side of it: this is the one annotation in the
		# drawing, it is what the private path IS, and a label that fits nowhere
		# fails the build rather than being nudged onto a wire.
		railLab = ('hart 0\'s private\\\\ extended-flash port:\\\\ \\texttt{'
			+ fmthex(flashBase) + '} and above,\\\\ never through the bar')
		gap2 = (0.62 + 0.10 + hLine * L(railLab) + 0.20) if xipOn else 1.10

		# ---- heights, WHICH ARE SETTLED BEFORE ANY x IS ------------------------
		# Nothing below depends on the width, and the width has to depend on THEM:
		# this figure is \resizebox'd to the text width, so a drawing taller than
		# it is wide is blown UP by the resize and walks off the bottom of the
		# page. MEASURED on config/castalia_nospi1.json, whose rank is two boxes
		# instead of three: at 11.7 x 14.7 cm the caption printed through the page
		# footer. The rank is JUSTIFIED to a minimum aspect below, which is the
		# flat whole-chip figure's own answer and costs the drawing nothing but
		# air between blocks that were already separate.
		hCells = hCmp + hLine
		hMaster = (pad + hTitle + hLine * max(L(m['sub']) + L(m['note']) for m in masters)
			+ hCells + pad)
		hRank = (pad + hTitle + hLine * max(L(c['sub']) for c in rank)
			+ (hCells if any(c['cells'] for c in rank) else 0.0) + pad)
		hSel = (pad + hTitle + hLine * len(selLines) + pad) if xipOn else 0.0
		# The partner box: the stubs and their names at the top, the partner's own
		# name under them. The names are what a board engineer opens this figure
		# for, so they get the body size and a clear row of their own.
		hExt = 0.24 + hLine + 0.16 + hTitle + hLine + pad
		MIN_ASPECT = 1.20
		bandW = sum(m['w'] for m in masters) + gapM * (len(masters) - 1)
		# The bar's own text is one paragraph in a fixed-width node, so on a narrow
		# bar the title and the fact beside it do not overflow, they WRAP -- and a
		# \quad-joined pair wraps mid-phrase ("ev-/ery ordinary load"). MEASURED on
		# config/castalia_nospi1.json before the aspect guard widened the drawing.
		# So the two are set on ONE line where one line fits and on TWO where it
		# does not, and the bar's HEIGHT follows that decision instead of being a
		# constant the text can overrun.
		barTitle = '\\small\\bfseries multi-hart shared-bus arbiter'
		barFact = 'every ordinary load and store, one at a time'
		barNote = '\\textit{the extended-flash range is not decoded here and never arrives}'

		# The band's top slack is the shadow stack's if a stack is drawn and a flat
		# 0.34 if it is not, and yBandT below already said so.
		# heightOf used to reserve the STACKED value unconditionally, which agreed
		# with yBandT on every configuration that draws a stack and disagreed by
		# 0.20 cm on every configuration that does not.
		# No shipped chip drew a stackless band until the single-hart mcu_hart row,
		# whose master band is one box (there is no `harts 1..N-1' box at N = 1), so
		# the E17 guard below fired on the first N <= 2 build: drawn 14.08 against a
		# justified 14.28.
		# Both sites now read the same value from one place.
		def bandSlack():
			return (max(0.34, stackDy * (maxShadow - 1) + 0.14)
				if any(m['stack'] > 1 for m in masters) else 0.34)

		def heightOf(bh):
			return (0.34 + bandSlack() + hMaster + gap1 + bh
				+ gap2 + hRank + (0.42 + hSel if xipOn else 0.0) + 0.44 + 0.62 + hExt)

		def layoutRank(spread):
			x = xEdge
			for i, c in enumerate(rank):
				if i:
					gap = gapRank + spread
					if c is spi0Chip and gpioChip is not None:
						# The CS lane is spi0L + 0.40 and the box's right edge is
						# 0.45 past it, so the box reaches back to spi0L + 0.85
						# minus its own text: put SPI0 far enough right that the
						# box still starts inside the drawing.
						gap = max(gap, (selText - 0.80) - x)
					if c is spi1Chip:
						# ...and far enough right that the two partner boxes below,
						# each wider than the block it hangs off, cannot collide.
						gap = max(gap, (spi0Chip['cx'] + spi0Chip['half'] + gapExt + c['half']
							- c['w'] / 2.0) - x)
					x += gap
				c['cx'] = x + c['w'] / 2.0
				x += c['w']
			w = max(x + xEdge, barL + bandW + xEdge)
			for c in rank:
				if c['pads']:
					w = max(w, c['cx'] + c['half'] + xEdge)
			return w
		def solve(bh):
			h = heightOf(bh)
			w = layoutRank(0.0)
			if w < h * MIN_ASPECT and len(rank) > 1:
				w = layoutRank((h * MIN_ASPECT - w) / (len(rank) - 1))
			return max(w, h * MIN_ASPECT), h
		barH = 0.95
		W, hAll = solve(barH)
		barOneLine = TWs(barTitle, tBold) + TWs(barFact) + 0.90 <= (W - xEdge - barL) - 0.40
		if not barOneLine:
			# Two lines in the bar is 0.37 cm more height, which the width then has
			# to be justified against again -- and a wider bar can only make the
			# one-line form MORE likely to fit, so this settles in one more pass.
			barH = 0.95 + hLine
			W, hAll = solve(barH)

		# ---- the master band, centred over the bar ---------------------------
		xb = barL + ((W - xEdge - barL) - bandW) / 2.0
		for m in masters:
			m['cx'] = xb + m['w'] / 2.0
			xb += m['w'] + gapM

		yRedT = -0.34
		yBandT = yRedT - bandSlack()
		yBandB = yBandT - hMaster
		yBarT = yBandB - gap1
		yBarB = yBarT - barH
		yRankT = yBarB - gap2
		yRankB = yRankT - hRank
		ySelT = yRankB - 0.42
		ySelB = ySelT - hSel
		yRedB = (ySelB if xipOn else yRankB) - 0.44
		yExtT = yRedB - 0.62
		yExtB = yExtT - hExt
		yRail = yRankT + 0.62                    # the private rail's run under the bar
		yStub = yBandB - stubOpen                # the other harts' open port

		# ---- emission ---------------------------------------------------------
		s = ('% Generated SPI0/boot-flash figure (harts=' + str(N) + ', spis='
			+ str([p.Name for p in spis]) + ', xip=' + str(xipOn) + ', flashBase='
			+ fmthex(flashBase) + ', flashPads=' + str(flashPads) + ', spi1Pads='
			+ str(spi1Pads) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\thd/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt, anchor=north},\n'
		s += '\tbc/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\tsig/.style={->, >=Stealth, semithick},\n'
		s += '\treach/.style={->, >=Stealth, line width=1.4pt},\n'
		s += '\twire/.style={semithick},\n'
		s += ('\tpadlab/.style={font=\\sffamily\\scriptsize\\ttfamily, align=center, '
			'inner sep=1pt},\n')
		s += ('\trail/.style={font=\\sffamily\\scriptsize\\itshape, black!55, align=left, '
			'fill=white, inner sep=1.5pt, anchor=south west},\n')
		s += '\tredlab/.style={font=\\sffamily\\small\\bfseries, red!70!black, align=left}]\n'

		def frame(cx, yTop, w, h, fill, opts='thick'):
			return ('\\draw[' + opts + ', fill=' + fill + '] (' + P(cx - w / 2.0) + ', '
				+ P(yTop - h) + ') rectangle (' + P(cx + w / 2.0) + ', ' + P(yTop) + ');\n')

		def head(cx, yTop, w, title, sub, note=None):
			tex = '{\\small\\bfseries ' + title + '}'
			for extra in (sub, note):
				if extra:
					tex += '\\\\[1pt] ' + extra
			return ('\\node[hd, text width=' + P(w - 0.20) + 'cm] at (' + P(cx) + ', '
				+ P(yTop - pad) + ') {' + tex + '};\n')

		def shadows(cx, yTop, w, h, n, fill, opts='thick'):
			'''N copies of one tile, offset so you can see there are N. Every
			   layer carries the FRONT box's fill and border: white back copies
			   draw a shadow, not a count.'''
			out = ''
			for k in range(min(n, maxShadow) - 1, 0, -1):
				out += frame(cx + stackDx * k, yTop + stackDy * k, w, h, fill, opts)
			return out

		def compartments(cx, yTop, yBot, w, cs):
			'''The block drawn as the things the RTL builds it from — the flat
			   whole-chip figure's tile idiom, and the reason the two paths in
			   this drawing can be seen to leave the SAME decoder.'''
			out = ''
			yD = yBot + hCells
			out += ('\\draw[semithick] (' + P(cx - w / 2.0) + ', ' + P(yD) + ') -- ('
				+ P(cx + w / 2.0) + ', ' + P(yD) + ');\n')
			k = len(cs)
			for i, t in enumerate(cs):
				xL = cx - w / 2.0 + w * i / float(k)
				if i:
					out += ('\\draw[semithick] (' + P(xL) + ', ' + P(yD) + ') -- (' + P(xL)
						+ ', ' + P(yBot) + ');\n')
				out += ('\\node[bc, text width=' + P(w / float(k) - 0.16) + 'cm] at ('
					+ P(xL + w / (2.0 * k)) + ', ' + P(yBot + hCells / 2.0) + ') {' + t + '};\n')
			return out

		def redSquare(xk, yline):
			return ('\\fill[red!70!black] (' + P(xk - 0.07) + ', ' + P(yline - 0.07)
				+ ') rectangle (' + P(xk + 0.07) + ', ' + P(yline + 0.07) + ');\n')

		def brokenLine(yline, x0, x1, cuts, opts, gapw=0.14):
			'''One horizontal run with a REAL GAP at every wire that crosses it.
			   The gaps are not cosmetic: a heavy rail that touches a bus tap is
			   a junction until the reader gets close enough to see it is not.'''
			out, xc = '', x0
			for cut in sorted(c for c in cuts if x0 + gapw < c < x1 - gapw):
				if cut - gapw > xc + 0.02:
					out += ('\\draw[' + opts + '] (' + P(xc) + ', ' + P(yline) + ') -- ('
						+ P(cut - gapw) + ', ' + P(yline) + ');\n')
				xc = cut + gapw
			if x1 > xc + 0.02:
				out += ('\\draw[' + opts + '] (' + P(xc) + ', ' + P(yline) + ') -- (' + P(x1)
					+ ', ' + P(yline) + ');\n')
			return out

		def labelAt(xL, xR, cuts, wLab, lab):
			'''WHERE AN ANNOTATION MAY STAND: the leftmost gap between the wires
			   crossing its lane that is wide enough to hold it. A label that fits
			   nowhere is not nudged, it fails the build — a white label box
			   sitting on a wire reads as an open circuit, which is the exact
			   fault the AFE figure was rejected for.'''
			ivs, lo = [], xL + 0.10
			for t in sorted(t for t in cuts if xL < t < xR):
				ivs.append((lo, t - 0.16))
				lo = t + 0.16
			ivs.append((lo, xR - 0.10))
			fits = [iv for iv in ivs if iv[1] - iv[0] >= wLab]
			if not fits:
				raise Exception('SpiFlashDiagram: the annotation "' + lab + '" is ' + P(wLab)
					+ ' cm wide and the widest wire-free interval of its lane is '
					+ P(max(iv[1] - iv[0] for iv in ivs)) + ' cm: it would sit on a wire.')
			return fits[0][0]

		# ---- the red package boundary, drawn first ---------------------------
		s += ('\\draw[red!75!black, line width=1.2pt] (0.00, ' + P(yRedB) + ') rectangle ('
			+ P(W) + ', ' + P(yRedT) + ');\n')
		s += ('\\node[redlab, anchor=south west] at (0.00, ' + P(yRedT + 0.10)
			+ ') {chip boundary};\n')

		# ---- the masters ------------------------------------------------------
		for m in masters:
			s += shadows(m['cx'], yBandT, m['w'], hMaster, m['stack'], 'black!8',
				'thick, rounded corners=2pt')
			s += frame(m['cx'], yBandT, m['w'], hMaster, 'black!8', 'thick, rounded corners=2pt')
			s += head(m['cx'], yBandT, m['w'], m['title'], m['sub'], m['note'])
			s += compartments(m['cx'], yBandT, yBandB, m['w'], m['cells'])
			# The two wires that leave a tile, BOTH out of the bottom of its
			# address-decoder compartment, because that is where both are decided:
			# the shared-window request on the right, the extended-flash access on
			# the left. Bringing them out of different edges would make the split
			# a property of the drawing instead of a property of the decoder.
			# Both land INSIDE the decoder compartment (which runs from the box's
			# centre to its right edge) and clear of its divider: a wire that
			# leaves a box on a rule reads as leaving the rule.
			m['xBus'] = m['cx'] + m['w'] * 0.35
			m['xFlash'] = m['cx'] + m['w'] * 0.15
			s += ('\\draw[bus] (' + P(m['xBus']) + ', ' + P(yBandB) + ') -- (' + P(m['xBus'])
				+ ', ' + P(yBarT) + ');\n')

		# ---- THE BAR, and the lane it deliberately leaves ---------------------
		# It stops short of the left margin so hart 0's private rail passes the
		# END of it. That is the one thing in this drawing claimed by geometry
		# rather than by a caption: a rail crossing under a full-width bar would
		# be a rail the reader has to be TOLD does not touch it.
		s += ('\\draw[thick, fill=black!15] (' + P(barL) + ', ' + P(yBarB) + ') rectangle ('
			+ P(W - xEdge) + ', ' + P(yBarT) + ');\n')
		barTex = ('{' + barTitle + '} \\quad ' + barFact if barOneLine
			else '{' + barTitle + '}\\\\ ' + barFact)
		s += ('\\node[bc, text width=' + P(W - xEdge - barL - 0.40) + 'cm] at ('
			+ P((barL + W - xEdge) / 2.0) + ', ' + P(yBarB + barH / 2.0)
			+ ') {' + barTex + '\\\\ ' + barNote + '};\n')

		# ---- the rank ---------------------------------------------------------
		for c in rank:
			s += frame(c['cx'], yRankT, c['w'], hRank, 'black!5')
			s += head(c['cx'], yRankT, c['w'], c['title'], c['sub'])
			if c['cells']:
				s += compartments(c['cx'], yRankT, yRankB, c['w'], c['cells'])
			# The bus tap. On the compartmented SPI0 box it rises out of the
			# REGISTER half, which is the half of the block the bar can reach;
			# the flash half is reached only by hart 0's own rail.
			c['tx'] = (c['cx'] + c['w'] * 0.25) if c['cells'] else c['cx']
			c['fx'] = c['cx'] - c['w'] * 0.25
			s += ('\\draw[bus] (' + P(c['tx']) + ', ' + P(yRankT) + ') -- (' + P(c['tx']) + ', '
				+ P(yBarB) + ');\n')

		# ---- HART 0's PRIVATE RAIL, and the same port left open on every other -
		if xipOn:
			m0 = masters[0]
			xDrop = spi0Chip['fx']
			taps = [c['tx'] for c in rank]
			s += ('\\draw[reach, -] (' + P(m0['xFlash']) + ', ' + P(yBandB) + ') -- ('
				+ P(m0['xFlash']) + ', ' + P(yBandB - gap1 / 2.0) + ') -- (' + P(xRail) + ', '
				+ P(yBandB - gap1 / 2.0) + ') -- (' + P(xRail) + ', ' + P(yRail) + ');\n')
			s += brokenLine(yRail, xRail, xDrop, taps, 'line width=1.4pt')
			s += ('\\draw[reach] (' + P(xDrop) + ', ' + P(yRail) + ') -- (' + P(xDrop) + ', '
				+ P(yRankT) + ');\n')
			s += ('\\node[rail] at (' + P(labelAt(xRail, xDrop, taps, TWs(railLab), railLab))
				+ ', ' + P(yRail + 0.10) + ') {' + railLab + '};\n')
			# THE OPEN-PORT TERMINATOR IS A CIRCLE, NOT A BAR. It was drawn as a
			# short stub ending in a heavy horizontal bar, which is the schematic
			# glyph for GROUND — a USER read it as exactly that, and a reader who
			# believes the other tiles tie their flash port to 0 V has been taught
			# a connection this chip does not make. It is now the unconnected-pin
			# idiom every schematic uses for the same fact: the wire stops short
			# and ends in a small open (white-filled) circle, which cannot be read
			# as a rail. The contract stays in the box above it.
			for m in masters[1:]:
				s += ('\\draw[wire] (' + P(m['xFlash']) + ', ' + P(yBandB) + ') -- ('
					+ P(m['xFlash']) + ', ' + P(yStub + stubDot) + ');\n')
				s += ('\\draw[wire, fill=white] (' + P(m['xFlash']) + ', ' + P(yStub)
					+ ') circle (' + P(stubDot) + ');\n')

		# ---- the pads and the outside world ----------------------------------
		withExt = [c for c in rank if c['pads']]
		for c in withExt:
			n = len(c['pads'])
			c['lanes'] = [c['cx'] + (k - (n - 1) / 2.0) * c['pitch'] for k in range(n)]
			wExt = 2 * c['half']
			s += frame(c['cx'], yExtT, wExt, hExt, 'black!3')
			for k, xk in enumerate(c['lanes']):
				if xipOn and c is spi0Chip and c['pads'][k] == 'CS_FLASH':
					pass         # this one comes through the driver-select box below
				else:
					s += ('\\draw[wire] (' + P(xk) + ', ' + P(yRankB) + ') -- (' + P(xk) + ', '
						+ P(yExtT - 0.24) + ');\n')
					s += redSquare(xk, yRedB)
				s += ('\\draw[wire, line width=1.4pt] (' + P(xk - 0.24) + ', '
					+ P(yExtT - 0.24) + ') -- (' + P(xk + 0.24) + ', ' + P(yExtT - 0.24) + ');\n')
				s += ('\\node[padlab, anchor=north] at (' + P(xk) + ', ' + P(yExtT - 0.34)
					+ ') {' + fmttex(c['pads'][k]) + '};\n')
			extTitle, extSub = (('serial boot flash',
					'read command \\texttt{0x0B}, 24-bit address')
				if c is spi0Chip else
				('SPI1 bus devices', '\\texttt{CS1} is an input to ' + fmttex(spi1.Name)))
			s += ('\\node[hd, text width=' + P(wExt - 0.20) + 'cm] at (' + P(c['cx']) + ', '
				+ P(yExtT - 0.24 - hLine - 0.16) + ') {{\\small\\bfseries ' + extTitle
				+ '}\\\\[1pt] ' + extSub + '};\n')
			c['extL'], c['extR'] = c['cx'] - c['half'], c['cx'] + c['half']

		# E17: every partner wire lands INSIDE its own partner box, and no two
		# partner boxes overlap. Both hold by construction above; a drawing that
		# finds either out on the render has already shipped once.
		for c in withExt:
			for xk in c['lanes']:
				if not (c['extL'] + 0.10 <= xk <= c['extR'] - 0.10):
					raise Exception('SpiFlashDiagram: the straight wire at ' + P(xk)
						+ ' would enter the ' + str(c['key']) + ' partner box (which spans '
						+ P(c['extL']) + '--' + P(c['extR']) + ') off the box.')
		for a, b in zip(withExt, withExt[1:]):
			if b['extL'] - a['extR'] < 0.20:
				raise Exception('SpiFlashDiagram: the partner boxes of ' + str(a['key'])
					+ ' and ' + str(b['key']) + ' overlap (' + P(a['extR']) + ' against '
					+ P(b['extL']) + ').')

		# ---- the two drivers of CS_FLASH, meeting in a plain-words box --------
		if xipOn:
			csLane = spi0Chip['lanes'][spi0Chip['pads'].index('CS_FLASH')]
			gTap = gpioChip['cx']
			selR = csLane + 0.45
			selL = min(selR - selText, gTap - 0.45)
			if selL < 0.05:
				raise Exception('SpiFlashDiagram: the driver-select box would start at '
					+ P(selL) + ', off the left edge of the drawing — its text needs '
					+ P(selText) + ' cm and the rank does not give it that far.')
			inside = sorted(xk for c in withExt for xk in c['lanes'] if selL < xk < selR)
			if inside != [csLane]:
				raise Exception('SpiFlashDiagram: the driver-select box spans ' + P(selL)
					+ '--' + P(selR) + ', which contains the pad lanes ' + str(inside)
					+ ' instead of exactly the CS_FLASH lane at ' + P(csLane) + ' — a third '
					'wire through it would read as a third driver.')
			if not (selL + 0.10 < gTap < selR - 0.10):
				raise Exception('SpiFlashDiagram: the ' + str(gpioChip['title']) + ' drop at '
					+ P(gTap) + ' misses the driver-select box (' + P(selL) + '--' + P(selR)
					+ ').')
			for xk in (gTap, csLane):
				s += ('\\draw[sig] (' + P(xk) + ', ' + P(yRankB) + ') -- (' + P(xk) + ', '
					+ P(ySelT) + ');\n')
			s += frame((selL + selR) / 2.0, ySelT, selR - selL, hSel, 'white')
			s += head((selL + selR) / 2.0, ySelT, selR - selL, selTitle, '\\\\ '.join(selLines))
			s += ('\\draw[wire] (' + P(csLane) + ', ' + P(ySelB) + ') -- (' + P(csLane) + ', '
				+ P(yExtT - 0.24) + ');\n')
			s += redSquare(csLane, yRedB)

		s += '\\end{tikzpicture}\n'
		# E17: the height the WIDTH was justified against is the height actually
		# drawn. They are computed twice, once forwards from the band metrics and
		# once backwards off the last y, and a figure whose aspect guard was
		# computed against a height it does not have is a figure that walks off
		# the page for the reason the guard exists.
		if abs(-yExtB - hAll) > 0.01:
			raise Exception('SpiFlashDiagram: the drawn height ' + P(-yExtB) + ' cm is not the '
				+ P(hAll) + ' cm the width was justified against.')
		s = (s.split('\n', 1)[0][:-1] + ', width=' + P(W) + 'cm, height=' + P(hAll)
			+ 'cm, aspect=' + P(W / hAll) + ')\n' + s.split('\n', 1)[1])
		self._writeInclude('SpiFlashDiagram.tex', s)
		return

	def GenerateSpiTimingDiagram(self):
		'''include/SpiTimingDiagram.tex — all four SPI modes. Waveform content is
		   the proven hand-written original; only the styling changed. The two
		   vertical-line families are SEMANTIC (leading vs trailing SCK edge —
		   which one samples depends on CPHA), so they are kept as two
		   distinguishable families rather than flattened to one guide style.'''
		rows = [
			('CPOL $=0$', 'LL 15{T} LL'),
			('CPOL $=1$', 'HH 15{T} HH'),
			('CS',        'H 17L H'),
			(None, None),
			('Cycle \\#', 'U     R 8{2Q} 2U'),
			('MISO',      'D{z}  R 8{2Q} 2D{z}'),
			('MOSI',      'D{z}  R 8{2Q} 2D{z}'),
			(None, None),
			('Cycle \\#', 'UU    R 8{2Q} U'),
			('MISO',      'D{z}U R 8{2Q} D{z}'),
			('MOSI',      'D{z}U R 8{2Q} D{z}'),
		]
		extra = ''
		extra += '\t\\begin{pgfonlayer}{background}\n'
		extra += '\t\t\\begin{scope}[semithick]\n'
		extra += '\t\t\t\\vertlines[red!55, densely dotted]{2.1,4.1,...,17.1}\n'
		extra += '\t\t\t\\vertlines[blue!55, densely dashed]{3.1,5.1,...,17.1}\n'
		extra += '\t\t\\end{scope}\n'
		extra += '\t\\end{pgfonlayer}\n'
		# Group labels for the three bands of rows. These are anchored to the
		# table's OWN row-label nodes (label1..labelN, one per row including the
		# blank spacer rows) and to `all labels`, NOT to hand-counted y
		# coordinates: a row's y is rowdist*yunit, so hardcoded coordinates
		# silently slide onto the wrong band the moment the row geometry or the
		# label font changes. Band n spans label(3n-2)..label(3n) with a spacer
		# row between bands.
		extra += '\t\\path (all labels.west) ++(-2.5mm,0) coordinate (grouplabels);\n'
		extra += '\t\\begin{scope}[anchor=east, font=' + self._LABEL_FONT + ']\n'
		for band, (first, last) in enumerate([(1, 3), (5, 7), (9, 11)]):
			text = 'SCK' if band == 0 else 'CPHA $=' + str(band - 1) + '$'
			extra += ('\t\t\\coordinate (band%d) at ($(label%d.base)!0.5!(label%d.base)$);\n'
			          % (band, first, last))
			extra += '\t\t\\node at (grouplabels |- band%d) {%s};\n' % (band, text)
		extra += '\t\\end{scope}\n'
		# 19 units wide, and the CPHA/SCK group labels hang ~26 mm further left
		# than the row labels, so this is the tightest figure in the manual for
		# width. Its cells hold one digit, which needs almost none of the unit.
		s = '% Generated SPI timing diagram (all four SPI modes)\n'
		s += self._timingTable(rows, extraOpts='timing/xunit=6.3mm, timing/d/background/.style={fill=white}',
		                       extracode=extra)
		self._writeInclude('SpiTimingDiagram.tex', s)
		return

	def GenerateSpiByteOrderingDiagram(self):
		'''include/SpiByteOrderingDiagram.tex — SPITXSB/SPIRXSB byte swapping.'''
		rows = [
			('No byte swap',                '[X] D{byte 0} D{byte 1} D{byte 2} D{byte 3} D{byte 4} D{byte 5} D{byte 6} D{byte 7} D{\\ldots}'),
			('16-bit transfers, byte swap', '[X] D{byte 1} D{byte 0} D{byte 3} D{byte 2} D{byte 5} D{byte 4} D{byte 7} D{byte 6} D{\\ldots}'),
			('32-bit transfers, byte swap', '[X] D{byte 3} D{byte 2} D{byte 1} D{byte 0} D{byte 7} D{byte 6} D{byte 5} D{byte 4} D{\\ldots}'),
		]
		# 9 units; the long row labels ("32-bit transfers, byte swap") take the
		# rest. Cells hold "byte 0", so the unit cannot go much below 13 mm.
		s = '% Generated SPI byte-ordering diagram\n'
		s += self._timingTable(rows, extraOpts='timing/xunit=13.1mm')
		self._writeInclude('SpiByteOrderingDiagram.tex', s)
		return

	def GenerateSpiBitOrderingDiagram(self):
		'''include/SpiBitOrderingDiagram.tex — bit order for a 16-bit transfer,
		   showing that MSB/LSB-first is applied BEFORE the byte swap.'''
		def seq(order):
			return '[X] ' + ' '.join(['D{' + str(b) + '}' for b in order]) + ' D{\\ldots}'
		lsb = list(range(16))
		msb = list(range(15, -1, -1))
		rows = [
			('No byte swap, LSB-first', seq(lsb)),
			('Byte swap, LSB-first',    seq(lsb[8:] + lsb[:8])),
			('No byte swap, MSB-first', seq(msb)),
			('Byte swap, MSB-first',    seq(msb[8:] + msb[:8])),
		]
		# 17 units; cells hold at most two digits.
		s = '% Generated SPI bit-ordering diagram (16-bit transfer)\n'
		s += self._timingTable(rows, extraOpts='timing/xunit=7.1mm')
		self._writeInclude('SpiBitOrderingDiagram.tex', s)
		return

	def GenerateUartFrameDiagram(self):
		'''include/UartFrameDiagram.tex — one UART frame. The K/J metachars label
		   a held level in the middle of its cell (idle/start/stop); they are the
		   hand-written original's, restyled.'''
		meta = ''
		meta += 'timing/metachar={{K}[2]{#1H !{++(-.5\\xunit + 0.5*\\slope\\xunit, -.5\\yunit)} N[rectangle,scale=.8]{#2} !{++(.5\\xunit - 0.5*\\slope\\xunit, +.5\\yunit)}}}, '
		meta += 'timing/metachar={{J}[2]{#1L !{++(-.5\\xunit + 0.5*\\slope\\xunit, +.5\\yunit)} N[rectangle,scale=.8]{#2} !{++(.5\\xunit - 0.5*\\slope\\xunit, -.5\\yunit)}}}'
		rows = [('TX or RX',
		         'K{IDLE} J{START} D{D0} D{D1} D{D2} D{D3} D{D4} D{D5} D{D6} D{D7} D{\\mbox{[P]}} K{STOP} K{IDLE}')]
		# Single-row figure, so the span arrow hangs a fixed distance under row 1
		# and does not depend on the row pitch.
		extra = ''
		extra += '\t\\begin{scope}[font=' + self._NOTE_FONT + ']\n'
		extra += '\t\t\\draw[<->, >=Stealth] (1,-1.75) -- (2,-1.75);\n'
		extra += '\t\t\\node[below, inner sep=2pt] at (1.5,-2.00) {one bit period $=1/\\textrm{baud}$};\n'
		extra += '\t\\end{scope}\n'
		s = '% Generated UART data-frame diagram\n'
		# No yscale here any more: the height comes from _TABLE_YUNIT like every
		# other table figure, and the K/J metachars are written in \yunit so they
		# follow it. 13 units.
		s += self._timingTable(rows,
		                       extraOpts='timing/xunit=10.8mm, timing/d/background/.style={fill=white}, ' + meta,
		                       extracode=extra)
		self._writeInclude('UartFrameDiagram.tex', s)
		return

	def GenerateI2cTransactionDiagram(self):
		'''include/I2cTransactionDiagram.tex — one complete I2C byte write. Bus
		   protocol (START/address+R\\overline{W}/ACK/data/STOP), not chip
		   registers, so it is configuration-independent.'''
		# 1 unit = 1 SCL bit period; 18 bits = address(7)+R/W+ACK then data(8)+ACK.
		# Keep to chars proven elsewhere in this file (H/L/D{}/0.5C) — per-char
		style_note = None
		rows = [
			('\\pin{SCLx}', 'H 36{0.5C} H'),
			('\\pin{SDAx}', 'H D{A6} D{A5} D{A4} D{A3} D{A2} D{A1} D{A0} D{R/W} D{ACK} '
			               'D{D7} D{D6} D{D5} D{D4} D{D3} D{D2} D{D1} D{D0} D{ACK} H'),
		]
		# The bus-condition strip sits a fixed 0.9 units under the SDAx row, and
		# the SDAx row is one _TABLE_ROWDIST under the SCLx row — so this y is
		# DERIVED, not a literal. A hardcoded one slides up onto the waveform the
		# next time the row pitch moves.
		annY = '%.2f' % (-(self._TABLE_ROWDIST + 0.9))
		extra = ''
		extra += '\t\\begin{scope}[font=' + self._NOTE_FONT + ']\n'
		for x, text in [('0.8', 'START'), ('9.5', 'ACK'), ('18.5', 'ACK'), ('20.9', 'STOP')]:
			extra += '\t\t\\node[below, inner sep=2pt] at (' + x + ',' + annY + ') {' + text + '};\n'
		extra += '\t\\end{scope}\n'
		# THE ONE FIGURE THAT CANNOT CARRY BODY-SIZE CELL TEXT. Every cell here is
		# one SCL bit period, so they must all be the same width, and there are
		# 20 of them across a 165 mm text block — about 7 mm each. "ACK" and
		# "R/W" do not fit in 7 mm at \small (they already crowded their cells at
		# the old 7.5 mm), so this figure alone steps its cell text down. Do not
		# "fix" it by widening the ACK cells: unequal cells would misdraw the
		# protocol, which is the whole point of the figure.
		s = '% Generated I2C transaction diagram\n'
		s += self._timingTable(rows,
		                       extraOpts='timing/xunit=6.9mm, '
		                                 'timing/d/text/.style={font=\\sffamily\\footnotesize}',
		                       extracode=extra)
		self._writeInclude('I2cTransactionDiagram.tex', s)
		return

	def _cycleFigure(self, xunit, rows, guides, annotations, shade=None,
	                 rowH=None, pitch=None, fonts=None):
		'''Shared shape for the cycle-level contract waveforms (arbiter, IRQ
		   claim/complete, mutex, capture). rows = list of (chars, label), TOP
		   FIRST; the y of each row is COMPUTED from _ROW_PITCH rather than
		   written per figure, so changing the waveform height does not silently
		   overlap rows or strand the annotations. The figure exports \\YTOP and
		   \\YBOT so annotations can hang off the grid instead of hardcoding
		   coordinates that go stale with the geometry.

		   rowH/pitch/fonts override the house geometry for ONE figure. They
		   move together on purpose: the row pitch must stay clear of the row
		   height, and the D-cell font sets the floor on how narrow xunit can
		   go (a D{} cell does not shrink its text to fit). Callers that pass
		   nothing are unaffected, which is what keeps a resize of one figure
		   out of the other five.'''
		pitch = pitch or self._ROW_PITCH
		rowH = rowH or self._ROW_H
		ybot = -pitch * (len(rows) - 1)
		s = self._timingPreamble(xunit, rowH=rowH, fonts=fonts)
		s += '\\def\\YTOP{%.2f}\\def\\YBOT{%.2f}\n' % (float(rowH[:-2]) + 0.14, ybot - 0.14)
		if shade:
			s += '\\fill[black!7] (' + shade[0] + ',\\YTOP) rectangle (' + shade[1] + ',\\YBOT);\n'
		s += '\\foreach \\k in {1,...,' + str(guides) + '} { \\draw[guide] (\\k,\\YTOP) -- (\\k,\\YBOT); }\n'
		half = float(rowH[:-2]) / 2.0
		for i, (chars, label) in enumerate(rows):
			y = -pitch * i
			s += '\\timing[tim] at (0,' + ('%.2f' % y) + ') {' + chars + '};\n'
			s += '\\node[lbl] at (-0.2,' + ('%.2f' % (y + half)) + ') {' + label + '};\n'
		s += annotations
		s += '\\end{tikzpicture}\n'
		return s

	def GenerateIrqClaimCompleteDiagram(self):
		'''include/IrqClaimCompleteDiagram.tex — the M19 IRQROUTER delivery
		   contract, which the TRM otherwise only states in prose. Behaviour is
		   from hdl/common/irq_router.vhd: meip(h) = OR over i of (level(i) AND
		   en[h](i) AND NOT in_service(i)); a CLAIM read sets in_service(id),
		   masking the source out of EVERY hart until a COMPLETE write clears
		   it. That masking window is the exactly-once guarantee.'''
		# CLAIM gets TWO units, like COMPLETE: at body-size cell text a word that
		# long does not fit one unit, and a D{} cell does not shrink its text to
		# fit — it just spills over the cell outline. Widening it (rather than
		# widening the whole figure) keeps the timeline within the page. The
		# whole sequence therefore runs 12 units, not 11: CLAIM 3-5, handler
		# 5-9, COMPLETE 9-11. in_service and the masking arrow follow it.
		rows = [
			('24{0.5C}',                                   '\\register{mclk}'),
			('L 8H 3L',                                    '\\textit{level}(i)'),
			('2L 3H 7L',                                   '\\register{meip}(h)'),
			('3U 2D{CLAIM} 4D{handler} 2D{COMPLETE} U',    'hart bus'),
			('5L 6H L',                                    '\\textit{in\\_service}(i)'),
		]
		ann = ''
		ann += '\\draw[<->, >=Stealth] (5,{\\YBOT-0.55}) -- (11,{\\YBOT-0.55});\n'
		ann += '\\node[ann, below] at (8,{\\YBOT-0.58}) {source masked on every hart: exactly-once delivery};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-1.15})\n'
		ann += '\t{The handler clears the level at the peripheral \\emph{before} the dispatcher completes;\\\\[-2pt]\n'
		ann += '\t if the level is still high at COMPLETE the source simply re-pends.\\\\[-2pt]\n'
		ann += '\t The \\textsf{handler} cell stands for many \\register{mclk} cycles of software.};\n'
		s = '% Generated IRQROUTER claim/complete diagram\n'
		s += self._cycleFigure('1.05cm', rows, 11, ann, shade=('5', '11'))
		self._writeInclude('IrqClaimCompleteDiagram.tex', s)
		return

	def GenerateIrqFabricDiagram(self):
		'''include/IrqFabricDiagram.tex — the interrupt fabric of the whole chip
		   in one landscape view: where every interrupt vector on the die comes
		   from, what the IRQROUTER does with it, and the two vectors that never
		   go near the router at all. The manual describes this topology at
		   length in TWO chapters and draws it NOWHERE: Section
		   \\ref{s:interrupts} says each hart takes three lines, the IRQROUTER
		   chapter says the CLINT pair reaches each hart "on dedicated hardwired
		   wires", and a reader who has just met a claim/complete controller has
		   no reason to believe the timer and IPI interrupts are not claimed
		   through it too. THAT is the fact this figure exists to teach, so the
		   drawing is built around it:

		   THE BYPASS IS A ROUTE, NOT A LABEL. \\texttt{msip} and \\texttt{mtip}
		   leave the CLINT on two heavy rails that run along a lane UNDER the
		   router, up the far margin, and into each hart's RIGHT edge — the
		   opposite side of the hart from the router's \\texttt{meip}, which
		   arrives on its left. The router is a box those two rails pass beneath
		   and never touch. A reader who never reads the annotation still cannot
		   read the CLINT pair as going through the router, which is what
		   drawing the fact instead of writing it buys. (The emitter ASSERTS the
		   non-connection: exactly the type frames get a router-input arrow, and
		   the CLINT box gets none.)

		   THE ROW IS ITS HART. Routing row $h$ is drawn at exactly the height of
		   hart $h$'s box, so \\texttt{meip} leaves the row and enters the hart on
		   ONE straight horizontal wire, and the per-hart correspondence between
		   a row of enable words and a hart is a property of the drawing rather
		   than a sentence under it. Both columns take the same elision (all of
		   them up to five, else $0, 1, 2, \\cdots, N-1$), so they cannot fall out
		   of step; the Argus manual's eighteen harts stack in the same frame as
		   Castalia's five.

		   THE SOURCES ARE COLLAPSED BY TYPE, AND THE TOTAL IS DERIVED. A
		   hundred-and-twenty-one-row vector table is Table
		   \\ref{t:interrupt-vectors}'s job. What an overview owes the reader is
		   the SHAPE of the population, so the generator's own vector list is
		   bucketed into the same Title Case type vocabulary Figure
		   \\ref{fig:chip-system-flat-diagram} groups its rank by, each frame
		   wearing the $\\times N$ title and the offset squares that say how many
		   instances feed it, and the total strip under the column adds up to
		   \\VectorsCount{} and SPLITS it the way the hardware does: all but two
		   through the router, two on the dedicated wires. Every one of those
		   numbers is re-derived here and checked against \\texttt{VectorsCount},
		   so a peripheral added to the vector table fails \\texttt{make
		   generate} rather than quietly falling out of the drawing.

		   NO ADDRESSES, NO PACKAGE BOUNDARY. Nothing in this fabric leaves the
		   die and nothing about it is an address: the register block's base and
		   offsets are the IRQROUTER chapter's, and a red boundary round a
		   drawing with no pin in it would be decoration asserting a fact.'''
		gen = self.Gen
		N = gen.NumHarts
		compat = getattr(gen, 'McuMpCompat', None) or {}
		vecs = list(compat.get('irqVectors') or [])
		if len(vecs) != gen.VectorsCount:
			raise Exception('IrqFabricDiagram: the generator\'s IRQB vector list has '
				+ str(len(vecs)) + ' entries but VectorsCount is ' + str(gen.VectorsCount)
				+ ' — the figure would draw a source population that is not this chip\'s.')

		# ---- the two blocks this figure is about, and their derived facts ----
		irqr = clint = None
		for p in gen.Peripherals:
			if p.Name == 'IRQROUTER':
				irqr = p
			if p.Name == 'CLINT':
				clint = p
		if irqr is None or clint is None:
			raise Exception('IrqFabricDiagram: this configuration has '
				+ ('no IRQROUTER' if irqr is None else 'no CLINT')
				+ ' — the interrupt fabric this figure draws does not exist here.')
		# The free-running-MCLK clause is PRINTED IN THE DRAWING (it is why a
		# routed interrupt can wake a gated hart), so it is checked against the
		# generator's own clocking class for both blocks rather than remembered
		# from the chapter prose.
		for p in (irqr, clint):
			if p.ClockDomain != 'mclk':
				raise Exception('IrqFabricDiagram: ' + p.Name + ' is on the '
					+ str(p.ClockDomain) + ' clock, but the drawing prints the free-running '
					'MCLK clause that lets a routed interrupt wake a gated hart.')
		msipVec, mtipVec = clint.InterruptPriority, clint.InterruptPriority + 1
		meipVec = gen.MeipVector if gen.MeipVector is not None else gen.VectorsCount
		if vecs[msipVec][0] != 'IRQB_CLINT_MSIP' or vecs[mtipVec][0] != 'IRQB_CLINT_MTIP':
			raise Exception('IrqFabricDiagram: vectors ' + str(msipVec) + '/' + str(mtipVec)
				+ ' are ' + str(vecs[msipVec][0]) + '/' + str(vecs[mtipVec][0])
				+ ', not the CLINT pair the bypass rails are drawn for.')
		# The meip slot is the router's OWN delivery vector, never a routable
		# source: where it falls inside the source list it must be the reserved
		# self-slot placeholder, or the drawing would show a peripheral standing
		# on the wire the router delivers over.
		if meipVec < len(vecs) and not vecs[meipVec][0].startswith('IRQB_RSVD'):
			raise Exception('IrqFabricDiagram: the meip slot ' + str(meipVec) + ' is '
				+ str(vecs[meipVec][0]) + ', a live source — meip cannot be delivered at a '
				'vector some peripheral also pends on.')

		# ---- the enable rows, TRANSCRIBED from the register model ------------
		# hdl/common/irq_router.vhd carries one enable BIT per source per hart;
		# generate.py packs them into as many 32-bit words as the source count
		# needs (three below 96 sources, four above). The row names are read back
		# out of the emitted register model, so the figure prints the words this
		# build actually has.
		rowsOf = {}
		for h in range(N):
			rr = [r for r in irqr.Registers if re.match('^H' + str(h) + 'EN', r.Name)]
			rr.sort(key=lambda r: r.Offset)
			rowsOf[h] = [r.Name for r in rr]
		nWords = len(rowsOf[0])
		if any(len(rowsOf[h]) != nWords for h in range(N)):
			raise Exception('IrqFabricDiagram: the harts do not carry the same number of '
				'enable words (' + str(dict((h, len(rowsOf[h])) for h in range(N))) + ')')
		if not (32 * (nWords - 1) < gen.VectorsCount <= 32 * nWords):
			raise Exception('IrqFabricDiagram: ' + str(nWords) + ' enable words per hart do not '
				'exactly cover this build\'s ' + str(gen.VectorsCount) + ' vectors — the drawing '
				'would print a routing row that is too short or one word too long.')

		# ---- THE SOURCE POPULATION, COLLAPSED BY TYPE ------------------------
		# The bucket key is the vector name's own instance token (IRQB_<INST>_<sig>,
		# or IRQB_<INST> where the block has one), with its trailing index cut off:
		# GPIO4_B7 -> GPIO, RSVD117 -> RSVD, OW0 -> OW. The Title Case type names
		# are Figure \ref{fig:chip-system-flat-diagram}'s, so the two overviews
		# call the same blocks the same thing.
		TYPE_OF = {'SYS': 'System', 'GPIO': 'Digital I/O',
			'SPI': 'Comms', 'UART': 'Comms', 'I2C': 'Comms', 'I2CT': 'Comms',
			'I3C': 'Comms', 'NFC': 'Comms', 'OW': 'Comms', 'QSPI': 'Comms',
			'TIM': 'Timing \\& Sync', 'RTC': 'Timing \\& Sync', 'PWM': 'Timing \\& Sync',
			'NPU': 'Compute', 'DMA': 'Compute', 'TRNG': 'Compute',
			'RSVD': 'Reserved', 'CLINT': 'CLINT'}
		ORDER = ['System', 'Digital I/O', 'Comms', 'Timing \\& Sync', 'Compute', 'Reserved']
		count, insts, clintVecs, unknown = {}, {}, [], set()
		for i, (nm, _d) in enumerate(vecs):
			tok = nm[len('IRQB_'):].split('_')[0]
			fam = tok.rstrip('0123456789') or tok
			lab = TYPE_OF.get(fam)
			if lab is None:
				unknown.add(fam)
				continue
			if lab == 'CLINT':
				clintVecs.append(i)
				continue
			count[lab] = count.get(lab, 0) + 1
			insts.setdefault(lab, set()).add(tok)
		if unknown:
			raise Exception('IrqFabricDiagram: interrupt source family/families '
				+ str(sorted(unknown)) + ' belong to no type frame. Add the family to TYPE_OF '
				'and decide what kind of source it is — otherwise the drawing would show a '
				'vector total that is not this chip\'s.')
		if clintVecs != [msipVec, mtipVec]:
			raise Exception('IrqFabricDiagram: the CLINT occupies vectors ' + str(clintVecs)
				+ ', not the pair ' + str([msipVec, mtipVec]) + ' the bypass rails are drawn as.')
		# The RESERVED frame counts SLOTS, not instances: every reserved vector
		# carries its own RSVD<n> token, so an offset-squares stack behind it
		# would be counting nothing.
		srcs = []
		for lab in ORDER:
			n = count.get(lab, 0)
			if not n:
				continue
			k = 1 if lab == 'Reserved' else len(insts[lab])
			srcs.append({'label': lab, 'n': n, 'stack': k,
				'sub': (str(n) + ' frozen slot' + ('' if n == 1 else 's')) if lab == 'Reserved'
					else (str(n) + ' vector' + ('' if n == 1 else 's'))})
		routed = sum(x['n'] for x in srcs)
		if routed + len(clintVecs) != gen.VectorsCount:
			raise Exception('IrqFabricDiagram: the drawn type frames total ' + str(routed)
				+ ' vectors plus the CLINT pair, which is not this build\'s '
				+ str(gen.VectorsCount) + '.')

		# ---- the hart / row grid, and its elision ---------------------------
		# Draw every hart up to five and elide only beyond that (Argus is
		# eighteen), the rule Figure \ref{fig:debug-stack-diagram} already uses.
		# The ROWS take the same list, so a row and its hart are always the same
		# height and their meip wire is always straight.
		shown = list(range(N)) if N <= 5 else [0, 1, 2, None, N - 1]
		drawnH = [h for h in shown if h is not None]
		elided = N - len(drawnH)
		if len(drawnH) + elided != N:
			raise Exception('IrqFabricDiagram: %d harts drawn + %d elided is not the %d this '
				'configuration builds.' % (len(drawnH), elided, N))

		def P(v):
			return '%.2f' % v

		# Per-character width rule, in cm, copied from the flat whole-chip
		# figure: ALL-CAPS register names are half again as wide as prose, and
		# every derived name this drawing prints is all-caps.
		def TW(t, bold=1.0):
			best = 0.0
			for line in (t or '').split('\\\\'):
				u = re.sub(r'\\[a-zA-Z]+', '', line)
				for ch in '{}$\\':
					u = u.replace(ch, '')
				w = 0.0
				for ch in u.strip():
					w += (0.185 if (ch.isupper() or ch.isdigit())
						else 0.085 if ch in ' .,:;/|!\'ilj' else 0.145)
				best = max(best, w * bold)
			return best

		tBold, pad, base = 1.40, 0.13, 0.37
		stackDx, stackDy, maxShadow = 0.12, 0.20, 3

		# A TikZ node whose contents outgrow its box does not clip, it prints the
		# extra line through the floor — and every long string in this drawing is
		# a derived sentence whose length is a property of the configuration, not
		# of anything anyone typed. So the emitter BREAKS the lines itself and the
		# heights below are that line count times a baseline, rather than a guess
		# that LaTeX's own wrapping is free to exceed. (The first cut trusted
		# text width and measured only the unbroken string: the CLINT box's
		# summary strip set itself in four lines through the box under it.)
		def wrapTx(t, maxw):
			lines, cur = [], ''
			for w in t.split(' '):
				trial = (cur + ' ' + w).strip()
				if cur and TW(trial) > maxw:
					lines.append(cur)
					cur = w
				else:
					cur = trial
			if cur:
				lines.append(cur)
			return lines

		def lay(clauses, maxw):
			'''One logical clause per element; each is wrapped in place, and the
			   pair (text, line count) comes back so a box height and the text it
			   holds can never disagree.'''
			out = []
			for c in clauses:
				out += wrapTx(c, maxw)
			return '\\\\ '.join(out), len(out)

		# ---- the strings the drawing prints, all derived ---------------------
		rowTxt = dict((h, ' '.join('\\register{' + nm + '}' for nm in rowsOf[h]))
			for h in range(N))
		rtrClauses = ['the chip\'s peripheral interrupt controller',
			'\\textit{free-running MCLK: a routed interrupt wakes a hart whose gated CPU '
			'clock is off}']
		rowHead = ('Per-Hart Routing Rows \\quad one enable bit per vector, vectors '
			+ str(gen.VectorsCount - 1) + ':0 \\quad reset all-zero, fully masked')
		claimClauses = ['\\register{CLAIM} read = claim the lowest pending vector enabled for '
			'the reading hart \\quad write = complete',
			'\\register{PEND} raw deglitched levels \\quad \\register{INSVC} under service '
			'\\quad fixed priority: lowest vector number wins']
		annTxt = ('\\textit{a claimed vector is masked from every hart\'s \\texttt{meip} until it '
			'is completed, so a source routed to several harts is serviced by exactly one}')
		byClauses = ['\\textit{\\texttt{msip} and \\texttt{mtip} bypass the router entirely: '
			'dedicated hardwired wires, one pair per hart, always enabled}',
			'\\textit{the router\'s row bits ' + str(msipVec) + ' and ' + str(mtipVec)
			+ ' are writable but inert, and no CLINT interrupt is ever claimed}']
		totTxt = ('$\\Sigma$ \\textbf{' + str(gen.VectorsCount) + ' interrupt vectors} \\quad '
			+ str(routed) + ' through the router \\quad ' + str(len(clintVecs))
			+ ' on dedicated per-hart wires, never routed and never claimed')
		clintSub = 'software (IPI) \\& timer, per hart'

		# ---- widths ----------------------------------------------------------
		# The rank of type frames and the hart column are sized by their own
		# (short) contents; the ROUTER is given a floor wide enough that its
		# derived sentences come out in one or two lines rather than five, since
		# the spine's width is what sets the aspect of the whole drawing and a
		# tall figure lands small on the page.
		wSrc = 3.30
		for sp in srcs:
			t = sp['label'] + ('' if sp['stack'] < 2 else ' $\\times$' + str(sp['stack']))
			sp['title'] = t
			wSrc = max(wSrc, 0.40 + max(TW(t, tBold), TW(sp['sub'])) + stackDx * 2)
		wSrc = max(wSrc, 0.40 + TW('CLINT', tBold), 0.40 + TW(clintSub))
		wHart = max(2.00, 0.40 + TW('hart ' + str(N - 1), tBold))
		wRtr = max(12.00, 0.50 + max([TW(rowTxt[h]) for h in drawnH] + [TW(rowHead)]))

		xEdge, gapA, gapB, gapC = 0.30, 1.30, 2.30, 0.85
		xSrcL = xEdge
		xSrcR = xSrcL + wSrc
		xRtrL = xSrcR + gapA
		xRtrR = xRtrL + wRtr
		xHartL = xRtrR + gapB
		xHartR = xHartL + wHart
		xRailA = xHartR + gapC
		xRailB = xRailA + gapC
		W = xRailB + 1.15

		# ---- the wrapped text, and the heights that are its line count --------
		wIn = wRtr - 0.50
		rtrSub, nRtr = lay(rtrClauses, wIn)
		rowHeadTx, nRowHd = lay([rowHead], wIn)
		claimSub, nClaim = lay(claimClauses, wIn - 0.20)
		annTx, nAnn = lay([annTxt], wIn - 0.20)
		clintTx, nClint = lay([clintSub], wSrc - 0.24)
		byTx, nBy = lay(byClauses, (xRailB - xRtrL))
		totTx, nTot = lay([totTxt], (xRailB - xSrcL) - 0.30)

		hHead = 2 * pad + 0.44 + nRtr * base
		hRowHd = 0.10 + nRowHd * base
		hRow, pitch, hHart = 0.46, 1.16, 0.86
		hClaim = 2 * pad + 0.44 + nClaim * base
		hAnn = 0.16 + nAnn * base
		hClint = 2 * pad + 0.44 + nClint * base
		hTot = 0.18 + nTot * base

		yRtrT = 0.00
		yGridT = yRtrT - hHead - hRowHd - 0.18
		yc = [yGridT - 0.16 - hHart / 2.0 - i * pitch for i in range(len(shown))]
		yGridB = yc[-1] - hHart / 2.0 - 0.16
		yClaimT = yGridB - 0.30
		yAnnT = yClaimT - hClaim - 0.16
		yRtrB = yAnnT - hAnn - 0.16
		yClintT = yRtrB - 0.85
		yClintB = yClintT - hClint
		yLaneA, yLaneB = yClintT - 0.36, yClintT - 0.74
		yByT = min(yClintB, yLaneB - 0.30) - 0.34
		yTotT = yByT - nBy * base - 0.36
		yBot = yTotT - hTot - 0.25
		yLabel = 0.42                            # the band headings, above it all

		# ---- emission ---------------------------------------------------------
		s = ('% Generated interrupt-fabric overview (harts=' + str(N)
			+ ', vectors=' + str(gen.VectorsCount) + ', routed=' + str(routed)
			+ ', meip=' + str(meipVec) + ', msip=' + str(msipVec) + ', mtip=' + str(mtipVec)
			+ ', enableWords=' + str(nWords) + ', elided=' + str(elided)
			+ ', types=' + str([(x['label'], x['n'], x['stack']) for x in srcs]) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\thd/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt, anchor=north},\n'
		s += '\tbc/.style={font=\\sffamily\\scriptsize, align=center, inner sep=1pt},\n'
		s += '\tsig/.style={->, >=Stealth, semithick},\n'
		# The bypass rails are the heaviest stroke in the drawing on purpose:
		# at 1.5 pt they read as one more box border on the whole-page view.
		s += '\trail/.style={line width=1.9pt, black!70},\n'
		s += ('\ttyp/.style={font=\\sffamily\\large\\itshape, black!55, align=left, '
			'inner sep=1.5pt, anchor=south west},\n')
		s += ('\tlane/.style={font=\\sffamily\\scriptsize, align=center, fill=white, '
			'inner sep=1.5pt, anchor=south},\n')
		s += ('\tnote/.style={font=\\sffamily\\scriptsize, black!60, align=left, '
			'inner sep=1.5pt, anchor=north west}]\n')

		def frame(cx, yTop, w, h, fill, opts='thick'):
			return ('\\draw[' + opts + ', fill=' + fill + '] (' + P(cx - w / 2.0) + ', '
				+ P(yTop - h) + ') rectangle (' + P(cx + w / 2.0) + ', ' + P(yTop) + ');\n')

		def shadows(cx, yTop, w, h, n, fill, opts='thick'):
			out = ''
			for k in range(min(n, maxShadow) - 1, 0, -1):
				out += frame(cx + stackDx * k, yTop + stackDy * k, w, h, fill, opts)
			return out

		def head(cx, yTop, w, title, sub=None):
			tex = '{\\small\\bfseries ' + title + '}'
			if sub:
				tex += '\\\\[1pt] ' + sub
			return ('\\node[hd, text width=' + P(w - 0.20) + 'cm] at (' + P(cx) + ', '
				+ P(yTop - pad) + ') {' + tex + '};\n')

		xRtrC = (xRtrL + xRtrR) / 2.0
		xSrcC = (xSrcL + xSrcR) / 2.0
		xHartC = (xHartL + xHartR) / 2.0

		# ---- band headings ----------------------------------------------------
		s += '\\node[typ] at (' + P(xSrcL) + ', ' + P(yLabel) + ') {Interrupt Sources};\n'
		s += ('\\node[typ] at (' + P(xHartL - 0.10) + ', ' + P(yLabel) + ') {Harts $\\times$'
			+ str(N) + '};\n')

		# ---- the router spine -------------------------------------------------
		hRtr = yRtrT - yRtrB
		s += frame(xRtrC, yRtrT, wRtr, hRtr, 'black!8')
		s += head(xRtrC, yRtrT, wRtr, 'IRQROUTER', rtrSub)
		s += ('\\draw[semithick, black!45] (' + P(xRtrL) + ', ' + P(yRtrT - hHead) + ') -- ('
			+ P(xRtrR) + ', ' + P(yRtrT - hHead) + ');\n')
		s += ('\\node[bc, text width=' + P(wRtr - 0.30) + 'cm] at (' + P(xRtrC) + ', '
			+ P(yRtrT - hHead - hRowHd / 2.0) + ') {' + rowHeadTx + '};\n')
		wRow = wRtr - 0.44
		for i, h in enumerate(shown):
			if h is None:
				s += ('\\node[font=\\sffamily\\Large] at (' + P(xRtrC) + ', ' + P(yc[i])
					+ ') {$\\cdots$};\n')
				continue
			s += frame(xRtrC, yc[i] + hRow / 2.0, wRow, hRow, 'white')
			s += ('\\node[bc] at (' + P(xRtrC) + ', ' + P(yc[i]) + ') {' + rowTxt[h] + '};\n')
		# the claim/pend/in-service machinery, one compact box
		s += frame(xRtrC, yClaimT, wRow, hClaim, 'white')
		s += head(xRtrC, yClaimT, wRow, 'Claim / Pend / In-Service', claimSub)
		# ...and the ONE annotation this drawing carries
		s += ('\\node[bc, text width=' + P(wRtr - 0.36) + 'cm] at (' + P(xRtrC) + ', '
			+ P(yAnnT - hAnn / 2.0) + ') {' + annTx + '};\n')

		# ---- the source type frames, and their one arrow each -----------------
		hSrc = 2 * pad + 0.44 + 0.37
		gapSrc = 0.34
		if len(srcs) > 1:
			gapSrc = min(1.10, max(0.34,
				(hRtr - 0.40 - len(srcs) * hSrc) / float(len(srcs) - 1)))
		ySrcT = yRtrT - 0.20
		fed = []
		for i, sp in enumerate(srcs):
			yT = ySrcT - i * (hSrc + gapSrc)
			cy = yT - hSrc / 2.0
			s += shadows(xSrcC - stackDx, yT, wSrc - stackDx * 2, hSrc, sp['stack'], 'white')
			s += frame(xSrcC - stackDx, yT, wSrc - stackDx * 2, hSrc, 'white')
			s += head(xSrcC - stackDx, yT, wSrc - stackDx * 2, sp['title'], sp['sub'])
			s += ('\\draw[sig] (' + P(xSrcR - stackDx) + ', ' + P(cy) + ') -- (' + P(xRtrL)
				+ ', ' + P(cy) + ');\n')
			fed.append(sp['label'])
		# E17, and the whole of what the bypass claims: exactly the type frames
		# feed the router, and the CLINT feeds it nothing.
		if sorted(fed) != sorted(x['label'] for x in srcs) or 'CLINT' in fed:
			raise Exception('IrqFabricDiagram: the blocks drawn with a router input are '
				+ str(sorted(fed)) + ', which is not the type-frame set '
				+ str(sorted(x['label'] for x in srcs)) + ' with the CLINT outside it.')

		# ---- the CLINT, and the two rails that go round the router ------------
		s += frame(xSrcC, yClintT, wSrc, hClint, 'black!8')
		s += head(xSrcC, yClintT, wSrc, 'CLINT', clintTx)
		# The bypass annotation sits UNDER the two rails, in the lane they run
		# along, so it reads as a note on them and not on the router above.
		s += ('\\node[note, text width=' + P(xRailB - xRtrL) + 'cm] at (' + P(xRtrL) + ', '
			+ P(yByT) + ') {' + byTx + '};\n')
		# The total: one grey strip across the whole drawing, which is where the
		# source population and the bypass pair finally add up to one number.
		s += ('\\draw[thick, fill=black!15] (' + P(xSrcL) + ', ' + P(yTotT - hTot)
			+ ') rectangle (' + P(xRailB) + ', ' + P(yTotT) + ');\n')
		s += ('\\node[bc, text width=' + P(xRailB - xSrcL - 0.30) + 'cm] at ('
			+ P((xSrcL + xRailB) / 2.0) + ', ' + P(yTotT - hTot / 2.0) + ') {' + totTx + '};\n')

		# ---- the harts, their meip, and the two rails into their far side -----
		portM, portT = 0.26, 0.26
		for i, h in enumerate(shown):
			if h is None:
				s += ('\\node[font=\\sffamily\\Large] at (' + P(xHartC) + ', ' + P(yc[i])
					+ ') {$\\cdots$};\n')
				continue
			s += frame(xHartC, yc[i] + hHart / 2.0, wHart, hHart, 'black!8',
				'thick, rounded corners=2pt')
			s += ('\\node[bc] at (' + P(xHartC) + ', ' + P(yc[i])
				+ ') {{\\small\\bfseries hart ' + str(h) + '}};\n')
			# meip, straight out of this hart's own routing row
			s += ('\\draw[sig] (' + P(xRtrR) + ', ' + P(yc[i]) + ') -- (' + P(xHartL) + ', '
				+ P(yc[i]) + ');\n')
			# msip off rail A, and mtip off rail B with a REAL GAP where it
			# crosses rail A: a heavy rail a stub touches is a junction until the
			# reader gets close enough to see it is not.
			s += ('\\draw[rail, ->, >=Stealth] (' + P(xRailA) + ', ' + P(yc[i] + portM)
				+ ') -- (' + P(xHartR) + ', ' + P(yc[i] + portM) + ');\n')
			s += ('\\draw[rail] (' + P(xRailB) + ', ' + P(yc[i] - portT) + ') -- ('
				+ P(xRailA + 0.14) + ', ' + P(yc[i] - portT) + ');\n')
			s += ('\\draw[rail, ->, >=Stealth] (' + P(xRailA - 0.14) + ', ' + P(yc[i] - portT)
				+ ') -- (' + P(xHartR) + ', ' + P(yc[i] - portT) + ');\n')
		# the rails themselves: out of the CLINT, along a lane UNDER the router,
		# and up the far margin. They touch nothing between the two.
		yTopA, yTopB = yc[0] + portM + 0.55, yc[0] + portM + 1.60
		s += ('\\draw[rail] (' + P(xSrcR) + ', ' + P(yLaneA) + ') -- (' + P(xRailA) + ', '
			+ P(yLaneA) + ') -- (' + P(xRailA) + ', ' + P(yTopA) + ');\n')
		s += ('\\draw[rail] (' + P(xSrcR) + ', ' + P(yLaneB) + ') -- (' + P(xRailB) + ', '
			+ P(yLaneB) + ') -- (' + P(xRailB) + ', ' + P(yTopB) + ');\n')

		# ---- the three lanes, named once each, above the top hart -------------
		# They are staggered in height because the two rails are 8.5 mm apart and
		# a lane name is 13 mm wide: side by side they printed through each other.
		s += ('\\node[lane] at (' + P((xRtrR + xHartL) / 2.0) + ', ' + P(yc[0] + 0.55)
			+ ') {\\texttt{meip}\\\\ vector ' + str(meipVec) + '};\n')
		s += ('\\node[lane] at (' + P(xRailA) + ', ' + P(yTopA)
			+ ') {\\texttt{msip}\\\\ vector ' + str(msipVec) + '};\n')
		s += ('\\node[lane] at (' + P(xRailB) + ', ' + P(yTopB)
			+ ') {\\texttt{mtip}\\\\ vector ' + str(mtipVec) + '};\n')

		s += '\\end{tikzpicture}\n'
		hAll = yLabel + 0.40 - yBot
		s = (s.split('\n', 1)[0][:-1] + ', width=' + P(W) + 'cm, height=' + P(hAll)
			+ 'cm, aspect=' + P(W / hAll) + ')\n' + s.split('\n', 1)[1])
		self._writeInclude('IrqFabricDiagram.tex', s)
		return

	def GenerateMutexClaimDiagram(self):
		'''include/MutexClaimDiagram.tex — the return-old-and-claim read that
		   makes the MUTEX bank a one-instruction lock (hdl/common/mutex_bank.vhd).
		   Two harts race for the same mutex; the arbiter serializes the two
		   reads, so the claim is atomic with no retry loop.

		   D-series sweep (s2): the racers are two CHANNEL harts, not hart 0.
		   Hart 0 is the management/orchestrator hart on every configuration
		   this manual is built for, and using it as one of two interchangeable
		   racers teaches the wrong picture of the chip. The pair is DERIVED so
		   the figure is config-agnostic: harts 1 and 2 wherever a third hart
		   exists (every shipped configuration -- N is 4, 5 or 18), falling back
		   to the historical 0/1 pair on a hypothetical two-hart build rather
		   than raising. The winner's marker is its \\register{mhartid}$+1$
		   (hdl/common/mutex_bank.vhd:108, `owner := master + 1`), so it is
		   drawn from the racer index and never from a literal.'''
		lo = 1 if self.Gen.NumHarts >= 3 else 0
		hi = lo + 1
		loS, hiS = str(lo), str(hi)
		rows = [
			('16{0.5C}',                                                 '\\register{mclk}'),
			('U 2D{\\asminline{lw} MUTEX0} 4U 2D{\\asminline{sw x0}}',   'hart ' + loS + ' bus'),
			('3U 2D{\\asminline{lw} MUTEX0} 4U',                         'hart ' + hiS + ' bus'),
			('3D{free} 5D{owned by hart ' + loS + '} D{free}',           '\\textit{owner}[0]'),
			('3U D{0} 5U',                                               'hart ' + loS + ' result'),
			('5U D{' + str(lo + 1) + '} 3U',                             'hart ' + hiS + ' result'),
		]
		ann = ''
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-0.35})\n'
		ann += '\t{\\textbf{0} = the mutex was free and is now yours. A non-zero result is the holder\'s\\\\[-2pt]\n'
		ann += '\t \\register{mhartid}$+1$, so hart ' + hiS + ' must back off and retry. Release with \\asminline{sw x0}.};\n'
		s = '% Generated MUTEX claim/release diagram\n'
		s += self._cycleFigure('1.15cm', rows, 8, ann)
		self._writeInclude('MutexClaimDiagram.tex', s)
		return

	def GeneratePowerDomainDiagram(self):
		'''include/PowerDomainDiagram.tex — the chip's power architecture: ONE
		   always-on domain and N-1 switched tile rails, and what a PWRCR gate
		   bit actually does to one of them.

		   DRAWN FROM THE RTL, every claim cited:
		     * hdl/common/pwr_ctrl.vhd — the pd_iso_en/pd_sleep/pd_rstn rows are
		       (NHARTS-1 downto 1), hart 0 has NO row; PWRCR bit 0 reads 0 and
		       ignores writes; the sequencer order is iso -> rstn -> sleep on the
		       gate and sleep -> T_RAIL -> iso -> rstn on the wake, with the six
		       PWRSR nibble states S_ON/S_ISO/S_RSTOFF/S_OFF/S_RAIL/S_UNISO.
		     * mcu_vhd.py emitIsoClamps() — the clamps are EXPLICIT RTL AND gates
		       on the ALWAYS-ON side (`... when pd_iso_en(h) = '0' else 0`), which
		       is why the clamp layer is drawn above the boundary and not inside
		       the tile; the clamped list is that emitter's row list.
		     * mcu_vhd.py emitTileRstn() — tile_rstn(h) = resetn and pd_rstn(h)
		       and pgood_rstn, i.e. the cold-gate reset AND the DP-S3 boot gate.
		     * mcu_vhd.py tileInstance() — tcm_pgen => pd_sleep(h): the TCM macro
		       power-gates itself off the same wire, which is why it is drawn
		       inside the switched band even though its VDD pin is always-on.
		     * cpf/hart_tile.cpf — PD_AO / PD_GATED, the HEADBUF16MA10TH switch
		       rule (PSW_TILE), VDD -> VDD_SW, and the explicit NO-RETENTION
		       decision that makes wake a cold boot (the M12/M17a contract).
		     * mcu_vhd.py emitTcmApertures() — tcmw_dark(h) = pd_iso_en(h) or not
		       tile_rstn(h): a dark tile's aperture completes with zeros (R4-A2).

		   UNGATED on purpose: tiles 1..N-1 are gateable on every configuration
		   this manual is built for. What DOES switch is hart 0's own story --- an
		   always-on SOFT orchestrator with no header switches, or an always-on
		   hart TILE whose pd_* controls are simply tied inactive --- so the
		   hart-0 box derives its wording from the orchestrator knob and nothing
		   else in the figure moves.

		   E17: the drawn PWRCR bit map is enumerable from the hart count, so it
		   is collected while drawing and cross-checked against the REGISTER
		   MODEL (generate.py's PWRGATE / PWRH0 bit fields, the same source
		   MemoryMap.h's PWRGATE_MASK comes from). The tile columns are checked
		   against N-1 including the elided ones.

		   LAYOUT is a GRID, and that is the whole readability argument: the four
		   horizontal layers are the mechanism (clamps / header switches / the
		   tile / its TCM), the columns are the tiles, so "every tile has all
		   four" is a property of the drawing rather than a sentence. The long
		   explanations live in the left margin at each layer's own height and
		   are kept to what fits there --- pass 1 of this figure put five-sentence
		   labels in that column and they overprinted each other and the band
		   banner. Anything longer belongs in the caption.'''
		N = self.Gen.NumHarts
		if N < 2:
			# Degrade, never raise: a single-hart build has no switched domain to
			# draw. The chapter's \input still resolves.
			self._writeInclude('PowerDomainDiagram.tex',
				'% numHarts=' + str(N) + ': no switchable tile domains, figure suppressed.\n')
			return
		orch = bool((getattr(self.Gen, 'McuMpGeometry', None) or {}).get('orchestrator'))
		apertures = bool(self._TcmApertureWindows())
		tcmKiB = self.Gen.RamMemorySlotSize // 1024

		def P(v):
			return '%.2f' % v

		# ---- which tile columns are drawn. Every channel tile up to four; only
		# beyond that is the row elided (Argus has seventeen). An elided
		# four-tile chip would be a picture of a chip that does not exist.
		tiles = list(range(1, N))
		if len(tiles) > 4:
			shown = [tiles[0], tiles[1], None, tiles[-1]]
		else:
			shown = list(tiles)
		drawnTiles = [t for t in shown if t is not None]
		elided = len(tiles) - len(drawnTiles)

		tileW, elW, gap = 2.95, 1.05, 0.40
		xCol0 = 6.10
		cols = []
		x = xCol0
		for t in shown:
			w = elW if t is None else tileW
			cols.append((t, x + w / 2.0, w))
			x += w + gap
		colsX1 = x - gap

		# ---- the PWRCR bit strip: one cell per bit N-1..0 plus the reserved
		# cell above them. This is the enumerable content the assertion guards.
		cellW = 0.64 if N <= 8 else 0.42
		cellH, resW = 0.62, 1.75
		xStrip0 = xCol0
		strip = [('reserved', None, resW)]
		for b in range(N - 1, -1, -1):
			strip.append(('gate' if b >= 1 else 'ro', b, cellW))
		stripW = sum(c[2] for c in strip)
		# --- E17 cross-check against the register model -------------------
		drawnMask = 0
		for role, b, _w in strip:
			if role == 'gate':
				drawnMask |= 1 << b
		modelMask, h0Field = None, None
		for p in self.Gen.Peripherals:
			if p.Name != 'PWRCTRL':
				continue
			for r in p.Registers:
				if r.Name != 'PWRCR':
					continue
				for bf in r.BitFields:
					if bf.Name == 'PWRGATE':
						modelMask = bf.BitMask
					if bf.Name == 'PWRH0':
						h0Field = bf
		if modelMask is None or h0Field is None:
			raise Exception('PowerDomainDiagram: the configuration has no PWRCTRL PWRCR '
				'PWRGATE/PWRH0 bit fields to check the drawn bit map against.')
		if drawnMask != modelMask:
			raise Exception('PowerDomainDiagram: the figure draws gate bits 0x%X but the '
				'PWRCR register model says 0x%X — the picture and the register table '
				'would disagree.' % (drawnMask, modelMask))
		if not (h0Field.MSB == 0 and h0Field.LSB == 0 and h0Field.Accessibility == 'r'):
			raise Exception('PowerDomainDiagram: PWRH0 is %s bits %d:%d, not a read-only '
				'bit 0 — the figure draws hart 0 as the reserved always-on bit.'
				% (h0Field.Accessibility, h0Field.MSB, h0Field.LSB))
		if len(drawnTiles) + elided != N - 1:
			raise Exception('PowerDomainDiagram: %d tile columns drawn + %d elided is not the '
				'%d switchable domains pwr_ctrl instantiates.' % (len(drawnTiles), elided, N - 1))

		noteW, pwrW, margin = 4.60, 4.70, 0.25
		# The shared-fabric box carries the most text in the picture, so the
		# figure width has a FLOOR as well as a content-derived value: at N=4 the
		# columns and the bit strip are both short, the fabric box was squeezed to
		# 4.4 cm, and it grew vertically straight through the banner above it and
		# the bit strip below (caught by rendering the castalia4 manual, not by
		# any gate). 7.20 cm is the measured width at which its text fits the row.
		W = max(colsX1, xStrip0 + stripW + 0.30 + noteW,
			xCol0 + 7.20 + 0.55 + pwrW) + margin

		# ---- vertical anchors, in cm (everything below derives from these)
		yTop, yBan = 16.05, 15.25      # always-on banner strip
		yBoxT, yBoxB = 15.00, 11.90    # the always-on row of three
		yStrip = 10.85                 # PWRCR bit strip centre line
		yHead = 9.20                   # per-column header row (two lines)
		yClT, yClB = 8.85, 7.70        # the isolation-clamp layer
		yBnd = 7.30                    # THE domain boundary
		yHdT, yHdB = 6.95, 5.90        # the header-switch layer
		yCoT, yCoB = 5.55, 3.75        # the tile core layer
		yTcT, yTcB = 3.40, 2.10        # the TCM layer
		ySwB, ySwBan = 0.70, 1.50      # switched band floor + its banner strip
		xLab0, xLab1 = 0.20, 5.30      # the left label column
		xRis = 5.60                    # the always-on control riser
		yRis = 11.72                   # its horizontal run, under the AO boxes

		s = '% Generated power-domain diagram (numHarts=' + str(N) + ', orchestrator='
		s += ('yes' if orch else 'no') + ', gate mask ' + fmthex(drawnMask, minDigits=2) + ')\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small},\n'
		s += '\tunit/.style={blk, fill=black!12},\n'
		s += '\taob/.style={blk, fill=black!6},\n'
		s += '\tclamp/.style={blk, fill=black!16, font=\\sffamily\\scriptsize},\n'
		s += '\thead/.style={blk, fill=black!22, font=\\sffamily\\scriptsize},\n'
		s += '\tcore/.style={blk, fill=white, font=\\sffamily\\scriptsize},\n'
		s += '\ttcm/.style={blk, fill=black!8, font=\\sffamily\\scriptsize},\n'
		s += '\tcell/.style={draw, thick, fill=white, font=\\sffamily\\scriptsize, '
		s += 'minimum height=' + P(cellH) + 'cm, inner sep=0pt},\n'
		s += '\tctrl/.style={->, >=Stealth, thick},\n'
		s += '\tban/.style={font=\\sffamily\\small\\bfseries, black!60},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=left},\n'
		s += '\tkey/.style={draw, thick, dashed, align=left, font=\\sffamily\\scriptsize, '
		s += 'fill=white, inner sep=4pt}]\n'

		# ---- the two bands, drawn first so everything sits on top of them
		s += '\\fill[black!7] (0, ' + P(yBnd) + ') rectangle (' + P(W) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!14] (0, ' + P(yBan) + ') rectangle (' + P(W) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!3] (0, ' + P(ySwB) + ') rectangle (' + P(W) + ', ' + P(yBnd) + ');\n'
		s += '\\fill[black!10] (0, ' + P(ySwB) + ') rectangle (' + P(W) + ', ' + P(ySwBan) + ');\n'
		s += '\\node[ban] at (' + P(W / 2.0) + ', ' + P((yBan + yTop) / 2.0) + ') '
		s += '{the always-on domain: \\texttt{VDD}, never switched};\n'
		s += '\\node[ban] at (' + P(W / 2.0) + ', ' + P((ySwB + ySwBan) / 2.0) + ') '
		s += '{' + _numberWord(len(tiles)) + ' switched tile rails: \\texttt{VDD\\_SW}, '
		s += 'one per channel tile, each gated on its own};\n'
		# THE boundary: a real line, labelled, with the one true claim on it
		s += '\\draw[line width=1.4pt, black!60] (0, ' + P(yBnd) + ') -- (' + P(W) + ', ' + P(yBnd) + ');\n'
		s += '\\node[font=\\sffamily\\scriptsize\\bfseries, black!60, fill=black!5, inner sep=2pt] '
		s += 'at (' + P(W - 3.10) + ', ' + P(yBnd) + ') {the power-domain boundary};\n'

		# ---- band A: hart 0, the fabric it shares, and the controller
		h0W = xLab1 - xLab0
		if orch:
			h0 = ('{\\textbf{hart 0}: the orchestrator\\\\[2pt] soft core $+$ '
				+ str(tcmKiB) + '\\,KiB TCM,\\\\ in the always-on centre band\\\\[3pt] '
				'\\scriptsize no header switches exist\\\\ \\scriptsize for it: no gate bit, '
				'no clamps,\\\\ \\scriptsize no sequencer row}')
		else:
			h0 = ('{\\textbf{hart 0}: the management hart\\\\[2pt] the same hart tile as the '
				'others,\\\\ wired always-on\\\\[3pt] \\scriptsize its \\texttt{pd\\_*} controls '
				'are tied\\\\ \\scriptsize inactive and \\texttt{pwr\\_ctrl}\\\\ '
				'\\scriptsize gives it no row}')
		s += '\\node[aob, minimum width=' + P(h0W) + 'cm, minimum height=' + P(yBoxT - yBoxB)
		s += 'cm] at (' + P((xLab0 + xLab1) / 2.0) + ', ' + P((yBoxT + yBoxB) / 2.0) + ') ' + h0 + ';\n'

		pwX1 = W - margin
		pwX0 = pwX1 - pwrW
		fbX0, fbX1 = xCol0, pwX0 - 0.55
		s += '\\node[aob, minimum width=' + P(fbX1 - fbX0) + 'cm, minimum height=' + P(yBoxT - yBoxB)
		s += 'cm, text width=' + P(fbX1 - fbX0 - 0.50) + 'cm] at (' + P((fbX0 + fbX1) / 2.0) + ', '
		s += P((yBoxT + yBoxB) / 2.0) + ') {\\textbf{the shared fabric}\\\\[2pt] '
		s += '\\texttt{mp\\_arbiter}, the boot ROM every hart resets into, the peripheral window, '
		s += '\\peripheral{CLINT}, the mutexes, the interrupt router, the shared RAM banks '
		s += 'and the pad ring\\\\[3pt] \\scriptsize all on \\texttt{VDD}: gating a tile '
		s += 'costs the rest of the chip nothing};\n'
		s += '\\node[unit, minimum width=' + P(pwX1 - pwX0) + 'cm, minimum height=' + P(yBoxT - yBoxB)
		s += 'cm, text width=' + P(pwX1 - pwX0 - 0.50) + 'cm] (pwr) at (' + P((pwX0 + pwX1) / 2.0) + ', '
		s += P((yBoxT + yBoxB) / 2.0) + ') {\\textbf{\\texttt{pwr\\_ctrl}} at \\texttt{0x4B00}\\\\[2pt] '
		s += '\\register{PWRCR} gate bits\\\\ \\register{PWRSR} state nibbles\\\\[3pt] '
		s += '\\scriptsize one sequencing FSM per tile, on the always-on \\register{mclk}};\n'

		# ---- the PWRCR bit strip (enumerated above, asserted above)
		xc = xStrip0
		for role, b, w in strip:
			cx = xc + w / 2.0
			if role == 'reserved':
				body, fill, tick = '{\\textbf{31:' + str(N) + '}}', 'fill=black!5', 'resv'
			elif role == 'ro':
				body, fill, tick = '{\\textbf{0}}', 'fill=black!30', 'hart 0'
			else:
				body, fill, tick = '{\\textbf{' + str(b) + '}}', 'fill=black!12', 'tile ' + str(b)
			s += '\\node[cell, ' + fill + ', minimum width=' + P(w) + 'cm] at ('
			s += P(cx) + ', ' + P(yStrip) + ') ' + body + ';\n'
			s += '\\node[font=\\sffamily\\tiny, rotate=90, anchor=east] at (' + P(cx) + ', '
			s += P(yStrip - 0.36) + ') {' + tick + '};\n'
			xc += w
		s += '\\node[lab, anchor=west, text width=' + P(noteW) + 'cm] at ('
		s += P(xStrip0 + stripW + 0.30) + ', ' + P(yStrip) + ') '
		s += '{\\register{PWRCR}: bits 1--' + str(N - 1) + ' (mask \\texttt{'
		s += fmthex(drawnMask, minDigits=2) + '}) request a gate; bit 0 is read-only 0, because '
		s += 'hart 0 has no domain to switch.};\n'

		# ---- the left label column: what each layer IS, at that layer's height
		def leftLabel(yTopL, yBotL, text):
			return ('\\node[lab, anchor=west, text width=' + P(xLab1 - xLab0) + 'cm] at ('
				+ P(xLab0) + ', ' + P((yTopL + yBotL) / 2.0) + ') {' + text + '};\n')

		s += leftLabel(yClT, yClB, '\\register{pd\\_iso\\_en}$(h)$ \\textbf{clamps.} AND gates on '
			'the \\emph{always-on} side: every outbound signal of tile $h$ reads 0.')
		s += leftLabel(yHdT, yHdB, '\\register{pd\\_sleep}$(h)$ \\textbf{opens the switches.} '
			'A \\texttt{HEADBUF16} chain carries \\texttt{VDD} to the tile\'s \\texttt{VDD\\_SW}.')
		s += leftLabel(yCoT, yCoB, '\\register{pd\\_rstn}$(h)$ \\textbf{holds it in reset.} '
			'\\register{tile\\_rstn}$(h)$ = \\register{resetn} AND \\register{pd\\_rstn}$(h)$ AND '
			'the field-power boot gate, asserted \\emph{before} the rail goes, released '
			'\\emph{after} it is back.')
		tcmText = ('\\register{tcm\\_pgen} \\textbf{gates the macro.} The TCM runs off the same '
			'\\register{pd\\_sleep}$(h)$, so it dies with the rail: a wake is a cold boot.')
		if apertures:
			tcmText += (' Its aperture then reads \\emph{zeros}, so check \\register{PWRSR} first.')
		s += leftLabel(yTcT, yTcB, tcmText)

		# ---- the sequencer key, in the dead space under the hart-0 box
		s += '\\node[key, anchor=north west, text width=' + P(xLab1 - xLab0 - 0.35) + 'cm] at ('
		s += P(xLab0) + ', ' + P(yBoxB - 0.35) + ') {\\textbf{the sequencer, both ways}\\\\[2pt] '
		s += 'gate: clamp $\\rightarrow$ reset $\\rightarrow$ switches open\\\\[1pt] '
		s += 'wake: switches close $\\rightarrow$ rail settles $\\rightarrow$ unclamp $\\rightarrow$ '
		s += 'reset released\\\\[2pt] '
		s += '\\register{PWRSR} $h$: 0 ON, 1 ISO, 2 RSTOFF, 3 OFF, 4 RAIL, 5 UNISO};\n'

		# ---- the always-on control riser, and its four reaches
		s += '\\draw[thick] (pwr.south) -- (' + P((pwX0 + pwX1) / 2.0) + ', ' + P(yRis)
		s += ') -- (' + P(xRis) + ', ' + P(yRis) + ') -- (' + P(xRis) + ', '
		s += P((yTcT + yTcB) / 2.0) + ');\n'
		for yA, yB in ((yClT, yClB), (yHdT, yHdB), (yCoT, yCoB), (yTcT, yTcB)):
			y = (yA + yB) / 2.0
			s += '\\draw[ctrl] (' + P(xRis) + ', ' + P(y) + ') -- (' + P(xCol0 - 0.06) + ', ' + P(y) + ');\n'

		# ---- the columns: one per channel tile, four layers deep
		for t, cx, w in cols:
			if t is None:
				s += '\\node[font=\\sffamily\\scriptsize, align=center] at (' + P(cx) + ', '
				s += P(yHead) + ') {' + str(elided) + '\\\\ more};\n'
				for y in ((yClT + yClB) / 2.0, (yHdT + yHdB) / 2.0,
						(yCoT + yCoB) / 2.0, (yTcT + yTcB) / 2.0):
					s += '\\node[font=\\sffamily\\Large] at (' + P(cx) + ', ' + P(y) + ') {$\\cdots$};\n'
				continue
			ts = str(t)
			s += '\\node[font=\\sffamily\\scriptsize, align=center] at (' + P(cx) + ', ' + P(yHead)
			s += ') {\\textbf{tile ' + ts + '}\\\\ {\\tiny \\register{PWRCR} bit ' + ts
			s += ' $\\cdot$ \\register{PWRSR} nibble ' + ts + '}};\n'
			s += '\\node[clamp, minimum width=' + P(w) + 'cm, minimum height=' + P(yClT - yClB)
			s += 'cm, text width=' + P(w - 0.35) + 'cm] at (' + P(cx) + ', ' + P((yClT + yClB) / 2.0)
			s += ') {clamps on tile ' + ts + '\'s outputs\\\\ \\texttt{AND} $\\rightarrow$ 0};\n'
			s += '\\node[head, minimum width=' + P(w) + 'cm, minimum height=' + P(yHdT - yHdB)
			s += 'cm, text width=' + P(w - 0.35) + 'cm] at (' + P(cx) + ', ' + P((yHdT + yHdB) / 2.0)
			s += ') {\\texttt{HEADBUF16} bank\\\\ \\texttt{VDD} $\\rightarrow$ \\texttt{VDD\\_SW}};\n'
			s += '\\node[core, minimum width=' + P(w) + 'cm, minimum height=' + P(yCoT - yCoB)
			s += 'cm, text width=' + P(w - 0.35) + 'cm] at (' + P(cx) + ', ' + P((yCoT + yCoB) / 2.0)
			s += ') {\\textbf{\\normalsize tile ' + ts + '}\\\\[3pt] core, CSRs, register file,\\\\ '
			s += 'boundary registers, clock tree};\n'
			s += '\\node[tcm, minimum width=' + P(w) + 'cm, minimum height=' + P(yTcT - yTcB)
			s += 'cm, text width=' + P(w - 0.35) + 'cm] at (' + P(cx) + ', ' + P((yTcT + yTcB) / 2.0)
			s += ') {private TCM, ' + str(tcmKiB) + '\\,KiB\\\\ \\emph{no retention}};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('PowerDomainDiagram.tex', s)
		return


	def GenerateTimerCaptureDiagram(self):
		'''include/TimerCaptureDiagram.tex — input capture (TIMER chapter had no
		   figure for it). Bit-field names are the GENERATED ones (CAP0EN/CAP0FE/
		   CAP0IF) — the chapter prose used to call them TCAP*, which matched
		   nothing in the register tables.'''
		rows = [
			('16{0.5C}',        'timer clock'),
			('R 8{Q}',          '\\register{TIMxVAL}'),
			('3L 5H',           '\\pin{TxCAP0}'),
			('3U 5D{4}',        '\\register{TIMxCAP0}'),
			('3L 4H L',         '\\bitfield{CAP0IF}'),
		]
		ann = ''
		ann += '\\draw[gray!65] (3,\\YTOP) -- (3,{\\YTOP+0.35});\n'
		ann += '\\node[ann, above] at (3,{\\YTOP+0.33}) {capture edge (\\bitfield{CAP0FE} $=0$: rising)};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-0.35})\n'
		ann += '\t{The edge latches \\register{TIMxVAL} into \\register{TIMxCAP0} and sets \\bitfield{CAP0IF}.\\\\[-2pt]\n'
		ann += '\t Clear the flag by writing 1 to it in \\register{TIMxSR} before the next capture.};\n'
		s = '% Generated timer input-capture diagram\n'
		s += self._cycleFigure('1.20cm', rows, 7, ann)
		self._writeInclude('TimerCaptureDiagram.tex', s)
		return

	def _writeInclude(self, name, contents):
		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		with open(self.IncludeDirectory + '/' + name, 'w') as f:
			f.write(contents)
		return

	# -----------------------------------------------------------------
	# D-series debug figures (2026-08). All eight are emitted unconditionally:
	# the chapter decides what renders, by placing the \input for the gated
	# ones inside its own \ifdebugenable. Emitting them always keeps this file
	# free of a second copy of the gating rule, and an unused include costs
	# nothing. The two ALWAYS-RENDERED figures (debug stack, TAP graph, JTAG
	# scan) are architecture-level and appear in every build.
	#
	# SOURCES — do not edit these from memory of the RTL:
	#   hdl/common/jtag_dtm.vhd       (TAP table, IR/DR, the crossing, idle)
	#   hdl/common/debug_module.vhd   (DMI map, the entry page, THE PLANT)
	#   ~/vesta_docs/d_series/d3_spec.md, d3_cdc_spec.md, d4_spec.md
	# -----------------------------------------------------------------

	def GenerateDebugStackDiagram(self):
		'''include/DebugStackDiagram.tex — the whole debug path, probe to hart.
		   CONFIGURATION-DRIVEN (numHarts). Composed as three vertical bands:
		   the TCK side (the probe and the transport it clocks), the wall, and
		   the chip on mclk. The wall is crossed by exactly TWO signals, which
		   is what hdl/common/jtag_dtm.vhd:45-63 describes: one source toggle
		   each way, the payload held still while the toggle is in flight,
		   three destination flops. The OR-merge junction is mcu_vhd.py's
		   valid-gated select, so the raw dmi_* ports still reach the DM with
		   the DTM present. dm0 then reaches the chip THREE ways, each drawn
		   as its own arm and labelled with a verb: it halts and resumes the
		   harts over direct wires, it reads and writes memory as one more
		   master on mp_arbiter, and it plants its own trampoline into the
		   debug program page (D4, debug_module.vhd, THE PLANT).'''
		N = self.Gen.NumHarts
		# CPR8: on an orchestrator configuration hart 0 is NOT one of the
		# interchangeable tiles -- it is the always-on management hart, and the
		# debugger's view of the chip is the first place that asymmetry shows
		# (it is the hart that is still there to be attached to when every
		# other one is gated off). Same condition the system block diagram
		# splits on, so the two figures can never disagree about which chip
		# they are drawing. MINIMAL by intent: this figure's subject is the
		# debug stack, so hart 0 gets a wider box, a distinguishing fill and a
		# name -- and nothing else here changes. Without an orchestrator every
		# byte below is what it was.
		geo = getattr(self.Gen, 'McuMpGeometry', None) or {}
		orch = bool(geo.get('orchestrator')) and bool(self._TcmApertureWindows())
		# Draw every tile up to five; only elide beyond that (Argus is 18). At
		# N=4 all four are drawn -- an elided four-hart chip would be a picture
		# of a chip that does not exist.
		if N <= 5:
			shown = list(range(N))
		else:
			shown = [0, 1, 2, None, N - 1]

		def P(v):
			return '%.2f' % v

		# ---- geometry, in cm. Everything below is derived from these anchors,
		# so a different hart count only stretches the fabric band.
		aX0, aX1 = 0.00, 4.90          # band A: the TCK side
		wX0, wX1 = 4.90, 5.80          # the clock-domain wall
		yBot, yTop = -1.60, 10.05      # band extent
		yBan = 9.25                    # banner strip
		yReq, yRsp = 6.10, 4.25        # the two crossings
		gap = 0.36                     # half-height of the gaps they pass through
		yDm = 6.10                     # the junction/dm0 row

		aCx = (aX0 + aX1) / 2.0
		dtmX1 = aCx + 2.05             # dtm0's east edge
		junX0, junX1 = 10.20, 12.50
		dmX0, dmX1 = 13.20, 16.60
		dmCx = (dmX0 + dmX1) / 2.0
		yDmBot = yDm - 0.95

		# fabric rows
		yArb, arbH = 2.75, 0.80
		yTile, tileH = 0.90, 1.20
		tileW, tileGap = 1.75, 0.28
		fabX0 = 6.60                   # first tile's west edge
		trunkX = 6.05                  # the halt/resume trunk's riser
		yTrunk = -0.55                 # the halt/resume trunk, below the tiles

		orchW = tileW + 0.55        # the orchestrator's box carries one more line
		x = fabX0
		xs = []
		for t in shown:
			w = 0.90 if t is None else (orchW if (orch and t == 0) else tileW)
			xs.append((t, x + w / 2.0, w))
			x += w + tileGap
		tilesX1 = x - tileGap

		ramW = 4.20
		ramX0 = tilesX1 + 0.75
		ramX1 = ramX0 + ramW
		ramCx = (ramX0 + ramX1) / 2.0
		arbX0, arbX1 = 6.30, ramX1 + 0.60
		plantX = arbX1 + 0.70          # the plant arm's riser, clear of the bus
		bX1 = plantX + 0.40            # band B's east edge

		s = '% Generated debug stack block diagram (numHarts=' + str(N) + ')\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={draw, thick, align=center, fill=white, font=\\sffamily\\small},\n'
		s += '\ttile/.style={blk, fill=black!6},\n'
		if orch:
			# emitted only where it is used, so a configuration without an
			# orchestrator keeps a byte-identical include
			s += '\torch/.style={blk, fill=black!14},\n'
		s += '\tunit/.style={blk, fill=black!12},\n'
		s += '\tpage/.style={blk, fill=black!25, font=\\sffamily\\scriptsize},\n'
		s += '\tbus/.style={<->, >=Stealth, thick},\n'
		s += '\tsig/.style={->, >=Stealth, thick},\n'
		s += '\tcross/.style={->, >=Stealth, line width=1.6pt},\n'
		s += '\tban/.style={font=\\sffamily\\small\\bfseries, black!60},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, align=center},\n'
		s += '\tvrb/.style={font=\\sffamily\\scriptsize, align=left}]\n'

		# ---- the three bands, drawn first so everything else sits on top
		s += '\\fill[black!8] (' + P(aX0) + ', ' + P(yBot) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!4] (' + P(wX1) + ', ' + P(yBot) + ') rectangle (' + P(bX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!4] (' + P(wX0) + ', ' + P(yBot) + ') rectangle (' + P(wX1) + ', ' + P(yTop) + ');\n'
		# The wall reads as a real barrier: hatched masonry, in THREE segments
		# with a gap at each crossing height. The gaps are the point of the
		# figure -- the only two signals in the design that cross this line
		# are the two that pass through them.
		for (y0, y1) in [(yBot, yRsp - gap), (yRsp + gap, yReq - gap), (yReq + gap, yTop)]:
			s += '\\fill[black!22] (' + P(wX0) + ', ' + P(y0) + ') rectangle (' + P(wX1) + ', ' + P(y1) + ');\n'
			s += '\\begin{scope}\n'
			s += '\\clip (' + P(wX0) + ', ' + P(y0) + ') rectangle (' + P(wX1) + ', ' + P(y1) + ');\n'
			s += '\\foreach \\i in {0,...,' + str(int((y1 - y0) / 0.42) + 3) + '} {\n'
			s += '\t\\draw[black!45, line width=0.5pt] (' + P(wX0) + ', ' + P(y0 - 0.90) + '+\\i*0.42) -- (' + P(wX1) + ', ' + P(y0) + '+\\i*0.42);\n'
			s += '}\n'
			s += '\\end{scope}\n'
			s += '\\draw[black!45, line width=0.9pt] (' + P(wX0) + ', ' + P(y0) + ') -- (' + P(wX0) + ', ' + P(y1) + ');\n'
			s += '\\draw[black!45, line width=0.9pt] (' + P(wX1) + ', ' + P(y0) + ') -- (' + P(wX1) + ', ' + P(y1) + ');\n'
		# banners
		s += '\\fill[black!18] (' + P(aX0) + ', ' + P(yBan) + ') rectangle (' + P(aX1) + ', ' + P(yTop) + ');\n'
		s += '\\fill[black!12] (' + P(wX1) + ', ' + P(yBan) + ') rectangle (' + P(bX1) + ', ' + P(yTop) + ');\n'
		s += '\\node[ban] at (' + P(aCx) + ', ' + P((yBan + yTop) / 2.0) + ') {the \\register{TCK} side};\n'
		s += '\\node[ban] at (' + P((wX1 + bX1) / 2.0) + ', ' + P((yBan + yTop) / 2.0) + ') {the chip: everything here runs on \\register{mclk}};\n'
		s += '\\node[ban, rotate=90] at (' + P((wX0 + wX1) / 2.0) + ', 1.30) {clock-domain crossing};\n'

		# ---- band A: the probe, its five pins, and the transport
		s += '\\node[blk, dashed, minimum width=3.5cm, minimum height=1.05cm] (probe) at (' + P(aCx) + ', 8.20) {external\\\\ debug probe};\n'
		s += '\\node[unit, minimum width=4.1cm, minimum height=3.10cm] (dtm) at (' + P(aCx) + ', 4.55) {\\textbf{dtm0}\\\\ TAP $+$ transport\\\\[2pt] \\scriptsize the sixteen-state port,\\\\ \\scriptsize the instruction register,\\\\ \\scriptsize and the \\register{dmi} shift register};\n'
		s += '\\draw[bus] (probe.south) -- (dtm.north);\n'
		s += '\\node[lab, fill=black!8, inner sep=2pt] at (' + P(aCx) + ', 7.05) {\\textbf{5 pins}\\\\ \\pin{TCK} \\pin{TMS} \\pin{TDI}\\\\ \\pin{TDO} \\pin{TRSTn}};\n'
		s += '\\node[lab] at (' + P(aCx) + ', 1.30) {\\textit{on the chip, but clocked by}\\\\ \\textit{the probe: nothing in this}\\\\ \\textit{band moves unless \\pin{TCK} does}};\n'

		# ---- the two crossings: one toggle each way, payload held still
		s += '\\draw[cross] (' + P(dtmX1) + ', ' + P(yReq) + ') -- (' + P(junX0) + ', ' + P(yReq) + ');\n'
		s += '\\draw[cross, rounded corners] (' + P(dmCx - 1.00) + ', ' + P(yDmBot) + ') -- (' + P(dmCx - 1.00) + ', ' + P(yRsp) + ') -- (' + P(dtmX1) + ', ' + P(yRsp) + ');\n'
		s += '\\node[lab, fill=black!4, inner sep=2.5pt] at (7.95, ' + P(yReq) + ') {\\register{req\\_tgl} $+$ a 41-bit request};\n'
		s += '\\node[lab, fill=black!4, inner sep=2.5pt] at (7.95, ' + P(yRsp) + ') {\\register{rsp\\_tgl} $+$ a 34-bit response};\n'
		s += '\\node[lab] at (7.95, ' + P((yReq + yRsp) / 2.0) + ') {\\textit{two signals, and no others:}\\\\ \\textit{each payload is held still}\\\\ \\textit{while its toggle crosses}};\n'

		# ---- the merge, the raw ports, and the one Debug Module
		s += '\\node[unit, minimum width=' + P(junX1 - junX0) + 'cm, minimum height=1.35cm, font=\\sffamily\\scriptsize] (jun) at (' + P((junX0 + junX1) / 2.0) + ', ' + P(yDm) + ') {\\textbf{either master}\\\\ drives the same port};\n'
		s += '\\node[blk, dashed, minimum width=3.2cm, minimum height=1.0cm, font=\\sffamily\\scriptsize] (ext) at (' + P((junX0 + junX1) / 2.0) + ', 8.20) {raw \\register{dmi\\_*} ports\\\\ (what a bench drives)};\n'
		s += '\\draw[sig] (ext.south) -- (jun.north);\n'
		s += '\\node[unit, minimum width=' + P(dmX1 - dmX0) + 'cm, minimum height=1.90cm] (dm) at (' + P(dmCx) + ', ' + P(yDm) + ') {\\textbf{dm0}\\\\ the Debug Module\\\\ \\scriptsize one, for the whole chip};\n'
		s += '\\draw[cross] (jun.east) -- (dm.west);\n'

		# ---- the fabric: one arbiter, N tiles, the shared RAM, the page
		s += '\\node[blk, fill=black!15, minimum width=' + P(arbX1 - arbX0) + 'cm, minimum height=' + P(arbH) + 'cm] (arb) at (' + P((arbX0 + arbX1) / 2.0) + ', ' + P(yArb) + ') {\\textbf{mp\\_arbiter}: ' + str(N) + ' harts and \\textbf{dm0}, all masters on one shared bus};\n'
		for t, tcx, w in xs:
			if t is None:
				s += '\\node[font=\\sffamily\\Large] at (' + P(tcx) + ', ' + P(yTile) + ') {$\\cdots$};\n'
				continue
			body = '{\\textbf{hart ' + str(t) + '}\\\\ core $+$ TCM}'
			style = 'tile'
			if orch and t == 0:
				body = '{\\textbf{hart 0}\\\\ the orchestrator\\\\ core $+$ TCM}'
				style = 'orch'
			s += '\\node[' + style + ', minimum width=' + P(w) + 'cm, minimum height=' + P(tileH) + 'cm, font=\\sffamily\\scriptsize] (t' + str(t) + ') at (' + P(tcx) + ', ' + P(yTile) + ') ' + body + ';\n'
			s += '\\draw[bus] (' + P(tcx) + ', ' + P(yTile + tileH / 2.0) + ') -- (' + P(tcx) + ', ' + P(yArb - arbH / 2.0) + ');\n'
			s += '\\draw[bus] (' + P(tcx) + ', ' + P(yTrunk) + ') -- (' + P(tcx) + ', ' + P(yTile - tileH / 2.0) + ');\n'
		s += '\\node[blk, fill=black!8, minimum width=' + P(ramW) + 'cm, minimum height=1.75cm] (ram) at (' + P(ramCx) + ', 1.03) {};\n'
		s += '\\node[font=\\sffamily\\scriptsize] at (' + P(ramCx) + ', 1.62) {shared RAM \\texttt{0x10000}};\n'
		s += '\\node[page, minimum width=' + P(ramW - 0.40) + 'cm, minimum height=0.62cm] (pg) at (' + P(ramCx) + ', 0.85) {\\textbf{debug program page}\\\\ \\texttt{0x10680}--\\texttt{0x1087F}};\n'
		s += '\\draw[bus] (' + P(ramCx) + ', 1.90) -- (' + P(ramCx) + ', ' + P(yArb - arbH / 2.0) + ');\n'

		# ---- dm0's three reaches, each an arm of its own, each a verb
		# 1. run control: direct wires, down the outside and along under the tiles
		s += '\\draw[thick, rounded corners] (' + P(dmCx + 0.10) + ', ' + P(yDmBot) + ') -- (' + P(dmCx + 0.10) + ', 3.45) -- (' + P(trunkX) + ', 3.45) -- (' + P(trunkX) + ', ' + P(yTrunk) + ') -- (' + P(xs[-1][1]) + ', ' + P(yTrunk) + ');\n'
		s += '\\node[lab, anchor=west] at (' + P(trunkX) + ', ' + P(yTrunk - 0.62) + ') {\\textbf{halts and resumes} every hart: \\register{haltreq} / \\register{resumereq} out, \\register{halted} / \\register{unavail} back, on direct wires};\n'
		# 2. memory: one more master on the arbiter
		s += '\\draw[bus] (' + P(dmCx + 1.10) + ', ' + P(yDmBot) + ') -- (' + P(dmCx + 1.10) + ', ' + P(yArb + arbH / 2.0) + ');\n'
		s += '\\node[vrb, anchor=west] at (' + P(dmCx + 1.25) + ', 4.15) {\\textbf{reads and writes memory}\\\\ as one more master on the bus};\n'
		# 3. the plant (D4)
		s += '\\draw[sig, rounded corners] (dm.east) -- (' + P(plantX) + ', ' + P(yDm) + ') -- (' + P(plantX) + ', 0.85) -- (' + P(ramX1 - 0.20) + ', 0.85);\n'
		s += '\\node[vrb, anchor=east] at (' + P(plantX - 0.15) + ', 5.20) {\\textbf{plants} its own 40-word\\\\ trampoline into that page};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugStackDiagram.tex', s)
		return

	# TAP state names and the transition table, TRANSCRIBED from
	# hdl/common/jtag_dtm.vhd:185-200 (the ST_* encoding) and :204-208 (the
	# TAP_NEXT aggregate, which that file in turn transcribed from Spike
	# jtag_dtm.cc:60-77). next[state][tms]. If jtag_dtm.vhd changes, this
	# changes with it -- the figure is a picture of THIS table and nothing else.
	_TAP_STATES = ['Test-Logic-Reset', 'Run-Test/Idle',
		'Select-DR', 'Capture-DR', 'Shift-DR', 'Exit1-DR', 'Pause-DR',
		'Exit2-DR', 'Update-DR',
		'Select-IR', 'Capture-IR', 'Shift-IR', 'Exit1-IR', 'Pause-IR',
		'Exit2-IR', 'Update-IR']
	_TAP_NEXT = [(1, 0), (1, 2), (3, 9), (4, 5),
		(4, 5), (6, 8), (6, 7), (4, 8),
		(1, 2), (10, 0), (11, 12), (11, 12),
		(13, 15), (13, 14), (11, 15), (1, 2)]

	def GenerateTapStateDiagram(self):
		'''include/TapStateDiagram.tex — the 16-state IEEE 1149.1 TAP graph,
		   every edge drawn from _TAP_NEXT (jtag_dtm.vhd:204-208). Solid edges
		   are TMS=0, dashed are TMS=1; the five-ones recovery is emphasised
		   because it is the only thing a debugger needs when it has lost the
		   state.

		   LAYOUT is the canonical datasheet one, and it is chosen to keep the
		   edges apart rather than to look tidy on paper: a TOP ROW of
		   Test-Logic-Reset, Run-Test/Idle, Select-DR, Select-IR (so the TMS=1
		   chain runs left to right along it), with the two seven-state lobes
		   hanging below their Select. Every remaining edge then has a channel
		   of its own -- forward skips down the INNER flank of each lobe, the
		   Exit2 back edge and the self-loops on the OUTER flank, the two
		   Update->Select-DR returns over the top and up the middle, the two
		   Update->Run-Test/Idle returns along the bottom. Edge labels are
		   placed at computed points rather than by `pos=', so no label ever
		   lands on another edge.'''
		# THE COORDINATES BELOW ARE PRINTED CENTIMETRES, AND THAT IS THE POINT
		# (2026-08-15, USER, twice: smaller type and smaller boxes, with the
		# states FURTHER APART, so that every arrow between them can be traced
		# individually). The chapter used to wrap this figure in
		# \resizebox{\linewidth}, which made every number here a RATIO: the
		# drawing was authored at ~21.5 units and squeezed to the 16.5 cm text
		# block, so the boxes, the type and the gaps between the boxes all
		# shrank together and a wider layout bought no extra air, it only
		# scaled itself away. The \resizebox is gone; these numbers land on the
		# page as written, and the two halves of the USER's constraint are set
		# independently, which is the pair of things that cannot be had at once
		# from a single scale factor:
		#
		#            box          state font   vert. air   inner channel   total
		#   resized  2.07x0.55    ~7.7 pt      0.48 cm     0.31 cm         16.5x10.1
		#   round 1  1.75x0.44    6.5 pt       0.55 cm     0.58 cm         14.7x9.0
		#   round 2  1.56x0.35    5.0 pt       0.71 cm     0.60 cm         14.6x8.9
		#
		# So round 2 takes another 11 % off the box, drops the type to \tiny,
		# and spends every millimetre it frees on AIR: +29 % between rows,
		# +22 % between the two lobe columns, +22 % between Test-Logic-Reset
		# and Run-Test/Idle, inside a figure that is smaller in both dimensions
		# than the one it replaces.
		# FLOORS, so a future edit does not squeeze this back: the box width is
		# set by `Test-Logic-Reset` at the state font (~1.4 cm of type), and
		# the outer flank must clear the self-loop bulge, which reaches about
		# 0.6 cm past the node.
		HW, HH = 0.78, 0.175           # half width / half height of a state box
		TOP = 0.00                     # the top row
		xTLR, xRTI = 0.00, 2.60
		cx = {'dr': 5.45, 'ir': 10.45}
		rows = [-0.95 - 1.06 * k for k in range(6)]         # capture .. update
		yWrapT, yWrapS = 1.02, 1.45    # the two returns over the top
		yRetD, yRetI = -6.87, -7.45    # the two returns along the bottom
		xRiseD, xRiseI = 7.95, 13.05   # the two Update -> Select-DR risers

		pos = {0: (xTLR, TOP), 1: (xRTI, TOP), 2: (cx['dr'], TOP), 9: (cx['ir'], TOP)}
		for k, st in enumerate([3, 4, 5, 6, 7, 8]):
			pos[st] = (cx['dr'], rows[k])
		for k, st in enumerate([10, 11, 12, 13, 14, 15]):
			pos[st] = (cx['ir'], rows[k])

		def P(v):
			return '%.2f' % v

		s = '% Generated TAP state graph (edges transcribed from jtag_dtm.vhd TAP_NEXT)\n'
		s += '\\begin{tikzpicture}[\n'
		# Type sizes are absolute here for the same reason the coordinates are:
		# nothing scales this figure after the fact, so what is written is what
		# prints. The state font is the one that had to come down for the boxes
		# to come down with it; the edge labels are single digits and go a step
		# smaller still so a `0' sitting on a channel never reads as loud as a
		# state name.
		s += '\tst/.style={draw, semithick, rounded corners=1.5pt, align=center, font=\\sffamily\\fontsize{5.0}{6.0}\\selectfont, inner sep=0.8pt, minimum width=' + P(2 * HW) + 'cm, minimum height=' + P(2 * HH) + 'cm, fill=black!4},\n'
		s += '\ttlr/.style={st, fill=black!18, thick},\n'
		s += '\ttms0/.style={->, >=Stealth, thin},\n'
		s += '\ttms1/.style={->, >=Stealth, thin, densely dashed},\n'
		s += '\tel/.style={font=\\sffamily\\fontsize{5.0}{6.0}\\selectfont, inner sep=0.8pt, fill=white},\n'
		s += '\tkey/.style={font=\\sffamily\\fontsize{6.0}{7.0}\\selectfont, align=left, text width=2.60cm},\n'
		s += '\tkeylab/.style={font=\\sffamily\\fontsize{6.0}{7.0}\\selectfont, anchor=west}]\n'
		for i, name in enumerate(self._TAP_STATES):
			style = 'tlr' if i == 0 else 'st'
			s += '\\node[' + style + '] (s' + str(i) + ') at (' + P(pos[i][0]) + ', ' + P(pos[i][1]) + ') {' + name + '};\n'

		# Every edge below is one row of TAP_NEXT. `emit' draws the path and
		# then drops the sampled-TMS label at an explicitly chosen point; the
		# TABLE decides what is drawn, the geometry only decides where.
		edges = []

		def emit(src, tms, path, lx, ly):
			dst = self._TAP_NEXT[src][tms]
			edges.append((src, dst))
			sty = 'tms1' if tms else 'tms0'
			s_ = '\\draw[' + sty + ', rounded corners] ' + path + ';\n'
			s_ += '\\node[el] at (' + P(lx) + ', ' + P(ly) + ') {' + str(tms) + '};\n'
			return s_

		def loop(src, tms, sgn):
			'''A self-loop on the OUTWARD-facing side of the node.

			   THE ANGULAR SPREAD IS 32 DEGREES, NOT 40 (round 2), and the whole
			   loop is tipped 12 degrees UP. The loop's vertical reach is (its
			   length) x sin(half-spread), and the box is now 0.35 cm tall: at
			   the old spread the Shift loop bulged BELOW the box, straight
			   across the horizontal run of the Exit2 -> Shift retry arrow, which
			   enters that same box's outward bottom corner. Narrowing and
			   tipping the loop leaves that corner to the retry alone.'''
			dst = self._TAP_NEXT[src][tms]
			edges.append((src, dst))
			sty = 'tms1' if tms else 'tms0'
			out, inn = (356, 28) if sgn > 0 else (184, 152)
			x, y = pos[src]
			s_ = '\\draw[' + sty + '] (s' + str(src) + ') to[loop, out=' + str(out) + ', in=' + str(inn) + ', looseness=6] (s' + str(src) + ');\n'
			s_ += '\\node[el] at (' + P(x + sgn * (HW + 0.60)) + ', ' + P(y + 0.10) + ') {' + str(tms) + '};\n'
			return s_

		# ---- the top row ------------------------------------------------
		s += loop(0, 1, -1)                                   # TLR holds on 1
		s += emit(0, 0, '(s0.east) -- (s1.west)', (xTLR + HW + xRTI - HW) / 2.0, TOP)
		s += '\\draw[tms0] (s1) to[loop, out=115, in=65, looseness=6] (s1);\n'
		edges.append((1, self._TAP_NEXT[1][0]))
		# The apex label of Run-Test/Idle's own loop is the ONE label with a
		# through-edge over it (the Select-IR -> Test-Logic-Reset wrap runs the
		# width of the figure at yWrapT), so it is placed low enough to leave
		# 0.22 cm between its top and that line.
		s += '\\node[el] at (' + P(xRTI) + ', ' + P(TOP + 0.68) + ') {0};\n'
		s += emit(1, 1, '(s1.east) -- (s2.west)', (xRTI + HW + cx['dr'] - HW) / 2.0, TOP)
		s += emit(2, 0, '(s2.south) -- (s3.north)', cx['dr'] - 0.20, (TOP - HH + rows[0] + HH) / 2.0)
		s += emit(2, 1, '(s2.east) -- (s9.west)', (cx['dr'] + HW + cx['ir'] - HW) / 2.0 + 1.00, TOP)
		s += emit(9, 0, '(s9.south) -- (s10.north)', cx['ir'] + 0.20, (TOP - HH + rows[0] + HH) / 2.0)
		# Select-IR on a 1 is the last hop of the five-ones recovery.
		s += emit(9, 1, '(s9.north) -- (' + P(cx['ir']) + ', ' + P(yWrapT) + ') -- (' + P(xTLR) + ', ' + P(yWrapT) + ') -- (s0.north)',
			(cx['ir'] + xTLR) / 2.0 + 2.60, yWrapT)

		# ---- the two lobes, identical in shape --------------------------
		# sgn = which side is the OUTWARD one for this lobe.
		for lobe, sgn, base in (('dr', -1.0, 3), ('ir', +1.0, 10)):
			c = cx[lobe]
			cap, shf, ex1, pau, ex2, upd = [base + k for k in range(6)]
			# Every flank channel is quoted as clearance FROM THE BOX EDGE, so
			# it holds its air when the box changes size.
			#
			# THE TWO FORWARD SKIPS GET A CHANNEL EACH (round 2). They used to
			# share one: Capture -> Exit1 ran down x=xIn from row 0 to row 2 and
			# Exit1 -> Update ran down THE SAME x from row 2 to row 5, so the two
			# were collinear and read on the page as a single long edge from
			# Capture straight past Exit1 to Update, an edge this machine does
			# not have. Splitting them (the shorter skip inboard at 0.60 cm, the
			# longer one outboard at 1.15 cm) makes the step at Exit1 visible and
			# leaves both individually traceable, which is the whole point of the
			# spacing pass.
			xOut = c + sgn * (HW + 1.20)      # Exit2 -> Shift, on the outside
			xInA = c - sgn * (HW + 0.60)      # Capture -> Exit1, inside, near
			xInB = c - sgn * (HW + 1.15)      # Exit1 -> Update, inside, far
			aOut = 'west' if sgn < 0 else 'east'
			aIn = 'east' if sgn < 0 else 'west'

			# Straight down the spine. THE SPINE LABEL SITS BESIDE ITS ARROW, NOT
			# ON IT (0.20 cm to the outward side): a `1' is a bare vertical stroke,
			# and a white-filled `1' centred on a dashed vertical line reads as one
			# more dash. Three of the five spine edges are TMS=1, so on the page
			# the ladder had three invisible labels. A `0' survives being centred
			# (it punches a round hole), but the two are set the same way so the
			# reader never has to work out which convention is in force.
			lx = c + sgn * 0.20
			s += emit(cap, 0, '(s%d.south) -- (s%d.north)' % (cap, shf), lx, (rows[0] - HH + rows[1] + HH) / 2.0)
			s += emit(shf, 1, '(s%d.south) -- (s%d.north)' % (shf, ex1), lx, (rows[1] - HH + rows[2] + HH) / 2.0)
			s += emit(ex1, 0, '(s%d.south) -- (s%d.north)' % (ex1, pau), lx, (rows[2] - HH + rows[3] + HH) / 2.0)
			s += emit(pau, 1, '(s%d.south) -- (s%d.north)' % (pau, ex2), lx, (rows[3] - HH + rows[4] + HH) / 2.0)
			s += emit(ex2, 1, '(s%d.south) -- (s%d.north)' % (ex2, upd), lx, (rows[4] - HH + rows[5] + HH) / 2.0)
			# the two self-loops, outward
			s += loop(shf, 0, sgn)
			s += loop(pau, 0, sgn)
			# Capture -> Exit1 and Exit1 -> Update: forward skips, inner flank
			s += emit(cap, 1, '(s%d.%s) -- (%s, %s) -- (%s, %s) -- (s%d.north %s)'
				% (cap, aIn, P(xInA), P(rows[0]), P(xInA), P(rows[2] + HH), ex1, aIn), xInA, (rows[0] + rows[2]) / 2.0)
			s += emit(ex1, 1, '(s%d.south %s) -- (%s, %s) -- (%s, %s) -- (s%d.north %s)'
				% (ex1, aIn, P(xInB), P(rows[2] - HH), P(xInB), P(rows[5] + HH), upd, aIn), xInB, (rows[2] + rows[5]) / 2.0)
			# Exit2 -> Shift: the retry path, outer flank, clear of the loops
			s += emit(ex2, 0, '(s%d.%s) -- (%s, %s) -- (%s, %s) -- (s%d.south %s)'
				% (ex2, aOut, P(xOut), P(rows[4]), P(xOut), P(rows[1] - HH), shf, aOut), xOut, (rows[1] + rows[4]) / 2.0)

		# ---- the four returns, two along the bottom and two up top -------
		# Update-DR -> Run-Test/Idle, and Update-DR -> Select-DR up the middle
		s += emit(8, 0, '(s8.south) -- (' + P(cx['dr']) + ', ' + P(yRetD) + ') -- (' + P(xRTI) + ', ' + P(yRetD) + ') -- (s1.south)',
			xRTI, (yRetD + TOP) / 2.0 + 1.20)
		# Update-DR's riser leaves the BOTTOM-outer corner, not the east face. The
		# DR lobe's inner flank and this riser are on the same side of the lobe, so
		# an east-face departure ran horizontally 0.175 cm under the Exit1 -> Update
		# arrow arriving at the north-east corner: two dashed edges in one lane.
		# Dropping it to the south-east corner puts 0.35 cm between them.
		s += emit(8, 1, '(s8.south east) -- (' + P(xRiseD) + ', ' + P(rows[5] - HH) + ') -- (' + P(xRiseD) + ', ' + P(TOP - HH) + ') -- (s2.south east)',
			xRiseD, (rows[5] + TOP) / 2.0)
		# Update-IR -> Run-Test/Idle, and Update-IR -> Select-DR over the top
		s += emit(15, 0, '(s15.south) -- (' + P(cx['ir']) + ', ' + P(yRetI) + ') -- (' + P(xRTI - HW) + ', ' + P(yRetI) + ') -- (s1.south west)',
			xRTI - HW, (yRetI + TOP) / 2.0 - 1.20)
		s += emit(15, 1, '(s15.east) -- (' + P(xRiseI) + ', ' + P(rows[5]) + ') -- (' + P(xRiseI) + ', ' + P(yWrapS) + ') -- (' + P(cx['dr']) + ', ' + P(yWrapS) + ') -- (s2.north)',
			(xRiseI + cx['dr']) / 2.0 + 1.40, yWrapS)

		# The figure IS the table: assert that here, so a change to TAP_NEXT
		# that this routing does not cover fails the build instead of quietly
		# dropping an edge.
		expected = [(i, self._TAP_NEXT[i][t]) for i in range(16) for t in (0, 1)]
		if sorted(edges) != sorted(expected):
			raise Exception('TapStateDiagram: drew %d edges, TAP_NEXT has %d'
				% (len(edges), len(expected)))

		# The key lives in the one large empty region the layout leaves: below
		# Test-Logic-Reset, inside the two bottom returns' risers.
		# The key's own right edge is a real constraint, not a taste: the
		# Update-IR -> Run-Test/Idle return rises at x = xRTI - HW, and the key
		# text block is sized and placed to stay clear of that riser.
		kx = xTLR - HW - 0.72
		s += '\\draw[tms0] (' + P(kx) + ', -1.60) -- (' + P(kx + 0.62) + ', -1.60);\n'
		s += '\\node[keylab] at (' + P(kx + 0.74) + ', -1.60) {\\pin{TMS} sampled \\textbf{0}};\n'
		s += '\\draw[tms1] (' + P(kx) + ', -2.15) -- (' + P(kx + 0.62) + ', -2.15);\n'
		s += '\\node[keylab] at (' + P(kx + 0.74) + ', -2.15) {\\pin{TMS} sampled \\textbf{1}};\n'
		s += '\\node[key, anchor=north west] at (' + P(kx) + ', -2.70) {\\textbf{Five} \\pin{TMS}$=$\\textbf{1} clocks reach Test-Logic-Reset from \\textit{any} state in the graph, the recovery a debugger uses when it has lost track of the machine.};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('TapStateDiagram.tex', s)
		return

	def GenerateJtagScanDiagram(self):
		'''include/JtagScanDiagram.tex — one four-bit DR scan, TAP states from
		   _TAP_NEXT. TDO is drawn HALF A UNIT LATE on purpose: jtag_dtm.vhd
		   samples TMS/TDI on the RISING TCK edge (:342, :406) and changes TDO
		   on the FALLING edge (:500-514), so its transitions belong mid-unit.
		   Shift is LSB-first (:222-224 declare the DR widths; the shifter runs
		   low bit out first). Generic 1149.1 -- always rendered.'''
		rows = [
			('20{0.5C}',                                                   '\\pin{TCK}'),
			('H 5L 2H 2L',                                                 '\\pin{TMS}'),
			('3U D{b0} D{b1} D{b2} D{b3} 3U',                              '\\pin{TDI}'),
			('3.5U D{q0} D{q1} D{q2} D{q3} 2.5U',                          '\\pin{TDO}'),
			('D{RTI} D{Sel} D{Cap} 4D{Shift-DR} D{Ex1} D{Upd} D{RTI}',     '\\textit{TAP state}'),
		]
		ann = ''
		ann += '\\draw[<->, >=Stealth] (3,{\\YBOT-0.45}) -- (7,{\\YBOT-0.45});\n'
		ann += '\\node[ann, below] at (5,{\\YBOT-0.47}) {shift: LSB first, one bit per \\pin{TCK}};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-1.05})\n'
		ann += '\t{\\textbf{Capture} loads the register in parallel from what it shadows; \\textbf{Update} commits\\\\[-2pt]\n'
		ann += '\t what was shifted in. One scan therefore reads the old contents and writes the new\\\\[-2pt]\n'
		ann += '\t ones at the same time. \\pin{TMS} is sampled on the RISING edge; \\pin{TDO} changes on the\\\\[-2pt]\n'
		ann += '\t FALLING edge, which is why its transitions sit half a cycle after the others.};\n'
		s = '% Generated JTAG DR-scan diagram\n'
		s += self._cycleFigure('1.25cm', rows, 9, ann)
		self._writeInclude('JtagScanDiagram.tex', s)
		return

	def GenerateDmiCrossingDiagram(self):
		'''include/DmiCrossingDiagram.tex — one DMI transaction across the
		   TCK<->mclk boundary. CYCLE-ACCURATE against hdl/common/jtag_dtm.vhd:
		   the Update-DR of a dmi scan loads the 41-bit request hold and flips
		   req_tgl (:55-58); the mclk side syncs through 2-FF + an edge flop
		   (:47-49) and presents the held payload; dmi_req_valid is a ONE-SHOT
		   held only until the REGISTERED ready is observed -- exactly two mclk
		   (:71-75) -- because the DM re-accept lockout is a TIMER that reopens
		   9 mclk after a capture (:67-69), so a level-held master would earn a
		   duplicate accept. The response latches rsp_op/rsp_data into a 34-bit
		   hold and flips rsp_tgl (:60-63). The whole budget is :79-90.
		   TIMEBASE IS mclk; the two TCK events are annotated rather than drawn,
		   because the TCK:mclk ratio is a board choice, not a fixed number.'''
		rows = [
			('24{0.5C}',                          '\\register{mclk}'),
			('L 11H',                             '\\register{req\\_tgl} \\ \\scriptsize(\\register{TCK})'),
			('U 11D{addr, data, op}',             'request hold, 41\\,b'),
			('4L 8H',                             '\\register{req\\_sync} \\ \\scriptsize(3 flops)'),
			('4L 2H 6L',                          '\\register{dmi\\_req\\_valid}'),
			('5L H 6L',                           '\\register{dmi\\_req\\_ready}'),
			('6L H 5L',                           '\\register{dmi\\_rsp\\_valid}'),
			# The response hold and rsp_tgl move on the SAME mclk edge -- the DM
			# latches rsp_op/rsp_data and flips the toggle in one clocked block,
			# and payload-written-on-the-toggle's-own-edge IS the idiom (the
			# request side above does the same). Drawing the toggle a cycle late
			# would show a payload in flight ahead of its own toggle.
			('7U 5D{op, data}',                   'response hold, 34\\,b'),
			('7L 5H',                             '\\register{rsp\\_tgl}'),
		]
		ann = ''
		# the one-shot, and why it is one
		ann += '\\draw[<->, >=Stealth] (4,{\\YTOP+0.45}) -- (6,{\\YTOP+0.45});\n'
		ann += '\\node[ann, above] at (5,{\\YTOP+0.47}) {\\register{valid} high exactly \\textbf{2} \\register{mclk}, retired on the \\emph{registered} \\register{ready}};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-0.35})\n'
		ann += '\t{The Debug Module\'s re-accept lockout is a \\textbf{timer}, not a handshake: it reopens\\\\[-2pt]\n'
		ann += '\t 9 \\register{mclk} after a capture. A master that held \\register{valid} until its response came back would\\\\[-2pt]\n'
		ann += '\t still be asserting it then and would earn a \\textbf{second, duplicate accept}: two responses for\\\\[-2pt]\n'
		ann += '\t one request, sliding every later pair by one. The symptom is not a wrong answer; it is\\\\[-2pt]\n'
		ann += '\t the \\emph{previous} answer. Two cycles leaves seven inside the window.};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-2.55})\n'
		ann += '\t{\\textbf{Where \\bitfield{idle} $=7$ comes from.} A debugger sees the result no earlier than\\\\[-2pt]\n'
		ann += '\t 3 \\pin{TCK} (this response synchroniser) $+$ $\\lceil t_{\\mathrm{DM}} / T_{\\pin{TCK}}\\rceil$. Here $t_{\\mathrm{DM}}$ is 8--10 \\register{mclk} for a\\\\[-2pt]\n'
		ann += '\t Debug Module register, and \\emph{tens} for \\register{data0} or a program-buffer word, which are\\\\[-2pt]\n'
		ann += '\t proxied into shared RAM through the arbiter. At \\pin{TCK} $\\leq$ 7.14\\,MHz against a 24\\,MHz\\\\[-2pt]\n'
		ann += '\t \\register{mclk} that is 6 cycles for the worst class; \\textbf{7} adds one of margin and is the largest\\\\[-2pt]\n'
		ann += '\t value the 3-bit field can hold. Faster \\pin{TCK}, or a contended bus, can still report busy.};\n'
		# mark the two TCK-domain events
		ann += '\\node[ann, anchor=south west, align=left] at (0.05,{\\YTOP+1.05}) {\\textbf{Update-DR} (\\register{TCK}): the 41-bit\\\\[-2pt] payload is written and \\emph{held}, and \\register{req\\_tgl} flips};\n'
		ann += '\\draw[gray!65] (1,{\\YTOP+1.02}) -- (1,\\YTOP);\n'
		ann += '\\node[ann, anchor=south east, align=right] at (11.95,{\\YTOP+1.05}) {\\register{rsp\\_tgl} crosses back through\\\\[-2pt] 3 \\pin{TCK} flops, then the shadow updates};\n'
		ann += '\\draw[gray!65] (7,{\\YTOP+1.02}) -- (7,\\YTOP);\n'
		s = '% Generated DMI clock-crossing diagram (mclk timebase)\n'
		s += self._cycleFigure('1.15cm', rows, 11, ann, shade=('4', '6'))
		self._writeInclude('DmiCrossingDiagram.tex', s)
		return

	def GenerateDebugSwimlaneDiagram(self):
		'''include/DebugSwimlaneDiagram.tex — the twelve numbered steps of the
		   worked halt/read/resume, across the four agents that perform them.
		   The numbers are the list items in the chapter, so the figure and the
		   prose are one document.'''
		lanes = [('debugger', 4.8), ('DTM \\ \\scriptsize(\\register{TCK})', 3.2),
			('DM', 1.6), ('hart $h$', 0.0)]
		# (step, lane index, x, label)
		steps = [
			(1, 0, 0.9, 'reset TAP,\\\\ read IDCODE'),
			(2, 0, 2.6, 'read\\\\ DTMCS'),
			(3, 1, 4.1, 'select\\\\ \\register{dmi} DR'),
			(4, 2, 5.6, '\\bitfield{dmactive}\\\\ $\\leftarrow 1$'),
			(5, 2, 7.1, '\\bitfield{haltreq},\\\\ \\bitfield{hartsel} $= h$'),
			(6, 3, 8.6, 'halt at an\\\\ instruction\\\\ boundary'),
			(7, 2, 10.1, 'drop\\\\ \\bitfield{haltreq}'),
			(8, 2, 11.6, 'clear\\\\ \\bitfield{cmderr}'),
			(9, 3, 13.1, 'run the\\\\ abstract\\\\ command'),
			(10, 2, 14.6, 'poll\\\\ \\bitfield{busy}'),
			(11, 0, 16.1, 'read\\\\ \\register{data0}'),
			(12, 3, 17.6, '\\asminline{dret},\\\\ running'),
		]
		s = '% Generated debug halt/read/resume swimlane\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tlane/.style={font=\\sffamily\\small, anchor=east},\n'
		s += '\tband/.style={fill=black!4},\n'
		s += '\tstp/.style={draw, thick, rounded corners=2pt, align=center, font=\\sffamily\\scriptsize, minimum width=1.30cm, minimum height=0.95cm, fill=white, inner sep=2pt},\n'
		s += '\tnum/.style={circle, draw, thick, fill=black!12, font=\\sffamily\\scriptsize, inner sep=1.2pt},\n'
		s += '\tflow/.style={->, >=Stealth, semithick, gray!75},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left}]\n'
		for name, y in lanes:
			s += '\\fill[band] (-0.2, ' + '%.2f' % (y - 0.62) + ') rectangle (18.6, ' + '%.2f' % (y + 0.62) + ');\n'
			s += '\\node[lane] at (-0.35, ' + '%.2f' % y + ') {' + name + '};\n'
		prev = None
		for n, li, x, txt in steps:
			y = lanes[li][1]
			s += '\\node[stp] (p' + str(n) + ') at (' + '%.2f' % x + ', ' + '%.2f' % y + ') {' + txt + '};\n'
			s += '\\node[num, anchor=center] at (' + '%.2f' % (x - 0.72) + ', ' + '%.2f' % (y + 0.50) + ') {' + str(n) + '};\n'
			if prev is not None:
				s += '\\draw[flow] (p' + str(prev) + ') -- (p' + str(n) + ');\n'
			prev = n
		s += '\\draw[->, >=Stealth, thick] (-0.2, -1.05) -- (18.6, -1.05);\n'
		s += '\\node[note, anchor=north east] at (18.6, -1.15) {time $\\rightarrow$ (not to scale)};\n'
		s += '\\node[note, anchor=north west] at (-0.2, -1.15) {Step numbers are the numbered list in this section.};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugSwimlaneDiagram.tex', s)
		return

	def GenerateDmiFieldDiagram(self):
		'''include/DmiFieldDiagram.tex — the 41-bit dmi data register.
		   Field split from hdl/common/jtag_dtm.vhd:222 and :573-575:
		   op(1 downto 0), data(33 downto 2), address(40 downto 34). Widths are
		   drawn for legibility, not to scale -- the bit numbers carry the
		   truth, and saying so in the caption is cheaper than a 41-cell bar.'''
		fields = [
			(3.4, '\\register{address}', '40:34', '7 bits: the DMI address'),
			(6.4, '\\register{data}', '33:2', '32 bits: read result or write value'),
			(2.6, '\\register{op}', '1:0', '2 bits'),
		]
		s = '% Generated 41-bit DMI data-register field bar\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tfld/.style={draw, thick, align=center, font=\\sffamily\\small, minimum height=1.0cm, fill=black!6},\n'
		s += '\tbit/.style={font=\\sffamily\\scriptsize},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=center}]\n'
		x = 0.0
		for w, name, bits, desc in fields:
			cx = x + w / 2.0
			s += '\\node[fld, minimum width=' + '%.2f' % w + 'cm] at (' + '%.2f' % cx + ', 0) {' + name + '};\n'
			s += '\\node[bit, anchor=south west] at (' + '%.2f' % x + ', 0.52) {' + bits.split(':')[0] + '};\n'
			s += '\\node[bit, anchor=south east] at (' + '%.2f' % (x + w) + ', 0.52) {' + bits.split(':')[1] + '};\n'
			s += '\\node[note, anchor=north] at (' + '%.2f' % cx + ', -0.55) {' + desc + '};\n'
			x += w
		s += '\\node[note, anchor=north west, align=left] at (0, -1.30) {\\textbf{Shifted LSB first}, so \\register{op} goes in and comes out first. On the way \\emph{in}: \\texttt{00} no-op, \\texttt{01} read, \\texttt{10} write.\\\\ On the way \\emph{out}: \\texttt{00} success, \\texttt{10} failed, \\texttt{11} busy. Field widths here are for legibility; the bit numbers are exact.};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DmiFieldDiagram.tex', s)
		return

	def GenerateDebugPageDiagram(self):
		'''include/DebugPageDiagram.tex — the debug program page, drawn to the
		   LANDED ledger in hdl/common/debug_module.vhd:53-79 and its address
		   constants at :255-278: W_DATA0 0x10680, W_PROGBUF0/1 0x10684/88,
		   W_IMPLICIT 0x1068C, MIRROR0/1 0x106F0/F4, W_FLAGS0 0x10700,
		   W_ENTRY 0x10780, TRAMP_WORDS 40, W_ABST 0x10820, W_EPILOG 0x10840,
		   W_BAND_HI 0x1087F. The bootrom zeroes 0x10000-0x107FF, so the
		   0x10800 line is where the write-before-read contract stops covering
		   the page -- above it every word is DM-written CODE.'''
		# (height, addr label, contents, fill)
		segs = [
			(0.62, '\\texttt{0x10680}', '\\register{data0}: the abstract data word', 'black!14'),
			(0.62, '\\texttt{0x10684}', '\\register{progbuf0}, \\register{progbuf1}, implicit third word', 'black!10'),
			(0.62, '\\texttt{0x10690}', 'reserved for the Debug Module', 'black!4'),
			(0.62, '\\texttt{0x106F0}', 'saved \\asminline{s0} / \\asminline{s1}, written by the stub, never by the DM', 'black!10'),
			(0.82, '\\texttt{0x10700}', 'per-hart handshake word \\ \\texttt{0x10700}$+4h$', 'black!14'),
			(1.05, '\\texttt{0x10780}', '\\textbf{trampoline}, 40 words, \\emph{planted by the Debug Module}', 'black!20'),
			(0.62, '\\texttt{0x10820}', 'abstract command body (DM-written per command)', 'black!10'),
			(0.62, '\\texttt{0x10840}', 'epilogue (DM-written once)', 'black!10'),
			(0.52, '\\texttt{0x10864}', 'spare', 'black!4'),
		]
		W = 10.4
		s = '% Generated debug program page map (landed D4 ledger)\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tseg/.style={draw, thick, align=center, font=\\sffamily\\small, minimum width=' + '%.2f' % W + 'cm},\n'
		s += '\tadr/.style={font=\\sffamily\\scriptsize\\ttfamily, anchor=east},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left}]\n'
		# LOW ADDRESS AT THE TOP, matching the table this figure sits beside:
		# each segment's start address labels its OWN TOP edge, and the band's
		# end address labels the bottom edge of the last one.
		xAdr = -W / 2.0 - 0.12
		y = 0.0
		yTramp = None
		for h, addr, txt, fill in segs:
			s += '\\node[seg, minimum height=' + '%.2f' % h + 'cm, fill=' + fill + ', anchor=north] at (0, ' + '%.2f' % y + ') {};\n'
			s += '\\node[adr] at (' + '%.2f' % xAdr + ', ' + '%.2f' % y + ') {' + addr + '};\n'
			if 'trampoline' in txt:
				# the 0x10800 line crosses this band, so its text sits in the
				# UPPER part of the band, clear of the line at word 32 of 40
				yTramp = y
				s += '\\node[font=\\sffamily\\small, anchor=north] at (0, ' + '%.2f' % (y - 0.06) + ') {' + txt + '};\n'
			else:
				s += '\\node[font=\\sffamily\\small] at (0, ' + '%.2f' % (y - h / 2.0) + ') {' + txt + '};\n'
			y -= h
		s += '\\node[adr] at (' + '%.2f' % xAdr + ', ' + '%.2f' % y + ') {0x1087F};\n'
		# The zero-range boundary. 0x10800 is word 32 of the 40-word trampoline,
		# i.e. 32/40 of the way down that band -- NOT a band edge.
		yBoundary = yTramp - 1.05 * (32.0 / 40.0)
		xNote = W / 2.0 + 0.20
		s += '\\draw[very thick, densely dashed] (' + '%.2f' % (-W / 2.0 - 0.05) + ', ' + '%.2f' % yBoundary + ') -- (' + '%.2f' % (W / 2.0 + 6.6) + ', ' + '%.2f' % yBoundary + ');\n'
		# anchored ACROSS the line, so the two blocks cannot overprint
		s += '\\node[note, anchor=south west] at (' + '%.2f' % xNote + ', ' + '%.2f' % (yBoundary + 0.10) + ') {\\textbf{\\texttt{0x10800}}: above this line the boot ROM does \\emph{not}\\\\ zero-fill. Everything up here is CODE the Debug Module\\\\ writes before anything reads it: the trampoline\'s last\\\\ eight words, the command body and the epilogue.};\n'
		s += '\\node[note, anchor=north west] at (' + '%.2f' % xNote + ', ' + '%.2f' % (yBoundary - 0.10) + ') {Below \\texttt{0x10800} the boot ROM zeroes \\texttt{0x10000}--\\texttt{0x107FF}\\\\ at every boot, so every DM-written \\emph{data} word starts\\\\ from a known value.};\n'
		s += '\\node[note, anchor=north west] at (' + '%.2f' % (-W / 2.0) + ', ' + '%.2f' % (y - 0.40) + ') {The whole span \\texttt{0x10680}--\\texttt{0x1087F} is reserved. It is ordinary shared RAM, and it cannot be read-only,\\\\ because the Debug Module rewrites the command body at every abstract command.};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugPageDiagram.tex', s)
		return

	def GenerateDebugModeStateDiagram(self):
		'''include/DebugModeStateDiagram.tex — debug mode from the hart's side.
		   Entry causes and their dcsr.cause encodings are vesta.vhd:2648-2654
		   (1 ebreak, 3 halt request, 4 step, 5 halt-on-reset); the entry vector
		   is DEBUG_ENTRY_ADDR, 0x00010780 on a debug-ON build (mcu_vhd.py:3037).
		   dret is 0x7B200073 (constants.vhd:484) and is an illegal instruction
		   outside debug mode (maindec.vhd:1112-1131).'''
		s = '% Generated hart debug-mode state diagram\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tst/.style={draw, thick, rounded corners=3pt, align=center, font=\\sffamily\\small, minimum width=3.5cm, minimum height=1.25cm},\n'
		s += '\trun/.style={st, fill=black!5},\n'
		s += '\tdbg/.style={st, fill=black!16},\n'
		s += '\tflow/.style={->, >=Stealth, thick},\n'
		s += '\tel/.style={font=\\sffamily\\scriptsize, align=center, fill=white, inner sep=2pt},\n'
		s += '\tnote/.style={font=\\sffamily\\scriptsize, align=left}]\n'
		s += '\\node[run] (run) at (0, 3.2) {\\textbf{running}\\\\ \\scriptsize M-mode or U-mode};\n'
		s += '\\node[dbg] (dbg) at (0, 0) {\\textbf{debug mode}\\\\ \\scriptsize executing the stub at\\\\ \\scriptsize \\texttt{0x00010780}};\n'
		s += '\\draw[flow] (-1.15, 2.58) -- node[el, anchor=east, xshift=-3pt] {\\textbf{entry}: taken at an instruction\\\\ boundary; \\register{dpc} and \\register{dcsr}.\\bitfield{cause}\\\\ are written, then the hart jumps} (-1.15, 0.62);\n'
		s += '\\draw[flow] (1.15, 0.62) -- node[el, anchor=west, xshift=3pt] {\\asminline{dret}: \\register{dpc} restores the\\\\ program counter, \\register{dcsr}.\\bitfield{prv} the\\\\ privilege level} (1.15, 2.58);\n'
		s += '\\node[note, anchor=north west, align=left] at (5.9, 3.55) {\\textbf{Four ways in}, each recorded in \\register{dcsr}.\\bitfield{cause}:\\\\[3pt]\n'
		s += '\t\\texttt{3} \\ a halt request from the Debug Module,\\\\ \\hspace*{1.1em}unmaskable, and recognised even in the\\\\ \\hspace*{1.1em}terminal trap state\\\\[2pt]\n'
		s += '\t\\texttt{1} \\ an \\asminline{EBREAK}, when \\register{dcsr}.\\bitfield{ebreakm} is set\\\\[2pt]\n'
		s += '\t\\texttt{4} \\ one instruction retired with \\register{dcsr}.\\bitfield{step}\\\\[2pt]\n'
		s += '\t\\texttt{5} \\ halt-on-reset, sampled once as the hart\\\\ \\hspace*{1.1em}leaves reset};\n'
		s += '\\node[note, anchor=north west, align=left] at (5.9, 0.30) {While in debug mode: \\textbf{no interrupt is taken}\\\\ (they stay pending and arrive after the \\asminline{dret}),\\\\ and a synchronous exception \\textbf{re-enters} here with\\\\ \\register{dpc} and \\register{dcsr} untouched rather than wedging\\\\ the hart.};\n'
		s += '\\draw[flow] (dbg.south west) to[out=200, in=160, looseness=4.2] node[el, anchor=east, xshift=-2pt] {exception in\\\\ debug mode} (dbg.north west);\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugModeStateDiagram.tex', s)
		return

	def GeneratePackagePinoutDiagram(self):
		'''include/PackagePinoutDiagram.tex — fully labeled package top view,
		   derived from the same package model as config/PadRing.json.'''
		pkg = self.Gen.Package
		D = float(pkg.Dimensions[0])
		half = D / 2.0
		pitch = float(pkg.PinPitch)
		pw = float(pkg.PinWidth)
		pd = float(pkg.PinDepth)

		def pinLabel(pin):
			if pin.NoConnect:
				return '\\textit{\\color{black!55}NC}'
			name = fmttex(pin.Name)
			if pin.FuncName is not None:
				name += '\\,/\\,' + fmttex(pin.FuncName)
			if pin.IsPowerDomainPin:
				return '\\textbf{' + name + '}'
			return name

		s = '% Generated package pinout (derived from the package model; see config/PadRing.json)\n'
		s += '\\begin{tikzpicture}[x=10mm, y=10mm]\n'
		s += '\\draw[thick] (' + '%.3f' % -half + ',' + '%.3f' % -half + ') rectangle (' + '%.3f' % half + ',' + '%.3f' % half + ');\n'
		# Center annotation
		s += '\\node[align=center, font=\\sffamily] at (0,0) {\\textbf{\\AsicNameForUserGuide}\\\\ ' + pkg.PackageType + '-' + str(pkg.PinCount) + ', top view\\\\ \\footnotesize ' + str(pkg.Dimensions[0]) + '$\\times$' + str(pkg.Dimensions[1]) + '\\,' + pkg.Units + ', ' + str(pkg.PinPitch) + '\\,' + pkg.Units + ' pitch};\n'
		# Pin-1 dot
		s += '\\fill (' + '%.3f' % (-half + 0.55) + ',' + '%.3f' % (half - 0.55) + ') circle (0.09);\n'

		sideCount = {'W': 0, 'S': 0, 'E': 0, 'N': 0}
		for pin in pkg.Pins:
			sideCount[pin.Side] += 1
		sideIdx = {'W': 0, 'S': 0, 'E': 0, 'N': 0}
		for pin in pkg.Pins:
			n = sideCount[pin.Side]
			j = sideIdx[pin.Side]
			sideIdx[pin.Side] += 1
			fill = ', fill=black!15' if pin.IsPowerDomainPin else ''
			if pin.Side == 'W':
				y = ((n - 1) / 2.0 - j) * pitch
				s += '\\draw[thick' + fill + '] (' + '%.3f' % (-half - 0.001) + ',' + '%.3f' % (y - pw / 2) + ') rectangle (' + '%.3f' % (-half + pd) + ',' + '%.3f' % (y + pw / 2) + ');\n'
				s += '\\node[font=\\tiny, anchor=west, inner sep=1pt] at (' + '%.3f' % (-half + pd + 0.06) + ',' + '%.3f' % y + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[font=\\tiny\\sffamily, anchor=east, inner sep=1.5pt] at (' + '%.3f' % (-half - 0.12) + ',' + '%.3f' % y + ') {' + pinLabel(pin) + '};\n'
			elif pin.Side == 'S':
				xq = (j - (n - 1) / 2.0) * pitch
				s += '\\draw[thick' + fill + '] (' + '%.3f' % (xq - pw / 2) + ',' + '%.3f' % (-half - 0.001) + ') rectangle (' + '%.3f' % (xq + pw / 2) + ',' + '%.3f' % (-half + pd) + ');\n'
				s += '\\node[font=\\tiny, anchor=west, inner sep=1pt, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (-half + pd + 0.06) + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[font=\\tiny\\sffamily, anchor=east, inner sep=1.5pt, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (-half - 0.12) + ') {' + pinLabel(pin) + '};\n'
			elif pin.Side == 'E':
				y = (j - (n - 1) / 2.0) * pitch
				s += '\\draw[thick' + fill + '] (' + '%.3f' % (half - pd) + ',' + '%.3f' % (y - pw / 2) + ') rectangle (' + '%.3f' % (half + 0.001) + ',' + '%.3f' % (y + pw / 2) + ');\n'
				s += '\\node[font=\\tiny, anchor=east, inner sep=1pt] at (' + '%.3f' % (half - pd - 0.06) + ',' + '%.3f' % y + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[font=\\tiny\\sffamily, anchor=west, inner sep=1.5pt] at (' + '%.3f' % (half + 0.12) + ',' + '%.3f' % y + ') {' + pinLabel(pin) + '};\n'
			else:	# N
				xq = ((n - 1) / 2.0 - j) * pitch
				s += '\\draw[thick' + fill + '] (' + '%.3f' % (xq - pw / 2) + ',' + '%.3f' % (half - pd) + ') rectangle (' + '%.3f' % (xq + pw / 2) + ',' + '%.3f' % (half + 0.001) + ');\n'
				s += '\\node[font=\\tiny, anchor=east, inner sep=1pt, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (half - pd - 0.06) + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[font=\\tiny\\sffamily, anchor=west, inner sep=1.5pt, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (half + 0.12) + ') {' + pinLabel(pin) + '};\n'
		s += '\\end{tikzpicture}\n'
		with open(self.IncludeDirectory + '/PackagePinoutDiagram.tex', 'w') as f:
			f.write(s)
		return

	def GenerateInterruptsTable(self):
		# Get all of the peripherals that generate interrupt signals
		interruptPeripherals = [p for p in self.Gen.Peripherals if p.InterruptPriority is not None]
		interruptPeripherals.sort(key=lambda p: p.InterruptPriority)

		# Create the interrupts table tex file
		s = '\\begin{longtable}[c]{ l l }\n'
		s += '\\caption{Interrupt Vectors} \\label{t:interrupt-vectors} \\\\ \n'
		
		s += '\\hline \\textbf{Priority} & \\textbf{Interrupt Source} \\\\ \\hline \\endfirsthead\n'

		s += '\\multicolumn{2}{c}{\\textit{Continued from previous page}} \\\\ \\hline\n'
		s += '\\hline \\textbf{Priority} & \\textbf{Interrupt Source} \\\\ \\hline \\endhead\n'

		s += '0 & CPU Internal Timer \\\\\n'
		s += '\\rowcolor{tablehighlightcolor} 1 & EBREAK, ECALL, or Illegal Instruction \\\\\n'
		s += '2 & Bus Error (unaligned memory access) \\\\\n'

		thisRowColored = True
		for p in interruptPeripherals:
			if thisRowColored:
				s += '\\rowcolor{tablehighlightcolor} '
			s += str(p.InterruptPriority) + ' & \\peripheral{' + fmttex(p.Name) + '}\\\\\n'
			thisRowColored = not thisRowColored
		
		# Remove the \\ from the final entry and add an ending horizontal line
		s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
		
		s += '\\end{longtable}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/InterruptsTable.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return
	
	def GeneratePackagePinsConfigurationTable(self):
		s = '\\begin{longtable}[c]{ l l l l l }\n'
		s += '\\caption{Package Pins} \\label{t:package-pins} \\\\ \n'

		s += '\\hline \\textbf{\\#} & \\textbf{Pin} & \\textbf{I/O} & \\textbf{Power Domain} & \\textbf{Power Pins} \\\\ \\hline \\endfirsthead\n'

		s += '\\multicolumn{5}{c}{\\textit{\\tablename\ \\thetable\ continued from previous page}} \\\\ \\hline\n'
		s += '\\textbf{\\#} & \\textbf{Pin} & \\textbf{I/O} & \\textbf{Power Domain} & \\textbf{Power Pins} \\\\ \\hline \\endhead\n'

		s += '\\hline \\multicolumn{5}{c}{\\textit{\\tablename\\ \\thetable\\ continued on next page}} \\\\ \\endfoot \\hline \\endlastfoot\n'

		thisRowColored=False

		prevSide = self.Gen.Package.Pins[0].Side

		for pin in self.Gen.Package.Pins:
			if prevSide != pin.Side:
				s += '\\hline \n'
			prevSide = pin.Side
			
			if thisRowColored:
				s += '\\rowcolor{tablehighlightcolor} '
			thisRowColored = not thisRowColored
			
			s += str(pin.PackagePinNumber) + ' & '

			if pin.NoConnect:
				s += '\\textit{NC} & -- & -- & -- \\\\\n'
				continue

			s += fmttex(pin.Name) + ' & ' + pin.IOString + ' & ' + pin.PowerDomain.Description + ' & ' + fmttex(pin.PowerDomain.PositiveRailPackagePin.Name) + '/' + fmttex(pin.PowerDomain.NegativeRailPackagePin.Name) + ' \\\\\n'
		
		# Remove the \\ from the final entry and add an ending horizontal line
		s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
		s += '\\end{longtable}\n'
		
		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/PackagePinsConfigurationTable.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return

	
	def GenerateGpioPinsConfigurationTable(self):
		# Get all of the GPIO peripherals
		gpioPeripherals = []
		for p in self.Gen.Peripherals:
			if p.IsGPIO():
				gpioPeripherals.append(p)
		
		# Create the GPIO pins configuration table. The pin's additional alternate
		# functions (AF1-AF7) are deliberately NOT a column here: the full per-pin
		# plane matrix is Table \ref{t:gpio-afs}, and inlining the comma-joined list
		# made this table overrun the text block and push the reset-value columns
		# off the page.
		s = '\\begin{longtable}[c]{ l l l l l l l }\n'
		s += '\\caption{GPIO Pin Functions and Reset Values} \\label{t:gpio-pins} \\\\ \n'

		s += '\\hline & \\textbf{Primary} & \\textbf{Alternate} & \\multicolumn{4}{c}{\\textbf{\\textit{Reset Values}}}\\\\ \\cline{4-7}\n'
		s += '\\textbf{Pin} & \\textbf{Function} & \\textbf{Function (AF0)} & \\textbf{SEL} & \\textbf{OUT} & \\textbf{DIR} & \\textbf{REN} \\\\  \\hline \\endfirsthead\n'

		s += '\\multicolumn{7}{c}{\\textit{\\tablename\ \\thetable\ continued from previous page}} \\\\ \\hline\n'
		s += ' & \\textbf{Primary} & \\textbf{Alternate} & \\multicolumn{4}{c}{\\textbf{\\textit{Reset Values}}}\\\\ \\cline{4-7}\n'
		s += '\\textbf{Pin} & \\textbf{Function} & \\textbf{Function (AF0)} & \\textbf{SEL} & \\textbf{OUT} & \\textbf{DIR} & \\textbf{REN} \\\\ \\hline \\endhead\n'

		s += '\\hline \\multicolumn{7}{c}{\\textit{\\tablename\\ \\thetable\\ continued on next page}} \\\\ \\endfoot \\hline \\endlastfoot\n'

		thisRowColored = False

		for i, p in enumerate(gpioPeripherals):
			for j, pin in enumerate(p.Pins):
				if pin.NoConnect:
					continue
				if thisRowColored:
					s += '\\rowcolor{tablehighlightcolor} '
				s += 'P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber) + ' & '

				if len(pin.PrimaryName) > 0:
					s += '\\pin{' + fmttex(pin.PrimaryName) + '} & '
				else:
					s += '-- & '

				if len(pin.FuncName) > 0:
					s += '\\pin{' + fmttex(pin.FuncName) + '} & '
				else:
					s += '-- & '

				if pin.RstSEL == 1:
					s += '1 \\textit{(Alternate)} & '
				else:
					s += '0 \\textit{(Primary)} & '
				
				if pin.RstOUT == 1:
					s += '1 \\textit{(High)} & '
				else:
					s += '0 \\textit{(Low)} & '
				
				if pin.RstDIR == 1:
					s += '1 \\textit{(Output)} & '
				else:
					s += '0 \\textit{(Input)} & '
				
				if pin.RstREN == 1:
					s += '1 \\textit{(Enabled)} \\\\'
				else:
					s += '0 \\textit{(Disabled)} \\\\'
				
				if ((i + 1) < len(gpioPeripherals)) and ((j + 1) == len(p.Pins)):
					# This is not the last GPIO port, but is the last pin in the port
					s += ' \\hline'
				s += '\n'
				thisRowColored = not thisRowColored
		
		# Remove the \\ from the final entry and add an ending horizontal line
		s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
		s += '\\end{longtable}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/GpioPinsConfigurationTable.tex'
		with open(path, 'w') as f:
			f.write(s)

		return


	def GenerateGpioAltFunctionMatrixTable(self):
		# One row per GPIO pin, one column per PxAFS field value (0..7): the exact
		# function driven onto (or read from) the pad when the pin is in alternate
		# function mode (PxSEL = 1) and its PxAFS field selects that plane. Plane 0
		# is the pin's AF0 (legacy secondary) function; planes 1..7 come from the
		# pin's additional alternate functions. A plane with no function assigned is
		# a high-impedance input.
		gpioPeripherals = []
		for p in self.Gen.Peripherals:
			if p.IsGPIO():
				gpioPeripherals.append(p)

		# Compact superscript tag for the plane's I/O direction ('I'/'O'/'IO'/'')
		def ioTag(ioType):
			if ioType == 'I':
				return '\\textsuperscript{\\scriptsize in}'
			if ioType == 'O':
				return '\\textsuperscript{\\scriptsize out}'
			if ioType == 'IO':
				return '\\textsuperscript{\\scriptsize io}'
			return ''

		# Render a single plane cell. A dagger marks the pin's reset plane (PxAFS
		# reset value); an unassigned plane renders as a high-impedance input.
		def planeCell(name, ioType, isReset):
			if name is None or len(name) < 1:
				cell = '\\textit{\\color{lightgray}Hi-Z}'
			else:
				cell = '\\pin{' + fmttex(name) + '}' + ioTag(ioType)
			if isReset:
				cell += '\\textsuperscript{$\\dagger$}'
			return cell

		# The matrix is 9 columns wide; shrink the font and column padding so it fits
		# the text block, and wrap in a group so those changes are local.
		s = '{\\footnotesize\\setlength{\\tabcolsep}{3pt}\n'
		s += '\\begin{longtable}[c]{ l | c c c c c c c c }\n'
		s += '\\caption{GPIO Alternate Function Selection (\\register{PxAFS})} \\label{t:gpio-afs} \\\\ \n'

		topSpan = '\\hline & \\multicolumn{8}{c}{\\textbf{\\textit{\\register{PxAFS} field value (selected AF plane)}}} \\\\ \\cline{2-9}\n'
		header = '\\textbf{Pin} & \\textbf{0 (AF0)} & \\textbf{1} & \\textbf{2} & \\textbf{3} & \\textbf{4} & \\textbf{5} & \\textbf{6} & \\textbf{7} \\\\'

		s += topSpan
		s += header + ' \\hline \\endfirsthead\n'

		s += '\\multicolumn{9}{c}{\\textit{\\tablename\ \\thetable\ continued from previous page}} \\\\ \\hline\n'
		s += topSpan
		s += header + ' \\hline \\endhead\n'

		s += '\\hline \\multicolumn{9}{c}{\\textit{\\tablename\\ \\thetable\\ continued on next page}} \\\\ \\endfoot \\hline \\endlastfoot\n'

		thisRowColored = False
		for i, p in enumerate(gpioPeripherals):
			for j, pin in enumerate(p.Pins):
				if pin.NoConnect:
					continue
				if thisRowColored:
					s += '\\rowcolor{tablehighlightcolor} '
				s += 'P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber) + ' & '

				cells = []
				# Plane 0 is AF0 (the pin's primary secondary/peripheral function)
				cells.append(planeCell(pin.FuncName, pin.FuncIOType, pin.RstAFS == 0))
				# Planes 1..7 are drawn from the pin's additional alternate functions
				for planeIdx in range(1, 8):
					af = None
					for a in pin.AltFuncs:
						if a.Index == planeIdx:
							af = a
							break
					if af is None:
						cells.append(planeCell(None, None, pin.RstAFS == planeIdx))
					else:
						cells.append(planeCell(af.Name, af.IOType, pin.RstAFS == planeIdx))

				s += ' & '.join(cells) + ' \\\\'

				if ((i + 1) < len(gpioPeripherals)) and ((j + 1) == len(p.Pins)):
					# Not the last GPIO port, but the last pin in this port
					s += ' \\hline'
				s += '\n'
				thisRowColored = not thisRowColored

		# Remove the \\ from the final entry and add an ending horizontal line
		s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
		s += '\\end{longtable}\n'
		s += '}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/GpioAltFunctionMatrixTable.tex'
		with open(path, 'w') as f:
			f.write(s)

		return

	def GenerateForthCommandsItemized(self):
		s = '\\subsection{Memory Access Functions}\n'
		s += '\\begin{itemize}\n'

		s += self.generateForthCommand('@', 'Read directly from the memory address and push the value to the TOS',
			args=[['addr', 'The address to read from (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += self.generateForthCommand('!', 'Write directly to memory address',
			args=[['x', 'The value to write to the memory address'], ['addr', 'The address to write to (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += self.generateForthCommand('+!', 'Add to value, direct memory access (*addr += x)',
			args=[['x', 'The value to add to the value at the memory address'], ['addr', 'The address to write to (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += self.generateForthCommand('sbi', 'Set bit, direct memory access (*addr |= (1 << bitnum))',
			args=[['bitnum', 'The bit number'], ['addr', 'The address to write to (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += self.generateForthCommand('cbi', 'Clear bit, direct memory access (*addr &= ~(1 << bitnum))',
			args=[['bitnum', 'The bit number'], ['addr', 'The address to write to (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += self.generateForthCommand('mask', 'Change only masked bits, direct memory access (*addr = (*addr & ~bitmask) | (x & bitmask))',
			args=[['bitmask', 'The bit mask. Only bits with 1s can be changed'], ['x', 'The value to write (only masked bits will be written)'], ['addr', 'The address to write to (must be aligned to a 4-byte (32-bit) boundary)']],
			rets=None)
		
		s += '\\end{itemize}\n\n'

		# Printing
		s += '\\subsection{Print and Input Functions}\n'
		s += '\\begin{itemize}\n\n'
		
		s += self.generateForthCommand('.', 'Prints the TOS as an integer',
			args=[['x', 'The value to print']],
			rets=None)
		
		s += self.generateForthCommand('h.', 'Prints the TOS as a hex string', 				args=[['x', 'The value to print']],
			rets=None)
		
		s += self.generateForthCommand('echo', 'Change the echo state, which controls whether the Forth interpreter repeats all of its received characters',
			args=[['bool', 'If 0, does not echo. Otherwise, it does']],
			rets=None)
		
		s += self.generateForthCommand('emit', 'Prints the char at the TOS (integers are mapped to their ASCII counterparts)',
			args=[['x', 'The ASCII value of the char to print']],
			rets=None)
		
		s += self.generateForthCommand('key', 'Waits for a char over UART and pushes the ASCII value of the char to the TOS',
			args=None,
			rets=[['char', 'The char that was received over UART']])

		s += self.generateForthCommand('list', 'Prints all currently available functions',
			args=None,
			rets=None)
		
		s += '\\end{itemize}\n\n'

		# Arithmatic
		s += '\\subsection{Arithmetic Functions}\n'
		s += '\\begin{itemize}\n\n'
		
		s += self.generateForthCommand('+', 'Adds two numbers (y + x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('-', 'Subtracts two numbers (y - x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('*', 'Multiplies two numbers (y * x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['retprodhi', 'Upper 32 bits of the return product'], ['retprodlo', 'Lower 32 bits of the return product']])
		
		s += self.generateForthCommand('/%', 'Divides two numbers with remainder (y / x and y % x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['retdiv', 'The integer division result'], ['retrem', 'The remainder (or modulo) result']])
		
		s += self.generateForthCommand('neg', 'Returns the negative (twos complement) of x',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('abs', 'Absolute value (|x|)',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += '\\end{itemize}\n\n'

		# Bitwise
		s += '\\subsection{Bitwise Logic Functions}\n'
		s += '\\begin{itemize}\n\n'

		s += self.generateForthCommand('~', 'Bitwise complement/inversion (~x)',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('|', 'Bitwise OR (y | x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('&', 'Bitwise AND (y & x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('^', 'Bitwise XOR (y ^ x)',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('*2', 'Shift left 1 bit (x << 1)',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('/2', 'Shift right 1 bit (x >> 1)',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('sll', 'Shift left logical (x << bits)',
			args=[['x', 'Signed integer'], ['bits', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('srl', 'Shift right logical (x >> bits), no sign extension',
			args=[['x', 'Signed integer'], ['bits', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += '\\end{itemize}\n\n'

		# Comparisons
		s += '\\subsection{Comparison Functions}\n'
		s += '\\begin{itemize}\n\n'
		
		s += self.generateForthCommand('>', 'Greater than. Returns 1 if y > x, returns 0 otherwise.',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', '1 if true, 0 if false']])
		
		s += self.generateForthCommand('<', 'Less than. Returns 1 if y < x, returns 0 otherwise.',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', '1 if true, 0 if false']])
		
		s += self.generateForthCommand('==', 'Equals. Returns 1 if y == x, returns 0 otherwise.',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', '1 if true, 0 if false']])
		
		s += '\\end{itemize}\n'

		# Boolean
		s += '\\subsection{Boolean Functions}\n'
		s += '\\begin{itemize}\n\n'
		
		s += self.generateForthCommand('not', 'Logical not (!x). Returns 1 if x is equal to 0, returns 0 otherwise',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('and', 'Logical and (y && x). Returns 1 if y and x are both true (nonzero), returns 0 otherwise',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])

		s += self.generateForthCommand('or', 'Logical or (y || x). Returns 1 if y or x are true (nonzero), returns 0 otherwise',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += '\\end{itemize}\n'

		# Stack
		s += '\\subsection{Stack Manipulation Functions}\n'
		s += '\\begin{itemize}\n\n'
		
		s += self.generateForthCommand('dup', 'Duplicates the TOS (pops the TOS and then pushes the value to the TOS twice)',
			args=[['x', 'Value to duplicate']],
			rets=[['x', 'The original TOS'], ['x', 'The duplicated value']])
		
		s += self.generateForthCommand('drop', 'Pops the TOS and sets it as the internal Forth \\forthinline{i} value. Usually used to delete the TOS.',
			args=[['x', 'The value that is dropped']],
			rets=None)
		
		s += self.generateForthCommand('swap', 'Swaps the TOS with the value below the TOS',
			args=[['y', 'Old value below the TOS'], ['x', 'Old TOS']],
			rets=[['x', 'Old TOS'], ['y', 'Old value below the TOS']])
		
		s += self.generateForthCommand('over', 'Copies the value below the TOS and pushes it to the TOS',
			args=[['y', 'Signed Integer'], ['x', 'Signed Integer']],
			rets=[['y', 'Signed Integer'], ['x', 'Signed Integer'], ['y', 'Signed Integer']])
		
		s += self.generateForthCommand('tuck', 'Copies the TOS and inserts it two after the TOS',
			args=[['y', 'Signed Integer'], ['x', 'Signed Integer']],
			rets=[['x', 'Signed Integer'], ['y', 'Signed Integer'], ['x', 'Signed Integer']])
		
		s += self.generateForthCommand('roll', 'Removes value at index n of the stack and pushes it to the TOS (zero indexed)',
			args=[['n', 'Stack index (zero indexed)']],
			rets=None)
		
		s += self.generateForthCommand('pick', 'Copies value at index n of the stack and pushes it to the TOS (zero indexed)',
			args=[['n', 'Stack index (zero indexed)']],
			rets=None)
		
		s += self.generateForthCommand('depth', 'Gets size of stack and pushes it to the top of the stack (making the new stack size the value of TOS + 1)',
			args=None,
			rets=[['ret', 'Return value']])
		
		s += '\\end{itemize}\n\n'

		# Flash
		s += '\\subsection{SPI Flash R/W and Programming Functions} \\label{ss:forthflash}\n'
		s += '\\begin{itemize}\n\n'

		s += self.generateForthCommand('fr', 'Reads data from the SPI flash.',
			args=[['bin', 'If true (nonzero), transmits binary data, otherwise transmits ASCII hex string'], ['length', 'The number of bytes to read'], ['addr', 'The address in the SPI flash to begin reading from']],
			rets=None)
		
		s += self.generateForthCommand('fe', 'Erases a 256-byte page from the SPI flash memory. The start address must be 256-byte aligned.',
			args=[['conf', 'If equal to 123, erases the page and returns 1, otherwise does not erase and returns 0'], ['addr', 'The start address of the page to erase in the SPI flash. Must be 256-byte aligned.']],
			rets=[['eraseSuccessful', 'Nonzero if successful, zero if failed']])
		
		s += self.generateForthCommand('fw', 'Writes data to the SPI flash. Must write exactly 256 bytes at a time. The start address must be 256-byte aligned.',
			args=[['bin', 'If true (nonzero), expects to receive binary data, otherwise expects to receive an ASCII hex string'], ['addr', 'The address in the SPI flash to begin writing to. Must be 256-byte aligned.']],
			rets=None)
		
		s += '\\end{itemize}\n\n'

		# Misc
		s += '\\subsection{Miscellaneous Functions}\n'
		s += '\\begin{itemize}\n\n'

		s += self.generateForthCommand('rst', 'Performs a soft reset (turns on all memory cells and jumps to address 0 in the ROM, does not reset clocks or hardware)',
			args=None,
			rets=None)
		
		s += self.generateForthCommand('clk', 'Measures selected clock frequency',
			args=[['meastime', 'Measurement time. 0 = 1 s; 1 = 0.5 s; 2 = 0.25 s; 3 = 0.125 s'], ['clksel', 'Clock select. 0 = SMCLK; 1 = MCLK; 2 = LFXT; 3 = HFXT']],
			rets=[['freq', 'Selected clock frequency in Hz']])
		
		s += self.generateForthCommand('min', 'Returns minimum value of y and x',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('max', 'Returns maximum value of y and x',
			args=[['y', 'Signed integer'], ['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('swpb', 'Swap bits 15 downto 8 with bits 7 downto 0 of TOS, also causes bits 31 downto 16 to all be 0',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += self.generateForthCommand('swphw', 'Swap upper 16 bits with lower 16 bits of TOS',
			args=[['x', 'Signed integer']],
			rets=[['ret', 'Return value']])
		
		s += '\\end{itemize}\n\n'
	
		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/ForthCommandsItemized.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return
	
	def generateForthCommand(self, cmd:str, desc:str, args, rets):
		# Latex-ify the command
		cmd = cmd.replace('~', '{\\~}').replace('%', '{\\%}')
		
		# Make the headline
		s = '\\item \\forthinlinehl{' + cmd + '}\\ \\forthinline{( '
		if (type(args) == list or type(args) == tuple) and len(args) > 0:
			for arg in args:
				s += arg[0] + ' '
		s += '-- '
		if (type(rets) == list or type(rets) == tuple) and len(rets) > 0:
			for ret in rets:
				s += ret[0] + ' '
		s += ')}\n\n'

		# Print the description
		s += '\\noindent ' + fmttex(desc) + '\n\n'

		# Print the arguments
		s += '\\noindent Arguments: '
		if (type(args) != list and type(args) != tuple) or len(args) == 0:
			s += 'none\n\n'
		else:
			s += '(in order from TOS down, reverse text order):\n'
			s += '\\begin{enumerate}\n'
			for i, arg in enumerate(reversed(args)):
				tosStr = ''
				if i == 0:
					tosStr = '(TOS) '
				s += '\\item \\forthinline{' + arg[0] + '}' + ': ' + tosStr + arg[1] + '\n'
			s += '\\end{enumerate}\n\n'
		
		# Print the return values
		s += '\\noindent Return values: '
		if (type(rets) != list and type(rets) != tuple) or len(rets) == 0:
			s += 'none\n\n'
		else:
			s += '(in order from TOS down, reverse text order):\n'
			s += '\\begin{enumerate}\n'
			for i, ret in enumerate(reversed(rets)):
				tosStr = ''
				if i == 0:
					tosStr = '(TOS) '
				s += '\\item \\forthinline{' + ret[0] + '}' + ': ' + tosStr + ret[1] + '\n'
			s += '\\end{enumerate}\n\n'
		
		return s
	
	def GeneratePeripheralSections(self):
		# Get all the peripheral templates
		pts = []
		for p in self.Gen.Peripherals:
			if p.Template not in pts:
				pts.append(p.Template)
		
		# Generate the tex file for each peripheral template
		s = ''
		for pt in pts:
			# Is this the GPIO peripheral?
			gpioBits = None
			if pt.NameTemplate == 'GPIOx':
				# What is the maximum number of bits in each of the GPIO ports?
				gpioBits = 8
				for p in self.Gen.Peripherals:
					if not p.IsGPIO():
						continue
					if p.Registers[0].Size > gpioBits:
						gpioBits = p.Size
			
			# Start the peripheral's section
			s += '\\section{\\peripheral{' + fmttex(pt.NameTemplate) + '} Peripheral} \\label{peripheral' + pt.NameTemplate.replace('_', '') + '}\n'

			# Add the latex intro file or the description
			if pt.LatexIntroFileName is not None:
				s += '\\input{include/' + pt.LatexIntroFileName + '}\n\n\\newpage\n\n'
			else:
				s += fmttex(pt.Description) + '\n\n'
			
			# Add the registers
			s += '\\subsection{Register Description}\n\n'
			for rt in pt.RegisterTemplates:
				size = rt.Size
				if gpioBits is not None:
					size = gpioBits
				
				# Add the register subsection
				# Strip the 'x' from the register name for display (but keep it in the label for hyperlinks)
				displayRegisterName = rt.NameTemplate.replace('x', '')
				s += '\\subsubsection{\\texttt{' + fmttex(displayRegisterName) + '} Register} \\label{ss:' + rt.NameTemplate.replace('_', '') + '}\n'

				# Add the memory address, register slot, offset, and size
				addS = ''
				if size > 8:
					addS = 's'
				s += '\\noindent \\textit{Register memory slot:} ' + str(rt.RegisterMemorySlot) + ', \\textit{offset:} ' + str(rt.Offset) + ' bytes, \\textit{size:} ' + str(size // 8) + ' byte' + addS + '\n\n'

				# Add the register description
				s += '\\noindent ' + fmttex(rt.Description) + '\n\n'

				# Add the bytefield
				s += '\\begin{center}\n'
				s += '\\begin{bytefield}[endianness=big, bitwidth=0.125\\linewidth]{8}\n'

				for byteNum in reversed(range(4)):
					# Add each bytefield byte
					if byteNum >= 2 and size <= 16:
						continue
					if byteNum >= 1 and size <= 8:
						continue
					
					lineLSB = byteNum * 8
					lineMSB = lineLSB + 7

					# Make the bit header
					s += '\\bitheader[lsb=' + str(lineLSB) + ']{' + str(lineLSB) + '-' + str(lineMSB) + '} \\\\\n'

					# Make the bit fields for this byte
					# For GPIO registers with multi-bit fields spanning the entire register, render each bit individually
					# Otherwise, group consecutive bits with the same bitfield
					isGPIO = (pt.NameTemplate == 'GPIOx')
					bfs = []
					for bitNum in reversed(range(lineLSB, lineMSB + 1)):
						bf = rt.GetBitFieldAt(bitNum)
						if bf is None:
							bfs.append((None, bitNum))
						elif isGPIO and bf.Size > 1 and bf.MSB == rt.Size - 1 and bf.LSB == 0:
							# GPIO multi-bit field spanning entire register - render each bit separately
							bfs.append((bf, bitNum))
						elif len(bfs) == 0 or bfs[-1][0] != bf:
							# New bitfield or different from previous
							bfs.append((bf, bitNum))
					
					for bf_info in bfs:
						bf, bitNum = bf_info
						if bf is None:
							s += '\\bitbox{1}{} & '
							continue
						
						# Check if this is a GPIO multi-bit field spanning entire register
						if isGPIO and bf.Size > 1 and bf.MSB == rt.Size - 1 and bf.LSB == 0:
							# Render single bit with index for GPIO only
							length = 1
							displayName = bf.Name
							if type(pt.BitFieldPrefix) == str and bf.Name.startswith(pt.BitFieldPrefix):
								displayName = bf.Name[len(pt.BitFieldPrefix):]
							s += '\\bitbox{' + str(length) + '}{\\texttt{' + fmttex(displayName) + '[' + str(bitNum) + ']}} & '
						else:
							# Normal grouped rendering
							length = 1 + min(bf.MSB, lineMSB) - max(bf.LSB, lineLSB)
							if bf.Unused:
								s += '\\bitbox{' + str(length) + '}{\\textit{\\color{lightgray}Unused}} & '
							else:
								displayName = bf.Name
								if type(pt.BitFieldPrefix) == str and bf.Name.startswith(pt.BitFieldPrefix):
									displayName = bf.Name[len(pt.BitFieldPrefix):]
								s += '\\bitbox{' + str(length) + '}{\\texttt{' + fmttex(displayName) + '}} & '
					s = s[:-2] + '\\\\\n'
				
					# Make the read/write/reset fields
					for bitNum in reversed(range(lineLSB, lineMSB + 1)):
						bf = rt.GetBitFieldAt(bitNum)

						if bf is None or bf.Unused:
							s += '\\bitbox[t]{1}{} & '
						else:
							s += '\\bitbox[t]{1}{\\tiny ' + bf.Accessibility + '-(' + str(rt.GetBitResetValue(bitNum)) + ')} & '
					s = s[:-2] + '\\\\\n'
				
				s += '\\end{bytefield}\n'
				s += '\\end{center}\n\n'

				# Add the value descriptions table
				skip = True
				for bf in rt.BitFields:
					if bf.Unused:
						continue
					if bf.SameNameAsRegister and (len(bf.ValueDescriptions) == 0):
						continue
					skip = False
				
				if not skip:
					s += '\\begin{tabularx}{\\textwidth}{ l l l X }\n'
					s += '\\textbf{Bitfield} & \\textbf{Range} & \\multicolumn{2}{X}{\\textbf{Description}} \\\\ \\hline\n'
					
					for i, bf in enumerate(rt.BitFields):
						if bf.Unused:
							s += '\\textit{Unused} & '
						else:
							# Strip the peripheral prefix from the bitfield name for display
							displayName = bf.Name
							if type(pt.BitFieldPrefix) == str and bf.Name.startswith(pt.BitFieldPrefix):
								displayName = bf.Name[len(pt.BitFieldPrefix):]
							s += '\\texttt{' + fmttex(displayName) + '} & '
						
						if bf.Size > 1:
							s += 'Bits ' + str(bf.MSB) + '-' + str(bf.LSB) + ' & '
						else:
							s += 'Bit ' + str(bf.MSB) + ' & '
						
						s += '\\multicolumn{2}{X}{' + fmttex(bf.Description) + '} \\\\\n'

						thisRowColored = False

						for vd in bf.ValueDescriptions:
							value, description, name = vd
							s += ' & & '

							if thisRowColored:
								s += '\\cellcolor{tablehighlightcolor}'
							
							s += '\\texttt{' + fmtbin(value, minDigits=bf.Size, usePrefix=False) + '} & '

							if thisRowColored:
								s += '\\cellcolor{tablehighlightcolor}'
							
							if len(name) > 0:
								s += '\\texttt{' + fmttex(name) + '}: '
							
							s += fmttex(description) + ' \\\\\n'

							thisRowColored = not thisRowColored
						
						if (i + 1) < len(rt.BitFields):
							# Not the last line
							s += '\\hline\n'
					
					# Remove the \\ from the final entry and add an ending horizontal line
					s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
					s += '\\end{tabularx}\n\n'
			
			s += '\\newpage\n\n\n\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/PeripheralSections.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return
	
	def GeneratePeripheralAndRegistersList(self):
		# Generate the tex file for each peripheral template
		s = ''
		for p in self.Gen.Peripherals:
			# Start the peripheral's section
			s += '\\subsection{\\peripheral{' + fmttex(p.Name) + '} Peripheral}\n'

			# Add the base address and peripheral memory slot
			if p.PeripheralMemorySlot is None:
				s += '\\noindent Base address: \\texttt{' + fmthex(p.BaseAddress) + '} (shared window, arbitrated across all harts)\n\n'
			else:
				s += '\\noindent Base address: \\texttt{' + fmthex(p.BaseAddress) + '}, peripheral memory slot: ' + str(p.PeripheralMemorySlot) + '\n\n'
			
			# Add the table of all the register templates
			s += '\\begin{tabularx}{\\textwidth}{ l l l l X }\n'
			s += '\\textbf{Register} & \\textbf{Address} & \\textbf{Slot} & \\textbf{Offset (bytes)} & \\textbf{Size (bytes)} \\\\ \\hline\n'

			thisRowColored = False
			for r in p.Registers:
				if thisRowColored:
					s += '\\rowcolor{tablehighlightcolor} '
				s += '\\hyperref[ss:' + r.Template.NameTemplate.replace('_', '') + ']{\\texttt{' + fmttex(r.Name) + '}} & '
				s += '\\texttt{' + fmthex(r.Address) + '} & '
				s += str(r.RegisterMemorySlot) + ' & '
				s += str(r.Offset) + ' & '
				s += str(r.Size // 8) + ' \\\\\n'

				thisRowColored = not thisRowColored
			
			# Remove the \\ from the final entry and add an ending horizontal line
			s = s[:-3] + r'\\' + '\n' + r'\hline' + '\n'
			s += '\\end{tabularx}\n\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)
		
		path = self.IncludeDirectory + '/PeripheralAndRegistersList.tex'
		with open(path, 'w') as f:
			f.write(s)
		
		return
			


	