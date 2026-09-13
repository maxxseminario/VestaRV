# A chip of your own, and a peripheral to put in it

Two recipes for the VestaRV generator. The first configures a chip and proves it
generates, elaborates and boots. The second adds a peripheral to the register
flow, RTL, benches and TRM, with the gate that refuses each mistake named beside
the step that can make it.

Run every command from the repository root. The build needs no locally installed
toolchain: `sh tools/get_bazel.sh` fetches bazelisk into `tools/bin/bazel`, and
Bazel provisions Python, a C/C++ toolchain, the RISC-V cross-compiler, GHDL and
TeX Live.

---

## A chip of your own

### 1. Copy a configuration

```bash
cp platform/common/config/asic_default.json platform/common/config/mychip.json
```

`asic_default.json` is one hart, no orchestrator, and the smallest configuration
that goes through synthesis, place-and-route and LVS. Every key is optional and a
missing key takes the Castalia default, which since 2026-09-12 is
`config/castalia.json` itself. An unknown key or an out-of-range value is a
hard error, never a silent fallback.

### 2. The five knobs that matter

The authoritative list is `_CONFIG_SCHEMA` in
`platform/common/python/generate.py`, 61 knobs. Five decide what the chip is.

| Knob | What it does | What to know |
|---|---|---|
| `numHarts` | Hart and tile count | 1, 4 and 5 are the verified counts. Any other value emits well-formed but unproven RTL, and the generator says so on the console. 18 generates and no longer elaborates: `hdl/common/hart_tile.vhd` asserts `RamSize = 8192` and every Argus configuration asks for a 16 KiB TCM |
| `orchestrator` | Hart 0's shape | `true` = hart 0 is the always-on soft `orch_tile` and harts 1..N-1 are gateable channel tiles, on memory map v2. `false` = every hart a hardened `hart_tile` |
| `isa.*` | The instruction set | Each knob generates its hardware away when off and traps the encoding as illegal. `isa.minimalTiles` builds harts 1..N-1 as rv32iac while hart 0 keeps the full ISA, so no binary may migrate between the two |
| `memory.*` | `romSize`, `tcmSizePerHart`, `sharedBulkRamSize`, `npuStagingRamSize`, in bytes | The schema checks range and step only. `tcmSizePerHart: 4096` passes it and then fails in `ChipGenerator.py` with `PROGADDR_IRQ must be located in RAM, not in the interrupt vector table`; 8192 is the value that both generates and elaborates today |
| `peripherals.*` | Which blocks exist | A dropped instance's window reads zero, its interrupt vectors become reserved gaps because the numbering is frozen, and its pins revert to plain GPIO |

`package.model` is the sixth knob worth naming: it is the single source of the
pad ring, which is derived and not configured, and only `castalia-lqfp100` bonds
the JTAG TAP.

### 3. Generate

```bash
make -C platform/common generate CONFIG=config/mychip.json
```

The generation is itself a gate chain: schema validation and the
`check_config_defaults` axis, a C compile of the emitted `MemoryMap.h` with
`riscv-none-elf-gcc -fsyntax-only`, the configurator sync check, and
`check_intro_names` against every TRM intro chapter. Any of them failing stops
the run.

It also rewrites two TRACKED files for the configuration in hand:
`platform/common/config/ChipConfig.resolved.json` and
`platform/common/config/PadRing.json`. Restore them with `git checkout` before
committing anything else, or skip the Makefile and build hermetically instead
(step 4), which writes only into `bazel-bin`.

### 4. The three gates

Shown on `asic_default`, which has the two Bazel rules already.

```bash
tools/bin/bazel build //platform/common:chip_artifacts_asic_default
tools/bin/bazel test //opensource_sim/asic_default:asic_default_elaborate
tools/bin/bazel test //opensource_sim/asic_default:asic_default_boot
```

