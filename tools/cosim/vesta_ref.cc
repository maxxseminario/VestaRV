// ---------------------------------------------------------------------------
// vesta_ref.cc -- VestaRV lockstep reference model (Spike libriscv, phase V3).
// ---------------------------------------------------------------------------
//
// WHAT THIS IS
//
//   A standalone reference model built on Spike's `libriscv` that does NOT use
//   `sim_t`.  We implement `simif_t` (riscv/simif.h) ourselves and drive
//   `processor_t` directly.  Consequences, all of them load-bearing for V3:
//
//     * WE OWN THE WHOLE ADDRESS SPACE.  `sim_t`'s constructor unconditionally
//       does `bus.add_device(DEBUG_START /*0x0*/, &debug_module)`
//       (riscv/sim.cc:72) and `debug_module_t::size()` returns PGSIZE
//       (riscv/debug_module.cc:289), so under `sim_t` the region [0x0,0x1000)
//       can NEVER be RAM.  VestaRV boots at pc=0x0 out of a 16 KB boot ROM.
//       With our own simif_t there is no debug module at all.
//     * No DTB, so no forked `dtc`; no HTIF, so no tohost/fromhost spin; no
//       `--extlib`/`--device` plugin plumbing (which `--disable-dtb` silently
//       breaks anyway).
//     * MMIO callbacks at any page-aligned window, and exact single-stepping.
//     * ZERO modifications to Spike's source.  All ISA semantics still come
//       from the pinned libriscv (3d8eb089bd289c59dcb506f197a172e02beb7b5b).
//       `git status --porcelain` in ~/local/src/spike-src staying EMPTY is the
//       whole D1 argument -- never patch Spike to make this file work.
//
// BUILD (see build_vesta_ref.sh for the tracked, reproducible recipe)
//
//   $CXX -std=c++20 -O2 -I$HOME/local/include \
//        -o <out>/vesta_ref vesta_ref.cc -L$HOME/local/lib -lriscv
//
//   where $CXX = ~/local/mamba/envs/spike13/bin/x86_64-conda-linux-gnu-g++
//   (there is no plain g++ on this host).
//
//   * `-lriscv` ALONE SUFFICES.  No -lsoftfloat, no -ldisasm, no -lfesvr.
//     libriscv.so carries RPATH=[.../spike13/lib:$HOME/local/lib] and its only
//     softfloat references are two *weak* TLS-init symbols
//     (_ZTH22softfloat_roundingMode, _ZTH24softfloat_exceptionFlags).
//     `ldd -r` on the result reports 0 undefined symbols.
//   * USE -std=c++20.  At -std=c++17 it still compiles, links and runs, but
//     emits 5 warnings of the form
//       riscv/mmu.h:69:30: warning: default member initializers for bit-fields
//       only available with '-std=c++20' or '-std=gnu++20' [-Wc++20-extensions]
//     (mmu.h lines 69-73).  c++20 is clean.
//   * The BINARY MUST NOT BE COMMITTED.  Build it to the gitignored
//     xcelium/riscv_test/behavioral_mp/cosim_work/ or to ~/local/bin/.
//   * RUNTIME: `source ~/local/spike_env.sh` first (LD_LIBRARY_PATH for the
//     conda libstdc++.so.6 that libriscv is linked against).
//
// CLI SYNOPSIS
//
//   vesta_ref identity  [image/mem/isa opts] --instructions N
//   vesta_ref cosim     [image/mem/isa opts] --instructions N
//                       --inject F   <-- MANDATORY in cosim mode
//                       [--interrupt F] [--bracket F] [--mmio-log F]
//     The compared flow never fabricates an unmodelled-load value, so cosim
//     REFUSES to start without a replay list (Fable ruling 2026-07-30, exit 1).
//     identity/selftest may omit it: there the absence of a replay is the
//     point, and neither mode feeds the comparator.
//   vesta_ref selftest
//
//   image (exactly one of):
//     --elf <path>              ELF32/ELF64 PT_LOAD segments to p_paddr;
//                               start pc defaults to e_entry.
//     --rom <path>              flat image loaded at --rom-base (default 0x0).
//                               .rcf = one 32-bit word per line as 32 ASCII
//                               '0'/'1' chars, MSB FIRST.  .bin = raw
//                               little-endian bytes.  Override with
//                               --rom-format rcf|bin.
//     --rom-base <hex>          default 0x0.
//
//   memory / isa:
//     --mem  <base:size>        RAM window, hex, PGSIZE-aligned.
//                               Default 0x8000:0x18000 (the frozen V2 window).
//                               base 0x0 works -- that is the entire point.
//     --mmio <base:size>        UNMODELLED region: addr_to_mem() returns NULL
//                               here so every access enters mmio_load/store.
//                               Carved OUT of --mem when they overlap (MMIO
//                               wins).  MUST be PGSIZE-aligned; refused
//                               otherwise, because mmu.cc:127/247/335 calls
//                               addr_to_mem() once per page and caches
//                               (host_addr - vaddr) for the whole page -- a
//                               misaligned hole would silently serve RAM.
//                               Default 0x4000:0x4000 in cosim, DISABLED in
//                               identity (use --mmio explicitly to enable).
//     --isa  <str>              default rv32imac_zicsr_zba_zbb_zbs_zbc
//     --priv <str>              default m
//     --hartid <n>              mhartid of the modelled hart, decimal.  Default
//                               0.  Also keys cfg.hartids and the get_harts()
//                               map, so cfg/proc/map never disagree.
//     --pc   <hex>              override start pc
//
//   run / output:
//     --instructions <N>        bound.  identity: N raw step(1) calls.
//                               cosim:   N *retires* (minstret-driven).
//     --log <file>              commit-log sink (default stdout)
//     --no-log-commits          disable the commit log
//     --trace                   per-retire pc/insn trace on stderr
//     --quiet                   suppress the stderr summary
//
// EXIT CODES
//     0  ok (an unconsumed --inject tail is a stderr warning, still 0)
//     1  usage / image / config error
//     7  injection fault (INJECT-MISMATCH or INJECT-EXHAUSTED)
//
// MODE NOTES
//
//   identity -- THE STANDING GATE.  Reproduces stock `spike --log-commits`
//     byte-for-byte.  Deliberately dumb: N raw `step(1)` calls, no minstret
//     probing, no MMIO region, no injection.  Compare with:
//       spike --isa=... --priv=m -m0x8000:0x18000 --log-commits <elf> \
//         | tail -n +6            # drop spike's own 5 reset-vector ROM lines
//     PROVEN: 2000 lines, md5 identical, on rv32ui-p-add.
//
//   cosim -- the real reference path.  minstret-delta driver contract (see
//     step_retire() below): +1 = one RTL retire consumed, +0 = the step was
//     consumed by a trap and NO commit-log line was printed.  Never infer a
//     retire from "did state.pc change" -- a `j .` does not change it, and the
//     instruction at mepc is NOT executed by the trapping step.
//
// THE ISR BRACKET / REALIGNMENT SCRIPT (--bracket, V3 + V4)
//
//   Spike cannot model VestaRV's LEGACY vectored trap (custom `iret`, IVT
//   dispatch, hardware return-PC push), so this reference is NEVER interrupted.
//   Instead the RTL's ISR window is bracketed OUT of the comparison
//   (compare.py --bracket-isr) and the reference is REALIGNED across it from a
//   script produced by mk_inject.py --bracket-out.  V4 (amendments A12/A13/A14)
//   extends the SAME channel with three more record types.  All five:
//
//       B <retire_index> <resume_pc>              state.pc <- resume_pc
//       S <retire_index> <addr> <size> <data>     poke reference RAM (bracket
//                                                 interior store replay, V3)
//       P <retire_index> <addr> <size> <data>     PLANT: poke reference RAM
//                                                 (A13a -- cross-hart data
//                                                 arrival on the mainline)
//       G <retire_index> <rd> <val>               poke reference GPR x<rd>
//                                                 (A12; rd = 2 hex, 00-1f)
//       F <retire_index>                          clear the load reservation so
//                                                 the next sc.w FAILS (A14)
//
//   `<retire_index>` is counted in THIS model's retires (the minstret-delta
//   counter below), which is the RTL's post-entry retire count with the
//   bracketed ISR retires removed -- the reference does not execute them.
//
//   APPLICATION ORDER AT ONE INDEX IS NORMATIVE (RECORD_FORMAT.md section
//   "A11-A14 application order at one retire index") and must NOT be reordered:
//
//       1. S and P  -- memory first;
//       2. G        -- registers, after memory (a G never depends on RAM, but a
//                      fixed order makes a script reproducible);
//       3. F        -- reservation, after memory, so that a plant to the
//                      reserved address cannot be mistaken for the thing that
//                      broke the reservation;
//       4. B        -- the pc, LAST, per V3's ruled order: a REDIRECTED
//                      bracket's stacked-PC store must land before the pc it
//                      implies is installed (otherwise the redirect masks it).
//
//   S-before-P inside step 1 is this file's tie-break; RECORD_FORMAT groups
//   them as one "memory" step and does not order them relative to each other.
//   Where both write one address the PLANT wins, which is the useful direction:
//   P is the value the reference is about to READ.
//
//   The resume PC itself is NOT decided here: it is determined and VERIFIED
//   trace-internally against the first post-`iret` RTL retire, so this file only
//   ever applies an already-checked value.
//
//   LOGGING DISCIPLINE (also normative, same section).  B/S/G keep a
//   per-application stderr line -- they are rare, one bracket per park.  P and F
//   are COUNTED ONLY and reported in the summary as `plants=<applied>/<total>`
//   and `scfails=<applied>/<total>`: measured scale is ~29,000 plants and
//   ~29,000 forced SC failures per hart per test (`shcount`), where a
//   per-application line would bury the log a triage actually reads.
//
//   Nothing is swallowed.  A store/plant outside --mem, an unreached bracket,
//   and an UNCONSUMED P/F/G tail are all loud stderr WARNINGs: a silent
//   realignment is indistinguishable from a comparator that was simply told to
//   skip the hard part, and a plant that never fired means the reference read
//   STALE RAM -- the single failure mode of the whole V4 design.
//
//   ASSERTED, NOT VERIFIED (say so wherever these results are reported): the
//   ISR's register writes (A12) and every SC success/failure DECISION (A14).
//   What an SC still genuinely proves is its address, its rd, the
//   outcome/effect consistency (a forced-fail reference writes nothing and
//   rd=1; an unforced one writes and rd=0) and everything downstream.
//
// API PROVENANCE (file:line, all against the pinned libriscv)
//   processor_t ctor .................. riscv/processor.h:231
//   cfg_t defaults .................... riscv/cfg.cc:34
//   mem_cfg_t::check_if_supported ..... riscv/cfg.cc:15
//   start pc = get_state()->pc ........ riscv/processor.h:251 (cfg.start_pc is
//                                       consumed only by sim_t, sim.cc:113)
//   enable_log_commits() .............. riscv/processor.h:242
//   commit_log_print_insn ............. riscv/execute.cc:62
//   slow_path() (log => slow path) .... riscv/execute.cc:205
//   step()/instret accounting ......... riscv/execute.cc:209,229,371
//   take_pending_interrupt() .......... riscv/processor.h:397
//   mip_csr_t::backdoor_write_with_mask riscv/csrs.h:396
//   addr_to_mem page caching .......... riscv/mmu.cc:127,247,335
// ---------------------------------------------------------------------------

