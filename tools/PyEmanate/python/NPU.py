#!/usr/bin/env python3
import sys, os, json, random, time, argparse, itertools, copy
from shutil import copyfile
from progressbar import ProgressBar, Percentage, Bar, ETA	# progressbar2 (install with pip install progressbar2)
import numpy as np
#from numpy.lib import nanfunctions
from scipy.special import erf, erfinv
from scipy.signal import resample
import matplotlib.pyplot as plt

import tensorflow as tf
from tensorflow.keras import layers, models

thisDir = os.path.dirname(os.path.abspath(__file__))
# thisChipPythonDir = os.path.dirname(os.path.abspath(__file__))
# thisChipRootDir = os.path.abspath(thisChipPythonDir + '/../')
# sys.path.append(thisChipRootDir + '/../common/PyEmanate/python')
#PyEmanatePythonDir = thisDir + '/../../../../Chips/common/PyEmanate/python'
#sys.path.append(PyEmanatePythonDir)


from Chip import Chip
from HistogramChannel import HistogramChannel, HistogramCollection
from HelperFunctions import *
from OptimizedMLPNN import OptimizedMlpnnWrapper

class NPU():
	WorkingDirectory = None
	
	HistogramCollectionFileName = None
	OriginalHistogramFilePath = None
	ChipName = None
	DieID = None
	ClassificationIsotopes = None
	WhitelistedIsotopes = None
	BlacklistedIsotopes = None
	DesiredHistogramBits = None
	MaxBackgroundAbundance = None
	Layers = None
	TrainingSetType = None
	Engine = None
	LearningGain = None
	MomentumGain = None
	MaxEpochs = None
	TargetMse = None
	UseBatch = None
	BatchSize = None
	HistogramBinStdDev = None
	BinScaleStdDev = None
	BinShiftStdDev = None
	MaxAllowableIncrementMse = None
	DesiredFalsePositiveRate = None
	DesiredFalseNegativeRate = None
	TrainingToTestRatio = None
	
	keys = ['HistogramCollectionFileName', 'OriginalHistogramFilePath', 'ChipName',
		'DieID', 'ClassificationIsotopes', 'WhitelistedIsotopes', 'BlacklistedIsotopes', 'DesiredHistogramBits', 'MaxBackgroundAbundance', 'Layers', 'TrainingSetType', 'Engine', 'LearningGain', 'MomentumGain', 'MaxEpochs', 'TargetMse', 'MaxAllowableIncrementMse', 'UseBatch', 'BatchSize', 'HistogramBinStdDev', 'BinScaleStdDev', 'BinShiftStdDev', 'DesiredFalsePositiveRate', 'DesiredFalseNegativeRate', 'TrainingToTestRatio']

	def LoadConfigFromJson(self, filePath:str):
		with open(filePath, 'r') as f:
			d = json.load(f)
		ret = self.LoadConfigFromDict(d)
		if not ret:
			return False
		self.WorkingDirectory = os.path.dirname(os.path.abspath(filePath)).replace('\\', '/')
		return True
	
	def LoadConfigFromDict(self, d:dict):
		if type(d) != dict:
			return False
		if 'Type' not in d:
			return False
		if d['Type'] != 'NpuIsotopeIDConfigMLP':
			return False

		for k in self.keys:
			if k not in d:
				print('Config does not have key "' + str(k) + '"')
				return False
			self.__dict__[k] = d[k]
		
		if self.BatchSize is None:
			self.BatchSize = 0
		
		return True
	
	def ConfigToDict(self):
		d = {}
		for k in self.keys:
			d[k] = self.__dict__[k]
		return d
	
	def CreateWorkingDirectory(self, histogramCollectionPath:str, newWorkingDirectory=None):
		# Check the histogram collection file
		if (not os.path.isfile(histogramCollectionPath)) or (not histogramCollectionPath.lower().endswith('.json')):
			print('Invalid histogramCollectionPath:', histogramCollectionPath)
			return False
		
		histogramCollection = HistogramCollection.LoadFromJson(histogramCollectionPath)
		if histogramCollection is None or len(histogramCollection.Histograms) == 0:
			print('Invalid histogramCollectionPath:', histogramCollectionPath)
			return False
		
		histogramCollectionPath = os.path.abspath(histogramCollectionPath).replace('\\', '/')
		while '//' in histogramCollectionPath:
			histogramCollectionPath = histogramCollectionPath.replace('//', '/')
		
		# Determine which chip this is
		chip = Chip.CreateFromPath(histogramCollectionPath)
		if chip is None:
			chip = Chip.CreateFromExecutionDirectory()
			if chip is None:
				print('Cannot determine the chip from the path of the histogram collection or the current working directory')
				return False
		dieID = histogramCollection.Histograms[0].DieID
		if chip.IDChipPrefix != dieID[0:2]:
			print('The histogram collection is for chip ID prefix ' + histogramCollection.Histograms[0].DieID[0:2] + ', but the software has loaded the chip directory for ' + chip.Name)
			return False

		# Create the working directory, if desired
		if not os.path.isdir(chip.DataDirectory):
			print('Chip data directory does not exist:', chip.DataDirectory)
			return False
		if newWorkingDirectory is not None:
			self.WorkingDirectory = newWorkingDirectory
		else:
			self.WorkingDirectory = chip.DataDirectory + '/NPU/' + dieID + '/IsotopeID-' + get_string_timestamp(includeSeconds=True, dt=histogramCollection.Timestamp)
		if os.path.isdir(self.WorkingDirectory):
			print('Working directory already exists:', self.WorkingDirectory)
			return False
		else:
			if not os.makedirs(self.WorkingDirectory):
				print('Failed to make working directory at', self.WorkingDirectory)
				return False

		# Copy the histogram collection to the working directory
		histogramFileName = histogramCollectionPath.split('/')[-1]
		histogramCollectionCopyPath = self.WorkingDirectory + '/' + histogramFileName
		if os.path.abspath(histogramCollectionPath).lower() != os.path.abspath(histogramCollectionCopyPath).lower():
			copyfile(histogramCollectionPath, histogramCollectionCopyPath)
		
		# Create or add to the config.json file
		configPath = self.WorkingDirectory + '/config.json'
		if os.path.isfile(configPath):
			with open(configPath, 'r') as f:
				config = json.load(f)
		else:
			config = {}
		
		config['Type'] = 'NpuIsotopeIDConfigMLP'
		config['HistogramCollectionFileName'] = histogramFileName
		config['OriginalHistogramFilePath'] = histogramCollectionPath
		config['ChipName'] = chip.Name
		config['DieID'] = dieID
		config['ClassificationIsotopes'] = []
		config['WhitelistedIsotopes'] = None
		config['BlacklistedIsotopes'] = []
		config['DesiredHistogramBits'] = None
		config['MaxBackgroundAbundance'] = 1
		config['Layers'] = []
		config['TrainingSetType'] = None
		config['Engine'] = 'OptimizedMLPNN'
		config['LearningGain'] = None
		config['MomentumGain'] = None
		config['MaxEpochs'] = None
		config['TargetMse'] = 0
		config['UseBatch'] = False
		config['BatchSize'] = 32
		config['HistogramBinStdDev'] = 0
		config['BinScaleStdDev'] = 0
		config['BinShiftStdDev'] = 0
		config['MaxAllowableIncrementMse'] = None
		config['DesiredFalsePositiveRate'] = None
		config['DesiredFalseNegativeRate'] = None
		config['TrainingToTestRatio'] = 1

		with open(configPath, 'w') as f:
			json.dump(config, f, indent='\t')
		
		return True

	
	def CreateSets(self):
		# Argument checking and default values
		if type(self.ClassificationIsotopes) != list:
			print('Invalid self.ClassificationIsotopes')
			return False
		if self.DesiredHistogramBits is None:
			self.DesiredHistogramBits = 6
			print('Using default value of 6 for DesiredHistogramBits')
		if type(self.DesiredHistogramBits) != int or self.DesiredHistogramBits < 2:
			print('Invalid desiredHistogramBits')
			return False
		if self.TrainingToTestRatio is None:
			self.TrainingToTestRatio = 1
		if (type(self.TrainingToTestRatio) != float and type(self.TrainingToTestRatio) != int) or self.TrainingToTestRatio <= 0:
			print('Invalid trainingToTestRatio')
			return False

		# Check the histogram collection file
		histogramCollectionPath = self.WorkingDirectory + '/' + self.HistogramCollectionFileName
		if (not os.path.isfile(histogramCollectionPath)) or (not histogramCollectionPath.lower().endswith('.json')):
			print('Invalid histogramCollectionPath:', histogramCollectionPath)
			return False
		
		histogramCollection = HistogramCollection.LoadFromJson(histogramCollectionPath)
		if histogramCollection is None or len(histogramCollection.Histograms) == 0:
			print('Invalid histogramCollectionPath:', histogramCollectionPath)
			return False
		
		# Clean up the MeasuredIsotopeAbundances in each histogram in case of None or zero values
		for h in histogramCollection.Histograms:
			if h.MeasuredIsotopeAbundances is None:
				continue
			isosToRemove = []
			for iso in h.MeasuredIsotopeAbundances:
				ab = h.MeasuredIsotopeAbundances[iso]
				if iso == 'Background':
					continue
				if (not (type(ab) == float or type(ab) == int)) or ab < 1e-12:
					isosToRemove.append(iso)
			for iso in isosToRemove:
				h.MeasuredIsotopeAbundances.pop(iso)
		
		# Remove histograms with both a Background entry and more isotopes, or histograms without any isotope
		for i in reversed(range(len(histogramCollection.Histograms))):
			h = histogramCollection.Histograms[i]
			if h.MeasuredIsotopeAbundances is None:
				histogramCollection.Histograms.pop(i)
				continue
			if len(h.MeasuredIsotopeAbundances) == 0:
				histogramCollection.Histograms.pop(i)
				continue
			if 'Background' in h.MeasuredIsotopeAbundances and len(h.MeasuredIsotopeAbundances) > 1:
				histogramCollection.Histograms.pop(i)
				continue
		
		# Remove histograms with isotopes not in the whitelist
		if type(self.WhitelistedIsotopes) == list:
			self.WhitelistedIsotopes = [HistogramChannel.StandardizeIsotopeString(iso, allowUnknown=False) for iso in self.WhitelistedIsotopes]
			if None in self.WhitelistedIsotopes:
				print('An unknown isotope is in the whitelist, please remove it')
				return False
			for i in reversed(range(len(histogramCollection.Histograms))):
				h = histogramCollection.Histograms[i]
				for iso in h.MeasuredIsotopeAbundances:
					if iso == 'Background':
						continue
					if iso not in self.WhitelistedIsotopes:
						histogramCollection.Histograms.pop(i)
						continue
		
		# Remove histograms with isotopes in the blacklist
		if type(self.BlacklistedIsotopes) == list:
			self.BlacklistedIsotopes = [HistogramChannel.StandardizeIsotopeString(iso, allowUnknown=False) for iso in self.BlacklistedIsotopes]
			if None in self.BlacklistedIsotopes:
				print('An unknown isotope is in the blacklist, please remove it')
				return False
			for i in reversed(range(len(histogramCollection.Histograms))):
				h = histogramCollection.Histograms[i]
				for iso in h.MeasuredIsotopeAbundances:
					if iso == 'Background':
						continue
					if iso not in self.BlacklistedIsotopes:
						histogramCollection.Histograms.pop(i)
						continue
		
		# Are there any histograms left?
		if len(histogramCollection.Histograms) == 0:
			print('No histograms remaining after removing invalid or unwanted histograms')
			return False
		
		# Order the classification isotopes in alphabetical order
		self.ClassificationIsotopes = [HistogramChannel.StandardizeIsotopeString(s, allowUnknown=False) for s in self.ClassificationIsotopes]
		if None in self.ClassificationIsotopes:
			print('An unknown isotope is in the list of classification isotopes, please remove it')
			return False

		# Get the background histograms
		backgroundHistograms = HistogramCollection()
		backgroundHistograms.Histograms = [h for h in histogramCollection.Histograms if 'Background' in h.MeasuredIsotopeAbundances]

		# Sort the histograms into collections based on their combination of isotopes
		collections = []
		for h in histogramCollection.Histograms:
			if 'Background' in h.MeasuredIsotopeAbundances:
				continue
			match = False
			for collection in collections:
				if h.MeasuredIsotopeAbundances == collection.Histograms[0].MeasuredIsotopeAbundances:
					# This histogram belongs in this collection
					collection.Histograms.append(h)
					match = True
					break
			if not match:
				# Make a new collection and place this histogram in it
				hc = HistogramCollection()
				hc.Histograms = [h]
				collections.append(hc)

		singleIsotopeCollections = [c for c in collections if (len(c.Histograms[0].MeasuredIsotopeAbundances) == 1) and (list(c.Histograms[0].MeasuredIsotopeAbundances.keys())[0] in self.ClassificationIsotopes)]
		multiIsotopeCollections = [c for c in collections if len(c.Histograms[0].MeasuredIsotopeAbundances) > 1]
		allCollections = [backgroundHistograms] + singleIsotopeCollections + multiIsotopeCollections

		# Sort the histograms in each collection by timestamp
		for collection in allCollections:
			collection.Histograms.sort(key=lambda h: h.Timestamp)
		
		# Make sure all collections have the same number of histograms
		numHistsPerCollection = min([len(c.Histograms) for c in allCollections])
		for c in allCollections:
			c.Histograms = c.Histograms[:numHistsPerCollection]
		
		# Get the time deltas for the histograms to calculate the average amount of time between each histogram. Also, detect if the histograms were auto cleared between each one or not.
		averageTimeDeltas = []
		for collection in allCollections:
			if len(collection.Histograms) < 2:
				print('Must have at least two histograms for each unique set of isotopes. The collection failed for isotopes', collection.Histograms[0].MeasuredIsotopeAbundances)
				return False
			timeDeltas = []
			for i in range(len(collection.Histograms) - 1):
				timeDeltas.append((collection.Histograms[i + 1].Timestamp - collection.Histograms[i].Timestamp).total_seconds())
			
			avTimeDelta = np.mean(timeDeltas)
			stddevTimeDelta = np.std(timeDeltas)
			if stddevTimeDelta > (avTimeDelta / 10) or max(timeDeltas) > (1.51 * avTimeDelta) or min(timeDeltas) < (0.5 * avTimeDelta):
				print('Histogram collection for isotopes', collection.Histograms[0].MeasuredIsotopeAbundances, 'has irregular time intervals. Average is', avTimeDelta, 's, but standard deviation is', stddevTimeDelta, 's')
				return False
			averageTimeDeltas.append(avTimeDelta)
			
			m, b = np.linalg.lstsq(np.vstack([avTimeDelta * np.arange(1, len(collection.Histograms) + 1), np.ones(len(collection.Histograms))]).T, np.array([h.TotalCounts for h in collection.Histograms], dtype=float), rcond=None)[0]
			if b < 0 or m > (b / 10):
				# These histograms were made with auto clear off. Subtract them from one another.
				for i in range(len(collection.Histograms) - 1):
					collection.Histograms[i + 1].Counts = np.subtract(collection.Histograms[i + 1].Counts, collection.Histograms[i].Counts).tolist()
		avAvTimeDelta = np.average(averageTimeDeltas)
		stddevAvTimeDelta = np.std(averageTimeDeltas)
		if stddevAvTimeDelta > (avAvTimeDelta / 10) or max(averageTimeDeltas) > (1.51 * avAvTimeDelta) or min(averageTimeDeltas) < (0.5 * avAvTimeDelta):
			print('The average time delta between histograms is different for each hisogram collection')
			return False
		
		# Calculate the average number of counts in each background histogram
		avBackgroundCounts = np.mean([h.TotalCounts for h in backgroundHistograms.Histograms])

		# Calculate the expected isotope abundances for the background
		for h in backgroundHistograms.Histograms:
			h.ExpectedIsotopeAbundances = {'Background': 1.0}
		
		# Calculate the expected isotope abundances for the single isotope histograms
		normalizedSingleIsotopeBackgroundSubtractedCounts = {}
		for c in singleIsotopeCollections:
			for i in reversed(range(len(c.Histograms))):
				h = c.Histograms[i]
				iso = list(h.MeasuredIsotopeAbundances.keys())[0]
				totalCounts = h.TotalCounts
				backgroundProportion = avBackgroundCounts / totalCounts
				if backgroundProportion > 1:
					h.pop[i]
					continue
				h.ExpectedIsotopeAbundances = {'Background': backgroundProportion, iso: 1 - backgroundProportion}	# Ignore the value of the isotope's abundance for single isotope histograms
				if iso not in normalizedSingleIsotopeBackgroundSubtractedCounts:
					normalizedSingleIsotopeBackgroundSubtractedCounts[iso] = []
				normalizedSingleIsotopeBackgroundSubtractedCounts[iso].append((totalCounts - avBackgroundCounts) / h.ExpectedIsotopeAbundances[iso])
		normalizedSingleIsotopeAvBackgroundSubtractedCounts = {}
		
		for iso in normalizedSingleIsotopeBackgroundSubtractedCounts:
			normalizedSingleIsotopeAvBackgroundSubtractedCounts[iso] = np.average(normalizedSingleIsotopeBackgroundSubtractedCounts[iso])
		
		# Calculate the expected isotope abundances for the multi isotope histograms
		for c in multiIsotopeCollections:
			for i in reversed(range(len(c.Histograms))):
				h = c.Histograms[i]
				totalCounts = h.TotalCounts
				backgroundProportion = avBackgroundCounts / totalCounts
				if backgroundProportion > 1:
					h.pop[i]
					continue
				# Calculate each isotope's abundance based on each one's single-isotope histogram total counts average
				h.ExpectedIsotopeAbundances = {}
				for iso in h.MeasuredIsotopeAbundances:
					if iso in normalizedSingleIsotopeAvBackgroundSubtractedCounts:
						h.ExpectedIsotopeAbundances[iso] = normalizedSingleIsotopeAvBackgroundSubtractedCounts[iso] * h.MeasuredIsotopeAbundances[iso] / totalCounts
				# Calculate the background counts based on the leftover counts not attributed to any of the single-isotope histogram total counts averages
				excessProportion = 1 - sum(h.ExpectedIsotopeAbundances.values())
				if backgroundProportion > excessProportion:
					h.ExpectedIsotopeAbundances['Background'] = backgroundProportion
				else:
					h.ExpectedIsotopeAbundances['Background'] = excessProportion
				# Renormalize the abundances
				totalAbundance = sum(h.ExpectedIsotopeAbundances.values())
				for iso in h.ExpectedIsotopeAbundances:
					h.ExpectedIsotopeAbundances[iso] /= totalAbundance
		
		# Create a dictionary containing the training set
		trainingProportion = self.TrainingToTestRatio / (1 + self.TrainingToTestRatio)
		d = {'Type': 'TrainingSet', 'Timestamp': get_string_timestamp(includeSeconds=True, dt=histogramCollection.Timestamp), 'ChipName': self.ChipName, 'DieID': self.DieID, 'AfeName': histogramCollection.Histograms[0].AfeName, 'ClassificationIsotopes': self.ClassificationIsotopes, 'TrainingSet': [], 'TestSet': []}
		for collection in allCollections:
			for i, h in enumerate(collection.Histograms):
				if (i / len(collection.Histograms)) >= trainingProportion:
					key = 'TestSet'
				else:
					key = 'TrainingSet'
				rebinnedHist = HistogramChannel.ReBinSimple(h.Counts, desiredHistogramBits=self.DesiredHistogramBits)
				if rebinnedHist is None:
					print('Could not re-bin the histogram with desiredHistogramBits =', self.DesiredHistogramBits)
					return False
				d[key].append({'Timestamp': get_string_timestamp(includeSeconds=True, dt=h.Timestamp), 'NormalizedCountsQ': HistogramChannel.GetNormalizedCountsForNPU(rebinnedHist), 'MeasuredIsotopeAbundances': h.MeasuredIsotopeAbundances, 'ExpectedIsotopeAbundances': h.ExpectedIsotopeAbundances})
		
		## Randomize the ordering of the training and test sets
		#random.shuffle(d['TrainingSet'])
		#random.shuffle(d['TestSet'])
		
		# Save the training set
		trainingSetJsonPath = self.WorkingDirectory + '/TrainingSet.json'
		with open(trainingSetJsonPath, 'w') as f:
			json.dump(d, f)
		
		print('Saved training set to', trainingSetJsonPath)
		
		
		
		# Create the archetypal background histogram
		archetypalHistograms = []
		
		backgroundCounts = np.zeros((len(c.Histograms[0].Counts)), dtype=np.int32)
		for h in backgroundHistograms.Histograms:
			backgroundCounts += h.Counts
		backgroundCounts = HistogramChannel.ReBinSimple(backgroundCounts.tolist(), removeFirstBin=True, removeLastBin=True, desiredHistogramBits=self.DesiredHistogramBits)
		'''
		scalingFactor = 1.0
		for c in singleIsotopeCollections:
			# Accumulate all counts
			counts = np.zeros((len(c.Histograms[0].Counts)), dtype=np.int32)
			for h in c.Histograms:
				counts += h.Counts
			
			# Re-bin
			counts = HistogramChannel.ReBinSimple(counts.tolist(), removeFirstBin=True, removeLastBin=True, desiredHistogramBits=self.DesiredHistogramBits)
			
			# Get the scaling factor needed to ensure no bins will be negative
			scalingFactors = np.array(counts) / backgroundCounts
			scalingFactor = min(scalingFactor, np.min(scalingFactors))
		
		# Reduce the background such that no bins will be negative once the background is subtracted
		backgroundCounts = np.round(scalingFactor * np.array(backgroundCounts)).astype(int).tolist()
		'''
		
		d = {
			'Isotope': 'Background',
			'TotalCounts': sum(backgroundCounts),
			'Counts': backgroundCounts,
		}
		
		archetypalHistograms.append(d)
		
		# Create the archetypal single-isotope and background histograms
		for c in singleIsotopeCollections:
			# Accumulate all counts
			counts = np.zeros((len(c.Histograms[0].Counts)), dtype=np.int32)
			for h in c.Histograms:
				counts += h.Counts
			
			# Re-bin
			counts = HistogramChannel.ReBinSimple(counts.tolist(), removeFirstBin=True, removeLastBin=True, desiredHistogramBits=self.DesiredHistogramBits)
			
			# Subtract background
			#counts = np.clip(np.subtract(counts, backgroundCounts), 0, None).tolist()
			counts = np.subtract(counts, backgroundCounts).tolist()
			
			# Create dictionary and add to list
			d = {
				'Isotope': list(c.Histograms[0].MeasuredIsotopeAbundances.keys())[0],
				'TotalCounts': sum(counts),
				'Counts': counts,
			}
			
			archetypalHistograms.append(d)
		
		# Save the archetypal histograms
		d = {
			'Type': 'ArchetypalHistograms',
			'Timestamp': get_string_timestamp(includeSeconds=True, dt=histogramCollection.Timestamp),
			'ChipName': self.ChipName,
			'DieID': self.DieID,
			'AfeName': histogramCollection.Histograms[0].AfeName,
			'ClassificationIsotopes': self.ClassificationIsotopes,
			'ArchetypalHistograms': archetypalHistograms,
		}
		archetypalHistogramsJsonPath = self.WorkingDirectory + '/ArchetypalHistograms.json'
		with open(archetypalHistogramsJsonPath, 'w') as f:
			json.dump(d, f)
		
		print('Saved archetypal histograms set to', archetypalHistogramsJsonPath)

		return True
	
	def GetTrainingAndTestSet(self, skipTestSet:bool=False, useQuantization:bool=False, returnClassificationIsotopes:bool=False):
		# Load the training set
		trainingSetJsonPath = self.WorkingDirectory + '/TrainingSet.json'
		if not os.path.isfile(trainingSetJsonPath):
			print('Training set file does not exist at', trainingSetJsonPath)
			return False
		
		with open(trainingSetJsonPath, 'r') as f:
			d = json.load(f)
		
		if type(d) != dict or 'Type' not in d or d['Type'] != 'TrainingSet':
			print('Invalid training set file at', trainingSetJsonPath)
			return False
		
		# Get the classification isotopes
		classificationIsotopes = d['ClassificationIsotopes']
		if 'Background' in classificationIsotopes:
			classificationIsotopes.pop('Background')
		classificationIsotopes = ['Background'] + classificationIsotopes
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i
		
		# Convert the training set to a matrix
		trainingSetDict = d['TrainingSet']
		trainingSetInputVectors = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in trainingSetDict], axis=1)
		
		if not useQuantization:
			trainingSetInputVectors = trainingSetInputVectors.astype(float) / 32768
		
		trainingSetExpectedOutputVectors = []
		for h in trainingSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			trainingSetExpectedOutputVectors.append(v)
		trainingSetExpectedOutputVectors = np.concatenate(trainingSetExpectedOutputVectors, axis=1)

		if skipTestSet:
			if returnClassificationIsotopes:
				return trainingSetInputVectors, trainingSetExpectedOutputVectors, classificationIsotopes, classificationIsotopeIndices
			else:
				return trainingSetInputVectors, trainingSetExpectedOutputVectors

		# Convert the test set to a matrix
		testSetDict = d['TestSet']
		testSetInputVectors = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in testSetDict], axis=1)
		if not useQuantization:
			testSetInputVectors /= 32768
		testSetExpectedOutputVectors = []
		for h in testSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			testSetExpectedOutputVectors.append(v)
		testSetExpectedOutputVectors = np.concatenate(testSetExpectedOutputVectors, axis=1)

		if returnClassificationIsotopes:
			return trainingSetInputVectors, trainingSetExpectedOutputVectors, testSetInputVectors, testSetExpectedOutputVectors, classificationIsotopes, classificationIsotopeIndices
		else:
			return trainingSetInputVectors, trainingSetExpectedOutputVectors, testSetInputVectors, testSetExpectedOutputVectors
	
	def Train(self, timeCompile=True, plot=True, verbose=True):
		# Get parameters
		numInputs = 2**self.DesiredHistogramBits
		
		# Load the training set
		numTrainingSetVectors = min(max(self.BatchSize * 100, 10000), 1000000)
		trainingSetType = self.TrainingSetType.lower()

		if trainingSetType == 'archetypal':
			if verbose:
				print('Training with archetypal histograms')
			
			# Load the archetypal histograms (regardless of what mode this is in)
			archetypalHistogramsJsonPath = self.WorkingDirectory + '/ArchetypalHistograms.json'
			if not os.path.isfile(archetypalHistogramsJsonPath):
				print('ArchetypalHistograms file does not exist at', archetypalHistogramsJsonPath)
				return False
			
			with open(archetypalHistogramsJsonPath, 'r') as f:
				d = json.load(f)
			
			if type(d) != dict or 'Type' not in d or d['Type'] != 'ArchetypalHistograms':
				print('Invalid archetypal histograms file at', archetypalHistogramsJsonPath)
				return False
			
			# Get the classification isotopes
			classificationIsotopes = d['ClassificationIsotopes']
			if 'Background' in classificationIsotopes:
				classificationIsotopes.pop('Background')
			classificationIsotopes = ['Background'] + classificationIsotopes
			classificationIsotopeIndices = {}
			for i, iso in enumerate(classificationIsotopes):
				classificationIsotopeIndices[iso] = i
			numOutputs = len(classificationIsotopes)
			
			# Get the archetypal histograms, each with a total abundance of 1.0
			self.ArchetypalHistograms = np.zeros((numInputs, numOutputs), dtype=float)
			for ahist in d['ArchetypalHistograms']:
				if len(ahist['Counts']) != numInputs:
					print('An archetypal histogram does not have', numInputs, 'elements')
					return False
				abundanceOneCounts = np.array(ahist['Counts'], dtype=float).reshape((len(ahist['Counts']), 1))
				abundanceOneCounts = abundanceOneCounts / sum(ahist['Counts'])
				isotopeIndex = classificationIsotopeIndices[ahist['Isotope']]
				self.ArchetypalHistograms[:, [isotopeIndex]] = abundanceOneCounts
			
			#if len(classificationIsotopes) != numOutputsPerLayer[-1]:
			#	print('config.json does not have the proper number of outputs (' + str(numOutputs) + ') in the final layer')
			#	return False
			if len(d['ArchetypalHistograms']) != numOutputs:
				print('The ArchetypalHistograms.json file contains', len(d['ArchetypalHistograms']), 'archetypal histograms, but the system expects', numOutputs, 'outputs')
				return False
		
			trainingSetInputVectors, trainingSetExpectedOutputVectors = self.GetRandomInputAndExpectedOutputVectors(numTrainingSetVectors, maxBackgroundAbundance=self.MaxBackgroundAbundance)
			
		elif trainingSetType == 'set':
			# Load the training set
			if verbose:
				print('Training with set histograms')
			trainingSetInputVectors, trainingSetExpectedOutputVectors = self.GetTrainingAndTestSet(skipTestSet=True, useQuantization=False)

			repetitions = int(round(numTrainingSetVectors / trainingSetInputVectors.shape[1]))
			trainingSetInputVectors = np.concatenate([trainingSetInputVectors for i in range(repetitions)], axis=1)
			trainingSetExpectedOutputVectors = np.concatenate([trainingSetExpectedOutputVectors for i in range(repetitions)], axis=1)
		else:
			raise Exception('Invalid training set type')
		
		trainingSetInputVectors = self.ScaleAndShiftInputVectors(trainingSetInputVectors, self.BinScaleStdDev, self.BinShiftStdDev)
		if self.HistogramBinStdDev is not None and self.HistogramBinStdDev > 1e-9:
			trainingSetInputVectors = self.AddNoiseToInputVectors(trainingSetInputVectors, self.HistogramBinStdDev)
		trainingSetInputVectors = self.NormalizeInputs(trainingSetInputVectors)
		
		# Error checking
		#if trainingSetExpectedOutputVectors.shape[0] != numOutputsPerLayer[-1]:
		#	print('config.json does not have the proper number of outputs (' + str(numOutputs) + ') in the final layer')
		#	return False
		if trainingSetInputVectors.shape[0] != numInputs:
			print('config.json does not have the proper number of inputs (as in DesiredHistogramBits) in the final layer')
			return False
		
		engine = self.Engine.lower()

		# Compile the training algoritm (if necessary)
		if timeCompile and engine == 'optimizedmlpnn':
			self.CompileMlpnnTrainingAlgorithm(numInputs, [4, 2], [True, False], ['sigmoid-approx', 'sigmoid'])

		# Initialize training data
		d = {'Type': 'TrainingData'}
		d = {**d, **self.ConfigToDict()}

		# Train
		if verbose:
			print('Training...')
		t1 = time.time()
		if engine == 'optimizedmlpnn':
			# Set up DNN
			numOutputsPerLayer = [l['NumOutputs'] for l in self.Layers]
			numOutputs = numOutputsPerLayer[-1]
			useBiasPerLayer = [l['UseBias'] for l in self.Layers]
			activationFunctionPerLayer = [l['ActivationFunction'] for l in self.Layers]

			m = OptimizedMlpnnWrapper()
			m.Initialize(numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionPerLayer)
			m.Train(self.MaxEpochs, self.LearningGain, self.MomentumGain, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse=self.TargetMse, maxAllowableIncrementMse=self.MaxAllowableIncrementMse, useBatch=self.UseBatch, batchSize=self.BatchSize)
			
			# Check for out-of-bounds weights
			weights = m.Weights
			for layerNum, w in enumerate(weights):
				w = self.toQx_15(w)
				if np.max(w) > 8388607:
					print('Weights matrix', layerNum, 'has at least one value that is greater than the Q8.15 upper limit')
					return False
				if np.min(w) < -8388608:
					print('Weights matrix', layerNum, 'has at least one value that is less than the Q8.15 lower limit')
					return False
			
			# Collect training data
			for layerNum, layer in enumerate(self.Layers):
				layer['Weights'] = weights[layerNum].tolist()
			
			minMse = m.MinMse
			epochAtMinMse = m.EpochAtMinMse
			lastEpoch = m.CurrentEpoch
			mseAtEachEpoch = m.MseAtEachEpoch.tolist()
		elif engine == 'tensorflow':
			# Set up DNN
			model = self.createTensorFlowModel()
			optimizer = tf.keras.optimizers.SGD(learning_rate=self.LearningGain, momentum=self.MomentumGain)
			model.compile(optimizer=optimizer, loss='mse')

			# Reshape the training set
			trainingSetInputVectors = trainingSetInputVectors.T.reshape((trainingSetInputVectors.shape[1], trainingSetInputVectors.shape[0], 1))
			trainingSetExpectedOutputVectors = trainingSetExpectedOutputVectors.T.reshape((trainingSetExpectedOutputVectors.shape[1], trainingSetExpectedOutputVectors.shape[0], 1))

			# Train
			history = model.fit(trainingSetInputVectors, trainingSetExpectedOutputVectors, epochs=self.MaxEpochs, batch_size=self.BatchSize, steps_per_epoch=1, verbose=0)
			mseAtEachEpoch = history.history['loss']

			epochAtMinMse = int(np.argmin(mseAtEachEpoch))
			minMse = mseAtEachEpoch[epochAtMinMse]
			lastEpoch = self.MaxEpochs

			weights = []
			for layerNum, layer in enumerate(model.layers):
				wlist = [w.tolist() for w in layer.get_weights()]
				if len(wlist) == 0:
					weights.append(None)
					continue
				weights.append(wlist)
				for w in wlist:
					w = self.toQx_15(w)
					if np.max(w) > 8388607:
						print('Weights matrix', layerNum, 'has at least one value that is greater than the Q8.15 upper limit')
						return False
					if np.min(w) < -8388608:
						print('Weights matrix', layerNum, 'has at least one value that is less than the Q8.15 lower limit')
						return False
			
			# Collect training data
			for layerNum, layer in enumerate(self.Layers):
				w = weights[layerNum]
				if w is not None:
					layer['Weights'] = w

		t2 = time.time()
		trainingTime = t2 - t1

		# Save the training data (including the weights)
		d['TrainedMinMse'] = minMse
		d['EpochAtMinMse'] = epochAtMinMse
		d['TrainingTime'] = trainingTime

		trainingDataPath = self.WorkingDirectory + '/TrainingData.json'
		with open(trainingDataPath, 'w') as f:
			json.dump(d, f)
		
		mseAtEachEpochPath = self.WorkingDirectory + '/MseAtEachEpoch.csv'
		with open(mseAtEachEpochPath, 'w') as f:
			for i in range(len(mseAtEachEpoch)):
				f.write(str(mseAtEachEpoch[i]) + '\n')
		
		if verbose:
			print('Minimum MSE of', minMse, 'achieved in', lastEpoch, 'epochs')
			print('Minimum MSE occurred in epoch', epochAtMinMse + 1)
			print('Training time:', trainingTime, 's')
			print('Saved training data to', trainingDataPath)

		if plot:
			if verbose:
				print('Plotting...')
			plt.clf()
			plt.style.use(thisDir + '/ieee.mplstyle')
			plt.semilogy([i + 1 for i in range(len(mseAtEachEpoch))], mseAtEachEpoch, 'b-')
			plt.grid(True)
			plt.xlabel('Epoch')
			plt.ylabel('MSE')
			outdir = self.WorkingDirectory + '/figures'
			os.makedirs(outdir, exist_ok=True)
			plt.savefig(outdir + '/mse.pgf')
			plt.savefig(outdir + '/mse.png')
		
		return d
	
	def getRandomAbundances(self, numOutputs, transpose:bool=False, maxBackgroundAbundance:float=1):
		if transpose:
			a = np.sort(np.concatenate((np.random.uniform(size=(1, 1), high=maxBackgroundAbundance), np.random.uniform(size=(1, numOutputs - 2)), np.ones((1, 1), dtype=float)), axis=1))
			for i in reversed(range(1, a.shape[1])):
				a[0, i] -= a[0, i - 1]
			return a
		else:
			a = np.sort(np.concatenate((np.random.uniform(size=(1, 1), high=maxBackgroundAbundance), np.random.uniform(size=(numOutputs - 2, 1)), np.ones((1, 1), dtype=float)), axis=0))
			for i in reversed(range(1, a.shape[0])):
				a[i, 0] -= a[i - 1, 0]
			return a
	
	def GetRandomInputAndExpectedOutputVectors(self, numVectors, maxBackgroundAbundance:float=1):
		numInputs = self.ArchetypalHistograms.shape[0]
		numOutputs = self.ArchetypalHistograms.shape[1]
		inputVectors = np.zeros((numInputs, numVectors), dtype=float)
		expectedOutputVectors = np.zeros((numOutputs, numVectors), dtype=float)
		for i in range(numVectors):
			abundances = self.getRandomAbundances(numOutputs, transpose=True, maxBackgroundAbundance=maxBackgroundAbundance)
			inputVector = np.sum(self.ArchetypalHistograms * abundances, axis=1, keepdims=True)
			np.clip(inputVector, 0, None, out=inputVector)
			inputVectors[:, i:i+1] = inputVector
			expectedOutputVectors[:, i:i+1] = abundances.T
		return inputVectors, expectedOutputVectors
	
	def GenerateInputVectorsFromExpectedOutputVectors(self, expectedOutputVectors:np.ndarray):
		numOutputs, numInputs = expectedOutputVectors.shape
		
	
	def NormalizeInputs(self, inputVectors):
		return inputVectors / np.max(inputVectors, axis=0)
	
	def AddNoiseToInputVectors(self, inputVectors, std_dev):
		#for i in range(inputVectors.shape[1]):
		#	inputVectors[:, [i]] *= np.clip(np.random.normal(loc=1.0, scale=std_dev, size=(inputVectors.shape[0], 1)), 0.01, None)
		return inputVectors * np.clip(np.random.normal(loc=1.0, scale=std_dev, size=inputVectors.shape), 0.01, None)
	
	def ScaleAndShiftInputVector(self, inputVector, scale_std_dev, shift_std_dev):
		if scale_std_dev is not None and scale_std_dev > 1e-9:
			num_samples = int(np.round(len(inputVector) * np.random.normal(loc=1, scale=scale_std_dev)))
			y = resample(inputVector, num_samples)
		else:
			num_samples = len(inputVector)
			y = inputVector
		if shift_std_dev is not None and shift_std_dev > 1e-9:
			shift_bins = int(np.round(len(inputVector) * np.random.normal(loc=0, scale=shift_std_dev)))
		else:
			shift_bins = 0
		old_middle_bin = len(inputVector) // 2
		new_middle_bin = num_samples // 2
		if num_samples % 2 == 1 and np.random.uniform() > 0.5:
			new_middle_bin += 1
		shift = new_middle_bin - old_middle_bin + shift_bins
		out = np.zeros(shape=inputVector.shape)
		for i in range(len(out)):
			j = i + shift
			if j < 0 or j >= len(y):
				continue
			out[i] = y[j]
		return out
	
	def ScaleAndShiftInputVectors(self, inputVectors, scale_std_dev, shift_std_dev):
		return np.concatenate([self.ScaleAndShiftInputVector(inputVectors[:, i:i+1], scale_std_dev, shift_std_dev) for i in range(inputVectors.shape[1])], axis=1)
	
	def CompileMlpnnTrainingAlgorithm(self, numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionPerLayer):
		# Compile MLPNN software
		print('Compiling MLPNN training software...')
		t1 = time.time()
		m = OptimizedMlpnnWrapper()
		m.Initialize(numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionPerLayer)
		trainingSetInputVectors = np.ones((numInputs, 4))
		trainingSetExpectedOutputVectors = np.ones((numOutputsPerLayer[-1], 4))
		m.Train(1, self.LearningGain, self.MomentumGain, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse=self.TargetMse, useBatch=self.UseBatch, batchSize=self.BatchSize)
		m.Feedforward()
		t2 = time.time()
		compileTime = t2 - t1
		print('Compile time:', compileTime, 's')
		return

	def EvaluateTrainingData(self, plot=True, verbose=True):
		# Argument checking and default values
		if type(self.DesiredFalsePositiveRate) != float and not (0 < self.DesiredFalsePositiveRate < 1):
			print('Invalid desiredFalsePositiveRate')
			return False
		if type(self.DesiredFalseNegativeRate) != float and not (0 < self.DesiredFalseNegativeRate < 1):
			print('Invalid desiredFalseNegativeRate')
			return False
		
		# Open the training data
		trainingDataPath = self.WorkingDirectory + '/TrainingData.json'
		if not os.path.isfile(trainingDataPath):
			print('Training data does not exist at', trainingDataPath)
			return False
		
		with open(trainingDataPath, 'r') as f:
			trainingDataDict = json.load(f)
		
		if trainingDataDict is None or 'Type' not in trainingDataDict or trainingDataDict['Type'] != 'TrainingData':
			print('Invalid training data file at', trainingDataPath)
			return False

		# Open the training and test sets
		trainingSetJsonPath = self.WorkingDirectory + '/TrainingSet.json'
		if not os.path.isfile(trainingSetJsonPath):
			print('Invalid training set file at', trainingSetJsonPath)
			return False
		
		with open(trainingSetJsonPath, 'r') as f:
			trainingAndTestSetDict = json.load(f)
		
		if type(trainingAndTestSetDict) != dict or 'Type' not in trainingAndTestSetDict or trainingAndTestSetDict['Type'] != 'TrainingSet':
			print('Invalid training set file at', trainingSetJsonPath)
			return False
		
		# Get the classification isotopes
		classificationIsotopes = trainingAndTestSetDict['ClassificationIsotopes']
		if 'Background' in classificationIsotopes:
			classificationIsotopes.pop('Background')
		classificationIsotopes = ['Background'] + classificationIsotopes
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i
		numOutputs = len(classificationIsotopes)
		
		# Convert the training set to a matrix
		trainingSetDict = trainingAndTestSetDict['TrainingSet']
		trainingSetInputVectorsQ = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in trainingSetDict], axis=1)
		trainingSetInputVectors = trainingSetInputVectorsQ.astype(float) / 32768
		
		trainingSetExpectedOutputVectors = []
		for h in trainingSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso == 'Background' or iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			trainingSetExpectedOutputVectors.append(v)
		trainingSetExpectedOutputVectors = np.concatenate(trainingSetExpectedOutputVectors, axis=1)
		numInputs = trainingSetInputVectors.shape[0]

		# Convert the test set to a matrix
		testSetDict = trainingAndTestSetDict['TestSet']
		testSetInputVectorsQ = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in testSetDict], axis=1)
		testSetInputVectors = testSetInputVectorsQ.astype(float) / 32768
		
		testSetExpectedOutputVectors = []
		for h in testSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso == 'Background' or iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			testSetExpectedOutputVectors.append(v)
		testSetExpectedOutputVectors = np.concatenate(testSetExpectedOutputVectors, axis=1)

		# Load the archetypal histograms (regardless of what mode this is in)
		archetypalHistogramsJsonPath = self.WorkingDirectory + '/ArchetypalHistograms.json'
		if not os.path.isfile(archetypalHistogramsJsonPath):
			print('ArchetypalHistograms file does not exist at', archetypalHistogramsJsonPath)
			return False
		
		with open(archetypalHistogramsJsonPath, 'r') as f:
			d = json.load(f)
		
		if type(d) != dict or 'Type' not in d or d['Type'] != 'ArchetypalHistograms':
			print('Invalid archetypal histograms file at', archetypalHistogramsJsonPath)
			return False
		
		# Get the classification isotopes
		if 'Background' in d['ClassificationIsotopes']:
			d['ClassificationIsotopes'].pop('Background')
		d['ClassificationIsotopes'] = ['Background'] + d['ClassificationIsotopes']
		if len(d['ClassificationIsotopes']) != numOutputs:
			print('ArchetypalHistograms file does not contain the proper number of isotopes')
			return False
		
		# Get the archetypal histograms, each with a total abundance of 1.0
		self.ArchetypalHistograms = np.zeros((numInputs, numOutputs), dtype=float)
		for ahist in d['ArchetypalHistograms']:
			if len(ahist['Counts']) != numInputs:
				print('An archetypal histogram does not have', numInputs, 'elements')
				return False
			abundanceOneCounts = np.array(ahist['Counts'], dtype=float).reshape((len(ahist['Counts']), 1))
			abundanceOneCounts = abundanceOneCounts / sum(ahist['Counts'])
			isotopeIndex = classificationIsotopeIndices[ahist['Isotope']]
			self.ArchetypalHistograms[:, [isotopeIndex]] = abundanceOneCounts

		# Get archetypal vectors
		archetypalInputVectors, archetypalExpectedOutputVectors = self.GetRandomInputAndExpectedOutputVectors(1000, maxBackgroundAbundance=self.MaxBackgroundAbundance)

		# Compute the outputs to the training and test sets
		engine = self.Engine.lower()
		if engine == 'optimizedmlpnn':
			# Create DNN
			useBiasPerLayer = [d['UseBias'] for d in trainingDataDict['Layers']]
			layerWeightsMatricesQ = [self.toQx_15(d['Weights']) for d in trainingDataDict['Layers']]

			# Feedforward
			trainingSetEstimatedOutputVectorsQ = self.feedforwardQ(useBiasPerLayer, trainingSetInputVectorsQ, layerWeightsMatricesQ)
			testSetEstimatedOutputVectorsQ = self.feedforwardQ(useBiasPerLayer, testSetInputVectorsQ, layerWeightsMatricesQ)

			trainingSetEstimatedOutputVectors = trainingSetEstimatedOutputVectorsQ.astype(float) / 32768
			testSetEstimatedOutputVectors = testSetEstimatedOutputVectorsQ.astype(float) / 32768

			# Compute archetypal outputs
			archetypalInputVectorsQ = np.round(archetypalInputVectors * 32767).astype(int)
			archetypalEstimatedOutputVectorsQ = self.feedforwardQ(useBiasPerLayer, archetypalInputVectorsQ, layerWeightsMatricesQ)
			archetypalEstimatedOutputVectors = archetypalEstimatedOutputVectorsQ.astype(float) / 32768

			# Compute trainable parameters
			numTrainableParams = int(np.sum([np.prod(w.shape) for w in [np.array(d['Weights']) for d in trainingDataDict['Layers']]]))
		elif engine == 'tensorflow':
			# Create DNN
			model = self.createTensorFlowModel(trainingDataDictForLoadingWeights=trainingDataDict)

			# Feedforward
			trainingInputs = trainingSetInputVectors.T.reshape((trainingSetInputVectors.shape[1], trainingSetInputVectors.shape[0], 1))
			trainingSetEstimatedOutputVectors = model.predict(trainingInputs)
			trainingSetEstimatedOutputVectors = trainingSetEstimatedOutputVectors.T.astype(float)

			testInputs = testSetInputVectors.T.reshape((testSetInputVectors.shape[1], testSetInputVectors.shape[0], 1))
			testSetEstimatedOutputVectors = model.predict(testInputs)
			testSetEstimatedOutputVectors = testSetEstimatedOutputVectors.T.astype(float)
			
			# Compute archetypal outputs
			archetypalInputs = archetypalInputVectors.T.reshape((archetypalInputVectors.shape[1], archetypalInputVectors.shape[0], 1))
			archetypalEstimatedOutputVectors = model.predict(archetypalInputs)
			archetypalEstimatedOutputVectors = archetypalEstimatedOutputVectors.T.astype(float)

			# Compute trainable parameters
			numTrainableParams = int(np.sum([np.prod(v.get_shape()) for v in model.trainable_weights]))

		# Compute the error
		trainingSetErrorVectors = trainingSetExpectedOutputVectors - trainingSetEstimatedOutputVectors
		testSetErrorVectors = testSetExpectedOutputVectors - testSetEstimatedOutputVectors

		# Compute the MSE per output
		trainingSetMses = np.sum(trainingSetErrorVectors**2, axis=0) / trainingSetErrorVectors.shape[0]
		testSetMses = np.sum(testSetErrorVectors**2, axis=0) / testSetErrorVectors.shape[0]

		# Compute the total MSEs for the training and test sets
		trainingSetMse = np.sum(trainingSetMses) / len(trainingSetMses)
		testSetMse = np.sum(testSetMses) / len(testSetMses)

		# Compute archetypal MSE
		archetypalErrorVectors = archetypalExpectedOutputVectors - archetypalEstimatedOutputVectors
		archetypalMses = np.sum(archetypalErrorVectors**2, axis=0) / archetypalErrorVectors.shape[0]
		archetypalMse = np.sum(archetypalMses) / len(archetypalMses)

		# Create the Receiver Operating Characteristic (ROC) for each isotope using the training set
		ROC = {'IsotopeValueMethod': {}, 'BackgroundRatioMethod': {}}
		rocEvaluation = {'IsotopeValueMethod': {'TrainingSet': {}, 'TestSet': {}}, 'BackgroundRatioMethod': {'TrainingSet': {}, 'TestSet': {}}}
		backgroundindex = classificationIsotopeIndices['Background']

		for h in trainingSetDict:
			h['EstimatedIsotopeAbundances'] = None
			h['RocResults'] = {}
		valueRocCorrect = [1 for i in range(len(trainingSetDict))]
		ratioRocCorrect = [1 for i in range(len(trainingSetDict))]
		
		for iso in classificationIsotopes:
			if iso == 'Background':
				continue
			isoindex = classificationIsotopeIndices[iso]
			ROC['IsotopeValueMethod'][iso] = {}
			ROC['BackgroundRatioMethod'][iso] = {}

			# Collect the estimated output of each isotope in each test set histogram and sort by if the isotope was present or not
			valuesWithIso = []
			valuesWithoutIso = []
			ratiosWithIso = []
			ratiosWithoutIso = []
			for col, h in enumerate(trainingSetDict):
				backgroundRatio = trainingSetEstimatedOutputVectors[isoindex, col] / np.clip(trainingSetEstimatedOutputVectors[backgroundindex, col], 1/32768, None)
				if iso in h['MeasuredIsotopeAbundances'] and h['MeasuredIsotopeAbundances'][iso] > 1e-9:
					valuesWithIso.append(trainingSetEstimatedOutputVectors[isoindex, col])
					ratiosWithIso.append(backgroundRatio)
				else:
					valuesWithoutIso.append(trainingSetEstimatedOutputVectors[isoindex, col])
					ratiosWithoutIso.append(backgroundRatio)
			
			
			valueThreshold, valueWithIsoMean, valueWithIsoStdDev, valueWithoutIsoMean, valueWithoutIsoStdDev = self.calculateRocThreshold(valuesWithIso, valuesWithoutIso)
			ratioThreshold, ratioWithIsoMean, ratioWithIsoStdDev, ratioWithoutIsoMean, ratioWithoutIsoStdDev = self.calculateRocThreshold(ratiosWithIso, ratiosWithoutIso)

			if plot:
				outdir = self.WorkingDirectory + '/figures'
				os.makedirs(outdir, exist_ok=True)

				plt.clf()
				plt.style.use(thisDir + '/ieee.mplstyle')
				plt.hist((valuesWithIso, valuesWithoutIso), color=['green', 'red'], histtype='bar', stacked=True, bins=100)
				bottom, top = plt.ylim()
				plt.plot([valueThreshold, valueThreshold], [0, top], 'b-')
				plt.xlabel('Output Values')
				plt.ylabel('Count')
				#plt.title(iso)
				plt.savefig(outdir + '/isotope-value-stats-' + iso + '.pgf')
				plt.savefig(outdir + '/isotope-value-stats-' + iso + '.png')

				plt.clf()
				plt.style.use(thisDir + '/ieee.mplstyle')
				plt.hist((ratiosWithIso, ratiosWithoutIso), color=['green', 'red'], histtype='bar', stacked=True, bins=100)
				bottom, top = plt.ylim()
				plt.plot([ratioThreshold, ratioThreshold], [0, top], 'b-')
				plt.xlabel('Background Ratio')
				plt.ylabel('Count')
				#plt.title(iso)
				plt.savefig(outdir + '/background-ratio-stats-' + iso + '.pgf')
				plt.savefig(outdir + '/background-ratio-stats-' + iso + '.png')

			# Evaluate the ROC on the training set for this isotope
			rocResults, partRocCorrect = self.evaluateRocResults(trainingSetDict, iso, trainingSetEstimatedOutputVectors[isoindex, :], valueThreshold, valueWithIsoMean, valueWithIsoStdDev, valueWithoutIsoMean, valueWithoutIsoStdDev)

			for i in range(len(partRocCorrect)):
				if not partRocCorrect[i]:
					valueRocCorrect[i] = 0
			
			ROC['IsotopeValueMethod'][iso] = {'Threshold': valueThreshold}
			rocEvaluation['IsotopeValueMethod']['TrainingSet'][iso] = rocResults

			ratioValues = trainingSetEstimatedOutputVectors[isoindex, :] / np.clip(trainingSetEstimatedOutputVectors[backgroundindex, :], 1/32768, None)

			rocResults, partRocCorrect = self.evaluateRocResults(trainingSetDict, iso, ratioValues, ratioThreshold, ratioWithIsoMean, ratioWithIsoStdDev, ratioWithoutIsoMean, ratioWithoutIsoStdDev)

			for i in range(len(partRocCorrect)):
				if not partRocCorrect[i]:
					ratioRocCorrect[i] = 0
			
			ROC['BackgroundRatioMethod'][iso] = {'Threshold': valueThreshold}
			rocEvaluation['BackgroundRatioMethod']['TrainingSet'][iso] = rocResults
		
		trainingSetValueRocCorrectRate = sum(valueRocCorrect) / len(valueRocCorrect)
		trainingSetRatioRocCorrectRate = sum(ratioRocCorrect) / len(ratioRocCorrect)

		# Evaluate the test set for ROC
		for h in testSetDict:
			h['EstimatedIsotopeAbundances'] = None
			h['RocResults'] = {}
		valueRocCorrect = [1 for i in range(len(testSetDict))]
		ratioRocCorrect = [1 for i in range(len(testSetDict))]
		for iso in classificationIsotopes:
			if iso == 'Background':
				continue
			isoindex = classificationIsotopeIndices[iso]
			
			rocResults, partRocCorrect = self.evaluateRocResults(testSetDict, iso, testSetEstimatedOutputVectors[isoindex, :], valueThreshold)

			for i in range(len(partRocCorrect)):
				if not partRocCorrect[i]:
					valueRocCorrect[i] = 0
			
			rocEvaluation['IsotopeValueMethod']['TestSet'][iso] = rocResults
			
			ratioValues = testSetEstimatedOutputVectors[isoindex, :] / np.clip(testSetEstimatedOutputVectors[backgroundindex, :], 1/32768, None)

			rocResults, partRocCorrect = self.evaluateRocResults(testSetDict, iso, ratioValues, ratioThreshold)

			for i in range(len(partRocCorrect)):
				if not partRocCorrect[i]:
					ratioRocCorrect[i] = 0
			
			rocEvaluation['BackgroundRatioMethod']['TestSet'][iso] = rocResults

		testSetValueRocCorrectRate = sum(valueRocCorrect) / len(valueRocCorrect)
		testSetRatioRocCorrectRate = sum(ratioRocCorrect) / len(ratioRocCorrect)

		# Create the output dictionary
		d = trainingAndTestSetDict
		d['Type'] = 'TrainingEvaluation'

		for col in range(trainingSetInputVectors.shape[1]):
			# Save the data for each training set vector
			est = {}
			for i, iso in enumerate(classificationIsotopes):
				est[iso] = trainingSetEstimatedOutputVectors[i, col]
			#trdc = 
			trainingSetDict[col]['EstimatedIsotopeAbundances'] = est
			trainingSetDict[col]['MSE'] = trainingSetMses[col]
		
		for col in range(testSetInputVectors.shape[1]):
			# Save the data for each training set vector
			est = {}
			for i, iso in enumerate(classificationIsotopes):
				est[iso] = int(testSetEstimatedOutputVectors[i, col])
			#trdc = 
			testSetDict[col]['EstimatedIsotopeAbundances'] = est
			testSetDict[col]['MSE'] = testSetMses[col]
		
		numConvLayers = 0
		numFCLayers = 0
		stride = 0
		kernelSize = 0
		totalMACs = 0
		totalParams = 0
		numLayers = 0

		layers = trainingDataDict['Layers']
		prevLayerOutputWidth = 2**trainingDataDict['DesiredHistogramBits']
		prevLayerOutputChannels = 1
		for layer in layers:
			if 'Weights' in layer:
				layer.pop('Weights')
			layerType = layer['Type'].lower()

			if layerType == 'fc':
				numFCLayers += 1
				layer['NumParams'] = (prevLayerOutputWidth + int(layer['UseBias'])) * layer['NumOutputs']
				layer['NumMACs'] = layer['NumParams']
				prevLayerOutputWidth = layer['NumOutputs']
				numLayers += 1
			elif layerType == 'conv':
				numConvLayers += 1
				stride = layer['Stride']
				kernelSize = layer['KernelSize']
				layer['NumParams'] = layer['KernelSize'] * layer['NumFilters'] * prevLayerOutputChannels
				layer['NumMACs'] = prevLayerOutputWidth * prevLayerOutputChannels * layer['KernelSize'] * layer['NumFilters'] // layer['Stride']
				layer['NumOutputs'] = prevLayerOutputWidth * layer['NumFilters'] // layer['Stride']
				prevLayerOutputChannels = layer['NumFilters']
				prevLayerOutputWidth //= layer['Stride']
				numLayers += 1
			elif layerType == 'maxpooling':
				layer['NumParams'] = 0
				layer['NumMACs'] = 0
				layer['NumOutputs'] = (prevLayerOutputWidth * prevLayerOutputChannels) // layer['PoolSize']
				prevLayerOutputWidth //= layer['PoolSize']
			elif layerType == 'flatten':
				layer['NumParams'] = 0
				layer['NumMACs'] = 0
				layer['NumOutputs'] = prevLayerOutputWidth * prevLayerOutputChannels
				prevLayerOutputWidth = layer['NumOutputs']
				prevLayerOutputChannels = 1
			totalParams += layer['NumParams']
			totalMACs += layer['NumMACs']

		if totalParams != numTrainableParams:
			print('Error! total params is', totalParams, 'but numTrainableParams is', numTrainableParams)
			return False
		
		d['Layers'] = layers
		d['NumLayers'] = numLayers
		d['NumParams'] = totalParams
		d['NumMACs'] = totalMACs
		d['NumConvLayers'] = numConvLayers
		d['NumFullyConnectedLayers'] = numFCLayers
		d['Stride'] = stride
		d['KernelSize'] = kernelSize
		d['TrainingSetMse'] = trainingSetMse
		d['TestSetMse'] = testSetMse
		d['ArchetypalMse'] = archetypalMse
		d['ROC'] = ROC
		d['RocEvaluation'] = rocEvaluation
		d['TrainingSetIsotopeValueMethodRocCorrectRate'] = trainingSetValueRocCorrectRate
		d['TrainingSetBackgroundRatioMethodRocCorrectRate'] = trainingSetRatioRocCorrectRate
		d['TestSetIsotopeValueMethodRocCorrectRate'] = testSetValueRocCorrectRate
		d['TestSetBackgroundRatioMethodRocCorrectRate'] = testSetRatioRocCorrectRate
		
		# Save the evaluation data
		trainingEvaluationPath = self.WorkingDirectory + '/TrainingEvaluation.json'
		with open(trainingEvaluationPath, 'w') as f:
			json.dump(d, f)
		
		# Save a results summary file
		resultsPath = self.WorkingDirectory + '/results-summary.txt'

		results = [
			'Timestamp: ' + d['Timestamp'],
			'Chip name: ' + d['ChipName'],
			'Die ID: ' + d['DieID'],
			'AFE name: ' + d['AfeName'],
			'Classification isotopes: ' + str(classificationIsotopes),
			'Number of trainable parameters: ' + str(numTrainableParams),
			'Training set MSE: {:.3e}'.format(trainingSetMse),
			'Test set MSE:     {:.3e}'.format(testSetMse),
			'Archetypal MSE:   {:.3e}'.format(archetypalMse),
			'Training set ROC Correct Rate (isotope value method):    {:.2f}%'.format(100 * trainingSetValueRocCorrectRate),
			'Training set ROC Correct Rate (background ratio method): {:.2f}%'.format(100 * trainingSetRatioRocCorrectRate),
			'Test set ROC Correct Rate (isotope value method):        {:.2f}%'.format(100 * testSetValueRocCorrectRate),
			'Test set ROC Correct Rate (background ratio method):     {:.2f}%'.format(100 * testSetRatioRocCorrectRate),
		]

		with open(resultsPath, 'w') as f:
			f.write('\n'.join(results) + '\n')
		
		# Print
		if verbose:
			print('Number of trainable parameters:', numTrainableParams)
			print('Training set MSE: {:.3e}'.format(trainingSetMse))
			print('Test set MSE:     {:.3e}'.format(testSetMse))
			print('Archetypal MSE:   {:.3e}'.format(archetypalMse))
			print('Training set ROC Correct Rate (isotope value method):    {:.2f}%'.format(100 * trainingSetValueRocCorrectRate))
			print('Training set ROC Correct Rate (background ratio method): {:.2f}%'.format(100 * trainingSetRatioRocCorrectRate))
			print('Test set ROC Correct Rate (isotope value method):        {:.2f}%'.format(100 * testSetValueRocCorrectRate))
			print('Test set ROC Correct Rate (background ratio method):     {:.2f}%'.format(100 * testSetRatioRocCorrectRate))
			print('Saved training evaluation data to', trainingEvaluationPath)
			print('Saved results summary file data to', resultsPath)

			if engine == 'tensorflow':
				print(model.summary())

		return d
	


	def GenerateMlpnnBinaryFile(self, workingDirectory):
		'''
		The ordering of the file is as follows:
		* numWeightsMatrices (uint8): The number of weights matrices in the MLPNN. numWeightsMatrices is also equal to numLayers - 1
		* numInputNeurons (uint16): The number of input neurons
		* for each weights matrix/layer (there are numWeightsMatrices of them):
			* numOutputNeurons (uint16): The number of output neurons for this layer
			useBias (uint8): Either 1 or 0 for if this layer uses a bias term or not
			eightsMatrix (uint8 * 3 * thisLayerNumNeurons * (prevLayerNumNeurons + thisLayerUseBias)): This is intended to be loaded on a byte basis directly into the NPU RAM. Each 3-byte weight is stored in reverse byte order because a file is naturally big-endian, but RISC-V is little-endian
		* ROC data for each output neuron (there are lastNeuronsPerLayer of them):
			* Isotope name string (string of ASCII chars, variable length, ends in null terminator)
			* ROC threshold value (uint16): If the MLPNN output is greater than or equal to the associated ROC output, then the MLPNN is predicting that that output's isotope is present in the histogram
		'''
		if workingDirectory is None:
			workingDirectory = self.WorkingDirectory
		
		# Load the training data
		trainingDataPath = workingDirectory + '/TrainingData.json'
		if not os.path.isfile(trainingDataPath):
			print('Training data does not exist at', trainingDataPath)
			return False
		
		with open(trainingDataPath, 'r') as f:
			trainingDataDict = json.load(f)

		# Get the classification isotopes
		classificationIsotopes = trainingDataDict['ClassificationIsotopes']
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i

		# Get the relevant data from the training data file
		neuronsPerLayer = trainingDataDict['NeuronsPerLayer']
		numWeightsMatrices = len(neuronsPerLayer) - 1
		useBiasPerLayer = trainingDataDict['UseBiasPerLayer']
		layerWeightsMatricesQ = trainingDataDict['LayerWeightsMatricesQ']

		# Load the evaluation data
		trainingEvaluationPath = workingDirectory + '/TrainingEvaluation.json'
		if not os.path.isfile(trainingEvaluationPath):
			print('Training evaluation data does not exist at', trainingEvaluationPath)
			return False

		with open(trainingEvaluationPath, 'r') as f:
			evaluationDict = json.load(f)

		# Save the binary data
		b = b''
		b += numWeightsMatrices.to_bytes(length=1, byteorder='little', signed=False)	# numWeightsMatrices
		b += neuronsPerLayer[0].to_bytes(length=2, byteorder='little', signed=False)	# numInputNeurons
		for i in range(numWeightsMatrices):
			b += neuronsPerLayer[i + 1].to_bytes(length=2, byteorder='little', signed=False)	# this layer's numOutputNeurons
			b += int(useBiasPerLayer[i]).to_bytes(length=1, byteorder='little', signed=False)	# this layer's useBias
			weightsMatrix = np.asarray(layerWeightsMatricesQ[i], dtype=int)
			for row in range(weightsMatrix.shape[0]):
				for col in range(weightsMatrix.shape[1]):
					b += int(weightsMatrix[row, col]).to_bytes(length=3, byteorder='little', signed=True)	# 3-byte signed Q8.15 synaptic weight
			inputVectorSizeInRam = (((neuronsPerLayer[i] * 2) + 2) >> 2) << 2
			outputVectorSizeInRam = (((neuronsPerLayer[i + 1] * 2) + 2) >> 2) << 2
			weightsMatrixSizeInRam = 3 * neuronsPerLayer[i + 1] * (neuronsPerLayer[i] + int(useBiasPerLayer[i]))
			sizeInRam = inputVectorSizeInRam + outputVectorSizeInRam + weightsMatrixSizeInRam
			if sizeInRam > 16384:
				print('ERROR: Layer', i, ', number of inputs =', neuronsPerLayer[i], ', number of outputs =', neuronsPerLayer[i + 1], ', use bias =', useBiasPerLayer[i], ', will NOT fit in a 16 kB RAM chunk because it uses', sizeInRam, 'bytes')
				return False

			print('Layer', i, ', number of inputs =', neuronsPerLayer[i], ', number of outputs =', neuronsPerLayer[i + 1], ', use bias =', useBiasPerLayer[i], ', size in RAM =', sizeInRam, 'bytes')

		#roc = [evaluationDict['ROC'][classificationIsotopes[i]]['ThresholdQ'] for i in range(neuronsPerLayer[-1])]
		#for threshold in roc:
		#	b += threshold.to_bytes(length=2, byteorder='little', signed=False)

		for iso in classificationIsotopes:
			b += iso.encode('ascii') + int(0).to_bytes(length=1, byteorder='little', signed=False)	# Name string with null terminator
			b += evaluationDict['ROC'][iso]['ThresholdQ'].to_bytes(length=2, byteorder='little', signed=False)	# threshold
		
		binaryMlpnnFilePath = workingDirectory + '/MLPNN.BIN'
		with open(binaryMlpnnFilePath, 'wb') as f:
			f.write(b)
		
		print('Wrote binary MLPNN file to', binaryMlpnnFilePath)
		return True
		





	def feedforwardQ(self, useBiasPerLayer:list, inputVectorsQ:np.ndarray, layerWeightsMatricesQ:list):
		activationVectorsQ = [None for i in range(len(layerWeightsMatricesQ))]
		decisionVectorsQ = [None for i in range(len(layerWeightsMatricesQ))]
		for i in range(len(layerWeightsMatricesQ)):
			# Get the input vectors
			if i == 0:
				layerInputVectorsQ = inputVectorsQ.astype(np.int64)
			else:
				layerInputVectorsQ = decisionVectorsQ[i - 1].astype(np.int64)
			
			# Add bias terms if needed
			if useBiasPerLayer[i]:
				layerInputVectorsQ = np.concatenate((layerInputVectorsQ, 32768 * np.ones((1, layerInputVectorsQ.shape[1]), dtype=np.int64)), axis=0)
			
			# Multiply the matrices
			prod = layerWeightsMatricesQ[i].astype(np.int64).dot(layerInputVectorsQ)

			# Round and convert to Q16_15 for storage in the activation vector
			# This Python shifting operation is verified identical to the operation performed by the hardware NPU
			activationVectorsQ[i] = (prod + 16384) >> 15

			# Calculate the decision vector using the logistic sigmoid approximation
			decisionVectorsQ[i] = self.logSigApproxQVector(activationVectorsQ[i])
		return decisionVectorsQ[-1]
	
	def logSigApproxQ(self, x:int):
		# Verified identical to the operation performed by the hardware NPU
		if x < -131071:
			return 0
		if x > 131072:
			return 32767
		inputIsNegative = x < 0
		if inputIsNegative:
			x = -x
		a = 32767 - (x >> 2)
		b = (a * a) + 16383	# Note: this is identical to LogisticSigmoidApprox.vhd, which may have a bug. Should probably be 16384 instead of 16383
		Z = b >> 16
		if inputIsNegative:
			return Z
		return 32767 - Z
	
	def logSigApproxQVector(self, x:np.ndarray):
		y = np.zeros(x.shape, dtype=int)
		for row in range(x.shape[0]):
			for col in range(x.shape[1]):
				y[row, col] = self.logSigApproxQ(x[row, col])
		return y
	
	def toQx_15(self, x):
		return np.round(np.array(x) * 32768).astype(int)
	
	def calculateRocThreshold(self, valuesWithIso, valuesWithoutIso):
		# Calculate the Gaussian normal distribution using the value threshold method
		withIsoMean = np.mean(valuesWithIso)
		withIsoStdDev = np.std(valuesWithIso)
		withoutIsoMean = np.mean(valuesWithoutIso)
		withoutIsoStdDev = np.std(valuesWithoutIso)
		
		# Calculate the ROC threshold for the isotope
		minWith = min(valuesWithIso)
		maxWithout = max(valuesWithoutIso)
		if minWith > maxWithout:
			# A first attempt at getting the threshold
			threshold = (maxWithout + minWith) / 2
		else:
			# Calculate the threshold (x) beneath which will produce the desired false positive rate
			# This is based on the CDF of a Gaussian normal distribution: phi(x) = (1/2) * (1 + erf((x - u) / (sigma * sqrt(2))))
			# where x is the threshold, phi(x) is the probability that the threshold x will produce a false positive, u is the mean, and sigma is the standard deviation
			# Rearranging the equation to extract the threshold x gives: x = sigma * sqrt(2) * erfinv(2*phi - 1) + u
			# Note that the valuesWithIso will yield the false positive rate
			threshFalsePos = withIsoStdDev * np.sqrt(2) * erfinv(2 * (1 - self.DesiredFalsePositiveRate) - 1) + withIsoMean

			# Calculate the threshold (x) which will produce the desired true negative rate
			# Note that the valuesWithIso will yield the true negative rate
			threshTrueNeg = withoutIsoStdDev * np.sqrt(2) * erfinv(2 * (1 - self.DesiredFalseNegativeRate) - 1) + withoutIsoMean

			if threshFalsePos > threshTrueNeg and threshFalsePos > 0 and threshTrueNeg > 0:
				# A second attempt at getting the threshold
				# Since the true positives and true negatives have well defined groups that are separated from each other and in the correct order, simply split the gap between the two thresholds to optimize them both at once
				threshold = (threshFalsePos + threshTrueNeg) / 2
			elif threshFalsePos > 0:
				# A third attempt at getting the threshold
				# The true positives and true negatives overlap. In this case, we prefer not to generate false positives, so choose the threshold that generates the desired false positive rate 
				threshold = threshFalsePos
			elif threshTrueNeg > 0:
				# A fourth attempt at getting the threshold
				# The false positive rate is negative, so try useing the true negative rate instead
				threshold = threshTrueNeg
			else:
				# The fifth and last attempt at getting the threshold
				# Both the desired false positive and false negative rates are unattainable, so set the threshold to 1 plus the max of the "without" values to reduce the chance of a false positive
				threshold = maxWithout
		return threshold, withIsoMean, withIsoStdDev, withoutIsoMean, withoutIsoStdDev
	
	def evaluateRocResults(self, trainingOrTestSetDict, isotope, values, threshold, withIsoMean=None, withIsoStdDev=None, withoutIsoMean=None, withoutIsoStdDev=None):
		rocResults = {}
		if all([withIsoMean, withIsoStdDev, withoutIsoMean, withoutIsoStdDev]):
			# Calculate the statistics for the chosen threshold
			targetedFalsePositiveRate = 0.5 * (1 + erf((threshold - withIsoMean) / (withIsoStdDev * np.sqrt(2))))
			targetedTruePositiveRate = 1 - targetedFalsePositiveRate
			targetedTrueNegativeRate = 0.5 * (1 + erf((threshold - withoutIsoMean) / (withoutIsoStdDev * np.sqrt(2))))
			targetedFalseNegativeRate = 1 - targetedTrueNegativeRate

			rocResults = {'TargetedTruePositiveRate': targetedTruePositiveRate, 'TargetedFalsePositiveRate': targetedFalsePositiveRate, 'TargetedTrueNegativeRate': targetedTrueNegativeRate, 'TargetedFalseNegativeRate': targetedFalseNegativeRate}

		# Evaluate the threshold on the training set
		truePosCount = 0
		falsePosCount = 0
		trueNegCount = 0
		falseNegCount = 0
		rocCorrect = [1 for i in range(len(trainingOrTestSetDict))]
		for col, h in enumerate(trainingOrTestSetDict):
			value = values[col]
			if isotope in h['MeasuredIsotopeAbundances'] and h['MeasuredIsotopeAbundances'][isotope] > 1e-9:
				if value >= threshold:
					truePosCount += 1
					h['RocResults'][isotope] = {'PresentEst': True, 'Correct': True}
				else:
					falseNegCount += 1
					h['RocResults'][isotope] = {'PresentEst': False, 'Correct': False}
					rocCorrect[col] = 0
			else:
				if value >= threshold:
					falsePosCount += 1
					h['RocResults'][isotope] = {'PresentEst': True, 'Correct': False}
					rocCorrect[col] = 0
				else:
					trueNegCount += 1
					h['RocResults'][isotope] = {'PresentEst': False, 'Correct': True}
		
		actualTruePositiveRate = truePosCount / len(trainingOrTestSetDict)
		actualFalseNegativeRate = falseNegCount / len(trainingOrTestSetDict)
		
		actualTrueNegativeRate = trueNegCount / len(trainingOrTestSetDict)
		actualFalsePositiveRate = falsePosCount / len(trainingOrTestSetDict)

		rocResults['ActualTruePositiveRate'] = actualTruePositiveRate
		rocResults['ActualFalsePositiveRate'] = actualFalsePositiveRate
		rocResults['ActualTrueNegativeRate'] = actualTrueNegativeRate
		rocResults['ActualFalseNegativeRate'] = actualFalseNegativeRate

		return rocResults, rocCorrect
		#return rocCorrect, targetedTruePositiveRate, targetedFalsePositiveRate, targetedTrueNegativeRate, targetedFalseNegativeRate, actualTruePositiveRate, actualFalsePositiveRate, actualTrueNegativeRate, actualFalseNegativeRate
		#isotopeROC = {'Threshold': threshold, 'TargetedTruePositiveRate': truePositiveRate, 'TargetedFalsePositiveRate': targetedFalsePositiveRate, 'TargetedTrueNegativeRate': targetedTrueNegativeRate, 'TargetedFalseNegativeRate': targetedFalseNegativeRate, 'TrainingSetTruePositiveRate': actualTruePositiveRate, 'TrainingSetFalsePositiveRate': actualFalsePositiveRate, 'TrainingSetTrueNegativeRate': actualTrueNegativeRate, 'TrainingSetFalseNegativeRate': actualFalseNegativeRate}
	
	def createTensorFlowModel(self, trainingDataDictForLoadingWeights=None):
		model = models.Sequential()
		model.add(layers.Input(shape=(2**self.DesiredHistogramBits, 1)))

		for layerNum, layer in enumerate(self.Layers):
			layerType = layer['Type'].lower()
			
			if layerType == 'fc':
				model.add(layers.Dense(layer['NumOutputs'], activation=layer['ActivationFunction'], use_bias=layer['UseBias']))
			elif layerType == 'conv':
				model.add(layers.Conv1D(filters=layer['NumFilters'], kernel_size=layer['KernelSize'], strides=layer['Stride'], padding='same', activation=layer['ActivationFunction'], use_bias=layer['UseBias']))
			elif layerType == 'maxpooling':
				model.add(layers.MaxPooling1D(pool_size=layer['PoolSize']))
			elif layerType == 'flatten':
				model.add(layers.Flatten())
			else:
				raise Exception('Layer type "' + str(layerType) + '" not supported')
		
		if trainingDataDictForLoadingWeights is not None:
			for layerNum, layer in enumerate(self.Layers):
				if 'Weights' in trainingDataDictForLoadingWeights['Layers'][layerNum]:
					weights = trainingDataDictForLoadingWeights['Layers'][layerNum]['Weights']
					if type(weights) != list or len(weights) == 0:
						continue
					weights = [np.array(w) for w in weights]
					model.layers[layerNum].set_weights(weights)

		return model

	def testConv(self):
		archetypalHistogramsJsonPath = self.WorkingDirectory + '/ArchetypalHistograms.json'
		if not os.path.isfile(archetypalHistogramsJsonPath):
			print('ArchetypalHistograms file does not exist at', archetypalHistogramsJsonPath)
			return False
		
		with open(archetypalHistogramsJsonPath, 'r') as f:
			d = json.load(f)
		
		if type(d) != dict or 'Type' not in d or d['Type'] != 'ArchetypalHistograms':
			print('Invalid archetypal histograms file at', archetypalHistogramsJsonPath)
			return False
		
		# Get the classification isotopes
		classificationIsotopes = d['ClassificationIsotopes']
		if 'Background' in classificationIsotopes:
			classificationIsotopes.pop('Background')
		classificationIsotopes = ['Background'] + classificationIsotopes
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i
		numInputs = 2**self.DesiredHistogramBits
		numOutputs = len(classificationIsotopes)
		if len(d['ArchetypalHistograms']) != numOutputs:
			print('The ArchetypalHistograms.json file contains', len(d['ArchetypalHistograms']), 'archetypal histograms, but the system expects', numOutputs, 'outputs')
			return False
		
		# Get the archetypal histograms, each with a total abundance of 1.0
		self.ArchetypalHistograms = np.zeros((numInputs, numOutputs), dtype=float)
		for ahist in d['ArchetypalHistograms']:
			if len(ahist['Counts']) != numInputs:
				print('An archetypal histogram does not have', numInputs, 'elements')
				return False
			abundanceOneCounts = np.array(ahist['Counts'], dtype=float).reshape((len(ahist['Counts']), 1))
			abundanceOneCounts = abundanceOneCounts / sum(ahist['Counts'])
			isotopeIndex = classificationIsotopeIndices[ahist['Isotope']]
			self.ArchetypalHistograms[:, [isotopeIndex]] = abundanceOneCounts

		model = models.Sequential()
		model.add(layers.Conv1D(filters=32, kernel_size=9, strides=2, padding='same', activation='sigmoid', input_shape=(64, 1)))
		model.add(layers.MaxPooling1D((2)))
		model.add(layers.Conv1D(filters=16, kernel_size=5, strides=2, padding='same', activation='sigmoid'))
		model.add(layers.MaxPooling1D((2)))
		model.add(layers.Flatten())
		model.add(layers.Dense(5, activation='sigmoid', use_bias=True))
		#model.add(layers.Conv1D(filters=5, kernel_size=5, strides=2, padding='same', activation='sigmoid'))

		print(model.summary())

		trainingSetExpectedInputVectors, trainingSetExpectedOutputVectors = self.GetRandomInputAndExpectedOutputVectors(1000)
		trainingSetExpectedInputVectors = trainingSetExpectedInputVectors.T.reshape((trainingSetExpectedInputVectors.shape[1], trainingSetExpectedInputVectors.shape[0], 1))
		trainingSetExpectedOutputVectors = trainingSetExpectedOutputVectors.T.reshape((trainingSetExpectedOutputVectors.shape[1], trainingSetExpectedOutputVectors.shape[0], 1))
		#trainingSetExpectedInputVectors = trainingSetExpectedInputVectors.reshape((1, 64, 1))
		#trainingSetExpectedInputVectors = trainingSetExpectedInputVectors.reshape((len(trainingSetExpectedInputVectors)))
		#trainingSetExpectedInputVectors = trainingSetExpectedInputVectors.T
		print('Input shape:', trainingSetExpectedInputVectors.shape)
		trainingSetEstimatedOutputVectors = model.predict(trainingSetExpectedInputVectors)
		#print(trainingSetEstimatedOutputVectors)
		print('Output shape:', trainingSetEstimatedOutputVectors.shape)

		model.compile(optimizer='sgd', loss='mse')

		history = model.fit(trainingSetExpectedInputVectors, trainingSetExpectedOutputVectors, epochs=50)

		trainingSetExpectedInputVectors, trainingSetExpectedOutputVectors = self.GetRandomInputAndExpectedOutputVectors(1)
		trainingSetExpectedInputVectors = trainingSetExpectedInputVectors.T.reshape((trainingSetExpectedInputVectors.shape[1], trainingSetExpectedInputVectors.shape[0], 1))
		trainingSetExpectedOutputVectors = trainingSetExpectedOutputVectors.T.reshape((trainingSetExpectedOutputVectors.shape[1], trainingSetExpectedOutputVectors.shape[0], 1))

		trainingSetEstimatedOutputVectors = model.predict(trainingSetExpectedInputVectors)
		print('Expected output shape:', trainingSetExpectedOutputVectors.shape)
		print('Estimated output shape:', trainingSetEstimatedOutputVectors.shape)
		mse = np.sum((trainingSetEstimatedOutputVectors - trainingSetExpectedOutputVectors)**2) / len(trainingSetEstimatedOutputVectors)
		print('Expected outputs:', trainingSetExpectedOutputVectors)
		print('Estimated outputs:', trainingSetEstimatedOutputVectors)
		print('MSE:', mse)



