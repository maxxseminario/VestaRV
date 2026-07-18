# lab09_multicore_boot -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** Moves to the course's private repo before any
vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`.

Multi-core bring-up (module M8, TRM ch. 4.3), on the SDK multi-core layer
(`sdk/course_lib/mp.h`). Hart 0 stages its TCM image to `0x18000`, launches
tile harts 1..`NTILES` (=5) through the bootrom loader (`mp_launch_hart`: loader
row {SRC,LEN,ENTRY} then `msip[h]`), and each tile runs `mp_tile_main`, writing
`DONE[h]=0xD09E0000+h` in the course band (`0x102A0+4h`). Hart 0 gathers with
bounded waits, checks each tile's `msip` self-cleared, and prints a per-hart
line. The shipped skeleton stubs the launch/gather (no tile launched -> every
DONE stays 0), so it FAILS. `NTILES` is a `#define` (the handout discusses all
17). ~21 s wall.

```
lab09_multicore_boot: hart 0 launches 5 tile harts (TRM 4.3)
hart 1: DONE=0xd09e0001, msip cleared -- OK
...
all 5 tiles launched and reported -- PASS
```
