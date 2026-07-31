# VestaRV ↔ Spike lockstep: the frozen record format

Phase V0 deliverable. Frozen 2026-07-29 against **Spike
`3d8eb089bd289c59dcb506f197a172e02beb7b5b`** (`Spike RISC-V ISA Simulator
1.1.1-dev`). Home per D4: `tools/cosim/` is tracked; generated traces and runner
scratch live under `xcelium/` (gitignored).

Every statement about Spike below was verified either by running this exact
binary or by reading `riscv/execute.cc` / `riscv/csrs.cc` / `riscv/sim.cc` /
`riscv/platform.h` at that commit. Nothing here is inferred from documentation.

---

## 0. Wire format

One event per line, ASCII, single-space separated, LF terminated. All numeric
fields are **lowercase hex with no `0x` prefix** and a **fixed width** (see each
record). No trailing whitespace. A `#` in column 1 is a comment line and is
ignored by the comparator (used for headers/provenance).

```
R <hart> <cycle> <pc> <insn> <rd> <rdval>
M <hart> <cycle> <L|S> <addr> <size> <data>
C <hart> <cycle> <csr> <val>
T <hart> <cycle> <cause> <epc> <tval> <priv>
X <hart> <cycle> <kind>
```

Field widths: `hart` 2, `cycle` 8, `pc`/`addr`/`epc`/`tval`/`rdval`/`val`/`data`
8, `insn` **4 or 8** (see §1), `rd` 2, `size` 1, `csr` 3, `cause` 8, `priv` 1,
`kind` a lowercase keyword.

### Deviations from the kickoff §4 proposal — and why

| Kickoff proposal | Frozen form | Reason |
|---|---|---|
| all values 8 hex digits | `insn` is **4** digits for a 16-bit instruction | Spike prints the instruction at its native width (`commit_log_print_value(…, insn.length()*8, …)`); zero-extending to 8 would make a compressed `a011` indistinguishable from a 32-bit `0000a011`. Kickoff §3b already requires logging the 16-bit form. |
| `M … <lanes> …` | `M … <size> …` | Spike never emits a lane mask. For stores it emits size implicitly (§2); a 1-digit byte count is the widest field **both** sides can produce. The RTL's active-low `wen` mask is normalized into (byte address, size). |
| `C` as its own event | still its own record, but **derived** | Spike does not emit a CSR line. CSR writes are extra fields on the retire line (§3), so the parser splits one Spike line into 1×R + n×M + n×C. |
| `T` compared | `T` **not compared** in V2 | Spike's commit log carries no trap information whatsoever (§4, proven). |
| `X` compared | `X` **not compared** | Spike logs `wfi`/`mret` as ordinary retires, so X is redundant with R (§5). |

### Per-retire emission order (both sides, mandatory)

`R`, then all `M` with `L`, then all `M` with `S`, then all `C`, then `T`/`X`.
This mirrors Spike's own print order (`log_reg_write` → `log_mem_read` loop →
`log_mem_write` loop) and makes the two streams comparable as one flat ordered
sequence.

### `cycle` — present, never compared

8 hex digits. RTL side: the tracer's own free-running count. **Spike side: the
0-based retire ordinal**, because Spike's commit log has no cycle concept at all.
The comparator MUST ignore this field. It exists only so a human triaging a
divergence can jump straight to the right point in a waveform.

---

## 1. `R` — retire

```
R <hart> <cycle> <pc> <insn> <rd> <rdval>
```

One record per **architectural instruction retired**, never one per FSM state.

* `pc` — the address of the instruction. Spike: field 4 of the line.
* `insn` — the architectural encoding. 4 hex digits if 16-bit, 8 if 32-bit.
  Spike: the parenthesised field.
* `rd` `rdval` — the committed integer register write. `rd`=`00` and
  `rdval`=`00000000` when the instruction writes no register.

**Spike source of truth.** `core%4d: %1d <pc> (<insn>)[ x%-2d <val>]…`. Note the
two spaces Spike emits for single-digit register numbers (`x5  0x…`) — the parser
must tokenize on whitespace runs, not fixed columns.

**Writes to `x0` are never logged by either side.** Spike skips them
(`if (item.first == 0) continue;` — key `(0<<4)|0` is exactly 0);
`regfile_sbirq.vhd` suppresses them (`if we3 = '1' and a3 /= "00000"`). So `rd`
is never `00` *because of an x0 write* — `00` unambiguously means "no write".

**What the RTL tracer samples** — the *port*, per invariant 7, not the
controller's intent: inside `hdl/common/vesta/datapath.vhd`, the `regfile`
instance's `we3 => reg_write`, `a3 => rf_a3_addr`, `wd3 => Result`. Sampling
`reg_write_dp` from `controller` instead is exactly the gap the phantom-write bug
class lives in.

**THE SECOND WRITE PORT — normalization rule.** `regfile_sbirq` has a *second*
write path into `x2`: `sp_in` / `sp_write` (driven by `sp_write_en`), used by the
IRQ push/pop and the Zcmp sequencer. A retire that commits `sp` through that port
has `reg_write='0'` on the main port, so a naive tracer emits `rd=00` while Spike
emits `x2 0x…`. **Rule:** when `sp_write_en` is asserted at a retire boundary the
tracer emits `rd=02`, `rdval=sp_in`. If both ports commit in the same retire the
architectural instruction is malformed — the tracer emits both as two `R` records
only if they belong to two architectural instructions; otherwise this is a bug to
report, not to normalize away.

**Compared:** `pc`, `insn`, `rd`, `rdval`. **Debug-only:** `cycle`.

---

## 2. `M` — committed memory transaction

```
M <hart> <cycle> <L|S> <addr> <size> <data>
```

`addr` is a **byte** address. `size` ∈ {`1`,`2`,`4`} bytes. `data` is
right-justified in 8 hex digits.

### Spike side

* **Load:** ` mem 0x<addr>` — **address only. No data. No size.**
* **Store:** ` mem 0x<addr> 0x<data>` where the *width of the data field encodes
  the size*: `commit_log_print_value(log_file, std::get<2>(item) << 3, …)`, so
  2 hex digits = 1 byte, 4 = 2 bytes, 8 = 4 bytes. Verified empirically:
  `rv32ui-p-sb` → `mem 0x00008690 0xaa`; `-sh` → `mem 0x000086d0 0x00aa`;
  `-sw` → `mem 0x000086d0 0x00aa00aa`.
* An AMO emits **both** a load and a store field on **one** line → two `M`
  records for one retire, `L` first.

### RTL side

The memory interface is word-addressed with an **active-low per-byte-lane**
`wen`. Normalization to the wire format:

