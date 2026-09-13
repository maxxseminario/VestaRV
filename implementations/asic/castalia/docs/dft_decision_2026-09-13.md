# VestaRV Castalia: scan DFT decision, 2026-09-13

Decision memo, not a flow change. Nothing in `genus/`, `innovus/`, the RTL or the pad ring
was modified; the Genus trial ran as a side cut into `genus/hart_tile_pt/out.t6dft*`.
Supersedes nothing until the owner rules on section 6; decision D11 in
`tapeout_review/DECISIONS.md` currently reads "no scan".

## 1 Current state: there is no DFT anywhere

A tree-wide grep for `define_dft`, `connect_scan_chains`, `check_dft_rules`,
`fix_dft_violations`, `dft_scan_style`, `convert_to_scan`, `scan_chain`, `scanDEF` and
`insert_dft` over every tracked `.tcl .sh .py .vhd .v .sv .json .md` (excluding `attic/`
and `bazel-out`) returns **zero hits**. So does `atpg`, `tetramax`, `boundary scan`,
`bsdl` and `stuck-at`. The word "scan" appears 62 times under `innovus/` and every one is
geometric (the PG clearance and via-repair coordinate scans); it appears in
`hdl/common/jtag_dtm.vhd` only as the TAP's own DR shift.

Five flow scripts mention DFT, all in the same negative sentence about latches
(`genus/hart_tile_pt/tcl/hart_tile_pt.genus.tcl:236`,
`genus/hart_tile/tcl/hart_tile.genus.tcl:191`,
`genus/MCU_PENTA/tcl/MCU_PENTA_hier.genus.tcl:283`,
`genus/MCU_PENTA_pt/tcl/MCU_PENTA_pt_hier.genus.tcl:329`,
`genus/MCU_PENTA_pt_b/tcl/MCU_PENTA_pt_b_hier.genus.tcl:367`): "untestable without
latch-aware DFT (this flow has none)". No RTL carries a `scan_in`, `scan_en`, `test_se` or
`test_mode` port.

The 270 `SDFF*` cells already in `hart_tile_pt.genus.v` and the 4,332 in
`MCU_PENTA_pt_hier.genus.v` are **not** scan. Genus maps an RTL enable flop onto a muxed-D
cell and uses its SI/SE pins for the functional enable. They are the reason
`convert_to_scan` is a required step (section 2.3).

### Tools and licences

`lmstat -a -c 5280@poseidon` (2026-09-13 00:44) issues every Cadence test feature and none
is in use:

| feature | issued | in use |
|---|---|---|
| `Modus_DFT_Opt` | 40 | 0 |
| `Modus_Hierarchical_Opt` | 40 | 0 |
| `Modus_common_ui` | 40 | 0 |
| `modus_atpg` | 40 | 0 |
| `modus_atpg_mcpu` | 40 | 0 |
| `dfsverifault` / `verifault` | 40 | 0 |

**Modus is not installed.** `/opt/cadence` holds `GENUS191 INNOVUS201 IC618 XCELIUM2009
PEGASUS221 PVS201 EXT191 SPECTRE191 SPECTRE201 ASSURA415 VIPCAT113` and no `MODUS`;
`which modus` fails, as do `lec` and `tmax`. So ATPG patterns cannot be generated on this
host today, and neither can fault grading. The licences say the tool may be installed; the
installation, the ATPG flow and its verification are work nobody has started.

Genus 19.15's own DFT command set is present and works: `define_dft` (with
`scan_chain`, `shift_enable`, `test_mode`, `test_clock`, `tap_port`, `jtag_macro`,
`boundary_scan_segment` subcommands), `check_dft_rules`, `report_dft_violations`,
`fix_dft_violations`, `convert_to_scan`, `connect_scan_chains`, `report_scan_chains`. The
trial below checked out `Genus_Synthesis` and `Genus_Low_Power_Opt` only. **No DFT licence
feature was requested and no denial was issued.**

### Library

`scadv10_cln65gp_hvt` carries a scan twin for every sequential cell the two netlists use:
48 `DFF*`/`SDFF*` pairs plus the always-on `A2SDFF*`, the `ESDFF*` and the multibit
`M2SDFF*` families. Swap cost, from `scadv10_cln65gp_hvt_tt_1p0v_25c.lib`:

