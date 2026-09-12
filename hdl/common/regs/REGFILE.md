# `periph_regs`: the house peripheral bus, written once

`hdl/common/periph_regs.vhd` implements the memory-mapped register protocol every
VestaRV peripheral speaks. A peripheral instantiates it, passes the tables its
`.rdl` already single-sources, and keeps only its datapath. The hand-written
`case` decode, the byte-lane merge, the registered read mux, the write-1-to-clear
arm and the strobe retirement stop being twenty-two independent transcriptions of
one protocol.

`hdl/common/tb/periph_regs_tb.vhd` is the unit bench; it exercises every mask
class and every byte lane against the module alone.

## The bus

| signal | sense | meaning |
|---|---|---|
| `ClkMem` | rising | the capture edge for writes, strobes and the read register |
| `resetn` | low | asynchronous, resets storage to `RSTVAL` |
| `EnMemPeriph` | low | peripheral selected |
| `WEn(3:0)` | low | byte-lane write enables; `"1111"` is a read |
| `MABPart(7:2)` | - | word slot inside the 256 B window |
| `wdata` / `rdata_out` | - | 32-bit data, read registered |

One access, one `ClkMem` cycle:

```
                 ___     ___     ___
 ClkMem      ___|   |___|   |___|   |___
 EnMemPeriph ____                    ____     select on a ClkMem falling edge
                 |__________________|
 MABPart     ----<      slot       >-----
 WEn         ----<  lanes / 1111   >-----
                 ^        ^         ^
                 |        |         `- strobes retire (STROBE_HOLD) / deselect
                 |        `- T: storage written, strobes set, rdata_out registered
                 `- the peripheral's own falling-edge pre-latch fires here
 rdata_out   ========< word read at T >====
```

`rdata_out` is a flop loaded every `ClkMem` edge from the decoded word. While the
peripheral is deselected the decode points at `WORD_BASE`, so an idle read
register holds word 0 - which is what every hand-written decode does today, and
the reason this is stated rather than fixed.

## Entity

```vhdl
entity periph_regs is
    generic (
        NWORDS      : natural;              -- words in the decode window
        WORD_BASE   : natural := 0;         -- first word inside the sub-slot
        RSTVAL, IMPL, W1C, WOSET, WOT,
        PULSE, RCLR, HWOWN : word_array;    -- from <block>_regs_pkg, one row per word
        RSTVAL_OR   : word_array := ...;    -- OR-ed onto RSTVAL: a reset that is a generic
        HWALIAS     : word_array := ...;    -- hookable beyond HWOWN: an alias word of this block
        RDTHRU      : std_logic_vector := "";   -- per word: read from hw_rd, not storage
        WIDEWR      : std_logic_vector := "";   -- per word: any enabled lane writes all 32 bits
        FULLWR      : std_logic_vector := "";   -- per word: only WEn = "0000" is a write at all
        STROBE_HOLD : boolean := false;         -- strobe retirement, see below
        REGISTERED_READ : boolean := true       -- false: rdata_out is the read mux itself
    );
    port (
        ClkMem, resetn, EnMemPeriph : in std_logic;
        WEn       : in  std_logic_vector(3 downto 0);
        MABPart   : in  std_logic_vector(7 downto 2);
        wdata     : in  word;
        rdata_out : out word;

        regs      : out word_array(0 to NWORDS-1);   -- the stored words, for the datapath
        wr_inhibit : in std_logic_vector(0 to NWORDS-1) := (others => '0');  -- refuse the write
        hw_rd     : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_we     : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_wdata  : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_set    : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_clr    : in  word_array(0 to NWORDS-1) := (others => (others => '0'));

        acc_hit   : out std_logic_vector(0 to NWORDS-1);  -- combinational: selected now
        rd_strobe : out std_logic_vector(0 to NWORDS-1);  -- per word
        wr_strobe : out std_logic_vector(0 to NWORDS-1);
        wr_pulse  : out word_array(0 to NWORDS-1);        -- per bit
        w1c_hit   : out word_array(0 to NWORDS-1);
        woset_hit : out word_array(0 to NWORDS-1);
        wot_hit   : out word_array(0 to NWORDS-1);
        rd_clr    : out word_array(0 to NWORDS-1)
    );
```

`word` and `word_array` come from `work.Constants`, which declares
`type word_array is array (natural range <>) of word` and which every peripheral
already `use`s. That is why there is no new shared package: the one shared type
the brief asks for has existed since the first commit, and a second declaration of
it - in `constants.vhd` under a new name, or in `regs/vhdl/` - would be a second,
incompatible type. `<block>_regs_pkg` declares only
`subtype reg_arr_t is word_array(0 to NWORDS-1)`, a constrained subtype of it, so
tables from different packages remain assignment-compatible. A hand-written file
under `regs/vhdl/` would also have to be exempted from
`//platform/common:rdl_vhdl_pkg_test`'s byte-compare, and that gate has no
exemptions for a reason.