The first is the same generation inside a staged copy with declared outputs, so
it proves the configuration generates from a clean tree.
`:asic_default_generation_test` asserts every artifact it should emit is there
and parses. The elaborate gate binds the generated hierarchy and runs it for 1 ns,
which is what the concurrent size assertions in `MCU.vhd` and `hart_tile.vhd`
need. The boot gate releases reset on the real mask-ROM image and grades the
banner the ROM-resident Forth monitor prints on UART0: it proves the chip
fetched through the arbiter, ran C out of its TCM and drove a pad.

A new configuration needs two rules before those commands exist: a
`chip_artifacts` target in `platform/common/BUILD.bazel` naming
`config/mychip.json` (copy `chip_artifacts_asic_default`), and a package under
`opensource_sim/` (copy `opensource_sim/asic_default`, whose `defs.bzl` splices
the two generated labels into the shared analysis order).

### 5. Where the outputs are

`platform/common/out/` is gitignored. The Bazel build puts the same tree under
`bazel-bin/platform/common/chip_artifacts_<name>/`.

| Path | What |
|---|---|
| `out/hdl/MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd` | The generated RTL and its bench |
| `out/software/include/MemoryMap.h`, `periph.S`, `core_features.h` | Firmware headers |
| `out/linker-scripts/memory.x`, `periph.x`, `*.txt` | Linker regions and symbols |
| `out/pnr/chip_top_padring.tcl` | The pad ring as ordered per-side lists |
| `out/web/chip_data.js`, `MemoryMap.json` | The configurator and register-browser bundle |
| `config/MemoryMap.json` | The machine-readable memory map |
| `config/ChipConfig.resolved.json`, `PadRing.json` | The resolved knobs and the derived pad ring, both TRACKED |
| `platform/common/latex/TRM/` | The TRM LaTeX project for exactly this configuration |

---

## Add a peripheral

Start from the skeleton in `hdl/common/regs/templates/`: `skel.rdl` (a control
register with a strobe field, a status register with a hardware-set write-1-to-clear
flag, and a data register), `SKEL.vhd` (an entity on `periph_regs` using exactly
those hooks) and `SKEL_tb.vhd` (a bench on the shared BFM covering byte lanes,
the strobe and the W1C). Copy the three, rename `SKEL`/`skel`/`SKELx`
throughout, and put each file where the step below says.

```bash
tools/bin/bazel test //hdl/common/regs/templates:skel_smoke
```

That gate re-emits the skeleton's package with the real emitter into a scratch
directory, analyses `SKEL.vhd` against it and runs `SKEL_tb` under GHDL, so the
template cannot rot against a change to `rdl_vhdl.py` or `periph_regs.vhd`. The
skeleton is deliberately registered in neither `config/rdl.json` nor
`rdl_vhdl.RTL_PACKAGES`; `skel_emit.py` supplies those two rows for one emission
only, which is why a copy of it can never ship as a phantom peripheral.

### 1. Write the `.rdl`

`hdl/common/regs/rdl/<block>.rdl`, beside the twenty-two others. It is the
authority: a width, an access code, a reset value or a field description written
there reaches the VHDL package, the C header, the TRM table, `MemoryMap.h`,
`MemoryMap.vhd`, the configurator and the register browser. Reserved bits are
absent, as SystemRDL intends. `vesta_access` is written on every field and is
redundant on purpose.

**The gate.** `rdl_model.py` re-derives `vesta_access` from the
`(sw, hw, onwrite, singlepulse)` tuple and refuses to compile a file where the two
disagree, naming the field; a SystemRDL warning is promoted to an error;
`//tools/rdl:peakrdl_export_test` proves the description is valid SystemRDL that
stock PeakRDL exporters consume.

### 2. Register it

Five rows, all of them in lists that already exist.

- `platform/common/config/rdl.json`: one entry under `peripherals`, with
  `rdl: true`, `source`, `top`, `registerPrefix`, `bitFieldPrefix` and
  `registerSource: "rdl"`. This is the only registry; there is no second list in
  Python.
