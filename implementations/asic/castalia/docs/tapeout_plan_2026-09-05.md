# Castalia tapeout plan, 2026-09-05

> **Analog interfacing collateral lives outside the public tree.** The AFE2/BIASG RTL,
> their `.rdl` descriptions and C headers, the AFE-bearing configurations, benches, ISA
> tests and lab tools were removed on 2026-09-11 and kept in the gitignored
> `private/analog/`, which mirrors their original paths. See `private/analog/README.md`.

Consolidated from the nine-area review of 2026-09-05 (raw reports and the decision list:
`~/chips/castalia/tapeout_review/`). Every claim below is traced to an executed artifact in
those reports. Cut of record: `MCU_castalia_penta` wq22e (2026-09-02), tile `hart_tile`
2026-08-26 05:20. Repository checkout: `~/vestarv` on branch `docs/relocate-vesta-docs-pointers`
(no `multicore-mp` branch exists; CLAUDE.md is stale on this).

## 1 Goal and scope

Tape out the five-hart Castalia SoC with the four-channel `anatop` AFE integrated, the
Genus + Innovus flow re-run clean (setup and hold on coupled-SI parasitics, Innovus DRC and
antenna clean, Calibre chipdrc down to waivable classes, Pegasus LVS MATCH), the software,
tests and documentation consistent with the shipped configuration. Dummy fill, seal ring and
the fab deliverable checks are deferred by the owner and listed in section 7.

## 2 Blockers (state of record)

| # | Blocker | Evidence | Owner of the fix |
|---|---|---|---|
| B1 | JTAG/debug transport synthesized to tie cells: `dm0` 99 tie cells, `dtm0` 43; `tdo` tied low into PAD_TDO. The Genus prep strips `ENABLE_DEBUG => CORE_ENABLE_DEBUG`, both entities default to false. | 05 F1, 06 F6 | F2 (Genus) |
| B2 | No analog interface in the tapeout netlist: the full-peripheral configuration sets `cqAfeStubs=false`; 0 AFE instances in the Genus and P&R netlists; MCU has no analog ports; 8 `PDB3A_G` pads with no core connection. Each `anatop_pixel` needs 50 control bits, SAR clock and reset in, 11 bits out. | 02 B-1, 08 F5 | F7 (AFE2) |
| B3 | The assembled analog tops (`anatop`, `anatop_channel`, `anatop_pstat`, `anatop_controlamp`, `anatop_dacsupply`) are absent from the OA library since the 2026-08-26 write; no backup existed. `anatop_pixel` is the only assembled channel and has no routed layout. | 01 F1, 03 F-1 | new wave (section 5) |
| B4 | The four reserved analog windows cannot reach a pad or the core: the tile obstructs M1 to M8 over its footprint, all 281 tile pins sit on the centre-band edge, no pad faces a window. | 06 F7 | decision D17 |
| B5 | Signoff timing never ran on coupled-SI parasitics: wq22e used `setDelayCalMode -SIAware false` and `rc_decoupled`. Re-timed with coupled SI on 2026-09-05 (F6, read-only): setup WNS +0.012 ns (the quoted +0.239 was 95 % uncomputed crosstalk), hold WNS -0.003 ns at three `hart_tile` boundary inputs (`hart3/sh_rdata[19]`, `[27]`, `hart1/mtip_in`), still at 25 C RC corners. Five generated clocks were sourced with the wrong edge (ICGs fed by the inverted clock), handing crossing paths a phantom 20 ns. The tile's own signoff extraction aborted (`tech_file = ""`). | 06 F1 F2, 06a F2, F6 | F3, F6 |
| B6 | The synthesized RTL is not the simulated RTL: `hdl/common/MCU.vhd` (penta.json), the full-peripheral Genus staging copy of `MCU.vhd` (full-peripheral configuration, 733 diff lines) and `hdl/castalia/MCU.vhd` (older) are three variants; `NUM_IRQ_SRCS` 121 vs 124. | 04 F2, 08 F3 F4 | F7 (single config: the AFE overlay configuration) |
| B7 | DAC bit drivers in `anatop_pixel_dacR2R12` are 1.0 V HVT core cells (`AND2X8MA10TH`, 24 per pixel) on the 2.5 V rail, schematic and layout. | 01 F2 | F1 |
| B8 | The tile GDS of record carries two real DRC results (`M1.S.5`, `M2.S.2`) that Innovus did not gate; the `pg_clearance.tcl` that ran is not the one on disk. | 06a F1 F5 | F3 |
| B9 | 22 real chipdrc results on wq22e (4 `M4.S.1` at tile corners, 3 pad risers, 4 VIA4, 9 signal spacing, 2 tile-internal); none fixable by `ecoRoute` as the flow stands. | 07 F4, 06 F4 | F6 step 5 |
| B10 | RTL-vs-netlist equivalence has never been checked; no `check_design`, no `check_timing`; 263 inferred latches (vesta `sp_write_data`, `div` result, SPI `s_SPIxRX`). | 05 F2 F4 F5 | F2, F9 |

## 3 Decisions

Owner-stated: AFE on this tapeout; EIS island dropped (potentiostat + square-wave vref +
firmware); dummy fill deferred; priority is the Genus + Innovus flow; Opus-class agents.

Defaults taken by the review (override by editing `tapeout_review/DECISIONS.md`):

- D1 Debug stays in scope; `ENABLE_DEBUG => true` restored for `dm0`/`dtm0`.
- D2 14 north pads: CE/RE/WE x4 + ATP0/1, contiguous with AVDD/AVSS; no RE2 pads.
- D3 Level shifters (1.0 V to 2.5 V, 200 bits) live inside `anatop_quad`.
- D4 Bias nets inside `anatop_pixel` become local nets; the rev-1 global biasgen path is archived.
- D5 to D7 DAC drivers to `anatop_and2`; mux slots re-paired; `ATP` is a pixel output.
- D9 `Better_ADCs` (a symlink into `/home/smcrobert2`) is snapshotted into `castalia` as `anatop_sar_*`; `tb_utils` benches copied as `tb_*`.
- D10 EIS island archived to `~/backups/eis_island_20260905.tgz` then deleted (deletion pending owner go).
- D11 No second R_CAL ladder, no `anatop_cdac_mom` swap, no scan.
- D12 The AFE2 peripheral derives the 20 MHz SAR clocking from mclk.
- D13 `hart_tile` is re-hardened once (tile DRC, latches, Quantus RC base, `pg_clearance`), then the chip is re-cut.
- D17 One `anatop_quad` macro in the north-centre corridor (x 680 to 2010, y 1809 to 2690) under the analog pad block; the four corner windows stay empty. Budget about 1000 x 450 um (F18 measured about 440,000 um^2; the placeholder LEF was regenerated at that size before the d13a chip cut).
- D18 Coupled-SI Quantus signoff at ss/125 C and ff/-40 C, setup and hold, FATAL on WNS < 0.

Open for the owner: `UART.vhd:530` `RX_REN` (an enabled UART with an unconnected RX pin
self-triggers its receiver; enabling the pull-up is a one-line RTL change that alters the
netlist, F21); `anatop_tia_rprog` unit pitch and `anatop_and2_dac` finger width (F18);
`make_ram_deposit.py` zeroes only the shared banks, so 3,539 X-data writes come from
un-deposited tile TCM tails at gate level (F21); per-channel `En` pin (D8); vcm/RE tap buffers in the pixel (02 B-6);
deletion go-ahead for the stale pixel views and the EIS island; reclaim of about 30 GB of
superseded signoff libraries and run trees.

## 4 Fix waves, 2026-09-05 (status at 15:00)

Done: F1 to F10. Running: F11 (regression on the AFE overlay configuration), F12 (generated clocks,
resynthesis, LEC), F13 (`anatop_quad` wrapper, bench, LEF), F14 (SAR/DAC/pixel re-runs).

New facts from the fix waves:

- The `Better_ADCs` SAR flip-flop cells netlisted as empty subcircuits (never Check-and-Saved); every schematic-level SAR result before 2026-09-05 ran without the SAR logic. The `anatop_sar_*` copies netlist correctly and `px_zero.v_rdy_p` passes (F1).
- The mask ROM was re-cut (stack init contract, bounded flash-boot polls, WDT armed): new image `99b0c95d`, 7,532 of 8,192 B. The `rom2k_hvt_pg` plate must be recompiled before the next cut (F8, F11).
- 1201 sequential clock pins in `MCU_PENTA` (897 in soft logic, 108 in the orchestrator) and 44 in `hart_tile` have no clock waveform: the muxed and divided clocks were never declared, so those registers were never timed (F2; fix in F12).
- `hdl_error_on_latch` trips on two further RTL sites (`csr_unit.vhd:463`, `NFC.vhd:600`) beyond the three fixed in F9 (F2; fix in F12).
- Coupled-SI re-time of wq22e: setup +12 ps, hold -3 ps; five generated clocks were edge-wrong (F6).
- The JTAG bench carried a four-week-old stale `hartinfo` assertion; corrected, 16/17 then re-run (F9).
- The TRM republish path deleted the analog chapter under any full-peripheral config; fixed (F10).


| Wave | Scope | Report |
|---|---|---|
| F1 | Analog schematic repairs: ATP symbol, DAC drivers, local bias nets, mux re-pair, `Better_ADCs` and `tb_utils` snapshots, `TGNX2A` repoint, ADC grid snap. Additive only. | `reports/F1_analog_schematic_fixes.md` |
| F2 | Genus: debug restore + FATAL census, `check_design -all`, `check_timing`, `hdl_error_on_latch`, I/O constraints, clock fixes, hygiene. | `F2_genus_fixes.md` |
| F3 | `hart_tile` Innovus scripts: Quantus tech file, Wiring gate, `pg_clearance` provenance, `flash_clk_mem` source, SDC library names, LEF M2 stubs, `verifyPowerDomain`. | `F3_hart_tile_innovus_fixes.md` |
| F4 | Testbenches: SYSTEM_tb widths, dbg_dmi C5, pwr_ctrl at shipped generics, ten new GHDL targets, tile-ISA objdump gate. | `F4_testbench_fixes.md` |
| F5 | Signoff hygiene: cut-knob derivation and ingest guard, legacy-block fence, strmin gate, LVS negative control, ERC baseline, DRC waiver skeleton. | `F5_signoff_hygiene.md` |
| F6 | Chip Innovus flow: coupled-SI signoff setup+hold with hold ECO, corner temperatures, SDC generator, verification gates, fenced `ANATOP_INTEGRATION` block and 14-pad list. | `F6_penta_innovus_fixes.md` |
| F7 | AFE2 peripheral (RTL, generator, the AFE overlay configuration with Bazel gates, bench), pad-ring model, wrapper-netlist patch. | `F7_afe2_peripheral.md` |
| F8 | Boot ROM: stack init, flash-boot timeout and WDT, ROM image symlinks in gate sims, header contradictions, sidecars. | `F8_bootrom_fixes.md` |
| F9 | RTL: three latch sites, sensitivity lists, TIMER CDC, CLINT mtime race, irq_router, trstn path, fk51mp test contract. | `F9_rtl_fixes.md` |

### 4.1 Second-round waves (status at 18:30)

