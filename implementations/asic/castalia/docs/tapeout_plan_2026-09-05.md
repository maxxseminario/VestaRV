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
| **P15-1** TILE_ generic strip | **CLOSED.** `=> TILE_` with any suffix, plus a census that ENUMERATES what the staged generation emits, both in `genus/common/tcl/flow_gates.tcl` and called from all three assemblies. `genus/common/in/{penta_wound_hdl,penta_wound_pt_hdl}` re-staged from the current generator. Proven by both 30-minute cuts: 100 associations removed, 0 remain, elaborate clean |
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
