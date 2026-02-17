/** Includes **/
#include <MemoryMap.h>
#include <irq.h>
#include <HardwareMLPNN.h>



/** Interrupt Service Routine Declaration Macros **/
RVISR(IRQ_NN0_VECTOR, ISR_NN0)



/** Defines **/



/** Private Variables **/



/** Public Function Declarations **/
int8_t check_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
void run_mlpnn_layer_without_check(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
int8_t run_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
void normalize_mlpnn_input_vector(Q0_31 *unnormalized_input_vector, uint16_t input_vector_length, Q0_15 *normalized_input_vector_out);



/** Private Function Declarations **/
static uint8_t isOutOfBoundsOfNN0SRAM(uint32_t start_address, uint32_t lengthBytes);
static uint8_t doArraysOverlap(uint32_t start_address1, uint32_t lengthBytes1, uint32_t start_address2, uint32_t lengthBytes2);



/** Function Definitions **/
int8_t check_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector)
{
	/*
	Checks the parameters for the MLPNN layer and pointers to make sure the NPU will function properly.
	WARNING: Each element in the weights matrix must be represented as three "unpacked" uint8_t numbers, starting with the LSbyte first and ending with the MSbyte.
	Arguments:
		@numInputs: The number of inputs (1 to 256)
		@numOutputs: The number of outputs (1 to 256)
		@useBiasTerms: If bias terms are being used or not (1 or 0)
		@inputVector: Pointer to the input vector, which is composed of numInputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@weightsMatrix: Pointer to the weights matrix, which is composed of (numOutputs * (numInputs + useBiasTerms)) Q8.15 (represented as int24) numbers. As there is no intrinsic int24 number, you must store each element in the weights matrix as three "unpacked" uint8_t numbers, starting with the LSbyte and ending with the MSbyte. Note that the MSB of the MSbyte is the sign bit. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@outputVector: Pointer to the output vector, which is composed of numOutputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
	Returns: 0 if no errors, otherwise the error value
	*/

	// Error checking
	if (NN0CR & NNRUN)
		return MlpnnError_AlreadyRunning;
	
	if (numInputs == 0 || numInputs > 256)
		return MlpnnError_InvalidNumInputs;

	if (numOutputs == 0 || numOutputs > 256)
		return MlpnnError_InvalidNumInputs;

	uint16_t inputVectorBytes = 2 * numInputs;
	uint32_t weightsMatrixBytes = 3 * (numOutputs * (numInputs + useBiasTerms));
	uint16_t outputVectorBytes = 2 * numOutputs;

	// Check if the vectors/matrix are outside the NN0SRAM
	if (isOutOfBoundsOfNN0SRAM((uint32_t)inputVector, inputVectorBytes))
		return MlpnnError_InputVectorOutOfBounds;
	
	if (isOutOfBoundsOfNN0SRAM((uint32_t)weightsMatrix, weightsMatrixBytes))
		return MlpnnError_WeightsMatrixOutOfBounds;

	if (isOutOfBoundsOfNN0SRAM((uint32_t)outputVector, outputVectorBytes))
		return MlpnnError_OutputVectorOutOfBounds;

	// Check if any of the vectors/matrix overlap
	if (doArraysOverlap((uint32_t)inputVector, inputVectorBytes, (uint32_t)weightsMatrix, weightsMatrixBytes))
		return MlpnnError_InputOverlapsWeights;
	
	if (doArraysOverlap((uint32_t)inputVector, inputVectorBytes, (uint32_t)outputVector, outputVectorBytes))
		return MlpnnError_InputOverlapsOutput;
	
	if (doArraysOverlap((uint32_t)weightsMatrix, weightsMatrixBytes, (uint32_t)outputVector, outputVectorBytes))
		return MlpnnError_OutputOverlapsWeigts;
	
	return MlpnnError_Good;
}

void run_mlpnn_layer_without_check(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector)
{
	/*
	Computes a single MLPNN layer based on the inputs and weights matrix. Does not check the MLPNN layer parameters or vector/matrix pointers before doing so.
	WARNING: Each element in the weights matrix must be represented as three "unpacked" uint8_t numbers, starting with the LSbyte first and ending with the MSbyte.
	Arguments:
		@numInputs: The number of inputs (1 to 256)
		@numOutputs: The number of outputs (1 to 256)
		@useBiasTerms: If bias terms are being used or not (1 or 0)
		@inputVector: Pointer to the input vector, which is composed of numInputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@weightsMatrix: Pointer to the weights matrix, which is composed of (numOutputs * (numInputs + useBiasTerms)) Q8.15 (represented as int24) numbers. As there is no intrinsic int24 number, you must store each element in the weights matrix as three "unpacked" uint8_t numbers, starting with the LSbyte and ending with the MSbyte. Note that the MSB of the MSbyte is the sign bit. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@outputVector: Pointer to the output vector, which is composed of numOutputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
	Returns: void
	*/

	// Set up the neural processing unit
	NN0CR = 0
#ifndef NPU_DO_NOT_USE_INTERRUPT
		| NNCIE	// Neural network complete interrupt enable
#endif
		// | NNLSIS	// Logistic sigmoid input select ('0' => NPU; '1' => NN0LSI register)
		| NNCS	// NPU clock source ('0' => SMCLK; '1' => MCLK)
		// | NNBIAS
		// | NNRUN
		| ((numOutputs - 1) << NNO_LSB)
		| (numInputs - 1)
	;

	if (useBiasTerms)
		NN0CR |= NNBIAS;

	NN0IVA = (uint32_t)inputVector;
	NN0OVA = (uint32_t)outputVector;
	NN0WMA = (uint32_t)weightsMatrix;

#ifdef NPU_DO_NOT_USE_INTERRUPT
	// Start the NPU and wait for it to finish
	NN0CR |= NNRUN;
	while (NN0CR & NNRUN) {}
#else
	// Start the NPU and go to sleep, waiting for the ISR to wake the CPU up
	set_IRQ_disable_mask(get_IRQ_disable_mask() & ~(1 << IRQ_NN0_VECTOR));
	NN0CR |= NNRUN;
	cpu_sleep();
	while (NN0CR & NNRUN) {}
	NN0CR &= ~(NNCIE | NNCIF);
#endif
	
}

