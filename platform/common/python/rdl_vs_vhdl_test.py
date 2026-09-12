#!/usr/bin/env python3
"""rdl_vs_vhdl_test.py -- an .rdl description and the VHDL that implements it
describe the same registers.

THE VHDL IS THE AUTHORITY, so this gate reads the RTL rather than any generated
artifact: the decode constants, the implemented-bit tables and the reset tables
are parsed out of the peripheral's own source and compared against the compiled
.rdl. What is compared, per register:

    word offset      the W_* / RegSlot* / WORD_BASE the decode actually uses
    reset value      the RSTVAL table, or the reset branch of the write process
    storage mask     the mask of bits that hold a software-written flop

The storage mask is the one that carries real information, because it is where a
register map and its decode usually part company: a field added to the .rdl but
not to IMPL is a field software can write and hardware never sees.

    rdl_vs_vhdl_test.py --periph {uart,gpio,...} [--rdl-config <rdl.json>]
                        [--vhdl <file>] [--memorymap-vhd <file>]
"""

import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import rdl_model
import rdl_vhdl

REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))


def _arg(name, default=None):
    flag = '--' + name
    for i, a in enumerate(sys.argv):
        if a == flag and i + 1 < len(sys.argv):
            return sys.argv[i + 1]
        if a.startswith(flag + '='):
            return a.split('=', 1)[1]
    return default


PERIPH = _arg('periph')
VHDL = _arg('vhdl')
MEMORYMAP_VHD = _arg('memorymap-vhd')
sys.argv = sys.argv[:1]


def _read(path):
    with open(path) as f:
        return f.read()


def _defaultVhdl(name):
    return os.path.join(REPO, 'hdl', 'common', 'periph', name)


REGS_VHDL_DIR = os.path.join(REPO, 'hdl', 'common', 'regs', 'vhdl')


def _decodeText(vhdlPath):
    """The entity's source plus the text of every generated register package it
       `use`s.

       Report R8a moved each peripheral's word-offset constants out of its
       architecture (or out of work.MemoryMap) and into a tracked
       hdl/common/regs/vhdl/<x>_regs_pkg.vhd generated from the same .rdl. THE
       VHDL STAYS THE AUTHORITY AND THIS GATE STILL READS IT: what changes is
       that "the VHDL" is now the entity plus the package it compiles against,
       so the readers below follow the context clause instead of failing on
       constants that are no longer declared locally.

       What that costs, for a migrated block: the constants read here came from
       the .rdl, so this gate
       stops being .rdl-against-an-independent-copy for it. The independent copy
       is rdl_pkg_vs_legacy_test, which holds the package against the constants
       frozen before the migration. Both gates are needed."""
    src = _read(vhdlPath)
    parts = [src]
    for m in re.finditer(r'use\s+work\.(\w+_regs_pkg)\.all\s*;', src):
        path = os.path.join(REGS_VHDL_DIR, m.group(1) + '.vhd')
        if not os.path.isfile(path):
            raise Exception('rdl_vs_vhdl: %s uses work.%s, which is not in the tree; '
                            'regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`'
                            % (os.path.basename(vhdlPath), m.group(1)))
        parts.append(_read(path))
    return '\n'.join(parts)


def _slotText(vhdlPath, memoryMapPath):
    """Everything a slot constant could be declared in, for this entity.

       The memory-map package is appended only where the entity still `use`s it:
       a migrated peripheral has swapped that clause for its own package, and
       reading the memory map anyway would let this gate pass on a constant the
       entity can no longer see."""
    text = _decodeText(vhdlPath)
    if re.search(r'use\s+work\.MemoryMap\.all\s*;', text, re.I):
        text += '\n' + _read(memoryMapPath)
    return text


# ---------------------------------------------------------------------------
# The three decode readers. Each returns {registerName: {'word', 'reset', 'impl'}}
# with `impl` None where the VHDL states no implemented-bit table.
# ---------------------------------------------------------------------------

def _aggregatePairs(src, constName, arrayType):
    """`constant NAME : TYPE := (KEY => x"...", ..., others => ...);` as a dict."""
    m = re.search(r'constant\s+' + constName + r'\s*:\s*' + arrayType + r'\s*:=\s*\((.*?)\);',
                  src, re.S)
    if m is None:
        raise Exception('rdl_vs_vhdl: no `constant %s : %s` aggregate found' % (constName, arrayType))
    body = m.group(1)
    out = {}
    for key, val in re.findall(r'(W_\w+)\s*=>\s*x"([0-9A-Fa-f]+)"', body):
        out[key] = int(val, 16)
    out['__others__'] = 0 if re.search(r"others\s*=>\s*\(\s*others\s*=>\s*'0'\s*\)", body) else None
    return out


def _decodeSource(path, package):
    """The text the decode's constants live in.

    SystemRDL level 2 (2026-09-10, report R6): a migrated entity no longer
    declares its word offsets, IMPL or RSTVAL itself; it `use`s a generated
    package that exports them under those names. The entity is still checked --
    it must carry the context clause, or these constants are not the ones it
    compiles against -- but the values are read from the package.

    Note what this costs: for such a peripheral the comparison below is no
    longer .rdl-against-an-independent-copy, because the package IS the .rdl.
    The independent copy moved to rdl_pkg_vs_legacy_test.py, which holds the
    package against the hand-written constants frozen at the migration. Both
    gates are needed; neither replaces the other.
    """
    src = _read(path)
    if ('use work.%s.all;' % package) not in src:
        raise Exception('rdl_vs_vhdl: %s does not `use work.%s.all`, so the generated package '
                        'is not what its decode compiles against.'
                        % (os.path.basename(path), package))
    pkgPath = os.path.join(REGS_VHDL_DIR, package + '.vhd')
    if not os.path.isfile(pkgPath):
        raise Exception('rdl_vs_vhdl: %s is missing; regenerate with '
                        '`bazel run //platform/common/python:rdl_vhdl_pkgs`' % pkgPath)
    return _read(pkgPath)


# ---------------------------------------------------------------------------
# THE periph_regs READER (report R12a, 2026-09-11)
#
# A block whose bus side is an instance of hdl/common/periph_regs.vhd no longer
# has a case decode, a reset branch or a write-1-to-clear arm to read: its decode
# IS the table its register package exports, and the entity's only statement
# about it is the generic map. So this reader checks the two things that are
# still statements of the RTL --
#
#   * the entity instantiates work.periph_regs, and
#   * its generic map takes the PACKAGE's tables under the package's own names,
#     not a local copy, so a hand-edited table in the entity is a mismatch here
#
# -- and then reads word, reset and IMPL out of that package's tables.
#
# What this costs is the same thing report R6 already paid at level 3: for such a
# block the comparison below is no longer .rdl-against-an-independent-copy. The
# independent copy is rdl_pkg_vs_legacy_test.py, which holds every value in the
# package against the constant that was hand-written before the migration.
# ---------------------------------------------------------------------------

_REGFILE_TABLES = ('RSTVAL', 'IMPL', 'W1C', 'WOSET', 'WOT', 'PULSE', 'RCLR', 'HWOWN')