## Property to mask, property to hook

Everything in the left column is a SystemRDL property of a field in
`hdl/common/regs/rdl/<block>.rdl`. Nothing in the right column is special-cased
per block inside the module.

| `.rdl` | count | mask | what `periph_regs` does |
|---|---|---|---|
| `sw=rw`, `hw=r`/`na` | 393 / - | `IMPL` | holds the flop; lane write replaces, read returns it |
| `sw=r`, `hw=w` | 146 | none (outside `IMPL`) | holds nothing; the read comes from `hw_rd` |
| `sw=w` | 17 | `IMPL` | holds the flop; add the word to `RDTHRU` with `hw_rd = 0` where the register reads 0 |
| `hw=w` / `hw=rw` | 194 / 32 | `HWOWN` | permits `hw_we`/`hw_set`/`hw_clr` on that bit. A bit outside `IMPL and HWOWN` gets no hook logic at all, so a hook wired to one would be dropped; the assertion in section "Ownership" says so instead |
| `hw=na` | 19 | - | software-only; hardware hooks on such a bit assert |
| `onwrite=woclr` | 69 | `W1C` | `w1c_hit` pulses the bit a 1 was written to; the flag's flop stays with the hardware that sets it |
| `onwrite=woset` | 2 | `WOSET` | `woset_hit`, same shape |
| `onwrite=wot` | 1 | `WOT` | `wot_hit`, same shape |
| `singlepulse` | 9 | `PULSE` | `wr_pulse`, one strobe per written 1; no storage |
| `onread=rclr` | 1 | `RCLR` | `rd_clr` pulses on a read of that word |
| reset value | - | `RSTVAL` | asynchronous reset of the stored words |

Three generics are the RTL's, not the description's, because SystemRDL cannot
express them:

- **`RDTHRU`**, per word. The read value does not come from the module's storage.
  `TIMxVAL` is `sw=rw hw=rw` and stored here as the write staging word, while the
  read comes from the counter's clock-domain-crossing copy. `DMAxCR`'s
  `GO`/`ABORT` are `sw=w` and read 0.
- **`WIDEWR`**, per word. Any enabled lane writes all 32 bits. `TIMxVAL` has no
  byte lanes (`config/rdl.json` says so); every other word merges per lane.
- **`FULLWR`**, per word. Only a four-lane write (`WEn = "0000"`) is a write to
  the word at all; a partial write is dropped whole and is not a read either.
  It is the inverse of `WIDEWR`, not its complement: `WIDEWR` widens a partial
  write to 32 bits, `FULLWR` refuses it. SYSTEM's `WDTPASS` is the one word in
  the tree that needs it, because a password compared against half a word is a
  password guessed a byte at a time.
- **`STROBE_HOLD`**, per block. Which of the two strobe retirements the peripheral
  needs; see below. It is a property of who CONSUMES the strobe.
- **`REGISTERED_READ`**, per block. See "The read path" below.
- **`RSTVAL_OR`**, per bit, OR-ed onto `RSTVAL`. The one thing a reset value can
  be that SystemRDL cannot describe: a GENERIC of the peripheral. I2C's slave
  address resets to `default_SAD` (0x79 on I2C0, 0x23 on I2C1) and GPIO's `PxOUT`,
  `PxDIR`, `PxSEL`, `PxREN` and `PxAFS` to the `RstValPx*` generics, all per
  instance. Left at its one-row default it is all zero and `RSTVAL` stands; an
  elaboration assertion refuses a bit outside `IMPL`, which would set a flop that
  does not exist.
- **`HWALIAS`**, per bit, in ADDITION to `HWOWN`. See "Alias words" below.

## Ownership: a flop lives with whoever sets it

`periph_regs` holds exactly the `IMPL` bits - the software-written storage. It does
NOT hold a W1C flag, because a flag is set by hardware, frequently on another
clock, and its set/clear ordering is the peripheral's business. The module emits
`w1c_hit` and the peripheral clears its own flop with it, which is byte for byte
what `clr_UTCIF` and `clear_compare0_flag` already are.

What stays in the peripheral:

- the datapath, the FSMs and every clock domain but `ClkMem`;
- hardware-set flags, their CDC and their set-wins-over-clear ordering;
- the falling-`EnMemPeriph` pre-latch of asynchronous read values. The module does
  not offer one: which of a peripheral's signals are asynchronous to `ClkMem` is a
  CDC judgement, and the existing `reg_sync` processes (inverted storage included)
  stay where they are and keep feeding `hw_rd`;
