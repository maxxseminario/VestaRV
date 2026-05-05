#!/usr/bin/env python3

import numpy as np

class ProportionalTimeConstant():
	'''
	Represents a decaying exponential in the kth piece of the pulse current equation:
	i_k(t) = (Q_k / tau_k) * exp(-t / tau_k)
	where Q_k is the amount of charge deposited in this piece of the current pulse and tau_k is the time constant for this piece.
	Note that the integral from t = 0 to infinity is equal to Q_k.
	
	This changes slightly when the rise time is accounted for. The equation becomes:
	i_k(t) = (CurrentCoefficient / tau_k) * (exp(-t / tau_k) - exp(-t / tau_r))
	where tau_r is the rise time and CurrentCoefficient is the coefficient that makes this piece of the current pulse produce the correct amount of charge despite the rise time.
	Note that the integral is still Q_k if CurrentCoefficient is calculated correctly
	The integral from 0 to t_f is thus: CurrentCoefficient * (1 + (tau_r/tau_k) * (exp(-t_f/tau_r) - 1) - exp(-t_f/tau_k))
	
	The "intensity" is defined as Q_k / tau_k
	'''
	TimeConstant = None	# The time constant of the exponential (seconds)
	ChargeProportion = None	# The coefficient that keeps the charge that this piece contributes equal to ChargeProportion despite the inclusion of the rise time
	
	CurrentCoefficient = None	# The constant needed to produce the charge proportion from ChargeProportion
	CutoffFrequency = None	# The cutoff frequency of this piece of the current equation, equal to 
	
	def __init__(self, TimeConstant, ChargeProportion):
		self.TimeConstant = TimeConstant
		self.ChargeProportion = ChargeProportion
	
	def GetValueAtTime(self, time, RiseTimeConstant):
		return (self.CurrentCoefficient / self.TimeConstant) * (np.exp(-time / self.TimeConstant) - np.exp(-time / RiseTimeConstant))
	
	def GetIntegratedValueAtTime(self, time, RiseTimeConstant):
		return self.CurrentCoefficient * (1 + (RiseTimeConstant/self.TimeConstant) * (np.exp(-time/RiseTimeConstant) - 1) - np.exp(-time/self.TimeConstant))

