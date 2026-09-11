# Castalia AFE rev-2: block summary, 2026-09-06

One file for the slide deck. Part 1 = per-block specification tables (13 tables, each with condition and source per row). Part 2 = what it does, headline results, the firmware contract in one slide, topology A versus B, the figure inventory (26 TRM figures with their data paths), and limitations. Twenty-five specs are marked "not measured" with the bench that would measure them; never present those as results.

## Part 1: Blocks and specifications

Scope: every analog block that exists in OA library `castalia` and sits on the tapeout
path, topology A (`anatop_quad` of four `anatop_pixel`) and topology B (`anatop_ch` plus
the shared `anatop_biasgen_g`). One table per block. Every value carries its condition
(corner, temperature, view, Monte Carlo sample count) and its source.

Rules used throughout:

- Where the TRM analog chapter carries the number, the TRM value is quoted and its
  section cited (`~/vestarv/implementations/asic/castalia/analog/`, rendered in
  `~/vestarv/platform/common/latex/TRM/TRM.pdf`).
- Where a later campaign report supersedes the TRM, the later value is quoted and the
  supersession is stated in one clause.
- A spec never measured is written **not measured** with the bench that would measure it.
  Nothing is estimated.
- Unless a row says `av_extracted`, the value is schematic-level, pre-layout, no
  parasitics.
- **Pinned-passive caveat** (TRM page `p:pinned-passives`): the five-point corner set
  moves the sixteen transistor model rows only; the resistor, capacitor and MIM rows hold
  their typical sections. Every corner spread marked (†) below is the transistors alone
  and is a lower bound. The Monte Carlo (`castalia_pm_25`) does vary the resistors and is
  the honest process bound.

---

### 1.1 Class-AB amplifier `anatop_tia_amp_ab`, control-amplifier role (A1)

One cell serves as both A1 and A2. This table is the amplifier itself and the amplifier
driving a three-electrode cell. Corner columns are transistor-only (†); the corner offset
carries no statistical term and is an order of magnitude below the manufactured spread.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Open-loop gain A_OL | 82.77 dB tt; 79.88–84.94 dB over 5 corners (†) | open-loop bench, C_L 5 pF, C_c 500 fF, 2.5 V, 37 °C tt / 25 °C skew | TRM tab:ampab-openloop |
| Gain-bandwidth product | 22.781 MHz tt; 22.587–23.187 MHz (†) | same | TRM tab:ampab-openloop |
| Unity-gain frequency f_u | 22.474 MHz tt; 22.358–22.942 MHz (†) | unity-feedback loop probe, v_cm 1.25 V | TRM tab:ampab-unity |
| Phase margin, unity feedback | 73.43° tt; 72.76–74.26° (†) | same | TRM tab:ampab-unity |
| Gain margin, unity feedback | 8.81 dB tt; 8.12–9.75 dB (†) | same | TRM tab:ampab-unity |
| Systematic input offset | 0.622 mV tt; 0.456–0.649 mV (†) | corner run, zero statistical offset | TRM tab:ampab-offset |
| Input offset σ | **5.201 mV**, mean 0.583 mV, min/max −14.13/+15.71 mV | 200 samples, **process + mismatch**, `castalia_pm_25`, 37 °C, nominal corner | TRM tab:ampab-mc-offset |
| Offset yield vs ±1 mV | 12.0 % per channel, 0.0 % four-channel | same 200 samples, independent channels assumed | TRM tab:ampab-mc-offset |
| Output noise 0.1 Hz–100 kHz | 30.44 µV mean, σ 1.04 µV | unity feedback, 200 MC samples, 37 °C | TRM tab:ampab-mc-unity |
| Quiescent supply current | 121.03 µA tt; 111.14–141.34 µA (†); MC mean 123.42 µA, σ 16.80 µA | at the bench supply terminal, so amplifier (97 µA) **plus** its local bias generator (24 µA); one generator per channel | TRM tab:ampab-power, tab:ampab-mc-power |
| Dissipation | 302.57 µW tt; 277.85–353.34 µW (†) | 2.5 V | TRM tab:ampab-power |
| Output drive, sourcing / sinking | +2.224 / −2.159 mA tt; MC mean +2.224 mA σ 0.084, −2.158 mA σ 0.104 | load current at 50 mV output error, not a hard limit; 200 MC samples | TRM tab:ampab-drive, tab:ampab-mc-drive |
| Closed-loop output resistance | 1.811 Ω tt; 1.484–1.862 Ω (†) | slope at zero load | TRM tab:ampab-drive |
| CE compliance, ceiling / floor | 2.4622 V / 25.67 mV tt; MC σ 1.3 mV / 1.09 mV | measured at the electrode over a 0–2.5 V command sweep; independent of loop offset | TRM tab:ampab-compliance, tab:ampab-mc-compliance |
| Cell current delivered | 101.0 µA anodic, 102.0 µA cathodic | compliance limits divided by the 12 kΩ CE-to-WE resistance of **this** cell; does not transfer to another electrode | TRM tab:ampab-compliance |
| Loop gain into a cell | 72.24 dB tt; 71.85–74.11 dB (†); MC mean 72.13 dB σ 1.27 | Randles cell R_ce 1 k, R_u 1 k, R_ct 10 k, C_dl 1 µF, probe in the RE sense wire | TRM tab:ampab-cellstab |
| Loop crossover into a cell | 10.440 MHz tt; MC mean 10.497 MHz σ 1.523 | same; 10 dB below the unloaded figure because the cell loads a ~25 kΩ open-loop output | TRM tab:ampab-cellstab |
| Phase margin into a cell | 81.88° tt; 81.68–82.14° (†); MC worst 80.13°, 200/200 pass ≥60° | same | TRM tab:ampab-cellstab, tab:ampab-mc-cellstab |
| RE tracking error at zero current | −619.5 µV tt; −488.1 to −676.9 µV (†); MC σ 5.708 mV | offset-inclusive; this is A1's own offset carried to the electrode | TRM tab:ampab-tracking, tab:ampab-mc-tracking |
| RE worst tracking error over 0.4–2.1 V | 771.5 µV tt; MC mean 5.494 mV, worst 23.082 mV, yield 87.0 % vs 10 mV, 57.3 % four-channel | window frozen for every corner and sample | TRM tab:ampab-mc-tracking |
| RE load regulation at ±10 µA | −23.00 / +22.63 µV tt; MC σ 27.4 / 34.4 µV, 200/200 inside ±1 mV | zero-current error subtracted at the same corner | TRM tab:ampab-tracking, tab:ampab-mc-regulation |
| Slew rate | not published | bench view exists (`sch_tb_slew.tex`), never written up; it is an orphan fragment of the analog chapter | TRM AnalogChapter orphan list |

Run of record: `simarchive/tb_anatop_ctrl_amp_ab/ctrl_ab_2026-08-16/`.

---

### 1.2 Class-AB amplifier `anatop_tia_amp_ab`, transimpedance role (A2)

Same cell, closed transimpedance loop at the single R_f = 560 kΩ tap only. R_f is an
**ideal resistor** here, so no row carries the ladder's ±35 % tolerance; the real ladder
is Table 1.3.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Transimpedance Z_t at 1 Hz | 559.933 kΩ tt, −118.8 ppm from R_f; MC σ 0.01 kΩ | R_f 560 k, C_f 22 pF, C_L 5 pF, C_c 500 fF, BiasAdj 37, Randles R_s 100 Ω / R_ct 1 MΩ / C_dl 100 nF, 37 °C tt / 25 °C skew | TRM tab:tiaab-transfer, tab:tiaab-mc-accuracy |
| Signal bandwidth f_−3dB | 8.868 kHz tt; 8.651–9.149 kHz (†); MC mean 8.84 kHz σ 0.34 | same; 200/200 clear the 1 kHz floor | TRM tab:tiaab-transfer, tab:tiaab-mc-bandwidth |
| Gain peaking | 0.812 dB tt; MC mean 0.82 dB σ 0.23, max 1.52 dB | referred to Z_t(1 Hz); 200/200 clear the 2 dB ceiling | TRM tab:tiaab-transfer, tab:tiaab-mc-bandwidth |
| Loop gain at DC | 78.74 dB tt; 76.32–82.69 dB (†); MC mean 78.65 dB σ 1.23 | feedback probe, loop includes amplifier + network + electrode | TRM tab:tiaab-stability, tab:tiaab-mc-stability |
| Loop crossover | 9.375 kHz tt; MC mean 9.41 kHz σ 0.98 | same | TRM tab:tiaab-stability |
| Phase margin | 76.50° tt; 72.78–80.30° (†); MC mean 76.7° σ 5.2, worst 64.7°, 200/200 pass ≥45° | same | TRM tab:tiaab-stability, tab:tiaab-mc-stability |
| Gain margin | 21.81 dB tt; MC mean 22.06 dB on **167 of 200** samples | on 33 samples the loop phase never reaches the critical value, so no gain margin exists; those are held out, not failures | TRM tab:tiaab-mc-stability |
| Output offset at zero current | −0.967 mV tt; −0.762 to −1.056 mV (†); **MC σ 8.91 mV**, worst −28.46 mV | 200 samples process + mismatch, 37 °C | TRM tab:tiaab-accuracy, tab:tiaab-mc-offset |
| Offset yield vs ±5 mV | 48.0 % per channel, 5.3 % four-channel | same | TRM tab:tiaab-mc-offset |
| Gain error | −167.3 ppm tt; MC mean −171.7 ppm σ 23.1, 200/200 pass ±2000 ppm | central ±0.9 of full-scale input current | TRM tab:tiaab-accuracy, tab:tiaab-mc-accuracy |
| Integral nonlinearity | 0.021 LSB tt; MC mean 0.022 LSB, worst 0.051, 200/200 pass ≤0.5 | referred to the **nominal** 2.441 mV ADC LSB; multiply by 1.535 for converter codes (Table 1.5) | TRM tab:tiaab-accuracy, tab:tiaab-mc-accuracy |
| Total unadjusted error | MC mean 2.90 LSB σ 2.34, worst 11.72; yield 75.0 % vs 4 LSB, 31.6 % four-channel | correlates with abs(V_OS) at r = 1.000: it is the offset row in LSB, not an independent result | TRM tab:tiaab-mc-accuracy |
| Output noise 0.1 Hz–1 kHz | 1.690 mV tt; MC mean 1.696 mV σ 0.055 | noise analysis 0.1 Hz–10 kHz, 20 pts/decade | TRM tab:tiaab-noise, tab:tiaab-mc-noise |
| Input current noise 0.1–10 Hz | 68.23 pA tt; MC mean 68.5 pA σ 2.2 | output noise / R_f; scales inversely with the selected gain tap | TRM tab:tiaab-noise, tab:tiaab-mc-noise |
| Input current noise 0.1–100 Hz | 340.24 pA tt; MC mean 341.5 pA σ 11.0, 200/200 pass ≤2 nA | this band carries the 2 nA channel budget | TRM tab:tiaab-noise, tab:tiaab-mc-noise |
| Input current noise 0.1 Hz–1 kHz | 3.017 nA tt; MC mean 3.029 nA σ 0.098 | above the feedback/electrode impedance crossover the noise gain is set by C_dl, not R_f | TRM tab:tiaab-noise, tab:tiaab-mc-noise |
| Compensation capacitor C_F | 22 pF (`mimcap_sin` lt=wt=52.09 µm, mf=4, mismatchflag=1) | on the TIA summing node inside `anatop_tia`; verified in the executed netlist | report 01 verified-good |
| Effect of C_F on the loop | pm 92.30° → 83.99°, gm 28.02 → 9.76 dB, f_x 1.064 → 22.15 MHz; phase error at 5 kHz 0.265° → 1.049° | measured 2026-09-05 (SQ-00) against the archived 2026-08-25 run of the same tests. **Supersedes** the ±0.573° band edge at 5.3 kHz, which was measured on a bench with no C_F | SIM_STATUS §6.5 SQ-00; F17 |

Run of record: `simarchive/tb_anatop_tia_amp_ab/tia_ab_2026-08-16/`.

---

### 1.3 Programmable TIA feedback resistor `anatop_tia_rprog`

Two-terminal ladder measurements at a forced 500 nA, plus one in-loop noise run. The
corner axis here **is** the resistor family, so this is the one block whose ±35 % poly
spread is visible; the Monte Carlo is mismatch-only.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Law | R = 18 kΩ + 6 kΩ·N, N = bin(`ResEn<5:0>`) + 64·popcount(`ThEn<3:0>`), N = 0…319 | 325 `rppolywo` units (3 fixed + binary 1/2/4/8/16/32 + four thermometer segments of 64), each switched segment shunted by a CMOS bypass gate; active-high = insert | TRM §ss:tiarprog |
| R at N = 0 | 19.648 kΩ typ; 13.263–26.407 kΩ over 5 corners | typ = `castalia_typ_25`, 27 °C; corners ff-res/ss-res at 27 °C and ff/ss at −40/125 °C | TRM tab:tiarprog-corners |
| R at N = 63 / 64 | 396.182 / 403.601 kΩ typ | same | TRM tab:tiarprog-corners |
| R at N = 319 | 1.9308 MΩ typ; 1.2802–2.6064 MΩ | same | TRM tab:tiarprog-corners |
| Absolute tolerance | ±32 to 35 % across corners | poly sheet resistance; a calibration term, not a defect | TRM §ss:tiarprog |
| Monotonicity | 320/320 codes at every corner; step_min 5576 Ω typ, 3574 Ω worst corner, always positive | 320-code sweep at 500 nA | TRM tab:tiarprog-corners |
| Monotonicity under mismatch | 320/320 in 200/200 samples; minimum step 5470 Ω, 137 σ from zero | 200 samples, **mismatch only**, `castalia_pm_25`, 25 °C, seed 12345, LDS | firmware contract §1.2 [bgladder B1]; TRM tab:tiarprog-mc |
| Step spread | 5576–8509 Ω typ; the seam 63→64 is 7.419 kΩ | the large steps are at the four carry seams and are switch R_on, not the ladder. A gain measurement built from two nearby codes must not straddle a seam (63/64, 127/128, 191/192, 255/256) | TRM tab:tiarprog-corners; firmware contract §1.2 |
| Seam step under mismatch | mean 7.424 kΩ, σ 0.504 kΩ, 14.7 σ to zero, 200/200 pass | same 200 mismatch samples | TRM tab:tiarprog-mc |
| Relative mismatch σ/µ | 0.359 % at N = 0, 0.091 % at N = 63, 0.037 % at N = 319; gain ratio R(319)/R(0) 0.354 % | same | TRM tab:tiarprog-mc |
| Full scale, N = 0 | ±40.75 µA, 1 LSB = 81.2 nA | ±0.80 V TIA compliance against the **measured** R_f 19 630.4 Ω, converter LSB 1.591 mV. Three bases for this LSB are in circulation (81.2 / 88.5 / 79.5 nA), an 11 % spread | firmware contract §1.2; TRM §ss:tiarprog |
| Full scale, N = 63 | ±2.026 µA, 1 LSB = 4.04 nA | same basis, R_f 394.84 kΩ | firmware contract §1.2 |
| Full scale, N = 319 | ±415.7 nA, **1 LSB = 0.83 nA** | same basis, R_f 1.9243 MΩ; against a measured 48.9 pA of in-loop noise the max-gain floor is quantisation, not noise | firmware contract §1.2; TRM §sss:tiarprog-noise |
| Top-code compliance | ≈0.65 µA before the terminal voltage rails | v_cm 1.25 V on 2.5 V; the ±0.416 µA range fits inside it | TRM §ss:tiarprog |
| **R_on caveat, bottom code** | closed-switch stack 1.65 kΩ = +9.06 % at N = 0; drive nonlinearity 1.998 mV = **1.26 ADC LSB** at N = 0 against a 0.5 LSB budget, 0.0032 LSB at N = 63 and 0.0031 at N = 319 | chord over ±90 % of the ±0.8 V window, typ. Fails the 0.5 LSB spec at 4 of 5 corners (1.24 typ, 3.60 worst at ss 125 °C, 0.41 at ff −40 °C). Accepted: chord-resistance error stays 0.12–0.53 %. Firmware must not use the nominal law at N = 0; every code from N = 20 up is within 0.5 % | TRM tab:tiarprog-lin, tab:tiarprog-spec; firmware contract R11 |
| In-loop noise, ladder share | 0.0008 % (N = 0) to 0.0065 % (N = 63) of input-referred noise power in 0.1–10 Hz | real ladder inside the real TIA loop, 37 °C, C_dl 100 nF, R_u 100 Ω, R_ct 1 MΩ, C_f 22 pF, `castalia_typ_25`. Replacing the whole ladder by an ideal resistor of the measured value changes the answer by 0.02 % at worst | TRM tab:tiarprog-noise |
| In-loop stability | pm 74.94° (N = 63) to 92.86° (N = 319), gm 21.65–21.79 dB | same run, six gain codes, one electrode, one corner | TRM §sss:tiarprog-noise |
| Area | **no layout.** Reference pitch `anatop_eis_rprog_lpf2` (leon, 223 units) 110.85 × 206.48 µm = 22 888 µm² = 102.6 µm²/unit, so 325 units ≈ 33 400 µm²; devices alone are 352 µm², so a purpose-drawn row lands near 2 000 µm² | leon's cell is DRC density-only and LVS MATCH; the pitch choice moves the four-channel macro by ~125 000 µm² and is an open owner decision | F18-10; `~/vestarv/signoff_mp/ANALOG_LAYOUT_WORKLIST.md` §1.3 |
| Process + mismatch MC | **not measured** (mismatch-only today) | bench `tb_anatop_tia_rprog` test `rp_mc` re-run with `variations=all` on `castalia_pm_25` | TRM note_tiarprog_scope |
| Settling with the real switches | **not measured** | bench `tb_anatop_tia_rprog_noise` design pointer `tb_anatop_tia_amp_ab/TiaFbRprogTB`, transient step instead of ac/noise | TRM note_tiarprog_scope |
| Extracted R_on | **not measured** (no layout view) | needs 1.2/1.3 of the layout work list, then `analog_cell_signoff.sh anatop_tia_rprog pex` | F18; worklist §1.2–1.3 |

