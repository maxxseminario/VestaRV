#!/usr/bin/python3.6
# -*- coding: utf-8 -*-
"""Compact rv32imac_zba_zbb_zbs_zbc disassembler for lockstep triage output.

Phase V2 (Agent A).  Stdlib only, Python 3.6 syntax only.

This is NOT a general-purpose disassembler.  Its only job is to annotate the
`R` records the comparator prints around a divergence so a human reading the
context does not have to hand-decode hex.  Coverage target = exactly the ISA
the default Castalia config implements (`v0_report.md` §6:
rv32imac_zba_zbb_zbs_zbc, all X-/P-series knobs false) plus the three VestaRV
custom encodings on opcode 0x0b (`verification/env/p/riscv_test.h`).

Anything outside that returns a string beginning with "unknown" — a deliberate,
documented limitation (kickoff: "'unknown' is acceptable for exotica").  The
caller must never make a comparison decision from this module's output; it is
presentation only.
"""

from __future__ import print_function

# ABI register names.  Used instead of x<n> because a human triaging a
# divergence reads "a0"/"sp" far faster than "x10"/"x2".
XREG = [
    "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2",
    "s0", "s1", "a0", "a1", "a2", "a3", "a4", "a5",
    "a6", "a7", "s2", "s3", "s4", "s5", "s6", "s7",
    "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6",
]

# CSR numbers the core implements or the suite touches, for readable csr* output.
CSR_NAMES = {
    0x001: "fflags", 0x002: "frm", 0x003: "fcsr",
    0x300: "mstatus", 0x301: "misa", 0x302: "medeleg", 0x303: "mideleg",
    0x304: "mie", 0x305: "mtvec", 0x306: "mcounteren", 0x320: "mcountinhibit",
    0x340: "mscratch", 0x341: "mepc", 0x342: "mcause", 0x343: "mtval",
    0x344: "mip", 0x34a: "mtinst", 0x34b: "mtval2",
    0x017: "jvt",
    0xb00: "mcycle", 0xb02: "minstret", 0xb80: "mcycleh", 0xb82: "minstreth",
    0xc00: "cycle", 0xc01: "time", 0xc02: "instret",
    0xc80: "cycleh", 0xc81: "timeh", 0xc82: "instreth",
    0xf11: "mvendorid", 0xf12: "marchid", 0xf13: "mimpid", 0xf14: "mhartid",
    0x323: "mhpmevent3", 0x324: "mhpmevent4",
    0xb03: "mhpmcounter3", 0xb04: "mhpmcounter4",
}


def _csr(n):
    return CSR_NAMES.get(n, "0x%03x" % n)


def _sx(value, bits):
    """Sign-extend `value` interpreted as a `bits`-wide two's-complement int."""
    sign = 1 << (bits - 1)
    return (value & (sign - 1)) - (value & sign)


def _imm(v):
    """Render a signed immediate the way objdump does."""
    return "%d" % v


# --------------------------------------------------------------------------
# 32-bit forms
# --------------------------------------------------------------------------

_BRANCH = {0: "beq", 1: "bne", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}
_LOAD = {0: "lb", 1: "lh", 2: "lw", 4: "lbu", 5: "lhu"}
_STORE = {0: "sb", 1: "sh", 2: "sw"}
_OPIMM = {0: "addi", 2: "slti", 3: "sltiu", 4: "xori", 6: "ori", 7: "andi"}
_OP_B0 = {0: "add", 1: "sll", 2: "slt", 3: "sltu", 4: "xor", 5: "srl",
          6: "or", 7: "and"}
_OP_M = {0: "mul", 1: "mulh", 2: "mulhsu", 3: "mulhu",
         4: "div", 5: "divu", 6: "rem", 7: "remu"}
# funct7 == 0x05 : Zbc carry-less multiply + Zbb min/max
_OP_F05 = {1: "clmul", 3: "clmulh", 2: "clmulr",
           4: "min", 5: "minu", 6: "max", 7: "maxu"}
_OP_F10 = {2: "sh1add", 4: "sh2add", 6: "sh3add"}          # Zba
_OP_F20 = {0: "sub", 5: "sra", 7: "andn", 6: "orn", 4: "xnor"}
_OP_F30 = {1: "rol", 5: "ror"}                              # Zbb
_AMO = {0x00: "amoadd.w", 0x01: "amoswap.w", 0x02: "lr.w", 0x03: "sc.w",
        0x04: "amoxor.w", 0x08: "amoor.w", 0x0c: "amoand.w",
        0x10: "amomin.w", 0x14: "amomax.w", 0x18: "amominu.w",
        0x1c: "amomaxu.w"}
