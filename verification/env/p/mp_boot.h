// See LICENSE for license details.
//
// mp_boot.h  (M12 single-ROM boot)
// -----------------------------------------------------------------------------
// Hart-0-side helpers for launching the tile harts (1-3) through the M12
// bootrom loader. Since M12 nothing preloads the tiles' private TCMs: they
// boot from THE shared ROM, park in WFI, and wake only when hart 0 writes
// their loader mailbox row and sets their CLINT msip. The bootrom's msip ISR
// (ROM-resident) then clears the msip level, copies SRC..SRC+LEN*4 into the
// tile's TCM at 0x8000, and enters ENTRY with sp = 0xBFFC.
//
// Loader mailbox row (bootrom contract, zeroed by the bootrom at boot):
//     MP_BOOT_MB_BASE + 0x10*h + 0x0 = SRC   (word-aligned shared-space address)
//     MP_BOOT_MB_BASE + 0x10*h + 0x4 = LEN   (words to copy to TCM; 0 = no copy)
//     MP_BOOT_MB_BASE + 0x10*h + 0x8 = ENTRY (PC the tile enters with)
//
// The canonical use (every hart runs the SAME image at the SAME addresses,
// exactly like the pre-M12 preload):
//     MP_STAGE_IMAGE(4096)             // hart 0: TCM image -> 0x18000 (once)
//     MP_LAUNCH_HART(1, tile_entry, 4096)
//     ...bounded-wait on the test's own DONE mailbox...
//
// MP_STAGE_BASE is shared bulk RAM bank 2 (0x18000-0x1BFFF) — clear of the
// whole test/mailbox ledger at 0x100xx-0x106xx (loader rows 0x10500-0x1061F at
// N=18, still inside the bootrom zero range). A full-TCM stage/copy (4096
// words) is the uniform safe choice: it carries the IVT, the ISR bank
// (0xB200-0xBAFF) and the 0xBB00 parking word, so tile-side interrupts work
// exactly as they did with the preload.
//
// Both macros clobber t0-t3 only. Loads/stores are all through the arbiter.
// -----------------------------------------------------------------------------

#ifndef _ENV_MP_BOOT_H
#define _ENV_MP_BOOT_H

// Hart count (Argus A3). Default 5 since CPR8/R7 = Castalia-Penta, the shipped
// chip: hart 0 is the always-on soft orchestrator and harts 1-4 are the
// hardened channel tiles. (It was 4 until 2026-08-15; config/castalia4.json
// still builds that shape, and its image set carries -DNHARTS=4 explicitly.)
// The Argus image build passes -DNHARTS=18. sh tests derive their tile-launch
// loop, gather bound, expected totals, and (NHARTS-sized) DONE-array layout
// from this ONE knob so a single source serves every config at its own hart
// count. NOTE build_mp_images.sh ALWAYS passes -DNHARTS explicitly, so this
// fallback is only reached by a hand build.
#ifndef NHARTS
#define NHARTS 5
#endif

#define MP_STAGE_BASE    0x18000
// N-agnostic loader-row base (Argus A3): relocated 0x10400 -> 0x10500 so the
// rows {SRC,LEN,ENTRY} at 0x10*h (up to 0x10500+0x10*(N-1); block 0x10500-0x1061F
// at N=18) clear the sh-test scratch below 0x10500 and stay inside the bootrom
// zero range (ends 0x10800). MUST stay equal to BOOT_MB_BASE in
// software/bootrom_mp/src/start.S.
#define MP_BOOT_MB_BASE  0x10500
#define MP_CLINT_MSIP    0x5000

// Stage this hart's TCM image [0x8000, 0x8000 + words*4) into MP_STAGE_BASE.
// Run ONCE before any MP_LAUNCH_HART (all tiles share the staged copy).
#define MP_STAGE_IMAGE(words)                                           \
    li   t0, 0x8000;                                                    \
    li   t1, MP_STAGE_BASE;                                             \
    li   t2, (words);                                                   \
41641:                                                                  \
    lw   t3, 0(t0);                                                     \
    sw   t3, 0(t1);                                                     \
    addi t0, t0, 4;                                                     \
    addi t1, t1, 4;                                                     \
    addi t2, t2, -1;                                                    \
    bnez t2, 41641b

// Write hart h's loader row (SRC = the staged image, LEN = words,
// ENTRY = entry_label at its linked TCM address), THEN ignite via msip.
#define MP_LAUNCH_HART(h, entry_label, words)                           \
    li   t0, MP_BOOT_MB_BASE + 0x10*(h);                                \
    li   t1, MP_STAGE_BASE;                                             \
    sw   t1, 0(t0);                                                     \
    li   t1, (words);                                                   \
    sw   t1, 4(t0);                                                     \
    la   t1, entry_label;                                               \
    sw   t1, 8(t0);                                                     \
    li   t0, MP_CLINT_MSIP + 4*(h);                                     \
    li   t1, 1;                                                         \
    sw   t1, 0(t0)

// Launch ALL tile harts 1..NHARTS-1 into entry_label with the staged image
// (register-indexed form of MP_LAUNCH_HART in a loop — the N-agnostic launcher
// for the sh suite). Run MP_STAGE_IMAGE first. Clobbers t0-t4. entry_label is
// resolved once (all tiles share the staged copy + entry). Use at most once per
// test (the local label 90001 is file-unique-by-single-use).
#define MP_LAUNCH_ALL(entry_label, words)                              \
    la   t4, entry_label;              /* ENTRY (same for all tiles) */\
    li   t3, 1;                        /* h = 1 */                     \
90001:                                                                 \
    slli t0, t3, 4;                    /* MP_BOOT_MB_BASE + 0x10*h */  \
    li   t1, MP_BOOT_MB_BASE;                                          \
    add  t0, t0, t1;                                                   \
    li   t1, MP_STAGE_BASE;                                            \
    sw   t1, 0(t0);                    /* SRC */                       \
    li   t1, (words);                                                  \
    sw   t1, 4(t0);                    /* LEN */                       \
    sw   t4, 8(t0);                    /* ENTRY */                     \
    slli t0, t3, 2;                    /* MP_CLINT_MSIP + 4*h */       \
    li   t1, MP_CLINT_MSIP;                                            \
    add  t0, t0, t1;                                                   \
    li   t1, 1;                                                        \
    sw   t1, 0(t0);                    /* ignite msip[h] */            \
    addi t3, t3, 1;                                                    \
    li   t1, NHARTS;                                                   \
    bltu t3, t1, 90001b

#endif