- `hdl/common/regs/rdl/castalia_penta_wound.rdl`, the chip addrmap: an
  `` `include `` and one instance line at the base address the generator
  computes, with its `->vesta_vector`. The firmware header emitter reads the chip
  addrmap, so without that line `software/include/regs/<block>_regs.h` and the
  `<INST>_BASE_ADDR` / `<INST>_REGS` / `<INST>_IRQ_VECTOR` triple in
  `castalia_regs.h` are never emitted.
- `rdl_vhdl.RTL_PACKAGES` in `platform/common/python/rdl_vhdl.py`: `package`,
  `file`, `source`, `top`, `rtl`, `periph`, and `migrated: True` because a new
  entity `use`s its package from the first commit. Add `replacesMemoryMap: True`
  only if the entity reads its slot constants from `work.MemoryMap` today.
- `rdl_vhdl._DECODE`: the spelling the entity's decode uses, so adopting the
  package moves no assignment. A new block takes the house style,
  `{'style': 'strip', 'strip': '<PREFIX>x', 'prefix': 'SLOT_'}`, which emits
  `SLOT_CR`, `SLOT_SR` and so on.
- `rdl_vhdl._REGFILE`: add the addrmap name. Without it the package carries the
  scalar constants and no `NWORDS`, `reg_arr_t` or eight-table section, and the
  entity cannot instantiate `periph_regs`.

**The gates.** `//platform/common:rdl_vhdl_pkg_test` fails when a tracked package
differs from a fresh emission by one byte, when a package flagged `migrated` is
not `use`d by its entity or one not flagged is, and when an adopted entity kept
the `work.MemoryMap` clause the package re-declares (two directly visible
declarations of one name are homographs and VHDL LRM 12.4 makes neither visible).
`//platform/common:rdl_vs_generator_test` asserts every peripheral flagged `"rdl"`
is loaded by a `_rdlRegisters()` call in `generate.py` and every such call names a
flagged peripheral. A new block needs no row in
`platform/common/python/rdl_legacy_constants.json`: that snapshot is the frozen
independent copy of a decode that existed before its migration, and a block
written description-first has none.

### 3. Regenerate the package and the header

```bash
tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs      # hdl/common/regs/vhdl/
tools/bin/bazel run //platform/common/python:rdl_regs_headers   # software/include/regs/
```

`tools/bin/bazel run //:regs` runs both and then the generator, in dependency
order. Review with `git status`: both emitters are idempotent, so a second run on
an unchanged tree produces no diff. Nothing under `hdl/common/regs/vhdl/` or
`software/include/regs/` is ever hand-edited.

**The gates.** `//platform/common:rdl_vhdl_pkg_test`,
`:regs_headers_identity_test` (byte-identical, and no stale header left behind),
`:regs_headers_vs_memorymap_test` (every base and offset equals `MemoryMap.h`'s)
and `:regs_headers_compile_test` (a translation unit using every object-like
macro compiles freestanding at `-Wall -Wextra -Werror`).

### 4. Write the entity on `periph_regs`

`hdl/common/periph/<BLOCK>.vhd`. The context clause is
`use work.<block>_regs_pkg.all;`, which REPLACES `use work.MemoryMap.all` rather
than joining it. The entity instantiates `periph_regs` with the package's eight
tables and keeps only its datapath: the FSMs, every clock domain but `ClkMem`,
hardware-set flags with their CDC, and the falling-`EnMemPeriph` pre-latch of
asynchronous read values, which feeds `hw_rd`.

The hooks, from `hdl/common/regs/REGFILE.md`:

| `.rdl` property | Mask | Hook |
|---|---|---|
| `sw=rw`, `hw=r`/`na` | `IMPL` | `regs(i)` holds the flop |
| `sw=r`, `hw=w` | none | the read comes from `hw_rd(i)` |
| `sw=w` | none | holds nothing and reads 0; consume it on `wr_pulse` (one bit, `singlepulse`) or on `wr_hit` plus the raw `wdata` |
| `hw=w` / `hw=rw` | `HWOWN` | `hw_we` / `hw_set` / `hw_clr` may touch the bit |
| `onwrite=woclr` / `woset` / `wot` | `W1C` / `WOSET` / `WOT` | `w1c_hit` / `woset_hit` / `wot_hit`; the flag's flop stays with the hardware that sets it |
| `singlepulse` | `PULSE` | `wr_pulse` |
| `onread=rclr` | `RCLR` | `rd_clr` |

Four generics are the RTL's, because SystemRDL cannot express them: `RDTHRU` (the
read does not come from storage), `WIDEWR` (any enabled lane writes all 32 bits),
`FULLWR` (only `WEn = "0000"` is a write at all) and `STROBE_HOLD`. `STROBE_HOLD`
is a property of who CONSUMES the strobe: `false` retires on the next `ClkMem`
edge, for a consumer clocked on `ClkMem`; `true` retires on deselect, for a
level-sensitive consumer in another clock domain. Getting it wrong loses the event
in one direction and widens the pulse in the other.