def CreateNpuConfigs(genericConfigJsonPath:str):
	# Load generic config
	workingDirectory = os.path.dirname(os.path.abspath(genericConfigJsonPath)).replace('\\', '/')
	n = NPU()
	if not n.LoadConfigFromJson(genericConfigJsonPath):
		print('Generic config must be the path to a valid config.json file')
		return False
	testsDir = workingDirectory + '/tests'
	if os.path.exists(testsDir):
		print('tests directory already exists, please make a backup of it and delete it before running this command')
		return False
	os.makedirs(testsDir)
	
	numOutputs = len(n.ClassificationIsotopes)
	if 'Background' not in n.ClassificationIsotopes:
		numOutputs += 1
	
	genericConfig = {'Type': 'NpuIsotopeIDConfigMLP'}
	genericConfig = {**genericConfig, **n.ConfigToDict()}

	if 'Layers' in genericConfig:
		genericConfig['Layers'] = None
	if 'TrainingSetType' in genericConfig:
		genericConfig['TrainingSetType'] = None
	if 'Engine' in genericConfig:
		genericConfig['Engine'] = None
	
	# Create training and test sets (this generates the ArchetypalHistograms.json and TrainingSet.json files in the root directory)
	n.CreateSets()

	# Generate the list of all configs to use
	configs = []
	#numNonOutputLayers = {
	#	1: {'default': 32, 'minOutputs': 16, 'maxOutputs': 128, 'step': 16},
	#	2: {'minOutputs': 8, 'maxOutputs': 32, 'step': 8},
	#	3: {'minOutputs': 8, 'maxOutputs': 32, 'step': 8},
	#}
	numNonOutputLayers = {
		1: {'default': 32, 'minOutputs': 32, 'maxOutputs': 44, 'step': 4},
		2: {'minOutputs': 24, 'maxOutputs': 40, 'step': 4},
		3: {'minOutputs': 24, 'maxOutputs': 40, 'step': 4},
	}

	numOutputsPerLayerAllCombos = []
	for numOutputsPerLayer in numNonOutputLayers:
		numOutputsPerLayerLists = []
		for j in numNonOutputLayers:
			if j > numOutputsPerLayer:
				continue
			d = numNonOutputLayers[j]
			numOutputsPerLayerLists.append(list(range(d['minOutputs'], d['maxOutputs'] + 1, d['step'])))

		theseLayerSizes = list(itertools.product(*numOutputsPerLayerLists))
		numOutputsPerLayerAllCombos += theseLayerSizes
	
	for combo in numOutputsPerLayerAllCombos:
		#for trainingSetType in ['set', 'archetypal']:
		for trainingSetType in ['archetypal']:
			# Do the OptimizedMLPNN config
			layers = []
			for layerNum in range(len(combo)):
				d = {
					'Type': 'FC',
					'Name': 'Layer ' + str(layerNum + 1),
					'NumOutputs': combo[layerNum],
					'UseBias': True,
					'ActivationFunction': 'sigmoid-approx',
				}
				layers.append(d)
			d = {
				'Type': 'FC',
				'Name': 'Output Layer',
				'NumOutputs': numOutputs,
				'UseBias': True,
				'ActivationFunction': 'sigmoid-approx',
			}
			layers.append(d)
		
			config = genericConfig.copy()
			config['Engine'] = 'OptimizedMLPNN'
			config['TrainingSetType'] = trainingSetType
			config['Layers'] = layers
			configs.append(config)
			
			'''
			# Do the tensorflow config
			layers = []
			for layerNum in range(len(combo)):
				d = {
					'Type': 'CONV',
					'Name': 'Layer ' + str(layerNum + 1) + ' CONV',
					'NumFilters': combo[layerNum],
					'KernelSize': 7,
					'Stride': 2,
					'UseBias': False,
					'ActivationFunction': 'sigmoid',
				}
				layers.append(d)
				d = {
					'Type': 'MaxPooling',
					'Name': 'Layer ' + str(layerNum + 1) + ' MaxPooling',
					'PoolSize': 2,
				}
				layers.append(d)
			d = {
				'Type': 'Flatten',
				'Name': 'Flatten',
			}
			layers.append(d)
			d = {
				'Type': 'FC',
				'Name': 'Output Layer',
				'NumOutputs': numOutputs,
				'UseBias': True,
				'ActivationFunction': 'sigmoid',
			}
			layers.append(d)

			config = genericConfig.copy()
			config['Engine'] = 'TensorFlow'
			config['TrainingSetType'] = trainingSetType
			config['Layers'] = layers
			configs.append(config)
			'''

	# Create working directories for each config
	for i, config in enumerate(configs):
		testNum = i + 1
		testName = 'Test{:04}'.format(testNum)
		thisTestDir = testsDir + '/' + testName
		os.makedirs(thisTestDir)
		copyfile(workingDirectory + '/ArchetypalHistograms.json', thisTestDir + '/ArchetypalHistograms.json')
		copyfile(workingDirectory + '/TrainingSet.json', thisTestDir + '/TrainingSet.json')

		with open(thisTestDir + '/config.json', 'w') as f:
			json.dump(config, f)
	
	print('Created ' + str(len(configs)) + ' configurations')

	return True