* `size` = popcount(active lanes)
* `addr` = `data_addr` with its low 2 bits replaced by the index of the
  lowest active lane
* `data` = the `write_data` bytes under the active lanes, right-justified

**A10: a tainted compared field is followed by its bit mask.** `hexstr` marks a
whole nibble `x` if any of its four bits is non-0/1 — that is unchanged and the
field width is frozen. What the nibble cannot say is *which* bits, so a tainted
`R`/`M`/`C` field additionally emits, on the line **below** its record,
`# XBITS <hart> <cycle> <field> <mask> <defined>` — `mask` 1 at each undriven
bit, `defined` the value with those bits zeroed, both the field's own width. A
clean trace is byte-identical to a pre-A10 one.

**A16: `SC_CHECK` is the one state where a presented store is not a committed
one.** The core drives `wen` on its LOCAL reservation check alone; `resv_unit`
suppresses the write downstream when the GLOBAL check fails. A store presented
with `sc_fail_ext = '1'` is therefore **not** an `M … S` — it is
`# SCGHOST <hart> <cycle> <addr> <size> <data>`. If the verdict is `x`, the
tracer refuses to classify: `# SCGHOSTX`, and the store is kept.

Sample `data_addr` / `wen` / `write_data` / the returned `read_data` at the
committed transaction, and never from the AMO/SC `ALU_result` path: in atomic
states `ALU_result` is `amo_phase`-dependent and `rs1_value` is the
phase-independent export. Also: `mem_access_instr` is `'0'` in `MEMORY_WAIT` and
`data_addr` is only valid during the `EXECUTE` cycle. Instruction fetches are
**not** `M` records.

### Compared vs debug-only

| field | `L` | `S` |
|---|---|---|
| `addr` | **compared** | **compared** |
| `size` | debug-only (RTL) | **compared** |
| `data` | debug-only (RTL) — **the RETURNED BUS WORD since A6** | **compared** |

A load's *architectural effect* is still fully checked — through the `R` record's
`rdval` on the same retire. What is not checked for a load is the raw bus data
and the lane strobes, because Spike does not produce them. This is a real
coverage limit of the reference model, not a comparator shortcut, and it is the
reason V3's MMIO load injection is a separate phase: the RTL's returned `rdata`
is precisely the quantity Spike must be *told*.

---

## 3. `C` — committed CSR write

```
C <hart> <cycle> <csr> <val>
```

`csr` = the 12-bit CSR address, **3 lowercase hex digits**.

### Spike side — inline, decimal, and order-unstable

CSR writes are **extra fields on the retire line**, not separate lines:
` c<decimal_addr>_<name> 0x<val>`. Verified: `rv32ziscr-p-csr` produced
`core   0: 3 0x0000827a (0xb0041a73) x20 0x0000002e c2816_mcycle 0x00000000`
(2816 = 0xb00 = `mcycle`).

Normalization: parse the decimal number, emit 3-digit hex, **discard the
`_<name>` suffix** (it is Spike's disassembler name table; the RTL has none and
`-V200X` makes building one pointless).

**ORDERING TRAP — do not assume GPRs come before CSRs.** `log_reg_write` is a
`std::map` keyed by `(number << 4) | type` (type 0 = GPR, 1 = FPR, 4 = CSR), so
it iterates in *numeric key* order. `c1_fflags` has key 20; `x20` has key 320 —
a low-numbered CSR prints **before** a high-numbered GPR. The parser must
classify each field by its prefix, never by position.

### The rule that matters most: implicit trap-path CSR writes are INVISIBLE

Source-verified, and it is load-bearing. `commit_log_reset()` clears
`log_reg_write` / `log_mem_read` / `log_mem_write` at the **top** of
`execute_insn_logged`. A trapping instruction prints **no** line at all (§4), and
the `mepc`/`mcause`/`mtval`/`mstatus` writes that `take_trap()` performs
afterwards land in `log_reg_write` and are then **cleared before the next
instruction's line is printed**. They are discarded, never emitted.

**Therefore:** `C` records are emitted **only for architecturally explicit CSR
writes** — i.e. a retiring `csrrw`/`csrrs`/`csrrc[i]` (and `mret`'s own
`mstatus` update, which Spike does perform through `set_csr` on a retiring
instruction and therefore does log). The RTL tracer must **suppress from the
COMPARED stream** CSR-write port activity that does not belong to a retiring
instruction — trap-sequencer writes belong in the `T` record, not in `C`.
A tracer that faithfully logs every `csr_unit` write port assertion into the
compared stream will manufacture a divergence on every single trap.

**Amendment A1 (2026-07-29, V1 red-team):** suppressed ≠ discarded. The
discriminator for a compared `C` is **"a retire happens on this edge"**, never
"the FSM is in state X" — a state-based blanket suppression would hide exactly
the bug class the tracer exists to find (a CSR write enable erroneously live on
a non-retire edge, e.g. the legacy-trap and half-fetch-bubble leak classes,
findings F3/F7). The tracer emits any CSR-port write activity seen on a
NON-retire edge as a non-compared diagnostic comment line:
`# CSRLEAK <hart> <cycle> <state> <csr> <val>`. The comparator ignores `#`
lines (§0); the runner may grep for CSRLEAK and warn.

**Compared:** `csr`, `val`.

---

## 4. `T` — trap entry (RTL-emitted; **not compared** in V2)

```
T <hart> <cycle> <cause> <epc> <tval> <priv>
```

`cause` is the full 32-bit `mcause` (interrupt bit included). `priv` is the
privilege level *entered* (`3` = M).

**Spike's commit log contains no trap information at all.** Proven: running
`rv32um-p-mul` with `--isa=rv32iac` (M removed, so the `mul` at 0x8260 is
illegal) produced a log that ends at the instruction *before* it —

```
core   0: 3 0x00008258 (0xb6db7637) x12 0xb6db7000
core   0: 3 0x0000825c (0xdb760613) x12 0xb6db6db7
```