def _regfileTable(pkgSrc, name):
    """[(registerName, value)] of one `constant <name> : reg_arr_t := (...)` table,
       in slot order. Each row carries its register's name as a comment, which is
       what ties a word index to a register without a second table."""
    m = re.search(r'constant\s+' + name + r'\s*:\s*reg_arr_t\s*:=\s*\(\n(.*?)\n\s*\);',
                  pkgSrc, re.S)
    if m is None:
        raise Exception('rdl_vs_vhdl: the register package has no `constant %s : reg_arr_t` '
                        'table; regenerate with `bazel run '
                        '//platform/common/python:rdl_vhdl_pkgs`' % name)
    rows = re.findall(r'x"([0-9A-Fa-f]+)"\s*[,);]*\s*--\s*(\w+)', m.group(1))
    if not rows:
        raise Exception('rdl_vs_vhdl: the %s table carries no `x"..." -- <register>` rows' % name)
    return [(reg, int(val, 16)) for val, reg in rows]


# The gap rows of a sparse periph_regs table. A VHDL identifier cannot start
# with an underscore, so this can never be a register name.
_RESERVED_ROW = re.compile(r'^_reserved_\d+$')


# A configuration-dependent block passes its package's table FUNCTIONS, called on
# the block's own generics, where a fixed block passes the table constants. Same
# statement about the entity, one call away: the decode it runs on is the
# package's and not a hand-written copy.
def _FN_TABLE_REQUIRE(call):
    return [r'%s\s*=>\s*%s\(%s\)' % (t, t, call) for t in _REGFILE_TABLES]


def makeRegfileReader(package):
    def read(vhdlPath, memoryMapPath):
        src = _read(vhdlPath)
        if re.search(r'entity\s+work\.periph_regs', src) is None:
            raise Exception('rdl_vs_vhdl: %s is registered as a periph_regs block but does not '
                            'instantiate work.periph_regs.' % os.path.basename(vhdlPath))
        for t in _REGFILE_TABLES:
            if re.search(r'\b' + t + r'\s*=>\s*' + t + r'\b', src) is None:
                raise Exception('rdl_vs_vhdl: %s does not pass `%s => %s` to periph_regs, so the '
                                'table it decodes with is not %s\'s.'
                                % (os.path.basename(vhdlPath), t, t, package))
        pkgSrc = _decodeSource(vhdlPath, package)
        rst = _regfileTable(pkgSrc, 'RSTVAL')
        impl = dict(_regfileTable(pkgSrc, 'IMPL'))
        out = {}
        for word, (name, reset) in enumerate(rst):
            # A SPARSE table (SYSTEM, EVFAB) carries an all-zero `_reserved_<word>`
            # row for every word its register set skips, so that the row index is
            # still the word offset. Those rows are not registers; the row index
            # is what they exist to keep honest.
            if _RESERVED_ROW.match(name):
                continue
            out[name] = {'word': word, 'reset': reset, 'impl': impl[name]}
        return out

    return read


# ---------------------------------------------------------------------------
# THE GENERIC READER (added by the 20-block sweep, R2 2026-09-10)
#
# The reader above is bespoke because UART's decode is split across two files.
# The other twenty blocks share ONE house style, so they share one reader:
#
#   slots   either `constant SLOT_<KEY> : natural := N;` inside the block, or
#           `constant RegSlot<PREFIX><KEY> : natural := N;` in the memory-map
#           package the entity `use`s, or `constant MmrAddr<KEY> : natural := N;`
#           (NPU), or a per-block literal table for the blocks that decode a
#           bare integer word index (pwr_ctrl, clint, mutex_bank, irq_router,
#           EVFAB's action half).
#   reset   the reset branch of the register-write process: every
#           `<signal> <= <value>;` before the `elsif rising_edge`, with <value>
#           read as (others => '0'), x"...", "0101", (N => '1', others => '0')
#           or a NAMED CONSTANT resolved out of hdl/common/constants.vhd.
#           A register whose storage this block does not name -- a status word
#           assembled from per-flag flops, a staged value that lives in another
#           clock domain -- is left as None and its reset is not compared.
#   impl    NOT derived. No block in the public tree states an implemented-bit
#           table; the storage mask would have to be inferred from the case
#           arms, and an inference that is wrong in the safe direction is worse
#           than no check. It stays None here, which the gate skips.
#
# WHAT THIS DOES NOT COVER, and the fallback for it: a block whose reset values
# are not written as literals in one reset branch (PWM, OneWire, I2CTarget and
# EVFAB keep one flop per FIELD, so a register's reset is the concatenation of a
# dozen assignments). Those are declared reset-unknown here. The designed
# fallback for them is a GHDL reset readback -- elaborate the entity, release
# reset, read every decoded word through the bus port and compare the words
# against the .rdl -- which needs `bazel run //tools:ghdl` and one small bench
# per block; every one of those four resets every field to '0', so the static
# reader's silence costs nothing today and the fallback is only worth building
# when one of them acquires a non-zero reset.
# ---------------------------------------------------------------------------

CONSTANTS_VHD = os.path.join(REPO, 'hdl', 'common', 'constants.vhd')


def _namedConstants():
    """`constant NAME : std_logic_vector(...) := <literal>;` from constants.vhd."""
    src = _read(CONSTANTS_VHD)
    out = {}
    for m in re.finditer(r'constant\s+(\w+)\s*:\s*std_logic_vector\([^)]*\)\s*:=\s*([^;]+);', src):
        v = _literal(m.group(2).strip(), {})
        if v is not None:
            out[m.group(1)] = v
    return out


def _literal(text, consts):
    """A VHDL reset literal as an integer, or None when it is not one."""
    text = text.strip()
    m = re.match(r'^[xX]"([0-9A-Fa-f_]+)"$', text)
    if m:
        return int(m.group(1).replace('_', ''), 16)
    m = re.match(r'^"([01_]+)"$', text)
    if m:
        return int(m.group(1).replace('_', ''), 2)
    if re.match(r"^\(\s*others\s*=>\s*'0'\s*\)$", text):
        return 0
    if re.match(r"^\(\s*others\s*=>\s*\(\s*others\s*=>\s*'0'\s*\)\s*\)$", text):
        return 0
    if re.match(r"^\(\s*others\s*=>\s*'1'\s*\)$", text) or \
       re.match(r"^\(\s*others\s*=>\s*\(\s*others\s*=>\s*'1'\s*\)\s*\)$", text):
        return -1            # all ones, width-resolved by the caller
    m = re.match(r"^\(\s*((?:\d+\s*=>\s*'1'\s*,\s*)+)others\s*=>\s*'0'\s*\)$", text)
    if m:
        v = 0
        for b in re.findall(r"(\d+)\s*=>\s*'1'", m.group(1)):
            v |= 1 << int(b)
        return v
    if re.match(r'^\w+$', text):
        return consts.get(text)
    return None


def _resetAssignments(src, processName, consts):
    """{signal: value} from the reset branch of one named process."""
    m = re.search(processName + r'\s*:\s*process\b.*?\bbegin(.*?)elsif\s+rising_edge', src, re.S)
    if m is None:
        m = re.search(r'process\b[^;]*?\bbegin(.*?)elsif\s+rising_edge', src, re.S)
        if m is None:
            return {}
    body = m.group(1)
    out = {}
    for a in re.finditer(r'(\w+)\s*<=\s*([^;]+);', body):
        v = _literal(a.group(2), consts)
        if v is not None:
            out[a.group(1)] = v
    return out


def _slotsLocal(src):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(r'constant\s+SLOT_(\w+)\s*:\s*natural\s*:=\s*(\d+);', src))