Run of record: `simarchive/tb_anatop_tia_rprog/` (`rprog_R_table.txt`, `summaries/`, `mc_psf/`).

---

### 1.4 12-bit reference DAC `anatop_pixel_dacR2R12` with driver `anatop_and2_dac`

Two independent defects: the ladder is matching-limited on an ideal rail, and the supply
block modulates the reference. The supply block was **deleted from the pixel** on
2026-08-24, so the reference rows below describe the standalone DAC bench, not the
tapeout channel.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Resolution / step | 12 bit; 610.35 µV per code (2.5 V / 4096); measured 610.2797 µV, σ 0.184 µV over 200 mismatch samples | ideal 2.5 V rail, `DacTB`, 25 °C, all 4096 codes, reltol 1e-6 | TRM tab:dacr2r12-ideal; firmware contract §1.4 |
| Zero scale / full scale | 89.98 µV / 2.499287 V tt | same; ideal endpoints 610.35 µV and 2.499390 V, measured LSB within 0.35 µV at every corner | TRM tab:dacr2r12-ideal |
| INL worst, nominal | **0.3756 LSB**, monotonic, all three specs pass | `DacNonlinTB`, `castalia_pm_25`, 25 °C, with the resized `anatop_and2_dac` driver. **Supersedes** the TRM's 0.417 LSB, which was measured with the 1.0 V `AND2X8MA10TH` cell | SIM_STATUS §6.4; F16-1; `simarchive/tb_anatop_pixel_dacR2R12/20260905_driverfix/` |
| DNL most negative, nominal | **−0.4234 LSB at code 2048**, monotonic | same; supersedes the TRM's −0.511 LSB | SIM_STATUS §6.4; F16-1 |
| INL / DNL by corner (old driver) | INL worst 0.399–0.425 LSB; DNL most negative −0.500 to −0.535 LSB (†) | 5 corners, 25 °C, endpoint-referred, no mismatch. Freed passives give −0.755 DNL / −0.617 INL | TRM tab:dacr2r12-ideal |
| INL yield <1 LSB | **20.5 %** per channel | 200 samples, process + mismatch, `castalia_pm_25`, seed 12345, LDS, 25 °C, all 4096 codes, 82 devices at mismatchflag=1, 234 random variables. Supersedes the TRM's 21.0 % | SIM_STATUS §6.4; TRM tab:dacr2r12-mc-ideal |
| **Monotonic yield** (DNL min > −1) | **42.0 %** per channel, **0.12 %** four-channel chip | same 200 samples. Supersedes the TRM's 40.0 % / 0.08 %; the F1-era broken driver gave 17.0 % / 0.002 % | SIM_STATUS §6.2, §6.4; F16-1 |
| Both graded | 18.5 % per channel | same | SIM_STATUS §6.4 |
| MC INL / DNL distribution | INL worst mean 1.490 LSB σ 0.625, worst sample 3.453; DNL min mean −1.737 σ 1.437, worst −6.608 | 200 samples, process + mismatch, 25 °C. A single 6.6 LSB step is 3.5 mV of lost command resolution that no constant recovers | TRM tab:dacr2r12-mc-ideal |
| **Driver R_on** | pull-up **104.14 Ω**, pull-down **47.27 Ω**, 10–90 % edge into a 2R leg 359.7 ps | (rail − V(Y))/10 µA, `castalia_pm_25`, 25 °C. Against `AND2X8MA10TH` 117.26 / 67.57 Ω and the F1 `anatop_and2` 333.55 / 232.32 Ω. W/L 100.0 (PMOS, 28 µm) and 71.4 (NMOS, 20 µm), l = 280 nm | SIM_STATUS §6.4; F16-1 |
| Why R_on is a linearity term | the pull-up/pull-down difference appears divided by a 2R leg and multiplied by 2048 at the MSB carry: 0.495 LSB for the removed cell against the 0.511 LSB of DNL it produced | mechanism, nominal | TRM note_dacr2r12_driver |
| **Reference modulation (with PSU)** | **25.700 mV pk-pk** tt, 25.7–29.6 mV over 5 corners, against a **133 µV** quarter-LSB budget: 190–220× over | `DacWPSUTB`, zero external load, 25 °C. Minimum at code 1365 = 0b010101010101 (the maximum-reference-current bit pattern) at four corners. MC: mean 25.835 mV σ 2.302, 0/200 meet the limit | TRM tab:dacr2r12-reference, tab:dacr2r12-mc-reference |
| Effect on linearity through the PSU | raw INL 32.5–45.1 LSB, raw DNL −9.8 to −18.4 LSB; ratiometric INL 0.43–0.45 LSB, DNL −0.52 to −0.54 LSB | 99 % of the raw nonlinearity is the reference modulation, not the ladder | TRM tab:dacr2r12-wpsu |
| Full scale / LSB through the PSU | 2.16484 V / 528.646 µV tt | `DacWPSUTB`. **Does not apply to the tapeout pixel**: both DAC supply regulators were deleted from `anatop_pixel` on 2026-08-24 and both ladders run from the 2.5 V analog rail directly | TRM tab:dacr2r12-wpsu; firmware contract §1.4 |
| Supply-block line regulation | 0.1253 V/V tt, 0.102–0.323 V/V (†); quiescent 158.05 µA tt | `DacPSUTB`, 2.25–2.75 V, zero load, 27 °C tt / 25 °C skew | TRM tab:dacr2r12-linereg |
| Supply-block load regulation | 1136.7 Ω tt (113.667 mV over 0–100 µA); Z_out(1 Hz) 902.5 Ω tt, flat to 100 kHz | `DacPSUTB`, ADE default tolerances | TRM tab:dacr2r12-loadreg, tab:dacr2r12-zout |
| V_PATTERN range in the pixel | 0.104 mV to 2.4217 V | assembled channel, both regulators deleted, returning 806.8 µW | firmware contract §1.4 [rebase §3(a)] |
| Settling time, glitch impulse, major-carry glitch | **not measured** | every published number is a DC solve: the code bus is a static `busset12`. Bench `tb_anatop_dacsettle` exists (1 test, 4 specs) and has never been run | TRM §sss:dacr2r12-scope; report 01 F9 |
| Disabled-state supply current | **not measured** in this run | the last figure, 59.45 µA against a 1 µA target, comes from a superseded setup. Bench `tb_anatop_pixel_dacR2R12` test `EnableTB`, added to the corner set | TRM §sss:dacr2r12-scope |
| Post-layout | **not measured.** Layout LVS **MISMATCH** since F1/F16: the layout still holds 12 `AND2X8MA10TH` + 4 `FILLTIE2A10TH` 1.0 V cells; the `av_extracted` view is a foreign inheritance from pingora and predates two schematic changes | re-place after `anatop_and2_dac/layout` exists, then `analog_cell_signoff.sh anatop_pixel_dacR2R12 pex` | F18-6, F18-2; SIM_STATUS §1.5 |

Run of record: `simarchive/tb_anatop_pixel_dacR2R12/20260905_driverfix/`.

---

### 1.5 10-bit SAR ADC `anatop_pixel_adc`

The only block characterised post-extraction, and it has to be: the capacitor array exists
only in layout, so the schematic view is a one-bit comparator. The span is 1.63 V, not
2.5 V, and 34.9 % of the nominal input range is unreachable.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Architecture | 10-bit single-ended charge-redistribution SAR, offset-binary about the V_CM code (509) | one per channel; the capacitor array is both sampling network and feedback DAC | TRM §ss:adc |
| Trigger clock | 20 MHz; one bit trial per **falling** edge | `SAMPLESTEP` 7 (AFE2 `CR[11:8]`, reset value); a 12 MHz alternative is verified | SIM_STATUS §2.4, §6.1 |
| Conversion period / rate | **1.1500 µs / 869.6 kSa/s** at 20 MHz; 1.9167 µs / 521.7 kSa/s at 12 MHz | extracted view, nominal, 37 °C; identical codes at both rates on all 20 staircase levels | TRM tab:adc-power; SIM_STATUS §6.1 |
| Conversion phases | clear 50 ns, sample 400 ns, convert 500 ns (10 pulses in that window) | the peripheral as delivered holds the convert phase statically high, giving one falling edge where ten are needed: READY then asserts every 4.600 µs (217.4 kSa/s) with **identical codes**. Stimulus defect, one commented-out line at `SARADC.vhd:260` | TRM §ss:adc; SIM_STATUS §2.4 |
| **Effective full-scale span** | **1.6274 V** (extrapolated code 0 at 0.4408 V, code 1023 at 2.0683 V), centred on 1.255 V | `av_extracted`, `adc_dc`, nominal, 37 °C, 2.5 V analog / 1.0 V digital | TRM tab:adc-transfer; SIM_STATUS §1.4, §6.1 |
| Fitted slope | 628.59 codes/V (ideal 409.60), ratio **1.535** | least-squares over 24 unclipped points, 0.0625 V steps, 0.5–2.0 V | TRM tab:adc-transfer |
| Effective LSB | **1.591 mV** (nominal would be 2.441 mV) | multiply every LSB figure elsewhere in this document by 1.535 to read it as converter codes | TRM tab:adc-transfer |
| Range lost to clipping | 34.9 %, split 0.441 V low and 0.432 V high | symmetric about V_CM, so a full-scale transimpedance swing truncates at both ends | TRM §sss:adc-transfer |
| Mechanism of the 1.535 | 1.235 (differencing CDAC: summed physical plate / summed weight) × 1.243 (top-plate parasitic + comparator input). The parasitic alone is 0.226 of the physical array | seven perturbation runs; two added top-plate capacitances predict the perturbed slope to 0.03 %. The larger factor is topology, not layout | TRM §sss:adc-transfer |
| Corner invariance | slope 628.13–628.73 codes/V, span 1.6271–1.6286 V, LSB 1.5905–1.5920 mV over 5 corners; monotonic 20/20 at every corner | the transfer is a ratio of extracted fixed capacitances, which the corner rows do not move | TRM tab:adc-corners |
| Residual about the fit | worst 0.52 LSB, rms 0.29 LSB | a 24-point fit at 39 codes per step. **This is not an INL** | TRM tab:adc-transfer |
| **DNL / INL per code** | **not measured.** No sweep grid resolves individual codes (0.25 V = 157 codes, 0.0625 V = 39, the corner staircase = 63) | bench `tb_anatop_pixel_adc` test `adc_ramp` on the extracted view with a full-code ramp. As saved it grades nothing: its stop time is a literal `16.389m` left over from the 1 MHz stimulus and its `t_rdy1` `cross()` expression errors, taking the results database read-only | TRM §ss:adc coverage; SIM_STATUS §6.1 |
| **READY pulse width** | **149.8 ns at 20 MHz, 249.8 ns at 12 MHz** (3 trigger clocks in both cases) | extracted view, 200 ps strobe, nominal, 37 °C | SIM_STATUS §6.1; F14-3 |
| **Data hold after READY rise** | **100.0 ns at 20 MHz, 166.7 ns at 12 MHz** (2 trigger clocks) | same. Outside the window every bit reads high and the bus returns raw 1023, which is indistinguishable from a real code | SIM_STATUS §6.1; F14-3; firmware contract R2 |
| Capture margin | `AFE2.vhd:371` captures 1–2 mclk after the rise: 25–50 ns into a 100 ns hold at 20 MHz, 41.7–83.3 ns into 166.7 ns at 12 MHz. Margins 50.0 and 83.4 ns; both safe | `AFE2.vhd:22` assumes hold ≥ 2 mclk, met with a factor of two | SIM_STATUS §6.1; firmware contract R2 |
| Bit 9 | inverted on the raw bus: usable code = raw + 512 − 1024·b9. AFE2 does this in hardware | rule R1 | firmware contract §1.1, R1 |
| Power, design rate | **18.09 µW**, 6.360 µA on the 2.5 V analog rail, **20.8 pJ/conversion** | extracted, nominal, 37 °C, averaged over one whole conversion, 63-code sweep step | TRM tab:adc-power |
| Power, stimulus as delivered | 12.95 µW, 4.737 µA analog, 59.6 pJ/conversion; digital 1.09 µA at 1.0 V and 2.0 nA at 2.5 V | 4.600 µs conversions | TRM tab:adc-power |
| Power by corner | 15.77–43.06 µW, analog current 4.79–15.43 µA, energy 18.1–49.5 pJ | 5 corners; the slow corner alone is a factor of two above the other four (leakage, not switching) | TRM tab:adc-corners |
| Current depends on the step | 6.36 µA on a 63-code step, 12.56 µA on a 220-code step | the switching term dominates; a converter current quoted without its code step is not comparable | TRM §sss:adc-power |
| **Gain and offset σ (die-to-die)** | **not measured, and not small.** A 100-sample process+mismatch MC on the extracted netlist returns σ = 0 on two of three input levels and reproduces the process-only run to every printed digit | extraction flattens the mismatch wrappers (5 of 6 mismatch parameters non-referenced), the array is 3308 linear capacitors with no statistical model, and the comparator's reference divider ships with mismatchflag cleared. Needs a schematic CapDAC bench built from the kit's statistical metal-fringe device: precedents `Cap_DAC_2V5D_Mismatch_Test`, `Cap_DAC_MOM_Pcell_Mismatch_Test`, and the castalia model-level `tb_anatop_cdac_mm` | TRM §sss:adc-mc |
| What the MC does establish | analog supply current σ 11.4 %, total power σ 10.5 % (10.5–16.4 µW); conversion timing identical in every sample | 100 samples, `variations=all`, `castalia_pm_25`, nominal corner, 37 °C | TRM §sss:adc-mc |
| Comparator reference divider | forcing its mismatch on gives σ 0.821 mV = 0.52 LSB on the converter zero, ±1 code, and 0.012 % on gain | 15 samples, mismatch only, mismatchflag forced to 1 on the eight `rppolywo` | TRM §sss:adc-mc |
| Model-level array matching | σ(DNL) at mid-scale 0.263 LSB, worst DNL over 300 × 1023 transitions −0.789 LSB, monotonic 300/300, σ(gain) 0.0145 %, P(missing code) 6.1e-5 per array | `tb_anatop_cdac_mm`, 300 MC samples: a model of the array, not the drawn metal | firmware contract §1.6 [cdacmm] |
| LVS | MISMATCH by exactly one instance: the schematic instantiates the CDAC as a hierarchical cell whose subckt is empty, the layout draws it flat. Identical to the rev-1 mismatch, silicon-proven, not a regression | Calibre v2.6_2a + Pegasus, 2026-09-05: 19:19 pins, 498:498 nets, devices 981:982, 0 unmatched on the layout side; DRC 3 results, all density | F18-5 |

