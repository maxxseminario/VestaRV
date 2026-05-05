#!/usr/bin/env python3
import os, json, random, time, argparse
from shutil import copyfile
import numpy as np
from scipy.special import erf, erfinv

from Chip import Chip
from HistogramChannel import HistogramChannel, HistogramCollection
from HelperFunctions import *
from OptimizedMLPNN import OptimizedMLPNN

class NPU():
	WorkingDirectory = None

	def CreateWorkingDirectory(self, workingDirectory, histogramCollectionPath:str):
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
		if workingDirectory is not None:
			self.WorkingDirectory = workingDirectory
		else:
			self.WorkingDirectory = chip.DataDirectory + '/NPU/' + dieID + '/IsotopeID-' + get_string_timestamp(includeSeconds=True, dt=histogramCollection.Timestamp)
		if not os.path.isdir(self.WorkingDirectory):
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
		
		config['Type'] = 'NpuIsotopeIDConfig'
		config['histogramCollectionFileName'] = histogramFileName
		config['originalHistogramFilePath'] = histogramCollectionPath
		config['chipName'] = chip.Name
		config['dieID'] = dieID

		with open(configPath, 'w') as f:
			json.dump(config, f, indent='\t')
		
		return True

	
	def CreateSets(self, workingDirectory, classificationIsotopes:list, whitelistedIsotopes=None, blacklistedIsotopes=None, desiredHistogramBits=None, trainingToTestRatio=None):
		# Argument checking and default values
		if type(classificationIsotopes) != list:
			print('Invalid classificationIsotopes')
			return False
		if desiredHistogramBits is None:
			desiredHistogramBits = 6
		if type(desiredHistogramBits) != int or desiredHistogramBits < 2:
			print('Invalid desiredHistogramBits')
			return False
		if trainingToTestRatio is None:
			trainingToTestRatio = 1
		if (type(trainingToTestRatio) != float and type(trainingToTestRatio) != int) or trainingToTestRatio <= 0:
			print('Invalid trainingToTestRatio')
			return False
		
		# Load the config.json file to get the histogramCollectionFileName
		if workingDirectory is None:
			workingDirectory = self.WorkingDirectory
		configPath = workingDirectory + '/config.json'
		with open(configPath, 'r') as f:
			config = json.load(f)
		if type(config) != dict or 'Type' not in config or config['Type'] != 'NpuIsotopeIDConfig':
			print('Error reading config file at', configPath)
			return False

		# Check the histogram collection file
		histogramCollectionPath = workingDirectory + '/' + config['histogramCollectionFileName']
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
		if type(whitelistedIsotopes) == list:
			whitelistedIsotopes = [HistogramChannel.StandardizeIsotopeString(iso, allowUnknown=False) for iso in whitelistedIsotopes]
			if None in whitelistedIsotopes:
				print('An unknown isotope is in the whitelist, please remove it')
				return False
			for i in reversed(range(len(histogramCollection.Histograms))):
				h = histogramCollection.Histograms[i]
				for iso in h.MeasuredIsotopeAbundances:
					if iso == 'Background':
						continue
					if iso not in whitelistedIsotopes:
						histogramCollection.Histograms.pop(i)
						continue
		
		# Remove histograms with isotopes in the blacklist
		if type(blacklistedIsotopes) == list:
			blacklistedIsotopes = [HistogramChannel.StandardizeIsotopeString(iso, allowUnknown=False) for iso in blacklistedIsotopes]
			if None in blacklistedIsotopes:
				print('An unknown isotope is in the blacklist, please remove it')
				return False
			for i in reversed(range(len(histogramCollection.Histograms))):
				h = histogramCollection.Histograms[i]
				for iso in h.MeasuredIsotopeAbundances:
					if iso == 'Background':
						continue
					if iso not in blacklistedIsotopes:
						histogramCollection.Histograms.pop(i)
						continue
		
		# Are there any histograms left?
		if len(histogramCollection.Histograms) == 0:
			print('No histograms remaining after removing invalid or unwanted histograms')
			return False
		
		# Order the classification isotopes in alphabetical order
		classificationIsotopes = [HistogramChannel.StandardizeIsotopeString(s, allowUnknown=False) for s in classificationIsotopes]
		if None in classificationIsotopes:
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

		singleIsotopeCollections = [c for c in collections if (len(c.Histograms[0].MeasuredIsotopeAbundances) == 1) and (list(c.Histograms[0].MeasuredIsotopeAbundances.keys())[0] in classificationIsotopes)]
		multiIsotopeCollections = [c for c in collections if len(c.Histograms[0].MeasuredIsotopeAbundances) > 1]
		allCollections = [backgroundHistograms] + singleIsotopeCollections + multiIsotopeCollections

		# Sort the histograms in each collection by timestamp
		for collection in allCollections:
			collection.Histograms.sort(key=lambda h: h.Timestamp)
		
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

			m, b = np.linalg.lstsq(np.vstack([avTimeDelta * np.arange(1, len(collection.Histograms) + 1), np.ones(len(collection.Histograms))]).T, [h.TotalCounts for h in collection.Histograms], rcond=None)[0]
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
		trainingProportion = trainingToTestRatio / (1 + trainingToTestRatio)
		d = {'Type': 'TrainingSet', 'Timestamp': get_string_timestamp(includeSeconds=True, dt=histogramCollection.Timestamp), 'ChipName': config['chipName'], 'DieID': config['dieID'], 'AfeName': histogramCollection.Histograms[0].AfeName, 'ClassificationIsotopes': classificationIsotopes, 'TrainingSet': [], 'TestSet': []}
		for collection in allCollections:
			for i, h in enumerate(collection.Histograms):
				if (i / len(collection.Histograms)) >= trainingProportion:
					key = 'TestSet'
				else:
					key = 'TrainingSet'
				rebinnedHist = HistogramChannel.ReBinSimple(h.Counts, desiredHistogramBits=desiredHistogramBits)
				if rebinnedHist is None:
					print('Could not re-bin the histogram with desiredHistogramBits =', desiredHistogramBits)
					return False
				d[key].append({'Timestamp': get_string_timestamp(includeSeconds=True, dt=h.Timestamp), 'NormalizedCountsQ': HistogramChannel.GetNormalizedCountsForNPU(rebinnedHist), 'MeasuredIsotopeAbundances': h.MeasuredIsotopeAbundances, 'ExpectedIsotopeAbundances': h.ExpectedIsotopeAbundances})
		
		# Randomize the ordering of the training and test sets
		random.shuffle(d['TrainingSet'])
		random.shuffle(d['TestSet'])
		
		# Save the training set
		trainingSetJsonPath = self.WorkingDirectory + '/TrainingSet.json'
		with open(trainingSetJsonPath, 'w') as f:
			json.dump(d, f)
		
		print('Saved training set to', trainingSetJsonPath)

		# Save the configuration parameters to config.json
		config['classificationIsotopes'] = classificationIsotopes
		config['whitelistedIsotopes'] = whitelistedIsotopes
		config['blacklistedIsotopes'] = blacklistedIsotopes
		config['desiredHistogramBits'] = desiredHistogramBits
		config['trainingToTestRatio'] = trainingToTestRatio

		with open(configPath, 'w') as f:
			json.dump(config, f, indent='\t')

		return True
	


	def Train(self, workingDirectory, numHiddenNeurons:int, useHiddenBias:bool, useOutputBias:bool, learningGain:float, momentumGain:float, maxEpochs:int, averageMseTarget=None, maxAllowableIterationMse=None, numTriesRandomGeneration=None):
		# Argument checking and default values
		if type(numHiddenNeurons) != int or numHiddenNeurons <= 0:
			print('Invalid numHiddenNeurons')
			return False
		if type(useHiddenBias) != bool:
			print('Invalid useHiddenBias')
			return False
		if type(useOutputBias) != bool:
			print('Invalid useOutputBias')
			return False
		if type(learningGain) != float or not (0 < learningGain < 1):
			print('Invalid learningGain')
			return False
		if type(momentumGain) != float or not (0 < momentumGain < 1):
			print('Invalid momentumGain')
			return False
		if type(maxEpochs) != int or maxEpochs < 1:
			print('Invalid maxEpochs')
			return False
		if averageMseTarget is None:
			averageMseTarget = 0
		if (type(averageMseTarget) != float and type(averageMseTarget) != int):
			print('Invalid averageMseTarget')
			return False
		if maxAllowableIterationMse is None:
			maxAllowableIterationMse = 1.0
		if (type(maxAllowableIterationMse) != float and type(maxAllowableIterationMse) != int) or maxAllowableIterationMse <= 0:
			print('Invalid maxAllowableIterationMse')
			return False
		if numTriesRandomGeneration is None:
			numTriesRandomGeneration = 100
		if type(numTriesRandomGeneration) != int or numTriesRandomGeneration <= 0:
			print('Invalid numTriesRandomGeneration')
			return False

		# Load the training set
		if workingDirectory is None:
			workingDirectory = self.WorkingDirectory
		if not os.path.isdir(workingDirectory):
			print('Working directory does not exist')
			return False
		trainingSetJsonPath = workingDirectory + '/TrainingSet.json'
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
		numOutputNeurons = len(classificationIsotopes)
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i
		
		# Convert the training set to float-type vectors
		trainingSetDict = d['TrainingSet']
		trainingSetInputVectors = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T / 32768 for h in trainingSetDict], axis=1)
		trainingSetExpectedOutputVectors = []
		for h in trainingSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso == 'Background' or iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			trainingSetExpectedOutputVectors.append(v)
		trainingSetExpectedOutputVectors = np.concatenate(trainingSetExpectedOutputVectors, axis=1)
		
		# Extract the parameters for the MLPNN
		numInputNeurons = trainingSetInputVectors.shape[0]
		numOutputNeurons = trainingSetExpectedOutputVectors.shape[0]

		# Initialize the MLPNN
		t1 = time.time()
		print('Compiling MLPNN training software...')
		t = OptimizedMLPNN(numInputNeurons, numHiddenNeurons, numOutputNeurons, useHiddenBias, useOutputBias)

		# Initialize weights
		initialMse = t.GenerateRandomWeights(trainingSetInputVectors, trainingSetExpectedOutputVectors, numTriesRandomGeneration)
		print('Initial MSE:', initialMse)

		# Train
		t2 = time.time()
		print('Compiled in', t2 - t1, 'seconds')
		printStatus = False
		print('Training MLPNN...')
		t1 = time.time()
		mseAtEachEpoch, completedEpochs = t.Train(trainingSetInputVectors, trainingSetExpectedOutputVectors, maxEpochs, learningGain, momentumGain, averageMseTarget, maxAllowableIterationMse, printStatus)
		t2 = time.time()
		print('Trained MLPNN in', t2 - t1, 'seconds')
		print('End MSE is', t.MinMse, 'after', completedEpochs, 'epochs')
		print('Maximum iteration MSE in final epoch is', t.MaxIterationMse)

		# Collect data
		neuronsPerLayer = [t.NumInputNeurons, t.NumHiddenNeurons, t.NumOutputNeurons]
		useBiasPerLayer = [bool(t.HiddenBias), bool(t.OutputBias)]
		layerWeightsMatricesQ = [np.round(t.HiddenWeightsMatrixMinMse * 32768).astype(int).tolist(), np.round(t.OutputWeightsMatrixMinMse * 32768).astype(int).tolist()]

		# Check for out-of-bounds weights
		for i, weightsMatrix in enumerate(layerWeightsMatricesQ):
			if np.max(weightsMatrix) > 8388607:
				print('Weights matrix ', i, 'has at least one value that is greater than the Q8.15 upper limit')
				return False
			if np.max(weightsMatrix) < -8388608:
				print('Weights matrix ', i, 'has at least one value that is less than the Q8.15 lower limit')
				return False

		# Save the training data (including the weights)
		wd = {'Type': 'TrainingData', 'Timestamp': d['Timestamp'], 'ChipName': d['ChipName'], 'DieID': d['DieID'], 'AfeName': d['AfeName'], 'ClassificationIsotopes': d['ClassificationIsotopes'], 'NeuronsPerLayer': neuronsPerLayer, 'UseBiasPerLayer': useBiasPerLayer, 'TrainedMinMse': t.MinMse, 'EpochAtMinMse': t.EpochAtMinMse, 'LastEpochMaxIterationMse': t.MaxIterationMse, 'LayerWeightsMatricesQ': layerWeightsMatricesQ, 'MseAtEachEpoch': mseAtEachEpoch}

		trainingDataPath = workingDirectory + '/TrainingData.json'
		with open(trainingDataPath, 'w') as f:
			json.dump(wd, f)
		
		print('Saved training data to', trainingDataPath)

		# Save the configuration parameters to config.json
		configPath = workingDirectory + '/config.json'
		with open(configPath, 'r') as f:
			config = json.load(f)
		
		config['numHiddenNeurons'] = numHiddenNeurons
		config['useHiddenBias'] = useHiddenBias
		config['useOutputBias'] = useOutputBias
		config['learningGain'] = learningGain
		config['momentumGain'] = momentumGain
		config['maxEpochs'] = maxEpochs
		config['averageMseTarget'] = averageMseTarget
		config['maxAllowableIterationMse'] = maxAllowableIterationMse
		config['numTriesRandomGeneration'] = numTriesRandomGeneration

		with open(configPath, 'w') as f:
			json.dump(config, f, indent='\t')
		
		return True
	



	def EvaluateTrainingData(self, workingDirectory, desiredFalsePositiveRate:float, desiredFalseNegativeRate:float):
		# Argument checking and default values
		if type(desiredFalsePositiveRate) != float and not (0 < desiredFalsePositiveRate < 1):
			print('Invalid desiredFalsePositiveRate')
			return False
		if type(desiredFalseNegativeRate) != float and not (0 < desiredFalseNegativeRate < 1):
			print('Invalid desiredFalseNegativeRate')
			return False
		if workingDirectory is None:
			workingDirectory = self.WorkingDirectory
		
		# Open the training data
		trainingDataPath = workingDirectory + '/TrainingData.json'
		if not os.path.isfile(trainingDataPath):
			print('Training data does not exist at', trainingDataPath)
			return False
		
		with open(trainingDataPath, 'r') as f:
			trainingDataDict = json.load(f)
		
		if trainingDataDict is None or 'Type' not in trainingDataDict or trainingDataDict['Type'] != 'TrainingData':
			print('Invalid training data file at', trainingDataPath)
			return False
		
		neuronsPerLayer = trainingDataDict['NeuronsPerLayer']
		numLayers = len(neuronsPerLayer)
		useBiasPerLayer = trainingDataDict['UseBiasPerLayer']
		layerWeightsMatricesQ = [np.asarray(m) for m in trainingDataDict['LayerWeightsMatricesQ']]

		# Open the training and test sets
		trainingSetPath = workingDirectory + '/TrainingSet.json'
		if not os.path.isfile(trainingSetPath):
			print('Invalid training set file at', trainingSetPath)
			return False
		
		with open(trainingSetPath, 'r') as f:
			trainingAndTestSetDict = json.load(f)
		
		# Get the classification isotopes
		classificationIsotopes = trainingAndTestSetDict['ClassificationIsotopes']
		classificationIsotopeIndices = {}
		for i, iso in enumerate(classificationIsotopes):
			classificationIsotopeIndices[iso] = i
		
		# Convert the training set to float-type vectors
		trainingSetDict = trainingAndTestSetDict['TrainingSet']
		trainingSetInputVectorsQ = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in trainingSetDict], axis=1)
		trainingSetExpectedOutputVectors = []
		for h in trainingSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso == 'Background' or iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			trainingSetExpectedOutputVectors.append(v)
		trainingSetExpectedOutputVectors = np.concatenate(trainingSetExpectedOutputVectors, axis=1)

		# Convert the test set to float-type vectors
		testSetDict = trainingAndTestSetDict['TestSet']
		testSetInputVectorsQ = np.concatenate([np.asarray(h['NormalizedCountsQ'])[np.newaxis].T for h in testSetDict], axis=1)
		testSetExpectedOutputVectors = []
		for h in testSetDict:
			v = np.zeros((len(classificationIsotopes), 1))
			for iso in h['ExpectedIsotopeAbundances']:
				if iso == 'Background' or iso not in classificationIsotopeIndices:
					continue
				v[classificationIsotopeIndices[iso], 0] = h['ExpectedIsotopeAbundances'][iso]
			testSetExpectedOutputVectors.append(v)
		testSetExpectedOutputVectors = np.concatenate(testSetExpectedOutputVectors, axis=1)

		# Compute the outputs to the training and test sets
		trainingSetEstimatedOutputVectorsQ = self.feedforwardQ(useBiasPerLayer, trainingSetInputVectorsQ, layerWeightsMatricesQ)
		testSetEstimatedOutputVectorsQ = self.feedforwardQ(useBiasPerLayer, testSetInputVectorsQ, layerWeightsMatricesQ)

		# Compute the error
		trainingSetErrorVectors = trainingSetExpectedOutputVectors - (trainingSetEstimatedOutputVectorsQ / 32768)
		testSetErrorVectors = testSetExpectedOutputVectors - (testSetEstimatedOutputVectorsQ / 32768)

		# Compute the MSE per output
		trainingSetMses = np.sum(trainingSetErrorVectors**2, axis=0) / trainingSetErrorVectors.shape[0]
		testSetMses = np.sum(testSetErrorVectors**2, axis=0) / testSetErrorVectors.shape[0]

		# Compute the total MSEs for the training and test sets
		trainingSetMse = np.sum(trainingSetMses) / len(trainingSetMses)
		testSetMse = np.sum(testSetMses) / len(testSetMses)

		# Create the Receiver Operating Characteristic (ROC) for each isotope
		tsd = trainingAndTestSetDict['TestSet']
		for h in tsd:
			h['RocResults'] = {}
		ROC = {}
		rocCorrect = [1 for i in range(len(tsd))]
		for isoindex, iso in enumerate(classificationIsotopes):
			# Collect the estimated output of each isotope in each test set histogram and sort by if the isotope was present or not
			outputsWithIso = []
			outputsWithoutIso = []
			for col, h in enumerate(tsd):
				h['RocResults'] = {}
				if iso in h['ExpectedIsotopeAbundances']:
					outputsWithIso.append(testSetEstimatedOutputVectorsQ[isoindex, col])
					#outputsWithIso.append(h['EstimatedIsotopeAbundancesQ'][iso])
				else:
					outputsWithoutIso.append(testSetEstimatedOutputVectorsQ[isoindex, col])
					#outputsWithoutIso.append(h['EstimatedIsotopeAbundancesQ'][iso])
			
			# Calculate the Gaussian normal distribution
			withIsoMean = np.mean(outputsWithIso)
			withIsoStdDev = np.std(outputsWithIso)
			withoutIsoMean = np.mean(outputsWithoutIso)
			withoutIsoStdDev = np.std(outputsWithoutIso)
			
			# Calculate the ROC threshold for the isotope
			minWith = min(outputsWithIso)
			maxWithout = max(outputsWithoutIso)
			if minWith > maxWithout:
				# A first attempt at getting the threshold
				thresholdQ = int(round((maxWithout + minWith) / 2))
			else:
				# Calculate the threshold (x) beneath which will produce the desired false positive rate
				# This is based on the CDF of a Gaussian normal distribution: phi(x) = (1/2) * (1 + erf((x - u) / (sigma * sqrt(2))))
				# where x is the threshold, phi(x) is the probability that the threshold x will produce a false positive, u is the mean, and sigma is the standard deviation
				# Rearranging the equation to extract the threshold x gives: x = sigma * sqrt(2) * erfinv(2*phi - 1) + u
				# Note that the outputsWithIso will yield the false positive rate
				threshFalsePos = withIsoStdDev * np.sqrt(2) * erfinv(2 * desiredFalsePositiveRate - 1) + withIsoMean

				# Calculate the threshold (x) which will produce the desired true negative rate
				# Note that the outputsWithIso will yield the true negative rate
				threshTrueNeg = withoutIsoStdDev * np.sqrt(2) * erfinv(2 * (1 - desiredFalseNegativeRate) - 1) + withoutIsoMean

				if threshFalsePos > threshTrueNeg and threshFalsePos > 0 and threshTrueNeg > 0:
					# A second attempt at getting the threshold
					# Since the true positives and true negatives have well defined groups that are separated from each other and in the correct order, simply split the gap between the two thresholds to optimize them both at once
					thresholdQ = int(round((threshFalsePos + threshTrueNeg) / 2))
				elif threshFalsePos > 0:
					# A third attempt at getting the threshold
					# The true positives and true negatives overlap. In this case, we prefer not to generate false positives, so choose the threshold that generates the desired false positive rate 
					thresholdQ = int(round(threshFalsePos))
				elif threshTrueNeg > 0:
					# A fourth attempt at getting the threshold
					# The false positive rate is negative, so try useing the true negative rate instead
					thresholdQ = int(round(threshTrueNeg))
				else:
					# The fifth and last attempt at getting the threshold
					# Both the desired false positive and false negative rates are unattainable, so set the threshold to 1 plus the max of the "without" values to reduce the chance of a false positive
					thresholdQ = 1 + int(maxWithout)
			
			# Calculate the statistics for the chosen threshold
			falsePositiveRate = 0.5 * (1 + erf((thresholdQ - withIsoMean) / (withIsoStdDev * np.sqrt(2))))
			truePositiveRate = 1 - falsePositiveRate
			trueNegativeRate = 0.5 * (1 + erf((thresholdQ - withoutIsoMean) / (withoutIsoStdDev * np.sqrt(2))))
			falseNegativeRate = 1 - trueNegativeRate

			truePosCount = 0
			falsePosCount = 0
			trueNegCount = 0
			falseNegCount = 0
			for col, h in enumerate(tsd):
				if iso in h['MeasuredIsotopeAbundances']:
					if testSetEstimatedOutputVectorsQ[isoindex, col] >= thresholdQ:
						truePosCount += 1
						h['RocResults'][iso] = {'Present': True, 'Correct': True}
					else:
						falseNegCount += 1
						h['RocResults'][iso] = {'Present': False, 'Correct': False}
						rocCorrect[col] = 0
				else:
					if testSetEstimatedOutputVectorsQ[isoindex, col] >= thresholdQ:
						falsePosCount += 1
						h['RocResults'][iso] = {'Present': True, 'Correct': False}
						rocCorrect[col] = 0
					else:
						trueNegCount += 1
						h['RocResults'][iso] = {'Present': False, 'Correct': True}
			
			testSetTruePositiveRate = 0.0
			if (truePosCount + falseNegCount) > 0:
				testSetTruePositiveRate = truePosCount / (truePosCount + falseNegCount)
			testSetFalseNegativeRate = 1 - testSetTruePositiveRate
			
			testSetTrueNegativeRate = 0.0
			if (trueNegCount + falsePosCount) > 0:
				testSetTrueNegativeRate = trueNegCount / (trueNegCount + falsePosCount)
			testSetFalsePositiveRate = 1 - testSetTrueNegativeRate

			testSetRocCorrectRate = 0.0
			if len(rocCorrect) > 0:
				testSetRocCorrectRate = sum(rocCorrect) / len(rocCorrect)

			ROC[iso] = {'ThresholdQ': thresholdQ, 'EstimatedTruePositiveRate': truePositiveRate, 'EstimatedFalsePositiveRate': falsePositiveRate, 'EstimatedTrueNegativeRate': trueNegativeRate, 'EstimatedFalseNegativeRate': falseNegativeRate, 'TestSetTruePositiveRate': testSetTruePositiveRate, 'TestSetFalsePositiveRate': testSetFalsePositiveRate, 'TestSetTrueNegativeRate': testSetTrueNegativeRate, 'TestSetFalseNegativeRate': testSetFalseNegativeRate}

		# Create the output dictionary
		d = trainingAndTestSetDict
		d['Type'] = 'TrainingEvaluation'
		d['TrainingSetMse'] = trainingSetMse
		d['TestSetMse'] = testSetMse
		d['ROC'] = ROC
		d['TestSetRocCorrectRate'] = testSetRocCorrectRate

		trd = d['TrainingSet']
		for col in range(trainingSetInputVectorsQ.shape[1]):
			# Save the data for each training set vector
			estQ = {}
			for i, iso in enumerate(classificationIsotopes):
				estQ[iso] = int(trainingSetEstimatedOutputVectorsQ[i, col])
			#trdc = 
			trd[col]['EstimatedIsotopeAbundancesQ'] = estQ
			trd[col]['MSE'] = trainingSetMses[col]
		
		tsd = d['TestSet']
		for col in range(testSetInputVectorsQ.shape[1]):
			# Save the data for each training set vector
			estQ = {}
			for i, iso in enumerate(classificationIsotopes):
				estQ[iso] = int(testSetEstimatedOutputVectorsQ[i, col])
			#trdc = 
			tsd[col]['EstimatedIsotopeAbundancesQ'] = estQ
			tsd[col]['MSE'] = trainingSetMses[col]
		
		# Save the evaluation data
		trainingEvaluationPath = workingDirectory + '/TrainingEvaluation.json'
		with open(trainingEvaluationPath, 'w') as f:
			json.dump(d, f)
		
		# Print
		print('Training set MSE:', trainingSetMse)
		print('Test set MSE:    ', testSetMse)
		print('ROC Correct Rate:', 100 * testSetRocCorrectRate, '%')
		print('Saved training evaluation data to', trainingEvaluationPath)

		# Save the configuration parameters to config.json
		configPath = workingDirectory + '/config.json'
		with open(configPath, 'r') as f:
			config = json.load(f)
		
		config['desiredFalsePositiveRate'] = desiredFalsePositiveRate
		config['desiredFalseNegativeRate'] = desiredFalseNegativeRate

		with open(configPath, 'w') as f:
			json.dump(config, f, indent='\t')
		
		# Save a results summary file
		resultsPath = workingDirectory + '/results-summary.txt'

		results = [
			'Timestamp: ' + d['Timestamp'],
			'Chip name: ' + d['ChipName'],
			'Die ID: ' + d['DieID'],
			'AFE name: ' + d['AfeName'],
			'Classification isotopes: ' + str(classificationIsotopes),
			'Training set MSE: ' + '{:.3e}'.format(trainingSetMse),
			'Test set MSE:     ' + '{:.3e}'.format(testSetMse),
			'ROC correct classification rate: ' + '{:.1f}%'.format(100 * testSetRocCorrectRate),
		]

		with open(resultsPath, 'w') as f:
			f.write('\n'.join(results) + '\n')
		
		print('Saved results summary file data to', resultsPath)

		return True
	


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



		

		


