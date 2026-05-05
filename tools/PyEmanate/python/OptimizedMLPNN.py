import numpy as np	# package numpy (install with pip install numpy)
from collections import OrderedDict
from numba import jit, int32, float64	# package numba (install with pip install numba)
from numba.experimental import jitclass

@jit(nopython=True)
def ApproxLogisticSigmoid(a, out):
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
def ApproxLogisticSigmoidDerivative(a, out):
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
def LogisticSigmoidDerivative(d, out):
	out[:,:] = d * (1.0 - d)
	return

@jit(nopython=True)
def HyperbolicTangent(a, out):
	out[:,:] = np.tanh(a)
	return
	
@jit(nopython=True)
def HyperbolicTangentDerivative(d, out):
	out[:,:] = 1.0 - (d * d)
	return

@jit(nopython=True)
def HyperbolicTangentDerivative2(a, out):
	out[:,:] = (1/np.cosh(a))**2
	return

@jit(nopython=True)
def ReLU(a, out):
	rows, cols = a.shape
	for row in range(rows):
		for col in range(cols):
			if a[row, col] < 0:
				out[row, col] = 0
			else:
				out[row, col] = a[row, col]
	return
	
@jit(nopython=True)
def ReLUDerivative(a, out):
	rows, cols = a.shape
	for row in range(rows):
		for col in range(cols):
			if a[row, col] > 0:
				out[row, col] = 1
			else:
				out[row, col] = 0
	return

OptimizedMLPNNSpec = OrderedDict()

OptimizedMLPNNSpec['NumInputs'] = int32	# aka number of input neurons
OptimizedMLPNNSpec['NumOutputsPerLayer'] = int32[:]	# size = NumLayers
OptimizedMLPNNSpec['UseBiasPerLayer'] = int32[:]	# Each element is 1 if there is a bias term for that layer, 0 if not. size = NumLayers
OptimizedMLPNNSpec['ActivationFunctionEnumPerLayer'] = int32[:]	# The enumeration for each layer's activation function. size = NumLayers

OptimizedMLPNNSpec['NumLayers'] = int32	# Number of layers = number of weights matrices
OptimizedMLPNNSpec['NumInputVectors'] = int32	# aka number of input vectors in batch
OptimizedMLPNNSpec['InputsOutputsPerLayer'] = int32[:,:]	# size = (NumLayers, 2). [i, j] indexed. i is layer number, j is 0 (for number of inputs) or 1 (for number of outputs)
OptimizedMLPNNSpec['ShapePerLayer'] = int32[:,:]	# size = (NumLayers, 2). [i, j] indexed. i is layer number, j is 0 (for number of outputs) or 1 (for number of inputs + hidden bias)

OptimizedMLPNNSpec['InputVectors'] = float64[:,:]	# The vector(s) x, size = (NumInputs, NumInputVectors)
OptimizedMLPNNSpec['ExpectedOutputVectors'] = float64[:,:]	

OptimizedMLPNNSpec['WeightsMatrixPerLayer'] = float64[:,:,:]	# [i, j, k] indexed. i is layer number, (j, k) is (ShapePerLayer[i,0] (num outputs), ShapePerLayer[i, 1] (num inputs) + UseBiasPerLayer[i])
OptimizedMLPNNSpec['ActivationVectorPerLayer'] = float64[:,:,:]	# [i, j, k] indexed. i is layer number, (j, k) is (NumOutputsPerLayer[i], NumInputVectors)
OptimizedMLPNNSpec['DecisionVectorPerLayer'] = float64[:,:,:]	# [i, j, k] indexed. i is layer number, (j, k) is (NumOutputsPerLayer[i], NumInputVectors)

OptimizedMLPNNSpec['MaxEpochs'] = int32
OptimizedMLPNNSpec['TargetMse'] = float64
OptimizedMLPNNSpec['MaxAllowableIncrementMse'] = float64
OptimizedMLPNNSpec['LearningGain'] = float64
OptimizedMLPNNSpec['MomentumGain'] = float64

OptimizedMLPNNSpec['TrainingSetInputVectors'] = float64[:,:]	# The vector(s) x, size = (NumOutputsPerLayer[NumLayers - 1], number of training set vectors in batch)
OptimizedMLPNNSpec['TrainingSetExpectedOutputVectors'] = float64[:,:]	# The vector(s) x, size = (NumOutputsPerLayer[NumLayers - 1], number of training set vectors in batch)