int8_t run_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector)
{
	/*
	Checks the parameters for the MLPNN layer and pointers to make sure the NPU will function properly. If no errors are found, computes a single MLPNN layer based on the inputs and weights matrix.
	WARNING: Each element in the weights matrix must be represented as three "unpacked" uint8_t numbers, starting with the LSbyte first and ending with the MSbyte.
	Arguments:
		@numInputs: The number of inputs (1 to 256)
		@numOutputs: The number of outputs (1 to 256)
		@useBiasTerms: If bias terms are being used or not (1 or 0)
		@inputVector: Pointer to the input vector, which is composed of numInputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@weightsMatrix: Pointer to the weights matrix, which is composed of (numOutputs * (numInputs + useBiasTerms)) Q8.15 (represented as int24) numbers. As there is no intrinsic int24 number, you must store each element in the weights matrix as three "unpacked" uint8_t numbers, starting with the LSbyte and ending with the MSbyte. Note that the MSB of the MSbyte is the sign bit. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
		@outputVector: Pointer to the output vector, which is composed of numOutputs Q0.15 (represented as int16) numbers. Must be contained in the NN0SRAM region. Suggested to use the ALLOCATE_IN_NN0SRAM macro as a prefix to the array's global variable declaration.
	Returns: 0 if no errors, otherwise the error value
	*/

	// Error checking
	int8_t ret = check_mlpnn_layer(numInputs, numOutputs, useBiasTerms, inputVector, weightsMatrix, outputVector);
	if (ret != MlpnnError_Good)
		return ret;

	// Run the layer
	run_mlpnn_layer_without_check(numInputs, numOutputs, useBiasTerms, inputVector, weightsMatrix, outputVector);

	return MlpnnError_Good;
}

void normalize_mlpnn_input_vector(Q0_31 *unnormalized_input_vector, uint16_t input_vector_length, Q0_15 *normalized_input_vector_out)
{
	// Find the maximum value in the unnormalized vector
	Q0_31 maxval = 0, val;
	uint16_t row;
	for (row = 0; row < input_vector_length; row++)
	{
		val = unnormalized_input_vector[row];
		if (val > maxval)
			maxval = val;
	}

	// Calculate the normalizing factor
	uint32_t normalizingFactor;
	int8_t multOrDiv;	// 1 => multiply; -1 => divide

	if (maxval == 0)
	{
		normalizingFactor = 1;
		multOrDiv = 1;
	}
	else if (maxval >= Qx_15_ONE)
	{
		// The maximum value needs to be scaled down with a division
		// Indicate division with a negative multOrDiv flag
		normalizingFactor = (((int64_t)maxval) << 16) / 32767;
		multOrDiv = -1;
	}
	else
	{
		// The maximum value needs to be scaled up with a multiplication
		// Indicate multiplication with a positive multOrDiv flag
		normalizingFactor = 1073709056 / maxval;	// 1073709056 = 32767 << 15
		multOrDiv = 1;
	}

	// Normalize the input vector
	for (row = 0; row < input_vector_length; row++)
	{
		if (multOrDiv < 0)
		{
			// Scale down with division
			normalized_input_vector_out[row] = (((uint64_t)unnormalized_input_vector[row]) << 16) / normalizingFactor;
		}
		else
		{
			// Scale up with multiplication
			normalized_input_vector_out[row] = (unnormalized_input_vector[row] * normalizingFactor) >> 15;
		}
	}

	return;
}

static uint8_t isOutOfBoundsOfNN0SRAM(uint32_t start_address, uint32_t lengthBytes)
{
	return ((start_address < NN0SRAM_START) || ((start_address + lengthBytes) > NN0SRAM_END));
}

static uint8_t doArraysOverlap(uint32_t start_address1, uint32_t lengthBytes1, uint32_t start_address2, uint32_t lengthBytes2)
{
	return ((start_address1 < (start_address2 + lengthBytes2)) && (start_address2 < (start_address1 + lengthBytes1)));
}



/** Interrupt Service Routines **/
void ISR_NN0()
{
	// Clear the interrupt flag
	NN0CR &= ~NNCIF;

	// Wake up
	cpu_wake();
}
