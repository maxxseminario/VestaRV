/* lab09_multicore_boot -- REFERENCE SOLUTION.
 *
 * PRIVATE -- do not commit. This completed solution moves to the course's
 * private repo before any vestarv commit.
 *
 * MULTI-CORE BRING-UP (TRM ch. 4.3 Boot and Tile Loading). Every hart boots
 * THE shared ROM; hart 0 is the only one running this image at reset, while
 * harts 1..17 park in WFI inside the bootrom. Hart 0 STAGES its TCM image into
 * shared RAM and LAUNCHES a subset of the tile harts through the bootrom
 * loader (course_lib/mp.h): write the loader row {SRC, LEN, ENTRY}, then set
 * the tile's CLINT msip. The ROM copies the image into the tile's TCM and
 * enters our tile shim, which calls mp_tile_main() below.
 *
 * Each launched tile writes a DONE word (0xD09E0000 + hartid) to its slot in
 * the shared course band, then parks. Hart 0 gathers with a BOUNDED wait per
 * hart, verifies each tile's msip level self-cleared (the ROM loader ISR
 * cleared it through the arbiter), and prints a per-hart status line. All
 * tiles reporting -> PASS.
 *
 * Shared words (course band 0x102A0-0x1037F, bootrom-zeroed at boot):
 *     DONE[h] = 0x102A0 + 4*h      (h = 1..NTILES)
 */
#include "course.h"

/* Stage/copy the whole small image (code + data + this file's statics). */
#define MP_IMAGE_WORDS  (1024u)
#include "mp.h"

#define NTILES      (5)                 /* launch harts 1..NTILES (a modest subset) */
#define DONE_BASE   (0x102A0u)          /* course band; DONE[h] = DONE_BASE + 4*h  */
#define DONE_MAGIC  (0xD09E0000u)       /* tile writes DONE_MAGIC + hartid          */
#define GATHER_BUDGET (200000)          /* bounded per-hart wait (covers ROM copy)  */

#define DONE(h)     MMR_32_BIT_MACRO(DONE_BASE + 4u*(h))

/* ======================================================================= */
/* The tile body: runs on each launched hart (sp/gp set by the SDK shim).    */
/* ======================================================================= */
void mp_tile_main(unsigned hartid)
{
    /* Report in: write my DONE word, then return (the shim marks PASS+parks).
     * A tile must NOT touch the console (UART0 is shared -- only hart 0 prints). */
    DONE(hartid) = DONE_MAGIC + hartid;
}

/* ======================================================================= */
/* Hart 0: stage, launch, gather, report.                                    */
/* ======================================================================= */
int main(void)
{
    unsigned h;
    int all_ok = 1;

    console_init();
    printf("lab09_multicore_boot: hart 0 launches %d tile harts (TRM 4.3)\n", NTILES);

    /* Stage my TCM image once; every tile is loaded from this copy. */
    mp_stage_image(MP_IMAGE_WORDS);

    for (h = 1; h <= NTILES; h++) {
        int budget;

        /* Before launch the tile is parked and its DONE slot is 0 (the bootrom
         * zeroes the mailbox range at boot -- write-before-read). */
        if (DONE(h) != 0) {
            printf("hart %u: FAIL (DONE nonzero before launch)\n", h);
            all_ok = 0;
            continue;
        }

        mp_launch_hart(h, MP_IMAGE_WORDS);        /* row + msip: wake tile h */

        /* Bounded wait for the tile to report in. */
        for (budget = GATHER_BUDGET;
             budget && (DONE(h) != DONE_MAGIC + h);
             budget--) { }

        if (DONE(h) != DONE_MAGIC + h) {
            printf("hart %u: FAIL (no DONE; got 0x%x)\n", h, DONE(h));
            all_ok = 0;
            continue;
        }
        /* The tile's ROM loader ISR must have cleared its own msip level. */
        if (mp_msip(h) != 0) {
            printf("hart %u: FAIL (msip level stuck)\n", h);
            all_ok = 0;
            continue;
        }
        printf("hart %u: DONE=0x%x, msip cleared -- OK\n", h, DONE(h));
    }

    if (all_ok) {
        printf("all %d tiles launched and reported -- PASS\n", NTILES);
        pass();
    } else {
        printf("FAIL\n");
        fail();
    }
    return 0; /* unreachable */
}