#include <riscv/processor.h>
#include <riscv/simif.h>
#include <riscv/cfg.h>
#include <riscv/mmu.h>
#include <riscv/csrs.h>
#include <riscv/encoding.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <cinttypes>
#include <ctime>
#include <string>
#include <vector>
#include <map>
#include <iostream>
#include <fstream>
#include <sstream>

// ---------------------------------------------------------------- defaults
static const char    *DEF_ISA       = "rv32imac_zicsr_zba_zbb_zbs_zbc";
static const char    *DEF_PRIV      = "m";
static const uint64_t DEF_MEM_BASE  = 0x8000;      // frozen V2 window
static const uint64_t DEF_MEM_SIZE  = 0x18000;
static const uint64_t DEF_MMIO_BASE = 0x4000;      // cosim only
static const uint64_t DEF_MMIO_SIZE = 0x4000;

static const int EXIT_USAGE  = 1;
static const int EXIT_INJECT = 7;

// ------------------------------------------------------------ inject replay
struct inject_rec_t {
  uint64_t addr;
  unsigned size;
  uint32_t word;   // RAW BUS WORD (amendment A6), not the architectural result
};

struct mmio_rec_t {
  uint64_t addr;
  unsigned size;
  uint64_t val;
  bool     is_store;
};

// ------------------------------------------------------------- ISR brackets
struct bracket_store_t {
  uint64_t addr;
  unsigned size;
  uint32_t data;
};

// A12: one GPR poke.  `rd` is validated 0..31 at parse time; rd==0 is a legal
// no-op (x0), never an error.
struct gpr_poke_t {
  unsigned rd;
  uint32_t val;
};

// One realignment POINT: everything the script asks for at a single retire
// index.  V3 had only `pc`/`stores` (a "bracket"); V4 adds plants/gprs/scfails,
// which are counted SEPARATELY so the two censuses stay interpretable -- a
// mainline plant is not a bracket realignment even though it rides the same
// channel.  is_bracket() is the V3 notion, used for the `brackets=` census and
// the per-application log line.
struct bracket_t {
  uint64_t                     retire_index;
  bool                         has_pc = false;
  uint64_t                     pc = 0;
  std::vector<bracket_store_t> stores;   // S -- bracket-interior store replay
  std::vector<bracket_store_t> plants;   // P -- A13a mainline plant
  std::vector<gpr_poke_t>      gprs;     // G -- A12 register replay
  unsigned                     scfails = 0;  // F -- A14 forced SC failure(s)
  bool                         applied = false;

  bool is_bracket() const { return has_pc || !stores.empty(); }
};

// --------------------------------------------------------- interrupt schedule
struct irq_rec_t {
  uint64_t    retire_index;
  reg_t       mip_bit;
  std::string bit_name;
  uint64_t    source_id;
};

static reg_t mip_bit_by_name(const std::string &n)
{
  if (n == "MSIP" || n == "msip") return MIP_MSIP;
  if (n == "MTIP" || n == "mtip") return MIP_MTIP;
  if (n == "MEIP" || n == "meip") return MIP_MEIP;
  if (n == "SSIP" || n == "ssip") return MIP_SSIP;
  if (n == "STIP" || n == "stip") return MIP_STIP;
  if (n == "SEIP" || n == "seip") return MIP_SEIP;
  return 0;
}

// =========================================================== the simif
class vesta_sim_t : public simif_t
{
public:
  vesta_sim_t(const char *isa_str, const char *priv_str,
              uint64_t mem_base, uint64_t mem_size,
              uint64_t mmio_base, uint64_t mmio_size,
              FILE *logf, uint32_t hartid,
              // K2 item 6.  Defaulted to cfg_t's OWN defaults, so every
              // existing call site and every run that does not pass the new
              // flags is bit-identical to before.
              unsigned pmpregions = 16,
              unsigned pmpgranularity = 4,
              unsigned blocksz = 64,
              // D1 / DD9-4 (2026-08-05).  Defaulted to cfg_t's OWN default (4),
              // so every existing call site and every run that does not name
              // --triggers is bit-identical to before.
              unsigned triggers = 4)
    : mem_base_(mem_base), mem_size_(mem_size),
      mmio_base_(mmio_base), mmio_size_(mmio_size)
  {
    cfg.isa              = isa_str;
    cfg.priv             = priv_str;
    cfg.endianness       = endianness_little;
    cfg.mem_layout       = std::vector<mem_cfg_t>({mem_cfg_t(mem_base, mem_size)});
    cfg.hartids          = std::vector<size_t>({(size_t)hartid});
    cfg.explicit_hartids = false;
    cfg.real_time_clint  = false;
    // K2 item 6 (2026-08-03).  THIS COMMENT USED TO SAY these were "deliberately
    // left at cfg_t's defaults so we match stock spike exactly", and that was
    // true and load-bearing until the flags below existed.  It is now WRONG as a
    // description and RIGHT as a default, so it is rewritten rather than deleted
    // (method rule 12: a stale rationale is worse than none).
    //
    // WHAT CHANGED AND WHY.  The K0 oracle probe measured three things:
    //   * PMP_ENTRIES=8 was INEXPRESSIBLE -- pmpaddr0..15 were all live and
    //     pmpaddr16 READ 0 instead of trapping, so a config whose RTL traps it
    //     diverged there;
    //   * Spike's PMP RESET STATE IS NOT ZERO (pmpcfg0=0x1f, pmpaddr0=~0 -- a
    //     backward-compatibility TOR entry granting unrestricted access) while
    //     the RTL's bank resets ALL-ZERO with every entry A=OFF.  For a chip
    //     with no PMP at all the honest request is --pmpregions 0;
    //   * the identity gate was ALREADY ASYMMETRIC on this axis -- it invoked
    //     stock spike with --pmpregions=0 while vesta_ref ran with 16.  Harmless
    //     only while no compared instruction touched a PMP CSR.
    // The defaults here still equal cfg_t's, so "matches stock spike exactly"
    // remains TRUE FOR A RUN THAT PASSES NO FLAGS -- which is every run before
    // the derivation is switched on.  NEVER PATCH SPIKE: this is CLI work on
    // vesta_ref, and build_vesta_ref.sh's clean-tree-at-a-pinned-commit
    // assertion is untouched.
    cfg.pmpregions       = pmpregions;
    cfg.pmpgranularity   = pmpgranularity;
    cfg.cache_blocksz    = blocksz;
    // D1 / DD9-4 (2026-08-05).  THIS COMMENT USED TO SAY trigger_count was
    // "still left at cfg_t's default ... inventing a flag for it would be a
    // knob with no reader", and that was true until the D-series began.  It is
    // now WRONG as a description and would be wrong as a policy, so it is
    // rewritten rather than deleted (method rule 12).
    //
    // WHAT CHANGED.  The D-series makes debug hardware a configurable part of
    // this chip, so "what does the REFERENCE think this hart has" acquires a
    // reader.  The RTL implements NO hardware triggers -- 0x7A0-0x7AF is
    // absent from maindec's csr_addr_valid in every build, and stays absent
    // until D6 -- while cfg_t's default gives the reference FOUR, with live
    // tselect/tdata1/tdata2/tinfo CSRs where the RTL raises
    // illegal-instruction.  Nothing in the standing comparison touches those
    // addresses today, so the misalignment is latent; the moment a D-series
    // test reads one it becomes a divergence manufactured by the reference.
    // The honest request for a chip with no triggers is --triggers 0.
    // The default here still equals cfg_t's, so "matches stock spike exactly"
    // remains TRUE FOR A RUN THAT PASSES NO FLAGS.  NEVER PATCH SPIKE: this is
    // CLI work on vesta_ref, and build_vesta_ref.sh's clean-tree-at-a-pinned-
    // commit assertion is untouched.
    cfg.trigger_count    = triggers;

    ram.assign(mem_size, 0);

    // Parity with sim.cc:99 -- a proc-less MMU for backdoor access.  Nothing
    // requires it (is_debug_module_access() defaults to false and there is no
    // debug module), but simif_t::debug_mmu is a raw public member and leaving
    // it uninitialised is a trap waiting to happen.
    debug_mmu = new mmu_t(this, cfg.endianness, NULL, cfg.cache_blocksz);

    // `id` IS mhartid: csr_init.cc:345 builds it as a const_csr_t from
    // proc->get_id() (processor.h:247).  The get_harts() map must be keyed by
    // the same value -- libriscv internals look harts up by hartid, so a map
    // keyed 0 while the proc answers 3 is an inconsistency waiting to bite.
    proc = new processor_t(cfg.isa, cfg.priv, &cfg, this, /*id=*/hartid,
                           /*halt_on_reset=*/false, logf, std::cerr);
    harts[hartid] = proc;
  }