Which hook is a timing question. `acc_hit`, `rd_hit` and `wr_hit` are
combinational and valid during the access, and are mandatory where `ClkMem` is
GATED by `EnMemPeriph`, because such an access presents one rising edge and a
registered strobe is sampled a whole bus access late. The registered
`rd_strobe` / `wr_strobe` are the same condition one flop later, for a consumer
downstream of the access edge with a free-running `ClkMem`.

**The gates.** `//platform/common:rdl_vs_vhdl_<block>_test` re-derives the decode
out of the VHDL and compares it against the description; add the block to the
`for periph in [...]` list in `platform/common/BUILD.bazel` and to
`GENERIC_BLOCKS` and `_RDL_FOR` in
`platform/common/python/rdl_vs_vhdl_test.py`, with `regfile=<block>_regs_pkg` and
a `require` list of the instance's load-bearing lines. A hook wired to a bit
outside `IMPL and (HWOWN or HWALIAS)` reaches no logic, and a concurrent
assertion inside `periph_regs`, fenced with `-- pragma translate_off`, reports
that instead of dropping it silently.

### 5. Write the bench

`hdl/common/tb/<BLOCK>_tb.vhd`, on `work.periph_tb_pkg`: the `periph_bus_t`
record and `PERIPH_BUS_IDLE`, the `bus_write` / `bus_read` / `bus_write_hold`
BFM, and the `scoreboard` protected type. Declare the DUT as a `component` so the
bench compiles standalone. End with exactly one deliberate negative control and a
final banner, so a passing run reports exactly one failure and proves the
scoreboard can fail at all.

Two sharp edges. `periph_tb_pkg.bus_write` always drives all four lanes; a byte-lane
case needs a local procedure that drives `wen` itself, which `SKEL_tb.vhd` carries.
And `periph_tb_pkg.img` formats through `to_integer`, so an expected word with bit
31 set aborts the run with `overflow detected` instead of reporting a mismatch.

**The gate.** The bench is the oracle, and for a new block it is the only
independent check that the description and the RTL say the same thing. If it does
not cover a register, it does not prove that register.

### 6. Wire the source set, the bench and the synth target

- `hdl/common/tb/BUILD.bazel`: a `vhdl_source_set` naming the closure in ANALYSIS
  ORDER (`constants.vhd`, `periph_regs.vhd`, `regs/vhdl/<block>_regs_pkg.vhd`,
  then `periph/<BLOCK>.vhd`), and a `ghdl_test` with `entity`, `pass_pattern` and
  `tags = ["ghdl"]`.
- `hdl/common/synth/BUILD.bazel`: a `ghdl_synth_test` on the same source set, and
  the target added to `SYNTH_TARGETS`. Zero latches is a requirement, not an
  observation. `//toolchains/ghdl:synth_census_test` then freezes the flop, latch
  and cell counts.
