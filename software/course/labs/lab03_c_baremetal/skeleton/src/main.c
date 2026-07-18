/* lab03_c_baremetal -- STUDENT STARTING POINT.
 *
 * Bare-metal C + memory-mapped I/O. You will bring up UART0 at the register
 * level and transmit bytes by hand, then read words at the ROM/TCM address-
 * space boundaries. The SDK console API (console_init / uart_putc / printf) is
 * OFF-LIMITS in this lab -- talk to the registers directly through the
 * MMR_32_BIT_MACRO accessor and the register-map constants from chip.h. The
 * ONLY SDK helpers you may call are pass()/fail() (the checker).
 *
 * As shipped this BUILDS but FAILS: load_word() returns 0, so the marker check
 * mismatches and main() calls fail() (a0 = 0xDEADBEEF), and nothing prints
 * (put_char is empty). Complete the three PART 1 functions to make it PASS
 * with visible UART output.
 */
#include "course.h"

/* ======================================================================= */
/* PART 1 -- bare-metal MMIO primitives.  IMPLEMENT THESE THREE.            */
/* ======================================================================= */

#define UART_CR_UEN    (0x20u)   /* UART0CR bit5: UART enable       (TRM 13.6, 22.5) */
#define UART_SR_TCIF   (0x01u)   /* UART0SR bit0: TX-complete flag  (TRM 13.7)       */
#define TX_POLL_BUDGET (20000)   /* bounded -> a wedged UART trips the tb watchdog   */

/* Bring up the UART0 console directly through its registers. */
static void uart_init(void)
{
    /* TODO(lab03): three word writes, in order.
     *   1. SYS_CLK_CR (SYSCLKCR_ADDRESS) = 0  -- the bootrom leaves SMCLK on the
     *      32 kHz LFXT; move it to HFXT or every frame takes ~10 ms. (TRM 15.1)
     *   2. UART0BR_ADDRESS = 1                -- baud divisor. (TRM 13.4)
     *   3. UART0CR_ADDRESS = UART_CR_UEN      -- enable, no interrupts.
     * Use MMR_32_BIT_MACRO(addr) = value for each (the bus is word-oriented).
     */
}

/* Transmit one byte: write TX, poll TCIF until set, then clear it. */
static void put_char(char c)
{
    /* TODO(lab03):
     *   1. Write the byte to UART0TX_ADDRESS.
     *   2. Spin (bounded by TX_POLL_BUDGET) until UART0SR_ADDRESS has TCIF set.
     *   3. Clear TCIF by writing UART_SR_TCIF back to UART0SR_ADDRESS.
     * All accesses are 32-bit (MMR_32_BIT_MACRO); byte loads read garbage.
     */
    (void)c;
}

/* Memory-map explorer primitive: read a 32-bit word from any address. */
static uint32_t load_word(uint32_t addr)
{
    /* TODO(lab03): return the 32-bit word at `addr` with a VOLATILE load:
     *   return *(volatile uint32_t *)addr;
     */
    (void)addr;
    return 0;
}

/* ======================================================================= */
/* PART 2 -- output helpers + explorer/checker (provided; uses put_char).   */
/* ======================================================================= */

static void put_str(const char *s) { while (*s) put_char(*s++); }

static void put_hex32(uint32_t v)
{
    static const char hx[] = "0123456789abcdef";
    int i;
    put_str("0x");
    for (i = 28; i >= 0; i -= 4) put_char(hx[(v >> i) & 0xFu]);
}

/* Region boundaries (TRM ch 3 Address Space; periph.x RomSize/RamSize). */
#define ROM_BASE 0x00000000u     /* shared boot ROM base (reset vector) */
#define ROM_TOP  0x00003FFCu     /* last word of the 16 KiB boot ROM    */
#define TCM_BASE 0x00008000u     /* private per-hart TCM (RAM) base      */
#define TCM_TOP  0x0000BFFCu     /* last word of the 16 KiB TCM          */

/* Deterministic probe words in .rodata (TCM). load_word() must read them back
   exactly; SIGNATURE is their running XOR -- an image-stable pass check. */
static const uint32_t MARKERS[4] = {
    0xDEADC0DEu, 0x0BADF00Du, 0xFEEDFACEu, 0xABCD1234u
};
#define SIGNATURE (0xDEADC0DEu ^ 0x0BADF00Du ^ 0xFEEDFACEu ^ 0xABCD1234u)

static void explore(uint32_t addr, const char *label)
{
    put_str("  ["); put_hex32(addr); put_str("] = ");
    put_hex32(load_word(addr));
    put_str("   "); put_str(label); put_char('\n');
}

int main(void)
{
    int i, ok = 1;
    uint32_t sig = 0;

    uart_init();

    put_str("lab03_c_baremetal: bare-metal MMIO + memory-map explorer\n");
    put_str("memory-map probe (address = word):\n");
    explore(ROM_BASE, "boot ROM base (reset vector word)");
    explore(ROM_TOP,  "boot ROM top word");
    explore(TCM_BASE, "TCM base (IVT slot 0)");
    explore((uint32_t)(uintptr_t)&main, "a code word from main() in TCM");

    /* Verify the explorer's load_word against direct C reads of the markers. */
    for (i = 0; i < 4; i++) {
        uint32_t got  = load_word((uint32_t)(uintptr_t)&MARKERS[i]);
        uint32_t want = MARKERS[i];
        sig ^= got;
        put_str("  marker "); put_char((char)('0' + i)); put_str(" = ");
        put_hex32(got);
        if (got != want) { put_str("   MISMATCH"); ok = 0; }
        else               put_str("   ok");
        put_char('\n');
    }

    put_str("signature="); put_hex32(sig);
    put_str(" expected=");  put_hex32(SIGNATURE); put_char('\n');

    if (ok && sig == SIGNATURE) { put_str("PASS\n"); pass(); }
    else                        { put_str("FAIL\n"); fail(); }
    return 0; /* unreachable */
}
