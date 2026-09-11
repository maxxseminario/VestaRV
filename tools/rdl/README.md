# SystemRDL in this repo

> **Analog interfacing collateral lives outside the public tree.** The AFE2/BIASG RTL,
> their `.rdl` descriptions and C headers, the AFE-bearing configurations, benches, ISA
> tests and lab tools were removed on 2026-09-11 and kept in the gitignored
> `private/analog/`, which mirrors their original paths. See `private/analog/README.md`.

The register map of a peripheral used to be written down in four places: the RTL
that decodes it, `platform/common/python/generate.py`'s hand-written
`PeripheralTemplate`, the TRM chapter and `MemoryMap.h`. Three of those four were
generated from the second, so they could not disagree with it. **Nothing tied any
of them to the first.**

Both halves of that are now closed. An `.rdl` description describes each block and
a build-time gate re-derives the decode out of the VHDL and compares
(`rdl_vs_vhdl_<block>_test`); and, since 2026-09-10, **the description IS the
register map for all 22 peripherals** — `generate.py` builds every template by
calling `rdl_model.registerTemplatesFor()` and carries no register data of its
own. A width, an access code, a reset value or a field description is written once,
in `hdl/common/regs/rdl/`, and reaches the TRM table, the register index, `MemoryMap.h`,
`MemoryMap.vhd`, the configurator and the register browser from there.

The gate found a live defect on its first run: two registers whose RTL reset was
non-zero and which `generate.py` published as 0, so the TRM's reset column and the
firmware-facing header described a chip that does not exist. It found 82 more
across the next twenty blocks (reports R2/R3), and one more on the way to single-sourcing: the per-template `Px*_MSB`
constants published 8-pin GPIO registers as 32 bits wide, because the width
correction had been applied to the instances and not to the template.

## What is here

| path | what |
|---|---|
| `requirements.in` | the three direct requirements, pinned exactly |
| `requirements_lock.txt` | the full closure, one sha256 per wheel; `MODULE.bazel`'s `pip.parse` reads this |
| `toolchain_smoke_test.py` | the hermetic interpreter imports all three at the pinned versions |
| `peakrdl_export_test.py` | the tracked descriptions export through stock PeakRDL |
| `READY` | touched when the compiler and the emitters work, for the agent consuming this toolchain |
| `platform/common/python/rdl_python.py` | finds an interpreter that can import the compiler, for the Makefile |
| `hdl/common/regs/rdl/*.rdl` | the descriptions: one per block, plus `vesta_udp.rdl` and the chip addrmap |
| `hdl/common/regs/README.md` | what the two register trees are and how to regenerate `regs/vhdl/` |
| `platform/common/python/rdl_*.py` | the model loader, the four emitters and the gates |
| `platform/common/config/rdl.json` | the per-peripheral `rdl: true` flag |
| `hdl/common/regs/vhdl/*_regs_pkg.vhd` | GENERATED and TRACKED: the VHDL packages the RTL `use`s (level 3) |
| `software/include/regs/*.h` | GENERATED and TRACKED: the firmware register headers, through stock PeakRDL-cheader |

Provisioning follows the repo's existing rule for an external tool: pinned
version, pinned artifact hash, fetched once and then served from the disk cache,
exactly as `@xpack_riscv_gcc` is. Wheels only, so no build step and no C
compiler: `systemrdl-compiler` ships a manylinux2014 abi3 wheel and the rest is
pure Python.

Regenerate the lock after editing `requirements.in`:

```sh
python3.11 -m pip download --only-binary=:all: --dest /tmp/rdlwheels -r tools/rdl/requirements.in
# then, for each wheel: name==version \  --hash=sha256:<sha256sum of the wheel>
```

## The model, and why it is not a fifth formatter

`rdl_model.py` compiles an `.rdl` description into the generator's **own**
`RegisterTemplate` / `BitField` objects. Every emitter then consumes those, so a
peripheral moved onto SystemRDL reaches the TRM, the C header, the RTL package
and the configurator through code paths that are already proven. `rdl_latex.py`
goes further and borrows `LatexUserGuide`'s own table methods wholesale, so the
TRM format is identical by construction rather than by imitation — and
`//platform/common:rdl_vs_generator_test` asserts the pilot's register tables are
**byte-identical** to the ones the generation emitted.

Two things SystemRDL does not say are carried as user-defined properties in
`hdl/common/regs/rdl/vesta_udp.rdl`:

- `vesta_access` — the generator's access code (`rw`, `r`, `rw1`, `w1`, …). It is
  redundant by design: `rdl_model.py` re-derives it from `sw`/`hw`/`onwrite`/
  `singlepulse` and refuses to compile a file where the two disagree.