def _slotsMemoryMap(mmSrc, prefix):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(r'constant\s+RegSlot' + prefix + r'(\w+)\s*:\s*natural\s*:=\s*(\d+);', mmSrc))


def _slotsMmr(mmSrc):
    return dict((m.group(1), int(m.group(2)))
                for m in re.finditer(r'constant\s+MmrAddr(\w+)\s*:\s*natural\s*:=\s*(\d+);', mmSrc))


def makeGenericReader(spec):
    """One reader function for a house-style block; see the header above."""

    def read(vhdlPath, memoryMapPath):
        src = _read(vhdlPath)
        # Reset values are read from the ENTITY only: they live in the reset
        # branch of a process, which no package can hold. Slot constants are read
        # from wherever the entity can see them -- itself, its generated register
        # package, or the memory map while it still uses one.
        slotSrc = _slotText(vhdlPath, memoryMapPath)
        consts = _namedConstants()
        if spec['slots'] == 'local':
            raw = _slotsLocal(slotSrc)
        elif spec['slots'] == 'mmr':
            raw = _slotsMmr(slotSrc)
        elif spec['slots'].startswith('memmap:'):
            raw = _slotsMemoryMap(slotSrc, spec['slots'].split(':', 1)[1])
        else:
            raw = {}
        raw.update(spec.get('extraSlots', {}))
        if not raw and not spec.get('literalSlots'):
            raise Exception('rdl_vs_vhdl: no slot constants found in ' + vhdlPath)
        words = dict(spec.get('literalSlots', {}))
        for key, slot in raw.items():
            name = spec['name'](key)
            if name is not None:
                words[name] = slot
        rst = _resetAssignments(src, spec.get('process', 'reg_write'), consts)
        out = {}
        for name, slot in words.items():
            sig = spec.get('storage', {}).get(name)
            reset = None
            if sig is not None:
                reset = rst.get(sig) if isinstance(sig, str) else sig
                if reset == -1:
                    reset = 0xFFFFFFFF
            out[name] = {'word': slot, 'reset': reset, 'impl': None}
        return out

    return read

# ---------------------------------------------------------------------------
# The twenty house-style blocks. `storage` maps a register to the reset-branch
# SIGNAL that holds it, or to a literal when the reset lives outside the
# register-write process (DMA's CRC accumulator is owned by the engine process,
# EVFAB's CAP is a constant). A register absent from `storage` has no reset
# check -- it holds no software-written flop, its reset is a GENERIC, or its
# storage is one flop per field. `require` is the list of patterns that must
# still be in the file for the literal slot table and the literal resets to mean
# anything: it is what makes a hand-written table a reading of the RTL rather
# than a copy of it.
# ---------------------------------------------------------------------------

def _names(mapping):
    return lambda k: mapping.get(k)


def _prefixed(prefix, keys):
    return lambda k: (prefix + k) if k in keys else None


_GPIO_KEYS = ['IN', 'OUT', 'OUTS', 'OUTC', 'OUTT', 'DIR', 'IF', 'IES', 'IE', 'SEL', 'REN', 'AFS', 'TASK']
_SPI_KEYS = ['CR', 'SR', 'TX', 'RX', 'FOS']
_TIM_KEYS = ['CR', 'SR', 'VAL', 'CMP0', 'CMP1', 'CMP2', 'CAP0', 'CAP1']
_I2C_KEYS = ['CR', 'FCR', 'SR', 'MTX', 'MRX', 'STX', 'SRX', 'AR', 'AMR']
_SYS_NAMES = {'SYS_CLK_CR': 'SYSCLKCR', 'SYS_CLK_DIV_CR': 'CLKDIVCR',
              'SYS_BLOCK_PWR': 'BLOCKPWR', 'SYS_CRC_DATA': 'CRCDATA',
              'SYS_CRC_STATE': 'CRCSTATE', 'SYS_WDT_PASS': 'WDTPASS',
              'SYS_WDT_CR': 'WDTCR', 'SYS_WDT_SR': 'WDTSR', 'SYS_WDT_VAL': 'WDTVAL',
              'DCO0_BIAS': 'DCO0BIAS', 'DCO1_BIAS': 'DCO1BIAS'}
_NPU_NAMES = dict((n, n) for n in ('NPUCR', 'NPUIVSAR', 'NPUWVSAR', 'NPUOVSAR', 'NPUSR',
                                   'NPUCFG1', 'NPUCFG2'))

_CLINT_SLOTS = dict([('MSIP%d' % h, h) for h in range(5)] +
                    [('MTIMEL', 8), ('MTIMEH', 9)] +
                    [('MTIMECMP%d%s' % (h, half), 12 + 2 * h + i)
                     for h in range(5) for i, half in enumerate('LH')])
_CLINT_RESET = dict([('MSIP%d' % h, 0) for h in range(5)] +
                    [('MTIMEL', 0), ('MTIMEH', 0)] +
                    [('MTIMECMP%d%s' % (h, half), 0xFFFFFFFF) for h in range(5) for half in 'LH'])

_MUTEX_SLOTS = dict(('MUTEX%d' % i, i) for i in range(16))
_MUTEX_RESET = dict(('MUTEX%d' % i, 0) for i in range(16))

_IRQR_SLOTS = {}
_IRQR_RESET = {}
for _h in range(5):
    for _i, _w in enumerate(('L', 'M', 'U', 'X')):
        _IRQR_SLOTS['H%dEN%s' % (_h, _w)] = 4 * _h + _i
        _IRQR_RESET['H%dEN%s' % (_h, _w)] = 0
_IRQR_SLOTS['CLAIM'] = 512
for _i, _w in enumerate(('L', 'M', 'U', 'X')):
    _IRQR_SLOTS['PEND' + _w] = 516 + _i
    _IRQR_SLOTS['INSVC' + _w] = 520 + _i
    _IRQR_RESET['PEND' + _w] = 0
    _IRQR_RESET['INSVC' + _w] = 0

_DMA_SLOTS = {'DMAxCR': 0, 'DMAxSR': 1, 'DMAxCRC': 18, 'DMAxDESC': 19}
for _c in range(4):
    for _i, _f in enumerate(('SRC', 'DST', 'LEN', 'CFG')):
        _DMA_SLOTS['DMAxC%d%s' % (_c, _f)] = 2 + 4 * _c + _i

_EVF_SLOTS = dict(('EVFCH%dCFG' % n, 16 + n) for n in range(1, 16))

_PWR_SLOTS = {'PWRCR': 0, 'PWRSR': 1, 'PWRWAKE': 5, 'PWRSTS': 6, 'TASKWKM': 7}
_PWR_RESET = {'PWRCR': 0, 'PWRWAKE': 0, 'TASKWKM': 0}