— 46 lines, no line for 0x8260, and the run then **terminated silently with
`rc=0`** even under `--instructions=200` (the trap vectored to `mtvec`=0, which
is Spike's Debug Module region, §7). Two consequences:

1. **A truncated Spike log is not proof the test ended.** The comparator must
   treat "Spike stream exhausted while RTL continues" as a divergence to
   investigate, never as success.
2. `T` has no Spike counterpart to compare against. In V2 (D3 scope: single-hart,
   TCM-resident, entry-aligned) no traps are expected, so a `T` record is a
   *signal* — the comparator reports it as a control-flow divergence. Giving `T`
   a comparable Spike side is V3 work.

Both delivery paths must be representable, and they differ in a way that shows up
in the `M` stream: the **legacy** path (`IRQ_SV`/`IRQ_JUMP`) pushes the return PC
to memory at `sp-4`, which is a genuine committed store; the **standard** P1 path
(`MTRAP_SV`/`MTRAP_JUMP`/`MTRAP_RET`) does not. Trap entry is **not** a retire —
it never emits `R`.

**Amended by A7:** that push is no longer an `M … S …` record. It has no Spike
counterpart and belongs to no retire, so it is now the non-compared diagnostic
`# IRQPUSH <hart> <cycle> <addr> <size> <data>` (or `# IRQPUSHBAD …` when it
misses the slot `sp` is simultaneously being set to). A boot- or
interrupt-inclusive comparison run must **replay it into the reference model's
memory**, because the ISR loads the pushed PC back from `0(sp)`.

---

## 5. `X` — control events (RTL-emitted; **not compared**)

```
X <hart> <cycle> <kind>
```

`kind` ∈ `mret` | `iret` | `wfi_enter` | `wfi_wake`.

Spike logs `wfi` as an **ordinary retire line** — `execute.cc` catches
`wait_for_interrupt_t`, calls `commit_log_print_insn`, then rethrows — and logs
`mret` as a retire plus its explicit `mstatus` CSR write. So both are already
covered by `R`/`C`, and `X` carries no comparable information. It is kept because
the RTL-side structure (a `wfi` that is *entered* and later *woken* is one retire
but two events) is worth having in a trace a human is reading.

**Amended by A7:** the `iret` stack POP is likewise no longer an `M … L …`
record (it rode `MEMORY_WAIT` with `isr_ret='1'`, which is *not* a retire, so it
injected a compared record no retire owned — `v1_report.md` §7.3). It is now
`# IRETPOP <hart> <cycle> <addr>`, bounded by an equality against
`stack_pointer`, with `# IRETPOPBAD` on a miss.

**VestaRV's custom instructions `iret` / `ignite` / `extinguish` (env
`riscv_test.h`) have no Spike encoding** — Spike takes an illegal-instruction
trap on them. Any test using them cannot run in lockstep without V3 work. This
constrains V2 test selection and is recorded in the V0 report's open questions.

---

## 6. `hart`

2 hex digits. Spike prints `core%4d: ` in **decimal** — parse and re-emit as hex.
Per-hart streams are compared independently (V4); cross-hart memory ordering is
never compared instruction-by-instruction.

---

## 7. What the comparator must know about Spike's address space

Spike hard-reserves two low regions, and they collide with VestaRV's boot ROM:

* `[0x0, 0x1000)` — Debug Module, `DEBUG_START`/`DEBUG_SIZE` in
  `riscv/platform.h`, added **unconditionally** as the first bus device
  (`sim.cc:72`). **Unavoidable.**
* `[0x1000, 0x2000)` — the reset-vector stub + DTB ROM (`DEFAULT_RSTVEC`,
  `set_rom()`). Removed by `--disable-dtb`.

With the DTB enabled, the commit log therefore opens with a **5-instruction
prologue at 0x1000–0x1010** that ends in `jr t0` to the ELF entry. The frozen
recipe uses `--disable-dtb --pc=<entry>` instead, which makes the log start
**exactly at the entry PC** and implements D3 entry-alignment with no comparator
special-casing. Proven identical otherwise: stripping the 5 prologue lines from
the DTB-on log makes the two logs byte-identical.

Alignment is still a comparator responsibility, because a bootrom-inclusive run
(V3) cannot use that trick.

---

## 8. Summary: compared vs debug-only

| record | compared | debug-only / RTL-side only |
|---|---|---|
| `R` | `pc` `insn` `rd` `rdval` | `cycle` |
| `M` `L` | `addr` | `cycle` `size`; `data` = the returned bus word (A6) |
| `M` `S` | `addr` `size` `data` | `cycle` |
| `C` | `csr` `val` | `cycle` |
| `T` | *(nothing — V2)* | all fields |
| `X` | *(nothing)* | all fields |

`hart` selects the stream rather than being compared within one.

---

## 9. Amendment log

Amendments are numbered, dated, and never silently rewrite frozen semantics.

* **A1 (2026-07-29, V1 red-team)** — §3: `C` suppression is from the *compared*
  stream only; the compared-`C` discriminator is "a retire happens on this
  edge", and non-retire-edge CSR write activity is emitted as a `# CSRLEAK`
  diagnostic line. Rationale: a state-based blanket suppression hides the F3/F7
  leak classes.
* **A2 (2026-07-29, V1 checkpoint-1 review)** — §1: a multi-`rd` retire
  (Zcmp `cm.pop`* / `cm.mv*`, knobs-on only — both `ENABLE_ZCMP`/`ENABLE_ZCMT`
  default false) is represented as **n consecutive `R` records with identical
  `pc`/`insn`**, one per committed register write, and the comparator
  canonicalizes any same-`pc` run by sorting on `rd` before comparing (Spike
  prints the same writes on one line in numeric-key order; the parser splits
  them the same way). The single-`rd` `R` shape is unchanged.
* **A3 (2026-07-29, V1 review)** — §2: the RTL-side address rule "never from
  `ALU_result` in atomic states … `rs1_value` is the phase-independent export"
  is corrected to: **the M record's address is the `data_addr` output port
  sampled in the cycle that issues the transaction.** (`rs1_value` is right for
  the AMO load and for SC, wrong for the AMO store: a `rd==rs1` AMO clobbers
  `rs1_value` in AMO_WRITEBACK; AMO_WRITE's `data_addr` is pass-A of the
  AMO_READ-latched `amo_addr_reg` by construction.) Additionally, tracer-side
  suppressions of bus re-presentations (LR/AMO read re-issue) must be bounded
  by an EQUALITY against the already-logged address with an assert on mismatch,
  never by FSM state alone; a failed-SC read presentation is emitted as a
  non-compared `# SCFAILRD <hart> <cycle> <addr>` diagnostic (it is finding F2,
  not noise).
* **A4 (2026-07-29, V1 review)** — §2/§6: the `M L` `size` field (debug-only)
  is derived from the held instruction's `funct3`, not from `wen` popcount
  (meaningless for reads); the `hart` field is `hart_id(7 downto 0)` (2 hex
  digits, sufficient through 256 harts; Argus is 18).
