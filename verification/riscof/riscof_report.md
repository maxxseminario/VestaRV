# riscof: RISCOF / riscv-arch-test conformance for VestaRV

## Status after the fixes (2026-11-04)

The findings below are the pre-fix record. All four are fixed in `hdl/common/vesta/`, with a fifth that the misaligned fix exposed: `jalr` did not clear bit 0 of its target, so the PC stayed odd. Misaligned accesses now trap with causes 4 and 6.

| Profile | Hart | Tests run | Pass | RTL defect | Memory-map limit | Documented deviation |
|---|---|---|---|---|---|---|
| orchestrator | 0 | 133 | 124 | 0 | 7 | 2 |
| tile | 1, 2, 3, 4 (each) | 93 | 84 | 0 | 7 | 2 |

Slices 47/47 on all five harts. `repro/csr_stall.S` and `repro/mis_trap.S` match Spike. The handlers are still patched into TCM; an unpatched `arch_test.h` was not re-run across the suite.

## Result

RISCOF now runs on the five-hart Castalia behavioural simulation, on any hart. **"Conformant" cannot be claimed yet.** riscv-arch-test 3.10.0 finds three RTL defects, and the harness found a fourth, which it has to work around for most of the suite to run at all. All four would move the netlist, so none is fixed.

| Profile | Hart | Tests run | Pass | RTL defect | Memory-map limit | Documented deviation |
|---|---|---|---|---|---|---|
| orchestrator `rv32imac_zba_zbb_zbc_zbs` + Zicsr, Zifencei | 0 | 133 | 117 | 7 | 7 | 2 |
| tile `rv32iac` + Zicsr, Zifencei | 1, 2, 3, 4 (each) | 93 | 77 | 7 | 7 | 2 |

The seven RTL-defect tests are `xori-01`, `clui-01` and the five `misalign-*` data tests. The seven limit tests are too large for the chip's RAM. As slices they pass 47/47 on all five harts, which recovers the six branch tests in full and 29 of the 32 `jal-01` cases; the other 3 cases jump further than any hart has memory.

Reference: Spike 3d8eb08 was the primary, and Sail 0.16 (prebuilt release binary, no toolchain build) ran every test as well. The two agreed on all 180 test rows, 0 differences. Report-side verdicts were recomputed from the signature files and match RISCOF's count on the tile hart 1 run (77 Passed, 16 Failed).

Hart independence: signatures are identical across tiles 1-4 for all 85 whole tests that produced one and all 47 slices. Hart 0 equals the tiles on 84 of those 85 and all 47 slices. The exception is `xori-01`, caused by RTL finding 2. Images differ between harts by exactly 2 words (target-hart word and its shadow), over all 344 test-hart pairs compared.

## RTL findings (not fixed, `hdl/` untouched)

**1. CSR read-modify-write returns the post-write value when the next fetch stalls.** `hdl/common/vesta/vesta.vhd:1862`, `csr_valid_eff <= csr_valid and dec_dispatch`, is not qualified by `mem_ready`. `csr_unit` commits on the free-running clock (`csr_unit.vhd:335`, `:601`), while rd is captured at the gated `clk_cpu` edge. In EXECUTE with the next fetch waiting on the arbiter, the CSR is written first and rd then reads the new value. Any CSR instruction with rd != x0 fetched from shared RAM or ROM is affected.
- Reproduction: `verification/riscof/repro/run_repro.sh <dir> 0 1 4`. `csrrw t2,mscratch,t1` with mscratch 0x5678, t1 0x1234: TCM gives 0x5678 (correct), shared RAM gives 0x1234 on harts 0, 1 and 4. `csrrs` gives 0x567c and `csrrc` 0x4448, both wrong the same way. Spike gives 0x5678 for all.
- Consequence: the arch-test handler opens with `csrrw sp,mscratch,sp`. Run from shared RAM, `add-01` looped in the handler; that one test was the only one tried unpatched, on hart 0, and it had not finished at 270 ms of sim. So the harness moves the trap handlers to TCM. **That means the pass counts above do not include this defect; no arch test fails on it as run.**
- Root cause check: in a scratch copy, adding `and mem_ready` to that line makes the reproduction match Spike on all 12 words, harts 0 and 1. That was a diagnostic of this one reproduction, not a validated fix; nothing else ran on it.

**2. `xori rd,rs1,0x80` decodes as `zext.h`.** `hdl/common/vesta/maindec.vhd:985` has an I-type ZEXT.H row (`op = I_ARITH_OPCODE, funct3 = 100, imm12 = 0x080`), not gated by ENABLE_BITMANIP. Real `zext.h` is R-type and has its own row at `:976`. `is_zbb_i_instr` at `:252` carries the same term. Reproduction: `xori-01` words 15 and 62. rs1 = 0xFFF7FFFF expects 0xFFF7FF7F; hart 0 returns 0x0000FFFF (zext.h), tiles return 0. Exactly this immediate is hit, and a compiler will emit it for `x ^ 0x80`. The boot ROM has no such instruction (0 matches in `flashboot.dump`).