GENERIC_BLOCKS = {
    # GPIO is on periph_regs (report R12e). It was parked until NUM_AFS became a
    # generic and the entity could drop `use work.MemoryMap.all`; its slots and
    # its tables now both come from gpio_regs_pkg. The three PxOUT ALIAS words
    # are the point: PxOUTS -> hw_set, PxOUTC -> hw_clr, PxOUTT -> hw_we with a
    # complemented hw_wdata, all onto PxOUT's one storage word, alongside the
    # event-fabric tasks on the same two masks.
    'gpio': dict(vhdl='GPIO.vhd', regfile='gpio_regs_pkg',
                 require=[r'u_regs\s*:\s*entity work\.periph_regs',
                          r'STROBE_HOLD => false',
                          r'RSTVAL_OR   => RSTVAL_OR_GPIO',
                          r'r\(RegSlotPxOUT\) := RstValPxOUT and IMPL\(RegSlotPxOUT\);',
                          r'hw_set_s   <= \(RegSlotPxOUT => woset_s\(RegSlotPxOUTS\) or task_set,',
                          r'hw_clr_s   <= \(RegSlotPxOUT => w1c_s\(RegSlotPxOUTC\) or task_clr,',
                          r'hw_we_s    <= \(RegSlotPxOUT => wot_s\(RegSlotPxOUTT\),',
                          r'clr_if <= w1c_s\(RegSlotPxIF\)\(num_pins - 1 downto 0\);',
                          r'NUM_AFS\s+:\s+natural := 8;']),
    # SPI is a periph_regs block (report R12d): no case decode, no reset branch,
    # no write-1 arm to read. RDTHRU is a function of ENABLE_EXTENDED_MEM, since
    # SPIxFOS exists on SPI0 only and must read 0 on SPI1. The SPIxTX launch
    # takes the module's combinational wr_hit, which carries the old decode's
    # `wen /= "1111"` qualifier itself (report R12f).
    'spi': dict(vhdl='SPI.vhd', regfile='spi_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'STROBE_HOLD => true',
                         r'RDTHRU      => SPI_RDTHRU',
                         r'r\(RegSlotSPIxFOS\) := \x271\x27;',
                         r'clr_spi_teif <= w1c_s\(RegSlotSPIxSR\)\(SPITEIF_LSB\);',
                         r'or rd_str\(RegSlotSPIxRX\) or wr_str\(RegSlotSPIxRX\);',
                         r"if wrh_s\(RegSlotSPIxTX\) = '1'"]),
    # TIMER is a periph_regs pilot (report R12a): no case decode, no reset
    # branch, no write-1 arm to read. WIDEWR marks TIMxVAL, word 2 of 8, as the
    # word any enabled lane writes whole, which is what `if wen /= "1111" then`
    # used to say.
    'timer': dict(vhdl='TIMER.vhd', regfile='timer_regs_pkg',
                  require=[r'u_regs\s*:\s*entity work\.periph_regs',
                           r'STROBE_HOLD => true',
                           r'WIDEWR      => "00100000"',
                           r'RDTHRU      => "00100000"',
                           r'latch_timer_value <= wr_str\(RegSlotTIMxVAL\);',
                           r'clear_compare0_flag <= w1c_s\(RegSlotTIMxSR\)\(CMP0IF_LSB\);']),
    # SYSTEM is on periph_regs (report R12e), and is the first block whose table
    # is SPARSE: eleven registers over eighteen words, the seven retired SYS_IRQ
    # slots emitted as all-zero _reserved_ rows so a row index is still a word
    # offset. Its two per-word write qualifiers are the module's new ones:
    # FULLWR on WDT_PASS, wr_inhibit on WDT_CR.
    'system': dict(vhdl='SYSTEM.vhd', regfile='system_regs_pkg',
                   require=[r'u_regs\s*:\s*entity work\.periph_regs',
                            r'STROBE_HOLD => true',
                            r'FULLWR      => "000000000000100000"',
                            r'RDTHRU      => "000010000000100000"',
                            r"wr_inh <= \(RegSlotSYS_WDT_CR => not unlocked, others => '0'\);",
                            r'and write_data = WDT_UNLCK_PASSWD else',
                            r'and write_data = WDT_CLR_PASSWD   else',
                            r'clr_wdt_if <= w1c_s\(RegSlotSYS_WDT_SR\)\(SYSWDTIF_LSB\);']),
    # NPU is a periph_regs block (report R12d): no MMR_WRITE case, no reset branch,
    # and no read splice -- NPUTHINK is NPUCR bit 16 of the register file's own
    # storage, set by the fabric task through hw_set and cleared by NpuDone through
    # hw_clr. REGISTERED_READ is false because MabMmrQ is combinational by contract
    # and MCU.vhd's bridge is the flop.
    'npu': dict(vhdl='NPU.vhd', regfile='npu_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'REGISTERED_READ\t=> false',
                         r'STROBE_HOLD\t\t=> false',
                         r'NPUTHINK\s*<=\s*regs_q\(MmrAddrNPUCR\)\(NPUTHINK_LSB\);',
                         r'NPUTHINK_LSB => task_think',
                         r'NPUTHINK_LSB => NpuDone',
                         r'acc_s\(MmrAddrNPUSR\)']),
    # QSPI is a periph_regs block (report R12b). Its decode IS qspi_regs_pkg's
    # table; what is left to read in the entity is the instance, the strobe
    # retirement its clk_baud consumers need, the three SR clears and the launch
    # guard that still takes the combinational acc_hit plus its own WEn(0).
    'qspi': dict(vhdl='QSPI.vhd', regfile='qspi_regs_pkg',
                 require=[r'u_regs\s*:\s*entity work\.periph_regs',
                          r'STROBE_HOLD => true',
                          r'clr_tcif\s+<= w1c_s\(SLOT_SR\)\(QSPITCIF_LSB\);',
                          r"acc_s\(SLOT_CMD\) = '1' and WEn\(0\) = '0'",
                          r'constant SLOT_SR\s*:\s*natural\s*:=\s*5;']),
    # I2C is on periph_regs (report R12e). Its read stays COMBINATIONAL and
    # MCU.vhd's i2c_rdata_bridge stays the flop, which is what REGISTERED_READ =>
    # false buys; I2CxAR's reset is the default_SAD generic, which reaches the
    # storage through RSTVAL_OR because the .rdl cannot describe a generic.
    'i2c': dict(vhdl='I2C.vhd', regfile='i2c_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'REGISTERED_READ => false',
                         r'STROBE_HOLD     => true',
                         r'RSTVAL_OR       => RSTVAL_OR_I2C',
                         r'RegSlotI2CxAR => pad\(default_SAD\)',
                         r"wr_inh <= \(RegSlotI2CxMTX => not I2CMEN, others => '0'\);",
                         r'ClearI2CSTR\s*<=\s*w1c_s\(RegSlotI2CxSR\)\(I2CSTR_LSB\);']),
    # CLINT is a periph_regs block (report P4). Its register SET is a function of
    # NHARTS and its layout of MTIME_W / CMP_W, so clint_regs_pkg carries the eight
    # tables as FUNCTIONS of all three; rdl_vhdl._checkRegfileFn grades them
    # against this .rdl at every hart count below. mtimecmp's all-ones reset is now
    # the RSTVAL row and not a reset branch, which is why the pattern that read the
    # branch is gone. What stayed in the entity is the mtime tick and the compares.
    'clint': dict(vhdl=os.path.join('..', 'clint.vhd'), slots='none', name=lambda k: None,
                  literalSlots=_CLINT_SLOTS, storage=_CLINT_RESET,
                  require=[r'u_regs\s*:\s*entity work\.periph_regs',
                           r'constant NW\s*:\s*natural\s*:=\s*NWORDS\(NHARTS, MTIME_W, CMP_W\);',
                           r'NWORDS      => NW',
                           r'constant MTIME_W\s*:\s*natural\s*:=\s*\(\(4\*NHARTS \+ 15\) / 16\) \* 4;',
                           r'constant CMP_W\s*:\s*natural\s*:=\s*MTIME_W \+ 4;',
                           r'assert CMP_W \+ 2\*NHARTS <= 64',
                           r'mtime      <= regs_q\(MTIME_W \+ 1\) & regs_q\(MTIME_W\);',
                           r'mtime_wr   <= wr_hit_s\(MTIME_W\) or wr_hit_s\(MTIME_W \+ 1\);',
                           r'regs_q\(CMP_W \+ 2\*h \+ 1\) & regs_q\(CMP_W \+ 2\*h\)',
                           r'msip\(h\) <= regs_q\(MSIP0_WORD \+ h\)\(CLINTMSIPH0_LSB\);']
                          + _FN_TABLE_REQUIRE('NHARTS, MTIME_W, CMP_W')),
    # MUTEX is a periph_regs block (report P4). Its register SET is a function of
    # NMUTEX and its owner field of MW, so mutex_bank_regs_pkg carries the eight
    # tables as FUNCTIONS of both; rdl_vhdl._checkRegfileFn grades them against
    # this .rdl at every shipped (NMUTEX, MW) pair. The claim rule is what stayed
    # in the entity: a read of a free word writes the granted master's marker.
    'mutex_bank': dict(vhdl=os.path.join('..', 'mutex_bank.vhd'), slots='none', name=lambda k: None,
                       literalSlots=_MUTEX_SLOTS, storage=_MUTEX_RESET,
                       require=[r'u_regs\s*:\s*entity work\.periph_regs',
                                r'constant NW\s*:\s*natural\s*:=\s*NWORDS\(NMUTEX, MW\);',
                                r'NWORDS      => NW',
                                r'WIDEWR      => ALL_WIDE',
                                r'assert 2\*\*AW = NMUTEX',
                                r'constant OWNER_MASK\s*:\s*word\s*:=\s*IMPL\(NMUTEX, MW\)\(0\);',
                                r'inhib_s <= \(others => \'0\'\) when wdata = x"00000000"',
                                r"rd_hit_s\(idx\) = '1' and regs_q\(idx\)\(MW downto 0\) = OWNER_FREE"]
                               + _FN_TABLE_REQUIRE('NMUTEX, MW')),
    'irq_router': dict(vhdl=os.path.join('..', 'irq_router.vhd'), slots='none', name=lambda k: None,
                       literalSlots=_IRQR_SLOTS, storage=_IRQR_RESET,
                       require=[r'constant W_CLAIM\s*:\s*natural\s*:=\s*512;',
                                r'constant W_PENDL\s*:\s*natural\s*:=\s*516;',
                                r'constant W_INSVCL\s*:\s*natural\s*:=\s*520;',
                                r'constant NUM_EN_WORDS\s*:\s*natural\s*:=\s*\(NUM_SRCS \+ 31\) / 32;']),
    # PWRCTRL is a periph_regs block (report P4). Its register SET is a function of
    # NHARTS, so pwr_ctrl_regs_pkg carries the eight tables as FUNCTIONS of it and
    # the entity calls them in its generic map; rdl_vhdl._checkRegfileFn grades
    # those functions against this .rdl at every shipped hart count, which is the
    # leg of the argument the require list below cannot carry.
    'pwr_ctrl': dict(vhdl=os.path.join('..', 'pwr_ctrl.vhd'), slots='none', name=lambda k: None,
                     literalSlots=_PWR_SLOTS, storage=_PWR_RESET,
                     require=[r'u_regs\s*:\s*entity work\.periph_regs',
                              r'constant NW\s*:\s*natural\s*:=\s*NWORDS\(NHARTS\);',
                              r'NWORDS      => NW',
                              r'WIDEWR      => "10000101"',
                              r'constant W_PWRWAKE\s*:\s*(?:integer|natural)\s*:=\s*5;',
                              r'constant W_PWRSTS\s*:\s*(?:integer|natural)\s*:=\s*6;',
                              r'constant W_TASKWKM\s*:\s*(?:integer|natural)\s*:=\s*7;',
                              r'gate_req <= regs_q\(PWRCR_WORD\)\(PD_HI downto 1\);',
                              r'task_wkm <= regs_q\(W_TASKWKM\)\(PD_HI downto 1\);',
                              r'hw_clr_s\(PWRCR_WORD\)\(PD_HI downto 1\) <= task_wkm;']
                             + _FN_TABLE_REQUIRE('NHARTS')),
    # I3C is a periph_regs block (report R12b). The DAT window is an indexed
    # four-entry side table, not register storage, so its three words are RDTHRU
    # and their writes stay in the clk domain behind acc_hit. I3CxCR's reset
    # (SDAPP = 1) is now the package's RSTVAL row, which is what the reader reads.
    'i3c': dict(vhdl='I3C.vhd', regfile='i3c_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'STROBE_HOLD => true',
                         r'RDTHRU      => "000001110"',
                         r'clr_ibip\s+<= w1c_s\(SLOT_SR\)\(I3CIBIP_LSB\);',
                         r"acc_s\(SLOT_TX\) = '1' and WEn\(0\) = '0'",
                         r"acc_s\(SLOT_DAT\) = '1'"]),
    # NFC is a periph_regs block (report R12d). RDTHRU marks NFCxDATA, word 7 of
    # 10: the description gives it eight bits of storage, but the byte a read
    # returns comes from one of the two 64-byte windows, which stay in the
    # peripheral. The index auto-increment is a hardware write to NFCxIDX.NFCIDX,
    # which is why nfc.rdl gives that field hw = rw.
    'nfc': dict(vhdl='NFC.vhd', regfile='nfc_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'STROBE_HOLD => true',
                         r'RDTHRU      => "0000000100"',
                         r'idx_inc  <= acc_s\(SLOT_DATA\) and idx_ainc;',
                         r'NFCIDX_MSB downto NFCIDX_LSB => idx_inc',
                         r'clr_fieldf   <= w1c_s\(SLOT_SR\)\(NFCFIELDF_LSB\);',
                         r'payload_mem\(idx\) <= wdata\(NFCDATA_MSB downto NFCDATA_LSB\);']),
    # RTC is a periph_regs block (report R12b). SEC and SUB store the write
    # staging pair and read the counter's coherent snapshot (RDTHRU); the four
    # staging words take a whole-word write (WIDEWR); and because every write in
    # the block is lane-0 qualified, the lane vector handed to the register file
    # is forced to a read when lane 0 is not enabled.
    'rtc': dict(vhdl='RTC.vhd', regfile='rtc_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'RDTHRU      => "0110000"',
                         r'WIDEWR      => "0111100"',
                         r'wen_eff <= WEn when WEn\(0\) = \'0\' else "1111";',
                         r'constant SLOT_TRIM\s*:\s*natural\s*:=\s*6;']),
    # PWM is a periph_regs block (report R12c): the fourteen per-field flops are
    # the IMPL bits of four stored words, and there is no case decode, reset
    # branch or write-1 arm left to read. No WIDEWR row: the decode it replaced
    # already merged per byte lane. The hooks take the COMBINATIONAL acc_hit,
    # because this block's ClkMem is gated by EnMemPeriph and a registered strobe
    # would be sampled a whole bus access late.
    'pwm': dict(vhdl='PWM.vhd', regfile='pwm_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'STROBE_HOLD => false',
                         r"acc_s\(SLOT_PER\) = '1' or acc_s\(SLOT_DTY0\) = '1'",
                         r"wdata\(FLTTRIG_LSB\) = '1'",
                         r"if wdata\(FLTF_LSB\) = '1' then clr_flt_tgl <= not clr_flt_tgl;"]),
    # OneWire is a periph_regs block (report R12c). OWxCMD and OWxDIV are the
    # two WIDEWR words: the decode it replaced qualified every write on WEn(0)
    # alone and then wrote OWBITVAL at bit 8 and OWDIV at 15:0, both in lane 1.
    # The OWxCMD write snapshots OWODS and OWxTX and launches, off acc_hit.
    'onewire': dict(vhdl='OneWire.vhd', regfile='onewire_regs_pkg',
                    require=[r'u_regs\s*:\s*entity work\.periph_regs',
                             r'WIDEWR      => "0100100"',
                             r"cmd_wr <= '1' when \(acc_s\(SLOT_CMD\) = '1' and WEn\(0\) = '0'\)",
                             r"if wdata\(OWTCIF_LSB\)   = '1' then clr_tcif_tgl"]),
    # DMA is a periph_regs block (report R12d). It decoded a bare integer word
    # index, so the migration was a body rewrite: twenty words, WIDEWR everywhere
    # (the old decode qualified every write on WEn(0) and then wrote the full
    # word), RDTHRU on DMAxCR, the four LEN words, DMAxCRC and on every register
    # of a channel above NCH. ClkMem is gated to one edge per access, so the five
    # command toggles take acc_hit and not the registered wr_pulse / w1c_hit.
    'dma': dict(vhdl='DMA.vhd', regfile='dma_regs_pkg',
                require=[r'u_regs\s*:\s*entity work\.periph_regs',
                         r'STROBE_HOLD => true',
                         r'RDTHRU      => DMA_RDTHRU',
                         r'WIDEWR      => DMA_WIDEWR',
                         r'cr_hit  <= acc_s\(DMAxCR_WORD\)  and not WEn\(0\);',
                         r'sr_hit  <= acc_s\(DMAxSR_WORD\)  and not WEn\(0\);',
                         r'r\(wLen\(ch\)\) := \x271\x27;',
                         r'crc_acc\s*<=\s*X"FFFF";']),
    # TRNG is a periph_regs block (report R12c) and the tree's one onread=rclr
    # register lives here. The read-consume stays qualified on WEn = "1111", but
    # that qualifier is now the module's own: rd_hit is acc_hit ANDed with
    # WEn = "1111", combinational, so dr_read_acc is one indexing and no
    # hand-written direction test (report R12f). It is rd_hit and not the
    # module's rd_clr because this block's ClkMem is gated by EnMemPeriph, so a
    # strobe flop set on the access edge is only sampled by the NEXT bus access.
    # TRNGxCR is the one WIDEWR word (TRNGDECIM sits at 11:8, lane 1, under a
    # WEn(0) qualifier).
    'trng': dict(vhdl='TRNG.vhd', regfile='trng_regs_pkg',
                 require=[r'u_regs\s*:\s*entity work\.periph_regs',
                          r'WIDEWR      => "1000"',
                          r'rd_hit      => rdh_s,',
                          r'dr_read_acc <= rdh_s\(SLOT_DR\);',
                          r"wdata\(TRNGALMF_LSB\) = '1'"]),
    # I2CTarget is a periph_regs block (report R12c). I2CTxCR and I2CTxWDG are
    # the two WIDEWR words (SAD at 14:8, SADM at 22:16 and WDTO at 15:0 all
    # reach past lane 0 under a WEn(0) qualifier). An I2CTxTX write loads the
    # buffer, which the module now holds, and launches off acc_hit.
    'i2ctarget': dict(vhdl='I2CTarget.vhd', regfile='i2ctarget_regs_pkg',
                      require=[r'u_regs\s*:\s*entity work\.periph_regs',
                               r'WIDEWR      => "10001"',
                               r"if acc_s\(SLOT_TX\) = '1' and WEn\(0\) = '0' then",
                               r"if wdata\(I2CTAMF_LSB\)     = '1' then clr_amf_tgl"]),
    # EVFAB is on periph_regs (report R12e), on a SPARSE table: twenty-nine
    # registers over thirty-two words, words 12-14 all-zero _reserved_ rows. The
    # ACTION half (slots 7-11) is untouched and still decodes in the free-running
    # clk domain, because exactly-one-action-per-write is not a ClkMem property.
    # EVFCHENSET / EVFCHENCLR are the tree's first HWALIAS: software set and clear
    # aliases of EVFCHEN, which the description rightly calls hw=r. They take the
    # module's combinational wr_hit (report R12f); because wr_inh is WEn(0) on
    # every word here, wr_hit IS "addressed and WEn(0) = '0'", which is what the
    # hand-written qualifier spelled.
    'evfab': dict(vhdl='EVFAB.vhd', regfile='evfab_regs_pkg',
                  require=[r'u_regs\s*:\s*entity work\.periph_regs',
                           r'HWALIAS     => HWALIAS_EVF',
                           r'RDTHRU      => RDTHRU_EVF',
                           r'WIDEWR      => WIDEWR_EVF',
                           r"wr_inh <= \(others => WEn\(0\)\);",
                           r"when wrh_s\(SLOT_CHENSET\) = '1' else",
                           r"when wrh_s\(SLOT_CHENCLR\) = '1' else",
                           r'hw_set_s <= \(SLOT_CHEN => set_word, others => \(others => .0.\)\);',
                           r'hw_clr_s <= \(SLOT_CHEN => clr_word, others => \(others => .0.\)\);',
                           r'constant CAP_CONST\s*:\s*std_logic_vector\(31 downto 0\)',
                           r'N_CH\s*:\s*natural\s*:=\s*8;', r'N_EV\s*:\s*natural\s*:=\s*16;',
                           r'N_TASK\s*:\s*natural\s*:=\s*10;', r'VER\s*:\s*natural\s*:=\s*1']),
}