  ~vesta_sim_t() override { delete proc; delete debug_mmu; }

  // ---- simif_t ------------------------------------------------------------
  char* addr_to_mem(reg_t paddr) override
  {
    // MMIO wins over RAM wherever they overlap.
    if (mmio_size_ && paddr >= mmio_base_ && paddr < mmio_base_ + mmio_size_)
      return NULL;
    if (paddr >= mem_base_ && paddr < mem_base_ + mem_size_)
      return (char*)&ram[paddr - mem_base_];
    return NULL;
  }

  bool mmio_load(reg_t paddr, size_t len, uint8_t *bytes) override
  {
    uint64_t v = 0;

    if (inject_active) {
      // Strict ordered replay: the Nth access to an unmodelled address pops
      // entry N.  NEVER an address-keyed lookup, NEVER a fallback to 0.
      if (inject_idx >= inject.size()) {
        fflush(NULL);
        fprintf(stderr, "INJECT-EXHAUSTED %zu addr=%08" PRIx64 "\n",
                inject_idx, (uint64_t)paddr);
        exit(EXIT_INJECT);
      }
      const inject_rec_t &r = inject[inject_idx];
      if (r.addr != (uint64_t)paddr || r.size != len) {
        fflush(NULL);
        fprintf(stderr, "INJECT-MISMATCH %zu exp=%08" PRIx64 "/%u got=%08" PRIx64 "/%zu\n",
                inject_idx, r.addr, r.size, (uint64_t)paddr, len);
        exit(EXIT_INJECT);
      }
      // The record is the RAW BUS WORD; take the addressed lane (amendment A6).
      v = (uint64_t)r.word >> (8 * (paddr & 3));
      inject_idx++;
    } else {
      // Reachable ONLY from identity/selftest/smoke contexts: `cosim` mode
      // REFUSES to start without --inject (Fable ruling, 2026-07-30), because
      // the compared flow must never fabricate a value.  Serving 0 here is the
      // ABSENCE of a replay, not a fallback within one -- once a list exists
      // every access is strict.
      if (!warned_no_inject) {
        warned_no_inject = true;
        fprintf(stderr, "vesta_ref: note: no --inject list; unmodelled loads read 0"
                        " (never reachable in cosim mode)\n");
      }
      v = 0;
    }

    if (len < 8) v &= (1ull << (8 * len)) - 1;
    memset(bytes, 0, len);
    for (size_t i = 0; i < len && i < 8; i++)
      bytes[i] = (uint8_t)(v >> (8 * i));

    n_load++;
    if (mmio_log) mmio_trace.push_back({(uint64_t)paddr, (unsigned)len, v, false});
    return true;
  }

  bool mmio_store(reg_t paddr, size_t len, const uint8_t *bytes) override
  {
    // Accept and discard.  Stores are compared on BOTH sides by the
    // comparator, so divergence is its job to report, not ours.
    uint64_t v = 0;
    for (size_t i = 0; i < len && i < 8; i++) v |= (uint64_t)bytes[i] << (8 * i);
    n_store++;
    if (mmio_log) mmio_trace.push_back({(uint64_t)paddr, (unsigned)len, v, true});
    return true;
  }

  void proc_reset(unsigned) override {}
  const cfg_t& get_cfg() const override { return cfg; }
  const std::map<size_t, processor_t*>& get_harts() const override { return harts; }
  const char* get_symbol(uint64_t) override { return NULL; }

  // ---- image helpers ------------------------------------------------------
  bool in_ram(uint64_t a, uint64_t n) const
  { return a >= mem_base_ && a + n <= mem_base_ + mem_size_; }

  void write_bytes(uint64_t a, const uint8_t *src, size_t n)
  { memcpy(&ram[a - mem_base_], src, n); }

  void zero_bytes(uint64_t a, size_t n)
  { memset(&ram[a - mem_base_], 0, n); }

  // Little-endian poke of `size` bytes at the BYTE address, straight into the
  // RAM array -- deliberately bypassing the MMU/processor so it never appears
  // as an architectural access or a commit-log line.  Returns false (and writes
  // nothing) if the target is not backed by --mem RAM: an ISR-bracket replay
  // whose address left the RAM window is a real finding, not something to
  // partially apply.
  bool poke(uint64_t a, unsigned size, uint32_t data)
  {
    if (!size || size > 4 || !in_ram(a, size)) return false;
    uint8_t le[4];
    for (unsigned i = 0; i < size; i++) le[i] = (uint8_t)(data >> (8 * i));
    write_bytes(a, le, size);
    return true;
  }

  // A12.  Poke an integer register WITHOUT emitting a commit-log line, for the
  // same reason poke() above bypasses the MMU: a realignment must never appear
  // as an architectural event.
  //
  // THE WRITE PATH (all file:line against the pinned libriscv):
  //   processor_t::get_state() ... riscv/processor.h:251  (public)
  //   state_t::XPR ............... riscv/processor.h:85   (public member)
  //   regfile_t::write() ......... riscv/decode.h:228-233 (public)
  // regfile_t::write is a bare array store.  The commit-log entry is made
  // SEPARATELY, by the WRITE_RD macro's `STATE.log_reg_write[...] = ...` in
  // Spike's generated insn bodies -- never by regfile_t itself -- so writing
  // through the regfile is invisible to enable_log_commits().  (There is no
  // "put_gpr" on processor_t at all; put_csr exists, get/set for GPRs does not.)
  //
  // x0 NEEDS NO SPECIAL CASE: XPR is regfile_t<reg_t, NXPR, **true**> and that
  // third template argument is `zero_reg`, so write(0, v) is a no-op by
  // construction (decode.h:230 `if (!zero_reg || i != 0)`).
  //
  // Sign-extension: Spike keeps RV32 registers sign-extended into reg_t (every
  // WRITE_RD goes through sext_xlen), so a 32-bit record value must be extended
  // the same way or a later comparison/branch on the poked register would see a
  // value no RV32 instruction could ever have produced.
  void poke_gpr(unsigned rd, uint32_t val)
  {
    reg_t v = (proc->get_xlen() == 32) ? (reg_t)(int64_t)(int32_t)val
                                       : (reg_t)val;
    proc->get_state()->XPR.write(rd, v);
  }

  // A14.  Clear the load reservation so the NEXT sc.w fails.
  //   processor_t::get_mmu() ................ riscv/processor.h:250 (public)
  //   mmu_t::yield_load_reservation() ....... riscv/mmu.h:258-261   (public)
  // This is the same method sim_t calls at its interleave boundary
  // (riscv/sim.cc:330); it sets load_reservation_address = (reg_t)-1, which
  // check_load_reservation() (mmu.h:263-276) can never match, so
  // store_conditional() (mmu.h:283-292) returns "no reservation" -> writes
  // NOTHING and the sc.w commits rd=1.
  void clear_reservation() { proc->get_mmu()->yield_load_reservation(); }

