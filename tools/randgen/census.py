#!/usr/bin/python3.6
"""census.py -- count what is ACTUALLY in a built image, by field decode.

WHY THIS IS A SEPARATE INSTRUMENT
---------------------------------
k3_spec.md requirement 5 (witness-first): *"prove the generator actually emitted
the shapes it claims -- count them from the DECODED image ... A per-stream shape
manifest is part of the output, and the census validates the manifest, not the
other way round."*

So this module must not be able to agree with the generator by construction.
It shares nothing with `isa_model.py` except the class NAMES: the generator
emits mnemonic TEXT, `gas` encodes it, and this file decodes the resulting BYTES
back to a mnemonic from its own opcode/funct3/funct7 table, written from the
RISC-V encodings and checked against `objdump -M no-aliases` in the unit tests.
`gas` and `objdump` are the third parties that make the loop honest.

R-K2-5 IS THE REASON IT IS A FIELD DECODE AND NOT A PATTERN MATCH.
The S5 ledger's census shorthand "ends `200f`" for `cbo.zero` was ruled WRONG as
a detector: it holds only for `rs1 in {x0,x1}`, because `rs1` sits in bits 19:15
-- inside the low sixteen -- so a real `cbo.zero a1` ends `a00f`.  A K3 stream
draws rd/rs1/rs2 from a 25-register pool, so ANY low-bits pattern match is
confidently wrong here.  `naive_suffix_count()` below exists solely so the unit
tests can demonstrate that live rather than cite it.

`tools/cosim/disasm.py` is deliberately NOT reused: its own docstring says "the
caller must never make a comparison decision from this module's output; it is
presentation only."

Python 3.6 compatible.
"""

import os
import re
import struct
import subprocess
import sys

PREFIX = os.environ.get('RISCV_PREFIX', 'riscv-none-elf-')

# --------------------------------------------------------------------------
# The decode table.  Written from the RISC-V base + M + A + Zba/Zbb/Zbc/Zbs
# encodings; every entry is asserted against `objdump -M no-aliases` by
# test_randgen.test_decoder_agrees_with_objdump, which is the instrument
# validation method rule 4 asks for -- against KNOWN NONZERO values, one per
# mnemonic, not against an expected zero.
# --------------------------------------------------------------------------
_BRANCH = {0: 'beq', 1: 'bne', 4: 'blt', 5: 'bge', 6: 'bltu', 7: 'bgeu'}
_LOAD = {0: 'lb', 1: 'lh', 2: 'lw', 4: 'lbu', 5: 'lhu'}
_STORE = {0: 'sb', 1: 'sh', 2: 'sw'}
_OPIMM = {0: 'addi', 2: 'slti', 3: 'sltiu', 4: 'xori', 6: 'ori', 7: 'andi'}
_OP_F0 = {0: 'add', 1: 'sll', 2: 'slt', 3: 'sltu', 4: 'xor', 5: 'srl',
          6: 'or', 7: 'and'}
_OP_F20 = {0: 'sub', 4: 'xnor', 5: 'sra', 6: 'orn', 7: 'andn'}
_OP_F01 = {0: 'mul', 1: 'mulh', 2: 'mulhsu', 3: 'mulhu',
           4: 'div', 5: 'divu', 6: 'rem', 7: 'remu'}
_OP_F10 = {2: 'sh1add', 4: 'sh2add', 6: 'sh3add'}
_OP_F05 = {1: 'clmul', 2: 'clmulr', 3: 'clmulh',
           4: 'min', 5: 'minu', 6: 'max', 7: 'maxu'}
_OP_F30 = {1: 'rol', 5: 'ror'}
_OP_F24 = {1: 'bclr', 5: 'bext'}
_OP_F34 = {1: 'binv'}
_OP_F14 = {1: 'bset'}
_ZBB_UNARY = {0: 'clz', 1: 'ctz', 2: 'cpop', 4: 'sext.b', 5: 'sext.h'}
# OP-FP (0x53) single-precision, fmt=00.  Keyed on funct7; the ones that also
# need funct3 (sign-inject, min/max, compare) or rs2 (the fcvt pairs, fclass)
# get their own sub-tables.  Written from the RISC-V encodings and asserted
# against `objdump -M no-aliases` by the same unit test as everything else --
# never copied from isa_model.py, which is the whole reason this file exists.
_FP_SGNJ = {0: 'fsgnj.s', 1: 'fsgnjn.s', 2: 'fsgnjx.s'}
_FP_MINMAX = {0: 'fmin.s', 1: 'fmax.s'}
_FP_CMP = {0: 'fle.s', 1: 'flt.s', 2: 'feq.s'}
_FP_CVT_W = {0: 'fcvt.w.s', 1: 'fcvt.wu.s'}     # FP -> int, rs2 selects
_FP_CVT_S = {0: 'fcvt.s.w', 1: 'fcvt.s.wu'}     # int -> FP, rs2 selects
_FP_F7 = {0x00: 'fadd.s', 0x04: 'fsub.s', 0x08: 'fmul.s', 0x0C: 'fdiv.s'}
# The four fused opcodes; fmt (bits 26:25) must be 00 for single precision.
_FMA_OP = {0x43: 'fmadd.s', 0x47: 'fmsub.s', 0x4B: 'fnmsub.s', 0x4F: 'fnmadd.s'}