**3. C.LUI with rd = x0 traps illegal instead of retiring as a HINT.** `hdl/common/vesta/c_dec.vhd:319`, `if rd = "00000" or ...`, sends it to the reserved arm. The spec reserves only nzimm = 0; rd = x0 with nzimm != 0 is a HINT. Reproduction: `clui-01` `inst_19`, `c.lui zero,0x1` at 0x10B74 gives mcause 2. This test has no trap handler, so it hangs at mtvec = 0 on every hart (300 s kill).

**4. Misaligned data accesses neither trap nor complete correctly.** The low address bits are dropped: no load or store misaligned cause exists (the TRM cause table has no 4 or 6), and the access lands on the aligned word. All five `misalign-{lh,lhu,lw,sh,sw}-01` differ from Spike and Sail, which trap. They also differ from Sail configured to allow misaligned access: `lw` returns 0xBABECAFE at offsets 1, 2, 3 where that model returns 0xFEBABECA, 0xCAFEBABE, 0xBECAFEBA, and `sw` writes the aligned word. The spec allows only trap or correct completion. Both ISA YAMLs state `hw_data_misaligned_support: false`, which selects the trapping form of these tests.

## Documented deviation (spec-permitted)

`ebreak` and `cebreak-01`: mtval is 0 on EBREAK, as the TRM cause table states and the privileged spec allows. The arch-test handler treats mtval outside the test's regions as an abort. With Sail set to `xtval_nonzero.software_breakpoint = false`, the DUT signature is byte-identical to Sail's on both tests. Caveat: the test aborts early, so the code after the EBREAK is not exercised by these two.

## Harness / memory-map limits

Whole tests that do not link below 0x1E000 in shared RAM: `beq` 124 KB, `bne` 126, `blt` 124, `bge` 129, `bgeu` 162, `bltu` 164, `jal` 887. `sim/split_big.py` partitions their cases into 47 slices. `sim/merge_slices.py` overlays the DUT slice signatures and compares with Spike's signature of the unsliced test: all six branch tests equal word for word on all five harts, 0 uncovered.

`jal-01`: 3 cases uncovered (offsets 0x55556, 0x40000 twice), since executable memory spans about 96 KB on any hart. One further word differs from the whole test only because it is a link value that depends on layout; it equals Spike's on the slice. XIP from flash could reach these on hart 0 only; not attempted.

## Exclusions

`pmp32/*`, 41 tests, both profiles. RISCOF selects them because no ISA check names PMP; Castalia has `priv.pmp` false. Recorded in `verification/riscof/exclusions.txt`. Selected but filtered out of the run, not run and classified. No other test was excluded.

## Measured

- Matrix: 5 whole runs and 5 slice runs, 705 chip sims, `MAX_PARALLEL` 4. About 20 s per typical test.
- Target hart is a parameter; the test body and data sit in shared RAM at 0x10900, the handlers in each hart's own TCM (tiles copy them through the bootrom loader). Signature readback is through hart 0's load path, streamed on `a0` with tagged, ordered words.
- Negative controls:
  - Seeded wrong word (`CORRUPT=3:00c0ffee`), 4 tests on hart 2: RISCOF Failed on all 4, `report.py` MISMATCH(1). Reverted: all 4 Passed.
  - Orchestrator profile on tile hart 1: `mul-01`, `div-01`, `clz-01`, `sh1add-01` all fail, `add-01` passes, so the run does see the tile's missing extensions.
- Load path: default is a preload into the bulk RAM macros at elaboration. 8 test runs through the full flash boot path (`LOAD=flash`, harts 4 and 0) all pass.
- Trap handling: `mtrapctl.LEGACY` resets 1, so the model boot clears it (CSR 0x7C0). `ENABLE_TRAPCSR` is true on both hart classes.
- Spike `marchid`: 0 of the selected tests read marchid, mvendorid or mimpid, so the `vesta_ref` override is not needed.
- Custom `extinguish` is used only in the DUT model halt, never on a reference.

## Not measured