def CreateBetterConfigs(genericConfigJsonPath:str, baseTestName:str):
	# Load config
	workingDirectory = os.path.dirname(os.path.abspath(genericConfigJsonPath)).replace('\\', '/')

	testsDir = workingDirectory + '/tests'

	baseTestDir = testsDir + '/' + baseTestName
	if not os.path.isdir(baseTestDir):
		print('could not find base test')
		return False

	baseConfigJsonPath = baseTestDir + '/config.json'
	n = NPU()
	if not n.LoadConfigFromJson(baseConfigJsonPath):
		print('Config must be the path to a valid config.json file')
		return False
	
	numOutputs = len(n.ClassificationIsotopes)
	if 'Background' not in n.ClassificationIsotopes:
		numOutputs += 1
	
	genericConfig = {'Type': 'NpuIsotopeIDConfigMLP'}
	genericConfig = {**genericConfig, **n.ConfigToDict()}

	if 'TrainingSetType' in genericConfig:
		genericConfig['TrainingSetType'] = None
	
	# Create training and test sets (this generates the ArchetypalHistograms.json and TrainingSet.json files in the root directory)
	n.CreateSets()

	# Generate the list of all configs to use
	configs = []
	for stride in [1, 2, 4]:
		for kernelSize in [5, 7, 9, 11, 13]:
			for activation_function in ['sigmoid', 'relu']:
				for trainingSetType in ['set', 'archetypal']:
					config = copy.deepcopy(genericConfig)
					config['TrainingSetType'] = trainingSetType
					for layer in config['Layers']:
						if 'Stride' in layer:
							layer['Stride'] = stride
						if 'KernelSize' in layer:
							layer['KernelSize'] = kernelSize
						if layer['Type'].lower() == 'conv':
							layer['ActivationFunction'] = activation_function
					configs.append(config)

	# Create working directories for each config
	for i, config in enumerate(configs):
		testNum = i + 1
		testName = baseTestName + '_{:04}'.format(testNum)
		thisTestDir = testsDir + '/' + testName
		os.makedirs(thisTestDir)
		copyfile(workingDirectory + '/ArchetypalHistograms.json', thisTestDir + '/ArchetypalHistograms.json')
		copyfile(workingDirectory + '/TrainingSet.json', thisTestDir + '/TrainingSet.json')

		with open(thisTestDir + '/config.json', 'w') as f:
			json.dump(config, f)
	
	print('Created ' + str(len(configs)) + ' configurations')

	return True