* **A5 (2026-07-29, V1 checkpoint 2)** — §0: a literal `x` nibble in any hex
  field of an RTL-side record means the sampled RTL state carried an X at that
  position (the tracer maps non-01 std_logic to `x` rather than inventing a
  value). The comparator treats any record containing `x` as INVESTIGATE —
  never as a match, never silently skipped. First real catch: two X-reads of
  undriven MMIO during boot (GPIO0 pads @0x4000, empty SPI0 RX @0x420c),
  outside the D3 window but real.

* **A6 (2026-07-30, V3)** — §2: the `M … L … <data>` field, specified through V2
  as "debug-only (RTL)" and in fact **emitted as a hardcoded zero** in every
  `L` record ever produced (`vesta_tracer.vhd:449/456/458/479`; verified on a
  real 38,427-line trace — all 6,544 `L` records read `00000000`), now carries
  **the 32-bit word the memory interface returned for that load**. It stays
  **uncompared** — Spike emits no load data (§2) — but it becomes the normative
  source for V3's MMIO load injection, replacing the alternative of *inferring*
  the value from the owning retire's `rdval` (which requires guessing the
  record grouping, the exact silent coupling this program exists to remove).
  Sampled from the tracer's `instr` port (= `read_data`, `vesta.vhd:1052`) on
  the edge one `clk_cpu` after the issue — the edge on which the core itself
  consumes it, per state: `MEMORY_WAIT` (datapath `Result`), `AMO_READ`
  (`vesta.vhd:1152/1154`), `LR_READ` (retires there), `ZCM_POP_WB`,
  `ZCM_JT_WB` (`vesta.vhd:1240`). A multi-cycle memory needs no tracking: the
  stall gates `clk_cpu`.
  **The `L` data field is the RAW BUS WORD, not the architectural result** — for
  a sub-word load the core's byte/half extraction happens afterwards in
  `datapath` (from `funct3`), so the recorded word holds all four lanes while
  `size` says 1 or 2. This is deliberate and is what an injector needs: the
  bytes to serve for a load of `size` bytes at `addr` are
  `word[8*(addr mod 4) + 8*size - 1 : 8*(addr mod 4)]`. It also means the `L`
  `data` field is **not** comparable with the `R` record's `rdval` without
  applying that lane select and the sign extension. (Contrast the `S` data
  field, which is right-justified per §2.)
  An `x` nibble keeps its A5 meaning. Two cases carry no
  data and say so with a `# NODATA` line — an `L` emitted outside a retire
  group (written to file at the issue edge, so unfillable) and a fill whose
  buffer was flushed by a sequencer abort. **An injector MUST refuse a
  `# NODATA` load rather than inject a fabricated `0`.**

* **A7 (2026-07-30, V3)** — §4/§5: the two trap-path memory events LEAVE the
  compared stream, becoming `# IRQPUSH` (legacy `IRQ_SV` return-PC push) and
  `# IRETPOP` (the `iret` stack pop). Rationale: both are genuine committed
  transactions that (a) have no Spike counterpart and (b) belong to no retire,
  so each misaligns the compared stream the instant an interrupt is taken —
  the `v1_report.md` §7.3 V3 TODO. Per the A3 principle each reclassification is
  **bounded by an equality**, never by FSM state alone, and the bound is a real
  hardware contract needing no arithmetic: the push address must equal
  `sp_write_data` (`IRQ_SV` drives both from `sp-4` in the same cycle,
  `vesta.vhd:1561` and `:3286`) and the pop address must equal `stack_pointer`
  (the `next_state = IRQ_REST` arm of the `data_addr` mux, `vesta.vhd:1562`).
  A violation emits `# IRQPUSHBAD` / `# IRETPOPBAD` with both addresses. The
  popped WORD is deliberately not logged: `read_data` does not carry it until
  the following `IRQ_REST` edge, and its correctness is already provable from
  `T`'s `epc` versus the first post-`iret` retire's `pc`.

* **A8 (2026-07-30, V3, CONDITIONAL on the standard-delivery config)** — §4:
  `T`'s `cause`/`epc`/`tval` become **compared** when, and only when, the
  reference model is driven through a harness able to emit a `T` record of its
  own from post-`take_trap` state, AND the configuration uses **standard
  `mtvec` delivery** (`ENABLE_TRAPCSR = true`). §4's "Spike's commit log
  contains no trap information at all" remains true and is the reason: it is a
  property of the *log*, not of the *model*. The **legacy** sentinel form
  (`cause = 8000007f`, `tval = ivt_entry`) stays **uncompared** — Spike does
  not and must not model that path — and serves instead as the delimiter of the
  bracketed ISR window, with the interrupt source recovered as
  `(ivt_entry - 0x8000) / 4` (83 = CLINT msip, 84 = CLINT mtip, 85 = meip;
  `MemoryMap.vhd:1144-1145,1182`).

* **A9 (2026-07-30, V3)** — §0/§8: an **x-wildcard allowlist**. A5 makes any
  record containing an `x` nibble INVESTIGATE, never a match — correct, and
  unchanged for everything not named below. But a **bootrom-inclusive** run
  moves the boot's two known undriven-MMIO reads INTO the compared window, and
  their taint propagates from the `M L` data field to the consuming `R`
  record's `rdval`, so a bare A5 would exit 4 on *every* boot-inclusive run.
  A9 admits a **named, per-test allowlist** (`compare.py --x-allow`, one
  `<pc> <addr>` pair per line): for a record whose `pc` (an `R`) or `addr` (an
  `M`) appears in it, an `x` nibble in the RTL field compares as a
  **wildcard** — **every defined nibble is still compared exactly and the field
  width must still match**, so the relaxation applies only at the positions the
  RTL itself reported as undriven. A defined-nibble disagreement on an
  allowlisted record is a normal `EXIT_DIVERGE`, reported as such.
  **"Never silently skipped" (A5) is honoured by a printed census:** every
  application is counted per record identity and printed in the stderr summary
  (`x-wildcard applied N application(s) across M record ident(s)`), so an entry
  that begins absorbing more taint than its written rationale predicts is
  visible in the run log. A9 is the operational form of **ruling A2** (refuse by
  default; permit only what is named, justified, and counted) and it is NOT a
  "skip x" switch.
  The two seed records, both `v1_report.md` §8.2 benign-and-real, both verified
  stable across two byte-identical runs, live in
  `xcelium/riscv_test/behavioral_mp/cosim_xallow.txt` with their rationales:
  `pc 00000070 / addr 00004000` (GPIO0 `PxIN`, undriven pads, observed
  `000000bx`, masked by the next instruction) and `pc 00000198 / addr 0000420c`
  (SPI0 RXBUF before any transfer, observed `000000xx`, discarded by the copy
  loop). The paired **injection-side** allowlist (`mk_inject.py --allow-x`)
  supplies the concrete substituted values handed to the reference
  (`000000b0`, `00000000` — defined nibbles matching the observed ones); the
  two sides must be kept consistent.
  The injection side accepts `<n>:<addr>:<val>` (pin one exact ordinal), `*` (the
  first x-tainted record at that address) and `*N` (the first N of them).
  **There is deliberately no unbounded form**: occurrence N+1 is refused, so an
  entry stays an auditable claim about a *known number* of undriven reads rather
  than a standing licence. Proven: a budget of 513 against a 514-read loop
  refuses at ordinal 520 with exit 5.