class Detector():
	
	Name = None
	NameForFile = None
	
	Luminosity = None	# The number of visible light photons per incident gamma ray energy (photons/eV)
	OpticalCouplingEfficiency = None # The ratio of the visible light photons produced by the scintillator that are coupled to the photocathode of the PMT (unitless, between 0 and 1)
	QuantumEfficiency = None	# The ratio of free electrons produced at the photocathode for PMT amplification to the total number of visible light photons that arrive at the photocathode (number of electrons/number of photons)
	RiseTimeConstant = None	# The time constant that produces the desired rise time (seconds). Note that the RiseTimeConstant is NOT that actual rise time. You will need to do some manual twiddling of this figure to iteratively close in on the proper rise time.
	Resolution = None	# The resolution of the scintillator, a value between 0 and 1 (percent / 100)
	ProportionalTimeConstants = None	# A list of ProportionalTimeConstant objects. Each has two elements: time constant (seconds), and intensity proportion (number 0 to 1, all sum to unity)
	
	TimeTo50Pct = None	# The time it takes to integrate 50% of the total charge
	TimeTo90Pct = None	# The time it takes to integrate 90% of the total charge
	TimeTo99Pct = None	# The time it takes to integrate 99% of the total charge
	TimeTo1Lsb = None	# The time it takes to integrate 1023/1024 of the total charge
	RiseTime = None		# The estimated rise time (aka peaking time)
	
	def __init__(self, Name, NameForFile):
		self.Name = Name
		self.NameForFile = NameForFile
		return
	
	def GammaToVisibleLight(self, energy_eV):
		'''
		Calculates the number of visible light photons produced by a scintillator of a given luminosity by an incident gamma ray
		
		Returns: NumVisiblePhotons, the number of visible light photons produced by the scintillator after the gamma ray strikes it (unitless)
		'''
		return energy_eV * self.Luminosity

	def PmtAmplification(self, PmtGain, NumVisiblePhotons):
		'''
		Calculates the amount of charge produced from the number of visible light photons striking the photocathode of the PMT
		
		@PmtGain: Linear gain of electrons in the PMT from photocathode to anode (unitless, large)
		
		Returns: Charge, the charge produced by the PMT from the visible light photons (Coulombs)
		'''
		NumElectrons = NumVisiblePhotons * self.OpticalCouplingEfficiency * self.QuantumEfficiency * PmtGain
		q_e = 1.607e-19	# Elementary charge (Coulombs per electron)
		Charge = NumElectrons * q_e
		return Charge
		
	def GammaToChargePmt(self, PmtGain, energy_eV):
		'''
		Calculates the amount of charge produced by a detector from an incident gamma ray energy
		
		@PmtGain: Linear gain of electrons in the PMT from photocathode to anode (unitless, large)
		
		Returns: Charge, the charge produced by the detector from the incident gamma ray (Coulombs)
		'''
		NumVisiblePhotons = self.GammaToVisibleLight(energy_eV)
		Charge = self.PmtAmplification(PmtGain, NumVisiblePhotons)
		return Charge
		
	def ChargeIntegrationToVoltageCsa(self, Charge, Cfb):
		'''
		Calculates the voltage output of the CSA after it has integrated the incoming charge pulse
		
		@Charge: Total charge in the gamma pulse (Coulombs)
		@Cfb: Capacitance of the feedback capacitor (Farads)
		
		Returns: CsaOutVoltage, the output voltage of the CSA
		'''
		return Charge / Cfb
	
	def AddProportionalTimeConstant(self, TimeConstant, ChargeProportion):
		ptc = ProportionalTimeConstant(TimeConstant, ChargeProportion)
		if self.ProportionalTimeConstants is None:
			self.ProportionalTimeConstants = []
		self.ProportionalTimeConstants.append(ptc)
	
	def CalculateCurrentCoefficients(self):
		'''
		Uses the generalized equation from Joseph's Mathematica document "CsI(Na) Charge Pulse"
		'''
		# Calculate the product of all the time constants (except the rise time)
		timeConstantsProduct = 1.0
		for ptc in self.ProportionalTimeConstants:
			timeConstantsProduct *= ptc.TimeConstant
		
		# Calculate the denominator  which is shared by all charge proportions
		denominator = timeConstantsProduct
		for ptc in self.ProportionalTimeConstants:
			sub = ptc.ChargeProportion * self.RiseTimeConstant
			for ptc2 in self.ProportionalTimeConstants:
				if ptc is ptc2:
					continue
				sub *= ptc2.TimeConstant
			denominator -= sub
		
		# Calculate the numerators, and then finish the calculation for each charge proportion
		for ptc in self.ProportionalTimeConstants:
			numerator = ptc.ChargeProportion * timeConstantsProduct
			ptc.CurrentCoefficient = numerator / denominator
			ptc.CutoffFrequency = 1 / (2 * np.pi * (ptc.TimeConstant + self.RiseTimeConstant))
		
		return
	
	def GetCurrentAtTime(self, time, TotalCharge):
		current = None
		
		for ptc in self.ProportionalTimeConstants:
			if current is None:
				current = ptc.GetValueAtTime(time, self.RiseTimeConstant)
			else:
				current += ptc.GetValueAtTime(time, self.RiseTimeConstant)
		current *= TotalCharge
		
		return current
	
	def GetIntegratedChargeAtTime(self, time, TotalCharge):
		charge = None
		
		for ptc in self.ProportionalTimeConstants:
			if charge is None:
				charge = ptc.GetIntegratedValueAtTime(time, self.RiseTimeConstant)
			else:
				charge += ptc.GetIntegratedValueAtTime(time, self.RiseTimeConstant)
		charge *= TotalCharge
		
		return charge
	
	def GetCurrentSamples(self, TotalCharge, TimeStep, StopTime, lastPointZeroCurrent=False):
		time = np.arange(0, StopTime + TimeStep/2, TimeStep)
		current = np.zeros(time.shape)
		
		for ptc in self.ProportionalTimeConstants:
			current += ptc.GetValueAtTime(time, self.RiseTimeConstant)
		current *= TotalCharge
		
		if lastPointZeroCurrent:
			current[-1] = 0.0
		
		# Make the time and current data into column vectors, then concatenate
		time = np.reshape(time, (-1, 1))
		current = np.reshape(current, (-1, 1))
		data = np.concatenate((time, current), axis=1)
		
		return data
	
	def SavePwl(self, path, timeAndCurrentMatrix, timeDigits=6, currentDigits=4):
		# Save the data
		np.savetxt(path, timeAndCurrentMatrix, fmt=['%.' + str(timeDigits) + 'e', '%.' + str(currentDigits) + 'e'], delimiter=',')
		
		return
	
	def GenerateRandomPulses(self, timeStep, pulseTimeLength, numPulses, countRate, minEnergy_eV, maxEnergy_eV, pmtGain, prune=True, returnEnergies=False):
		
		# Generate a list of random delay times that each pulse waits before the next begins using a Poisson Random Process. This follows the function T = -ln(U)/lambda where U is a uniform random variable from 0 to 1 and lambda is the count rate
		poissonArrivalTimes = [-np.log2(np.random.uniform()) / countRate for i in range(numPulses - 1)]
		
		# Accumulate the arrival times to get the start time of each pulse
		pulseStartTimes = [0]
		for poissonArrivalTime in poissonArrivalTimes:
			pulseStartTimes.append(pulseStartTimes[-1] + poissonArrivalTime)
		
		# Round the start times to the nearest multiple of timeStep
		for i, startTime in enumerate(pulseStartTimes):
			pulseStartTimes[i] = timeStep * round(startTime / timeStep)
		
		# Generate the pulses, delay them, and put them in the main matrix (unsorted)
		time = np.arange(0, pulseStartTimes[-1] + pulseTimeLength + timeStep/2, timeStep)
		current = np.zeros(len(time))
		
		energies = []
		for pulseStartTime in pulseStartTimes:
			# Calculate the index in the time and current array that this pulse start time corresponds to
			index = int(round(pulseStartTime / timeStep))
			
			# Select the energy of the pulse
			energy_eV = maxEnergy_eV
			if minEnergy_eV < maxEnergy_eV:
				energy_eV = np.random.uniform(low=minEnergy_eV, high=maxEnergy_eV)
			energies.append(energy_eV)
			
			# Get the total charge in the pulse
			Q_tot = self.GammaToChargePmt(PmtGain=pmtGain, energy_eV=energy_eV)	# Coulombs
			
			# Create the pulse
			pulseWaveform = self.GetCurrentSamples(Q_tot, timeStep, pulseTimeLength, lastPointZeroCurrent=True)
			pulseCurrent = pulseWaveform[:, 1]
			numSamps = len(pulseCurrent)
			
			# Accumulate the pulse with the existing current waveform
			current[index:index+numSamps] += pulseCurrent
		
		# Make the time and current data into column vectors, then concatenate
		time = np.reshape(time, (-1, 1))
		current = np.reshape(current, (-1, 1))
		data = np.concatenate((time, current), axis=1)
		
		# Remove data points that have the same current value for at least three data points in a row
		if prune:
			endIndex = None
			for i in reversed(range(data.shape[0] - 1)):
				if data[i, 1] == data[i + 1, 1]:
					if endIndex is None:
						endIndex = i + 1
				elif endIndex is not None:
					if (endIndex - i) >= 2:
						# Found the beginning of the string of same values
						data = np.concatenate((data[:i + 1, :], data[endIndex:, :]))
					endIndex = None
		
		if returnEnergies:
			return data, energies
		return data
	
	def GetTimeToChargePct(self, percent, TimeStep, StopTime):
		if (percent < 0) or (percent >= 1):
			raise Exception('"percent" cannot be below 0 or above 1')
		
		time = np.arange(0, StopTime + TimeStep/2, TimeStep)
		charge = self.GetIntegratedChargeAtTime(time, TotalCharge=1)
		
		for i in range(len(time)):
			finishTime = time[i]
			integratedChargePct = charge[i]
			if integratedChargePct >= percent:
				return finishTime
		
		# Not enough samples to get the time
		raise Exception('"StopTime" is too short to approximate the time it takes to integrate the percentage of charge')
	
	def GenerateFiles(self, directoryPath, TimeStep, StopTime):
		
		# Generate file with total charge equal to 1 Coulomb
		Q_tot = 1	# Coulombs
		data = self.GetCurrentSamples(Q_tot, TimeStep, StopTime)	# seconds, amps
		self.SavePwl(directoryPath + '/' + self.NameForFile + '_charge=1C.csv', data)
		
		# Calculate rise time
		maxIndex = int(np.average(np.argmax(data[:,1])))
		self.RiseTime = data[maxIndex, 0]
		
		# Get integration time data
		ts = self.RiseTime / 100
		st = max([ptc.TimeConstant for ptc in self.ProportionalTimeConstants]) * 10
		self.TimeTo50Pct = self.GetTimeToChargePct(0.50, ts, st)
		self.TimeTo90Pct = self.GetTimeToChargePct(0.90, ts, st)
		self.TimeTo99Pct = self.GetTimeToChargePct(0.99, ts, st)
		self.TimeTo1Lsb = self.GetTimeToChargePct(1023/1024, ts, st)
		
		# Generate a file that can be scaled depending on PMT gain and gamma ray energy
		Q_tot = self.GammaToChargePmt(PmtGain=1, energy_eV=1e3)	# Coulombs
		data = self.GetCurrentSamples(Q_tot, TimeStep, StopTime, lastPointZeroCurrent=True)	# seconds, amps
		self.SavePwl(directoryPath + '/' + self.NameForFile + '_pmtGain=1_energy=1keV.csv', data)
		
		# Generate a file with the detector parameters
		s = 'Detector parameters for ' + self.Name + '\n'
		s += 'Luminosity (photons/eV) = ' + str(self.Luminosity) + '\n'
		s += 'Optical Coupling Efficiency = ' + str(self.OpticalCouplingEfficiency) + '\n'
		s += 'Quantum Efficiency (# electrons/ # photons) = ' + str(self.QuantumEfficiency) + '\n'
		s += 'Rise Time Constant (not actual rise time) = ' + str(self.RiseTimeConstant) + '\n'
		s += 'Resolution (%) = ' + str(self.Resolution * 100) + '\n'
		for i, ptc in enumerate(self.ProportionalTimeConstants):
			s += 'Proportional Time Constant #' + str(i + 1) + ' time constant (seconds) = ' + str(ptc.TimeConstant) + '\n'
			s += 'Proportional Time Constant #' + str(i + 1) + ' charge proportion (%) = ' + str(ptc.ChargeProportion * 100) + '\n'
			s += 'Proportional Time Constant #' + str(i + 1) + ' current coefficient = ' + str(ptc.CurrentCoefficient) + '\n'
			s += 'Proportional Time Constant #' + str(i + 1) + ' cutoff frequency (Hz) = ' + str(ptc.CutoffFrequency) + '\n'
		s += 'Time to integrate 50% of total charge (seconds) = ' + str(self.TimeTo50Pct) + '\n'
		s += 'Time to integrate 90% of total charge (seconds) = ' + str(self.TimeTo90Pct) + '\n'
		s += 'Time to integrate 99% of total charge (seconds) = ' + str(self.TimeTo99Pct) + '\n'
		s += 'Time to integrate for 1 LSB of resolution of total charge (seconds) = ' + str(self.TimeTo1Lsb) + '\n'
		s += 'Estimated rise time (seconds) = ' + str(self.RiseTime) + '\n'
		with open(directoryPath + '/' + self.NameForFile + ' Detector Parameters.txt', 'w', newline='\n') as f:
			f.write(s)
		
		return
		
		