def _wrapRequire(spec, reader):
    def read(vhdlPath, memoryMapPath):
        # Over the entity AND its register package: a `require` pattern names a
        # declaration the reader's literal table depends on, and after report
        # R8a that declaration may have moved into the package the entity uses.
        # It is still a reading of what the entity compiles against.
        src = _decodeText(vhdlPath)
        for pat in spec.get('require', []):
            if re.search(pat, src) is None:
                raise Exception('rdl_vs_vhdl: %s no longer contains `%s`, so the slot table or a '
                                'reset value this reader states about it is no longer a reading of '
                                'the RTL. Re-read the decode.' % (os.path.basename(vhdlPath), pat))
        return reader(vhdlPath, memoryMapPath)
    return read


# UART and TIMER are the two periph_regs pilots (report R12a). The bespoke
# readUart that read UART's hand-written case decode is gone with the decode; the
# reading of the entity that replaced it is the `require` list below plus
# test_uart_write_one_to_clear_bits.
_UART_SPEC = dict(vhdl='UART.vhd', regfile='uart_regs_pkg',
                  require=[r'u_regs\s*:\s*entity work\.periph_regs',
                           r'STROBE_HOLD => false',
                           r'clr_UTCIF <= w1c_s\(RegSlotUARTxSR\)\(TCIF_LSB\);',
                           r'clr_SR_RX <= rd_str\(RegSlotUARTxRX\) or wr_str\(RegSlotUARTxRX\);'])