def TrainNpuConfigs(genericConfigJsonPath:str):
	# Get a list of all the test directories in the tests directory
	workingDirectory = os.path.dirname(os.path.abspath(genericConfigJsonPath)).replace('\\', '/')
	majorTestDir = workingDirectory + '/tests'
	if not os.path.isdir(majorTestDir):
		print('Error: tests directory does not exist')
		return False
	
	allTestDirs = [os.path.join(majorTestDir, o).replace('\\', '/') for o in os.listdir(majorTestDir) if os.path.isdir(os.path.join(majorTestDir, o).replace('\\', '/'))]
	if len(allTestDirs) == 0:
		print('No tests exist in the tests directory. Run --createConfigs first')
		return False
	
	testDirs = [testDir for testDir in allTestDirs if not os.path.exists(testDir + '/TrainingData.json')]
	if len(testDirs) == 0:
		print('All tests have already been trained')
		return True
	
	if len(allTestDirs) != len(testDirs):
		print(len(allTestDirs) - len(testDirs), 'out of', len(allTestDirs), 'configurations ({:.1f}%)'.format(100 * (len(allTestDirs) - len(testDirs)) / len(allTestDirs)), 'have already been trained. Skipping those that have already been trained...')
	
	# Pre-compile the OptimizedMLPNN
	n = NPU()
	if not n.LoadConfigFromJson(genericConfigJsonPath):
		print('Generic config must be the path to a valid config.json file')
		return False
	n.CompileMlpnnTrainingAlgorithm(4, [4, 2], [True, False], ['sigmoid-approx', 'sigmoid'])
	
	# Train each config
	pbar = ProgressBar(widgets=['Training: ', Percentage(), ' ', Bar(), ' ', ETA()])
	for testDir in pbar(testDirs):
		n = NPU()
		configPath = testDir + '/config.json'
		if not n.LoadConfigFromJson(configPath):
			print('')
			print('Error loading config')
			return False
		ret = n.Train(timeCompile=False, verbose=False, plot=True)
		if not ret:
			print('')
			print('Error training test in directory', testDir)
			return False
	
	return True