# CsI(Na) detector parameters
# These were taken from Joseph's "Analysis of CsI(Na) Charge Pusle" Mathematica document. I do not know where he originally got these parameters
CsINa = Detector('CsI(Na)', 'CsINa')
CsINa.Luminosity = 45e-3	# (number of electrons/number of photons). Taken from https://scintillator.lbl.gov . The values it lists are 38e-3, 49e-3, 43e-3, 49e-3, and 46e-3 (mean = 45e-3)
CsINa.OpticalCouplingEfficiency = 0.9 # (unitless, between 0 and 1)
CsINa.QuantumEfficiency = 0.3	# The ratio of free electrons produced at the photocathode for PMT amplification to the total number of visible light photons that arrive at the photocathode (number of electrons/number of photons, 0 to 1)
CsINa.Resolution = 7.4 / 100	# Taken from https://scintillator.lbl.gov .
# The timing parameters were taken from both:
# Syntfeld-Kazuch: Non-Proportionality Components in Doped CsI (for the decay time constants and ratios)
# Sun: The fast light of CsI(Na) Crystals (for the rise time constant)
CsINa.RiseTimeConstant = 10e-9	# From Sun. Actual rise time is 40 ns. Time constant is adjusted to give about a 40 ns rise time
CsINa.AddProportionalTimeConstant(TimeConstant=480e-9, ChargeProportion=0.38)	# From Syntfeld-Kazuch
CsINa.AddProportionalTimeConstant(TimeConstant=2.4e-6, ChargeProportion=0.36)	# From Syntfeld-Kazuch
CsINa.AddProportionalTimeConstant(TimeConstant=14e-6,  ChargeProportion=0.26)	# From Syntfeld-Kazuch
CsINa.CalculateCurrentCoefficients()




