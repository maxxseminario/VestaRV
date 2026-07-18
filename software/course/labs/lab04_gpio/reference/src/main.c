/* lab04_gpio -- REFERENCE SOLUTION.
 *
 * PRIVATE -- do not commit. This completed solution moves to the course's
 * private repo before any vestarv commit.
 *
 * GPIO at the register level (TRM ch. 11). We configure pin directions, drive
 * the output register through the set/clear/toggle convenience registers, and
 * flip a pin between GPIO (primary) mode and an alternate-function plane with
 * PxSEL / PxAFS. Every check is self-contained: we read back what we wrote
 * through the peripheral's OWN registers -- no external pin loopback, so the
 * result is deterministic in simulation and on silicon. Progress prints go to
 * the UART0 console through the SDK (console_init / printf); the pass gate is
 * pass()/fail().
 *
 * Port under test: GPIO1 (0x4100). Pin under test for the pinmux flip: P1.0,
 * whose alternate function 1 (AF1) is the TIMER0 compare output T0CMP0 -- the
 * worked example in TRM 11.3.
 */
#include "course.h"

/* ---- GPIO register offsets (from the peripheral base; TRM 11.5) ----------
 * chip.h gives the port BASE addresses (GPIO1_BASE = 0x4100); the register
 * offsets below are transcribed from sdk/generated/MemoryMap.h. All accesses
 * are 32-bit -- the peripheral bus is word-oriented. */
#define PxIN_OFF    (0)    /* input state      (RO)                       */
#define PxOUT_OFF   (4)    /* output drive     (RW)                       */
#define PxOUTS_OFF  (8)    /* write-1-to-SET   (reads PxOUT)              */
#define PxOUTC_OFF  (12)   /* write-1-to-CLEAR (reads ~PxOUT, TRM 11.2)  */
#define PxOUTT_OFF  (16)   /* write-1-to-TOGGLE(reads PxOUT)             */
#define PxDIR_OFF   (20)   /* direction: 1 = output                      */
#define PxSEL_OFF   (36)   /* 0 = GPIO mode, 1 = alternate-function mode */
#define PxAFS_OFF   (44)   /* AF select: 4-bit field per pin (low 3 used)*/

#define GPIO_R(base, off)       MMR_32_BIT_MACRO((base) + (off))
#define GPIO_W(base, off, val)  (MMR_32_BIT_MACRO((base) + (off)) = (uint32_t)(val))

/* PxAFS is nibble-packed: pin y's field is bits [4y+2 : 4y] (TRM 11.5.12). */
#define AFS_SHIFT(pin)      ((pin) * 4)
#define AFS_FIELD_MASK(pin) (0x7u << AFS_SHIFT(pin))
#define AFS_FIELD(pin, af)  (((uint32_t)(af) & 0x7u) << AFS_SHIFT(pin))

#define PORT   GPIO1_BASE   /* 0x4100 */
#define AF_PIN (0)          /* P1.0 */
#define AF_NUM (1)          /* AF1 = T0CMP0 (TRM 11.3 worked example) */

/* ======================================================================= */
/* PART 1 -- the three GPIO primitives.  (Reference: implemented.)         */
/* ======================================================================= */

/* Set the whole direction register: 1 = output, 0 = input (TRM 11.5.6). */
static void gpio_set_dir(uint32_t base, uint32_t dir_mask)
{
    GPIO_W(base, PxDIR_OFF, dir_mask);
}

/* Drive pins without a read-modify-write: PxOUTS sets the bits in set_mask,
   PxOUTC clears the bits in clr_mask. Writing 0 to a bit has no effect, so the
   two writes never race each other (TRM 11.2). */
static void gpio_drive(uint32_t base, uint32_t set_mask, uint32_t clr_mask)
{
    GPIO_W(base, PxOUTS_OFF, set_mask);
    GPIO_W(base, PxOUTC_OFF, clr_mask);
}

/* Put one pin into alternate-function mode on plane `af`: program the pin's
   PxAFS field (read-modify-write so the other pins' fields survive) and set the
   pin's PxSEL bit. The peripheral now governs the pad (TRM 11.3). */
static void gpio_pin_to_af(uint32_t base, unsigned pin, unsigned af)
{
    uint32_t afs = GPIO_R(base, PxAFS_OFF);
    afs = (afs & ~AFS_FIELD_MASK(pin)) | AFS_FIELD(pin, af);
    GPIO_W(base, PxAFS_OFF, afs);
    GPIO_W(base, PxSEL_OFF, GPIO_R(base, PxSEL_OFF) | (1u << pin));
}