if __name__ == '__main__':
	#n = NPU()
	#n.CreateSets('C:/Users/smurr/sync/Chips/teewinot/data/Histograms/A200F/Histograms-A200F-AFE0-2020-11-20-1218-10.json', ['Ba-133', 'Co-60', 'Cs-137', 'Mn-54', 'Na-22'])
	#n.Train('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44', 15, True, True, 0.5, 0.5, 1000, numTriesRandomGeneration=1000)
	#n.EvaluateTrainingData('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44', 0.05, 0.05)
	#n.GenerateMlpnnBinaryFile('C:/Users/smurr/sync/Chips/teewinot/data/NPU/A200F/IsotopeID-2020-11-20-1300-44')

	parser = argparse.ArgumentParser()

	# General arguments
	parser.add_argument(
		'--useConfig',
		'-c',
		default=False,
		action='store_true',
		help='Use configuration file config.json, located in the working directory, to set the parameters rather than command line arguments. Used in --createSets, --train, --evaluate, and --bin'
	)

	parser.add_argument(
		'--workingDirectory',
		'-w',
		default=None,
		nargs=1,
		type=str,
		help='The path to the working directory. Used in --train, --evaluate, and --bin, and optionally in --createSets'
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
		'--histogramCollectionPath',
		default=None,
		nargs=1,
		type=str,
		help='The path to the histogram collection used in --createSets'
	)

	parser.add_argument(
		'--classificationIsotopes',
		default=None,
		nargs=1,
		type=str,
		help='A string containing a list of all the isotopes you wish the NPU to classify. Only used in --createSets'
	)

	parser.add_argument(
		'--whitelistedIsotopes',
		default=None,
		nargs=1,
		type=str,
		help='A string containing a list of all the isotopes that will be included in the training and test sets. Any histograms with other isotopes will not be included in the training and test sets. Only used in --createSets'
	)

	parser.add_argument(
		'--blacklistedIsotopes',
		default=None,
		nargs=1,
		type=str,
		help='A string containing a list of any isotopes that will not be included in the training and test sets. Any histogram with any of these isotopes will not be included in the training and test sets. Only used in --createSets'
	)

	parser.add_argument(
		'--desiredHistogramBits',
		default=None,
		nargs=1,
		type=int,
		help='The number of effective ADC bits used in the training and test sets after rebinning. The number of bins in training and test set histograms is thus 2^desiredHistogramBits. Only used in --createSets'
	)

	parser.add_argument(
		'--trainingToTestRatio',
		default=None,
		nargs=1,
		type=float,
		help='The ratio of training set histograms to test set histograms. Only used in --createSets'
	)

	# Arguments for the "Train" function
	parser.add_argument(
		'--train',
		'-t',
		default=False,
		action='store_true',
		help='Trains the MLPNN using the training set created by --createSets. Required arguments: [--workingDirectory or --config], --numHiddenNeurons, --useHiddenBias, --useOutputBias, --learningGain, --momentumGain, --maxEpochs. Optional arguments: --averageMseTarget, --maxAllowableIteratoinMse, --numTriesRandomGeneration'
	)

	parser.add_argument(
		'--numHiddenNeurons',
		default=None,
		nargs=1,
		type=int,
		help='The number of hidden neurons in the MLPNN. Only used in --train'
	)

	parser.add_argument(
		'--useHiddenBias',
		default=False,
		action='store_true',
		help='Use hidden layer bias in the MLPNN. Only used in --train'
	)

	parser.add_argument(
		'--useOutputBias',
		default=False,
		action='store_true',
		help='Use hidden layer bias in the MLPNN. Only used in --train'
	)

	parser.add_argument(
		'--learningGain',
		default=None,
		nargs=1,
		type=float,
		help='The MLPNN training learning gain, must be on the range of (0, 1). Only used in --train'
	)

	parser.add_argument(
		'--momentumGain',
		default=None,
		nargs=1,
		type=float,
		help='The MLPNN training momentum gain, must be on the range of (0, 1). Only used in --train'
	)

	parser.add_argument(
		'--maxEpochs',
		default=None,
		nargs=1,
		type=int,
		help='The maximum number of epochs to run while training the MLPNN. Only used in --train'
	)

	parser.add_argument(
		'--averageMseTarget',
		default=None,
		nargs=1,
		type=float,
		help='The desired epoch MSE target. Training is completed early when this MSE is reached. Only used in --train'
	)

	parser.add_argument(
		'--maxAllowableIterationMse',
		default=None,
		nargs=1,
		type=float,
		help='The maximum allowable MSE in a single output vector in an epoch while training. Only used in --train'
	)

	parser.add_argument(
		'--numTriesRandomGeneration',
		default=None,
		nargs=1,
		type=int,
		help='The maximum number of times to randomly generate weights, seeking the lowest initial MSE. Only used in --train'
	)

	# Arguments for the "Evaluate" function
	parser.add_argument(
		'--evaluate',
		'-e',
		default=False,
		action='store_true',
		help='Evaluates the MLPNN using the training data created by --train and the the training and test sets created by --createSets, and creates the receiver operating characteristic (ROC) for the MLPNN outputs. Required arguments: [--workingDirectory or --config], --desiredFalsePositiveRate, --desiredFalseNegativeRate'
	)

	parser.add_argument(
		'--desiredFalsePositiveRate',
		default=None,
		nargs=1,
		type=float,
		help='The desired false positive rate for the MLPNN output ROC, must be on the range of (0, 1). Only used in --evaluate'
	)

	parser.add_argument(
		'--desiredFalseNegativeRate',
		default=None,
		nargs=1,
		type=float,
		help='The desired false negative rate for the MLPNN output ROC, must be on the range of (0, 1). Only used in --evaluate'
	)

	# Arguments for the "Generate Binary File" function
	parser.add_argument(
		'--bin',
		'-b',
		default=False,
		action='store_true',
		help='Creates the binary MLPNN.BIN file for the chip using the training data created in --train and the ROC data created in --evaluate. Required arguments: --workingDirectory'
	)

	args = parser.parse_args()

	# Parse optional arguments, changing them from lists to values
	if args.workingDirectory is not None:
		args.workingDirectory = args.workingDirectory[0]
	
	if args.histogramCollectionPath is not None:
		args.histogramCollectionPath = args.histogramCollectionPath[0]

	if args.classificationIsotopes is not None:
		args.classificationIsotopes = args.classificationIsotopes[0]
		args.classificationIsotopes = args.classificationIsotopes.replace(',', ' ')
		while '  ' in args.classificationIsotopes:
			args.classificationIsotopes = args.classificationIsotopes.replace('  ', ' ')
		args.classificationIsotopes = [iso for iso in args.classificationIsotopes.split(' ')]

	if args.whitelistedIsotopes is not None:
		args.whitelistedIsotopes = args.whitelistedIsotopes[0]
		args.whitelistedIsotopes = args.whitelistedIsotopes.replace(',', ' ')
		while '  ' in args.whitelistedIsotopes:
			args.whitelistedIsotopes = args.whitelistedIsotopes.replace('  ', ' ')
		args.whitelistedIsotopes = [iso for iso in args.whitelistedIsotopes.split(' ')]

	if args.blacklistedIsotopes is not None:
		args.blacklistedIsotopes = args.blacklistedIsotopes[0]
		args.blacklistedIsotopes = args.blacklistedIsotopes.replace(',', ' ')
		while '  ' in args.blacklistedIsotopes:
			args.blacklistedIsotopes = args.blacklistedIsotopes.replace('  ', ' ')
		args.blacklistedIsotopes = [iso for iso in args.blacklistedIsotopes.split(' ')]

	if args.desiredHistogramBits is not None:
		args.desiredHistogramBits = args.desiredHistogramBits[0]

	if args.trainingToTestRatio is not None:
		args.trainingToTestRatio = args.trainingToTestRatio[0]

	if args.numHiddenNeurons is not None:
		args.numHiddenNeurons = args.numHiddenNeurons[0]

	if args.learningGain is not None:
		args.learningGain = args.learningGain[0]

	if args.momentumGain is not None:
		args.momentumGain = args.momentumGain[0]
	
	if args.maxEpochs is not None:
		args.maxEpochs = args.maxEpochs[0]

	if args.numTriesRandomGeneration is not None:
		args.numTriesRandomGeneration = args.numTriesRandomGeneration[0]

	if args.desiredFalsePositiveRate is not None:
		args.desiredFalsePositiveRate = args.desiredFalsePositiveRate[0]

	if args.desiredFalseNegativeRate is not None:
		args.desiredFalseNegativeRate = args.desiredFalseNegativeRate[0]
	
	# If the --config switch was given, load the config file
	config = {}
	if args.useConfig:
		if not os.path.isdir(args.workingDirectory):
			print('Error: When --config is given,  --workingDirectory must be given with a valid path to the desired working directory.')
			exit(-1)
		
		configPath = args.workingDirectory + '/config.json'
		if not os.path.isfile(configPath):
			print('Error: When --config is given, then the file config.json must exist in the directory given with --workingDirectory')
			exit(-1)
		
		with open(configPath, 'r') as f:
			config = json.load(f)
		
		if type(config) != dict or 'Type' not in config or config['Type'] != 'NpuIsotopeIDConfig':
			print('Error: The path given with --config is not a valid config.json path')
			exit(-1)
		
		if 'classificationIsotopes' in config:
			args.classificationIsotopes = config['classificationIsotopes']
		
		if 'whitelistedIsotopes' in config:
			args.whitelistedIsotopes = config['whitelistedIsotopes']
		
		if 'blacklistedIsotopes' in config:
			args.blacklistedIsotopes = config['blacklistedIsotopes']
		
		if 'desiredHistogramBits' in config:
			args.desiredHistogramBits = config['desiredHistogramBits']
		
		if 'trainingToTestRatio' in config:
			args.trainingToTestRatio = config['trainingToTestRatio']
		
		if 'numHiddenNeurons' in config:
			args.numHiddenNeurons = config['numHiddenNeurons']
		
		if 'useHiddenBias' in config:
			args.useHiddenBias = config['useHiddenBias']
		
		if 'useOutputBias' in config:
			args.useOutputBias = config['useOutputBias']
		
		if 'learningGain' in config:
			args.learningGain = config['learningGain']
		
		if 'momentumGain' in config:
			args.momentumGain = config['momentumGain']
		
		if 'maxEpochs' in config:
			args.maxEpochs = config['maxEpochs']
		
		if 'averageMseTarget' in config:
			args.averageMseTarget = config['averageMseTarget']
		
		if 'maxAllowableIterationMse' in config:
			args.maxAllowableIterationMse = config['maxAllowableIterationMse']
		
		if 'numTriesRandomGeneration' in config:
			args.numTriesRandomGeneration = config['numTriesRandomGeneration']
		
		if 'desiredFalsePositiveRate' in config:
			args.desiredFalsePositiveRate = config['desiredFalsePositiveRate']
		
		if 'desiredFalseNegativeRate' in config:
			args.desiredFalseNegativeRate = config['desiredFalseNegativeRate']

	# Initialize
	n = NPU()
	ret = False
	didSomething = False

	# Create sets function
	if args.createSets or args.all:
		# Does the working directory need to be created?
		ret = True
		if args.workingDirectory is None or (not os.path.isdir(args.workingDirectory)):
			# Working directory does not yet exist
			if args.histogramCollectionPath is None:
				print('Error: Must provide either --workingDirectory or --histogramCollection path when running --createSets')
				exit(-1)
			else:
				ret = n.CreateWorkingDirectory(workingDirectory=None, histogramCollectionPath=args.histogramCollectionPath)
				args.workingDirectory = n.WorkingDirectory
		else:
			# Working directory exists
			if args.histogramCollectionPath is not None:
				# A new histogram collection path is specified, re-create the working directory, copy over the new histogram collection file, and adjust the config.json file
				ret = n.CreateWorkingDirectory(workingDirectory=args.workingDirectory, histogramCollectionPath=args.histogramCollectionPath)
		
		if not ret:
			print('Error: Failed to create working directory with the desired histogram collection file when running --createSets')
			exit(-1)
		
		# Create the training and test sets
		ret = n.CreateSets(args.workingDirectory, args.classificationIsotopes, whitelistedIsotopes=args.whitelistedIsotopes, blacklistedIsotopes=args.blacklistedIsotopes, desiredHistogramBits=args.desiredHistogramBits, trainingToTestRatio=args.trainingToTestRatio)
		
		if not ret:
			print('Error: Failed to create training and test sets while running --createSets')
			exit(-1)
		
		didSomething = True
		
	# Train function
	if args.train or args.all:
		ret = n.Train(workingDirectory=args.workingDirectory, numHiddenNeurons=args.numHiddenNeurons, useHiddenBias=args.useHiddenBias, useOutputBias=args.useOutputBias, learningGain=args.learningGain, momentumGain=args.momentumGain, maxEpochs=args.maxEpochs, averageMseTarget=args.averageMseTarget, maxAllowableIterationMse=args.maxAllowableIterationMse, numTriesRandomGeneration=args.numTriesRandomGeneration)
	
		if not ret:
			print('Error: Failed to train the MLPNN while running --train')
			exit(-1)
		
		didSomething = True
	
	# Evaluate function
	if args.evaluate or args.all:
		ret = n.EvaluateTrainingData(workingDirectory=args.workingDirectory, desiredFalsePositiveRate=args.desiredFalsePositiveRate, desiredFalseNegativeRate=args.desiredFalseNegativeRate)

		if not ret:
			print('Error: Failed to evaluate the training and test sets using the trained MLPNN data and to create the ROC data while running --evaluate')
			exit(-1)
		
		didSomething = True
	
	# Create binary MLPNN.BIN file
	if args.bin or args.all:
		ret = n.GenerateMlpnnBinaryFile(args.workingDirectory)

		if not ret:
			print('Error: Failed to create the binary MLPNN.BIN file while running --bin')
			exit(-1)
		
		didSomething = True
	
	if not didSomething:
		print('Error: No command issued. Valid commands: --createSets, --train, --evaluate, --bin, and/or --all')
		exit(-1)

	# Completed successfully
	exit(0)
