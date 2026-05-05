import numpy as np	# package numpy (install with pip install numpy)
from collections import OrderedDict
from numba import jit, int32, float64	# package numba (install with pip install numba)
from numba.experimental import jitclass

@jit(nopython=True)
def ActivationFunction(a, out):
	rows, cols = a.shape
	for row in range(rows):
		for col in range(cols):
			if a[row, col] > 4:
				out[row, col] = 4
			elif a[row, col] < -4:
				out[row, col] = -4
			else:
				out[row, col] = a[row, col]
	out[:,:] = -0.03125 * np.sign(out) * out**2 + 0.25 * out + 0.5
	return

@jit(nopython=True)
def ActivationFunctionDerivative(a, out):
	rows, cols = a.shape
	for row in range(rows):
		for col in range(cols):
			if a[row, col] > 4:
				out[row, col] = 4
			elif a[row, col] < -4:
				out[row, col] = -4
			else:
				out[row, col] = a[row, col]
	out[:,:] = -0.0625 * np.sign(out) * out + 0.25
	return

@jit(nopython=True)
def LogisticSigmoid(a, out):
	out[:,:] = 1.0 / (1.0 + np.exp(-a))
	return

@jit(nopython=True)
def LogisticSigmoidDerivative(a, out):
	out[:,:] = a * (1.0 - a)
	return

@jit(nopython=True)
def HyperbolicTangent(a, out):
	out[:,:] = np.tanh(a)
	return
	
@jit(nopython=True)
def HyperbolicTangentDerivative(a, out):
	out[:,:] = 1.0 - (a * a)
	return

OptimizedMLPNNSpec = OrderedDict()

OptimizedMLPNNSpec['NumInputNeurons'] = int32
OptimizedMLPNNSpec['NumHiddenNeurons'] = int32
OptimizedMLPNNSpec['NumOutputNeurons'] = int32

OptimizedMLPNNSpec['HiddenBias'] = int32	# 1 if there is a hidden bias term, 0 if not
OptimizedMLPNNSpec['OutputBias'] = int32	# 1 if there is an output bias term, 0 if not

OptimizedMLPNNSpec['HiddenWeightsMatrix'] = float64[:,:]	# The matrix W, size = (NumHiddenNeurons, NumInputNeurons + HiddenBias)
OptimizedMLPNNSpec['OutputWeightsMatrix'] = float64[:,:]	# The matrix V, size = (NumOutputNeurons, NumHiddenNeurons + OutputBias)

OptimizedMLPNNSpec['InputVectors'] = float64[:,:]	# The vector(s) x, size = (NumInputNeurons, NumInputVectors)
OptimizedMLPNNSpec['HiddenActivationVectors'] = float64[:,:]	# The vector(s) a_h, size = (NumHiddenNeurons, NumInputVectors)
OptimizedMLPNNSpec['HiddenDecisionVectors'] = float64[:,:]	# The vector(s) d_h, size = (NumHiddenNeurons + HiddenBias, NumInputVectors)
OptimizedMLPNNSpec['OutputActivationVectors'] = float64[:,:]	# The vector(s) a_o, size = (NumOutputNeurons, NumInputVectors)
OptimizedMLPNNSpec['OutputDecisionVectors'] = float64[:,:]	# The vector(s) d_o, or simply y_hat, size = (NumOutputNeurons, NumInputVectors)

OptimizedMLPNNSpec['MinMse'] = float64	# The minimum MSE from the training algorithm
OptimizedMLPNNSpec['EpochAtMinMse'] = int32	# The epoch number that provided the minimum MSE
OptimizedMLPNNSpec['MseAtEachEpoch'] = float64[:]	# An array with the MSE from each epoch
OptimizedMLPNNSpec['MaxIterationMse'] = float64	# The maximum MSE in the current iteration

OptimizedMLPNNSpec['HiddenWeightsMatrixMinMse'] = float64[:,:]	# The hidden weights matrix with the minimum MSE from the training algorithm
OptimizedMLPNNSpec['OutputWeightsMatrixMinMse'] = float64[:,:]	# The output weights matrix with the minimum MSE from the training algorithm