OptimizedMLPNNSpec['DecisionVectorErrorPerLayer'] = float64[:,:,:]
OptimizedMLPNNSpec['ActivationVectorErrorPerLayer'] = float64[:,:,:]
OptimizedMLPNNSpec['WeightsMatrixErrorPerLayer'] = float64[:,:,:]
OptimizedMLPNNSpec['WeightsMatrixDeltaPerLayer'] = float64[:,:,:]
OptimizedMLPNNSpec['WeightsMatrixDeltaPrevPerLayer'] = float64[:,:,:]
OptimizedMLPNNSpec['WeightsMatrixMinMsePerLayer'] = float64[:,:,:]

OptimizedMLPNNSpec['CurrentEpoch'] = int32
OptimizedMLPNNSpec['MinMse'] = float64	# The minimum MSE from the training algorithm
OptimizedMLPNNSpec['EpochAtMinMse'] = int32	# The epoch number that provided the minimum MSE
OptimizedMLPNNSpec['MseAtEachEpoch'] = float64[:]	# An array with the MSE from each epoch
OptimizedMLPNNSpec['MaxIncrementMse'] = float64	# The maximum MSE in the current increment



@jitclass(OptimizedMLPNNSpec)
class OptimizedMLPNN():
	
	def __init__(self, numInputs:int, numOutputsPerLayer:int32[:], useBiasPerLayer:int32[:], activationFunctionEnumPerLayer:int32[:]):
		self.Initialize(numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionEnumPerLayer)
		return
	
	def Initialize(self, numInputs:int, numOutputsPerLayer:int32[:], useBiasPerLayer:int32[:], activationFunctionEnumPerLayer:int32[:]):
		if numInputs < 1:
			raise Exception('numInputs must be > 0')
		if len(numOutputsPerLayer) < 1:
			raise Exception('Must be greater than 0 layers (numOutputsPerLayer > 0)')
		if len(useBiasPerLayer) != len(numOutputsPerLayer):
			raise Exception('useBiasPerLayer must have the same dimension as numOutputsPerLayer')
		if len(activationFunctionEnumPerLayer) != len(numOutputsPerLayer):
			raise Exception('activationFunctionEnumPerLayer must have the same dimension as numOutputsPerLayer')
		
		# Set internal data
		self.NumLayers = len(numOutputsPerLayer)
		self.NumInputs = numInputs
		self.NumInputVectors = 1
		self.NumOutputsPerLayer = np.zeros((self.NumLayers), dtype=int32)
		self.UseBiasPerLayer = np.zeros((self.NumLayers), dtype=int32)
		for i in range(self.NumLayers):
			self.NumOutputsPerLayer[i] = numOutputsPerLayer[i]
			if useBiasPerLayer[i]:
				self.UseBiasPerLayer[i] = 1
			else:
				self.UseBiasPerLayer[i] = 0
		self.ActivationFunctionEnumPerLayer = activationFunctionEnumPerLayer.copy()
		
		self.InputsOutputsPerLayer = np.zeros((self.NumLayers, 2), dtype=int32)
		self.ShapePerLayer = np.zeros((self.NumLayers, 2), dtype=int32)
		for i in range(self.NumLayers):
			if i == 0:
				self.InputsOutputsPerLayer[i, 0] = self.NumInputs
			else:
				self.InputsOutputsPerLayer[i, 0] = self.NumOutputsPerLayer[i - 1]
			self.InputsOutputsPerLayer[i, 1] = self.NumOutputsPerLayer[i]
			self.ShapePerLayer[i, 0] = self.InputsOutputsPerLayer[i, 1]
			self.ShapePerLayer[i, 1] = self.InputsOutputsPerLayer[i, 0] + self.UseBiasPerLayer[i]
		
		# Initialize weights matrices
		rows = np.max(self.ShapePerLayer[:,0])
		cols = np.max(self.ShapePerLayer[:,1])
		self.WeightsMatrixPerLayer = np.zeros((self.NumLayers, rows, cols), dtype=float64)
		for i in range(self.NumLayers):
			self.WeightsMatrixPerLayer[i, :self.ShapePerLayer[i, 0], :self.ShapePerLayer[i, 1]] = 1 - (2 * np.random.rand(self.ShapePerLayer[i, 0], self.ShapePerLayer[i, 1]))
		
		# Initialize the vectors
		self.InputVectors = np.zeros((self.NumInputs, self.NumInputVectors), dtype=float64)
		self.initializeVectors()
		
		return
	
	def initializeVectors(self):
		rows = np.max(self.InputsOutputsPerLayer[:,0])
		self.ActivationVectorPerLayer = np.zeros((self.NumLayers, rows, self.NumInputVectors), dtype=float64)
		self.DecisionVectorPerLayer = np.ones((self.NumLayers, rows + 1, self.NumInputVectors), dtype=float64)	# the +1 for rows is there to support an optional bias term for the input to the subsequent layer. Setting all to 1 allows for the use of the bias term to be multiplied by 1 (the last row will always remain 1s)
		self.ActivationVectorErrorPerLayer = np.zeros((self.NumLayers, rows, self.NumInputVectors), dtype=float64)
		self.DecisionVectorErrorPerLayer = np.zeros((self.NumLayers, rows + 1, self.NumInputVectors), dtype=float64)	# the +1 for rows is there to support an optional bias term for the input to the subsequent layer
		return
	
	def SetInputVectors(self, InputVectors:float64[:,:]):
		# Error checking
		new_num_inputs, new_num_vectors = InputVectors.shape
		if new_num_inputs != self.NumInputs:
			raise Exception('New InputVectors does not have the proper number of inputs (first dimension)')
		
		# Do we need to change the shape of the activation and decision vectors?
		if new_num_vectors != self.NumInputVectors:
			self.NumInputVectors = new_num_vectors
			self.initializeVectors()
		
		# Copy input vectors
		if self.InputVectors.shape == InputVectors.shape:
			if self.UseBiasPerLayer[0]:
				self.InputVectors = np.concatenate((InputVectors, np.ones((1, self.NumInputVectors))), axis=0)
			else:
				self.InputVectors[:,:] = InputVectors[:,:]
		else:
			if self.UseBiasPerLayer[0]:
				self.InputVectors = np.concatenate((InputVectors, np.ones((1, self.NumInputVectors))), axis=0)
			else:
				self.InputVectors = InputVectors.copy()
		
		return
	
	def SetExpectedOutputVectors(self, ExpectedOutputVectors:float64[:,:]):
		# Error checking
		new_num_outputs, new_num_vectors = ExpectedOutputVectors.shape
		if new_num_outputs != self.NumOutputsPerLayer[-1]:
			raise Exception('New ExpectedOutputVectors does not have the proper number of inputs (first dimension)')
		
		# Do we need to change the shape of the activation and decision vectors?
		if new_num_vectors != self.NumInputVectors:
			raise Exception('New ExpectedOutputVectors does not have the proper number vectors (second dimension, must equal that of InputVectors')
		
		# Copy expected output vectors
		if self.ExpectedOutputVectors.shape == ExpectedOutputVectors.shape:
			self.ExpectedOutputVectors[:,:] = ExpectedOutputVectors[:,:]
		else:
			self.ExpectedOutputVectors = ExpectedOutputVectors.copy()
		
		return
		
	def Feedforward(self, InputVectors=None):
		if InputVectors is not None:
			self.SetInputVectors(InputVectors)
		
		# Compute each layer
		for layerNum in range(self.NumLayers):
			# Calculate the activation vector
			# a[layer] = W[layer] * x[layer]
			prevLayerNum = layerNum - 1
			if layerNum == 0:
				self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = self.WeightsMatrixPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]].dot(self.InputVectors)
			else:
				self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = self.WeightsMatrixPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]].dot(self.DecisionVectorPerLayer[prevLayerNum, :self.ShapePerLayer[layerNum, 1], :])
			
			# Calculate the decision vector
			# d[layer] = f_a(a[layer])
			fa_num = self.ActivationFunctionEnumPerLayer[layerNum]
			if fa_num == 1:
				ApproxLogisticSigmoid(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
			elif fa_num == 2:
				LogisticSigmoid(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
			elif fa_num == 3:
				HyperbolicTangent(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
			elif fa_num == 4:
				ReLU(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
			elif fa_num == 5:
				# Linear
				self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :]
			else:
				raise Exception('Invalid actiation function enumeration')
			
		return
	
	def GetOutputVector(self):
		lastLayer = self.NumLayers - 1
		return self.DecisionVectorPerLayer[lastLayer, :self.NumOutputsPerLayer[lastLayer], :]
	
	def InitializeBackpropagation(self, maxEpochs:int32, learningGain:float64, momentumGain:float64, targetMse:float64, maxAllowableIncrementMse:float64):
		# Error checking
		if maxEpochs < 1:
			raise Exception('maxEpochs must be > 0')
		if targetMse < 0:
			raise Exception('targetMse must be >= 0')
		if maxAllowableIncrementMse < 0:
			raise Exception('maxAllowableIncrementMse must be >= 0')
		if not (0 < learningGain < 1):
			raise Exception('learningGain must be between 0 and 1')
		if not (0 < momentumGain < 1):
			raise Exception('momentumGain must be between 0 and 1')
		
		# Populate parameters
		self.MaxEpochs = maxEpochs
		self.TargetMse = targetMse
		self.MaxAllowableIncrementMse = maxAllowableIncrementMse
		self.LearningGain = learningGain
		self.MomentumGain = momentumGain
		
		# Initialize training data
		self.CurrentEpoch = 0
		self.MinMse = np.inf
		self.MseAtEachEpoch = np.zeros((self.MaxEpochs), dtype=float64)
		self.EpochAtMinMse = -1
		
		# Initialize backpropagation weights errors
		self.WeightsMatrixErrorPerLayer = np.zeros(self.WeightsMatrixPerLayer.shape, dtype=float64)
		self.WeightsMatrixDeltaPerLayer = np.zeros(self.WeightsMatrixPerLayer.shape, dtype=float64)
		self.WeightsMatrixDeltaPrevPerLayer = np.zeros(self.WeightsMatrixPerLayer.shape, dtype=float64)
		self.WeightsMatrixMinMsePerLayer = np.zeros(self.WeightsMatrixPerLayer.shape, dtype=float64)
		
		return
	
	def SetTrainingSet(self, trainingSetInputVectors:float64[:,:], trainingSetExpectedOutputVectors:float64[:,:], useBatch:bool, batchSize:int):
		# Error checking
		new_num_inputs, new_num_vectors = trainingSetInputVectors.shape
		if new_num_inputs != self.NumInputs:
			raise Exception('trainingSetInputVectors does not have the proper number of inputs (first dimension)')
		self.TrainingSetInputVectors = trainingSetInputVectors
		
		new_num_outputs, new_num_vectors2 = trainingSetExpectedOutputVectors.shape
		if new_num_outputs != self.NumOutputsPerLayer[self.NumLayers - 1]:
			raise Exception('trainingSetExpectedOutputVectors does not have the proper number of outputs (first dimension)')
		if new_num_vectors2 != new_num_vectors:
			raise Exception('trainingSetExpectedOutputVectors does not have the proper number of output vectors (second dimension) (must be equal to the number of input vectors)')
		
		self.TrainingSetExpectedOutputVectors = trainingSetExpectedOutputVectors

		if useBatch and not (1 <= batchSize < self.TrainingSetInputVectors.shape[1]):
			self.SetInputVectors(self.TrainingSetInputVectors)
			self.SetExpectedOutputVectors(self.TrainingSetExpectedOutputVectors)
		
		return
	
	def BackpropagateEpoch(self, useBatch:bool, batchSize:int):
		if useBatch:
			increments = 1
		else:
			# Randomize the training set
			increments = self.TrainingSetInputVectors.shape[1]
			randomizedIndices = np.arange(increments)
			np.random.shuffle(randomizedIndices)
			if 1 <= batchSize < increments:
				increments = batchSize
			self.MaxIncrementMse = 0.0
		
		numOutputs = self.NumOutputsPerLayer[self.NumLayers - 1]
		
		# Run each increment of the backpropagation algorithm (if using Batch mode, there is only 1 increment)
		mseEpoch = 0.0
		self.MaxIncrementMse = 0.0
		for increment in range(increments):
			if not useBatch:
				# Select an input/output pair from the training set
				index = randomizedIndices[increment]
				nextIndex = index + 1
				self.SetInputVectors(self.TrainingSetInputVectors[:, index:nextIndex])
				self.SetExpectedOutputVectors(self.TrainingSetExpectedOutputVectors[:, index:nextIndex])
			elif 1 <= batchSize < self.TrainingSetInputVectors.shape[1]:
				# This is batch mode
				# Randomly select batchSize vectors from the training set for backpropagation
				if self.InputVectors.shape != (self.TrainingSetInputVectors.shape[0], batchSize):
					self.SetInputVectors(np.zeros((self.TrainingSetInputVectors.shape[0], batchSize), dtype=float64))
				if self.ExpectedOutputVectors.shape != (self.TrainingSetInputVectors.shape[0], batchSize):
					self.SetExpectedOutputVectors(np.zeros((self.TrainingSetExpectedOutputVectors.shape[0], batchSize), dtype=float64))
				randomizedIndices = np.arange(batchSize)
				np.random.shuffle(randomizedIndices)
				for i in range(batchSize):
					index = randomizedIndices[i] 
					self.InputVectors[:self.NumInputs, i:i+1] = self.TrainingSetInputVectors[:, index:index+1]
					self.ExpectedOutputVectors[:, i:i+1] = self.TrainingSetExpectedOutputVectors[:, index:index+1]
			
			# Feedforward
			self.Feedforward()
			
			# Step through each layer
			for inverseLayerNum in range(self.NumLayers):
				layerNum = self.NumLayers - inverseLayerNum - 1
				nextLayerNum = layerNum  + 1
				
				# Calculate the decision vector error
				if inverseLayerNum == 0:
					if useBatch:
						# ey_hat = -(dE / dy_hat) = -(d / dy_hat) * 0.5 * (y - y_hat)^2 = -(y - y_hat) * (-1) = y - y_hat
						# Ed[last] = y_expected - d[last], dimensions: (NumOutputsPerLayer[last], NumInputVectors)
						self.DecisionVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = self.ExpectedOutputVectors - self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :]
						
						# Calculate the epoch's MSE
						mseEpoch = np.sum(self.DecisionVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :]**2) / self.ExpectedOutputVectors.size
						self.MseAtEachEpoch[self.CurrentEpoch] = mseEpoch
						
						# Is this the new best MSE target?
						if mseEpoch < self.MinMse:
							# Update the minimum MSE and the epoch number it happened at
							self.MinMse = mseEpoch
							self.EpochAtMinMse = self.CurrentEpoch
							
							# Store the weights that resulted in the minimum MSE
							self.WeightsMatrixMinMsePerLayer[:,:,:] = self.WeightsMatrixPerLayer[:,:,:]
							
							# If the minimum MSE has beaten the target minimum MSE, the process is complete
							if self.MinMse <= self.TargetMse:
								self.CurrentEpoch += 1
								return True
					else:
						# Ed[last] = y_expected - d[last], dimensions: (NumOutputsPerLayer[last], NumInputVectors)
						self.DecisionVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], 0:1] = self.ExpectedOutputVectors - self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], 0:1]
						
						# Calculate the increment's MSE
						mseIncrement = np.sum(self.DecisionVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], 0:1]**2) / numOutputs
						if mseIncrement > self.MaxIncrementMse:
							self.MaxIncrementMse = mseIncrement
						
						mseEpoch += mseIncrement
						
						# If this is the last increment in the epoch, determine if the epoch MSE is the new minimum MSE
						if increment == increments - 1:
							# This is the last increment in the epoch. Calculate the epoch MSE.
							mseEpoch /= increments
							self.MseAtEachEpoch[self.CurrentEpoch] = mseEpoch
							
							# Is this the new best MSE target?
							if mseEpoch < self.MinMse:
								# Update the minimum MSE and the epoch number it happened at
								self.MinMse = mseEpoch
								self.EpochAtMinMse = self.CurrentEpoch
								
								# Store the weights that resulted in the minimum MSE
								self.WeightsMatrixMinMsePerLayer[:,:,:] = self.WeightsMatrixPerLayer[:,:,:]
								
								# If the minimum MSE has beaten the target minimum MSE, the process is complete
								if (self.MinMse <= self.TargetMse) and (self.MaxIncrementMse <= self.MaxAllowableIncrementMse):
									self.CurrentEpoch += 1
									return True
				else:
					# ed_i = dE / dd_i = (dE / da_o) * (da_o / dd_i) = transpose(W_o) * ea_o
					# Ed[layer] = W[layer + 1].T * Ea[layer + 1], dimensions: (NumOutputsPerLayer[layer] + UseBiasPerLayer[layer + 1], NumInputVectors)
					self.DecisionVectorErrorPerLayer[layerNum, :self.ShapePerLayer[nextLayerNum, 1], :] = self.WeightsMatrixPerLayer[nextLayerNum, :self.ShapePerLayer[nextLayerNum, 0], :self.ShapePerLayer[nextLayerNum, 1]].T.dot(self.ActivationVectorErrorPerLayer[nextLayerNum, :self.ShapePerLayer[nextLayerNum, 0], :])
				
				# Calculate the activation vector error
				# ea_o = dE / da_o = (dE / dd_o) * (dd_o / da_o) = ey_hat * (dd_o / da_o) = e_y_hat .* df_activ(a_o)
				# Ea[layer] = Ed[layer] .* (d/dx f_a[layer](a[layer]))
				fa_num = self.ActivationFunctionEnumPerLayer[layerNum]
				if fa_num == 1:
					ApproxLogisticSigmoidDerivative(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
				elif fa_num == 2:
					LogisticSigmoidDerivative(self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
				elif fa_num == 3:
					HyperbolicTangentDerivative(self.DecisionVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
				elif fa_num == 4:
					ReLUDerivative(self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :], self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :])
				elif fa_num == 5:
					# Linear
					#self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = self.ActivationVectorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :]
					self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] = np.ones((self.NumOutputsPerLayer[layerNum], self.NumInputVectors), dtype=float64)
				else:
					raise Exception('Invalid actiation function enumeration')
				self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :] *= self.DecisionVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :]
				
				# Calculate weights matrix error
				# EV = dE / dV = (dE / da_o) * (da_o / dV) = ea_o * transpose(d_h)
				if layerNum == 0:
					# EW[first] = Ea[first] * InputVectors.T, dimensions: (NumOutputsPerLayer[layer], NumInputs + UseBiasPerLayer[first])
					self.WeightsMatrixErrorPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] = self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :].dot(self.InputVectors.T)
				else:
					# EW[layer] = Ea[layer] * d[layer - 1].T, dimensions: (NumOutputsPerLayer[layer], NumOutputsPerLayer[layer - 1] + UseBiasPerLayer[layer - 1])
					self.WeightsMatrixErrorPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] = self.ActivationVectorErrorPerLayer[layerNum, :self.NumOutputsPerLayer[layerNum], :].dot(self.DecisionVectorPerLayer[layerNum - 1, :self.ShapePerLayer[layerNum, 1], :].T)
				
				# Calculate weights delta
				self.WeightsMatrixDeltaPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] = self.LearningGain * self.WeightsMatrixErrorPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] + self.MomentumGain * self.WeightsMatrixDeltaPrevPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]]
				
				# Copy previous delta weights matrix for next increment
				self.WeightsMatrixDeltaPrevPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] = self.WeightsMatrixDeltaPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]]
				
				# Update the weights matrix
				self.WeightsMatrixPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]] += self.WeightsMatrixDeltaPerLayer[layerNum, :self.ShapePerLayer[layerNum, 0], :self.ShapePerLayer[layerNum, 1]]
		
		self.CurrentEpoch += 1
		
		return False
	
	def Train(self, useBatch:bool, batchSize:int, maxEpochs:int32, learningGain:float64, momentumGain:float64, trainingSetInputVectors:float64[:,:], trainingSetExpectedOutputVectors:float64[:,:], targetMse:float64, maxAllowableIncrementMse:float64):
		self.InitializeBackpropagation(maxEpochs, learningGain, momentumGain, targetMse, maxAllowableIncrementMse)
		self.SetTrainingSet(trainingSetInputVectors, trainingSetExpectedOutputVectors, useBatch, batchSize)
		
		while self.CurrentEpoch < self.MaxEpochs:
			if self.BackpropagateEpoch(useBatch, batchSize):
				break
		
		self.WeightsMatrixPerLayer[:,:,:] = self.WeightsMatrixMinMsePerLayer[:,:,:]
		self.MseAtEachEpoch = self.MseAtEachEpoch[:self.CurrentEpoch].copy()
		
		return