- `vesta_named_values` — whether a field's enum member identifiers are emitted as
  value-description names, and therefore become `#define`s. `false` (the default)
  means they are documentation only; `true` is what `TIMER`'s `DIV_1…DIV_32768`
  and `SSEL_MCLK` need.

Reserved bits are absent from an `.rdl` file, as SystemRDL intends; the loader
synthesises the generator's `unused` fields for the gaps, which is also the check
that a register is fully specified.

### The access-code vocabulary, and what it did NOT need

`BitField.py` accepts `rw r r0 r1 rw0 rw1 w w0 w1`, and
`LatexUserGuide._ACCESS_LEGEND` gives every one of them a plain-English row that
`GenerateAccessLegend` reads out of `BitField.py` at build time, so a code with no
legend entry fails the build. The 2026-09-10 sweep needed four codes and all four
were already there, so the vocabulary did not grow:

| RTL shape | code | why that one |
|---|---|---|
| write-1 command strobe that reads 0 (`DMAxCR.DMAGO`/`DMAABORT`) | `w` | the field has no read value at all; the legend's read effect is "Not defined by this manual" and the register's prose says it reads 0 |
| one-bit write-1 pulse that reads 0 (`NFCxCR.NFCHALTCLR`) | `w1` | "a 1 triggers the action; a 0 has no effect" |
| write-1-to-set / write-1-to-clear ALIAS of another register (`EVFCHENSET`, `EVFCHENCLR`) | `rw1` | the alias is readable - both read `EVFCHEN` - and a written 0 leaves the bit alone, which is exactly the `rw1` legend. It is NOT `rw`: a plain read/write register would let a write of 0 clear the other harts' channels |
| a flop hardware also writes (`NPUCR.NPUTHINK`) | `rw` | a written 0 clears it, so it is not `rw1` |

`rdl_model._ACCESS_FROM_RDL` maps the SystemRDL `(sw, hw, onwrite, singlepulse)`
tuple onto these, and raises naming the field when a description declares a
`vesta_access` the tuple does not imply. Two SystemRDL spellings are worth
knowing: `onwrite = woset`/`woclr`/`wot` all reach the generator as `rw1`,
because the generator's `rw1` says "a written 1 acts", not which direction; and
`singlepulse` is a ONE-BIT property in SystemRDL 2.0, so a multi-bit command
field (`DMAGO[4:1]`) is written `sw = w` without it.

The one place the vocabulary is genuinely short is the register-level *summary*:
`_AccessSummary` joins the distinct codes of a register's fields with `/`, so
`DMA0CR` prints `rw/w` and `NFC0CR` prints `rw/w1`. That is accurate but terse;
the per-field table beneath it carries the codes themselves.

### Per-instance reset values

A `.rdl` BLOCK file describes a peripheral the way its RTL generics default. Two
peripherals reset a register differently per INSTANCE, because the value arrives
as a generic: GPIO's `RstValPx{OUT,DIR,SEL,REN,AFS}` and I2C's `default_SAD`.
Those are dynamic assignments in the top addrmap
(`hdl/common/regs/rdl/castalia_penta_wound.rdl`) and only exist after
ELABORATION, so `rdl_vs_generator_test` loads the elaborated per-instance blocks
through `rdl_chip.bind()` and grades the instance the generator side names. On
the generator side the same values are applied to the INSTANCE registers
(`generate.py`, after `ChangeGPIOPortSize`), never to the template, and the TRM
register index takes its reset column off the instance for the same reason
`_BlockSize` already takes the width off it.

## The four emitters

| module | output | conventions |
|---|---|---|
| `rdl_latex.py` | `<TAG>-registers-rdl.tex` | `LatexUserGuide`'s own methods: register summary table, one `\subsection` per block, reserved runs collapsed, striped rows, `hyperref` labels |
| `rdl_cheader.py` | `MemoryMap_<TAG>_rdl.h` | `<REG>_OFFSET`, `<REG>_PTR(_<PERIPH>_BASE)`, `<FIELD>_BIT`/`_MASK`/`_LSB`, one `#define` per named value description, plus a `<REG>_RESET` block the tracked header does not have today |
| `rdl_vhdl.py` | `<TAG>_reg_pkg.vhd`, and the two TRACKED packages below | `<REG>_WORD`/`_ADDR`/`_RESET`/`_IMPL`/`_SINGLEPULSE` and `<FIELD>_MSB`/`_LSB`/`_RESET`. For a block listed in `RTL_PACKAGES` it also emits an AGGREGATE section — the array type, the index constants and the `IMPL` / `RSTVAL` tables under the identifiers that block's decode already used — which is what makes adopting it a context clause and a deletion |
| `rdl_configurator.py` | `<TAG>_rdl.json` | the `Peripherals[].Registers[]` sub-tree of `config/MemoryMap.json`, from the same `ToDict` methods, plus the block metadata SystemRDL carries |