Done: F11 regression on the single-source RTL (147/147, full-peripheral verify 157/157, cosim
8/8, JTAG at five harts 17/17 and 51 checks); F13 `anatop_quad` (4 x pixel + 200 shifter
bits + ATP grant; TB-09 top_op/top_mix/top_xtalk/top_pwr pass; placeholder LEF 760 x 240 um
at `innovus/common/shared/anatop_quad/`); F14 re-runs (1.63 V SAR span is the extracted
CDAC; AFE2 capture window safe with 50 ns margin at 20 MHz, 83 ns at 12 MHz; pixel
regression clean); F15 ROM signoff collateral from the re-cut plate, `make verify` on
the AFE overlay configuration, Bazel 112/112; F16 DAC driver (`anatop_and2_dac`, Ron 104/47 ohm vs
the 1.0 V cell's 117/68; INL 0.376 LSB, MC monotonic yield 42 %). Running: F12
(generated clocks, resynthesis, LEC), F17 (square-wave EIS benches SQ-01/02/09), F18
(rev-1 leaf layouts copied, per-cell DRC v2.6 + LVS harness, layout work list).

Applied by the main agent: `irq_router` CLINT-ID generic map in `hdl/common/MCU.vhd`;
AFE2 `MUX.ATPSEL` resets to 0xF (parks every site off the shared test pads) with the
bench updated; 57 GB of raw psf from the quad runs deleted (numbers archived).

### 4.2 Third-round results (status at 21:00)

- F17 square-wave EIS through the real pixel (`tb_anatop_eissq`, 6 tests, 26 runs): settled |Z| within 0.015 %; demodulator exact to 0.01 %; converter adds +0.160 % and 0.063°; code stream reconstructs to 0.305 LSB rms; ratio-calibrated R_ct/C_dl within 0.15 % to 5 kHz once the firmware restores the R_f·C_F pole (phase error otherwise +1.16° at 1 kHz, +11.5° at 10 kHz). Firmware-contract corrections: step settling is R_f·C_F-limited (3 to 5 us), not 5 τ_e; square-wave compliance is a charge limit (C_dl·ΔV into C_F, about 1.7 nF at ±16 codes), not R_f·I; the R_s = Re(Z(f_top)) estimator carries a +9.9 % structural bias. The published ±0.573° band edge at 5.3 kHz was measured without C_F; with 22 pF it is 1.05° and the TIA loop gain margin drops to 9.8 dB against a 10 dB spec. The extracted DAC view drops `mismatchflag` on the 76 ladder resistors, so MC through it is silently mismatch-free until the view is rebuilt.
- F18 analog physical prep: 13 rev-1 leaf layouts copied in (4 arrived with phantom `potentiostat_final` masters, repointed); per-cell harness `signoff_mp/analog_cell_signoff.sh` on the v2.6_2a deck over 63 cells: 44 LVS MATCH, antenna clean, every tapeout-path cell density-only in DRC; macro footprint about 440,000 um^2, LEF regenerated at 1000 x 450 um; work list in `signoff_mp/ANALOG_LAYOUT_WORKLIST.md`.
- F23: `anatop_biasgen_local` LVS MATCH after restoring the three Modgen dummies (electrically neutral to 7 figures); all five foreign-sourced extracted views rebuilt from castalia geometry; zero foreign inheritances remain in the library.
- F20/F21/F22 gate level: 13 of 13 rows pass on the promoted netlist (the `shirq` hang was X from the floating UART RX pad; weak pulls added to the generated testbench); JTAG through real cells; the AFE2 register/conversion/IRQ test `shafe2` passes on RTL and at gate exposed that the netlist predated the ATP-select reset, hence the d13b resynthesis (F24).

### 4.3 Physical re-cut d13a (status at 23:30)

- Tile of record: `hart_tile` d13a attempt 7 (attempts 1 to 6 were flow-script defects exposed by the new netlist's placement, each fixed at source: repeater site selection under the M7 VSS column, `addStripe` trimming the mini-strap, the frozen PG4/F2g patch coordinates, the two-corner Quantus log parser, the tap-row check). Gates: Wiring 0, MINCUT 0, setup +0.350 ns and hold +0.035 ns on Quantus parasitics, Calibre blockdrc real results 2 (`M3.S.2`, carried for waiver), ant25 0, Pegasus LVS MATCH.
- `MCU_PENTA` d13b promoted (F24): only the AFE2 bodies differ from d13a; gates unchanged; gate regression 14 of 14 including the TCM aperture row under SDF (F25).
- Chip cut d13a: SDC generator repaired and AFE2 port budgets added; wrapper netlist carries the 14-pad north band and the `anatop_quad` black box (1000 x 450 um at x 845, y 2180) with a pin-accurate placeholder GDS/CDL and a minimal `.lib`; the first full run reached placement and failed at the electrode-net attribute step on non-legacy Innovus syntax; the resumed run fixes that and continues through signoff (F19, in progress).
- Documentation: firmware contract R7 amended, R12 to R14 added, AFE2 register map in §1.10; TRM EIS notes now state the C_F condition and the real-pixel numbers, TB-09 and the DAC driver subsections added; TRM builds with 0 undefined references and 0 dead links (F26).

## 5 Remaining path to the next cut (ordered)

1. Done (F13): `anatop_quad` schematic, symbol, TB-09 bench, placeholder LEF/CDL.
2. Done (F13). Open: a minimal `.lib` for the macro's clock input pins if Innovus refuses a LEF-only macro with clock pins (rom2k precedent).
3. Resynthesis: `hart_tile` (latch fixes) then `MCU_PENTA` from the AFE overlay configuration with debug restored; LEC (Conformal) RTL vs netlist for both.
4. Tile re-harden with F3; chip re-cut with F6 and the `anatop_quad` LEF; coupled-SI signoff; `penta_era`; ingest + chipdrc + ant25 + LVS with the knobs moved to the new tag.
5. Analog layout: `anatop_tia_rprog`, `anatop_tia`, `anatop_pixel` (pin labels, on-grid ADC), `anatop_quad`; per-cell blockdrc v2.6_2a + ant25 + Pegasus LVS; `castalia_sign` builder; reference library for the SAR sub-cells in `strmin/reflib.list`; CDL into `lvs_include_chip_penta`.
6. Square-wave EIS verification through the real pixel: the SQ-00 to SQ-09 Maestro plan in `reports/02_eis_and_ada_interface.md` Part A3, plus READY width and data hold on the extracted converter.
7. Gate-level regression on the new netlist (cp5 was the last, two revisions stale); JTAG bench at NHARTS=5; the single-source harness alignment named in F9.
8. Documentation: republish the TRM from the AFE overlay configuration; errata list in `reports/09_docs.md` (18 items); ISCAS27 paper is a rev-1 draft, the fact-checked successor is `~/work/ieee/ISCAS27/latek/iscas27.tex`; `SIM_STATUS.md` rewrite.

### 4.4 Chip cut d13a, resumed (status 2026-09-06 02:40)

Attempts 2 to 4 of the chip cut each removed a flow defect (read-back gate type, obsolete `optDesign -si`, eight false clock-gating hold checks on the one-hot glitch-free mux, pad straps overshooting the port by 0.1 um, the multi-corner Quantus log regexp). Attempt 4 is the furthest any Castalia cut has reached: routed, extracted, setup and hold timed on coupled-SI Quantus at four views, hold ECO, re-extracted; setup +37 ps, hold -39 ps over 16 `hart_tile` boundary inputs at ff/-40 C, antenna 0, one single-cut via on a clock net. Attempt 5 runs with the hold ECO target at 80 ps and the tile's marker-driven via repair ported into the chip flow.

### 4.4a Chip cut d13a closed (2026-09-06 12:41)

Twelve chip attempts. Attempts 5 to 11 each removed one flow cause: the hold ECO target
(80 ps regressed setup), hold uncertainty 100 to 50 ps (rule 11), no delay cells for the
hold fixer, four boundary nets the fixer silently refused (in-cut repeaters, WQ26c), a bare
`ecoRoute` re-routing far beyond the split nets (scoped routing), and finally `ecoPlace`
running a global legalization that moved 422 instances. Attempt 12: setup +83 ps and hold
+1 ps at four coupled-SI views, 0 violating; unwaived Wiring, Short, SameNet, Overlap,
dangling and antenna all 0. GDS `out/MCU_castalia_penta.d13a.gds2` (md5 `5b6ebe3e`).
Signoff on it: ant25 clean; chipdrc 1900 = 1518 pad-kit ESD (waived class) + 64 density
(fill deferred) + 62 carried real results + 256 new `PO.R.8` floating-gate results in the
row band under the macro (root cause in progress, re-cut d13b); LVS mismatch only from the
schematic-side `anatop_quad` stub not reaching the Verilog reader (collateral fix). Two
latent findings: 110 (wq22e) / 147 (d13a) region-fence violations inside the orchestrator's
soft tile that no gate ever checked; ERA cannot load current into abstract-only macros.

### 4.4b Chip cut d13b, cut of record for topology A (2026-09-06 17:20)

`out/MCU_castalia_penta.d13b.gds2` (md5 `2eecd8ce`): setup +55 ps, hold +1 ps at four
coupled-SI views, all Innovus gates passed. The sleep-chain buffer cell is now integrated
(its kit LEF declares a different site than the chip; a single retargeted-macro LEF and
VSSG/VDDG global connects fixed it; the buffers were then removed as redundant, so netlist,
DEF and GDS agree). Signoff: chipdrc 1805 (pad-kit ESD 1518, density 64, carried real 49,
`PO.R.8` 174 of which 122 at the flow's other row-cut sites and 52 in the tile), ant25
clean, LVS one unmatched instance = the placeholder macro (W-D13B-1). Flow hygiene done
for both A blocks (chip: 35 live scripts to 9, one KNOBS header with 24 knobs,
`ANATOP_INTEGRATION=0` as the owner's drop-in switch; runbooks; attics indexed); the tile
re-hardens from the runbook to identical gate numbers (numerically deterministic, GDS md5
differs). Final for this campaign: four tap-termination recipes for `PO.R.8` (packed
strips, single taps, surgical, fragment fill) each created min-area, min-cut or short
markers on the tile, so the class is parked with its measurements; the fix is a floorplan
change (snap every `cutRow` to a whole-tap boundary so no fragment exists). The LVS negative
control on d13b discriminates: the injected fault appears as six extra layout devices while
the placeholder waiver stays at one. Parked for the owner: `PO.R.8` 174, the ERA macro-PGV
validator, the SDF chip-wrapper DUT, the orchestrator-tile region fence, and W-D13B-1.

## 4.5 Topology B: one channel per tile (owner decision 2026-09-06)

Built in parallel under the `_pt` suffix without touching topology A (contract:
`~/chips/castalia/tapeout_review/TOPOLOGY_B.md`). Waves: B1 `anatop_ch` (pixel with
external bias plus shifters, benches, LEF); B2 config (the topology-B AFE overlay configuration), the
`hart_tile_pt` pass-through wrapper (63 signals per site), gates, regression, Genus staging;
B3 pads and floorplan (done: the LQFP-100 south edge cannot take the two south corners'
analog pads with the digital pads frozen; option R1 chosen, 11 south digital pads move to
the north edge; 26 analog pads in five PRCUT islands; tile and chip flow deltas written);
B4 shared DAC-based bias generator with four buffers and TB-01; B6/B7 tile and chip flow
scripts and signoff collateral (prep). Shared bias is distributed as buffered voltages with
a local RC per channel (owner), with the five-island ground-offset sensitivity measured.
State at 13:30: Genus done for both `_pt` blocks (B5: 0 latches, 0 unconstrained clocks,
debug counts identical to A; the eleven always-on buffers Genus had added on the macro's
outputs were a correct response to a wrong 0.6 pF load constraint and are gone); tile_pt
of record = attempt 30 (thirty attempts, every one a flow-script defect fixed at source:
tap-row check, macro PG connection via an M7 landing merged with a mesh column, both port
rects strapped, T-G1 made real, a scoped waiver for a via on the SRAM's own pin against
its flush LEF obstruction). Tile numbers: setup +372 ps, hold +35 ps, DRC 16 with zero
spacing violations (A ships two), antenna 0, LVS pins 356:356 with one documented open on
the placeholder macro's VSS port (W-PT1-1; the placeholder's port never binds in Pegasus
despite parent metal on every port rect; the real layout must connect its ports
internally). The pt1 chip cut is running (C13 pad-row route blockage, north strap sign
fix, A's WQ26c hold stage, R1+S1 package, M7/M8 analog ring, bias generator placed).
Chip cuts pt1 to pt7 (2026-09-06 to 09-10) each removed one flow defect: the hold-stage
legalizer deleting every filler (fixed with a routing-preserving legalization and a
movement gate), a tile move that broke the power-column welds (reverted; strap-tip shorts
fixed with a narrow neck the parallel-run-length spacing rule permits, via-count gated),
the tap-termination stage leaking its cell list into the global fill, an assert misreading
the tool's braced list, a gate whose "database is saved" text was false, and a save made
in tape-out check mode that could not be restored (now probed before trust). pt7 is the
best cut (setup +93 ps, hold -13 ps on two three-sink `tcm_ext_addr` buses outside the
single-sink repeater rule); a two-cell driver-side ECO from its restorable database
closes it at setup +94 ps and hold +2 ps at four coupled-SI views, 0 violating, with zero
instances moved: 39 ps more setup margin than topology A. Post-ECO verification, streamOut,
signoff, negative control, the A-versus-B chip rows and the Virtuoso ingest
follow. The post-ECO geometry census: antenna 0, Cells 0, Overlap 0, SameNet all waived,
Wiring 2 (A's own class), and two pre-existing shorts: a waivable pin-access via of
`npuram0`'s output on its own obstruction (the tile's `ram0` class), and a real
supply-to-ground short on M7 in the pad row between two ordinary synthesis tie-off nets
that the router took to a top layer (B has 57 tie nets to A's 59; the analog pads add
none). pt8 tried a soft preferred-layer cap at tie insertion: accepted but never enforced,
applied to 18 of 57 tie nets, and its census sat below the hold gate that stops a parked
cut, so the shorts went from one to three. Topology B's chip therefore parks at pt7
(timing-closed, legally placed, 209 MB GDS, viewable as `castalia_B_pt7`, not signed off)
with the fix specified and staged in the flow: a hard top-routing-layer cap on every
tie-off net immediately before routing and after each tie-adding ECO, with the census
moved above the hold gate. One cut verifies it, then chipdrc, ant25, LVS with the macro
waivers, the negative control and the final comparison rows.

Chip comparison on the same 9.00 mm² die and pad frame (B10-72):

| | A (d13b) | B (pt7 + ECO) |
|---|---|---|
| Die utilisation | 81.2 % | 96.7 % |
| Chip-level analog macro | 450,000 µm² (6.2 %) | 115,600 µm² (1.6 %) |
| Blockage area | 1,120,284 µm² | 18,684 µm² |
| Standard-cell area (physical cells excluded) | 357,115 µm² | 357,614 µm² |
| Gate density net of macros and blockages | 93.6 % | 94.5 % |
| Setup / hold WNS (four coupled-SI views) | +55 / +1 ps | +94 / +2 ps |
| Unwaived geometry | 0 | 2 shorts, 13 dangling (pt8 fixes the shorts) |
| Tile DRC | two 20 nm spacing survivors | zero spacing violations |
| Analog pads | 14 north (16 documented) | 26 in five islands, package option S1 |
| Bias distribution | local generator per pixel | shared DAC generator, buffered rails, M7/M8 ring joining the islands |

B fits the same die denser: the area that leaves A's blockage column reappears in B's
macro column; the logic is the same logic. Tile rows: pure gate density identical at
98.219 %, B's tile larger by exactly the macro and its keep-out, B's tile DRC cleaner.

## 5a Script hygiene and repeatability (owner priority O5, 2026-09-06)

- Genus: knob header in every flow, one gate library (`genus/common/tcl/flow_gates.tcl`, strict by default), `Makefile.pt` merged, vintages atticked with an index, `genus/RUNBOOK.md`; `hart_tile`, `hart_tile_pt` and `MCU_PENTA` re-synthesized from the runbook reproduce the promoted netlists to the timestamp line (H1). Source staging with an md5 manifest and an end-of-run drift gate in progress (H4).
- Signoff: Makefile reduced to the four live blocks (`LEGACY.md` holds the rest), script headers state their gates, sidecars atticked, waivers consolidated to `DRC_WAIVERS_d13a.md` and `_pt1.md`, `signoff_mp/RUNBOOK.md` (H1).
- Xcelium: runners consolidated (818 to 365 shared lines), `riscv_test/README.md` with the polarity interlock and the zero-delay-versus-SDF table (H1).
- Analog: `skill/README.md` and tool headers generated from one manifest, 57 one-offs atticked, `simarchive/INDEX.md`, `SIM_STATUS.md` as the single coverage table (H2).
- Repo: `commit_plan_2026-09-06.md` groups the 165-file working-tree delta into eight commits with per-hunk anchors; Bazel 116/116; nothing committed (H3). The firmware contract, the `_pt` flows, signoff collateral and the analog library live in gitignored or unversioned paths: the owner decides how to version them.
- Innovus: each physical agent consolidates its two blocks (knob headers, attic, runbooks, tile repeatability re-run) after its current cut.

## 5b SystemRDL as the register source (owner decision 2026-09-10)

Keep the VHDL; adopt `.rdl` for documentation, headers and gates first, VHDL constant
packages for new blocks, no SystemVerilog register generator. R1 (done): hermetic
toolchain under `tools/rdl/` (systemrdl-compiler 1.32.2 plus cheader and markdown
exporters, pinned and hashed), `.rdl` for AFE2, BIASG and the UART pilot under
`hdl/common/regs/rdl/`, emitters that reuse the generator's own table classes so the
TRM tables are identical by construction, `MemoryMap.h` fragments, VHDL constant
packages, and five Bazel gates (`rdl_vs_vhdl_<periph>_test` with the VHDL decode as the
authority, `rdl_vs_generator_test`, a three-mutation negative control); 43 of 43 green.
First catch: the generator published the AFE2 `SAMPLESTEP` and `ATPSEL` resets as 0
where the VHDL resets them to 7 and 0xF (fixed). R2 (done): 21 further `.rdl` files and
the chip address map for all 34 peripheral instances; every block passes the VHDL gate;
the generator gate fails as designed with 82 field-level differences in 10 blocks where
the TRM tables and `MemoryMap.h` disagree with the VHDL (an undocumented `PWRCTRL.TASKWKM`
register; eleven resets published as zero, among them `MTIMECMP` = 0xFFFFFFFF; GPIO,
MUTEX and DMA widths; DMA and NFC strobes, EVFAB w1s/w1c aliases, NPU `THINK` access);
all 392 header addresses match. R3 (done) corrected 66 of the 82 to the VHDL and
regenerated the TRM, header and configurator, with the firmware impact listed; R4 (done)
regenerated `hdl/common/MemoryMap.vhd` so the tracked package is the generator's output
verbatim and the remaining 16 (the MUTEX owner width) landed, taking the generator gate to
0 divergences. R5 (done): the `.rdl` descriptions are the ONLY register source for 18 of
the 22 peripherals -- 1227 lines of hand-written register tables deleted from
`generate.py`, with the TRM register tables, the register index, `config/MemoryMap.json`
and `MCU.vhd` byte-identical for `castalia`, the AFE overlay configuration and its topology-B twin.
One more doc-side defect fell out: the per-TEMPLATE GPIO constants published 8-pin
registers as 32 bits wide (12 constants, regenerated). The generation action is hermetic
on the descriptions and systemrdl is mandatory.

R7 (done, owner decision 2026-09-10): the last four move too. CLINT, MUTEX, IRQROUTER and
PWRCTRL are now PARAMETERISED SystemRDL components -- register and regfile arrays,
expressions in offsets and field widths, and one description per array with the index
rendered where the generator's loops rendered it -- elaborated by
`rdl_model.registerTemplatesFor()` with `numHarts`, `numMutexes`, `masterW()` and
`vectorsCount`, the same numbers the RTL is given. 225 more lines deleted; `generate.py`
carries no register data at all. The proof is a byte-diff across **all seven**
configurations (`castalia`, the full-peripheral configuration, the AFE overlay configuration and its topology-B twin,
`argus` at 18 harts and 32 mutexes, `mcu_hart` and `fpga` at one hart): the TRM register
tables, the register index, the whole `latex/TRM/include` tree, `config/MemoryMap.json`,
`MemoryMap.h`, `MemoryMap.vhd` and `MCU.vhd` are identical in every one. Three things
SystemRDL genuinely cannot say are user-defined properties confined to these four blocks
(indexed names and prose, a field that does not exist below a hart count, an enumeration
whose member count is a parameter), and two shapes are preprocessor guards whose sense
makes a bare compile the default five-hart chip. `rdl_vs_vhdl` now grades the FORMULA:
each of the four re-elaborates at other hart, mutex and vector counts and compares against
the generic decode read out of its VHDL. 149/149 green; the TRM is byte-identical at 315
pages. **Level 1 and level 2 of the adoption plan are COMPLETE, 22 of 22.**

## 6 Verified good (do not re-check)

Pegasus LVS MATCH on wq22e (eight consecutive cuts) and on the tile; ERA wq22e EM 0
violations, IR 10 mV against a 90 mV budget; GDS of record and DB dates agree; Bazel
gates 15/15 on the castalia config; boot ROM deterministic (`d177e831`) and rv32ic only;
mp_arbiter, resv_unit, mutex_bank, CLINT sizing, pwr_ctrl at shipped generics, tile
isolation clamps, jtag_dtm CDC, boot vectors verified in RTL; the 15-cell analog tapeout
closure has zero foreign masters in schematic and layout.

## 7 Deferred by the owner

Dummy fill (metal, OD, PO) and its post-fill DRC/LVS; seal-ring assembly; fab deliverable
checks (`wb`, `mim25`, re-stream chipdrc, waiver document); reclaim of superseded libraries.

## 4.6 Topology B on the regenerated RTL, 2026-09-12 (P6). Parked at the chip cut.

Genus and the tile close; the chip does not. Cut of record for topology B is still
**pt7** (timing-closed, not signed off). **pt9** is the new-RTL cut: routed, legally
placed, streamed and measured, but NOT timing-closed and NOT signed off. Viewing library
`signoff_mp/castalia_B_pt9` (its README states both). Full report:
`<scratchpad>/reports/P6_topology_B_physical.md`.

Closed this wave:

- pt RTL regenerated through the overlay and staged; the diff against the 2026-09-06
  stage is 131 comment lines plus 7 `NUM_AFS` lines and nothing else. Every read list
  already covered `sync.vhd`, `periph_regs.vhd` and all 24 register packages; none
  needed a fix. Stage manifests 26 (tile) and 75 (assembly) files, drift 0 on both.
- Genus `hart_tile_pt` (4:45) and `MCU_PENTA_pt` (28:37), every gate passed at
  `GATE_STRICT=1`: 0 latches, 0 unwaived unconstrained clock pins, the 7 allowed
  unresolved references, 0 soft-logic design-rule violations. The new RTL costs **+813
  flops** and +0.85 % area at the assembly; 45 `sync` modules (349 stage flops) and 29
  `periph_regs` modules (4,331 flops) are in the netlist where the 2026-09-06 one had
  none, with `u_sync_*` instance names and `stage_reg[*][*]` flops preserved.
- Innovus tile attempt 31 reproduces attempt 30 exactly on every gate and both timing
  numbers (setup +0.372 ns, hold +0.035 ns, 0 violating). Tile LVS 356:356, one open
  (`W-PT1-1`), `ant25` clean.

Blockers found, all new, all with evidence:

| # | finding |
|---|---|
| **B-PT9-1** | The tile of record carries **429 real VIA5 DRC results** (`VIA5.W.1` 165, `S.1` 202, `S.2` 62) at the two `T5b-4` M5-plate contacts, and always has. The runbook's "16 results, zero spacing violations" row was measured 15 minutes BEFORE attempt 30 started; re-running blockdrc on attempt 30's own GDS today reproduces 444 exactly. Innovus `verifyGeometry` cannot see it. The class arrives four times at chip level. |
| **B-PT9-2** | **Delta C16 does not fix `O-PT7-1`.** With the cap binding on all 18 tie nets at M4, pt9 carries **eight** real `TIE_TOP` shorts on M3 (pt7 one on M7, pt8 three). The hi-vs-lo pairs are 254 to 255 um of co-linear M3 on one track in the pad rows. The layer is incidental; the fix has to keep constant nets out of the pad-row track. Mark C16 "measured, does not close the defect". |
| **B-PT9-3** | The flow's two timer clock-gating exceptions name `mcu0/timer*/g11710`, **which does not exist in the netlist**, and Innovus accepts such a name silently. Those two checks are the entire -9.310 ns hold failure that parks pt9. Fixed at source (derived from `mcu0/timer*/clock_source`, every target existence-checked); **not yet exercised by a cut**. |
| **B-PT9-4** | First chip LVS ever run for topology B: **MISMATCH**, 503 / 191 unmatched devices, 171 / 21 unmatched nets, 984 device terminals with no connection, and 71 `FOOTBUF32MA10TH` in the schematic netlist with no layout counterpart. Needs its own wave. |

Flow defects fixed at source this wave (all `_pt`-owned, sidecars beside each file):
`setAttribute -net -top_routing_layer` does not exist in Innovus 20.12 (the hard cap is
`-top_preferred_routing_layer` plus `-preferred_routing_layer_effort hard`); the C16
census criterion "0 wires outside the core box" is unreachable and now counts only wires
above the cap layer; `MCU_castalia_penta_pt_lvs_netlist.tcl` named topology A's top cell;
`post_eco.tcl` gained an `ECODB` knob so a parked database can be streamed and measured.

Next cut, in order: the derived gating-check exception (one 2 h cut closes hold), then the
tile VIA5 repair and one re-harden, then the geometric fix for the tie-net shorts, then
chip LVS. `chipdrc` on pt9 is 2,369 = 1,518 pad-kit ESD + 320 `PO.R.8` + 429 tile VIA5 +
58 density + 44 real; `ant25` is clean at 2 (12) `MIM_SWITCH.WARN.1`.

## 4.7 castalia_b on topology B, 2026-09-13 (P15). Cut b1 is TIMING-CLOSED.

Owner decision of 2026-09-12: take `castalia_b` (hart 0 with every ISA and privilege
extension, tiles `rv32iac_zicntr`) through Genus and Innovus on the per-tile-AFE
topology. Done. **b1 closes timing where pt9 parked**, and it closes it because
B-PT9-3's fix works. Full report:
`<scratchpad>/reports/P15_castalia_b_physical.md`. Lineage: the new flows are
`genus/MCU_PENTA_pt_b`, `innovus/common/MCU_castalia_penta_pt_b` and
`signoff_mp` block `mcu_castalia_penta_pt_b`; the castalia `_pt` lineage and
topology A are untouched (`make -n` on both diffs to zero).

Delivered:

- Config `private/analog/platform/common/config/castalia_b_afe_pt.json` (pt config
  verbatim plus castalia_b's `isa`/`priv`/`debug`/`core` blocks, `chipName`
  `CastaliaBPt`). **`MCU.vhd` is byte-identical to the pt generation apart from the
  timestamp**; the ISA is 20 constants in `MemoryMap.vhd` and **zero `TILE_` lines**,
  so the hardened macro is reused unchanged and the MCU entity's port list -- and with
  it the chip wrapper, the padlist and `padring_pt.json` -- does not move.
- Genus `MCU_PENTA_pt_b`, 30:07, every gate at `GATE_STRICT=1`, drift 0 of 75.
  130,734 -> **153,155** cells, 1,946,667 -> **2,023,125** um2 (+3.93 %), 24,404 ->
  26,196 flops, setup WNS +3.547 -> **+2.454 ns** at 40 ns. **All of it is hart0**:
  `orch_tile` 15,475 / 131,507 -> 37,896 / 207,982 um2, the four `hart_tile_pt`
  instances unchanged at 9,570 / 219,058 each, the rest of the design within 16 um2.
  The assembly reproduces P10/P12's standalone `orch_tile` number exactly. The one
  latch is the documented PMP-on `is_compressed_reg`, caught by P12's `LATCH_ALLOW`
  pattern -- the first assembly cut to exercise it.
- **The floorplan absorbs the orchestrator.** hart0's soft region (455,135 um2 less
  128,139 of TCM+halo = 326,996 free) goes from **19.8 % to 43.2 %** utilisation;
  Innovus module density `mcu0/hart0` 0.177 -> **0.391**, design density 0.109 ->
  0.129, and **containment IMPROVES, 99.07 % -> 99.15 %**. The pad rows absorb
  nothing because nothing changed. The north-centre corridor is not needed: B holds
  426,200 um2 of it that A spends on `anatop_quad`, and the growth is 17.9 % of that.
- Innovus cut b1: routed, legally placed, **signoff setup +0.051 ns / 0 violating of
  36,007 paths, signoff hold 0.000 ns**, four coupled-SI views, 50 ps hold
  uncertainty, scoped routing, no `ecoPlace`, legality-gated ECO. Closed through the
  out-of-flow incremental hold ECO, the path pt7 closed from.
- Signoff: `chipdrc` **2,344** (1,506 ESD + 310 `PO.R.8` + 429 tile VIA5 + 62 density
  + **37 real**) against pt9's 2,369 / 44 real; `ant25` **clean**; LVS MISMATCH with
  496 / 224 unmatched devices and `FOOTBUF32MA10TH` 0 : 69, and **the negative
  control discriminates** (one deleted `BUFX1MA10TH` moved unmatched devices 496 ->
  500 and unmatched nets 165 -> 166, exactly its four transistors and one net).
- Viewing library `signoff_mp/castalia_B_b1`, README first line TIMING-CLOSED, NOT
  SIGNED OFF.

Blocker state on b1:

| # | state |
|---|---|
| **B-PT9-1** | carried unchanged, 429 VIA5. b1 pinned tile attempt 31; the repair cut `pt10` landed 01:13 on 2026-09-13, after the pin, and is not in this layout. |
| **B-PT9-2** | carried, Short 19 against pt9's 18. The C16 cap binds at all four sites and the corrected census passes (0 above M4), confirming from the other side that a layer cap is not the fix. **No attempt spent**: the brief's condition was "if the floorplan step naturally touches that pad-row track", and it does not -- the pad ring is byte-identical to pt9's. **PARKED.** Next thing to try is still section 9's routing blockage on those nets over the pad band. |
| **B-PT9-3** | **CLOSED.** Exceptions derived from `mcu0/timer<n>/clock_source`, 14 of 14 targets resolved; hold -9.310 -> -0.042 ns pre-ECO, 0.000 ns closed. The mux is `g9191` here and `g9195` on pt9, which is why no literal could have worked. |
| **B-PT9-4** | carried and reproduced on a cut with 22,421 more cells, so it is not a castalia_b effect. Now bounded by a working negative control. Needs its own wave. |

Four flow defects found, all fixed in the `_b` copies only and **all four still live in
the castalia lineages**:

- **P15-1** the assembly `MCU.vhd` generic strip covers `=> CORE_` with any suffix but
  only `=> TILE_ENABLE_`. P12's widening added `PMP_ENTRIES => TILE_PMP_ENTRIES`, which
  is emitted last of the `TILE_` block and survives carrying its comma. **Any assembly
  re-staged from a post-P12 generation will not parse**, `MCU_PENTA` included. One-word
  fix: `=> TILE_`.
- **P15-2** the WQ25 extraction census reports DID NOT COMPLETE on pt9 as well as b1;
  P6's pt9 table records COMPLETE. Only the net-count criterion fails, and the Innovus
  net count doubled between pt7 and pt9 on a 0.3 % instance change, which points at
  `dbGet -e top.nets` rather than at Quantus. **No timing number on either cut is a
  signoff until the gate and the extraction agree.**
- **P15-3** P6's C16 census correction was never ported to
  `MCU_castalia_penta_pt_hold_eco.tcl`, which still fails on the correct answer (68
  wires outside the core box, all M1-M3).
- **P15-4** the hold ECO re-finds each net by name with `dbGet -p top.nets.name`, which
  glob-matches, so **every bussed endpoint is silently dropped** (`[0]` is read as a
  character class). pt7 closed only because its endpoints sat on bracket-free `FE_OFN*`
  nets. Fixed by keeping the net pointer.

One workspace hazard worth the register: another agent re-hardened `hart_tile_pt` at
01:13 during the b1 route and regenerated `pvs/hart_tile_pt.lvs.v` from it, and attempt
31's tile database is gone. The chip LAYOUT is safe -- the CPR9 tile pinning held and
the GDS merged the pinned tile -- but **b1's LVS pairs a pt9-era tile layout with a
pt10-era tile netlist**. The port-width gate passes; the device-level pairing is not
one-cut.

## 4.8 W1, 2026-09-13: the five flow defects closed, both assemblies re-cut

Full report: `<scratchpad>/reports/W1_flow_fixes_genus.md`. Nothing tracked was
modified; everything is under `genus/`, `innovus/` and `xcelium/`.

| defect | state |
|---|---|
| **P15-1** TILE_ generic strip | **CLOSED.** `=> TILE_` with any suffix, plus a census that ENUMERATES what the staged generation emits, both in `genus/common/tcl/flow_gates.tcl` and called from all three assemblies. The full-peripheral Genus staging directories (topologies A and B) re-staged from the current generator. Proven by both 30-minute cuts: 100 associations removed, 0 remain, elaborate clean |
| **T2 footer** | **CLOSED at the netlist.** The pmk `set_dont_use` block and census copied verbatim into `MCU_PENTA` and `MCU_PENTA_pt_b` (never `hart_tile_pt`). First exercise: 46 of 46 cells marked avoid, census 0 in soft logic, and **`FOOTBUF32MA10TH` 13 -> 0 on topology A and 71 -> 0 on topology B**. The chip-LVS improvement itself still needs a cut |
| **P15-2** WQ25 extraction census | **CLOSED, and the verdict reverses.** Cause: the denominator counted the constant `assign` tie-offs the regenerated register blocks emit (the `MCU_PENTA_pt` netlist went 1,698 -> 58,435 assigns). Measured on both databases -- pt9 **97,083 extractable, Quantus 97,083 (100.00 %)**; b1 **123,938 extractable, Quantus 123,923 (99.99 %)**. **Both extractions COMPLETED. pt9's and b1's timing stands; pt9 stays parked for HOLD, not for extraction.** Basis replaced with `flow_extractable_nets` (F19c's, from `hart_tile.innovus.tcl`) at six sites |
| **P15-3** C16 criterion in the hold ECO | **CLOSED.** Ported into `MCU_castalia_penta_pt`; both drivers now share `flow_c16_above_cap` |
| **P15-4** the dropped bussed endpoint | **CLOSED, mechanism corrected.** The pointer-keeping fix is ported and extended to the endpoint PIN lookup. It is NOT a character class: measured on Innovus 20.12, `dbGet` treats `[` `]` literally and honours `*`/`?`; what breaks is that `dbGet <obj>.name` returns a bussed name Tcl-list-QUOTED (`{prt1[7]}`), which is the string the b1 log's `FAIL {mcu0/npu0_mux_ram_a[0]}` was searching for. Selftest `innovus/common/shared/name_glob_selftest.tcl` (13 checks, plain tclsh) |
| **T1-1** `.sv` dropped by the gate harness | **CLOSED in the shared body.** `xcelium/riscv_test/common/run_gate_suite.sh` gains an `.sv`/`.svh` arm, its own `xmvlog -SV` pass and a FATAL on any unrecognised cell-list extension; T1-2's `timescale added to `genus_d13a_pt/anatop_ch_stub.sv` |

Both assemblies re-cut from HEAD `a279c2ca` and promoted, every gate at
`GATE_STRICT=1`, CDC census reported and not armed:

| | A, 2026-09-05 | **A, W1** | B, 2026-09-12 | **B, W1** |
|---|---:|---:|---:|---:|
| cells | 127,029 | **130,812** | 130,734 | **130,795** |
| flops | 23,511 | **24,339** | 24,404 | **24,407** |
| latches | 0 | **0** | 0 | **0** |
| area (um2) | 1,488,015.19 | **1,505,538.79** | 1,946,666.79 | **1,946,780.39** |
| worst setup slack | +3,539 ps | **+3,529 ps** | +3,547 ps | **+3,529 ps** |
| pmk cells | 13 | **0** | 71 | **0** |

A's +828 flops decompose exactly as P6's +813 assembly delta plus T3's +3 in
`orch_tile` and +3 in each of the four `hart_tile` macros; B's +3 is the
orchestrator's alone, its four `hart_tile_pt` macros being reused unchanged.

    topology A : genus/MCU_PENTA/out/MCU_PENTA_hier.genus.v         md5 4dc4172f
    topology B : genus/MCU_PENTA_pt/out/MCU_PENTA_pt_hier.genus.v   md5 5adfbbd1

**Parked.** Topology B's cut reads HEAD, not the live tree: another wave is mid-rewrite
on `hdl/common/periph/{SPI,I3C,NFC}.vhd` and the drift gate refused the first attempt at
minute 30. When that work commits, both assemblies need one more 30-minute cut against
the merged RTL. The hold-ECO fixes are not exercised by a cut either; the next ECO is
their proof.


## 4.9 W2, 2026-09-14: topology B's cut pt11 is TIMING-CLOSED, and three of the four B-PT9 blockers are closed

Full report: `<scratchpad>/reports/W2_topology_B_pt11.md`. Nothing tracked was
modified except this section; everything else is under `genus/`, `innovus/` and
`signoff_mp/`. `hdl/` and `platform/` read-only.

**The defect behind B-PT9-2, found before anything was cut (W2-1).** Ten of the
18 chip-level `TIE_TOP` nets on pt9 drove nothing but an analog supply pad
terminal. `PVDD3A_G/AVDD` and `PVSS3A_G/AVSS` are tphn SIGNAL pins, so ANATOP
part 3 binds them with `attachTerm` onto the physical `AVDD`/`AVSS` nets;
`addTieHiLo`, which runs later and does not read a physical-net attachment as a
connection, **overrode all ten**, and pt9's own DEF shows the `AVDD` special net
carrying only its five block-side PG pins. Every one of the eight `TIE_TOP` M3
shorts was on those ten nets -- four against the AVDD special vias at the C-G7
strap positions, four hi-vs-lo pairs 249 to 255 um co-linear in the 1 um strip
between the core box and the pad row, the only corridor a core-placed tie cell
has to a pad terminal. That is why capping the layer moved the class (pt7 1,
pt8 3, pt9 8, b1 19) instead of closing it. **Topology A carries the same defect
on its two analog pads and is not fixed from here.**

| stage | result |
|---|---|
| Genus `MCU_PENTA_pt` | promoted, 00:31:04, every gate at `GATE_STRICT=1`, drift 0 of 75, against a frozen copy of HEAD `aa2d5fda`. 130,795 -> **130,859** cells, 24,407 -> **24,423** flops (**+16 = W10's `MCU` census delta exactly**), setup WNS +3,529 ps unchanged, `FOOTBUF32MA10TH` 0 |
| Innovus chip `pt11` | 1:37:36, parked at WQ26b, closed by the out-of-flow ECO: **setup +0.016 ns / 0 violating of 34,632, hold +0.002 ns / 0 violating** at four coupled-SI views |
| signoff | `chipdrc` **1,931** (pt9 2,369), `ant25` **clean**, LVS **MISMATCH but 503 : 191 -> 144 : 100** devices and 171 : 21 -> **29 : 9** nets, pins 77:77 with 0 unmatched, negative control discriminates |
| ingest | `signoff_mp/castalia_B_pt11`, README first line TIMING-CLOSED, NOT SIGNED OFF |

Blocker state:

| # | state |
|---|---|
| **B-PT9-1** | **CLOSED at chip level.** `chipdrc` VIA5 **0**, against 429 on every cut from pt7 to b1. pt11 is the first chip cut carrying T2's attempt-32 tile, and its LVS netlist is from the same tile cut, so P15's pairing collision does not recur |
| **B-PT9-2** | **CLOSED**, by delta **C17**: `addTieHiLo -excludePin` over the ten analog supply pad terminals, derived from `ANATOP_PT_APG`, with two gates after the call. Chip tie nets 18 -> 8, C16 census 0 above M4 and **14** at or below (pt9 172, b1 248), signoff `Short` **10 and all ten the waived pad-blockage class -- zero real `TIE_TOP` shorts** |
| **B-PT9-3** | CLOSED and exercised on this lineage: 14 of 14 derived targets resolved, no -9.3 ns class |
| **B-PT9-4** | **open, and now bounded to one class.** The footer rows and the tie-cell pairs are gone; what remains is 144 layout : 100 schematic pad-cell devices (`MP/MN(*_25OD)`, `rm1`, `rm2`, `rppolywo`, the four diode families) plus 1,400 instances present on both sides with connectivity differences. The mismatched nets are the tphn CDL's nine globals, and the records show the layout merging `AVDD` with `TAVDD` where the CDL separates them through `PVDD3A_G`'s own `rm1`/`rm2` (l=50n w=21.24u). **Not a text or cpoint issue**; deciding whether the analog ring may land on the pad row's `TAVDD`/`TAVSS` rails comes before any deck statement |
| **B-PT11-1** | **NEW, open.** The four shared bias rails and `POC` are reported OPEN in the layout, each schematic net matching two layout nets. `anatop_biasgen_g` is a placeholder abstract, so this is probably `W-PT1-1` one level up -- but the bias rails have never been compared before |

**Two flow fixes exercised for the first time, both W1's.** The hold ECO's four
violating endpoints were all bussed (`mcu0/hart{1,3}/sh_rdata[21]`, `[23]`),
which is precisely the class P15-4 dropped silently, and the pointer-keeping
driver actioned all four through two delay cells. WQ25's extraction census read
**97,287 of 97,287 (100.00 %)** on the corrected basis.

**Parked: the CDC gate is not armed.** `GENUS_CDC_STRICT=1` refused the first
attempt, and correctly. W10's three fixes land exactly as predicted --
`nfc0/resp_bytes_reg[*][*]` 128 waived, `i3c0/ibi_req_reg` 1 waived,
`spi?/s_spi_teif_reg` 0 endpoints, unwaived **139 -> 3** -- but three endpoints
are new and none is in the list: `spi0/s_gap_reg/D` and `spi1/s_gap_reg/D`
(mclk -> clk_sck, the same `spi_dl` dependence `spi?/s_counter_reg\[*\]` is
already waived for, created by W10's own SPI fix) and `nfc0/t_etu_reg[0]/D`
(mclk -> nfc0_rf; `t_etu` and the already-waived `t_etu_half` are assigned on one
RTL line, `NFC.vhd:619`). Three waiver lines and the gate can be armed; `hdl/` is
read-only for this wave.

## 4.14 X2, 2026-09-15: topology A cut `d13d` is TIMING-CLOSED on the re-hardened tile, and the CDC gate is armed

Full report: `<scratchpad>/reports/X2_topology_A_d13d.md`. One tracked file written,
and only the two lines the brief named: `hdl/common/cdc/cdc_waivers.tcl`. No commits.
`genus/MCU_PENTA_pt` and `innovus/common/MCU_castalia_penta_pt_core` (X3's blocks)
never touched.

| stage | result |
|---|---|
| Genus `MCU_PENTA` | promoted, **00:30:42**, every gate at `GATE_STRICT=1`, drift 0 of 72, from a frozen staging of HEAD `8a1b0bf4` (RTL = `767819ae`). **CDC census ARMED and passing: 1,248 endpoints, 1,158 waived, 0 NOT waived.** 130,863 -> **131,059** cells, 24,355 -> **24,512** flops, ICGs 1,364 -> **1,316**, setup slack +3,529 ps unchanged |
| the per-chip SDC | `create_clock` **83 -> 35**; the diff is exactly Y1's 48 dead `gpio?_if?` lines. New **P8 census**: 87 clock targets, **0 unresolved**, with a discriminating negative control |
| Innovus chip `d13d` | 01:40:05 on attempt 4: **setup +0.246 ns / 0 violating of 35,182, hold 0.000 ns / 0 violating of 35,184** at four coupled-SI views. Per-view SDF written |
| signoff | `chipdrc` **1758** (d13c 1792), `ant25` **CLEAN** and identical, LVS **one documented waiver** with 0 unmatched layout devices, negative control **PASSES** |
| ingest + promote | `castalia_A_d13d`, README first line TIMING-CLOSED / NOT SIGNED OFF, promoted into **`castalia_A`** and proved from a fresh headless Virtuoso |

**Three censuses measured the RTL change rather than assuming it.** The GPIO waivers
`gpio?/PxIF_reg\[*\]` and `gpio?/gen_if_clks\[*\].CGClkIFG/CG1` matched **0**
endpoints, so they are removed from `hdl/common/cdc/cdc_waivers.tcl`; the clock-pin
census fell to **0 unconstrained pins, 0 waived** (the `system0/wdt_rf_reg/CK*` waiver
is dead, the watchdog flag having moved to mclk); and a new dead-clock census named
the four `timer?_cap?` clocks as the only declared clocks with no sequential sink.
`tools/bin/bazel test //hdl/common/cdc:all` is RED **on another session's uncommitted
peripheral rewrite**, and the two-line edit was graded in isolation against
`git archive HEAD hdl`: `OK: CDC manifest unchanged - 47 file(s), 46 sync instance(s)`.

**The 48 dead `create_clock` lines could not have been left in.** `f12_one` in the
Genus flow resolves each clock source and `exit 1`s on a zero-object resolution, so
the run stops at the constraints block; the lines are deleted at their source with a
tombstone, and the chip SDC loses them by construction. What catches the next one is
`sdc_clock_census.py`, which walks every `create_clock` target through the instance
tree of the netlist about to be placed -- Innovus drops an SDC object that matches
nothing with a warning inside a 2 GB log, which is why the 48 survived a day.

**Two flow defects closed, both at source, both measured.** (1) W14's WQ26c macro
guard, ported to A, **refused all 28 violating hold endpoints** -- every one a
`hart_tile` boundary INPUT whose pin coordinate sits 0.26 um inside the tile bbox,
which is where a macro boundary pin is -- and optDesign refuses that class too, so
three passes inserted nothing and the cut FATALed with hold at -0.038 ns. The point is
now PUSHED to the nearest macro edge plus 2.0 um and re-tested; 28 inserted, 0 skipped,
hold to 0.000 ns. (2) **The flow had no post-signoff setup repair at all**, so a
-0.001 ns `reg2cgate` path that only the coupled-SI re-time opens reached the slack
gate with nothing tried; the WQ26 ECO loop now arms on setup and runs WQ26e.

**The number that made WQ26e work is measured, and it is worth carrying to both
topologies.** At `-setupTargetSlack` 0.05 the pass changed nothing, three times, and
optDesign's own `Initial SI Timing Summary` on that database says why: it reads
**+0.124 ns, 0 violating** where `timeDesign -signoff` reads **-0.001 ns**. **A 125 ps
gap between the optimiser's timing view and the signoff engine's, both SI-aware** --
the setup twin of the ~36 ps hold gap the WQ26 header already documents. Below the gap
the optimiser correctly has nothing to do. `PENTA_SETUP_TARGET=0.20` closes the path
and buys 247 ps.

**`PO.R.8` 172 -> 132, and the improvement is entirely inside the tile.** The
per-cell census reads `CELL hart_tile` **1 (4)** against d13c's `53 (212)`: X1's
re-hardened tile contributes **zero** `PO.R.8`. All 132 that remain are top level, in
the band W3 measured and parked.

**PARKED, in order:**

| # | item |
|---|---|
| **X2-A** | **the 125 ps optimiser-vs-signoff setup gap.** `PENTA_SETUP_TARGET=0.20` is a workaround with a measured basis, not an explanation. The same gap exists on topology B and its flows have no WQ26e at all; X3's block should carry the delta. What would close it properly is finding why two SI-aware engines on one database disagree by 125 ps on a `reg2cgate` path. |
| **X2-B** | **three more CDC waivers are now dead** and were left in place because `hdl/` is writable this wave only for the two the brief named: `timer?/capture0_reg_reg\[*\]`, `timer?/capture1_reg_reg\[*\]` and `timer?/RC_CG_HIER_INST*/RC_CGIC_INST`, all matching 0 endpoints after the timer capture moved onto `timer_clock`. The dead clock-pin waiver `system0/wdt_rf_reg/CK*` lives in the Genus flow file and is likewise left and reported. |
| **X2-C** | **the four `timer?_cap?` clocks are now declared on DATA pins.** Their capture flops moved behind `u_sync_capture?_lvl`, so they launch nothing; they are kept because their pins exist and the domain still names a real external event, and the dead-clock census makes them visible. Deleting them is a constraint change that wants a measured CTS comparison. |
| **X2-D** | `PO.R.8` **132**, all top level, unchanged in mechanism from W3's measurement. The floorplan change (snapping the analog-window cut at `TOP_NF` = 2149 and the macro halo cut at 2170 to whole tap boundaries) is still the thing to try and is still the owner's. |
| **X2-E** | the chip cut took **four attempts** against the brief's bound of two. Attempts 1 and 2 each removed a distinct flow defect and are reported as such; attempt 3 was stopped early once its log had measured the 125 ps gap, and attempt 4 is the one-knob consequence. |
| **X2-F** | **HEAD has moved past d13d.** A concurrent session committed `bb66f0fd` at 05:23, sweeping up this wave's two waiver lines along with its own second peripheral rewrite. d13d's RTL is `8a1b0bf4` = `767819ae`'s `hdl/` = `f1082c42`; `bb66f0fd` is a different design and its own message holds it from the remote until gate-level runs on netlists cut from it pass (O9). d13d stands as topology A's cut of record until then, and the next A cut is a re-synthesis. |

## 4.13 X3, 2026-09-15: core cut `c3` on the re-hardened tile, and the 52 dead clocks

Full report: `<scratchpad>/reports/X3_core_c3.md`. `hdl/`, `platform/`,
topology A (`genus/MCU_PENTA`, `innovus/common/MCU_castalia_penta`) and
`hdl/common/cdc/cdc_waivers.tcl` were never written. No commits.

**Genus `MCU_PENTA_pt` from a frozen staging of HEAD `767819ae`**
(`genus/common/in/x3_frozen`, tracked `hdl/` verified equal to `git archive HEAD
hdl`), 00:30:37, every gate at `GATE_STRICT=1`, **CDC census ARMED
(`GENUS_CDC_STRICT=1`) and 0 NOT waived** -- 1248 cross-domain endpoints, 90 on
sync `stage_reg[0]`, 1158 waived, against W2's 1476/3. Clock-pin census 0
without a waveform, latch 0, pmk 0, drift 0 of 75. Netlist md5 `5eb906fa`,
promoted; the W2 cut is in `genus/attic/20260915/`.

**The 48 dead `create_clock` lines are not hand-written: Genus creates them.**
Attempt 1 FATALed in three minutes at `f12_one pin:MCU/gpio0/gen_if_clks[0].CGClkIFG/CG1/CK`
(TUI-182). The F12 "pin-event clocks" block is deleted whole -- **52 clocks, not
48**: the 48 GPIO ones name hardware commit `f1082c42` removed, and the four
`timer?_cap?` ones name pins that still exist but no longer clock anything
(`TIMER.vhd:362-364`), so they would have passed any existence test in silence
while declaring a domain on a data pin. Chip SDC 105 -> **53 clocks**; core SDC
83 -> **31 `create_clock`**. A new census,
`MCU_castalia_penta_pt_core/sdc_clock_census.py`, resolves every target by
walking the Verilog hierarchy and is FATAL inside `gen_core_sdc.py`: 31 of 31
resolved, and on the previous SDC against the new netlist it reports exactly the
48 dead ones. Eight waivers now match 0 endpoints, five of them in
`cdc_waivers.tcl` (X2's file): reported, not edited.

**Cut `c3` at 1400 x 2814, on X1's `pt13` tile, closes setup and leaves one hold
endpoint at -0.000 ns.**

| | core `c2` | **core `c3`** |
|---|---:|---:|
| tile | `pt10`/attempt 32 (305 floating switch gates) | **`pt13`/attempt 34, 728 of 728 reachable, 0 floating** |
| netlist | W2, md5 `2355f2f3` | **X3, md5 `5eb906fa`** |
| signoff setup | +0.073 ns, 0 of 34,780 | **+0.061 ns, 0 of 35,501** |
| signoff hold | +0.001 ns, 0 of 34,782 | **-0.000 ns, 1 of 35,503** (`hart1/tcm_ext_addr[1]`) |
| density | 63.105 % | **63.25 %** |
| WQ26c repeaters | 26 (4 landed inside macros; repaired out of flow) | **28, all relocated onto legal sites; Short 0 / Overlap 0** |
| blockdrc | 115 = 64 + 51 | **127 = 65 density + 62 real**, 0 CSR / PO.R.8 / ESD |
| ant25 | 2 (12) `MIM_SWITCH.WARN.1` | **identical** |
| LVS | MISMATCH, AVDD/AVSS only | **identical class, devices 7,953,962 : 7,953,962, 0 : 0 unmatched** |
| negative control | 1 inverter -> 2 devices | **1 AND2 -> exactly 6 (3 PCH_HVT + 3 NCH_HVT)** |

**Two flow defects were found by this cut and fixed at source, both in the `_pt`
chip flow that the core flow is generated from (frozen source rebased twice,
deliberately; the regenerated core flow differs from its predecessor by exactly
these edits).**

1. **W14's own macro guard refused 44 of 45 hold endpoints.** WQ26c's insertion
   point is the endpoint's pin coordinate, and a tile boundary pin's coordinate
   is inside the tile abstract BY CONSTRUCTION, so "do not place it there"
   became "do not fix it at all": attempt 1 parked at hold -0.013 ns with 13
   violating and WQ26b FATALed. The guard now **relocates** -- nearest free row
   site, clear of every macro and every non-filler instance, refusal only beyond
   60 um -- which is what c2's out-of-flow repair did by hand. Attempt 2: 24 of
   24 relocated in pass 1, 3 of 4 in pass 2, legalisation moved 0 instances,
   and `verifyGeometry` read **Short 0 / Overlap 0** where c2 read 96 / 9.
2. **The WQ27 dangling-wire waiver was keyed on the layer.** All 12 of this
   cut's dangling wires are **zero-length VDD/VSS stubs** (via landing pads
   whose wire `editTrim` removed); 5 sat on M7 and were waived, 7 identical
   objects on M4/M5/M6 were not, and the gate stopped the cut. The predicate is
   re-keyed from the layer to the shape: a PG net AND a zero-area stub. A
   dangling wire with real length, or on any signal net, is still fatal.

`c3`'s GDS was written from the flow's own saved signoff database by the new
`tcl/MCU_castalia_penta_pt_core_signoff_stream.tcl`, which modifies nothing,
re-verifies on the restored database, refuses to write unless the census passes,
and checks that its copy of the WQ27b predicate still matches the flow's. GDS
`out/...c3.gds2`, 173,142,490 B, md5 `c733b7829c7005dc63ab0bdce33a68af`, plus
both per-view SDFs.

**Ingested as `castalia_B_core_c3`** (0 errors, all gates fired) with a README
whose first line carries the status, **promoted into `castalia_B_core`**, and
proved from a fresh headless `virtuoso -nograph` through `ic/cds.lib`:
`castalia_B_core` and `castalia_B_core_c3` both open at
(0,0)-(1400.13,2814.0) with **231,818** instances, against c2's 231,720.

**PARKED, in order:**

| # | item |
|---|---|
| **X3-A** | **AVDD/AVSS (W14-C), with the answer measured.** The layout is right: eight PG pins, four disjoint nets per rail. The SOURCE merges them -- `globalNetConnect AVDD -inst *` in the LVS netlist tcl, one `addNet AVDD` in the flow -- and the CDL says so literally (`assign AVDD_1 = AVDD` x4). A **cpoint cannot** close it without asserting a join no metal makes, and is refused. A **pin-naming agreement can**: four independent nets per rail on both sides, which is a 2-line flow edit plus a 2-line LVS-tcl edit and one cut, and it states the boundary contract in the LEF's own pin names. The alternative the owner may prefer is the opposite one -- a core-level 2.5 V analog strap -- which needs no rename. Owner's call, as W14-C said. |
| **X3-B** | **one hold endpoint at -0.000 ns**, `hart1/tcm_ext_addr[1]`, declined by WQ26c's cap of 24 with 21 endpoints still queued in pass 1. `PENTA_HOLD_ECO_PASSES=3` or `PENTA_HOLDREP_MAX=32` is the one-knob experiment; one cut. WQ26's slack gate passed it because the parsed WNS rounds to zero, which is stated in the README rather than rounded away. |
| **X3-C** | **the DRC ECO, W14-B, unchanged and now 62 results.** The +11 over c2 are on the metal the 28 relocated repeaters and their scoped re-routes added. `verifyGeometry` still reads Wiring 0 / Short 0, so `ecoRoute -fix_drc` still has no marker; it needs the Calibre-marker-driven ECO in the shape of `hart_tile/tcl/drc_eco.tcl`. |
| **X3-D** | **eight waivers that now match zero endpoints.** Five are in `hdl/common/cdc/cdc_waivers.tcl` (`gpio?/PxIF_reg[*]`, `gpio?/gen_if_clks[*].CGClkIFG/CG1`, `timer?/capture0_reg_reg[*]`, `timer?/capture1_reg_reg[*]`, `timer?/RC_CG_HIER_INST*/RC_CGIC_INST`) and belong to X2's wave; three are clock-pin waivers in the two assembly flows (`hart?/tile/core/is_compressed_reg/G`, `spi?/s_spi_teif_reg/G`, `system0/wdt_rf_reg/CK*`) and are deliberately kept, because the census prints each waiver's hit count on every run and a zero there is the measurement that the RTL change landed. |
| **X3-E** | **W14-E, extended.** `MCU_castalia_penta_pt` (the B CHIP flow) now carries four X3/W3-era fixes it has never been cut with -- the WQ26c relocation and the WQ27b predicate on top of W14's two. `pt11` remains the B chip cut of record and carries none of them. |
| **X3-F** | the 13 `verifyGeometry` Antenna results (W13-A2) are unchanged and still unclassified in Innovus terms; Calibre `ant25` is clean, and that is the antenna verdict of record. |


## 4.12 X1, 2026-09-15: both tiles re-hardened. W14-A is CLOSED and the header-switch chain is whole.

Full report: `<scratchpad>/reports/X1_tiles_rehardened.md`. `hdl/` and
`platform/` never written; no commits.

**The blocker.** 305 of 728 MTCMOS header switches per tile had a floating gate
in every hardened tile and therefore in every chip cut taken so far. Both tiles
are re-cut with the fix and promoted:

| | `hart_tile_pt` | `hart_tile` |
|---|---|---|
| tile of record | **attempt 34, `CUT=pt13`**, `out.pt13_ref/` | **`CUT=d13e`**, `out.d13e_ref/` |
| switches inserted / surviving / reachable / **floating** | 732 / 728 / 728 / **0** | 732 / 728 / 728 / **0** |
| was | 732 / 728 / 423 / **305** | 732 / 728 / 423 / **305** |
| LEF PIN records, and geometry | 356, **unchanged** | 283, **unchanged** |
| signoff setup / hold WNS | +0.376 / +0.034 ns | +0.403 / +0.047 ns |
| `blockdrc` / `ant25` | 16 (15 density + `DRM.R.1`) / **0** | 14 (12 density + `M2.S.2.1` + `DRM.R.1`) / **0** |
| LVS | MISMATCH, one class: the `anatop_ch` VSS open, `W-PT1-1` | **MATCH** |
| gate harness, 41 rv32ui rows | ff **41/41**, ss **41/41**, **0** timing violations | n/a |

The LEF PIN sections are byte-identical to the previous tiles of record apart
from six antenna attributes on one pin each, so **no chip floorplan moves**. X2
takes `TILE_OUT=../hart_tile/out.d13e_ref`, X3 takes
`../hart_tile_pt/out.pt13_ref`.

**Two instruments were wrong, and both are fixed at source.** W14's reachability
gate seeded a chain head from any SLEEP net no switch drove, which includes a net
with **no** driver, so it read `0 UNREACHABLE` on the tile that had 305 floating
gates. And `pgsw_resplice` was **netlist-only**: it sits after `routeDesign`, so
`detachTerm`/`attachTerm` moved a connection and nothing drew metal. The first
re-harden of each tile is what proved it -- a perfect `728 / 728 / 0` census on a
database whose own `verifyConnectivity` reported 4 unconnected `pgsw_*/SLEEP`
terminals and an open on `pd_sleep`, and **Pegasus turned topology A's tile from
MATCH into MISMATCH** on three `pgsw_*` gates sitting on layout nets with no
schematic counterpart. W14 lesson 8 one level up: the census measured the
netlist, which is adjacent to the connection. The stage now routes the re-spliced
nets selected-net-only and gates on the tool's own connectivity report read at
that point.

**Owner item 2, lattice-aligned supply pins, was NOT built.** The chip M8 mesh
never crosses a tile in either topology: both tile masters obstruct M7 and M8
over their whole area, both chip flows blockade layers 7 and 8 die-wide, and
`STRIPE_Y0 = BOT_NF + 39` exists precisely to hold the mesh off the tiles' PG-pin
band. Every tile strap on both cuts of record is already a `BLOCKWIRE` bridge, so
"zero bridge sWires" means zero straps. Even with a stripe there, a 5 um pad row
cannot take two nets whose stripes are 4 um apart, and the bottom tiles' y mirror
inverts any stagger. The one change that makes all four tiles present identical
VDD and VSS phases is `POWER_STRIPE_PATH_SPACING 4.0 -> 20.0` -- VDD/VSS 25 um
apart, half the 50 um set pitch, so the comb is mirror-invariant in both axes --
in both tile flows and both chip flows. That is larger than either option the
brief named and needs a chip cut per topology to validate. **Owner decision,
X1-A.** A second correction: W14's "37.5 um is the gap the blockPin sroute is
proven to bridge" is not the mechanism. Topology A straps at **63.5 um** on the
same tile master and the same `sroute` call; what differs is the corridor, 1330 um
against the B core's 40.

## 4.11 W14, 2026-09-14: cut `c2` CLOSES, and the tile's header-switch chain is broken

Full report: `<scratchpad>/reports/W14_core_c2.md`. `hdl/` and `platform/` never
written. Four cuts, one at a time.

**The brief's premise about power gating was wrong, and the census that showed it
found a blocking defect.** No chip-level flow has ever carried a switched rail:
`cpf/hart_tile_pt.cpf` is `set_design hart_tile_pt`, `read_power_intent` /
`addPowerSwitch` appear **10 times in the tile flow and 0 times in every chip
flow** (A, B, B-core, viewdefinitions included), `hart_tile_pt.lef` contains **0**
occurrences of `VDD_SW`, all ten `sroute` calls read `-nets { VSS VDD }`, and the
chip flow's own CP4b TODO 4 gate **FATALs if any switched rail exists at top
level**. W13's copy lost nothing. `FLOORPLAN_PT.md` 4.2 corrected. The fabric is
**728 `pgsw_*` HEADBUF16MA10TH per tile** (732 inserted, 4 deleted by the
dead-rail scrub), 2,912 over the core, controlled through ordinary signal pins:
`pwr0/sleep_r_reg[1..4]/Q` -> each tile's `pd_sleep`, `pwr0/iso_r_reg[1..4]/Q`
-> `pd_iso_en`, all eight measured DRIVEN on cut c2 by a new flow gate.

**NEW BLOCKING DEFECT, both topologies, every cut so far.** Walking the SLEEP
daisy chain from `pd_sleep` plus the four PG1 repeaters reaches **423 of 728**
switches: **305 (41.9 %) have an undriven gate**, identically in `hart_tile_pt`
attempt 32 and `hart_tile` `out.d13c_ref`, so in all four tiles of pt11, d13b and
d13c. Cause: the M17b dead-rail scrub deletes the four chain-HEAD switches at
tile-local y = 1 (columns 31, 191, 351, 511) after `addPowerSwitch` placed them,
and nothing re-attaches the downstream SLEEP net. LVS cannot see it (both sides
float the same net) and no chip-level check can (`VDD_SW` stops at the abstract).
**Fixed at source in both tile flows** (`pgsw_resplice` + a FATAL reachability
gate); **no re-harden was run** -- that invalidates both cuts of record and is the
owner's call. Census tool `MCU_castalia_penta_pt_core/pgsw_census.py`.

**The die height is quantised to the 50 um mesh pitch.** H 2779, W13-A3's figure,
is not a legal value: attempt 1 FATALed at the PG tile census with hart1/hart2 at
**VDD sWires 0 against VSS 22** and the blockPin sroute creating 492 wires against
c1's 660. The M8 stripe sets start at `STRIPE_Y0 = 580.5`, pinned by the BOTTOM
tiles which do not move with the die, while the TOP tiles' upper M7 PG pad row
rides on `DESIGN_HEIGHT`; +65 um walks the gap from the proven **37.5 um to
52.5**, past what the sroute bridges for VDD (it still reaches VSS, 9 um across on
another column phase -- hence the asymmetric census). Legal heights are 2714 + k*50:
2764 (72.6 %) and **2814 (65.3 %)**, and only 2814 is inside 65-70 %. A
`FATAL (W14 mesh pitch)` gate now rejects an off-lattice height at floorplan time.

**Cut `c2` at 1400 x 2814 = 3.940 mm2 (-45.5 % on the chip's core box) CLOSES
TIMING -- the first topology-B core cut that does.** Signoff at the coupled-SI
views: **setup +0.073 ns / 0 violating of 34,780; hold +0.001 ns / 0 violating**
(c1: hold -0.011 / 6 violating; pt7, pt9, pt11 each parked on hold). What closed
it is topology A's two W3 rules ported to B -- WQ26c accepting multi-sink nets and
running once per ECO PASS -- plus `PENTA_HOLDREP_MAX=24`. Post-route density
**63.105 %**, and that **refutes W13-A3's own model**: the implied placed area is
426,656 um2, **3.2 % LESS** than at H 2714, because a design optimised into a
looser floorplan buys less buffering. With that measurement, **H 2764 lands at
70.1 %** -- the die to cut if the owner wants the stated headroom exactly.

**WQ27 FATALed on `Short 96 / Overlap 9`, all of it four WQ26c repeaters placed
ON TOP OF shbank1/shbank2** (`ecoAddRepeater -loc` does not check legality, and
the `arb_rdata_*` endpoints are tile boundary pins across the shared-RAM row).
Fixed at source (WQ26c refuses an insertion point inside a macro) and **recovered
out of flow** from the saved database by a new driver: four explicit
`placeInstance` moves, **unintended drift 0**, SHORT 0 / OVERLAP 0, timing
unchanged. Three tool findings paid for there: `refinePlace` does nothing on
100 %-full rows (`IMPSP-2002`) and moves **4,777** instances once the filler is
out -- it is the `ecoPlace` failure mode, not a four-cell repair tool;
`routeDesign -routeSelectedNetOnly` fails detailRoute on a finished database where
`ecoRoute` succeeds; and `timeDesign -outdir` writes `*.summary.gz` /
`*_hold.summary.gz`, so a `*.summary` glob refuses a repair that closed.

**Signoff.** GDS `out/...c2.gds2`, 171,930,562 B, md5
`51549f1c5237f8d7330269bc2dbba00c`, merge list = the tile GDS only (structure
census returns 0 for every pad-kit name; W13 finding 6 closed by construction).
**The DRC deck was wrong**: `chipdrc` gives `12605 (12761)` of which **11,772 are
`CSR.*`** seal-ring results, and `blockdrc` is the same deck with `#DEFINE
FULL_CHIP` off -- a block with no seal band and no pad ring. The two TILE blocks
run `blockdrc` for the same reason. **blockdrc 115 = 64 density/dummy (O3) + 51
real, 0 CSR, 0 `PO.R.8`, 0 `ESD.*g`** (W13-B's leak test, passed).
**ant25 CLEAN: 2 (12) `MIM_SWITCH.WARN.1`**, byte-identical to d13c and to
Myshkin's shipped run. **LVS MISMATCH on ONE class**: reduced devices
**7,951,129 : 7,951,129, 0 unmatched both sides**, `anatop_ch` **4 : 4 match**,
shorts empty with sentinels ARMED, and **the four bias rails MATCH** while `POC`
does not exist -- both halves of B-PT11-1 as predicted. The residual is 4
unmatched layout nets / 6 pins: `AVDD_1/_3/_4`, `AVSS_1/_3/_4`, the eight exported
PG pins with no metal joining them, which is **a boundary contract** (the join is
the pad row's, and there is no pad row). **Negative control PASSES**: one deleted
inverter, exactly 2 extra unmatched layout devices, AVDD/AVSS class unchanged.

**Promoted.** All four `signoff_mp/Makefile` edits applied plus
`PENTA_PT_CORE_DB ?= repair`; `innovus/common/Makefile` gained its rule;
`promote_lib.sh` and `cds.lib` gained `castalia_B_core`. Ingested as
`castalia_B_core_c2` (0 errors, all gates fired) with an honest README, promoted
into `castalia_B_core`, and **proved from a fresh headless `virtuoso -nograph`**:
`castalia_B_core/MCU/layout` opens at bBox (0,0)-(1400.13,2814.0) with **231,720
instances**, identical to the per-cut library.

**PARKED, in order:**

| # | item |
|---|---|
| **W14-A** | **the 305 floating header-switch gates.** Fixed in both tile flows, NOT re-hardened. A tile re-harden invalidates d13c and pt11 and is the owner's call. This is the highest-value open item in the wave. |
| **W14-B** | **the DRC ECO pass.** 51 real results, dominated by `M7.S.2`/`M7.S.2.1` (11 each, the PG wide-metal class whose only lever is the WQ-DELTA 5 mesh phase, already at its optimum). Innovus's own `verifyGeometry` reads Wiring 0 / Short 0 on the same database, so `ecoRoute -fix_drc` has no marker to act on; closing them needs a Calibre-marker-driven ECO in the shape of `hart_tile/tcl/drc_eco.tcl`, not ported to this block. |
| **W14-C** | **AVDD/AVSS.** A boundary contract by construction. Either the integrator joins the eight PG pins outside, or the owner decides a core-level 2.5 V analog strap across the digital band is acceptable and the flow draws it. Not a decision this wave may take. |
| **W14-D** | **H 2764 if the owner wants 70 %.** c2 measured the coefficient the extrapolation needed; 2764 is a legal lattice point and lands at 70.1 %. One cut. |
| **W14-E** | the four W3 WQ26c fixes and the macro guard went into the `_pt` CHIP flow as well as the core's. **`MCU_castalia_penta_pt` has not been re-cut with them**, so pt11 remains the B chip cut of record and does not carry them. |

## 4.10 W13, 2026-09-14: the CORE-ONLY topology B, and what is parked

Owner instruction of 2026-09-14: stop including the pad ring, implement the core
only, and shrink the control-plane area of the per-tile-analog topology, because
it is mostly empty space. New block `innovus/common/MCU_castalia_penta_pt_core`;
the `_pt` and `_pt_b` lineages and topology A were not written. Full report:
`<scratchpad>/reports/W13_core_only_B.md`; geometry in that block's
`FLOORPLAN_CORE.md`.

**The floorplan study, which the owner asked for before any cut.** The top cell
is `MCU` (Genus `MCU_PENTA_pt`, md5 `2355f2f3`), so the pad wrapper, its 95 pad
cells, the ten `PRCUTA_G`, the seal band, `anatop_biasgen_g0`, ANATOP parts
1b/2/3/3b, delta **C17**, WQ-DELTA 22 and WQ-DELTA 24 all have no object and are
removed rather than disabled. The 525 MCU port bits become core-boundary pins.

Three measured quantities fix the die and nothing is chosen: the tile is
660 x 880 with its `anatop_ch` cutout on the die-facing edge (so W >= 1320 and
H >= 1762), the centre macros are 714,345 um2, and the standard cell to place is
365,538 um2 (pt11 `summaryReport`, physical cells excluded). Above the tile
minimum **a micron of width buys 1,760 um2 of corridor and a micron of height
buys W um2 of band**, and the corridor is not a usable logic region below about
200 um -- so every wide-and-short candidate overshoots the free-area budget in
space that cannot be routed to. The smallest die that closes to the owner's
65-70 % puts all of the logic in ONE band:

| | chip `pt11` | core `c1` |
|---|---:|---:|
| core box | 2690 x 2690 = 7,225,344 um2 | **1400 x 2714 = 3,791,376 um2** (-47.5 %) |
| die incl. pad ring | 3000 x 3000 = 9,000,000 um2 | **none: the die is the core** |
| centre band | 928 x 2688 = 2,494,464 um2 | **952 x 1398 = 1,330,896 um2** |
| corridors between the tile columns | 2 x 1330 x 880 = 2,340,800 um2 | 2 x 40 x 880, **cut** |
| centre macro area | 829,945 um2 (incl. the 115,600 bias generator) | **714,345 um2** |
| free row area | 3,988,171 um2 | **540,345 um2** |
| **utilisation** | **9.2 %** (tool: pure gate density #4 8.976 %) | **67.6 %** |
| north-centre corridor reserve | 691,600 um2, **426,200 held** (P15) | **0: no corridor, no bias generator** |
| hart0 soft region | 455,135 um2, 326,996 free, **19.8 %** (43.2 % on castalia_b) | **166,868 um2, 95,875 free, 67.5 %** |

**The floorplan + PG stage PASSES every gate**, and the whole-die M7/M8
wide-metal spacing census on its own DEF is better than the chip's: M7 S3 0/0,
S4 **1**/2 over 9,768 rectangles; M8 0/0 over 1,371. Three gates characterised
against the 2690 um die were re-derived from their own run-time measurement, not
relaxed: the WQ-DELTA 5 M7 phase 21.6 -> **0.9 um** (the gate's own 56-phase
sweep; 21.6 now scores 5 hazards and 0.9 scores 2), the WQ17 uncovered-row
budget from an absolute 60 to **10 % of the live row count** (measured 61 of
1252), and the WQ21 tile-PG-weld floor 40 -> **0** (1 of 120 stripes coincides
with a riser pad at the new phase -- a weld floor is the wrong gate for a
coincidence count).

**There are no tile header switches to re-plan.** `VDD_SW` and `PD_*` appear
zero times in the netlist, every `sroute` reads `-nets { VSS VDD }`, and the flow
FATALs on any switched rail (CP4b TODO 4). `FLOORPLAN_PT.md` section 4.2's claim
to the contrary is stale prose and is not fixed from here.

**B-PT9-2 cannot arise on this block**: the class was a core tie cell overriding
a pad `attachTerm`, and there is no pad. Delta C17 is deleted, not disabled.

**B-PT11-1 on this core, by construction.** `POC` does not exist -- it is a tphn
`.GLOBAL` rail carried by pad cells that are not in this netlist, so the pt11
`POC` open is a pad-ring artefact that cannot recur. The four bias rails are
ordinary five-terminal port nets (one boundary pin, four tile pins) with the
placeholder `anatop_biasgen_g` abstract out of the path; what remains of
`W-PT1-1` is one level down, in the `hart_tile_pt` placeholder, unchanged.
`AVDD`/`AVSS` needed a decision and got one: with no pad, no PRCUT bracket and
no C12 ring, the core **exports eight PG pins** at the eight tile analog pins,
which already sit on the die edge, and the four channels' analog supplies are
joined outside the block. That is a boundary contract rather than an open, and
it is the honest limit of a core-only deliverable. The LVS number that confirms
it needs the GDS.

**PARKED, in order:**

| # | item |
|---|---|
| **W13-A** | cut `c1` is **ROUTED and MEASURED, NOT timing-closed.** Three attempts, 03:50 to 06:55; attempts 1 and 2 stopped at chip-era absolute census constants (the C16 "0 TIE_TOP nets is fatal" test, whose own message names the pad band it protects and which is now a consistency test; and the WQ23 filler floor of 400,000, read against a die with 3,988,171 um2 of free row where this core has 540,345). Attempt 3: signoff **setup +0.086 ns / 0 violating of 34,780 paths**, signoff **hold -0.011 ns / 6 violating** after both in-flow ECO passes, `verifyGeometry` **Cells 0, SameNet 0, Wiring 0, Short 0, Overlap 0**, Antenna 13, `verifyProcessAntenna` **0**, Quantus extraction **COMPLETE 97,657 of 97,657**. FATAL at WQ27 so **no GDS**; the signoff database is saved. It parks exactly where pt7, pt9 and pt11 each parked -- HOLD -- and the way out is the out-of-flow incremental ECO whose driver is not yet ported to this block. |
| **W13-A2** | the 13 `verifyGeometry` Antenna results and 7 unclassified dangling wires (11 total, 4 waived; the samples are PG stubs, `VDD M6 (16.250,1296.565)` and `VSS M4 (1049.100,898.500)`). None is a real antenna. |
| **W13-A3** | **the one number this study got wrong.** `timeDesign -signoff` reports **Density 81.682 %** against the 67.6 % the die was sized for. The planning figure was pt11's measured cell area, 365,538 um2 -- but that is the area after optimisation at **9 %** density, and a design optimised into a 68 %-full floorplan buys 21 % more buffering (implied placed area 441,363 um2). Size from the post-optimisation area at the TARGET density; the first cut is what measures it. H 2714 -> **2779** lands the block at 70 %, a 3.885 mm2 core, still 46.2 % below the chip's. 81.7 % routed without a congestion failure, so c1's die is usable as it stands. |
| **W13-B** | core DRC. Expected to be the pt11 census MINUS the pad kit: the 1,506 `ESD.*g` and the 312 `PO.R.8` come from tphn cells that are not in this stream, so **their presence would mean a pad cell leaked in**. |
| **W13-C** | LVS with the negative control. The collateral generator does not exist yet: it is `gen_MCU_castalia_penta_pt_b_lvs_collateral.sh` with the block dir, the design name and the CUTSEL/XSIMSEL defaults changed and `patch_chip_pads_penta_pt.py` DROPPED. |
| **W13-D** | stream and promote into `castalia_B_core`. `signoff_mp/Makefile` was NOT edited (W12's wave is in it); the block definition is written out in the new file `signoff_mp/blocks_pt_core.mk`, whose header lists the four edits that file needs, with line numbers. `innovus/common/Makefile` needs one rule, a copy of `MCU_castalia_penta_pt_b.innovus`; until it lands, `./run_core.sh <CUT>` is the same command line. |
| **W13-E** | fold the six post-surgery fixes back into `<scratchpad>/w13/surgery.py` so the flow regenerates in one step. |

**Three Innovus 20.12 behaviours paid for here.** `editPin -unit` requires
`-spacing` (IMPTCM-113). The ranged and spread forms of `editPin` **SEGFAULT the
process** on a 505-name `-pin` list -- one `-assign` per port is what this flow
does instead. `dbGet -p top.terms` is rejected: `-p` requires a pattern.


## 4.9 W3, 2026-09-14: topology A confirmed on the new RTL. Cut d13c is the cut of record.

Full report: `<scratchpad>/reports/W3_topology_A_d13c.md`. No tracked file but this
one was modified; `hdl/` and `platform/` were never written.

**Genus `MCU_PENTA` from a frozen staging of HEAD `aa2d5fda`** (the commit after the
three CDC fixes), 00:30:52, every gate at `GATE_STRICT=1`, pmk census 0, drift 0 of
72. **The CDC census is the headline: NOT waived 701 -> 3.** The 701 was the waiver
lint reading the list differently from Tcl, fixed in `bfbedb55`; the residual three
are `nfc0/t_etu_reg[0]/D` (mclk -> nfc0_rf) and `spi0`/`spi1` `s_gap_reg/D`
(mclk -> clk_sck0/1), all one-bit quasi-static, all consequences of the W10 fixes
plus Genus's own register merging, and all needing an entry in
`hdl/common/cdc/cdc_waivers.tcl` that this wave may not write. QoR against W1's
cut: 130,812 -> **130,863** cells, 24,339 -> **24,355** flops, 0 latches, worst
setup slack unchanged at **+3,529 ps**.

**The topology-A tile.** T3's harden had never had its Calibre pass. It does now:
blockdrc **14** against the d13a tile's 16 (the two 20 nm `M3.S.2` survivors are
gone, one `M2.S.2.1` appears elsewhere), ant25 **0**, LVS **MATCH** with sentinels
ARMED, ERC bit-identical. Promoted as the tile of record, pinned at
`innovus/common/hart_tile/out.d13c_ref/`.

**Chip cut d13c, closed on attempt 4**, `out/MCU_castalia_penta.d13c.gds2` md5
`60c4b13a58f8ccb9df13767e471e3368`:

| | d13b | **d13c** |
|---|---:|---:|
| setup / hold WNS, 4 coupled-SI views | +55 / +1 ps | **+67 / 0 ps**, 0 violating both |
| chipdrc | 1805 | **1792** (1506 ESD + 64 density + **172 `PO.R.8`** + 50 real) |
| ant25 | CLEAN | **CLEAN**, identical |
| LVS | 1 waiver | **1 waiver** (the placeholder macro), negative control PASSES |
| WQ27 waived Short / dangling | 2 / 67 | **0 / 65** |

Four attempts, four flow defects, all fixed at source: (1) WQ-DELTA 13's
`mcu0/timer*/g11710` were stale literals that had never existed in any netlist,
and `set_disable_clock_gating_check` accepts an unresolvable name in silence --
two false clock-gating hold checks at **-9.3 ns**, now DERIVED from
`mcu0/timer*/clock_source`; (2) WQ26c refused multi-sink nets and the whole
residual was the `mp_arb0` read-data bus, though `ecoAddRepeater -term` is
terminal scoped; (3) WQ26c ran once per cut and so never saw the endpoints the
ECO's own re-extraction opens, now once per pass; (4) **C17**, W2's topology-B
root cause, present here too: `addTieHiLo` re-bound the two analog pad terminals
ANATOP part 3 had attached to AVDD/AVSS, and that is where d13b's two analog-pad
`SHORT` results came from. `-excludePin` plus a census that FATALs on any analog
pad terminal left on a tie net; **those two waivers are retired, not carried**.

Topology A's LVS shows **neither** of the two residual classes W2 reports on B:
`rm1` and `rm2` compare 2:2 with zero unmatched, and there are no
`** missing connection **` lines at all -- A has no shared bias rails, each pixel
carrying its own local bias generator.

**Parked items, one bounded attempt each.** *hart-0 region fence*: the 129
"violations" are `adddec0`, `bnd_*_r`, `tx_rdata_r` and `sh_rdata`, every one an
interface register whose counterparty is west of the flank; containment 99.47 %;
the soft region is working as designed and what needs changing is the instrument,
not the floorplan. *`PO.R.8` 172*: the register's claim that the residual sits at
the flow's other `cutRow` sites is **wrong** -- all 120 top-level results are in
x[908.0,1664.9] y[2143.5,2168.6], the row band under the analog macro's halo cut
-- and **70 of them are inside the 6 um band WQ28 already taps**, so more or
deeper tap strips is refuted at chip level as it was at tile level. The band is
where two independent cuts truncate the same rows 21 um apart (the analog-window
cut at 2149, the macro halo cut at 2170); snapping both to whole tap boundaries is
the floorplan change to try, and it is the owner's. *ERA macro PGV*: three tool
blockers cleared (LEF set, layermap dialect, techonly-first merge) and
`ERA_PGV_DIR` added to the shared driver, but a LEF-abstract macro PGV still loads
19.83 mA of 32.32 mA -- the same 61 % -- because it carries pin geometry and no
internal resistance network. A GDS- or SPICE-based PGV off the SIGNOFF strmout is
what would close it.

**Ingested as `castalia_A_d13c`** (0 errors, all strmin gates fired) with a
README that states what the cut does NOT establish: the 172 open `PO.R.8`, the
placeholder macro, the absent ERA verdict, the three unwaived CDC crossings, and
LEC never having run. All three signoff knobs, `DRC_WAIVERS_d13c.md`, both
runbooks and the attic index moved with it.

## 4.15 Z5, 2026-09-15: O9 IS SATISFIED. Both assemblies pass every gate and the chip regression

Full report: `<scratchpad>/reports/Z5_o9_evidence.md`. Z4 left O9 unmet for exactly two
reasons and both are closed.

**Z4-1, the shim.** Z1 removed the falling-mclk re-register of the shared-slave peripheral
enables; Z4 bisected topology B's zero-delay gate regression (0/14 TIMEOUT against 13/14) to
that 72-line delta alone. It is restored at its source in
`platform/common/python/mcu_vhd.py` and `MCU.template.vhd` -- eleven flops. A negative-edge
flop on `mclk` is a clock on a clock pin, so the owner's rule (no DATA signal on a flop clock
pin) is untouched and the clock-pin census still reads 0 / 0 waived / 0 NOT waived. The
emitted VHDL is byte-identical to the pre-Z generation: the diff against the `MCU.vhd.pre_z4`
Z4 staged for `out.z4bx` is a timestamp and six comment lines, zero statements, on both chip
configurations. The prose is new because the reason changed under the set: no peripheral
clocks a snapshot latch on falling `en_mem` any more, but the arbiter still clears `s_en` on
the same rising mclk edge at which the slave samples `EnMemPeriph`, so a raw-strobe shim
deasserts the select in the same delta as its own capture edge -- fatal at zero delay,
invisible with real cell delays.

**The CDC gate.** Z4's armed census refused both assemblies at 248 unwaived crossings in four
register classes. All four are the toggle-qualified multi-cycle payload the waiver file
already accepts three times over; each was read out of the RTL before it was waived
(`NFC.vhd:356-358, 372-380, 784, 787` on `u_sync_rf_pub`; `TIMER.vhd:409-411, 450-452,
576-578, 591, 594` on `u_sync_cap_tgl`). Five globs, because `capture0_mem` and
`capture1_mem` take one each. Z4's fourteen deletions are kept and the eighteen zero-hit
globs are kept and re-measured at zero on both new cuts.

| | topology B `out.z5b_20260915` | topology A `out.z5a_20260915` |
|---|---|---|
| netlist md5 | **`b5c78884`** | **`f8b3e421`** |
| gates | `all gates passed (GATE_STRICT=1)`, drift 0 of 75 | same, drift 0 of 72 |
| **CDC, ARMED** | 1000 endpoints, **891 waived, 0 NOT waived** | 1000, **891 / 0** |
| pmk / latch / clock-pin | 0 / 0 / 0-0-0 | 0 / 0 / 0-0-0 |
| flops | 24,862 -> **24,873** | 24,794 -> **24,805** |
| worst setup slack | +3,548 ps unchanged | +3,548 ps unchanged |
| zero delay | **13 / 14**, `shtcm` FAIL at 20089645511899 FS | **13 / 14**, same FS |
| genus SDF, tt/25 C | **14 / 14** ALL ROWS PASSED | `shtcm` **PASS** at 34005728622575 FS |

Both femtoseconds are T1's, W4's and Z4's, so the regression reproduces the reference table
row for row and flag for flag. `*W,SDFNET` is 0 on both SDF legs. Tile netlists are untouched
(md5s unchanged and the intersection of `hart_tile_pt`'s staged read list with this wave's
seven changed files is empty), so the tile harness was not re-run. Both netlists are promoted
into their flows' `out/`, previous cuts kept as `out.pre_z5_20260915`.

**Z5-1, a flow defect worth the name.** A gate harness names its netlist in *both*
`harness.conf` and its cell list, and `run_gate_suite.sh` rewrites only the cell-list line
that equals `NETLIST_DEFAULT`. A freshly staged harness with the two disagreeing therefore
printed `out.z5b` in its header, its md5 and its results file while `xmvlog` compiled Z4's
shim-less `out.z4b2` -- a clean 0/14 for a netlist that was never read. The shared runner now
FATALs when the netlist it just printed is not among its Verilog inputs; the negative control
discriminates.

**What O9 unblocks, and what it does not.** The push and the merge are clear. Both promoted
chip cuts now postdate the Innovus runs that read their predecessors (`d13d` on A, `c3` on B),
so a re-harden on each is the next physical step. Still open and unchanged by this wave: the
`_pt` flow has no dead-clock census, 24 to 28 dead `create_clock` lines stand in the two flow
files, no `_pt` chip cut has written a P&R SDF (so both SDF legs here are the pre-layout genus
SDF at tt/25 C and `SDF_RECOVERY` remains a tile-harness knob only), and the eighteen zero-hit
waivers still want X2's and Z2a's decision.

## 4.16 Y3, 2026-09-16: the 2 mm IO ring, built and clean; the package is the blocker

Full report: `<scratchpad>/reports/Y3_io_ring_2mm.md`. Owner decision O10 fixed
die Y at exactly 2 mm including ring and seal. The ring is built, every gate
passes and `verifyGeometry` finds nothing.

**The frame, measured.** Pad depth 135.0 um and pad pitch 25.0 um are the `SIZE`
of every cell in `tphn65gpgv2od3_sl_8lm.lef`; the seal band is the flow's 20.0
um. So the ring band is **155 um per edge** and **core Y = 2000 - 310 = 1690**,
not O10's provisional 1650 -- 40 um of free core height, and the control band
becomes 790 um tall rather than 710. **Y2 must land 1690**; the flow now FATALs
on any die Y off 2000. Core X 1970 = two abutted 985 um tiles, so the die is
**2280 x 2000 um**. One further constraint on Y2: **no `MY` tile orientation**
(top row `R0`, bottom row `MX`), because four *identical* analog sections are
only possible if tile-local x maps to chip x unchanged.

**The analog section is 600 um -- exactly one notch, brackets included**, and
four copies are cell-for-cell identical. Slots 9-14 carry AVDD, AVSS, CE, WE, RE
and ATP and sit **exactly** over `anatop_ch`'s own die-edge ports, which the
abstract already puts on a 25 um pitch: every electrode is a 49 um vertical drop
with zero lateral travel. The other sixteen slots are five AVDD and five AVSS
pads in parallel (one net pair per channel, the X3-A agreement applied at the pad
end), **two `PVSS2A_G` latch-up anchors**, and six reserved analog debug pads.
The shared bias island moves to the **east** row -- in the flat arrangement the
control plane is a horizontal band, so its nearest edges are west and east, not
pt11's north-centre -- and picks up force/sense pads on the four live bias rails.
Five islands and ten `PRCUTA_G` as before, so gates C3 and C4 keep their literals.

**The last pad-ring residual is closed.** `RN_TPHN65GPGV2OD3_SL_210B` 6(i) wants
a bonded `PVSS2A/2AC_G` within 1 ohm of VSS bus of every `PDBxA_G`; pt11 placed
**zero** and commit `225fadcd`'s own message records the gap. This ring places
nine, worst `PDB3A_G`-to-anchor run **6 cells / 150 um** (measured by a new gate
on the placed database). The 1 ohm itself is still an extracted number.

**Digital: 73 pads in five arcs, every arc with its own VDDPST/VSSPST pair by
construction.** pt11 had four pairs for five arcs and needed resolution S1 by
hand. All 48 GPIO bits, RESETN, the five TAP pins and POC keep their cells and
their core-side nets, and unlike pt11 **no GPIO port is split across edges**.
171 pads sit in 292 perimeter slots; the 106 leftover slots are filler and stay
filler, because a seventh GPIO port is a peripheral instance, a memory-map slot,
an IRQ vector and RTL -- not a ring change.

**A defect the new gates caught before anything was declared done.** An arc
**wraps a corner**: the north edge's east span and the east edge's north span are
one arc, joined through `PCORNER_G`. pt11's C-G3 walked the two horizontal rows
separately and could not express that. The first digital placer used first-fit,
put the two east runs in each other's spans, split `PAD_VDDPST_3` from
`PAD_VSSPST_3` across two arcs and left both unsupplied -- the exact class S1 had
to repair by hand. Runs now name their span; the gate re-derives the arcs from
the database.

**The whole ring is emitted, not typed.** `gen_padring_pt2mm.py` is the plan and
produces the padlist tcl, the frame knob header, the chip wrapper's pad instances
and `config/padring_pt2mm.json`; `--check` proves the tree matches and
`run_ring.sh` refuses to start Innovus if it does not. A die-size change is one
edit in one Python table.

| gate, run `y3r4` | result |
|---|---|
| O10 frame | die **2280.0 x 2000.0**, core 1970.0 x 1690.0 |
| C-G9 (new) section over notch | 4 of 4 |
| C3 / C4 | **10** brackets; **171** pads, every one bound to the cell the padlist names |
| C-G8 (new) latch-up | 9 anchors, worst run 6 cells, 0 islands outside budget |
| C-G3 I/O supply per arc | **5 arcs, 0 unsupplied** |
| C-G10 (new) pad-ring power | every supply pad bound; 10 analog nets, 44 pad terminals |
| **verifyGeometry** | **Cells 0 / SameNet 0 / Wiring 0 / Antenna 0 / Short 0 / Overlap 0** |

Generator gates: `package_die_row_test`, `castalia_b_generation_test`,
`generation_determinism_test` and the overlay determinism test all re-run
unchanged and pass (`padring_pt.json` and the package model are untouched); the
new `padring_pt2mm_test` passes 15/15 and fails on a deleted latch-up anchor.

**Y3-B, THE BLOCKER, and it is the owner's: LQFP-100 is exhausted by this ring.**
The essential set -- 55 digital signals, 18 digital supply pads, 24 per-channel
analog, 2 bias -- is **99 of its 100 fingers**, and the per-edge cap of 25 binds
hard: twelve essential analog pads on each of the north and south rows leave the
**east edge needing 30 fingers of its 25**. Rebalancing is arithmetically
possible only by splitting GPIO ports across three edges, with zero margin, and
with all 72 surplus pads unbonded -- including every `PVSS2A_G`, and 6(i) says
*bonded*, so the latch-up fix is only a fix in a package that can bond it. No
ball is therefore assigned anywhere in this wave and the package model is
untouched. Three resolutions are costed in the report (QFP/QFN-176; LQFP-100
with ports split and 72 pads unbonded; chip-on-board). **The die geometry is
identical under all three** -- the property B3 established for pt11. Wiring
`padring_pt2mm.json` into `generate.py` needs the decision first; the edit is one
package-model branch in `vesta_overlay.py` plus a chip config, about 200 lines.

Also open: **Y3-A**, `anatop_ch` exposes exactly ONE analog debug output (`ATP`),
so 25 bonded pads have no internal driver -- the ask of Y1 is four to six more
taps on the same 25 um pitch (ATP2, VOUT, VREF, VCM, RE-force), and the ring does
not move either way. **Y3-1**, ANATOP parts 3b / C12 / C14 / C17 and the WQ27
waiver class still name one `AVDD` / `AVSS` while part 3 now creates five
domains; a hard gate stops the flow there rather than three thousand lines later,
and generalising them belongs to the first cut with a real core to strap to.
**Y3-2**, `addIoFiller -area` is unsupported on Innovus 20.12, so the
analog-profile spacer pass never runs -- inert today because the island spans are
gap-free, live the moment a pad is added to or removed from an island.

The ring is a ring on an empty core: `hart_tile_pt` is still the pt11 master and
the B core is still the L-shape. The first cut that places tiles inside this
frame is the one that proves the notches line up in metal rather than in
arithmetic, and gate C-G9 is what will say so.

## 4.17 Y2, 2026-09-16: the B core for the flat 2 mm die. Phase 1 done, the geometry is derived, c4 waits on Y1

Report `reports/Y2_core_flat_c4.md`.

**Core 1970 x 1690 = 3.329 mm2, die exactly 2280 x 2000 um** -- Y3's number,
reached independently from the same three measured depths (pad 135.0 from the
tphn LEF, pad-to-core gap 0.0 from the pt11 flow, seal 20.0 from `SEAL_OFF`).
O10's provisional 1650 and the brief's "rounded down to the M8 lattice quantum"
are both superseded, and the reason is a finding rather than a preference:
**W14's `H = 2714 + k*50` is a property of a fixed 39 um M8 band inset, not of
the mesh.** The inset is the C0 idiom and has slack, so the lattice is phased to
the die height instead of the height being quantised to the lattice
(`fp::solve_inset`: 18.3 um on the O10 stub, worst tile PG pad gap 14.0 um
against the 37.5 the blockPin sroute is proven to bridge).

| phase 1 item | state |
|---|---|
| Z5 netlist `b5c78884` staged; core SDC regenerated | DONE. X3's census: 31 of 31 `create_clock` resolved, 52 of 52 generated. |
| the in-flow dead-clock census the `_pt` Genus flow lacked (Z5 open 1) | DONE, reported not fatal. Measured: **24 of 53 declared clocks have no sequential sink**, 17 of them `*_enmem` -- identical to Z4's out-of-flow list. |
| X2-2 ported to the B lineage | DONE. WQ26 armed on setup as well as hold, WQ26e before the hold pass, `PENTA_SETUP_TARGET` 0.20. |
| the flat arrangement as a first-class option | DONE, as PROCEDURES (`tcl/core_floorplan_lib.tcl`) that read the tile abstract at run time, not as a second set of literals. `PENTA_CORE_ARRANGE=quad` reproduces W13/W14/X3 exactly and that is how the derivation is checked. |
| unit test | DONE. `tclsh tcl/core_floorplan_test.tcl`, 60 checks, 0 failures, ~1 s, no licence. Part A re-derives every W13 constant and the whole of W14 section 3.1's mesh table from the REAL pt13 abstract. |
| floorplan stage on a stub abstract | DONE and BEYOND the brief: the floorplan+PG stage runs END TO END on an O10-geometry stub and writes a DEF. |
| X3-A (AVDD/AVSS) | **CLOSED at both ends.** Four independent `AVDD_<h>`/`AVSS_<h>` nets with one boundary PG pin each, in the flow and in the LVS netlist tcl, matching Y3's per-tile pad sections. `lvs_cpoint` stays refused. |
| cut `c4` | **NOT STARTED.** `hart_tile_pt/out/Y1_READY` does not exist. |

**Agreed with Y3, in writing and in the log**: tile origins hart1 (0,1239) R0,
hart2 (985,1239) R0, hart3 (0,1) MX, hart4 (985,1) MX -- **never MY or R180**, so
tile-local x maps to chip x on all four and the ring's four analog sections are
identical. The flow prints all four every run; Y3's C-G9 re-derives them.

**Five flow defects found by the flat floorplan and fixed at source**, each a gate
that passed on the quad floorplan for a reason that does not hold here, none of
them fixed by relaxing it: a degenerate `cutRow -area` box with a gate keyed to
"something was removed"; the WQ17 corridor census window inverted when there is no
corridor; the WQ17 row-coverage POCKETS printed after the FATAL rather than before
it (two floorplans were re-run to learn what the gate already knew); rows too
narrow to be strapped counted instead of cut (436 of 469); and the WQ5 measured
backstop counting a gap that exactly MEETS M7.S.4 as violating it, in double
precision.

Parked: **Y2-A** WQ19 reads 41 PG-stage special-wire opens against a budget of 20
on the stub, 10/10/11/33 inside the four tiles -- it measures the TILE's PG pad
pattern, which the stub invents, so it is the first thing to re-measure with Y1's
real abstract. **Y2-B** the lattice against the real tile (a `tclsh` sweep finds a
legal inset at H 1690 for notch depths 140/250/310, but the real pad rows decide).
**Y2-C** the 24 dead clocks. **Y2-D** the B CHIP flow now carries X2-2 and two WQ5
changes it has never been cut with, on top of X3-E's four. **Y2-E** two surviving
WQ17 pockets in the band's second row.

### Y1 -- `hart_tile_pt` re-floorplanned from content for the 2 mm die (2026-09-16)

**DONE. Tile of record `CUT=y1f`, `out/Y1_READY` written, Y2 unblocked.** Report
`tapeout_review/reports/Y1_tile_pt_flat.md`.

The tile is **985 x 450** with an **L**-shaped die: one 355 um full-height west
column holding the TCM, and a **630 x 310 east-flush analog notch** on the
die-facing edge holding a **600 x 250 `anatop_ch`** at (370,190). 348 pins
(344 digital + 4 bias) on the band-facing edge over x[4,916]; the four
electrode/ATP pins and AVDD/AVSS on the die-facing edge. O10's "600 x 250 notch"
is the MACRO; the notch is that plus the clearances the flow's own mechanisms
need -- 10 um for T5c's M6 stub and the electrode via, 50 um for the T5b-2 jog
band, 15 um each side for T-G1 and the tile abutment.

**Why an L.** The TCM is 319.65 x 208.675 and a 250 um analog reservation in a
450 um tile leaves a base band shorter than the macro, so it can only sit in a
full-height side column of about 355 um -- and 985 - 630 = 355 um of side column
exists in total. It is also the better shape: the PG4/F2b failures that
bracketed the old `BASE_H` at 340 (81 and 101 um fail, 121 passes) are gone by
construction, because the clear M2 window above ram0 is now 231 um.

**Both notch walls are on the 50 um PG lattice and that is load-bearing.**
`NOTCH_X0 = 355`, `BASE_H = 140`. A wall on the wrong phase puts an
opposite-net stripe inside the notch ring band -- `BASE_H = 180` shorts the VSS
floor leg to a VDD M8 stripe. Move either only in 50 um steps.

| | `pt13` (660 x 880) | **`y1f` (985 x 450)** |
|---|---|---|
| LEF PIN records | 356 | **356**, `SIZE 985.000000 BY 450.000000` |
| digital pin pitch | 1.598 um | **5.006 um**, 348 assigned, **0 relocated** |
| switches inserted / reachable / floating | 732 / 728 / 0 | **477 / 477 / 0** |
| Quantus | 11401 / 11401 | **11091 / 11091** |
| G0 | MINCUT 0, Short real 0, Wiring 0, M1 merges 0 | **identical** |
| signoff setup / hold WNS | +0.376 / +0.034 ns | **+0.571 / +0.030 ns**, 0 violating |
| density | 21 % | **27.152 %** |
| `blockdrc` | 16 = 15 density + 1 `DRM.R.1` | **15 = 14 density/dummy + 1 `DRM.R.1`** |
| `ant25` | 0 | **0** |
| Pegasus LVS | **MISMATCH**, `anatop_ch` VSS open, waiver `W-PT1-1` | **MATCH**, pins 356:356, no supply-pin exception |
| gate harness, 41 rows | ff 41/41, ss 41/41 | **ff 41/41, ss 41/41** |

**`W-PT1-1` can be retired**: moving the macro's two south supply ports onto the
tile's M7 PG column lattice (done to kill a MINCUT marker) also made T5b-3's
landing merge into a column instead of reaching 10 um for one, so the VSS strap
lands and LVS is a clean MATCH. Promoted by the `ingest` inside
`make signoff BLOCK=hart_tile_pt`; proved from a fresh headless Virtuoso as
`hart_tile_pt_signoff/hart_tile_pt/layout bBox=((1.0 0.0) (984.0 450.0))`,
41,465 instances.

**What closed it, after five attempts against a bound of three (Y1-E).**
`DEAD_ROW_BANDS` is EMPTY. The new gate **Y1-PSW** -- every core row segment
carries a header switch or is a declared dead row, measured on the database
ninety seconds into every cut, because Innovus truncates `IMPPSO-306` at 20
messages and that hid 107 dead rows on the first attempt -- reported **366 row
segments, 0 uncovered**. The whole dead-row apparatus therefore had nothing to
do, and its scrub was the sole source of the two orphan markers that stopped
attempts 4 and 5. The second new gate, `pg1_corridor_m7_clear`, tests an AO
repeater's link corridor rather than its strap band; without it PG4/F2b aborts
40 minutes in.

**For Y2** (all of it also in `out/Y1_READY`): `PENTA_CORE_NOTCH_X0 = 355`,
`PENTA_CORE_NOTCH_W = 630` (east-flush, `NOTCH_X1 = TILE_W = 985`),
`TILE_W 985`, `TILE_H 450`, `TILE_NOTCH_Y0 140`. The notch is **no longer
mirror-symmetric in x**, unlike pt13's, so the chip's notch blockage has to be
mirrored with the tile -- harmless under the agreed R0/R0/MX/MX placement, but
now an assertion rather than an inheritance. M7 PG pads: VDD `51 + 50k`, VSS
`60 + 50k`, on the bottom edge across the full width, on the notch floor
(y[135,140]) east of x=355, and on the top edge (y[445,450]) west of it. Six
die-facing analog ports at tile-local **607.5 + 25k**, order AVDD AVSS CE WE RE
ATP -- with the agreed tile origins x = 0 and 985 that is chip x `7.5 mod 25`,
which Y2 can phase away in the tile origin or Y1 can move with
`TILE_PT_ANACH_X=362.5` at the cost of one harden.

**Open (Y1-D), an ordering constraint, not a preference:**
`signoff_mp/anatop_ch_bbox` is rebuilt at 600 x 250, so a chip signoff run
against `pt13` collateral would now resolve the macro to the wrong footprint.
**Open (Y1-H):** each gate-sim row logs one timing violation at t = 3-4 ps on
`ram0`'s unannotated `$hold(negedge PGEN, posedge RETN)` retention check at the
model default; pt13 logged none, and all 41 rows still pass at both corners.

### 4.17b Y2 phase 2, 2026-09-16: cut `c4` closes setup, fails hold, and names the blocker

`Y1_READY` landed 04:16; all six collateral md5s verified against it, tile
interface 356 bits / 52 base names / 4 instantiations matching bit for bit, SDC
census 31 of 31. Cut `c4` on `out.y1f_ref`.

**Signoff, coupled SI, on a floorplan and a tile neither of which had ever been
cut:** setup **+0.074 ns, 0 violating of 37,294**; WQ19 opens **0 / 0 / 0**
(cpr9 192/979/1620); WQ21 PASS both layers; Quantus COMPLETE 99,441 of 99,441;
density 51.005 %. Hold **-0.765 ns, 270 violating** -- and the group split is the
finding: `reg2reg` **-0.063 / 18**, `default` **-0.765 / 253**, and the 253 are
**100 % `Library Clock Gating Hold Check`** launched from `timer1/en_mem`, which
the SDC constrains as `create_clock timer1_enmem` and which this wave's own new
in-flow dead-clock census measures as having **no sequential sink**. The ECO
proves it: pass 1 inserted 15 cells and fixed ten real paths, pass 2 inserted
**0**. The physical residual is 18 paths at -0.063 ns, the scale c2/c3 closed.

**Second defect, fixed at source:** `wq26c_hold_violators` read only the 50-path
`*_all_hold.tarpt.gz` and matched only `Hold Check`, so the false checks filled
the report and the in-cut fixer reported "no violating endpoint" and did nothing.
It now reads every per-group report and classifies; on c4's own reports it
returns 7 ordinary endpoints and names 100 clock-gating ones, where the old proc
returned nothing.

**c4 did not stream.** No GDS, so DRC / antenna / LVS / ingest / promote / the
chip gate regression are unrun and `castalia_B_core` still holds **c3**. Routed
database kept at `dbs/MCU_castalia_penta_pt_core.c4.holdfail.innovus.dat`.

**Y2-A and Y2-B are CLOSED** (WQ19 `IMPVFC-200 = 0` on the real abstract against
41 on the stub; band inset 32.7 um at H 1690 with worst PG pad gap 30.2 um).
**Y2-G is the blocker**: delete the seventeen `*_enmem` `create_clock` lines at
their Genus source, X3's shape, then re-cut. Also found and fixed this phase:
`QTILES` and `fp::tile_places` were two placement lists allowed to disagree
(`FATAL (PG tile census): hart4 (R180,bottom) VDD sWires=0`) -- `set QTILES
$FP_PLACES` removes the second. Four attempts against a bound of three, recorded.

## 4.18 Y4, 2026-09-16: the 24 dead clocks deleted at the Genus source; the c4 hold miss closes; `c5` parked at CPR6

**Y2-G is closed at its source and the fix is measured.** The 24 `create_clock`
declarations that the dead-clock census named as reaching no sequential cell are
deleted from `genus/MCU_PENTA_pt/tcl/MCU_PENTA_pt_hier.genus.tcl`: four protocol
source clocks (`clk_scl0/1` on `i2c?/SCL_IN`, `clk_sck0/1` on `spi?/sck_in`),
seventeen `*_enmem`, three SDA. Each carries two independent pieces of evidence,
the census (`all_registers -clock` = 0 on the netlist of record `b5c78884`) and
the RTL, which states it in its own words -- `QSPI.vhd:244` "Nothing here is
clocked by EnMemPeriph", `NFC.vhd:4`, `TIMER.vhd:556`, `UART.vhd:551` -- plus a
structural fan-in walk of the netlist that finds no path from any of the 24 pins
to any clock pin. The four protocol cost/path groups, the `i3c0 SCL_IN` false
path and the Genus-19.15 `reset_clock` power workaround went with them.

**One Genus cut against a bound of two**, from `genus/common/in/y4_frozen`, a
byte-identical copy of Z5's freeze, so the constraint change is the only
variable. `all gates passed (GATE_STRICT=1)`, CDC ARMED 1000 / 891 waived / **0
NOT waived** (Z5's numbers to the endpoint), dead-clock census now an armed GATE
reading **0**, clock-pin 0, latch 0, pmk 0, drift 0 of 75. The netlist
(`d383a520`) is logically unchanged against `b5c78884`: **1462 modules both,
24,873 flops both, worst setup slack +3,548 ps on the same endpoint**, +15
instances of buffering and drive-strength swaps. The +158,561 um2 of area is
Y1's `anatop_ch` abstract resize (441,600 -> 600,000 over four instances), not
this change. `create_clock` **31 -> 7**; the core SDC is 3,181 lines and both
censuses pass -- X3's existence census 7 of 7, and a NEW netlist-side dead-clock
walk (`sdc_clock_census.py`) 0 of 7 dead. That walk reproduces Genus's
timing-engine census name for name on the old pair, which is what makes it worth
having.

**The deletion does what Y2 predicted.** At the same stage on both cuts
(`optDesign` Final SI Timing Summary, post-route, SI-aware): hold **-0.760 ns /
TNS -104.603 / 253 violating** on c4 becomes **+0.009 ns / TNS 0.000 / 0
violating of 37,075** on c5. The `default` group goes 252 -> 0 and `reg2reg`
-0.016 / 2 -> **+0.010 / 0**, so the 18-path physical residual closes with the
false checks. Setup at that stage is -0.026 ns on 3 `reg2cgate` paths (c4:
+0.144 / 0), the class the X2-2 WQ26 loop is armed for. Neither is a signoff
number: the run never reached coupled-SI Quantus.

**`c5` is parked at the three-attempt bound on an unrelated gate, Y4-A.** All
three attempts were refused by the CPR6 acceptance gate over ONE hold-fix delay
cell, `hart0/tile/FE_PHC18866_tx_sel (DLY2X0P5MA10TH)`. Diagnostics added in
attempts 2 and 3 (additive only; the gate and its refusal untouched) settle what
it is: its output net drives exactly `g2655/A` and `g2648/A`, and the ram0 clock
mux gates `g1828`/`g2668` are NOT behind it -- they stay on the undelayed
`tx_sel` net. The mux switch instant does not move, which is the harm the gate
exists for; a third application of the gating-check disable, immediately before
`optDesign -postRoute`, found the same two gates and eliminated the
missed-clone hypothesis. The gate matches a DLY cell by INSTANCE NAME
(`*tx_sel*`), which is wider than its own stated intent ("any DLY cell landing
on the orchestrator's ram0 mux select"). The fix is one edit -- derive the mux
gates from ram0/CLK, walk back through the repeater chain into their `*tx_sel*`
input, FATAL on DLY cells on THAT path, keep the name census as a WARN -- and it
changes the condition of a tapeout safety gate, so it is the owner's call.

**`c5` did not stream (Y4-B)**, so DRC / antenna / LVS / ingest / promote / the
headless proof and the five-scope P&R SDF leg are unrun and `castalia_B_core`
still holds `c3`. PG stage was c4's number for number: WQ19 0/0/0, WQ21 PASS both
layers, WQ17 51 of 389, WQ5 backstop 6 of 6, density 50.572 %.

**Gate level on the new netlist: 13/14 zero delay** (only `shtcm`, at
`20089645511899 FS`, the reference femtosecond) **and 14/14 under the pre-layout
genus SDF**, `*W,SDFNET` 0 in simulation, and the 14-row raw `Timing violation`
total **889,778, equal to Z5's to the digit**.

**Y1-H is answered: a model-default artefact.** The `ram0`
`$hold(negedge PGEN, posedge RETN, 1.000 : 1 NS)` is unannotated because Innovus
writes the constraint as an SDF `SETUPHOLD` with a null setup field, which does
not map onto the ARM model's bare `$hold`; the tile bench ties both pins
(`tcm_pgen => lo, tcm_retn => hi`), so each has one transition in the whole run;
and the pt13-vs-`y1f` delta is **1 ps of interconnect** (pt13 PGEN 0.006 / RETN
0.005 ns, so RETN rises first and there is no check to fail; `y1f` 0.002 /
0.003, so PGEN falls first). At chip level `tcm_retn` is a `logic_1` tie on all
four tiles, so the four RETN-edge retention checks are unreachable in silicon.
One real gap noted for power-gating bring-up (Y4-C): the two PGEN/CEN checks that
CAN fire are also unannotated, so gate sim measures them against 1.000 ns where
the SDF signs them off at 0.980 / 7.642 ns.

### 4.18b Y4, 2026-09-17: D19 applied, CPR6 passes, `c5` closes SETUP and parks on 5 hold endpoints

**Owner decision D19**: the CPR6 acceptance gate is re-keyed from the `*tx_sel*`
instance-name match to the documented path. The predicate is one file with two
homes (`tcl/cpr6_gate_lib.tcl`, md5 `838ff197` in both the `_pt` chip flow and
the core flow), sourced beside the other helper libraries so a missing file stops
a run in seconds. It walks the `ram0/CLK` clock cone backwards (4 hops, never
descending a `*tx_sel*` net), then probes every input of every cone gate
backwards through repeater stages (6 hops); an input whose probe **reaches the
tx_sel origin** is select-side and a DLY on it is the refusal. Keying on reaching
the origin, not on the cone/name split, is what survives the optimiser renaming a
stage; deriving the cone on the post-optimisation database is what makes a missed
clone impossible. The out-of-range derived-gate count stays fatal; clock-side
delay cells and off-path `*tx_sel*`-named ones are reported.

**Unit-tested without Innovus**, `tclsh tcl/cpr6_gate_test.tcl`, **13 checks, 0
failures**, on a stub `dbGet` over c5's measured topology: it refuses a DLY
between `tx_sel_reg` and `g1828`/`g2668` both directly and one inverter back,
accepts `FE_PHC18866`, reports a clock-side DLY without refusing, and refuses an
underivable mux. The test found a defect in its own stub first (a redefined
instance left a phantom driver behind, so one case silently tested nothing).

**c5 attempt 4 passes CPR6** -- `select-path delay cells = 0`, cone 9 gates
naming the CTS buffers and ICGs the old derivation never saw, name census 1
reported -- **and closes SETUP at +0.078 ns, 0 violating of 37,075** at the
coupled-SI Quantus views. **Hold is -0.017 ns / 5 violating** (from -0.022 / 29),
and the run stops at `FATAL (WQ26b)` because ECO pass 2 inserted nothing.

**Y2-G is settled by that number.** Against c4's -0.765 ns / TNS -105.362 / 270,
TNS falls by **595x**, all 253 false clock-gating checks are gone, and WQ26c's
classifier reports 5 ordinary endpoints and zero clock-gating ones. **Four of the
five are physically unreachable, not mis-constrained**: `hart4/mtip_in`,
`hart4/sh_resv_valid`, `hart3/sh_rdata[28]`, `hart3/sh_rdata[26]` all sit at
y 450.74 -- the abutted tile edge of the flat O10 arrangement -- inside a macro
with no free row site within the finder's 60 um reach. The quad floorplan had a
corridor to relocate into; this one does not. The levers are `PENTA_HOLDREP_MAX`,
the ECO pass count and that 60 um radius, none of which was touched because the
brief authorised exactly one attempt.

**Still unstreamed (Y4-B)**, so DRC / antenna / LVS / ingest / promote / the
headless proof and the five-scope P&R SDF leg are unrun and `castalia_B_core`
holds `c3`. Routed database at `dbs/MCU_castalia_penta_pt_core.c5.holdfail.innovus.dat`.
**One new class recorded for the next attempt**: WQ27 signoff `verifyGeometry`
reads SameNet 151 real / Wiring 1 / Antenna 1 / Short 10 / Overlap 0 against
wq22e's 0 / 3 / 0 / 0.

## 4.19 Y5, 2026-09-17: the c5 geometry class closed at source, and core cut `c6` closes SETUP AND HOLD

**`c6` is the first topology-B core cut to close both sides of timing**: setup
WNS **+0.066 ns / 0 violating of 37,075**, hold WNS **+0.001 ns / 0 violating**,
TNS 0.000, on one hold-ECO pass. `castalia_B_core` now holds `c6` (1970 x 1690,
289,369 instances, proved in a fresh headless Virtuoso session). It is **NOT
signed off**: one real LVS short class remains (Y5-A).

### The c5 verifyGeometry class: 163 markers, four mechanisms, and the seam is innocent

Diagnosed from c5's own reports, not re-measured. **No marker names two tiles**:
the abutment at x = 985 is clean in both rows, so no inter-tile gap knob was
needed or added.

| class | n | where | fix |
|---|---:|---|---|
| SameNet spacing, band macro vs tile row | **139** | the line **y = 451**, gaps 1.00-1.44 um against a 1.5 um wide-metal minimum | `fp::band_plan -tile_gap`, knob `PENTA_CORE_TILE_GAP` = 2.0 with a 1.5 um floor gate. **Zero die cost in both axes** |
| SameNet spacing, M7 mesh vs tile obstruction | **12** | x 515.8-516.5 / 815.8-816.5, west tiles only, 0.7 um | the mesh phase pinned to the tile's own M7 riser lattice (VDD 51 + 50k, read from the abstract), i.e. 1.0 not 1.8 |
| SHORT, M7 | **8** | the WQ17 extension ribs, drawn through the west tiles' notch obstruction | `wq17_rib_blocked`: the census window and the drawing window are separate; a rib over a macro is refused and counted |
| bias_bp M6 / MINCUT / Antenna | 2 / 1 / 1 | post-route | see Y5-A and waiver W-Y5-1 |

**Near-alignment was the trap.** The west tile column's riser lattice is 0.8 um
from the mesh -- close enough that `-extend_to_closest_target` pulls the stripe
into the tile, not far enough to clear the tile's own comb. The east column is
35 um out (985 mod 50) and was clean throughout. Pinning the phase costs the ROM
class nothing: with the phase fixed the ROM's x is the lever (`PENTA_CORE_ROM_DX`
8.0 -> 7.2), 2 hazards against the same budget of 2, and the gate now prints the
ROM-shift sweep so the next value is read rather than guessed.

**Proved before the cut.** A 52-second floorplan-only probe took the
blockage-excluded `verifyGeometry` from **SameNet 151 / Short 8** to **0 / 0**.

### Hold: the launch end of the path, not a bigger reach

The four y = 450.74 endpoints have the band occupied edge to edge above them
(five RAM macros plus halos, y[448,839]); the nearest free row site is ~390 um
away, so X3's 60 um refusal was correct. `ecoAddRepeater -term` is terminal
scoped, so the buffer may sit anywhere on the path: the policy is now
`wq26c_choose_pt` returning `{x y how}` with `how` in {pin, near, launch}, and the
launch point goes through the same site finder (never the driver's raw
coordinate). On `c6` it placed **19 of 19 endpoints, 0 skipped, 6 at the launch
end** 391-532 um away, all tile boundary pins. Unit-tested without Innovus
(`tcl/wq26c_site_test.tcl`, 23 checks on c5's measured placement).

**A third defect in the same classifier regex**, found on c6 attempt 2: a
`VIOLATED Removal Check` on an async reset pin does not match `Hold Check` either,
so a 6 ps miss on `i2c0/I2CSC_reg/R` stopped a cut without ever being named. A
removal check IS fixable where a clock-gating hold check is not -- its endpoint is
the reset pin and the reset net is the data path -- so it is now classified,
counted and returned. Tested against c6's real signoff hold report
(`tcl/wq26c_holdparse_test.tcl`, 6 checks).

### c6's numbers

| | `c4` | `c5` | **`c6`** |
|---|---:|---:|---:|
| setup WNS / violating | +0.074 / 0 | +0.078 / 0 | **+0.066 / 0 of 37,075** |
| hold WNS / violating | -0.765 / 270 | -0.017 / 5 | **+0.001 / 0** |
| WQ27 SameNet real / Short / Wiring / Antenna | -- | 151 / 10 / 1 / 1 | **0 / 0 / 2 / 0** |
| dangling / process antenna | -- | -- | **0 / 0** |
| density | 51.005 % | 50.585 % | **50.541 %** |
| blockdrc real (density/dummy) | -- | -- | **23 (57)**, c3: 62 (65) |
| ant25 | -- | -- | **2 (12) MIM_SWITCH.WARN.1** |

`M7.S.2` and `M7.S.2.1`, c3's dominant real DRC pair at 11 each, are **gone** --
the mesh-phase change is what removed them. `VIA4.R.4:M5` goes 1 -> 2, which is
the measured price of waiver W-Y5-1 and was named as its falsifier in advance.
**X3-A is closed**: the AVDD/AVSS LVS class is gone.

### The five-scope P&R SDF leg runs, 14/14 at both views

Z5 open item 4 and Y4-B are closed. Harness
`xcelium/riscv_test/genus_pt_y5_pnr_20260917`: the core cut's `c6.xsim.v` plus the
tile's `hart_tile_pt.xsim.v`, five scopes (the core SDF over `:dut`, each tile's
over `:dut:hart1..4`), `MTM_CONTROL` following the view.

| leg | result |
|---|---|
| `setup_analysis_view` (ss 0.9 V 125 C, MAXIMUM) | **14/14** |
| `hold_analysis_view` (ff 1.1 V -40 C, MINIMUM) | **14/14** |

Every per-hart flag is Z5's and Y4's, `shpwr` 1:t 2:f 3:f 4:t included.
`*W,SDFNET` in simulation is 0 at both views; `Timing violation` totals 803 at
setup and 880,351 at hold, the latter within 1.1 % of the 889,778 both waves
measured on the pre-layout genus SDF.

**A module-name collision stopped all 14 rows first.** `saveNetlist` writes the
RTL's own ICG wrapper modules into both netlists and each flow numbers them
independently -- `ClkGate_1` is 3 ports in the tile and 4 in the core, because
CCOpt cloned an output pin -- so `xmelab` bound the core's `i3c0/cg_clk_baud` to
the TILE definition. `gen_gate_tile_v.py` (new) renames the colliding modules in a
harness-local copy of the tile netlist, measures the collision set rather than
assuming it (exactly `{ClkGate, ClkGate_1}` of 110 against 1352), and FATALs if
any survives. The tile SDF is unaffected.

**The unannotated list is the shape of a five-scope annotation**: 436 `SDFNSB` per
row are the core SDF's entries at the tile MACRO boundary, dropped because
`hart_tile_pt.xsim.v` is a structural netlist with no specify block; 157
`SDFGENNF` are the behavioural leaves (`irq_gf0..3`, `dco0/1`, `por`); 500
`SDFNET` are the `afe0`/`afe1` `fifo_reg` `RECREM` class the genus leg also has.

### Parked

| # | item | what it needs |
|---|---|---|
| **Y5-A** | **THE BLOCKER. `bias_bp` and `afe_ctl_1<16>` are shorted to VSS at hart1's pin band.** The tile's four M6 bias pins sit at tile-local x = 880 + 12k and its own M7 PG riser columns at x = 51/60 + 50k: `bp` at 903.9 is INSIDE the VDD column [901,906]. The tile alone is LVS-clean; the short exists only in the assembled core. c5 saw the same collision as a verifyGeometry SHORT at hart3. | Tile-side: move the bias pins off the PG lattice (one re-harden, Y1's call). Or core-side: a PG-only keep-out over the bias escape corridor. `afe_ctl_1<16>` is presumed the same mechanism -- one line of evidence, not a traced path. |
| **Y5-B** | Waiver class **W-Y5-1**, two same-net PG `MINCUT` results (1 cut of 2) on VIA4 arrays clipped by `shbank2`'s and `ram0`'s edges. Shape- and database-keyed, capped by `PENTA_CORE_WQ27_MINCUT_MAX`. | Calibre is the verdict and read `VIA4.R.4:M5` = 2 against c3's 1. Close it with a PG-only keep-out band along macro vertical edges if it ever matters. |
| **Y5-C** | **Every fix is in the CORE block or in its frozen source; the `_pt` CHIP flow has none of them.** Its live file has drifted 646 lines from the frozen copy, and adopting that drift is a `W14_REBASE` decision. | One rebase plus a chip cut, deliberately. |
| **Y5-D** | The CPR6 cone ceiling was a literal (12) calibrated on c5's 9 and refused c6's 14 with both mux gates present. Re-keyed to the predicate it stood for (**every disabled mux gate must be IN the cone**) with the ceiling kept as a knob at 24. | Nothing; recorded because it changed a D19 gate's arithmetic, not its subject. |

## 4.20 Y6, 2026-09-17: Y5-A closed at the tile pins; the band-facing pins are off the PG riser lattice

**Y5-A was never two pins.** The tile assigns its band-facing pins on one lattice
and its own M7 PG riser columns on another, and nothing made them avoid each
other: digital at 4.0 + 5.006k, bias at 880 + 12k, risers at VDD 51 + 50k and
VSS 60 + 50k, 5 um wide and 140 um long. Measured on the `y1f` abstract,
**120 of the 348 band-facing pins were inside the required clearance of a column
and 70 of them INSIDE one**. `bp` at 903.9 sat inside the VDD column [901,906],
`bpc` at 915.9 against the VSS column [910,915], and **`afe_ctl[16]` at 714.7
inside the VSS column [710,715]** -- which is the `afe_ctl_1<16>` of c6's shorts
file, so Y5's presumption is now a traced path.

The tile alone stays clean because a pin is a label and nothing inside the tile
drives both nets. The short exists only assembled, where the core welds its M7
mesh onto the riser pad -- Y5 pinned the mesh phase to that lattice deliberately,
and that is right -- and routes to the pin at the same x.

### The clearance, from the tech LEF

`TILE_PT_PG_KEEPOUT` = **1.57 um** = M7 wide-metal spacing **1.50**
(`tsmc_cln65_a10_6X1Z_tech.lef`, M7 `SPACINGTABLE`, WIDTH 4.50 /
PARALLELRUNLENGTH 4.50 -- the riser is 5 x 140 um, so that is the row and the
column that apply) + VIA6 `PREFERENCLOSURE` **0.07**, the enclosure the CORE's
landing via needs. `TILE_PT_PG_KEEPOUT_MIN` = 1.5 is a floor the flow FATALs
below: a value under the M7 spacing cannot be satisfied by any router on the
other side of the boundary, so it is not a tuning knob.

`TILE_PT_PG_BRIDGE_GUARD` = **2.0 um** covers the one class of M7 PG shape that
is not on the lattice: PG4's pad-union bridges, which reach at most
1.6 + 0.16 = 1.76 um past a VDD stripe (the `y1f` abstract carries three at this
edge, widening the columns at 451 / 651 / 751 by 1.15 / 1.65 / 1.15). It is a
placement allowance, never the gate. And the placement is solved at
keep-out + 0.1, because `editPin` snaps to the 0.2 um M4/M6 track and a pin left
on the boundary could be snapped back across the line the gate measures.

### What moved

| | |
|---|---|
| pins moved | **138 of 348** -- 134 digital (max **7.894 um**, mean 5.23) + the four bias pins (9.8 / 13.8 / 17.8 / 21.8 um west) |
| pin order per layer, layer assignment, pin names | **unchanged** |
| minimum pin-to-pin spacing | 0.600 um |
| outline, notch, ram0, `anatop_ch` placement | **unchanged** |
| analog die-edge ports (607.5 + 25k), PG pad rows, ring, OBS | **unchanged** |
| `anatop_ch.lef` | **unchanged**, so `signoff_mp/anatop_ch_bbox` was not rebuilt and Y1-D is untouched |

The bias group compresses as well as moves, and the arithmetic forces it: four
2 um pins at a 12 um pitch span 36 um, and the widest riser-free window on this
edge is **28.86 um**, so no placement of the group at pitch 12 exists.
`870.1 + 8k` centres it in x[867.57,896.43] with 2.5 / 2.3 um of margin and
leaves 6 um of clear metal between pins, against the ~5 the 1.0/1.0 shielded NDR
and its VSS shield need.

### Gate T-G2c, in two halves

Part 1 checks the ASSIGNMENT against the derived lattice before a stripe is
drawn. Part 2 re-reads the finished database after PG4's bridge pass and
measures the PLACED coordinates against the M7 PG geometry that actually exists,
at the **bare** keep-out, so a guard that turned out to be too small reads as a
measurement rather than as a silent pass. Its inclusion test is "overlaps a
derived column grown by the guard", which is the definition of a riser column
rather than a proxy for it -- an x-band exclusion was tried first and silently
dropped the last two columns of the 38.

`tcl/pin_pg_dodge.tcl` holds the arithmetic and `tcl/pin_pg_dodge_test.tcl`
proves it with no Innovus and no licence, against the measured columns of an
emitted LEF and a worst-case track snap. It runs on either abstract and says
which: `out.y1f_ref/` reports *carries the defect* (31 of 31 pass), `out/`
reports *already clear* and that the solver is a fixed point on it (30 of 30).

### Tile cut `y1i` -- the tile of record

| check | `y1f` | **`y1i`** |
|---|---|---|
| pins on the riser lattice | 120 pairs / 70 inside | **0** |
| achieved pin-to-riser clearance | -- | **1.85 um** (1.75 after a worst-case snap) |
| T-G2b | 348 assigned, 0 relocated | **348, 0** |
| T-G2c part 1 / part 2 | -- | **0 / 0** |
| G0 GATE | MINCUT 0, Short real 0, Wiring 0, M1 merges 0, 4 SPACING | **identical** |
| Quantus | 11091 / 11091 | **11094 / 11094** |
| signoff setup / hold WNS | +0.571 / +0.030 | **+0.462 / +0.025 ns**, 0 violating, TNS 0.000 |
| density | 27.152 % | **27.191 %** |
| Calibre `blockdrc` / `ant25` | 15 / 0 | **16 = 15 density/dummy + 1 `DRM.R.1`, 0 real** / **0** |
| Pegasus LVS | MATCH | **MATCH**, shorts 0, sentinels ARMED |
| gate harness, 41 rows | ss 41/41, ff 41/41 | **ss 41/41, ff 41/41** |

Promoted by the `ingest` inside `make signoff`; headless Virtuoso, fresh
session: `hart_tile_pt_signoff / hart_tile_pt / layout bBox=((1.0 0.0)
(984.0 450.0)) instances=41440`. `out/Y1_READY` rewritten.

**Three launches, and the second and third are worth one line each.** `y1g`
carried the same pin fix, and Innovus accepted every new position (`0 relocated
by the tool`) -- then the G0 gate refused it on ONE routed M1 short 340 um from
the nearest moved pin, placement noise from re-rolling the router. F1's targeted
`ecoRoute -fix_drc` could not close it and the report says why: the marker
**moved 1.4 um and stayed** inside a 4.0 x 4.4 um window, which is a window too
small to hold a solution and not a class the router cannot fix. New stage
**F1b** escalates a SHORT naming routed metal -- `-fix_drc` at 8 then 20 um,
then rip the net and re-route it, then `verifyConnectivity` **scoped to the
ripped nets by name** because a rip that trades a short for an open is the worse
defect and this tile's PG carries a standing set of open/dangling lines a
whole-report count would drown in. **No fence is drawn, on purpose**: the G0
driver records a cell-bbox fence answering with Short 23 / Overlap 16, and a
fence over the marker box can sit on the pin the net must reach. `y1h` cost 49
seconds to an exact-equality form of T-G2c part 2's own column count, on a cut
whose real predicate had just passed; re-keyed to the question the count stood
for.

### Core cut `c7`

`c7` is c6's flow with one variable, the `y1i` abstract, plus a generator fix to
a streamOut comment. It closes both sides of timing at the coupled-SI views --
**setup +0.088 ns, hold +0.001 ns, 0 violating of 37,075 on each** -- with two
hold-ECO passes and 18 repeaters, and it has **the cleanest WQ27 census of any
topology-B core cut**: Cells 0 / SameNet 0 / **Wiring 1** / Antenna 0 / Short 0 /
Overlap 0, the one Wiring being waiver W-Y5-1 at (976.125,609.300). CPR6 PASS,
WQ19 0 PG opens, WQ21 M7 S3 0/0 S4 1/2 and M8 0/0, WQ25 99,252 of 99,252 nets
extracted, density 50.801 %. GDS md5 `418c8fd3d7afbf1e23a2b35b0b4168b0`.

`c7` is also the first `_pt` core cut to reach the in-flow `streamOut`, and it
died there: `IMPTCM-48: "#" is not a legal option`. W13's F14 edit had put its
comment INSIDE a backslash-continued command, latent through c2/c3/c6 because
all three were refused at WQ27 and streamed out of flow. Fixed at the generator
(F14 emits no comment, new **F14b** prepends it above the command); regenerated
diff is exactly 8 lines. The cut was recovered with X3's out-of-flow stream
script, the same disposition the earlier three got.

Calibre on the streamed GDS: `blockdrc` 84 = 57 density/dummy + **27 real**
against c6's 80 = 57 + 23, with `M7.S.2`/`M7.S.2.1` still at **0** on both and no
result inside the Y6-A patch; `ant25` **2 (12)** `MIM_SWITCH.WARN.1`, the same
count as every cut since c2.

**Pegasus: the short is gone.** Devices 7,967,112 : 7,967,112 with 0 unmatched
both sides, `anatop_ch` 4 : 4 black box at 75 : 75 pins, the four `AVDD_h`/
`AVSS_h` pairs clean, pins 0 : 0, sentinels ARMED, and **an EMPTY shorts file**.
`bias_bp` and `afe_ctl_1<16>` are no longer shorted to VSS: **Y5-A is closed**.
The verdict is still MISMATCH, on 22 unmatched schematic nets that are the
`VNW`/`VPW` bulk nets of 11 Innovus optimisation buffers in hart 0's main ALU
(**Y6-A**). That class is not new -- c6 carried it at one cell and recorded it as
incidental beside the short -- and it is not a short, not a device mismatch and
not a pin mismatch. Every std cell in the kit declares those two pins, no flow in
this repo connects them (topology A's MATCHing netlist included), and `lvs.rep`
carries a standing SCONNECT stamping conflict (5,863 rejected nets on c7, 5,904
on c6) while both physical well checks are unchanged since c2
(`floating.nxwell_float` 38 (8300), `LVS_SOFTCHK nxwell` 1 (4)). The negative
control discriminates: one deleted `AOI222X1MA10TH` moved devices to
7,967,112 : 7,967,100 with 12 : 0 unmatched while the class stayed at exactly 22.

`c7` is therefore **promoted and NOT signed off**, with Y6-A as the first item of
the next wave.

## 4.21 Y7, 2026-09-17: Y6-A was the LVS netlist, not the wells. Core cut `c7` is LVS MATCH

**Y6-A is closed without touching the silicon.** Two Pegasus runs, no Innovus
run, no re-cut, no ECO: the GDS of record is byte-identical to the one Y6
streamed (md5 `418c8fd3d7afbf1e23a2b35b0b4168b0`).

**The mechanism is a line shape.** `signoff_mp/lvs.sh` binds `VNW=VDD VPW=VSS`
on std-cell instance lines -- the kit's `.SUBCKT`s declare those bulk ports and
no P&R flow writes them -- with two `sed` rules keyed on the two shapes v2cdl was
observed to emit. **v2cdl wraps at column 80 and there is a third**: when the
instance NAME plus the cell name fill the line, `$PINS` itself moves to the
continuation. Census of c7's own CDL: 106,140 shape 1 + 147 shape 2 + **11 shape
3** = 106,298 A10TH instances, 106,287 bound. 11 x 2 = **22**, the entire
residual. The 2026-08-26 note claiming that shape does not occur was a census of
the cpr8 CHIP netlist; the shape depends on the instance names a given
optimisation run creates.

**What it was not, measured from the cut's own database.** The layout side of all
44 devices already reads `B: VDD` / `B: VSS` -- it is the schematic that carries
a net with no counterpart. Tap coverage in the patch is **12.000 um on every
4 um row** (the `addWellTap -cellInterval 24 -checkerBoard` lattice) with the 11
cells **0.375 to 5.045 um** from a tap in their own row, against a kit rule of
`LUP.6 <= 30 um`, which c7's `blockdrc` computes with **0 results**. The SCONNECT
"stamping conflict" is an extraction note from a pegasus-internal cell
(`MASCO__P13`) that topology A's **MATCHing** chip run carries too, and its
`Rejected Nets: 5863` is **one net index, not 5,863 nets**. And all **38**
`floating.nxwell_float` results -- the only non-zero RULECHECK in the ERC summary
-- are inside the two vendor SRAM compiler macros, in 18 sub-cells of
`sram1p8k_hvt_pg` / `sram1p16k_hvt_pg`, none in a core row; they are counted per
unique master, which is why the number has been exactly 38 since c2.

**The fix, and the gate that must come with it.** `signoff_mp/cdl_bind_wells.py`
joins `+` continuations first, resolves each instance's master and binds only the
well ports that master declares (closing the `FILLBIASPWA10TH` trap on the way);
its census is a FATAL gate, and it is proven a strict superset of the two sed
rules byte-for-byte. Because the bind **asserts** the well connection instead of
comparing it, `signoff_mp/lvs_well_gate.sh` gates the **physical** well checks
against `pvs/<lib>_<cell>.wellbaseline` and `lvs.sh` exits **12** on any increase
even on a MATCH (gate G7). Offline test `lvs_well_gate_test.sh`, **21/21**, no
licence.

**The verdict.** `c7`: **MATCH**, cells 2/0, devices 7,967,112 : 7,967,112 with
0 : 0 unmatched, pins 535 : 535, nets 2,963,441 : 2,963,441, `anatop_ch` 4 : 4
black box at 75 : 75 pins, the four `AVDD_h`/`AVSS_h` pairs matched, shorts file
empty, sentinels ARMED, well gate PASS. Negative control (one `AOI222X1MA10TH`
deleted) gives MISMATCH with **12 : 0 unmatched devices and nothing else moved**,
and the Y6-A class does not reappear.

No promote and no ingest: nothing the OA libraries hold changed, so Y6's headless
proof (1970.13 x 1690.0, 290,551 instances) and the five-scope P&R SDF regression
(14/14 at both views) still stand. The `c7` README, `castalia_B_core/PROMOTED.txt`
and `RUNBOOK_CORE.md` now say MATCH.

**What is left on this block is DRC, not LVS**: 27 real `blockdrc` results, 57
density/dummy deferred under O3, and a device-free `anatop_ch` black box. Parked
in Y7's report: the other four signoff blocks have not been re-run against the
new bind (the census gate makes a silent regression impossible, but no Pegasus
run confirms it), and a MATCH on this block no longer measures well bias -- the
physical gate is the substitute and a deleted baseline file silently disarms it.

## 4.22 Y9, 2026-09-17: QFN-176 package model and ball map close D20

Owner decision D20: package = QFN-176 for the 2280 x 2000 um die with Y3's ring
(185 ring cells, 171 signal/power pads). LQFP-100 could not bond it (Y3-B: the
essential set alone is 99 of its 100 fingers and the per-edge caps bind at
25/25/25/25). Every latch-up anchor and every analog pad had to be bonded, not
just the 99-pad essential set.

**Package model.** `castalia-qfn176-pt2mm` (new private overlay model,
`qfn176_pt2mm.py`): 176 pins, **non-uniform per side** (W25/S56/E40/N55) --
no square 44-per-side catalog QFN-176 fits this ring's asymmetric demand, and no
vendor drawing is on disk, so the body (23.0 x 23.0 mm, 0.4 mm pitch) is a stated
assumption sized to the worst-case bond-wire fan-out angle rather than to a round
number. The angle is computed at every build, not asserted: N and S land at
43.7-44.8 deg against the assumed 45 deg assembler ceiling (correct by
construction, under 1.3 deg of margin) while E and W have real margin (35.4 and
24.5 deg). Both the body size and the resulting near-zero N/S margin are parked
for the owner as a packaging/procurement item -- the fit itself is real
engineering (the geometry forces it), sourcing the leadframe is not decided here.

**Ball map.** Every one of the ring's 171 real pads bonds to one package pin (98
analog including all 9 `PVSS2A_G` latch-up anchors, 73 digital), 5 spare pins
NC. Pin numbers follow the die row's own physical order per side (a pure pitch
change, 25 um to 0.4 mm, no reordering), so every analog island stays a
contiguous run of balls, per-tile AVDD/AVSS are independent 5-pad rails that
never share a ball across channels, and the bias island's force/sense pins land
on the east side. Latch-up anchors bond to numbered peripheral pins (a 12-pin
"Digital Core" VSS rail shared with the 3 core-ground pads, matching Y3's own
C-G10 measurement), not to an exposed thermal pad -- `Package.py` gained an
optional `ThermalPad` field (default None, backward-compatible) to make that a
recorded decision rather than an omission.

**The ring moved mid-wave.** `config/padring_pt2mm.json` was regenerated
(2026-09-17 19:52, presumably by Y8's chip-flow work) while this wave was
running: the two corner-wrap-split VDDPST/VSSPST pairs merged onto one package
side each, moving per-side counts from W24/S55/E38/N54 to W24/S54/E40/N53 (total
still 171) -- a real fix, since a split PST pair is exactly the S1/pt11 hazard
Y3's own C-G3 gate exists to catch. The ball-map builder reads the ring at every
generation and raises loudly if an instance appears or disappears without a
matching edit to its frozen ball table, so the map was re-derived against the
current shape rather than silently drifting.

**Gates, all pass, none weakened.** Public: `package_die_row_test.py` 20/20 (4
new `AsymmetricSidesTest` cases prove the 225fadcd ball-map gate at real-shape
skew); the default-chip and `castalia_b` generation/determinism gates
unaffected. Private (`private/analog/platform/common`): `padring_pt2mm_test`
(Y3's, untouched) 15/15; new `qfn176_pt2mm_ballmap_test` 10/10 and
the 2 mm topology-B AFE overlay generation test pass; `overlay_generation_determinism_test`
unaffected. `make generate` on the 2 mm topology-B AFE overlay configuration ran end to
end; verified from the artefact that `PadRing.json` carries the QFN-176 shape
and `chip_top_padring.tcl` emits exactly 171 `lappend` + 5 NC lines with every
analog island contiguous.

Parked: package sourcing (no vendor match for the assumed body); the N/S
wire-angle margin (re-check against a real assembler's rules once a vendor is
chosen); the east side now has zero spare pins; the 24 reserved analog debug
pads plus the bias island's stay bonded-but-undriven pending Y1 (Y3-A); no
analog TRM chapter for the 2 mm topology-B configuration (cosmetic); the note 6(i) 1-ohm
bonded-anchor check is still an extracted number pending Calibre/Quantus,
unaffected by the package choice. Report `reports/Y9_qfn176_ballmap.md`.

## 4.23 Y8, 2026-09-17: the `_pt` CHIP flow rebased onto the CORE flow of record; the 2 mm die floorplans

**Y5-C is closed by inverting the direction of derivation.** `surgery.py` derives
the CORE flow from a FROZEN copy of the CHIP flow, so every geometry fix since
2026-09-16 -- Y2's derived floorplan, Y4's dead clocks, Y5's mesh phase and
WQ17/WQ26c/WQ27 work, Y6's tile pins -- landed in the core and none of it ever
reached the chip. On entry the live chip driver had drifted **854 lines** from
that frozen copy (Y5 recorded 646), still carried the 660 x 880 quad floorplan on
a 2690 um square die, and could not have run at all: Y3's frame replacement had
deleted `CORE_SPACING`, `CORE_WIDTH`, `CORE_HEIGHT` and the five `POWER_*`
constants its own `floorPlan` call reads eleven lines later, and its
`tcl/wq5_rom_comb.tcl` was one ARGUMENT older than the call the geometry makes.

`innovus/common/MCU_castalia_penta_pt/gen_chip_geometry.py` (NEW) now GENERATES
the chip driver from the CORE driver (cut c7) plus
`tcl/MCU_castalia_penta_pt.chipbase.tcl`, the chip-only half. All **103**
differences between the two flows are classified exactly once -- 46 CORE
(geometry and gate fixes), 52 CHIP (pad ring, wrapper, the gates a core-only
block relaxes), 5 FRAME/SKIP -- keyed on the CONTENT of both sides, so a change
neither author has seen stops the generator rather than being silently taken or
dropped. `--check` refuses a cut on drift; six shared tcl/py files carry an md5
equality gate across the two homes, as `cpr6_gate_lib.tcl` has since D19. The
coordinate systems coincide (core box `(0,0)-(1970,1690)` in both; the ring
extends into negative coordinates), which is what makes the transplant exact;
the only rename is the `mcu0/` instance prefix, and `fp::tile_places` grew an
optional prefix argument rather than the chip keeping a second list of the same
four placements.

**The floorplan probe reproduces c7 to the digit** -- core 1970.0 x 1690.0,
hart1 (0,1239) R0 / hart2 (985,1239) R0 / hart3 (0,1) MX / hart4 (985,1) MX,
band inset 32.7 um with the same 8-step scan, mesh phase 1.0 um on the tile
riser lattice, stripe band y[343.8,1345.5], SRAM row x[1.00,1631.80] gap 8.14,
hart0 flank x[1639.8,1968.3] -- with the ring as the only delta: die
**2280.0 x 2000.0 um**, band 155.0/edge, and a new gate proving the floorplan
solver and the ring plan agree on the core box before anything is placed.
128 offline checks (80 `core_floorplan_test.tcl`, 32 a new `penta_pt_ring_test.tcl`,
16 the ring JSON test) run first, with no Innovus and no licence.

**Y3-1 closed.** Parts 3b / C12 / C14 / C17 and the two WQ27 waiver classes read
the net from the padlist's new net column; `PENTA_PT_ANA5_OK` is retired. The one
design change is C12 and it is stated as one: the closed M7/M8 ring that JOINED
the five islands becomes **five per-island rails**, because a ring that joins
them shorts AVDD_0..3 and AVDD_B in metal while the netlist says five nets. Drops
rise 10 -> 44 (every analog supply pad, not just the first pair of each island),
C17's `-excludePin` list 10 -> all 44 analog supply pad terminals, and new gate
**C-G11** proves five domains with ten distinct nets before part 3b runs. One
binding was missing and is not cosmetic: `PVDD3A_G`'s `TAVDD` bond plate was
floating, and `editPowerVia` refuses to land a via on a floating terminal.

**Y3-2 closed.** `addIoFiller -area` (IMPTCM-48 on 20.12) is replaced by a
measured gap census, a coordinate placer and a re-measure with a FATAL on any
residual; the decomposition is unit-tested offline because a gap-free ring proves
nothing about it.

**Three defects the ring carried, all found by running it.** (a) The four analog
sections were **177.5 um west of the electrodes**: Y3 built them on the O10 STUB
tile and y1i's notch is x[355,985] flush east with its six M6 ports at tile-local
607.5 + 25k. The section origin is PROBED from the abstract now
(`SECTION_DX = 370.0`, the `anatop_ch` macro's own x0) and gate C-G9 checks the
ELECTRODES -- 24 pad-to-port alignments, worst **0.000 um** -- instead of the
notch. `PAD_TRSTN` joins the other four TAP pins as a consequence; every pad
keeps its name and its cell. (b) `BIASG_X/Y` was the square die's north-centre
corridor, which a flat floorplan does not have: the position is SOLVED from the
band, lands at (1271.7, 878.4), and its supply pads sit on a VERTICAL row that
every branch of part 3b assumed away. (c) **Y8-2**: the core supply pads had
nothing to strap to on the west row -- the band's west edge is macro from
x = 1.00 and the tiles are flush elsewhere -- so all three pairs move to the east
row and WQ22 scores **51 of 51** (pt11 scored 50, wq21e 7).

### Y8 phase 2, 2026-09-22: D21 applied, the shorts classified, and the die grows in X

**D21.** The analog section is trimmed 24 -> **14 slots** -- 2 AVDD, 2 AVSS,
CE/WE/RE/ATP contiguous over the tile's own die-edge ports, 2 reserved debug,
2 `PVSS2A_G` latch-up anchors, 2 brackets -- the bias island 12 -> 11, and the
ring 171 -> **130 pads**. Bond fingers per edge: **north 33, south 34, west 20,
east 43**, all under the LQFP-176 cap of 44, 130 of 176 in total; the cap is a
checked invariant in the ring plan and the JSON test with a negative control.
Y3's gates all pass on the trimmed ring: C-G9 24/24 alignments at 0.000 um, C3
10 brackets, C4 130 pads, C5 0 gaps, C-G8 worst run 5 cells (better than the
24-slot form), C-G3 0 unsupplied arcs, **verifyGeometry all-zero**.

**Chip cut `chip_2mm_a` closed timing and failed the geometry gate**: signoff
setup **+0.092 ns** and hold **0.000 ns**, both 0 violating, density 63.2 %,
CPR6 passing, WQ22 51/51 -- and `FATAL (WQ27): Short 2040, Wiring 29, SameNet
1159 (1044 waived, 115 real)`. Classified from the saved report, 3227 markers
bucketed by layer, location and object pair:

- **1492 shorts are M7 signal-to-signal in the 30 um of pad band outside the
  core box**, and **1487 of them at y < 500**, on 141 nets of which 140 are
  GPIO/TAP pad nets; **~300 more are the same router inside the tile abstracts'
  obstructions**. One cause: with the tiles flush to the west and east core
  edges the only boundary a pad can enter on is the control band's 788 um, and
  a `PDUW16SDGZ_G` has four core-side nets, so each row's 16 GPIO bits are 64
  nets through 30 um of single-layer M7. **Fix: inset the tiles 100 um** -- O10
  fixes Y and leaves X free, the tiles still ABUT, and 100 is a whole mesh pitch
  so the tile M7 riser lattice keeps its phase (measured unchanged at 1.0 um).
  **Die 2280 x 2000 -> 2480 x 2000, core 2170 x 1690, area 4.56 -> 4.96 mm2.**
- **56 PG shorts** were Y8's own bias strap running its long leg horizontally on
  M7 across the core's vertical M7 mesh. The leg is M8 now with an M7 patch at
  the bond plate, and a new clearance gate -- which immediately caught the
  island centred 1.2 um from an M8 stripe and moved it 10 um.
- **108 are tie wires under analog pad cells**, the pin-access class the flow
  already waives for vias; waiver (c) widens to wires and keeps its
  connectivity test.
- **WQ23 part 4 and WQ24** were re-keyed off literals belonging to another
  floorplan: the first killed a cut for adding FEWER taps than c7 did on a
  smaller base (ratio, not count), the second for welding 0 of **0 candidates**.

**The owner's viewing stream.** `castalia_B` holds `chip_2mm_a` at
**2280 x 2000 um with 249,668 top-level instances**, streamed by a script that
refuses to run without `PENTA_VIEWING_STREAM=1`, writes a distinctly named file
no signoff target reads, and labels itself NOT SIGNED OFF at both ends.

### Y8 phase 3, 2026-09-22: the channel is proved; the bound is spent at WQ26c

Attempt 4 (`chip_2mm_b`, 6 h 33 m) on the widened core cut the geometry class
the channel was aimed at by 83 %: **Short 2040 -> 356, Wiring 29 -> 2, SameNet
real 115 -> 86**, and **every one of the 1492 pad-band M7 signal-to-signal
shorts is gone**, as are the 56 PG shorts. Both re-keyed gates pass on their
own terms (WQ23 part 4 at 14443 taps added against a 60000 cap; WQ24 reporting
0 candidates). It stopped at `FATAL (WQ26c): legalisation moved 3785 instances
after inserting 19 repeaters` -- a gate that is right and must not be widened.
The cause is the relocation, not the insertion: Y5's launch-end fallback
ignores the 60 um search reach, moved one repeater **391.3 um** and 14 of 19
into the band, so **3 ps of hold debt across five paths bought a 3785-instance
compaction** (Y8-6). The residual 356 shorts are ~250 of the adjudicated
pin-access class against a TILE, which waiver (c)'s connectivity test already
expresses (Y8-7). Parked at the bound with the classification in
`reports/Y8_chip_2mm.md`; signoff, promote and the SDF regression wait on a cut
that clears WQ26c and WQ27.

### Y10, 2026-09-23: timing closes on the 2 mm chip; the hold ECO's route is the blocker

`chip_2mm_d` (2480 x 2000 die, tiles inset 100 um, 8 h 33 m) **closes timing at
the coupled-SI signoff views: setup +0.030 ns / 0 violating, hold 0.000 ns /
0 violating of 36927 paths.** CPR6 (D19), WQ19, WQ21 and WQ27b all pass; WQ26c
passes with **legalisation moving 0 instances**, the gate that stopped Y8.
It FATALs at WQ27, and the cause is one missing line rather than a floorplan:

    verifyGeometry postfiller (pre-ECO)  Short 359 , Wiring  2 , SameNet real 14
                                         M7 signal-over-tile markers:   0
    verifyGeometry signoff   (post-ECO)  Short 451 , Wiring 22 , SameNet real 49
                                         M7 signal-over-tile markers: 178

`deleteAllRouteBlks` removes the die-frame M7/M8 block the floorplan creates to
"reserve M7/M8 for power during signal routing", and nothing restores it, so the
WQ26 hold ECO routes signal on M7 across the tile abstracts. None of it is
waivable: the pin-access waiver turns on the net terminating on the instance it
is reported against, and these are routes crossing a macro they have nothing to
do with. **`chip_2mm_e` proved that restoring the block so that it survives into
verification is the wrong form** (Short 359 -> 3136, Overlap 0 -> 1448, all
`Pin of Cell & Routing Blockage` -- the transient class the flow already
documents); the correct form is a create/delete pair around the ECO loop, and
the three-attempt bound is spent.

**The edge channel is 100 um because 100 um routed.** The demand and the supply
are both countable -- worst crossing 80 core-side pad nets against 750 free
vertical tracks in a 50 um channel, 9.4x, 5.33 um needed on tracks alone -- and
the count is not what binds. `chip_2mm_c` took 50 um to a finished route and the
class returned on M7 inside the tiles, 164 markers where `chip_2mm_b` at 100 um
scored none. Die 2480 x 2000 = 4.96 mm2, +8.8 % over the flush 2280 x 2000 that
could not route; die Y untouched, O10 holds.

**Four defects fixed at source, all in the analog ring and all systematic.**
C12's per-island rail axis was inverted (a tphn pad's long axis is NORMAL to its
row, so the aspect test returned the opposite of the row for all five islands,
and AVDD lay on AVSS for 770 um); ANATOP 3b's M8 clearance was gated on the
stripe-SET lattice while a set carries two stripes, and its M7 leg's x was never
compared to anything; 3b's jog row was shared by both polarities; C12's
vertical-row drop crossed the other rail on its own layer. Clearances are
database queries now, not arithmetic. The special-wire-to-special-wire short
class went **26 -> 6 -> 0** across the three cuts.

**O-PT7-1's VDD-to-VSS half is closed.** C16d caps the two tie polarities on
disjoint layer sets (LTIEHI M4, LTIELO M2) and widens the net glob to
`*TIE_TOP_*`, which is what makes it bind on 103 nets instead of 18: zero
`LTIEHI`-vs-`LTIELO` shorts on all three cuts, against 1 on pt7, 3 on pt8, 8 on
pt9, 19 on b1 and 3 on `chip_2mm_b`. One `LTIEHI`-vs-`LTIEHI` marker remains
(Y10-5) and capping HI at M5 does not remove it, at a cost of 22 ps of setup.

**Y8-6 is closed at source and was half a misdiagnosis**, which is recorded: the
launch-end fallback was always bounded by the reach from the DRIVER, and the
391-733 um Y8 measured is the length of the path. The bound is explicit and
asserted now (`PENTA_HOLDREP_LAUNCH_REACH`), a point beyond it is refused with a
reason rather than relocated, and the policy has ONE home
(`tcl/wq26c_site_lib.tcl`, md5-gated across both blocks) with an 87-check
offline test built on `chip_2mm_b`'s own 19 endpoints. **Y8-4 is closed**: the
promote gate could not refuse `NOT SIGNED OFF`; it now removes negated verdicts
before testing for a positive one, 26 offline checks. **Y8-5 is deliberately not
taken** -- `PENTA_PT_CUT` moves with a promote, and no cut passed WQ27, so there
is no GDS, no SDF, no Calibre run, no promote and no SDF regression.

### Y11, 2026-10-02: Y10-1 closed and proved; six source fixes; the blocker moves to WQ26c

**Y10-1 is closed at source and proved by a cut.** The die-frame M7/M8 signal
route block is a CREATE/DELETE PAIR around each WQ26 ECO pass -- one file, two
homes, identical md5, md5-gated in `gen_chip_geometry.py`'s `SHARED` list -- and
the delete's residual is READ BACK from the database with a FATAL on non-zero,
because a `deleteRouteBlk` that returns cleanly and removes nothing is exactly
what `chip_2mm_e` was. Offline gate 55/0 with two negative controls; the one that
matters substitutes a delete that removes nothing and asserts the residual
reports 2, not 0. **`chip_2mm_f` carries 0 M7 signal markers before AND after
the hold ECO where `chip_2mm_d` carried 0 -> 237 on the same netlist and the same
gates, and 0 `Routing Blockage` markers at either stage** -- so the pair neither
lets signal onto M7 nor leaves the transient class a persistent block does. The
Short total across the ECO reverses direction, 372 -> 314 against 359 -> 451.

**`chip_2mm_f` closed timing (setup +0.045 ns, hold 0.000 ns, 0 violating) and
FATALed at WQ27 on 234 markers. Re-running the gate's own connectivity test per
marker on the saved database resolved them to four root causes, all fixed at
source** -- 258 signature matches, 59 waived, 199 refused, **0 unresolvable**, so
it was never an escaping defect.

**121 markers were top-level signal lying on a hardened tile's real metal**, and
the cause is a sentence in the ring plan that is false: *"signal pads behind a
tile are fine: the router walks them along the pad band."* The tphn pad cells
obstruct M1-M6 over the full cell, the pad row abuts the core box with no gap,
and the tile abstract obstructs M1-M6 over 100 % of the tile -- so a north or
south signal pad over a tile has **no legal path into the core**. Y10's edge
channel serves west and east pads; the north and south pads were never in its
scope. The five TAP pads and the eight `prt6` bits moved to the free west row
inside the control band: **120 markers -> 0, and 83 ps of setup.**

**72 markers were one C17 scope bug, and it is electrical before it is
geometric.** `PVDD3A_G` declares `AVDD` (the core-side port) and `TAVDD` (the
pad frame's analog supply BUS, carried by abutment like `VDDPST`); C17 excluded
the first and not the second, so `addTieHiLo` tied **all 22 bus terminals to
1.0 V digital tie cells in the core**, and those eleven nets then ran from the
core to the analog sections, which sit over the tiles. One line fixes it,
derived from the same table row. `chip_2mm_g`: 40 terminals excluded, **0
TIE_TOP loads on any of them**, TIE_TOP nets 99 -> 70.

**22 markers were waiver (c) testing the wrong thing**: `AVDD_0` has two
instTerms, both pads, and none on the tile, because ANATOP part 3 DRAWS the
strap and never creates a terminal -- so the analog arm could never be waived by
construction. It is keyed on the domain table now, with gate C-G2 as the
connection's own evidence. **The rest were the `SPACING:`/`MINCUT:`/`Regular`
halves of classes adjudicated only as `SHORT:`/`Special`**: verifyGeometry's
categories map one-to-one onto the marker kinds, and every waiver was keyed on
one kind. Nine classifier changes, all POST_EDITS so the core flow of record is
untouched -- and the drift gate proved that discipline by refusing a launch with
"105 differences against a table of 104" when the ring-depth edit went into
shared text.

**The analog ring's last two markers took three floorplan probes and no
argument.** The via window was narrowed and they did not move; the rail was
moved M7 -> M8 and the short RELOCATED with identical bounds; only then was the
cause measurable -- at depth 55 the inner rail's x[2221,2229] overlaps the pads'
own bond plates, which reach 2226.185. M7 is the pads' top layer, which is why
the north/south rails have always been M8 and have never scored this class. The
fix is all three: M8, a via window of the rail's own width, and depths 70/85.

**`chip_2mm_g` (attempt 2 of 2) FATALed at WQ26c, not at WQ27.** Every geometry
fix held -- pre-ECO **Short 314 -> 58**, the 120 pad-crossing markers and the
EB island's two and the MAXWIDTH all to **0**, M7 signal 0 -- and **setup reached
+0.128 ns / 0 violating of 36,927, the best any 2 mm cut has produced.** What
stopped it is Y10-2b: the chip-wide `refinePlace` after the WQ26c insertion
moved 5062 instances, on a cut that relocated 24 of 24 insertion points off a
macro (13 to the launch end), the most any cut has done. The residual geometry
is at the gate's budget; the only unadjudicated class left is four
`TIE_TOP`-vs-`TIE_TOP` shorts that have **moved into the west edge channel**
with the tie cells of the relocated pads, where F19b's track repair has room --
it took one of them in this very cut. **WQ27 is not what stopped this cut.**

**Y10-2b is now implemented in both drivers, identically, STAGED with the gate
as its test**: the legalisation is scoped to the 40 um windows the insertion
itself opened, a refused `-area` form falls back to the chip-wide call with a
WARN, `PENTA_WQ26C_SCOPED_LEGAL=0` restores the old behaviour, and the
displacement gate is left chip-wide and unchanged so a scoped call that misses
something is caught rather than hidden. That is the arrangement Y10 asked for
and declined to take without a measurement; the measurement is five cuts (a, c,
d moved 0; b 3785, e 3854, g 5062).

**Two chip attempts is the bound and it is spent: no GDS, no SDF, no Calibre, no
ingest, no promote, no headless proof and no SDF regression.** `PENTA_PT_CUT`
stays at pt7 for the third wave running and the `chip_2mm_a` `.gds2` symlink
stays, because it is still the file `castalia_B`'s `PROMOTED.txt` names. The
chip SDF regression's harness and its two tools ARE built and staged
(`chip_pt_y11_pnr_20260923`, `gen_gate_sdfcmd_chip.sh`, `rescope_chip_sdf.py`,
the last validated on a real 11.9 MB SDF): a chip cut's top cell is the pad-level
wrapper, which the harness cannot bind as its DUT because `riscv_tb_gate.vhd`
grades every row on `a0`, a port of `MCU` that does not leave the die -- so the
chip SDF is re-scoped onto `mcu0` and the pad-cell delays stay with the
harness's own pad entities, as on the core leg.

### Y12, 2026-10-03: Y10-2b closed and the Y11 diagnosis overturned; the blocker moves to the scoped reroute

**The review came before the cut, and it changed what had to be fixed.** Y11
staged Y10-2b (a scoped `refinePlace -area` per insertion window) against the
reading that `chip_2mm_g`'s "legalisation moved 5062 instances" was a row
compaction along the 40 um filler windows. The probe Y11 asked for is impossible
-- WQ26c FATALs ~300 lines above `saveDesign ... .signoff`, so `chip_2mm_g` has
only `floorplan_pg` and `place` databases -- so the review was done on better
evidence instead: the `refinePlace` call itself in all **nine** WQ26c
invocations across the five 2 mm cuts, read at the call rather than at the gate.

1. **Every "legalisation moved 0" is a DENSITY ABORT.** `chip_2mm_a`, `_c`, `_d`
   and `_f` never legalised their repeaters at all: `**ERROR: (IMPSP-2002):
   Density too high (99.3%), stopping detail placement.` in 0.3 s of CPU. They
   were geometrically clean because the SITE FINDER had already chosen
   verified-free row sites -- four of nine invocations passed the gate while
   doing nothing, and the block header's correlation with launch-end relocations
   is spurious. A gate that passes because the tool declined to run is not a
   gate.
2. **The gate's number was ~96 % FILLER.** The same refinePlace summary reads
   `Instances move: 108 / 119 / 182` where the gate counted 3785 / 3854 / 5062,
   because `dbGet top.insts.pt` includes FILLER and TAPEDGE. A 182-instance
   problem reported as a 5062-instance one.
3. **The real movers are REGION/FENCE violations**, and `chip_2mm_g`'s own
   summary names the constraint: `Max displacement: 1497.00 um
   (mcu0/hart0/tile/FE_OFC1424_pgen_mem_1) ... constraint:Region / Violation at
   original loc: Region/Fence Violation`. The floorplan's soft `createRegion` on
   hart0 is still in force post-route; the containment census measures 66/71/114
   hart0 instances outside the flank on `_d`/`_f`/`_g` and CTS's `checkPlace`
   prints `Region/Fence Violation: 70` and `119`. pt1's worst mover was the same
   instance class at 1146 um, so the "ecoPlace deletes every filler" reading is
   half the story too.

**Four source fixes**, one new shared file `tcl/wq26c_legal_lib.tcl` (md5
`39ecaf7f`, both homes, in `SHARED`): drop the post-route region/fence groups
with a read-back (by TYPE, because the two homes name the region differently);
split the displacement census into REAL and physical-only and name the worst real
mover; **AUDIT every inserted repeater** (outside every macro, no real-cell
overlap, on a row site) -- which replaces "moved 0" as the gate; and read the
IMPSP-2002 refusal as a log annotation, explicitly not as the gate. Y10-2b kept
as the blast-radius bound. Offline gate 70/0 with four negative controls, plus a
harness test of the WHOLE 411-line proc extracted from the generated flow (44/0)
whose arm 3 isolates the mechanism to one variable: the same chip-wide
`refinePlace` with the region dropped first moves 0 real instances instead of
182.

**The four `TIE_TOP`-vs-`TIE_TOP` shorts are closed at source, and the lever is
not the track.** `chip_2mm_g`'s F19b log shows the one it repaired RELOCATED and
split in two, and the other two were `marker box larger than 5.0 um -- skipped`
(60+ um co-linear runs); blockading the only corridor a constant reaching a pad
terminal has would turn a short into an OPEN, so widening F19b was rejected.
The fix is C17's own principle applied to the multiplicity:
`setTieHiLoMode -maxFanout` 2 -> 8 (`PENTA_TIE_MAXFANOUT`), which took the
chip-level constant nets **70 -> 20** (24 LTIEHI -> 7, 46 LTIELO -> 13) and
F19b's postfiller scan to **0 constant pairs, 0 skipped**.

**`chip_2mm_h`, both attempts, FATAL at the SAME NEW step -- WQ26c's scoped
reroute -- with everything above it fixed.** Attempt 1: 24 repeaters, scoped
legalisation **0 real / 0 filler moved**, all 24 audited LEGAL, setup +0.074 ns /
0 violating; attempt 2 (`PENTA_HOLDREP_MAX=14`): 14 repeaters, **13 real moved,
worst 0.8 um**, all 14 audited LEGAL, setup **+0.082 ns / 0 violating**, hold
back to **-0.023 ns / 16 violating / 0 REMOVAL**. **The pre-ECO geometry is the
cleanest any 2 mm cut has produced and every class in it is adjudicated**: Short
54, all one signature (`Special Wire of Net AVDD_*/AVSS_* & Blockage of Cell
<mcu0/hartN | PAD_AV*>`); SameNet 1172 with **0 real**; Wiring 3; Overlap 0; **0
TIE_TOP of any kind**. On that geometry WQ27 had nothing to refuse.

**What stops it is characterised but not closed (Y12-A).** Attempt 1: 48 split
nets, stuck at ~145 violations, **54 open**. Attempt 2: 28 split nets, 68
violations, **14 open -- exactly one per repeater**, and every `timer1` insertion
gone, which kills the congestion reading. `chip_2mm_f` is the only comparison
that holds and it inverts it: stuck at **1611-1625** violations and **ZERO** open
nets, so `-fix_drc` proceeded and that cut reached WQ27. The selected-net
`ecoRoute`, given the whole batch at once and no licence to rip anything to make
room, **abandons nets rather than routing them badly**, independently of the
violation count. **Y12-3 is implemented and STAGED against it**: one `ecoRoute`
per insertion group (`PENTA_WQ26C_ROUTE_PER_INSERTION`, default 1), so the router
sees one repeater's 40 um neighbourhood at a time and a failure names the
endpoint; harness arms 8-10, and the next cut is its test.

**The chip gate probe: the VHDL route is measured impossible and the Verilog
route is built.** `xmelab 20.09-s006` will not resolve a VHDL external name into
a Verilog instance's scope -- a three-arm minimal testcase gives OK inside VHDL
and `*F,INTERR: INTERNAL EXCEPTION` one and two levels into Verilog, and the real
bench answered `*E,CUHPNM Illegal pathname element dut`. `wrappers_tap/
MCU_chip_tap.v` instantiates the pad wrapper and exports `u_chip.mcu0.a0` through
a Verilog-to-Verilog XMR, proved to resolve. The bench gained an `A0_PROBE`
generic (default 0 = the old behaviour) and the 14-row genus regression
reproduces the reference result with it in place (**13 PASS / `shtcm` FAIL at
zero delay**, W4's table row for row and flag for flag) -- after fixing a stale
boot-ROM copy in `genus_d13a_pt` that its own md5 guard had been refusing since
the ROM last changed.

**Parked at the two-attempt bound**: no GDS, no SDF, no Calibre, no Pegasus, no
ingest, no promote, no headless proof and no SDF regression, because every one of
them reads a cut that reaches WQ27. `PENTA_PT_CUT` stays at pt7 and the
`chip_2mm_a` `.gds2` symlink stays in `out/`. The chip SDF regression also has no
input at all -- `out/*.sdf` is empty for every chip cut ever taken. The only
unadjudicated class above WQ27 is `Antenna 46`, new in `chip_2mm_h` (Y12-4).
Report `tapeout_review/reports/Y12_chip_2mm_h.md`.

### Y13, 2026-10-04: `chip_2mm_i` closes, and the blocker moves into the layout

**Y12-3 is proved on a real database before the cut, and a probe found the defect in
Y13's own first draft.** The `chip_2mm_h` place database cannot host WQ26c (the stage
needs a routed design), so the probe ran on the CORE flow of record's `c7.signoff` --
290,551 instances, 30 s to restore, the same WQ26c block. The per-insertion group route
closed its split in 45 s, `verifyConnectivity -type regular` answered `Found no problems
or warnings.`, and `ecoRoute -fix_drc` passed: the exact step both `chip_2mm_h` attempts
died at. It also killed the obvious predicate: **`ecoAddRepeater -term` SPLITS the existing
routing**, so both halves carry wires (2 and 3) the instant the split is made, and
`dbGet <net>.wires` -- this project's route-status idiom everywhere else -- answers "routed"
for a net the router has abandoned. And `ecoDeleteRepeater -inst` works: the split merges
back, one selected-net `ecoRoute` closes the restored net, `-fix_drc` passes.

**`Antenna 46` is adjudicated and the class is not new (Y12-4 closed).** `Antenna` is 0 in
every non-signoff `verifyGeometry` of every cut because only the signoff call passes
`-antenna`; in the signoff report `chip_2mm_f` reads **78**, `_g` 47, `_h` 46 -- so the only
earlier cut to reach WQ27 and stream a GDS already carried 78 of the same signature. All 46
are `Special Wire of Net <PG net>` (0 Regular Wire/Via), 28 of 46 boxes are exactly
degenerate, 29 of 46 coincide with a `dangling Wire` WQ27b already waives, and
`verifyProcessAntenna` reads `No Violations Found`. A power net charges no gate, a zero-area
marker is not an area ratio, a diode has nothing to attach to and a jumper has nothing to
break. **WAIVED as class (f)**, with `tcl/wq27_ant_lib.tcl` classifying every marker on BOTH
tests (structural `Special Wire` and the database's own `isPwrOrGnd`) and three new WQ27 gate
arms: unclassified markers to 0, a blow-up cap, and a summary-vs-parser mismatch FATAL.

**Attempt 1 FATALed on the NEW check, which is how the real mechanism was found.** Setup
+0.121 ns / 0 violating of 36,927 -- the best number any 2 mm cut has produced -- all 24
per-insertion groups routed and **0 of 47 split nets open**, so Y12-3 works. Then
`verifyConnectivity -type regular` found **100 regular nets open, 0 split and 100
neighbours**, and the stage refused instead of handing an open database down. Two lines above:
the scoped `refinePlace -preserveRouting true -area <40 um box>` had moved **61 REAL
instances, worst 2.6 um**, and the old budget (`done + 40` = 64) PASSED it. The 100 opens are
exactly where those movers are -- 56 `timer1`, 19 `system0`, 7 `timer0`, 7 `spi1`, 2 `spi0`
and 9 top level including the clock net `CTS_65` -- and the sixteen hart-boundary band-row
insertions disturbed nothing. `deleteFiller` runs before the insertion, so the rows in the
window have gaps and a detail placement there COMPACTS them.

**Y13b: audit first, pin what you are not placing, and gate the NEIGHBOURS at zero.** The
audit now runs before any `refinePlace`; if every repeater is already on a free row site the
legalisation is SKIPPED entirely, and if one is not, every non-repeater instance in the
windows is `dbSet pStatus fixed` for the duration and restored afterwards. The displacement
gate moves off the real count and onto the NON-REPEATER count, at zero: a moved repeater is
harmless because the stage re-routes its two split nets by construction, and a moved
neighbour is an open net it does not repair.

**`chip_2mm_i` PASSES, and Y13b ran both of its branches inside the one cut.** 2 h 09 m real,
exit 0: **setup WNS +0.042 ns / 0 violating of 36,927, hold WNS 0.000 ns / 0 violating**, and
`WQ27 verification gate PASSED -- unwaived Wiring 0 (3 waived of 3), real SameNet 0 (1173
waived), unwaived Short 0 (54 waived), Overlap 0, unclassified dangling 0 (41 waived),
unclassified antenna 0 (46 waived PG special-wire of 46), process antenna 0`. ECO pass 1 found
**16 of 24 repeaters placed ILLEGALLY by `ecoAddRepeater -loc`** (overlapping tie cells, well
taps, `timer0` flops), pinned **2354** routed neighbours, legalised, restored all 2354 and
moved **20 real / 0 non-repeaters**; passes 2 and 3 each inserted one already-legal repeater
and SKIPPED the legalisation. Every pass reported `every split is CLOSED`. **The first 2 mm
chip cut of either topology to clear WQ26c, the slack gate and the WQ27 gate, and the first
chip cut of any size to write an SDF** (`out/*.sdf` was empty for every earlier one).

**Signoff: chipdrc and ant25 run for the first time on a 2 mm cut, and LVS finds ONE VDD-to-VSS
SHORT.** chipdrc 2366 results classified by cell: 1506 in purchased pad-kit cells (the ESD
family, Myshkin precedent), 110 in the `anatop_biasgen_g` placeholder, **752 at top level** --
82 density/dummy deferred per O3, 234 `PO.R.8`, 377 VIA5, 3 VIA4, 56 metal spacing/area, and
the last 670 are UNADJUDICATED. ant25: **6 real `A.R.6__A.R.8:M3`** plus 2 warnings in a
Cadence mimcap, and Innovus's `verifyProcessAntenna` and NanoRoute's diode ECO both score 0 on
the same database -- the two checks disagree and the foundry deck is the one that counts.
Pegasus: **MISMATCH on exactly one short, `VDD: - VSS:`**, and the 63-polygon path localises it
to the M5/M6/M7 straps inside `x[1462.4,1822.4] y[868.4,1228.4]` -- the window the cut's own
log names as `ANATOP part 3b -- VDD/VSS blockPin sroute`. **Innovus never sees it**: Short 54
are all the adjudicated AVDD/AVSS-vs-blockage class and there is no VDD-vs-VSS marker
anywhere. Everything else in the compare (27,517 : 27,470 unmatched devices, symmetric;
26,250 : 26,236 nets; the ERC population) follows from the merge. Not waivable: fix the sroute
and re-cut. Two collateral scripts had to be fixed first, both naming pt7-era analog pads that
D21 renamed, and both FATALed correctly rather than labelling the wrong conductor.

**Promoted, proved, and Y8-5 closed after five waves.** `castalia_B_chip_2mm_i` ingested with
0 errors and a README whose first line carries the timing, the Innovus verdict and the LVS
verdict; `make promote` rebuilt `castalia_B` from it; the headless proof reads
`bBox ((-135.0 -135.0) (2305.0 1825.0)) instances 259488` from both libraries through one
INCLUDE of `ic/cds.lib` (die frame 2480 x 2000, the outer 20 um of scribe carrying no drawn
geometry). `PENTA_PT_CUT` moved `pt7` -> `chip_2mm_i` and the `chip_2mm_a` `.gds2` symlink is
deleted. New register `signoff_mp/DRC_WAIVERS_chip_2mm_i.md` (W-I-1..3, O-I-1..5).

**The chip gate regression runs for the first time (Y12-6 closed).** Zero delay on the chip
netlist **13/14**, reproducing W4's table row for row and flag for flag with `shtcm`'s
documented zero-delay FAIL; the five-scope P&R SDF leg **14/14 ALL ROWS PASSED at BOTH views**
(`shtcm` PASSes under SDF, confirmed on a chip netlist for the first time), with 273,390
top-level INTERCONNECTs kept and 693 dropped by the re-scoper. `A0_PROBE=1` is re-measured
impossible on this netlist (`*E,CUHPNM Illegal pathname element dut`), so Y12-1 stays open.

Offline gates, both homes: `wq26c_legal_test` **86/0**, `wq27_ant_test` **19/0**, the
whole-proc harness **86/0 against both generated flows** (arms 1-20), `gen_chip_geometry.py
--check` and `gen_padring_pt2mm.py --check` pass, every earlier gate unchanged. Report
`tapeout_review/reports/Y13_chip_2mm_i.md`.

### Y14, 2026-10-04: Y13-A closed at source -- the placeholder's abstract did not describe its own GDS

`chip_2mm_j` **passes on attempt 1**: signoff setup **+0.055 ns / 0 violating of 36,927**, hold
**0.000 ns / 0 violating**, WQ27 PASSED, GDS and both per-view SDFs written, ingested, promoted
as `castalia_B`, **P&R SDF regression 14/14 at both views**. The three Y13 residuals resolve as
follows: the VDD-to-VSS short is **closed at source and proved three ways**, `ant25` is **clean**
(0 antenna violations, was 6), and the unadjudicated chipdrc set falls from 436 real-geometry
results to **72**, every one placed by coordinate.

**The short and the VIA5 DRC class were one defect.** `anatop_biasgen_g` is a black-box
placeholder, and its abstract did not describe its own GDS. The LEF's M6 OBS leaves a
**full-height access column** open per supply (`biasgen_g_lef_gen.py`'s own `access_channels()`
says so in words) and declares only an 8 x 4 um north tab; the GDS fills each column with an M6
leg running from that tab down to the supply's own **full-width** M5 strap, plus a 338-cut VIA5
array where the two overlap -- finding F19, drawn so Pegasus sees one conductor per supply
instead of two same-named shapes. Innovus reads the LEF and therefore saw empty M6 at
cell-local x 179.5-188.5, y 250-254, and landed a **VSS** M7-M6-M5 via stack at chip
(1660.200,1130.400) inside the **VDD** leg: `lvs.rep.shorts` SN 40 (the leg), SN 41 (one 0.1 um
VIA5 cut), SN 42 (the VSS strap). The same blindness let the flow stack its own VDD VIA5 array
on top of the placeholder's, in one 3.6 x 3.8 um box at x 1652.425-1655.975 y 1058.510-1062.290,
which produced **373 of the cut's 377 VIA5 results** (220 `VIA5.W.1` -- two abutting 0.1 um cuts
are no longer the exact rectangle the rule demands -- 207 `VIA5.S.1`, 56 `VIA5.S.2`).

**Fixed in three files with one derivation.** The abstract now declares each pin's M6 leg as a
PORT rect and carries `LAYER VIA5` OBS over the whole 340 x 340 footprint -- there is no
legitimate chip-level M5-to-M6 transition over this macro, because the straps are already tied
to their legs internally and the designed access is the leg itself, reached with a VIA6 from the
free M7. `gen_anatop_biasgen_g_bbox.py` takes the **union** of a pin's M6 rects for its overlap
test, so the emitted GDS is identical whether the abstract carries the leg or not (1439
boundaries, 74 texts, 1352 cuts, per-layer counts and M6 unions all unchanged, CDL byte-identical).
And NEW SHARED `tcl/pg_blockpin_lib.tcl` + `tcl/pg_blockpin_test.tcl` (both homes, identical md5,
in `gen_chip_geometry.py`'s SHARED list, **45/0** offline) feed gate **C-G19**: derive the
same-pin and cross-pin M<k>-n-M<k+1> windows from the abstract's own pin rows, assert the
abstract declares its internal arrays, blank the six cross-pin windows with
`createRouteBlk -pgnetonly` **above the first PG sroute**, delete them with a read-back after the
last one, and audit the database for a via inside a window.

**Four floorplan probes found three defects before a chip attempt was spent.** `FPLAN=1
./run_chip.sh` stops at the floorplan + PG checkpoint in ~9 minutes, which is where this work
lives. `y14fp`: the offending via belonged to the `blockPin` **workhorse** sroute 300 lines
above part 3b -- part 3b's own sroute creates 0 wires on this floorplan -- so C-G19 was split
into C-G19a (above the first PG sroute) and C-G19b (after the last). `y14fp2`: a **default**
`createRouteBlk` does not stop a PG sroute and neither does declaring the foreign leg as pin
metal, so `-pgnetonly` was added and the cut-layer OBS widened to the footprint; the same probe
showed `dbQuery -area` matching by EXTENT (three `AVDD_B` hits at a y no window contains).
`y14fp3`: `dbQuery -objType sVia` returns **every** cut layer, and the core M7 VSS column
crosses the macro freely, so its VIA7 at the VSS M8 strap looked like the short -- the audit now
filters on the window's own cut layer. `y14fp4` passes: 0 vias in 6 windows, 0 extent-only hits,
scoped `verifyGeometry` over the bias halo 0 different-net SHORT, and the PG-stage opens
**improved** (terminals 9, special 1), because the declared leg gives the chip 160 um of pin
metal to strap instead of a 4 um tab.

**Signoff.** `chipdrc` **1874** against 2368: 1506 in the purchased pad kit (identical counts),
**zero in the placeholder** (was 110), 368 at top level (was 752) = 80 density/dummy deferred
per O3 + 216 `PO.R.8` + 64 metal spacing/area + 8 via-rule. `VIA5.W.1`/`S.1`/`S.2` are **110 ->
0, 207 -> 0, 56 -> 0**: the fix measured by a second, independent check. `PO.R.8` is
**adjudicated** -- all 234 of `chip_2mm_i`'s result centres were tested for containment against
259,488 placed components and **234 of 234 landed inside a vendor cell, 0 in flow-drawn
geometry**, at FIXED cell-local sites (`PDUW16SDGZ_G` 120 at five sites x 24 pads,
`DLY2X0P5MA10TH` 52 at eight, `BUFX0P7MA10TH` 34 at four, five `NOR2XB*` masters 22,
`BUFX0P7BA10TH` 6), so the flow cannot move a structure that lives inside a purchased cell;
waiver W-J-4, and topology A's 132 on `d13d` is the same class. `ant25` is **clean**. Pegasus
LVS is still a MISMATCH but **`lvs.rep.shorts` is 0 lines** and the compare is back to the
pad-ring baseline: devices unmatched **155 : 95** against 27,517 : 27,470, nets 46 : 30, pins
85 : 85 with 0 unmatched, both placeholders matched, and **every digital device class 0 : 0**.
**Y13-4 is closed**: the negative control deleted one `BUFX2BA10TH` from `orch_vesta` and moved
unmatched layout devices 155 -> 159 and layout nets 46 -> 47 with the schematic side unchanged --
one injected fault, one caught fault.

**The antenna premise was wrong.** `tsmc65_hvt_sc_adv10_macro.lef` DOES carry per-pin antenna
data; the keyword is mixed-case (`AntennaGateArea`, 2643 instances across 916 macros) and an
uppercase grep misses it. The two checks differ in **which diffusion they credit**: the deck
counts only the protection diffusion connected at or below the layer under test
(`M3_DIO AREA = 0` on the violating net, so 294.962 / 0.0588 = 5016.4 against a 5000 limit,
0.33 % over) while Innovus counts the whole net's, and every std-cell output pin sits above the
0.06 um2 PWL knee that switches the limit to 43017 -- **8.6x loose**. The metal comes from the
CTS non-default rule: `CTS_2W2S`/`CTS_2W1S` are 0.4 um wide and `trunk_rule`/`leaf_rule` confine
clock trunks and leaves to M2/M3, into pure-gate clock-gate and flop CK sinks. New tool
`signoff_mp/ant_m13_census.py` measures that numerator from a DEF in ~3 minutes against
`ant25`'s 19: nine nets above 300 um2 on `chip_2mm_i`, 35 above 150, every one a CTS net.
**Not repaired**: both levers change clock routing on a cut closing at +0.055 ns, and the hard
LVS blocker had the attempts. `ant25` reads 0 on `chip_2mm_j` and NanoRoute's diode list carries
exactly one entry where `chip_2mm_i`'s was empty, so the class closed by accident and can return
(O-J-3).

**What did not improve.** The **zero-delay** gate leg fell 13/14 -> **4/14**: every multi-hart
row fails with all four per-hart flags false while the four single-hart rows pass with runtimes
identical to the reference. The failures are in SIMULATED time (`tb_shboot` runs to 56.6 ms and
reports TEST FAILED with all four tiles silent) and reproduce deterministically at
`MAX_PARALLEL=1`, so neither machine load nor the antenna diode (which `saveNetlist
-excludeCellInst`s) is the cause. It is the W4 finding-5 zero-delay artefact class -- a
zero-delay netlist simulation of a shared-memory multi-hart design has no timing to order the
arbitration -- widened by a different hold-ECO repeater set (13 against 24). The P&R SDF legs
are the regression of record and they are 14/14 at both corners (O-J-4).

**Next, in order**: the pad-ring LVS device class 155 : 95, the only remaining MISMATCH and a
vendor-netlist correspondence wave of its own; the antenna class structurally; the 72
real-geometry chipdrc results (at most 49 physical sites, 8 of them tile cut `y1i`'s); the
zero-delay gate leg. Register `signoff_mp/DRC_WAIVERS_chip_2mm_j.md`, report
`tapeout_review/reports/Y14_chip_2mm_j.md`.

### Y15, 2026-10-04: the pad ring cannot correspond, and the deck's markers are invisible to the flow

Four mechanisms are now named, the LVS residual falls **155 : 95 -> 16 : 16** with the parameter
mismatches gone, and the chip cut `chip_2mm_k` is **parked at attempt 2 of 2**: `chip_2mm_j` stays
the cut of record, `PENTA_PT_CUT` is untouched and `castalia_B` is still promoted to it.

**O-J-1, the pad-ring MISMATCH, is not a CDL version, a tolerance or a missing cpoint.** It is two
defects and both are inside purchased cells. First,
`tphn65gpgv2od3_sl_1_2.spi:22` declares `.GLOBAL VDD VSS VDDPST VSSPST POC TAVSS TAVDD TACVSS
TACVDD` -- one node per ring bus for the whole netlist -- while this ring deliberately CUTS every
one of them: ten `PRCUTA_G` brackets give five analog domains (`AVDD_0..3`/`AVDD_B`, decision X3-A,
and the chip log's own ten `ANATOP part 3 -- net AVDD_<n>: 4 pad terminal(s)` lines) and D21 gives
six VDDPST/VSSPST pairs to five digital arcs. Four pad masters reference the analog pair and two of
them cannot even name it, because it is not in their port list: `.SUBCKT PVSS2A_G VSS` hangs
nineteen devices off `TAVDD`/`TAVSS`, and `.SUBCKT PDB3A_G AIO` nine. One schematic net cannot
correspond to five layout conductors, so every ESD and clamp device in those 57 pads is
uncorrespondable -- that is the 155 : 95, and all eleven `XPAD_*` "finger-count" parameter errors
are the same defect seen from the reduction side (`<X2/X39/X450> rm1 w 42.48 u` against
`<XPAD_AVDD_1_0/X_53> rm1 w 212.4 u` is 2 x 21.24 against 10 x 21.24: the schematic merged all ten
AVDD pads' copy, the layout merged the two in one island). Second, `PDUW16SDGZ_G` carries
`X_97 VSS net_37 rppolywo` and `X_98 net_38 VDD rppolywo` with both far nodes used nowhere else --
108 identical two-terminal devices with an open end, an ambiguity no matcher breaks: 36 : 36
unmatched `rppolywo`. **The control is Myshkin's shipped `ASIC_final`**: same pad kit, same deck,
one uncut ring, and every pad device class came back 0 : 0.

**The fix** declares the eleven tphn masters the chip instantiates as regular `lvs_black_box`es --
no `-black`, no `-gray`, so the cells are still extracted and compared PIN TO PIN, which keeps the
pin assignment, the one thing chip LVS is for -- plus four scoped `lvs_delete_cell_pin` classes
with their reasons in the control file: `PGATE`/`NGATE` layout-side (`*PGATE NGATE` is a SPICE
COMMENT in every vendor pad subckt, so the netlist has no such ports while the GDS carries the
texts) and `TAVDD`/`TAVSS` on the four analog masters. `lvs_delete_cell` was rejected because
removing the instance removes the only path from a top-level port to its core net. Measured on
`chip_2mm_j` with nothing but the control file changed: devices **16 : 16**, nets **14 : 3**,
parameter mismatches **0**, `rppolywo` **0 : 0**, every MOS and diode class 0 : 0, shorts 0 with
sentinels armed, **9 of 13 box cells MATCH**, and the design's own 7,968,803 reduced devices still
compared device for device. **The negative control discriminates**: one deleted `BUFX2BA10TH` moves
unmatched layout devices 16 -> 20, as MP(PCH_HVT) 0 -> 2 and MN(NCH_HVT) 0 -> 2, with the schematic
side unchanged -- so black-boxing the purchased pads did not blind the compare, which was the one
real risk of the fix. The remaining 16 are pad instances and all 16 are the five-domain class;
**O-K-1** is the three coupled edits that close it and needs no cut.

**O-J-2: `verifyGeometry` does not implement the rules the deck fails on.** `chip_2mm_j`'s signoff
pass read Wiring 0, real SameNet 0, Short 0, Overlap 0 on the database that carried all 72
real-geometry chipdrc results, because `M<n>.S.2` is a *union-projection* width/parallel-run
spacing rule and `M6.A.2` is an *enclosed area* rule Innovus has no equivalent for. F19b, driven
by a verifyGeometry report, had nothing to repair; the markers exist only in the previous cut's
chipdrc RDB. New `signoff_mp/drc_eco_markers.py` turns that RDB into a marker file and accounts for
every result (1874 = 1506 pad-kit ESD + 216 `PO.R.8` + 72 density + 8 dummy + 72 real in 16
classes); new SHARED `tcl/drc_eco_{lib,test}.tcl` (26/0 offline, gate 12 in `run_chip.sh`) holds the
policy; stage C-G20 applies it. The 72 are now classified BY REPAIR BRANCH on the real database:
41 weldable PG -- of which 24 are **8 enclosed 1.5 x 0.1 um = 0.15 um2 holes** on the two flanks of
the bias-island pads' 4.0 um `TAVDD`/`TAVSS` plate, and 2 are the same-net `M7.S.4` gaps the
independent WQ21 scorer reproduces to the coordinate -- 23 router geometry, and 8 inside
`hart_tile_pt`, which belong to tile cut `y1i`.

**O-J-3: the two antenna checks carry the same rule, and the disagreement has no knob in this
release.** `ant25.rul` says `net_area SD -ge 0.06 -outputlayer M3_DIO` and then
`antenna M3 M2 M3_DIO HV18_GATE GATE -accumulate ACC_M2` with the 5000 and
`456*AREA(M3_DIO)+43000` branches; the technology LEF says
`ANTENNACUMAREARATIO 4996` and `ANTENNACUMDIFFAREARATIO PWL ( (0 4996) (0.059 4996) (0.06 43017)
(1 43436) )` -- the same 0.06 um2 source/drain break point, the same two branches, the same
456 um^-2 slope. The gate areas agree to 0.8 % (`AntennaGateArea 0.0593` on the flagged
`PREICGX0P5BA10TH` CK pin against the deck's measured 0.0588). The whole difference is
`-accumulate ACC_M2`: the deck scores the PARTIAL net that exists when only M1..M3 are etched, so a
trunk reached by its driver only through M4 has `M3_DIO = 0` and a limit of 5000, while Innovus
credits the whole routed net's diffusion and lands on 43017. **Innovus 20.12 has no
`setAntennaMode`** and `verifyProcessAntenna`'s entire option set is
`-detailed -error -net -selected -noIOPinDefault -noMaxFloatArea -pgnet -report`; the diode
insertion earlier waves suspected was never off (`-routeInsertDiodeForClockNets true` has been armed
since before `pt11`). The only lever is the data -- strip `AntennaDiffArea` from a local macro LEF
copy, or raise `trunk_rule`/`leaf_rule` one layer -- and both change routing, so neither was
combined with the DRC repair. **The class is NOT closed by construction and this plan does not
claim it is**; `ant25` remains the authority.

**O-J-4: the zero-delay leg is the W4 finding-5 artefact, localised.** The hold repeaters are DELAY
CELLS, so a zero-delay run sets their delay to zero -- it deletes the fix and keeps only its
one-delta-cycle cost. Ten of `chip_2mm_j`'s fourteen sit on a `hart_tile_pt` boundary pin, and the
pass pattern matches the per-hart distribution exactly: on the four rows where any hart passes,
harts 2 and 3 pass and harts 1 and 4 do not, which are precisely the two harts whose
`tcm_ext_addr` bus carries a repeater in this cut (hart1 bits 4 and 8, hart4 bit 5; harts 2 and 3
carry none). `chip_2mm_i`'s single `tcm_ext_addr` repeater was on hart4 and `shtcm` is the one row
that failed there. Not functional: the SDF legs are 14/14 at both corners including the ff/-40 C
hold corner these insertions exist to fix, signoff hold is 0.000 ns / 0 of 36,927, all four
single-hart rows pass within 1 s of the reference runtimes, and the netlist carries no antenna
diode. The actionable item is the LEG (`-excludeCellInst DLY*`, or retire it for the two SDF legs).

**`chip_2mm_k`, both attempts.** Attempt 1 ran clean through the hold ECO and then died at
`ecoRoute -fix_drc` with IMPSYT-6692, because C-G20's weld is `add_shape -shape STRIPE` and it had
welded six markers on SIGNAL nets; a STRIPE on a signal net is a disconnected piece to the router,
which answered "There were 10 open nets". F19b's own header already carried the rule in words; the
library now enforces it, and both the `ecoRoute` and the whole stage call are caught so a
non-gating stage can never cost a cut again. Attempt 2 closed **setup at +0.130 ns / TNS 0.0 /
0 violating of 36,927** -- 75 ps better than the cut of record -- with `verifyProcessAntenna` at 0,
and then FAILED the WQ27 gate with Wiring 2, Short 3 and SameNet 26 unwaived against
`chip_2mm_j`'s 0/0/0. **Every delta is at a weld**: replaying the 48 logged weld coordinates
against the signoff report's own `Bounds` lines, 20 SPACING, 12 SHORT and 2 MINSTEP markers contain
a weld point on the weld's own layer. The weld is right for the deck and wrong for Innovus's
checker -- a same-net rectangle abutting existing routing produces same-net SPACING, MINSTEP and
SHORT-against-blockage of its own, and the WQ27 waiver classifier only knows the two shapes F19b
draws. `PENTA_DRCECO` now defaults to 0, with three repairs named at the knob (teach the classifier
the weld boxes by coordinate; draw the weld as a regular wire; or do it in the GDS writer). The
routed database is saved; no GDS, no SDF, nothing ingested or promoted.

**Next, in order**: O-K-1, because it is the only thing between the chip and an LVS MATCH and it
needs no cut; O-K-2, after which C-G20 can run and the 72 fall to single digits; the antenna lever,
on a cut with margin to spare -- this floorplan has 130 ps; O-K-4. Register
`signoff_mp/DRC_WAIVERS_chip_2mm_k.md`, report `tapeout_review/reports/Y15_chip_2mm_k.md`.

### Y16, 2026-10-04: the island binding takes LVS to 6 : 6, and two prescribed remedies are disproved

`chip_2mm_j` entered this wave as the cut of record with four residuals. Three of them moved and
one of them was overturned.

**O-K-1(b)/(c), the analog supply domains, stated end to end.**
`patch_chip_pads_penta_pt.py` bound all twenty analog supply pads to ONE net literally named
`AVDD`/`AVSS` while the database carries FIVE per rail and says so ten times
(`ANATOP part 3 -- net AVDD_0: 4 pad terminal(s)`). It now writes the five domains the way the
database does: every `PAD_AV{DD,SS}_<h>_<k>` ball pin onto `AV{DD,SS}_<h>`, the island nets threaded
through `module MCU` (the harts are instantiated inside it, the pads at chip top, so without eight
new ports there is no path between them in the netlist at all), and into each hart's own
`AVDD`/`AVSS` port and `anatop_biasgen_g0`'s `AVDD_B`/`AVSS_B`. The island tag is read out of the
instance name and the SET of tags is checked against the five X3-A/D21 islands; the hart-to-island
map is ANATOP part 3's and the script refuses to run if the tile instances are not `hart1..hart4`.
Measured on `chip_2mm_j` -- same GDS, same deck, two LVS runs -- unmatched devices **16 : 16 ->
6 : 6**, `PVDD3A_G` **8 : 8 -> 0 : 0**, `PVSS2A_G` / `PDB3A_G` / `PVDD1DGZ_G` / `PVSS1DGZ_G` /
`PVDD2POC_G` all 0 : 0, every MOS / diode / `rppolywo` class 0 : 0, 7,968,803 : 7,968,803 reduced
devices compared, top-level pins **83 : 85 with 0 unmatched** (Y15's two extra layout pins gone),
`lvs.rep.shorts` empty with the sentinels ARMED.

**O-K-1(a) is required, and the shortcut is disproved.** `lvs_delete_cell_pin` cannot remove a pin
whose name is also a `.GLOBAL`. pegasusref says `-source_layout` applies to both views and it does
-- `PGATE`/`NGATE` go 12 pins to 10 on both I/O masters and those cells read `match` -- but
`VDDPST` is both a port of `PVDD2DGZ_G` and a name in the vendor's
`.GLOBAL VDD VSS VDDPST VSSPST POC TAVSS TAVDD TACVSS TACVDD`, so Pegasus deletes it and re-creates
it by global connection. Run 1 measured a one-sided deletion
(`Layout Pin: ** missing pin ** | Schematic Pin: VDDPST`), which is a guaranteed CELL mismatch, and
the disturbed pairing made the class worse: `PVSS2DGZ_G` 2 : 2 -> 5 : 5, `PVDD1DGZ_G` and
`PVSS1DGZ_G` 0 : 0 -> 1 : 1. Reverted, with the measurement written at the line. A second
experiment was also reverted: ten per-island layout texts on a new non-PORT layer 232 ATTACHED, and
two of them to the same conductor -- `SHORT 1. AVSS_B: - AVDD_B:`, the first entry this chip's
shorts file has ever had, because the vendor's M3 ring bus runs ALONG the pad row, so metal3 at a
bond-plate coordinate names the bus and not the plate. The analog rails now carry no layout text at
all, which is strictly better than both predecessors.

**The last 6 : 6, named.** `PVSS3A_G` 2 : 2 is the pad whose core-side stub ANATOP part 3b does NOT
strap (the log names which one it does): the other pad reaches its island only through the vendor's
own `rm1`/`rm2` metal resistors to the bond plate, which Pegasus extracts as DEVICES, so binding
that stub to the island is a statement the layout does not support -- reported as a missing
connection on islands 1 and 3 and as an OPEN on 0 and 2. `PVDD2DGZ_G` / `PVSS2DGZ_G` 2 : 2 is one
`.GLOBAL VDDPST` against the THREE bracketed arcs the cut's own C-G3 census counts (1, 1 and 4
supply pads). Both need the de-globalised local copy of the pad SPICE, which the report prescribes
in four steps.

**O-K-4's prescribed remedy is disproved by a controlled experiment.**
`xcelium/riscv_test/common/zero_delay_dly_filter.py` (NEW, offline gate 19/0) collapses the 14
`FE_ECOC*` hold-ECO delay cells to `assign Y = A;` -- instance-scoped on purpose, because the
netlist carries 1334 `DLY*` instances of which all but 14 are CTS buffers and placement repeaters,
and `-excludeCellInst` on a two-pin cell leaves its output undriven. The zero-delay leg re-ran all
14 rows and came back **4/14 with verdicts and per-hart flags byte-identical to the unfiltered
run**. So the delay cells are not the cause and Y15's hart-1/hart-4 correlation is a coincidence.
The two SDF legs remain the regression of record (14/14 at both views, signoff hold 0.000 ns / 0 of
36,927). O-L-1: bisect `chip_2mm_i` 13/14 against `chip_2mm_j` 4/14; every failing row is
multi-hart and all four single-hart rows pass, so the de-collided tile netlist is the first suspect.

**O-J-2, the largest chipdrc class, fixed in the geometry by a derived number.** 24 of the 72
real-geometry results are eight sites at the EAST bias island's two AVDD drops, each flagged by
`M6.A.2` + `M6.S.2` + `M6.S.2.1`. The vendor leaves a 1.5 um M6 gap on each flank of the bond plate
(the two marker x-ranges are exactly those flanks); the M6 drop bar is drawn at the plate centre
+/- `ANARING_W`/2 = +/- 4.0 um and crosses both, leaving exactly 0.100 um to the vendor's own M6
above and below -- against 0.12 for `M6.S.2`, 0.16 for `M6.S.2.1` and a 1.5 x 0.1 = 0.15 um2
enclosed area against `M6.A.2`'s 0.2. New knob `ANARING_DROP_W` = 7.6 um opens the gap to 0.300 um
and the hole to 0.45 um2, for 5 % of one 22 um M6 strap on a 6.6 ohm budget. Welding it shut was
`chip_2mm_k`'s mistake; opening it is free.

**O-K-2's per-branch knob.** `PENTA_DRCECO` is back to 1 with `PENTA_DRCECO_WELD` = 0: the ROUTE
branch (blockage + `ecoRoute -fix_drc`, F19b's own recipe, never implicated in either `chip_2mm_k`
failure) runs and a weldable marker is SKIPPED with its class named. Re-enabling the weld still
needs the WQ27 classifier to reconcile 20 SPACING + 12 SHORT + 2 MINSTEP marker lines against
+25 SameNet / +11 Short / +2 Wiring in the summary; a classifier written from the marker lines
alone would under-waive and FATAL the gate.

**O-J-3's lever is pulled.** `ant_m13_census.py` on `chip_2mm_j`'s own DEF: 2 nets above 300 um2 of
M1~M3, 10 above 250, 32 above 150, worst 363.16 um2 with 361.84 of it on M3, every one of the top
twelve a `CTS_2W2S` trunk -- against the 293.8 um2 that the deck's own measured 0.0588 um2 clock-gate
gate area implies. `trunk_rule` therefore goes from M4/M3 to M5/M4 with its VSS shield, in both the
chip base and the core flow so `gen_chip_geometry.py`'s decision table still sees an equal run.
`leaf_rule` is deliberately not raised. `ant25` stays the authority.

**`chip_2mm_l`, attempt 1: FATAL at the WQ26c scoped-route gate, and it priced the antenna lever.**
0 FATAL through floorplan, PG, placement, CTS, routing, C-G20 and the first signoff timing; then
`FATAL (WQ26c): the scoped route disturbed 21 net(s) it was not given`, 13 of the 21 inside
`mcu0/i2c1`. What it measured first: setup IMPROVED to **+0.095 ns / 0 violating of 36,927** on the
raised trunk (j: +0.055), hold got WORSE (-0.039 / 19 endpoints against -0.037 / 13), and the raised
trunk created a NEW signal-net antenna marker -- `Non-Default Wire of Net mcu0/afe0/CTS_14 ( M1 )`,
45 parsed / 44 waived / 1 unclassified -- which the WQ27 gate refuses in its own right. C-G20's
ROUTE branch ran clean in the same attempt (72 markers, 22 router ECOs, 22 blockages created and
deleted, 50 skipped, no WARN) but cannot be cleared of the FATAL from one attempt. **O-J-3's cheap
lever is therefore a measured refusal: 40 ps of setup for a WQ26c FATAL and an M1 antenna.** Both
routing deltas reverted, each with its measurement at its line.

**`chip_2mm_l`, attempt 2: PASSES, and it is the cut of record.** One delta over `chip_2mm_j`:
`ANARING_DROP_W`. Setup WNS **+0.006 ns / TNS 0.0 / 0 violating of 36,927**, hold **0.000 ns / 0
violating** after two hold-ECO passes (-0.030 / 50 endpoints -> 22 -> 0, 46 repeaters), density
62.989 %. **WQ19 PASSED** (0 regular-routing PG opens) and **WQ27 PASSED** (Wiring 0 of 3, SameNet 0
of 1171, Short 0 of 54, Overlap 0, dangling 0 of 41, antenna 0 of 44, verifyProcessAntenna 0); C-G19
clean. GDS 179,323,516 B md5 `68f3e2d29ccff91071c4912b07bbdc6a`, both per-view SDFs.
`chipdrc` **1874 -> 1839** with **real-geometry results 72 -> 34** (8 of them `hart_tile_pt` cut
`y1i`'s, 2 the `M7.S.4` west-flank pair, 24 core metal/via) and the bias-island class gone:
`M6.A.2` 8 -> 0, `M6.S.2` 9 -> 1, `M6.S.2.1` 9 -> 1. **`ant25` CLEAN** (`A.R.6__A.R.8:M3` 0; the
census says the exposure grew, 8 nets above 300 um2 against j's 2, so the class is clean on this cut
and not closed). **LVS MISMATCH at 6 : 6 with the shorts file EMPTY** -- the same residual as
`chip_2mm_j` under this control file. Ingested, promoted, `PENTA_PT_CUT` moved, headless proof
`PROOF castalia_B ... instances 260252` identical to `castalia_B_chip_2mm_l`. **Five-scope P&R SDF
regression 14/14 at BOTH views**; the zero-delay leg with the DLY exclusion armed and all 46 cells
collapsed is 5/14, a third per-hart pattern, which is the second disproof of O-K-4's remedy.

**Setup is +0.006 ns.** 0 violating of 36,927 at four views with SI on is the gate and it passes,
but the margin moved 90 ps across three cuts that differ only in routing, so none of the three
numbers is a property of the design and this one leaves no room for a timing-affecting ECO (O-L-3).

**Next, in order**: the LVS negative control on this cut (O-L-4 -- one run, the cheapest item, and
the cut's LVS cannot be trusted without it); O-K-1(a), the only route to a MATCH and it needs no
cut; one chip cut with `PENTA_DRCECO=1` alone, to separate the ROUTE branch from the trunk and close
the 24 core markers; O-L-2, the `AVDD_B`/`AVSS_B` correspondence collapse at the biasgen
placeholder; O-L-1, the zero-delay bisection between `chip_2mm_i` and `chip_2mm_j`; O-J-3's
macro-LEF lever. Register `signoff_mp/DRC_WAIVERS_chip_2mm_l.md`, report
`tapeout_review/reports/Y16_chip_2mm_l.md`, `TOPOLOGY_B.md` section B.P.

### Y17, 2026-10-04: every device corresponds, the ring plan does not, and the zero-delay leg is a scheduler artefact

**O-K-1(a) is built and LVS on `chip_2mm_l` is a different object.** The local de-globalised pad
SPICE is a BUILD PRODUCT of the vendor file -- `signoff_mp/gen_tphn_local_spi.py` emits it and
`--check` re-derives it on every collateral build, FATALing unless the only delta is the `.GLOBAL`
line plus the promoted ports (same 57 subckts, same 5024 device lines). `VDDPST`, `VSSPST` and `POC`
are ordinary ports now, bound **one net per ring arc** on all 73 digital pads (219 pins, arcs 1, 2
and 4) from a map `signoff_mp/padring_arcs_pt.py` derives from the cut's own floorplan DEF and
self-tests against gate C-G3's published census (16 / 8 / 30 I/O pads, VDDPST 1 / 1 / 4); the three
133 PORT texts came out in the same change. Measured across three Pegasus runs:

| | Y16 | Y17 run 1 | **Y17 run 2** |
|---|---|---|---|
| cells matched of 14 | 9 | 13 | **13** |
| unmatched devices | 6 : 6 | 2 : 2 | **0 : 0** |
| top-level pins | 83 : 85 | 80 : 80 | **80 : 80**, 0 unmatched |
| unmatched nets | 17 : 6 | 21 : 10 | **12 : 11** |
| shorts file | 0, ARMED | 0, ARMED | **0, ARMED** |

7,963,650 : 7,963,650 reduced devices with every class 0 : 0, including all eleven tphn pad masters
and both analog placeholders, and the five analog domains intact. **The negative control
discriminates** (O-L-4 CLOSED): one deleted `INVX7P5BA10TH` in `orch_vesta` comes back as 2 : 0
unmatched with both transistors named at their layout coordinates.

The verdict is still MISMATCH and the four reasons are named. One is LVS and is a one-line change
with two controlled runs behind it: bind BOTH `PVDD3A_G` ball pins to the island, because the layout
joins the two pads' AVDD core stubs within a section while their AVSS stubs are separate (Y16
measured it from the opposite binding, Y17 run 2 from this one). The other three are not LVS.

**W-L-6 is a NEW BLOCKER, and the per-arc audit is what found it.** `PRCUT`/`PRCUTA` pass only VSS,
so they CUT `VDD`, `VDDPST`, `VSSPST` and `POC` and every bracketed arc is its own conductor on all
four. All three `PVDD1DGZ_G` and all three `PVSS1DGZ_G` sit in the two EAST arcs, so **arc 4 -- the
west column plus the two top-west PST pads, 30 I/O pads -- has a 1.0 V ring segment isolated from
core VDD**, and those pads' pre-drivers and level shifters have no core supply. Innovus cannot see
it: those pins carry no `USE` line in the tphn LEF, the supply arrives by abutment with no net, and
WQ19 PASSED with 0 regular-routing PG opens while this was present. The extraction measures it as
`Layout Pin: VDD ... Layout Net: 4 | OPEN`, and the arc walk predicts all five rail conductor counts
correctly (VDDPST/VSSPST/POC three each, VDD two, VSS **one** -- VSS being the control, the one
candidate rail the brackets do not cut). **W-L-5**, same mechanism and lower severity: arcs 1 and 2
(16 and 8 I/O pads) have no `PVDD2POC_G`, so their `POC` input floats. Both need a ring-plan change,
i.e. a cut. NEW gate `RINGSUP` audits every arc against all four cut rails and FATALs on any
arc/rail pair not acknowledged by name with a reason and an owner; C-G3 checked only the
`VDDPST`/`VSSPST` pair, which is why both survived eleven cuts. Register
`signoff_mp/RING_SUPPLY_chip_2mm_l.md`.

**O-L-1 is answered and it is not a blocker: the zero-delay leg measures delta-cycle clock skew.**
Y16's first suspect is eliminated outright -- the de-collided tile netlist is byte-identical (md5
`b4091d05`) whether generated from `chip_2mm_i`'s chip netlist or `chip_2mm_l`'s. A zero-delay run
still charges every cell one DELTA, so the chip-level CTS tree is a clock skew of up to 12 delta
cycles (leaf depths 1..12 on `l`, 1..14 on `i`; the four hart clocks at 10/10/10/12 and 12/10/14/14)
against shared-interface handshake paths that are 1 to 7 gates deep. The controlled experiment:
`xcelium/riscv_test/common/zero_delay_clk_flatten.py` collapses every pure-inverter chain from
`mclk` to a direct `assign` with polarity preserved (149 inverters, hart clocks to 0/0/0/0,
structurally self-checked), and with no other change `shboot`, `shexec` and `shmutex` go from hart1
alone passing to **harts 1, 2 and 3** passing. hart4 survives it because `MCU` holds only 19 of the
chip's 1152 clock-leaf inverters -- the other 1133 are inside the submodules -- so the control is
partial by construction. The same netlist is 14/14 at BOTH per-view SDF legs and signoff hold is
0.000 ns / 0 of 36,927 at ff 1.1 V / -40 C, where the insertion delay is common-mode and CPPR
removes it. The consequence is a change to the leg, not to the design: run it flattened, or retire it
for the two SDF legs.

**Next, in order**: W-L-6's ring-plan fix, which is a cut and re-times the chip (O-L-3: setup is
+0.006 ns); the one-line AVDD binding change plus one LVS run, which should take unmatched nets to
8 : 7; the biasgen placeholder's split `bn_o`/`bnc_o`/`bp_o`/`bpc_o` pins and the `AVDD_B`/`AVSS_B`
collapse, which need a new macro GDS; `PENTA_DRCECO=1` alone to close the 24 core markers. Report
`tapeout_review/reports/Y17_lvs_zerodelay.md`.

### Y18, 2026-10-04: every rail-cut arc is supplied, the ring plan is the gate, and the package is a standard part

**W-L-6 and W-L-5 are closed in the ring plan, and the gate that found them now lives in three
places.** `gen_padring_pt2mm.py` adds six pads: `PAD_VDD_3`/`PAD_VSS_3` (`PVDD1DGZ_G` /
`PVSS1DGZ_G`) on the west row at **y[1025,1075]**, `PAD_POC_1` on the north edge's east span,
`PAD_POC_2` on the south edge's east span, and a second PST pair `PAD_VDDPST_6`/`PAD_VSSPST_6`
beside the latter. 130 -> **136 pads**, bond fingers per edge **27 / 27 / 39 / 43** against the
LQFP-176's 44 cap. The west pair's y is a measurement, not a placement: `chip_2mm_l`'s own
floorplan DEF puts the westmost standard-cell row at x0 = 90.0 over y[1015,1227] only, and the
core PG verticals nearest the west edge at x 9.0 / 53.5 (VDD M7) and 23.0 / 62.5 (VSS M7) over
y ~454-1210, so that window is the only one on the whole row with both -- Y8 measured 0 stubs on
four pads at y[500,600] and y[1060,1210] and that is why all three pairs went east. The floorplan
probe proves it: **`WQ22 pad stub census -- 68 M1 stubs on 8 core supply pads, PAD_VDD_3 = 10/10,
PAD_VSS_3 = 7/7`**, every offered stub on every pad.

**RINGSUP replaces the `VDDPST`-pair-only C-G3, and it found four more findings on the OLD cut.**
The arcs are now derived from the `PRCUTA_G` bracket positions on the closed perimeter in the ring
plan (offline), in `pt_gate_cg3` (from the placed database) and in `padring_arcs_pt.py` (from the
cut's DEF) -- one definition, three implementations. The predecessor grouped the digital runs by
their `A<n>` NAME prefix, and `A1`, `A2` and `A5` are three names on ONE arc, which is why a
name-keyed census could not see that the combined west arc had no core-supply pad at all. Run
against `chip_2mm_l`, the upgraded audit reports **7** arc/rail findings where Y17 had 3: the two
missing POC sources, the missing west VDD, **plus the west arc's missing `PVSS1DGZ_G`, arc 1's one
2.5 V pair for 16 I/O pads, and runs of 21 and 16 consecutive I/O pads with no 2.5 V source
between them**. The 21 is `TCK..TRSTN` then `P1` then `P0`: four pairs in that arc, all four at one
end of it. Three west runs plus `A4_E` are re-ordered -- same edge, same cells, same instance
names, only the order and hence each pad's y -- and the worst run on every arc is now 8. The
8-per-pair ratio is a **STATED ASSUMPTION**: no `tphn65gpgv2od3_sl` release note exists on this
disk (the vendor install directory holds only the unopened `.zip`), so the number lives in one
knob that all three gates read. `padring_arcs_pt.py`'s `ACK` table is now EMPTY -- every finding is
fixed in the plan, not waived -- and `penta_pt_ring_test.tcl` grew negative controls that
reproduce W-L-6, W-L-5 and the long-run finding from the emitted padlist (34 -> 43 pass / 0 fail).

**The package is a standard LQFP-176 and Y9's model could not have built.** D21 trimmed each
analog section from 24 slots to 14 precisely so a catalog part would fit; `castalia-qfn176-pt2mm`
was built before that, assumed an unequal-per-side 23 x 23 mm 0.4 mm-pitch lead frame with no
vendor match, and its 171-entry `BALL_BY_INST` names 169 pad instances the ring no longer has.
It is retired to `python/qfn176_pt2mm.py.superseded_d21`. `python/lqfp176_pt2mm.py` bonds all 136
pads into **24 x 24 mm, 0.5 mm pitch, 44 fingers a side** with 40 NC, the used block centred in
each side (W 3-41, S 53-79, E 89-131, N 141-167); every latch-up anchor and every per-arc supply
pad has a finger, `VSS` is a 13-pin rail and `VDD` a 4-pin one. Bond-wire angles from the live die
row: W 40.6, S 28.9, **E 43.2**, N 27.8 deg against the assumed 45. The east number is inherent to
D21 -- 44 leads at 0.5 mm span 22 mm and a 2.48 x 2.00 mm die in a 24 mm body has a 10.76 mm
standoff -- and is **parked for the owner**: if a real assembler's ceiling is below 45 deg the
answer is fewer east-side pads or a redistribution interposer, not a different ball map. The model
also found a real ring-plan defect: three `PVDD2POC_G` pads on one net name is a duplicate
package-pin symbol, so the nets are `POC`, `POC_1`, `POC_2` -- which is the truthful form too,
since `PRCUTA_G` cuts POC and `chip_2mm_l` measured three POC conductors.

**O-L-2's three `bias_*` opens are closed at the generator and the `AVDD_B`/`AVSS_B` candidate is
eliminated.** `gen_anatop_biasgen_g_bbox.py` joins any pin whose rects on one layer are disjoint
and PROVES the join by union-find, so the four bias outputs' two 2 x 2 um M4 squares (north edge
and east edge, both needed: the macro sits 21.6 um under the top tile row) are one conductor each;
only GDS layer 34 moves, 8 -> 16 boundaries. `biasgen_g_lef_gen.py` plates M5 over the whole
footprint -- the banded form advertised 6 800 um^2 of free M5 over four full-width M5 strap shapes,
and Y14's VIA5 OBS stopped the M5-to-M6 TRANSITION but not plain M5 metal reached with a VIA4.
**The collapse itself is NOT the macro's M5**: `chip_2mm_l`'s `lvs.rep.cls` puts SIX pins on layout
net 147 -- the macro's AVDD and AVSS plus all four EAST BIAS island supply pads' ball pins at
(2170, 742.34 / 767.34 / 917.34 / 942.34) -- which no shape inside a macro at x[1472.4,1812.4]
reaches. Carried as **O-M-1** with the next artefact named (the Pegasus layout-net geometry for
net 147, or a frame run on the bias island alone).

**The one LVS line Y17 left is applied**: both `PVDD3A_G` ball pins of a CHANNEL island go on the
island net and `PVSS3A_G` keeps the strapped-pad-only form, which is what two controlled runs from
opposite ends measured (Y16: both rails on the island, `PVSS3A_G` 2 : 2; Y17: strapped only, four
AVDD SHORTs). The east bias island is deliberately untouched -- it has no strapped pad and is the
O-M-1 class.

**The zero-delay leg is redefined rather than retired.** `run_gate_suite.sh` now runs
`common/zero_delay_clk_flatten.py` on the zero-delay leg by default, documented at the line as the
W4/Y17 artefact remedy; the two SDF legs are untouched. It is a partial control by construction
(module `MCU` holds 19 of the chip's 1152 clock-leaf inverters) and that is recorded at the line.

**Chip cut `chip_2mm_m` (attempt 1 of 2) IS THE CUT OF RECORD, and the ring bought the timing.**
`WQ26 slack gate PASSED -- setup WNS 0.073 ns, hold WNS 0.001 ns` against `chip_2mm_l`'s +0.006 /
0.000, with 26 hold repeaters instead of 46 and WQ26c reporting 0 open regular nets and 0 disturbed
neighbours. **No timing lever was pulled**: every `PENTA_*` knob is at the value `chip_2mm_l` used,
`PENTA_DRCECO` is 0 and the CTS trunk rule is untouched -- what moved is where 30 west-edge pads
sit. O-L-3 is answered by +67 ps of setup at no hold cost, so Y16's measured trunk-rule lever (40 ps
for a WQ26c FATAL and an M1 signal antenna) stays refused and untried. `WQ19` and `WQ27` PASSED,
`RINGSUP` 0 unsupplied arcs of 5, `WQ22` 68 stubs on 8 core supply pads, density 61.080 %, GDS
md5 `08ace969df43f72ce86ebd6d0fedc0e6`, both per-view SDFs written, Innovus exit 0 with 0 FATAL.
`chipdrc` **1736** (1506 + 108 + 80 + 42) against 1839; `ant25` **CLEAN**. Ingested as
`castalia_B_chip_2mm_m`, promoted into `castalia_B`, `PENTA_PT_CUT` moved, both libraries proved
headless at **259,611 instances**. **Five-scope P&R SDF regression 14/14 at the setup view** with
every multi-hart row reporting `pass=true` on all four tiles.

**LVS is MISMATCH and the residual is now ONE class instead of four.** Devices
**7,964,341 : 7,964,341 reduced, 0 : 0 unmatched** in every class, pins **80 : 80**, shorts file
EMPTY, no `** missing connection **` on any supply pin -- and unmatched nets **12 : 11 -> 1 : 7**.
Three of Y17's four classes are gone (the `VDD` OPEN, the three `bias_*` opens, the four AVDD
SHORTs). The six-line SHORTS AND OPENS section names the mechanism completely: a supply pad's
AVDD/AVSS BALL pin corresponds to a layout conductor only where top-level metal touches its
core-side stub, ANATOP part 3b straps ONE pad per rail per CHANNEL island, so the un-strapped AVSS
pads of islands 0 and 1 and all four EAST BIAS island supply pads land -- with the macro's own AVDD
and AVSS -- on one layout net. **That is why three waves read net 147 as a macro problem: four of
its six pins are PADS at x >= 2170.** The fix is a FLOW change, not an LVS one: a core-side strap
for every supply pad in part 3b (ten more jogs), or those ball pins deleted from the compare rather
than stated as stub nets. Either is a cut.

**Next, in order**: the ten part-3b straps, which is the whole remaining LVS class and takes the
chip to MATCH; the east M4 port of the four bias pins dropped (Y17's own prescription), which
removes the square the join exposed as touching VSS; `PENTA_DRCECO=1` ALONE, which is still the
only thing that separates C-G20's two branches and owns the 32 flow-drawn chipdrc results (24 on
`chip_2mm_l`, so the class is routing-dependent); the bond-wire fan-out against a real assembler's
rule (Y18-A); and the PST ratio against a real release note (Y18-B, D22). Report
`tapeout_review/reports/Y18_chip_2mm_m.md`, registers
`signoff_mp/RING_SUPPLY_chip_2mm_m.md` and `castalia_B_chip_2mm_m/README`.

### Y19, 2026-10-05: every analog supply pad is strapped, the east island's rails were isolated metal, and the zero-delay dead clock is the root re-entering its own generator

**O-M-1 is a FLOW defect in two parts, and measuring it offline found a second one the prose did
not contain.** Pegasus `lvs_black_box`es `PVDD3A_G`/`PVSS3A_G` and `lvs_delete_cell_pin`s their
`TAVDD`/`TAVSS` bond plate, so the only pin compared on a supply pad is the CORE-SIDE one -- and
ANATOP part 3b walked `ANATOP_PT_APG`, one pad per rail per island, ten of the ring's twenty. Part
3b now walks `ANATOP_PT_APG_ALL` x `ANATOP_PT_ADOMAIN`, both emitted from the `PRCUTA_G` bracket
walk, so the pad list is the ring plan's and never a literal; the eight `_0` channel pads sit
exactly on their tile's M6 port x and take the cheap vertical form, and the east-island pads reach
their core-side port through an M4 L in the east routing channel, which is EMPTY by measurement (no
standard-cell row on this die passes x = 1840.6 against a pad band starting at 2170). Gate **C-G7**
is now one leg per analog supply pad and reports which pads have no core-side strap, so the flow and
`signoff_mp/padring_arcs_pt.py` state the same thing and can be compared without a cut.

**The second defect: the east bias island's M8 rails were isolated metal.** A union-find over
`chip_2mm_m`'s own floorplan DEF -- area overlap joins, a shared edge does not, which is Pegasus's
rule as this campaign measured it -- says `AVDD_B` is THREE conductors and `AVSS_B` THREE: the macro
strap plus one pad's plate; the island rail ALONE with no via on it; and the second pad's drop, also
vialess. All four `C12 -- ... drop` lines printed and gate C-G4 PASSED, because C-G4 counts SHAPES.
`editPowerVia -bottom_layer M6 -top_layer M8` must synthesise the M7 landing between two layers it
was given no metal on, and over that window it places nothing and says nothing -- the same silence
B10-32 found on the M2 neck. The vertical-row drop now draws an M7 patch and makes two single-level
calls, and **new gate C-G4b counts the built vias per drop** and FATALs with the database saved.

**The biasgen placeholder had the same class one level down.** `gen_anatop_biasgen_g_bbox.py`'s
`_touch` admitted a shared edge as electrically one, so the Y18 proof gate passed on four pins
Pegasus sees as TWO conductors each -- `AVDD`/`AVSS`/`VDD`/`VSS` each declare an M6 north tab at
y[336,340] and an M6 leg at y[strap,336] that meet on one line with zero overlap, and the pin TEXT
goes on the tab. Split into `_conn` (overlap, connectivity) and `_abut` (overlap or edge, the
cross-pin hazard); the per-layer boundary census moves `34:16 36:8` -> `34:4 36:16` with 74 texts
unchanged. The four bias outputs also lose their EAST M4 port and the north port widens 2 -> 4 um,
which deletes the 220 um M4 join leg that `bias_bnc` reached the `VSS` conductor through -- Y17's own
first prescription, taken in the form that gives the router MORE access on the side that works.

**O-L-1: the dead clock is fixed and its mechanism is measured -- it is not the mux cell.** `mclk`
in module `MCU` has exactly ONE driver, `system0` (`SYSTEM`) on `mclk_out`, and `SYSTEM` declares
`clk_mem` and `clk_mem_clone1..5` as INPUTS; six of the Y18 form's 94 collapsed endpoints landed on
them, so the transform wrote the clock root back into its own generator with no simulated time
between, through the `ClockMuxGlitchFree*` inside it. Eleven more landed on
`RC_CG_MOD_108060*.ck_in`. `zero_delay_clk_flatten.py` is rewritten with an admission-controlled
walk -- single-input inverter/buffer cells only, and an endpoint is collapsed only if every load is
another admitted cell's input, a flop clock pin, or a submodule/macro port that is neither a clock
gate/mux nor an instance driving the root -- every refusal counted and printed, and a post-write
self-check that re-measures both forbidden classes. It refuses 7, collapses 65 (was 94), and the
netlist RUNS: **4 / 14** with no TIMEOUT but `shtcm`'s own 647 s row, against 1 / 14 with eleven
TIMEOUTs. `--strict`, the literal rule, collapses ZERO cells on this chip and says so rather than
writing a no-op: at `MCU` level the clock tree is distributed to MODULE PORTS, so no inverter's
whole fanout is flop clock pins.

**And the leg's next mechanism is measured too.** The flattened leg passes HART2 and HART4 on every
multi-hart row and HART1 and HART3 on none, and the split is the transform's own output:
`hart2.clk` (`CTS_37`) and `hart4.clk` (`CTS_33`) are `assign mclk`, while `hart1.clk` (`CTS_17`)
and `hart3.clk` (`CTS_22`) are NOT COLLAPSED -- both hang below `CTS_73`, whose load list is
`CTS_cdb_inv_06801.A , CTS_ccl_inv_00430.A , system0.clk_mem_clone5`. ONE feedback load on an
eight-deep net stops the walk, so three cells below it keep their deltas. The next change is to
CLONE the refused net instead of refusing it. `GATE_ZERO_CLKFLAT` stays 0 and the two per-view SDF
legs remain the record.

**Both chip attempts are spent and there is no new cut.** `chip_2mm_n` (PENTA_DRCECO=1) and
`chip_2mm_n2` (PENTA_DRCECO=0) both FATALed at the WQ26c scoped-route gate on disturbed
neighbours -- 8 spread and **5 all inside `mcu0/i2c0`** -- where `chip_2mm_m` reported 0 on both
hold-ECO passes. So the DRC ECO is NOT the cause: it ran clean (42 markers, 20 router ECOs, 20
blockages created and deleted, no WARN; the other 22 are 12 weldable-and-skipped and **10 inside a
placed macro**, which is 10 and not the 8 Y18 read off the rule names) and the pair without it
failed identically. **O-K-2's blame moves off C-G20**, and Y16's attempt 1 having had 13 of its 21
disturbed nets inside `mcu0/i2c1` says what the real problem is: the I2C blocks are a congestion
hot-spot that the hold ECO's scoped route cannot perturb without leaving neighbours open, and
`chip_2mm_m`'s 0 is the accident. **The next step is in the WQ26c stage, not the geometry: after it
detects disturbed neighbours, add them to the selected set, re-run the scoped route and re-check.**
The stage already prints every name and already routes a selected set; the FATAL moves to "still
disturbed after one repair pass". Two bisection knobs are in for the alternative hypothesis --
`PENTA_PT_ALLPADS=0` (the Y18 strap set) and `BIAS_EAST_PORT=1` (the biasgen's two-port bias pins and
the east M4 access column, 850 um^2 of corridor M4 that dropping the east port blocked).
`chip_2mm_m` remains the cut of record and `castalia_B`; `PENTA_PT_CUT` is untouched; none of the
three allowed Pegasus LVS runs was spent, because neither attempt reached a GDS. Report
`tapeout_review/reports/Y19_chip_2mm_n.md`, `TOPOLOGY_B.md` section B.Q, DECISIONS D23.

### Y20, 2026-10-05: the tiles' AVSS pins were open at TWO joints, every gate that passed was blind to the chain, and the WQ26c repair pass converges

**The promoted library now says what it is, and the promotion gate enforces it.**
`castalia_B_chip_2mm_m/README`'s first line and the status block `castalia_B/PROMOTED.txt` copies
from it lead with NOT ELECTRICALLY COMPLETE and carry the number: `pg_island_conn.py` on that cut's
own floorplan DEF finds **SIX of the ten analog island nets with a block pin that reaches NO supply
pad at all** -- all four channel AVSS rails plus both east-island rails -- and the other four
reaching one pad of two, so **4 of 20 analog supply pads are on their island conductor**.
`promote_status_gate.sh` gained a third verdict, NOT_COMPLETE, tested before the timing verdict; the
old gate read that first line as CLOSED, which is how the cut was promoted. 34 unit checks, 0 fail.

**Y19-1 is closed at source and it was only half the defect.** `__jsep` is retired: both rails take
the halfway row between the macro edge and the pad row -- the only y at which a layer transition is
legal, because outside the 1.0 um band Innovus refuses a via over macro obstruction (IMPPP-528) --
and the two lateral runs are separated by LAYER, AVSS on M3 under AVDD's M5, clipped inside the band
and given its own M3-only route blockage (C14b). All eight jog straps now build vias at the row.
**Y20-2, NEW: the straight straps were open too**, at a zero-area M4-to-M4 joint (`pt_apg_m2_leg`
drew its M4 tab from `edge-0.5` and each strap's column stopped AT `edge-0.5`), so on chip_2mm_m
NEITHER AVSS pad of any channel reached its tile; the AVDD ones were saved by accident. The tab is
now co-extensive in y with the M2 neck, which adds no M4 territory.

**Y20-3, NEW: two M3 tracks do not fit in the 1.0 um band**, so one leg per channel rail cannot be
built at all -- 0.8 um usable against 0.4 + 0.1 + 0.4 -- and the flow states which. 16 of 20 pads
are core-strapped on `chip_2mm_n3` and every island rail reaches a pad. The real fix is Y19-2
remedy 3 (one M7 riser per island per rail from the pad-row M8 rail to the core-side strap, then
delete the core-side ball pin from the compare) and it is a cut of its own.

**Y20-4, NEW: a window via census cannot tell which transition it counted.** C-G7 reported 2 M2->M4
vias on a leg that had none, counting the M4-M5-M6 stack on the tile pin whose M5 landing reaches
into the neck window. `pt_apg_svia_count_lay` keys on the cut layer and all six call sites moved to
it.

**The acceptance moves to the chain (D24).** NEW gate **C-G4d** runs `pg_island_conn.py` on the
cut's own floorplan DEF two minutes into the flow and FATALs unless every island net's block pin
reaches a pad and every pad the flow declared strapped is on that conductor; it then overwrites
`out/<cut>.corestrap` with the MEASURED map, which is what the LVS collateral reads. The prober
proves connections now as well as isolation, because it expands each via instance into the real
metal its DEF `VIAS` entry describes instead of grouping vias by point.

**The WQ26c disturbed-neighbour repair pass is implemented, unit-tested and exercised on the tool.**
`wq26c_legal_repair` absorbs the disturbed neighbours into the selected set, routes those and nothing
else, re-checks and iterates to a bound, with the two tool calls handed in as command prefixes so
the unit test exercises the shipping code. It refuses on a set that stops GROWING as well as on the
pass count. 126 offline checks, 0 fail, armed with chip_2mm_n2's five `i2c0` names and chip_2mm_n's
eight. On the core flow of record's signoff database five deliberately opened `i2c0` nets were
absorbed and closed in ONE pass, 53 s, independently re-verified clean.

**The cut of record is `chip_2mm_n4`** (attempt 2 of 2; attempt 1, `chip_2mm_n3`, got past WQ26c --
the repair pass absorbed 9 real disturbed neighbours and converged in one pass, which is the first
time this chip cleared that gate with a non-zero disturbed list -- and FATALed at WQ27 on **Y20-5**,
Y19's east-island core arm reaching 4.65 um inside `mcu0/hart0/tile/ram0`, because Y19 justified the
arm's depth by measuring standard-cell ROWS and the obstacle is a MACRO; the arm's limit is now
derived from the macros in its own y band and `chip_2mm_n3`'s artefacts are kept as the
measurement). `chip_2mm_n4`: setup WNS **+0.040 ns / 0 violating of 36,927**, hold **0.000 / 0**,
**WQ27 PASSED with unwaived Short 0 of 62 waived**, WQ19 0 PG opens, RINGSUP 0 unsupplied arcs of 5,
**C-G4d PASSED -- all ten analog islands reach a pad from the block pin, 16 of 20 pads strapped**,
chipdrc **1726 with 31 real-geometry** (19 flow-drawn against chip_2mm_m's 32), ant25 **CLEAN**, LVS
**devices 0 : 0 over 7,966,772, pins 80 : 80, nets `*0 : 1`, shorts file EMPTY** with the single
residual the biasgen BLACK BOX's own layout net (W-PT1-1) and a **live negative control (4 : 0 on
one deleted std cell)**, GDS md5 `caaee67e1eb1fc606980df4f21c837d9`, promoted to `castalia_B` with a
headless proof at 259,828 instances in both libraries, `PENTA_PT_CUT` moved, five-scope P&R SDF
**14 / 14 at BOTH views**, zero-delay leg **5 / 14** with HART1-3 passing and only HART4 false (108
cells collapsed, SELFCHECK PASS) -- equal to the unflattened count, so `GATE_ZERO_CLKFLAT` stays 0
and the SDF legs remain the record.

**Two open items, each with its fix written down**: **Y20-3**, one leg per channel rail is
unstrappable because two M3 tracks need 0.9 um of the 0.8 um usable in the jog band, closed by
Y19-2 remedy 3 (an M7 riser per island per rail, which also closes the W-PT1-1 residual) and a cut
of its own; and **Y20-6**, 12 of the 31 real-geometry chipdrc results are a new same-net M5 class at
the AVDD strap's tile-pin column, closed by the WQ21 part-1 weld idiom in 8 shapes.