Runs of record: `simarchive/tb_anatop_pixel_adc/20260905_sch_vs_ext/` (timing),
`simruns/adcchar_20260825/` (corners and MC, **not yet archived**).

---

### 1.6 Local bias generator `anatop_biasgen_local`

One per channel, inside `anatop_pixel`. Corner spreads here move the degeneration resistor
(the corrected `tab_biasgen_dcop_free`); the earlier pinned table reported a 0.30 µA I_DD
spread against the true 17.6 µA and is withdrawn.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Rails, standalone | V_BNM 614.3 mV, V_BNC 776.2 mV, V_BPM 1815.4 mV, V_BPC 1589.3 mV | tt, `BiasAdj` = 33, 25 °C. Corner spread 28.9–78.6 mV | TRM tab:biasgen-dcop |
| Rails, in-pixel | bn 0.6017977 V, bnc 0.7667792 V, bp 1.829275 V, bpc 1.599606 V | measured **inside `anatop_pixel`**, 37 °C, nominal, `Bias_Adj` = 37. These are 9–12 mV from the standalone set and are the values the channel actually runs on | B1-2 |
| Why the two differ | 27 → 37 °C (−7.5 / −1.8 / +8.4 / +0.2 mV) plus trim 33 → 37 (−3.4 / −7.3 / +3.8 / +10.0 mV); the two add to the whole delta | not a loading effect | SIM_STATUS §7.2; B9 |
| Trim nominal | **`Bias_Adj` = 37 at 37 °C**, which reproduces the in-pixel rails to ≤0.01 mV at 23.706 µA. Code 33 at 27 °C reproduces the published standalone rails at 24.4598 µA | the two are 4.7 % apart in reference current and are the same generator at two temperatures. Every channel bench runs at 37 °C, so 37 is the operating value | SIM_STATUS §7.2; B9 §1 |
| I_DD | 24.38 µA tt, 18.38–35.97 µA over 5 corners (17.59 µA spread) with the degeneration resistor freed | `BiasAdj` = 33, 25 °C | TRM tab:biasgen-dcop |
| Trim span | 39.87 µA on I_DD between codes 0 and 63; 2.7 % per code. Rail swing 89.6 mV (BNM), 198.2 (BNC), 98.9 (BPM), 283.2 (BPC) | tt; higher code = smaller current. ±½ code leaves ±1.4 % | TRM tab:biasgen-trim |
| Temperature coefficient | V_BNM 1248, V_BNC 215, V_BPM 453, V_BPC 17 ppm/°C; I_DD 1598 ppm/°C | tt, total variation over the swept range normalised to the mean (†) | TRM tab:biasgen-tempco |
| Temperature extremes | V_BNM 569.9–618.1 mV, V_BNC 766.3–777.1, V_BPM 1811.2–1865.4, V_BPC 1589.2–1590.9; I_DD 24.16–26.81 µA | typical corner, nominal supply, 23 points, 20–85 °C. Nothing bounds behaviour below 20 °C or above 85 °C | TRM tab:biasgen-temp-stats |
| Line sensitivity | V_BNM 0.30, V_BNC 0.53 %/V; (V_DD − V_BPM) 0.31, (V_DD − V_BPC) 0.61 %/V; I_DD 18.74 %/V | tt (†). The PMOS rails are supply-referred by design, so the supply-referred drops are what is quoted | TRM tab:biasgen-line |
| **Monte Carlo spread** | σ(bnm) 3.76 mV, σ(bnc) 10.61 mV, σ(bpm) 5.41 mV, σ(bpc) 12.95 mV; **σ(I_DD) 1.392 µA on 24.45 µA = 5.7 % 1σ** | first 200-sample MC on this block, `tb_anatop_bg_startup` rails, `variations=mismatch`, `castalia_pm_25`, 27 °C, `bias_adj` = 33 | SIM_STATUS §7.1; B8 |
| Untrimmed bias spread | σ/µ = 12.5 %, which the corner runs do not show: a self-biased loop is structurally corner-blind | the quantity the 6-bit trim exists to remove; 2.7 % per code against 12.5 % | TRM note_meas_biasgen |
| Poly-resistor contribution to that σ | 0.43–1.26 mV against rail σ of 3.7–13.0 mV | deck-level control with the 18 flags forced to 0. All 18 poly devices of this cell already carry mismatchflag=1, so no topology-A pixel MC is invalidated | SIM_STATUS §7.1 |
| Start-up | 101 of 101 corner points start, none into the degenerate state; settled operating point bit-identical over five decades of ramp rate | ramp rate ×5 decades, 5 process corners, 4 temperatures, 3 trim codes, plus a brown-out sweep and an enable cycle | TRM §sss:biasgen-startup |
| Settling time | V_BNM 0.85 µs, V_BNC 0.95, V_BPM/V_BPC 1.10 µs tt (1 % band); floor 211/232 ns at a 100 ns ramp, 487/641 ns at the slow corner | tt, 25 °C | TRM tab:biasgen-startup-time, tab:biasgen-ramp |
| Brown-out | no floor exists in 0–2.5 V: recovery ratio 1.000000 at thirteen dip depths and three hold times, including a 100 ms hold at 0 V | recovery edges slower than 1 ms are untested | TRM §sss:biasgen-startup |
| Enable | de-asserted forces V_BNM to 0.00000 V; on re-assert rails and supply current return to 1.000000 of their previous values at all six cells tested | the stronger test, and it passes | TRM §sss:biasgen-startup |
| Start-up-branch mismatch MC | **not measured, and not measurable as the cell stands**: the start-up devices sit on model cards with no per-instance mismatch terms, so a mismatch run reports zero from exactly the mechanism under test | needs the start-up devices moved onto `_macx` wrappers, then `tb_anatop_bg_startup` test `bg_su` with `variations=mismatch` | TRM §sss:biasgen-startup |
| Layout | 76.16 × 81.60 µm = 6 214.7 µm²; **LVS MATCH** since 2026-09-05 (three rev-1 Modgen dummies restored to the schematic; DC quantities identical to seven digits, settling moved 0.9 ns on a 10 µs transient) | Calibre v2.6_2a, DRC 9 results all density, antenna clean | F23; F18-4 |

Runs of record: `simruns/bgladder_20260825/` (trim matrix, **not archived**),
`simarchive/tb_anatop_bg_startup/20260906_mismatchflag/`.

---

### 1.7 Shared DAC-based bias generator `anatop_biasgen_g` (topology B)