  uint32_t peek32(uint64_t a) const
  {
    const uint8_t *p = &ram[a - mem_base_];
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8)
         | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
  }

  uint64_t mem_base() const { return mem_base_; }
  uint64_t mem_size() const { return mem_size_; }

  cfg_t                          cfg;
  processor_t                   *proc = NULL;
  std::map<size_t, processor_t*> harts;
  std::vector<uint8_t>           ram;

  std::vector<inject_rec_t> inject;
  size_t                    inject_idx      = 0;
  bool                      inject_active   = false;
  bool                      warned_no_inject = false;

  bool                     mmio_log = false;
  std::vector<mmio_rec_t>  mmio_trace;

  uint64_t n_load = 0, n_store = 0;

private:
  uint64_t mem_base_, mem_size_, mmio_base_, mmio_size_;
};

// =========================================================== image loaders
// Minimal self-contained ELF32/ELF64 little-endian PT_LOAD loader.  We do NOT
// use fesvr's load_elf(): it wants a memif_t/chunked_memif_t and would drag in
// libfesvr, breaking the "-lriscv alone" property.
static bool load_elf_image(vesta_sim_t &s, const char *path, uint64_t *entry_out)
{
  std::ifstream f(path, std::ios::binary);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open ELF %s\n", path); return false; }
  std::vector<uint8_t> b((std::istreambuf_iterator<char>(f)),
                          std::istreambuf_iterator<char>());
  if (b.size() < 64 || memcmp(&b[0], "\177ELF", 4) != 0) {
    fprintf(stderr, "vesta_ref: %s is not an ELF\n", path); return false;
  }
  const bool is64 = (b[4] == 2);
  if (b[5] != 1) { fprintf(stderr, "vesta_ref: only little-endian ELF\n"); return false; }

  auto rd = [&](size_t off, size_t n) -> uint64_t {
    uint64_t v = 0;
    for (size_t i = 0; i < n; i++) v |= (uint64_t)b[off + i] << (8 * i);
    return v;
  };

  uint64_t entry, phoff; uint16_t phentsize, phnum;
  if (is64) {
    entry = rd(0x18, 8); phoff = rd(0x20, 8);
    phentsize = (uint16_t)rd(0x36, 2); phnum = (uint16_t)rd(0x38, 2);
  } else {
    entry = rd(0x18, 4); phoff = rd(0x1c, 4);
    phentsize = (uint16_t)rd(0x2a, 2); phnum = (uint16_t)rd(0x2c, 2);
  }
  *entry_out = entry;

  unsigned loaded = 0;
  for (uint16_t i = 0; i < phnum; i++) {
    size_t ph = phoff + (size_t)i * phentsize;
    if (ph + phentsize > b.size()) break;
    uint32_t type = (uint32_t)rd(ph, 4);
    if (type != 1 /*PT_LOAD*/) continue;
    uint64_t off, paddr, filesz, memsz;
    if (is64) {
      off = rd(ph + 0x08, 8); paddr = rd(ph + 0x18, 8);
      filesz = rd(ph + 0x20, 8); memsz = rd(ph + 0x28, 8);
    } else {
      off = rd(ph + 0x04, 4); paddr = rd(ph + 0x0c, 4);
      filesz = rd(ph + 0x10, 4); memsz = rd(ph + 0x14, 4);
    }
    if (!memsz) continue;
    if (!s.in_ram(paddr, memsz)) {
      fprintf(stderr, "vesta_ref: PT_LOAD paddr=0x%" PRIx64 " memsz=0x%" PRIx64
                      " falls outside --mem 0x%" PRIx64 ":0x%" PRIx64 "\n",
              paddr, memsz, s.mem_base(), s.mem_size());
      return false;
    }
    if (off + filesz > b.size()) {
      fprintf(stderr, "vesta_ref: PT_LOAD truncated in file\n"); return false;
    }
    s.zero_bytes(paddr, memsz);
    if (filesz) s.write_bytes(paddr, &b[off], filesz);
    loaded++;
  }
  if (!loaded) { fprintf(stderr, "vesta_ref: no PT_LOAD in %s\n", path); return false; }
  return true;
}

// .rcf = one 32-bit word per line, 32 ASCII '0'/'1', MSB FIRST.
static bool load_rcf_image(vesta_sim_t &s, const char *path, uint64_t base, size_t *nw)
{
  std::ifstream f(path);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open %s\n", path); return false; }
  std::string line; size_t n = 0;
  while (std::getline(f, line)) {
    std::string bits;
    for (char c : line) if (c == '0' || c == '1') bits.push_back(c);
    if (bits.empty()) continue;
    if (bits.size() != 32) {
      fprintf(stderr, "vesta_ref: %s line %zu has %zu bits, expected 32\n",
              path, n + 1, bits.size());
      return false;
    }
    uint32_t w = 0;
    for (char c : bits) w = (w << 1) | (uint32_t)(c - '0');
    uint64_t a = base + 4 * n;
    if (!s.in_ram(a, 4)) {
      fprintf(stderr, "vesta_ref: rcf word %zu at 0x%" PRIx64 " outside --mem\n", n, a);
      return false;
    }
    uint8_t le[4] = { (uint8_t)w, (uint8_t)(w >> 8), (uint8_t)(w >> 16), (uint8_t)(w >> 24) };
    s.write_bytes(a, le, 4);
    n++;
  }
  *nw = n;
  return true;
}

static bool load_bin_image(vesta_sim_t &s, const char *path, uint64_t base, size_t *nb)
{
  std::ifstream f(path, std::ios::binary);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open %s\n", path); return false; }
  std::vector<uint8_t> b((std::istreambuf_iterator<char>(f)),
                          std::istreambuf_iterator<char>());
  if (!s.in_ram(base, b.size())) {
    fprintf(stderr, "vesta_ref: .bin of 0x%zx bytes at 0x%" PRIx64 " outside --mem\n",
            b.size(), base);
    return false;
  }
  if (!b.empty()) s.write_bytes(base, &b[0], b.size());
  *nb = b.size();
  return true;
}

// ============================================================ list loaders
// `<addr8> <size1> <value8>` -- lowercase hex, no 0x.  Blank lines and lines
// beginning with '#' are ignored.
static bool load_inject_list(const char *path, std::vector<inject_rec_t> &out)
{
  std::ifstream f(path);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open --inject %s\n", path); return false; }
  std::string line; size_t ln = 0;
  while (std::getline(f, line)) {
    ln++;
    size_t h = line.find('#');
    if (h != std::string::npos) line.resize(h);
    std::istringstream is(line);
    std::string a, sz, v;
    if (!(is >> a >> sz >> v)) {
      if (line.find_first_not_of(" \t\r\n") == std::string::npos) continue;
      fprintf(stderr, "vesta_ref: --inject %s:%zu malformed: %s\n", path, ln, line.c_str());
      return false;
    }
    inject_rec_t r;
    r.addr = strtoull(a.c_str(),  NULL, 16);
    r.size = (unsigned)strtoul(sz.c_str(), NULL, 16);
    r.word = (uint32_t)strtoull(v.c_str(), NULL, 16);
    if (r.size != 1 && r.size != 2 && r.size != 4 && r.size != 8) {
      fprintf(stderr, "vesta_ref: --inject %s:%zu bad size %u\n", path, ln, r.size);
      return false;
    }
    out.push_back(r);
  }
  return true;
}