# NaI(Tl) detector parameters
NaITl = Detector('NaI(Tl)', 'NaITl')
NaITl.Luminosity = 44.25e-3	# (number of electrons/number of photons). Taken from https://scintillator.lbl.gov . The values it lists are 45e-3, 43e-3, 44e-3, and 45e-3 (mean = 44.25e-3)
NaITl.OpticalCouplingEfficiency = 0.9 # (unitless, between 0 and 1)
NaITl.QuantumEfficiency = 0.3	# (number of electrons/number of photons, 0 to 1)
NaITl.Resolution = 5.6 / 100	# Taken from https://scintillator.lbl.gov . The values it lists are 7.1% and 5.6%
NaITl.RiseTimeConstant = 2.1e-9	# From Weber. Actual rise time is between 5 ns and 27 ns. Time constant is adjusted to give about a 10 ns rise time
NaITl.AddProportionalTimeConstant(TimeConstant=225e-9, ChargeProportion=0.90)	# From Swiderski
NaITl.AddProportionalTimeConstant(TimeConstant=1.04e-6, ChargeProportion=0.10)	# From Swiderski
NaITl.CalculateCurrentCoefficients()





# LaBr3 detector parameters
LaBr = Detector('LaBr3(Ce)', 'LaBr3Ce')
LaBr.Luminosity = 68.7e-3	# (number of electrons/number of photons). Taken from https://scintillator.lbl.gov . The values it lists are 61e-3, 73e-3, 74e-3, 75e-3, 68.6e-3, 78e-3, 64e-3, and 56e-3 (mean = 68.7e-3)
LaBr.OpticalCouplingEfficiency = 0.9 # (unitless, between 0 and 1)
LaBr.QuantumEfficiency = 0.3	# (number of electrons/number of photons, 0 to 1)
LaBr.Resolution = 2.7 / 100	# Taken from https://scintillator.lbl.gov . The values it lists are 2.0% and 3.2%
LaBr.RiseTimeConstant = 5.36e-9	# From Glondo. Actual rise time is 9.4 ns. Time constant is adjusted to give about a 9.4 ns rise time
LaBr.AddProportionalTimeConstant(TimeConstant=19e-9, ChargeProportion=0.56)	# From Glondo
LaBr.AddProportionalTimeConstant(TimeConstant=15.2e-9, ChargeProportion=0.28)	# From Glondo
LaBr.AddProportionalTimeConstant(TimeConstant=55e-9, ChargeProportion=0.16)	# From Glondo
LaBr.CalculateCurrentCoefficients()