class OptimizedMlpnnWrapper():
	
	MLP = None
	
	ActivationFunctionEnum = {
		'sigmoid-approx': 1,
		'sigmoid': 2,
		'tanh': 3,
		'relu': 4,
		'linear': 5,
	}
	
	@property
	def OutputVector(self):
		return self.MLP.GetOutputVector()
	
	@property
	def CurrentEpoch(self):
		return self.MLP.CurrentEpoch
	
	@property
	def MaxEpochs(self):
		return self.MLP.MaxEpochs
	
	@property
	def MinMse(self):
		return self.MLP.MinMse
	
	@property
	def EpochAtMinMse(self):
		return self.MLP.EpochAtMinMse
	
	@property
	def MseAtEachEpoch(self):
		return self.MLP.MseAtEachEpoch
	
	@property
	def Weights(self):
		w = [self.MLP.WeightsMatrixPerLayer[i, :self.MLP.ShapePerLayer[i, 0], :self.MLP.ShapePerLayer[i, 1]] for i in range(self.MLP.NumLayers)]
		return w
	
	@Weights.setter
	def Weights(self, value):
		if type(value) != list:
			raise Exception('Weights must be a list of matrices for each layer. Did not provide a list.')
		if len(value) != self.MLP.NumLayers:
			raise Exception('Weights must be a list of matrices for each layer. Improper number of layers')
		for i, w in enumerate(value):
			if type(w) == list:
				w = np.array(w)
			elif type(w) != np.ndarray:
				raise Exception('Weights must be a list of matrices for each layer. Did not provide list of matrices')
			self.MLP.WeightsMatrixPerLayer[i, :self.MLP.ShapePerLayer[i, 0], :self.MLP.ShapePerLayer[i, 1]] = w.copy()
	
	@property
	def BestWeights(self):
		w = []
		for i in range(self.MLP.NumLayers):
			w.append(self.MLP.WeightsMatrixMinMsePerLayer[i, :self.MLP.ShapePerLayer[i, 0], :self.MLP.ShapePerLayer[i, 1]])
		return w
	
	@property
	def BestWeightsQx_15(self):
		return [OptimizedMlpnnWrapper.FloatMatrixToQx_15(w) for w in self.BestWeights]
	
	@property
	def BestWeightsByteArrays(self):
		weightsListQ = self.BestWeightsQx_15
		weightsListBytes = [OptimizedMlpnnWrapper.Qx_15MatrixToByteArray(w) for w in weightsListQ]
		return weightsListBytes
	
	@staticmethod
	def FloatMatrixToQx_15(wf:np.ndarray):
		return np.round(wf * 32768).astype(int)
	
	@staticmethod
	def Qx_15MatrixToByteArray(wq:np.ndarray, reverseByteOrder=True):
		wflat = wq.flatten(order='C').tolist()
		byteorder = 'big'
		if reverseByteOrder:
			byteorder = 'little'
		b = b''
		for i in wflat:
			b += i.to_bytes(3, byteorder=byteorder, signed=True)
		return b
	
	
	
	
	def Initialize(self, numInputs:int, numOutputsPerLayer:list, useBiasPerLayer:list, activationFunctionPerLayer:list):
		# Convert the lists into numpy arrays
		numOutputsPerLayer = np.array(numOutputsPerLayer, dtype=int)
		useBiasPerLayer = np.array(useBiasPerLayer, dtype=int)
		
		# Create the activation function enumerations
		activationFunctionEnumPerLayer = np.zeros((len(numOutputsPerLayer)), dtype=int)
		for i, fn in enumerate(activationFunctionPerLayer):
			if fn not in self.ActivationFunctionEnum:
				print('Valid activation functions:', self.ActivationFunctionEnum.keys())
				raise Exception('Invalid activation function ' + str(fn) + ' (see list above of valid activation functions')
			activationFunctionEnumPerLayer[i] = self.ActivationFunctionEnum[fn]
		
		self.MLP = OptimizedMLPNN(numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionEnumPerLayer)
		
		return self.MLP
	
	def SetInputVectors(self, InputVectors):
		if type(InputVectors) == list:
			InputVectors = np.array(InputVectors)
		elif type(InputVectors) != np.ndarray:
			raise Exception('InputVectors must be a matrix')
		self.MLP.SetInputVectors(InputVectors)
		return
	
	def Feedforward(self, InputVectors=None):
		if InputVectors is not None:
			self.MLP.SetInputVectors(InputVectors)
		self.MLP.Feedforward()
		return self.MLP.GetOutputVector()
	
	def InitializeBackpropagation(self, maxEpochs:int, learningGain:float, momentumGain:float, targetMse:float=0.0, maxAllowableIncrementMse:float=np.inf):
		self.MLP.InitializeBackpropagation(maxEpochs, learningGain, momentumGain, targetMse, maxAllowableIncrementMse)
		return
	
	def SetTrainingSet(self, trainingSetInputVectors, trainingSetExpectedOutputVectors, useBatch:bool, batchSize=None):
		if type(trainingSetInputVectors) == list:
			trainingSetInputVectors = np.array(trainingSetInputVectors)
		elif type(trainingSetInputVectors) != np.ndarray:
			raise Exception('trainingSetInputVectors must be a matrix')
		
		if type(trainingSetExpectedOutputVectors) == list:
			trainingSetExpectedOutputVectors = np.array(trainingSetExpectedOutputVectors)
		elif type(trainingSetExpectedOutputVectors) != np.ndarray:
			raise Exception('trainingSetExpectedOutputVectors must be a matrix')
		
		if batchSize is None:
			batchSize = 0
		
		self.MLP.SetTrainingSet(trainingSetInputVectors, trainingSetExpectedOutputVectors, useBatch, batchSize)
		return
	
	def BackpropagateEpoch(self, useBatch:bool, batchSize=None):
		if batchSize is None:
			batchSize = 0
		return self.MLP.BackpropagateEpoch(useBatch, batchSize)
	
	def Train(self, maxEpochs:int, learningGain:float, momentumGain:float, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse:float=0.0, maxAllowableIncrementMse:float=np.inf, useBatch:bool=False, batchSize=None):
		if batchSize is None:
			batchSize = 0
		self.MLP.Train(useBatch, batchSize, maxEpochs, learningGain, momentumGain, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse, maxAllowableIncrementMse)
		return
	
	def ComputeMSE(self, expectedOutputVectors, estimatedOutputVectors):
		return np.sum((expectedOutputVectors - estimatedOutputVectors)**2) / estimatedOutputVectors.size
		