// The realignment script (V3 B/S + V4 P/G/F).  Lowercase hex, no 0x, `#`
// comments; the retire index is DECIMAL.
//
//   B <retire_index> <resume_pc>
//   S <retire_index> <addr> <size> <data>
//   P <retire_index> <addr> <size> <data>
//   G <retire_index> <rd> <val>
//   F <retire_index>
//
// Entries are GROUPED BY retire_index, so the file's line order WITHIN one index
// is irrelevant: the applier imposes the normative order S+P -> G -> F -> B (see
// the header block).  Two B records at one index is a malformed script and is
// refused -- silently keeping the last would make a generator bug look like a
// working realignment.  Repeated F records at one index are accepted and counted
// individually (clearing an already-clear reservation is idempotent).
static bool load_bracket_list(const char *path, std::vector<bracket_t> &out)
{
  std::ifstream f(path);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open --bracket %s\n", path); return false; }
  std::string line; size_t ln = 0;
  std::map<uint64_t, size_t> where;      // retire_index -> slot in `out`
  while (std::getline(f, line)) {
    ln++;
    size_t h = line.find('#');
    if (h != std::string::npos) line.resize(h);
    std::istringstream is(line);
    std::string tag;
    if (!(is >> tag)) continue;
    if (tag != "B" && tag != "S" && tag != "P" && tag != "G" && tag != "F") {
      fprintf(stderr, "vesta_ref: --bracket %s:%zu unknown record tag '%s'"
                      " (expected B, S, P, G or F)\n", path, ln, tag.c_str());
      return false;
    }
    std::string idx_s;
    if (!(is >> idx_s)) {
      fprintf(stderr, "vesta_ref: --bracket %s:%zu malformed: no retire index\n", path, ln);
      return false;
    }
    // The retire index is DECIMAL in the emitted script (it is a count, not a
    // machine word); accept only digits so a stray hex letter is caught rather
    // than silently reinterpreted.
    if (idx_s.find_first_not_of("0123456789") != std::string::npos) {
      fprintf(stderr, "vesta_ref: --bracket %s:%zu retire index '%s' is not decimal\n",
              path, ln, idx_s.c_str());
      return false;
    }
    const uint64_t idx = strtoull(idx_s.c_str(), NULL, 10);

    if (where.find(idx) == where.end()) {
      where[idx] = out.size();
      bracket_t b; b.retire_index = idx;
      out.push_back(b);
    }
    bracket_t &b = out[where[idx]];

    if (tag == "B") {
      std::string pc_s;
      if (!(is >> pc_s)) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu B needs a resume pc\n", path, ln);
        return false;
      }
      if (b.has_pc) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu a second B record at retire"
                        " index %" PRIu64 " (already 0x%08" PRIx64 ")\n",
                path, ln, idx, b.pc);
        return false;
      }
      b.has_pc = true;
      b.pc     = strtoull(pc_s.c_str(), NULL, 16);
    } else if (tag == "G") {
      // A12.  `rd` is 2 hex digits, 00-1f.  Validated on BOTH the charset and
      // the range: an out-of-range rd silently masked to 5 bits would poke the
      // wrong register and look like a core bug.  rd=00 is legal and is a no-op
      // (x0), never an error -- see poke_gpr().
      std::string rd_s, v_s;
      if (!(is >> rd_s >> v_s)) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu G needs <rd> <val>\n", path, ln);
        return false;
      }
      if (rd_s.find_first_not_of("0123456789abcdefABCDEF") != std::string::npos) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu G rd '%s' is not hex\n",
                path, ln, rd_s.c_str());
        return false;
      }
      unsigned long rd = strtoul(rd_s.c_str(), NULL, 16);
      if (rd > 31) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu G rd '%s' (=%lu) is out of"
                        " range 00-1f\n", path, ln, rd_s.c_str(), rd);
        return false;
      }
      gpr_poke_t g;
      g.rd  = (unsigned)rd;
      g.val = (uint32_t)strtoull(v_s.c_str(), NULL, 16);
      b.gprs.push_back(g);
    } else if (tag == "F") {
      // A14.  No operands beyond the index.  Trailing tokens are REFUSED rather
      // than ignored: `F <idx> <addr>` is a generator that thinks the record
      // takes an address, and silently dropping it would forge an agreement.
      std::string extra;
      if (is >> extra) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu F takes no operands beyond"
                        " the retire index (got '%s')\n", path, ln, extra.c_str());
        return false;
      }
      b.scfails++;
    } else {
      // S (bracket-interior store replay) and P (A13a mainline plant) share one
      // wire shape and one poke; only the census they land in differs.
      std::string a_s, sz_s, d_s;
      if (!(is >> a_s >> sz_s >> d_s)) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu %s needs <addr> <size> <data>\n",
                path, ln, tag.c_str());
        return false;
      }
      bracket_store_t s;
      s.addr = strtoull(a_s.c_str(), NULL, 16);
      s.size = (unsigned)strtoul(sz_s.c_str(), NULL, 16);
      s.data = (uint32_t)strtoull(d_s.c_str(), NULL, 16);
      if (s.size != 1 && s.size != 2 && s.size != 4) {
        fprintf(stderr, "vesta_ref: --bracket %s:%zu bad %s size %u\n",
                path, ln, tag.c_str(), s.size);
        return false;
      }
      if (tag == "P") b.plants.push_back(s);
      else            b.stores.push_back(s);
    }
  }
  // Ascending index order is what the single-pass applier below relies on.
  for (size_t i = 1; i < out.size(); i++) {
    if (out[i].retire_index < out[i - 1].retire_index) {
      fprintf(stderr, "vesta_ref: --bracket %s: retire indices are not in"
                      " ascending order (%" PRIu64 " after %" PRIu64 ")\n",
              path, out[i].retire_index, out[i - 1].retire_index);
      return false;
    }
  }
  return true;
}

// `I <retire_index> <mip_bit_name> <source_id>`
static bool load_irq_list(const char *path, std::vector<irq_rec_t> &out)
{
  std::ifstream f(path);
  if (!f) { fprintf(stderr, "vesta_ref: cannot open --interrupt %s\n", path); return false; }
  std::string line; size_t ln = 0;
  while (std::getline(f, line)) {
    ln++;
    size_t h = line.find('#');
    if (h != std::string::npos) line.resize(h);
    std::istringstream is(line);
    std::string tag, name; uint64_t idx, src;
    if (!(is >> tag)) continue;
    if (tag != "I") {
      fprintf(stderr, "vesta_ref: --interrupt %s:%zu unknown record tag '%s'\n",
              path, ln, tag.c_str());
      return false;
    }
    if (!(is >> idx >> name >> src)) {
      fprintf(stderr, "vesta_ref: --interrupt %s:%zu malformed\n", path, ln);
      return false;
    }
    irq_rec_t r;
    r.retire_index = idx;
    r.bit_name     = name;
    r.mip_bit      = mip_bit_by_name(name);
    r.source_id    = src;
    if (!r.mip_bit) {
      fprintf(stderr, "vesta_ref: --interrupt %s:%zu unknown mip bit '%s'\n",
              path, ln, name.c_str());
      return false;
    }
    out.push_back(r);
  }
  return true;
}

// ================================================================= options
struct opts_t {
  std::string mode;
  const char *elf = NULL, *rom = NULL, *rom_format = NULL;
  const char *inject_file = NULL, *irq_file = NULL, *bracket_file = NULL;
  const char *log_file = NULL, *mmio_log_file = NULL;
  const char *isa = DEF_ISA, *priv = DEF_PRIV;
  uint64_t rom_base = 0x0;
  uint64_t mem_base = DEF_MEM_BASE,  mem_size  = DEF_MEM_SIZE;
  uint64_t mmio_base = DEF_MMIO_BASE, mmio_size = 0;   // set per-mode below
  bool     mmio_given = false;
  bool     pc_given = false; uint64_t pc = 0;
  uint32_t hartid = 0;                                 // == mhartid
  // K2 item 6.  cfg_t's own defaults, so an invocation that names none of them
  // is byte-identical to the pre-K2 binary.
  unsigned pmpregions = 16, pmpgranularity = 4, blocksz = 64;
  // D1/DD9-4: cfg_t's own default, so an invocation that does not name it is
  // byte-identical to the pre-D1 binary.
  unsigned triggers = 4;
  long     instructions = 0;
  bool     log_commits = true, trace = false, quiet = false;
};

static bool parse_pair(const char *s, uint64_t *a, uint64_t *b)
{
  const char *c = strchr(s, ':');
  if (!c) return false;
  *a = strtoull(s, NULL, 16);
  *b = strtoull(c + 1, NULL, 16);
  return true;
}

static void usage(void)
{
  fprintf(stderr,
    "usage: vesta_ref <identity|cosim|selftest> [options]\n"
    "  --elf F | --rom F [--rom-base HEX] [--rom-format rcf|bin]\n"
    "  --mem BASE:SIZE (hex, PGSIZE-aligned, default 8000:18000)\n"
    "  --mmio BASE:SIZE (hex, PGSIZE-aligned, default 4000:4000 in cosim)\n"
    "  --isa STR --priv STR --hartid N (mhartid, default 0) --pc HEX\n"
    "  --pmpregions N (default 16; 0 = no PMP at all, matching a chip built\n"
    "                  without ENABLE_PMP -- spike's PMP RESET STATE IS NOT ZERO)\n"
    "  --pmpgranularity N (default 4) --blocksz N (default 64, cbo.zero block)\n"
    "  --triggers N (default 4 = spike's own; 0 = no hardware triggers, which\n"
    "                is what this RTL has until D6 -- 0x7A0-0x7AF all trap)\n"
    "  --instructions N\n"
    "  --inject F (MANDATORY in cosim) --interrupt F --mmio-log F --log F\n"
    "  --bracket F (cosim only: realignment script; B/S/P/G/F records, applied\n"
    "               in the normative order S+P -> G -> F -> B at one index)\n"
    "  --no-log-commits --trace --quiet\n"
    "exit: 0 ok, 1 usage/image, 7 injection fault\n");
}

// ================================================================== driver
// THE DRIVER CONTRACT.  step(1) retires exactly one instruction (execute.cc:209
// `while (instret < n)`, advance_pc() bumps instret) -- EXCEPT when the step is
// consumed by a trap: take_pending_interrupt() runs at the top of step()
// (execute.cc:229), throws, and instret stays 0, so state.minstret does not
// bump (execute.cc:371).  The instruction at mepc is NOT executed and NO
// commit-log line is printed.  minstret delta is therefore the only sound
// retire detector.  "did state.pc change" is WRONG: a `j .` does not change it.
static uint64_t minstret_of(processor_t *p)
{
  return (uint64_t)p->get_csr(CSR_MINSTRET);
}