# K5.  Zawrs: SYSTEM funct12 0x00D/0x01D with rd=rs1=x0.
_WRS_F12 = {0x00D: 'wrs.nto', 0x01D: 'wrs.sto'}
# K5.  Zihintntl: the hint is the rs2 specifier of `add x0, x0, rs2`.
_NTL_RS2 = {2: 'ntl.p1', 3: 'ntl.pall', 4: 'ntl.s1', 5: 'ntl.all'}

_AMO_F5 = {0x00: 'amoadd.w', 0x01: 'amoswap.w', 0x02: 'lr.w', 0x03: 'sc.w',
           0x04: 'amoxor.w', 0x08: 'amoor.w', 0x0C: 'amoand.w',
           0x10: 'amomin.w', 0x14: 'amomax.w', 0x18: 'amominu.w',
           0x1C: 'amomaxu.w'}


def decode(w):
    """32-bit encoding -> mnemonic string, or None if this decoder does not
    name it.  `None` is a census FAILURE inside the stream range, never a
    silent skip: an encoding the instrument cannot name is an encoding it
    cannot count."""
    op = w & 0x7F
    rd = (w >> 7) & 0x1F
    f3 = (w >> 12) & 7
    rs2 = (w >> 20) & 0x1F
    f7 = (w >> 25) & 0x7F

    if op == 0x37:
        return 'lui'
    if op == 0x17:
        return 'auipc'
    if op == 0x6F:
        return 'jal'
    if op == 0x67:
        return 'jalr' if f3 == 0 else None
    if op == 0x63:
        return _BRANCH.get(f3)
    if op == 0x03:
        return _LOAD.get(f3)
    if op == 0x23:
        return _STORE.get(f3)
    if op == 0x0F:
        # K5 Zicboz: MISC-MEM funct3=010, rd=x0, imm[11:0]=0x004, rs1 free.
        # rs1 IS free, which is the entire content of R-K2-5's correction: the
        # S5 ledger's "ends 200f" shorthand is true only for rs1 in {x0,x1}
        # because rs1 sits in bits 19:15, inside the low sixteen.  This decode
        # reads the fields and does not care.  cbo.clean/flush/inval (imm 1/2/0)
        # are deliberately NOT named: the RTL traps them (cbozill.S is the
        # standing proof), so an encoding of one inside a stream is a finding,
        # and an unnamed encoding is a census FAILURE rather than a silent skip.
        if f3 == 2:
            return 'cbo.zero' if (rd == 0 and ((w >> 20) & 0xFFF) == 0x004) \
                else None
        if f3 != 0:
            return None
        # K5: `pause` IS a FENCE encoding -- fm=0, pred=W, succ=0, rd=rs1=0,
        # i.e. the whole word 0x0100000F.  A decoder that stopped at
        # `op == 0x0F and f3 == 0` would count it as `fence` and put it in the
        # wrong class, which is R-K2-5's lesson one field deeper: the
        # discriminator is in the fields, so read the fields.
        if w == 0x0100000F:
            return 'pause'
        return 'fence'
    if op == 0x13:
        if f3 in _OPIMM:
            return _OPIMM[f3]
        if f3 == 1:
            if f7 == 0x00:
                return 'slli'
            if f7 == 0x30:
                return _ZBB_UNARY.get(rs2)
            if f7 == 0x24:
                return 'bclri'
            if f7 == 0x34:
                return 'binvi'
            if f7 == 0x14:
                return 'bseti'
            return None
        if f3 == 5:
            if f7 == 0x00:
                return 'srli'
            if f7 == 0x20:
                return 'srai'
            if f7 == 0x30:
                return 'rori'
            if f7 == 0x24:
                return 'bexti'
            if f7 == 0x14 and rs2 == 7:
                return 'orc.b'
            if f7 == 0x34 and rs2 == 0x18:
                return 'rev8'
            return None
        return None
    if op == 0x33:
        if f7 == 0x00:
            # K5 Zihintntl: `add x0, x0, rs2` with rs2 in {x2,x3,x4,x5} IS the
            # hint encoding -- the architecture says so, so this is a correct
            # decode of anyone's bytes and not a generator-specific reading.
            # objdump 2.41 has no `ntl.*` mnemonic and prints `add zero,zero,sp`;
            # the unit test therefore referees the ENCODING against objdump and
            # owns the MNEMONIC here, which is the honest split.
            if f3 == 0 and rd == 0 and ((w >> 15) & 0x1F) == 0 \
                    and rs2 in _NTL_RS2:
                return _NTL_RS2[rs2]
            return _OP_F0.get(f3)
        if f7 == 0x20:
            return _OP_F20.get(f3)
        if f7 == 0x01:
            return _OP_F01.get(f3)
        if f7 == 0x10:
            return _OP_F10.get(f3)
        if f7 == 0x05:
            return _OP_F05.get(f3)
        if f7 == 0x30:
            return _OP_F30.get(f3)
        if f7 == 0x24:
            return _OP_F24.get(f3)
        if f7 == 0x34:
            return _OP_F34.get(f3)
        if f7 == 0x14:
            return _OP_F14.get(f3)
        if f7 == 0x04 and f3 == 4 and rs2 == 0:
            return 'zext.h'
        return None
    if op == 0x2F:
        if f3 != 2:
            return None            # RV32A is .w only
        return _AMO_F5.get(f7 >> 2)
    if op == 0x53:
        if f7 & 0x03:
            return None            # fmt != 00: not single precision
        if f7 in _FP_F7:
            return _FP_F7[f7]
        if f7 == 0x2C:
            return 'fsqrt.s' if rs2 == 0 else None
        if f7 == 0x10:
            return _FP_SGNJ.get(f3)
        if f7 == 0x14:
            return _FP_MINMAX.get(f3)
        if f7 == 0x50:
            return _FP_CMP.get(f3)
        if f7 == 0x60:
            return _FP_CVT_W.get(rs2)
        if f7 == 0x68:
            return _FP_CVT_S.get(rs2)
        if f7 == 0x70:
            # rs2 must be 0; f3 1 = fclass.s. f3 0 would be fmv.x.w, which
            # Zfinx does NOT have (it traps on both sides -- k0 §1.3m), so it
            # is deliberately NOT named here.
            return 'fclass.s' if (rs2 == 0 and f3 == 1) else None
        return None
    if op == 0x73:
        # SYSTEM.  The ONLY encodings named here are the two Zawrs ones
        # (funct3=000, rd=x0, rs1=x0, funct12 = 0x00D / 0x01D).  Everything else
        # in this opcode -- every CSR access, ecall, ebreak, mret, wfi -- stays
        # UNNAMED on purpose: the generator emits no SYSTEM instruction inside
        # the census range other than these two, so an unnamed one appearing
        # there is a real finding and must surface as a census failure.
        if f3 == 0 and rd == 0 and ((w >> 15) & 0x1F) == 0:
            return _WRS_F12.get((w >> 20) & 0xFFF)
        return None
    if op in _FMA_OP:
        return _FMA_OP[op] if (f7 & 0x03) == 0 else None
    del rd
    return None