@jitclass(OptimizedMLPNNSpec)
class OptimizedMLPNN():
	def __init__(self, numInputNeurons:int, numHiddenNeurons:int, numOutputNeurons:int, useHiddenBias:bool, useOutputBias:bool):
		self.Initialize(numInputNeurons, numHiddenNeurons, numOutputNeurons, useHiddenBias, useOutputBias)
		return
	
	def Initialize(self, numInputNeurons:int, numHiddenNeurons:int, numOutputNeurons:int, useHiddenBias:bool, useOutputBias:bool):
		# Error checking
		if numInputNeurons <= 0:
			raise Exception('numInputNeurons must be > 0')
		if numHiddenNeurons <= 0:
			raise Exception('numHiddenNeurons must be > 0')
		if numOutputNeurons <= 0:
			raise Exception('numOutputNeurons must be > 0')
		
		# Set internal data
		self.NumInputNeurons = numInputNeurons
		self.NumHiddenNeurons = numHiddenNeurons
		self.NumOutputNeurons = numOutputNeurons
		
		self.HiddenBias = 0
		if useHiddenBias:
			self.HiddenBias = 1
		
		self.OutputBias = 0
		if useOutputBias:
			self.OutputBias = 1
		
		# Randomize the initial weights matrices
		self.HiddenWeightsMatrix = 1 - (2 * np.random.rand(self.NumHiddenNeurons, self.NumInputNeurons + self.HiddenBias))
		self.OutputWeightsMatrix = 1 - (2 * np.random.rand(self.NumOutputNeurons, self.NumHiddenNeurons + self.OutputBias))
	
	def SetHiddenWeightsMatrix(self, W:np.ndarray):
		self.HiddenWeightsMatrix[:,:] = W[:,:]
		return
	
	def SetOutputWeightsMatrix(self, V:np.ndarray):
		self.OutputWeightsMatrix[:,:] = V[:,:]
		return
	
	def SetInputVectors(self, X:np.ndarray):
		dimensions = X.shape
		if len(dimensions) != 2:
			raise Exception('X must be a matrix of dimension 2')
		if dimensions[0] != self.NumInputNeurons:
			raise Exception('X must have NumInputNeurons number of rows')
		
		numInputVectors = dimensions[1]
		
		if self.HiddenBias:
			self.InputVectors = np.concatenate((X, np.ones((1, numInputVectors))), axis=0)
		else:
			self.InputVectors = X.copy()
		
		# Set up the sizes of the other vectors
		self.HiddenActivationVectors = np.zeros((self.NumHiddenNeurons + 0, numInputVectors))
		self.HiddenDecisionVectors = np.ones((self.NumHiddenNeurons + self.OutputBias, numInputVectors))
		self.OutputActivationVectors = np.zeros((self.NumOutputNeurons + 0, numInputVectors))
		self.OutputDecisionVectors = np.zeros((self.NumOutputNeurons + 0, numInputVectors))
		
		return
	
	def Feedforward(self, X=None):
		if X is not None:
			self.SetInputVectors(X)
		
		# Calculate the hidden activation vectors
		# a_h = W * x
		self.HiddenActivationVectors = self.HiddenWeightsMatrix.dot(self.InputVectors)
		
		# Calculate the hidden decision vectors, accounting for the output bias
		# d_h = f_a(a_h)
		if self.OutputBias:
			ActivationFunction(self.HiddenActivationVectors, self.HiddenDecisionVectors[0:self.NumHiddenNeurons, :])
		else:
			ActivationFunction(self.HiddenActivationVectors, self.HiddenDecisionVectors)
		
		# Calculate the output activation vectors
		# a_o = V * d_h
		self.OutputActivationVectors = self.OutputWeightsMatrix.dot(self.HiddenDecisionVectors)
		
		# Calculate the estimated output vectors, or the output decision vectors
		# y_hat = d_o = f_a(a_o)
		ActivationFunction(self.OutputActivationVectors, self.OutputDecisionVectors)
		
		return
	
	def GenerateRandomWeights(self, trainingSetInputVectors:np.ndarray, trainingSetExpectedOutputVectors:np.ndarray, maxTries:int):
		# Error checking
		numInputNeurons, numInputVectors = trainingSetInputVectors.shape
		numOutputNeurons, numOutputVectors = trainingSetExpectedOutputVectors.shape
		
		if numInputNeurons != self.NumInputNeurons:
			raise Exception('The number of input neurons does not match the number of rows in trainingSetInputVectors')
		if numOutputNeurons != self.NumOutputNeurons:
			raise Exception('The number of output neurons does not match the number of rows in trainingSetExpectedOutputVectors')
		if numInputVectors != numOutputVectors:
			raise Exception('The number of vectors in trainingSetInputVectors does not match the number of vectors in trainingSetExpectedOutputVectors')
		if numInputNeurons <= 0:
			raise Exception('Training set is empty')
		if maxTries <= 0:
			raise Exception('maxTries must be > 0')
		
		# Initialize the vectors and matrices
		self.SetInputVectors(trainingSetInputVectors)	# This initializes the feedforward vectors
		
		mse = -1.0
		minMse = np.inf
		
		hiddenWeightsMatrixBest = self.HiddenWeightsMatrix[:,:]
		outputWeightsMatrixBest = self.OutputWeightsMatrix[:,:]
		
		for i in range(maxTries):
			# Randomize the initial weights matrices
			self.HiddenWeightsMatrix = 1 - (2 * np.random.rand(self.NumHiddenNeurons, self.NumInputNeurons + self.HiddenBias))
			self.OutputWeightsMatrix = 1 - (2 * np.random.rand(self.NumOutputNeurons, self.NumHiddenNeurons + self.OutputBias))
			
			# Feedforward
			self.Feedforward()
			
			# Calculate MSE
			errorVectors = trainingSetExpectedOutputVectors - self.OutputDecisionVectors
			mse = np.sum((errorVectors**2)) / errorVectors.size
			
			if mse < minMse:
				minMse = mse
				hiddenWeightsMatrixBest[:,:] = self.HiddenWeightsMatrix[:,:]
				outputWeightsMatrixBest[:,:] = self.OutputWeightsMatrix[:,:]
		
		return minMse
	
	def Train(self, trainingSetInputVectors:np.ndarray, trainingSetExpectedOutputVectors:np.ndarray, maxEpochs:int, learningGain:float64, momentumGain:float64, averageMseTarget:float64, maxAllowableIterationMse:float64, printStatus:bool):
		# Error checking
		numInputNeurons, numInputVectors = trainingSetInputVectors.shape
		numOutputNeurons, numOutputVectors = trainingSetExpectedOutputVectors.shape
		
		if numInputNeurons != self.NumInputNeurons:
			raise Exception('The number of input neurons does not match the number of rows in trainingSetInputVectors')
		if numOutputNeurons != self.NumOutputNeurons:
			raise Exception('The number of output neurons does not match the number of rows in trainingSetExpectedOutputVectors')
		if numInputVectors != numOutputVectors:
			raise Exception('The number of vectors in trainingSetInputVectors does not match the number of vectors in trainingSetExpectedOutputVectors')
		if numInputNeurons <= 0:
			raise Exception('Training set is empty')
		if maxEpochs <= 0:
			raise Exception('maxEpochs must be >= 0')
		if learningGain <= 0 or learningGain >= 1:
			raise Exception('learningGain must be on the range (0, 1)')
		if momentumGain < 0 or momentumGain >= 1:
			raise Exception('momentumGain must be on the range [0, 1)')
		
		# Initialize the vectors and matrices
		self.SetInputVectors(np.zeros((self.NumInputNeurons + 0, 1)))	# This initializes the feedforward vectors
		
		expectedOutputVector = np.zeros(self.OutputDecisionVectors.shape)
		outputDecisionVectorError = np.zeros(self.OutputDecisionVectors.shape)
		outputActivationVectorError = np.zeros(self.OutputActivationVectors.shape)
		hiddenDecisionVectorError = np.zeros(self.HiddenDecisionVectors.shape)
		hiddenActivationVectorError = np.zeros(self.HiddenActivationVectors.shape)
		
		outputWeightsMatrixError = np.zeros(self.OutputWeightsMatrix.shape)
		outputWeightsMatrixDelta = np.zeros(self.OutputWeightsMatrix.shape)
		outputWeightsMatrixDeltaPrev = np.zeros(self.OutputWeightsMatrix.shape)
		self.OutputWeightsMatrixMinMse = np.zeros(self.OutputWeightsMatrix.shape)
		
		hiddenWeightsMatrixError = np.zeros(self.HiddenWeightsMatrix.shape)
		hiddenWeightsMatrixDelta = np.zeros(self.HiddenWeightsMatrix.shape)
		hiddenWeightsMatrixDeltaPrev = np.zeros(self.HiddenWeightsMatrix.shape)
		self.HiddenWeightsMatrixMinMse = np.zeros(self.HiddenWeightsMatrix.shape)
		
		# Initialize training data
		iterations = trainingSetInputVectors.shape[1]
		currentEpoch = 0
		self.MinMse = np.inf
		#self.MseAtEachEpoch = np.ones((maxEpochs))
		mseAtEachEpoch = [0.0 for i in range(maxEpochs)]
		self.EpochAtMinMse = -1
		
		trainingSetInputVectorsComplete = trainingSetInputVectors[:,:]
		if self.HiddenBias:
			trainingSetInputVectorsComplete = np.concatenate((trainingSetInputVectors, np.ones((1, iterations))), axis=0)
		
		trainingSetInputVectorsList = [np.ascontiguousarray(trainingSetInputVectorsComplete[:, i]).reshape(self.NumInputNeurons + self.HiddenBias, 1) for i in range(iterations)]
		trainingSetExpectedOutputVectorsList = [np.ascontiguousarray(trainingSetExpectedOutputVectors[:, i]).reshape(self.NumOutputNeurons, 1) for i in range(iterations)]
		
		# Initialize status printout
		epochAtPercent = (np.arange(0, 100).astype(float64) * 0.01 * maxEpochs).astype(int32)
		percent = 0
		if printStatus:
			print('')
		
		# Run each epoch
		completedEpochs = maxEpochs + 0
		randomizedIndices = np.arange(iterations)
		for currentEpoch in range(maxEpochs):
			# Update status
			if printStatus:
				if currentEpoch == epochAtPercent[percent]:
					print('\033[FMLPNN Training:', percent, '%', 'Minimum MSE:', self.MinMse, ' ' * 10)
					percent += 1
			
			# Perform backpropagation on the training set over one epoch
			np.random.shuffle(randomizedIndices)
			
			# Run each iteration of the backpropagation algorithm
			mseEpoch = 0.0
			self.MaxIterationMse = 0.0
			for iteration in range(iterations):
				# Select an input/output pair from the training set
				index = randomizedIndices[iteration]
				self.InputVectors = trainingSetInputVectorsList[index]
				expectedOutputVector = trainingSetExpectedOutputVectorsList[index]
				
				# Feedforward
				self.Feedforward()
				
				# Calculate the output decision vector error
				# Assumes InputVectors is an (NumInputNeurons, 1) column vector
				# Uses the square law error function: E = 0.5 * ||y - y_hat||^2
				
				# Calculate the output error
				# ey_hat = -(dE / dy_hat) = -(d / dy_hat) * 0.5 * (y - y_hat)^2 = -(y - y_hat) * (-1) = y - y_hat
				outputDecisionVectorError = expectedOutputVector - self.OutputDecisionVectors
				
				# Calculate the iteration's MSE
				# MSE = (1 / NumOutputNeurons) * sum from i = 1 to i = NumOutputNeurons of (y_i - y_hat_i)^2
				mseIteration = np.sum(outputDecisionVectorError**2) / self.NumOutputNeurons
				if mseIteration > self.MaxIterationMse:
					self.MaxIterationMse = mseIteration
				
				# Accumulate the epoch MSE
				mseEpoch += mseIteration
				
				# If this is the last iteration in the epoch, determine if the epoch MSE is the new minimum MSE
				if iteration == iterations - 1:
					# This is the last iteration in the epoch
					
					# Calculate the MSE
					mseEpoch /= iterations
					mseAtEachEpoch[currentEpoch] = mseEpoch
					
					## Calculate the hidden activation vectors
					## a_h = W * x
					#hiddenActivationVectors = self.HiddenWeightsMatrix.dot(trainingSetInputVectorsComplete)
					#
					## Calculate the hidden decision vectors, accounting for the output bias
					## d_h = f_a(a_h)
					#hiddenDecisionVectors = np.ones((self.NumHiddenNeurons + self.OutputBias, numInputVectors))
					#if self.OutputBias:
					#	ActivationFunction(hiddenActivationVectors, hiddenDecisionVectors[0:self.NumHiddenNeurons, :])
					#else:
					#	ActivationFunction(hiddenActivationVectors, hiddenDecisionVectors)
					#
					## Calculate the output activation vectors
					## a_o = V * d_h
					#outputActivationVectors = self.OutputWeightsMatrix.dot(hiddenDecisionVectors)
					#
					## Calculate the estimated output vectors, or the output decision vectors
					## y_hat = d_o = f_a(a_o)
					#outputDecisionVectors = np.empty((self.NumOutputNeurons + 0, numInputVectors))
					#ActivationFunction(outputActivationVectors, outputDecisionVectors)
					#
					#error = trainingSetExpectedOutputVectors - outputDecisionVectors
					#mseEpoch = np.sum(error**2) / (self.NumOutputNeurons * iterations)
					
					if mseEpoch < self.MinMse:
						# Update the minimum MSE and the epoch number it happened at
						self.MinMse = mseEpoch
						self.EpochAtMinMse = currentEpoch
						
						# Store the weights that resulted in the minimum MSE
						self.OutputWeightsMatrixMinMse[:,:] = self.OutputWeightsMatrix[:,:]
						self.HiddenWeightsMatrixMinMse[:,:] = self.HiddenWeightsMatrix[:,:]
						
						# If the minimum MSE has beaten the target minimum MSE, the process is complete
						if (self.MinMse <= averageMseTarget) and (self.MaxIterationMse <= maxAllowableIterationMse):
							break
				
				# Backpropagate the iteration
				# Calculate output activation vector error
				# ea_o = dE / da_o = (dE / dd_o) * (dd_o / da_o) = ey_hat * (dd_o / da_o) = e_y_hat .* df_activ(a_o)
				ActivationFunctionDerivative(self.OutputActivationVectors, outputActivationVectorError)
				outputActivationVectorError *= outputDecisionVectorError
				
				# Calculate output weights matrix error
				# EV = dE / dV = (dE / da_o) * (da_o / dV) = ea_o * transpose(d_h)
				outputWeightsMatrixError = outputActivationVectorError.dot(self.HiddenDecisionVectors.T)
				
				# Calculate hidden decision vector error
				# ed_h = dE / dd_h = (dE / da_o) * (da_o / dd_h) = transpose(V) * ea_o
				hiddenDecisionVectorError = self.OutputWeightsMatrix.T.dot(outputActivationVectorError)
				
				# Calculate hidden activation vector error
				# ea_h = dE / da_h = (dE / dd_h) * (dd_h / da_h) = ed_h * (dd_h / da_h) = ed_h .* df_activ(a_h)
				ActivationFunctionDerivative(self.HiddenActivationVectors, hiddenActivationVectorError)
				hiddenActivationVectorError *= hiddenDecisionVectorError[0:self.NumHiddenNeurons, :]
				
				# Calculate hidden weights matrix error
				# EW = dE / dW = (dE / da_h) * (da_h / dW) = ea_h * transpose(x)
				hiddenWeightsMatrixError = hiddenActivationVectorError.dot(self.InputVectors.T)
				
				# Calculate the delta in the output weights matrix
				outputWeightsMatrixDelta = learningGain * outputWeightsMatrixError + momentumGain * outputWeightsMatrixDeltaPrev
				
				# Copy the previous output delta weights matrix for the next iteration
				outputWeightsMatrixDeltaPrev[:,:] = outputWeightsMatrixDelta[:,:]
				
				# Update the next output weights matrix
				self.OutputWeightsMatrix += outputWeightsMatrixDelta
				
				# Calculate the delta in the hidden weights matrix
				hiddenWeightsMatrixDelta = learningGain * hiddenWeightsMatrixError + momentumGain * hiddenWeightsMatrixDeltaPrev
				
				# Copy the previous hidden delta weights matrix for the next iteration
				hiddenWeightsMatrixDeltaPrev[:,:] = hiddenWeightsMatrixDelta[:,:]
				
				# Update the next hidden weights matrix
				self.HiddenWeightsMatrix += hiddenWeightsMatrixDelta
			
			# If this epoch's MSE is less than the target minimum MSE, then training is complete
			if (self.MinMse <= averageMseTarget) and (self.MaxIterationMse <= maxAllowableIterationMse):
				completedEpochs = currentEpoch + 1
				break
		
		# Resize the MseAtEachEpoch array to match the number of completed epochs
		#self.MseAtEachEpoch = self.MseAtEachEpoch[0:completedEpochs]
		
		# Update the status
		if printStatus:
			print('\033[FMLPNN Training: 100 %', 'Minimum MSE:', self.MinMse)
		
		return mseAtEachEpoch, completedEpochs