* **A10 (logged 2026-07-30 as a candidate; IMPLEMENTED 2026-07-31, WT)** — §0: **bit-granular
  `x` marking.** A5 marks a hex *nibble* `x` if ANY of its four bits is non-0/1,
  which is conservative for detection but **lossy for reproduction**: it does not
  say WHICH bits were undriven, so a load whose *defined* bits determine control
  flow cannot be replayed into a reference model. Motivating workload:
  `rv32ui-p-afsel`, whose 514 GPIO1 `PxIN` reads all print `000000xx` while the
  program branches on bit 0 — provably defined (the consuming `andi t0,t0,1`
  commits a fully defined `00000000`) but invisible in the trace. That test is
  therefore injection-infeasible and is dispositioned **X-GRANULARITY** in
  `v2_test_set.md`. Candidate form: a per-record undriven-bit mask emitted only
  when a field is tainted, keeping the frozen field widths intact. Cost is a
  `vesta_tracer.vhd` edit plus injector/comparator updates under the
  both-polarity discipline — the core-RTL freeze does not forbid tracer edits
  (the tracer is verification collateral, amended twice in V3), but one test does
  not justify the churn mid-phase. Backlogged to V4 / the per-config phase.

  **AS IMPLEMENTED (WT, 2026-07-31).** The candidate form is what shipped, with
  one deliberate narrowing and one motivation the candidate text did not have.

  * **The compared fields are UNCHANGED.** `hexstr` stays nibble-granular, every
    field keeps its frozen width, and A5's "a record containing `x` is never a
    match" is untouched. A10 adds INFORMATION; it changes no verdict.
  * A tainted **compared** field (`R` pc/insn/rd/rdval, `M` addr/data, `C`
    csr/val) additionally emits, on the line **below** its record:

        # XBITS <hart> <cycle> <field> <mask> <defined>

    `mask` = 1 at every undriven bit; `defined` = the value with those bits
    forced to `0`; both are the same width as the field they describe. It
    **binds backward**, like `# NODATA` — the emit sits inside the record
    procedures so the adjacency cannot be broken by a later edit.
  * **`T` and `X` are excluded.** They are RTL-side only and never compared
    (§4/§5), so a mask there would be a number nothing can act on.
  * **A clean trace is byte-identical to a pre-A10 one** — the line is emitted
    only when a field is actually tainted.
  * The header declares `A1-A7,A10,A16`, so a consumer can tell the vintages
    apart at a glance.

  **The motivation that turned out to matter more than `afsel`.** `mk_inject`'s
  `--allow-x ORD:ADDR:VAL` (ruling A2) was an **unchecked hand-off**: the
  operator supplied 8 hex digits and they were written into the reference's
  mouth. Nibble-granular `x` made it impossible to tell whether those digits
  preserved the bits the RTL had actually **driven**, so an allowlist entry
  could silently **overwrite a driven bit** and the only symptom would be a
  divergence somewhere downstream, blamed on the DUT. With the mask the check is
  exact: every driven bit must survive, and the entry may only fill undriven
  ones. **A2 permits fabrication; it does not permit contradiction.** A
  contradiction is now `EXIT_REFUSED`, and the fills are counted.

  **What A10 does NOT do, stated because the candidate text invites the
  opposite reading.** It does not clear `rv32ui-p-afsel`. That test's
  disposition names TWO obstacles and A10 removes only the first: the format
  can now say that bits 7:1 of its `PxIN` reads are undriven while bit 0 — the
  bit the program branches on — is driven. Making the test RUN still needs a
  substitution policy for 514 records with three different required bit-0
  presentations, and that is a new amendment with its own both-polarity
  control, not a consequence of this one. **`afsel` moves from
  X-GRANULARITY (a defect in the wire format) to an ordinary
  injection-scope item.** The blocker moves; it does not vanish.

  **Consumers, enumerated, because a silent parse-through is the failure mode:**
  `records.py` — indifferent (counts every `#` tag already, so `XBITS` reaches
  the findings surface for free); `compare.py` — indifferent by parse, and
  `XBITS` is deliberately left off `FINDING_TAGS` because it is metadata, not a
  defect signal; `mk_inject.py` — **changed** (indexes the masks, verifies
  `--allow-x`); `spike_log.py` — indifferent (parses Spike logs, never a trace);
  `disasm.py` — indifferent (decodes instruction words only);
  `test_compare.py` — **changed** (three cases, both polarities plus the
  pre-A10 no-mask case).

* **A11 (2026-07-30, V4) — the SLEEP bracket.** §5: an ISR bracket may open on
  `X <hart> <cycle> wfi_enter` as well as on a `T` record, and closes on the
  matching `X … iret`. Rationale, and it is not a convenience: VestaRV's park
  instruction is `EXTINGUISH` = `.insn r 0x0b,1,0` = `0x0000100b`
  (`verification/env/p/riscv_test.h:25-27`, ROM `start.S:468` at pc `0x2B4`), a
  **custom opcode the reference cannot execute** — it raises an illegal
  instruction, and with `mtvec`=0 the reference vectors to 0 and **re-runs the
  boot ROM forever** (measured: `--instructions 11` → `traps=0` and a log ending
  at the last park retire; `12` → `traps=1` and a 12th line back at pc 0). Every
  hart 1-3 on every test enters this window, so without A11 the multi-hart phase
  cannot start. The bracket delimiters stay **uncompared**, as A8 already rules
  for the legacy sentinel `T`.
  Two sub-cases, both observed and both handled:
  * a hart parked **forever** (never woken) emits `X wfi_enter` as its LAST
    record and **no `EXTINGUISH` retire at all** — the retire is emitted at the
    WAKE edge, not the sleep edge. Its bracket therefore never closes, which is
    correct: there is nothing after it to realign to. `--stop-before-sleep`
    (comparator) truncates such a stream instead.
  * a hart that IS woken emits `X wfi_enter`, then the `EXTINGUISH` retire, then
    `# IRQPUSH`, the legacy sentinel `T`, the ISR body, `# IRETPOP`, `X iret`.
    The whole span is one bracket.