READERS = {
    'uart': {
        'rdl': ('uart.rdl', 'uart'),
        'vhdl': 'UART.vhd',
        'read': _wrapRequire(_UART_SPEC, makeRegfileReader('uart_regs_pkg')),
    },
}

# rdl.json is the registry of descriptions; this is the registry of DECODES.
# One entry per house-style block, all sharing makeGenericReader.
_RDL_FOR = {
    'gpio': ('gpio.rdl', 'gpio'), 'spi': ('spi.rdl', 'spi'), 'timer': ('timer.rdl', 'timer'),
    'system': ('system.rdl', 'system'), 'npu': ('npu.rdl', 'npu'), 'qspi': ('qspi.rdl', 'qspi'),
    'i2c': ('i2c.rdl', 'i2c'), 'clint': ('clint.rdl', 'clint'),
    'mutex_bank': ('mutex_bank.rdl', 'mutex_bank'), 'irq_router': ('irq_router.rdl', 'irq_router'),
    'pwr_ctrl': ('pwr_ctrl.rdl', 'pwr_ctrl'), 'i3c': ('i3c.rdl', 'i3c'), 'nfc': ('nfc.rdl', 'nfc'),
    'rtc': ('rtc.rdl', 'rtc'), 'pwm': ('pwm.rdl', 'pwm'), 'onewire': ('onewire.rdl', 'onewire'),
    'dma': ('dma.rdl', 'dma'), 'trng': ('trng.rdl', 'trng'),
    'i2ctarget': ('i2ctarget.rdl', 'i2ctarget'), 'evfab': ('evfab.rdl', 'evfab'),
}
for _k, _spec in GENERIC_BLOCKS.items():
    _inner = (makeRegfileReader(_spec['regfile']) if _spec.get('regfile')
              else makeGenericReader(_spec))
    READERS[_k] = {
        'rdl': _RDL_FOR[_k],
        'vhdl': _spec['vhdl'],
        'read': _wrapRequire(_spec, _inner),
    }