int main(int argc, char **argv)
{
  opts_t o;
  if (argc < 2) { usage(); return EXIT_USAGE; }
  if (!strcmp(argv[1], "-h") || !strcmp(argv[1], "--help")) { usage(); return 0; }
  o.mode = argv[1];
  if (o.mode != "identity" && o.mode != "cosim" && o.mode != "selftest") {
    fprintf(stderr, "vesta_ref: unknown mode '%s'\n", o.mode.c_str());
    usage(); return EXIT_USAGE;
  }

  for (int i = 2; i < argc; i++) {
    std::string a = argv[i];
    auto need = [&](void) -> const char* {
      if (i + 1 >= argc) { fprintf(stderr, "vesta_ref: %s needs a value\n", a.c_str()); exit(EXIT_USAGE); }
      return argv[++i];
    };
    if      (a == "--elf")            o.elf = need();
    else if (a == "--rom")            o.rom = need();
    else if (a == "--rom-base")       o.rom_base = strtoull(need(), NULL, 0);
    else if (a == "--rom-format")     o.rom_format = need();
    else if (a == "--mem")          { if (!parse_pair(need(), &o.mem_base, &o.mem_size)) { fprintf(stderr, "vesta_ref: --mem wants BASE:SIZE\n"); return EXIT_USAGE; } }
    else if (a == "--mmio")         { if (!parse_pair(need(), &o.mmio_base, &o.mmio_size)) { fprintf(stderr, "vesta_ref: --mmio wants BASE:SIZE\n"); return EXIT_USAGE; } o.mmio_given = true; }
    else if (a == "--isa")            o.isa = need();
    else if (a == "--priv")           o.priv = need();
    else if (a == "--hartid")       { const char *v = need(); char *end = NULL;
                                      unsigned long h = strtoul(v, &end, 0);
                                      if (!*v || *end || h > 0xffffffffUL) {
                                        fprintf(stderr, "vesta_ref: --hartid wants a non-negative integer, got '%s'\n", v);
                                        return EXIT_USAGE; }
                                      o.hartid = (uint32_t)h; }
    else if (a == "--pmpregions")     o.pmpregions = (unsigned)strtoul(need(), NULL, 0);
    else if (a == "--triggers")       o.triggers = (unsigned)strtoul(need(), NULL, 0);
    else if (a == "--pmpgranularity") o.pmpgranularity = (unsigned)strtoul(need(), NULL, 0);
    else if (a == "--blocksz")        o.blocksz = (unsigned)strtoul(need(), NULL, 0);
    else if (a == "--pc")           { o.pc = strtoull(need(), NULL, 0); o.pc_given = true; }
    else if (a == "--instructions")   o.instructions = atol(need());
    else if (a == "--inject")         o.inject_file = need();
    else if (a == "--interrupt")      o.irq_file = need();
    else if (a == "--bracket")        o.bracket_file = need();
    else if (a == "--mmio-log")       o.mmio_log_file = need();
    else if (a == "--log")            o.log_file = need();
    else if (a == "--no-log-commits") o.log_commits = false;
    else if (a == "--trace")          o.trace = true;
    else if (a == "--quiet")          o.quiet = true;
    else if (a == "-h" || a == "--help") { usage(); return 0; }
    else { fprintf(stderr, "vesta_ref: unknown option '%s'\n", a.c_str()); usage(); return EXIT_USAGE; }
  }

  // ---- selftest: no image, exercises the plumbing incl. RAM at 0x0 --------
  if (o.mode == "selftest") {
    vesta_sim_t s(o.isa, o.priv, 0x0, 0x20000, 0x4000, 0x4000, stdout, o.hartid,
                  o.pmpregions, o.pmpgranularity, o.blocksz, o.triggers);
    s.proc->enable_log_commits();
    // lui a0,0x4 ; addi a0,a0,0x204 ; lw t0,0(a0) ; j .
    const uint32_t prog[] = { 0x00004537, 0x20450513, 0x00052283, 0x0000006f };
    for (unsigned i = 0; i < 4; i++) {
      uint8_t le[4] = { (uint8_t)prog[i], (uint8_t)(prog[i] >> 8),
                        (uint8_t)(prog[i] >> 16), (uint8_t)(prog[i] >> 24) };
      s.write_bytes(4 * i, le, 4);
    }
    s.inject.push_back({0x4204, 4, 0x12345678});
    s.inject_active = true;
    s.proc->get_state()->pc = 0x0;
    for (int i = 0; i < 4; i++) s.proc->step(1);
    fflush(stdout);
    uint64_t t0 = (uint64_t)s.proc->get_state()->XPR[5] & 0xffffffffull;
    fprintf(stderr, "selftest: RAM@0x0 executed, injected t0=0x%08" PRIx64 " %s\n",
            t0, t0 == 0x12345678 ? "OK" : "FAIL");
    return t0 == 0x12345678 ? 0 : 1;
  }

  // ---- mode defaults -----------------------------------------------------
  if (o.mode == "cosim" && !o.mmio_given) o.mmio_size = DEF_MMIO_SIZE;
  // identity leaves mmio_size = 0 (disabled) unless --mmio was given.

  if (!o.elf == !o.rom) {
    fprintf(stderr, "vesta_ref: give exactly one of --elf / --rom\n");
    return EXIT_USAGE;
  }
  if (o.instructions <= 0) {
    fprintf(stderr, "vesta_ref: --instructions N (N>0) is required\n");
    return EXIT_USAGE;
  }

  // ---- alignment validation ---------------------------------------------
  if (o.mem_base % PGSIZE || o.mem_size % PGSIZE || o.mem_size == 0) {
    fprintf(stderr, "vesta_ref: --mem 0x%" PRIx64 ":0x%" PRIx64
                    " must be PGSIZE(0x%x)-aligned and non-empty\n",
            o.mem_base, o.mem_size, (unsigned)PGSIZE);
    return EXIT_USAGE;
  }
  if (o.mmio_size) {
    if (o.mmio_base % PGSIZE || o.mmio_size % PGSIZE) {
      fprintf(stderr, "vesta_ref: --mmio 0x%" PRIx64 ":0x%" PRIx64
                      " must be PGSIZE(0x%x)-aligned -- mmu.cc caches"
                      " (host_addr - vaddr) per page, so a misaligned"
                      " unmodelled hole would silently serve RAM\n",
              o.mmio_base, o.mmio_size, (unsigned)PGSIZE);
      return EXIT_USAGE;
    }
  }

  // ---- commit-log sink ---------------------------------------------------
  FILE *logf = stdout;
  if (o.log_file) {
    logf = fopen(o.log_file, "w");
    if (!logf) { fprintf(stderr, "vesta_ref: cannot write --log %s\n", o.log_file); return EXIT_USAGE; }
  }

  vesta_sim_t s(o.isa, o.priv, o.mem_base, o.mem_size,
                o.mmio_base, o.mmio_size, logf, o.hartid,
                o.pmpregions, o.pmpgranularity, o.blocksz, o.triggers);
  s.mmio_log = (o.mmio_log_file != NULL);

  // ---- image -------------------------------------------------------------
  uint64_t start_pc = 0;
  if (o.elf) {
    uint64_t entry = 0;
    if (!load_elf_image(s, o.elf, &entry)) return EXIT_USAGE;
    start_pc = entry;
    if (!o.quiet) fprintf(stderr, "vesta_ref: loaded ELF %s entry=0x%" PRIx64 "\n", o.elf, entry);
  } else {
    std::string p = o.rom;
    bool rcf;
    if (o.rom_format)          rcf = (strcmp(o.rom_format, "rcf") == 0);
    else if (p.size() > 4 && p.compare(p.size() - 4, 4, ".rcf") == 0) rcf = true;
    else                       rcf = false;
    size_t n = 0;
    if (rcf) { if (!load_rcf_image(s, o.rom, o.rom_base, &n)) return EXIT_USAGE; }
    else     { if (!load_bin_image(s, o.rom, o.rom_base, &n)) return EXIT_USAGE; }
    start_pc = o.rom_base;
    if (!o.quiet)
      fprintf(stderr, "vesta_ref: loaded %s (%s) %zu %s at 0x%" PRIx64 "\n",
              o.rom, rcf ? "rcf" : "bin", n, rcf ? "words" : "bytes", o.rom_base);
  }
  if (o.pc_given) start_pc = o.pc;

  // ---- lists -------------------------------------------------------------
  // FABLE RULING 2026-07-30: --inject is MANDATORY in `cosim` mode. The
  // compared flow never fabricates a load value; a missing replay list is a
  // usage error, not a silent read-0. (identity/selftest deliberately still
  // allow it -- there the absence of a replay is the point, and neither one
  // feeds the comparator.)
  if (o.mode == "cosim" && !o.inject_file) {
    fprintf(stderr,
            "vesta_ref: cosim mode requires --inject <file>.\n"
            "  The compared flow must never fabricate an unmodelled-load value;\n"
            "  a missing replay list is a usage error, not a read-0 fallback.\n"
            "  (identity/selftest may omit it -- they do not feed the comparator.)\n");
    return EXIT_USAGE;
  }
  if (o.inject_file) {
    if (!load_inject_list(o.inject_file, s.inject)) return EXIT_USAGE;
    s.inject_active = true;
    if (!o.quiet) fprintf(stderr, "vesta_ref: --inject %zu records\n", s.inject.size());
  }
  std::vector<irq_rec_t> irqs;
  if (o.irq_file) {
    if (!load_irq_list(o.irq_file, irqs)) return EXIT_USAGE;
    if (!o.quiet) fprintf(stderr, "vesta_ref: --interrupt %zu records\n", irqs.size());
  }
  std::vector<bracket_t> brackets;
  // Script censuses, kept apart on purpose (A13's "counted separately so the two
  // censuses stay interpretable"): n_brk_pts counts V3-style realignment points
  // (a B and/or S at an index), while plants/gprs/scfails are counted PER RECORD.
  size_t n_brk_pts = 0, n_plant = 0, n_gpr = 0, n_scf = 0;
  if (o.bracket_file) {
    if (o.mode != "cosim") {
      fprintf(stderr, "vesta_ref: --bracket is a cosim-mode option (identity is"
                      " the standing byte-identity gate and must stay dumb)\n");
      return EXIT_USAGE;
    }
    if (!load_bracket_list(o.bracket_file, brackets)) return EXIT_USAGE;
    size_t nst = 0, npc = 0;
    for (const bracket_t &b : brackets) {
      nst += b.stores.size(); npc += b.has_pc ? 1 : 0;
      n_plant += b.plants.size(); n_gpr += b.gprs.size(); n_scf += b.scfails;
      if (b.is_bracket()) n_brk_pts++;
    }
    if (!o.quiet) {
      fprintf(stderr, "vesta_ref: --bracket %zu bracket(s), %zu pc realignment(s),"
                      " %zu store(s)\n", n_brk_pts, npc, nst);
      // Only printed when present, so a V3 script's stderr is unchanged.
      if (n_plant || n_gpr || n_scf)
        fprintf(stderr, "vesta_ref: --bracket %zu plant(s), %zu gpr poke(s),"
                        " %zu forced sc-fail(s) across %zu script index(es)\n",
                n_plant, n_gpr, n_scf, brackets.size());
    }
    for (const bracket_t &b : brackets)
      if (!b.has_pc && !b.stores.empty())
        fprintf(stderr, "vesta_ref: WARNING --bracket retire index %" PRIu64
                        " has S record(s) but NO B record: %zu store(s) will be"
                        " applied with no pc realignment\n",
                b.retire_index, b.stores.size());
  }

  // ---- start pc ----------------------------------------------------------
  // cfg.start_pc is consumed only by sim_t (sim.cc:113); for a bare
  // processor_t the start pc IS state.pc.
  s.proc->get_state()->pc = start_pc;
  if (o.log_commits) s.proc->enable_log_commits();

  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);

  uint64_t retires = 0, traps = 0, steps = 0;
  uint64_t brk_applied = 0, brk_stores = 0, brk_bad_addr = 0;
  uint64_t plant_applied = 0, plant_bad_addr = 0;
  uint64_t gpr_applied = 0, scf_applied = 0;

  if (o.mode == "identity") {
    // THE STANDING GATE.  Deliberately dumb and fast: N raw step(1) calls,
    // nothing else, so the byte stream is exactly stock spike's.
    for (long i = 0; i < o.instructions; i++) s.proc->step(1);
    steps = retires = (uint64_t)o.instructions;
  } else {
    // cosim: minstret-driven.
    size_t irq_next = 0;
    // One-time interrupt-delivery setup, exactly the proven sequence.
    if (!irqs.empty()) {
      reg_t want = 0;
      for (const irq_rec_t &r : irqs) want |= r.mip_bit;
      // mtvec is DELIBERATELY not forced: the boot code under test sets it,
      // and overwriting it would mask a real divergence in the RTL's mtvec.
      s.proc->put_csr(CSR_MSTATUS, s.proc->get_csr(CSR_MSTATUS) | MSTATUS_MIE);
      s.proc->put_csr(CSR_MIE, s.proc->get_csr(CSR_MIE) | want);
      if (!o.quiet)
        fprintf(stderr, "vesta_ref: irq setup mtvec=0x%" PRIx64 " mstatus=0x%" PRIx64
                        " mie=0x%" PRIx64 "\n",
                (uint64_t)s.proc->get_csr(CSR_MTVEC),
                (uint64_t)s.proc->get_csr(CSR_MSTATUS),
                (uint64_t)s.proc->get_csr(CSR_MIE));
    }
    size_t brk_next = 0;
    const uint64_t step_budget = (uint64_t)o.instructions * 4 + 1024;
    while (retires < (uint64_t)o.instructions && steps < step_budget) {
      // ---- REALIGNMENT SCRIPT: S/P (memory), G (regs), F (reservation), B (pc).
      // `<=` rather than `==` so a multi-retire step (minstret delta > 1) can
      // never step OVER a point without applying it; a strictly-less index means
      // exactly that happened, and it is reported.
      while (brk_next < brackets.size() &&
             brackets[brk_next].retire_index <= retires) {
        bracket_t &bk = brackets[brk_next];
        // ================= THE ORDER BELOW IS NORMATIVE =====================
        // RECORD_FORMAT.md, "A11-A14 application order at one retire index":
        //   1. S + P  (memory)   2. G (registers)   3. F (reservation)
        //   4. B (pc) LAST
        // It must not be reordered.  Each step's reason:
        //   * memory first, because a G/F/B decision may be about to be read
        //     through it and because a REDIRECTED bracket's stacked-PC store has
        //     to be in RAM before the redirect it implies takes effect;
        //   * G after memory -- a G never depends on RAM, but a fixed order is
        //     what makes a script reproducible;
        //   * F after memory, so a plant landing on the RESERVED address cannot
        //     be mistaken for the thing that broke the reservation;
        //   * B LAST (V3's already-ruled order): installing the pc first would
        //     let the redirect mask a store/plant that belongs at this index.
        // ====================================================================

        // --- 1a. S: bracket-interior store replay (V3), per-application logged.
        unsigned ok = 0;
        for (const bracket_store_t &st : bk.stores) {
          if (s.poke(st.addr, st.size, st.data)) { ok++; brk_stores++; }
          else {
            brk_bad_addr++;
            fprintf(stderr, "vesta_ref: WARNING bracket at retire %" PRIu64
                            ": store addr=%08" PRIx64 " size=%u is NOT backed by"
                            " --mem 0x%" PRIx64 ":0x%" PRIx64 " -- NOT applied\n",
                    bk.retire_index, st.addr, st.size, o.mem_base, o.mem_size);
          }
        }
        // --- 1b. P: A13a mainline plant.  Counted separately and deliberately
        // NOT logged per application (~29,000 per hart per test -- see the
        // header's LOGGING DISCIPLINE).  A plant whose address is not backed by
        // --mem IS reported, exactly as an S is: it means the reference will read
        // stale RAM at the consuming retire.
        //
        // A PLANT IS *NOT* MECHANICALLY IDENTICAL TO AN S, and the difference is
        // amendment A6.  An `M ... S` data field is RIGHT-JUSTIFIED (§2), so an S
        // pokes its low `size` bytes directly.  An `M ... L` data field is THE RAW
        // BUS WORD -- all four lanes -- because the core's byte/half extraction
        // happens afterwards in `datapath` from `funct3`.  A6 states the rule
        // explicitly: the bytes to serve for a load of `size` bytes at `addr` are
        //     word[8*(addr mod 4) + 8*size - 1 : 8*(addr mod 4)]
        // and `mmio_load()` above already does exactly that for the injected
        // stream.  The plant path did NOT, which is a REAL BUG that sub-word
        // shared-window loads expose:
        //
        //   MEASURED, rv32ui-p-shmem hart 0 (the cell that caught it):
        //     M 00 00008b6c L 00010009 1 beef33ee   ; lbu t2,9(t0) -> rdval 33
        //     P 28635 00010009 1 beef33ee
        //   The addressed byte is (0xbeef33ee >> 8*(9 mod 4)) & 0xff = 0x33, and
        //   the RTL retire commits 0x33.  A raw poke() of the LOW byte writes
        //   0xee, and the comparison diverged rdval rtl=00000033 spike=000000ee.
        //
        // Latent until now only because Stage 2-5's shared-window traffic is all
        // word-wide; `shmem` deliberately does byte and half loads at odd offsets.
        for (const bracket_store_t &pl : bk.plants) {
          const uint32_t lane = (pl.size >= 4) ? pl.data
                                               : (pl.data >> (8 * (pl.addr & 3)));
          if (s.poke(pl.addr, pl.size, lane)) plant_applied++;
          else {
            plant_bad_addr++;
            fprintf(stderr, "vesta_ref: WARNING plant at retire %" PRIu64
                            ": addr=%08" PRIx64 " size=%u is NOT backed by"
                            " --mem 0x%" PRIx64 ":0x%" PRIx64 " -- NOT applied"
                            " (the reference will read STALE RAM here)\n",
                    bk.retire_index, pl.addr, pl.size, o.mem_base, o.mem_size);
          }
        }
        // --- 2. G: A12 register replay, per-application logged.  The ISR's
        // register writes are ASSERTED by this, not verified.
        for (const gpr_poke_t &g : bk.gprs) {
          s.poke_gpr(g.rd, g.val);
          gpr_applied++;
          fprintf(stderr, "vesta_ref: bracket at retire %" PRIu64 ": x%u <- %08"
                          PRIx32 "%s (ASSERTED, not verified)\n",
                  bk.retire_index, g.rd, g.val,
                  g.rd == 0 ? " [no-op: x0]" : "");
        }
        // --- 3. F: A14 forced SC failure.  Counted only, never logged per
        // application.  The SC's success/failure DECISION is ASSERTED by this,
        // not compared; its address, its rd and its outcome/effect consistency
        // still are.
        for (unsigned i = 0; i < bk.scfails; i++) {
          s.clear_reservation();
          scf_applied++;
        }
        // --- 4. B: the pc, LAST.
        if (bk.has_pc) s.proc->get_state()->pc = (reg_t)bk.pc;

        bk.applied = true;
        if (bk.is_bracket()) brk_applied++;
        if (bk.retire_index < retires)
          fprintf(stderr, "vesta_ref: WARNING bracket retire index %" PRIu64
                          " was STEPPED OVER (applied late, at retire %" PRIu64
                          ")\n", bk.retire_index, retires);
        // Only a V3-shaped point (B and/or S) gets the per-application line; a
        // plant-only / F-only index is counted in the summary instead.
        if (bk.has_pc)
          fprintf(stderr, "vesta_ref: bracket at retire %" PRIu64 ": applied %u"
                          " store(s), pc <- %08" PRIx64 "\n",
                  bk.retire_index, ok, bk.pc);
        else if (!bk.stores.empty())
          fprintf(stderr, "vesta_ref: bracket at retire %" PRIu64 ": applied %u"
                          " store(s), pc unchanged (no B record)\n",
                  bk.retire_index, ok);
        brk_next++;
      }

      // Raise every interrupt scheduled for this retire boundary BEFORE the
      // step, using the un-logged clint-style poke (csrs.h:396) so it never
      // appears as a CSR write in the commit log.
      while (irq_next < irqs.size() && irqs[irq_next].retire_index == retires) {
        const irq_rec_t &r = irqs[irq_next];
        s.proc->get_state()->mip->backdoor_write_with_mask(r.mip_bit, r.mip_bit);
        if (!o.quiet)
          fprintf(stderr, "vesta_ref: irq raise retire=%" PRIu64 " %s src=%" PRIu64
                          " mip=0x%" PRIx64 "\n",
                  retires, r.bit_name.c_str(), r.source_id,
                  (uint64_t)s.proc->get_csr(CSR_MIP));
        irq_next++;
      }

      reg_t pc_before = s.proc->get_state()->pc;
      uint64_t ir0 = minstret_of(s.proc);
      s.proc->step(1);
      steps++;
      uint64_t d = (minstret_of(s.proc) - ir0) & 0xffffffffull;
      if (d) {
        retires += d;
        if (o.trace)
          fprintf(stderr, "  r[%" PRIu64 "] pc=0x%08" PRIx64 "\n", retires - 1, (uint64_t)pc_before);
      } else {
        traps++;
        if (o.trace)
          fprintf(stderr, "  TRAP at pc=0x%08" PRIx64 " mcause=0x%" PRIx64
                          " mepc=0x%" PRIx64 " -> 0x%08" PRIx64 " (no commit line)\n",
                  (uint64_t)pc_before, (uint64_t)s.proc->get_csr(CSR_MCAUSE),
                  (uint64_t)s.proc->get_csr(CSR_MEPC),
                  (uint64_t)s.proc->get_state()->pc);
      }
    }
  }

  clock_gettime(CLOCK_MONOTONIC, &t1);
  double dt = (t1.tv_sec - t0.tv_sec) + 1e-9 * (t1.tv_nsec - t0.tv_nsec);

  fflush(logf);
  if (logf != stdout) fclose(logf);

  int rc = 0;

  if (o.mmio_log_file) {
    FILE *m = fopen(o.mmio_log_file, "w");
    if (m) {
      for (const mmio_rec_t &r : s.mmio_trace)
        fprintf(m, "%c %08" PRIx64 " %u %08" PRIx64 "\n",
                r.is_store ? 'S' : 'L', r.addr, r.size, r.val);
      fclose(m);
    } else {
      fprintf(stderr, "vesta_ref: cannot write --mmio-log %s\n", o.mmio_log_file);
      rc = EXIT_USAGE;
    }
  }

  // An ISR bracket that was never reached means the reference stopped short of
  // a realignment point, so everything the comparator would compare past it is
  // unaligned by construction.  Reported loudly; the exit contract (0/1/7) is
  // deliberately NOT extended -- the runner's verdict already requires
  // compare.py to exit 0, and that is what this invalidates.
  {
    size_t unreached = 0, first = 0, un_brk = 0;
    size_t un_plant = 0, un_gpr = 0, un_scf = 0, un_first = 0;
    for (const bracket_t &b : brackets)
      if (!b.applied) {
        if (!unreached) first = b.retire_index;
        unreached++;
        if (b.is_bracket()) un_brk++;
        if (!(un_plant + un_gpr + un_scf) &&
            (b.plants.size() || b.gprs.size() || b.scfails))
          un_first = b.retire_index;
        un_plant += b.plants.size();
        un_gpr   += b.gprs.size();
        un_scf   += b.scfails;
      }
    if (un_brk)
      fprintf(stderr, "vesta_ref: WARNING %zu of %zu ISR bracket(s) NEVER"
                      " REACHED (run ended at retire %" PRIu64 ", first"
                      " unreached index %zu). The reference is NOT realigned"
                      " past that point.\n",
              un_brk, n_brk_pts, retires, (size_t)first);
    // An unconsumed P/F/G tail is as loud as the --inject one, and for a
    // stronger reason: a PLANT THAT NEVER FIRED means the reference read stale
    // RAM somewhere, which is the one failure mode of the whole V4 design
    // (v4_design.md 3.5).  Exit stays 0/1/7 -- the runner's verdict already
    // requires compare.py to exit 0, and that is what this invalidates.
    if (un_plant || un_gpr || un_scf)
      fprintf(stderr, "vesta_ref: WARNING realignment tail UNCONSUMED: %zu"
                      " plant(s), %zu gpr poke(s), %zu forced sc-fail(s) NEVER"
                      " APPLIED (run ended at retire %" PRIu64 ", first unapplied"
                      " index %zu). A plant that never fired means the reference"
                      " READ STALE RAM.\n",
              un_plant, un_gpr, un_scf, retires, (size_t)un_first);
    if (brk_bad_addr)
      fprintf(stderr, "vesta_ref: WARNING %" PRIu64 " bracket store(s) fell"
                      " outside --mem and were not applied\n", brk_bad_addr);
    if (plant_bad_addr)
      fprintf(stderr, "vesta_ref: WARNING %" PRIu64 " plant(s) fell outside"
                      " --mem and were not applied\n", plant_bad_addr);
  }

  if (s.inject_active && s.inject_idx < s.inject.size()) {
    // An unconsumed tail is a WARNING, not a failure (exit stays 0).
    fprintf(stderr, "vesta_ref: warning: --inject tail unconsumed: %zu of %zu"
                    " records unused (next addr=%08" PRIx64 ")\n",
            s.inject.size() - s.inject_idx, s.inject.size(),
            s.inject[s.inject_idx].addr);
  }

  if (!o.quiet) {
    // Each census only appears when the script actually carried that record
    // type, so a V3 (B/S-only) run's summary line is byte-for-byte the V3 one.
    char brk[320] = "";
    {
      // snprintf returns the WOULD-BE length, so every += is clamped: an
      // unclamped one would let `brk + off` run past the buffer.
      size_t off = 0;
      auto bump = [&](int n) {
        if (n > 0) off += (size_t)n;
        if (off > sizeof brk - 1) off = sizeof brk - 1;
      };
      auto add = [&](const char *fmt, uint64_t a, uint64_t b) {
        bump(snprintf(brk + off, sizeof brk - off, fmt, a, b));
      };
      if (n_brk_pts) {
        bump(snprintf(brk + off, sizeof brk - off,
                      " brackets=%" PRIu64 "/%zu brkstores=%" PRIu64,
                      brk_applied, n_brk_pts, brk_stores));
      }
      if (n_gpr)   add(" gprs=%" PRIu64 "/%" PRIu64,    gpr_applied,   (uint64_t)n_gpr);
      if (n_plant) add(" plants=%" PRIu64 "/%" PRIu64,  plant_applied, (uint64_t)n_plant);
      if (n_scf)   add(" scfails=%" PRIu64 "/%" PRIu64, scf_applied,   (uint64_t)n_scf);
    }
    // hartid appears ONLY when non-default: the single-hart path's output must
    // not acquire new noise (the identity gate is compared by md5).
    char hid[32] = "";
    if (o.hartid) snprintf(hid, sizeof hid, " hartid=%u", (unsigned)o.hartid);
    fprintf(stderr, "vesta_ref: %s%s retires=%" PRIu64 " traps=%" PRIu64 " steps=%" PRIu64
                    " mmio_l=%" PRIu64 " mmio_s=%" PRIu64 " inject=%zu/%zu%s"
                    " %.4fs (%.0f insn/s)\n",
            o.mode.c_str(), hid, retires, traps, steps, s.n_load, s.n_store,
            s.inject_idx, s.inject.size(), brk, dt, retires / (dt > 0 ? dt : 1));
  }

  return rc;
}