New 2026-09-06: the rev-1 global generator with its four inherited rails brought out
through class-AB unity-gain buffers onto explicit pins. Every number is from standalone
spectre decks, nominal only; the cell has no authored Maestro setup and the cloned maestro
view still carries the start-up bench's variables and specs.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Composition | `anatop_biasgen_core_g` (rev-1 generator with four 14-bit `anatop_dac_g` DACs) + four `anatop_tia_amp_ab` unity-gain buffers + eight 500 fF compensation mimcaps + one `anatop_lvl_d10a25` for `en`; 15 terminals, `schCheck` (0 0) | schematic + symbol only | SIM_STATUS §7; B4 |
| Generator rails | bn 0.614697 V, bnc 0.777105 V, bp 1.814929 V, bpc 1.588046 V | `castalia_pm_25`, 25 °C, `use_dac` = 0, internal rev-1 buffers bypassed, real four-channel load | SIM_STATUS §7; B4 |
| Buffered outputs | bn 0.614126 V, bnc 0.776540 V, bp 1.814330 V, bpc 1.587462 V | same | SIM_STATUS §7 |
| **Buffer offset** | −571.5 / −564.6 / −598.9 / −584.5 µV (bn/bnc/bp/bpc) | same; −406 µV at −40 °C to −788 µV at 85 °C | SIM_STATUS §7 |
| **σ(buffer offset)** | **5.497 / 5.029 / 5.636 / 5.413 mV** | 200 samples, `variations=mismatch`, `castalia_pm_25`, seed 12345, LDS, 2068 random variables, after the mismatchflag fix | SIM_STATUS §7.1; B8 |
| σ(rail) | 6.642 / 12.085 / 7.482 / 14.939 mV; trim margin 4.35 / 10.18 / 4.67 / 12.84 σ; 200/200 inside the `Bias_Adj` trim range | same 200 samples. The mismatchflag fix on the 18 poly devices is worth σ = 0.42–1.22 mV of per-sample delta, under 1 % in quadrature: the spread is device-mismatch limited, not string limited | SIM_STATUS §7.1; B8 |
| AVDD current | 438.7 µA at 25 °C (390 µA of it the four buffers at 97.5 µA each); 419.2 µA at 37 °C, `bias_adj` = 37; σ 26.2 µA | `use_dac` = 0. Generator mode never leaves 435.8 ± 17 µA over −40 to 85 °C | SIM_STATUS §7, §7.1, §7.2 |
| Temperature drift of the rails | bn −0.764, bnc −0.178, bp +0.840, bpc +0.004 mV/K | −40 to 85 °C | SIM_STATUS §7 |
| Supply sensitivity | bn 1.31, bnc 3.36 mV/V ground-referenced; (AVDD − bp) 2.2, (AVDD − bpc) 5.2 mV/V supply-referenced | 2.25 to 2.75 V. bp and bpc track AVDD 1:1 by construction | SIM_STATUS §7 |
| **PSRR to 1 kHz** | bn 57.7 dB, bnc 49.7 dB (ground-referenced); bp 53.4 dB, bpc 45.9 dB (supply-referenced). All fall ~30 dB by 1 MHz | nominal | SIM_STATUS §7 |
| Output noise 0.1 Hz–1 kHz | 29.8 / 51.2 / 33.1 / 54.3 µV rms at the buffer outputs | the per-channel 20 kΩ / 5 pF RC is a 1.59 MHz corner and attenuates none of it | SIM_STATUS §7 |
| Start-up | all four rails track monotonically on a 100 µs supply ramp, settle within 1 % by 100 µs, zero overshoot, no latched-off state. Generator mode settles 1.26–1.74 µs after the enable edge; enable inrush 3.69 mA for a few microseconds | measured on a real ramp (B4's `t4_start.scs` had eight DC sources and no ramp) | SIM_STATUS §7, §7.2; B9 |
| **DAC-path caveat 1: not a fine trim** | stepping one 14-bit code by 1 LSB moves its own rail by −2.7 to +3.1 mV against a 130.2 µV ideal LSB, and moves the other three by up to 1.5 mV | all four ladders share one `DacPowerSupply` node (R_out 939 Ω, 16.8 mV of code-dependent droop) whose output follows the aggregate popcount of the 56 code bits: about ±22 LSB of local DNL. A step-and-keep firmware search will not converge | SIM_STATUS §7.2; B9 |
| **DAC-path caveat 2: no corner survival** | with the 25 °C codes applied, all four buffers rail to AVDD for T ≤ −25 °C and for AVDD ≤ 2.275 V; re-solving works but the codes move 4.8 to 22.2 LSB/K. Supply current reaches 1325 µA at 85 °C and 2035 µA at AVDD 2.75 V | the buffers take their own cascode bias from the rails they drive, and a DAC produces a ground-referenced `bp` where the mirrors need a supply-referenced one | SIM_STATUS §7.2; B9 |
| **DAC-path caveat 3: reset codes are a hazard** | with all four codes 0, asserting `USEDAC` drives the rails to 5 / 13 / 172 / 120 mV and the macro holds **1.20 mA, 2.7× nominal**, indefinitely, with a 4.3 mA peak. Clearing `USEDAC` restores the generator rails in 1.5 µs | forbidden by firmware rule R15 | SIM_STATUS §7.2; firmware contract R15 |
| Mission mode | **ship `use_dac` = 0**, `bias_adj` = 37 at 37 °C: 601.2 / 766.2 / 1828.6 / 1599.0 mV, every in-pixel target within 0.68 mV, at 419.2 µA, with no code at all | the 14-bit table (bn 0x1250, bnc 0x1754, bp 0x37A1, bpc 0x30A6 at 37 °C) is a bench override and a measured point solution that cannot be interpolated | SIM_STATUS §7.2; firmware contract R15 |
| Open: `bp`/`bpc` are supply-referenced | any AVDD IR drop between this macro and a channel is a direct PMOS bias error: 10 mV ≈ 12 % of mirror current (measured d(ln I)/dV = 12.3 /V) | topology A never had this, because the generator sits inside the pixel | SIM_STATUS §7; B4-1 |
| Open: offsets cannot be trimmed out | σ(buffer offset) 5.0–5.7 mV against trim steps of 1.42–4.47 mV, and the four offsets are independent while `bias_adj<5:0>` is one shared code | removing the per-pixel generator also removes the per-site trim | SIM_STATUS §7; B4-2 |
| Corners and process MC | **not measured** (the decks sweep temperature and supply instead; the MC is mismatch-only) | needs an authored Maestro setup on `tb_anatop_biasgen_g` with `castalia_cor.scs` and a `variations=all` run | SIM_STATUS §1.2, §1.5 |
| Layout | **none.** Placeholder LEF `innovus/common/shared/anatop_biasgen_g/`, 340 × 340 µm. `anatop_and2_dac` has no layout, so the four DACs cannot be laid out; `anatop_biasgen_r1` (the mismatchflag copy) is schematic-only and its two `INVX1` instances still point into `AFE_ECS` | | SIM_STATUS §7, §7.1; B4-6 |

Run of record: `simarchive/tb_anatop_biasgen_g/{decks,results,20260906_mismatchflag,20260906_codes}`.

---

### 1.8 Single-channel pixel `anatop_pixel`

The tapeout channel: A1 + A2 + `anatop_tia_rprog` + its own SAR + two 12-bit DACs +
local bias generator + two 16:1 multiplexers. Two benches feed this table and they are not
the same circuit: `tb_anatop_pixel` is **flat** (ideal R_f, ideal v_ref) and carries the
accuracy and stability grid; `tb_anatop_pixel_top` instantiates the real cell and is the
15-spec regression gate.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Sign convention | `vout = V_CM + i_we·R_f`; firmware reads `i_we = (vout − V_CM)/R_f` | measured and fixed; the simplan TB-07 formula inverts it | SIM_STATUS §2.1 |
| **Bipolar accuracy at R_f = 35 kΩ** | worst full-scale error **0.539 LSB** tt, 0.409–0.606 LSB over 5 corners (†) | flat bench, `i_we` swept ±36 µA (full scale 33 µA) into the R_ct = 10 kΩ electrode, 37 °C tt / 25 °C skew, error referred to the **nominal** 2.441 mV LSB (×1.535 for converter codes) | TRM tab:px-acc35 |
| **Bipolar accuracy at R_f = 560 kΩ** | worst full-scale error **0.333 LSB** tt, 0.253–0.376 LSB (†): the headline rev-2 accuracy figure | same bench, ±2.3 µA (full scale 2.06 µA) into the R_ct = 1 MΩ operational electrode | TRM tab:px-hg1m-acc |
| Zero-crossing error | −17.704 nA at 35 kΩ; −1.107 nA at 560 kΩ | same; no crossover kink, crossing slope = −1/T exactly | TRM tab:px-acc35, tab:px-hg1m-acc |
| Residual mechanism | finite closed-loop gain alone: zero-crossing slope error is −1/T to within 4 % at every tap (−0.00052 at 35 k to −0.00394 at 560 k) | typical point, 37 °C, R_ct held at 10 kΩ across the demonstration | TRM tab:px-hg-demo |
| **re_err, control loop** | zero-current tracking error **−0.620 mV** tt, −0.488 to −0.677 mV (†); worst over the fixed 0.4–2.1 V window **0.748 mV** tt, 0.646–0.814 mV | flat bench, v_ref swept 0–2.5 V, R_f 35 k, R_ce = R_u = 1 k, R_ct 10 k, C_dl 100 nF. All five corners clear the 1 mV limit | TRM tab:px-ctrl-tracking |
| **re_err, assembled cell** | `px_dc.re_err_max` **1.419646 mV** against a 2 mV budget | `tb_anatop_pixel_top`, nominal, 37 °C, real DACs and real ladder. 15 specs, all pass, 0 errored outputs, at nominal and all five corners. Supersedes the F14 value 1.419277 mV by the DAC driver resize | SIM_STATUS §1.4, §6.4; F16 |
| **Zero offset, assembled cell** | `px_zero.tia_offset` **−619.6736 µV**; `we_offset` −619.629 µV; `v_cm_dc` 1.249760 V | same run. It is the same 619.64 µV at every gain code, 0.3 nV of spread over all 320 taps, and the per-sample correlation between N = 0 and N = 63 is 1.000000000 | SIM_STATUS §6.4; firmware contract §2.1 |
| Control loop stability | loop gain 72.24 dB, crossover 21.475 MHz, PM 79.51° tt; PM 79.09–79.98° over 5 corners (†) | flat bench, same electrode | TRM tab:px-ctrl-stability |
| **PM over the electrode grid** | **89.3–93.3°** over all twelve R_f × C_dl × R_ct cells and all five corners, with **no C_F** | typical point, 37 °C, Randles R_u = R_ce = 1 kΩ, C_dl 0.1/1/10 µF, R_ct 10 k/1 M, R_f 35 k/560 k. TIA loop gain 46.68–82.23 dB over the same grid | TRM tab:px-grid-pm |
| PM with the real 22 pF C_F | worst 75.7° on the 24-point grid of the assembled cell | `simruns/rebase_20260824` on the 2026-08-24 cell. The 22 pF costs about 8° (SQ-00, Table 1.2), so the no-C_F grid above is optimistic | report 01 F9 |
| Noise over the grid | output 0.141–0.746 mV at 35 kΩ and 2.187–11.402 mV at 560 kΩ (0.1 Hz–1 kHz); input-referred 3.9–21.3 nA | typical point. Noise grows with C_dl, not R_ct: the closed-loop noise gain is e_n·(1 + R_f/Z_electrode) | TRM tab:px-grid-noise |
| Noise against budget | `in_rma` at 560 kΩ is 3.6–21 nA against a 2 nA budget, 2–10× over | published with its mechanism, not resolved | SIM_STATUS §3.2; report 01 F9 |
| Drive and compliance | CE ceiling 2.4804 V, floor 13.15 mV; cell current delivered ±52.5 µA; RE tracking range 2.382 V and TIA compliance range **0.805 V** (10 mV criterion) | flat bench, 5 corners. Both directions clear the ±33 µA limits by more than 50 %. The ±0.805 V compliance is essentially coincident with the converter's ±0.815 V window | TRM tab:px-ctrl-drive, tab:px-ctrl-range |
| Supply current, flat bench | 218.71 µA tt, 196.65–250.19 µA (†) | covers both amplifiers, both local bias generators and the shared global generator of that bench | TRM tab:px-ctrl-drive |
| **Power per channel** | **1.14 mW** (four channels 4.55 mW) | `anatop_quad` TB-09, nominal, 37 °C, extracted SAR, ideal rails. The 2026-08-24 assembled-cell figure was 1.3228 mW, of which `BUF_ATP` spent 243 µW driving a test port | SIM_STATUS §6.6; report 01 F6 |
| Monte Carlo, zero-current offset | σ(i_zero) 0.729 µA at 560 kΩ and 0.843 µA at 35 kΩ (0.729–0.843 µA over four taps); in LSB **12.09 / 43.45 / 95.71 / 167.33** at 35/140/315/560 kΩ | 200 samples × 4 gain taps, **mismatch only**, nominal process, **25 °C**, R_ct = 10 kΩ (the non-operational stiff electrode) | TRM tab:px-mc-izero, tab:px-mc-izero-allgain; SIM_STATUS §2.2 |
| Monte Carlo, RE offset | **σ = 5.7176 mV**, identical to five significant figures at all four taps | same. This is the loop's own tracking offset and is the clean gain-independent statistic | TRM tab:px-mc-rezero |
| Predicted offset at the operational electrode | ≈5.7 nA ≈ 1.3 LSB at 560 kΩ into a 1.001 MΩ cell | derived from the measured 5.72 mV, not measured directly | TRM tab:px-mc-rezero |
| Output rail under mismatch | `vout_zero` spans 0.21–2.50 V at 560 kΩ: some samples rail | bounds the range a V_CM-mux offset calibration must cover. A constant removes the current zero only while R_f/R_cell < 47.5 | TRM tab:px-mc-izero; firmware contract §2.1 |
| CV in the loop | commanded RE 0.749–1.749 V, working-electrode current −20.473 to +20.440 µA, unclipped | typical point, nonlinear electrode model | TRM tab:px-cv-stats |
| Step response | i_we −35.456 to +35.315 µA, CE 1.204–1.695 V, settling 49.0 µs | transient peaks on a rail-limited edge, not a sustained rating | TRM tab:px-step-stats |
| MC at the operational 1 MΩ electrode | **not measured** (corner data only) | re-run `tb_anatop_pixel` test `ps_mc` with `rct_we` = 1 MΩ | SIM_STATUS §3.2 |
| MC on accuracy, phase margin and noise | **not measured** (MC covers zero-current offset only) | add `ierr_lsb`, `pm` and `in_rma` as MC outputs on `ps_mc`, nominal corner only | SIM_STATUS §3.2, §5 |
| Power-down state | **not measured.** There is no channel enable: `BIASGEN`, `CONTROLAMP`, `BUF_ADC`, `BUF_ATP` and `TIAAMP` all tie `En` to `vdd!` | needs `En` pins on `anatop_tia` and `anatop_pixel`, then `px_pwr` with `En` = 0. The amplifier's own `En` = 0 state measures 0.2 nW | report 01 F6 |
| Layout | **none routed.** Only `layout_v1_floorplan`, 148.565 × 173.409 µm = 25 762 µm², 8 instances, 18 shapes, no routing, and it still places two `anatop_pixel_dac_psu` instances the schematic no longer has | must be redrawn, not extended | F18; worklist §1.5 |
| Bare globals | `anatop_tia`, `anatop_tia_rprog` and `anatop_pixel` tie a few nets to `vdd!`/`vss!`, which the macro's AVDD/AVSS pins do not carry at chip level. Simulation is unaffected; LVS is not | relabel to inherited-pin form before any pixel layout starts | SIM_STATUS §1.5; F13 finding 2 |

Runs of record: `simarchive/tb_anatop_pixel/` (flat bench, `rdb/Interactive.20` corners,
`Plan.0.Run.0` MC), `simarchive/tb_anatop_pixel_top/20260905_px_dc_px_zero/` (regression gate).

---

### 1.9 Pixel multiplexer slot map and calibration path

The slot map below is the state after the 2026-09-05 re-pairing. It is the **third**
version of this map: the firmware contract §1.3 and the TRM `note_pixtop_mux` fragment
describe earlier ones and are stale.

| Code | `ADC_MUX` (`SARADC_SEL<3:0>`) | `ATP_MUX` (`ATP_SEL<3:0>`) |
|---|---|---|
| 0 | V_OUT (transimpedance output, the normal readout) | WE |
| 1 | V_CM (converter zero, the origin of the current axis) | V_CM |
| 2 | WE | RE |
| 3 | V_CM | V_PATTERN |
| 4 | RE | CE |
| 5 | V_PATTERN (the commanded potential) | V_PATTERN |
| 6 | CE | V_OUT |
| 7 | V_PATTERN | V_CM |
| 8 | ATP | bp |
| 9 | V_CM | bpc |
| 10 | bp | bn |
| 11 | bpc | bnc |
| 12 | bn | vss! |
| 13 | bnc | DVDD |
| 14 | vss! | V_CM |
| 15 | DVDD | V_CM |

| Property | Value | Condition | Source |
|---|---|---|---|
| Tree | `anatop_amux_16` = `_4` = `_2`, so level-1 sibling pairs are fixed at (0,1) (2,3) … (14,15) | every pair above is now a tracking pair; the four bias-monitor slots are the real rails, which before had two mux inputs and no driver; zero floating nets remain in `anatop_pixel` | F1 step 4 |
| Off-state leakage | 0.05–0.07 pA within 1.00 V of the sibling, 0.37 pA at 1.125 V, **24.7 pA at 1.25 V** at 40 °C, against a 20 pA budget; 0.05 / 8.5 / 298 pA at 85 °C | gate-induced drain leakage in the off pass device. 300 pA into WE is 0.36 LSB at the top gain code | `simruns/muxchar_20260825`; firmware contract R4 |
| Charge transferred per select toggle | ≈0.13 fC per mV of pair difference (119 fC at 1 ns select edges, 830 fC at 20 ns) | make-before-break; a toggle of `SARADC_SEL<0>` shorts all eight sibling pairs at once | firmware contract R3 |
| Select-bit skew | 5 ns of skew swings the output the full 1.25 V through a third, unintended slot and stretches settling from 2.4 to 6.3 ns; 50 ns of skew stretches it to 51 ns | drive the four select bits of one tree from one shifter instance | firmware contract R3 |
| Channel settling after a slot change | **0.54 µs** (the TIA and buffer recovering, not the mux) | wait this plus the worst-case skew before sampling | firmware contract R3 |
| Slot 1 in operation | V_CM holds 1.249602 V, moves 0.433 mV pp while being converted, returns code 508 on all 32 conversions with a 0.051 LSB rms residual | measured 2026-09-05 on the tapeout pixel with the extracted converter, at 869 565 conversions/s. The 2026-08-23 collapse of the V_CM tap does **not** reproduce after the re-pairing | SIM_STATUS §6.5; F17 §9 |
| Floating pin current | a select input parked at its own threshold draws 2.5 µA per channel from the **analog** rail; twenty select bits is 51 µA | never leave the 1.0 V domain floating while the analog domain is live | firmware contract §1.1 |
| Calibration path | 10 stored constants; 8 measurable by the channel against itself through its own converter, 2 need the production tester (reference-DAC scale, transimpedance gain anchor). Under 128 bytes per channel at eight gain codes | correction order: invert bit 9, subtract the converter zero, scale by the per-code gain constant, subtract i·R_on of the WE switch, subtract R_s where an impedance sweep supplied it | TRM §ss:calibration; firmware contract §2 |
| Calibration residual | potential axis **1.38 mV rms** against 5.71 mV uncalibrated (0.65 mV quantisation + 0.93 mV droop-fit + 0.79 mV ladder INL in quadrature, over the 0.4–2.1 V window only); current axis **0.71 LSB plus 0.1–0.4 % of reading** against 12.1–167.3 LSB uncalibrated | design intent. **No calibration has been executed, in simulation or on silicon** | TRM §ss:calibration; firmware contract §2.4 |
| Calibration blockers | the isolation switches (C1), the A1 loopback switch (C2) and the on-chip gain reference resistor (C4) do not exist in any schematic; the converter input mux (C3) does exist, at 16:1 | design intent throughout | firmware contract §1.7 |
| Temperature dependence of every constant | **not measured**: no block has a temperature-resolved Monte Carlo, so how far a power-up re-measurement tracks a 37 °C operating point is unknown | needs MC at two temperatures on `tb_anatop_pixel_top` | TRM §ss:calibration |

---

### 1.10 Four-channel macro `anatop_quad` (TB-09)

Nominal only, and deliberately: the macro adds no device the block sections do not already
corner. The neighbour-disturbance row is **not** a crosstalk measurement, because this
bench has ideal rails and per-site bias and therefore no coupling path.

| Spec | Site 0 | Site 1 | Site 2 | Site 3 | Condition |
|---|---|---|---|---|---|
| Code returned, 10 µA at gain code 0 | 633 | 633 | 633 | 633 | 0 codes of spread |
| Transimpedance output | 1.449192 V | 1.449195 V | 1.449234 V | 1.449195 V | 42 µV of spread |
| Applied-potential error (RE − V_PATTERN) | −0.56 mV | −0.56 mV | −0.56 mV | −0.56 mV | reproduces the single-channel pedestal rather than adding to it |
| Working-electrode error (WE − vcm) | −0.59 mV | −0.59 mV | −0.59 mV | −0.59 mV | same |
| Mixed drive, current forced | +20 µA | −20 µA | +1 µA | −0.2 µA | simultaneous |
| Mixed drive, gain code | 0 | 0 | 63 | 319 | 107-fold of gain |
| Mixed drive, code about common mode | +257 | −247 | +244 | −245 | symmetric |
| Quiet-site output, site 0 stepping 40 µA | not applicable | 1.751 mV pp | 1.750 mV pp | 1.751 mV pp | 1.10 LSB; the same measure with **no** neighbour stepping is 2.1 mV pp |

| Property | Value | Condition | Source |
|---|---|---|---|
| Conditions | nominal corner, 37 °C, `castalia_typ_25`, SAR bound to `av_extracted`, 20 MHz trigger at SAMPLESTEP 7 (1.150 µs/conversion), ideal 2.5 V and 1.0 V supplies, one `randles_cell` per site | numbers read from the executed psf by `skill/quad_eval.py`, because the Assembler summaries came back empty (outputs created with `plot nil`); re-verified by a short `top_op` with 0 errored outputs and identical numbers | SIM_STATUS §6.6; F13 |
| Composition | 82 instances, 150 nets, 38 terminals (270 scalar pins); per site one `anatop_pixel`, five level-shifter groups carrying `afe_ctl_h<49:0>` from 1.0 to 2.5 V, an `ATP_SEL`-decoded grant and a pass gate onto the shared test pad | `schCheck` 0 errors, 0 unbound and 0 unconnected instTerms, 260/260 geometric stub audit | SIM_STATUS §6.6 |
| **Power** | **1.815 mA on 2.5 V, 14.2 µA on 1.0 V: 4.55 mW total, 1.14 mW per channel** | the 42.6 mA peak is start-up inrush into an ideal source, not an operating number | SIM_STATUS §6.6; TRM tab:quad-tb09 |
| **Crosstalk** | **not measured, and not measurable on this bench** | needs the post-layout supply and substrate network. The 1.1 LSB of neighbour ripple is each channel's own converter sampling its own output | SIM_STATUS §1.5, §6.6; TRM §ss:quad |
| Corners | **not measured** | `tb_anatop_quad` with `castalia_cor.scs` on all four tests | SIM_STATUS §1.1, §6.6 |
| Monte Carlo | **not measured**: `castalia_pm_25` is set on no quad test | same bench, nominal corner, `variations=all` | SIM_STATUS §6.6 |
| ATP park code | `MUX.ATPSEL` must reset to 0xF or both pixels of a pad pair drive the shared pad at once (tens of µA of contention). Fixed in RTL by F24 | two sites share each pad (0/1 on ATP0, 2/3 on ATP1) and the pixel's ATP buffer has no enable | SIM_STATUS §6.6; firmware contract §1.10 |

Netlist and full CDL: `simarchive/anatop_quad/`; runs `simruns/quad_20260905/` (**57 GB, not
yet archived**).

---

### 1.11 Per-tile channel `anatop_ch` and `anatop_pixel_xb` (topology B)

`anatop_pixel_xb` is `anatop_pixel` with the local bias generator deleted, `Bias_Adj<5:0>`
removed, and a 20 kΩ / 5 pF RC per rail; `anatop_ch` wraps one of them with the level
shifters and the ATP grant. Nominal only, 37 °C, no corners and no Monte Carlo.

| Spec | Value | Condition | Source |
|---|---|---|---|
| Terminals | `anatop_pixel_xb` 22; `anatop_ch` 17 (75 scalar bits): `afe_ctl<49:0>`, SAR clk/rst/rdy/d<9:0>, bn/bnc/bp/bpc, CE/RE/WE/ATP, AVDD/AVSS, VDD/VSS | `schCheck` (0 0) on `anatop_pixel_xb` modulo two pre-existing warnings; (0 errors, 7 warnings) on `anatop_ch`, all of them the six unloaded `Bias_Adj` shifter outputs | B1 §1, §2 |
| Per-rail RC | R = `rppolywo` w 400 n, l 9.0356 µm, mismatchflag=1, **20.000 kΩ**; C = `mimcap` lt=wt=15.58 µm, mf=10, **5.001 pF**. **f_c = 1.5912 MHz** | the four MIM caps sit between M7 and M8 and cost no placement area under the tile's M7/M8-only route blockage | B1 §1 |
| RC transparency at DC | bn −0.34 µV, bnc −0.087 µV, bp +1.19 µV, bpc −0.18 µV of drop: the four rails together draw **under 60 pA** | nominal, 37 °C | B1 §3 |
| Acceptance against topology A | `re_err_max` 1.419652 mV (+0.004 % vs A), `tia_offset` −619.6708 µV (+0.0004 %), `v_cm_dc` 1.249760 V, `adc_code` 512, `v_rdy_p` 0.9999747; all ten `px_dc`/`px_zero` specs pass | `tb_anatop_pixel_xb`, nominal, 37 °C, rails at the **in-pixel** values. Removing the local generator and adding the RC changes nothing measurable, provided the rails carry the right voltages | B1 §3.1 |
| Cost of the wrong rails | at the F23 standalone rails: `tia_offset` −664.686 µV (+7.3 %), `re_err_max` 1.626836 mV (+14.6 %) | this is why B1-2 retargets `anatop_biasgen_g` onto the in-pixel column | B1-2 |
| Operating point | code 635 (raw 123) at 10 µA, gain code 0; `vout` 1.449093 V, `vcm` 1.249601 V; code-implied current 9.97 µA against 10 µA injected; `re_err` −601.1 µV, `we_err` −632.6 µV, `atp_err` −601.0 µV | `tb_anatop_ch` test `ch_op2`, nominal, 37 °C, extracted SAR, 3 conversions. `anatop_quad` `top_op` at the same condition reads 633 | B1 §3 |
| Zero current | code 508, `vout − vcm` = −606.0 µV | `ch_zero` | B1 §3 |
| **Channel current** | **489.5 µA at 2.5 V = 1.22 mW** per channel | `ch_bias` nominal. Against the quad's 454 µA per channel with its own local generator plus 24.46 µA for that generator: the arithmetic closes to within 11 µA | B1 §3 |
| **External bias tolerance, −5 %** | `re_err` **−3541.5 µV** (5.9× nominal, outside the pixel's own 2 mV spec) and AVDD current **1017.9 µA** (double); the code moves only 4 LSB | all four rails ×0.95 (−30.6 mV on bn, −38.8 bnc, −90.8 bp, −79.5 bpc) | B1 §3 |
| External bias tolerance, +5 % | `re_err` −558.9 µV, `i_avdd` 469.6 µA: benign | all four rails ×1.05 | B1 §3 |
| **Budget** | the tolerance is asymmetric and the low side sets it: **stay above about −10 mV per rail**, not the ±5 % band | what has to meet this is the buffers' residual MC offset plus drift, since the per-rail DAC trim absorbs static offset | B1 §3; SIM_STATUS §1.5 |
| Ground-island difference | +5 mV between the generator's AVSS and the channel's costs 72 µV on `re_err`, 80 µV on `we_err` and **0 LSB** | the B3 PRCUT-isolated-island case: buffered voltages plus the local RC survive it | B1 §3 |
| AVDD-island difference | +10 mV on the channel's AVDD moves the code by **4 LSB** and the channel current by 6.8 % (489.5 → 522.6 µA) | consistent with the 12 % PMOS mirror error per 10 mV. **Partial stimulus**: the pixel's DACs are simulated from an extracted view that ties its PMOS rail to the bare global `vdd!`, so the DAC reference did not see the +10 mV. The true sensitivity is at least this large | B1 §3, B1-3 |
| AVSS-island difference | +10 mV moves `vcm` +5.0 mV and `vout` +5.3 mV, so `vout − vcm` and the code are unchanged. Costs 5 mV of ADC headroom, not accuracy | | B1 §3 |
| `ch_pwr` | authored but **not run** | `tb_anatop_ch` test `ch_pwr` (supply and per-rail bias currents, `p_total`, `i_avdd_pk`) | SIM_STATUS §1.2; B1 §3 |
| Corners and Monte Carlo | **not measured** on either cell | `tb_anatop_ch` and `tb_anatop_pixel_xb` with `castalia_cor.scs`, then `castalia_pm_25` | SIM_STATUS §1.2, §1.5 |
| Layout | **none.** Placeholder LEF `innovus/common/shared/anatop_ch/`, 480 × 230 µm = 110 400 µm², 75 pins, placed at tile-local (90, 640) R0; measured content ≈60 700 µm², so 1.8× headroom | digital pins south on M3, electrodes north on M4, M5 supply stripes with M6 edge tabs. B10 requires the macro layout to bridge its own M5 stripe to its M6 tab, or tile LVS reports a supply open that Innovus cannot see | B1 §4; worklist B10 requirement |

Runs of record: `simruns/ch_20260906/{ch_op2,ch_bias_*,pxxb2}` (**not yet archived**).

---

### 1.12 Electrode models

Two models, and they are simulation elements, not silicon. Neither carries a spread, so no
Monte Carlo σ anywhere in this document accounts for electrode-to-electrode variation,
which on a real wound interface is likely to exceed the process spread reported beside it.

| Model | Element | Value | Role | Source |
|---|---|---|---|---|
| `randles_cell` (three-electrode, linear) | R_ce | 1 kΩ | solution resistance, CE to RE | TRM tab:analog-models |
| | R_u | 1 kΩ | uncompensated resistance, RE to WE surface | |
| | R_ct | 30 kΩ | charge transfer at the WE interface | |
| | C_dl | 1 µF | double layer at the WE interface | |
| `randles_electrode` (single interface, linear) | R_s / R_ct / C_dl | 10 kΩ / 1 MΩ / 10 nF | not used by any bench reported here | TRM tab:analog-models |
| Overrides in use | R_u, R_ct, C_dl | 100 Ω or 1 kΩ; 10 kΩ or 1 MΩ; 100 nF, 0.2 µF, 1 µF or 10 µF | the value used is stated with every measurement; DC impedance into WE about 31 kΩ, falling toward R_u above roughly 5 Hz | TRM §ss:analog-models |
| Limitation | both linear models | no Warburg term, no potential dependence, frequency-independent elements | small-signal behaviour about a bias point only, and no element carries a spread | TRM §ss:analog-models |

| `electrode_bc` (Verilog-A, Butler-Volmer + diffusion) | Value | Condition | Source |
|---|---|---|---|
| Why it exists | a linear network cannot produce a voltammetric peak: its extrema stay pinned at the switching potentials whatever the element values. Kinetics alone give a sigmoid; the peak needs diffusional depletion | used only for cyclic and differential-pulse voltammetry; the linear cell remains correct for impedance work | TRM §ss:analog-electrode-bc |
| Numerics | 28 slabs per species on an expanding grid, h_0 = 0.5 µm, β = 1.280, δ = 1.79 mm; exponents clamped through `limexp` at ±40 | 8 slabs is unusable (i_p high by 232 %), 16 and above agree within 0.35 %; the max-time-step dependence is below the fourth significant figure | TRM §ss:analog-electrode-bc, note_electrode_valid |
| Defaults | E0 0 V, n 1, α 0.5, k0 0.1 cm/s, D 5e-6 cm²/s, A 0.01 cm², C_O* 1e-6 mol/cm³, C_R* 0, T 298.15 K | CGS units, as in the source literature | TRM tab:electrode-params |
| Validation, Randles-Sevcik | i_p runs high by +0.08 to +1.86 % over 25 to 400 mV/s; with C_dl removed the residual is −0.45 to −0.25 %, scan-rate independent, so the whole rate dependence of the error is double-layer charging | 25 °C, first cathodic scan, R_s 500 Ω | TRM tab:electrode-peaks |
| Validation, kinetics | at 50 mV/s, k0 = 0.1 cm/s gives Λ = 18.1, ΔE_p = 60.0 mV, i_p within 0.11 %; k0 = 1e-3 gives Λ = 0.181, ΔE_p = 167 mV, i_p 15.5 % low | walks the Matsuda-Ayabe progression correctly. With R_s and C_dl removed ΔE_p is 57.04 mV at every rate against Nicholson's 56.9 mV | TRM note_electrode_valid |
| In the rev-2 loop | peak 8.666 µA against 8.74 µA predicted, −0.8 % | pixel bench with the linear cell swapped out, ideal R_f 35 kΩ, C_dl 0.2 µF, R_u = R_ce = 1 kΩ, E0' 0.3 V, 1 mmol/L, k0 0.1 cm/s, 0.75–1.75 V triangle at 2 V/s, typical process, 37 °C. Peak moves the output 0.30 V, 38 % of the ±0.80 V window: unclipped | TRM note_electrode_afe |
| Design limit found | at 50 mV/s on 1 mm², double-layer charging is 0.74 % of the peak at 1 mmol/L but 37 % of a 27 nA peak at 0.02 mmol/L: below roughly 0.1 mmol/L the faradaic peak is buried in charging current, not in front-end noise. The remedy is a slower scan, not more gain | | TRM note_electrode_valid |
| Corners and Monte Carlo | **not measured**: nominal transients only, one process point, one temperature. A Verilog-A element carries no mismatch statistics | the analyte panel varies electrode parameters alone, as corners on the same test | TRM note_electrode_afe |
| Temperature | `tab_electrode_peaks` runs at 25 °C; the in-loop run is the only 37 °C result. `Temp` is a plain model parameter, so a new bench must set it explicitly or the kinetics silently revert to 25 °C. D is held at its 25 °C value, so the ~30 % rise in a real aqueous D over 25 to 37 °C is **not modelled** | | TRM note_electrode_afe |

---

### 1.13 Block areas

Measured bBoxes are read from the OA layout views by the 2026-09-05 63-cell
DRC/antenna/LVS sweep. Estimates are marked; the `anatop_tia_rprog` pitch is an open owner
decision that moves the four-channel macro by about 125 000 µm².

**Cells with a layout (measured).**

| Cell | Layout bBox | Area | DRC / LVS, 2026-09-05 | Source |
|---|---|---|---|---|
| `anatop_tia_amp_ab` | 42.46 × 43.14 µm | 1 831.7 µm² | 9 density, MATCH; `av_extracted` re-extracted from castalia geometry 2026-09-05 | F18; worklist §1.4 |
| `anatop_biasgen_local` | 76.16 × 81.60 µm | 6 214.7 µm² | 9 density, **MATCH** since F23 | F18; F23 |
| `anatop_pixel_adc` | 58.34 × 49.29 µm | 2 875.4 µm² | 3 density, MISMATCH by one CDAC instance (inherited, rev-1 precedent) | F18-5; worklist §1.5 |
| `anatop_pixel_dacR2R12` | 58.41 × 34.28 µm | 2 002.3 µm² | 9 density, **MISMATCH** (F18-6): the layout still holds 12 `AND2X8MA10TH` + 4 `FILLTIE2A10TH` | F18-6; worklist §2.1 |
| `anatop_pixel_dac_psu` | 93.75 × 35.34 µm | 3 313 µm² | 10 density, MATCH. No longer in the pixel schematic | F18 |
| `anatop_amux_16` | 22.13 × 24.12 µm | 533.8 µm² | 8 density, MATCH | F18; worklist §1.5 |
| `anatop_and2` | 7.53 × 4.26 µm | 32.1 µm² | 1 density, MATCH | F18 |
| `anatop_inv` | 2.22 × 4.18 µm | 9.3 µm² | 1 density, MATCH | F18; worklist §1.6 |
| `anatop_tgate` (TGP2A) | 3.81 × 4.47 µm | 17.0 µm² | 1 density, MATCH | F18 |
| `anatop_tgate_p16` / `_n16` | 12.07 × 4.475 µm | 54.0 µm² | 1 density each, MATCH | F18 |
| `anatop_mux2` | 7.35 × 4.47 µm | 32.9 µm² | 1 density, MATCH | F18 |
| `anatop_lvl_d10a25` | 2.22 × 25.875 µm | 57.4 µm² | 1 density, MATCH | F18; worklist §1.6 |
| `anatop_lvl_d10a25_x6` | 4.40 × 25.875 µm | 113.9 µm² | 1 density, MATCH | F18; worklist §1.6 |
| `anatop_lvl_d10a25_x14` | 8.76 × 25.875 µm | 226.7 µm² | 1 density, MATCH | F18; worklist §1.6 |
| `anatop_lvl_a25d10` | 2.22 × 9.155 µm | 20.3 µm² | 1 density, MATCH | F18 |
| `anatop_r2r14` | 58.59 × 46.90 µm | 2 748 µm² | 11 density, MATCH | F18 |
| `anatop_dac` (14-bit) | 46.90 × 66.41 µm | 3 115 µm² | 20 density, MATCH. Off the tapeout path in topology A | F18 |
| `anatop_biasgen` (rev-1 global) | 148.865 × 425.15 µm | 63 290 µm² | 15 density, MATCH. Dead per D4 | F18 |
| `anatop_eis_rprog_lpf2` | 110.85 × 206.48 µm | 22 888 µm² (223 units = **102.6 µm²/unit**) | density-only, MATCH. The pitch reference for `anatop_tia_rprog` | F18-10; worklist §1.3 |
| `anatop_pixel/layout_v1_floorplan` | 148.565 × 173.409 µm | 25 762 µm² | 8 instances, 18 shapes, **no routing**, and it still places two deleted PSU instances. Not a `layout` view, so it was not in the sweep | F18; worklist §1.5 |

Sweep totals: 63 cells with both views, **44 LVS MATCH, 19 MISMATCH, 0 blocked**; antenna
0 real results on all 63; every cell on the tapeout path is DRC density-only; max
single-cell DRC runtime 7 s.

**Cells that need a layout (estimated).**

| Cell | Estimate | Basis | Blocks | Source |
|---|---|---|---|---|
| `anatop_and2_dac` | ~160 µm² | 5× `anatop_and2` at 28 µm PMOS / 20 µm NMOS output stage | the DAC block's LVS, and therefore any pixel assembly | worklist §1.1 |
| `anatop_tia_rprog_sw` | ~68 µm² | 4× `anatop_eis_tgate_n2` (17.0 µm²) | `anatop_tia_rprog` | worklist §1.2 |
| `anatop_tia_rprog_sw8` | ~136 µm² | 8× the same | `anatop_tia_rprog` | worklist §1.2 |
| `anatop_tia_rprog` | **~33 400 µm²** at leon's pitch, or ~2 000 µm² purpose-drawn (devices alone are 352 µm²; leon's cell is 1 % fill) | 325 units × 102.6 µm²/unit | `anatop_tia`, and the whole macro size | worklist §1.3; F18-10 |
| `anatop_tia` | ~35 400 µm² raw, ~40 000 routed | amp 1 832 + ladder 33 400 + 3 mimcaps ~150 | `anatop_pixel` | worklist §1.4 |
| `anatop_pixel` | **~59 200 µm² raw, ~94 700 routed** (×1.6, the ratio the rev-1 single-channel top achieved) | tia 35 400 + biasgen 6 215 + 3 amps 5 495 + 2 DACs ~7 800 + ADC 2 875 + 2 muxes 1 068 + 6 mimcaps ~300 | `anatop_quad`, `anatop_ch` | worklist §1.5 |
| `anatop_quad` | **~440 000 µm²** (~95 600 per site + 15 % for shared rails, guard rings and the ATP bus); roughly 1 000 × 450 µm at leon's pitch | measured sub-cell areas | chip drop-in | worklist §1.6; F18-10 |
| `anatop_ch` | measured content ~60 700 µm² (excludes the four bias MIMs, which overlap under the M7/M8 blockage) | pixel 25 763 floorplan + ladder 33 400 + 25 dual shifter bits 1 437 + grant logic <100 | topology-B tile | B1 §4 |
| `anatop_biasgen_g` | not estimated | four 14-bit DACs cannot be laid out until `anatop_and2_dac` exists | topology-B tile | SIM_STATUS §7 |

**Placeholder LEFs.**

| Macro | Placeholder SIZE | Area | Status | Source |
|---|---|---|---|---|
| `anatop_quad` | 760 × 240 µm | 182 400 µm² | **~2.5× too small.** Its README derived the size from `anatop_tia_rprog` ≈ 1 200 µm², 28× low. Needs ~1 000 × 450 µm, which still fits the D17 corridor 1 330 × 881 µm. Regenerate with `skill/quad_lef_gen.py`, do not hand-edit: the two analog M5 stripes move with the north edge | F18-10 |
| `anatop_ch` | 480 × 230 µm | 110 400 µm² | 1.8× headroom over measured content; 75 pins; placed by B3 at tile-local (90, 640) R0 | B1 §4 |
| `anatop_biasgen_g` | 340 × 340 µm | 115 600 µm² | placeholder only | SIM_STATUS §7 |

**Extracted views.** Only two of the seven `av_extracted` views in the library were
produced from castalia geometry (`anatop_tia_amp_ab` and `anatop_pixel_dac_psu`,
re-extracted 2026-09-05). The other five are `dbCopyCellView` inheritances from teewinot,
pingora, leon and `potentiostat_final`. `anatop_pixel_dacR2R12`'s is the urgent one: its
schematic changed twice in one week, and both `anatop_quad` and `anatop_ch` simulate the
DAC from it, so every simulated DAC number in both topologies carries the 1.0 V drivers
and the bare-`vdd!` PMOS rail. (F18-2, F16-3, B1-3.)

## Part 2: System, results and figures

Deck source, 2026-09-06. Every number is traced to the artifact in the Source column.
Part 1 covers the topology and the block chain; this part covers what the front end does,
what it measures, the firmware contract, chip integration, the figure inventory and the
open items. "Not measured" appears where no run exists — nothing here is estimated.

Scope note applying to every table: the analog blocks are characterised at schematic level
except the SAR converter, the reference DAC and the DAC supply, which run from extracted
views and say so. No silicon exists, and no calibration has been executed in simulation or
on silicon. The 2026-08-21 ISCAS27 draft in `docs/publications/iscas27-castalia/` describes
the retired four-hart cut and the rev-1 unidirectional AFE; every AFE number in it is
copied from the Myshkin paper and is superseded by the tables here (ERRATA.md).

---

## 1 What the front end does

Four identical grounded-working-electrode potentiostat channels, each with its own
reference and common-mode DACs, feedback ladder, converter and local bias generator.
Modes are firmware programmes over one control surface; no mode adds hardware.

| Item | Value | Source |
|---|---|---|
| **Mode — amperometry / chronoamperometry** | DC current at a held potential; step response to a 400 mV potential step characterised at `Rf` = 35 kΩ, `Rct` = 1 MΩ | `fig_px_step_i.tex`; TRM §24.5.5 |
| **Mode — cyclic voltammetry** | Staircase CV through the complete channel: real 12-bit potential codes, real ladder at N = 3 (37.16 kΩ in loop), 4 mV treads at 2 V/s, 503 treads. Peak potentials within 0.3 mV (forward) and 2.3 mV (reverse) of the same electrode on an ideal source | `tab_pixtop_summary.tex`; `fig_pixtop_cv.tex` |
| **Mode — differential-pulse voltammetry** | 4 mV treads, 50 mV / 50 ms pulses at 200 ms period, 213 steps over −0.300 to +0.548 V (42.6 s), two samples 5 ms before each edge, `Rf` = 560 kΩ. Simulated on the electrode model, not through the assembled channel netlist | `fig_electrode_dpv.tex` |
| **Mode — square-wave EIS via the potentiostat** | Two-code square out of the real 12-bit reference DAC; boxcar demodulation in firmware. No EIS hardware (owner decision O2, EIS island dropped). Diagnostic band 1–5 kHz on the measured load | F17 §7; DECISIONS O2 |
| **Mode — calibration via the vcm mux** | `SARADC_SEL` = 1 converts the common-mode rail: code 508 on all 32 conversions, residual 0.051 LSB rms, `vcm` moves 0.433 mV pp under 869 565 conversions/s | F17 §9 (SQ-05) |
| **Channels** | 4, identical, simultaneously sampled (`CR.SYNC` → `trig_out`, ORed into every site's `trig_in`) | F7 §1; F13 |
| **Electrodes per channel** | 3 — CE, RE, WE. Plus one ATP analog test node per site (shared onto 2 pads in topology A, one pad per site in B) | D2; F13 §1 |
| **Gain codes** | `Rf` = 18 kΩ + 6 kΩ·N, N = 0…319 = binary(`ResEn<5:0>`) + 64·popcount(`ThEn<3:0>`); strictly monotonic over all 320 codes at every corner and in 200/200 mismatch samples | TRM §24.8; contract §1.2 |
| **Current full scale / LSB, bottom code** | ±40.75 µA at N = 0 (`Rf` measured 19 630.4 Ω in loop); 81.2 nA per converter code. The nominal law is +9.06 % wrong at N = 0 and firmware must not use it there | contract §1.2 (R11) |
| **Current full scale / LSB, top code** | ±415.7 nA at N = 319 (`Rf` 1.9243 MΩ); 0.83 nA per code, below the 2 nA in-loop noise floor, so the top codes are noise- and not quantisation-limited | contract §1.2; TRM §24.5.4 |
| **Sample rate** | 869.6 kSa/s design rate (20 MHz trigger, 23 clocks, 1.150 µs per conversion); 521.7 kSa/s at the 12 MHz pairing from a 24 MHz mclk; 217.4 kSa/s from the as-delivered stimulus file, which is a stale artifact and not the converter | contract §4; F14-2/F14-3 |
| **Converter resolution** | 10-bit SAR, offset-binary about the vcm code. Slope 628.593 codes/V, effective LSB 1.591 mV, window 0.4408–2.0683 V = 1.6274 V; 34.9 % of the 2.5 V span unreachable | TRM §24.7.1; F14-2 |
| **Converter linearity** | 0.523 LSB worst, 0.294 LSB rms against its own fitted line, 24 sampled points; a full INL/DNL needs every code and this grid does not provide one | `fig_adc_inl.tex` |
| **Supplies** | 2.5 V analog (AVDD/AVSS), 1.0 V digital core (VDD/VSS). Level shifting 1.0 → 2.5 V for 50 control bits per site lives inside the analog wrapper | D3; F13 §1 |
| **Power per channel** | 1.14 mW in the four-channel macro (1.815 mA on 2.5 V + 14.2 µA on 1.0 V, 4.55 mW total); 1.323 mW for the single assembled channel with the extracted converter, of which 487.1 µW is the two unity-gain buffers; 20.8 pJ per conversion at the design rate | F13 top_pwr; `tab_pixtop_summary.tex`; `tab_adc_power.tex` |
| **Digital interface — control** | 63 signals per site: `afe_ctl<49:0>` (1.0 V CMOS, pixel symbol order: 49:44 `ResEn`, 43:40 `ThEn`, 39:28 `A_Dac_Vp`, 27 `En_Dac_Vp`, 26:15 `A_Dac_Vcm`, 14 `En_Dac_Vcm`, 13:8 `Bias_Adj`, 7:4 `SARADC_SEL`, 3:0 `ATP_SEL`), plus `sar_clk`, `sar_rst`, `sar_rdy`, `sar_d<9:0>` | F7 §1; F13 §1 |
| **Digital interface — register set** | AFE2 peripheral, 9 words per site at 0x6C00 / 0x6D00 / 0x6E00 / 0x6F00: CR, SR, DATA, TIA, DACVP, DACVCM, BIAS, MUX, SWAP. ~254 flops per site; 4-entry FIFO tagged with `ADCSEL` and swap phase; reads never mutate state; ownership gate OWNER_HART or MGMT_HART | F7 §1 |
| **Digital interface — interrupt** | One vector, 124 (`IRQB_AFE`), `NUM_IRQ_SRCS` = 125; firmware demultiplexes on each site's SR. Four per-site vectors were rejected by the `irq_router` `NUM_SRCS <= 127` assertion | F7 §2 |
| **Digital interface — data path** | `f_sar` = `f_mclk` / (2·(CLKDIV+1)); capture 1–2 mclk after the READY rise; bit 9 inverted in hardware; DATA[9:0] CODE, [13:10] SEL tag, [14] swap phase, [15] VALID | F7 §1; F14-3 |
| **Pads, topology A** | 14 analog signal (CE/WE/RE ×4 + ATP0/ATP1) + 1 AVDD + 1 AVSS, contiguous on the north band, 2 `PRCUTA_G` ring breaks | D2; B10 §12 |
| **Pads, topology B** | 26 analog: 16 signal (CE/WE/RE/ATP per site) + 5 AVDD/AVSS pairs, five PRCUT islands, 10 ring breaks. 12 of the 26 are un-bonded die pads on LQFP-100 | TOPOLOGY_B B.5; B3 pad table; B10 §12 |

Caption: the control surface, ranges and rates of one AFE channel and the four-channel
array, with the source artifact for each row. DPV is simulated against the electrode model
rather than through the assembled channel netlist, and the 217.4 kSa/s figure is a stale
stimulus file, not a converter limit.

---

## 2 Headline results — the twelve numbers

| # | Quantity | Value | Condition | Source |
|---|---|---|---|---|
| 1 | Bipolar accuracy | 0.409–0.606 LSB worst full-scale across five corners; 0.21–0.30 LSB over ±2.3 µA | `Rf` = 35 kΩ into `Rct` = 10 kΩ, ±36 µA sweep, LSB referred to the nominal 2.441 mV step (×1.535 for real converter codes). Corner spread is a lower bound: passives pinned at typical | `tab_px_acc35.tex`; TRM §24.5.1 |
| 2 | Reference tracking error (`re_err`) | 0.672 mV over the specified 0.4–2.1 V window; 1.419 mV over 0–2.42 V; σ = 5.287 mV | Assembled channel, nominal point, 37 °C; σ from 200 process+mismatch samples. One stored per-channel constant leaves 0.36 mV inside the window and nothing outside it | `tab_pixtop_summary.tex`; `fig_pixtop_mc.tex` |
| 3 | Zero-current offset | −619.64 µV, spread 0.3 nV over all 320 gain codes; σ = 5.488 mV against a ±2 mV budget | Inert electrode. The gain-independence is what lets one measurement calibrate all 320 codes; the σ is why it must be calibrated per channel | `tab_pixtop_summary.tex`; contract §2.1 |
| 4 | Transimpedance phase margin | 75.7° worst of 24 electrode × gain points, 1.07 dB peaking; both buffer loops ≥ 78.4°. 72.37° at ss, not re-measured on the current cell | With the 22 pF `C_F`. The pixel-level 12-point grid without `C_F` reads 89.3–93.3°; the two are different circuits, not a discrepancy | `tab_pixtop_summary.tex`; `tab_px_grid_pm.tex` |
| 5 | EIS demodulator accuracy | +0.034 % magnitude, +0.078° phase at 1 kHz; ≤0.01 % / 0.01° attributable to the demodulator, two-code square and boxcar | Randles arc load (`Rs` 1 kΩ, `Rct` 10 kΩ, `Cdl` 3.18 nF), N = 20, one recorded period per frequency, converter idle. Everything above this is the instrument | F17 §7.1; `tab_eis_pixel.tex` |
| 6 | EIS extraction accuracy, `Rf·C_F` pole restored | `Rct` −0.01 %, `Cdl` +0.15 % at 1 kHz; −0.40 % / +0.38 % at 5 kHz | Ratio-calibrated record with `Rs` supplied, demodulated against `Zt` = `Rf`/(1+jω`Rf C_F`). Fails beyond 5 kHz (`Rct` −1.87 % at 10 kHz). With the firmware's own `Rs` = Re(Z) estimator, `Rs` is +22.7 % out | F17 §7.2 |
| 7 | Converter cost in an impedance record | +0.160 % of magnitude, 0.063° of phase; code stream reconstructs the analog input to 0.305 LSB rms, 0.740 LSB worst | 32 conversions per excitation period, 11.000 kΩ load, N = 20, extracted converter, `SARADC_SEL` static. The 16-conversion variant at 2× frequency gives +0.195 % / −0.150 °, which is the check that this is the converter and not the record length | F17 §8 |
| 8 | Four-channel simultaneity | 0 codes site-to-site spread — all four sites return code 633; transimpedance outputs agree to 42 µV. Mixed drive gives +257 / −247 / +244 / −245 codes for +20 / −20 / +1 / −0.2 µA across 107× of gain | 10 µA out of every WE at gain code 0, then per-site current, polarity and gain code simultaneously; nominal corner, 37 °C, extracted converter, 20 MHz trigger | F13 top_op / top_mix; `tab_quad_tb09.tex` |
| 9 | Neighbour disturbance (crosstalk bound) | 1.751 / 1.750 / 1.751 mV pp = 1.10 LSB on the quiet sites | Site 0 stepping 40 µA. **Not a crosstalk measurement**: the same 1.1 LSB appears with no neighbour stepping at all (2.10–2.13 mV pp on `top_op`), and this bench has ideal supplies and per-site bias, so it carries no coupling path. A real figure needs the post-layout supply and substrate network | F13 top_xtalk; `note_quad_tb09.tex` |
| 10 | Reference DAC linearity after the driver fix | Nominal INL 0.3756 LSB, DNL −0.4234 LSB at code 2048, 0 non-monotonic steps. MC: 42.0 % of channels monotonic (84/200), 20.5 % INL < 1 LSB, 0.12 % of four-channel chips | `anatop_and2_dac` 28 µm/20 µm 2.5 V driver (Ron 104.1/47.3 Ω against the 1.0 V cell's 117.3/67.6 Ω); 200 samples, `castalia_pm_25`, 25 °C, 82 devices at `mismatchflag`=1, none at 0. The residual spread is `rppolywo` ladder matching, not the driver | F16 §F16-1 |
| 11 | SAR span | 1.6274 V (0.4408–2.0683 V), slope 628.593 codes/V, effective LSB 1.591 mV | Extracted `anatop_pixel_adc`, identical at 20 MHz and 12 MHz. The span is the capacitor array, not the once-missing flip-flops: on the schematic view the empty CDAC returns code 0 below 1.25 V and 1023 above 1.5 V | F14-2; TRM §24.7.1 |
| 12 | Power | 4.55 mW for four channels = 1.14 mW per channel (1.815 mA on 2.5 V, 14.2 µA on 1.0 V) | `top_op` condition averaged over the last conversion, ideal supplies. The 42.6 mA peak is start-up inrush into an ideal source with no series impedance and is not an operating number | F13 top_pwr |

Caption: the twelve measurements that carry the rev-2 argument, each with the condition
that makes it readable and the run it came from. Rows 1 and 4 carry corner sets whose
passive model rows are pinned at typical, so their corner spreads are lower bounds; row 9
is a bound on an ideal bench and not a crosstalk figure.

---

## 3 The firmware contract in one slide

Fifteen rules, each with the measured cost of ignoring it. Full text and provenance:
`/home/mseminario2/chips/castalia/docs/afe_rev2_firmware_contract.html` §3.

| Rule | One line |
|---|---|
| R1 | Invert bit 9 of the converter bus first: `code = raw + 512 − 1024·b9`. Reading raw is a silent 512-code error over half the range (done in hardware by AFE2). |
| R2 | The bus is valid only in the READY window — 3 trigger clocks wide, data held 2 clocks (149.8 / 100.0 ns at 20 MHz). Outside it every bit reads high and returns code 511 with no error flag. |
| R3 | Wait after any multiplexer slot change: make-before-break shorts sibling pairs, and 5 ns of select skew swings the output the full 1.25 V through a third slot. Channel-level recovery 0.54 µs. |
| R4 | Keep every unselected slot near vcm, never more than 1 V from its level-1 sibling: leakage is 0.05 pA within 1.00 V, 24.7 pA at 1.25 V against a 20 pA budget at 40 °C. Tie spares to `V_CM`, not ground. |
| R5 | Choose an excitation code pair inside one octave: +0.06 % delivered amplitude, against −1.5 % across eight bits and −3.5 % at a top-bit carry. Working ±16-code pairs: 256/288, 512/544, 1024/1056, 2048/2080, 3072/3104, 3584/3616. |
| R6 | Use the two-level square, not a synthesised sine: identical impedance to five figures, 1.28× the fundamental for the same interface excursion, and −1.5 % of amplitude against the sine's −2.4 %. |
| R7 | Wait ≥100 electrode time constants before the record starts, and 5 × max(τe, `Rf·C_F`) per half period. `Rf·C_F` runs 0.43 µs at N = 0 to 42.5 µs at N = 319 and dominates: a wait in τe alone is short by up to 36×. |
| R8 | Derive the converter strobe and the excitation from one divider. A grid 0.35 samples per period out of step costs 0.6 % on a reactive load and reads correctly on a resistor. |
| R9 | Average with a boxcar, never by decimation: the n-th current harmonic is Z(f)/(n·Z(nf)) of the fundamental, so high orders fold into the fundamental bin (+4.95 % where the analysis says +0.03 %). |
| R10 | Averaging buys √N exactly over 4.2 decades and then stops at a deterministic quantisation bias (+1.94 %, identical at every N); only a ratio against a known impedance removes it. |
| R11 | Do not use the nominal `Rf` law at the bottom gain code: +9.06 % at N = 0, within 0.5 % from N = 20 up. Store gain constants per code. |
| R12 | Gain-range against the double-layer charge, not the settled current: the binding constraint is `Cdl`·ΔV ≤ `C_F`·headroom. At ±16 codes and N = 20 the ceiling is ~1.7 nF; 10 nF rails both supplies while the settled current is 1.88 µA. |
| R13 | Do not take `Rs` as Re(Z) at the top sweep frequency: +9.92 % structural bias before any measurement, +22.7 % with it, and it propagates into `Rct` and `Cdl`. Fit `Rs`, `Rct`, `Cdl` jointly over the sweep. |
| R14 | Demodulate against `Zt` = `Rf`/(1 + jω`Rf C_F`), not `Rf`: the nominal law carries +1.159° at 1 kHz and +52.3° at 50 kHz at N = 20. Restoring the pole leaves 0.07° at 1 kHz. Supersedes the ±0.573° band edge at 5.3 kHz, which was measured with no `C_F`. |
| R15 | Topology B only: write `AFE0BIASGCR` = 0x0000250A (ENGEN, EN, ADJ = 37) first, confirm the four rails (601.2 / 766.2 / 1828.6 / 1599.0 mV at 37 °C, 419.2 µA), then leave USEDAC alone. Every bit resets to 0, which leaves the generator off and nothing on the die meaningful. |

Caption: the fifteen firmware rules condensed to one line each, in the order of the
contract. R7, R12, R13 and R14 were added or amended on 2026-09-05 from measurements
through the real pixel; R14 supersedes the published ±0.573° band edge, which was taken on
a replica bench carrying no feedback capacitor.

---

## 4 Chip integration: topology A against topology B

A places one `anatop_quad` macro in the north-centre corridor; B puts one `anatop_ch` in
each hart tile's corner notch with a shared buffered bias generator in the corridor. The
two are not at the same stage: A has taken twelve chip cuts and no tile re-harden, B a tile
harden and no chip cut. Each row says which level it is measured at.

| Axis | Topology A (d13a) | Topology B (pt1) |
|---|---|---|
| **Analog macro silicon** | one `anatop_quad`, 1000 × 450 = 450 000 µm² (F18 measured ~440 000 µm²; the placeholder LEF was regenerated at that size) | four `anatop_ch` at 480 × 230 = 110 400 µm² each (441 600, inside the tiles) + one `anatop_biasgen_g` 340 × 340 = 115 600 µm² = 557 200 µm² |
| **Corridor cost at chip level** | 450 000 µm², 65.1 % of the macro-legal corridor box | 115 600 µm², 3.4 % of it — the four channels cost the corridor nothing |
| **Die / tile area** | die 3000 × 3000 µm; tile is a U polygon, 305 400 µm² | die identical, no edge moved; tile is a full rectangle, 580 800 µm² (+275 400, the notch reclaimed) |
| **Tile utilisation** | Density #1 76.480 %, #3 97.611 % | Density #1 55.975 %, #3 57.533 %, place density 20.145 %. Pure gate density is identical at 98.219 % in both, so B's larger tile is exactly the macro and its keep-out (PLAN §4.5) |
| **Analog pads** | 14 signal + 2 supply, 2 `PRCUTA_G` breaks, 83 of 100 balls used | 16 signal + 10 supply (5 pairs), 10 breaks, 93 of 100 balls used; 12 pads un-bonded, package option R1 moves 11 south digital pads north, S1 gives the south I/O its post-driver supply |
| **Electrode route length** | 14 nets, ~60 µm vertical from the north pad row to the macro's M4 pins at y = 2630, plus a lateral component across the macro's 1000 µm width | 16 nets, **49.2–53.2 µm purely vertical, zero lateral** — each island is centred on its tile notch's x centre |
| **Bias distribution** | none at chip level: bias is local inside each `anatop_pixel` (D4) | 4 shielded NDR rails from `anatop_biasgen_g0`, 7524 µm per rail, 30.1 mm total, with a local RC (≈20 kΩ / 5 pF) per channel. Rail targets are the in-pixel values (bn 0.6018, bnc 0.7668, bp 1.8293, bpc 1.5996 V); rails 5 % low push `re_err` to −3.5 mV and double channel current, so buffers are budgeted at about −10 mV per rail |
| **Analog supply islands** | one AVDD/AVSS pad pair, one PRCUT island, `TAVDD`/`TAVSS` separate LVS ports, no on-die join | five pad pairs and five PRCUT islands joined into one on-die net pair by an M7/M8 ring in the pad row over the PRCUT brackets, `ANARING_W` 8 µm → 6.6/6.7 Ω generator to farthest tile; a 5 mV ground-offset sensitivity case is recorded as a caveat |
| **Setup timing** | **chip**, coupled SI, 4-view MMMC: WNS +0.083 ns, 0 violating of 30 515 | **tile**, coupled SI: WNS +0.353 ns, 0 violating of 4642 |
| **Hold timing** | **chip**: closes at attempt 12 — WNS +0.001 ns after seven flow fixes (attempt 7 was −0.035 ns, 4 violating after two ECO passes) | **tile**: WNS +0.037 ns, 0 violating, no ECO needed |
| **DRC** | **chip** GDS `MCU_castalia_penta.d13a.gds2` (md5 5b6ebe3e); chipdrc 1900 = 1518 pad-kit ESD (waived class) + 64 density (fill deferred) + 62 carried real + 256 new `PO.R.8` floating-gate in the row band under the macro, root cause in progress | **tile** blockdrc 18 = 17 density + 1 real `M6.S.2.1`; ANT 0 of 714 rule checks. A's tile of record ships two spacing violations, B's zero |
| **LVS** | **chip** mismatch only from the schematic-side `anatop_quad` stub not reaching the Verilog reader (collateral fix) | **tile** devices 551 388 : 551 388, pins 356 : 356, unmatched 0, `anatop_ch` matched as a black box; residue 22 layout nets from the always-on buffers' supplies, cause found (CPF `PD_AO` list) |
| **Status of the cut** | chip cut d13a **closed** 2026-09-06 12:41 after twelve attempts; d13b re-cut for the `PO.R.8` root cause | tile `hart_tile_pt` **hardened** (attempt 30); **no chip cut taken** — every chip-level row above is empty for B |

Caption: topology A and topology B side by side, from PLAN §4.4a and §4.5 and the B10
comparison table. The comparison settles that B's tile is buildable and that the per-tile
macro costs the corridor 115 600 µm² instead of 450 000; it does not settle chip hold
closure, which is the number deciding A and which B has never measured.

---

## 5 Figure inventory

Fragment files live in `/home/mseminario2/vestarv/implementations/asic/castalia/analog/`;
`data/` paths are relative to that directory; `figures/` paths are relative to
`/home/mseminario2/vestarv/platform/common/latex/TRM/figures/`. "On disk, not input" means
the fragment is complete and unedited but its `\input` line was removed by an owner-ordered
cut — restoring it to a deck costs nothing.

| Figure | Fragment | Renders from | What it shows | Caption caveat | TRM status |
|---|---|---|---|---|---|
| Staircase CV, assembled channel | `fig_pixtop_cv.tex` | `data/pixtop_cv_{fwd,rev}.dat` | Voltammogram taken through real 12-bit potential codes and the real ladder at N = 3, 2 V/s, 37 °C | Sampled peak heights are 11.2 % / 13.9 % low — staircase sampling, not a channel error; sign convention is `dvout/di = +Rf`, so oxidation reads negative | On disk, not input (whole assembled-channel section commented out 2026-08-26) |
| Pixel-level CV loop | `fig_px_cv_voltammogram.tex` + `fig_px_cv_potential.tex` | `data/px_cv_voltammogram_tt.dat`, `data/px_cv_potential_00.dat` | Current against commanded RE potential, one triangular sweep, `Rf` = 35 kΩ, `Rct` = 1 MΩ | The loop is an ellipse because `Cdl` carries a d`v`/d`t` current on top of the faradaic one; current stays unclipped over the whole sweep | Input (TRM Fig. 24.35–24.36) |
| Monte Carlo tracking error | `fig_pixtop_mc.tex` | `data/pixmc_track_{sigma,res}.dat` | σ of `V_RE − V_PATTERN` against commanded potential, 200 process+mismatch samples, before and after one stored constant | Residual is zero at mid-code by construction; inside the 0.4–2.1 V window the error is a pure constant to 0.36 mV, outside it A1's input pair leaves its common-mode range and no constant reaches it | On disk, not input |
| Zero-current MC | `fig_px_mc_izero_35k.tex`, `fig_px_mc_izero_560k.tex` | `data/px_mc_izero_{35k,560k}_00.dat` | Zero-current output offset at two gain taps, mismatch only, 200 samples | Axis is the nominal 2.441 mV LSB; multiply by 1.535 for real converter codes. At 560 kΩ the LSB spread is 14× wider for the same offset current, and some samples reach the output rails | Input (Fig. 24.38–24.39) |
| Bipolar accuracy crossing | `fig_px_xover_ierr.tex` | `data/px_xover_ierr_00.dat` | Accuracy error across the ±36 µA sweep at `Rf` = 35 kΩ; the zero crossing is smooth | Slope through zero is −1/T exactly; the same feedback path serves both polarities, unlike the rev-1 mirror. LSB is the nominal 2.441 mV | Input (Fig. 24.32) |
| Input-referred noise vs gain | `fig_pixtop_noise.tex` | `data/pixtop_noise_{lsb,sig1,sig1_lsb,tread,tread_lsb}.dat` | Noise in current and in LSB against gain code, 16 codes | σ_tread is the exact Dirichlet integral over the 2 ms tread, not σ₁/√N, which is wrong by up to 6.7×. One sample is never better than 3.4 LSB, so the readout average is part of the specification | On disk, not input |
| EIS Nyquist arcs | `fig_eis_nyquist.tex` | `data/eis_nyq_{fresh,typical,fouled}_{true,meas,dec}.dat` | Measured arcs against analytic impedance for three electrode models, 0.01 Hz–100 kHz, 20 points/decade, gain code 0 | **Three panels have independent scales** (1 MΩ / 100 kΩ / 10 kΩ) and equal axes. Agreement 0.44 % / 1.03° below 20 kHz, 2.94 % / 4.67° at 100 kHz. Code 0 covers 236 Ω–150.9 kΩ, so the fresh arm above 151 kΩ is a code-20 read | On disk, not input (dropped 2026-08-27) |
| EIS error vs frequency | `fig_eis_error.tex` | `data/eis_{err,dph}_{fresh,typical,fouled,pureR}.dat` | Magnitude and phase error against frequency for four loads, each at the gain code that ranges it | The gate crossings drawn are **not** the bandwidth specification: `Rf`/\|Z\| moves with frequency on a real electrode. Markers are thinned one in four; every frequency is drawn | On disk, not input |
| EIS settling | `fig_eis_settling.tex` | `data/eis_settle_*.dat`, `data/eis_excess_*.dat` | Impedance error against how late the demodulation window starts, in units of the electrode τ, four conditions spanning 10× in τ and 10× in frequency | Gives the ≥5τ rule for 0.1 %. **Superseded for per-half-period settling by R7**: on the real pixel `Rf·C_F` dominates τe, so a wait in τe alone is short by up to 36× | On disk, not input |
| EIS code-level attribution | `fig_eis_codelevel.tex` | inline (no `.dat`) | Impedance from ten-bit words: magnitude attributed term by term, and the phase mechanism | The −2.94° is the interleave (180·f/f_s), not the converter; it is absent when `SARADC_SEL` is static. One record, one die, one frequency, resistive load, no noise sources | Replaced by `tab_eis_codelevel.tex`; figure on disk, not input |
| EIS wafer calibration | `fig_eis_mccal.tex` | `data/eis_mc_{law,dc}.dat` | Impedance error over 649 MC dies under a stored design law against one dc `Rf` measurement per chip: σ 10.24 % → 0.00065 % | **The two x-axes are independent**: left spans 70 %, right 0.005 %. The statistical section holds capacitors at typical, so this bounds `Rf` and not the pole | On disk, not input |
| DAC INL / DNL, ideal rail | `fig_dacr2r12_inl_ideal.tex`, `fig_dacr2r12_dnl_ideal.tex` | `data/dacr2r12_{inl,dnl}_ideal_0{0..4}.dat` | Corner INL and DNL against code, ladder on an ideal 2.5 V rail | Corner run with no device mismatch: R-2R linearity is a matching property, so this is the systematic term alone. Worst DNL is the mid-scale carry, −0.50 to −0.54 LSB; the DNL comb is stride-decimated but the extreme is exact | Input (Fig. 24.52–24.53) |
| DAC INL / DNL, Monte Carlo | `fig_dacr2r12_mc_inl.tex`, `fig_dacr2r12_mc_dnl.tex` | `data/dacr2r12_mc_{inl,dnl}_00.dat` | 200-sample distributions of worst INL and worst negative DNL | Right- and left-skewed respectively, so percentiles rather than mean ±3σ. **These are the pre-driver-fix figures** (40 % monotonic, 2.6 % four-channel); the current driver gives 42.0 % and 0.12 % (F16) | Input (Fig. 24.58–24.59) |
| DAC reference droop | `fig_dacr2r12_vddac.tex`, `fig_dacr2r12_inl_wpsu.tex` | `data/dacr2r12_vddac_0{0..4}.dat`, `data/dacr2r12_inl_wpsu_0{0..4}.dat` | The ladder's own current modulating its reference 25.7–29.6 mV pp, and the −37.1 LSB bow that follows | Droop×code accounts for −36.9 of the −37.1 LSB, so the raw nonlinearity is reference modulation, not a ladder error. **The two supply regulators were deleted from the tapeout cell on 2026-08-24**, so this term is no longer modelled — not smaller | Input (Fig. 24.55–24.56) |
| Bias generator start-up | `fig_biasgen_startup.tex`, `fig_biasgen_startup_corners.tex` | `data/biasgen_startup_0{0..2}.dat`, `data/biasgen_startup_corners_0{0..4}.dat` | Power-up transient at tt and `V_BNM` settling over all corners; rails settle 0.77–1.10 µs | Corner separation is a lower bound (passives pinned at typical). Separately measured: 101 of 101 corners start, circuit floor 211–232 ns at tt and 487–641 ns at ss, worst 7.28 ms on a 10 ms supply ramp | Input (Fig. 24.16–24.17) |
| Bias trim law | `fig_biasgen_vbnm_vs_code.tex`, `fig_biasgen_idd_vs_code.tex` | `data/biasgen_{vbnm,idd}_vs_code_0{0..4}.dat` | `V_BNM` and supply current against the `BiasAdj` word over corners | The bench sweeps the trim as a continuous variable, so only six points are sampled: this is the shape of the law, not a per-code characterisation | Input (Fig. 24.14–24.15) |
| ADC transfer and window | `fig_adc_transfer.tex`, `fig_adc_range.tex` | `data/adc_transfer_0{0,1}.dat`, `data/adc_range_0{0,1}.dat` | Code against input with the ideal 409.6 codes/V line, and the usable 0.441–2.068 V window | Slope is 628.64 codes/V, 1.535× ideal; the flat segments are code limits, not sweep ends. Eleven simulated points, 0.25 V apart = 157 codes, so the curve between them is interpolation and carries no linearity information | Input (Fig. 24.42, 24.44) |
| ADC error and INL | `fig_adc_error.tex`, `fig_adc_inl.tex` | `data/adc_error_00.dat`, `data/adc_inl_00.dat` | Error against the ideal line (±168 LSB) and against the converter's own line (0.523 LSB worst) | The 168 LSB is gain error alone and carries no linearity information; 24 points 39 codes apart bound the deviation but are not a DNL/INL measurement. A 25th point is absent because its simulation errored | Input (Fig. 24.43, 24.45) |
| CDAC floor plan | `fig_adc_capdac_layout.tex` | `figures/CDAC_layout.png` | Segmented 10-bit array: binary b0–b4 in split strips, unary b5–b9 from identical strips, dummy rows top and bottom | The array exists **only in layout**, which is why this section's data comes from an extracted netlist | Input (Fig. 24.41) |
| Feedback resistor vs code | `fig_tiarprog_r_vs_code.tex`, `fig_tiarprog_err_vs_code.tex` | `data/tiarprog_r_vs_code_0{0..4}.dat`, `data/tiarprog_err_vs_code_00.dat` | Measured R over 320 codes at five corners, and deviation from the ideal law | Corner families move the absolute value −33 to +35 % — poly sheet tolerance, absorbed by gain calibration and not by code choice. +9.2 % at N = 0 is the 1.65 kΩ closed-switch stack | Input (Fig. 24.47–24.48) |
| Thermometer seam MC | `fig_tiarprog_mc_seam.tex` | `data/tiarprog_mc_seam_00.dat` | Per-sample step across code 63→64, the transition most exposed to mismatch | Mean 7.42 kΩ, σ 504 Ω, worst 5.88 kΩ — 14.7σ above the monotonicity limit, so no realistic mismatch closes the seam. Mismatch only, 25 °C | Input (Fig. 24.50) |
| TIA loop MC | `fig_tiaab_mc_pm.tex`, `fig_tiaab_mc_voff.tex`, `fig_tiaab_mc_inoise.tex` | `data/tiaab_mc_{pm,voff,inoise}_00.dat` | Phase margin, output offset and integrated input noise of the transimpedance loop, 200 samples | PM: all 200 clear 45°, minimum 64.7°, measured through the feedback probe with the Randles electrode included; right-skewed, so percentiles rather than ±3σ | Input (Fig. 24.25–24.27) |
| A1 into a real cell | `fig_ampab_cell_ce.tex`, `fig_ampab_mc_cellaol.tex` | `data/ampab_cell_ce_0{0..4}.dat`, `data/ampab_mc_cellaol_00.dat` | CE potential against commanded RE potential over corners, and the DC loop gain closed around the cell | The central segment's 12/11 slope is the cell divider, the flat ends are compliance limits. The loop includes the cell, whose 12 kΩ loads a ~25 kΩ open-loop output resistance | Input (Fig. 24.29–24.30) |
| Electrode model validation | `fig_electrode_validation.tex` | `data/electrode_cv_{bc,randles}.dat`, `data/electrode_rs_{line,sim}.dat` | Nonlinear electrode against the linear cell, and peak current against √v against Randles–Ševčík | The two panels use different cycles: Randles–Ševčík describes the first scan into an undepleted bulk; the second cycle is the repeatable response and sits 3–5 % below it | Input (Fig. 24.3) |
| Four-analyte CV panel | `fig_electrode_panel.tex` | `data/electrode_panel_{ua,aa,h2o2,pyo}.dat` | Voltammograms of the wound panel through the rev-2 channel, one parameter set per analyte | E⁰′ and concentrations are literature-anchored; k⁰ is fitted, and reversal peaks appear for irreversible couples because following chemistry is not modelled. Two cathodic markers span −1.4 to −2.4 µA, unmeasurable by the rev-1 front end | Input (Fig. 24.4) |
| DPV panel and dose response | `fig_electrode_dpv.tex`, `fig_electrode_dose.tex` | `data/electrode_dpv_*.dat`, `data/electrode_dose_*.dat` | DPV of the four-reporter panel and the dose curves through the measured current transfer | The 152.6 µV DPV step is finer than the shipped 12-bit DAC's 610.35 µV LSB, so the apex accuracy read off the panel is a **lower bound** on the channel's. The binding model is analytic; only the electrode and channel are simulated | Input (Fig. 24.5–24.6) |

Caption: every analog figure worth a slide, with the fragment that draws it, the data it
renders from, and the one caveat the caption carries that a reader needs to avoid
misreading it. Eleven fragments are complete on disk but no longer input by the TRM after
the owner-ordered cuts of 2026-08-26/27, and the four-channel macro section carries a table
rather than a figure.

---

## 6 Known limitations and open items

| # | Item | State | Consequence / next step |
|---|---|---|---|
| L1 | SAR usable window 1.6274 V of a 2.5 V span | Measured, extracted view; it is the capacitor array and not the once-empty flip-flops | 34.9 % of the input range is lost to clipping; a transimpedance swing beyond ±0.81 V about vcm is truncated, not digitised. Gain ranging must respect it (contract §2.1: a stored zero only works while `Rf`/`Rcell` < 47.5) |
| L2 | Reference DAC is matching-limited | 42.0 % monotonic yield per channel after the driver fix (was 40 % on the 1.0 V driver, 17 % on the un-widened 2.5 V cell); 0.12 % of four-channel chips monotonic on all four; mean INL 1.485 LSB, mean DNL −1.682 LSB | The driver term is gone from the distribution; what remains is `rppolywo` ladder matching. Open item, unaffected by F16. The −6.6 LSB worst DNL is up to 3.5 mV of lost command resolution that no constant recovers |
| L3 | DAC reference droop | 25.8 mV pp over a code sweep against a 0.133 mV budget; a one-parameter fit removes 94 %, leaving 931 µV rms | The two supply regulators were **deleted** from the tapeout cell on 2026-08-24 (returning 806.8 µW), so this term is no longer modelled — not smaller. Both ladders now run from the 2.5 V analog rail directly |
| L4 | Bias DAC path (rev-1 global generator) | Archived and dead in topology A (D4: bias nets are local per pixel). Kept in topology B as `anatop_biasgen_g` with `USEDAC` | The DAC path is unusable as a trim: non-monotonic at the LSB level (one code by 1 LSB moves its rail −2.7 to +3.1 mV), hard-fails cold (all four buffers rail to AVDD for T ≤ −25 °C or AVDD ≤ 2.275 V), and `USEDAC` with the RTL reset codes holds 1.20 mA, 2.7× nominal, indefinitely. R15 says: enable, trim with the 6-bit `ADJ`, leave `USEDAC` alone |
| L5 | Bias trim nominal code | 37 at 37 °C, 33 at 27 °C — the same generator at two temperatures, 4.7 % apart in reference current | Not a contradiction, but the stored code is temperature-specific and the in-pixel target set is a 37 °C set. Temperature dependence of every calibration constant is unquantified: no block has a temperature-resolved Monte Carlo |
| L6 | Analog layout | `anatop_quad` has **none**; the LEF is a placeholder. 13 rev-1 leaf layouts copied in; 63 cells through the per-cell harness gave 44 LVS MATCH, antenna clean, every tapeout-path cell density-only in DRC | Work list at `signoff_mp/ANALOG_LAYOUT_WORKLIST.md`. Remaining: `anatop_tia_rprog`, `anatop_tia`, `anatop_pixel` (pin labels, on-grid ADC), `anatop_quad`, then per-cell blockdrc + ant25 + Pegasus LVS and the CDL into the chip LVS include |
| L7 | Placeholder LVS waivers | Owner decision O5: placeholder black-box LVS port opens stay as documented waivers. A's chip LVS mismatch is the schematic-side `anatop_quad` stub not reaching the Verilog reader; B carries W-PT1-1, the placeholder macro's VSS port never binding in Pegasus despite parent metal on every port rect | Both close only when the real layout exists and connects its ports internally. Waivers consolidated in `DRC_WAIVERS_d13a.md` and `_pt1.md` |
| L8 | Dummy fill deferred | Owner decision O3. 64 of the d13a chipdrc results are density | Fill, its post-fill DRC/LVS, the seal ring and the fab deliverable checks are all deferred (PLAN §7) |
| L9 | Bare globals inside the pixel hierarchy | `anatop_tia`, `anatop_tia_rprog` and `anatop_pixel` tie nets directly to `vdd!`/`vss!`, bypassing the netSet rebinding | Harmless in simulation (the bench's globals are AVDD/AVSS, so every measured number stands); in the chip CDL they become `.GLOBAL` and the macro's AVDD/AVSS pins do not carry them. Fix: relabel, or map the globals in the LVS include |
| L10 | Extracted DAC view drops `mismatchflag` | 88 devices at 0 in the executed deck — 76 `rppolywo` ladder resistors, 8 in the ADC, 4 in the local biasgen — all inside `av_extracted` views, while the schematic view carries the flag | Any Monte Carlo through the EIS or pixel-top bench as it stands gives the reference ladder no mismatch and produces a tidy, wrong distribution. Re-extract with the flag, or bind the schematic DAC for MC runs |
| L11 | EIS Monte Carlo not run | Set up, not executed: `sq_step` at 200 samples is 3.4 h. The tests also point at the typical-only `castalia_typ_25` section, not `castalia_pm_25` | Fix L10 and the model section first; then MC is affordable at 50 samples in ~51 min |
| L12 | Crosstalk not measured | The 1.10 LSB neighbour figure is a bound on an ideal-supply, per-site-bias bench with no coupling path | A crosstalk number needs the post-layout supply and substrate network — shared AVDD/AVSS metal and guard rings — i.e. after the layout exists |
| L13 | `Rs` estimator and gain law both need calibration | `Rs` = Re(Z) at the top sweep frequency carries a +9.92 % structural bias; the reported current through the nominal `Rf` law spans −33.3 % to +35.7 % across corners while the true current is constant to 0.12 % | Per-chip ratio calibration against a known impedance is not a refinement, it is the only thing between the reported current and a ±35 % error. The on-chip reference resistor that would let firmware refresh it without equipment does not exist (contract C4) |
| L14 | Calibration fabric is design intent | The electrode isolation switch (C1), the A1 loopback switch (C2) and the reference resistor (C4) are not in any schematic; no calibration has been executed in simulation or on silicon | Two of the ten stored constants need a production tester regardless. The zero-current slot-1 read is the one piece proven executable on the current cell (F17 §9) |
| L15 | Converter die-to-die spread | Unmeasured, and not small. The extracted netlist has no mechanism to produce it: extraction flattens the mismatch wrappers and the array is 3308 linear capacitors | A separate statistical-capacitor bench gives σ(gain) = 0.0145 % and σ(offset) exactly zero by construction; the comparator's threshold divider carries σ = 0.968 mV = 0.607 LSB. Nothing in the TRM quotes a converter gain or offset σ |
| L16 | Corner sets pin the passives | Five of the eight coverage rows are cornered over transistors only; poly sheet resistance, a ±35 % quantity, does not move | Every corner spread marked in the TRM is a lower bound. Re-running them is an owner decision |
| L17 | DAC settling and glitch | Never measured. Every published DAC number is a dc solve | Update rate, glitch impulse and the major-carry glitch are unknown, which matters for the swap engine's excitation edges |
| L18 | Topology B chip cut | Not taken. Every chip-level row of the A-vs-B table is empty for B | B's tile closes hold at +0.037 ns, which says nothing about the chip: A's binding class is the `hart_tile` ETM boundary at chip level, and B has four such boundaries with 63 more signals each |

Caption: the open items behind the headline numbers, each with what it costs and what
closes it. L1–L5 are circuit properties that calibration or firmware must absorb; L6–L9 are
physical-implementation state; L10–L18 are measurements not yet taken or fabric not yet
drawn.

---

## Sources

- `/home/mseminario2/chips/castalia/tapeout_review/PLAN.md` §2–§4.5, §7
- `/home/mseminario2/chips/castalia/tapeout_review/DECISIONS.md`, `TOPOLOGY_B.md`
- `/home/mseminario2/chips/castalia/tapeout_review/reports/` — F7, F13, F14, F16, F17, F22, B3, B9, B10
- `/home/mseminario2/chips/castalia/docs/afe_rev2_{strategy,simplan,firmware_contract,cv_electrode}.html`
- `/home/mseminario2/vestarv/implementations/asic/castalia/analog/` — chapter, `fig_*.tex`, `tab_*.tex`, `data/`
- `/home/mseminario2/vestarv/platform/common/latex/TRM/TRM.pdf` (revision 2026-08-30, analog chapter pp. 200–285)
- `/home/mseminario2/vestarv/docs/publications/iscas27-castalia/ERRATA.md`