| pair | plain | scan | delta | % |
|---|---|---|---|---|
| `DFFRPQX1MA10TH` (the dominant cell, 1,669 in the tile) | 9.600 | 11.600 | +2.000 | +20.8 |
| `DFFQX1MA10TH` | 8.400 | 10.800 | +2.400 | +28.6 |
| `DFFSRPQX1MA10TH` | 12.000 | 14.000 | +2.000 | +16.7 |
| `A2DFFQX1MA10TH` (always-on) | 8.800 | 11.600 | +2.800 | +31.8 |
| all 48 pairs | | | +2.0 to +3.2 | +16.1 to +32.0 |

## 2 Genus scan-insertion trial on `hart_tile_pt`

Side cut, `GENUS_OUT_DIR=out.t6dft*`, `GENUS_RPT_DIR=rpt.t6dft*`,
`GENUS_GATE_STRICT=0`; the flow of record in `genus/hart_tile_pt/tcl/` and its promoted
`out/` were not touched. The trial tcl is a copy of the flow with a DFT block inserted
before `syn_generic` and a stitching block between `syn_map` and `syn_opt`; everything else,
including the SDC, the clock-gating settings and all fourteen flow gates, is identical.

### 2.1 Results

Baseline is the promoted cut `genus/hart_tile_pt/out/` (2026-09-12 17:57), which the RUNBOOK
records as reproducible bit-for-bit.

| | baseline | scan, DFT rules unfixed | scan, rules fixed + `convert_to_scan` |
|---|---|---|---|
| total cells | 9,570 | 9,566 | **9,985** |
| standard-cell area (um2) | 41,955.2 | 42,181.6 | **47,254.4** |
| delta vs baseline | - | +226.4 (+0.54 %) | **+5,299.2 (+12.63 %)** |
| total area incl. `anatop_ch` + TCM (um2) | 219,058.2 | 219,284.6 | **224,357.4 (+2.42 %)** |
| sequential cells | 2,131 | 2,134 | 2,134 |
| sequential area (um2) | 20,949.6 | 21,200.0 | **24,714.4 (+17.97 %)** |
| flops on a scan cell | 270 (functional muxed-D) | 381 | **2,134 (100 %)** |
| DFT rule violations | n/a | 74 | **0** |
| scan chains | 0 | 2 | 2 |
| chain lengths | - | 59 + 59 = **118 (5.5 %)** | 2,097 + 37 = **2,134 (100 %)** |
| setup WNS (25 MHz, 40 ns) | **+9.248 ns** | +9.369 ns | **+9.333 ns** |
| Genus runtime | 04:45 to 04:54 | 05:06 | 05:24 |

Setup slack does not move: the tile's worst path is 9.2 ns inside a 40 ns period and the
worst endpoint in all three cuts is a clock-gating enable. The 85 ps difference is the
worst path changing instance, not a DFT cost. **Scan is nowhere near this tile's timing
limit.** Scan-shift timing was not measured: the flow has no scan-mode SDC, and building
one is part of the work section 5 prices.

All fourteen flow gates still pass with the chains in
(`out.t6dftfix4/GATES_RELAXED` records 0 downgraded failures): unresolved references 0,
clock-pin census 0 not waived, latch census 0 outside the allow list, `aon_drc_bufs` 0,
top-level leaf instances 1, B10-1 feedthrough census passed. Scan insertion disturbs none
of them.

### 2.2 Where the +5,299 um2 goes

| contribution | cells | area (um2) |
|---|---|---|
| flop swap `DFF*` to `SDFF*` (1,861 flops) | 0 | +3,764.8 |
| `MXT2X0P5MA10TH` test-clock bypass muxes | +262 | +1,152.8 |
| `AO22X0P5MA10TH` + `INVX1MA10TH` async-reset gating | +154 | +400.4 |
| remapping of the surrounding logic | -1 | -18.8 |
| total | +415 | **+5,299.2** |

The 262 muxes are the price of fixing the clock rule violations with
`fix_dft_violations -clock`, which bypasses each gated clock with a test clock. Hooking the
94 integrated clock-gating cells' test-enable pins to the shift enable instead costs no
cells at all, so about 1,150 um2 of the measured delta is an artefact of the blunt
auto-fix and a hand-written setup would not pay it.