* **A12 (2026-07-30, V4) — bracket REGISTER replay (`G`).** §4: the realignment
  script gains
  ```
  G <retire_index> <rd> <val>        poke reference GPR <rd> (2 hex, 00-1f)
  ```
  applied at the same index as that bracket's `S` set. Rationale: V3's
  store-only bracket rests on the `CLAUDE.md` ISR contract that an ISR
  saves/restores its own registers. **The ROM loader ISR does not** — the tile
  entry ABI is "sp valid, everything else undefined" (`start.S:471-474`: *"The
  interrupted context is the park loop, which we never return to — every register
  is ours"*). So a store-only bracket leaves the reference's GPRs holding
  park-loop values while the RTL holds loader leftovers, and any test image that
  reads such a register before writing it diverges **at the landing**, in a way
  indistinguishable from a core bug. The concession is explicit and is the same
  one V3 already made for memory: **the ISR's register writes become ASSERTED,
  not verified.** `sp` needs no special case — `IRQ_SV` pushes at `sp-4` and
  `iret` pops it back, so the net is zero.

  **STATUS: IMPLEMENTED, NEGATIVE-CONTROL-PROVEN *UNEXERCISED* BY THE STAGE 2-3
  CORPUS.** (Fable ruling, 2026-07-30: keep, and label it.) `mk_inject
  --no-reg-replay` drops the `G` set; run across **five** bracketed tile cells —
  `shboot` h01, `shlock` h01, `shspin` h01, `shcount` h02, `shuart` h01 — with the
  perturbation confirmed landed each time (7 → 0 `G` records), **every one still
  exited 0.** Cause, and it is a property of the tests rather than of `G`: every
  tile image writes each register before it reads it, so the loader's leftovers
  are never observed. The measured `G` population is tiny in any case — 7 records
  collapsed from 16,396 raw ISR register writes, because only the last write to
  each register can be observed at a single realignment point.
  So `G` is **correct precaution, not validated coverage**, and it must never be
  quoted as the latter. It is kept rather than deleted because deleting working
  safety mid-phase is the worse risk, and no test may be manufactured to exercise
  it (kickoff §1: this program writes no tests). **Validation is deferred to the
  first test that genuinely needs it — likeliest a Stage-5 mid-test re-park
  (`shwfi`/`shirq`/`shafe`), where the woken image resumes into code it did not
  itself enter.** If Stage 5 runs, validate `G` there with a landed-perturbation
  control and update this label.

* **A13 (2026-07-30, V4) — PLANT (`P`), and the bracket inject PARTITION.**
  §2/§7. Two halves of one mechanism.
  **(a) Plant.** A load whose address lies in the shared-and-writable window is
  served by **poking the reference's own RAM immediately before the consuming
  retire**, not by an MMIO callback:
  ```
  P <retire_index> <addr> <size> <data>     poke reference RAM before that retire
  ```
  The window is `[0xC000, 0x20000)` for the base N=4 config — NPU staging RAM +
  shared bulk RAM — i.e. the complement of {boot ROM, MMIO page, own TCM} inside
  `--mem 0x0:0x20000`. It MUST be derived from `MemoryMap.vhd`'s constants, never
  hardcoded twice, because the Argus `4*NHARTS` ledger moves these addresses.
  **Why poke and not a second `--mmio` window, and this is decisive, not
  stylistic:** `simif_t::reservable()` defaults to `addr_to_mem()`
  (`riscv/simif.h:19`), so an `lr.w` to a callback region throws
  `trap_load_access_fault` (`mmu.cc:253-255`) and an `sc.w` throws
  `trap_store_access_fault` (`mmu.h:277-279`). LR/SC on the shared window is the
  entire subject of `shcount`/`shspin`/`shlrsc`/`shlock`. Planting keeps the
  region real RAM, so LR/SC, AMO (`mmu.h:193-202`: probe → ordinary `load` →
  ordinary `store`) and execute-from-shared all work natively, and the reference's
  shared memory is correct **at every read point by construction**.
  What is given up is stated plainly: the *provenance* of a shared value. Lockstep
  never claimed it — cross-hart effects arrive as data (kickoff §4).
  **(b) Partition.** Bracket-interior `P`/inject entries are **DROPPED from the
  mainline replay list**, because the reference does not execute the interior and
  so never asks for those values; the interior's memory effects reach it through
  the `S` replay instead. They are emitted as counted, non-consumed annotations
  so that A5's "never silently skipped" survives:
  ```
  # BRACKET <n> DROPPED L <addr> <size> <data>
  # BRACKET <n> census: <k> dropped load(s), <m> replayed store(s), <j> dropped MMIO store(s)
  ```
  This is the V3-declared **V4 prerequisite** (`v3_report.md` §1: an
  unmodelled-region load inside an ISR window "is still emitted into the
  `--inject` list, but the reference never executes the ISR and so can never
  consume it"). It also makes **`meip` ISRs alignable** for the first time: the
  `MEIP_DISPATCHER`'s opening CLAIM read of `0x7800` is exactly such an entry.
  Alignable is NOT verified — the router's priority, its `in_service`
  exactly-once gateway and the dispatch itself remain taken as true.

* **A14 (2026-07-30, V4) — forced SC failure (`F`).** §1/§2:
  ```
  F <retire_index>                   clear the reference's load reservation
  ```
  implemented as `proc->get_mmu()->yield_load_reservation()` (`riscv/mmu.h:258-261`,
  public; the method `sim_t` itself calls), applied before that retire so the
  following `sc.w` fails. Rationale: in an isolated per-hart reference the
  reservation is set by its own `lr.w` and cleared only by its own `sc.w` —
  **spike models no remote invalidation at all** (the only mutation sites are the
  ctor `mmu.cc:28`, `store_conditional` `mmu.h:290`, and `sim_t`'s interleave
  boundary `sim.cc:330`), whereas VestaRV adjudicates **globally** in `resv_unit`
  (`resv_unit.vhd:134-161`, an address-match kill on the arbiter's serialized
  slave port, returned to the core as `sc_fail_ext`). So the reference's SC would
  otherwise always succeed and every RTL failure must be forced.
  **Therefore the SC's success/failure DECISION is ASSERTED, not compared. Say so
  wherever an SC result is reported.**

  **RESTATED 2026-07-30 (Fable ruling, after the A15 measurement below).** The
  first draft of this amendment listed the SC's **`rd`** as a compared field. **It
  is not, and the claim must not be repeated.** The oracle that decides whether to
  emit an `F` *is* `rd` — A15 proves it has to be, because a globally-failed SC
  still emits a store record and so store-presence cannot serve — and **comparing
  a value you forced is not comparison.** With `rd` as the oracle, the reference's
  `rd` agrees with the RTL's by construction at every SC.

  The compared set for an SC is therefore exactly:
  1. the SC's **address** — the reference computes it from its own `rs1`, so the
     historical M4b "SC addr=0 via PASS-B ALU" bug is still caught;
  2. **store-presence CONSISTENCY with the asserted outcome** — an `rd`=0 SC must
     carry a real `M … S` (its absence is a divergence: the reference stores);
     an `rd`=1 SC's store record is the A15 exception and is dropped with a
     census. So "success without a write" remains catchable; "failure with a
     write" is no longer a *finding* because A15 establishes it as the RTL's
     normal shape, and the two must not be confused;
  3. **downstream effects** — what subsequent loads read back, the retry loop's
     arithmetic, the backoff, the final counter. This is where a genuinely wrong
     SC still surfaces, and it is the reason the directed tests' end-state
     assertions (`shcount`'s counter == 4×64, `shlrsc`'s foreign-write leg) are
     not superseded by lockstep.

  **THE WEAKENING, ACCEPTED EXPLICITLY (Fable ruling, 2026-07-30), and its three
  compensations.** Consequence stated first, in the words it must always be
  reported in: **the historical M4b "SC premature write" bug — a failed SC that
  nevertheless commits a write — would NOT be caught by lockstep AT THE SC
  ITSELF today.** It is detectable only downstream. The compensations:

  (a) **The directed suite already owns exactly this shape.** M4b was *found*
      historically by end-state assertions and downstream reads, not by
      instruction-level comparison — `shlrsc`'s foreign-write leg and `shcount`'s
      "counter == 4×64" fail if a failed SC commits. Lockstep runs **in addition
      to** `xrun_parallel.sh`, never instead of it (`xrun_cosim.sh:17-33`), so the
      coverage is not lost, it is located elsewhere. Say where, every time.

  (b) **The evidence stays visible to a human even though the comparator ignores
      it.** A15 *drops the record from the compared stream* — it does not remove it
      from the trace, and every drop is printed per `(pc, addr)` in the
      `A15 scfail ghost` census line. So a triage reading the run log sees exactly
      which failed SCs presented a write and at which addresses. A genuine
      premature write would show up there as a store at an address or with a value
      the ghost census cannot explain.

  (c) **The full remedy is formal, not comparative.** `resv_unit`'s adjudication
      is the thing being taken as true, and the durable fix is to prove it rather
      than to sample it — the **`resv_unit` properties** step on the core-RTL
      roadmap (`~/vesta_docs/core_rtl_roadmap.md`). Lockstep structurally cannot
      supply it: §4.8's "atomicity is taken as true" is a statement about the
      method, not about this implementation. Cross-referenced here so the gap has
      an owner.
  Scale, measured: `shcount` hart 0 issued **29,096** loads at `0x10080` for
  **64** committed increments, so ~29,000 `F` records for one hart of one test.

### A11-A14 application order at one retire index (normative)

All four share the existing `--bracket` script channel and the reference's own
retire counter (the `minstret`-delta counter), identical to `B`/`S`. When several
apply at one index the order is **fixed and must not be reordered**:

1. `S` (bracket-interior store replay) and `P` (mainline plant) — memory first;
2. `G` — registers, after memory (a `G` never depends on RAM, but a fixed order
   makes a script reproducible);
3. `F` — reservation, after memory. **CORRECTED 2026-07-30 (V4 implementation):**
   the first draft of this clause justified the position by claiming "a plant to
   the reserved address must not be mistaken for the thing that broke the
   reservation". **That reason is wrong for this implementation and must not be
   repeated.** `poke()` writes the RAM array directly, bypassing `mmu_t`
   entirely, and `load_reservation_address` is mutated in exactly three places —
   the mmu ctor (`mmu.cc:28`), `store_conditional` (`mmu.h:290`) and
   `yield_load_reservation` (`mmu.h:258`). A plant therefore **cannot** break a
   reservation, and the P-vs-F order is **unobservable**. The order is fixed for
   script reproducibility, nothing more. Recorded explicitly so that nobody later
   "proves" this ordering with a test that cannot fail — the negative-control
   rule cuts both ways, and an ordering claim with no observable consequence is
   not a property, it is a convention;
4. `B` — the pc, **LAST**, per V3's existing ruled order (a REDIRECTED bracket's
   stacked-PC store must land before the pc it implies is installed).

**Logging:** `B`/`S`/`G` keep V3's per-application stderr line (they are rare —
one bracket per park). `P` and `F` are **counted only**, reported in the summary
as `plants=<applied>/<total>` and `scfails=<applied>/<total>`; at ~29,000 per
hart a per-application line would bury the log a triage reads. An unconsumed
`P`/`F` tail is a **loud warning**, exactly as the existing unconsumed `--inject`
tail already is — a plant that never fired means the reference read stale RAM
somewhere, which is the one failure mode of the whole design (`v4_design.md`
§3.5).

