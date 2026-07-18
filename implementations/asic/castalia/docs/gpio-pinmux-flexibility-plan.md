# Castalia GPIO Alternate-Function Flexibility — Analysis & Plan

*Status: **v1 IMPLEMENTED** (output-function spread), 2026-07-10; **v2 IMPLEMENTED**
(input relocation + AF1-gap fill), 2026-07-11 — see §6. Target: `hdl/common`
(Castalia, `multicore-mp`), generated via `platform/common`.*

## v1 result (implemented 2026-07-10)

Every GPIO pin now exposes a full complement of alternate **output** functions on its
AF planes, drawn from a shared pool (UART `TX0`/`TX1`, timer compares
`T0CMP0/1`/`T1CMP0/1`, SPI1 `SCK1`/`MOSI1`), fanned across **all four ports** so each
output is reachable on **~23–27 pins**. The TRM AF matrix table dropped from ~200
Hi-Z cells to **5** (P0.7 AF0 = the real BOOT strap; 4 AF1 gaps on pins that never had
an AF1 — filled by v2 on 2026-07-11, leaving **1**). Verification: `check_mcu_vhd` IDENTICAL / `check_memorymap`
DROP-IN COMPATIBLE (both exit 0); `behavioral_mp` smoke 26/26 PASS incl. `afsel`.
Mechanism: reset `PxAFS=0` keeps AF0 active, so boot + every test is byte-identical;
new planes are additive output aggregates that never touch a peripheral input path.

*Update (G1b, 2026-07-11): the spread pool is config-aware — a dropped second
instance (`peripherals.uart1/spi1/timer1 = false`) removes its outputs (TX1,
SCK1/MOSI1, T1CMP0/1) from the pool and their plane slots revert to Hi-Z. The
spread planes are now emitted by `platform/common/python/mcu_vhd.py` from the
filtered pool rather than carried as fixed template text.*

*Original analysis + plan follows.*

Goal: make (almost) any GPIO pin able to host (almost) any peripheral function —
an RPi-style flexible pin-mux so the chip is easy to interface to a PCB in any
layout.

---

## 1. Why the TRM's alternate-function table shows "Hi-Z" almost everywhere

The TRM "GPIO Alternate Function Selection (`PxAFS`)" table (Table 3, auto-generated
by `LatexUserGuide.GenerateGpioAltFunctionMatrixTable()`) prints **Hi-Z** for nearly
every cell. That is **real hardware behavior, not a documentation artifact**:

- Each pin has a **3-bit `PxAFS` field** selecting one of **8 alternate-function
  "planes" (AF0…AF7)**. That is *mux capacity*, i.e. room for up to 8 functions/pin.
- Today only **AF0** (the legacy secondary function) is populated on every pin, and
  **AF1** on a subset (the timer/UART/I2C relocations). **AF2…AF7 are unassigned
  everywhere.**
- An unassigned plane is wired to `afunc_none` (all-zeros → `dir=0`), so selecting it
  tri-states the pad's output driver → the pin becomes a **high-impedance input**.
  That is a defined, safe state, and it is exactly what the table reports.

Verified path in RTL: `MCU.vhd` concatenates `afunc_none` into the unassigned plane
slots (`afunc*_all_out/dir/ren`) → `GPIO.vhd:af_plane_mux` selects the plane by
`PxAFS` → `dir=0` tri-states the pad. The generator renders the same fact from the
same pin table that drives the RTL.

**Reality check:** even the Raspberry Pi is *not* a true any-pin/any-function
crossbar — each pin has a fixed set of 6 alternates (ALT0–ALT5) chosen so common
buses are reachable on several pins. Castalia already has that mechanism, with
headroom for **8**.

---

## 2. What is already true (the enabling facts)

- **8 planes already synthesize.** `GPIO_NUM_AFS = 8` (`MemoryMap.vhd`), the plane
  mux exists, `PxAFS` is 3 bits/pin. **No change to `GPIO.vhd` is needed** — we only
  wire signals into planes that are currently tied to `afunc_none`.
- **3 bits/pin is the ceiling.** `PxAFS` is one nibble per pin (low 3 bits used);
  `GPIO.vhd` asserts `num_pins <= 8` so the nibble-per-pin layout fits a 32-bit
  register. 8 functions/pin is the max without a *second* AFS register. **Decision:
  stay at 3 bits — 1 normal function + 7 alternates.**
- **Reset selects AF0 on every pin** (`RstValPxAFS = 0`). If every pin keeps its
  current AF0 and we only *add* AF1–AF7, **all existing behavior (boot + every
  regression test) is byte-preserved** — new planes are dormant until software writes
  `PxAFS`. This is what keeps hart 0 green.

---

## 3. The one honest hardware limit

There is exactly **one** of each peripheral resource (one UART0 receiver, one SPI1,
one I2C0, one TIMER0-capture, …). "8 functions on every pin" therefore does **not**
mean 8 independent peripherals per pin. It means what the RPi does: each function is
offered on several pins and software picks **which pin hosts it** (placement
flexibility for the PCB):

- **Outputs** (UART TX, timer PWM/compare, SPI clock, TRAP) are free — offer them on
  many pins; only the pin whose `PxAFS` selects that plane drives it.
- **Inputs / I2C** (RX, MISO, capture, SDA/SCL) are single-source — offering one on N
  pins costs an N-way priority mux, and only one pin can be the source at a time. So
  these go on a **bounded** set of pins; the remaining planes fill with free outputs.

Net: every pin's 8 planes get filled and buses are reachable all over the chip, but
the value is **routing choice**, not duplicated peripherals.