- Coverage gaps in this suite: no LR/SC in `A` (AMOs only), no Zicsr test, no interrupts, no check of `misa`. The tile YAML's misa is read from `csr_unit.vhd`, not from sim. riscv-config has no B letter, so the orchestrator YAML says 0x40001105 where the RTL gives 0x40001107.
- Only `add-01` was run with an unpatched `arch_test.h`, so there is no count of how many tests finding 1 alone would fail.
- Tests other than the 8 flash runs were not run through the flash load.
- No TCM-resident test bodies; everything fetches through the arbiter except the handlers.
- No gate-level run. Upstream's newer ACT4 framework was not used; 3.10.0 is the RISCOF-format tag.
- The run used `ARM_IP_RAM.vhd`/`ARM_IP_ROM.vhd` from `~/vestarv` (untracked). ROM image is byte-identical to the one the worktree builds; `stage.sh` checks this.
- `tools/cosim/gate/behavioral_mp/cell_list_behavioral.txt` is stale (no register packages); `sim/cell_list.txt` was derived from the live list instead.
- Whether the Myshkin netlist shares findings 1-4 was not checked.

## How to reproduce

```sh
cd verification/riscof
sim/stage.sh
export RISCOF_ENV=<python>=3.7 env with riscof 1.25.3> ARCH_TEST=<riscv-arch-test 3.10.0> SAIL=<sail_riscv_sim 0.16>
./run_riscof.sh orch 0 <w>/orch_h0
for h in 1 2 3 4; do ./run_riscof.sh tile $h <w>/tile_h$h; done
for t in beq bne blt bge bltu bgeu jal; do sim/split_big.py $ARCH_TEST/riscv-test-suite/rv32i_m/I/src/$t-01.S <d>/rv32i_m/I/src; done
SUITE=<d>/rv32i_m ./run_riscof.sh tile 1 <w>/sl_tile_h1     # likewise the other harts
sim/report.py table.md h0=<w>/orch_h0 h1=<w>/tile_h1 ...
sim/merge_slices.py <w>/sl_tile_h1 <w>/tile_h1 beq-01 bne-01 blt-01 bge-01 bltu-01 bgeu-01 jal-01
CORRUPT=3:00c0ffee ./run_riscof.sh tile 2 <w>/nc 'I/src/add-01.S'
repro/run_repro.sh <dir> 0 1 4
```

The toolchain and run data are in scratch, `/tmp/claude-1019/-home-mseminario2/bafe1087-5448-4735-8c98-7871e664e4f2/scratchpad/rf` (1.6 GB) and will not persist.

## Files changed in the worktree

New, uncommitted: `verification/riscof/` (`README.md` is the map). Nothing tracked was modified; `git status` shows only that directory. Ignored build output: `software/bootrom_mp/{bin,obj}`, `xcelium/riscof` (869 MB).

## Owner decisions

1. Whether and when to fix findings 1-4. Each moves the netlist, during tile closure. Finding 2 corrupts data silently on ordinary compiled code, and finding 1 hits any image running from shared RAM that does a CSR swap.
2. Finding 4: add causes 4 and 6, or implement misaligned access. Until then a conformance claim must carve this out.
3. EBREAK mtval: keep 0, or write the PC so the two tests run to completion.
4. Whether "conformant" may be used publicly before findings 1-4 are closed. Suggested wording until then: "passes riscv-arch-test 3.10.0 except for listed defects".
5. Whether the generator's ISA string should add `_zicsr_zifencei`. `Fencei` passes on all five harts.
6. Proposed TRM text, cause table: "Misaligned loads and stores do not trap. The low address bits are ignored and the access uses the aligned word." It should stand only until finding 4 is closed.

## Appendix: per-extension and per-test results

PASS: DUT signature equals Spike's and Sail's. MISMATCH(n): n words differ. SIM_FAIL: no complete signature. LINK_FAIL: image does not fit; see the slice table.

| Extension | h0 | h1 | h2 | h3 | h4 |
|---|---|---|---|---|---|
| A | 9/9 | 9/9 | 9/9 | 9/9 | 9/9 |
| B | 32/32 | n/a | n/a | n/a | n/a |
| C | 27/29 | 27/29 | 27/29 | 27/29 | 27/29 |
| I | 31/39 | 31/39 | 31/39 | 31/39 | 31/39 |
| M | 8/8 | n/a | n/a | n/a | n/a |
| Zifencei | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 |
| privilege | 9/15 | 9/15 | 9/15 | 9/15 | 9/15 |
| I, slices | 47/47 | 47/47 | 47/47 | 47/47 | 47/47 |

### Whole tests