- read side effects beyond `rclr`: a FIFO pop, a claim, a consume. `rd_strobe` is
  the hook. `rd_strobe or wr_strobe` is the hook for "any access to this slot",
  which is what `UARTxRX` and `SPIxRX` mean today.
  `acc_hit` is the one unregistered hook: a write that LAUNCHES a transaction on
  the edge it lands (`QSPIxCMD`, `UARTxTX`, `OWxCMD`) qualifies it with its own
  `WEn(0)`, exactly as the raw decode did, and so does not slip a cycle.

On a stored bit the module resolves a coincident software write and hardware hook
in this order: lane write, `hw_we`, `hw_set`, `hw_clr`. Hardware beats a coincident
CPU write, and clear beats set - the safe direction for an enable, and exactly
TIMER's `task_start` then `task_stop`.

A hook wired to a bit outside `IMPL and HWOWN` reaches no logic, because the hook
path for such a bit is not built. A concurrent assertion, fenced with
`-- pragma translate_off` so it costs no gate, reports that instead of leaving the
drop silent: the `.rdl` and the RTL disagree about who owns the bit, and one of
them has to change.

## The read path: registered here, or registered by the fabric

`REGISTERED_READ` defaults to `true` and is the flop every hand-written decode in
the tree has: `rdata_out` is loaded from the read mux on every `ClkMem` edge.