if __name__ == '__main__':
	import time
	# Example of how to train the MLPNN using the classic XOR gate
	
	# Create training set
	trainingSetInputVectors = np.array([[0.0, 0.0], [0.0, 1.0], [1.0, 0.0], [1.0, 1.0]]).T
	trainingSetExpectedOutputVectors = np.array([[0.0, 1.0, 1.0, 0.0]])
	
	# Configure MLP
	numInputs = 2
	numOutputsPerLayer = [5, 5, 1]
	useBiasPerLayer = [True, True, False]
	activationFunctionPerLayer = ['sigmoid-approx', 'tanh', 'sigmoid-approx']
	
	print('Compiling training algorithm...')
	t1 = time.time()
	m = OptimizedMlpnnWrapper()
	m.Initialize(numInputs, numOutputsPerLayer, useBiasPerLayer, activationFunctionPerLayer)
	
	# Set training parameters
	maxEpochs = 10000
	targetMse = 0
	learningGain = 0.75
	momentumGain = 0.75
	maxAllowableIncrementMse = np.inf
	useBatch=True
	
	# Run a dummy training algorithm to get the jit functions and class to compile
	m.Train(1, learningGain, momentumGain, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse=targetMse, useBatch=useBatch)
	m.SetInputVectors(trainingSetInputVectors)
	m.Feedforward()
	t2 = time.time()
	compileTime = t2 - t1
	print('Compiled in', compileTime, 'seconds')
	
	# Train
	print('Training...')
	t1 = time.time()
	ret = m.Train(maxEpochs, learningGain, momentumGain, trainingSetInputVectors, trainingSetExpectedOutputVectors, targetMse=targetMse, useBatch=useBatch)
	t2 = time.time()
	trainingTime = t2 - t1
	if ret:
		print('Met MSE target')
	else:
		print('Did not meet MSE target')
	print('Minimum MSE of', m.MinMse, 'achieved in', m.CurrentEpoch, 'epochs')
	print('Minimum MSE occurred in epoch', m.EpochAtMinMse + 1)
	print('Trained in', trainingTime, 'seconds')
	
	# Test
	m.SetInputVectors(trainingSetInputVectors)
	estimatedOutputVectors = m.Feedforward()
	
	MSE = m.ComputeMSE(trainingSetExpectedOutputVectors, estimatedOutputVectors)
	
	print('Expected Outputs:')
	print(trainingSetExpectedOutputVectors)
	print('Estimated Outputs:')
	print(estimatedOutputVectors)
	print('MSE:', MSE)
	
	print('Weights:')
	w = m.BestWeights
	m.Weights = w
	w1 = w[1]
	m.Weights[1] = np.zeros(w1.shape)
	for w in m.Weights:
		print(w)
	
	import matplotlib.pyplot as plt
	plt.semilogy(m.MseAtEachEpoch)
	plt.xlabel('Epoch')
	plt.ylabel('MSE')
	plt.show()
