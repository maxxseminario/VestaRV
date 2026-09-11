# Castalia tapeout plan, 2026-09-05

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
| B2 | No analog interface in the tapeout netlist: `penta_wound.json` sets `cqAfeStubs=false`; 0 AFE instances in the Genus and P&R netlists; MCU has no analog ports; 8 `PDB3A_G` pads with no core connection. Each `anatop_pixel` needs 50 control bits, SAR clock and reset in, 11 bits out. | 02 B-1, 08 F5 | F7 (AFE2) |
| B3 | The assembled analog tops (`anatop`, `anatop_channel`, `anatop_pstat`, `anatop_controlamp`, `anatop_dacsupply`) are absent from the OA library since the 2026-08-26 write; no backup existed. `anatop_pixel` is the only assembled channel and has no routed layout. | 01 F1, 03 F-1 | new wave (section 5) |
| B4 | The four reserved analog windows cannot reach a pad or the core: the tile obstructs M1 to M8 over its footprint, all 281 tile pins sit on the centre-band edge, no pad faces a window. | 06 F7 | decision D17 |
| B5 | Signoff timing never ran on coupled-SI parasitics: wq22e used `setDelayCalMode -SIAware false` and `rc_decoupled`. Re-timed with coupled SI on 2026-09-05 (F6, read-only): setup WNS +0.012 ns (the quoted +0.239 was 95 % uncomputed crosstalk), hold WNS -0.003 ns at three `hart_tile` boundary inputs (`hart3/sh_rdata[19]`, `[27]`, `hart1/mtip_in`), still at 25 C RC corners. Five generated clocks were sourced with the wrong edge (ICGs fed by the inverted clock), handing crossing paths a phantom 20 ns. The tile's own signoff extraction aborted (`tech_file = ""`). | 06 F1 F2, 06a F2, F6 | F3, F6 |
| B6 | The synthesized RTL is not the simulated RTL: `hdl/common/MCU.vhd` (penta.json), `genus/common/in/penta_wound_hdl/MCU.vhd` (penta_wound.json, 733 diff lines) and `hdl/castalia/MCU.vhd` (older) are three variants; `NUM_IRQ_SRCS` 121 vs 124. | 04 F2, 08 F3 F4 | F7 (single config `penta_wound_afe`) |
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

Done: F1 to F10. Running: F11 (regression on `penta_wound_afe`), F12 (generated clocks,
resynthesis, LEC), F13 (`anatop_quad` wrapper, bench, LEF), F14 (SAR/DAC/pixel re-runs).

New facts from the fix waves:

- The `Better_ADCs` SAR flip-flop cells netlisted as empty subcircuits (never Check-and-Saved); every schematic-level SAR result before 2026-09-05 ran without the SAR logic. The `anatop_sar_*` copies netlist correctly and `px_zero.v_rdy_p` passes (F1).
- The mask ROM was re-cut (stack init contract, bounded flash-boot polls, WDT armed): new image `99b0c95d`, 7,532 of 8,192 B. The `rom2k_hvt_pg` plate must be recompiled before the next cut (F8, F11).
- 1201 sequential clock pins in `MCU_PENTA` (897 in soft logic, 108 in the orchestrator) and 44 in `hart_tile` have no clock waveform: the muxed and divided clocks were never declared, so those registers were never timed (F2; fix in F12).
- `hdl_error_on_latch` trips on two further RTL sites (`csr_unit.vhd:463`, `NFC.vhd:600`) beyond the three fixed in F9 (F2; fix in F12).
- Coupled-SI re-time of wq22e: setup +12 ps, hold -3 ps; five generated clocks were edge-wrong (F6).
- The JTAG bench carried a four-week-old stale `hartinfo` assertion; corrected, 16/17 then re-run (F9).
- The TRM republish path deleted the analog chapter under any `penta_wound*` config; fixed (F10).