# --------------------------------------------------------------------------
# K5: the 16-bit half of the decoder.
#
# gas 2.41 cannot assemble `cm.*` and objdump 2.41 cannot disassemble it
# (measured), so this table has NO third-party referee of its own.  What it has
# instead is a known-NONZERO cross-check (method rule 4): the X3 wave's directed
# tests carry hand-verified literals -- extzcmp.S 0xB852 / 0xBA52 and
# extzcmt.S 0xA016 -- and `test_randgen.py` asserts this decoder names all three
# correctly AND that `stream.zcmp_push_pop_word`/`zcmt_word` reproduce them.
# The generator's encoder and this decoder are written from the spec
# independently, exactly as the 32-bit halves are.
#
# Scope is deliberately narrow: ONLY the C2/funct3=101 shapes the generator can
# emit.  Every other 16-bit encoding -- `c.addi`, `c.lw`, all of Zcb -- returns
# None, and `stream_words` turns that into the same hard CensusError it has
# always raised, so `.option norvc` keeps precisely the guarantee it had before
# this file learned to read 16 bits at all.
# --------------------------------------------------------------------------
def decode16(h):
    """16-bit encoding -> mnemonic, or None if this decoder does not name it."""
    if (h & 0x3) != 0x2:
        return None                       # not quadrant C2
    if (h >> 13) & 0x7 != 0x5:
        return None                       # not funct3 101
    if (h >> 12) & 1 == 0:
        if (h >> 10) & 0x3 == 0:
            # cm.jt / cm.jalt; index = bits 9:2.  The mnemonic is decided by the
            # index, exactly as `vesta.vhd`'s `zcm_jt_link <= '1' when
            # unsigned(zcm_index) >= 32` decides whether ra is written.
            idx = (h >> 2) & 0xFF
            return 'cm.jalt' if idx >= 32 else 'cm.jt'
        return None                       # moves / reserved: not emitted here
    # bit12 = 1: the push/pop family.  bit11 must be 1 and bit8 must be 0, and
    # rlist (bits 7:4) must be >= 4 -- c_dec.vhd refuses otherwise and leaves
    # `dec` all-zero, i.e. illegal-instruction.  A word that fails those tests
    # is NOT a cm.push this instrument may count.
    if (h >> 11) & 1 != 1 or (h >> 8) & 1 != 0:
        return None
    if ((h >> 4) & 0xF) < 4:
        return None
    sub = (h >> 9) & 0x3
    return {0: 'cm.push', 1: 'cm.pop'}.get(sub)   # 2/3 = popretz/popret