`bazel run //platform/common:rdl_generate` writes all four into
`platform/common/out/rdl/` (gitignored, like the rest of `out/`).

Two further emitters write TRACKED files, because their consumers are compilers
that read the source tree and not a build output:

| module | output | regenerate |
|---|---|---|
| `rdl_vhdl_pkg.py` | `hdl/common/regs/vhdl/<x>_regs_pkg.vhd`, one per block, **22 of them** (level 3) | `bazel run //platform/common/python:rdl_vhdl_pkgs` |
| `rdl_cheader_regs.py` | `software/include/regs/*.h` — the firmware register headers, through stock PeakRDL-cheader | `bazel run //platform/common/python:rdl_regs_headers` |

## `config/rdl.json`: the registry, and `registerSource`

`platform/common/config/rdl.json` is the ONE place a peripheral's description is
registered: which `.rdl` file, which `addrmap` in it, which `generate.py`
`PeripheralTemplate` its registers belong to, and where those registers come from.
`rdl_model.blocks()` reads it; there is no second list in Python.

| `registerSource` | meaning | who |
|---|---|---|
| `"rdl"` | `generate.py` BUILDS the template from the description and holds no register data | all 22: UARTx, SPIx, GPIOx, TIMERx, SYSTEM, NPU, QSPIx, I2Cx, I3Cx, NFCx, RTCx, PWMx, OWx, I2CTx, DMAx, TRNGx, EVFAB, **CLINT, MUTEX, IRQROUTER, PWRCTRL** |
| `"generator"` | the table is still hand-written — **no peripheral is, since 2026-09-10 (report R7)** | — |
| `"none"` | not a memory-mapped peripheral at all | DEBUG |

**The last four are PARAMETERISED components** (report R7). `CLINT` has one
`MSIPh` and one `MTIMECMPhL`/`H` pair per hart and moves its `MTIME` word base
with the hart count; `MUTEX` has `numMutexes` registers and an owner field
`masterW()` bits wide; `IRQROUTER` has four routing words per hart and sizes the
live MSB of its `U` and `X` words off `vectorsCount`; `PWRCTRL` carries one bit per
tile hart and `(numHarts+7)//8` `PWRSR` words. Their `.rdl` files are SystemRDL
components with parameters, register arrays and expressions in offsets and widths,
and `rdl_model.registerTemplatesFor()` elaborates them with the generator's own
values — the same numbers the RTL is given. `config/rdl.json` names each block's
parameters in a `parameters` field. See "Parameterised blocks" below.

**The flags and the code cannot drift.**
`rdl_vs_generator_test.test_rdl_sourced_peripherals_carry_no_generator_table`
asserts both directions: every peripheral flagged `"rdl"` is loaded by a
`_rdlRegisters()` call in `generate.py`, every `_rdlRegisters()` call names a
flagged peripheral, and no `RegisterTemplate` for a flagged peripheral's register
survives in `generate.py`.

## Parameterised blocks

Four blocks size their register SET and their FIELD GEOMETRY off the
configuration. They are SystemRDL components with parameters, elaborated by
`rdl_model.registerTemplatesFor(name, parameters=..., defines=...)` with the values
`generate.py` also hands the RTL, so one description emits the 1-, 5- and 18-hart
chips.

| block | parameters | what moves |
|---|---|---|
| `clint.rdl` | `NHARTS`, `NHARTS_WORD` (the count spelled), `MTIME_W`, `CMP_W` | `MSIPh` is a register array; the `MTIMECMPhL`/`H` pair is a REGFILE array on an 8-byte stride; the two word bases are the RTL's `((4*NHARTS+15)/16)*4` layout formula |
| `mutex_bank.rdl` | `NMUTEX`, `MW` (`mcu_vhd.masterW()`), `NHARTS` | `NMUTEX` registers as one array; the owner field is `MW:0`; one owner marker enumerated per hart |
| `irq_router.rdl` | `NHARTS`, `VECTORS`, `UMSB`, `UTOP`, `XMSB` | one four-word routing row per hart as a regfile array; the live MSB of the `U` and `X` words |
| `pwr_ctrl.rdl` | `NHARTS` | `PWRCR.PWRGATE` and `TASKWKM.PWRTASKWKM` span harts `NHARTS-1:1`; `PWRSR` is `ceil(NHARTS/8)` words of one nibble per hart |

### What SystemRDL does not say, and how it is said