# Zbb single-bit-count / sign-extend, encoded as OP-IMM funct7=0x30, funct3=001
_ZBB_UNARY = {0x00: "clz", 0x01: "ctz", 0x02: "cpop",
              0x04: "sext.b", 0x05: "sext.h"}


def _d32(insn):
    op = insn & 0x7f
    rd = (insn >> 7) & 0x1f
    f3 = (insn >> 12) & 7
    rs1 = (insn >> 15) & 0x1f
    rs2 = (insn >> 20) & 0x1f
    f7 = (insn >> 25) & 0x7f
    d, a, b = XREG[rd], XREG[rs1], XREG[rs2]

    if op == 0x37:
        return "lui %s,0x%x" % (d, (insn >> 12) & 0xfffff)
    if op == 0x17:
        return "auipc %s,0x%x" % (d, (insn >> 12) & 0xfffff)
    if op == 0x6f:
        j = _sx((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xff) << 12) |
                (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3ff) << 1), 21)
        return "jal %s,pc%+d" % (d, j)
    if op == 0x67 and f3 == 0:
        return "jalr %s,%s(%s)" % (d, _imm(_sx(insn >> 20, 12)), a)
    if op == 0x63:
        bi = _sx((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) |
                 (((insn >> 25) & 0x3f) << 5) | (((insn >> 8) & 0xf) << 1), 13)
        return "%s %s,%s,pc%+d" % (_BRANCH.get(f3, "b?%d" % f3), a, b, bi)
    if op == 0x03:
        if f3 in _LOAD:
            return "%s %s,%s(%s)" % (_LOAD[f3], d, _imm(_sx(insn >> 20, 12)), a)
        return "unknown load funct3=%d" % f3
    if op == 0x23:
        si = _sx(((insn >> 25) << 5) | ((insn >> 7) & 0x1f), 12)
        if f3 in _STORE:
            return "%s %s,%s(%s)" % (_STORE[f3], b, _imm(si), a)
        return "unknown store funct3=%d" % f3
    if op == 0x13:
        if f3 in _OPIMM:
            return "%s %s,%s,%s" % (_OPIMM[f3], d, a, _imm(_sx(insn >> 20, 12)))
        sh = rs2
        if f3 == 1:
            if f7 == 0x00:
                return "slli %s,%s,%d" % (d, a, sh)
            if f7 == 0x30 and rs2 in _ZBB_UNARY:
                return "%s %s,%s" % (_ZBB_UNARY[rs2], d, a)
            if f7 == 0x24:
                return "bclri %s,%s,%d" % (d, a, sh)
            if f7 == 0x34:
                return "binvi %s,%s,%d" % (d, a, sh)
            if f7 == 0x14:
                return "bseti %s,%s,%d" % (d, a, sh)
        if f3 == 5:
            if f7 == 0x00:
                return "srli %s,%s,%d" % (d, a, sh)
            if f7 == 0x20:
                return "srai %s,%s,%d" % (d, a, sh)
            if f7 == 0x24:
                return "bexti %s,%s,%d" % (d, a, sh)
            if f7 == 0x30:
                return "rori %s,%s,%d" % (d, a, sh)
            if f7 == 0x14 and rs2 == 0x07:
                return "orc.b %s,%s" % (d, a)
            if f7 == 0x34 and rs2 == 0x18:
                return "rev8 %s,%s" % (d, a)
        return "unknown op-imm funct3=%d funct7=0x%02x" % (f3, f7)
    if op == 0x33:
        if f7 == 0x00 and f3 in _OP_B0:
            return "%s %s,%s,%s" % (_OP_B0[f3], d, a, b)
        if f7 == 0x01:
            return "%s %s,%s,%s" % (_OP_M[f3], d, a, b)
        if f7 == 0x05 and f3 in _OP_F05:
            return "%s %s,%s,%s" % (_OP_F05[f3], d, a, b)
        if f7 == 0x10 and f3 in _OP_F10:
            return "%s %s,%s,%s" % (_OP_F10[f3], d, a, b)
        if f7 == 0x20 and f3 in _OP_F20:
            return "%s %s,%s,%s" % (_OP_F20[f3], d, a, b)
        if f7 == 0x30 and f3 in _OP_F30:
            return "%s %s,%s,%s" % (_OP_F30[f3], d, a, b)
        if f7 == 0x04 and f3 == 4 and rs2 == 0:
            return "zext.h %s,%s" % (d, a)
        if f7 == 0x14 and f3 == 1:
            return "bset %s,%s,%s" % (d, a, b)
        if f7 == 0x24 and f3 == 1:
            return "bclr %s,%s,%s" % (d, a, b)
        if f7 == 0x24 and f3 == 5:
            return "bext %s,%s,%s" % (d, a, b)
        if f7 == 0x34 and f3 == 1:
            return "binv %s,%s,%s" % (d, a, b)
        return "unknown op funct3=%d funct7=0x%02x" % (f3, f7)
    if op == 0x0f:
        if f3 == 0:
            if (insn >> 20) == 0x010:
                return "pause"
            return "fence"
        if f3 == 1:
            return "fence.i"
        return "unknown misc-mem funct3=%d" % f3
    if op == 0x73:
        imm12 = (insn >> 20) & 0xfff
        if f3 == 0:
            if imm12 == 0x000:
                return "ecall"
            if imm12 == 0x001:
                return "ebreak"
            if imm12 == 0x302:
                return "mret"
            if imm12 == 0x102:
                return "sret"
            if imm12 == 0x105:
                return "wfi"
            if imm12 == 0x00d:
                return "wrs.nto"
            if imm12 == 0x01d:
                return "wrs.sto"
            return "unknown system imm12=0x%03x" % imm12
        if f3 in (1, 2, 3):
            m = {1: "csrrw", 2: "csrrs", 3: "csrrc"}[f3]
            return "%s %s,%s,%s" % (m, d, _csr(imm12), a)
        if f3 in (5, 6, 7):
            m = {5: "csrrwi", 6: "csrrsi", 7: "csrrci"}[f3]
            return "%s %s,%s,%d" % (m, d, _csr(imm12), rs1)
        return "unknown system funct3=%d" % f3
    if op == 0x2f and f3 == 2:
        f5 = f7 >> 2
        aq = "aq" if (f7 >> 1) & 1 else ""
        rl = "rl" if f7 & 1 else ""
        sfx = (("." + aq) if aq else "") + (("." + rl) if rl else "")
        name = _AMO.get(f5)
        if name is None:
            return "unknown amo funct5=0x%02x" % f5
        if f5 == 0x02:
            return "%s%s %s,(%s)" % (name, sfx, d, a)
        return "%s%s %s,%s,(%s)" % (name, sfx, d, b, a)
    if op == 0x0b:
        # VestaRV custom encodings, verification/env/p/riscv_test.h:15-33
        if f3 == 0:
            return "iret"
        if f3 == 1:
            return "ignite" if f7 == 1 else "extinguish"
        return "unknown custom-0x0b funct3=%d" % f3
    return "unknown opcode=0x%02x" % op