# CeBr3 detector parameters
CeBr = Detector('CeBr3', 'CeBr3')
CeBr.Luminosity = 63e-3	# (number of electrons/number of photons). Taken from https://scintillator.lbl.gov . The values it lists are 68e-3 and 58e-3 (mean = 63e-3)
CeBr.OpticalCouplingEfficiency = 0.9 # (unitless, between 0 and 1)
CeBr.QuantumEfficiency = 0.3	# (number of electrons/number of photons, 0 to 1)
CeBr.Resolution = 3.2 / 100	# Taken from https://scintillator.lbl.gov . The valueis between 3.2% and 3.4%
CeBr.RiseTimeConstant = 14e-12	# From Kanai. Actual rise time is 100 ps. Time constant is adjusted to give about a 100 ps rise time
CeBr.AddProportionalTimeConstant(TimeConstant=17e-9, ChargeProportion=1)	# From Kanai
CeBr.CalculateCurrentCoefficients()




# Poisson arrivals long-duration pulses

#data = CsINa.GenerateRandomPulses(timeStep=2e-9, pulseTimeLength=100e-6, numPulses=50, countRate=30e3, minEnergy_eV=30e3, maxEnergy_eV=1e6, pmtGain=1)
#CsINa.SavePwl(saveDirectory + '/CsINa_poisson_pmtGain=1.csv', data, timeDigits=6)

#data = LaBr.GenerateRandomPulses(timeStep=10e-12, pulseTimeLength=500e-9, numPulses=30, countRate=30e3, minEnergy_eV=30e3, maxEnergy_eV=1e6, pmtGain=1)
#LaBr.SavePwl(saveDirectory + '/LaBr3Ce_poisson_pmtGain=1.csv', data, timeDigits=6)

if __name__ == "__main__":
	saveDirectory = '../sims/detectors'
	CsINa.GenerateFiles(saveDirectory, TimeStep=2e-9, StopTime=100e-6)
	NaITl.GenerateFiles(saveDirectory, TimeStep=0.2e-9, StopTime=10e-6)
	LaBr.GenerateFiles(saveDirectory, TimeStep=10e-12, StopTime=500e-9)
	CeBr.GenerateFiles(saveDirectory, TimeStep=10e-12, StopTime=200e-9)
	