* **A15 (2026-07-30, V4) — the spurious failed-SC `M … S` record: a KNOWN,
  BOUNDED exception to §2's "committed transaction" contract.** §2/§8.

  **The measurement.** A globally-failed `sc.w` **still emits an `M … S` record**
  on the RTL side. Found INDEPENDENTLY by both V4 implementation lineages on the
  same workload, `rv32ua-p-shlrsc` hart 0, which has 6 `sc.w` retires of which 4
  report `rd`=1. Mechanism: the core's **local** reservation check
  (`reservation_valid` + address match) passes, so it drives `wen`, and the tracer
  samples the core's **port** (invariant 7 — the tracer records what the core
  presented). The write is then suppressed **downstream**, by `resv_unit`'s
  `s_we_gated` (`resv_unit.vhd:120-123`), and only `sc_fail_ext` returns to the
  core, which reports `rd`=1.

  **Proof that nothing committed — in-trace readback, two independent sites.**
  At line 216504-6 the trace shows
  ```
  R 00 0003ce01 0000836c 19c2aeaf 1d 00000001     <- sc.w, rd=1 = FAILED
  M 00 0003ce01 S 0001000c 4 000015b3             <- the ghost store record
  R 00 0003ce05 00008374 0002a383 07 0000115c     <- lw from the same address
  M 00 0003ce05 L 0001000c 4 0000115c             <- reads the OLD word back
  ```
  and at the other site the `0000dead` "store" to `00010044` is never observed by
  anyone: hart 1 later writes `01c0ffee` there and reads back `01c0ffee`.
  **Memory was not modified. This is NOT a silicon bug** — see
  `~/vesta_docs/lockstep/rtl_findings.md` finding T2 for the tracer-limitation
  note.

  **The rule.** An `M … S` that immediately follows an `sc.w` retire whose `rd`
  is nonzero is **DROPPED from the compared stream**, because it describes a write
  that never happened and would otherwise manufacture a divergence at every failed
  SC against a reference that correctly writes nothing (4 of 6 on `shlrsc`;
  ~29,000 on `shcount`). Bounded and loud, never silent:
  * only the record **immediately following** the failed retire is eligible — a
    retire owns at most one memory operation, so that adjacency is the whole of
    the association;
  * the oracle is `rd`, the **same** oracle `mk_inject` uses to emit `F`, so the
    two sides cannot disagree about which SCs failed;
  * if `rd` is unusable — A5 x-tainted, or written to `x0` so no result exists —
    **nothing is dropped and the case is printed as INDETERMINATE.** Refuse,
    never guess;
  * every application is counted per `(pc, addr)` identity and printed in the
    stderr summary (`A15 scfail ghost  N sc.w retire(s), M failed, K ghost
    store(s) dropped`), so a rule that starts firing beyond its rationale is
    visible in the run log — the A9 discipline, applied to a drop instead of a
    substitution.

  **This is NOT a "skip failed SC" switch.** A succeeding SC's store is left in
  place and compared normally, and its **absence** there is still `EXIT_DIVERGE`
  — so the M4b "success without a write" shape stays catchable. `compare.py
  --no-a15` is the negative control and is proven load-bearing: the same two
  streams exit 0 with A15 and **exit 1 without it** (`test_compare.py`, 5 cases,
  both polarities).

  **Consequence for A14, ruled the same day: the SC's `rd` is ASSERTED, not
  compared.** See the restatement inside A14 above.

