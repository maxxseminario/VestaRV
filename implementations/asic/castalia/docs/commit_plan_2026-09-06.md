# Commit plan for the 2026-09-05/06 tape-out campaign

Working tree of `~/vestarv` on branch `docs/relocate-vesta-docs-pointers`, read at
2026-09-06 14:20 America/Chicago. **Nothing here has been committed and nothing has been
reverted.** This document is a proposal for the owner.

State: 165 tracked files modified, 1 tracked file deleted and staged
(`hdl/common/tb/testbench.vhd`, staged by `git rm`), 18 untracked files in 16 status
entries. `git diff --stat` totals 7,510 insertions and 3,371 deletions; 5,560 of those
lines are the two identical boot-ROM `.rcf` goldens.

Waves are named as in `~/chips/castalia/tapeout_review/reports/`.

---

## 1. Every tracked file, what changed, which wave

### 1.1 RTL, shared spine (F9 latch/CDC audit, F12 clock and latch resynthesis)

| file | change | wave |
|---|---|---|
| `hdl/common/clint.vhd` | `mtime` increment unfolded from `mtime_next`; a same-cycle write no longer keeps or drops the carry between the lo and hi words | F9 |
| `hdl/common/irq_router.vhd` | new elaboration assert that `CLINT_SIP`/`CLINT_TIP` are distinct source IDs below `NUM_SRCS` | F9 |
| `hdl/common/jtag_dtm.vhd` | `trstn` synchroniser plus a 3-sample `trstn_guard` on the request edge detect, mirroring the existing `rst_guard`; kills the unqualified `op="00"` transaction at address 0 after a TAP reset | F9 |
| `hdl/common/periph/NFC.vhd` | `rxbuf_mem(9..63)` and `resp_bytes(16..63)` held at zero on the clock edge; removes 110 reset-only inferred latches | F12 |
| `hdl/common/periph/SPI.vhd` | slave RX read path moved from the live shift register `s_rx_sreg` to a captured `s_rx_hold` (F9); `s_spi_teif` latch fix (F12) | F9 + F12 |
| `hdl/common/periph/TIMER.vhd` | gray-coded mirror of `timer_value` plus `bin2gray`/`gray2bin`, so the `TIMxVAL` read crosses from `timer_clock` to `clk_mem` one bit at a time | F9 |
| `hdl/common/vesta/csr_unit.vhd` | extension-disabled CSRs written to their reset constant on the clock edge instead of only in the reset branch; removes the latch class Genus later collapses | F12 |
| `hdl/common/vesta/div.vhd` | `elsif complete = '1'` becomes `else`; removes 32 inferred latches on `result` | F9 |
| `hdl/common/vesta/maindec.vhd` | `dbg_csr_denied` and `debug_mode` added to the second legality-stage sensitivity list | F9 |
| `hdl/common/vesta/vesta.vhd` | ZCM sequential block put behind `gen_zcm_seq` generate arms; `is_compressed` and `sp_write_data` defaults; `amo_wen` added to a sensitivity list | F9 + F12 |
| `hdl/common/MCU.vhd` | regenerated: `irtr0` now associates `CLINT_SIP => IRQB_CLINT_MSIP, CLINT_TIP => IRQB_CLINT_MTIP` | F9, emitted by `mcu_vhd.py` |

### 1.2 AFE2 peripheral and generator (F7, plus F11/F22 generator hunks)

| file | change | wave |
|---|---|---|
| `platform/common/python/generate.py` | `peripherals.afe2` schema/meta/default; the `IRQB_AFE` vector; the four sites at `0x6C00 + 0x100*h`; `_irqClearMethod('IRQB_AFE')`; `McuMpGeometry['afe2']`; `afe2` in the resolved-config row | F7 |
| `platform/common/python/mcu_vhd.py` | `emitAfe2Ports`/decls/instance (164 new lines), the AFE0..AFE3 slot list, the trailing-semicolon rule, the entity port group | F7 |
| `platform/common/python/mcu_vhd.py` | the `irq_router` `CLINT_SIP`/`CLINT_TIP` association | F11 |
| `platform/common/python/tb_vhd.py` | `afe2` flag, the `tb-afe2-signals` region and `emitAfe2Signals` | F22 |
| `platform/common/python/ChipGenerator.py` | passes `McuMpGeometry['afe2']` and `afeTopology` to `tb_vhd` | F22 + B2 |
| `platform/common/python/web_export.py` | AFE2 in the derived counts and memory regions | F7 |
| `platform/common/python/check_configurator_sync.py` | one AFE2 derived fragment | F7 |
| `platform/common/hdl_templates/MCU.template.vhd` | three `--@GEN:afe2-*@` markers | F7 |
| `platform/common/BUILD.bazel` | `chip_artifacts_penta_wound`, `..._penta_wound_afe`, `..._penta_wound_afe_pt` and their generation / memorymap / intro-name tests (223 new lines) | F7 + B2 |
| `docs/chip_configurator.html` | the `afe2` and `afeTopology` knobs, and a re-spliced `VESTA_DATA` blob | F7 + B2 (+F8 address-map data) |
| `platform/common/config/ChipConfig.resolved.json` | two generated lines: `"afeTopology": "top_ports"` and `"afe2": false` | F11 / B2 regeneration |

### 1.3 Per-tile topology and BIASG (B2, B3, B4, B9)

| file | change | wave |
|---|---|---|
| `platform/common/python/generate.py` | `afeTopology` knob; `castalia-lqfp100-pt` package model and its `_buildPackageData` branch reading `config/padring_pt.json` with five cross-check FATALs; the `BIASG` register block; `BGCODE0..3`/`BGADJ`/`BGUSEDAC` field descriptions | B2, B9 |
| `platform/common/python/mcu_vhd.py` | per-tile electrode/bias ports, decls, `hart_tile_pt` instance binding and clamps | B2 |
| `platform/common/python/tb_vhd.py` | per-tile bench: biasg group, no top-level analog models | B2 |
| `platform/common/python/verify_stage.py` | `afe2pt` tag and its three cell gates | B2 |
| `platform/common/python/LatexUserGuide.py` | `afeTopology` in the TRM config-table `keyOrder` | B2 |
| `opensource_sim/isa/BUILD.bazel`, `opensource_sim/isa/run_isa.sh` | `shafe2` SKIP row on the open-source simulator (no MCU peripheral there) | B2 |

### 1.4 Boot ROM (F8)

| file | change | wave |
|---|---|---|
| `software/bootrom_mp/src/start.S` | stack pointer `0xBFFC -> 0xA000` at all three sites; both SPI flash polls bounded with a status word at `0x10644`; boot watchdog armed | F8 |
| `software/bootrom_mp/testdata/rom_rcf_golden.txt` | regenerated image, md5 `99b0c95dfb3fc0da52a49d1a68efa904` | F8 |
| `tools/cosim/gate/bootrom_mp_rom.rcf` | same image, byte-identical to the golden (verified by md5) | F8 |
| `software/bootrom_mp/BUILD.bazel` | provenance block for the fourth ROM re-cut; records that the physical `rom2k_hvt_pg` plate is not yet recompiled | F8 |
| `tools/build/BUILD.bazel` | same md5 provenance for the five-file set | F8 |
| `tools/build/linker-scripts/MCU-bootrom.ld` | `_stack_top` comment corrected to `ORIGIN(RAM) + LENGTH(RAM) = 0xA000` and the mirror explained | F8 |
| `tools/cosim/check_gate_files.py` | records that the cut moved the first word, so the cosim boot-mode X pins at pc `0x5c` / `0x15c` are stale | F8 |
| `software/commune/include/myshkin.h` | `PERIPH_SARADC0_BASE` deleted (0x4B00 is PWRCTRL); `PERIPH_AFE0_BASE` annotated | F8 |
| `software/commune/include/myshkin_s.h` | same removal plus the corrected 8 KiB TCM / 16 KiB decode-window note | F8 |
| `docs/index.html` | links the seven previously unlinked `afe_rev2_*.html` notes | F8 |

### 1.5 Testbenches and Bazel gates (F4, F7, F11, F21/F22)