`false` makes `rdata_out` the read mux itself, unregistered. It exists for one
reason: `I2C.vhd`'s read has always been combinational (`with MABPartInteger
select rdataPart <=`), and `MCU.vhd` carries an `i2c_rdata_bridge` that registers
it on the mclk edge while the access strobe is high. Two flops in series would
land the data a cycle after the arbiter captures it. Either the module offers the
combinational path or the bridge is deleted, and the bridge is in generated
`MCU.vhd`, guarded by a `combinationalRead` metadata check in
`platform/common/python/mcu_vhd.py`; the generic is the change that is local to
the block. The two paths are timing-equivalent at the bus by construction, and
`periph_regs_tb` GROUP 11 proves it on one access: the value the combinational
instance presents BEFORE the capture edge is bit for bit the value the registered
instance presents AFTER it, so a flop clocked on that edge sees the same word
either way.

Both paths park on `WORD_BASE` while deselected, so a combinational `rdata_out`
collapses to word 0 on deselect - which is exactly what `I2C.vhd` does today, and
what the bridge exists to catch.

## `wr_inhibit`: a write the peripheral refuses

`wr_inhibit(i) = '1'` makes the access neither a write nor a read of word `i`.
Storage, `wr_strobe(i)` and every write-1 arm on that word are suppressed
together, because a refused write is not half an access; `acc_hit(i)` still
reports that the word is addressed, and a read (`WEn = "1111"`) is unaffected.

It is a PORT and not a mask because the qualifier is live state: SYSTEM's
`WDTCR` takes writes only inside the 64-cycle window a correct `WDTPASS` opens,
so the inhibit is `not unlocked`, not a property of the description. A condition
that IS a property of the description belongs in the tables.

## Sparse tables: a register set with gaps

The tables are indexed by WORD, not by register. A block whose registers do not
occupy a contiguous run of slots - SYSTEM (words 0-4 and 12-17), EVFAB (0-11, 15
and 16-31) - gets a row for every word from the first to the last, with an
all-zero row named `_reserved_<word>` for each gap. `IMPL = 0` gives such a word
no flop, no hook logic and no arm; it reads 0, which is what the `when others`
arm of each hand-written decode returns today.

Sparse rather than a second instance per run. A gap costs the two per-word strobe
flops and nothing else (14 in SYSTEM, 6 in EVFAB), while a second instance would
need a second read mux, a second strobe set and an `rdata_out` merge inside the
peripheral - the decode this module exists to delete. `WORD_BASE` moves the whole
window instead, and is for a block that sits at an offset inside someone else's
256 B slot, not for a gap.

`rdl_vs_vhdl_test`'s regfile reader skips exactly the `_reserved_<word>` spelling
when it maps a row back to a register; a VHDL identifier cannot begin with an
underscore, so the name can never collide with one.

## Alias words: one storage word, several addresses

A set/clear/toggle alias is a separate WORD that acts on another word's storage:
GPIO's `PxOUTS` / `PxOUTC` / `PxOUTT` onto `PxOUT`, EVFAB's `EVFCHENSET` /
`EVFCHENCLR` onto `EVFCHEN`. The module already expresses it - the alias word
holds no storage, its `WOSET` / `W1C` / `WOT` mask arms `woset_hit` / `w1c_hit` /
`wot_hit`, and the peripheral wires that to the storage word's `hw_set` /
`hw_clr` / `hw_we` - with one catch.

**The catch is `HWOWN`.** An alias write is SOFTWARE writing, so the description
correctly says `hw=r` on the target, and a hook on a bit outside
`IMPL and HWOWN` reaches no logic and asserts. GPIO needs nothing extra only
because its `PxOUT` really is hardware-driven (the event fabric's `task_outset` /
`task_outclr`). EVFAB's `EVFCHEN` is not. `HWALIAS` is where the RTL says so:
the hook mask is `IMPL and (HWOWN or HWALIAS)`, and the ownership assertion uses
the same mask, so it still catches a hook on a bit nobody claims. Use it ONLY for
a cross-word alias inside the block; a hook that really is hardware's belongs in
the `.rdl`.

**Which hook, registered or not, is a timing question.** The arms are flops set on
the access edge, so a storage word takes an alias write one `ClkMem` edge later
than a hand-written decode did. That is correct where `ClkMem` free-runs (GPIO:
its fabric tasks act outside the `en` gate, so it must). Where `ClkMem` is GATED
by the select there may be no edge after the access at all, and the write would
be lost: EVFAB is that case, and its aliases take `acc_hit` qualified with their
own lane instead, which lands on the access edge exactly as the case arm did.

## Strobe retirement: two idioms, one generic

Every strobe (`rd_strobe`, `wr_strobe`, `wr_pulse`, `w1c_hit`, `woset_hit`,
`wot_hit`, `rd_clr`) is a flop set on the `ClkMem` edge of the access. They differ
only in how they retire, and the two forms are NOT interchangeable:

| `STROBE_HOLD` | retirement | width | for a consumer that is |
|---|---|---|---|
| `false` | synchronous: cleared on the next `ClkMem` edge | one `ClkMem` cycle | synchronous on `ClkMem` (UART's flag process) |
| `true` | asynchronous: cleared while `EnMemPeriph` is high | select-to-deselect | level-sensitive in another clock domain (TIMER's `capture0_process`, QSPI's `fsm_proc`) |

Pick `true` when the strobe reaches an asynchronous clear or load in a gated or
foreign clock domain, `false` when it is sampled on `ClkMem`. Getting it wrong is
not subtle: a held strobe never spans the consumer's next `ClkMem` edge and the
event is lost; a synchronous pulse on an async clear is a wider pulse than today.

## Migration recipe

1. Read the block's decode and write down, per word: which bits software stores,
   which the hardware drives, which read value is asynchronous, and what a read or
   a write does beyond storing. This is the only step that needs judgement.
2. Add the block to `rdl_vhdl._REGFILE` and regenerate:
   `tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs`. The package gains
   `NWORDS`, `reg_arr_t` and the eight tables. Nothing existing moves, so
   `rdl_vhdl_pkg_test` and `rdl_pkg_vs_legacy_test` stay green.
3. Replace the `case` decode, the read mux and the strobe retirement with one
   `periph_regs` instance. Keep the `reg_sync` pre-latch and feed `hw_rd`.
4. Replace each `SIGNAL_REG(a downto b)` field read with
   `regs(W_x)(FIELD_MSB downto FIELD_LSB)`, so no bit literal survives.
5. `ghdl --synth` before and after and compare cell and latch counts. Zero latches
   is a requirement, not an observation.
6. Update the block's `require` list in
   `platform/common/python/rdl_vs_vhdl_test.py` and set `regfile=<package>` on its
   entry, so the gate reads the instance instead of the case decode it no longer
   has.
7. The bench is the oracle. If it does not cover a register, add the case BEFORE
   the migration, so the proof is not hollow.

### Blocks whose description and RTL disagree, and where that lands

Three registers are `sw=rw` in the `.rdl` and stored by nothing in the RTL, so the
module holds storage for them and `RDTHRU` keeps the read at 0: SYSTEM's
`WDTPASS` (32 bits, a password port), EVFAB's `EVFCHTRIG` (8) and `EVFEVTRIG`
(16, both action slots decoded in another clock domain). That is 56 flops nothing
reads. Correcting the description rather than the RTL is the fix, and it is a
`.rdl` change with its own gate sweep, not a migration edit.

Shared files a per-block migration must NOT touch: `hdl/common/periph_regs.vhd`,
`hdl/common/constants.vhd`, `hdl/common/tb/periph_regs_tb.vhd`, this file,
`platform/common/python/rdl_model.py`, `platform/common/python/rdl_vhdl.py` beyond
adding the block's own `_REGFILE` entry, any other block's `_regs_pkg.vhd`, and
`rdl_pkg_vs_legacy_test.py` with `rdl_legacy_constants.json` - the frozen
independent copy, and the one leg of the argument that does not run through the
`.rdl`. A per-block need that the module cannot meet is a brief for its own wave,
not an edit in passing.