* **A16 (2026-07-31, WT / finding T2) — the failed-SC ghost store is fixed AT
  SOURCE; A15 becomes a compatibility shim.** §2/§8, and it is the amendment
  that lets §2 mean what it says again.

  **What changed.** `vesta_tracer.vhd` gains one input, `sc_fail_ext` — the
  global SC verdict from `resv_unit`, already an existing `vesta` port. In
  `SC_CHECK`, a store presented with `sc_fail_ext = '1'` is **not recorded as an
  `M … S`**; the tracer emits

      # SCGHOST <hart> <cycle> <addr> <size> <data>

  instead, carrying the whole store it withheld. §2 defines `M` as a **committed**
  memory transaction; this write is suppressed downstream by `s_we_gated` and
  never reaches memory, so the record was describing a *presentation*. A15
  removed it from the compared stream after the fact; A16 stops it being claimed.

  **No holding mechanism is needed, and that is a measurement, not a
  simplification.** T2 was logged as "hold the SC's store record until
  `sc_fail_ext` resolves, then emit or drop", which presumes it resolves later.
  It does not: `vesta.vhd:92-95` contracts `sc_fail_ext` **stable by the end of
  the SC_CHECK cycle** (latched from the arbiter done for a stalled shared SC),
  and the core consumes it combinationally *in that same cycle* to select
  `amo_phase` `"101"`/`"100"` (`vesta.vhd:1930-1933`) — the very term that
  produces the SC's architectural `rd`. The tracer samples on the edge that ends
  that cycle, so the verdict is already there. A hold would have been dead
  machinery on the tracer's only timing-critical path.

  **X is REFUSED, not guessed** (the A5/A15 discipline). If `sc_fail_ext` is
  itself `x` the tracer cannot know whether the write committed, so it emits
  `# SCGHOSTX` and **keeps the store** — the conservative direction, because a
  kept ghost is caught downstream (by A15, or by the next load of that word)
  while a wrongly-dropped real store is invisible.

  **The port default is `'0'`, chosen for its FAIL-SAFE direction** (rule
  R-W4-12, learned on F10's `csr_rs1_zero`): an unwired instantiation reports
  "no external failure" and therefore behaves **exactly as the pre-A16 tracer
  did**, dropping nothing. The opposite default would silently delete every
  shared SC's store record.

  **The trace header now declares its vintage** — `format RECORD_FORMAT.md
  A1-A7,A16` — because traces and consumers are versioned independently and a
  pre-A16 trace must still compare correctly.

  **A15's status changes to COMPATIBILITY SHIM + x-FALLBACK; it is NOT deleted,
  and not only for the obvious reason.** The obvious one is that archived and
  quarantined pre-A16 traces exist (218 in
  `cosim_work/legacy_v3_logs.quarantine/` alone) and must still be comparable.
  The second is sharper: **A16 deliberately declines the `# SCGHOSTX` case, and
  A15 is what covers it** — A16 decides from the *cause* when the cause is
  readable, A15 from the *effect* (`rd`) when it is not. They are a division of
  labour, not duplicates. Consequently:
  * on a post-A16 trace the A15 census reads `… 0 ghost store(s) dropped`, and
    **that is the healthy reading**;
  * the `--no-a15` negative control becomes **inert on post-A16 traces** (exit 0
    either way) and **stays load-bearing on pre-A16 ones**. Its inversion is the
    proof that A16 removed the shape at source rather than merely moving
    numbers: the comparator no longer *needs* the exception;
  * a **nonzero** census on a trace declaring A16 means an `# SCGHOSTX` fired or
    `sc_fail_ext` is unwired. Both are findings, and the census prints either way.

  **`mk_inject` gains the same witness, and it is an upgrade rather than a
  rename.** Its `ext`/`local` failure-shape census counted `ext` from *the
  presence of a following store* — i.e. it was reading the very defect A15
  exists to delete as its own instrument. It now counts `# SCGHOST` (keeping the
  store test so pre-A16 traces still census correctly), which makes the two
  shapes symmetric: one dedicated diagnostic each, `# SCGHOST` external and
  `# SCFAILRD` local. A16 also makes a genuinely new cross-check possible, and
  it is reported (never used to override `rd`): **`rd`=0 alongside a
  `# SCGHOST`** means `resv_unit` suppressed the write while the core claimed
  success — the mirror image of the existing `rd`=0-with-`# SCFAILRD` check, and
  the same M4b shape.

  **What A16 does NOT buy.** The SC's `rd` remains **ASSERTED, not compared**
  (A14 as restated): `rd` is still the oracle `mk_inject` uses to emit `F`, and
  A16 changes nothing about that. The M4b "SC premature write" bug would still
  not be caught at the SC itself. A16 makes the trace HONEST; it does not make
  the SC verdict CHECKED.