def EvaluateNpuConfigs(genericConfigJsonPath:str, reEvaluate=True):
	# Get a list of all the test directories in the tests directory
	workingDirectory = os.path.dirname(os.path.abspath(genericConfigJsonPath)).replace('\\', '/')
	majorTestDir = workingDirectory + '/tests'
	if not os.path.isdir(majorTestDir):
		print('Error: tests directory does not exist')
		return False
	
	allTestDirs = [os.path.join(majorTestDir, o).replace('\\', '/') for o in os.listdir(majorTestDir) if os.path.isdir(os.path.join(majorTestDir, o).replace('\\', '/'))]
	if len(allTestDirs) == 0:
		print('No tests exist in the tests directory. Run --createConfigs first')
		return False
	
	testDirs = [testDir for testDir in allTestDirs if os.path.exists(testDir + '/TrainingData.json')]
	if len(testDirs) < len(allTestDirs):
		print('Error: some tests have not been trained yet. Please train them with --trainConfigs')
		return False
	
	# Evaluate each config
	results = []
	pbar = ProgressBar(widgets=['Evaluating: ', Percentage(), ' ', Bar(), ' ', ETA()])
	for testDir in pbar(testDirs):
		testName = os.path.basename(testDir)
		if not reEvaluate and os.path.isfile(testDir + '/TrainingEvaluation.json'):
			with open(testDir + '/TrainingEvaluation.json') as f:
				d = json.load(f)
		else:
			n = NPU()
			configPath = testDir + '/config.json'
			if not n.LoadConfigFromJson(configPath):
				print('')
				print('Error loading config')
				return False
			d = n.EvaluateTrainingData(verbose=False, plot=False)
		if type(d) != dict:
			print('')
			print('Error evaluating test in directory', testDir)
			return False
		d.pop('TrainingSet')
		d.pop('TestSet')
		d['TestName'] = testName
		d['TestDirectory'] = testDir

		with open(testDir + '/TrainingData.json', 'r') as f:
			dtrain = json.load(f)
		
		d['TrainingSetType'] = dtrain['TrainingSetType']
		d['Engine'] = dtrain['Engine']
		d['TrainedMinMse'] = dtrain['TrainedMinMse']
		d['EpochAtMinMse'] = dtrain['EpochAtMinMse']
		d['TrainingTime'] = dtrain['TrainingTime']

		results.append(d)
	
	# Save the results dictionary
	d = {
		'Type': 'TrainingSweepEvaluation',
		'Results': results,
	}

	# Find the best results
	b = sorted(results, key=lambda x: x['TestSetMse'], reverse=False)
	d['BestTestSetMseTest'] = b[0]

	b = sorted(results, key=lambda x: x['ArchetypalMse'], reverse=False)
	d['BestArchetypalMseTest'] = b[0]

	b = sorted(results, key=lambda x: (-x['TestSetIsotopeValueMethodRocCorrectRate'], x['TestSetMse']))
	d['BestRocIsotopeValueMethodTest'] = b[0]

	b = sorted(results, key=lambda x: (-x['TestSetBackgroundRatioMethodRocCorrectRate'], x['TestSetMse']))
	d['BestRocBackgroundRatioMethodTest'] = b[0]
	
	# Save the results dictionary
	with open(workingDirectory + '/TrainingSweepEvaluation.json', 'w') as f:
		json.dump(d, f)
	
	# Create a results file
	lines = [
		'Timestamp: ' + get_string_timestamp(),
		'Number of configurations evaluated: ' + str(len(results)),
		'',
	]

	linesDict = copy.copy(d)
	linesDict.pop('Type')
	linesDict.pop('Results')

	for key in linesDict:
		keyDict = linesDict[key]
		lines += [
			key + ': ' + keyDict['TestName'],
			'Directory: ' + keyDict['TestDirectory'],
			'Training set type: ' + keyDict['TrainingSetType'],
			'Engine: ' + keyDict['Engine'],
			'Number of layers: ' + str(keyDict['NumLayers']),
			'Number of trainable parameters: ' + str(keyDict['NumParams']),
			'Number of MACs: ' + str(keyDict['NumMACs']),
			'Number of CONV Layers: ' + str(keyDict['NumConvLayers']),
			'Number of Fully Connected Layers: ' + str(keyDict['NumFullyConnectedLayers']),
			'Stride: ' + str(keyDict['Stride']),
			'Kernel Size: ' + str(keyDict['KernelSize']),
			'Test Set MSE: {:3e}'.format(keyDict['TestSetMse']),
			'Archetypal MSE: {:3e}'.format(keyDict['ArchetypalMse']),
			'Test Set Isotope Value Method ROC Correct Rate:    {:.2f}%'.format(keyDict['TestSetIsotopeValueMethodRocCorrectRate'] * 100),
			'Test Set Background Ratio Method ROC Correct Rate: {:.2f}%'.format(keyDict['TestSetBackgroundRatioMethodRocCorrectRate'] * 100),
			'',
		]
	
	with open(workingDirectory + '/TrainingSweepBestResults.txt', 'w') as f:
		for line in lines:
			f.write(line + '\n')
	
	# Create a CSV that can be sorted in Excel
	with open(workingDirectory + '/TrainingSweepEvaluation.csv', 'w') as f:
		f.write('#Test Name, Training Set Type, Engine, Number of Layers, Number of Trainable Parameters, Number of MACs, Number of CONV Layers, Number of Fully Connected Layers, CONV Stride, CONV Kernel Size, Activation Function, Test Set MSE, Archetypal MSE, ROC Correct Rate (Isotope Value Method), ROC Correct Rate (Background Ratio Method)\n')

		for result in results:
			f.write(str(result['TestName']) + ',')
			f.write(str(result['TrainingSetType']) + ',')
			f.write(str(result['Engine']) + ',')
			f.write(str(result['NumLayers']) + ',')
			f.write(str(result['NumParams']) + ',')
			f.write(str(result['NumMACs']) + ',')
			f.write(str(result['NumConvLayers']) + ',')
			f.write(str(result['NumFullyConnectedLayers']) + ',')
			f.write(str(result['Stride']) + ',')
			f.write(str(result['KernelSize']) + ',')
			f.write(str(result['Layers'][0]['ActivationFunction']) + ',')
			f.write(str(result['TestSetMse']) + ',')
			f.write(str(result['ArchetypalMse']) + ',')
			f.write(str(result['TestSetIsotopeValueMethodRocCorrectRate']) + ',')
			
			f.write(str(result['TestSetBackgroundRatioMethodRocCorrectRate']) + '\n')
	
	return True
	


		

		