| ext | test | h0 | h1 | h2 | h3 | h4 | refs |
|---|---|---|---|---|---|---|---|
| A | amoadd.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amoand.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amomax.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amomaxu.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amomin.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amominu.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amoor.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amoswap.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| A | amoxor.w-01 | PASS | PASS | PASS | PASS | PASS | agree |
| B | andn-01 | PASS | - | - | - | - | agree |
| B | bclr-01 | PASS | - | - | - | - | agree |
| B | bclri-01 | PASS | - | - | - | - | agree |
| B | bext-01 | PASS | - | - | - | - | agree |
| B | bexti-01 | PASS | - | - | - | - | agree |
| B | binv-01 | PASS | - | - | - | - | agree |
| B | binvi-01 | PASS | - | - | - | - | agree |
| B | bset-01 | PASS | - | - | - | - | agree |
| B | bseti-01 | PASS | - | - | - | - | agree |
| B | clmul-01 | PASS | - | - | - | - | agree |
| B | clmulh-01 | PASS | - | - | - | - | agree |
| B | clmulr-01 | PASS | - | - | - | - | agree |
| B | clz-01 | PASS | - | - | - | - | agree |
| B | cpop-01 | PASS | - | - | - | - | agree |
| B | ctz-01 | PASS | - | - | - | - | agree |
| B | max-01 | PASS | - | - | - | - | agree |
| B | maxu-01 | PASS | - | - | - | - | agree |
| B | min-01 | PASS | - | - | - | - | agree |
| B | minu-01 | PASS | - | - | - | - | agree |
| B | orcb_32-01 | PASS | - | - | - | - | agree |
| B | orn-01 | PASS | - | - | - | - | agree |
| B | rev8_32-01 | PASS | - | - | - | - | agree |
| B | rol-01 | PASS | - | - | - | - | agree |
| B | ror-01 | PASS | - | - | - | - | agree |
| B | rori-01 | PASS | - | - | - | - | agree |
| B | sext.b-01 | PASS | - | - | - | - | agree |
| B | sext.h-01 | PASS | - | - | - | - | agree |
| B | sh1add-01 | PASS | - | - | - | - | agree |
| B | sh2add-01 | PASS | - | - | - | - | agree |
| B | sh3add-01 | PASS | - | - | - | - | agree |
| B | xnor-01 | PASS | - | - | - | - | agree |
| B | zext.h_32-01 | PASS | - | - | - | - | agree |
| C | cadd-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | caddi-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | caddi16sp-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | caddi4spn-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cand-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | candi-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cbeqz-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cbnez-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cebreak-01 | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | agree |
| C | cj-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cjal-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cjalr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cjr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cli-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | clui-01 | SIM_FAIL | SIM_FAIL | SIM_FAIL | SIM_FAIL | SIM_FAIL | agree |
| C | clw-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | clwsp-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cmv-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cnop-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cor-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cslli-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | csrai-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | csrli-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | csub-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | csw-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cswsp-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | cxor-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | misalign1-cjalr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| C | misalign1-cjr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | add-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | addi-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | and-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | andi-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | auipc-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | bge-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | bgeu-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | blt-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | bltu-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | bne-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | fence-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | jal-01 | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | LINK_FAIL | agree |
| I | jalr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lb-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lbu-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lh-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lhu-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lui-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | lw-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | misalign1-jalr-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | or-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | ori-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sb-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sh-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sll-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | slli-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | slt-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | slti-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sltiu-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sltu-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sra-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | srai-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | srl-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | srli-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sub-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | sw-align-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | xor-01 | PASS | PASS | PASS | PASS | PASS | agree |
| I | xori-01 | MISMATCH(2) | MISMATCH(2) | MISMATCH(2) | MISMATCH(2) | MISMATCH(2) | agree |
| M | div-01 | PASS | - | - | - | - | agree |
| M | divu-01 | PASS | - | - | - | - | agree |
| M | mul-01 | PASS | - | - | - | - | agree |
| M | mulh-01 | PASS | - | - | - | - | agree |
| M | mulhsu-01 | PASS | - | - | - | - | agree |
| M | mulhu-01 | PASS | - | - | - | - | agree |
| M | rem-01 | PASS | - | - | - | - | agree |
| M | remu-01 | PASS | - | - | - | - | agree |
| Zifencei | Fencei | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | ebreak | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | MISMATCH(3) | agree |
| privilege | ecall | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-beq-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-bge-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-bgeu-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-blt-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-bltu-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-bne-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-jal-01 | PASS | PASS | PASS | PASS | PASS | agree |
| privilege | misalign-lh-01 | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | agree |
| privilege | misalign-lhu-01 | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | agree |
| privilege | misalign-lw-01 | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | agree |
| privilege | misalign-sh-01 | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | MISMATCH(5) | agree |
| privilege | misalign-sw-01 | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | MISMATCH(15) | agree |
| privilege | misalign2-jalr-01 | PASS | PASS | PASS | PASS | PASS | agree |

### Slices

| ext | test | h0 | h1 | h2 | h3 | h4 | refs |
|---|---|---|---|---|---|---|---|
| I | beq-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | beq-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bge-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p7 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bgeu-01.p8 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | blt-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p7 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bltu-01.p8 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p1 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p2 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p3 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p4 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p5 | PASS | PASS | PASS | PASS | PASS | agree |
| I | bne-01.p6 | PASS | PASS | PASS | PASS | PASS | agree |
| I | jal-01.p0 | PASS | PASS | PASS | PASS | PASS | agree |
