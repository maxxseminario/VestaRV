// ---------------------------------------------------------------------------
// probe_a13_a14.cc -- the MANDATORY §7.4 probe for v4_design.md's A13/A14
// C++ claims, which the design memo made from SOURCE READING ONLY.
//
// Build (the build_vesta_ref.sh compile line verbatim -- same pinned libriscv,
// same conda gcc 13; there is no plain g++ on this host):
//
//   ~/local/mamba/envs/spike13/bin/x86_64-conda-linux-gnu-g++ -std=c++20 -O2 \
//     -I$HOME/local/include \
//     -o ~/vestarv/xcelium/riscv_test/behavioral_mp/cosim_work/probe_a13_a14 \
//     probe_a13_a14.cc -L$HOME/local/lib -lriscv
//
// Run:    source ~/local/spike_env.sh && cosim_work/probe_a13_a14
// Exit:   0 = every claim confirmed, 1 = at least one FALSIFIED (then STOP: the
//         memo's C++ claims were source-read only, and Stage 3 rests on them).
//
// RESULT 2026-07-30 (C2): 5/5 PASS. See the report; the one memo CORRECTION is
// P5 -- v4_design.md §4.1 M3 names `state.XPR.write_no_log()` as a peer of
// poke(); NO SUCH METHOD EXISTS at this pin. `regfile_t` (decode.h:226-248)
// offers only `write()`, which is ALREADY un-logged: the commit log is driven by
// a separate `state->log_reg_write` map (processor.h:212) that only the WRITE_RD
// insn macros populate. So A12/`G` is implementable, but not under that name.
//
// Five claims, each executed rather than read:
//
//   P1  a plain lr.w / sc.w pair on --mem RAM SUCCEEDS (rd=0, memory written).
//       This is the control: it proves the hand-assembled encodings are right,
//       so a "failure" in P2 cannot be a broken opcode.
//   P2  mmu_t::yield_load_reservation() between the lr.w and the sc.w makes the
//       sc.w FAIL: rd=1 AND the memory word is unchanged.   [A14]
//   P3  a raw RAM poke() between the lr.w and the sc.w does NOT disturb the
//       reservation (rd=0, memory written).  So PLANT and F are orthogonal
//       mechanisms and a plant may safely land inside an LR/SC window. [A13]
//   P4  lr.w to an address inside the MMIO callback window THROWS (the retire
//       does not commit).  This is the reason PLANT exists instead of a second
//       --mmio window.                                                   [A13]
//   P5  regfile write: `state->XPR.write(rd,v)` changes the architectural
//       register and emits NO commit-log line.  [A12 -- note the memo names a
//       `write_no_log()` peer of poke(); NO SUCH METHOD EXISTS at this pin.]
// ---------------------------------------------------------------------------
#include <cstdio>
#include <cstdarg>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <iostream>

#include "riscv/cfg.h"
#include "riscv/processor.h"
#include "riscv/simif.h"
#include "riscv/mmu.h"

static const uint64_t MEM_BASE = 0x0,     MEM_SIZE = 0x20000;
static const uint64_t MMIO_BASE = 0x4000, MMIO_SIZE = 0x4000;
static const uint64_t CODE = 0x8000;        // private TCM -- where the pair executes
static const uint64_t WORD = 0x10080;       // shared bulk RAM: shcount's atomic counter