### 2.3 What the trial cost to get right, and why it matters to the estimate

Four Genus runs. The first three produced misleading, plausible-looking answers, and each
failure is a step a real DFT insertion must carry:

1. **Rules unfixed: 118 of 2,134 flops on scan, and the run still completes.** Two rule
   violations gate the whole tile. `CLOCK-05` on `tile/core/cg_clk_cpu/CG1/ECK` (an
   internally driven clock) blocks 1,619 registers, and `ASYNC-05` on
   `tile/boot_fetched_reg` (a flop driving an async reset) blocks 2,938; after mapping the
   count becomes 74 violations, one per inserted ICG. `connect_scan_chains` then stitches
   only the 118 boundary flops that sit on the ungated `clk` and reports two tidy chains.
   Coverage would have been 5.5 % with nothing in the log calling it a failure.
2. **`fix_dft_violations` takes no output redirection** (`> file` is parsed as an argument
   and the command aborts, TUI-64), and it needs `check_dft_rules` run **immediately
   before it** in the same netlist state; a pre-synthesis rule check is invalidated by
   `syn_generic`/`syn_map` and the fix dies with DFT-307 "TDRC data not available".
3. **`convert_to_scan` is not optional.** With 0 rule violations and every flop mapped to
   an `SDFF*` cell, `connect_scan_chains` still stitched only 118 bits, warning DFT-512
   ("the non-scan flop is not included in a scan chain") and DFT-514 ("scan flop is mapped
   for non-DFT functional operation"). The 270 functional muxed-D flops own their SI/SE
   pins and the rest were mapped as non-scan. `convert_to_scan` reports "2,134 scan
   flip-flops mapped for DFT, 100.00 %" and the chains then take all 2,134.
   Without it the netlist also carried 2,202 `TIELOX1` cells against 186 in the baseline:
   2,016 tie-offs on unstitched scan inputs, +3,226 um2 of pure waste.
4. `set_db dft_min_number_of_scan_chains`, `dft_lockup_element_type` and
   `use_scan_seqs_for_non_dft` are not root attributes in Genus 19.15; chain count is set
   by how many `define_dft scan_chain` calls are made and by `-max_length`.

The two chains came out at 2,097 and 37 because Genus split them by clock edge, not by
length. A real insertion sets `-max_length` per chain; the numbers in 2.1 are insensitive
to that choice (the flops and their muxes exist either way).

## 3 Pad budget

Scan needs, per configuration: one shift enable, one test mode, one scan-in and one
scan-out per chain, and optionally a test clock (the functional clock pad serves if the
chip is shifted at the functional clock).

| configuration | dedicated pads |
|---|---|
| 1 chain, functional clock reused | 4 (SE, TM, SI, SO) |
| 2 chains | 6 |
| 4 chains (one per tile, parallel) | 10 |
| any chain count, shifted through the JTAG TAP | **0** |

Free package balls, from `platform/common/python/generate.py:2158` (topology A) and
`private/analog/platform/common/python/vesta_overlay.py:446` (topology B), cross-checked
against `platform/common/config/PadRing.json` and
`private/analog/platform/common/config/padring_pt.json`:

| topology | NC balls | usable for a digital signal | why |
|---|---|---|---|
| A, `castalia-lqfp100` + afe2 re-cut | 23, 24, 25 (W), 26 (S), 72 to 75 (E), 92 to 100 (N) = 17 | **8** (23 to 26, 72 to 75) | 92 to 100 sit inside the north PRCUT analog island, which carries no `VDDPST`/`VSSPST` pair. A digital pad there needs a new I/O supply pair on the island, which costs two of the nine. |
| B, `castalia-lqfp100-pt` | 23, 24, 25 (W), 72 to 75 (E) = **7** | **7** | Under resolution R1 the north and south edges are full: 11 relocated digital + 14 analog north, 15 digital + 12 analog south. |

So a 1-chain or 2-chain scan fits either topology on dedicated pads; 4 parallel chains do
not fit topology B and do not fit topology A without opening the analog island. On the die
side both W and E rows have physical room (LEFT is 22 pads over y 1070 to 1595 of a 2690 um
edge), so the binding constraint is package fingers, not pad sites.

The 7 free balls in topology B are all on the west and east edges, which are the far side
of the die from the four corner tiles the chains would live in. Any dedicated-pad scan in
topology B routes scan-in and scan-out across the full die.

**Sharing with JTAG costs zero pads.** The TAP at pins 47 to 51 (A) / 84 to 87 and 51 (B)
is already bonded and the `_checkDebugTransportBonded` guard in `generate.py:2183` enforces
it. Driving the chains from the TAP means a private IR opcode in `hdl/common/jtag_dtm.vhd`
selecting the chain as a data register, TDI to scan-in, scan-out to TDO, and shift enable
from a TAP-controlled bit. That is an RTL change, not a pad change. The cost is shift rate:
one bit per TCK, and `jtag_dtm.vhd:20` bounds TCK at about 7 MHz against a 24 MHz mclk, so a
2,134-bit chain is 0.30 ms per pattern and a 8,536-bit four-tile daisy chain is 1.2 ms.
Adequate for bring-up and chain-integrity screening, too slow for a volume test program.

## 4 What JTAG already gives silicon bring-up

`hdl/common/jtag_dtm.vhd` is a full IEEE 1149.1 TAP: 16-state controller, 5-bit IR, IDCODE
(Castalia `0x1CA57EEF`), `dtmcs`, the 41-bit `dmi` DR and BYPASS, with the sticky
busy/failed machine and the TCK-to-mclk crossing. `hdl/common/debug_module.vhd` is a
RISC-V Debug Module giving, per hart and at all five harts:

- halt, resume, single step, and halt-on-reset (`dbg_resethaltreq`), with halt groups;
- abstract access-register commands: every GPR and every CSR, read and write;
- a 2-word program buffer with an implicit third word, so arbitrary instruction sequences
  run on a halted hart;
- memory read and write anywhere the hart can reach, including its own TCM, by `lw`/`sw`
  from the program buffer (`debug_module.vhd:3`);
- hart discovery and `anynonexistent` probing, hart availability reporting.

Not present, by design (`debug_module.vhd:4`): System Bus Access (`sbcs` reads zero),
hardware triggers/watchpoints, and any boundary-scan register. The JTAG bench passes 17/17
at NHARTS=5 with 51 checks (campaign log, F11).

For bring-up this means the full architectural state of every hart is readable and writable
from four pins without running any chip software, and a failing hart can be stepped
instruction by instruction. What it cannot do is see a flop that is not architectural
state: a pipeline register, an FSM state bit, a FIFO pointer, the QSPI shifter, the AFE2
control registers' shadow. Nor can it distinguish a systematic fab defect from an RTL bug
in the part of the tile that is replicated four times, which is precisely the failure scan
exists for. Outside JTAG the chip's own observability is the TRAP pin (GPIO6), the two
UARTs, and the analog test pads ATP0/ATP1.

## 5 Full-chip estimate, and what a late decision costs

`MCU_PENTA_pt_hier.genus.v` carries 24,404 sequential cells: 19,826 plain `DFF*`, 4,273
functional `SDFF*`, 246 always-on `A2DFF*`, 59 `A2SDFF*`. Standard-cell area is 530,891.2
um2 of the 1,946,666.8 um2 total (the rest is 15 timing models: 4 `anatop_ch`, the TCMs and
the ROM).

| basis | delta (um2) | of chip std cell | of chip total |
|---|---|---|---|
| library flop swap only (20,072 conversions) | **+40,436** | +7.6 % | +2.08 % |
| scaled from the measured tile (2.483 um2 per flop) | **+60,600** | +11.4 % | +3.11 % |
| four tiles only (4 x the measured +5,299.2) | **+21,197** | +4.0 % | +1.09 % |

**No die area is at stake.** The 2,690 x 2,690 um die runs at design density 0.129 (P15,
measured on the placed `b1` database); +60,600 um2 takes it to about 0.143. The chip is
pad- and macro-limited, not cell-limited, and nothing in the floorplan moves.

Deciding late is the expensive part, because the boundary changes:

| artefact | change |
|---|---|
| RTL | `hart_tile.vhd` / `hart_tile_pt.vhd` gain 4 to 5 ports; `MCU.vhd` gains the chip-level scan ports; both are generator output, so `platform/common/python/` and a config knob change with them |
| Genus tile flow | DFT block, `convert_to_scan`, chain definition, plus a chain-count/length census in the gate set |
| Genus assembly flow | the four tile netlists become preserved scan segments to be stitched, not opaque blocks |
| Innovus tile | scanDEF export, post-placement scan reorder, 5 new LEF pins (356 to 361), tile re-harden (about 15 min) and re-signoff (blockdrc, ant25, Pegasus LVS) |
| Innovus chip | pad instances, the SDC generator, a chip re-cut (about 2 h) and a full re-signoff (chipdrc, ant25, LVS) |
| package | `generate.py` and `padring_pt.json` both change, and `_buildPackageData` FATALs if they disagree; the LQFP-100 bonding diagram is redrawn |
| verification | a scan-shift gate-level row; ATPG needs a tool that is not installed |

Against that, taking the decision now costs one Genus flow edit and one tile re-harden that
is already scheduled.

## 6 Recommendation

**Confirm D11 (no scan) for this tapeout, and take the pad reservation instead.**

The argument is not cost. The measured cost is small: +12.6 % of tile standard-cell area,
about +3 % of chip cell area, zero die area, zero timing. The argument is that scan
hardware with no pattern generator is hardware that cannot be used on this run:

- Modus is not installed on this host. The licences are issued, so the tool could be
  installed, but the installation, the ATPG flow, the fault model setup, the pattern
  verification and the tester program are all unstarted work, and none of it is on the
  path to a cut.
- The chains would ship untestable beyond a flush/chain-integrity shift, which does prove
  the clock tree, reset and shift path but finds none of the defects scan is bought for.
- The JTAG Debug Module already gives full architectural-state access at all five harts,
  verified, which covers bring-up.
- This is a prototype run, not a volume part, so there is no yield screen to feed.

**If the owner wants insurance, the smallest useful variant is scan on the tile macro
only**, and it must be decided before the tile is re-hardened:

- one chain per `hart_tile_pt`, 2,134 bits, four tile macros;
- hart 0 (the orchestrator) and the peripherals excluded, so 8,536 of 24,404 chip flops
  are covered, **35 %**, and it is the 35 % that is replicated four times and that
  functional test can least localise;
- area +21,197 um2, +4.0 % of chip standard-cell area, +1.09 % of the total;
- tile LEF 356 to 361 pins; the four tile chains daisy-chained at chip level give one
  8,536-bit chain needing **4 pads** (SE, TM, SI, SO), which fits topology B's 7 free balls
  and topology A's 8;
- or **0 pads** by driving that chain from the existing TAP through a private IR opcode,
  at 1.2 ms per pattern, which is the right trade for a bring-up-only chain;
- the RTL, LEF and pad decisions are then frozen even if ATPG never runs, and installing
  Modus later turns the reservation into coverage with no silicon change.

Rejected: full-chip scan on dedicated pads (4 parallel chains need 10 balls against 7 free
in topology B), and scan compression (`dft_compression_*` exists in Genus but needs
`Modus_DFT_Opt` and a tool that is not installed).

## 7 Artefacts

| item | path |
|---|---|
| trial tcl, unfixed rules | `<scratchpad>/t6/hart_tile_pt_dft.genus.tcl` |
| trial tcl, rules fixed + `convert_to_scan` | `<scratchpad>/t6/hart_tile_pt_dftfix4.genus.tcl` |
| side cuts | `genus/hart_tile_pt/out.t6dft`, `out.t6dftfix`, `out.t6dftfix2`, `out.t6dftfix3`, `out.t6dftfix4` (each carries `GATES_RELAXED`; none promotable) |
| reports | `genus/hart_tile_pt/rpt.t6dft*/hart_tile_pt.genus.{dft_rules_presyn,dft_rules_postmap,dft_rules_postfix,scan_chains_final,gates,area,timing}.rpt` |
| logs | `genus/hart_tile_pt/log/hart_tile_pt.t6dft*.log` |
| licence evidence | `lmstat -a -c 5280@poseidon`, 2026-09-13 00:44 |