- The other lists that read the RTL tree, each of which wants the package
  immediately before its entity: `REGS_PACKAGES` in
  `platform/common/python/verify_stage.py`, `opensource_sim/mcu/defs.bzl`,
  `opensource_sim/fpga_default/defs.bzl`, and the `read_hdl` pair in the Genus
  scripts. `genus/` is gitignored, so no gate can see that last one: the rule is
  one `read_hdl` line for the package and one for the entity, in that order.

```bash
tools/bin/bazel test //hdl/common/tb:<BLOCK>_tb //hdl/common/synth:<BLOCK> \
                     //toolchains/ghdl:synth_census_test
```

### 7. The TRM intro chapter

`platform/common/latex/PeripheralIntroductions/<NAME>-intro-<chip>-<date>.tex`,
named by the `latexIntroFileName` argument of the peripheral's
`PeripheralTemplate`. Sections, in this order: `Overview`, optionally
`Block diagram`, `Functional description`, `Interrupts and events`,
`Programming`, `Usage notes`. `Instances and signals` and `Registers` are
generated by `LatexUserGuide.py` and must not appear in the intro. No subsection
above the first section, and no `\caption` inside a `tabular`.

**The gate.** `check_intro_names`, which runs inside `make generate`, matches every
`\register{}` and `\bitfield{}` token against the generated memory map (with `x`,
`y`, `n` and `h` as instance, sub-unit, channel and hart placeholders), enforces
the section skeleton and rejects second-person and changelog voice.

### 8. The generator hook that places it in the memory map

In `platform/common/python/generate.py`:

- a `_CONFIG_SCHEMA` entry, `peripherals.<name>`, with its validator and a
  one-line meaning;
- a `PeripheralTemplate(...)` carrying `nameTemplate`, `description`,
  `registerPrefix`, `bitFieldPrefix`, `latexIntroFileName` and
  `latexFeatureSummary`, followed by `m.AddPeripheralTemplate(p)` and one
  `_rdlRegisters('<NAMEx>', p)` call, which is the whole register table;
- an `m.CreatePeripheral(...)` guarded by the knob, giving `nameIndex`,
  `interruptPriority`, the base address or peripheral slot, `sharedBus`,
  `clockDomain` and a `strobeNote`;
- an interrupt-vector row and, if the block is on the event fabric, its producer
  and consumer taps.

In `platform/common/hdl_templates/MCU.template.vhd` and
`platform/common/python/mcu_vhd.py`: a `--@GEN:<name>-decls@` marker and a
`--@GEN:<name>-instance@` marker, with the emitter methods that fill them. An
out-of-tree block uses the `overlay-decls` and `overlay-instance` markers and the
`mcuRegion` overlay stage instead, and touches no public file.

**The gates.** `check_mcu_vhd_test`, `check_memorymap_vhd_test`,
`check_memorymap_h_test`, `check_riscv_tb_vhd_test`, `generation_determinism_test`
and `check_configurator_sync_test` hold the generated tree byte-identical to the
tracked one, so a hook that changes anything it should not fails immediately.

### The whole set, once

```bash
tools/bin/bazel run  //:regs
tools/bin/bazel test //platform/common:rdl_vhdl_pkg_test \
                     //platform/common:rdl_pkg_vs_legacy_test \
                     //platform/common:rdl_vs_generator_test \
                     //platform/common:rdl_vs_vhdl_<block>_test \
                     //platform/common:regs_headers_identity_test \
                     //platform/common:regs_headers_compile_test \
                     //hdl/common/tb:<BLOCK>_tb \
                     //hdl/common/synth:<BLOCK> \
                     //hdl/common/regs/templates:skel_smoke
tools/bin/bazel test //...
```

## Further reading

`hdl/common/regs/README.md` is the two register trees and how to regenerate them.
`hdl/common/regs/REGFILE.md` is the `periph_regs` design note, the full
property-to-mask table and the migration recipe for an existing block.
`tools/rdl/README.md` is the SystemRDL toolchain, the four emitters, the registry
and the four adoption levels. `BAZEL.md` is the full target map.
