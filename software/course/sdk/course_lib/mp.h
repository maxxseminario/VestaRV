/* mp.h -- VestaRV course SDK multi-core layer (student API).
 *
 * A student-clean C wrapper over the M12 single-ROM boot contract
 * (verification/env/p/mp_boot.h). Since M12 nothing preloads the tile harts:
 * harts 1..17 boot the SHARED ROM, park in WFI, and wake only when hart 0
 * writes their loader mailbox row and sets their CLINT software interrupt
 * (msip). The ROM's msip handler then clears the level, COPIES the staged
 * image into the tile's private TCM at 0x8000, and enters ENTRY with
 * sp = 0xBFFC.
 *
 * WHAT A LAB WRITES
 * -----------------
 * A multi-core lab provides ONE tile entry function, exactly parallel to how a
 * single-core lab provides main():
 *
 *     void mp_tile_main(unsigned hartid);   // the code every launched tile runs
 *
 * and, on hart 0, stages the image once and launches the tiles it wants:
 *
 *     mp_stage_image(MP_IMAGE_WORDS);              // snapshot my TCM -> 0x18000
 *     for (h = 1; h <= NTILES; h++)
 *         mp_launch_hart(h, MP_IMAGE_WORDS);       // row + msip: wake tile h
 *     ... bounded-wait on the lab's own shared DONE words ...
 *
 * Every tile runs the SAME staged image at the SAME linked addresses (the
 * launch copies hart 0's TCM verbatim), so mp_tile_main and every symbol it
 * references resolve identically on the tiles. The SDK supplies the tile ENTRY:
 * a tiny assembly shim (_mp_tile_entry, the tile's crt0) that establishes the
 * ABI the loader does NOT -- it sets sp and gp, reads mhartid, and calls
 * mp_tile_main(mhartid). If mp_tile_main returns, the shim marks PASS
 * (a0 = 0xCAFEBABE, which riscv_tb latches for harts 1-3) and parks.
 *
 * STAGING SIZE. mp_stage_image / mp_launch_hart copy `words` 32-bit words of
 * the image (from 0x8000). Stage enough to cover the whole program AND the
 * static data mp_tile_main touches; MP_IMAGE_WORDS below (1024 words = 4 KB) is
 * a safe default for a course lab. The bootrom serializes the per-tile copies
 * through the arbiter, so keep `words` modest and the tile count small to stay
 * inside the tb's 100 ms watchdog (and reasonable wall-clock sim time).
 *
 * SHARED WORDS. Tiles and hart 0 communicate ONLY through the shared window.
 * Course labs use the reserved course band 0x102A0-0x1037F (see
 * software/course/README.md); the bootrom zeroes 0x10000-0x107FF at every boot,
 * so a DONE/counter word in the band starts at 0 (write-before-read holds).
 * All accesses are 32-bit (word-oriented bus).
 *
 * This header is ADDITIVE and self-contained: it does not change course.mk,
 * course.ld, crt0.S, or any other lab. A lab opts in simply by #include "mp.h"
 * and defining mp_tile_main.
 */
#ifndef COURSE_MP_H
#define COURSE_MP_H

#include <stdint.h>
#include "chip.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ---- M12 bootrom loader contract (mp_boot.h, transcribed) ---------------- */
#define MP_STAGE_BASE     (0x18000u)          /* shared bulk RAM bank 2      */
#define MP_BOOT_MB_BASE   (0x10500u)          /* loader row = base + 0x10*h  */
#define MP_CLINT_MSIP     (0x5000u)           /* msip[h] = base + 4*h        */

/* Default image copy size (words). 4 KB covers a small course lab's code,
 * rodata and the static data its tile body touches. Override before including
 * mp.h if a lab needs more. */
#ifndef MP_IMAGE_WORDS
#define MP_IMAGE_WORDS    (1024u)
#endif

/* ---- the tile entry a multi-core lab MUST define -------------------------
 * Runs on each launched tile hart with sp/gp already established by the SDK
 * shim; `hartid` is the tile's mhartid. Communicate with hart 0 only through
 * shared-window words. Returning marks the tile PASS and parks it. */
void mp_tile_main(unsigned hartid);

/* the SDK-provided tile crt0 shim (defined in the asm block below) */
extern void _mp_tile_entry(void);

/* Snapshot this hart's TCM image [0x8000, 0x8000 + words*4) into the shared
 * staging RAM at 0x18000. Call ONCE, on hart 0, before any mp_launch_hart:
 * every tile is loaded from this one staged copy. */
static inline void mp_stage_image(unsigned words) {
    volatile uint32_t *src = (volatile uint32_t *)0x8000u;
    volatile uint32_t *dst = (volatile uint32_t *)MP_STAGE_BASE;
    unsigned i;
    for (i = 0; i < words; i++) dst[i] = src[i];
}

/* Wake tile hart h: write its loader row {SRC, LEN, ENTRY} FIRST, then ignite
 * its msip. ENTRY is always the SDK tile shim, which calls mp_tile_main. The
 * bootrom copies `words` words of the staged image into the tile's TCM and
 * enters ENTRY with sp = 0xBFFC. Call after mp_stage_image. */
static inline void mp_launch_hart(unsigned h, unsigned words) {
    volatile uint32_t *row = (volatile uint32_t *)(MP_BOOT_MB_BASE + 0x10u * h);
    row[0] = MP_STAGE_BASE;                          /* SRC   */
    row[1] = words;                                  /* LEN   */
    row[2] = (uint32_t)(uintptr_t)&_mp_tile_entry;   /* ENTRY */
    MMR_32_BIT_MACRO(MP_CLINT_MSIP + 4u * h) = 1u;   /* ignite msip[h]        */
}

/* Read tile hart h's msip level back (0 once the ROM ISR has cleared it). */
static inline uint32_t mp_msip(unsigned h) {
    return MMR_32_BIT_MACRO(MP_CLINT_MSIP + 4u * h);
}

/* ---- the tile crt0 shim (the ENTRY every launch points at) ---------------
 * The loader ABI leaves ONLY sp defined (0xBFFC). This shim, staged with the
 * image, establishes the rest of the C ABI on the tile: stack pointer at the
 * test convention 0xBFF0, gp for gp-relative access, mhartid in a0, then calls
 * mp_tile_main. The build march is rv32ima (no zicsr), so the mhartid read is
 * wrapped in .option arch,+zicsr. Kept alive by mp_launch_hart's reference. */
__asm__(
    ".text\n"
    ".p2align 2\n"
    ".globl _mp_tile_entry\n"
    "_mp_tile_entry:\n"
    "  li   sp, 0xBFF0\n"                 /* private TCM top (IRQ_SV contract) */
    "  .option push\n"
    "  .option norelax\n"
    "  la   gp, __global_pointer$\n"      /* gp before any gp-relative access  */
    "  .option pop\n"
    "  .option push\n"
    "  .option arch, +zicsr\n"
    "  csrr a0, mhartid\n"                /* arg0 = my hartid                  */
    "  .option pop\n"
    "  call mp_tile_main\n"
    "  li   a0, 0xCAFEBABE\n"             /* returned: inline PASS (a0_1/2/3)  */
    "1:\n"
    "  j    1b\n"
);

#ifdef __cplusplus
}
#endif

#endif /* COURSE_MP_H */
