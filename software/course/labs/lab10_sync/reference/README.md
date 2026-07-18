# lab10_sync -- REFERENCE SOLUTION (+ nobackoff negative control)

**PRIVATE -- do not commit.** `reference/` and `nobackoff/` both move to the
course's private repo before any vestarv commit. Only `../skeleton/` ships
publicly.

Synchronization (module M9, TRM ch. 4.4 / 7.9 / 20). Six harts (hart 0 + tiles
1..5) each do 32 non-atomic RMW increments of a shared counter under (a) an LR/SC
spinlock with hartid-scaled backoff and (b) the HW mutex bank. Correct exclusion
-> each counter ends EXACTLY 192. Student implements four lock primitives.

- `reference/` -- complete; PASSES `192/192` (~16 s).
- `../skeleton/` -- primitives stubbed -> lost updates -> FAILS `118/192` (~13 s).
- `nobackoff/` -- `#include`s the reference source with `-DNO_BACKOFF`.

## FINDING: nobackoff does NOT livelock in the behavioral sim

`nobackoff/` was intended as the sim-gated livelock negative control, but it
**PASSES 192/192** in the behavioral course simulator. The disassembly confirms a
genuine tight LR/SC spinlock with the backoff removed, and `skeleton` losing
updates proves real concurrent contention. A follow-up experiment adding a
HW-mutex barrier to force all six harts into the spinlock in perfect lockstep
STILL reached exactly 192. The behavioral core's LR/SC reservation + fair
round-robin arbiter make forward progress without backoff; the
starvation-livelock documented in CLAUDE.md/`shspin.S` is a gate/silicon timing
property this cycle-approximate behavioral model does not reproduce. This was NOT
tuned into failing artificially (per the WP brief) -- reported to the orchestrator.

Course-band words: `SLOCK=0x102C0 SCTR=0x102C4 SOWNER=0x102C8 MCTR=0x102CC
MOWNER=0x102D0 DONE[h]=0x102E0+4h`. HW mutex = `MUTEX0 @0x6000`.