def zcmp_fields(h):
    """(rlist, spimm) of a cm.push/cm.pop word -- for the unit tests."""
    return ((h >> 4) & 0xF, (h >> 2) & 0x3)


def zcmt_index(h):
    """The table index of a cm.jt/cm.jalt word -- for the unit tests."""
    return (h >> 2) & 0xFF


# The class each decoded mnemonic belongs to.  Kept HERE, not imported from
# isa_model, so that a mnemonic the generator can emit but this table forgets
# shows up as `unknown-class` rather than being silently agreed with.
MNEMONIC_CLASS = {}
for _cls, _ms in (
    ('alu_reg', _OP_F0.values()),
    ('alu_reg', _OP_F20.values()),
    ('alu_imm', list(_OPIMM.values()) + ['slli', 'srli', 'srai']),
    ('lui', ['lui']), ('auipc', ['auipc']),
    ('branch', _BRANCH.values()), ('jal', ['jal']), ('jalr', ['jalr']),
    ('load', _LOAD.values()), ('store', _STORE.values()),
    ('fence', ['fence']),
    ('mul', ['mul', 'mulh', 'mulhsu', 'mulhu']),
    ('div', ['div', 'divu', 'rem', 'remu']),
    ('amo', [m for m in _AMO_F5.values() if m not in ('lr.w', 'sc.w')]),
    ('lrsc', ['lr.w', 'sc.w']),
    ('zfinx', list(_FP_F7.values()) + ['fsqrt.s', 'fclass.s']
              + list(_FP_SGNJ.values()) + list(_FP_MINMAX.values())
              + list(_FP_CMP.values()) + list(_FP_CVT_W.values())
              + list(_FP_CVT_S.values()) + list(_FMA_OP.values())),
    ('zba', _OP_F10.values()),
    ('zbb', ['andn', 'orn', 'xnor', 'min', 'minu', 'max', 'maxu', 'rol', 'ror',
             'zext.h', 'clz', 'ctz', 'cpop', 'sext.b', 'sext.h', 'orc.b',
             'rev8', 'rori']),
    ('zbs', ['bclr', 'bext', 'binv', 'bset',
             'bclri', 'bexti', 'binvi', 'bseti']),
    ('zbc', ['clmul', 'clmulh', 'clmulr']),
    # K5 queue item 4.  Written here from the decode table's own names, never
    # imported from isa_model -- a mnemonic this file can decode but forgets to
    # class shows up as `unclassed`, which is a census failure, rather than
    # being silently agreed with.
    ('zicboz', ['cbo.zero']),
    ('zawrs', list(_WRS_F12.values())),
    ('zihint', ['pause'] + list(_NTL_RS2.values())),
    ('zcmp', ['cm.push', 'cm.pop']),
    ('zcmt', ['cm.jt', 'cm.jalt']),
):
    for _m in _ms:
        MNEMONIC_CLASS[_m] = _cls
