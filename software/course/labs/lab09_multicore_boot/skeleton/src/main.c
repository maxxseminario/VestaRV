/* lab09_multicore_boot -- STUDENT STARTING POINT.
 *
 * MULTI-CORE BRING-UP (TRM ch. 4.3 Boot and Tile Loading). Every hart boots
 * THE shared ROM; hart 0 is the only one running this image at reset, while
 * harts 1..17 park in WFI inside the bootrom. You make hart 0 STAGE its TCM
 * image into shared RAM and LAUNCH a subset of the tile harts through the
 * bootrom loader (course_lib/mp.h): write the loader row {SRC, LEN, ENTRY},
 * then set the tile's CLINT msip. The ROM copies the image into the tile's TCM
 * and enters the SDK tile shim, which calls mp_tile_main() below.
 *
 * Each launched tile must write a DONE word (0xD09E0000 + hartid) to its slot
 * in the shared course band, then return (the shim marks PASS and parks it).
 * Hart 0 gathers with a BOUNDED wait per hart, verifies each tile's msip level
 * self-cleared, and prints a per-hart status line.
 *
 * As shipped this BUILDS but FAILS: mp_tile_main is empty and the launch/gather
 * loop is stubbed, so no tile is ever launched and every DONE slot stays 0.
 * Hart 0 reports every hart FAIL and calls fail() (a0 = 0xDEADBEEF). Implement
 * the two TODO regions to make it PASS.
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
    /* TODO(lab09): report in -- write my DONE word, then return.
     *   DONE(hartid) = DONE_MAGIC + hartid;
     * A tile must NOT touch the console (UART0 is shared -- only hart 0 prints). */
    (void)hartid;
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

        if (DONE(h) != 0) {
            printf("hart %u: FAIL (DONE nonzero before launch)\n", h);
            all_ok = 0;
            continue;
        }

        /* TODO(lab09): launch tile h, then bounded-wait for its DONE.
         *   mp_launch_hart(h, MP_IMAGE_WORDS);       -- row + msip
         *   for (budget = GATHER_BUDGET;
         *        budget && (DONE(h) != DONE_MAGIC + h);
         *        budget--) { }
         */
        (void)budget;

        if (DONE(h) != DONE_MAGIC + h) {
            printf("hart %u: FAIL (no DONE; got 0x%x)\n", h, DONE(h));
            all_ok = 0;
            continue;
        }
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
