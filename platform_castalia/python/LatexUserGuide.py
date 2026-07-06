import datetime, os, pathlib
from shutil import copyfile

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

	def __init__(self, gen, outDirectoryPath):
		self.Gen = gen
		if not os.path.isdir(outDirectoryPath):
			raise Exception('outDirectoryPath does not exist: ' + str(outDirectoryPath))
		self.SaveDirectory = outDirectoryPath
		self.IncludeDirectory = self.SaveDirectory + '/include'
		return
	
	def Generate(self):
		self.CopyTemplateTexFiles()
		self.GenerateDefinesFile()
		self.GenerateSystemConfigurationListFile()
		self.GenerateFeaturesList()
		self.GenerateExtraIntroChapters()
		self.GenerateAddressSpaceDiagram()
		self.GenerateInterruptsTable()
		self.GeneratePackagePinsConfigurationTable()
		self.GenerateGpioPinsConfigurationTable()
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

	def GenerateDefinesFile(self):
		# Generate revision date string
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

		s = ''
		for item in defines:
			s += '\\newcommand{\\' + item + '}{' + defines[item] + '}\n'
		
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
		if self.Gen.COMPRESSED_ISA:
			extensions += '[C]'
		
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

			s += pin.Name + ' & ' + pin.IOString + ' & ' + pin.PowerDomain.Description + ' & ' + pin.PowerDomain.PositiveRailPackagePin.Name + '/' + pin.PowerDomain.NegativeRailPackagePin.Name + ' \\\\\n'
		
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
		
		# Create the GPIO pins configuration table
		s = '\\begin{longtable}[c]{ l l l l l l l }\n'
		s += '\\caption{GPIO Pins} \\label{t:gpio-pins} \\\\ \n'

		s += '\\hline & \\textbf{Primary} & \\textbf{Secondary} & \\multicolumn{4}{c}{\\textbf{\\textit{Reset Values}}}\\\\ \\cline{4-7}\n'
		s += '\\textbf{Pin} & \\textbf{Function} & \\textbf{Function} & \\textbf{SEL} & \\textbf{OUT} & \\textbf{DIR} & \\textbf{REN} \\\\  \\hline \\endfirsthead\n'

		s += '\\multicolumn{7}{c}{\\textit{\\tablename\ \\thetable\ continued from previous page}} \\\\ \\hline\n'
		s += ' & \\textbf{Primary} & \\textbf{Secondary} & \\multicolumn{4}{c}{\\textbf{\\textit{Reset Values}}}\\\\ \\cline{4-7}\n'
		s += '\\textbf{Pin} & \\textbf{Function} & \\textbf{Function} & \\textbf{SEL} & \\textbf{OUT} & \\textbf{DIR} & \\textbf{REN} \\\\ \\hline \\endhead\n'

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
					s += '1 \\textit{(Secondary)} & '
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
			


	