#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/** Includes **/
#include <MemoryMap.h>
#include <irq.h>



/** Defines **/
#define NN0SRAM_START	(0x1C000)	// SRAM07
#define NN0SRAM_LENGTH	(16384)	// 16 KiB
#define NN0SRAM_END		(NN0SRAM_START + NN0SRAM_LENGTH)

// Data minima and maxima
#define int16_t_MIN			(-32768)
#define int16_t_MAX			(32767)
#define int32_t_MIN			(-2147483647 - 1)
#define int32_t_MAX			(2147483647)

// Fixed point number definitions
#define Qx_15_ALMOST_ONE	(32767)
#define Qx_15_ONE			(32768)
#define Qx_15_HALF			(16384)
#define Qx_15_FOURTH		(8192)
#define Qx_15_NEG_ONE		(-32768)

#define Q8_15_MAX			(8388607)
#define Q8_15_MIN			(-8388608)
#define Q0_31_MAX			(2147483647)
#define Q0_31_MIN			(0)



/** Macros **/
#define ALLOCATE_IN_NN0SRAM __attribute__((section(".NN0SRAM"))) __attribute__((aligned (4))) volatile

#define ELEMENTS_IN_INPUT_VECTOR(_numInputs)	(_numInputs)
#define BYTES_IN_INPUT_VECTOR(_numInputs)	(2 * ELEMENTS_IN_INPUT_VECTOR(_numInputs))

#define ELEMENTS_IN_WEIGHTS_MATRIX(_numInputs, _numOutputs, _useBiasTerms)	(_numOutputs * (_numInputs + (_useBiasTerms != 0)))
#define BYTES_IN_WEIGHTS_MATRIX(_numInputs, _numOutputs, _useBiasTerms)	(3 * ELEMENTS_IN_WEIGHTS_MATRIX(_numInputs, _numOutputs, _useBiasTerms))

#define ELEMENTS_IN_OUTPUT_VECTOR(_numOutputs)	(_numOutputs)
#define BYTES_IN_OUTPUT_VECTOR(_numOutputs)	(2 * ELEMENTS_IN_OUTPUT_VECTOR(_numOutputs))



/** Error Defines **/
#define MlpnnError_Good						(0)
#define MlpnnError_AlreadyRunning			(-1)
#define MlpnnError_InvalidNumInputs			(-2)
#define MlpnnError_InvalidNumOutputs		(-3)
#define MlpnnError_InputVectorOutOfBounds	(-4)
#define MlpnnError_WeightsMatrixOutOfBounds	(-5)
#define MlpnnError_OutputVectorOutOfBounds	(-6)
#define MlpnnError_InputOverlapsOutput		(-7)
#define MlpnnError_InputOverlapsWeights		(-8)
#define MlpnnError_OutputOverlapsWeigts		(-9)



/** Type Definitions **/
typedef int16_t		Q0_15;	// Signed, 0 integer bits, 15 fractional bits, Range: [-1, 1 - 2^-15]
typedef int32_t		Q8_15;	// Signed, 0 integer bits, 15 fractional bits, Range: [-256, 256 - 2^-15]
typedef int32_t		Q16_15;	// Signed, 16 integer bits, 15 fractional bits, Range: [-65536, 65535 - 2^-15]
typedef int64_t		Q48_15;	// Signed, 48 integer bits, 15 fractional bits, Range: [-2.81e14, 2.81e14]
typedef uint32_t	Q0_24;	// Unsigned, 0 integer bits, 24 fractional bits, Range: [0, 0.9999999403953552]
typedef int32_t		Q0_25;	// Signed, 0 integer bits, 25 fractional bits (actually uses 26 bits), Range: [-1, 0.9999999701976776]
typedef uint32_t	Q0_31;	// Unsigned, 0 integer bits, 31 fractional bits, Range: [0, 0.9999999995343387]
typedef uint64_t	Q0_40;	// Signed, 0 integer bits, 15 fractional bits, Range: [0, 0.9999999999990905]



/** External Function Declarations **/
int8_t check_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
void run_mlpnn_layer_without_check(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
int8_t run_mlpnn_layer(uint16_t numInputs, uint16_t numOutputs, uint8_t useBiasTerms, Q0_15 *inputVector, uint8_t *weightsMatrix, Q0_15 *outputVector);
void normalize_mlpnn_input_vector(Q0_31 *unnormalized_input_vector, uint16_t input_vector_length, Q0_15 *normalized_input_vector_out);



#ifdef __cplusplus
}
#endif