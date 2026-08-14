import datetime, os, pathlib
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
		self.GenerateBootFlowDiagram()
		self.GenerateSyncPrimitiveDecisionTree()
		self.GenerateTimerRolloverDiagram()
		self.GenerateTimerOutputCompareDiagram()
		self.GenerateArbiterHandshakeDiagram()
		self.GenerateSpiTimingDiagram()
		self.GenerateSpiByteOrderingDiagram()
		self.GenerateSpiBitOrderingDiagram()
		self.GenerateUartFrameDiagram()
		self.GenerateI2cTransactionDiagram()
		self.GenerateIrqClaimCompleteDiagram()
		self.GenerateMutexClaimDiagram()
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
		defines['NumHarts'] = str(self.Gen.NumHarts)
		defines['NumHartsWord'] = hartWords.get(self.Gen.NumHarts, str(self.Gen.NumHarts))
		defines['MaxHartIndex'] = str(self.Gen.NumHarts - 1)
		defines['VectorsCount'] = str(self.Gen.VectorsCount)
		if self.Gen.SharedWindowSections:
			defines['SharedWindowStartAddress'] = fmthex(min(sec[1] for sec in self.Gen.SharedWindowSections))
			defines['SharedWindowEndAddress'] = fmthex(max(sec[2] for sec in self.Gen.SharedWindowSections))
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
		# CP6 (Castalia-Penta): the soft ORCHESTRATOR hart. False at the
		# defaults, so every orchestrator sentence in the multi-core chapter
		# folds away and the default TRM is byte-identical — the same
		# "inert unless declared" discipline as \ifcqanalog above.
		# \OrchHartIndex is defined UNCONDITIONALLY (the \PmpEntries precedent)
		# so the macro can never dangle inside a folded branch.
		_mgmtHart = getattr(self.Gen, 'MgmtHart', 0)
		s += '\\newcommand{\\OrchHartIndex}{' + str(_mgmtHart) + '}\n'
		s += '\\newif\\iforchpresent\n'
		s += ('\\orchpresenttrue' if _mgmtHart else '\\orchpresentfalse') + '\n'

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

	def GenerateAddressSpaceDiagram(self):
		# (Slot name (None if unused section), SRAM slot number (None if not SRAM), start address, end address)
		slots = [('ROM', None, self.Gen.RomStartAddress, self.Gen.RomEndAddress)]

		if self.Gen.PeripheralMemoryStartAddress - self.Gen.RomEndAddress != 1:
			slots += [(None, None, self.Gen.RomEndAddress + 1, self.Gen.PeripheralMemoryStartAddress - 1)]
		
		slots += [('Peripherals', None, self.Gen.PeripheralMemoryStartAddress, self.Gen.PeripheralMemoryEndAddress)]

		if self.Gen.RamStartAddress - self.Gen.PeripheralMemoryStartAddress != 1:
			slots += [(None, None, self.Gen.PeripheralMemoryEndAddress + 1, self.Gen.RamStartAddress - 1)]
		
		firstRamSlot = min(self.Gen.RamMemorySlotsAvailable)	# same formula as generateMemoryX; the old hardcoded (ramSlot - 2) drew the RAM at the wrong addresses
		for i, ramSlot in enumerate(self.Gen.RamMemorySlotsUsed):
			if i == (len(self.Gen.RamMemorySlotsUsed) - 1):
				thisSlotSize = self.Gen.LastRamMemorySlotSize
			else:
				thisSlotSize = self.Gen.RamMemorySlotSize
			addr = self.Gen.RamStartAddress + ((ramSlot - firstRamSlot) * self.Gen.RamMemorySlotSize)
			slots += [('SRAM{:02d}'.format(ramSlot), ramSlot, addr, addr + thisSlotSize - 1)]
		
		# Create the memory map diagram tex file
		s = '\\begin{bytefield}{8}\n'
		
		startedRAM = False
		for slot in slots:
			name = slot[0]
			sramSlotNum = slot[1]
			startAddr = slot[2]
			endAddr = slot[3]
			size = 1 + slot[3] - slot[2]
			if name is None:
				s += '\\memsection{' + fmthex(startAddr, minDigits=5) + '}{' + fmthex(endAddr, minDigits=5) + '}{3}{\\textit{\\color{lightgray}Unused}} \\\\\n'
			else:
				if (sramSlotNum is not None) and (not startedRAM):
					s += '\\begin{rightwordgroup}{RAM (Total size = ' + str(self.Gen.RamSize // 1024) + ' KiB)}\n'
					startedRAM = True
				height = '3'
				if sramSlotNum in self.Gen.RamMemorySlotsMuxed:
					height = '4'
				s += '\\memsection{' + fmthex(startAddr, minDigits=5) + '}{' + fmthex(endAddr, minDigits=5) + '}{' + height + '}{' + name + ' \\\\ Size = ' + str(size // 1024) + ' KiB'
				if sramSlotNum in self.Gen.RamMemorySlotsMuxed:
					s += ' \\\\ \\textit{Multiplexed'
					if type(self.Gen.RamMemorySlotsMuxed) == dict:
						s +=' with ' + self.Gen.RamMemorySlotsMuxed[sramSlotNum]
					s += '}'
				s += '}\\\\\n'
		s = s[:-3] + '\n'
		s += '\\end{rightwordgroup}\n'

		# Add the multi-core shared window sections (if any)
		lastUsedAddress = slots[-1][3]
		if self.Gen.SharedWindowSections is not None and len(self.Gen.SharedWindowSections) > 0:
			s += '\\\\\n'
			s += '\\begin{rightwordgroup}{Shared window\\\\(all harts, arbitrated)}\n'
			prevEnd = slots[-1][3]
			for name, startAddr, endAddr, desc in self.Gen.SharedWindowSections:
				if startAddr - prevEnd != 1:
					s += '\\memsection{' + fmthex(prevEnd + 1, minDigits=5) + '}{' + fmthex(startAddr - 1, minDigits=5) + '}{3}{\\textit{\\color{lightgray}Reserved}} \\\\\n'
				size = 1 + endAddr - startAddr
				if size >= 1024:
					sizeStr = str(size // 1024) + ' KiB'
				else:
					sizeStr = str(size) + ' B'
				s += '\\memsection{' + fmthex(startAddr, minDigits=5) + '}{' + fmthex(endAddr, minDigits=5) + '}{3}{' + name + ' \\\\ Size = ' + sizeStr + '} \\\\\n'
				prevEnd = endAddr
			s = s[:-3] + '\n'
			s += '\\end{rightwordgroup}\n'
			lastUsedAddress = prevEnd

		if self.Gen.NativeSpiFlashMemoryReadAccess and not self.Gen.NativeSpiFlashMemoryWriteAccess:
			s += '\\\\\n'
			s += '\\memsection{' + fmthex(lastUsedAddress + 1, minDigits=7) + '}{' + fmthex(0x0FFFFFF, minDigits=7) + '}{3}{\\textit{\\color{lightgray}Unused}} \\\\\n'
			s += '\\memsection{' + fmthex(0x1000000) + '}{' + fmthex(0x1FFFFFF) + '}{4}{SPI Flash Native\\\\Memory Access\\\\\\textit{(read only)}} \\\\\n'
		elif self.Gen.NativeSpiFlashMemoryReadAccess and self.Gen.NativeSpiFlashMemoryWriteAccess:
			s += '\\\\\n'
			s += '\\memsection{' + fmthex(lastUsedAddress + 1, minDigits=7) + '}{' + fmthex(0x0FFFFFF, minDigits=7) + '}{3}{\\textit{\\color{lightgray}Unused}} \\\\\n'
			s += '\\memsection{' + fmthex(0x1000000) + '}{' + fmthex(0x1FFFFFF) + '}{3}{SPI Flash Native\\\\Memory Access} \\\\\n'
		
		s += '\\end{bytefield}\n'
	
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
		keyOrder = ['chipName', 'numHarts', 'managementHart', 'numMutexes', 'registerFileDualPort',
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

	def GenerateSystemBlockDiagram(self):
		'''include/SystemBlockDiagram.tex — configuration-driven top-level block
		   diagram: N hart tiles over the registered boundary, the serializing
		   round-robin arbiter, and the shared-window slaves.'''
		N = self.Gen.NumHarts
		geo = getattr(self.Gen, 'McuMpGeometry', None) or {'shAw': 15, 'sharedRamBanks': 4, 'npu': True}
		banks = geo['sharedRamBanks']
		npu = geo['npu']
		flashBase = fmthex(1 << (geo['shAw'] + 2))
		romKiB = self.Gen.RomSize // 1024
		tcmKiB = self.Gen.RamMemorySlotSize // 1024
		nMtx = 0
		for p in self.Gen.Peripherals:
			if p.Name == 'MUTEX':
				nMtx = len(p.Registers)

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
		slaves = []
		slaves.append(('Boot ROM\\\\ \\texttt{0x0} (' + str(romKiB) + '\\,KiB)\\\\ all harts reset here', 2.9))
		slaves.append(('Peripherals \\texttt{0x4000}\\\\ 16 slots $+$ CLINT\\\\ ' + str(nMtx) + ' mutexes $+$ IRQ router', 3.6))
		if npu:
			slaves.append(('NPU staging RAM\\\\ \\texttt{0xC000} (16\\,KiB)', 2.9))
		slaves.append(('Shared RAM \\texttt{0x10000}\\\\ ' + str(banks) + ' $\\times$ 16\\,KiB banks', 3.3))
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

		with open(self.IncludeDirectory + '/SystemBlockDiagram.tex', 'w') as f:
			f.write(s)
		return

	def GenerateBootFlowDiagram(self):
		'''include/BootFlowDiagram.tex — the M12 single-ROM boot flow chart
		   (mhartid dispatch, hart-0 SPI boot, tile WFI park + msip loader).'''
		N = self.Gen.NumHarts
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
		s += '\\draw[flow] (who.west) -| node[lab, pos=0.25] {yes: hart 0} (h0a.north);\n'
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

	def _timingPreamble(self, xunit, extra=''):
		'''Shared tikzpicture options for the generated waveform figures.'''
		s = '\\begin{tikzpicture}[\n'
		s += '\tx=' + xunit + ', y=1cm,\n'
		s += '\tlbl/.style={font=' + self._LABEL_FONT + ', anchor=east},\n'
		s += '\tguide/.style={densely dotted, gray!65},\n'
		s += '\tann/.style={font=' + self._NOTE_FONT + ', inner sep=1.5pt},\n'
		s += '\ttim/.style={timing/xunit=' + xunit + ', timing/yunit=' + self._ROW_H + ', semithick,\n'
		s += '\t            timing/d/text/.style={font=' + self._CELL_FONT + '}}' + extra + ']\n'
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
		ann += '\\node[ann, align=left, anchor=north west] at (6.15,{\\YBOT-0.30})\n'
		ann += '\t{\\textit{ghost window:} \\register{req} is stale-high for one\\\\[-2pt]\n'
		ann += '\t cycle after \\register{done} --- masked by \\register{need\\_release}};\n'
		ann += '\\draw[gray!65] (5.5,\\YBOT) -- (5.5,{\\YBOT-0.42}) -- (6.1,{\\YBOT-0.42});\n'
		s = '% Generated mp_arbiter handshake diagram\n'
		s += self._cycleFigure('1.30cm', rows, 6, ann, shade=('5', '6'))
		self._writeInclude('ArbiterHandshakeDiagram.tex', s)
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

	def _cycleFigure(self, xunit, rows, guides, annotations, shade=None):
		'''Shared shape for the cycle-level contract waveforms (arbiter, IRQ
		   claim/complete, mutex, capture). rows = list of (chars, label), TOP
		   FIRST; the y of each row is COMPUTED from _ROW_PITCH rather than
		   written per figure, so changing the waveform height does not silently
		   overlap rows or strand the annotations. The figure exports \\YTOP and
		   \\YBOT so annotations can hang off the grid instead of hardcoding
		   coordinates that go stale with the geometry.'''
		pitch = self._ROW_PITCH
		ybot = -pitch * (len(rows) - 1)
		s = self._timingPreamble(xunit)
		s += '\\def\\YTOP{%.2f}\\def\\YBOT{%.2f}\n' % (float(self._ROW_H[:-2]) + 0.14, ybot - 0.14)
		if shade:
			s += '\\fill[black!7] (' + shade[0] + ',\\YTOP) rectangle (' + shade[1] + ',\\YBOT);\n'
		s += '\\foreach \\k in {1,...,' + str(guides) + '} { \\draw[guide] (\\k,\\YTOP) -- (\\k,\\YBOT); }\n'
		half = float(self._ROW_H[:-2]) / 2.0
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
		   reads, so the claim is atomic with no retry loop.'''
		rows = [
			('16{0.5C}',                                                 '\\register{mclk}'),
			('U 2D{\\asminline{lw} MUTEX0} 4U 2D{\\asminline{sw x0}}',   'hart 0 bus'),
			('3U 2D{\\asminline{lw} MUTEX0} 4U',                         'hart 1 bus'),
			('3D{free} 5D{owned by hart 0} D{free}',                     '\\textit{owner}[0]'),
			('3U D{0} 5U',                                               'hart 0 result'),
			('5U D{1} 3U',                                               'hart 1 result'),
		]
		ann = ''
		ann += '\\node[ann, align=left, anchor=north west] at (0,{\\YBOT-0.35})\n'
		ann += '\t{\\textbf{0} = the mutex was free and is now yours. A non-zero result is the holder\'s\\\\[-2pt]\n'
		ann += '\t \\register{mhartid}$+1$ --- hart 1 must back off and retry. Release with \\asminline{sw x0}.};\n'
		s = '% Generated MUTEX claim/release diagram\n'
		s += self._cycleFigure('1.15cm', rows, 8, ann)
		self._writeInclude('MutexClaimDiagram.tex', s)
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

		x = fabX0
		xs = []
		for t in shown:
			w = 0.90 if t is None else tileW
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
			s += '\\node[tile, minimum width=' + P(w) + 'cm, minimum height=' + P(tileH) + 'cm, font=\\sffamily\\scriptsize] (t' + str(t) + ') at (' + P(tcx) + ', ' + P(yTile) + ') {\\textbf{hart ' + str(t) + '}\\\\ core $+$ TCM};\n'
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
		HW, HH = 1.35, 0.36            # half width / half height of a state box
		TOP = 0.00                     # the top row
		xTLR, xRTI = 0.00, 3.80
		cx = {'dr': 7.90, 'ir': 14.40}
		rows = [-1.75, -3.10, -4.45, -5.80, -7.15, -8.50]   # capture .. update
		yWrapT, yWrapS = 1.60, 2.60    # the two returns over the top
		yRetD, yRetI = -9.80, -10.60   # the two returns along the bottom
		xRiseD, xRiseI = 11.05, 18.45  # the two Update -> Select-DR risers

		pos = {0: (xTLR, TOP), 1: (xRTI, TOP), 2: (cx['dr'], TOP), 9: (cx['ir'], TOP)}
		for k, st in enumerate([3, 4, 5, 6, 7, 8]):
			pos[st] = (cx['dr'], rows[k])
		for k, st in enumerate([10, 11, 12, 13, 14, 15]):
			pos[st] = (cx['ir'], rows[k])

		def P(v):
			return '%.2f' % v

		s = '% Generated TAP state graph (edges transcribed from jtag_dtm.vhd TAP_NEXT)\n'
		s += '\\begin{tikzpicture}[\n'
		s += '\tst/.style={draw, thick, rounded corners=2pt, align=center, font=\\sffamily\\small, minimum width=' + P(2 * HW) + 'cm, minimum height=' + P(2 * HH) + 'cm, fill=black!4},\n'
		s += '\ttlr/.style={st, fill=black!18, very thick},\n'
		s += '\ttms0/.style={->, >=Stealth, semithick},\n'
		s += '\ttms1/.style={->, >=Stealth, semithick, densely dashed},\n'
		s += '\tel/.style={font=\\sffamily\\scriptsize, inner sep=1.5pt, fill=white},\n'
		s += '\tkey/.style={font=\\sffamily\\small, align=left, text width=4.0cm},\n'
		s += '\tkeylab/.style={font=\\sffamily\\small, anchor=west}]\n'
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
			s_ += '\\node[el] at (' + P(x + sgn * (HW + 0.95)) + ', ' + P(y) + ') {' + str(tms) + '};\n'
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
			xOut = c + sgn * (HW + 1.50)      # Exit2 -> Shift, on the outside
			xIn = c - sgn * (HW + 0.80)       # the two forward skips, inside
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
		kx = xTLR - HW - 0.70
		s += '\\draw[tms0] (' + P(kx) + ', -2.40) -- (' + P(kx + 0.90) + ', -2.40);\n'
		s += '\\node[keylab] at (' + P(kx + 1.05) + ', -2.40) {\\pin{TMS} sampled \\textbf{0}};\n'
		s += '\\draw[tms1] (' + P(kx) + ', -3.15) -- (' + P(kx + 0.90) + ', -3.15);\n'
		s += '\\node[keylab] at (' + P(kx + 1.05) + ', -3.15) {\\pin{TMS} sampled \\textbf{1}};\n'
		s += '\\node[key, anchor=north west] at (' + P(kx) + ', -4.05) {\\textbf{Five} \\pin{TMS}$=$\\textbf{1} clocks reach Test-Logic-Reset from \\textit{any} state in the graph --- the recovery a debugger uses when it has lost track of the machine.};\n'
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
			


	