| file | change | wave |
|---|---|---|
| `hdl/common/tb/BUILD.bazel` | ten new `ghdl_test` targets and their `_rtl` libraries (arb_lat, clint, gpio, i2c, irq_router, irq_sys, pwr_ctrl, spi, system, timer, uart) | F4 |
| `hdl/common/tb/BUILD.bazel` | the `AFE2_tb` target and `afe2_rtl` | F7 |
| `hdl/common/tb/BUILD.bazel` | `NUM_SRCS` 121 -> 125 | F11 |
| `hdl/common/tb/SYSTEM_tb.vhd` | `PGEN_mem` and `SYS_BLOCK_PWR` widened 3 -> 7 bits, plus a `shb_off` case | F4 |
| `hdl/common/tb/dbg_dmi_tb.vhd` | C5 rewritten: `hartinfo` is the null claim, not `dataaddr = 0x680` | F4 |
| `hdl/common/tb/dbg_tap_tb.vhd` | J7 asserts the whole `hartinfo` word is zero | F9 |
| `hdl/common/tb/pwr_ctrl_tb.vhd` | poll budget scales with the generics, so the shipped `(5, 4, 256)` shape passes | F4 |
| `hdl/common/tb/{AFE_tb,AFE_FSM_tb,SARADC_tb}.vhd` | one-line "NOT IN THE CASTALIA BUILD" header each | F4 |
| `hdl/common/tb/testbench.vhd` | **deleted** (staged); dead, out of build | F4 |
| `tools/ci/crlf_manifest.txt` | drops the deleted `testbench.vhd` row | F4 |
| `platform/common/hdl_templates/riscv_tb.template.vhd` | `simulation_timeout_flag` initialises `false` so the TIMED OUT branch is reachable (F4); `--@GEN:tb-afe2-signals@` marker and the UART0/1 RX weak-`H` pulls (F22, from F21's X trace) | F4 + F22 |
| `hdl/common/tb/riscv_tb.vhd` | regenerated: both of the above | F4 + F22 |
| `hdl/castalia/tb/riscv_tb.vhd` | regenerated: timeout flag only, **not** the RX pulls (see finding U-1) | F4 |

### 1.6 Verification and ISA tests (F4, F9, F22)

| file | change | wave |
|---|---|---|
| `verification/isa/defs.bzl` | emits a `<suite>_dumps` filegroup of the objdump listings | F4 |
| `verification/isa/BUILD.bazel` | `isa_dumps` filegroup and its wiring into `image_contract_test`; `shafe2` in `_RV32UI_TESTS` | F4 + F22 |
| `verification/isa/tests_image_contract.py` | the tile ISA gate: rejects every M and Zb mnemonic in the rv32ui/rv32ua/rv32uc listings, with two named allowlisted hart-0 sites | F4 |
| `verification/isa/tests/rv32ua/fk51mp.S` | half (a) moved onto hart 0; victim preambles reduced to plain rv32i reserved-shamt forms so a stall cannot be the tile's narrowed ISA | F9 |
| `verification/isa/tests/rv32ui/shafe.S` | retirement header only, no code change | F22 |
| `verification/isa/tests/rv32ui/Makefrag` | `shafe2` | F22 |
| `platform/common/python/verify_stage.py` | `shafe2` CATALOG row, `sar_macro_model` cell gate, `shafe` retire note (F22); already-swapped cell-list anchors and the AFE cell gates (F15) | F15 + F22 |

### 1.7 Documentation, TRM and workspace docs (F10, F13, F15, F16, F17, F26)

| file | change | wave |
|---|---|---|
| `platform/common/latex/packages-commands.template.tex` | `\usepackage[noforwardlinks]{acronym}`; kills all 39 dead `acro:*` forward links and the standing "There were undefined references" | F10 |
| `platform/common/latex/TRM.template.tex` | build hash on the title page; the AFE feature bullet gated on the analog chapter's presence; `\RevisionDateISO` in the revision table; a PENDING block recording D-1/D-4/D-5 | F10 |
| `platform/common/Makefile` | `trm-lint` now fails on `There were undefined references` and prints the offending targets; header corrected to five harts | F10 |
| `platform/common/README.md` | states which suite is the standing regression (`SUITE=full CONFIG=config/penta_wound_afe.json`, 157/157) and that `behavioral_mp` is a smoke | F15 |
| `platform/common/latex/PeripheralIntroductions/{DMA,EVFAB,I2CT,I3C,OneWire,PWM,QSPI,RTC,TRNG}-intro-castalia-2026-07.tex` | section skeleton added so `check_intro_names.py` grades them | F15 |
| `platform/common/latex/PeripheralIntroductions/{DEBUG-...-2026-08,SYSTEM-...-2026-07}.tex` | two lines each | F10 |
| `platform/common/python/LatexUserGuide.py` | analog-chapter path guard for `chipName` PentaWound; the AFE prose corrections; the private-band decode width read from the geometry record; `AFEx` register-name mapping | F7 + F8 + F10 |
| `platform/common/tools/maestro2tex/configs/*.json` (10 files) | 13 rewritten captions and the em-dashes removed at source, so a regeneration does not put them back; `note_dacr2r12_driver` added to the DAC config `order` | F10 + F26 |
| `implementations/asic/castalia/analog/AnalogChapter.tex` | `\ifcqanalog` guard on the placeholder-map reference; the four-channel macro row and its nominal-only caveat; em-dashes | F10 + F26 |
| `implementations/asic/castalia/analog/DacR2R12.tex` | `\input` of the new driver-correction note | F16 + F26 |
| `implementations/asic/castalia/analog/note_eis_{accuracy,coverage,intro}.tex` | EIS-through-the-potentiostat corrections from F17, plus em-dashes | F17 + F26 |
| `implementations/asic/castalia/analog/note_dacr2r12_intro.tex` | driver correction cross-reference | F26 |
| `implementations/asic/castalia/analog/` 54 files, 2 to 4 changed lines each | em-dash conversion and regenerated captions: `BiasGenCascWideSwing`, `fig_adc_{error,range,transfer}`, `fig_dacr2r12_{dnl_ratio,inl_ideal}`, `fig_eis_{codelevel,error,mccal,nyquist,settling}`, `fig_electrode_{panel,validation}`, `fig_pixtop_{mc,noise}`, `fig_tiarprog_{lin_n0,mc_seam}`, `note_adc_{intro,mc,power,transfer}`, `note_ampab_{ctrl,ctrl_mc,intro}`, `note_dacr2r12_{scope,supply}`, `note_meas_{adc,ampab,tiarprog}`, `note_pixtop_zero`, `sch_dacr2r12_{ladder,psu}`, `sch_tiarprog_switch`, `tab_AmpAB_corners`, `tab_ampab_mc_{cellstab,compliance,offset,openloop,tracking,unity}`, `tab_BiasGenCascWideSwing_corners`, `tab_biasgen_temp_stats`, `tab_calibration_constants`, `tab_DacR2R12_corners`, `tab_dacr2r12_{ideal,linereg,mc_ideal,mc_psu_load,mc_reference,mc_wpsu}`, `tab_electrode_refs`, `tab_Pixel_corners`, `tab_pixtop_mc`, `tab_tiaab_accuracy`, `tab_TiaAmpAB_corners`, `tab_tiarprog_corners` | F10 |
| `implementations/asic/castalia/analog/` 20 files, 6 to 15 changed lines each | em-dash conversion with a rewrite at the site: `fig_electrode_dpv`, `fig_pixtop_cv`, `note_biasgen_startup`, `note_calibration`, `note_dacr2r12_mc`, `note_eis_{excitation,open,rules}`, `note_electrode_dpv`, `note_meas_{biasgen,dacr2r12,pixtop}`, `note_pixtop_{adc,comp,cv,intro,mc,mux,noise,open,potential,power}`, `note_tiarprog_{intro,mc,spec}` | F10 |

---

## 2. Proposed commits

Style follows `git log --format=%B -20`: an area prefix, a lower-case declarative summary
line, then prose that states the result, the mechanism and the consequence, with numbers.
Every message ends with the session trailer.

Six of the files below carry hunks from more than one wave
(`generate.py`, `mcu_vhd.py`, `tb_vhd.py`, `verify_stage.py`, `LatexUserGuide.py`,
`hdl/common/tb/BUILD.bazel`, `platform/common/BUILD.bazel`, `docs/chip_configurator.html`,
`SPI.vhd`, `vesta.vhd`). Splitting them needs `git add -p`; section 4 lists the split
points. If the owner would rather not split, collapse commits 2 and 3 into one
"generator" commit and commits 5 and 6 into one "regression" commit; nothing else changes.

### C1 - RTL fixes

```
RTL: remove the inferred latches and close two reset-domain holes

Ten files, all in the shared spine. div.vhd's result register was assigned only
while complete = '1' and inferred 32 latches; alu.vhd:388 reads it only in that
same window, so a plain combinational mux is bit-identical at the read. NFC's
rxbuf_mem(9..63) and resp_bytes(16..63) and csr_unit's extension-disabled CSRs
are the same class: a reset-only write that Genus infers as a latch and then
collapses to a constant. Writing that constant on the clock edge makes the
collapse explicit and leaves the netlist unchanged. vesta.vhd puts the ZCM
sequential block behind generate arms, so a build with both extensions off no
longer keeps 43 dead flops behind a provably constant ICG.

clint.vhd stops folding the increment into mtime_next: with it pre-incremented,
a write to the lo word kept a carry the increment had already pushed into hi and
a write to hi discarded the carry lo had produced, each a 2^32-tick fault on a
monotonic clock. jtag_dtm.vhd gains a trstn synchroniser and a three-sample
guard mirroring rst_guard, so a trstn asserted while req_tgl was high no longer
presents a real toggle edge with a zeroed payload and issues an unqualified
op="00" transaction at address 0. TIMER's TIMxVAL read crosses a gray mirror of
the counter instead of the binary counter. SPI's slave read path moves off the
live shift register onto a hold register captured on the wrap edge.

maindec and vesta gain the sensitivity-list entries whose absence let RTL
simulation hold state the netlist never sees. irq_router asserts that CLINT_SIP
and CLINT_TIP are distinct source IDs below NUM_SRCS, and MCU.vhd now associates
them from MemoryMap rather than relying on declaration defaults that only
happened to match.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `hdl/common/clint.vhd`, `hdl/common/irq_router.vhd`, `hdl/common/jtag_dtm.vhd`,
`hdl/common/periph/NFC.vhd`, `hdl/common/periph/SPI.vhd`, `hdl/common/periph/TIMER.vhd`,
`hdl/common/vesta/csr_unit.vhd`, `hdl/common/vesta/div.vhd`, `hdl/common/vesta/maindec.vhd`,
`hdl/common/vesta/vesta.vhd`, `hdl/common/MCU.vhd`, and the `irq_router` hunk of
`platform/common/python/mcu_vhd.py` (`@@ -3353 +3569,2 @@`).

### C2 - AFE2 peripheral and generator

```
AFE2: four rev-2 analog front-end sites and the generator that emits them

The rev-1 afe_stub bank at 0x4C00 collides with QSPI0 in page-0 slot 12 and does
not reach the rev-2 macro. AFE2.vhd is one entity instantiated four times, about
254 flops per site, at 0x6C00 + 0x100*h in page-2 sub-slots 12-15, which are
free in every configuration. It carries the 50 anatop_pixel control bits and the
11 status bits per site and one shared interrupt vector that each site's status
register demultiplexes; sources 55 and 56 stay QSPI0's.

The generator gains peripherals.afe2, the IRQB_AFE vector and its clear method,
the three MCU.template markers and the McuMpGeometry flag. config/
penta_wound_afe.json is the tape-out configuration: cqAfeStubs false, qspi true,
afe2 true. //opensource_sim/penta_wound_afe elaborates the generated MCU.vhd
against the tracked spine and is what caught the 128-source overflow.
//hdl/common/tb:AFE2_tb is the directed register bench.

The chip-wrapper netlist edit this implies is written down in
docs/afe2_chip_wrapper_patch.md rather than applied: innovus/ is an untracked
EDA tree. Pad count goes 72 to 78.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `hdl/common/periph/AFE2.vhd` (new), `hdl/common/tb/AFE2_tb.vhd` (new),
`platform/common/config/penta_wound_afe.json` (new),
`platform/common/latex/PeripheralIntroductions/AFE-intro-castalia-2026-09.tex` (new),
`docs/afe2_chip_wrapper_patch.md` (new), `opensource_sim/penta_wound_afe/` (new, 2 files),
`platform/common/hdl_templates/MCU.template.vhd`,
`platform/common/python/{generate,mcu_vhd,web_export,check_configurator_sync}.py` (F7 hunks),
`platform/common/BUILD.bazel` (F7 hunks), `hdl/common/tb/BUILD.bazel` (AFE2 hunks),
`docs/chip_configurator.html`, `platform/common/config/ChipConfig.resolved.json`.

### C3 - per-tile topology and BIASG

```
Generator: per-tile AFE topology, the BIASG register block and the _pt pad ring

Topology B puts one analog channel inside each hart tile instead of one
four-channel macro in a north corridor. afeTopology selects it; the electrode
and bias nets leave through the tile boundary, so hart_tile_pt.vhd is a pure
wiring wrapper and mcu_vhd.py binds the tiles to it. BIASG.vhd is the 66-bit
shared bias-generator register block: four 14-bit DAC codes, a 6-bit trim and
the USEDAC select, whose bring-up order (EN_GEN, adj, codes, then USEDAC, with
USEDAC defaulting to 0) is rule R15 of the firmware contract, because with fixed
codes the ladder rails to AVDD below -25 C and its enable inrush is 3.7 to 4.4
mA.

The package is castalia-lqfp100-pt. Its die-row geometry lives in
config/padring_pt.json and the generator branch cross-checks pad count,
electrode net names, rail names, the unbonded set and the per-island bonded flag
against its own ball map, with a FATAL on any disagreement: duplicating the pad
map in Python is how the model and the padlist drifted 18 against 10 the first
time. The LQFP-100 south edge cannot take both south corners' pads, so eleven
south digital pads move north (R1) and ATP_2/ATP_3 go unbonded to give the south
segment a post-driver supply pair (S1).

Both configurations generate and elaborate:
//platform/common:penta_wound_afe_pt_generation_test and
//opensource_sim/penta_wound_afe_pt:penta_wound_afe_pt_elaborate.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `hdl/common/hart_tile_pt.vhd` (new), `hdl/common/periph/BIASG.vhd` (new),
`platform/common/config/{padring_pt,penta_wound_afe_pt}.json` (new),
`opensource_sim/penta_wound_afe_pt/` (new, 2 files),
`platform/common/python/{generate,mcu_vhd,tb_vhd,verify_stage,LatexUserGuide,ChipGenerator}.py`
(B2/B9 hunks), `platform/common/BUILD.bazel` (B2 hunks),
`opensource_sim/isa/{BUILD.bazel,run_isa.sh}`, `docs/chip_configurator.html` (B2 hunk).

### C4 - boot ROM

```
Boot ROM: stack pointer at the TCM top, bounded flash polls and a boot watchdog

start.S loaded sp with 0xBFFC at all three sites. The TCM array is 8 KiB
(0x8000-0x9FFF) behind a 16 KiB decode window, so 0xBFFC is the mirror and every
first push landed at 0x9FF8. The correct value is 0xA000, one past the array,
because the push convention stores at sp-4 and then decrements; that is what
MemoryMap.h STACK_POINTER_INIT, ChipConfig.resolved.json
derived.stackPointerInit, periph.S StackPointerInit and the linker script's
__StackPointerInit have always published.

Both SPI flash polls are now bounded and fall through to the Forth monitor with
a status word at 0x10644, and the boot path arms the watchdog; an unresponsive
flash used to hang hart 0 forever. The image is 7,532 bytes of 8,192, was 7,376.

PERIPH_SARADC0_BASE is deleted from both commune headers: 0x4B00 is PWRCTRL on
this chip, so the name pointed a SARADC write at PWRCR and blind-gated the
tiles. Castalia emits no SARADC registers at all.

The image md5 goes d177e831 to 99b0c95dfb3fc0da52a49d1a68efa904 across
bin/rom.rcf, testdata/rom_rcf_golden.txt and tools/cosim/gate/bootrom_mp_rom.rcf
(all three verified equal). THE FIRST CHANGED WORD IS AT 0x004, the mhartid
dispatch branch, so unlike the 2026-08-23 cut nothing before 0x304 is preserved
and the cosim boot-mode X pins at pc 0x5c and 0x15c are stale. The physical
rom2k_hvt_pg plate is not recompiled here; that is a signoff job.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `software/bootrom_mp/{BUILD.bazel,src/start.S,testdata/rom_rcf_golden.txt}`,
`software/commune/include/{myshkin.h,myshkin_s.h}`,
`tools/build/{BUILD.bazel,linker-scripts/MCU-bootrom.ld}`,
`tools/cosim/{check_gate_files.py,gate/bootrom_mp_rom.rcf}`.

### C5 - testbenches and Bazel gates

```
Testbenches: ten new GHDL gates, the shipped generics, and a reachable timeout

//hdl/common/tb went from five test targets to fifteen. The ten added are
arb_lat, clint, gpio, i2c, irq_router, irq_sys, pwr_ctrl, spi, system and timer
and uart, each with its own _rtl library, so a bench that only ever ran under a
licensed simulator now gates every push.

Three benches were wrong rather than merely unbuilt. SYSTEM_tb checked
PGEN_mem and SYS_BLOCK_PWR as 3 bits; they are 7, and the four shared-bank off
bits were unchecked. dbg_dmi_tb and dbg_tap_tb still asserted hartinfo.dataaddr
= 0x680, left behind by 2352054: hartinfo is the null claim, and 0x680 is
precisely the wrong answer because the field is 12 bits and sign-extended, so
publishing DATA0_ADDR 0x10680 resolves inside the read-only boot ROM. pwr_ctrl_tb
had a fixed 61-read poll budget that covers T_RAIL=8 but not the shipped
T_RAIL=256 of MCU.vhd:3030, so twelve checks failed with the RTL correct; the
budget now scales with the generics.

simulation_timeout_flag initialised true. `wait until` resumes only on an event,
and the flag is only ever assigned true, so test_sequence's TEST TIMED OUT branch
was dead and a timeout reached run_isa.sh, xrun_cosim.sh and ghdl/defs.bzl as an
unclassified failure. It initialises false, in the template and in both generated
products.

testbench.vhd is deleted: dead, in no build, and its crlf_manifest row goes with
it. AFE_tb, AFE_FSM_tb and SARADC_tb are kept but headed NOT IN THE CASTALIA
BUILD; MCU.vhd instantiates afe_stub, and SARADC.vhd references a RegSlot the
memory map does not declare, so that closure does not even analyze.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `hdl/common/tb/BUILD.bazel` (F4/F11 hunks),
`hdl/common/tb/{SYSTEM_tb,dbg_dmi_tb,dbg_tap_tb,pwr_ctrl_tb,AFE_tb,AFE_FSM_tb,SARADC_tb,riscv_tb}.vhd`,
`hdl/common/tb/testbench.vhd` (deleted), `hdl/castalia/tb/riscv_tb.vhd`,
`platform/common/hdl_templates/riscv_tb.template.vhd`, `tools/ci/crlf_manifest.txt`.

### C6 - verification and ISA tests

```
Verification: a tile ISA gate, the AFE2 MCU test, and an honest fk51mp

Harts 1-4 are the hardened hart_tile macro at rv32iac (MCU.vhd:3290-3294 passes
TILE_ENABLE_MUL, TILE_ENABLE_DIV and TILE_ENABLE_BITMANIP false), but the images
are assembled -march=rv32imc / rv32imac, so gas accepts a mul or a bseti in
tile-executed code without a word and the first evidence would be an
illegal-instruction trap inside a licensed regression. image_contract_test now
reads the objdump listings of rv32ui, rv32ua and rv32uc and rejects every M and
Zb mnemonic in them. Whole-image, not tile sections: shexec.S puts orchestrator
after tile_entry and shboot.S hand-rolls the launch with no tile-named label, so
no section or symbol convention separates them. Exactly two sites in 176 images
use M or Zb today and both are allowlisted by image, symbol and mnemonic.
rv32um and rv32uzb* are excluded on purpose: those suites exist to exercise the
extensions and hart 0 runs them alone.

fk51mp half (a) moves onto hart 0. Since b1c39da the tiles take
TILE_ENABLE_BITMANIP false, so an rv32iac victim trapped the two Zbs-shaped
forms, PROGRESS1 stuck at 1 and hart 0 reported 0xF5100004: a bitmanip verdict
wearing a half-(b) label. Every victim preamble is now plain rv32i with
reserved shamt[5]=1 shift forms that trap identically at both polarities, so a
stall means what it says.

shafe2.S is the MCU-level AFE2 test, selected by the afe2 tag, against
0x6C00-0x6F00 and vector 124; sar_macro_model.vhd is its converter model.
shafe.S is kept and headed RETIRED: it targets the afe_stub bank, which is still
a supported configuration and has no other end-to-end ownership test, and the
two tags can never stage together.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `verification/isa/{BUILD.bazel,defs.bzl,tests_image_contract.py}`,
`verification/isa/tests/rv32ua/fk51mp.S`,
`verification/isa/tests/rv32ui/{Makefrag,shafe.S,shafe2.S (new)}`,
`hdl/common/sim/sar_macro_model.vhd` (new),
`platform/common/python/{verify_stage,tb_vhd,ChipGenerator}.py` (F15/F22 hunks).

### C7 - TRM

```
TRM: close every dead cross-reference, cut the em-dashes, add the missing sections

The build reported "There were undefined references" on every run. All 39 were
acronym-package forward links from the glossary list to a \ac{} use that does not
exist anywhere in the manual; [noforwardlinks] drops the forward link and keeps
the hypertarget. AnalogChapter's reference to the placeholder register map is now
guarded on \ifcqanalog, because a configuration that ships the analog IP with
cqAfeStubs false renders the analog chapter without the generated one. make
trm-lint failed to catch either: the gate now fails on the pdflatex line itself
and prints the offending targets.

201 of 220 em-dashes are gone from the analog chapter, one decision per site;
the 19 kept are table cells meaning "not applicable". The 15 in the maestro2tex
caption configs went too, so a regeneration does not put them back. Thirteen
captions outside the 2-to-5-sentence rule were rewritten in the JSON first and
regenerated, so no caveat was dropped.

Three sections were missing their results. The four-channel macro gets its TB-09
row and a nominal-only caveat. The DAC section gets the bit-driver correction:
every generated table there was extracted with the 1.0 V standard cell that was
replaced on 2026-09-05, so the correction is stated once in prose rather than
patched into output the next extraction rewrites. The EIS section is corrected
to EIS through the real pixel, with the per-pixel table.

306 pages to 309, and no new warning of any class: 0 undefined references
(was 1), 0 hyper-reference warnings (was 78), 37 overfull hboxes worst 28.14 pt
(unchanged), make trm-lint pass.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: all 110 `implementations/asic/castalia/analog/*.tex`, the four new fragments
(`note_dacr2r12_driver.tex`, `note_quad_tb09.tex`, `tab_eis_pixel.tex`,
`tab_quad_tb09.tex`), `platform/common/latex/TRM.template.tex`,
`platform/common/latex/packages-commands.template.tex`,
`platform/common/latex/PeripheralIntroductions/{DEBUG-...-2026-08,SYSTEM-...-2026-07}.tex`,
`platform/common/tools/maestro2tex/configs/*.json` (10 files), `platform/common/Makefile`,
`platform/common/python/LatexUserGuide.py` (F10 prose hunks).

**The four new fragments must land in this commit.** `AnalogChapter.tex:81` references
`\ref{ss:quad}`, whose label is `note_quad_tb09.tex:47`; `DacR2R12.tex` and
`note_eis_accuracy.tex` `\input` the other three. Committing the tracked edits without
them leaves the TRM unbuildable.

### C8 - peripheral intros and suite documentation

```
Docs: give nine peripheral intros the section skeleton, and name the regression

check_intro_names.py grades every intro against one template. Nine
wound-configuration intros (DMA, EVFAB, I2CT, I3C, OneWire, PWM, QSPI, RTC,
TRNG) predate it and had no \section skeleton, which is why
penta_wound_afe_intro_names_test shipped tagged manual. They have it now and
the gate passes, so the tag can go.

platform/common/README.md states which suite is the regression: make verify
SUITE=full CONFIG=config/penta_wound_afe.json, 157/157 on 2026-09-05.
xcelium/riscv_test/behavioral_mp is a smoke, not the regression: it compiles the
same generated tape-out RTL but has no polarity gate and runs the DEFINES=(none)
image set, so a green run there covers the OFF-arm software only.

docs/index.html links the seven afe_rev2_*.html engineering notes the remaining
tape-out work is written against, and marks the two EIS-engine pages superseded.
implementations/asic/castalia/docs/tapeout_plan_2026-09-05.md is the campaign's
consolidated plan.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `platform/common/latex/PeripheralIntroductions/{DMA,EVFAB,I2CT,I3C,OneWire,PWM,QSPI,RTC,TRNG}-intro-castalia-2026-07.tex`,
`platform/common/README.md`, `docs/index.html`,
`implementations/asic/castalia/docs/tapeout_plan_2026-09-05.md` (new),
`implementations/asic/castalia/docs/commit_plan_2026-09-06.md` (this file, new).

---

### C9 - SystemRDL register descriptions, toolchain and gates

Commit message:

    registers: SystemRDL as the single source, with VHDL-authority gates

    Adds a hermetic SystemRDL toolchain (systemrdl-compiler 1.32.2, PeakRDL
    cheader and markdown exporters; no register-block generator), one .rdl per
    tapeout peripheral plus the chip address map, emitters that reuse the
    generator's own table classes for the TRM, MemoryMap.h fragments and VHDL
    constant packages, and Bazel gates that check every .rdl against the VHDL
    decode and the generator's slot map, with a three-mutation negative control.
    The VHDL stays authoritative; the first gate run caught the generator
    publishing AFE2 SAMPLESTEP and ATPSEL resets as 0 (VHDL: 7 and 0xF).

Files (from git status at 2026-09-10; R1 + R2 waves):

    M MODULE.bazel
    ?? hdl/common/periph/rdl/
    ?? platform/common/python/rdl_cheader.py
    ?? platform/common/python/rdl_chip.py
    ?? platform/common/python/rdl_configurator.py
    ?? platform/common/python/rdl_emit.py
    ?? platform/common/python/rdl_latex.py
    ?? platform/common/python/rdl_model.py
    ?? platform/common/python/rdl_negative_control_test.py
    ?? platform/common/python/rdl_vhdl.py
    ?? platform/common/python/rdl_vs_generator_test.py
    ?? platform/common/python/rdl_vs_vhdl_test.py
    ?? tools/rdl/

### C10 - register-map corrections read out of the RTL, and MemoryMap.vhd regenerated

Depends on the SystemRDL wave (R1/R2). Land it after whichever commit carries
`platform/common/config/rdl.json` and `platform/common/python/rdl_*.py`, because
`rdl_vs_generator_test` is the gate that grades it.

```
Generator: correct 82 register fields the RTL contradicts; regenerate MemoryMap.vhd

The .rdl descriptions read out of the RTL disagreed with generate.py's
hand-written PeripheralTemplates in 82 field-level places across ten blocks.
The RTL is the authority, so the generator moved. Sixteen of the eighty-two
are the MUTEXn owner width, which could only be corrected by regenerating
hdl/common/MemoryMap.vhd; that is done here, so the tracked package is again
byte-identical to the generator's output and check_memorymap_vhd_test grades
a file with no hand edits left in it.

Reset values that were published as zero and are not: CLINT MTIMECMPn{L,H}
0xFFFFFFFF (mtip starts low), SYSTEM DCOnBIAS 0x800, NFC0 CR 0x00001000 /
CFG 0x00000044 / TIM 0x088004D4, I3C0 CR.I3CSDAPP 1, DMA0 CRC 0xFFFF, EVFAB
CAP 0x010A1008, and the per-instance generics the template could not carry:
GPIO's RstValPx{OUT,DIR,SEL,REN,AFS} per port and I2C's default_SAD (0x79 on
I2C0, 0x23 on I2C1). The register index now takes its reset column from the
INSTANCE, like _BlockSize already takes the width.

Widths: GPIO PxOUTT / PxIF / PxTASK are num_pins = 8, not 32 -
ChangeGPIOPortSize's registersToChange list named three registers this GPIO
does not have and missed these three. DMA0Cn{SRC,DST,LEN} store and read back
all 32 bits; bits 31:17 are writable scratch and a bad pointer is rejected at
GO with CHnERR, not masked.

Access codes: DMA0CR.GO/ABORT are w strobes that read 0, NFC0CR.NFCHALTCLR is
w1, EVFCHENSET/CHENCLR are rw1 write-1 aliases of EVFCHEN, and NPUCR.NPUTHINK
is plain rw (a written 0 clears it).

PWRCTRL.TASKWKM at 0x4B1C was decoded by pwr_ctrl.vhd for read and write and
modelled nowhere. Added at word 7 with PWRTASKWKM[numHarts-1:1]; the MCU.vhd
emitter's PWRCTRL layout cross-check now requires the slot.

MUTEXn's owner marker is MW+1 = 4 bits, not 32: mutex_bank.vhd:70-71 zeroes
rdata_reg and then drives only rdata_reg(MW downto 0), so bits 31:4 read 0.
MW is mcu_vhd.masterW(), so the field follows the arbiter master count rather
than a literal 3, and emitMutexInstance raises if the two ever disagree. That
moves MTXOWN0..15_MSB 31 -> 3 in hdl/common/MemoryMap.vhd, regenerated here
(owner-authorised 2026-09-10). No RTL and no firmware reads MTXOWN*, and
mutex_bank compares the whole written word on release, so nothing on the chip
behaves differently; rdl_vs_generator_test goes 16 -> 0 divergences.

The same regeneration carries the rest of this wave's register data into the
package (PWRCTRL.TASKWKM, the NFCx block and the GPIO5 AF1 pin numbers, which
this configuration has and the 2026-08-16 snapshot did not) and closes two
generator defects that hand edits in that file had been covering: UseSRAMnn's
base-address comment assumed the RAM region starts at 0 and printed 0x4000 for
the 0x8000 TCM, and the RomSize / RamSize / corner-tile comments lost their
macro-authority clauses on every regeneration. With those emitted, the tracked
package is the generator's output verbatim again.

MUTEX and PWRCTRL intro prose follow: the owner marker's width, and the
task-wake mask.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files: `platform/common/python/generate.py`, `platform/common/python/Peripheral.py`,
`platform/common/python/mcu_vhd.py`, `platform/common/python/ChipGenerator.py`,
`platform/common/python/LatexUserGuide.py`,
`hdl/common/MemoryMap.vhd` (regenerated; the only RTL file in this commit),
`platform/common/python/rdl_vs_generator_test.py` (untracked, R1's - grades per elaborated
instance now), `tools/rdl/README.md` (untracked, R1's - the access-code vocabulary),
`platform/common/latex/PeripheralIntroductions/MUTEX-intro-castalia-2026-07.tex`,
`platform/common/latex/PeripheralIntroductions/PWRCTRL-intro-castalia-2026-07.tex`.

`platform/common/config/MemoryMap.json` moves with it and is gitignored
(`platform/common/.gitignore:3`). `platform/common/config/ChipConfig.resolved.json`,
`config/PadRing.json` and `docs/chip_configurator.html` are byte-unchanged by this wave's
`make generate` (resolved-config md5 `55a1daa1a89704476fe92f5aa1c07049` before and after).
`hdl/castalia/MemoryMap.vhd` is deliberately NOT re-synced - it is a stale 2026-08-16
snapshot of a different configuration, nothing grades or builds it, and syncing only it
would leave it inconsistent with its equally stale `hdl/castalia/MCU.vhd` (same class of
item as U-1).

The TRM register index is unchanged by the MUTEX correction (181 rows; `MUTEXn` still
prints size 4, access `rw`, reset `0x00000000`, because `_AccessSummary` skips reserved
fields). The MUTEXn register table in the peripheral chapter gains a `31:4 Reserved` row:
TRM 310 pages, 2,168,085 bytes, 0 undefined references, `trm-lint` clean.

`docs/afe_rev2_firmware_contract.html` section 6.1 carries the firmware-facing list and is
gitignored (`.gitignore:303`), so no commit carries it.

Conflicts with C2/C3 (`generate.py`, `mcu_vhd.py`) and C7/C8
(`LatexUserGuide.py`, the intro files): same files, different hunks. Land C10 last.

---

### C11 - the .rdl descriptions become the only register source

Depends on C9 (the SystemRDL toolchain and descriptions) and C10 (the register-map
corrections). Land it after both: it deletes the tables C10 corrected.

```
registers: make the .rdl descriptions the only source, and the generation hermetic

All twenty-two peripherals build their PeripheralTemplate from
hdl/common/periph/rdl/ through rdl_model.registerTemplatesFor(). generate.py
holds no register data at all: a width, an access code, a reset value or a
field description is written once, beside the RTL that implements it, and
reaches the TRM table, the register index, MemoryMap.h, MemoryMap.vhd, the
configurator and the register browser from there. 1452 lines of
register-table code are deleted (1227 by the first eighteen, 225 by the last
four); one _rdlRegisters() call replaces each block.

The last four - CLINT, MUTEX, IRQROUTER and PWRCTRL - are PARAMETERISED
SystemRDL components, because their register SET and their field GEOMETRY are
functions of numHarts, numMutexes, the arbiter master width and vectorsCount.
MSIPh and MUTEXn are register arrays; the MTIMECMPhL/H pair is a regfile array
on an 8-byte stride; the routing row is a four-word regfile array per hart;
offsets and field widths are expressions in the parameters.
_rdlRegisters() elaborates each with the numbers generate.py also hands the
RTL. Three things SystemRDL has no syntax for are user-defined properties in
vesta_udp.rdl, and they act only inside an addrmap that sets vesta_indexed:
vesta_name and {expression} rendering in it and in desc (an array is MSIP[0],
not MSIP0, and carries one desc for the whole array, while the published names
are MSIP0..MSIP4 and the prose says "hart 3"); vesta_live, for a field that
does not exist below a hart count (PWRCR.PWRGATE spans numHarts-1 downto 1,
an empty range at one hart); and vesta_values_*, an enumeration whose member
count is a parameter, because a SystemRDL enum is a static type whose values
must fit the field and MUTEX's owner is 4 bits here and 6 on argus. Two shapes
a parameter cannot express - a register that does not exist, and prose that
reads differently - are preprocessor guards, each written so that no defines
is the default five-hart chip.

The proof that it changed nothing is a byte-diff of the generation before and
after across ALL SEVEN configurations with a chip_artifacts target - castalia,
penta_wound, penta_wound_afe, penta_wound_afe_pt, argus (18 harts, 32
mutexes), mcu_hart (1 hart) and fpga (1 hart). config/MemoryMap.json, the
whole latex/TRM/include tree (604 files), out/software/include/MemoryMap.h,
out/hdl/MemoryMap.vhd and out/hdl/MCU.vhd are identical in every one. The
149-test suite over //platform/... //tools/rdl:all //hdl/common/tb:all
//opensource_sim/... stays green, identity gates included, and the TRM builds
to the same 315 pages and 2,187,639 bytes.

The four descriptions carry a layout FORMULA now, not one of its values, so
rdl_vs_vhdl grades the formula: each of the four re-elaborates its .rdl at
other hart, mutex and vector counts and compares against the generic decode
read out of the VHDL - clint.vhd's MTIME_W = ((4*NHARTS+15)/16)*4,
irq_router.vhd's NUM_EN_WORDS = (NUM_SRCS+31)/32, pwr_ctrl.vhd's NSRW =
(NHARTS+7)/8 and mutex_bank.vhd's owner_t array of MW downto 0.

One correction does move, and it is the same class the .rdl descriptions were
added to find: the per-TEMPLATE GPIO constants published 8-pin registers as
32 bits wide. ChangeGPIOPortSize narrowed the six INSTANCES and left the
template at its 32-bit default, so PxIN_MSB..PxTASK_MSB read 31 in
MemoryMap.vhd and Px*_PTR used MMR_32_PTR in MemoryMap.h while every instance
was 8 bits. gpio.rdl states the RTL width (num_pins = 8) once, for both.
hdl/common/MemoryMap.vhd is regenerated: 12 constants move 31 -> 07. Nothing
reads them - grep over hdl/, software/ and verification/ finds them declared
in the memory-map packages and used nowhere - and the register index and
config/MemoryMap.json already published 8, so no documented value changes.

Peripheral.IsGPIO size-checks only the pin-width registers now. It compared
every register and passed only because it ran BEFORE ChangeGPIOPortSize
narrowed them: PxAFS is four bits per pin and is legitimately 32 wide on an
8-pin port, which the old check would have rejected the moment the templates
arrived at their RTL width.

config/rdl.json is now the one registry: rdl_model reads its blocks from it
instead of restating them, its registerSource field says where each
peripheral's registers come from - "rdl" for all twenty-two, and no
peripheral is "generator" any more - and its parameters field names each
parameterised block's knobs. rdl_vs_generator_test holds the flag and
generate.py to the same story in both directions and rejects a hand-written
table for a peripheral flagged "rdl", so a deleted table cannot come back
unnoticed.

MUTEX's SystemRDL array is instantiated as MTX, not MUTEX: the published
register names come from vesta_name = "MUTEX{i}", and MemoryMap.h defines a
bare MUTEX macro for the block's typed pointer, which would macro-expand the
struct member PeakRDL-cheader emits for an array called MUTEX.
software/include/regs/{clint,mutex_bank,irq_router,pwr_ctrl}_regs.h are
regenerated for the array shape (CLINT_REGS->MSIP[h] rather than ->MSIP0);
every address is unchanged, castalia_regs.h is byte-unchanged, and nothing
in software/ or verification/ includes the four.

The generation action is hermetic on the descriptions: chipgen.bzl attaches
//hdl:rdl_sources to every chip_artifacts action, and stage_generate carries
systemrdl-compiler and hands the closure to the generator subprocess on an
explicit PYTHONPATH. systemrdl is no longer optional - a missing toolchain
stops the generation rather than emitting a chip with eighteen peripherals'
registers missing. The Makefile resolves a capable interpreter through
python/rdl_python.py, because the compiler needs Python >= 3.8 and several
hosts here ship a 3.6 as python3.

Leftovers closed: GPIO5 pin 0 carries rstAFS = 1 when NFC is present, so the
GPIO chapter's pin table and the register index print the same reset AF plane
and make generate stops warning about RstValP6AFS; the Debug Module's
DMI-space description, the one block with no register-index row, is emitted
as DEBUG-registers-rdl.tex and inputted by the debug chapter; and the NPU
chapter's mode/activation code table, a copy of NPUCR's own value
descriptions, is replaced by a reference to them.

Claude-Session: https://claude.ai/code/session_016qtJvKtLuonAvtu3a4sjUB
```

Files:

    M hdl/common/MemoryMap.vhd          regenerated; 12 Px*_MSB constants 31 -> 07
    M hdl/BUILD.bazel                   (C9's :rdl_sources filegroup, already listed there)
    M platform/common/BUILD.bazel       generate.py + the .rdl into rdl_vs_generator_test;
                                        hdl/common/periph/rdl staged into the 3 intro-name tests
    M platform/common/Makefile          GEN_PYTHON / GEN_PYTHONPATH for the generate target
    M platform/common/bazel/BUILD.bazel systemrdl-compiler on :stage_generate
    M platform/common/bazel/chipgen.bzl _rdl_srcs: //hdl:rdl_sources on every generation action
    M platform/common/bazel/stage_generate.py  _rdlPath(): the closure on the child's PYTHONPATH
    M platform/common/python/BUILD.bazel  :generate depends on :rdl_lib
    M platform/common/python/generate.py  -1452 register-table lines, +_rdlRegisters
                                          (with parameters/defines), GPIO5 rstAFS,
                                          _emitRdlArtifacts rewritten
    M hdl/common/periph/rdl/{clint,mutex_bank,irq_router,pwr_ctrl}.rdl
                                          parameterised components: register/regfile
                                          arrays, expressions in offsets and widths
    M hdl/common/periph/rdl/vesta_udp.rdl  vesta_indexed / vesta_name / vesta_index /
                                          vesta_live / vesta_values_* (R7)
    M platform/common/python/rdl_model.py  parameters and defines on loadBlock() and
                                          registerTemplatesFor(); the {expression}
                                          renderer; regfile flattening; vesta_live
    M platform/common/python/rdl_vs_vhdl_test.py  the four parameter sweeps against
                                          the VHDL's own generic formulas
    M software/include/regs/{clint,mutex_bank,irq_router,pwr_ctrl}_regs.h
                                          regenerated (array members; addresses
                                          unchanged) - overlaps C12's tree
    M platform/common/python/Peripheral.py  GPIO_PIN_WIDTH_REGISTERS; IsGPIO size check
    M platform/common/python/check_intro_names.py  rdl_names(): template spellings from the .rdl
    M platform/common/latex/PeripheralIntroductions/DEBUG-intro-castalia-2026-08.tex
    M platform/common/latex/PeripheralIntroductions/NPU-intro-castalia-2026-07.tex
    ?? platform/common/python/rdl_python.py        (new; the Makefile's interpreter resolver)
    ?? platform/common/config/rdl.json             (C9's - registerSource added)
    ?? platform/common/python/rdl_model.py         (C9's - reads rdl.json, sources= filter, memoised)
    ?? platform/common/python/rdl_emit.py          (C9's - non-memory-mapped blocks)
    ?? platform/common/python/rdl_vs_generator_test.py (C9's - the registerSource cross-check)
    ?? hdl/common/periph/rdl/debug_module.rdl      (C9's - three short title sentences)
    ?? tools/rdl/README.md                         (C9's - level 1 and 2 status, the registry)

`platform/common/config/MemoryMap.json`, `platform/common/out/` and
`platform/common/latex/TRM/` move with it and are gitignored.
`platform/common/config/ChipConfig.resolved.json`, `config/PadRing.json` and
`docs/chip_configurator.html` are byte-unchanged by this wave.

Conflicts with C2/C3 and C10 on `generate.py` and with C10 on `Peripheral.py` and
`hdl/common/MemoryMap.vhd`: same files, different hunks. Land C11 after C10.

---

## 3. Untracked files: add, ignore or remove

**Add, all 18.** None is a generated artifact and none is scratch.

| path | wave | why it is source |
|---|---|---|
| `hdl/common/periph/AFE2.vhd` | F7 | 394 lines of hand-written RTL; `//opensource_sim/penta_wound_afe` will not elaborate without it |
| `hdl/common/periph/BIASG.vhd` | B2 | 134 lines of hand-written RTL |
| `hdl/common/hart_tile_pt.vhd` | B2 | 277 lines; the topology-B tile wrapper `mcu_vhd.py` binds to |
| `hdl/common/sim/sar_macro_model.vhd` | F22 | 97 lines; sim-only converter model. Note the directory also holds gitignored vendor files (`ARM_IP_*.vhd`); this one is not matched by any ignore rule |
| `hdl/common/tb/AFE2_tb.vhd` | F7 | 426 lines; `//hdl/common/tb:AFE2_tb` is already declared in the tracked BUILD file |
| `verification/isa/tests/rv32ui/shafe2.S` | F22 | 586 lines; already listed in the tracked `Makefrag`, `verification/isa/BUILD.bazel` and `opensource_sim/isa/run_isa.sh` |
| `platform/common/config/penta_wound_afe.json` | F7 | 8 lines; named by `platform/common/BUILD.bazel:617` |
| `platform/common/config/penta_wound_afe_pt.json` | B2 | 9 lines; named by `platform/common/BUILD.bazel:631` |
| `platform/common/config/padring_pt.json` | B3, B2 | 460 lines; `generate.py:4179` opens it at run time, and `config_srcs`' `glob(["config/*.json"])` already makes it a hermetic build input. **Trim before committing**: the `_hook` key is a block of agent-to-agent instructions whose own `status` field says IMPLEMENTED. Replace it with a two-line provenance comment |
| `platform/common/latex/PeripheralIntroductions/AFE-intro-castalia-2026-09.tex` | F7 | 71 lines; graded by `check_intro_names.py` |
| `opensource_sim/penta_wound_afe/{BUILD.bazel,defs.bzl}` | F7 | the elaboration gate that caught the 128-source overflow; ran and passed in this session's regression |
| `opensource_sim/penta_wound_afe_pt/{BUILD.bazel,defs.bzl}` | B2 | same for topology B; ran and passed |
| `implementations/asic/castalia/analog/note_quad_tb09.tex` | F13, F26 | holds `\label{ss:quad}`, which a tracked file already references |
| `implementations/asic/castalia/analog/tab_quad_tb09.tex` | F13, F26 | `\input` by the above |
| `implementations/asic/castalia/analog/note_dacr2r12_driver.tex` | F16, F26 | `\input` by tracked `DacR2R12.tex` |
| `implementations/asic/castalia/analog/tab_eis_pixel.tex` | F17, F26 | `\input` by tracked `note_eis_accuracy.tex` |
| `implementations/asic/castalia/docs/tapeout_plan_2026-09-05.md` | coordinator | 189 lines; the plan `~/chips/castalia/tapeout_review/PLAN.md` symlinks to |
| `docs/afe2_chip_wrapper_patch.md` | F7 | 72 lines; the only versioned record of an edit that has to be applied to the untracked `innovus/` tree. Consider moving it under `implementations/asic/castalia/docs/` where the other chip documents live |

**Nothing to gitignore and nothing to remove.** The scratch and sidecar files earlier
waves reported (`fix_contributors.sh`, six `*.pre_*` sidecars under `hdl/` and
`platform/common/python/`) are already gone; a sweep of `hdl platform verification
software tools opensource_sim implementations` finds two `.pre_*` files, one gitignored
(`software/bootrom_mp/bin/rom.rcf.pre_entryvec`) and one tracked from before this campaign
(`tools/cosim/gate/flow/MCU_castalia.v.pre_d3`).

**Work that no commit will carry.** `genus/`, `innovus/`, `signoff_mp/`, `xcelium/`,
`cpf/` and `docs/publications/` are gitignored, and `docs/afe_rev2_*.html` is matched by
`.gitignore:303`. That means the firmware contract's rule R15, the ISCAS27 `ERRATA.md`, the
`hart_tile_pt` and `chip_pt` flow scripts and every DRC/LVS run stay outside git. So does
`~/chips/castalia/ic/` (the analog OA library) and `~/chips/castalia/{CLAUDE.md,
SIM_STATUS.md,simarchive}`. If any of that is meant to be versioned it needs a separate
decision; this plan does not touch it.

---

## 4. Pre-commit checks

### 4.1 Bazel, run now

```
tools/bin/bazel test //platform/... //hdl/common/tb:all //opensource_sim/...
```

**116 of 116 tests pass.** `INFO: Analyzed 224 targets`, `Found 108 targets and 116 test
targets`, `Executed 10 out of 116 tests: 116 tests pass`, elapsed 338.6 s (3,383 action
cache hits). Breakdown: `//hdl/common/tb` 15, `//opensource_sim` 9, `//opensource_sim/isa`
43, `//opensource_sim/mcu` 2, `//opensource_sim/mcu_hart` 2,
`//opensource_sim/penta_wound_afe` 1, `//opensource_sim/penta_wound_afe_pt` 1,
`//opensource_sim/pmp` 22, `//opensource_sim/rv4th` 1, `//platform/common` 19,
`//platform/common/python` 1. No failure, no flake, no error. Log:
`scratchpad/bazel_test.log`.

The four identity gates that would catch a hand-edited generated file all pass:
`check_mcu_vhd_test`, `check_memorymap_vhd_test`, `check_memorymap_h_test`,
`check_riscv_tb_vhd_test`, plus `generation_determinism_test` and
`check_configurator_sync_test`.

One test in `//platform/...` does not run under the wildcard:
`//platform/common:penta_wound_afe_intro_names_test` is tagged `manual`
(`platform/common/BUILD.bazel:702`). Run explicitly: **PASSED in 0.2 s**. See finding U-2.

### 4.2 TRM build, not re-run

F26's build is on disk and current. `platform/common/latex/TRM/TRM.log` (2026-09-05
20:48) reports **309 pages** and **zero** `There were undefined references` lines, against
306 pages and one such line at HEAD. F26's table: hyper-reference warnings 0 (was 78),
`LaTeX Warning: Reference ... undefined` 0, `??` in rendered text 0, overfull hbox 37 worst
28.14 pt (unchanged), overfull vbox 0, underfull hbox 210 (unchanged), `make trm-lint`
pass, wall 1 m 30 s. Not re-run: `make pdf` is about 92 s per pass and three passes are
needed, and nothing has changed the sources since.

`platform/common/latex/TRM/include/analog/` was refreshed at 2026-09-06 05:28 by a later
`make chip`; the four new fragments there are byte-identical in size to the sources, and no
PDF rebuild has happened since, so the 309-page log is still the log of the current tree.

**`make check-publish` will be red.** The published
`implementations/asic/castalia/docs/TRM.pdf` is tracked and dated 2026-08-30; the build is
2026-09-05 and 309 pages. F10 left it alone on purpose: republishing belongs with the
`penta_wound_afe` republish (TRM.template.tex's PENDING block, items D-1, D-4, D-5), not
with this campaign. Either commit with `--no-verify` and republish separately, or run
`make publish-chip CONFIG=config/penta_wound_afe.json` first and add `TRM.pdf` to C7.

### 4.3 Files two waves edited, and how to split them

No conflict markers anywhere in the tree, no duplicated Bazel target names, no duplicated
`--@GEN:@` markers, and **no whitespace-only file**: every one of the 165 modified files
still has a non-empty diff under `git diff --ignore-all-space`.

| file | waves | split point |
|---|---|---|
| `platform/common/python/generate.py` | F7, B2, B9 | F7 owns the hunks at `+368`, `+675`, `+1087`, `+3646`, `+5024`, `+5197`; B2/B9 own `+80` (`_PACKAGE_MODELS`), `+3970`, `+4321` (`_buildPackageData` pt branch) and the BIASG block at 2971-3002 |
| `platform/common/python/mcu_vhd.py` | F7, F11, B2 | F7: `+813`, `+1122`, `+2814`, `+3157`, `+4953`. F11: `+3569` (CLINT_SIP). B2: `+4475`, `+4535` (`hart_tile_pt` bind, per-tile a0) |
| `platform/common/python/tb_vhd.py` | F22, B2 | F22: `+21` (`tb-afe2-signals`), `+174` (`emitAfe2Signals`). B2: the `perTile` branch inside `__init__` at `+52` and the port emission at `+93` |
| `platform/common/python/verify_stage.py` | F15, F22, B2 | F15: `+1145`, `+1175`, `+1275` (cell-list anchors). F22: `+133` (shafe2 CATALOG row). B2: `+61` (afe2pt tag) |
| `platform/common/python/LatexUserGuide.py` | F7, F8, F10, B2 | F7/F10: `+990`, `+1026`, `+1065` (AFE prose), `+1662`, `+3765` (AFEx mapping). F8: `+1227` (private-band decode width). F10: `+70` (analog path guard). B2: `+1489` (`afeTopology` keyOrder) |
| `platform/common/BUILD.bazel` | F7, B2 | one 223-line block; F7's `penta_wound` / `penta_wound_afe` targets precede B2's `_pt` twins |
| `hdl/common/tb/BUILD.bazel` | F4, F7, F11 | F4: the ten `*_rtl` / `*_tb` pairs. F7: `afe2_rtl` + `AFE2_tb`. F11: `NUM_SRCS` 121 -> 125 |
| `docs/chip_configurator.html` | F7, F8, B2 | the `afe2` and `afeTopology` knob definitions are hand edits; the rest is one re-spliced `VESTA_DATA` blob, which is machine output and cannot be split. Regenerate once at the end with `make web-copy` |
| `hdl/common/periph/SPI.vhd` | F9, F12 | F9: the `s_rx_sreg` -> `s_rx_hold` rename and the 16-arm read mux. F12: `s_spi_teif` |
| `hdl/common/vesta/vesta.vhd` | F9, F12 | F9: the two sensitivity lists. F12: `gen_zcm_seq`, `is_compressed`, `sp_write_data` |
| `platform/common/config/ChipConfig.resolved.json` | F7, F11, B2 | two generated lines; regenerate once, commit with whichever generator commit lands last |

### 4.4 Changes that look unintended, or need a decision

**U-1 (MINOR). `hdl/castalia/tb/riscv_tb.vhd` and `hdl/common/tb/riscv_tb.vhd` were
byte-identical at HEAD (both blob `fcfcdd5`) and are not any more.** Both are checked-in
generated products of the same emitter. F4 regenerated both with the
`simulation_timeout_flag` fix; F22 regenerated only `hdl/common` with the
`--@GEN:tb-afe2-signals@` marker and the UART RX weak-`H` pulls, so the `hdl/castalia` copy
is short one 12-line hunk. Nothing catches it:
`//platform/common:check_riscv_tb_vhd_test` compares the emission against
`hdl/common/tb/riscv_tb.vhd` only (`platform/common/BUILD.bazel:358`). Fix: copy the
emitted file over `hdl/castalia/tb/riscv_tb.vhd` before committing C5, or state in
`hdl/castalia/README.md` that the copy is unchecked and stale on purpose.
(`hdl/castalia/MCU.vhd` is also stale, generated 2026-08-16 against `hdl/common`'s
2026-08-24, but that predates this campaign and F7 left it alone deliberately.)

**U-2 (MINOR). `penta_wound_afe_intro_names_test` is still tagged `manual` for a reason
that no longer holds.** F7 tagged it because nine wound-configuration intros had no
`\section` skeleton (`platform/common/BUILD.bazel:693-697`). F15 added the skeleton to all
nine later the same day. Run explicitly, the test passes. It is the only `manual`-tagged
target in the file, and its topology-B twin `penta_wound_afe_pt_intro_names_test` is not
tagged, so `//platform/...` grades one configuration and not the other. Drop the tag in C8.

**U-3 (needs a decision, not a defect). The two 2,780-line `.rcf` goldens are regenerated
binaries-as-text and account for 5,560 of the 10,881 changed lines.** They are correct
(all three copies md5 `99b0c95dfb3fc0da52a49d1a68efa904`) and they must move with
`start.S`, but the cut moved the first word, so `tools/cosim/check_gate_files.py`'s own
comment says the cosim boot-mode X pins at pc `0x5c` and `0x15c` are stale and the physical
`rom2k_hvt_pg` plate is not recompiled. Committing C4 records a ROM the signoff collateral
does not yet match. That is stated in the message; the follow-up work is a signoff job.

**U-4 (informational). `hdl/common/MCU.vhd` carries a one-line change to a file headed
"WARNING: Do not edit or modify this file!"** The campaign log records it as applied by
hand. It is nevertheless correct: `mcu_vhd.py` emits exactly that line
(`@@ -3353 +3569,2 @@`), and `//platform/common:check_mcu_vhd_test` passes, so the tracked
file equals today's emission. No action.

**U-5 (informational). `platform/common/config/ChipConfig.resolved.json` gains two lines
that are pure generator output** (`"afeTopology": "top_ports"`, `"afe2": false`), from
`make generate` runs by F11, F22 and B9 that each restored the shipped defaults.
`platform/common/config/PadRing.json` is tracked and is **not** modified, so B9's two
regeneration cycles were restored cleanly. No action.

**U-6 (informational). `docs/index.html` uses `&mdash;` in the new paragraph.** The
no-em-dash rule the campaign applied is a TRM-prose rule; the surrounding page already uses
the entity. Left alone.

### 4.5 Order of operations

1. Copy the emitted `riscv_tb.vhd` onto `hdl/castalia/tb/riscv_tb.vhd` (U-1).
2. Trim the `_hook` block out of `config/padring_pt.json`.
3. Drop the `manual` tag from `penta_wound_afe_intro_names_test` (U-2).
4. `make generate` once, so `ChipConfig.resolved.json` and `docs/chip_configurator.html`
   are a single machine-produced state rather than three interleaved ones.
5. Commit C1 through C8 in order. C2 and C3 both touch the generators, so C3's tests only
   pass with C2 in; C7 needs the four new `.tex` fragments staged with it.
6. Re-run `tools/bin/bazel test //platform/... //hdl/common/tb:all //opensource_sim/...`
   plus `//platform/common:penta_wound_afe_intro_names_test` after the last commit.
7. Decide the TRM republish (4.2) before or after; `make check-publish` is red either way
   until it happens.
