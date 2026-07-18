/* lab11_npu -- STUDENT STARTING POINT.
 *
THE NPU (TRM ch. 16). A fixed-point multiply-accumulate accelerator: it reads
 * an input vector and a weight vector from the shared NPU staging RAM (0xC000),
 * computes each neuron's dot product OUT[n] = sum_i X[i]*W[i], and writes the
 * result(s) back into the staging RAM. Here: 2 inputs, 1 neuron, no bias, no
 * activation (a pure dot product).
 *
 * FIXED-POINT FORMATS (MCU generics, TRM 16):
 *     inputs  X  = sfixed(0,-24)  = Q0.24   (raw = value * 2^24, range [-1,1))
 *     weights W  = sfixed(7,-24)  = Q7.24   (raw = value * 2^24)
 *     outputs OUT= sfixed(7,-24)  = Q7.24
 * All expected values are precomputed HOST-SIDE as constants below -- the chip's
 * hardware divide has a result hazard, so firmware never divides by a variable.
 *
 *   X0 = 0.5  = 0x00800000     W0 = 2.0 = 0x02000000     X0*W0 = 1.00
 *   X1 = 0.25 = 0x00400000     W1 = 3.0 = 0x03000000     X1*W1 = 0.75
 *   OUT = 1.00 + 0.75 = 1.75 = 0x01C00000
 *
 * STAGING-RAM LAYOUT (IVSAR/WVSAR/OVSAR are WORD indices: addr = 0xC000+4*idx):
 *     X0 @0xC100 (word 0x40)   X1 @0xC104 (0x41)
 *     W0 @0xC108 (word 0x42)   W1 @0xC10C (0x43)
 *     OUT @0xC110 (word 0x44)
 *
 * CONTRACT: never touch 0xC000-0xFFFF while a THINK may be active -- the in-NPU
 * port mux owns the staging RAM during the run. Poll NPUCR bit 16 (THINK) back
 * to 0 before reading the output.
 *
 * As shipped this BUILDS but FAILS: npu_configure and npu_think are stubbed, so
 * the accelerator is never pointed at the vectors and never started -- the
 * output slot stays 0 and the product check fails (a0 = 0xDEADBEEF). Implement
 * the two functions to make it PASS.
 *
 * Hart-0 only; no shared course-band words.
 */
#include "course.h"

/* ---- NPU registers (base from chip.h; offsets from MemoryMap.h) ----------- */
#define NPUCR   (NPU_BASE + 0)      /* control/status */
#define NPUIVSAR (NPU_BASE + 4)     /* input  vector start addr (word index) */
#define NPUWVSAR (NPU_BASE + 8)     /* weight vector start addr (word index) */
#define NPUOVSAR (NPU_BASE + 12)    /* output vector start addr (word index) */

/* NPUCR fields (TRM 16): [7:0]=NN (#neurons-1), [15:8]=NI (#inputs-1),
 * bit16=THINK (start/busy), bit17=AEN (activation), bit18=BEN (bias). */
#define NPU_THINK   (1u << 16)
#define NPU_NI(n)   (((n) - 1u) << 8)   /* n inputs  */
#define NPU_NN(n)   (((n) - 1u) << 0)   /* n neurons */

/* staging RAM */
#define STAGE       (0xC000u)
#define X0_ADDR     (0xC100u)
#define X1_ADDR     (0xC104u)
#define W0_ADDR     (0xC108u)
#define W1_ADDR     (0xC10Cu)
#define OUT_ADDR    (0xC110u)
#define IV_WORD     (0x40u)            /* (0xC100-0xC000)/4 */
#define WV_WORD     (0x42u)            /* (0xC108-0xC000)/4 */
#define OV_WORD     (0x44u)            /* (0xC110-0xC000)/4 */

/* host-computed constants (Q0.24 inputs, Q7.24 weights/output) */
#define X0_VAL      (0x00800000u)      /* 0.5  */
#define X1_VAL      (0x00400000u)      /* 0.25 */
#define W0_VAL      (0x02000000u)      /* 2.0  */
#define W1_VAL      (0x03000000u)      /* 3.0  */
#define OUT_EXPECT  (0x01C00000u)      /* 1.75 = 0.5*2.0 + 0.25*3.0 */

#define THINK_BUDGET (20000)

#define R(a)  MMR_32_BIT_MACRO(a)

/* ======================================================================= */
/* PART 1 -- the two functions you implement.  (Reference: implemented.)      */
/* ======================================================================= */

/* Point the NPU at the staged vectors: IVSAR->inputs, WVSAR->weights,
 * OVSAR->output (all WORD indices into the staging RAM). Read each back (the
 * NPU register read is bridged/registered) to confirm the write landed. */
static int npu_configure(void)
{
    /* TODO(lab11): point the NPU at the staged vectors and read back.
     *   R(NPUIVSAR) = IV_WORD;  if (R(NPUIVSAR) != IV_WORD) return 1;
     *   R(NPUWVSAR) = WV_WORD;  if (R(NPUWVSAR) != WV_WORD) return 1;
     *   R(NPUOVSAR) = OV_WORD;  if (R(NPUOVSAR) != OV_WORD) return 1;
     */
    return 0;
}

/* Start the accelerator and poll THINK back to 0. NPUCR = THINK | NI(2) | NN(1):
 * 2 inputs, 1 neuron, no bias/activation. THINK reads back at bit 16 while busy
 * (the run is only ~10 MCLK). Returns 0 on completion, 1 on timeout. */
static int npu_think(void)
{
    /* TODO(lab11): start the accelerator and poll THINK back to 0.
     *   int budget;
     *   R(NPUCR) = NPU_THINK | NPU_NI(2) | NPU_NN(1);
     *   for (budget = THINK_BUDGET; budget; budget--)
     *       if ((R(NPUCR) & NPU_THINK) == 0) return 0;
     *   return 1;
     */
    return 0;
}

/* ======================================================================= */
/* PART 2 -- staging + verification harness (provided).                      */
/* ======================================================================= */

int main(void)
{
    console_init();
    printf("lab11_npu: fixed-point dot product OUT = X0*W0 + X1*W1 (TRM 16)\n");

    /* Reset proof: NPUCR and IVSAR read 0 out of reset. */
    if (R(NPUCR) != 0 || R(NPUIVSAR) != 0) {
        printf("FAIL (NPU not in reset state)\n"); fail();
    }

    /* Stage the input + weight vectors; clear the output slot. */
    R(X0_ADDR) = X0_VAL;
    R(X1_ADDR) = X1_VAL;
    R(W0_ADDR) = W0_VAL;
    R(W1_ADDR) = W1_VAL;
    R(OUT_ADDR) = 0;

    if (npu_configure()) { printf("FAIL (IVSAR/WVSAR/OVSAR did not stick)\n"); fail(); }
    if (npu_think())     { printf("FAIL (THINK never completed)\n"); fail(); }

    /* THINK cleared -> safe to read the staging RAM again. */
    uint32_t out = R(OUT_ADDR);
    printf("OUT = 0x%x (want 0x%x)\n", out, OUT_EXPECT);

    if (out == OUT_EXPECT) {
        printf("PASS\n"); pass();
    } else {
        printf("FAIL (wrong product)\n"); fail();
    }
    return 0; /* unreachable */
}