Four user-defined properties in `hdl/common/regs/rdl/vesta_udp.rdl`, all inert
unless the addrmap sets `vesta_indexed = true`. The other eighteen descriptions are
therefore loaded character for character as before — which matters, because their
prose contains braces of its own (`{SRC,DST,LEN,CFG}`, `{4,8}`, `{seconds, subsecond}`).

- **`vesta_name`, and `{expression}` in it and in `desc`.** A SystemRDL array names
  its elements `MSIP[0]`, not `MSIP0`, and carries ONE `desc` for the whole array;
  the published names are `MSIP0…MSIP4` and the published prose says "hart 3". The
  name and the prose are written once with the index rendered where the generator's
  loop rendered it (`desc = "Hart {i} timer compare register…"`,
  `vesta_name = "MTIMECMP{i}L"`). Inside the braces: `i` (the component's index —
  the array index plus `vesta_index`), the block's parameters by name, `+ - * / %`,
  parentheses and `min`/`max`. A field inherits its register's `i`, so a nibble at a
  fixed position inside an indexed word writes `{8*i+3}`. An expression that does
  not evaluate is an error naming the component, never a silently literal brace.
- **`vesta_index`** — the index of an array's first element, or of a lone component
  that continues one (PWRCTRL's last `PWRSR` word).
- **`vesta_live`** — a boolean parameter expression; false removes the component and
  leaves its bits reserved. `PWRCR.PWRGATE` spans harts `numHarts-1 downto 1`, which
  is EMPTY at one hart, and SystemRDL has no conditional instantiation.
- **`vesta_values_count` / `_first` / `_name` / `_desc`** — a run of value
  descriptions whose COUNT is a parameter, appended to the members of `encode`. A
  SystemRDL enum is a static type whose member values must fit the field, so one
  enum covering 32 harts is 6 bits wide and the compiler rejects it on MUTEX's
  4-bit owner field: `Field 'MTXOWN' is not wide enough to encode as enum 'owner_e'`.

### The two shapes that are preprocessor guards, and why

A parameter cannot make a register not exist, and it cannot choose between two
descriptions. Those are `` `ifdef `` guards, passed as `defines` by `generate.py`.
**Every guard's sense is chosen so that NO defines is the default five-hart chip**,
which is what a bare `loadBlock()` — and therefore every gate, the top addrmap and
the firmware headers — compiles.

| guard | defined when | why not a parameter |
|---|---|---|
| `VESTA_IRQR_NO_XWORDS` | `vectorsCount <= 96` | `HhENX`/`PENDX`/`INSVCX` do not exist at all |
| `VESTA_IRQR_U_NARROW` | `vectorsCount < 96` | the `U` words' prose states a narrower range |
| `VESTA_PWR_MULTIWORD` | `ceil(numHarts/8) > 1` | the one-word register is named `PWRSR`, the multi-word ones `PWRSR0/1/2`, and their prose differs |
| `VESTA_PWR_MIDWORDS` | `ceil(numHarts/8) > 2` | a SystemRDL array dimension "must be greater than zero", so the middle full words cannot be an array of size 0 |

Neither IRQROUTER guard is defined by any configuration emitted today: the source
count floor is 114.

### Three SystemRDL limits, with the compiler's words

1. `Array dimension must be greater than zero` — no empty arrays, so a component
   that may be absent needs a guard, not a size of 0.
2. `Instance 'MTIMECMPH' at offset +0x34:0x5B overlaps with 'MTIMECMPL' at offset
   +0x30:0x57` — two register arrays cannot interleave on a stride. A `regfile`
   array holds the pair instead, and `rdl_model` flattens the hierarchy back out.
3. `Field 'MTXOWN' is not wide enough to encode as enum 'owner_e'` — an enum's
   member values must fit every field that encodes it, so a parameter-width field
   cannot carry a static worst-case enumeration.

A fourth is not a compiler message but a naming one: **the SystemRDL instance name
of an array is an internal identifier now, not the published spelling.** MUTEX's
array is instantiated as `MTX`, because `MemoryMap.h` defines a bare `MUTEX` macro
for the block's typed pointer and it would macro-expand the struct member
PeakRDL-cheader emits for a member called `MUTEX`
(`//platform/common:regs_headers_compile_test` co-compiles the two). The published
names still come from `vesta_name = "MUTEX{i}"`.

## The toolchain is hermetic, and mandatory

`systemrdl-compiler` is no longer optional: the chip's register map comes out of
it, so a missing toolchain stops the generation rather than silently emitting a
chip with eighteen peripherals' registers missing.

- **Bazel.** `chipgen.bzl` attaches `//hdl:rdl_sources` to every
  `chip_artifacts` action as an implicit input, and
  `//platform/common/bazel:stage_generate` carries
  `requirement("systemrdl-compiler")` and hands the closure to the generator
  subprocess on an explicit `PYTHONPATH` (the directories that actually contain
  those packages, never the bootstrap's whole `sys.path`; the child runs with
  `cwd=python/`, so `sys.path[0]` is still the generator's own directory).
- **Make.** `systemrdl-compiler` needs Python >= 3.8 and several hosts here ship a
  3.6 as `/usr/bin/python3`, which is why the generator's own sources stay
  3.6-compatible while its toolchain does not.
  `platform/common/python/rdl_python.py` returns the calling `python3` when it can
  already import the compiler, and otherwise the hermetic interpreter and pinned
  wheels bazel provisions — the same ones the build uses. The Makefile's
  `generate` target runs the generator under it. It fails with the two commands
  that fix it rather than falling back.

## The gates

| target | what it proves |
|---|---|
| `//platform/common:rdl_vhdl_pkg_test` | all 22 TRACKED packages are byte-identical to a fresh emission; a package flagged `migrated` is `use`d by its entity and one that is not is not (so the flag cannot rot); and an adopted package that re-declares `work.MemoryMap`'s slot constants has REPLACED that context clause rather than joined it |
| `//platform/common:rdl_pkg_vs_legacy_test` | every value in those packages equals the hand-written constant it replaced, from `platform/common/python/rdl_legacy_constants.json`, frozen by `rdl_legacy_snapshot.py` before any of them migrated. **This is the one gate in the set that does not run through the `.rdl`**, and it is why level 3 is not circular (see below) |
| `//platform/common:regs_headers_identity_test` | `software/include/regs/*.h` is byte-identical to a fresh emission, and no stale header is left behind |
| `//platform/common:regs_headers_vs_memorymap_test` | every peripheral base and every register address in those headers equals `MemoryMap.h`'s |
| `//platform/common:regs_headers_compile_test` | a translation unit that USES every object-like macro the headers define (3182 of them) compiles freestanding at `-Wall -Wextra -Werror`, and `MemoryMap.h` + `castalia_regs.h` co-compile in one TU |
| `//platform/common:rdl_vs_vhdl_uart_test` | `uart.rdl` vs the `RegSlotUARTx*` constants `UART.vhd` compiles against (`work.MemoryMap`'s before the migration, `uart_regs_pkg`'s after it; the reader follows the context clause), plus `UART.vhd`'s storage signals, reset branch and write-1-to-clear arm |
| `//platform/common:rdl_vs_vhdl_<block>_test`, 20 more | the same, block by block, through `makeGenericReader`: slot constants and the reset branch of the register-write process |
| the CLINT / MUTEX / IRQROUTER / PWRCTRL four of those | additionally re-elaborate the description at 1, 5, 18 and 32 harts (16 and 32 mutexes, 114–125 vectors) and check the layout against the generic formula parsed out of the VHDL — `MTIME_W = ((4*NHARTS+15)/16)*4`, `NUM_EN_WORDS = (NUM_SRCS+31)/32`, `NSRW = (NHARTS+7)/8`, `owner_t is array(0 to NMUTEX-1) of std_logic_vector(MW downto 0)`. A formula is not checked by checking one of its values |
| `//platform/common:rdl_vs_generator_test` | the `.rdl` offsets equal the generated slot map, and then every register, field, reset value and description `config/MemoryMap.json` carries; plus the pilot's TRM tables byte-identically; plus `registerSource` and `generate.py` naming the same peripherals, with no hand-written table left for any of them |
| `//platform/common:rdl_negative_control_test` | each of those comparisons shown FAILING on a one-token mutation, and passing on the unmutated copy in the same run |
| `//tools/rdl:toolchain_smoke_test` | the wheels are there, at the pinned versions |
| `//tools/rdl:peakrdl_export_test` | the descriptions are valid SystemRDL that stock PeakRDL exporters consume |

`rdl_vs_generator_test` runs against `penta_wound`, the tape-out configuration,
which instantiates every flagged peripheral.

The identity gates are what prove a description change moves nothing it should
not: `check_mcu_vhd_test`, `check_memorymap_vhd_test`, `check_memorymap_h_test`,
`check_riscv_tb_vhd_test`, `generation_determinism_test`,
`check_configurator_sync_test` and `splice_web_data_check_test`.
`check_intro_names_test` reads the `.rdl` files for the template register and
field spellings, because `generate.py` no longer writes most of them down.

## The three-level adoption plan

**Level 1 — description plus gate. COMPLETE.** Every register-bearing block the
`penta_wound` configuration instantiates has an `.rdl` beside its RTL, an entry
in `config/rdl.json`, and a `//platform/common:rdl_vs_vhdl_<block>_test` that
re-derives its decode out of the VHDL and compares. 22 peripherals plus the Debug
Module; 0 blocks at level 0. For the four parameterised blocks the gate also
re-elaborates the description at other hart, mutex and vector counts and checks it
against the generic formula read out of the VHDL, because a formula is not checked
by checking one of its values.

**Level 2 — the description becomes the source. COMPLETE, 22 of 22.** Eighteen
moved on 2026-09-10 (report R5): 1227 lines of `RegisterTemplate` / `BitField`
calls deleted from `generate.py` and replaced by one `_rdlRegisters()` call per
peripheral. The last four — CLINT, MUTEX, IRQROUTER and PWRCTRL — followed the
same day as parameterised components (report R7), deleting 225 more. The proof
that neither changed anything is a before/after byte-diff across **all seven**
configurations with a `chip_artifacts` target (`castalia`, `penta_wound`,
`argus`, `mcu_hart`, `fpga`) of
`config/MemoryMap.json`, `out/software/include/MemoryMap.h`, `out/hdl/MemoryMap.vhd`,
`out/hdl/MCU.vhd` and the whole `latex/TRM/include` tree: identical, every file.

**Level 3 — the RTL `use`s a generated package.** An entity deletes its local
word-offset / `IMPL` / `RSTVAL` declarations and gains one context clause:

```vhdl
use work.uart_regs_pkg.all;     -- hdl/common/regs/vhdl/uart_regs_pkg.vhd, generated
```

The body is untouched, because the package exports those constants under the
identifiers the decode already used; the field slices additionally move from bit
literals to `<FIELD>_MSB downto <FIELD>_LSB`. Proof that nothing changed:
`ghdl --synth` of the entity before and after, through the same wrapper, is
byte-identical once the source-location comments are stripped, its bench still
prints `ALL CHECKS PASSED`, and the elaboration gates still bind.

**All twenty-two packages exist and every flow reads them** (2026-09-11, report
R8a). `rdl_vhdl.RTL_PACKAGES` carries one entry per block, each with a `migrated`
flag saying whether its entity has adopted it yet, and every flow that reads the
RTL tree lists all of them whether or not anything `use`s them: the tb source
sets in `hdl/common/tb/BUILD.bazel`, `opensource_sim/mcu/defs.bzl`,
`verify_stage.py`'s `REGS_PACKAGES` injection, the
`genus/MCU_PENTA*` `read_hdl` order and the live Xcelium cell lists. **Adopting a
peripheral is therefore an RTL edit and a flag, and touches no shared file.** An
unread package costs one analysis and synthesises to nothing.

The identifier convention is per block and is not negotiable, because the point is
that no assignment in the body moves: `rdl_vhdl._DECODE` says whether a block
spells its word offsets `SLOT_CR` (local, nine blocks), `RegSlotUARTxCR` /
`MmrAddrNPUCR` (six blocks that read them from `work.MemoryMap` today) or
`W_CLAIM` (irq_router, pwr_ctrl), and the package emits that spelling.

**An entity that adopts its package SWAPS the memory-map context clause, it never
adds to it.** The overlap is far wider than the slot constants: the generated
memory-map package publishes a `<FIELD>_MSB` / `<FIELD>_LSB` pair for every field
of every peripheral (`MemoryMap.vhd:422 PxAFS0_LSB`, `:485 BR_LSB`, and 900 more),
which is exactly what these packages emit. Two directly visible declarations of one
name are homographs, and VHDL LRM 12.4 then makes NEITHER visible, so the first
reference stops compiling. `rdl_vhdl_pkg_test` computes the overlap from the two
files and fails an adopted entity that kept the clause.

**GPIO is parked for that reason.** Its entity ports are `GPIO_NUM_AFS * num_pins`
wide and `GPIO_NUM_AFS` is a memory-map constant, so `GPIO.vhd` cannot drop the
clause and cannot adopt `gpio_regs_pkg` (which therefore also omits `RegSlotPx*`).
Give the entity a `NUM_AFS` generic, defaulted by its instantiator, and it unblocks.

**The four configuration-dependent blocks publish only what does not depend on
the configuration.** CLINT, MUTEX, IRQROUTER and PWRCTRL are emitted at every
shipped configuration and the result is the INTERSECTION: a constant survives only
where its name and value are the same everywhere. So `clint_regs_pkg` carries
`MSIP0_WORD` but no `MTIMEL_WORD` (that word is `MTIME_W`, a function of NHARTS),
and `pwr_ctrl_regs_pkg` carries `W_PWRWAKE`/`W_PWRSTS`/`W_TASKWKM` but no
`PWRCR_IMPL` (the gate mask is one bit per hart). Nothing is hand-curated; the
configuration list is in the block's `variants` entry and is the one
`rdl_vs_vhdl_<block>_test` already elaborates.

**Why it is not circular.** After the move, `rdl_vs_vhdl_<block>_test` compares
the `.rdl` against a file generated FROM the `.rdl`: the decode no longer holds an
independent copy to disagree with. `rdl_pkg_vs_legacy_test` is that independent
copy, frozen — every offset, mask, reset and field range as the hand-written
constants stated them, with the pre-migration file md5s recorded, in
`platform/common/python/rdl_legacy_constants.json`, written once by
`rdl_legacy_snapshot.py` and never regenerated by a gate. Its two halves are not
equally strong and the file says so: `decodeConstants` was read out of the RTL
text and is independent in SOURCE, while `registers` and `fields` were frozen from
the emission on 2026-09-11, after reports R2/R3 had graded every `.rdl` against its
decode, and are independent in TIME. A deliberate register change moves that
table, in the same commit, and nothing else may.

**Genus.** `genus/MCU_PENTA/tcl/MCU_PENTA_hier.genus.tcl` and the `_pt` script
list their RTL file by file. A package the RTL `use`s must be `read_hdl`-ed
immediately before its entity, or synthesis fails at elaboration:

```tcl
read_hdl -vhdl -library work [stg $MP/regs/vhdl/uart_regs_pkg.vhd]
read_hdl -vhdl -library work [stg $MP/periph/UART.vhd]
```

All twenty-two lines were added on 2026-09-11 (report R8a), so nothing has to be
added there when a peripheral adopts its package. **`genus/` is gitignored**, like
`xcelium/`: those edits live in the working tree only and no gate can see them.
Whoever re-creates a Genus area from a fresh clone has to re-apply them, and the
rule is the two lines above, one pair per peripheral.

**Adopting an already-emitted package** (fourteen of the twenty-two are waiting;
UART, TIMER and QSPI are done, and GPIO, DMA, CLINT, MUTEX and the debug module
have no adoption path). Three steps, none of them in a shared file:

1. delete the peripheral's local word constants, or its `use work.MemoryMap.all;`
   where the package re-declares what it was reading from there;
2. add `use work.<x>_regs_pkg.all;`;
3. flip `migrated` to `True` in `rdl_vhdl.RTL_PACKAGES`.

Then `bazel test //platform/common:rdl_vhdl_pkg_test
//platform/common:rdl_pkg_vs_legacy_test //platform/common:rdl_vs_vhdl_<x>_test`
and the block's GHDL bench. The flows already list the package.

**Level 3 for a NEW peripheral.** Write the `.rdl` first, add the block to
`rdl_vhdl.RTL_PACKAGES` (plus a `_DECODE` entry naming the spelling its decode
uses, or an `_AGGREGATE` entry if it wants array tables), run
`bazel run //platform/common/python:rdl_vhdl_pkgs`, and `use` the package from
the entity's first commit. Add its file to every analysis order above in the same
change.

**No SystemVerilog regblock, deliberately.** `peakrdl-regblock` generates
SystemVerilog. This is a VHDL chip synthesised by Genus out of a tracked RTL tree
that four identity gates hold byte-identical; introducing a generated SV module
into that flow would mean a mixed-language elaboration in every simulator and
tool the project uses, for a register file that is 40 lines of VHDL. The register
decode stays hand-written; what is generated is the *description* of it and the
gate that checks it.

## The firmware register headers

`software/include/regs/` is a second C view of the same descriptions, emitted by
`rdl_cheader_regs.py` from the chip addrmap
(`hdl/common/regs/rdl/castalia_penta_wound.rdl`):

    <block>_regs.h    23 of them, one per peripheral BLOCK. Straight
                      PeakRDL-cheader output: <REGTYPE>__<FIELD>_bm / _bp / _bw /
                      _reset for every field, and a packed struct overlay of the
                      block's registers.
    castalia_regs.h   the umbrella: every block header, then <INST>_BASE_ADDR,
                      <INST>_REGS (a typed pointer) and <INST>_IRQ_VECTOR for
                      each of the 34 instances, plus the 12 per-instance reset
                      overrides the top addrmap assigns.

So firmware writes `UART0_REGS->UARTxCR = ...` rather than computing an address.
The struct member carries the TEMPLATE spelling (`UARTxCR`) and the instance is in
the pointer, which is the one place these differ from `MemoryMap.h`'s
`UART0CR_ADDRESS` convention.

**One addition to the stock exporter, and it is marked as one.** PeakRDL-cheader
does not emit SystemRDL `encode` members, so TIMER's `DIV_1…DIV_32768`, SPI's
`SPIDL_*` and the rest would be lost; `_enumLines()` appends them in the
exporter's own `<REGTYPE>__<FIELD>__<MEMBER>` spelling under a banner saying so.
Nothing else in those files is touched.

**An overlay block is not an instance.** SystemRDL cannot say that two addrmaps
share one address range, so a block overlaid on another block's sub-slot stands
alone and `_OVERLAYS` in the emitter names its host: its pointer is the host's
base, because its registers are declared at their absolute offsets inside the
sub-slot. No block in the public tree is an overlay today.

**These do not replace `MemoryMap.h`.** The generator still emits it, the existing
firmware is still written against it, and the two co-compile in one translation
unit (0 name collisions either way, gated). What does NOT co-compile is
`castalia_regs.h` beside the legacy hand-written `software/commune/include/myshkin.h`:
8 struct member names — `SYSCLKCR`, `CLKDIVCR`, `CRCDATA`, `CRCSTATE`, `WDTPASS`,
`WDTCR`, `WDTSR`, `WDTVAL` — are also bare object-like macros there, so myshkin.h
macro-expands them inside the struct declaration. Every boot-ROM source includes
myshkin.h, which is why the boot ROM has no call site on the new headers yet
(report R6). The fix is on the myshkin.h side, not here.

## Adding a peripheral

1. Write `hdl/common/regs/rdl/<name>.rdl`, `` `include
   "vesta_udp.rdl" ``, one `addrmap` with `vesta_peripheral` set to the
   generator's template name (`UARTx`, not `UART0`).
2. Add an entry to `platform/common/config/rdl.json` with `"rdl": true`, the
   source file, the addrmap name, the register/bit-field prefixes the
   `PeripheralTemplate` uses, and `"registerSource": "rdl"`.
3. In `generate.py`, declare the `PeripheralTemplate` (name, prose, prefixes,
   intro file, feature summary) and follow it with `_rdlRegisters('<NAME>', p)`.
   Write no `RegisterTemplate` and no `BitField`: the gate rejects both for a
   peripheral flagged `"rdl"`.
4. Add a `rdl_vs_vhdl_<periph>_test` reader to
   `platform/common/python/rdl_vs_vhdl_test.py` — one function that parses that
   peripheral's decode — and a target in `platform/common/BUILD.bazel`.
5. Run `//platform/... //tools/rdl:all`. `rdl_vs_generator_test` picks the new
   peripheral up automatically from `rdl.json`; it will fail loudly on any
   divergence, and the message names the register and the field.

A peripheral whose register set or field geometry depends on the configuration is
a PARAMETERISED block: see the next section.

## Changing a register

Edit the `.rdl`. That is the whole procedure for anything the description carries:
a reset value, a width, an access code, a register or field description, a value
enumeration. `tools/bin/bazel build //platform/common:chip_artifacts_castalia`
regenerates the TRM table, the register index, `MemoryMap.h`, `MemoryMap.vhd`,
`config/MemoryMap.json` and the register-browser data from it, and
`//platform/common:rdl_vs_vhdl_<block>_test` fails if the change is not also true
of the RTL. **The RTL is the authority**: when the gate fires, the VHDL is right
and the description moves, not the other way round.

**A register change now moves tracked GENERATED files as well**, and the gates
name them: `hdl/common/regs/vhdl/<block>_regs_pkg.vhd` for a change to a migrated
block, and `software/include/regs/*.h` for a change to anything. Regenerate both
in the same commit:

```sh
tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs
tools/bin/bazel run //platform/common/python:rdl_regs_headers
```

A change to a migrated block's register geometry also moves
`platform/common/python/rdl_legacy_constants.json`, deliberately:
that file is the record of what the decode said before it was generated, so the
edit is the statement that the register really did change.

**A parameterised block's register is changed the same way**, in its `.rdl`; what
stays in `generate.py` is the VALUE of each parameter for the configuration in
hand (`numHarts`, `numMutexes`, `_mtxOwnerMsb` = `masterW()`, `_vectorsCount`),
passed at the `_rdlRegisters()` call. If the change is to the SHAPE — a register
that exists only above some count, prose that reads differently — see the guard
table in "Parameterised blocks" and keep the new guard's sense so that no defines
is still the default five-hart chip.

Two things are still not in the `.rdl` and are edited in `generate.py`: the
peripheral's own identity (its prose, its `registerPrefix`/`bitFieldPrefix`, its
intro chapter, its feature-summary line) and everything about where a peripheral
is INSTANTIATED (slot or absolute base, interrupt vector, clock domain, per-port
pin configuration, and the per-instance reset values GPIO and I2C take from RTL
generics). Those are chip assembly, not register description.
