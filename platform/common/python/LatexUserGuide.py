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
		return
	
	def Generate(self):
		self.CopyTemplateTexFiles()
		self.CopyAnalogChapter()
		self.GenerateDefinesFile()
		self.GenerateSystemConfigurationListFile()
		self.GenerateFeaturesList()
		self.GenerateExtraIntroChapters()
		self.GenerateCqAnalogChapter()
		self.GenerateAddressSpaceDiagram()
		self.GenerateChipConfigurationSection()
		self.GenerateSystemBlockDiagram()
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
		self.GenerateSpiTimingDiagram()
		self.GenerateSpiByteOrderingDiagram()
		self.GenerateSpiBitOrderingDiagram()
		self.GenerateUartFrameDiagram()
		self.GenerateI2cTransactionDiagram()
		self.GenerateIrqClaimCompleteDiagram()
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
			path = self.ThisFileDirectory + '/../latex/PeripheralIntroductions/' + pt.LatexIntroFileName
			if not os.path.isfile(path):
				raise Exception('The latex introduction for peripheral ' + pt.NameTemplate + ' does not exist at path ' + path)
			copyfile(path, self.SaveDirectory + '/include/' + pt.LatexIntroFileName)

		# Copy any extra intro tex files that the master template inputs directly (e.g. the multi-core chapter)
		if self.Gen.ExtraLatexIntroFiles is not None:
			for fileName in self.Gen.ExtraLatexIntroFiles:
				path = self.ThisFileDirectory + '/../latex/PeripheralIntroductions/' + fileName
				if not os.path.isfile(path):
					raise Exception('The extra latex introduction file does not exist at path ' + path)
				copyfile(path, self.SaveDirectory + '/include/' + fileName)

		# Copy the master MCU User Guide template tex file
		path = self.ThisFileDirectory + '/../latex/' + self.Gen.McuUserGuideLatexTemplateFileName
		copyfile(path, self.SaveDirectory + '/TRM.tex')

		# Copy the packages and commands tex file
		path = self.ThisFileDirectory + '/../latex/packages-commands.template.tex'
		copyfile(path, self.SaveDirectory + '/packages-commands.tex')

		## Copy the tikzit.sty file
		#path = self.ThisFileDirectory + '/../latex/tikzit.template.sty'
		#copyfile(path, self.SaveDirectory + '/tikzit.sty')

		## Copy the tikzit style file
		#path = self.ThisFileDirectory + '/../latex/murray.template.tikzstyles'
		#copyfile(path, self.SaveDirectory + '/murray.tikzstyles')

		# Copy the figures directory
		path = self.ThisFileDirectory + '/../latex/figures'
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
			defines['PeriphVectorsCount'] = str(clint.InterruptPriority)
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
			config += ['Supports the RISC-V Zacas extension, adding word compare-and-swap (amocas.w), and — when Zabha is also present — byte/halfword compare-and-swap (amocas.b/.h); the CAS is a single globally-coherent read-compare-conditional-write transaction on the shared window (amocas.d is unsupported on RV32)']

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
		s = '% Generated from ChipGenerator.ExtraLatexIntroFiles — do not edit\n'
		if self.Gen.ExtraLatexIntroFiles is not None:
			for fileName in self.Gen.ExtraLatexIntroFiles:
				s += '\\input{include/' + fileName + '}\n'

		if not os.path.isdir(self.IncludeDirectory):
			os.makedirs(self.IncludeDirectory)

		path = self.IncludeDirectory + '/ExtraIntroChapters.tex'
		with open(path, 'w') as f:
			f.write(s)

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

		s = '% Generated from ChipGenerator.DocSubSlotBlocks — do not edit. Rendered only under \\ifcqanalog.\n'
		s += '\\section{Analog Front-End Subsystem} \\label{s:cqanalog}\n\n'
		s += ('This chip carries a bipolar-potentiostat analog front-end (AFE) for '
			'electrochemical impedance measurement, organised as four per-quadrant '
			'measurement \\emph{sites} plus one shared electrochemical-impedance-'
			'spectroscopy (EIS) sweep engine. Each site drives its own electrode group '
			'(counter/working/reference/RE2) brought out on the package (Section '
			'\\ref{s:pinsConfig}). The analog blocks themselves --- the potentiostat, '
			'the transimpedance ADC path, and the shared EIS engine + analog multiplexer '
			'--- are analog IP that is not yet integrated; what \\emph{is} present is the '
			'complete \\emph{digital access path}: a register stub for each site and for '
			'the EIS engine, each a fully-functional shared-window arbiter slave with the '
			'ownership gate and interrupt path described below. Software (and the '
			'verification suite) programs and reads these exactly as it will the final '
			'analog blocks; the stubs hold placeholder storage and drive their interrupt '
			'from a software-settable flag until the analog IP replaces them.\n\n')

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
			'multi-core arbiter attributes to the in-flight transaction --- the same '
			'attribution the hardware mutex bank and the IRQ-router CLAIM use. Because '
			'each block decodes only its low four address bits, its 16 words fill its '
			'64-byte sub-slot exactly; the EIS block additionally aliases across the '
			'\\texttt{0x7C00}--\\texttt{0x7FFF} quarter it owns.\n\n')

		# --- Ownership / gating semantics --------------------------------------
		s += '\\subsection{Ownership gating} \\label{ss:cqanalog-gate}\n\n'
		s += ('Each AFE site is owned by the hart of its quadrant: site \\texttt{AFE}$h$ '
			'answers only when \\texttt{s\\_master} = $h$ \\emph{or} \\texttt{s\\_master} = 0. '
			'Hart 0 is the management hart, so it reaches every site (this is what lets it '
			'demultiplex the shared interrupt, below); every other hart sees only its own '
			'site. The EIS engine is instantiated hart-0-only (\\texttt{s\\_master} = 0), so '
			'other harts request a sweep through a software mailbox convention rather than '
			'touching it directly. The gate is hardware-enforced inside the slave and keys '
			'off \\texttt{s\\_master} alone --- there is no way to forge ownership, and no '
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
			'source, and both are routed --- by software convention in the routing rows --- '
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
			return fmttex(s.replace('—', '---'))

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
			'isa.mul', 'isa.fastMul', 'isa.div', 'isa.atomics', 'isa.compressed',
			'isa.bitmanip', 'isa.counters', 'isa.counters64',
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
		s += '% Derived geometry — computed by generate.py, NOT configurable\n'
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
		tcmBytes = self.Gen.RamMemorySlotSize
		for h, (start, end) in enumerate((sec[1], sec[2]) for sec in sections):
			if end - start + 1 != tcmBytes:
				raise Exception('TCM aperture %d spans 0x%X bytes but a TCM is 0x%X'
					% (h, end - start + 1, tcmBytes))
			if start != windows[0] + h * tcmBytes:
				raise Exception('TCM aperture %d is at 0x%X, not the uniform 0x%X + %d*0x%X'
					% (h, start, windows[0], h, tcmBytes))
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
		s += '\\node[blk, fill=black!15, minimum width=' + '%.2f' % totalW + 'cm, minimum height=0.85cm] (arb) at (' + '%.2f' % (totalW / 2.0) + ', 2.45) {\\textbf{mp\\_arbiter} --- serializing round-robin, ' + str(N) + ' masters, grant-locked AMOs};\n'
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

		s = ('% Generated system block diagram — ORCHESTRATOR shape (numHarts=' + str(N)
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
			+ P((aX0 + aX1) / 2.0) + ', ' + P(yH0) + ') {\\textbf{hart 0} --- orchestrator\\\\ \\scriptsize soft logic, always on\\\\'
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
			+ 'cm] (arb) at (' + P((aX0 + bX1) / 2.0) + ', ' + P(yArb) + ') {\\textbf{mp\\_arbiter} --- serializing round-robin, '
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
			+ ') {\\textbf{reads back} any hart\'s\\\\ private TCM through that\\\\ tile\'s own read port ---\\\\'
			+ ' hart 0 only, never writes,\\\\ and a gated tile reads zero};\n')
		s += '\\end{tikzpicture}\n'
		return s

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
			+ ') {the shared fabric --- always on};\n')
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
			+ ') {the word, six \\register{mclk} later --- or nothing at all, because this clamp zeroes a dark tile\'s \\register{tcm\\_ext\\_done} too};\n')

		# ---- band 3: the port, the pins it borrows, and the memory
		s += ('\\node[unit, minimum width=' + P(seqW) + 'cm, minimum height=' + P(seqH) + 'cm] (seq) at ('
			+ P(seqCx) + ', ' + P(ySeq) + ') {\\textbf{the tile\'s own TCM read port}\\\\ \\scriptsize four states, one SRAM read:\\\\'
			+ ' \\scriptsize \\textit{SETTLE} $\\to$ \\textit{READ} $\\to$ \\textit{LATCH},\\\\'
			+ ' \\scriptsize then one \\register{mclk} of \\register{tcm\\_ext\\_done}\\\\ \\scriptsize with the word riding on it};\n')
		s += ('\\node[blk, minimum width=' + P(muxW) + 'cm, minimum height=' + P(muxH) + 'cm, text width='
			+ P(muxW - 0.40) + 'cm] (mux) at ('
			+ P(muxCx) + ', ' + P(yMux) + ') {\\textbf{either the core or the port drives the TCM\'s pins --- never both}\\\\'
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
			+ ' Q shadow keeps showing it the word it last read --- so the frozen core can never mistake'
			+ ' the aperture\'s word for its own.}};\n')
		s += '\\end{tikzpicture}\n'
		self._writeInclude('TcmApertureDiagram.tex', s)
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
		s = '% Generated boot flow chart (M12 single-ROM boot, numHarts=' + str(N) + ')\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tstp/.style={draw, thick, rounded corners=2pt, align=center, font=\\sffamily\\small, text width=4.6cm, inner sep=5pt},\n'
		s += '\tterm/.style={stp, fill=black!12},\n'
		s += '\tdec/.style={draw, thick, diamond, aspect=2.4, align=center, font=\\sffamily\\small, inner sep=1.5pt},\n'
		s += '\tflow/.style={->, >=Stealth, thick},\n'
		s += '\tlab/.style={font=\\sffamily\\scriptsize, fill=white, inner sep=1pt}]\n'
		s += '\\node[term, text width=7.6cm] (rst) at (6.0, 10.6) {\\textbf{Power-on / reset}\\\\ all ' + str(N) + ' harts: PC $=$ \\texttt{0x0}, fetching THE shared boot ROM through the arbiter};\n'
		s += '\\node[dec] (who) at (6.0, 8.9) {\\register{mhartid} $= 0$?};\n'
		# Hart 0 branch (left)
		s += '\\node[stp] (h0a) at (2.6, 7.1) {Configure \\peripheral{GPIO0}/\\peripheral{SPI0}, read the BOOT strap pin};\n'
		s += '\\node[stp] (h0b) at (2.6, 5.5) {Copy the program from SPI flash to \\texttt{0x8000}--\\texttt{0xFFFC}; zero the mailbox region \\texttt{0x10000}--\\texttt{0x107FF}};\n'
		s += '\\node[term] (h0c) at (2.6, 3.9) {Jump to \\texttt{\\SpiFlashProgramAddress} --- application runs on hart 0};\n'
		s += '\\node[stp, dashed] (launch) at (2.6, 1.9) {\\textbf{Launching a tile $h$:} stage its image in shared RAM, write \\register{SRC[h]}/\\register{LEN[h]}/\\register{ENTRY[h]} at \\texttt{\\BootMailboxBase}$+16h$, then write $1$ to \\register{MSIPx} (\\texttt{0x5000}$+4h$)};\n'
		# Tile branch (right)
		s += '\\node[stp] (t1) at (9.4, 7.1) {Set $\\mathtt{sp}$ to the top of the private TCM; arm the software-interrupt vector};\n'
		s += '\\node[term] (t2) at (9.4, 5.5) {\\textbf{Park}: low-power sleep, waiting for a \\peripheral{CLINT} software interrupt};\n'
		s += '\\node[stp] (t3) at (9.4, 3.6) {ROM loader: clear the \\register{MSIPx} level, read \\register{SRC}/\\register{LEN}/\\register{ENTRY} at \\texttt{\\BootMailboxBase}$+16h$, copy \\register{LEN} words into the TCM at \\texttt{0x8000}};\n'
		s += '\\node[term] (t4) at (9.4, 1.9) {Enter \\register{ENTRY} with $\\mathtt{sp}$ at the top of the TCM --- tile runs};\n'
		# Edges
		s += '\\draw[flow] (rst) -- (who);\n'
		# The naming costs width: at pos=0.25 the label sits on the horizontal run
		# straight out of the diamond, and "yes: hart 0 (orchestrator)" on one line
		# runs INTO the diamond (measured in the render). On the orchestrator
		# polarity it therefore breaks in two and moves onto the vertical run,
		# clear of both nodes; without an orchestrator the original single-line
		# label is emitted unchanged, byte for byte.
		if orch:
			yesLab = 'node[lab, align=center, pos=0.62] {yes: hart 0\\\\ (orchestrator)}'
		else:
			yesLab = 'node[lab, pos=0.25] {yes: hart 0}'
		s += '\\draw[flow] (who.west) -| ' + yesLab + ' (h0a.north);\n'
		s += '\\draw[flow] (who.east) -| node[lab, pos=0.25] {no: harts 1--' + str(N - 1) + '} (t1.north);\n'
		s += '\\draw[flow] (h0a) -- (h0b);\n'
		s += '\\draw[flow] (h0b) -- (h0c);\n'
		s += '\\draw[flow, dashed] (h0c) -- (launch);\n'
		s += '\\draw[flow] (t1) -- (t2);\n'
		s += '\\draw[flow] (t2) -- node[lab, right=1pt] {\\register{MSIPx} interrupt} (t3);\n'
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
		s += '\\node[leaf] (mtx) at (2.4, 1.6) {\\textbf{Hardware mutex}\\\\(preferred)\\\\[1pt]\\asminline{lw} claims (0 $=$ yours), \\asminline{sw 0} releases --- one instruction, no retry state};\n'
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
		s += 'every retry loop needs a hart-scaled backoff ($\\mathtt{delay} \\propto \\register{mhartid}+1$) and a bounded retry count --- identical harts on the fair round-robin arbiter can otherwise livelock.};\n'
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
		ann += '\t after \\register{done} --- masked by \\register{need\\_release}};\n'
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
				state.append(('D', '\\textit{LATCH} --- held while \\register{s\\_stall} is high'))
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
			'would complete here --- on that zero};\n' % unst)
		ann += '\\draw[<->, >=Stealth] (%d,{\\YBOT-0.45}) -- (%d,{\\YBOT-0.45});\n' % (st0, st1 + 1)
		ann += ('\\node[ann, below] at (%.1f,{\\YBOT-0.47}) {\\register{s\\_stall} --- the tile read '
			'runs here: \\textit{SETTLE}, \\textit{READ}, \\textit{LATCH}, then one \\register{mclk} '
			'of \\register{tcm\\_ext\\_done} with the word on it};\n' % ((st0 + st1 + 1) / 2.0))
		ann += '\\draw[<->, >=Stealth] (%d,{\\YBOT-1.25}) -- (%d,{\\YBOT-1.25});\n' % (
			self._ARB_STALL_REQSEEN, self._ARB_STALL_DONE)
		ann += ('\\node[ann, below] at (%.1f,{\\YBOT-1.27}) {%d \\register{mclk} at the arbiter pins '
			'--- every other shared-window slave still completes in %d};\n'
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
		ann += '\\node[ann, below] at (8,{\\YBOT-0.58}) {source masked on every hart --- exactly-once delivery};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-1.15})\n'
		ann += '\t{The handler clears the level at the peripheral \\emph{before} the dispatcher completes;\\\\[-2pt]\n'
		ann += '\t if the level is still high at COMPLETE the source simply re-pends.\\\\[-2pt]\n'
		ann += '\t The \\textsf{handler} cell stands for many \\register{mclk} cycles of software.};\n'
		s = '% Generated IRQROUTER claim/complete diagram\n'
		s += self._cycleFigure('1.05cm', rows, 11, ann, shade=('5', '11'))
		self._writeInclude('IrqClaimCompleteDiagram.tex', s)
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
		ann += '\t \\register{mhartid}$+1$ --- hart ' + hiS + ' must back off and retry. Release with \\asminline{sw x0}.};\n'
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
				'% numHarts=' + str(N) + ': no switchable tile domains — figure suppressed.\n')
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
		s += '{the always-on domain --- \\texttt{VDD}, never switched};\n'
		s += '\\node[ban] at (' + P(W / 2.0) + ', ' + P((ySwB + ySwBan) / 2.0) + ') '
		s += '{' + _numberWord(len(tiles)) + ' switched tile rails --- \\texttt{VDD\\_SW}, '
		s += 'one per channel tile, each gated on its own};\n'
		# THE boundary: a real line, labelled, with the one true claim on it
		s += '\\draw[line width=1.4pt, black!60] (0, ' + P(yBnd) + ') -- (' + P(W) + ', ' + P(yBnd) + ');\n'
		s += '\\node[font=\\sffamily\\scriptsize\\bfseries, black!60, fill=black!5, inner sep=2pt] '
		s += 'at (' + P(W - 3.10) + ', ' + P(yBnd) + ') {the power-domain boundary};\n'

		# ---- band A: hart 0, the fabric it shares, and the controller
		h0W = xLab1 - xLab0
		if orch:
			h0 = ('{\\textbf{hart 0} --- the orchestrator\\\\[2pt] soft core $+$ '
				+ str(tcmKiB) + '\\,KiB TCM,\\\\ in the always-on centre band\\\\[3pt] '
				'\\scriptsize no header switches exist\\\\ \\scriptsize for it: no gate bit, '
				'no clamps,\\\\ \\scriptsize no sequencer row}')
		else:
			h0 = ('{\\textbf{hart 0} --- the management hart\\\\[2pt] the same hart tile as the '
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
		s += fmthex(drawnMask, minDigits=2) + '}) request a gate; bit 0 is read-only 0 --- '
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
			'the field-power boot gate --- asserted \\emph{before} the rail goes, released '
			'\\emph{after} it is back.')
		tcmText = ('\\register{tcm\\_pgen} \\textbf{gates the macro.} The TCM runs off the same '
			'\\register{pd\\_sleep}$(h)$, so it dies with the rail: a wake is a cold boot.')
		if apertures:
			tcmText += (' Its aperture then reads \\emph{zeros} --- check \\register{PWRSR} first.')
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
		s += '\\node[ban] at (' + P((wX1 + bX1) / 2.0) + ', ' + P((yBan + yTop) / 2.0) + ') {the chip --- everything here runs on \\register{mclk}};\n'
		s += '\\node[ban, rotate=90] at (' + P((wX0 + wX1) / 2.0) + ', 1.30) {clock-domain crossing};\n'

		# ---- band A: the probe, its five pins, and the transport
		s += '\\node[blk, dashed, minimum width=3.5cm, minimum height=1.05cm] (probe) at (' + P(aCx) + ', 8.20) {external\\\\ debug probe};\n'
		s += '\\node[unit, minimum width=4.1cm, minimum height=3.10cm] (dtm) at (' + P(aCx) + ', 4.55) {\\textbf{dtm0}\\\\ TAP $+$ transport\\\\[2pt] \\scriptsize the sixteen-state port,\\\\ \\scriptsize the instruction register,\\\\ \\scriptsize and the \\register{dmi} shift register};\n'
		s += '\\draw[bus] (probe.south) -- (dtm.north);\n'
		s += '\\node[lab, fill=black!8, inner sep=2pt] at (' + P(aCx) + ', 7.05) {\\textbf{5 pins}\\\\ \\pin{TCK} \\pin{TMS} \\pin{TDI}\\\\ \\pin{TDO} \\pin{TRSTn}};\n'
		s += '\\node[lab] at (' + P(aCx) + ', 1.30) {\\textit{on the chip, but clocked by}\\\\ \\textit{the probe --- nothing in this}\\\\ \\textit{band moves unless \\pin{TCK} does}};\n'

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
		s += '\\node[blk, fill=black!15, minimum width=' + P(arbX1 - arbX0) + 'cm, minimum height=' + P(arbH) + 'cm] (arb) at (' + P((arbX0 + arbX1) / 2.0) + ', ' + P(yArb) + ') {\\textbf{mp\\_arbiter} --- ' + str(N) + ' harts and \\textbf{dm0}, all masters on one shared bus};\n'
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
		s += '\\node[lab, anchor=west] at (' + P(trunkX) + ', ' + P(yTrunk - 0.62) + ') {\\textbf{halts and resumes} every hart --- \\register{haltreq} / \\register{resumereq} out, \\register{halted} / \\register{unavail} back, on direct wires};\n'
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
		# (2026-08-15, USER: smaller, with the states further apart so the
		# arrows between them are clearly visible). The chapter used to wrap
		# this figure in \resizebox{\linewidth}, which made every number here a
		# RATIO — the drawing was authored at ~21.5 units and squeezed to the
		# 16.5 cm text block, so the boxes, the type and the gaps between the
		# boxes all shrank together and a wider layout bought no extra air, it
		# only scaled itself away. The \resizebox is gone; these numbers now
		# land on the page as written, and the two halves of the USER's
		# constraint are set independently: the BOX is 1.75 x 0.44 cm at 6.5 pt
		# (it printed 2.07 x 0.55 at ~7.7 pt through the resizebox), while the
		# row pitch leaves 0.55 cm of clear vertical air between one box and
		# the next (it printed 0.48 cm) and the inner skip channels stand
		# 0.58 cm off the boxes they run past (0.31 cm). Total: 14.7 x 9.0 cm
		# against 16.5 x 10.1 --- about 11 % smaller in BOTH dimensions with
		# more air on every edge channel, which is the pair of things that
		# cannot be had at once from a single scale factor.
		# FLOORS, so a future edit does not squeeze this back: the box width is
		# set by `Test-Logic-Reset` at the state font (~1.7 cm of type), and
		# the outer flank must clear the self-loop bulge, which reaches about
		# 0.8 cm past the node.
		HW, HH = 0.875, 0.22           # half width / half height of a state box
		TOP = 0.00                     # the top row
		xTLR, xRTI = 0.00, 2.60
		cx = {'dr': 5.60, 'ir': 10.20}
		rows = [-1.00, -1.99, -2.98, -3.97, -4.96, -5.95]   # capture .. update
		yWrapT, yWrapS = 0.85, 1.45    # the two returns over the top
		yRetD, yRetI = -6.85, -7.55    # the two returns along the bottom
		xRiseD, xRiseI = 7.80, 12.95   # the two Update -> Select-DR risers

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
		s += '\tst/.style={draw, thick, rounded corners=2pt, align=center, font=\\sffamily\\fontsize{6.5}{7.5}\\selectfont, inner sep=1.0pt, minimum width=' + P(2 * HW) + 'cm, minimum height=' + P(2 * HH) + 'cm, fill=black!4},\n'
		s += '\ttlr/.style={st, fill=black!18, very thick},\n'
		s += '\ttms0/.style={->, >=Stealth, semithick},\n'
		s += '\ttms1/.style={->, >=Stealth, semithick, densely dashed},\n'
		s += '\tel/.style={font=\\sffamily\\fontsize{5.5}{6.5}\\selectfont, inner sep=1.0pt, fill=white},\n'
		s += '\tkey/.style={font=\\sffamily\\scriptsize, align=left, text width=2.95cm},\n'
		s += '\tkeylab/.style={font=\\sffamily\\scriptsize, anchor=west}]\n'
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
			'''A self-loop on the OUTWARD-facing side of the node.'''
			dst = self._TAP_NEXT[src][tms]
			edges.append((src, dst))
			sty = 'tms1' if tms else 'tms0'
			out, inn = (340, 20) if sgn > 0 else (200, 160)
			x, y = pos[src]
			s_ = '\\draw[' + sty + '] (s' + str(src) + ') to[loop, out=' + str(out) + ', in=' + str(inn) + ', looseness=6] (s' + str(src) + ');\n'
			s_ += '\\node[el] at (' + P(x + sgn * (HW + 0.72)) + ', ' + P(y) + ') {' + str(tms) + '};\n'
			return s_

		# ---- the top row ------------------------------------------------
		s += loop(0, 1, -1)                                   # TLR holds on 1
		s += emit(0, 0, '(s0.east) -- (s1.west)', (xTLR + HW + xRTI - HW) / 2.0, TOP)
		s += '\\draw[tms0] (s1) to[loop, out=115, in=65, looseness=6] (s1);\n'
		edges.append((1, self._TAP_NEXT[1][0]))
		s += '\\node[el] at (' + P(xRTI) + ', ' + P(TOP + 0.98) + ') {0};\n'
		s += emit(1, 1, '(s1.east) -- (s2.west)', (xRTI + HW + cx['dr'] - HW) / 2.0, TOP)
		s += emit(2, 0, '(s2.south) -- (s3.north)', cx['dr'], (TOP - HH + rows[0] + HH) / 2.0)
		s += emit(2, 1, '(s2.east) -- (s9.west)', (cx['dr'] + HW + cx['ir'] - HW) / 2.0 + 1.00, TOP)
		s += emit(9, 0, '(s9.south) -- (s10.north)', cx['ir'], (TOP - HH + rows[0] + HH) / 2.0)
		# Select-IR on a 1 is the last hop of the five-ones recovery.
		s += emit(9, 1, '(s9.north) -- (' + P(cx['ir']) + ', ' + P(yWrapT) + ') -- (' + P(xTLR) + ', ' + P(yWrapT) + ') -- (s0.north)',
			(cx['ir'] + xTLR) / 2.0 + 2.60, yWrapT)

		# ---- the two lobes, identical in shape --------------------------
		# sgn = which side is the OUTWARD one for this lobe.
		for lobe, sgn, base in (('dr', -1.0, 3), ('ir', +1.0, 10)):
			c = cx[lobe]
			cap, shf, ex1, pau, ex2, upd = [base + k for k in range(6)]
			# Both flank channels are quoted as clearance FROM THE BOX EDGE, so
			# they hold their air when the box changes size: 0.62 cm for the
			# inner skips (it was 0.31 cm on the page) and 1.35 cm for the outer
			# retry path, which also has to clear the self-loop bulge.
			xOut = c + sgn * (HW + 1.20)      # Exit2 -> Shift, on the outside
			xIn = c - sgn * (HW + 0.58)       # the two forward skips, inside
			aOut = 'west' if sgn < 0 else 'east'
			aIn = 'east' if sgn < 0 else 'west'

			# straight down the spine
			s += emit(cap, 0, '(s%d.south) -- (s%d.north)' % (cap, shf), c, (rows[0] - HH + rows[1] + HH) / 2.0)
			s += emit(shf, 1, '(s%d.south) -- (s%d.north)' % (shf, ex1), c, (rows[1] - HH + rows[2] + HH) / 2.0)
			s += emit(ex1, 0, '(s%d.south) -- (s%d.north)' % (ex1, pau), c, (rows[2] - HH + rows[3] + HH) / 2.0)
			s += emit(pau, 1, '(s%d.south) -- (s%d.north)' % (pau, ex2), c, (rows[3] - HH + rows[4] + HH) / 2.0)
			s += emit(ex2, 1, '(s%d.south) -- (s%d.north)' % (ex2, upd), c, (rows[4] - HH + rows[5] + HH) / 2.0)
			# the two self-loops, outward
			s += loop(shf, 0, sgn)
			s += loop(pau, 0, sgn)
			# Capture -> Exit1 and Exit1 -> Update: forward skips, inner flank
			s += emit(cap, 1, '(s%d.%s) -- (%s, %s) -- (%s, %s) -- (s%d.north %s)'
				% (cap, aIn, P(xIn), P(rows[0]), P(xIn), P(rows[2] + HH), ex1, aIn), xIn, (rows[0] + rows[2]) / 2.0)
			s += emit(ex1, 1, '(s%d.south %s) -- (%s, %s) -- (%s, %s) -- (s%d.north %s)'
				% (ex1, aIn, P(xIn), P(rows[2] - HH), P(xIn), P(rows[5] + HH), upd, aIn), xIn, (rows[2] + rows[5]) / 2.0)
			# Exit2 -> Shift: the retry path, outer flank, clear of the loops
			s += emit(ex2, 0, '(s%d.%s) -- (%s, %s) -- (%s, %s) -- (s%d.south %s)'
				% (ex2, aOut, P(xOut), P(rows[4]), P(xOut), P(rows[1] - HH), shf, aOut), xOut, (rows[1] + rows[4]) / 2.0)

		# ---- the four returns, two along the bottom and two up top -------
		# Update-DR -> Run-Test/Idle, and Update-DR -> Select-DR up the middle
		s += emit(8, 0, '(s8.south) -- (' + P(cx['dr']) + ', ' + P(yRetD) + ') -- (' + P(xRTI) + ', ' + P(yRetD) + ') -- (s1.south)',
			xRTI, (yRetD + TOP) / 2.0 + 1.20)
		s += emit(8, 1, '(s8.east) -- (' + P(xRiseD) + ', ' + P(rows[5]) + ') -- (' + P(xRiseD) + ', ' + P(TOP - HH) + ') -- (s2.south east)',
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
		kx = xTLR - HW - 0.80
		s += '\\draw[tms0] (' + P(kx) + ', -1.70) -- (' + P(kx + 0.72) + ', -1.70);\n'
		s += '\\node[keylab] at (' + P(kx + 0.84) + ', -1.70) {\\pin{TMS} sampled \\textbf{0}};\n'
		s += '\\draw[tms1] (' + P(kx) + ', -2.30) -- (' + P(kx + 0.72) + ', -2.30);\n'
		s += '\\node[keylab] at (' + P(kx + 0.84) + ', -2.30) {\\pin{TMS} sampled \\textbf{1}};\n'
		s += '\\node[key, anchor=north west] at (' + P(kx) + ', -2.90) {\\textbf{Five} \\pin{TMS}$=$\\textbf{1} clocks reach Test-Logic-Reset from \\textit{any} state in the graph --- the recovery a debugger uses when it has lost track of the machine.};\n'
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
		ann += '\\node[ann, above] at (5,{\\YTOP+0.47}) {\\register{valid} high exactly \\textbf{2} \\register{mclk} --- retired on the \\emph{registered} \\register{ready}};\n'
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-0.35})\n'
		ann += '\t{The Debug Module\'s re-accept lockout is a \\textbf{timer}, not a handshake: it reopens\\\\[-2pt]\n'
		ann += '\t 9 \\register{mclk} after a capture. A master that held \\register{valid} until its response came back would\\\\[-2pt]\n'
		ann += '\t still be asserting it then and would earn a \\textbf{second, duplicate accept} --- two responses for\\\\[-2pt]\n'
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
			(3.4, '\\register{address}', '40:34', '7 bits --- the DMI address'),
			(6.4, '\\register{data}', '33:2', '32 bits --- read result or write value'),
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
			(0.62, '\\texttt{0x10680}', '\\register{data0} --- the abstract data word', 'black!14'),
			(0.62, '\\texttt{0x10684}', '\\register{progbuf0}, \\register{progbuf1}, implicit third word', 'black!10'),
			(0.62, '\\texttt{0x10690}', 'reserved for the Debug Module', 'black!4'),
			(0.62, '\\texttt{0x106F0}', 'saved \\asminline{s0} / \\asminline{s1} --- written by the stub, never by the DM', 'black!10'),
			(0.82, '\\texttt{0x10700}', 'per-hart handshake word \\ \\texttt{0x10700}$+4h$', 'black!14'),
			(1.05, '\\texttt{0x10780}', '\\textbf{trampoline}, 40 words --- \\emph{planted by the Debug Module}', 'black!20'),
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
		s += '\\node[note, anchor=south west] at (' + '%.2f' % xNote + ', ' + '%.2f' % (yBoundary + 0.10) + ') {\\textbf{\\texttt{0x10800}} --- above this line the boot ROM does \\emph{not}\\\\ zero-fill. Everything up here is CODE the Debug Module\\\\ writes before anything reads it: the trampoline\'s last\\\\ eight words, the command body and the epilogue.};\n'
		s += '\\node[note, anchor=north west] at (' + '%.2f' % xNote + ', ' + '%.2f' % (yBoundary - 0.10) + ') {Below \\texttt{0x10800} the boot ROM zeroes \\texttt{0x10000}--\\texttt{0x107FF}\\\\ at every boot, so every DM-written \\emph{data} word starts\\\\ from a known value.};\n'
		s += '\\node[note, anchor=north west] at (' + '%.2f' % (-W / 2.0) + ', ' + '%.2f' % (y - 0.40) + ') {The whole span \\texttt{0x10680}--\\texttt{0x1087F} is reserved. It is ordinary shared RAM --- it cannot be read-only,\\\\ because the Debug Module rewrites the command body at every abstract command.};\n'
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
		s += '\\draw[flow] (-1.15, 2.58) -- node[el, anchor=east, xshift=-3pt] {\\textbf{entry} --- taken at an instruction\\\\ boundary; \\register{dpc} and \\register{dcsr}.\\bitfield{cause}\\\\ are written, then the hart jumps} (-1.15, 0.62);\n'
		s += '\\draw[flow] (1.15, 0.62) -- node[el, anchor=west, xshift=3pt] {\\asminline{dret} --- \\register{dpc} restores the\\\\ program counter, \\register{dcsr}.\\bitfield{prv} the\\\\ privilege level} (1.15, 2.58);\n'
		s += '\\node[note, anchor=north west, align=left] at (5.9, 3.55) {\\textbf{Four ways in}, each recorded in \\register{dcsr}.\\bitfield{cause}:\\\\[3pt]\n'
		s += '\t\\texttt{3} \\ a halt request from the Debug Module ---\\\\ \\hspace*{1.1em}unmaskable, and recognised even in the\\\\ \\hspace*{1.1em}terminal trap state\\\\[2pt]\n'
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
		s += '\\node[align=center, font=\\sffamily] at (0,0) {\\textbf{\\AsicNameForUserGuide}\\\\ ' + pkg.PackageType + '-' + str(pkg.PinCount) + ' --- top view\\\\ \\footnotesize ' + str(pkg.Dimensions[0]) + '$\\times$' + str(pkg.Dimensions[1]) + '\\,' + pkg.Units + ', ' + str(pkg.PinPitch) + '\\,' + pkg.Units + ' pitch};\n'
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
			


	