if __name__ == '__main__':
	#n = NPU()
	#n.CreateSets('C:/Users/smurr/sync/Chips/teewinot/data/Histograms/A200F/Histograms-A200F-AFE0-2020-11-20-1218-10.json', ['Ba-133', 'Co-60', 'Cs-137', 'Mn-54', 'Na-22'])
	#n.Train('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44', 15, True, True, 0.5, 0.5, 1000, numTriesRandomGeneration=1000)
	#n.EvaluateTrainingData('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44', 0.05, 0.05)
	#n.GenerateMlpnnBinaryFile('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44')

	parser = argparse.ArgumentParser()

	# General arguments
	parser.add_argument(
		'config',
		type=str,
		help='Use configuration file config.json, located in the working directory, to set the parameters rather than command line arguments. Used in --createSets, --train, --evaluate, and --bin'
	)

	parser.add_argument(
		'--all',
		'-a',
		default=False,
		action='store_true',
		help='Run all functions: --createSets, --train, --evaluate, and --bin'
	)

	# Arguments for the "Create Sets" function
	parser.add_argument(
		'--createSets',
		'-s',
		default=False,
		action='store_true',
		help='Creates a training and test set from a histogram collection file. Required arguments: --histogramCollectionPath, --classificationIsotopes. Optional arguments: --whitelistedIsotopes, --blacklistedIsotopes, --desiredHistogramBits, --trainingToTestRatio'
	)

	parser.add_argument(
		'--createConfigs',
		default=False,
		action='store_true',
		help=''
	)

	parser.add_argument(
		'--createBetterConfigs',
		default=False,
		action='store_true',
		help=''
	)

	# Arguments for the "Train" function
	parser.add_argument(
		'--train',
		'-t',
		default=False,
		action='store_true',
		help='Trains the DNN using the training set created by --createSets.'
	)

	parser.add_argument(
		'--trainConfigs',
		default=False,
		action='store_true',
		help='Trains the DNN using the training set created by --createSets.'
	)

	# Arguments for the "Evaluate" function
	parser.add_argument(
		'--evaluate',
		'-e',
		default=False,
		action='store_true',
		help='Evaluates the DNN using the training data created by --train and the the training and test sets created by --createSets, and creates the receiver operating characteristic (ROC) for the DNN outputs.'
	)

	parser.add_argument(
		'--evaluateConfigs',
		default=False,
		action='store_true',
		help='Evaluates the DNN using the training data created by --train and the the training and test sets created by --createSets, and creates the receiver operating characteristic (ROC) for the DNN outputs.'
	)

	# Arguments for the "Generate Binary File" function
	parser.add_argument(
		'--bin',
		'-b',
		default=False,
		action='store_true',
		help='Creates the binary MLPNN.BIN file for the chip using the training data created in --train and the ROC data created in --evaluate.'
	)

	# Arguments for the "testConv" function
	parser.add_argument(
		'--testConv',
		default=False,
		action='store_true'
	)

	args = parser.parse_args()
	
	# Get the working directory
	if not os.path.isfile(args.config):
		print('config must be the path to a valid config.json file')
		parser.print_help()
		exit(-1)
	
	workingDirectory = os.path.dirname(args.config)

	# Initialize
	n = NPU()
	if not n.LoadConfigFromJson(args.config):
		print('config must be the path to a valid config.json file')
		parser.print_help()
		exit(-1)
	ret = False
	didSomething = False

	# Create sets function
	if args.createSets or args.all:
		# Does the working directory need to be created?
		ret = True
		
		# Create the training and test sets
		ret = n.CreateSets()
		
		if not ret:
			print('Error: Failed to create training and test sets while running --createSets')
			exit(-1)
		
		didSomething = True
	
	# Train function
	if args.train or args.all:
		ret = n.Train()
	
		if not ret:
			print('Error: Failed to train the MLPNN while running --train')
			exit(-1)
		
		didSomething = True
	
	# Evaluate function
	if args.evaluate or args.all:
		ret = n.EvaluateTrainingData()

		if not ret:
			print('Error: Failed to evaluate the training and test sets using the trained MLPNN data and to create the ROC data while running --evaluate')
			exit(-1)
		
		didSomething = True
	
	# Test function
	if args.testConv:
		n.testConv()
		didSomething = True
	
	# Create binary MLPNN.BIN file
	if args.bin or args.all:
		ret = n.GenerateMlpnnBinaryFile(args.workingDirectory)

		if not ret:
			print('Error: Failed to create the binary MLPNN.BIN file while running --bin')
			exit(-1)
		
		didSomething = True
	
	if args.createConfigs:
		ret = CreateNpuConfigs(args.config)

		if not ret:
			print('Error: Failed to create a sweep of configs with --createConfigs')
			exit(-1)
		didSomething = True
	
	if args.createBetterConfigs:
		ret = CreateBetterConfigs(args.config, 'Test0034')

		if not ret:
			print('Error: Failed to create a better sweep of configs with --createBetterConfigs')
			exit(-1)
		didSomething = True
	
	if args.trainConfigs:
		ret = TrainNpuConfigs(args.config)

		if not ret:
			print('Error: Failed to train the configs with --trainConfigs')
			exit(-1)
		didSomething = True
	
	if args.evaluateConfigs:
		ret = EvaluateNpuConfigs(args.config, reEvaluate=False)

		if not ret:
			print('Error: Failed to evaluate the configs with --evaluateConfigs')
			exit(-1)
		didSomething = True
	
	if not didSomething:
		print('Error: No command issued. Valid commands: --createSets, --train, --evaluate, --bin, and/or --all')
		exit(-1)

	# Completed successfully
	exit(0)