| Wave | Scope | Report |
|---|---|---|
| F1 | Analog schematic repairs: ATP symbol, DAC drivers, local bias nets, mux re-pair, `Better_ADCs` and `tb_utils` snapshots, `TGNX2A` repoint, ADC grid snap. Additive only. | `reports/F1_analog_schematic_fixes.md` |
| F2 | Genus: debug restore + FATAL census, `check_design -all`, `check_timing`, `hdl_error_on_latch`, I/O constraints, clock fixes, hygiene. | `F2_genus_fixes.md` |
| F3 | `hart_tile` Innovus scripts: Quantus tech file, Wiring gate, `pg_clearance` provenance, `flash_clk_mem` source, SDC library names, LEF M2 stubs, `verifyPowerDomain`. | `F3_hart_tile_innovus_fixes.md` |
| F4 | Testbenches: SYSTEM_tb widths, dbg_dmi C5, pwr_ctrl at shipped generics, ten new GHDL targets, tile-ISA objdump gate. | `F4_testbench_fixes.md` |
| F5 | Signoff hygiene: cut-knob derivation and ingest guard, legacy-block fence, strmin gate, LVS negative control, ERC baseline, DRC waiver skeleton. | `F5_signoff_hygiene.md` |
| F6 | Chip Innovus flow: coupled-SI signoff setup+hold with hold ECO, corner temperatures, SDC generator, verification gates, fenced `ANATOP_INTEGRATION` block and 14-pad list. | `F6_penta_innovus_fixes.md` |
| F7 | AFE2 peripheral (RTL, generator, `penta_wound_afe.json` with Bazel gates, bench), pad-ring model, wrapper-netlist patch. | `F7_afe2_peripheral.md` |
| F8 | Boot ROM: stack init, flash-boot timeout and WDT, ROM image symlinks in gate sims, header contradictions, sidecars. | `F8_bootrom_fixes.md` |
| F9 | RTL: three latch sites, sensitivity lists, TIMER CDC, CLINT mtime race, irq_router, trstn path, fk51mp test contract. | `F9_rtl_fixes.md` |

### 4.1 Second-round waves (status at 18:30)

Done: F11 regression on the single-source RTL (147/147, verify_pentawound 157/157, cosim
8/8, JTAG at five harts 17/17 and 51 checks); F13 `anatop_quad` (4 x pixel + 200 shifter
bits + ATP grant; TB-09 top_op/top_mix/top_xtalk/top_pwr pass; placeholder LEF 760 x 240 um
at `innovus/common/shared/anatop_quad/`); F14 re-runs (1.63 V SAR span is the extracted
CDAC; AFE2 capture window safe with 50 ns margin at 20 MHz, 83 ns at 12 MHz; pixel
regression clean); F15 ROM signoff collateral from the re-cut plate, `make verify` on
`penta_wound_afe`, Bazel 112/112; F16 DAC driver (`anatop_and2_dac`, Ron 104/47 ohm vs
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
3. Resynthesis: `hart_tile` (latch fixes) then `MCU_PENTA` from `penta_wound_afe` with debug restored; LEC (Conformal) RTL vs netlist for both.
4. Tile re-harden with F3; chip re-cut with F6 and the `anatop_quad` LEF; coupled-SI signoff; `penta_era`; ingest + chipdrc + ant25 + LVS with the knobs moved to the new tag.
5. Analog layout: `anatop_tia_rprog`, `anatop_tia`, `anatop_pixel` (pin labels, on-grid ADC), `anatop_quad`; per-cell blockdrc v2.6_2a + ant25 + Pegasus LVS; `castalia_sign` builder; reference library for the SAR sub-cells in `strmin/reflib.list`; CDL into `lvs_include_chip_penta`.
6. Square-wave EIS verification through the real pixel: the SQ-00 to SQ-09 Maestro plan in `reports/02_eis_and_ada_interface.md` Part A3, plus READY width and data hold on the extracted converter.
7. Gate-level regression on the new netlist (cp5 was the last, two revisions stale); JTAG bench at NHARTS=5; the single-source harness alignment named in F9.
8. Documentation: republish the TRM from `penta_wound_afe`; errata list in `reports/09_docs.md` (18 items); ISCAS27 paper is a rev-1 draft, the fact-checked successor is `~/work/ieee/ISCAS27/latek/iscas27.tex`; `SIM_STATUS.md` rewrite.

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
external bias plus shifters, benches, LEF); B2 config `penta_wound_afe_pt`, the
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
and `MCU.vhd` byte-identical for `castalia`, `penta_wound_afe` and `penta_wound_afe_pt`.
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
configurations (`castalia`, `penta_wound`, `penta_wound_afe`, `penta_wound_afe_pt`,
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