if __name__ == '__main__':
	import time
	# Example of how to train the MLPNN using the classic XOR gate
	
	# Create training set
	trainingSetInputVectors = np.array([[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]).T
	trainingSetExpectedOutputVectors = np.array([[0.0, 1.0, 1.0, 0.0]])
	
	# Create MLPNN
	numInputNeurons = 2
	numHiddenNeurons = 5
	numOutputNeurons = 1
	useHiddenBias = True
	useOutputBias = False
	m = OptimizedMLPNN(numInputNeurons, numHiddenNeurons, numOutputNeurons, useHiddenBias, useOutputBias)
	
	# Set up training parameters
	maxEpochs = 100000
	learningGain = 0.75
	momentumGain = 0.75
	averageMseTarget = 0
	maxAllowableIterationMse = np.inf
	
	# Run a dummy training algorithm to get the jit functions and class to compile
	print('Compiling training algorithm...')
	m.Train(trainingSetInputVectors, trainingSetExpectedOutputVectors, 1, learningGain, momentumGain, averageMseTarget, maxAllowableIterationMse, False)
	
	# Run the training algorithm for real and time it
	m.Initialize(numInputNeurons, numHiddenNeurons, numOutputNeurons, useHiddenBias, useOutputBias)
	t1 = time.time()
	mseAtEachEpoch, completedEpochs = m.Train(trainingSetInputVectors, trainingSetExpectedOutputVectors, maxEpochs, learningGain, momentumGain, averageMseTarget, maxAllowableIterationMse, True)
	t2 = time.time()
	
	print('Minimum MSE of', m.MinMse, 'achieved in', completedEpochs, 'epochs')
	print('Minimum MSE occurred in epoch', m.EpochAtMinMse + 1)
	
	# Test
	m.SetInputVectors(trainingSetInputVectors)
	m.Feedforward()
	
	MSE = np.sum((trainingSetExpectedOutputVectors - m.OutputDecisionVectors)**2) / m.OutputDecisionVectors.size
	
	print('Expected Outputs:')
	print(trainingSetExpectedOutputVectors)
	print('Estimated Outputs:')
	print(m.OutputDecisionVectors)
	print('MSE:', MSE)
	
	print('Executed in', t2 - t1, 'seconds')