class RdlVsVhdlTest(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        if PERIPH not in READERS:
            raise Exception('rdl_vs_vhdl_test: --periph must be one of ' + ', '.join(sorted(READERS)))
        spec = READERS[PERIPH]
        vhdl = VHDL or _defaultVhdl(spec['vhdl'])
        mm = MEMORYMAP_VHD or os.path.join(REPO, 'hdl', 'common', 'MemoryMap.vhd')
        cls.vhdl = spec['read'](vhdl, mm)
        cls.block = rdl_model.loadBlock(spec['rdl'][0], spec['rdl'][1])
        cls.rdl = dict((rt.NameTemplate, rt) for rt in cls.block.RegisterTemplates)
        cls.vhdlPath = vhdl

    def test_the_two_decode_the_same_registers(self):
        self.assertEqual(sorted(self.rdl), sorted(self.vhdl),
                         'the .rdl and %s decode different register sets' % self.vhdlPath)

    def test_word_offsets_match(self):
        for name in sorted(self.rdl):
            self.assertEqual(self.rdl[name].RegisterMemorySlot, self.vhdl[name]['word'],
                             '%s: .rdl word %d, VHDL word %d'
                             % (name, self.rdl[name].RegisterMemorySlot, self.vhdl[name]['word']))

    def test_reset_values_match(self):
        for name in sorted(self.rdl):
            want = self.vhdl[name]['reset']
            if want is None:
                continue
            self.assertEqual(self.rdl[name].ResetValue, want,
                             '%s: .rdl resets to 0x%08X, %s resets it to 0x%08X. The VHDL is the '
                             'authority.' % (name, self.rdl[name].ResetValue,
                                             os.path.basename(self.vhdlPath), want))

    def test_storage_masks_match(self):
        for name in sorted(self.rdl):
            want = self.vhdl[name]['impl']
            if want is None:
                continue
            got = rdl_vhdl.storageMask(self.rdl[name])
            self.assertEqual(got, want,
                             '%s: the .rdl gives software-written bits 0x%08X, %s implements '
                             '0x%08X. Bits 0x%08X differ -- a field software can write that '
                             'hardware never sees, or the reverse.'
                             % (name, got, os.path.basename(self.vhdlPath), want, got ^ want))

    def test_field_widths_fit_the_register(self):
        for name, rt in sorted(self.rdl.items()):
            for bf in rt.BitFields:
                self.assertLess(bf.MSB, rt.Size, '%s.%s runs past the register width'
                                % (name, bf.Name))

    # -----------------------------------------------------------------------
    # THE PARAMETERISED BLOCKS (report R7). Everything above grades ONE
    # elaboration -- the five-hart default, which is what the tracked chip and
    # every gate around it use. Since CLINT, MUTEX, IRQROUTER and PWRCTRL became
    # the SOURCE of the published map for every configuration, their .rdl also
    # carries the LAYOUT FORMULA, and a formula is not checked by checking one
    # of its values. The three below re-elaborate the description at other
    # configurations and compare it against the same formula read out of the
    # VHDL generic decode, so a typo in the .rdl cannot move argus's or the
    # single-hart configurations' addresses unnoticed.
    # -----------------------------------------------------------------------

    def _elaborate(self, **params):
        spec = READERS[PERIPH]
        defines = params.pop('_defines', None)
        block = rdl_model.loadBlock(spec['rdl'][0], spec['rdl'][1], params, defines)
        return dict((rt.NameTemplate, rt) for rt in block.RegisterTemplates)

    def test_clint_layout_formula_matches_the_vhdl(self):
        """MTIME_W / CMP_W at 1, 5, 18 and 32 harts, against clint.vhd's own."""
        if PERIPH != 'clint':
            self.skipTest('CLINT-specific')
        src = _read(self.vhdlPath)
        self.assertRegex(src, r'constant MTIME_W\s*:\s*natural\s*:=\s*'
                              r'\(\(4\*NHARTS \+ 15\) / 16\) \* 4;',
                         'clint.vhd no longer states the MTIME_W formula this test evaluates')
        self.assertRegex(src, r'constant CMP_W\s*:\s*natural\s*:=\s*MTIME_W \+ 4;')
        for n in (1, 4, 5, 18, 32):
            mtimeW = ((4 * n + 15) // 16) * 4
            cmpW = mtimeW + 4
            regs = self._elaborate(NHARTS=n, MTIME_W=mtimeW, CMP_W=cmpW)
            self.assertEqual(sorted(r for r in regs if r.startswith('MSIP')),
                             sorted('MSIP%d' % h for h in range(n)),
                             'NHARTS=%d: the .rdl does not emit one MSIP per hart' % n)
            self.assertEqual(regs['MTIMEL'].RegisterMemorySlot, mtimeW)
            self.assertEqual(regs['MTIMEH'].RegisterMemorySlot, mtimeW + 1)
            for h in range(n):
                self.assertEqual(regs['MTIMECMP%dL' % h].RegisterMemorySlot, cmpW + 2 * h)
                self.assertEqual(regs['MTIMECMP%dH' % h].RegisterMemorySlot, cmpW + 2 * h + 1)
                self.assertEqual(regs['MTIMECMP%dL' % h].ResetValue, 0xFFFFFFFF)

    def test_mutex_bank_size_and_owner_width_match_the_vhdl(self):
        """NMUTEX registers and an MW+1-bit owner, at the two shipped shapes."""
        if PERIPH != 'mutex_bank':
            self.skipTest('MUTEX-specific')
        src = _decodeText(self.vhdlPath)
        # The owner array IS periph_regs' storage now, so what states the bank's
        # shape in the RTL is the table call and the owner mask taken off row 0.
        self.assertRegex(src, r'constant NW\s*:\s*natural\s*:=\s*NWORDS\(NMUTEX, MW\);',
                         'mutex_bank.vhd no longer sizes its register file from NMUTEX and MW')
        self.assertRegex(src, r'constant OWNER_MASK\s*:\s*word\s*:=\s*IMPL\(NMUTEX, MW\)\(0\);',
                         'mutex_bank.vhd no longer takes the owner mask out of the package IMPL table')
        for (nmutex, mw, nharts) in ((16, 3, 5), (32, 5, 18), (16, 2, 1)):
            regs = self._elaborate(NMUTEX=nmutex, MW=mw, NHARTS=nharts)
            self.assertEqual(sorted(regs), sorted('MUTEX%d' % i for i in range(nmutex)))
            for i in range(nmutex):
                own = regs['MUTEX%d' % i].GetBitFieldAt(0)
                self.assertEqual((own.Name, own.MSB, own.LSB), ('MTXOWN%d' % i, mw, 0))
                self.assertEqual(len(own.ValueDescriptions), nharts + 1,
                                 'the owner marker must enumerate free plus one value per hart')

    def test_irq_router_rows_and_word_widths_match_the_vhdl(self):
        """Four words per hart at 4h, and the top word's live width."""
        if PERIPH != 'irq_router':
            self.skipTest('IRQROUTER-specific')
        src = _decodeText(self.vhdlPath)
        self.assertRegex(src, r'constant NUM_EN_WORDS\s*:\s*natural\s*:=\s*'
                              r'\(NUM_SRCS \+ 31\) / 32;')
        self.assertRegex(src, r'constant W_CLAIM\s*:\s*natural\s*:=\s*512;')
        for (nharts, vectors) in ((1, 114), (5, 125), (18, 114), (32, 121)):
            xmsb = vectors - 97
            regs = self._elaborate(NHARTS=nharts, VECTORS=vectors, UMSB=31, UTOP=95, XMSB=xmsb)
            for h in range(nharts):
                for i, w in enumerate('LMUX'):
                    self.assertEqual(regs['H%dEN%s' % (h, w)].RegisterMemorySlot, 4 * h + i)
                enx = regs['H%dENX' % h]
                self.assertEqual(enx.GetBitFieldAt(0).MSB, xmsb,
                                 'NUM_SRCS=%d: the X word must be live to bit %d' % (vectors, xmsb))
            self.assertEqual(regs['CLAIM'].RegisterMemorySlot, 512)
            self.assertLess(4 * nharts, 512, 'the rows would collide with CLAIM')

    def test_pwr_ctrl_word_count_matches_the_vhdl(self):
        """ceil(NHARTS/8) PWRSR words, the fixed 5/6/7 tail above them."""
        if PERIPH != 'pwr_ctrl':
            self.skipTest('PWRCTRL-specific')
        src = _read(self.vhdlPath)
        self.assertRegex(src, r'constant NSRW\s*:\s*natural\s*:=\s*\(NHARTS \+ 7\) / 8;')
        for n in (1, 5, 8, 9, 18, 32):
            words = (n + 7) // 8
            defines = {}
            if words > 1:
                defines['VESTA_PWR_MULTIWORD'] = ''
            if words > 2:
                defines['VESTA_PWR_MIDWORDS'] = ''
            regs = self._elaborate(NHARTS=n, _defines=defines)
            names = ['PWRSR'] if words == 1 else ['PWRSR%d' % w for w in range(words)]
            self.assertEqual(sorted(r for r in regs if r.startswith('PWRSR') and r != 'PWRSTS'),
                             sorted(names),
                             'NHARTS=%d: the .rdl must emit %d PWRSR word(s)' % (n, words))
            for w, name in enumerate(names):
                live = [b for b in regs[name].BitFields if not b.Unused]
                self.assertEqual(sorted(b.Name for b in live),
                                 sorted('PWRST%d' % h for h in range(8 * w, min(8 * w + 8, n))),
                                 'NHARTS=%d: %s carries the wrong nibbles' % (n, name))
            gate = [b for b in regs['PWRCR'].BitFields if b.Name == 'PWRGATE']
            self.assertEqual(len(gate), 0 if n == 1 else 1,
                             'PWRCR.PWRGATE must be absent at one hart and present above it')
            if n > 1:
                self.assertEqual((gate[0].MSB, gate[0].LSB), (n - 1, 1))
            for name, word in (('PWRWAKE', 5), ('PWRSTS', 6), ('TASKWKM', 7)):
                self.assertEqual(regs[name].RegisterMemorySlot, word,
                                 '%s must stay at the NHARTS-independent word %d' % (name, word))

    def test_uart_write_one_to_clear_bits(self):
        """UART only: the three W1C flags the entity wires out of periph_regs are
           the three the description marks woclr, at the same bit positions.

           Before report R12a this read the SR arm of a hand-written case. The arm
           is gone: the entity now takes `w1c_hit(RegSlotUARTxSR)(<FIELD>_LSB)`
           per flag, and the bit position comes from the field constant rather
           than from a literal. That is still a statement of the RTL -- it names
           which flags this block retires on a written 1, and a flag the .rdl
           stopped calling woclr would arm nothing."""
        if PERIPH != 'uart':
            self.skipTest('UART-specific')
        src = _read(self.vhdlPath)
        wired = re.findall(
            r"clr_(\w+)\s*<=\s*w1c_s\(RegSlotUARTxSR\)\((\w+)_LSB\);", src)
        self.assertEqual(len(wired), 3,
                         'UART.vhd wires %d SR flags out of w1c_hit, expected 3' % len(wired))
        pkg = _decodeSource(self.vhdlPath, 'uart_regs_pkg')
        sr = self.rdl['UARTxSR']
        clears = {}
        for sig, field in wired:
            m = re.search(r'constant\s+' + field + r'_LSB\s*:\s*natural\s*:=\s*(\d+);', pkg)
            self.assertIsNotNone(m, 'uart_regs_pkg does not declare %s_LSB' % field)
            clears[int(m.group(1))] = sig
        self.assertEqual(sorted(clears), [0, 1, 2],
                         'UART.vhd clears SR bits %s, expected 0, 1 and 2' % sorted(clears))
        for bit in clears:
            bf = sr.GetBitFieldAt(bit)
            self.assertEqual(bf.Accessibility, 'rw1',
                             'UARTxSR bit %d is cleared by a write-1 in UART.vhd (clr_%s) but the '
                             '.rdl gives it access "%s"' % (bit, clears[bit], bf.Accessibility))
        # And every woclr bit the description declares is wired to something.
        declared = set(b.LSB for b in sr.BitFields
                       if not b.Unused and b.Accessibility == 'rw1')
        self.assertEqual(sorted(declared), sorted(clears),
                         'the .rdl marks UARTxSR bits %s write-1-to-clear; UART.vhd retires %s'
                         % (sorted(declared), sorted(clears)))


if __name__ == '__main__':
    unittest.main()
