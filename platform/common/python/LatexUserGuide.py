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

def fmtprose(s:str):
	'''Model text for the rendered page: TeX-escaped, with every dash spelled out (house rule: no en or em dashes).'''
	s = re.sub(r'\s*---\s*', ', ', s)
	s = re.sub(r'(?<=[0-9A-Fa-fx])--(?=[0-9A-Fa-fx])', ' to ', s)
	s = re.sub(r'\s*--\s*', ', ', s)
	return fmttex(s)

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
		# The whole-chip block diagram of the Overview chapter.
		# Ungated, so the master template can \ref it in either polarity.
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
		self.GeneratePackagePinoutDiagram()
		self.GenerateInterruptsTable()
		self.GenerateAccessLegend()
		self.GenerateAddressSpaceTable()
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
		# The ISA string and the TCM aperture stride, both from the generator's own records.
		# The template tests \ifdefined for each, so a configuration without them still builds.
		isa = ((getattr(self.Gen, 'ResolvedConfig', None) or {}).get('derived') or {}).get('isaString')
		if isa:
			defines['IsaString'] = fmttex(str(isa))
		if geo and geo.get('tcmApertureSize'):
			defines['TcmApertureStride'] = fmthex(int(geo['tcmApertureSize']))
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
				# One include per role (include/ExtraIntro-MULTICORE.tex and so on).
				# The template can then place a chapter by role without knowing the file's revision name.
				role = fileName.split('-intro')[0].upper()
				self._writeInclude('ExtraIntro-' + role + '.tex',
					'% Generated from ChipGenerator.ExtraLatexIntroFiles, do not edit\n\\input{include/' + fileName + '}\n')

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/ExtraIntroChapters.tex'
		with open(path, 'w') as f:
			f.write(s)

		return

	def GenerateAfeSystemDiagram(self):
		'''include/AfeSystemDiagram.tex is the analog front-end connectivity figure.
		   Drawn ONLY where the AFE bank exists (the CQ package model declares DocSubSlotBlocks; \\ifcqanalog gates the chapter that \\inputs this).
		   Six boxes: the arbiter bar, the EIS site and the four AFE sites in one rank under it, and one dashed box for the analog stages that are not integrated.
		   The harts are not drawn (the whole-chip figure has them); each site box names its owning hart and the caption carries the hart 0 rule.
		   The electrode pads are real (the CQ pad ring bonds four per site), so three per AFE site are drawn crossing the red boundary.'''
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
		# The three electrode pads this figure draws per site, plus the fourth it does not draw (RE2), must all be bonded by the package model.
		pinNames = set(p.Name for p in self.Gen.Package.Pins)
		electrodes = ['WE', 'RE', 'CE']
		missing = [e + '_' + str(i) for i in range(4)
			for e in ('WE', 'RE', 'CE', 'RE2') if (e + '_' + str(i)) not in pinNames]
		if missing:
			raise Exception('AfeSystemDiagram: the package model does not bond the electrode '
				'pads %s that this figure draws crossing the chip boundary' % str(missing))

		def P(v):
			return '%.2f' % v

		# ---- geometry, in cm.
		# One rank of five register sites under the arbiter bar, 15.3 cm wide at natural size, inside the 16.5 cm text block.
		# The harts are not drawn: the ownership is one line in each site box and one sentence in the caption.
		sites = eis + afe
		siteW, gap = 2.70, 0.35
		x0 = 0.30
		xs = [x0 + siteW / 2.0 + k * (siteW + gap) for k in range(len(sites))]
		barX0 = x0
		barX1 = x0 + len(sites) * siteW + (len(sites) - 1) * gap
		yArb, arbH = 4.40, 0.70        # the arbiter bar
		ySite, siteH = 2.60, 1.30      # the register sites
		yRed = 0.60                    # the chip boundary
		padDx = 0.85                   # electrode pitch within a site
		yAna = (ySite - siteH / 2.0 + yRed) / 2.0

		s = ('% Generated AFE connectivity diagram (sites=' + str(len(afe))
			+ ', owners=' + str(owners) + ', harts=' + str(N) + ')\n')
		s += '\\begin{tikzpicture}[\n'
		s += '\tsite/.style={vblockw, align=center, font=\\sffamily\\footnotesize},\n'
		s += '\tbar/.style={vbar, align=center, font=\\sffamily\\small\\bfseries},\n'
		s += '\tana/.style={vghost, rounded corners=2pt, align=center, font=\\sffamily\\footnotesize},\n'
		s += '\tlab/.style={font=\\sffamily\\footnotesize, align=center, inner sep=1pt},\n'
		s += '\tredlab/.style={vredlab, font=\\sffamily\\footnotesize\\bfseries},\n'
		s += '\tbus/.style={vbus},\n'
		s += '\twire/.style={vwire}]\n'

		# ---- the arbiter bar, and the five sites hanging off it
		s += ('\\node[bar, minimum width=' + P(barX1 - barX0) + 'cm, minimum height=' + P(arbH)
			+ 'cm] at (' + P((barX0 + barX1) / 2.0) + ', ' + P(yArb) + ') {mp\\_arbiter};\n')
		for k, b in enumerate(sites):
			if b['name'] == 'EIS':
				owner = 'hart ' + str(b['ownerHart']) + ' only'
			else:
				owner = 'owner hart ' + str(b['ownerHart'])
			s += ('\\node[site, minimum width=' + P(siteW) + 'cm, minimum height=' + P(siteH)
				+ 'cm, text width=' + P(siteW - 0.30) + 'cm] at (' + P(xs[k]) + ', ' + P(ySite)
				+ ') {\\textbf{\\small ' + b['name'] + '}\\\\ \\texttt{' + fmthex(b['base']) + '}\\\\ ' + owner + '};\n')
			s += ('\\draw[bus] (' + P(xs[k]) + ', ' + P(yArb - arbH / 2.0) + ') -- ('
				+ P(xs[k]) + ', ' + P(ySite + siteH / 2.0) + ');\n')

		# ---- the analog stages under the EIS site, drawn as absent
		s += ('\\node[ana, minimum width=' + P(siteW) + 'cm, minimum height=0.80cm, text width=' + P(siteW - 0.30)
			+ 'cm] at (' + P(xs[0]) + ', ' + P(yAna) + ') {analog stages\\\\ not integrated};\n')

		# ---- the chip boundary and the three electrode pads under each AFE site
		s += '\\draw[vbound] (' + P(barX0 - 0.20) + ', ' + P(yRed) + ') -- (' + P(barX1 + 0.20) + ', ' + P(yRed) + ');\n'
		s += '\\node[redlab, anchor=north west] at (' + P(barX0 - 0.20) + ', ' + P(yRed - 0.12) + ') {chip boundary};\n'
		for i, b in enumerate(afe):
			c = xs[sites.index(b)]
			for k, e in enumerate(electrodes):
				x = c + (k - 1) * padDx
				s += '\\draw[wire] (' + P(x) + ', ' + P(ySite - siteH / 2.0) + ') -- (' + P(x) + ', ' + P(yRed) + ');\n'
				s += ('\\fill[vestaRed] (' + P(x - 0.07) + ', ' + P(yRed - 0.07) + ') rectangle ('
					+ P(x + 0.07) + ', ' + P(yRed + 0.07) + ');\n')
				s += ('\\node[lab, anchor=north] at (' + P(x) + ', ' + P(yRed - 0.12)
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
		# The whole-chip PORTRAIT figure it was re-pointed at was itself retired
		# on 2026-08-25, so the citation is now the flat whole-chip figure, which
		# carries the same hart band and the same arbiter bar.
		s += ('Figure \\ref{fig:afe-system-diagram} is the arrangement: the five analog register '
			'sites in one rank under the shared-window arbiter of Figure \\ref{fig:chip-system-flat-diagram}, '
			'the three electrode pads that leave the die under each AFE site, and the analog stages '
			'that are not yet integrated.\n\n')
		# A portrait figure at natural size: the emitter fits the rank to the text block at 8 pt.
		s += '\\begin{figure}[htpb]\n\t\\centering\n'
		s += '\t\\input{include/AfeSystemDiagram.tex}\n'
		s += ('\t\\caption{Analog front-end connectivity: each AFE site answers its owning hart and hart 0, '
			'the EIS site answers hart 0 only, and three electrode pads per site leave the die.}\n')
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
			'\\texttt{0x7C00} to \\texttt{0x7FFF} quarter it owns.\n\n')

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
				offStr = '\\texttt{' + fmthex(loByte, 2) + '} to \\texttt{' + fmthex(hiByte, 2) + '}'
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
	_ADDR_GROUP_SHARED = '\\sffamily\\footnotesize Shared window\\\\(all harts, arbitrated)'
	# The private band is the one row in the column whose contents differ per
	# hart, so it carries the theme's red the way a boundary does elsewhere.
	# The colour does not survive the row break inside a rightwordgroup label,
	# so each line has to set it for itself.
	_ADDR_GROUP_PRIVATE = ('\\sffamily\\footnotesize\\bfseries\\color{vestaRedText}'
		'Private to each hart\\\\'
		'\\sffamily\\footnotesize\\bfseries\\color{vestaRedText}(not arbitrated)')
	_ADDR_GROUP_APERTURE = ('\\sffamily\\footnotesize Shared window\\\\(hart 0\'s read-only view'
		'\\\\of each hart\'s TCM)')
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
		unmappedLines = ['\\textit{\\color{black!55}Unmapped}', '\\textit{\\color{black!55}(reads zero)}']

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
		'''E17-style build-time assertion over the rows the emitter ACTUALLY
		   drew, parsed back out of the emitted tex rather than out of the model
		   that produced them.
		   Every row but the last carries its start address only (\\memrow or
		   \\memgap), and the last row (\\memsection) carries both ends.
		   The starts must be strictly increasing from zero and the last end must
		   be the top of the 32-bit space, or `make generate` fails instead of
		   shipping an inverted or gapped column.'''
		toks = re.findall(r'\\mem(section|row|gap)\{0x([0-9A-Fa-f]+)\}(?:\{0x([0-9A-Fa-f]+)\})?', tex)
		if not toks:
			raise Exception('AddressSpaceDiagram: no address rows were emitted')
		prev = -1
		for i, (kind, a, b) in enumerate(toks):
			start = int(a, 16)
			if start != prev + 1 and i > 0:
				raise Exception('AddressSpaceDiagram: drawn row {} starts at 0x{:X}, not right after 0x{:X}'.format(i, start, prev))
			if i == 0 and start != 0:
				raise Exception('AddressSpaceDiagram: the drawn column starts at 0x{:X}, not at zero'.format(start))
			if kind == 'section':
				if i != len(toks) - 1:
					raise Exception('AddressSpaceDiagram: only the last row carries an end address')
				end = int(b, 16)
				if end != self._ADDR_TOP:
					raise Exception('AddressSpaceDiagram: the drawn column ends at 0x{:X}, not at the top of the 32-bit space 0x{:X}'.format(end, self._ADDR_TOP))
			# The start of the next row is what closes this one.
			prev = start - 1
			if i + 1 < len(toks):
				prev = int(toks[i + 1][1], 16) - 1
		if toks[-1][0] != 'section':
			raise Exception('AddressSpaceDiagram: the last row must carry its end address')

	def _AddressSpaceFigureRows(self):
		'''The rows the figure draws, derived from _AddressSpaceRows.
		   The table keeps every row; the figure merges the per-hart aperture rows
		   into one, drops every "Size =" sub-line by folding the size into the
		   row label, and leaves the unmapped rows wordless.
		   Returns (start, end, group, label) with label None for an unmapped row.'''
		rows = self._AddressSpaceRows()
		out = []
		i = 0
		while i < len(rows):
			start, end, group, lines = rows[i]
			if group is None:
				out.append((start, end, None, None))
				i += 1
				continue
			if group == self._ADDR_GROUP_APERTURE:
				j = i
				while j + 1 < len(rows) and rows[j + 1][2] == group and rows[j + 1][0] == rows[j][1] + 1:
					j += 1
				n = j - i + 1
				each = rows[i][1] - rows[i][0] + 1
				label = ('TCM apertures 0 to ' + str(n - 1) + ', ' + str(n) + ' $\\times$ '
					+ self._AddressSpaceSizeString(each))
				if n == 1:
					label = 'TCM aperture 0, ' + self._AddressSpaceSizeString(each)
				out.append((start, rows[j][1], group, label))
				i = j + 1
				continue
			title = lines[0]
			extra = [l for l in lines[1:] if not self._StripTex(l).startswith('Size')]
			if group == self._ADDR_GROUP_FLASH:
				# The window has no meaningful size; it is the flash device's.
				label = title
				if any('read only' in self._StripTex(l) for l in extra):
					label += ', read only'
			else:
				size = self._AddressSpaceSizeString(end - start + 1)
				if group == self._ADDR_GROUP_PRIVATE:
					size += ' per hart'
				label = title + ', ' + size
				# A multiplexed slot keeps its note as the only extra line.
				for l in extra:
					if 'Multiplexed' in l:
						label += '\\\\ ' + l
			out.append((start, end, group, label))
			i += 1
		return out

	def GenerateAddressSpaceDiagram(self):
		'''include/AddressSpaceDiagram.tex, the address column drawn once for
		   every hart, the STM32 memory-map idiom.
		   One address per row edge, the size in the row label, the unmapped
		   rows a plain grey with no words, and one brace per access class run.
		   The column is input at natural size and every label is 8 pt or larger.'''
		rows = self._AddressSpaceFigureRows()
		hRow, hGap, hLast = '2', '1.3', '2.6'

		def cell(k, r):
			start, end, group, label = r
			if k == len(rows) - 1:
				body = label if label is not None else ''
				return ('\\memsection{' + fmthex(start, minDigits=5) + '}{' + fmthex(end, minDigits=5)
					+ '}{' + hLast + '}{' + body + '}')
			if label is None:
				return '\\memgap{' + fmthex(start, minDigits=5) + '}{' + hGap + '}'
			return '\\memrow{' + fmthex(start, minDigits=5) + '}{' + hRow + '}{' + label + '}'

		# A brace spans a RUN of one access class, and an unmapped row between
		# two rows of the same class is absorbed into that run so the shared
		# window reads as one bracket rather than four.
		def groupAt(k):
			g = rows[k][2]
			if g is not None:
				return g
			before = rows[k - 1][2] if k > 0 else None
			after = rows[k + 1][2] if k + 1 < len(rows) else None
			return before if before is not None and before == after else None

		s = '\\begin{bytefield}{8}\n'
		i = 0
		while i < len(rows):
			group = groupAt(i)
			j = i
			if group is not None:
				while (j + 1) < len(rows) and groupAt(j + 1) == group:
					j += 1
			body = [cell(k, rows[k]) for k in range(i, j + 1)]
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
		self._writeInclude('AddressSpaceDiagram.tex', s)
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
			('Shared-window address width', '\\texttt{' + str(drv.get('sharedWindowAddrWidth')) + '} bits (words)', 'Arbiter/tile word-address width; the window is \\texttt{0x0} to $2^{w+2}-1$'),
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

	# ------------------------------------------------------------------
	# WHOLE-CHIP BLOCK DIAGRAM (GenerateChipSystemFlatDiagram).
	# Everything drawn is derived from the configuration.
	# The boxes come from bucketing Gen.Peripherals with the table below.
	# The E17 assertion in _ChipSystemBoxes compares the drawn instance set
	# with Gen.Peripherals, so a peripheral nobody placed fails make chip.
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
					+ fmttex(gpioPads[0].Name) + ' to ' + fmttex(gpioPads[-1].Name), w=3.05)
			above['io'] = box('io', 'GPIO', self._chipFigNames([p.Name for p in ps]),
				str(len(ps[0].Pins)) + ' pins per port\\\\ AF0 to AF7 planes',
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
				masters.append({'title': 'hart 1 to ' + str(N - 1), 'sub': 'channel tile',
					'harts': [], 'stack': N - 1, 'note': tileNote, 'weight': 2.4})
		elif N <= 6:
			for h in range(N):
				masters.append({'title': 'hart ' + str(h), 'sub': 'hart tile', 'harts': [h],
					'stack': 1, 'note': tileNote, 'weight': 1.0})
		else:
			masters.append({'title': 'hart 0 to ' + str(N - 1), 'sub': 'hart tile', 'harts': [],
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

	def _vTextWidth(self, tex, size='small', bold=False):
		'''Width in cm of the widest line of a sans label in one of the theme's
		   two diagram sizes, calibrated on Libertine Sans at 9 pt and 8 pt.
		   Every box in the generated block diagrams is sized from this, so a
		   label the box cannot hold widens the box instead of spilling it.'''
		lower, upper, digit, space = {
			'small': (0.165, 0.221, 0.163, 0.088),
			'footnotesize': (0.148, 0.199, 0.147, 0.079)}[size]
		best = 0.0
		for line in (tex or '').split('\\\\'):
			t = line.replace('\\times', 'x').replace('\\,', ' ').replace('\\_', '_')
			t = re.sub(r'\\textsuperscript\{[^}]*\}', '2', t)
			t = re.sub(r'\\[a-zA-Z]+', '', t)
			for ch in '{}$':
				t = t.replace(ch, '')
			w = 0.0
			for ch in t.strip():
				if ch.isupper():
					w += upper
				elif ch.isdigit():
					w += digit
				elif ch == ' ':
					w += space
				elif ch in '.,:;/|!\'ilj()':
					w += lower * 0.55
				else:
					w += lower
			best = max(best, w * (1.12 if bold else 1.0))
		return best

	def _vBox(self, x0, y0, x1, y1, title, subs, badge=None):
		'''One themed block: a vbox outline with the name in \\small on top and
		   the secondary lines in \\footnotesize under it, both wrapped to the
		   box width so a long line can never print through the outline.'''
		P = lambda v: '%.2f' % v
		cx = (x0 + x1) / 2.0
		tw = P(x1 - x0 - 0.24)
		s = '\\draw[vbox] (' + P(x0) + ', ' + P(y0) + ') rectangle (' + P(x1) + ', ' + P(y1) + ');\n'
		body = title
		if subs:
			body += '\\\\[1pt] {\\footnotesize ' + '\\\\ '.join(subs) + '}'
		s += ('\\node[vname, text width=' + tw + 'cm, execute at begin node={\\hyphenpenalty=10000\\relax}] at ('
			+ P(cx) + ', ' + P((y0 + y1) / 2.0) + ') {' + body + '};\n')
		if badge:
			s += ('\\node[vlab, anchor=north east, fill=black!8, rounded corners=1pt, inner sep=1.5pt] at ('
				+ P(x1 - 0.06) + ', ' + P(y1 - 0.06) + ') {$\\times$' + str(badge) + '};\n')
		return s

	def GenerateChipSystemFlatDiagram(self):
		'''include/ChipSystemFlatDiagram.tex — the whole-chip figure the manual
		   prints. It began as the FLAT companion to the portrait cut
		   (GenerateChipSystemDiagram, retired 2026-08-25): the same
		   configuration and the same derived content, drawn as a datasheet block
		   diagram instead of a portrait page. Five things differ from that cut,
		   and each is the point:

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
					+ str(padOf[h]) + ', and this figure omits the shared engine\'s register '
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

	def GenerateClockSystemDiagram(self):
		'''include/ClockSystemDiagram.tex, the clock tree drawn the STM32 way,
		   left to right: the sources, the two select muxes with the code beside
		   each input, the two dividers, the SMCLKOFF gate, the MCLK and SMCLK
		   bars, and the three consumer boxes, with the timers on their own
		   SSEL mux between the bars.
		   Everything is read off the register model and asserted against it.
		   The mux legs are built from the MCLKSEL and SMCLKSEL value
		   descriptions, so a leg is a table row and cannot be mis-wired.
		   The source set comes from bit-field presence and is cross-checked
		   against the set the selects reach.
		   The divider ratios come from SYSMCLKDIV and SYSSMCLKDIV.
		   Every peripheral is placed by its own clockDomain and the drawn set
		   is proved to be the configured set.
		   The MCLKSEL code that names SMCLK is wired from the node after the
		   SMCLK divider and before the SMCLKOFF gate, which is where SYSTEM.vhd
		   takes it, so stopping SMCLK does not stop MCLK.
		   The drawing is input at natural size at the text width.'''
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None) or {}
		N = gen.NumHarts
		pkg = gen.Package
		padNames = set(pin.Name for pin in pkg.Pins)
		funcs = set(pin.FuncName for pin in pkg.Pins if pin.FuncName is not None)
		P = lambda v: '%.2f' % v

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
			   register order, with the enumeration's completeness asserted.'''
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

		def codeTex(bf, v):
			return '\\texttt{' + format(v, '0' + str(bf.Size) + 'b') + '}'

		selM, selS = field('SYSCLKCR', 'MCLKSEL'), field('SYSCLKCR', 'SMCLKSEL')
		divM, divS = field('CLKDIVCR', 'SYSMCLKDIV'), field('CLKDIVCR', 'SYSSMCLKDIV')

		# ---- THE SOURCES, derived from BIT-FIELD PRESENCE --------------------
		_SRC_SPEC = [
			('hfxt', 'HFXT', 'HFXTOFF', None),
			('lfxt', 'LFXT', 'LFXTOFF', None),
			('dco0', 'DCO0', 'DCO0ON', 'DCO0BIAS'),
			('dco1', 'DCO1', 'DCO1ON', 'DCO1BIAS'),
		]
		_SUFFIX_SRC = dict(('_' + spec[1], spec[0]) for spec in _SRC_SPEC)
		specOf = dict((spec[0], spec) for spec in _SRC_SPEC if spec[2] in sysBits)

		# The source column is in SMCLKSEL code order, so every SMCLK leg is a
		# straight horizontal at its own row.
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
				+ str(sorted(specOf)) + '. The drawn source set must BE the configured one.')
		rowOf = dict((k, i) for i, k in enumerate(order))
		for k in order:
			trim = specOf[k][3]
			if trim is not None and trim not in regOf:
				raise Exception('ClockSystemDiagram: source ' + specOf[k][1] + ' is present '
					'(its ' + specOf[k][2] + ' bit exists) but this configuration has no '
					+ trim + ' register for the figure to name as its trim.')

		# The MCLK legs: every code names a source box or the SMCLK node.
		mcLegs = []
		for v, suf, d in mcCodes:
			if suf == '_SMCLK':
				mcLegs.append((v, None))
				continue
			if suf not in _SUFFIX_SRC or _SUFFIX_SRC[suf] not in specOf:
				raise Exception('ClockSystemDiagram: MCLKSEL code ' + str(v) + ' names "'
					+ str(suf) + '", which this configuration has no source box for.')
			mcLegs.append((v, _SUFFIX_SRC[suf]))
		if len([1 for v, k in mcLegs if k is None]) > 1:
			raise Exception('ClockSystemDiagram: MCLKSEL takes the SMCLK node more than once; '
				'the figure draws exactly one such wire, from the pre-gate node.')

		# ---- THE DIVIDERS: one ratio list each ------------------------------
		def ratios(bf):
			out = []
			for v, suf, d in codes(bf):
				r = d.split(' ')[0]
				if not r.startswith('/'):
					raise Exception('ClockSystemDiagram: ' + bf.Name + ' code ' + str(v)
						+ ' is described as "' + str(d) + '", which the figure cannot read as '
						'a division ratio.')
				out.append(r[1:])
			return out
		ratM, ratS = ratios(divM), ratios(divS)

		# ---- THE CONSUMERS, placed by the model's own clockDomain ------------
		_PRETTY = {'GPIOx': 'GPIO', 'SPIx': 'SPI', 'QSPIx': 'QSPI', 'UARTx': 'UART',
			'I2Cx': 'I\\textsuperscript{2}C', 'I2CTx': 'I\\textsuperscript{2}C target',
			'I3Cx': 'I3C', 'NFCx': 'NFC', 'OWx': '1-Wire', 'TIMERx': 'TIMER', 'PWMx': 'PWM',
			'RTCx': 'RTC', 'SYSTEM': 'SYSTEM', 'PWRCTRL': 'PWRCTRL', 'CLINT': 'CLINT',
			'MUTEX': 'MUTEX', 'IRQROUTER': 'IRQROUTER', 'NPU': 'NPU', 'DMAx': 'DMA',
			'TRNGx': 'TRNG', 'EVFAB': 'EVFAB'}
		groups = {}
		for p in gen.Peripherals:
			t = p.Template.NameTemplate
			if t not in _PRETTY:
				raise Exception('ClockSystemDiagram: peripheral template "' + str(t)
					+ '" (instance ' + str(p.Name) + ') has no place in the clock figure. Add '
					'it to _PRETTY, so the drawing says which clock it runs on.')
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

		def famList(dom):
			names = []
			for key in sorted(groups, key=lambda k: min(p.BaseAddress for p in groups[k])):
				if key[0] != dom:
					continue
				n = len(groups[key])
				names.append(_PRETTY[key[1]] + (' $\\times$' + str(n) if n > 1 else ''))
			return names
		mclkNames = famList('mclk')
		smclkNames = famList('smclk')
		muxedKeys = [k for k in groups if k[0] == 'muxed']

		# The timers' own select, in its register order.
		sselLegs = []
		muxedTitle = None
		if muxedKeys:
			if len(muxedKeys) != 1:
				raise Exception('ClockSystemDiagram: more than one peripheral family declares '
					'clockDomain "muxed"; the figure draws one own-select mux.')
			key = muxedKeys[0]
			ssel = None
			for p in groups[key]:
				for r in p.Registers:
					for bf in r.BitFields:
						if bf.Name == 'SSEL':
							ssel = bf
			if ssel is None:
				raise Exception('ClockSystemDiagram: ' + str(key[1]) + ' declares clockDomain '
					'"muxed" but carries no SSEL select for the figure to enumerate.')
			for v, suf, d in codes(ssel):
				sselLegs.append((codeTex(ssel, v), suf.lstrip('_')))
			n = len(groups[key])
			muxedTitle = _PRETTY[key[1]] + (' $\\times$' + str(n) if n > 1 else '')

		# ---- GEOMETRY (cm) ---------------------------------------------------
		xBnd0, xBnd1 = 0.5, 16.4
		xSrc0, xSrc1 = 0.5, 2.9
		rowTop, rowPitch, boxH = 6.9, 1.20, 1.00
		ySrc = [rowTop - rowPitch * i for i in range(len(order))]
		xMux0, xMux1 = 4.6, 5.3
		xDiv0, xDiv1 = 5.9, 8.4
		xGate0, xGate1 = 9.1, 11.0
		xBar0, xBar1 = 11.3, 16.2
		yS = sum(ySrc) / len(ySrc)
		mRows = len(mcLegs)
		yMtop = 1.6
		yMrow = [yMtop - 0.45 * i for i in range(mRows)]
		yM = sum(yMrow) / mRows
		barH = 0.36
		hasBoundary = any(specOf[k][3] is None for k in order)

		def mux(x0, x1, yT, yB, name, yName):
			w = x1 - x0
			return ('\\draw[vbox, sharp corners] (' + P(x0) + ', ' + P(yB) + ') -- (' + P(x1) + ', '
				+ P(yB + 0.35) + ') -- (' + P(x1) + ', ' + P(yT - 0.35) + ') -- (' + P(x0) + ', '
				+ P(yT) + ') -- cycle;\n' + '\\node[vlab, anchor=south] at (' + P((x0 + x1) / 2.0)
				+ ', ' + P(yName) + ') {\\bitfield{' + name + '}};\n')

		def bar(x0, x1, y, name):
			return ('\\draw[vbar] (' + P(x0) + ', ' + P(y - barH / 2) + ') rectangle (' + P(x1)
				+ ', ' + P(y + barH / 2) + ');\n\\node[vname] at (' + P((x0 + x1) / 2.0) + ', '
				+ P(y) + ') {' + name + '};\n')

		s = '% Generated clock tree (make chip), drawn from the SYSTEM register model.\n'
		s += '% Input at natural size at the text width.\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm]\n'
		# the chip boundary, with the external clock pads on its left edge
		s += ('\\draw[vbound] (' + P(xBnd0) + ', -1.65) rectangle (' + P(xBnd1) + ', '
			+ P(rowTop + boxH / 2 + 0.95) + ');\n')
		s += ('\\node[vredlab, anchor=north east, inner sep=3pt] at (' + P(xBnd1) + ', '
			+ P(rowTop + boxH / 2 + 0.95) + ') {\\AsicNameForUserGuide};\n')
		# the sources
		for i, k in enumerate(order):
			key, name, bit, trim = specOf[k]
			y = ySrc[i]
			if trim is None:
				subs = ['external clock']
				s += ('\\fill[vestaInk] (' + P(xSrc0 - 0.08) + ', ' + P(y - 0.08) + ') rectangle ('
					+ P(xSrc0 + 0.08) + ', ' + P(y + 0.08) + ');\n')
				s += '\\draw[vwire] (' + P(xSrc0 - 0.45) + ', ' + P(y) + ') -- (' + P(xSrc0) + ', ' + P(y) + ');\n'
			else:
				subs = ['\\register{' + trim + '}']
			s += self._vBox(xSrc0, y - boxH / 2, xSrc1, y + boxH / 2, name, subs)
		# the SMCLK select: straight legs, the code inside the mux at each input
		yMuxT, yMuxB = ySrc[0] + 0.45, ySrc[-1] - 0.45
		s += mux(xMux0, xMux1, yMuxT, yMuxB, selS.Name, yMuxT + 0.05)
		for i, (v, suf, d) in enumerate(smCodes):
			y = ySrc[i]
			s += '\\draw[vwire] (' + P(xSrc1) + ', ' + P(y) + ') -- (' + P(xMux0) + ', ' + P(y) + ');\n'
			s += '\\node[vlab, anchor=west, inner sep=0.5pt] at (' + P(xMux0 + 0.08) + ', ' + P(y) + ') {' + codeTex(selS, v) + '};\n'
		# the MCLK select below it, its source legs dropped from the SMCLK legs
		yMmuxT, yMmuxB = yMrow[0] + 0.40, yMrow[-1] - 0.40
		s += mux(xMux0, xMux1, yMmuxT, yMmuxB, selM.Name, yMmuxT + 0.05)
		srcLegs = sorted([(rowOf[k], v, k) for v, k in mcLegs if k is not None])
		feed = [v for v, k in mcLegs if k is None]
		# The row order is nested so no two of these wires cross: the highest
		# source takes the outer lane and the lowest MCLK input.
		rowsFree = list(range(mRows))
		mRowOf = {}
		if feed:
			mRowOf[feed[0]] = rowsFree.pop(0)
		for j, (ri, v, k) in enumerate(srcLegs):
			mRowOf[v] = rowsFree[-1 - j]
		for j, (ri, v, k) in enumerate(srcLegs):
			xLane = 3.30 + 0.40 * j
			ySrcRow = ySrc[ri]
			yRow = yMrow[mRowOf[v]]
			s += '\\node[vdot] at (' + P(xLane) + ', ' + P(ySrcRow) + ') {};\n'
			s += ('\\draw[vwire] (' + P(xLane) + ', ' + P(ySrcRow) + ') -- (' + P(xLane) + ', '
				+ P(yRow) + ') -- (' + P(xMux0) + ', ' + P(yRow) + ');\n')
		for v, k in mcLegs:
			y = yMrow[mRowOf[v]]
			s += '\\node[vlab, anchor=west, inner sep=0.5pt] at (' + P(xMux0 + 0.08) + ', ' + P(y) + ') {' + codeTex(selM, v) + '};\n'
		# the SMCLK chain: divider, the node, the gate, the bar
		s += self._vBox(xDiv0, yS - 0.65, xDiv1, yS + 0.65, '$\\div$ ' + ', '.join(ratS),
			['\\bitfield{' + divS.Name + '}'])
		s += '\\draw[vflow] (' + P(xMux1) + ', ' + P(yS) + ') -- (' + P(xDiv0) + ', ' + P(yS) + ');\n'
		xNode = (xDiv1 + xGate0) / 2.0
		s += self._vBox(xGate0, yS - boxH / 2, xGate1, yS + boxH / 2, 'gate', ['\\bitfield{SMCLKOFF}'])
		s += '\\draw[vflow] (' + P(xDiv1) + ', ' + P(yS) + ') -- (' + P(xGate0) + ', ' + P(yS) + ');\n'
		s += '\\draw[vflow] (' + P(xGate1) + ', ' + P(yS) + ') -- (' + P(xBar0) + ', ' + P(yS) + ');\n'
		s += bar(xBar0, xBar1, yS, 'SMCLK')
		if feed:
			yFeed = yMmuxT + 0.55
			xFeed = xMux0 - 0.30
			yRow = yMrow[mRowOf[feed[0]]]
			s += '\\node[vdot] at (' + P(xNode) + ', ' + P(yS) + ') {};\n'
			s += ('\\draw[vflow] (' + P(xNode) + ', ' + P(yS) + ') -- (' + P(xNode) + ', ' + P(yFeed)
				+ ') -- (' + P(xFeed) + ', ' + P(yFeed) + ') -- (' + P(xFeed) + ', ' + P(yRow)
				+ ') -- (' + P(xMux0) + ', ' + P(yRow) + ');\n')
			s += ('\\node[vlab, anchor=south east] at (' + P(xNode - 0.10) + ', ' + P(yFeed + 0.02)
				+ ') {SMCLK before the gate};\n')
		# the MCLK chain: divider and bar
		s += self._vBox(xDiv0, yM - 0.65, xDiv1, yM + 0.65, '$\\div$ ' + ', '.join(ratM),
			['\\bitfield{' + divM.Name + '}'])
		s += '\\draw[vflow] (' + P(xMux1) + ', ' + P(yM) + ') -- (' + P(xDiv0) + ', ' + P(yM) + ');\n'
		xMbar0 = xDiv1 + 0.30
		s += '\\draw[vflow] (' + P(xDiv1) + ', ' + P(yM) + ') -- (' + P(xMbar0) + ', ' + P(yM) + ');\n'
		s += bar(xMbar0, xBar1, yM, 'MCLK')
		# the consumers: MCLK below its bar, SMCLK below its bar, the own-select
		# family between them
		hartsTitle = 'harts' + (' $\\times$' + str(N) if N > 1 else '') + ', \\texttt{mp\\_arbiter}'
		mclkSubs = ['every register interface']
		if mclkNames:
			mclkSubs.append(', '.join(mclkNames))
		xC0, xC1 = 12.2, xBar1
		yMc = yM - barH / 2 - 0.35
		s += self._vBox(xMbar0 + 0.3, yMc - 1.75, xC1, yMc, hartsTitle, mclkSubs)
		xTap = (xC0 + xC1) / 2.0
		s += '\\draw[vwire] (' + P(xTap) + ', ' + P(yM - barH / 2) + ') -- (' + P(xTap) + ', ' + P(yMc) + ');\n'
		ySc = yS - barH / 2 - 0.35
		s += self._vBox(xC0, ySc - 1.30, xC1, ySc, 'serial engines', [', '.join(smclkNames) if smclkNames else 'none'])
		s += '\\draw[vwire] (' + P(xTap) + ', ' + P(yS - barH / 2) + ') -- (' + P(xTap) + ', ' + P(ySc) + ');\n'
		if muxedTitle:
			nIn = len(sselLegs)
			yT0 = ySc - 1.30 - 0.45
			yIn = [yT0 - 0.36 * i for i in range(nIn)]
			yTm = sum(yIn) / nIn
			xTm0, xTm1 = 11.55, 12.15
			s += mux(xTm0, xTm1, yIn[0] + 0.35, yIn[-1] - 0.35, 'SSEL', yIn[0] + 0.40)
			s += self._vBox(12.7, yTm - 0.50, xC1, yTm + 0.50, muxedTitle, ['own clock source'])
			s += '\\draw[vflow] (' + P(xTm1) + ', ' + P(yTm) + ') -- (12.7, ' + P(yTm) + ');\n'
			for i, (code, src) in enumerate(sselLegs):
				y = yIn[i]
				if src == 'SMCLK':
					s += ('\\draw[vwire] (' + P(xBar0 + 0.10) + ', ' + P(yS - barH / 2) + ') -- ('
						+ P(xBar0 + 0.10) + ', ' + P(y) + ') -- (' + P(xTm0) + ', ' + P(y) + ');\n')
				elif src == 'MCLK':
					s += ('\\draw[vwire] (' + P(xBar0 - 0.10) + ', ' + P(yM + barH / 2) + ') -- ('
						+ P(xBar0 - 0.10) + ', ' + P(y) + ') -- (' + P(xTm0) + ', ' + P(y) + ');\n')
				else:
					s += ('\\draw[vwire] (' + P(xTm0 - 0.45) + ', ' + P(y) + ') -- (' + P(xTm0) + ', ' + P(y) + ');\n')
					s += '\\node[vlab, anchor=east, inner sep=1pt] at (' + P(xTm0 - 0.50) + ', ' + P(y) + ') {' + fmttex(src) + '};\n'
				s += '\\node[vlab, anchor=west, inner sep=0.5pt] at (' + P(xTm0 + 0.06) + ', ' + P(y) + ') {' + code + '};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('ClockSystemDiagram.tex', s)
		return

	def GenerateTcmApertureDiagram(self):
		'''include/TcmApertureDiagram.tex, one read through a TCM aperture as a
		   left-to-right block diagram: hart 0, the arbiter, the aperture slave,
		   the registered tile boundary, the tile's TCM read port and the TCM,
		   with the core hanging under the port on the SRAM pin mux.
		   Emitted unconditionally; the multi-core chapter inputs it inside its
		   own \\iforchpresent, so a configuration without apertures never
		   renders it and this writes a stub.
		   The mechanism is hdl/common/MCU.vhd (the aperture slave) and
		   hdl/common/hart_tile.vhd (the port, its sequencer and the pin mux).
		   The aperture base and stride are the geometry's, cross-checked by
		   _TcmApertureWindows against the address-space model.'''
		windows = self._TcmApertureWindows()
		if not windows:
			self._writeInclude('TcmApertureDiagram.tex',
				'% This configuration has no TCM apertures (no orchestrator).\n')
			return
		gen = self.Gen
		geo = getattr(gen, 'McuMpGeometry', None) or {}
		tcmKiB = gen.RamMemorySlotSize // 1024
		stride = geo['tcmApertureSize']
		orch = bool(geo.get('orchestrator'))
		P = lambda v: '%.2f' % v

		yB, yT = 2.1, 3.4
		cB, cT = 0.3, 1.3
		xBnd = 9.4
		boxes = [
			(0.0, 1.9, 'hart 0', ['orchestrator' if orch else 'management hart']),
			(2.4, 4.6, 'mp\\_arbiter', ['grant held for the read']),
			(5.1, 7.8, 'aperture slave', ['\\texttt{' + fmthex(windows[0]) + '} $+ h \\times$ \\texttt{'
				+ fmthex(stride) + '}', 'hart 0 only, read only']),
			(11.8, 14.3, 'TCM read port', ['borrows the SRAM port']),
			(14.7, 16.2, 'TCM', [str(tcmKiB) + '\\,KiB']),
		]
		s = '% Generated TCM aperture read path (make chip). Input at natural size.\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm]\n'
		for x0, x1, title, subs in boxes:
			s += self._vBox(x0, yB, x1, yT, title, subs)
		s += self._vBox(11.8, cB, 14.3, cT, 'VestaRV core', ['hart $h$'])
		# the tile boundary, registered
		s += '\\draw[vghost] (' + P(xBnd) + ', 0.0) -- (' + P(xBnd) + ', 4.35);\n'
		s += ('\\node[vlab, anchor=south] at (' + P(xBnd) + ', 4.40) {tile boundary, registered};\n')
		s += '\\node[vlab, anchor=south west, text=black!55] at (0.0, 3.55) {shared fabric, always on};\n'
		s += '\\node[vlab, anchor=south east, text=black!55] at (16.2, 3.55) {inside tile $h$};\n'
		# the read, left to right, and its answer back
		yMid = (yB + yT) / 2.0
		s += ('\\draw[vflow] (1.9, ' + P(yMid) + ') -- (2.4, ' + P(yMid) + ');\n')
		s += ('\\draw[vflow] (4.6, ' + P(yMid) + ') -- (5.1, ' + P(yMid) + ');\n')
		yReq, yRsp = yT - 0.30, yB + 0.30
		s += ('\\draw[vflow] (7.8, ' + P(yReq) + ') -- node[vlab, above] {\\texttt{tcm\\_ext\\_req}, word index} (11.8, '
			+ P(yReq) + ');\n')
		s += ('\\draw[vflow] (11.8, ' + P(yRsp) + ') -- node[vlab, below] {\\texttt{tcm\\_ext\\_done}, the word} (7.8, '
			+ P(yRsp) + ');\n')
		s += ('\\draw[vbus] (14.3, ' + P(yMid) + ') -- (14.7, ' + P(yMid) + ');\n')
		# the SRAM pin mux: the port or the core drives the pins, never both
		s += ('\\draw[vbus] (13.05, ' + P(cT) + ') -- node[vlab, right] {SRAM pin mux} (13.05, ' + P(yB) + ');\n')
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
		'''include/NpuDatapathDiagram.tex is the NPU datapath and the staging RAM it borrows.
		   Emitted unconditionally (the TCM-aperture precedent); a configuration without an NPU gets a stub here and never reaches the \\input.
		   Six boxes: the shared bus, the register file, the port multiplexer, the staging RAM with its three regions, the engine, and the interrupt router.
		   The one RAM port and the two sides that borrow it are the subject, so that path is drawn in the bus style and everything else as a flow.
		   The ownership rule, the one-cycle select registration, the mode list and the activation list are chapter prose and Table t:npu-codes, not text inside the drawing.
		   Every number printed here comes from _NpuFacts, which cross-checks it against the register model, the address map and the RTL.'''
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
		# The mode names are printed short inside the engine box; the full names are in Table t:npu-codes.
		short = {'1-D convolution': '1-D conv', 'XNOR-popcount': 'XNOR'}
		modes = ', '.join(short.get(label, label) for _code, label, _sub, _phrase in self._NPU_MODES)

		# ---- geometry, in cm.
		# The drawing is 14.2 cm wide at natural size, inside the 16.5 cm text block, so nothing scales the 8 pt labels.
		yBus, busH = 7.10, 0.70        # the shared bus, as a bar
		busX0, busX1 = 0.30, 14.50
		xReg, wReg = 2.80, 4.60        # the register file
		yReg, regH = 5.10, 1.30
		xEng, wEng = 2.80, 4.60        # the engine
		yEng, engH = 2.30, 2.00
		xMux, wMux = 7.90, 2.20        # the port multiplexer, on the engine's row
		xRam, wRam = 12.60, 3.80       # the staging RAM
		ramY0, ramY1 = yEng - 1.65, yEng + 1.65
		rowH, rowGap = 0.42, 0.10      # the three regions inside the RAM
		yIrq, irqH = -0.30, 0.80       # the interrupt router

		s = ('% Generated NPU datapath figure: ' + str(kiB) + ' KiB staging RAM at '
			+ fmthex(facts['base']) + ' (' + str(facts['words']) + ' words), think-done vector '
			+ str(vec) + ', ' + Q(facts['xq']) + ' x ' + Q(facts['wq']) + ' into '
			+ Q(facts['aq']) + '\n')
		# No hyphenation anywhere in this figure: a register name split across two lines reads as two identifiers.
		s += '\\begin{tikzpicture}[\n'
		s += '\tnb/.style={execute at begin node={\\hyphenpenalty=10000\\relax}},\n'
		s += '\tblk/.style={vblockw, align=center, font=\\sffamily\\footnotesize, nb},\n'
		s += '\tbar/.style={vbar, align=center, font=\\sffamily\\small\\bfseries},\n'
		s += '\trow/.style={vblock, align=center, font=\\sffamily\\footnotesize, inner sep=1pt},\n'
		s += '\tlab/.style={font=\\sffamily\\footnotesize, align=center, inner sep=1.5pt, fill=white, nb},\n'
		s += '\tsig/.style={vflow},\n'
		s += '\tbus/.style={vbus}]\n'

		# ---- the shared bus every hart reaches the NPU on
		s += ('\\node[bar, minimum width=' + P(busX1 - busX0) + 'cm, minimum height=' + P(busH)
			+ 'cm] (bus) at (' + P((busX0 + busX1) / 2.0) + ', ' + P(yBus) + ') {shared bus, any hart};\n')

		# ---- the register file, and the control it hands the engine
		s += ('\\node[blk, minimum width=' + P(wReg) + 'cm, minimum height=' + P(regH)
			+ 'cm, text width=' + P(wReg - 0.30) + 'cm] (reg) at (' + P(xReg) + ', ' + P(yReg)
			+ ') {\\textbf{\\small registers}\\\\ \\register{NPUCR}, \\register{NPUCFG1}, \\register{NPUCFG2}\\\\'
			+ ' \\register{NPUIVSAR}, \\register{NPUWVSAR}, \\register{NPUOVSAR}};\n')
		s += '\\draw[sig] (' + P(xReg) + ', ' + P(yBus - busH / 2.0) + ') -- (' + P(xReg) + ', ' + P(yReg + regH / 2.0) + ');\n'
		s += '\\draw[sig] (' + P(xReg) + ', ' + P(yReg - regH / 2.0) + ') -- (' + P(xReg) + ', ' + P(yEng + engH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=west, fill=none] at (' + P(xReg + 0.10) + ', '
			+ P((yReg - regH / 2.0 + yEng + engH / 2.0) / 2.0) + ') {mode, counts, pointers};\n')

		# ---- the engine: one sequencer, one MAC, one activation path
		s += ('\\node[blk, minimum width=' + P(wEng) + 'cm, minimum height=' + P(engH)
			+ 'cm, text width=' + P(wEng - 0.30) + 'cm] (eng) at (' + P(xEng) + ', ' + P(yEng)
			+ ') {\\textbf{\\small NPU engine}\\\\ mode sequencer\\\\ \\mbox{' + modes + '}\\\\ MAC '
			+ Q(facts['xq']) + ' $\\times$ ' + Q(facts['wq']) + ' into ' + Q(facts['aq']) + '\\\\ activation};\n')

		# ---- the port multiplexer: the staging window down from the bus, the compute port in from the engine, one port out to the RAM
		s += ('\\node[blk, minimum width=' + P(wMux) + 'cm, minimum height=' + P(regH)
			+ 'cm, text width=' + P(wMux - 0.30) + 'cm] (mux) at (' + P(xMux) + ', ' + P(yEng)
			+ ') {\\textbf{\\small port mux}\\\\ select = \\bitfield{NPUTHINK}};\n')
		s += '\\draw[bus] (' + P(xMux) + ', ' + P(yBus - busH / 2.0) + ') -- (' + P(xMux) + ', ' + P(yEng + regH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=west, fill=none] at (' + P(xMux + 0.10) + ', '
			+ P((yBus - busH / 2.0 + yEng + regH / 2.0) / 2.0) + ') {window \\texttt{' + fmthex(facts['base'])
			+ '} to \\texttt{' + fmthex(facts['last']) + '}};\n')
		s += '\\draw[bus] (' + P(xEng + wEng / 2.0) + ', ' + P(yEng) + ') -- (' + P(xMux - wMux / 2.0) + ', ' + P(yEng) + ');\n'
		s += ('\\node[lab, anchor=south, fill=none] at (' + P((xEng + wEng / 2.0 + xMux - wMux / 2.0) / 2.0) + ', '
			+ P(yEng + 0.06) + ') {compute port};\n')
		s += '\\draw[bus] (' + P(xMux + wMux / 2.0) + ', ' + P(yEng) + ') -- (' + P(xRam - wRam / 2.0) + ', ' + P(yEng) + ');\n'
		s += ('\\node[lab, anchor=south, fill=none] at (' + P((xMux + wMux / 2.0 + xRam - wRam / 2.0) / 2.0) + ', '
			+ P(yEng + 0.06) + ') {one port};\n')

		# ---- the staging RAM: one word array with three regions named by role, not to scale
		s += ('\\draw[vblockw] (' + P(xRam - wRam / 2.0) + ', ' + P(ramY0) + ') rectangle ('
			+ P(xRam + wRam / 2.0) + ', ' + P(ramY1) + ');\n')
		s += ('\\node[lab, fill=none, anchor=north, text width=' + P(wRam - 0.30) + 'cm] at (' + P(xRam) + ', '
			+ P(ramY1 - 0.06) + ') {\\textbf{\\small staging RAM}\\\\ \\texttt{' + fmthex(facts['base'])
			+ '} to \\texttt{' + fmthex(facts['last']) + '}, ' + str(kiB) + ' KiB};\n')
		for i, name in enumerate(['input vector', 'weight matrix', 'output vector']):
			y = ramY0 + 0.20 + rowH / 2.0 + (2 - i) * (rowH + rowGap)
			s += ('\\node[row, minimum width=' + P(wRam - 0.50) + 'cm, minimum height=' + P(rowH)
				+ 'cm] at (' + P(xRam) + ', ' + P(y) + ') {' + name + '};\n')

		# ---- the completion event, as the one interrupt source
		s += ('\\node[blk, minimum width=' + P(wEng) + 'cm, minimum height=' + P(irqH)
			+ 'cm] (irq) at (' + P(xEng) + ', ' + P(yIrq) + ') {\\textbf{\\small IRQROUTER}, vector ' + str(vec) + '};\n')
		s += '\\draw[sig] (' + P(xEng) + ', ' + P(yEng - engH / 2.0) + ') -- (' + P(xEng) + ', ' + P(yIrq + irqH / 2.0) + ');\n'
		s += ('\\node[lab, anchor=west, fill=none] at (' + P(xEng + 0.10) + ', '
			+ P((yEng - engH / 2.0 + yIrq + irqH / 2.0) / 2.0) + ') {think done};\n')

		s += '\\end{tikzpicture}\n'
		self._writeInclude('NpuDatapathDiagram.tex', s)
		return
	def GenerateBootFlowDiagram(self):
		'''include/BootFlowDiagram.tex, the single-ROM boot flow chart: the
		   mhartid dispatch, hart 0's SPI boot on the left, the tile park and
		   the mailbox-row loader on the right, and the MSIP write that joins
		   them.
		   One diamond and seven boxes of at most two lines, one text size, one
		   arrow style, drawn at natural size under the text width.
		   Only hart 0's name follows the orchestrator knob; the flow is the same
		   in both polarities.'''
		N = self.Gen.NumHarts
		orch = bool((getattr(self.Gen, 'McuMpGeometry', None) or {}).get('orchestrator'))
		xL, xR, xC = 2.9, 13.3, 8.1
		s = '% Generated boot flow chart (single-ROM boot, numHarts=' + str(N) + ')\n'
		s += '% Drawn at natural size: the chapter inputs this WITHOUT a \\resizebox.\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm,\n'
		s += '\tstp/.style={vbox, vname, text width=4.9cm, inner sep=4pt},\n'
		s += '\tdec/.style={vbox, vname, diamond, aspect=2.6, inner sep=1pt},\n'
		s += '\tlab/.style={vlab, fill=white, inner sep=1.5pt}]\n'
		s += ('\\node[stp, text width=7.0cm] (rst) at (' + str(xC) + ', 10.4) {\\textbf{Power-on reset}\\\\ all '
			+ str(N) + ' harts fetch the boot ROM at \\texttt{0x0}};\n')
		s += '\\node[dec] (who) at (' + str(xC) + ', 8.7) {\\register{mhartid} $= 0$?};\n'
		s += '\\node[stp] (h0a) at (' + str(xL) + ', 6.9) {\\textbf{Read the BOOT strap}\\\\ set up \\peripheral{GPIO0} and \\peripheral{SPI0}};\n'
		s += '\\node[stp] (h0b) at (' + str(xL) + ', 5.3) {\\textbf{Copy the image from flash}\\\\ to \\texttt{0x8000} to \\texttt{0xFFFC}};\n'
		s += '\\node[stp] (h0c) at (' + str(xL) + ', 3.7) {\\textbf{Jump to \\texttt{\\SpiFlashProgramAddress}}\\\\ the application runs on hart 0};\n'
		s += '\\node[stp] (t1) at (' + str(xR) + ', 6.9) {\\textbf{Set \\texttt{sp}, arm MSIP}\\\\ stack at the top of the TCM};\n'
		s += '\\node[stp] (t2) at (' + str(xR) + ', 5.3) {\\textbf{Park}\\\\ sleep until a software interrupt};\n'
		s += '\\node[stp] (t3) at (' + str(xR) + ', 3.7) {\\textbf{Load SRC, LEN, ENTRY}\\\\ from the mailbox row into the TCM};\n'
		s += '\\node[stp] (t4) at (' + str(xR) + ', 2.1) {\\textbf{Enter ENTRY}\\\\ the tile runs};\n'
		s += '\\draw[vflow] (rst) -- (who);\n'
		yesLab = 'yes: hart 0' + (' (orchestrator)' if orch else '')
		s += '\\draw[vflow] (who.west) -- node[lab] {' + yesLab + '} (h0a.north |- who.west) -- (h0a.north);\n'
		s += '\\draw[vflow] (who.east) -- node[lab] {no: harts 1 to ' + str(N - 1) + '} (t1.north |- who.east) -- (t1.north);\n'
		s += '\\draw[vflow] (h0a) -- (h0b);\n'
		s += '\\draw[vflow] (h0b) -- (h0c);\n'
		s += '\\draw[vflow] (t1) -- (t2);\n'
		s += '\\draw[vflow] (t2) -- (t3);\n'
		s += '\\draw[vflow] (t3) -- (t4);\n'
		# The launch: the application on hart 0 fills a tile's mailbox row and
		# writes its MSIP bit; the tile leaves Park on that interrupt.
		s += ('\\draw[vflow] (h0c.east) -- (' + str(xC) + ', 3.7) -- (' + str(xC)
			+ ', 5.3) -- node[lab, above] {write 1 to \\register{MSIPx}, $x = h$} (t2.west);\n')
		s += '\\end{tikzpicture}\n'
		self._writeInclude('BootFlowDiagram.tex', s)
		return
	def GenerateSyncPrimitiveDecisionTree(self):
		'''include/SyncPrimitiveDecisionTree.tex, which synchronization
		   primitive to use, as a decision tree of three questions and four
		   answers of one line each.
		   Drawn at natural size, about 0.75 of the text width.
		   The rules that apply to every branch are the section's own list.'''
		s = '% Generated synchronization-primitive decision tree\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm,\n'
		s += '\tdec/.style={vbox, vname, diamond, aspect=2.2, inner sep=1pt},\n'
		s += '\tleaf/.style={vbox, vname, execute at begin node={\\hyphenpenalty=10000\\relax}, text width=2.9cm, inner sep=4pt},\n'
		s += '\tyeslab/.style={vlab, pos=0, anchor=south east, xshift=-2pt, yshift=1pt},\n'
		s += '\tnolab/.style={vlab, pos=0, anchor=south west, xshift=2pt, yshift=1pt}]\n'
		s += '\\node[dec] (q1) at (5.0, 7.6) {Single shared word\\\\to update atomically?};\n'
		s += '\\node[leaf] (amo) at (1.6, 5.5) {\\textbf{AMO}\\\\ one word, the arbiter holds the grant};\n'
		s += '\\node[dec] (q2) at (8.5, 5.6) {Guarding a multi-word\\\\critical section?};\n'
		s += '\\node[dec] (q3) at (5.0, 3.5) {Hardware mutex free?\\\\(\\NumMutexes{} in the bank)};\n'
		s += '\\node[leaf] (lrfree) at (11.0, 3.5) {\\textbf{LR/SC retry loop}\\\\ lock-free structures};\n'
		s += '\\node[leaf] (mtx) at (1.8, 1.4) {\\textbf{Hardware mutex}\\\\ preferred};\n'
		s += '\\node[leaf] (lrlock) at (8.2, 1.4) {\\textbf{LR/SC spinlock}\\\\ in shared RAM};\n'
		s += '\\draw[vflow] (q1.west) -- node[yeslab] {yes} (amo.north |- q1.west) -- (amo.north);\n'
		s += '\\draw[vflow] (q1.east) -- node[nolab] {no} (q2.north |- q1.east) -- (q2.north);\n'
		s += '\\draw[vflow] (q2.west) -- node[yeslab] {yes} (q3.north |- q2.west) -- (q3.north);\n'
		s += '\\draw[vflow] (q2.east) -- node[nolab] {no} (lrfree.north |- q2.east) -- (lrfree.north);\n'
		s += '\\draw[vflow] (q3.west) -- node[yeslab] {yes} (mtx.north |- q3.west) -- (mtx.north);\n'
		s += '\\draw[vflow] (q3.east) -- node[nolab] {no} (lrlock.north |- q3.east) -- (lrlock.north);\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('SyncPrimitiveDecisionTree.tex', s)
		return
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
		s += '\tguide/.style={densely dotted, black!35},\n'
		# The waveform cell fills, on the figure theme's three greys: a data
		# cell is the faint one and a don't-care cell is the darker one, so
		# the two never have to be told apart by shape alone.
		s += '\ttiming/d/background/.style={draw=none, fill=black!3},\n'
		s += '\ttiming/u/background/.style={draw=none, fill=black!15},\n'
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
		s += '\\draw[vwire] (0,0) -- (0,\\HR);\n'
		s += '\\draw[densely dashed, black!55] (0,{\\HR*\\CMPTWO}) -- ({\\NPER*\\PER},{\\HR*\\CMPTWO});\n'
		# The count-up ramp is an ordinary signal and is drawn in ink.
		# The vertical fall at the end of each period is the rollover instant.
		# That is the one event this figure exists to show, so it is the accent.
		s += '\\foreach \\k in {0,...,3} {\n'
		s += '\t\\draw[vwire] ({\\k*\\PER},0) -- ({\\k*\\PER+\\PER},{\\HR*\\CMPTWO});\n'
		s += '\t\\draw[vbound] ({\\k*\\PER+\\PER},{\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER},0);\n'
		s += '}\n'
		s += '\\node[lbl] at (0,0) {0};\n'
		s += '\\node[lbl] at (0,{\\HR*\\CMPTWO}) {\\register{TIMxCMP2}};\n'
		s += '\\node[lbl] at (0,\\HR) {$2^{32}-1$ (max)};\n'
		s += '\\node[ann, rotate=90, anchor=south] at (-4.3,{\\HR/2}) {Timer Value};\n'
		s += '\\draw[vbus] (0,-0.45) -- (\\PER,-0.45);\n'
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
		# The TIMxCMP0 crossing is the compare match.
		# That is the one event this figure is about, so the guide that ties it
		# down to the pin edge it causes is the accent stroke.
		# The rollover guide beside it stays a plain grey tick.
		s += '\\foreach \\k in {0,...,3} {\n'
		s += ('\t\\draw[guide, draw=vestaRed, densely dashed, line width=0.7pt] '
			'({\\k*\\PER+1}, {\\HR*\\CMPZERO}) -- ({\\k*\\PER+1}, \\YTWO);\n')
		s += '\t\\draw[guide] ({\\k*\\PER+\\PER}, {\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER}, \\YTWO);\n'
		s += '}\n'
		s += '\\draw[vwire] (0,0) -- (0,\\HR);\n'
		s += '\\draw[densely dashed, black!55] (0,{\\HR*\\CMPTWO}) -- ({\\NPER*\\PER},{\\HR*\\CMPTWO});\n'
		s += '\\draw[densely dashed, black!55] (0,{\\HR*\\CMPZERO}) -- ({\\NPER*\\PER},{\\HR*\\CMPZERO});\n'
		s += '\\foreach \\k in {0,...,3} {\n'
		s += '\t\\draw[vwire] ({\\k*\\PER},0) -- ({\\k*\\PER+\\PER},{\\HR*\\CMPTWO}) -- ({\\k*\\PER+\\PER},0);\n'
		s += '}\n'
		s += '\\node[lbl] at (0,0) {0};\n'
		s += '\\node[lbl, text=vestaRedText] at (0,{\\HR*\\CMPZERO}) {\\register{TIMxCMP0}};\n'
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
		s += '\\draw[vbus] (1,{\\YONE+\\ROWH}) -- (\\PER,{\\YONE+\\ROWH});\n'
		s += '\\node[ann, above] at (2,{\\YONE+\\ROWH+0.02}) {HIGH time};\n'
		s += '\\draw[vbus] (0,{\\YTWO-0.40}) -- (\\PER,{\\YTWO-0.40});\n'
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
		# THE SHADED WINDOW IS A REGION, NOT A GREY BAND. It used to be a
		# full-bleed fill over the two cycles it names, which is the single
		# thing that made these figures read as machine output; it is now the
		# house vghost outline over white paper, which is also what it means:
		# the cycle inside it carries a req that is no longer a request.
		ann += '\\draw[vghost, rounded corners=3pt] (5,\\YTOP) rectangle (6,\\YBOT);\n'
		# THE RED IS THE TRANSACTION. This figure traces exactly one uncontended
		# read, and the span that measures it is the one thing in the drawing
		# that is about that read rather than about the pins, so it is the one
		# red stroke here. That is the grammar the whole-chip figure uses red in.
		ann += '\\draw[vaccent, <->] (1,{\\YBOT-0.45}) -- (4,{\\YBOT-0.45});\n'
		ann += '\\node[ann, below, text=vestaRedText] at (2.5,{\\YBOT-0.47}) {3 \\register{mclk}};\n'
		# THE GHOST NOTE HANGS UNDER THE FIGURE, NOT OFF ITS RIGHT EDGE, AND
		# THAT IS WHAT CENTRES THE FIGURE (2026-08-15, USER: "centred on the
		# page"). \centering centres the tikzpicture's BOUNDING BOX, and this
		# note used to be a ~5 cm block anchored north WEST at x=6.15 — outside
		# the 7 cycles the waveform draws — so the box reached ~4 cm further
		# right than anything visible, and centring the box pushed the visible
		# waveform left of the text block by half of that. The note is now
		# centred on the figure's own mid-cycle on a second annotation row,
		# with a leader dropping from the outlined ghost cycle it describes, so the box
		# is symmetric about the drawing and \centering does what it says.
		# The ghost window is explained in the caption, not in the drawing.
		s = '% Generated mp_arbiter handshake diagram\n'
		# HOUSE THEME, FOR THIS FIGURE ONLY. tikz-timing draws a don't-care cell
		# in a flat 50 percent gray and a bus cell unfilled, which is two more
		# greys than the manual has. The group below puts both on the palette
		# (black!15 and black!3) without leaking the change into the SPI, UART
		# and I2C figures, which are drawn through the same shared helper.
		s += '\\begingroup\n'
		s += '\\tikzset{timing/u/background/.style={draw=none, fill=black!15},\n'
		s += '\t timing/d/background/.style={draw=none, fill=black!3}}%\n'
		s += self._cycleFigure('1.15cm', rows, 6, ann,
			rowH=self._ARB_ROW_H, pitch=self._ARB_ROW_PITCH, fonts=self._ARB_FONTS)
		s += '\\endgroup\n'
		self._writeInclude('ArbiterHandshakeDiagram.tex', s)
		return
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
		# THE STALL WINDOW IS A REGION, NOT A GREY BAND. This used to be a
		# full-bleed fill over two thirds of the figure, which is the single
		# thing that made these drawings read as machine output; it is now the
		# house grouping outline over white paper.
		ann += '\\draw[vregion, draw=black!55] (%d,\\YTOP) rectangle (%d,\\YBOT);\n' % (lat0, lat1 + 1)
		# where an UNSTALLED transaction would have completed: the pick in c1,
		# LATCH in c2, DATA in c3, done in c4 — on the zero s_rdata is holding.
		unst = self._ARB_STALL_REQSEEN + self._ARB_BASE_LATENCY
		ann += '\\draw[black!35] (%d,\\YTOP) -- (%d,{\\YTOP+0.40});\n' % (unst, unst)
		ann += '\\node[ann, above] at (%d,{\\YTOP+0.38}) {unstalled done};\n' % unst
		ann += '\\draw[<->, >=Stealth] (%d,{\\YBOT-0.45}) -- (%d,{\\YBOT-0.45});\n' % (st0, st1 + 1)
		ann += ('\\node[ann, below] at (%.1f,{\\YBOT-0.47}) {tile read, %d \\register{mclk}};\n'
			% ((st0 + st1 + 1) / 2.0, st1 - st0 + 1))
		ann += '\\draw[vaccent, <->] (%d,{\\YBOT-1.25}) -- (%d,{\\YBOT-1.25});\n' % (
			self._ARB_STALL_REQSEEN, self._ARB_STALL_DONE)
		ann += ('\\node[ann, below, text=vestaRedText] at (%.1f,{\\YBOT-1.27}) {%d \\register{mclk}};\n'
			% ((self._ARB_STALL_REQSEEN + self._ARB_STALL_DONE) / 2.0, total))
		s = '%% Generated mp_arbiter stalled-transaction diagram (TCM aperture, window %s)\n' % fmthex(windows[h])
		# HOUSE THEME, FOR THIS FIGURE ONLY, and identical to the handshake
		# figure's group so a row of one still reads like a row of the other.
		# tikz-timing draws a don't-care cell in a flat 50 percent gray and a
		# bus cell unfilled, which is two greys the manual does not have; this
		# puts both on the palette without leaking into the SPI, UART and I2C
		# figures, which come through the same shared helper.
		s += '\\begingroup\n'
		s += '\\tikzset{timing/u/background/.style={draw=none, fill=black!15},\n'
		s += '\t timing/d/background/.style={draw=none, fill=black!3}}%\n'
		s += self._cycleFigure('0.84cm', rows, N - 1, ann,
			rowH=self._ARB_ROW_H, pitch=self._ARB_ROW_PITCH, fonts=self._ARB_FONTS)
		s += '\\endgroup\n'
		self._writeInclude('ArbiterStallDiagram.tex', s)
		return
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
		'''include/SpiFlashDiagram.tex is the SPI connection diagram.
		   It is drawn in the idiom of the UART connection figure.
		   Two on-chip boxes sit inside a thin red package boundary on the left.
		   Their two external partners sit on the right.
		   Each pair is joined by four straight wires, one per pin, each labelled with its pad name.
		   The one fact the figure states with geometry is which pin goes which way.
		   Everything else the old drawing carried (the private flash path, the pad driver select, the hart stall) is prose in the chapter and is not repeated here.

		   The pad names are read out of the package model and checked there.
		   A package that bonds only part of a four-pin group fails the build rather than drawing a partner on a port this package brings out only in part.
		   The number of SPI boxes equals the number of SPIx instances this configuration builds.
		   A configuration without the boot-flash quartet draws SPI0 with generic pin names and no port labels.
		   The figure is emitted unconditionally and the chapter inputs it ungated.'''
		gen = self.Gen
		pkg = gen.Package
		rc = getattr(gen, 'ResolvedConfig', None) or {}

		def P(v):
			return '%.2f' % v

		spis = sorted([p for p in gen.Peripherals if p.Template.NameTemplate == 'SPIx'],
			key=lambda p: p.BaseAddress)
		if not spis:
			raise Exception('SpiFlashDiagram: this configuration instantiates no SPIx '
				'peripheral, but the SPI chapter (and this figure) is emitted for it.')
		wantSpi1 = bool((rc.get('peripherals') or {}).get('spi1', True))
		if len(spis) != (2 if wantSpi1 else 1):
			raise Exception('SpiFlashDiagram: this configuration has peripherals.spi1='
				+ str(wantSpi1) + ' but builds ' + str([p.Name for p in spis]) + ', so the figure '
				'would draw a number of SPI boxes the configuration does not have.')
		spi0, spi1 = spis[0], (spis[1] if len(spis) > 1 else None)

		funcOf = dict((p.FuncName, p) for p in pkg.Pins if p.FuncName is not None)

		def padGroup(names, what):
			'''All of them or none of them.'''
			have = [n for n in names if n in funcOf]
			if have and len(have) != len(names):
				raise Exception('SpiFlashDiagram: this package model bonds ' + str(have)
					+ ' of the ' + what + ' group ' + str(list(names)) + ', so the figure would '
					'draw a partner on a port this package brings out only in part.')
			return list(names) if have else []
		# The wire order is the order a board engineer reads them in: select, clock, out, in.
		flashPads = padGroup(('CS_FLASH', 'SCK0', 'MOSI0', 'MISO0'), 'SPI0 boot-flash')
		spi1Pads = padGroup(('CS1', 'SCK1', 'MOSI1', 'MISO1'), 'SPI1 bus')
		if spi1 is None and spi1Pads:
			raise Exception('SpiFlashDiagram: there is no SPI1 in this configuration but the '
				'package model still bonds ' + str(spi1Pads) + '.')
		xipOn = bool(gen.NativeSpiFlashMemoryReadAccess) and bool(flashPads)

		def padLabel(name):
			'''Port.bit and the function name, as the pinout table prints them.'''
			pin = funcOf.get(name)
			if pin is None or pin.Gpio is None:
				return '\\texttt{' + fmttex(name) + '}'
			port = pin.Gpio.ParentPeripheral
			return ('P' + str(port.GetGPIOPortLabel()) + '.' + str(pin.Gpio.BitNumber)
				+ ' \\texttt{' + fmttex(name) + '}')

		# One entry per port: title, subtitle, partner name, and the four wires.
		# A wire is (label, direction) where direction is 'out' from the chip or 'in' to it.
		ports = []
		if flashPads:
			wires0 = [(padLabel(n), 'in' if n == 'MISO0' else 'out') for n in flashPads]
			partner0 = 'serial boot flash'
		else:
			wires0 = [('\\texttt{CS0}', 'out'), ('\\texttt{SCK0}', 'out'),
				('\\texttt{MOSI0}', 'out'), ('\\texttt{MISO0}', 'in')]
			partner0 = fmttex(spi0.Name) + ' device'
		ports.append({'title': fmttex(spi0.Name),
			'sub': 'master, boot flash' if xipOn else 'master',
			'partner': partner0, 'wires': wires0})
		if spi1 is not None:
			if spi1Pads:
				wires1 = [(padLabel(n), 'in' if n == 'MISO1' else 'out') for n in spi1Pads]
			else:
				wires1 = [('\\texttt{CS1}', 'out'), ('\\texttt{SCK1}', 'out'),
					('\\texttt{MOSI1}', 'out'), ('\\texttt{MISO1}', 'in')]
			ports.append({'title': fmttex(spi1.Name), 'sub': 'master or slave',
				'partner': fmttex(spi1.Name) + ' device', 'wires': wires1})

		# Geometry, in cm.
		# The wire pitch is what sets every height, so the box fits its four wires.
		wireDy, boxPad = 0.50, 0.40
		wBox, wPartner, wireLen = 2.80, 2.90, 3.60
		gapPorts = 0.70
		xBoxL = 0.45
		xBoxR = xBoxL + wBox
		xPartL = xBoxR + wireLen
		xPartR = xPartL + wPartner
		hBox = boxPad + (len(ports[0]['wires']) - 1) * wireDy + boxPad
		hTitle = 0.70

		s = '%% Generated SPI connection diagram (ports=%d, flashPads=%s)\n' % (
			len(ports), str(bool(flashPads)))
		s += '\\begin{tikzpicture}[x=1cm, y=1cm,\n'
		s += '\tpinlab/.style={font=\\sffamily\\footnotesize, inner sep=1.5pt, above},\n'
		s += '\tboxhd/.style={vhd, font=\\sffamily\\footnotesize}]\n'
		yTop = 0.0
		for k, port in enumerate(ports):
			yT = yTop - k * (hTitle + hBox + gapPorts)
			yB = yT - hTitle - hBox
			cx = (xBoxL + xBoxR) / 2.0
			pcx = (xPartL + xPartR) / 2.0
			s += ('\\draw[vblockw] (%s, %s) rectangle (%s, %s);\n'
				% (P(xBoxL), P(yB), P(xBoxR), P(yT)))
			s += ('\\node[boxhd] at (%s, %s) {{\\small\\bfseries %s}\\\\[1pt] %s};\n'
				% (P(cx), P(yT - 0.10), port['title'], port['sub']))
			s += ('\\draw[vblockw] (%s, %s) rectangle (%s, %s);\n'
				% (P(xPartL), P(yB), P(xPartR), P(yT)))
			s += ('\\node[boxhd] at (%s, %s) {{\\small\\bfseries %s}};\n'
				% (P(pcx), P(yT - 0.10), port['partner']))
			for i, (lab, direction) in enumerate(port['wires']):
				y = yT - hTitle - boxPad - i * wireDy
				if direction == 'out':
					s += ('\\draw[vflow] (%s, %s) -- (%s, %s);\n'
						% (P(xBoxR), P(y), P(xPartL), P(y)))
				else:
					s += ('\\draw[vflow] (%s, %s) -- (%s, %s);\n'
						% (P(xPartL), P(y), P(xBoxR), P(y)))
				s += ('\\node[pinlab] at (%s, %s) {%s};\n'
					% (P((xBoxR + xPartL) / 2.0), P(y), lab))
		yBot = yTop - len(ports) * (hTitle + hBox) - (len(ports) - 1) * gapPorts
		# The package boundary is the one red stroke in the figure.
		s += ('\\draw[vbound, rounded corners=3pt] (%s, %s) rectangle (%s, %s);\n'
			% (P(xBoxL - 0.45), P(yBot - 0.45), P(xBoxR + 0.45), P(yTop + 0.45)))
		s += ('\\node[font=\\sffamily\\footnotesize, text=vestaRedText, anchor=south west] '
			'at (%s, %s) {chip boundary};\n' % (P(xBoxL - 0.45), P(yTop + 0.47)))
		s += '\\end{tikzpicture}\n'
		self._writeInclude('SpiFlashDiagram.tex', s)
		return
	def GenerateSpiTimingDiagram(self):
		'''include/SpiTimingDiagram.tex — all four SPI modes. Waveform content is
		   the proven hand-written original; only the styling changed. The two
		   vertical-line families are SEMANTIC (leading vs trailing SCK edge —
		   which one samples depends on CPHA), so they are kept as two
		   distinguishable families rather than flattened to one guide style. The
		   LEADING edge is the one the figure is about, so it is the family drawn
		   in the manual accent colour and the trailing one is a plain grey guide;
		   the red/blue pair it replaces was two saturated colours that belong to
		   no other figure in this manual.'''
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
		# THE ONE GREY PAIR THE WAVEFORM FIGURES SHARE. A bus cell is the light
		# grey of a faint block and an undefined stretch is the ordinary block
		# grey, so the five waveform figures in this manual are shaded out of the
		# same two levels the block diagrams use. tikz-timing's own default for an
		# undefined stretch is a 50 per cent grey, which is darker than anything
		# else printed in this manual.
		cellFills = ('timing/d/background/.style={draw=none, fill=black!3}, '
			'timing/u/background/.style={draw=none, fill=black!15}')
		extra = ''
		extra += '\t\\begin{pgfonlayer}{background}\n'
		extra += '\t\t\\begin{scope}[semithick]\n'
		extra += '\t\t\t\\vertlines[vestaRed, densely dotted]{2.1,4.1,...,17.1}\n'
		extra += '\t\t\t\\vertlines[black!35, densely dashed]{3.1,5.1,...,17.1}\n'
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
		s += self._timingTable(rows, extraOpts='timing/xunit=6.3mm, ' + cellFills,
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
		# THE ONE GREY PAIR THE WAVEFORM FIGURES SHARE. A bus cell is the light
		# grey of a faint block and an undefined stretch is the ordinary block
		# grey, so the five waveform figures in this manual are shaded out of the
		# same two levels the block diagrams use. tikz-timing's own default for an
		# undefined stretch is a 50 per cent grey, which is darker than anything
		# else printed in this manual.
		cellFills = ('timing/d/background/.style={draw=none, fill=black!3}, '
			'timing/u/background/.style={draw=none, fill=black!15}')

		# THE ONE CELL THIS FIGURE IS ABOUT, TRACED IN THE ACCENT COLOUR. Each row
		# is the same data in a different order, and what the reader has to see is
		# where one named cell has MOVED to; a thin accent-coloured rule under
		# that cell in every row draws the staircase it walks. The cell is found
		# by reading the emitted rows back, so it cannot name a cell the figure
		# does not draw, and nothing about the rows themselves changes.
		def traceCell(want):
			out = '\t\\begin{scope}[vestaRed, semithick]\n'
			for n, (label, chars) in enumerate(rows):
				cells = re.findall(r'D\{(.*?)\}', chars)
				if want not in cells:
					raise Exception('%s: row "%s" has no cell "%s" to trace.'
						% ('SpiByteOrderingDiagram', label, want))
				k = cells.index(want)
				out += ('\t\t\\draw (%.2f,%.2f) -- (%.2f,%.2f);\n'
					% (k + 0.15, -n * self._TABLE_ROWDIST - 0.30,
					   k + 0.85, -n * self._TABLE_ROWDIST - 0.30))
			out += '\t\\end{scope}\n'
			return out
		# 9 units; the long row labels ("32-bit transfers, byte swap") take the
		# rest. Cells hold "byte 0", so the unit cannot go much below 13 mm.
		s = '% Generated SPI byte-ordering diagram\n'
		s += self._timingTable(rows, extraOpts='timing/xunit=13.1mm, ' + cellFills,
		                       extracode=traceCell('byte 0'))
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
		# THE ONE GREY PAIR THE WAVEFORM FIGURES SHARE. A bus cell is the light
		# grey of a faint block and an undefined stretch is the ordinary block
		# grey, so the five waveform figures in this manual are shaded out of the
		# same two levels the block diagrams use. tikz-timing's own default for an
		# undefined stretch is a 50 per cent grey, which is darker than anything
		# else printed in this manual.
		cellFills = ('timing/d/background/.style={draw=none, fill=black!3}, '
			'timing/u/background/.style={draw=none, fill=black!15}')

		# THE ONE CELL THIS FIGURE IS ABOUT, TRACED IN THE ACCENT COLOUR. Each row
		# is the same data in a different order, and what the reader has to see is
		# where one named cell has MOVED to; a thin accent-coloured rule under
		# that cell in every row draws the staircase it walks. The cell is found
		# by reading the emitted rows back, so it cannot name a cell the figure
		# does not draw, and nothing about the rows themselves changes.
		def traceCell(want):
			out = '\t\\begin{scope}[vestaRed, semithick]\n'
			for n, (label, chars) in enumerate(rows):
				cells = re.findall(r'D\{(.*?)\}', chars)
				if want not in cells:
					raise Exception('%s: row "%s" has no cell "%s" to trace.'
						% ('SpiBitOrderingDiagram', label, want))
				k = cells.index(want)
				out += ('\t\t\\draw (%.2f,%.2f) -- (%.2f,%.2f);\n'
					% (k + 0.15, -n * self._TABLE_ROWDIST - 0.30,
					   k + 0.85, -n * self._TABLE_ROWDIST - 0.30))
			out += '\t\\end{scope}\n'
			return out
		# 17 units; cells hold at most two digits.
		s = '% Generated SPI bit-ordering diagram (16-bit transfer)\n'
		s += self._timingTable(rows, extraOpts='timing/xunit=7.1mm, ' + cellFills,
		                       extracode=traceCell('0'))
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
		# THE ONE GREY PAIR THE WAVEFORM FIGURES SHARE. A bus cell is the light
		# grey of a faint block and an undefined stretch is the ordinary block
		# grey, so the five waveform figures in this manual are shaded out of the
		# same two levels the block diagrams use. tikz-timing's own default for an
		# undefined stretch is a 50 per cent grey, which is darker than anything
		# else printed in this manual.
		cellFills = ('timing/d/background/.style={draw=none, fill=black!3}, '
			'timing/u/background/.style={draw=none, fill=black!15}')
		# Single-row figure, so the span arrow hangs a fixed distance under row 1
		# and does not depend on the row pitch.
		# THE START BIT IS WHAT THE FIGURE IS ABOUT, so it is the one thing in it
		# drawn in the manual accent colour. The bit-period span already runs from
		# unit 1 to unit 2, which is exactly the start bit's own cell, so the span
		# takes the accent and two thin accent droppers carry its two edges up to
		# the waveform. No waveform is coloured and no text changes.
		extra = ''
		extra += '\t\\begin{scope}[font=' + self._NOTE_FONT + ']\n'
		for xEdge in ('1', '2'):
			extra += ('\t\t\\draw[vestaRed, densely dotted, semithick] (' + xEdge
				+ ',1.15) -- (' + xEdge + ',-1.75);\n')
		extra += '\t\t\\draw[vaccent, <->] (1,-1.75) -- (2,-1.75);\n'
		extra += '\t\t\\node[below, inner sep=2pt] at (1.5,-2.00) {one bit period $=1/\\textrm{baud}$};\n'
		extra += '\t\\end{scope}\n'
		s = '% Generated UART data-frame diagram\n'
		# No yscale here any more: the height comes from _TABLE_YUNIT like every
		# other table figure, and the K/J metachars are written in \yunit so they
		# follow it. 13 units.
		s += self._timingTable(rows,
		                       extraOpts='timing/xunit=10.8mm, ' + cellFills + ', ' + meta,
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
		# THE ONE GREY PAIR THE WAVEFORM FIGURES SHARE. A bus cell is the light
		# grey of a faint block and an undefined stretch is the ordinary block
		# grey, so the five waveform figures in this manual are shaded out of the
		# same two levels the block diagrams use. tikz-timing's own default for an
		# undefined stretch is a 50 per cent grey, which is darker than anything
		# else printed in this manual.
		cellFills = ('timing/d/background/.style={draw=none, fill=black!3}, '
			'timing/u/background/.style={draw=none, fill=black!15}')
		# The bus-condition strip sits a fixed 0.9 units under the SDAx row, and
		# the SDAx row is one _TABLE_ROWDIST under the SCLx row — so this y is
		# DERIVED, not a literal. A hardcoded one slides up onto the waveform the
		# next time the row pitch moves.
		annY = '%.2f' % (-(self._TABLE_ROWDIST + 0.9))
		# THE TWO ACK BITS ARE WHAT THE FIGURE IS ABOUT: they are the only two
		# cells the ADDRESSED DEVICE drives and the only two the master reads
		# back, so they are the one thing in it drawn in the manual accent
		# colour. Each takes the accent text colour and a thin accent leader up
		# to the bottom of its own \pin{SDAx} cell; START and STOP stay black,
		# no waveform is coloured, and no label text changes.
		# The leader's top is the \pin{SDAx} row's own baseline, which is one
		# _TABLE_ROWDIST under row 1 -- derived from the row pitch exactly as
		# annY is, not written as a literal.
		sdaY = '%.2f' % (-self._TABLE_ROWDIST)
		extra = ''
		extra += '\t\\begin{scope}[font=' + self._NOTE_FONT + ']\n'
		for x, text in [('0.8', 'START'), ('9.5', 'ACK'), ('18.5', 'ACK'), ('20.9', 'STOP')]:
			if text == 'ACK':
				extra += ('\t\t\\draw[vestaRed, densely dotted, semithick] (' + x + ','
					+ sdaY + ') -- (' + x + ',' + annY + ');\n')
				extra += ('\t\t\\node[below, inner sep=2pt, text=vestaRedText] at ('
					+ x + ',' + annY + ') {' + text + '};\n')
			else:
				extra += ('\t\t\\node[below, inner sep=2pt] at (' + x + ',' + annY
					+ ') {' + text + '};\n')
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
		                       extraOpts='timing/xunit=6.9mm, ' + cellFills + ', '
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
		# The claim/complete pair is the whole subject, so it is the accent: a
		# dashed red marker at each of the two instants, tied together by the
		# red span that is the masking window between them.
		# This replaced a full-bleed grey band behind the same six units, which
		# is the single thing that made the figure read as machine output.
		ann = ''
		ann += '\\draw[vbound, dashed, line width=0.9pt] (5,\\YTOP) -- (5,{\\YBOT-0.55});\n'
		ann += '\\draw[vbound, dashed, line width=0.9pt] (11,\\YTOP) -- (11,{\\YBOT-0.55});\n'
		ann += '\\draw[vbound, <->, >=Stealth] (5,{\\YBOT-0.55}) -- (11,{\\YBOT-0.55});\n'
		ann += ('\\node[ann, below, text=vestaRedText] at (8,{\\YBOT-0.58}) '
			'{source masked on every hart};\n')
		# The handler note is prose in the IRQROUTER chapter, not text in the drawing.
		s = '% Generated IRQROUTER claim/complete diagram\n'
		# HOUSE GREYS, FOR THIS FIGURE ONLY. tikz-timing fills a don't-care cell
		# in a flat 50 percent gray, which is a grey the manual does not have and
		# which lands as the darkest thing on the page. The group below puts it
		# on the palette without leaking the change into the other figures drawn
		# through the same shared helper.
		s += '\\begingroup\n'
		s += '\\tikzset{timing/u/background/.style={draw=none, fill=black!15}}%\n'
		s += self._cycleFigure('1.05cm', rows, 11, ann)
		s += '\\endgroup\n'
		self._writeInclude('IrqClaimCompleteDiagram.tex', s)
		return
	def GenerateIrqFabricDiagram(self):
		'''include/IrqFabricDiagram.tex is the interrupt fabric of the whole chip.
		   Every peripheral vector enters the IRQROUTER on the left.
		   Inside the router are the per-hart enable rows and the claim/complete stage.
		   One meip wire leaves the router for each hart on the right.
		   The CLINT pair (msip, mtip) goes round the router on its own wires.
		   That bypass is the one fact this figure exists to teach, so it is the one red path in the drawing.

		   Everything printed is derived from the generator.
		   The vector count, the CLINT vector pair, the meip slot and the enable-word names are all read back out of the model and checked.
		   A peripheral added to the vector table moves the total here rather than falling out of the drawing.
		   The hart count follows the configuration, so Argus draws harts 1 to 17 in the second box.'''
		gen = self.Gen
		N = gen.NumHarts
		compat = getattr(gen, 'McuMpCompat', None) or {}
		vecs = list(compat.get('irqVectors') or [])
		if len(vecs) != gen.VectorsCount:
			raise Exception('IrqFabricDiagram: the generator\'s IRQB vector list has '
				+ str(len(vecs)) + ' entries but VectorsCount is ' + str(gen.VectorsCount)
				+ ', so the figure would draw a source population that is not this chip\'s.')

		irqr = clint = None
		for p in gen.Peripherals:
			if p.Name == 'IRQROUTER':
				irqr = p
			if p.Name == 'CLINT':
				clint = p
		if irqr is None or clint is None:
			raise Exception('IrqFabricDiagram: this configuration has '
				+ ('no IRQROUTER' if irqr is None else 'no CLINT')
				+ ', so the interrupt fabric this figure draws does not exist here.')
		msipVec, mtipVec = clint.InterruptPriority, clint.InterruptPriority + 1
		meipVec = gen.MeipVector if gen.MeipVector is not None else gen.VectorsCount
		if vecs[msipVec][0] != 'IRQB_CLINT_MSIP' or vecs[mtipVec][0] != 'IRQB_CLINT_MTIP':
			raise Exception('IrqFabricDiagram: vectors ' + str(msipVec) + '/' + str(mtipVec)
				+ ' are ' + str(vecs[msipVec][0]) + '/' + str(vecs[mtipVec][0])
				+ ', not the CLINT pair the bypass wires are drawn for.')
		# The meip slot is the router's own delivery vector and never a routable source.
		if meipVec < len(vecs) and not vecs[meipVec][0].startswith('IRQB_RSVD'):
			raise Exception('IrqFabricDiagram: the meip slot ' + str(meipVec) + ' is '
				+ str(vecs[meipVec][0]) + ', a live source, and meip cannot be delivered at a '
				'vector some peripheral also pends on.')
		clintVecs = [i for i, (nm, _d) in enumerate(vecs) if nm.startswith('IRQB_CLINT')]
		if clintVecs != [msipVec, mtipVec]:
			raise Exception('IrqFabricDiagram: the CLINT occupies vectors ' + str(clintVecs)
				+ ', not the pair ' + str([msipVec, mtipVec]) + ' the bypass wires are drawn as.')
		routed = gen.VectorsCount - len(clintVecs)

		# The enable rows are transcribed from the register model.
		# generate.py packs one bit per source per hart into as many 32-bit words as the source count needs.
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
				'exactly cover this build\'s ' + str(gen.VectorsCount) + ' vectors, so the drawing '
				'would print a routing row that is too short or one word too long.')
		# The row is printed once with x in place of the hart number.
		rowNames = [re.sub('^H0', 'Hx', nm) for nm in rowsOf[0]]
		rowTxt = '\\register{' + rowNames[0] + '} to \\register{' + rowNames[-1] + '}'
		if len(rowNames) == 1:
			rowTxt = '\\register{' + rowNames[0] + '}'

		def P(v):
			return '%.2f' % v

		# Geometry, in cm.
		# Three columns: sources and CLINT, the router, the harts.
		wSrc, wRtr, wHart = 3.60, 4.90, 2.40
		gapA, gapB = 1.10, 2.30
		xSrcL = 0.30
		xSrcR = xSrcL + wSrc
		xRtrL = xSrcR + gapA
		xRtrR = xRtrL + wRtr
		xHartL = xRtrR + gapB
		xHartR = xHartL + wHart
		xSrcC, xRtrC, xHartC = ((xSrcL + xSrcR) / 2.0, (xRtrL + xRtrR) / 2.0,
			(xHartL + xHartR) / 2.0)
		# The inner boxes of the router set its height.
		hInner, padIn, hHead = 1.05, 0.35, 0.75
		hRtr = hHead + 2 * hInner + 3 * padIn
		yRtrT = 0.0
		yRtrB = yRtrT - hRtr
		yRowsT = yRtrT - hHead - padIn
		yClaimT = yRowsT - hInner - padIn
		# The two hart boxes sit level with the two inner boxes, so meip runs straight.
		hHart = 1.05
		hartBoxes = [('hart 0', yRowsT)]
		if N == 2:
			hartBoxes.append(('hart 1', yClaimT))
		elif N > 2:
			hartBoxes.append(('harts 1 to ' + str(N - 1), yClaimT))
		# The source box sits level with the enable rows it feeds.
		hSrc = 1.25
		ySrcT = yRowsT
		# The CLINT sits under the sources, clear of the router's floor.
		hClint = 1.25
		yClintT = yRtrB - 0.60
		yClintB = yClintT - hClint
		# The bypass lane runs under the router and up the far side of the harts.
		yLane = yClintB + 0.35
		xRail = xHartR + 0.70
		yBot = yClintB - 0.30

		s = ('% Generated interrupt-fabric overview (harts=' + str(N)
			+ ', vectors=' + str(gen.VectorsCount) + ', routed=' + str(routed)
			+ ', meip=' + str(meipVec) + ', msip=' + str(msipVec) + ', mtip=' + str(mtipVec)
			+ ', enableWords=' + str(nWords) + ')\n')
		s += '\\begin{tikzpicture}[x=1cm, y=1cm,\n'
		s += '\thd/.style={vhd, font=\\sffamily\\footnotesize},\n'
		s += '\tbc/.style={vbc, font=\\sffamily\\footnotesize},\n'
		s += '\twlab/.style={font=\\sffamily\\footnotesize, inner sep=1.5pt, fill=white},\n'
		s += '\trlab/.style={font=\\sffamily\\footnotesize, inner sep=1.5pt, fill=white, text=vestaRedText}]\n'

		def frame(xL, yT, w, h, style):
			return ('\\draw[' + style + '] (' + P(xL) + ', ' + P(yT - h) + ') rectangle ('
				+ P(xL + w) + ', ' + P(yT) + ');\n')

		def head(cx, yT, w, title, sub=None):
			tex = '{\\small\\bfseries ' + title + '}'
			if sub:
				tex += '\\\\[1pt] ' + sub
			return ('\\node[hd, text width=' + P(w - 0.30) + 'cm] at (' + P(cx) + ', '
				+ P(yT - 0.12) + ') {' + tex + '};\n')

		# The sources.
		s += frame(xSrcL, ySrcT, wSrc, hSrc, 'vblockw')
		s += head(xSrcC, ySrcT, wSrc, 'peripheral sources',
			str(routed) + ' vectors, 0 to ' + str(gen.VectorsCount - 1))
		s += ('\\draw[vflow] (' + P(xSrcR) + ', ' + P(ySrcT - hSrc / 2.0) + ') -- ('
			+ P(xRtrL) + ', ' + P(ySrcT - hSrc / 2.0) + ');\n')

		# The router and its two stages.
		s += frame(xRtrL, yRtrT, wRtr, hRtr, 'vblockw')
		s += head(xRtrC, yRtrT, wRtr, 'IRQROUTER', 'free-running MCLK')
		s += frame(xRtrL + padIn, yRowsT, wRtr - 2 * padIn, hInner, 'vblockw')
		s += head(xRtrC, yRowsT, wRtr - 2 * padIn, 'per-hart enable rows',
			rowTxt + ', $\\times$' + str(N))
		s += frame(xRtrL + padIn, yClaimT, wRtr - 2 * padIn, hInner, 'vblockw')
		s += head(xRtrC, yClaimT, wRtr - 2 * padIn, '\\register{CLAIM} / \\register{COMPLETE}',
			'lowest pending vector wins')
		s += ('\\draw[vflow] (' + P(xRtrC) + ', ' + P(yRowsT - hInner) + ') -- ('
			+ P(xRtrC) + ', ' + P(yClaimT) + ');\n')

		# The harts and their meip wires.
		for title, yT in hartBoxes:
			cy = yT - hHart / 2.0
			s += frame(xHartL, yT, wHart, hHart, 'vblockw')
			s += head(xHartC, yT, wHart, title)
			s += ('\\draw[vflow] (' + P(xRtrR) + ', ' + P(cy) + ') -- (' + P(xHartL)
				+ ', ' + P(cy) + ');\n')
			s += ('\\node[wlab, above] at (' + P((xRtrR + xHartL) / 2.0) + ', ' + P(cy)
				+ ') {\\texttt{meip}, vector ' + str(meipVec) + '};\n')

		# The CLINT and the one red path: msip and mtip round the router into every hart.
		s += frame(xSrcL, yClintT, wSrc, hClint, 'vblockw')
		s += head(xSrcC, yClintT, wSrc, 'CLINT', 'IPI and timer, per hart')
		yTopRail = hartBoxes[0][1] - hHart / 2.0
		s += ('\\draw[vaccent, -] (' + P(xSrcR) + ', ' + P(yLane) + ') -- (' + P(xRail)
			+ ', ' + P(yLane) + ') -- (' + P(xRail) + ', ' + P(yTopRail) + ');\n')
		for title, yT in hartBoxes:
			cy = yT - hHart / 2.0
			s += ('\\draw[vaccent] (' + P(xRail) + ', ' + P(cy) + ') -- (' + P(xHartR)
				+ ', ' + P(cy) + ');\n')
		s += ('\\node[rlab, anchor=north] at (' + P((xRtrL + xRtrR) / 2.0) + ', '
			+ P(yLane - 0.05) + ') {\\texttt{msip}, \\texttt{mtip}: vectors '
			+ str(msipVec) + ', ' + str(mtipVec) + ', never routed};\n')
		s += '\\end{tikzpicture}\n'
		W = xRail + 0.30
		hAll = 0.50 - yBot
		s = (s.split('\n', 1)[0][:-1] + ', width=' + P(W) + 'cm, height=' + P(hAll)
			+ 'cm)\n' + s.split('\n', 1)[1])
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
		# THE RED IS THE ONE CLAIM THIS FIGURE TRACES. Everything in the drawing
		# turns on a single mclk edge: the one where hart LO's read returns 0,
		# the owner word goes from free to owned, and hart HI's later read is
		# therefore answered with a marker instead. That edge is the figure's
		# only red stroke, drawn in the same grammar the whole-chip figure uses
		# red in, and the bold zero in the note below is coloured with it so the
		# note names the mark rather than sitting beside it.
		ann += '\\draw[vbound, dashed] (3,\\YTOP) -- (3,\\YBOT);\n'
		# What the two results mean is said in the caption, not in the drawing.
		s = '% Generated MUTEX claim/release diagram\n'
		# HOUSE THEME, FOR THIS FIGURE ONLY. tikz-timing draws a don't-care cell
		# in a flat 50 percent gray and a bus cell unfilled, which is two greys
		# the manual does not have; this puts both on the palette (black!15 and
		# black!3) so a hart's idle bus recedes behind the instruction it issues.
		# It is scoped so the SPI, UART and I2C figures, which come through the
		# same shared helper, are untouched.
		s += '\\begingroup\n'
		s += '\\tikzset{timing/u/background/.style={draw=none, fill=black!15},\n'
		s += '\t timing/d/background/.style={draw=none, fill=black!3}}%\n'
		s += self._cycleFigure('1.15cm', rows, 8, ann)
		s += '\\endgroup\n'
		self._writeInclude('MutexClaimDiagram.tex', s)
		return
	def GeneratePowerDomainDiagram(self):
		'''include/PowerDomainDiagram.tex, the chip's power architecture: the
		   always-on domain with hart 0, the shared fabric, pwr_ctrl and the
		   isolation clamps, and one representative switched channel tile under
		   the red domain boundary: the header switch, the tile and its TCM,
		   with the VDD to VDD_SW rail down the column and one control wire from
		   pwr_ctrl to each of the four gates, labelled with the signal name.
		   Six boxes, two text sizes, drawn at natural size.
		   Drawn from the RTL: hdl/common/pwr_ctrl.vhd (the rows 1 to N-1 and
		   the sequencer), mcu_vhd.py emitIsoClamps (the clamps are AND gates on
		   the always-on side), emitTileRstn, tileInstance (tcm_pgen off
		   pd_sleep) and cpf/hart_tile.cpf (the HEADBUF16 switch, no retention).
		   Ungated: tiles 1 to N-1 are gateable on every configuration this
		   manual is built for; only hart 0's wording follows the orchestrator knob.
		   E17: the number of switched tiles the figure claims is cross-checked
		   against the PWRCR register model (PWRGATE mask and the read-only PWRH0).'''
		N = self.Gen.NumHarts
		if N < 2:
			self._writeInclude('PowerDomainDiagram.tex',
				'% numHarts=' + str(N) + ': no switchable tile domains, figure suppressed.\n')
			return
		orch = bool((getattr(self.Gen, 'McuMpGeometry', None) or {}).get('orchestrator'))
		tcmKiB = self.Gen.RamMemorySlotSize // 1024
		P = lambda v: '%.2f' % v

		# ---- E17 cross-check against the register model --------------------
		drawnMask = 0
		for b in range(1, N):
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
			raise Exception('PowerDomainDiagram: this configuration has no PWRCTRL.PWRCR with '
				'PWRGATE/PWRH0 bit fields to check the drawn tile count against.')
		if drawnMask != modelMask:
			raise Exception('PowerDomainDiagram: the figure claims gate bits 0x%X but the '
				'PWRCR register model says 0x%X; the picture and the register table '
				'would disagree.' % (drawnMask, modelMask))
		if not (h0Field.MSB == 0 and h0Field.LSB == 0 and h0Field.Accessibility == 'r'):
			raise Exception('PowerDomainDiagram: PWRH0 is %s bits %d:%d, not a read-only '
				'bit 0, so hart 0 is not the always-on hart this figure draws.'
				% (h0Field.Accessibility, h0Field.MSB, h0Field.LSB))

		# ---- geometry (cm) ------------------------------------------------
		W = 13.4
		xCol0, xCol1 = 3.0, 8.4
		xRail, xSw = 0.5, 1.5
		boxH = 0.95
		yCl, ySw, yTile, yTcm = 4.85, 3.25, 1.90, 0.55
		yBnd = 4.15
		yTop = 8.6
		xA0, xA1, xB0, xB1 = 1.2, 6.4, 8.6, 13.0
		yAB0, yAB1 = 6.35, 7.75
		fan = [9.3, 11.2, 12.0, 12.8]

		s = '% Generated power-domain figure (make chip), one representative switched tile.\n'
		s += '% Input at natural size.\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm]\n'
		# the always-on domain
		s += '\\draw[vregion] (0.0, ' + P(yBnd + 0.20) + ') rectangle (' + P(W) + ', ' + P(yTop) + ');\n'
		s += ('\\node[vgroup, anchor=north east, inner sep=2pt] at (' + P(W - 0.15) + ', ' + P(yTop - 0.05)
			+ ') {always-on domain, \\texttt{VDD}};\n')
		s += self._vBox(xA0, yAB0, xA1, yAB1, 'hart 0 and the shared fabric',
			[('the orchestrator, ' if orch else '') + 'arbiter, boot ROM, shared RAM, peripherals, pad ring'])
		s += self._vBox(xB0, yAB0, xB1, yAB1, '\\texttt{pwr\\_ctrl}',
			['\\peripheral{PWRCTRL} sequencer', '\\register{PWRCR} gate bits'])
		s += self._vBox(xCol0, yCl - boxH / 2, xCol1, yCl + boxH / 2, 'isolation clamps',
			['every tile output held at 0'])
		# the switched domain
		s += '\\draw[vbound] (0.0, ' + P(yTcm - boxH / 2 - 0.30) + ') rectangle (' + P(W) + ', ' + P(yBnd) + ');\n'
		s += ('\\node[vredlab, anchor=north west, inner sep=2pt] at (' + P(xRail + 0.25) + ', ' + P(yBnd - 0.05)
			+ ') {channel tile $h$, one of ' + str(N - 1) + ' (harts 1 to ' + str(N - 1) + ')};\n')
		s += self._vBox(xCol0, ySw - boxH / 2, xCol1, ySw + boxH / 2, '\\texttt{HEADBUF16} power switch',
			['\\texttt{VDD} to \\texttt{VDD\\_SW}'])
		s += self._vBox(xCol0, yTile - boxH / 2, xCol1, yTile + boxH / 2, 'tile $h$: core, CSRs, clock tree',
			['in reset while the rail is off'])
		s += self._vBox(xCol0, yTcm - boxH / 2, xCol1, yTcm + boxH / 2, 'private TCM, ' + str(tcmKiB) + '\\,KiB',
			['no retention'])
		# the rail: VDD down the left into the switch, VDD_SW out of it to the tile and the TCM
		s += '\\node[vlab, anchor=south] at (' + P(xRail) + ', ' + P(yTop - 0.55) + ') {\\texttt{VDD}};\n'
		s += ('\\draw[vwire, thick] (' + P(xRail) + ', ' + P(yTop - 0.55) + ') -- (' + P(xRail) + ', ' + P(ySw)
			+ ') -- (' + P(xCol0) + ', ' + P(ySw) + ');\n')
		xOut = xCol0 + 0.5
		s += ('\\draw[vwire, thick] (' + P(xOut) + ', ' + P(ySw - boxH / 2) + ') -- (' + P(xOut) + ', '
			+ P(yTile + boxH / 2) + ');\n')
		yJ = (ySw - boxH / 2 + yTile + boxH / 2) / 2.0
		s += '\\node[vdot] at (' + P(xOut) + ', ' + P(yJ) + ') {};\n'
		s += ('\\draw[vwire, thick] (' + P(xOut) + ', ' + P(yJ) + ') -- (' + P(xSw) + ', ' + P(yJ) + ') -- ('
			+ P(xSw) + ', ' + P(yTcm) + ') -- (' + P(xCol0) + ', ' + P(yTcm) + ');\n')
		s += ('\\node[vlab, anchor=east] at (' + P(xSw - 0.10) + ', ' + P((yJ + yTcm) / 2.0)
			+ ') {\\texttt{VDD\\_SW}};\n')
		# the four controls, one wire each, nested so none crosses another
		ctl = [(yCl, 'pd\\_iso\\_en'), (ySw, 'pd\\_sleep'), (yTile, 'pd\\_rstn'), (yTcm, 'tcm\\_pgen')]
		for x, (y, name) in zip(fan, ctl):
			s += ('\\draw[vflow] (' + P(x) + ', ' + P(yAB0) + ') -- (' + P(x) + ', ' + P(y) + ') -- ('
				+ P(xCol1) + ', ' + P(y) + ');\n')
			s += ('\\node[vlab, anchor=south west, inner sep=1pt] at (' + P(xCol1 + 0.12) + ', ' + P(y + 0.04)
				+ ') {\\texttt{' + name + '}$(h)$};\n')
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
		# The capture edge is the one event the figure is about, so its tick and
		# its name carry the accent and everything else stays greyscale.
		ann += '\\draw[vbound, dashed, line width=0.9pt] (3,\\YTOP) -- (3,\\YBOT);\n'
		ann += '\\draw[vbound] (3,\\YTOP) -- (3,{\\YTOP+0.35});\n'
		ann += ('\\node[ann, above, text=vestaRedText] at (3,{\\YTOP+0.33}) '
			'{capture edge (\\bitfield{CAP0FE} $=0$: rising)};\n')
		# What the edge does is prose in the TIMER chapter, not text in the drawing.
		s = '% Generated timer input-capture diagram\n'
		# HOUSE GREYS, FOR THIS FIGURE ONLY. tikz-timing fills a don't-care cell
		# in a flat 50 percent gray, which is a grey the manual does not have and
		# which lands as the darkest thing on the page. The group below puts it
		# on the palette without leaking the change into the other figures drawn
		# through the same shared helper.
		s += '\\begingroup\n'
		s += '\\tikzset{timing/u/background/.style={draw=none, fill=black!15}}%\n'
		s += self._cycleFigure('1.20cm', rows, 7, ann)
		s += '\\endgroup\n'
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
	#   ~/work/chip_docs/castalia/d_series/d3_spec.md, d3_cdc_spec.md, d4_spec.md
	# -----------------------------------------------------------------

	def GenerateDebugStackDiagram(self):
		'''include/DebugStackDiagram.tex is the debug path from the probe to the harts.
		   CONFIGURATION-DRIVEN (numHarts).
		   Seven elements: the probe, dtm0, dm0, the arbiter bar, hart 0, the other harts as one box, and the shared RAM with the debug program page.
		   The clock-domain crossing is one thin dashed grey line between dtm0 and dm0, crossed by the two toggles hdl/common/jtag_dtm.vhd:45-63 describes.
		   dm0 reaches the chip two ways: as one more master on mp_arbiter, and over direct halt and resume wires to every hart.
		   The trampoline plant, the raw dmi ports and the bench view are chapter prose, not boxes.'''
		N = self.Gen.NumHarts
		# On an orchestrator configuration hart 0 is the always-on management hart, and its box says so.
		# Same condition the whole-chip figure splits on, so the two figures never disagree about which chip they draw.
		geo = getattr(self.Gen, 'McuMpGeometry', None) or {}
		orch = bool(geo.get('orchestrator')) and bool(self._TcmApertureWindows())

		def P(v):
			return '%.2f' % v

		# ---- geometry, in cm.
		# The drawing is 14.6 cm wide at natural size, inside the 16.5 cm text block, so nothing scales the 8 pt labels.
		yTop, boxH = 6.40, 1.10        # the probe, dtm0 and dm0 row
		xProbe, wProbe = 1.60, 2.60
		xDtm, wDtm = 5.20, 3.20
		xDm, wDm = 10.60, 2.80
		xDtmE = xDtm + wDtm / 2.0
		xDmW = xDm - wDm / 2.0
		xWall = (xDtmE + xDmW) / 2.0   # the clock-domain line
		yReq, yRsp = yTop + 0.28, yTop - 0.28
		yArb, arbH = 3.60, 0.70
		arbX0, arbX1 = 0.30, 13.90
		yLow, lowH = 1.60, 1.20        # the hart and RAM row
		xH0, wH0 = 2.30, 3.20
		xHn, wHn = 6.30, 3.20
		xRam, wRam = 11.50, 4.00
		xTrunk = 14.60                 # the halt and resume wires, around the right edge
		yTrunk = 0.35

		s = '% Generated debug stack block diagram (numHarts=' + str(N) + ')\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tblk/.style={vblockw, align=center, font=\\sffamily\\footnotesize},\n'
		s += '\tbar/.style={vbar, align=center, font=\\sffamily\\small\\bfseries},\n'
		s += '\tlab/.style={font=\\sffamily\\footnotesize, align=center, inner sep=1.5pt, fill=white},\n'
		s += '\tbus/.style={vbus},\n'
		s += '\tsig/.style={vflow}]\n'

		# ---- the top row: the probe, the transport on TCK, the wall, the Debug Module on mclk
		s += '\\node[blk, dashed, minimum width=' + P(wProbe) + 'cm, minimum height=' + P(boxH) + 'cm] (probe) at (' + P(xProbe) + ', ' + P(yTop) + ') {\\textbf{\\small debug probe}\\\\ \\pin{TCK} \\pin{TMS} \\pin{TDI} \\pin{TDO} \\pin{TRSTn}};\n'
		s += '\\node[blk, minimum width=' + P(wDtm) + 'cm, minimum height=' + P(boxH) + 'cm] (dtm) at (' + P(xDtm) + ', ' + P(yTop) + ') {\\textbf{\\small dtm0}\\\\ TAP and DMI transport};\n'
		s += '\\node[blk, minimum width=' + P(wDm) + 'cm, minimum height=' + P(boxH) + 'cm] (dm) at (' + P(xDm) + ', ' + P(yTop) + ') {\\textbf{\\small dm0}\\\\ Debug Module};\n'
		s += '\\draw[bus] (probe.east) -- (dtm.west);\n'
		# The clock-domain line, named once on each side.
		s += '\\draw[vghost] (' + P(xWall) + ', ' + P(yTop - 0.95) + ') -- (' + P(xWall) + ', ' + P(yTop + 1.25) + ');\n'
		s += '\\node[lab, anchor=east, fill=none] at (' + P(xWall - 0.08) + ', ' + P(yTop + 1.10) + ') {\\register{TCK}};\n'
		s += '\\node[lab, anchor=west, fill=none] at (' + P(xWall + 0.08) + ', ' + P(yTop + 1.10) + ') {\\register{mclk}};\n'
		# The two crossings: one toggle each way, named with the width of the payload it carries.
		s += '\\draw[sig] (' + P(xDtmE) + ', ' + P(yReq) + ') -- (' + P(xDmW) + ', ' + P(yReq) + ');\n'
		s += '\\draw[sig] (' + P(xDmW) + ', ' + P(yRsp) + ') -- (' + P(xDtmE) + ', ' + P(yRsp) + ');\n'
		s += '\\node[lab, anchor=south] at (' + P(xWall) + ', ' + P(yReq + 0.05) + ') {\\register{req\\_tgl}, 41 b};\n'
		s += '\\node[lab, anchor=north] at (' + P(xWall) + ', ' + P(yRsp - 0.05) + ') {\\register{rsp\\_tgl}, 34 b};\n'

		# ---- the arbiter bar, with dm0 as one more master on it
		s += '\\node[bar, minimum width=' + P(arbX1 - arbX0) + 'cm, minimum height=' + P(arbH) + 'cm] (arb) at (' + P((arbX0 + arbX1) / 2.0) + ', ' + P(yArb) + ') {mp\\_arbiter};\n'
		s += '\\draw[bus] (' + P(xDm) + ', ' + P(yTop - boxH / 2.0) + ') -- (' + P(xDm) + ', ' + P(yArb + arbH / 2.0) + ');\n'

		# ---- the harts and the shared RAM under the bar
		h0 = '\\textbf{\\small hart 0}\\\\ ' + ('orchestrator, ' if orch else '') + 'core and TCM'
		lows = [(xH0, wH0, h0)]
		if N == 2:
			lows.append((xHn, wHn, '\\textbf{\\small hart 1}\\\\ core and TCM'))
		elif N > 2:
			lows.append((xHn, wHn, '\\textbf{\\small harts 1 to ' + str(N - 1) + '}\\\\ core and TCM each'))
		lows.append((xRam, wRam, '\\textbf{\\small shared RAM}\\\\ debug program page\\\\ \\texttt{0x10680} to \\texttt{0x1087F}'))
		for x, w, body in lows:
			s += '\\node[blk, minimum width=' + P(w) + 'cm, minimum height=' + P(lowH) + 'cm, text width=' + P(w - 0.30) + 'cm] at (' + P(x) + ', ' + P(yLow) + ') {' + body + '};\n'
			s += '\\draw[bus] (' + P(x) + ', ' + P(yLow + lowH / 2.0) + ') -- (' + P(x) + ', ' + P(yArb - arbH / 2.0) + ');\n'

		# ---- the direct halt and resume wires, around the right edge and up into every hart
		hartXs = [x for x, _w, _b in lows[:-1]]
		s += '\\draw[vwire] (dm.east) -- (' + P(xTrunk) + ', ' + P(yTop) + ') -- (' + P(xTrunk) + ', ' + P(yTrunk) + ') -- (' + P(min(hartXs)) + ', ' + P(yTrunk) + ');\n'
		for x in hartXs:
			s += '\\draw[sig] (' + P(x) + ', ' + P(yTrunk) + ') -- (' + P(x) + ', ' + P(yLow - lowH / 2.0) + ');\n'
		s += '\\node[lab, anchor=north] at (' + P((xHn + xTrunk) / 2.0) + ', ' + P(yTrunk - 0.05) + ') {\\register{haltreq} / \\register{resumereq}, \\register{halted} / \\register{unavail}};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugStackDiagram.tex', s)
		return
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
		# Round 3 (2026-08-29): the type comes back UP to 8 pt for every state name and every edge label.
		# The box is sized by Test-Logic-Reset at \footnotesize (about 2.3 cm of type) and the flank channels are 0.45 cm apart, which a single 8 pt digit with a white fill needs.
		# The whole graph is 15.8 cm wide, inside the 16.5 cm text block, so nothing scales it after the fact.
		HW, HH = 1.20, 0.28            # half width / half height of a state box
		TOP = 0.00                     # the top row
		xTLR, xRTI = 0.00, 2.90
		cx = {'dr': 5.90, 'ir': 11.20}
		rows = [-1.05 - 1.15 * k for k in range(6)]         # capture .. update
		yWrapT, yWrapS = 1.10, 1.55    # the two returns over the top
		yRetD, yRetI = rows[5] - 0.75, rows[5] - 1.30       # the two returns along the bottom
		xRiseD, xRiseI = 8.55, 13.90   # the two Update to Select-DR risers

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
		s += '\tst/.style={vblockw, align=center, font=\\sffamily\\footnotesize, inner sep=1pt, minimum width=' + P(2 * HW) + 'cm, minimum height=' + P(2 * HH) + 'cm},\n'
		# Test-Logic-Reset is the entry state and the state the five-ones recovery lands in, so it is the one filled box.
		s += '\ttlr/.style={st, vblock},\n'
		# Two line styles and one head: solid is TMS sampled 0, dashed is TMS sampled 1.
		s += '\ttms0/.style={vflow},\n'
		s += '\ttms1/.style={vflow, dashed},\n'
		s += '\tel/.style={font=\\sffamily\\footnotesize, inner sep=1pt, fill=white}]\n'
		for i, name in enumerate(self._TAP_STATES):
			style = 'tlr' if i == 0 else 'st'
			s += '\\node[' + style + '] (s' + str(i) + ') at (' + P(pos[i][0]) + ', ' + P(pos[i][1]) + ') {' + name + '};\n'

		# Every edge below is one row of TAP_NEXT. `emit' draws the path and
		# then drops the sampled-TMS label at an explicitly chosen point; the
		# TABLE decides what is drawn, the geometry only decides where.
		edges = []

		def emit(src, tms, path, lx, ly, sty=None):
			dst = self._TAP_NEXT[src][tms]
			edges.append((src, dst))
			# `sty' names a style for the one edge that is drawn as the accent;
			# every other edge takes its style from the sampled TMS bit.
			sty = sty or ('tms1' if tms else 'tms0')
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
			s_ += '\\node[el] at (' + P(x + sgn * (HW + 0.50)) + ', ' + P(y + 0.10) + ') {' + str(tms) + '};\n'
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
		# Select-IR on a 1 is the last hop of the five-ones recovery, drawn like every other TMS=1 edge.
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
			xOut = c + sgn * (HW + 1.00)      # Exit2 to Shift, on the outside
			xInA = c - sgn * (HW + 0.50)      # Capture to Exit1, inside, near
			xInB = c - sgn * (HW + 0.95)      # Exit1 to Update, inside, far
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

		# No key and no side paragraph: every edge carries its TMS value, and the five-ones recovery is a sentence in the chapter prose.
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
		# The shift window is a grouping region, so it is a thin dashed outline
		# over the waveform rather than a grey band behind it.
		# The capture/update and edge-sampling explanation is chapter prose beside the figure reference, not text inside the drawing.
		ann += '\\draw[vregion] (3,{\\YTOP}) rectangle (7,{\\YBOT});\n'
		ann += '\\draw[vbus] (3,{\\YBOT-0.45}) -- (7,{\\YBOT-0.45});\n'
		ann += '\\node[ann, below] at (5,{\\YBOT-0.47}) {shift: LSB first, one bit per \\pin{TCK}};\n'
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
		# The one-shot window is a grouping region, so it is a thin dashed
		# outline over the waveform rather than the grey band this figure used
		# to shade behind it.
		ann += '\\draw[vregion] (4,{\\YTOP}) rectangle (6,{\\YBOT});\n'
		# The one bracket the figure keeps: the one-shot valid window.
		ann += '\\draw[vbus] (4,{\\YTOP+0.45}) -- (6,{\\YTOP+0.45});\n'
		ann += '\\node[ann, above] at (5,{\\YTOP+0.47}) {\\register{dmi\\_req\\_valid} high exactly 2 \\register{mclk}};\n'
		# The lockout and idle explanations are chapter prose after the figure, not text inside the drawing.
		# One grey marker for the TCK-side event that starts the transaction.
		ann += '\\draw[vghost, line width=0.6pt] (1,{\\YTOP+0.85}) -- (1,\\YTOP);\n'
		ann += '\\node[ann, anchor=south] at (1,{\\YTOP+0.87}) {Update-DR on \\pin{TCK}};\n'
		# 1.05 cm per cycle: twelve cycles plus the label column fit the 16.5 cm text block with no resizebox.
		s = '% Generated DMI clock-crossing diagram (mclk timebase)\n'
		s += self._cycleFigure('1.05cm', rows, 11, ann)
		self._writeInclude('DmiCrossingDiagram.tex', s)
		return
	def GenerateDebugSwimlaneDiagram(self):
		'''include/DebugSwimlaneDiagram.tex — the twelve numbered steps of the
		   worked halt/read/resume, across the four agents that perform them.
		   The numbers are the list items in the chapter, so the figure and the
		   prose are one document.'''
		# Time runs DOWN the page and the four agents are columns.
		# A portrait swimlane fits the text block at a true 8 pt with no resizebox, where the old landscape one had to be scaled to 6 pt.
		# Every arrow between lanes is orthogonal: down out of a step, across to the next lane, down into the next step.
		laneW, lanePitch = 3.20, 3.55
		laneX = [0.40 + laneW / 2.0 + k * lanePitch for k in range(4)]
		lanes = ['debugger', 'DTM (\\register{TCK})', 'DM', 'hart $h$']
		# (step, lane index, label)
		steps = [
			(1, 0, 'reset TAP, read IDCODE'),
			(2, 0, 'read DTMCS'),
			(3, 1, 'select the \\register{dmi} DR'),
			(4, 2, '\\bitfield{dmactive} $\\leftarrow 1$'),
			(5, 2, '\\bitfield{haltreq}, \\bitfield{hartsel} $= h$'),
			(6, 3, 'halt at a boundary'),
			(7, 2, 'drop \\bitfield{haltreq}'),
			(8, 2, 'clear \\bitfield{cmderr}'),
			(9, 3, 'run the abstract command'),
			(10, 2, 'poll \\bitfield{busy}'),
			(11, 0, 'read \\register{data0}'),
			(12, 3, '\\asminline{dret}, running'),
		]
		rowPitch = 1.05
		yTop = 0.0
		yBot = yTop - rowPitch * (len(steps) - 1)
		s = '% Generated debug halt/read/resume swimlane\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tlane/.style={font=\\sffamily\\small\\bfseries, align=center, anchor=base, text height=1.6ex, text depth=0.4ex},\n'
		s += '\tband/.style={vregion},\n'
		s += '\tstp/.style={vblockw, align=center, font=\\sffamily\\footnotesize, text width=' + '%.2f' % (laneW - 0.40) + 'cm, minimum height=0.62cm, inner sep=2pt, execute at begin node={\\hyphenpenalty=10000\\relax}},\n'
		s += '\tnum/.style={vblock, circle, font=\\sffamily\\footnotesize, inner sep=1.5pt, minimum size=0.44cm},\n'
		s += '\tflow/.style={vflow}]\n'
		# A lane is a grouping region: a thin dashed outline over white paper with its heading above it.
		for k, name in enumerate(lanes):
			x0 = laneX[k] - laneW / 2.0
			s += '\\draw[band] (' + '%.2f' % x0 + ', ' + '%.2f' % (yBot - 0.55) + ') rectangle (' + '%.2f' % (x0 + laneW) + ', ' + '%.2f' % (yTop + 0.55) + ');\n'
			s += '\\node[lane] at (' + '%.2f' % laneX[k] + ', ' + '%.2f' % (yTop + 0.62) + ') {' + name + '};\n'
		prev = None
		for n, li, txt in steps:
			x = laneX[li]
			y = yTop - rowPitch * (n - 1)
			s += '\\node[stp] (p' + str(n) + ') at (' + '%.2f' % x + ', ' + '%.2f' % y + ') {' + txt + '};\n'
			s += '\\node[num] at (' + '%.2f' % (x - (laneW - 0.40) / 2.0 - 0.06) + ', ' + '%.2f' % (y + 0.30) + ') {' + str(n) + '};\n'
			if prev is not None:
				yMid = y + rowPitch / 2.0
				s += '\\draw[flow] (p' + str(prev) + '.south) |- (' + '%.2f' % x + ', ' + '%.2f' % yMid + ') -- (p' + str(n) + '.north);\n'
			prev = n
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DebugSwimlaneDiagram.tex', s)
		return
	def GenerateDmiFieldDiagram(self):
		'''include/DmiFieldDiagram.tex — the 41-bit dmi data register.
		   Field split from hdl/common/jtag_dtm.vhd:222 and :573-575:
		   op(1 downto 0), data(33 downto 2), address(40 downto 34). Widths are
		   drawn for legibility, not to scale -- the bit numbers carry the
		   truth, and saying so in the caption is cheaper than a 41-cell bar.'''
		# The fourth column names the style each field is drawn in.
		# op is the emphasised one because it goes in and comes out first and carries the command in and the status out.
		# The shift order and the op codes are prose in the chapter, next to the figure reference, not text inside the drawing.
		fields = [
			(3.4, '\\register{address}', '40:34', '7 bits: the DMI address', 'fld'),
			(6.4, '\\register{data}', '33:2', '32 bits: read result or write value', 'fld'),
			(2.6, '\\register{op}', '1:0', '2 bits: command in, status out', 'fldem'),
		]
		s = '% Generated 41-bit DMI data-register field bar\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tfld/.style={vblockw, align=center, font=\\sffamily\\small, minimum height=1.0cm},\n'
		s += '\tfldem/.style={fld, vblock},\n'
		s += '\tbit/.style={font=\\sffamily\\footnotesize, inner sep=1pt},\n'
		s += '\tnote/.style={vbc, font=\\sffamily\\footnotesize}]\n'
		x = 0.0
		for w, name, bits, desc, sty in fields:
			cx = x + w / 2.0
			s += '\\node[' + sty + ', minimum width=' + '%.2f' % w + 'cm] at (' + '%.2f' % cx + ', 0) {' + name + '};\n'
			s += '\\node[bit, anchor=south west] at (' + '%.2f' % x + ', 0.52) {' + bits.split(':')[0] + '};\n'
			s += '\\node[bit, anchor=south east] at (' + '%.2f' % (x + w) + ', 0.52) {' + bits.split(':')[1] + '};\n'
			s += '\\node[note, anchor=north] at (' + '%.2f' % cx + ', -0.55) {' + desc + '};\n'
			x += w
		s += '\\end{tikzpicture}\n'
		self._writeInclude('DmiFieldDiagram.tex', s)
		return
	def GeneratePackagePinoutDiagram(self):
		'''include/PackagePinoutDiagram.tex, the fully labelled package top
		   view, derived from the same package model as config/PadRing.json.
		   The body is drawn to a pitch chosen so the whole figure lands at
		   about the text width at natural size, which keeps every pin label a
		   true 8 pt on the page; the physical dimensions are in the caption.'''
		pkg = self.Gen.Package
		pitchMm = float(pkg.PinPitch)
		pwMm = float(pkg.PinWidth)
		pdMm = float(pkg.PinDepth)
		sideCount = {'W': 0, 'S': 0, 'E': 0, 'N': 0}
		for pin in pkg.Pins:
			sideCount[pin.Side] += 1
		nSide = max(sideCount.values())

		def pinLabel(pin):
			if pin.NoConnect:
				return '\\textit{\\color{black!55}NC}'
			name = fmttex(pin.Name)
			if pin.FuncName is not None:
				name += '\\,/\\,' + fmttex(pin.FuncName)
			if pin.IsPowerDomainPin:
				return '\\textbf{' + name + '}'
			return name

		# The widest label on either vertical side sets the room the labels
		# need; the pin band then takes what is left of the text width.
		labW = 0.0
		for pin in pkg.Pins:
			labW = max(labW, self._vTextWidth(pinLabel(pin), 'footnotesize', pin.IsPowerDomainPin))
		textW = 16.4
		pitch = min(0.50, max(0.34, (textW - 2 * (labW + 0.30)) / (nSide + 3.5)))
		pw = pwMm / pitchMm * pitch
		pd = pdMm / pitchMm * pitch
		half = (nSide + 3.5) * pitch / 2.0

		s = '% Generated package pinout (derived from the package model; see config/PadRing.json)\n'
		s += '% Drawn to a pitch of ' + '%.3f' % pitch + ' cm so the figure lands at the text width.\n'
		s += '\\begin{tikzpicture}[x=1cm, y=1cm,\n'
		s += '\tpin/.style={vbox, rounded corners=0.4pt},\n'
		s += '\tpwr/.style={pin, fill=black!15},\n'
		s += '\tnum/.style={vlab},\n'
		s += '\tlab/.style={vlab, inner sep=1.5pt},\n'
		s += '\tctr/.style={vname}]\n'
		# The package body is a boundary, so it is drawn in the one colour this
		# manual reserves for boundaries, and its name is that boundary's label.
		s += '\\draw[vbound] (' + '%.3f' % -half + ',' + '%.3f' % -half + ') rectangle (' + '%.3f' % half + ',' + '%.3f' % half + ');\n'
		s += ('\\node[ctr] at (0,0) {\\textcolor{vestaRedText}{\\textbf{\\AsicNameForUserGuide}}\\\\ '
			+ pkg.PackageType + '-' + str(pkg.PinCount) + ', top view\\\\ {\\footnotesize '
			+ str(pkg.Dimensions[0]) + '$\\times$' + str(pkg.Dimensions[1]) + '\\,' + pkg.Units + ', '
			+ str(pkg.PinPitch) + '\\,' + pkg.Units + ' pitch}};\n')
		s += '\\fill[vestaInk] (' + '%.3f' % (-half + 0.55) + ',' + '%.3f' % (half - 0.55) + ') circle (0.09);\n'

		sideIdx = {'W': 0, 'S': 0, 'E': 0, 'N': 0}
		for pin in pkg.Pins:
			n = sideCount[pin.Side]
			j = sideIdx[pin.Side]
			sideIdx[pin.Side] += 1
			box = 'pwr' if pin.IsPowerDomainPin else 'pin'
			if pin.Side == 'W':
				y = ((n - 1) / 2.0 - j) * pitch
				s += '\\draw[' + box + '] (' + '%.3f' % (-half - 0.001) + ',' + '%.3f' % (y - pw / 2) + ') rectangle (' + '%.3f' % (-half + pd) + ',' + '%.3f' % (y + pw / 2) + ');\n'
				s += '\\node[num, anchor=west] at (' + '%.3f' % (-half + pd + 0.06) + ',' + '%.3f' % y + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[lab, anchor=east] at (' + '%.3f' % (-half - 0.12) + ',' + '%.3f' % y + ') {' + pinLabel(pin) + '};\n'
			elif pin.Side == 'S':
				xq = (j - (n - 1) / 2.0) * pitch
				s += '\\draw[' + box + '] (' + '%.3f' % (xq - pw / 2) + ',' + '%.3f' % (-half - 0.001) + ') rectangle (' + '%.3f' % (xq + pw / 2) + ',' + '%.3f' % (-half + pd) + ');\n'
				s += '\\node[num, anchor=west, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (-half + pd + 0.06) + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[lab, anchor=east, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (-half - 0.12) + ') {' + pinLabel(pin) + '};\n'
			elif pin.Side == 'E':
				y = (j - (n - 1) / 2.0) * pitch
				s += '\\draw[' + box + '] (' + '%.3f' % (half - pd) + ',' + '%.3f' % (y - pw / 2) + ') rectangle (' + '%.3f' % (half + 0.001) + ',' + '%.3f' % (y + pw / 2) + ');\n'
				s += '\\node[num, anchor=east] at (' + '%.3f' % (half - pd - 0.06) + ',' + '%.3f' % y + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[lab, anchor=west] at (' + '%.3f' % (half + 0.12) + ',' + '%.3f' % y + ') {' + pinLabel(pin) + '};\n'
			else:
				xq = ((n - 1) / 2.0 - j) * pitch
				s += '\\draw[' + box + '] (' + '%.3f' % (xq - pw / 2) + ',' + '%.3f' % (half - pd) + ') rectangle (' + '%.3f' % (xq + pw / 2) + ',' + '%.3f' % (half + 0.001) + ');\n'
				s += '\\node[num, anchor=east, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (half - pd - 0.06) + ') {' + str(pin.PackagePinNumber) + '};\n'
				s += '\\node[lab, anchor=west, rotate=90] at (' + '%.3f' % xq + ',' + '%.3f' % (half + 0.12) + ') {' + pinLabel(pin) + '};\n'
		s += '\\end{tikzpicture}\n'
		self._writeInclude('PackagePinoutDiagram.tex', s)
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
				s += '\\textit{NC} & - & - & - \\\\\n'
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
					s += '- & '

				if len(pin.FuncName) > 0:
					s += '\\pin{' + fmttex(pin.FuncName) + '} & '
				else:
					s += '- & '

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
	

	# -----------------------------------------------------------------
	# Register description format (TRM standard, section 4) and the
	# per-peripheral generated tables (section 5).
	# Everything below emits self-contained LaTeX.
	# The only theme dependencies are the tablehighlightcolor colour and the
	# ltablex package, both of which the packages file has carried for years.
	# -----------------------------------------------------------------

	# Flip this to True once every field carries a description.
	# While it is False an empty description prints a WARNING and the build continues.
	# Chapter titles read as a long name followed by the acronym, the way every vendor manual titles a peripheral chapter.
	# A PeripheralTemplate may carry its own LongName attribute; this table is the fallback keyed by the template name.
	_PERIPHERAL_LONG_NAMES = {
		'CLINT': 'Core-local interruptor',
		'DMAx': 'Direct memory access controller',
		'EVFAB': 'Event fabric',
		'GPIOx': 'General-purpose input and output',
		'I2CTx': 'I2C target',
		'I2Cx': 'Inter-integrated circuit interface',
		'I3Cx': 'Improved inter-integrated circuit interface',
		'IRQROUTER': 'Interrupt router',
		'MUTEX': 'Hardware mutexes',
		'NFCx': 'Near-field communication interface',
		'NPU': 'Neural processing unit',
		'OWx': '1-Wire interface',
		'PCT': 'Pin control',
		'PWMx': 'Pulse-width modulator',
		'PWRCTRL': 'Power control',
		'QSPIx': 'Quad serial peripheral interface',
		'RTCx': 'Real-time clock',
		'SPIx': 'Serial peripheral interface',
		'SYSTEM': 'System control',
		'TIMERx': 'Timer',
		'TRNGx': 'True random number generator',
		'UARTx': 'Universal asynchronous receiver and transmitter',
	}
	EMPTY_FIELD_DESCRIPTION_IS_ERROR = True

	# Plain-English meaning of every accessibility code BitField.py accepts.
	# The accepted set itself is read out of BitField.py at build time, and a
	# code that has no entry here fails the build, so the legend cannot drift.
	_ACCESS_LEGEND = {
		'rw': ('Read/write', 'Returns the current value.', 'Sets the field to the written value.'),
		'r': ('Read only', 'Returns the current value.', 'Ignored.'),
		'r0': ('Reserved, reads zero', 'Returns 0.', 'Ignored. Write 0.'),
		'r1': ('Reserved, reads one', 'Returns 1.', 'Ignored. Write 1.'),
		'rw0': ('Read, write 0 to act', 'Returns the current value.', 'A 0 in a bit position acts on that bit; a 1 leaves it unchanged.'),
		'rw1': ('Read, write 1 to act', 'Returns the current value.', 'A 1 in a bit position acts on that bit (clears a flag, or applies the register\'s set, clear or toggle operation); a 0 leaves it unchanged.'),
		'w': ('Write only', 'Not defined by this manual.', 'Sets the field to the written value.'),
		'w0': ('Write 0 to trigger', 'Not defined by this manual.', 'A 0 triggers the action; a 1 has no effect.'),
		'w1': ('Write 1 to trigger', 'Not defined by this manual.', 'A 1 triggers the action (a command strobe); a 0 has no effect.'),
	}

	def _AcceptedAccessCodes(self):
		'''The accessibility strings BitField.py validates against, read from its source.'''
		path = os.path.join(self.ThisFileDirectory, 'BitField.py')
		with open(path) as f:
			src = f.read()
		m = re.search(r'a\s+in\s+\[([^\]]*)\]', src)
		if m is None:
			raise Exception('AccessLegend: could not find the accepted accessibility list in ' + path)
		codes = re.findall(r"'([^']+)'", m.group(1))
		if len(codes) < 1:
			raise Exception('AccessLegend: the accepted accessibility list in ' + path + ' is empty')
		return codes

	def GenerateAccessLegend(self):
		'''include/AccessLegend.tex: the register access-type legend for the front matter.'''
		codes = self._AcceptedAccessCodes()
		for c in codes:
			if c not in self._ACCESS_LEGEND:
				raise Exception('AccessLegend: BitField.py accepts accessibility "' + c + '" but LatexUserGuide._ACCESS_LEGEND has no entry for it')
		s = self._TablePreamble()
		s += '\\begin{tabularx}{\\textwidth}{ l l X X }\n'
		s += '\\caption{Register access types} \\label{t:access-types} \\\\\n'
		s += '\\hline \\textbf{Type} & \\textbf{Meaning} & \\textbf{Read effect} & \\textbf{Write effect} \\\\ \\hline \\endfirsthead\n'
		s += '\\hline \\textbf{Type} & \\textbf{Meaning} & \\textbf{Read effect} & \\textbf{Write effect} \\\\ \\hline \\endhead\n'
		s += '\\hline \\endfoot\n'
		s += '\\hline \\endlastfoot\n'
		for i, c in enumerate(codes):
			meaning, rd, wr = self._ACCESS_LEGEND[c]
			if i % 2 == 1:
				s += '\\rowcolor{tablehighlightcolor} '
			s += '\\texttt{' + fmttex(c) + '} & ' + fmttex(meaning) + ' & ' + fmttex(rd) + ' & ' + fmttex(wr) + ' \\\\\n'
		s += '\\end{tabularx}\n'
		self._writeInclude('AccessLegend.tex', s)
		return

	def _TablePreamble(self):
		'''Guarded definitions every generated table file can rely on, whatever the template carries.'''
		return ('\\ifdefined\\FloatBarrier\\else\\providecommand{\\FloatBarrier}{}\\fi\n'
			# Under the article class (before the template moves to report) a chapter is a section.
			# The chapter counter exists only in the report and book classes, so it is the reliable test.
			'\\makeatletter\\ifdefined\\c@chapter\\else\\let\\chapter\\section\\fi\\makeatother\n'
			'\\providecommand{\\peripheral}[1]{\\texttt{#1}}\n'
			'\\providecommand{\\register}[1]{\\texttt{#1}}\n'
			'\\providecommand{\\bitfield}[1]{\\texttt{#1}}\n'
			'\\providecommand{\\pin}[1]{\\texttt{#1}}\n')

	# ---- small formatting helpers ------------------------------------

	def _FieldValueString(self, value, size):
		'''Binary for fields of four bits or fewer, hex (plus decimal) above that, a bare digit for one bit.'''
		if size == 1:
			return str(value)
		if size <= 4:
			return fmtbin(value, minDigits=size, usePrefix=True)
		digits = (size + 3) // 4
		return fmthex(value, minDigits=digits) + ' (' + str(value) + ')'

	def _FieldResetString(self, value, size):
		'''Like the value string, but without the decimal echo, which is noise in a reset column.'''
		if size == 1:
			return str(value)
		if size <= 4:
			return fmtbin(value, minDigits=size, usePrefix=True)
		return fmthex(value, minDigits=(size + 3) // 4)

	def _RegisterResetString(self, rt, size):
		return fmthex(rt.ResetValue if rt.ResetValue is not None else 0, minDigits=max(2, (size + 3) // 4))

	def _SentenceCount(self, text):
		return len(re.findall(r'[.!?](?:\s|$)', text.strip()))

	def _ShortTitle(self, description):
		'''The first sentence of a description when it is short enough to serve as a heading, else None.'''
		d = description.strip()
		if len(d) < 1:
			return None
		m = re.match(r'(.+?)(?:\.\s|\.$|$)', d)
		first = m.group(1).strip() if m else d
		if len(first) > 72 or '\n' in first:
			return None
		return first

	def _AccessSummary(self, fields):
		order = ['rw', 'r', 'rw1', 'rw0', 'w', 'w1', 'w0', 'r1', 'r0']
		seen = []
		for bf in fields:
			if bf.Unused:
				continue
			if bf.Accessibility not in seen:
				seen.append(bf.Accessibility)
		if len(seen) < 1:
			return 'r0'
		seen.sort(key=lambda a: order.index(a) if a in order else len(order))
		return '/'.join(seen)

	def _BitFieldDisplayName(self, pt, name):
		if type(pt.BitFieldPrefix) == str and name.startswith(pt.BitFieldPrefix) and len(name) > len(pt.BitFieldPrefix):
			return name[len(pt.BitFieldPrefix):]
		return name

	def _RangesString(self, numbers):
		'''Sorted integers as "1 to 8, 12, 16 to 21" without dashes.'''
		nums = sorted(set(numbers))
		parts = []
		i = 0
		while i < len(nums):
			j = i
			while (j + 1) < len(nums) and nums[j + 1] == nums[j] + 1:
				j += 1
			if j > i:
				parts.append(str(nums[i]) + ' to ' + str(nums[j]))
			else:
				parts.append(str(nums[i]))
			i = j + 1
		return ', '.join(parts)

	# ---- register arrays (standard 4.4) ------------------------------

	def _Templatize(self, strings, indices):
		'''One string with every varying decimal index replaced by n, or None when the strings do not differ by the index alone.
		   Each string is split into digit runs and the text between them; the text must agree everywhere,
		   and every digit run is either the same in all members or equal to that member's index.'''
		if all(s == strings[0] for s in strings):
			return strings[0]
		tokens = [re.split(r'(\d+)', s) for s in strings]
		n = len(tokens[0])
		if any(len(t) != n for t in tokens):
			return None
		out = []
		for pos in range(n):
			col = [t[pos] for t in tokens]
			if pos % 2 == 0:
				if any(c != col[0] for c in col):
					return None
				out.append(col[0])
			elif all(c == col[0] for c in col):
				out.append(col[0])
			elif all(c == str(i) for c, i in zip(col, indices)):
				out.append('n')
			else:
				return None
		return ''.join(out)

	def _FieldSignature(self, bf):
		return (bf.MSB, bf.LSB, bf.Accessibility, bf.ResetValue, bf.Unused, tuple(v[0] for v in bf.ValueDescriptions))

	def _TryRegisterArray(self, members):
		'''members: list of (index, rt) with the same name key. Returns the array record or None.'''
		members = sorted(members, key=lambda m: m[0])
		idx = [m[0] for m in members]
		rts = [m[1] for m in members]
		if len(rts) < 2:
			return None
		for k in range(1, len(idx)):
			if idx[k] != idx[k - 1] + 1:
				return None
		stride = rts[1].Offset - rts[0].Offset
		if stride <= 0:
			return None
		for k in range(1, len(rts)):
			if rts[k].Offset - rts[k - 1].Offset != stride:
				return None
		if any(rt.Size != rts[0].Size for rt in rts):
			return None
		nf = len(rts[0].BitFields)
		if any(len(rt.BitFields) != nf for rt in rts):
			return None
		for f in range(nf):
			sig = self._FieldSignature(rts[0].BitFields[f])
			if any(self._FieldSignature(rt.BitFields[f]) != sig for rt in rts):
				return None
		# Every piece of text must differ by the index alone.
		desc = self._Templatize([rt.Description for rt in rts], idx)
		if desc is None:
			return None
		fields = []
		for f in range(nf):
			bfs = [rt.BitFields[f] for rt in rts]
			name = self._Templatize([bf.Name for bf in bfs], idx)
			fdesc = self._Templatize([bf.Description for bf in bfs], idx)
			if name is None or fdesc is None:
				return None
			vds = []
			for v in range(len(bfs[0].ValueDescriptions)):
				vname = self._Templatize([bf.ValueDescriptions[v][2] for bf in bfs], idx)
				vdesc = self._Templatize([bf.ValueDescriptions[v][1] for bf in bfs], idx)
				if vname is None or vdesc is None:
					return None
				vds.append((bfs[0].ValueDescriptions[v][0], vdesc, vname))
			fields.append((bfs[0], name, fdesc, vds))
		return {'indices': idx, 'members': rts, 'stride': stride, 'description': desc, 'fields': fields}

	def _RegisterBlocks(self, pt):
		'''The registers of a peripheral template as an ordered list of blocks.
		   A block is either a single register template or a detected array of them.'''
		candidates = {}
		for rt in pt.RegisterTemplates:
			for m in re.finditer(r'\d+', rt.NameTemplate):
				key = rt.NameTemplate[:m.start()] + 'n' + rt.NameTemplate[m.end():]
				candidates.setdefault(key, []).append((int(m.group(0)), rt))
		used = set()
		arrays = {}
		for key in candidates:
			members = [(i, rt) for (i, rt) in candidates[key] if id(rt) not in used]
			arr = self._TryRegisterArray(members)
			if arr is None:
				continue
			arr['name'] = key
			for rt in arr['members']:
				used.add(id(rt))
			arrays[id(arr['members'][0])] = arr
		blocks = []
		for rt in pt.RegisterTemplates:
			if id(rt) in arrays:
				blocks.append(arrays[id(rt)])
			elif id(rt) not in used:
				blocks.append({'name': rt.NameTemplate, 'members': [rt], 'indices': None, 'stride': 0,
					'description': rt.Description,
					'fields': [(bf, bf.Name, bf.Description, list(bf.ValueDescriptions)) for bf in rt.BitFields]})
		return blocks

	def _BlockLabel(self, pt, block):
		return 'reg:' + pt.NameTemplate.replace('_', '') + ':' + block['name'].replace('_', '')

	def _BlockHeadingName(self, block):
		if block['indices'] is None:
			return block['name']
		return block['name'] + ' (n = ' + str(block['indices'][0]) + '..' + str(block['indices'][-1]) + ')'

	def _BlockOffsetString(self, block):
		first = block['members'][0]
		if block['indices'] is None:
			return fmthex(first.Offset, minDigits=2)
		base = first.Offset - block['indices'][0] * block['stride']
		return fmthex(base, minDigits=2) + ' + ' + str(block['stride']) + 'n'

	def _BlockSize(self, pt, block):
		'''The widest instance size of the block's first register, so a GPIO port widened per instance is honoured.'''
		rt = block['members'][0]
		sizes = []
		for p in self.Gen.Peripherals:
			if p.Template is not pt:
				continue
			for r in p.Registers:
				if r.Template is rt:
					sizes.append(r.Size)
		# The instances are the truth: a GPIO port template is declared 32 bits wide and narrowed per instance.
		if len(sizes) > 0:
			return max(sizes)
		return rt.Size

	# ---- pins and vectors per peripheral -----------------------------

	def _FunctionOwner(self, name, description, peripheralHint):
		'''The peripheral instance a pin function belongs to, or None.
		   An explicit hint on the model wins; otherwise the function's description names its instance.'''
		if peripheralHint is not None:
			for p in self.Gen.Peripherals:
				if p.Name == peripheralHint:
					return p
		if name is None or len(name) < 1:
			return None
		best = None
		for p in self.Gen.Peripherals:
			if re.match(re.escape(p.Name) + r'(?![A-Za-z0-9])', description or ''):
				if best is None or len(p.Name) > len(best.Name):
					best = p
		return best

	def _PeripheralSignals(self, p):
		'''[(signalName, ioType, description, [(portLabel, afIndex), ...])] for one instance.'''
		sig = {}
		order = []
		for g in self.Gen.Peripherals:
			if not g.IsGPIO():
				continue
			for pin in g.Pins:
				if pin.NoConnect:
					continue
				label = 'P' + g.GetGPIOPortLabel() + '.' + str(pin.BitNumber)
				funcs = [(pin.FuncName, pin.FuncIOType, pin.Description, 0, getattr(pin, 'Peripheral', None))]
				for af in pin.AltFuncs:
					funcs.append((af.Name, af.IOType, getattr(af, 'Description', ''), af.Index, getattr(af, 'Peripheral', None)))
				for (name, io, desc, afIdx, hint) in funcs:
					if name is None or len(name) < 1:
						continue
					if self._FunctionOwner(name, desc, hint) is not p:
						continue
					if name not in sig:
						sig[name] = [io, desc, []]
						order.append(name)
					elif afIdx == 0:
						sig[name][1] = desc
					sig[name][2].append((label, afIdx))
		out = []
		for name in order:
			io, desc, locs = sig[name]
			out.append((name, io, desc, locs))
		return out

	def _CleanFunctionDescription(self, desc):
		d = re.sub(r'\s*\((?:second |third )?alternate location\)', '', desc or '')
		d = re.sub(r'\s*\(alt plane AF\d\)', '', d)
		return d.strip()

	def _IoTypeWord(self, io):
		return {'I': 'Input', 'O': 'Output', 'IO': 'Bidirectional'}.get(io or '', '')

	def _VectorOwners(self):
		'''One peripheral (or None) per interrupt vector, from the generator's vector list.'''
		compat = getattr(self.Gen, 'McuMpCompat', None) or {}
		vecs = list(compat.get('irqVectors') or [])
		owners = []
		byFirst = {}
		for p in self.Gen.Peripherals:
			if p.InterruptPriority is not None:
				byFirst[p.InterruptPriority] = p
		for v, (name, desc) in enumerate(vecs):
			token = name[len('IRQB_'):].split('_')[0] if name.startswith('IRQB_') else name
			owner = None
			if v in byFirst:
				owner = byFirst[v]
			elif not token.startswith('RSVD'):
				exact = [p for p in self.Gen.Peripherals if p.Name == token]
				if len(exact) == 1:
					owner = exact[0]
				else:
					m = re.match(r'([A-Za-z]+)(\d*)$', token)
					if m:
						alpha, digits = m.group(1), m.group(2)
						cands = [p for p in self.Gen.Peripherals
							if p.Name.startswith(alpha) and (p.NameIndex == digits or (p.NameIndex == '' and digits in ('', '0')))]
						if len(cands) == 1:
							owner = cands[0]
						elif len(cands) > 1:
							print('WARNING: interrupt vector ' + str(v) + ' (' + name + ') matches several peripherals: ' + ', '.join(c.Name for c in cands))
			owners.append(owner)
		for p in self.Gen.Peripherals:
			if p.InterruptPriority is not None and p.InterruptPriority < len(owners) and owners[p.InterruptPriority] is not p:
				print('WARNING: vector ' + str(p.InterruptPriority) + ' is declared as the first vector of ' + p.Name + ' but the vector list does not agree')
		return vecs, owners

	def _VectorsOf(self, p, vecs, owners):
		return [(v, vecs[v][0], vecs[v][1]) for v in range(len(vecs)) if owners[v] is p]

	def _ClearMethod(self, p, vectorName):
		'''The model may carry a per-vector or per-peripheral clear method; otherwise the chapter says.'''
		compat = getattr(self.Gen, 'McuMpCompat', None) or {}
		fromGen = compat.get('irqClearMethods') or {}
		if type(fromGen) == dict and fromGen.get(vectorName):
			return fromGen[vectorName]
		perVector = getattr(p, 'InterruptClearMethods', None) or getattr(p.Template, 'InterruptClearMethods', None)
		if type(perVector) == dict and perVector.get(vectorName):
			return perVector[vectorName]
		single = getattr(p, 'InterruptClearMethod', None) or getattr(p.Template, 'InterruptClearMethod', None)
		if type(single) == str and len(single) > 0:
			return single
		return 'See chapter'

	# ---- interrupt vector table (standard section 3, chapter 8) ------

	def GenerateInterruptsTable(self):
		'''include/InterruptsTable.tex: one row per vector, reserved slots included.
		   The CPU-internal causes go to include/CpuExceptionsTable.tex so they cannot collide with vector numbers.'''
		vecs, owners = self._VectorOwners()
		if len(vecs) < 1:
			# A configuration without the vector list falls back to the peripherals' first vectors.
			for p in sorted([p for p in self.Gen.Peripherals if p.InterruptPriority is not None], key=lambda p: p.InterruptPriority):
				while len(vecs) < p.InterruptPriority:
					vecs.append(('IRQB_RSVD' + str(len(vecs)), 'Reserved'))
					owners.append(None)
				vecs.append(('IRQB_' + p.Name, p.Name + ' interrupt'))
				owners.append(p)
		s = self._TablePreamble()
		s += '{\\small\n'
		s += '\\begin{tabularx}{\\textwidth}{ l l X X l }\n'
		s += '\\caption{Interrupt vectors} \\label{t:interrupt-vectors} \\\\\n'
		head = '\\hline \\textbf{Vector} & \\textbf{Source} & \\textbf{Description} & \\textbf{Clear method} & \\textbf{Chapter} \\\\ \\hline'
		s += head + ' \\endfirsthead\n'
		s += head + ' \\endhead\n'
		s += '\\hline \\endfoot\n'
		s += '\\hline \\endlastfoot\n'
		for v, (name, desc) in enumerate(vecs):
			p = owners[v]
			if v % 2 == 1:
				s += '\\rowcolor{tablehighlightcolor} '
			if p is None:
				s += str(v) + ' & Reserved & ' + fmttex(desc) + ' & - & - \\\\\n'
				continue
			label = 'peripheral' + p.Template.NameTemplate.replace('_', '')
			s += (str(v) + ' & \\peripheral{' + fmttex(p.Name) + '} & ' + fmttex(desc)
				+ ' \\newline \\texttt{\\footnotesize ' + fmttex(name) + '}'
				+ ' & ' + fmttex(self._ClearMethod(p, name))
				+ ' & \\ref{' + label + '} \\\\\n')
		s += '\\end{tabularx}\n}\n'
		self._writeInclude('InterruptsTable.tex', s)
		self.GenerateCpuExceptionsTable()
		return

	def GenerateCpuExceptionsTable(self):
		'''include/CpuExceptionsTable.tex: the CPU-internal causes, in their own table.
		   These three rows are the legacy causes the old vector table hard-coded; they are not vector numbers.'''
		s = self._TablePreamble()
		s += '\\begin{tabularx}{\\textwidth}{ l X }\n'
		s += '\\caption{CPU-internal interrupt causes} \\label{t:cpu-exceptions} \\\\\n'
		s += '\\hline \\textbf{Cause} & \\textbf{Description} \\\\ \\hline \\endfirsthead\n'
		s += '\\hline \\textbf{Cause} & \\textbf{Description} \\\\ \\hline \\endhead\n'
		s += '\\hline \\endfoot\n'
		s += '\\hline \\endlastfoot\n'
		s += 'Timer & CPU internal timer \\\\\n'
		s += '\\rowcolor{tablehighlightcolor} Instruction & EBREAK, ECALL, or illegal instruction \\\\\n'
		s += 'Bus error & Unaligned memory access \\\\\n'
		s += '\\end{tabularx}\n'
		self._writeInclude('CpuExceptionsTable.tex', s)
		return

	# ---- memory map table (standard section 3, chapter 4) -----------

	def _RegionAttributes(self, group, title):
		t = title.lower()
		if group is None:
			return '-'
		if group == self._ADDR_GROUP_APERTURE:
			return 'R'
		if group == self._ADDR_GROUP_FLASH:
			return 'R/X'
		if 'rom' in t:
			return 'R/X'
		if 'ram' in t or 'tcm' in t:
			return 'R/W/X'
		return 'R/W'

	def _StripTex(self, text):
		t = re.sub(r'\\(?:textit|textbf|color)\{[^{}]*\}', '', text)
		t = re.sub(r'\\[A-Za-z]+', '', t)
		return t.replace('{', '').replace('}', '').strip()

	def GenerateAddressSpaceTable(self):
		'''include/AddressSpaceTable.tex: the address-space column as a table with an attribute column.'''
		rows = self._AddressSpaceRows()
		s = self._TablePreamble()
		s += '\\begin{tabularx}{\\textwidth}{ l l l X l }\n'
		s += ('\\caption{Address map (R = readable, W = writable, X = executable; unmapped rows read zero)}'
			' \\label{t:address-map} \\\\\n')
		head = '\\hline \\textbf{Start} & \\textbf{End} & \\textbf{Size} & \\textbf{Region} & \\textbf{Attr.} \\\\ \\hline'
		s += head + ' \\endfirsthead\n'
		s += head + ' \\endhead\n'
		s += '\\hline \\endfoot\n'
		s += '\\hline \\endlastfoot\n'
		for i, (start, end, group, lines) in enumerate(rows):
			if group is None:
				title = 'Unmapped (reads zero)'
			else:
				title = self._StripTex(lines[0])
				extra = [self._StripTex(l) for l in lines[1:] if not self._StripTex(l).startswith('Size')]
				if group == self._ADDR_GROUP_PRIVATE:
					extra.insert(0, 'private to each hart')
				elif group == self._ADDR_GROUP_APERTURE:
					extra.insert(0, 'hart 0 read-only view of a hart\'s TCM')
				elif group == self._ADDR_GROUP_FLASH:
					extra.insert(0, 'hart 0 only')
				if len(extra) > 0:
					title += ' (' + '; '.join(extra) + ')'
			if i % 2 == 1:
				s += '\\rowcolor{tablehighlightcolor} '
			s += ('\\texttt{' + fmthex(start, minDigits=8) + '} & \\texttt{' + fmthex(end, minDigits=8) + '} & '
				+ self._AddressSpaceSizeString(1 + end - start) + ' & ' + fmttex(title) + ' & '
				+ self._RegionAttributes(group, title) + ' \\\\\n')
		s += '\\end{tabularx}\n\n'
		# The one sentence on register widths, derived from the model.
		narrow = {}
		for p in self.Gen.Peripherals:
			for r in p.Registers:
				if r.Size != 32:
					narrow.setdefault(p.Template.NameTemplate, set()).add(r.Template.NameTemplate)
		if len(narrow) > 0:
			names = []
			for t in sorted(narrow):
				names.append('\\peripheral{' + fmttex(t) + '} (' + ', '.join('\\register{' + fmttex(n) + '}' for n in sorted(narrow[t])) + ')')
			s += ('Every register owns one word-aligned 4-byte slot, and registers are 32 bits wide except those of '
				+ '; '.join(names) + ', which are narrower and occupy the low-order bits of their slot.\n')
		else:
			s += 'Every register owns one word-aligned 4-byte slot and is 32 bits wide.\n'
		self._writeInclude('AddressSpaceTable.tex', s)
		return

	# ---- per-peripheral tables (standard 5.X.2) ----------------------

	def _InstancesOf(self, pt):
		return [p for p in self.Gen.Peripherals if p.Template is pt]

	def GeneratePeripheralTables(self, pt, vecs, owners):
		'''include/<TEMPLATE>-tables.tex: the Instances and signals section of one peripheral chapter.'''
		tag = pt.NameTemplate.replace('_', '')
		instances = self._InstancesOf(pt)
		s = self._TablePreamble()
		s += '\\section{Instances and signals} \\label{inst:' + tag + '}\n\n'
		# Instances table.
		s += '\\begin{tabularx}{\\textwidth}{ l l l X }\n'
		s += '\\caption{\\peripheral{' + fmttex(pt.NameTemplate) + '} instances} \\label{t:' + tag + '-instances} \\\\\n'
		head = '\\hline \\textbf{Instance} & \\textbf{Base address} & \\textbf{Interrupt vector(s)} & \\textbf{Pins (AF)} \\\\ \\hline'
		s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
		s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
		anyPins = False
		signalsPerInstance = {}
		for i, p in enumerate(instances):
			pv = self._VectorsOf(p, vecs, owners)
			vecCell = self._RangesString([v for (v, n, d) in pv]) if len(pv) > 0 else 'none'
			if p.IsGPIO():
				pins = [pin for pin in p.Pins if not pin.NoConnect]
				pinCell = ('P' + p.GetGPIOPortLabel() + '.' + str(pins[0].BitNumber) + ' to P' + p.GetGPIOPortLabel() + '.' + str(pins[-1].BitNumber)) if len(pins) > 0 else 'none'
				if len(pins) > 0:
					anyPins = True
			else:
				sigs = self._PeripheralSignals(p)
				signalsPerInstance[p.Name] = sigs
				# The instances table names each signal at its lowest AF plane only.
				# Every location is in the signals table below.
				cells = []
				for (name, io, desc, locs) in sigs:
					lo = sorted(locs, key=lambda t: (t[1], t[0]))[0]
					cells.append('\\pin{' + fmttex(name) + '} ' + lo[0] + ' (AF' + str(lo[1]) + ')')
				pinCell = ', '.join(cells) if len(cells) > 0 else 'none'
				if len(cells) > 0:
					anyPins = True
			if i % 2 == 1:
				s += '\\rowcolor{tablehighlightcolor} '
			s += '\\peripheral{' + fmttex(p.Name) + '} & \\texttt{' + fmthex(p.BaseAddress) + '} & ' + vecCell + ' & ' + pinCell + ' \\\\\n'
		s += '\\end{tabularx}\n\n'
		# Signals table.
		if anyPins:
			s += '\\begin{tabularx}{\\textwidth}{ l l X X }\n'
			s += '\\caption{\\peripheral{' + fmttex(pt.NameTemplate) + '} signals} \\label{t:' + tag + '-signals} \\\\\n'
			head = '\\hline \\textbf{Signal} & \\textbf{Direction} & \\textbf{Description} & \\textbf{Pin (AF)} \\\\ \\hline'
			s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
			s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
			row = 0
			for p in instances:
				if p.IsGPIO():
					for pin in p.Pins:
						if pin.NoConnect:
							continue
						label = 'P' + p.GetGPIOPortLabel() + '.' + str(pin.BitNumber)
						afs = []
						if len(pin.FuncName) > 0:
							afs.append('AF0 \\pin{' + fmttex(pin.FuncName) + '}')
						for af in pin.AltFuncs:
							afs.append('AF' + str(af.Index) + ' \\pin{' + fmttex(af.Name) + '}')
						desc = 'General-purpose I/O'
						if len(pin.PrimaryName) > 0:
							desc += ' \\pin{' + fmttex(pin.PrimaryName) + '}'
						if len(afs) > 0:
							desc += '; ' + ', '.join(afs)
						if row % 2 == 1:
							s += '\\rowcolor{tablehighlightcolor} '
						s += label + ' & Bidirectional & ' + desc + ' & ' + label + ' \\\\\n'
						row += 1
				else:
					for (name, io, desc, locs) in signalsPerInstance.get(p.Name, []):
						if row % 2 == 1:
							s += '\\rowcolor{tablehighlightcolor} '
						s += ('\\pin{' + fmttex(name) + '} & ' + self._IoTypeWord(io) + ' & '
							+ fmttex(self._CleanFunctionDescription(desc)) + ' & '
							+ ', '.join(l + ' (AF' + str(a) + ')' for (l, a) in locs) + ' \\\\\n')
						row += 1
			s += '\\end{tabularx}\n\n'
		# Interrupt vectors table.
		allVecs = []
		for p in instances:
			allVecs += [(v, n, d, p) for (v, n, d) in self._VectorsOf(p, vecs, owners)]
		if len(allVecs) > 0:
			s += '\\begin{tabularx}{\\textwidth}{ l l X X }\n'
			s += '\\caption{\\peripheral{' + fmttex(pt.NameTemplate) + '} interrupt vectors} \\label{t:' + tag + '-vectors} \\\\\n'
			head = '\\hline \\textbf{Vector} & \\textbf{Instance} & \\textbf{Description} & \\textbf{Clear method} \\\\ \\hline'
			s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
			s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
			for i, (v, n, d, p) in enumerate(sorted(allVecs, key=lambda t: t[0])):
				if i % 2 == 1:
					s += '\\rowcolor{tablehighlightcolor} '
				s += (str(v) + ' & \\peripheral{' + fmttex(p.Name) + '} & ' + fmttex(d) + ' \\newline \\texttt{\\footnotesize ' + fmttex(n) + '} & '
					+ fmttex(self._ClearMethod(p, n)) + ' \\\\\n')
			s += '\\end{tabularx}\n\n'
		fileName = tag + '-tables.tex'
		self._writeInclude(fileName, s)
		return fileName

	def _SpliceIntoIntro(self, introPath, inputLine, tablesFileName):
		'''Place the generated Instances and signals section after the intro's first (Overview) section.
		   The intro source is untouched; only the copy in include/ is edited.
		   An intro may name the spot itself with \\PeripheralInstancesAndSignals or by inputting the file.'''
		with open(introPath) as f:
			content = f.read()
		if tablesFileName in content:
			return
		if '\\PeripheralInstancesAndSignals' in content:
			content = content.replace('\\PeripheralInstancesAndSignals', inputLine, 1)
		else:
			inserted = False
			for level in ('section', 'subsection', 'subsubsection'):
				heads = [m.start() for m in re.finditer(r'^\\' + level + r'\*?\s*[\[{]', content, flags=re.M)]
				if len(heads) < 1:
					continue
				if len(heads) >= 2:
					content = content[:heads[1]] + inputLine + '\n\n' + content[heads[1]:]
				else:
					content = content.rstrip('\n') + '\n\n' + inputLine + '\n'
				inserted = True
				break
			if not inserted:
				content = content.rstrip('\n') + '\n\n' + inputLine + '\n'
		with open(introPath, 'w') as f:
			f.write(content)
		return

	# ---- the peripheral chapters -------------------------------------

	def _EnumerationLines(self, bf, vds):
		lines = []
		for (value, description, name) in vds:
			line = '\\texttt{' + self._FieldValueString(value, bf.Size) + '}'
			if len(name) > 0:
				line += ' \\texttt{' + fmttex(name) + '}'
			if len(description) > 0:
				line += ': ' + fmtprose(description)
			lines.append(line)
		return lines

	def _FieldRows(self, pt, block, size):
		'''The five-column field table rows of one block, MSB first, reserved runs collapsed.'''
		rows = []
		fields = sorted(block['fields'], key=lambda f: f[0].MSB, reverse=True)
		pending = None
		for (bf, name, desc, vds) in fields:
			if bf.LSB >= size:
				continue
			# A template field wider than the instance register is clipped to the register width.
			msb = min(bf.MSB, size - 1)
			if bf.Unused:
				if pending is None:
					pending = [msb, bf.LSB]
				elif pending[1] == msb + 1:
					pending[1] = bf.LSB
				else:
					rows.append(self._ReservedRow(pending))
					pending = [msb, bf.LSB]
				continue
			if pending is not None:
				rows.append(self._ReservedRow(pending))
				pending = None
			bits = str(msb) if msb == bf.LSB else str(msb) + ':' + str(bf.LSB)
			width = msb - bf.LSB + 1
			text = desc.strip()
			if len(text) < 1:
				self._NoteEmptyDescription(pt, block, name)
				title = self._ShortTitle(block['description'])
				text = title if (bf.SameNameAsRegister and title) else ''
			if self._SentenceCount(text) > 3:
				self.LongFieldDescriptions.append(pt.NameTemplate + '.' + block['name'] + '.' + name)
			enum = self._EnumerationLines(bf, vds)
			if len(enum) < 1:
				text, enum = self._CodedListFromProse(bf, text)
			cell = fmtprose(text)
			if len(enum) > 0:
				cell += ('\\newline ' if len(cell) > 0 else '') + ' \\newline '.join(enum)
			rows.append(bits + ' & \\texttt{' + fmttex(self._BitFieldDisplayName(pt, name)) + '} & \\texttt{' + bf.Accessibility
				+ '} & \\texttt{' + self._FieldResetString(bf.ResetValue, width) + '} & ' + cell + ' \\\\\n')
		if pending is not None:
			rows.append(self._ReservedRow(pending))
		return rows

	def _CodedListFromProse(self, bf, text):
		'''A description written as "0 = ..., 1 = ..., Codes a-b are reserved ..." becomes prose plus enumeration rows.
		   Fields that carry explicit value descriptions never reach this; the model keeps the prose form because
		   other emitters parse it back.'''
		sentences = re.split(r'(?<=\.)\s+', text.strip())
		codes = []
		kept = []
		for sent in sentences:
			m = re.match(r'^(\d+)\s*=\s*(.+?)\.?$', sent)
			r = re.match(r'^Codes\s+(\d+)-(\d+)\s+are\s+reserved\s*(.*?)\.?$', sent)
			if m:
				codes.append((int(m.group(1)), None, m.group(2)))
			elif r:
				codes.append((int(r.group(1)), int(r.group(2)), 'reserved' + ((', ' + r.group(3)) if r.group(3) else '')))
			else:
				kept.append(sent)
		if len(codes) < 2:
			return text, []
		lines = []
		for (lo, hi, desc) in codes:
			v = '\\texttt{' + self._FieldValueString(lo, bf.Size) + '}'
			if hi is not None:
				v += ' to \\texttt{' + self._FieldValueString(hi, bf.Size) + '}'
			lines.append(v + ': ' + fmtprose(desc))
		return ' '.join(kept), lines

	def _ReservedRow(self, span):
		bits = str(span[0]) if span[0] == span[1] else str(span[0]) + ':' + str(span[1])
		return bits + ' & - & - & - & Reserved. Reads zero; write zero. \\\\\n'

	def _NoteEmptyDescription(self, pt, block, fieldName):
		where = pt.NameTemplate + '.' + block['name'] + '.' + fieldName
		if self.EMPTY_FIELD_DESCRIPTION_IS_ERROR:
			raise Exception('Empty bit field description: ' + where)
		if where not in self.EmptyFieldDescriptions:
			self.EmptyFieldDescriptions.append(where)
			print('WARNING: empty bit field description: ' + where)
		return

	def _RegisterBlockTex(self, pt, block, instances, shortLabelOk):
		tag = pt.NameTemplate.replace('_', '')
		name = block['name']
		size = self._BlockSize(pt, block)
		first = block['members'][0]
		title = self._ShortTitle(block['description'])
		heading = '\\texttt{' + fmttex(self._BlockHeadingName(block)) + '}'
		if title:
			heading += ': ' + fmttex(title)
		plain = self._BlockHeadingName(block) + ((': ' + title) if title else '')
		s = '\\subsection{\\texorpdfstring{' + heading + '}{' + fmttex(plain) + '}}\n'
		s += '\\label{' + self._BlockLabel(pt, block) + '}'
		for rt in block['members']:
			s += ' \\label{ss:' + rt.NameTemplate.replace('_', '') + '}'
		if shortLabelOk:
			s += ' \\label{reg:' + name.replace('_', '') + '}'
		s += '\n'
		# The offset line.
		line = ('\\noindent \\textbf{Offset} \\texttt{' + self._BlockOffsetString(block) + '} \\quad '
			+ '\\textbf{Reset} \\texttt{' + self._RegisterResetString(first, size) + '} \\quad '
			+ '\\textbf{Width} ' + str(size))
		if block['indices'] is None and len(instances) <= 4 and len(instances) > 0:
			addrs = []
			for p in instances:
				for r in p.Registers:
					if r.Template is first:
						addrs.append('\\texttt{' + fmthex(r.Address) + '}' + ((' (' + fmttex(p.Name) + ')') if len(instances) > 1 else ''))
			line += ' \\quad \\textbf{Address} ' + ', '.join(addrs)
		elif len(instances) > 4:
			line += ' \\quad \\textbf{Address} see Table~\\ref{t:' + tag + '-instances}'
		s += line + '\n\n'
		desc = block['description'].strip()
		if len(desc) > 0 and not (title and desc.rstrip('.') == title):
			if self._SentenceCount(desc) > 3:
				self.LongRegisterDescriptions.append(pt.NameTemplate + '.' + name)
			s += '\\noindent ' + fmtprose(desc) + '\n\n'
		s += '\\begin{tabularx}{\\textwidth}{ l l l l X }\n'
		head = '\\hline \\textbf{Bits} & \\textbf{Field} & \\textbf{Type} & \\textbf{Reset} & \\textbf{Description} \\\\ \\hline'
		s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
		s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
		rows = self._FieldRows(pt, block, size)
		for i, r in enumerate(rows):
			if i % 2 == 1:
				s += '\\rowcolor{tablehighlightcolor} '
			s += r
		s += '\\end{tabularx}\n\n'
		return s

	def GeneratePeripheralSections(self):
		self.EmptyFieldDescriptions = []
		self.LongFieldDescriptions = []
		self.LongRegisterDescriptions = []
		pts = []
		for p in self.Gen.Peripherals:
			if p.Template not in pts:
				pts.append(p.Template)
		vecs, owners = self._VectorOwners()
		# A register template name shared by two peripheral templates cannot carry the short reg: label.
		nameCount = {}
		for pt in pts:
			for block in self._RegisterBlocks(pt):
				nameCount[block['name']] = nameCount.get(block['name'], 0) + 1

		s = self._TablePreamble()
		for pt in pts:
			tag = pt.NameTemplate.replace('_', '')
			instances = self._InstancesOf(pt)
			longName = getattr(pt, 'LongName', None)
			if not (type(longName) == str and len(longName) > 0):
				longName = self._PERIPHERAL_LONG_NAMES.get(pt.NameTemplate, None)
			if type(longName) == str and len(longName) > 0:
				chapterTitle = fmttex(longName) + ' (\\texorpdfstring{\\peripheral{' + fmttex(pt.NameTemplate) + '}}{' + fmttex(pt.NameTemplate) + '})'
			else:
				chapterTitle = '\\texorpdfstring{\\peripheral{' + fmttex(pt.NameTemplate) + '}}{' + fmttex(pt.NameTemplate) + '}'
			s += '\\chapter{' + chapterTitle + '} \\label{peripheral' + tag + '}\n'

			tablesFile = self.GeneratePeripheralTables(pt, vecs, owners)
			inputLine = '\\input{include/' + tablesFile + '}'
			if pt.LatexIntroFileName is not None:
				introPath = self.SaveDirectory + '/include/' + pt.LatexIntroFileName
				self._SpliceIntoIntro(introPath, inputLine, tablesFile)
				s += '\\input{include/' + pt.LatexIntroFileName + '}\n\n\\FloatBarrier\n\n'
			else:
				s += fmttex(pt.Description) + '\n\n' + inputLine + '\n\n\\FloatBarrier\n\n'

			# The Registers section.
			blocks = self._RegisterBlocks(pt)
			s += '\\section{Registers} \\label{regs:' + tag + '}\n\n'
			bases = ', '.join('\\peripheral{' + fmttex(p.Name) + '} \\texttt{' + fmthex(p.BaseAddress) + '}' for p in instances)
			if len(instances) > 0:
				s += ('Register offsets in this chapter are relative to the instance base address in Table~\\ref{t:' + tag + '-instances} ('
					+ bases + '); the generated header names each base \\texttt{' + fmttex(instances[0].Name) + '\\_BASE}'
					+ (' and so on' if len(instances) > 1 else '') + '.\n\n')
			# The register summary table.
			s += '\\begin{tabularx}{\\textwidth}{ l l l l X }\n'
			s += '\\caption{\\peripheral{' + fmttex(pt.NameTemplate) + '} register summary} \\label{t:' + tag + '-regsummary} \\\\\n'
			head = '\\hline \\textbf{Offset} & \\textbf{Name} & \\textbf{Access} & \\textbf{Reset} & \\textbf{Description} \\\\ \\hline'
			s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
			s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
			row = 0
			nextOffset = None
			for block in blocks:
				first = block['members'][0]
				last = block['members'][-1]
				if nextOffset is not None and first.Offset > nextOffset:
					if row % 2 == 1:
						s += '\\rowcolor{tablehighlightcolor} '
					s += ('\\texttt{' + fmthex(nextOffset, minDigits=2) + '} to \\texttt{' + fmthex(first.Offset - 1, minDigits=2)
						+ '} & - & - & - & Reserved \\\\\n')
					row += 1
				size = self._BlockSize(pt, block)
				title = self._ShortTitle(block['description']) or ''
				if row % 2 == 1:
					s += '\\rowcolor{tablehighlightcolor} '
				s += ('\\texttt{' + self._BlockOffsetString(block) + '} & \\hyperref[' + self._BlockLabel(pt, block) + ']{\\texttt{'
					+ fmttex(self._BlockHeadingName(block)) + '}} & \\texttt{' + self._AccessSummary([f[0] for f in block['fields']])
					+ '} & \\texttt{' + self._RegisterResetString(first, size) + '} & ' + fmttex(title) + ' \\\\\n')
				row += 1
				nextOffset = last.Offset + 4
			s += '\\end{tabularx}\n\n'
			# One block per register.
			for block in blocks:
				s += self._RegisterBlockTex(pt, block, instances, nameCount.get(block['name'], 0) == 1)
			s += '\n'

		# Report the cells the standard wants moved into the functional description.
		for what, names in (('register descriptions', self.LongRegisterDescriptions), ('field descriptions', self.LongFieldDescriptions)):
			if len(names) > 0:
				print('NOTE: ' + str(len(names)) + ' ' + what + ' run past three sentences: ' + ', '.join(names))
		if len(self.EmptyFieldDescriptions) > 0:
			print('WARNING: ' + str(len(self.EmptyFieldDescriptions)) + ' bit fields have no description (set LatexUserGuide.EMPTY_FIELD_DESCRIPTION_IS_ERROR = True to fail the build on them)')
		self._writeInclude('PeripheralSections.tex', s)
		return

	def GeneratePeripheralAndRegistersList(self):
		'''include/PeripheralAndRegistersList.tex: the flat register index of the appendix, arrays collapsed.'''
		s = self._TablePreamble()
		s += '{\\small\n'
		s += '\\begin{tabularx}{\\textwidth}{ l l l l l X }\n'
		s += '\\caption{Register index} \\label{t:register-index} \\\\\n'
		head = '\\hline \\textbf{Register} & \\textbf{Address} & \\textbf{Offset} & \\textbf{Size} & \\textbf{Access} & \\textbf{Reset} \\\\ \\hline'
		s += head + ' \\endfirsthead\n' + head + ' \\endhead\n'
		s += '\\hline \\endfoot\n\\hline \\endlastfoot\n'
		for p in self.Gen.Peripherals:
			pt = p.Template
			label = 'peripheral' + pt.NameTemplate.replace('_', '')
			s += ('\\multicolumn{6}{l}{\\textbf{\\hyperref[' + label + ']{\\peripheral{' + fmttex(p.Name) + '}}} base \\texttt{'
				+ fmthex(p.BaseAddress) + '}' + (' (shared window)' if p.PeripheralMemorySlot is None else '') + '} \\\\ \\hline\n')
			row = 0
			for block in self._RegisterBlocks(pt):
				first = block['members'][0]
				reg = None
				for r in p.Registers:
					if r.Template is first:
						reg = r
				if reg is None:
					continue
				if block['indices'] is None:
					name = reg.Name
					addr = fmthex(reg.Address)
					off = fmthex(reg.Offset, minDigits=2)
				else:
					name = block['name'].replace('x', p.NameIndex) if 'x' in block['name'] else block['name']
					name += ' (n = ' + str(block['indices'][0]) + '..' + str(block['indices'][-1]) + ')'
					base = reg.Offset - block['indices'][0] * block['stride']
					addr = fmthex(p.BaseAddress + base) + ' + ' + str(block['stride']) + 'n'
					off = fmthex(base, minDigits=2) + ' + ' + str(block['stride']) + 'n'
				size = self._BlockSize(pt, block)
				if row % 2 == 1:
					s += '\\rowcolor{tablehighlightcolor} '
				s += ('\\hyperref[' + self._BlockLabel(pt, block) + ']{\\texttt{' + fmttex(name) + '}} & \\texttt{' + addr + '} & \\texttt{' + off
					+ '} & ' + str(size // 8) + ' & \\texttt{' + self._AccessSummary([f[0] for f in block['fields']]) + '} & \\texttt{'
					+ self._RegisterResetString(first, size) + '} \\\\\n')
				row += 1
			s += '\\hline\n'
		s += '\\end{tabularx}\n}\n'
		self._writeInclude('PeripheralAndRegistersList.tex', s)
		return
