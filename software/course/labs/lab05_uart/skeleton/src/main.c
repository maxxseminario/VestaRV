/* lab05_uart -- STUDENT STARTING POINT.
 *
 * A polled UART1 transmit driver written from the registers up (TRM ch. 13).
 * UART0 stays the console (SDK console_init / printf) so you can watch progress;
 * UART1 is the device under test. You implement init (clock + baud + enable) and
 * a byte-transmit that follows the correct status-flag discipline. A self-check
 * transmits a known string and verifies the TX-complete flag (TCIF) sequences
 * 0 -> 1 -> 0 for every byte, all with bounded polls.
 *
 * As shipped this BUILDS but FAILS: uart1_init is empty (UART1 stays disabled)
 * and uart1_putc returns 0, so the first byte "times out" and main() calls
 * fail() (a0 = 0xDEADBEEF). The UART0 console still prints the progress trace,
 * showing the timeout -- the negative control. Implement the two functions to
 * make it PASS.
 */
#include "course.h"

/* ---- UART1 registers (base from chip.h; offsets shared by every UARTx) ----
 * The offsets are transcribed from sdk/generated/MemoryMap.h; all accesses are
 * 32-bit (the peripheral bus is word-oriented). */
#define U1CR   (UART1_BASE + 0)    /* control  (TRM 13.11.1)  */
#define U1SR   (UART1_BASE + 4)    /* status   (TRM 13.11.2)  */
#define U1BR   (UART1_BASE + 8)    /* baud div (TRM 13.11.3)  */
#define U1RX   (UART1_BASE + 12)   /* receive  (TRM 13.11.4)  */
#define U1TX   (UART1_BASE + 16)   /* transmit (TRM 13.11.5)  */

#define UEN_BIT   (0x20u)   /* UARTxCR bit5: UART enable                 (TRM 13.8)  */
#define TCIF_BIT  (0x01u)   /* UARTxSR bit0: transmit complete           (TRM 13.7)  */
#define TEIF_BIT  (0x02u)   /* UARTxSR bit1: TX register empty           (TRM 13.7)  */
#define TXBF_BIT  (0x40u)   /* UARTxSR bit6: transmit busy/pending       (TRM 13.7)  */

/* BR = 12 gives 115,385 baud from a 24 MHz SMCLK (baud = fSMCLK / (16*(BR+1)),
   TRM 13.4). Any modest divisor works; a big divisor slows the frame and would
   need a bigger poll budget. */
#define U1_BAUD_DIV  (12)
#define TX_BUDGET    (20000)   /* bounded -> a wedged UART trips the tb watchdog */

/* ======================================================================= */
/* PART 1 -- the UART1 driver.  IMPLEMENT THESE TWO.                        */
/* ======================================================================= */

/* Bring up UART1 at the register level. UART1 lives in the SMCLK clock domain,
   and the boot ROM parks SMCLK on the 32 kHz LFXT mid-boot -- so write
   SYS_CLK_CR = 0 (SMCLK -> HFXT) FIRST, or every frame takes ~10 ms and the
   bounded polls below expire (TRM 13.10, 15.1). Then set the baud divisor and
   enable the transmitter. */
static void uart1_init(void)
{
    /* TODO(lab05): three word writes, in order.
     *   1. MMR_32_BIT_MACRO(SYSCLKCR_ADDRESS) = 0;   -- SMCLK -> HFXT (do FIRST)
     *   2. MMR_32_BIT_MACRO(U1BR)  = U1_BAUD_DIV;    -- baud divisor
     *   3. MMR_32_BIT_MACRO(U1CR)  = UEN_BIT;        -- enable, no interrupts
     */
}

/* Transmit one byte with the correct flag discipline (TRM 13.7, 13.8):
 *   1. read UARTxSR once and discard it (settle any stale status),
 *   2. write the byte to UARTxTX to start the frame,
 *   3. poll (bounded) until TCIF = 1 -- the frame has fully shifted out,
 *   4. clear TCIF by writing a 1 to that bit,
 *   5. confirm (bounded) that TCIF read back 0 before returning.
 * Returns the poll count on success (>= 1), or 0 if TCIF never set / never
 * cleared inside the budget (a bounded failure, never an infinite spin). */
static int uart1_putc(char c)
{
    /* TODO(lab05): follow the five steps above.
     *   - Start the frame:   MMR_32_BIT_MACRO(U1TX) = (uint8_t)c;
     *   - Wait complete:     for (b = TX_BUDGET; b && !(MMR_32_BIT_MACRO(U1SR) & TCIF_BIT); b--) {}
     *                        if (b == 0) return 0;
     *   - Clear TCIF:        MMR_32_BIT_MACRO(U1SR) = TCIF_BIT;
     *   - Return a nonzero poll count on success.
     */
    (void)c;
    return 0;
}

/* ======================================================================= */
/* PART 2 -- self-checking harness (provided; UART0 console + UART1 flags).  */
/* ======================================================================= */

static const char TESTMSG[] = "VestaRV UART1 register-level driver\r\n";

int main(void)
{
    int i, bytes_ok = 0, want;
    uint32_t sr;

    console_init();                                   /* UART0 console (SDK) */
    printf("lab05_uart: polled UART1 driver from registers\n");
    printf("UART1 @ 0x%x, BR=%d (~115200 baud from 24 MHz SMCLK)\n",
           (unsigned)UART1_BASE, U1_BAUD_DIV);

    uart1_init();
    printf("UART1 initialized (SYS_CLK_CR=0, BR set, EN=1)\n");

    /* Flag-sequence demonstration on the first byte, traced over UART0. */
    sr = MMR_32_BIT_MACRO(U1SR);
    printf("pre-TX  UART1SR=0x%x (TCIF=%d)\n", (unsigned)sr, (int)(sr & TCIF_BIT ? 1 : 0));

    /* Transmit the known string; every byte must complete (TCIF 0->1->0). */
    want = (int)(sizeof(TESTMSG) - 1);
    for (i = 0; i < want; i++) {
        int polls = uart1_putc(TESTMSG[i]);
        if (polls > 0) {
            bytes_ok++;
        } else {
            printf("  byte %d ('%c') TIMED OUT waiting on TCIF\n", i, TESTMSG[i]);
            break;                                    /* bound the failure path */
        }
    }

    sr = MMR_32_BIT_MACRO(U1SR);
    printf("post-TX UART1SR=0x%x (TCIF=%d)\n", (unsigned)sr, (int)(sr & TCIF_BIT ? 1 : 0));
    printf("bytes transmitted OK: %d of %d\n", bytes_ok, want);

    if (bytes_ok == want) { printf("PASS\n"); pass(); }
    else                  { printf("FAIL\n"); fail(); }
    return 0; /* unreachable */
}