---

## 4. Implementation path (matches the generator flow)

1. **`platform/common/python/generate.py`** — extend each pin's `altFuncs` to
   AF1–AF7. Single source of truth: generates the `pnum_gpio*_afN_*` constants
   (`MemoryMap.vhd`), pin reset attrs, and TRM Table 3 (now real functions, not Hi-Z).
2. **`platform/common/hdl_templates/MCU.template.vhd`** — expand the AF-routing
   region: per-port plane aggregates for planes 2–7, the 8-wide flatten, and extend
   the input relocation muxes (priority across each function's candidate pins).
3. `make chip` → copy `out/hdl/MCU.vhd` over `hdl/common/MCU.vhd` →
   **`check_mcu_vhd.py` exit 0** (byte-identical) and `check_memorymap_vhd.py` clean.
4. **`behavioral_mp` regression** green (proves AF0/boot untouched) + a `GPIO_tb`
   plane-select check.
5. Update roadmap (`vestarv_roadmap.html`), `.devlog/`, and the GPIO intro tex.

---

## 5. Proposed pin map (illustrative)

Keep **AF0 = current function** on all 32 pins. Fill **AF1–AF7** from the shared pool
so each pin becomes flexible, e.g.:

| Pin  | AF0 (now) | AF1     | AF2    | AF3    | AF4    | AF5    | AF6   | AF7      |
|------|-----------|---------|--------|--------|--------|--------|-------|----------|
| P1.4 | TX0       | —       | T0CMP0 | T1CMP0 | RX1ⁱ   | SCK1   | TRAP  | SDA0     |
| P3.4 | DTP0      | T0CMP0  | TX0    | TX1    | RX0ⁱ   | T1CMP1 | SCL1  | MOSI1    |
| P2.0 | T0CMP0    | TX1     | T1CMP0 | RX1ⁱ   | TRAP   | SDA1   | SCK1  | T0CAP0ⁱ  |

(`ⁱ` = single-source input, offered on a bounded set of pins; outputs spread widely.)
The full explicit 32×8 table will be hand-designed for review, encoded in
`generate.py`, and the generator will emit the matching RTL + TRM.

## 6. v2 (IMPLEMENTED 2026-07-11) — input relocation + AF1-gap fill

v1 spreads OUTPUT functions only (purely additive, zero input-path risk). v2 adds
bidirectional-bus completions on a bounded set of pins (TRM pin naming P0-P3):

| v2 slot | Function | Config gate | Bus story |
|---------|----------|-------------|-----------|
| P1.4 AF1 | `SDA1` io | `i2c1` | port-1 AF1 row = BOTH I2C buses (with SDA0/SCL0 on P1.6/7) |
| P1.5 AF1 | `SCL1` io | `i2c1` | ” |
| P2.6 AF1 | `SDA0` io | — | port-2 AF1 row completely filled (both UARTs + both I2Cs) |
| P2.7 AF1 | `SCL0` io | — | ” |
| P3.5 AF2 | `RX0` io (was TX1) | — | full UART0 pair on the DTP pins at AFS=2 (TX0 @ P3.4 AF2) |
| P3.6 AF7 | `MISO1` io (was TX0) | `spi1` | full SPI1 master on P3.4/5/6 at AFS=7 |

All 4 AF1 gaps are filled; the only remaining Hi-Z cell at defaults is P0.7 AF0 (the
real BOOT strap). Input muxes extend the proven always-visible idiom (keyed on the
candidate pin's `PxAFS` only) to fixed-priority chains: **v2 pad > AF1 pad > home**
(selecting one input on two pins at once is a software error; priority makes it
deterministic). The two v2 spread io slots wire literal pin indices (no `pnum`,
FromSpread); the four AF1 slots get real `pnum_gpio{1,2}_af1_*` constants (added to
`hdl/common/MemoryMap.vhd` + `_mcuMpPnums`, bidirectional cross-check). RX1 and
UART1/I2C1's existing 2-location sets were left alone — a third location would have
collided with the existing `pnum_gpio2_af1_rx1`-class names for no bus-completion gain.

Proof: `afselv2.S` (rv32ui, smoke set, verify-tag `spi1`) — relocated-MISO1 static
levels through P3.6 AF7 (plus negative control), and a TIMER0-paced software
bit-banged UART frame received by RX0 through P3.5 AF2 (0xA5 then 0x3C, FEF/PEF/OVF
clean, plus negative control). Emitters degrade per config (noi2c1/nospi1 emit zero
dangling references); at the new golden master `check_mcu_vhd` is STRICT IDENTICAL
(3865 lines) and `check_memorymap_vhd` drop-in.

## Implementation notes (how v1 was built)

- Single map `_GPIO_AF_SPREAD` in `generate.py` drives everything: it appends
  `GpioAltFunc` objects (flagged `FromSpread`) to each pin (→ TRM matrix table +
  location-qualified C-header AF defines like `TX0_P1_4_AF`). The RTL wires the planes
  with **literal pin indices**, so no `pnum_*` reverse constants are emitted (their
  function names would collide across the ~24 pins that share each output);
  `ChipGenerator` skips `FromSpread` altFuncs in the `altFunc`↔`pnum` cross-check.
- Template `MCU.template.vhd`: new `afunc<port>_af<k>_{out,dir,ren}` 8-bit plane
  aggregates + the 8-plane `afunc<port>_all_*` flatten, per port. Generated
  deterministically and spliced in (see the session's scratchpad `gen_af_spread.py`).