# --------------------------------------------------------------------------
# 16-bit (RVC) forms
# --------------------------------------------------------------------------

def _cr(n):
    """Compressed 3-bit register field -> ABI name (x8..x15)."""
    return XREG[(n & 7) + 8]


def _d16(insn):
    q = insn & 3
    f3 = (insn >> 13) & 7
    rd = (insn >> 7) & 0x1f
    rs2 = (insn >> 2) & 0x1f
    rdp = _cr(insn >> 7)
    rs1p = _cr(insn >> 7)
    rs2p = _cr(insn >> 2)

    if q == 0:
        if insn == 0:
            return "illegal"
        if f3 == 0:
            nz = (((insn >> 7) & 0xf) << 6) | (((insn >> 11) & 3) << 4) | \
                 (((insn >> 5) & 1) << 3) | (((insn >> 6) & 1) << 2)
            return "c.addi4spn %s,sp,%d" % (rdp, nz)
        if f3 == 2 or f3 == 6:
            off = (((insn >> 5) & 1) << 6) | (((insn >> 10) & 7) << 3) | \
                  (((insn >> 6) & 1) << 2)
            if f3 == 2:
                return "c.lw %s,%d(%s)" % (rdp, off, rs1p)
            return "c.sw %s,%d(%s)" % (rs2p, off, rs1p)
        return "unknown c0 funct3=%d" % f3
    if q == 1:
        if f3 == 0:
            i = _sx((((insn >> 12) & 1) << 5) | rs2, 6)
            if rd == 0:
                return "c.nop"
            return "c.addi %s,%d" % (XREG[rd], i)
        if f3 == 1:
            j = _sx((((insn >> 12) & 1) << 11) | (((insn >> 8) & 1) << 10) |
                    (((insn >> 9) & 3) << 8) | (((insn >> 6) & 1) << 7) |
                    (((insn >> 7) & 1) << 6) | (((insn >> 2) & 1) << 5) |
                    (((insn >> 11) & 1) << 4) | (((insn >> 3) & 7) << 1), 12)
            return "c.jal pc%+d" % j
        if f3 == 2:
            return "c.li %s,%d" % (XREG[rd],
                                   _sx((((insn >> 12) & 1) << 5) | rs2, 6))
        if f3 == 3:
            if rd == 2:
                i = _sx((((insn >> 12) & 1) << 9) | (((insn >> 3) & 3) << 7) |
                        (((insn >> 5) & 1) << 6) | (((insn >> 2) & 1) << 5) |
                        (((insn >> 6) & 1) << 4), 10)
                return "c.addi16sp sp,%d" % i
            return "c.lui %s,0x%x" % (
                XREG[rd], (_sx((((insn >> 12) & 1) << 5) | rs2, 6)) & 0xfffff)
        if f3 == 4:
            f2 = (insn >> 10) & 3
            sh = (((insn >> 12) & 1) << 5) | rs2
            if f2 == 0:
                return "c.srli %s,%d" % (rs1p, sh)
            if f2 == 1:
                return "c.srai %s,%d" % (rs1p, sh)
            if f2 == 2:
                return "c.andi %s,%d" % (rs1p, _sx(sh, 6))
            if (insn >> 12) & 1:
                # RV64/Zcb territory; only c.mul is reachable on this config
                # and only with ENABLE_ZCB, which is false by default.
                if ((insn >> 5) & 3) == 2:
                    return "c.mul %s,%s" % (rs1p, rs2p)
                return "unknown c1 funct2=3 bit12=1"
            m = {0: "c.sub", 1: "c.xor", 2: "c.or", 3: "c.and"}[(insn >> 5) & 3]
            return "%s %s,%s" % (m, rs1p, rs2p)
        if f3 == 5:
            j = _sx((((insn >> 12) & 1) << 11) | (((insn >> 8) & 1) << 10) |
                    (((insn >> 9) & 3) << 8) | (((insn >> 6) & 1) << 7) |
                    (((insn >> 7) & 1) << 6) | (((insn >> 2) & 1) << 5) |
                    (((insn >> 11) & 1) << 4) | (((insn >> 3) & 7) << 1), 12)
            return "c.j pc%+d" % j
        if f3 == 6 or f3 == 7:
            b = _sx((((insn >> 12) & 1) << 8) | (((insn >> 5) & 3) << 6) |
                    (((insn >> 2) & 1) << 5) | (((insn >> 10) & 3) << 3) |
                    (((insn >> 3) & 3) << 1), 9)
            return "%s %s,pc%+d" % ("c.beqz" if f3 == 6 else "c.bnez", rs1p, b)
        return "unknown c1 funct3=%d" % f3
    if q == 2:
        if f3 == 0:
            return "c.slli %s,%d" % (XREG[rd],
                                     (((insn >> 12) & 1) << 5) | rs2)
        if f3 == 2:
            off = (((insn >> 2) & 3) << 6) | (((insn >> 12) & 1) << 5) | \
                  (((insn >> 4) & 7) << 2)
            return "c.lwsp %s,%d(sp)" % (XREG[rd], off)
        if f3 == 4:
            if (insn >> 12) & 1:
                if rs2 == 0 and rd == 0:
                    return "c.ebreak"
                if rs2 == 0:
                    return "c.jalr %s" % XREG[rd]
                return "c.add %s,%s" % (XREG[rd], XREG[rs2])
            if rs2 == 0:
                return "c.jr %s" % XREG[rd]
            return "c.mv %s,%s" % (XREG[rd], XREG[rs2])
        if f3 == 6:
            off = (((insn >> 7) & 3) << 6) | (((insn >> 9) & 0xf) << 2)
            return "c.swsp %s,%d(sp)" % (XREG[rs2], off)
        return "unknown c2 funct3=%d" % f3
    return "unknown quadrant"


def disasm(hexfield):
    """Decode a wire-format `insn` field (4 or 8 lowercase hex digits).

    Returns a short mnemonic string, or a string starting with "unknown"/"x?"
    when the encoding is outside the covered ISA or the field carries an
    Amendment-A5 `x` nibble.  Never raises.
    """
    if hexfield is None:
        return "?"
    s = hexfield.strip().lower()
    if "x" in s:
        # Amendment A5: the tracer sampled an X.  Do not invent a decode.
        return "x-tainted"
    try:
        v = int(s, 16)
    except ValueError:
        return "?"
    try:
        if len(s) <= 4:
            return _d16(v & 0xffff)
        return _d32(v & 0xffffffff)
    except Exception:                                   # pragma: no cover
        return "unknown (decoder error)"


if __name__ == "__main__":                              # pragma: no cover
    import sys
    for arg in sys.argv[1:]:
        print("%-9s %s" % (arg, disasm(arg)))