/* Return a pin to GPIO (primary) mode: clear its PxSEL bit. */
static void gpio_pin_to_gpio(uint32_t base, unsigned pin)
{
    GPIO_W(base, PxSEL_OFF, GPIO_R(base, PxSEL_OFF) & ~(1u << pin));
}

/* ======================================================================= */
/* PART 2 -- self-checking harness (provided; register readback only).      */
/* ======================================================================= */

static int g_fails = 0;

static void check(const char *name, uint32_t got, uint32_t want)
{
    if (got == want) {
        printf("  [ ok ] %s = 0x%x\n", name, (unsigned)got);
    } else {
        printf("  [FAIL] %s = 0x%x (expected 0x%x)\n", name, (unsigned)got, (unsigned)want);
        g_fails++;
    }
}

int main(void)
{
    console_init();
    printf("lab04_gpio: GPIO + alternate functions at the register level\n");
    printf("port under test: GPIO1 @ 0x%x\n", (unsigned)PORT);

    /* --- Check 1: direction register read/write (TRM 11.1, 11.5.6) ------- */
    printf("check 1: pin directions (PxDIR)\n");
    gpio_set_dir(PORT, 0x55);
    check("PxDIR<-0x55", GPIO_R(PORT, PxDIR_OFF) & 0xFF, 0x55);
    gpio_set_dir(PORT, 0xAA);
    check("PxDIR<-0xAA", GPIO_R(PORT, PxDIR_OFF) & 0xFF, 0xAA);
    gpio_set_dir(PORT, 0xFF);   /* all outputs for the drive checks below */
    check("PxDIR<-0xFF", GPIO_R(PORT, PxDIR_OFF) & 0xFF, 0xFF);

    /* --- Check 2: drive/read-back through set/clear/toggle (TRM 11.2) ---- */
    printf("check 2: output drive (PxOUTS / PxOUTC / PxOUTT)\n");
    gpio_drive(PORT, 0x00, 0xFF);              /* clear everything first */
    check("PxOUT cleared", GPIO_R(PORT, PxOUT_OFF) & 0xFF, 0x00);
    gpio_drive(PORT, 0x0F, 0x00);              /* set low nibble */
    check("PxOUT after set 0x0F", GPIO_R(PORT, PxOUT_OFF) & 0xFF, 0x0F);
    gpio_drive(PORT, 0x00, 0x03);              /* clear two bits */
    check("PxOUT after clear 0x03", GPIO_R(PORT, PxOUT_OFF) & 0xFF, 0x0C);
    /* PxOUTC reads back the INVERTED output register (TRM 11.2). */
    check("PxOUTC reads ~PxOUT", GPIO_R(PORT, PxOUTC_OFF) & 0xFF, (~0x0Cu) & 0xFF);
    GPIO_W(PORT, PxOUTT_OFF, 0xFF);            /* toggle all eight pins */
    check("PxOUT after toggle 0xFF", GPIO_R(PORT, PxOUT_OFF) & 0xFF, (~0x0Cu) & 0xFF);

    /* --- Check 3: flip a pin GPIO <-> alternate function (TRM 11.3) ------ */
    printf("check 3: pinmux P1.%d <-> AF%d (PxSEL / PxAFS)\n", AF_PIN, AF_NUM);
    gpio_pin_to_gpio(PORT, AF_PIN);            /* known start: GPIO mode */
    check("PxSEL bit clear (GPIO mode)",
          (GPIO_R(PORT, PxSEL_OFF) >> AF_PIN) & 1u, 0);
    gpio_pin_to_af(PORT, AF_PIN, AF_NUM);      /* -> alternate function */
    check("PxSEL bit set (AF mode)",
          (GPIO_R(PORT, PxSEL_OFF) >> AF_PIN) & 1u, 1);
    check("PxAFS field selects AF",
          (GPIO_R(PORT, PxAFS_OFF) >> AFS_SHIFT(AF_PIN)) & 0x7u, AF_NUM);
    gpio_pin_to_gpio(PORT, AF_PIN);            /* -> back to GPIO */
    check("PxSEL bit clear again",
          (GPIO_R(PORT, PxSEL_OFF) >> AF_PIN) & 1u, 0);

    if (g_fails == 0) { printf("ALL CHECKS PASSED\n"); pass(); }
    else              { printf("%d CHECK(S) FAILED\n", g_fails); fail(); }
    return 0; /* unreachable */
}