del _cls, _ms, _m
# `xnor/orn/andn` live in the funct7=0x20 OP group next to `sub`/`sra` but are
# Zbb, not base-I.  The loop above assigned them `alu_reg` from _OP_F20; fix
# that here rather than fragmenting the decode table, and note it, because a
# silent mis-class is exactly the failure this module exists to prevent.
for _m in ('xnor', 'orn', 'andn'):
    MNEMONIC_CLASS[_m] = 'zbb'
del _m


class CensusError(Exception):
    pass


def _run(cmd):
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()
    if p.returncode != 0:
        raise CensusError('%s failed (rc=%d): %s'
                          % (' '.join(cmd), p.returncode,
                             err.decode('utf-8', 'replace')[:400]))
    return out.decode('utf-8', 'replace')


def symbol_addr(elf, name):
    for line in _run([PREFIX + 'nm', elf]).splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == name:
            return int(parts[0], 16)
    raise CensusError('symbol %r not found in %s -- was this ELF built from a '
                      'randgen stream?' % (name, elf))


def _section(elf, sec):
    """(vma, size, bytes) for one section, read via objcopy/objdump."""
    hdr = _run([PREFIX + 'objdump', '-h', elf])
    vma = size = None
    pat = re.compile(r'^\s*\d+\s+' + re.escape(sec) +
                     r'\s+([0-9a-f]+)\s+([0-9a-f]+)\s+', re.I)
    for line in hdr.splitlines():
        m = pat.match(line)
        if m:
            size = int(m.group(1), 16)
            vma = int(m.group(2), 16)
            break
    if vma is None:
        raise CensusError('section %s not found in %s' % (sec, elf))
    import tempfile
    fd, tmp = tempfile.mkstemp(suffix='.bin')
    os.close(fd)
    try:
        _run([PREFIX + 'objcopy', '--dump-section', '%s=%s' % (sec, tmp), elf])
        with open(tmp, 'rb') as f:
            data = f.read()
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return vma, size, data


def stream_words(elf, section='.text.init',
                 begin='k3_stream_begin', end='k3_stream_end'):
    """The machine words between the two range symbols, as (addr, word) pairs.

    Bounds come from the ELF SYMBOL TABLE, not from a marker instruction or a
    fixed offset: the range is structurally determined and there is nothing to
    calibrate (method rule 7).
    """
    lo = symbol_addr(elf, begin)
    hi = symbol_addr(elf, end)
    if hi <= lo:
        raise CensusError('degenerate stream range: %s=0x%x %s=0x%x'
                          % (begin, lo, end, hi))
    vma, size, data = _section(elf, section)
    if lo < vma or hi > vma + size:
        raise CensusError(
            'stream range [0x%x,0x%x) is not inside %s [0x%x,0x%x)'
            % (lo, hi, section, vma, vma + size))
    blob = data[lo - vma:hi - vma]
    if len(blob) % 2:
        raise CensusError('stream range is %d bytes -- not a whole number of '
                          'RISC-V instructions (every encoding is a multiple '
                          'of 2 bytes).' % len(blob))
    # K5: the range is walked by ENCODING LENGTH, not in fixed 4-byte steps.
    # Until v1.3.0 every instruction here was 32-bit and a 16-bit word was, by
    # itself, the finding.  Zcmp/Zcmt are 16-bit by construction and gas has no
    # mnemonic for them, so the generator emits them as `.short` -- which means
    # the instrument has to be able to READ 16 bits without losing the
    # protection the old hard refusal gave.  It does not lose it: a 16-bit word
    # `decode16` cannot NAME still raises exactly the CensusError it always did,
    # so `c.addi` (or anything else `.option norvc` was supposed to prevent) is
    # still a hard stop.  What changed is that four deliberately-emitted
    # encodings are now nameable, not that unknown ones are tolerated.
    out = []
    i = 0
    while i < len(blob):
        (h,) = struct.unpack('<H', blob[i:i + 2])
        if (h & 3) == 3:
            if i + 4 > len(blob):
                raise CensusError(
                    'truncated 32-bit encoding at 0x%x -- the range ends '
                    'mid-instruction' % (lo + i))
            (w,) = struct.unpack('<I', blob[i:i + 4])
            out.append((lo + i, w))
            i += 4
        else:
            if decode16(h) is None:
                raise CensusError(
                    'word at 0x%x is a 16-bit (compressed) encoding (0x%04x) '
                    'that this instrument does not name -- `.option norvc` did '
                    'not hold, or a Zcmp/Zcmt shape outside the four the '
                    'generator emits reached the range' % (lo + i, h))
            out.append((lo + i, h))
            i += 2
    return out