class probe_sim_t : public simif_t {
public:
  probe_sim_t() {
    cfg.isa = "rv32imac_zicsr"; cfg.priv = "m";
    cfg.endianness = endianness_little;
    cfg.mem_layout = std::vector<mem_cfg_t>({mem_cfg_t(MEM_BASE, MEM_SIZE)});
    cfg.hartids = std::vector<size_t>({0});
    cfg.explicit_hartids = false; cfg.real_time_clint = false;
    ram.assign(MEM_SIZE, 0);
    debug_mmu = new mmu_t(this, cfg.endianness, NULL, cfg.cache_blocksz);
    proc = new processor_t(cfg.isa, cfg.priv, &cfg, this, 0, false, stdout, std::cerr);
    harts[0] = proc;
  }
  ~probe_sim_t() override { delete proc; delete debug_mmu; }
  char* addr_to_mem(reg_t p) override {
    if (p >= MMIO_BASE && p < MMIO_BASE + MMIO_SIZE) return NULL;   // MMIO wins
    if (p >= MEM_BASE && p < MEM_BASE + MEM_SIZE) return (char*)&ram[p - MEM_BASE];
    return NULL;
  }
  bool mmio_load(reg_t, size_t len, uint8_t *b) override { memset(b, 0, len); return true; }
  bool mmio_store(reg_t, size_t, const uint8_t *) override { return true; }
  void proc_reset(unsigned) override {}
  const cfg_t& get_cfg() const override { return cfg; }
  const std::map<size_t, processor_t*>& get_harts() const override { return harts; }
  const char* get_symbol(uint64_t) override { return NULL; }

  void poke32(uint64_t a, uint32_t v) {           // the vesta_ref poke(), verbatim shape
    for (int i = 0; i < 4; i++) ram[a - MEM_BASE + i] = (uint8_t)(v >> (8 * i));
  }
  uint32_t peek32(uint64_t a) const {
    const uint8_t *p = &ram[a - MEM_BASE];
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
  }
  void w32(uint64_t a, uint32_t v) { poke32(a, v); }

  cfg_t cfg; processor_t *proc = NULL;
  std::map<size_t, processor_t*> harts; std::vector<uint8_t> ram;
};

// ---- hand-assembled RV32A encodings ---------------------------------------
// funct5[31:27] aq[26] rl[25] rs2[24:20] rs1[19:15] funct3[14:12] rd[11:7] op[6:0]
static uint32_t enc_lr_w(unsigned rd, unsigned rs1)
{ return (0x02u << 27) | (rs1 << 15) | (2u << 12) | (rd << 7) | 0x2fu; }
static uint32_t enc_sc_w(unsigned rd, unsigned rs2, unsigned rs1)
{ return (0x03u << 27) | (rs2 << 20) | (rs1 << 15) | (2u << 12) | (rd << 7) | 0x2fu; }

static int fails = 0;
static void check(const char *tag, bool ok, const char *fmt, ...)
{
  va_list ap; char buf[512];
  va_start(ap, fmt); vsnprintf(buf, sizeof buf, fmt, ap); va_end(ap);
  printf("  %-4s %-6s %s\n", tag, ok ? "PASS" : "**FAIL**", buf);
  if (!ok) fails++;
}

// Run one lr.w/sc.w pair at pc=CODE with rs1=a0 pointing at `word_addr`,
// storing t2 = `store_val`.  `between` runs after the lr.w retires.
struct pair_result_t { uint32_t sc_rd; uint32_t mem_after; uint64_t traps; uint64_t retires; };

static pair_result_t run_pair(probe_sim_t &s, uint64_t code, uint64_t word_addr,
                              uint32_t store_val, void (*between)(probe_sim_t &))
{
  s.w32(code + 0, enc_lr_w(/*rd=t0*/5, /*rs1=a0*/10));
  s.w32(code + 4, enc_sc_w(/*rd=t1*/6, /*rs2=t2*/7, /*rs1=a0*/10));
  auto *st = s.proc->get_state();
  st->XPR.write(10, (reg_t)word_addr);      // a0 = the reservation address
  st->XPR.write(7,  (reg_t)store_val);      // t2 = the value sc.w will store
  st->XPR.write(6,  (reg_t)0xdeadbeef);     // t1 = poison, so "untouched" is visible
  st->pc = (reg_t)code;
  pair_result_t r{}; r.traps = 0; r.retires = 0;
  for (int i = 0; i < 2; i++) {
    uint64_t m0 = s.proc->get_state()->minstret->read();
    s.proc->step(1);
    if (s.proc->get_state()->minstret->read() == m0) r.traps++; else r.retires++;
    if (i == 0 && between) between(s);
  }
  r.sc_rd = (uint32_t)st->XPR[6];
  r.mem_after = s.peek32(word_addr);
  return r;
}

