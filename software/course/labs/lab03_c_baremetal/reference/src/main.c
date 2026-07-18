/* lab03_c_baremetal -- REFERENCE SOLUTION.
 *
 * PRIVATE -- do not commit. This completed solution moves to the course's
 * private repo before any vestarv commit.
 *
 * Bare-metal C + memory-mapped I/O. We bring up UART0 at the register level and
 * transmit bytes by hand (poll the TX-complete flag, write the TX register),
 * then walk the ROM/TCM address-space boundaries and read them back with a
 * volatile load. The SDK console API (console_init / uart_putc / printf) is NOT
 * used -- only the register map from chip.h and the pass()/fail() checker.
 */
#include "course.h"

/* ======================================================================= */
/* PART 1 -- bare-metal MMIO primitives (register level).                  */
/* ======================================================================= */

#define UART_CR_UEN    (0x20u)   /* UART0CR bit5: UART enable       (TRM 13.6, 22.5) */
#define UART_SR_TCIF   (0x01u)   /* UART0SR bit0: TX-complete flag  (TRM 13.7)       */
#define TX_POLL_BUDGET (20000)   /* bounded -> a wedged UART trips the tb watchdog   */

/* Bring up the UART0 console directly through its registers. */
static void uart_init(void)
{
    /* The bootrom parks SMCLK on the 32 kHz LFXT mid-boot; move it back to HFXT
       (SYS_CLK_CR = 0) first, or every frame takes ~10 ms and blows the poll
       budgets. This is the teachable MMIO gotcha. (TRM 15.1, 13.10) */
    MMR_32_BIT_MACRO(SYSCLKCR_ADDRESS) = 0;
    MMR_32_BIT_MACRO(UART0BR_ADDRESS)  = 1;            /* baud divisor  (TRM 13.4) */
    MMR_32_BIT_MACRO(UART0CR_ADDRESS)  = UART_CR_UEN;  /* enable, no interrupts    */
}

/* Transmit one byte: write TX, poll TCIF until set, clear it. The peripheral
   bus is WORD-oriented -- 32-bit accesses only (byte loads return garbage). */
static void put_char(char c)
{
    int budget;
    MMR_32_BIT_MACRO(UART0TX_ADDRESS) = (uint8_t)c;    /* start the frame */
    for (budget = TX_POLL_BUDGET;
         budget && !(MMR_32_BIT_MACRO(UART0SR_ADDRESS) & UART_SR_TCIF);
         budget--) { }
    MMR_32_BIT_MACRO(UART0SR_ADDRESS) = UART_SR_TCIF;  /* clear the pulse */
}

/* Memory-map explorer primitive: read a 32-bit word from any address. */
static uint32_t load_word(uint32_t addr)
{
    return *(volatile uint32_t *)addr;
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