def census(elf, **kw):
    """{'counts': {class: n}, 'mnemonics': {m: n}, 'total': n,
        'undecoded': [(addr, word)], 'unclassed': [(addr, mnemonic)]}"""
    counts, mnem = {}, {}
    undec, uncls = [], []
    words = stream_words(elf, **kw)
    for addr, w in words:
        # The low two bits are the RISC-V length encoding, so which decoder
        # applies is a property of the WORD and not of anything the generator
        # told us.
        m = decode(w) if (w & 3) == 3 else decode16(w)
        if m is None:
            undec.append((addr, w))
            continue
        mnem[m] = mnem.get(m, 0) + 1
        c = MNEMONIC_CLASS.get(m)
        if c is None:
            uncls.append((addr, m))
            continue
        counts[c] = counts.get(c, 0) + 1
    return {'counts': counts, 'mnemonics': mnem, 'total': len(words),
            'undecoded': undec, 'unclassed': uncls, 'elf': elf}


def check_against_manifest(cen, manifest):
    """Return an ordered list of human-readable MISMATCH lines; empty == clean.

    The census validates the manifest, not the reverse: every discrepancy is
    reported in the census's terms ("image has N, manifest claims M").
    """
    bad = []
    if cen['undecoded']:
        for addr, w in cen['undecoded'][:8]:
            bad.append('UNDECODED 0x%08x at 0x%x -- the instrument cannot name '
                       'this encoding, so it cannot count it' % (w, addr))
        if len(cen['undecoded']) > 8:
            bad.append('... and %d more undecoded'
                       % (len(cen['undecoded']) - 8))
    for addr, m in cen['unclassed'][:8]:
        bad.append('UNCLASSED %s at 0x%x -- decoded but in no class' % (m, addr))
    claimed = dict(manifest['class_counts'])
    got = dict(cen['counts'])
    for cls in sorted(set(list(claimed.keys()) + list(got.keys()))):
        c, g = claimed.get(cls, 0), got.get(cls, 0)
        if c != g:
            bad.append('CLASS %-10s image has %d, manifest claims %d'
                       % (cls, g, c))
    tot_claim = sum(claimed.values())
    if cen['total'] != tot_claim:
        bad.append('TOTAL image has %d instructions in the range, manifest '
                   'claims %d' % (cen['total'], tot_claim))
    return bad


# --------------------------------------------------------------------------
# THE WRONG WAY, kept on purpose.
# --------------------------------------------------------------------------
def naive_suffix_count(elf, suffix_hex, **kw):
    """Count words whose LOW SIXTEEN BITS equal `suffix_hex`.

    This is the S5 ledger's "ends `200f`" shorthand generalised, and it is
    WRONG for any instruction whose rs1/funct3/rd vary -- R-K2-5 placed a
    correction marker at the ledger site for exactly this.  It lives here, in
    the tree, so that `test_randgen.py` can DEMONSTRATE the wrong answer on a
    real stream instead of citing the lesson.  Nothing in the census path calls
    it.
    """
    want = int(suffix_hex, 16) & 0xFFFF
    return sum(1 for _a, w in stream_words(elf, **kw) if (w & 0xFFFF) == want)


def main(argv):
    import argparse
    import json
    ap = argparse.ArgumentParser(
        description='Field-decoded census of a K3 stream inside a built ELF.')
    ap.add_argument('elf')
    ap.add_argument('--manifest', help='manifest JSON to validate')
    ap.add_argument('--json', action='store_true')
    a = ap.parse_args(argv)
    cen = census(a.elf)
    if a.json:
        print(json.dumps({'counts': cen['counts'], 'mnemonics': cen['mnemonics'],
                          'total': cen['total']}, indent=2, sort_keys=True))
    else:
        print('census of %s' % a.elf)
        print('  range instructions: %d' % cen['total'])
        for c in sorted(cen['counts']):
            print('  %-10s %5d' % (c, cen['counts'][c]))
        if cen['undecoded']:
            print('  UNDECODED: %d' % len(cen['undecoded']))
    if a.manifest:
        with open(a.manifest) as f:
            man = json.load(f)
        bad = check_against_manifest(cen, man)
        if bad:
            print('CENSUS vs MANIFEST: %d MISMATCH(es)' % len(bad))
            for line in bad:
                print('  ' + line)
            return 1
        print('CENSUS vs MANIFEST: OK (%d instructions, %d classes)'
              % (cen['total'], len(cen['counts'])))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