int main()
{
  printf("probe_a13_a14: executing the A13/A14 claims (v4_design.md §7.4)\n");
  printf("  encodings: lr.w t0,(a0) = %08x   sc.w t1,t2,(a0) = %08x\n",
         enc_lr_w(5, 10), enc_sc_w(6, 7, 10));

  // ---- P1: control -- a plain lr/sc pair on RAM succeeds -------------------
  {
    probe_sim_t s; s.w32(WORD, 0x11111111);
    auto r = run_pair(s, CODE, WORD, 0xa5a5a5a5, NULL);
    check("P1", r.sc_rd == 0 && r.mem_after == 0xa5a5a5a5 && r.traps == 0,
          "plain lr.w/sc.w: rd=%u (want 0) mem=%08x (want a5a5a5a5) traps=%llu retires=%llu",
          r.sc_rd, r.mem_after, (unsigned long long)r.traps, (unsigned long long)r.retires);
  }

  // ---- P2 [A14]: yield_load_reservation() forces the SC to FAIL ------------
  {
    probe_sim_t s; s.w32(WORD, 0x11111111);
    auto r = run_pair(s, CODE, WORD, 0xa5a5a5a5,
                      [](probe_sim_t &sp) { sp.proc->get_mmu()->yield_load_reservation(); });
    check("P2", r.sc_rd == 1 && r.mem_after == 0x11111111 && r.traps == 0,
          "yield_load_reservation(): rd=%u (want 1) mem=%08x (want 11111111, UNwritten) traps=%llu",
          r.sc_rd, r.mem_after, (unsigned long long)r.traps);
  }

  // ---- P3 [A13]: a raw poke() does NOT disturb the reservation -------------
  {
    probe_sim_t s; s.w32(WORD, 0x11111111);
    auto r = run_pair(s, CODE, WORD, 0xa5a5a5a5,
                      [](probe_sim_t &sp) { sp.poke32(WORD, 0x22222222); });
    check("P3", r.sc_rd == 0 && r.mem_after == 0xa5a5a5a5 && r.traps == 0,
          "poke() inside the LR/SC window: rd=%u (want 0) mem=%08x (want a5a5a5a5) traps=%llu"
          "  -- PLANT and F are orthogonal",
          r.sc_rd, r.mem_after, (unsigned long long)r.traps);
  }

  // ---- P4 [A13]: lr.w into the MMIO callback window THROWS -----------------
  {
    probe_sim_t s;
    const uint64_t MMIO_W = 0x5000;                 // CLINT msip[0] -- a real callback addr
    s.w32(CODE + 0, enc_lr_w(5, 10));
    auto *st = s.proc->get_state();
    st->XPR.write(10, (reg_t)MMIO_W); st->pc = (reg_t)CODE;
    uint64_t m0 = st->minstret->read();
    s.proc->step(1);
    bool trapped = (st->minstret->read() == m0);
    check("P4", trapped,
          "lr.w to the --mmio window: %s (mcause=%llx mepc=%llx) -- this is WHY the shared"
          " window must be PLANTED, not made a callback region",
          trapped ? "TRAPPED, no commit" : "COMMITTED (claim falsified!)",
          (unsigned long long)s.proc->get_csr(CSR_MCAUSE),
          (unsigned long long)s.proc->get_csr(CSR_MEPC));
  }

  // ---- P5 [A12]: XPR.write() is architectural and un-logged ---------------
  {
    probe_sim_t s;
    auto *st = s.proc->get_state();
    st->XPR.write(28, (reg_t)0x12345678);           // t3
    bool val_ok  = ((uint32_t)st->XPR[28] == 0x12345678);
    bool log_ok  = st->log_reg_write.empty();
    check("P5", val_ok && log_ok,
          "state->XPR.write(28,..): x28=%08x (want 12345678) log_reg_write=%zu entries (want 0)"
          "  -- NOTE there is NO write_no_log() at this pin; write() is already un-logged",
          (uint32_t)st->XPR[28], st->log_reg_write.size());
  }

  printf("probe_a13_a14: %s (%d failure(s))\n", fails ? "FALSIFIED" : "ALL CLAIMS CONFIRMED", fails);
  return fails ? 1 : 0;
}
