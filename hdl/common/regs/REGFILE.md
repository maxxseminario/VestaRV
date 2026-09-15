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

One access, one `ClkMem` cycle. **`ClkMem` FREE-RUNS**: `MCU.vhd` wires every
peripheral's `ClkMem` to the ungated `mclk`, and `EnMemPeriph` selects the block
for one rising edge of it.

```
                 ___     ___     ___
 ClkMem      ___|   |___|   |___|   |___
 EnMemPeriph ____                    ____     select on a ClkMem falling edge
                 |__________________|
 MABPart     ----<      slot       >-----
 WEn         ----<  lanes / 1111   >-----
                          ^         ^
                          |         `- strobes retire (STROBE_HOLD) / deselect
                          `- T: storage written, strobes set, rdata_out registered
 rdata_out   ========< word read at T >====
```

**T, the one rising `ClkMem` edge inside the select window, is the whole timing
of the protocol.** Nothing in the bus is clocked by `EnMemPeriph` or by anything
derived from it: the select reaches the decode combinationally, the storage, the
strobes and the read register are all on rising `ClkMem`, and the only place
`EnMemPeriph` appears on a control pin is `STROBE_HOLD`'s asynchronous strobe
clear, which is a level and not an edge.

`rdata_out` is a flop loaded every `ClkMem` edge from the decoded word, so a read
returns the decoded word **as it stands at T**: a source that moves between the
select and T is returned whole at its new value, and one that moves after T is
not seen until the next access. The word is one register's value from one edge -
the read mux selects exactly one row and one flop captures it - so it can never
be a mixture of two instants. `periph_regs_tb` GROUP 13 is that case, driven with
two values that differ in every bit but 31 (which the bench's `img` cannot format).

While the peripheral is deselected the decode points at `WORD_BASE`, so an idle
read register holds word 0 - which is what every hand-written decode does today,
and the reason this is stated rather than fixed.

### The peripheral side: what T implies for a volatile word (2026-09-15, Z1 and Z2b)

Until 2026-09-15 eight peripherals snapshotted their volatile status and receive
words on `falling_edge(EnMemPeriph)` - a flop whose clock pin was the address
decode - and fed the snapshot to `hw_rd`. **None of them does now.** The
replacement is stated once here because it is the same in all of them, and it is
what makes T a legitimate snapshot edge for a word the block does not own:

| word shape | how it reaches `hw_rd` | age at T |
|---|---|---|
| already in the `ClkMem` domain (GPIO's `PxIF` and `prt_in_s2`, UART's whole `UART_SR`) | read directly | 0 edges: the flop's value before T |
| a FLAG word, n independent bits (`SPIxSR`, `I2CxSR`, `QSPIxSR`, `I3CxSR`, TIMER's status) | `work.sync` `WIDTH = n`, `DEPTH = 2`, on `ClkMem` | 2 edges |
| a DATA word whose validity a flag carries (`UART_RX`, `SPIxRX`, `QSPIxRX`, `I3CxRX`, `I2CxMRX`, `I2CxSRX`, `TIMxCAP0/1`) | the source domain flips a TOGGLE when it writes the word; the toggle crosses on `work.sync`; a `ClkMem` flop copies the whole word on the synchronized edge | 2 edges, and the copy holds until the next event |
| a word that changes every cycle (`TIMxVAL` alone) | gray mirror, `work.sync` `WIDTH = 32`, one decode register | 2 edges |
| a BINARY word that may not cross bit by bit at all (`NFCxSR.NFCSTATE`) | a four-phase MCP handshake: the source holds the word and flips a request, the destination captures it whole on the synchronized request edge and answers | 2 edges plus the handshake's own round trip, and a change arriving while one is in flight waits |

A read therefore returns a value up to **two `ClkMem` edges older** than the
select edge. Nothing in the bus protocol depends on the age of the datum, only on
its coherence, and both shapes above are coherent by construction: a flag word's
bits are independent, so a per-bit chain cannot assemble a word that was never
present, and a data word is copied whole by one flop at one edge.

Two places where two edges of age WOULD change the register contract, and what
each block does instead:

- **A launch the firmware polls for.** `SPIxSR.SPIBUSY` and `QSPIxSR/I3CxSR.BUSY`
  must read 1 on the access right after the write that launched the transfer.
  Each block ORs a **launch-pending** bit into the read: a `ClkMem` flop set by
  the same `wr_hit`/`acc_hit` the launch takes and retired at the first `ClkMem`
  edge where the synchronized BUSY reads high. The two overlap, so the level
  never dips mid-transfer.
- **A write-1-to-clear the firmware reads back.** The flags are cleared
  ASYNCHRONOUSLY in their own domains, so a clear needs the same two `ClkMem`
  edges to travel back through the synchroniser that the set needed coming in.
  Each block masks the read with a **clear shadow**: the armed W1C pattern, held
  over exactly those two edges. A flag therefore retires on the next access as it
  did off the pre-latch, and a hardware set inside the window is not lost,
  because the source flag is sticky and reappears when the mask retires. The
  shadow is armed from the COMBINATIONAL `wr_hit`/`acc_hit`, valid AT T; the
  registered `w1c_hit` levels rise after T and (under `STROBE_HOLD`) retire on
  deselect, so no `ClkMem` edge ever samples them high.

**NFC, the eighth block (Z2b).** Its four volatile words take three of the four
shapes at once and are worth naming, because the next block with a hard word will
look like one of them. `NFCxSR` splits: eight independent flag and level bits on a
`work.sync` `WIDTH = 8` chain, and `NFCSTATE` on the MCP row above, a SECOND
handshake behind the `rf_clk` one R14b built, because the 4-bit ISO state is binary,
gray coding is provably unavailable for it (see the comment at `state_mcp_src`) and
no ratio of `ClkMem` to `clk` is guaranteed. `NFCxRXST` and the nine live receive
bytes take the DATA row, published together on one `rf_clk` toggle when the receive
group goes final. `NFCxDBG` takes the DATA row rather than a gray mirror even though
it is two counters: they step once per FRAME, four orders of magnitude slower than
the two-edge sync latency, and one shared toggle keeps the 32-bit word coherent
across both halves, which per-counter gray coding would not. `NFCxDATA`'s payload
half needs no crossing at all - it is written on `ClkMem` - and is read
combinationally into `periph_regs`' own read register at T, with the pre-increment
index, which is the byte the pre-latch captured at the select.

### A held strobe is only as wide as the fabric's select (2026-09-15, Z1)

`STROBE_HOLD = true` retires the strobe ASYNCHRONOUSLY while `EnMemPeriph` is high,
so **the strobe's width is the fabric's, not the module's**. In `MCU.vhd` the
arbiter's `s_en` is a registered one-cycle strobe that self-clears on the very edge
the slave captures, so a shim carrying the RAW select deasserts `EnMemPeriph` on
that same mclk edge and the held strobe is a runt. The blocks that pre-latched were
shielded from this by their falling-mclk `en_q` shim, which put the deselect half a
cycle after the capture edge; removing the shim removes the shield.

**A peripheral must therefore not rely on a held strobe to reach an asynchronous
clear or load in another clock domain.** The seven converted blocks OR their held
strobe with a `ClkMem` level of their own: the combinational access condition
(`wr_hit` / `acc_hit` qualified by its lane) plus the two stages of the clear shadow,
about two and a half `ClkMem` periods, generated in `ClkMem` and independent of the
select. It is additive - the held strobe still contributes - and it costs 2 flops per
level. The price is that a hardware SET landing inside that window is swallowed, where
the old half-cycle window would have kept it; every event in these blocks is at serial
bit rate, orders of magnitude slower than two `mclk` periods.

**`SYSTEM` was the one block genuinely exposed (closed by Z2b).** Its four bus levels
-- `unlock`, `clr_wdt`, `clr_wdt_rf` and `clr_wdt_if` -- each reach a process clocked or
reset in another domain, and `clr_wdt_if` is sampled SYNCHRONOUSLY on `clk_wdt`, so a
select-wide level reached no edge of it at all. All four now take the same additive
`clk_mem` level. `SYSTEM_tb` GROUP 5d measures the WIDTH at the signal rather than the
value, because an event simulator resolves the race in delta cycles and can show the
clear landing anyway: 50 ns before, 250 ns after, against a 100 ns bus period.

**`DMA` was never exposed, and the reason is the pattern to copy.** Every
`periph_regs` strobe port in `DMA.vhd` is left `open`. Each of its five commands
(`CHnGO`, `CHnABORT`, the two SR write-1-to-clear requests and the CRC seed commit)
is armed from the COMBINATIONAL `acc_hit` into a `ClkMem` flop that flips a toggle,
and the toggle is what crosses. A block built that way has no held strobe to be a
runt. `DMA_tb` GROUP G-SEL is the standing proof: every access in it is a plain
single-cycle `bus_write`.

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
        rd_hit    : out std_logic_vector(0 to NWORDS-1);  -- ... and WEn = "1111"
        wr_hit    : out std_logic_vector(0 to NWORDS-1);  -- ... and a lane write that lands
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
| `sw=w` | 17 | none | a COMMAND, not a register: holds nothing whatever its width, reads 0 (`IMPL = 0` already sources the read from `hw_rd`), and the peripheral consumes it on the access that carries it - `wr_pulse` where the field is `singlepulse`, `wr_hit` / `wr_strobe` plus the raw bus `wdata` where it is wider |
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
  read comes from the counter's clock-domain-crossing copy. A word that is
  write-only in its ENTIRETY does not need it: `IMPL = 0` sources the read from
  `hw_rd` already, and `WDTPASS` / `EVFCHTRIG` / `EVFEVTRIG` keep their `RDTHRU`
  row only as the file's statement of intent.
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
- the CDC that carries an asynchronous read value into `ClkMem`. The module does
  not offer one: which of a peripheral's signals are asynchronous to `ClkMem` is a
  CDC judgement, and the `work.sync` chains and event-toggle copies that replaced
  the old `reg_sync` pre-latches stay where they are and keep feeding `hw_rd`;
- read side effects beyond `rclr`: a FIFO pop, a claim, a consume. `rd_strobe` is
  the hook. `rd_strobe or wr_strobe` is the hook for "any access to this slot",
  which is what `UARTxRX` and `SPIxRX` mean today.
  `acc_hit`, `rd_hit` and `wr_hit` are the unregistered hooks: a write that
  LAUNCHES a transaction on the edge it lands (`QSPIxCMD`, `UARTxTX`, `OWxCMD`)
  qualifies `acc_hit` with its own `WEn(0)`, exactly as the raw decode did, and so
  does not slip a cycle; where the direction is the whole qualifier, `rd_hit` and
  `wr_hit` carry it already. See "Which hook" below.

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

**The Z1 wave did not retire the bridge, and deliberately.** Once I2C's status and
receive words are `ClkMem` copies (above), `REGISTERED_READ = false` plus the
bridge and `REGISTERED_READ = true` with no bridge present the same word at the
same edge - the bridge captures `rd_comb` on the rising `mclk` edge of the access,
which is T. What separates them is only WHERE the flop sits, and moving it changes
the emitter (`combinationalRead` metadata, `crossCheck`'s bridge membership, the
I2C1 template) and the NPU's half of the same bridge, which no part of this wave
touched. That is a brief of its own; nothing in the pre-latch removal depends on it.

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

## Which hook: `rd_hit` / `wr_hit`, the registered strobes, or `acc_hit`

Three hooks report the same access. They differ in when they are valid and in how
much of the decode they carry.

| hook | timing | qualifier | use it when |
|---|---|---|---|
| `acc_hit(i)` | combinational, valid during the access | selected and addressed, nothing else | the side effect is direction-blind (NFC's `NFCxDATA` index auto-increment fires on a read as much as a write), or the block adds a qualifier the module does not have: a byte lane other than "any" (`WEn(0)`, `WEn(1)`), or a `wdata` bit |
| `rd_hit(i)` / `wr_hit(i)` | combinational, valid during the access | `rd_hit`: `WEn = "1111"`. `wr_hit`: a lane write that survives `FULLWR` and `wr_inhibit` | the side effect must land on the access edge AND the direction is the whole test. Mandatory where `ClkMem` is GATED by `EnMemPeriph`: the access is one rising edge, so a registered strobe is sampled a whole bus access late |
| `rd_strobe(i)` / `wr_strobe(i)` | flop set on the access edge, retired per `STROBE_HOLD` | the same as `rd_hit` / `wr_hit` | the consumer is downstream of the access edge and `ClkMem` free-runs: a `ClkMem`-synchronous flag process, or a level into another clock domain (`STROBE_HOLD = true`) |

`rd_hit` and `wr_hit` are `rd_strobe` and `wr_strobe` BEFORE the flop, so the
condition is bit for bit the same and only the timing differs. `acc_hit` is their
OR, minus the `FULLWR` and `wr_inhibit` refusals - which is the one place the
three genuinely disagree, and why `wr_hit` is not `acc_hit and not WEn(0)`:
a FULLWR partial write and an inhibited write both raise `acc_hit` and neither
raises `wr_hit`.

A block whose hand-written test is a LANE test rather than a direction test
(`acc_hit(i) and not WEn(0)`, which is most of the tree) keeps `acc_hit`: `wr_hit`
is any-lane, so substituting it would accept a lane-3-only write the old decode
dropped. The exception is a block that already makes every write lane-0 through
`wr_inhibit` - EVFAB - where the two are the same signal.

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

## A register set that is a function of a generic

CLINT, MUTEX and PWRCTRL have a register SET, not just a register value, that
moves with the configuration: CLINT has one `MSIP` and one 64-bit `MTIMECMP` per
hart and its `mtime` word base is `ceil(4*NHARTS/16)*4`, MUTEX has `NMUTEX`
identical words whose owner field is `MW` bits wide, PWRCTRL has one `PWRCR` gate
bit and one `TASKWKM` bit per tile hart and `ceil(NHARTS/8)` `PWRSR` words. A
constant aggregate cannot say any of that, so **their eight tables are FUNCTIONS
of the block's own generics**, declared in `<block>_regs_pkg` and defined in a
package body in the same file:

```vhdl
    constant NW : natural := NWORDS(NHARTS, MTIME_W, CMP_W);
    ...
    u_regs: entity work.periph_regs
        generic map (NWORDS => NW,
                     RSTVAL => RSTVAL(NHARTS, MTIME_W, CMP_W),
                     IMPL   => IMPL(NHARTS, MTIME_W, CMP_W), ...)
```

VHDL-2008 allows a constant array built by a function of a generic at
elaboration, so the call is folded before synthesis and **costs no hardware**:
the `ghdl --synth` flop delta of all three migrations is exactly `2 * NWORDS`,
which is `periph_regs`' per-word `rd_strobe` / `wr_strobe` pair that none of the
three connects, and the storage bit count is unchanged.

**Chosen over emitting one package per configuration.** That would have made the
package a function of the chip config: `vhdl/` would carry N files per block, the
generator would have to select one, and `rdl_vhdl_pkg_test`'s byte-compare would
need a configuration to compare at. A function keeps ONE tracked package per
block, which is the invariant the whole toolchain rests on.

**What keeps the layout recipe honest.** The recipe -- which word holds which
register, and what each of the eight rows is -- lives in `rdl_vhdl._REGFILE_FN`,
which is Python beside the `.rdl` rather than in it. Two things stop it drifting:

- every row value is either a constant the package ALREADY emits (`MSIP0_RESET`,
  `PWRWAKE_IMPL`, `MTXOWN0_LSB`) or a `bitRun` of the function's arguments, so
  the numbers still come from the description;
- `_checkRegfileFn` re-elaborates the `.rdl` at EVERY configuration in the
  block's `variants` entry -- the same list `rdl_vs_vhdl_<block>_test`
  elaborates -- and compares the recipe's rows against the description's, word by
  word and table by table. A recipe that disagrees fails the emission, and
  therefore `//platform/common:rdl_vhdl_pkg_test`.

The entity side is read by `rdl_vs_vhdl_<block>_test`'s `require` list, which
carries `<TABLE> => <TABLE>(<generics>)` for all eight: the decode the block runs
on is the package's, not a hand-written copy.

**IRQROUTER cannot adopt the module at all**, whatever the tables are made of.
`CLAIM` is at word 512 and the status words at 516-523, so its decode window is
524 words wide, while `periph_regs` decodes 64: `MABPart` is six bits and
`WORD_BASE + NWORDS <= 64` is an elaboration assertion. A second instance does
not help, because `WORD_BASE` is inside the same 64-word slot. Widening the
module's window is a change to the shared file and a brief of its own.

**CLINT's hart count is capped at 20 by that same window.** Its file is
`CMP_W + 2*NHARTS` words, which crosses 64 at `NHARTS = 21`; `clint.vhd` asserts
it. Every shipped configuration is at or below 18 harts (argus, 60 words), and
the `.rdl` still describes 1 to 32.

## Migration recipe

1. Read the block's decode and write down, per word: which bits software stores,
   which the hardware drives, which read value is asynchronous, and what a read or
   a write does beyond storing. This is the only step that needs judgement.
2. Add the block to `rdl_vhdl._REGFILE` and regenerate:
   `tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs`. The package gains
   `NWORDS`, `reg_arr_t` and the eight tables. Nothing existing moves, so
   `rdl_vhdl_pkg_test` and `rdl_pkg_vs_legacy_test` stay green. A block whose
   register SET is a function of a generic goes in `_REGFILE_FN` with a layout
   recipe instead, and declares `subtype reg_arr_t` itself off `NWORDS(...)`; see
   the section above.
3. Replace the `case` decode, the read mux and the strobe retirement with one
   `periph_regs` instance. Carry every volatile read value into `ClkMem` by the
   table in "The peripheral side" above and feed `hw_rd`; never clock a flop from
   `EnMemPeriph`.
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

### A write-only field holds nothing (owner decision, 2026-09-11)

`rdl_vhdl.storageMask` used to put a `sw=w` field in `IMPL` unless it was
`singlepulse`, and SystemRDL restricts `singlepulse` to a ONE-BIT field
(`Field 'EVFCHTRIG' marked as 'singlepulse' shall have width of 1`), so every
write-only field 2 bits or wider carried a flop software wrote, nobody read and
nothing drove. The rule is now width-blind: **`sw = w` never reaches `IMPL`.**

It lands in no mask at all rather than in `PULSE`. `PULSE` stays exactly the
`singlepulse` mask, so the one-bit behaviour is untouched, and spelling a wide
field as `PULSE` would cost more than it saves: `ACT_ANY` is the union of `W1C`,
`WOSET`, `WOT` and `PULSE` over every word and sizes the shared `sw1_q` register,
so a 32-bit `PULSE` row on `WDTPASS` would grow SYSTEM's `sw1_q` from 2 bits to 32
and turn a 32-flop saving into a 2-flop one. Every consumer in the tree already
reads the RAW BUS `wdata` on the access that carries it, so no RTL behaviour
changes.

Seven `_IMPL` values move, each one line in the frozen
`platform/common/python/rdl_legacy_constants.json`: `WDTPASS` `0xFFFFFFFF -> 0x0`,
`EVFCHTRIG` `0xFF -> 0x0`, `EVFEVTRIG` `0xFFFF -> 0x0`, `DMAxCR`
`0x31FF -> 0x3001` (`DMAGO`, `DMAABORT`), and in the unmigrated `debug_module`
package `DMCONTROL` `0xD3FF000D -> 0x83FF0009`, `DMCOMMAND` `0xFFFFFFFF -> 0x0`,
`DMCS2` `0x7F -> 0x7D`. Measured with `ghdl --synth --std=08 -fsynopsys
--latches`, 0 latches throughout: **EVFAB 380 -> 356 flop bits, SYSTEM's register
file 179 -> 147, DMA 1040 -> 1032; -64 in total.** (SYSTEM is measured on a
wrapper around `periph_regs` carrying `system_regs_pkg`'s tables, because
`ghdl --synth` on the whole block aborts with a GHDL bug, before and after alike.)
`debug_module` does not `use` its package, so its three rows cost no flops today
and exist so that it cannot adopt one that is wrong.

Shared files a per-block migration must NOT touch: `hdl/common/periph_regs.vhd`,
`hdl/common/constants.vhd`, `hdl/common/tb/periph_regs_tb.vhd`, this file,
`platform/common/python/rdl_model.py`, `platform/common/python/rdl_vhdl.py` beyond
adding the block's own `_REGFILE` entry, any other block's `_regs_pkg.vhd`, and
`rdl_pkg_vs_legacy_test.py` with `rdl_legacy_constants.json` - the frozen
independent copy, and the one leg of the argument that does not run through the
`.rdl`. A per-block need that the module cannot meet is a brief for its own wave,
not an edit in passing.
