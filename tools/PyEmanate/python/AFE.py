import json
import os, pathlib

from HistogramChannel import HistogramChannel
from PsdChannel import PsdChannel
from HelperFunctions import *

class AFE():
	# Analog front-end object
	ThisFileDirectory = str(pathlib.Path(__file__).parent.absolute())

	# Configuration data
	Index = None
	Name = None
	Parent = None	# Chip
	Peripheral = None

	AdcBits = None

	PhaDma = None
	PsdDma = None

	# Inferred data
	NumBins = None

	# Collected data
	Histogram = None
	Psd = None

	

	@staticmethod
	def CreateFromDict(d:dict, parentChip):
		if 'Type' not in d or d['Type'] != 'AFE':
			return None
		afe = AFE()
		afe.Index = d['Index']
		afe.Name = d['NameTemplate'].replace('x', fmthex(afe.Index, 1)[2:])
		afe.Parent = parentChip
		peripheralName = d['PeripheralNameTemplate'].replace('x', fmthex(afe.Index, 1)[2:])
		afe.Peripheral = parentChip.GetPeripheral(peripheralName)
		afe.AdcBits = d['AdcBits']
		afe.NumBins = 2**afe.AdcBits
		if 'PhaDma' in d:
			afe.PhaDma = PhaDmaInterface.CreateFromDict(d['PhaDma'], afe.Peripheral)
		if 'PsdDma' in d:
			afe.PsdDma = PsdDmaInterface.CreateFromDict(d['PsdDma'], afe.Peripheral)
		afe.Histogram = HistogramChannel.CreateFromAFE(afe)
		afe.Psd = PsdChannel.CreateFromAFE(afe)
		return afe
	
	
		
		
	

class PhaDmaInterface():
	StartAddress = None	# The address in the MCU where the AFE PHA DMA memory begins
	BytesPerBin = None	# Number of bytes per bin.
	WordBytesReversed = None	# True when every word needs bytes 0 and 3 swapped and bytes 1 and 2 swapped, False otherwise
	DisableDmaToAccess = None	# True when the DMA must be disabled in order to read the histogram, False otherwise
	EnableDmaRegister = None	# The register that contains the bit that enables/disables the DMA
	EnableDmaBitNum = None	# The index/number of the bit that enables/disables the DMA within EnableDmaRegisterName

	@staticmethod
	def CreateFromDict(d:dict, peripheral):
		pha = PhaDmaInterface()
		startAddress = d['StartAddress']
		if type(startAddress) == str:
			if startAddress.startswith('0x'):
				pha.StartAddress = int(startAddress[2:], 16)
			else:
				pha.StartAddress = int(startAddress)
		else:
			pha.StartAddress = startAddress
		pha.BytesPerBin = d['BytesPerBin']
		pha.WordBytesReversed = d['WordBytesReversed']
		pha.DisableDmaToAccess = d['DisableDmaToAccess']
		pha.EnableDmaRegister = peripheral.GetRegister(address=(peripheral.BaseAddress + d['EnableDmaRegisterByteOffset']))
		pha.EnableDmaBitNum = d['EnableDmaBitNum']
		return pha

class PsdDmaInterface():
	StartAddress = None	# The address in the MCU where the AFE PHA DMA memory begins
	WordBytesReversed = None	# True when every word needs bytes 0 and 3 swapped and bytes 1 and 2 swapped, False otherwise
	TotalElements = None	# The total number of PSD elements. A single PSD element includes 1 late PSD ADC sample and 1 early PSD ADC sample.
	EarlySampleFirst = None	# True when the early PSD ADC samples comes before the late PSD ADC sample, False otherwise
	DisableDmaToAccess = None	# True when the DMA must be disabled in order to read the histogram, False otherwise
	EnableDmaRegisterName = None	# The name of the register that contains the bit that enables/disables the DMA
	EnableDmaBitNum = None	# The index/number of the bit that enables/disables the DMA within EnableDmaRegisterName

	@staticmethod
	def CreateFromDict(d:dict, peripheral):
		psd = PhaDmaInterface()
		startAddress = d['StartAddress']
		if type(startAddress) == str:
			if startAddress.startswith('0x'):
				psd.StartAddress = int(startAddress[2:], 16)
			else:
				psd.StartAddress = int(startAddress)
		else:
			psd.StartAddress = startAddress
		psd.WordBytesReversed = d['WordBytesReversed']
		psd.TotalElements = d['TotalElements']
		psd.EarlySampleFirst = d['EarlySampleFirst']
		psd.DisableDmaToAccess = d['DisableDmaToAccess']
		psd.EnableDmaRegister = peripheral.GetRegister(address=(peripheral.BaseAddress + d['EnableDmaRegisterByteOffset']))
		psd.EnableDmaBitNum = d['EnableDmaBitNum']
		return psd