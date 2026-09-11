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

    rdl_vs_vhdl_test.py --periph {afe2,biasg,uart} [--rdl-config <rdl.json>]
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

       What that costs is the same thing it cost AFE2 and BIASG at level 2: for a
       migrated block the constants read here came from the .rdl, so this gate
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

    SystemRDL level 2 (2026-09-10, report R6): AFE2.vhd and BIASG.vhd no longer
    declare W_* / NSTORED / IMPL / RSTVAL themselves; they `use` a generated
    package that exports them under those names. The entity is still checked --
    it must carry the context clause, or these constants are not the ones it
    compiles against -- but the values are read from the package.

    Note what this costs: for these two peripherals the comparison below is no
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


def readAfe2(path):
    src = _decodeSource(path, 'afe2_regs_pkg')
    words = dict((m.group(1), int(m.group(2)))
                 for m in re.finditer(r'constant\s+W_(\w+)\s*:\s*natural\s*:=\s*(\d+);', src))
    if not words:
        raise Exception('rdl_vs_vhdl: no W_* word constants in afe2_regs_pkg')
    impl = _aggregatePairs(src, 'IMPL', 'reg_arr_t')
    rst = _aggregatePairs(src, 'RSTVAL', 'reg_arr_t')
    nstored = int(re.search(r'constant\s+NSTORED\s*:\s*natural\s*:=\s*(\d+);', src).group(1))
    if len(words) != nstored:
        raise Exception('rdl_vs_vhdl: afe2_regs_pkg declares NSTORED = %d but %d W_* constants'
                        % (nstored, len(words)))
    out = {}
    for key, word in words.items():
        out['AFEx' + key] = {
            'word': word,
            'impl': impl.get('W_' + key, impl['__others__']),
            'reset': rst.get('W_' + key, rst['__others__']),
        }
    return out


def readBiasg(path):
    src = _decodeSource(path, 'biasg_regs_pkg')
    base = int(re.search(r'constant\s+WORD_BASE_DEFAULT\s*:\s*natural\s*:=\s*(\d+);', src).group(1))
    n = int(re.search(r'constant\s+N_WORDS\s*:\s*natural\s*:=\s*(\d+);', src).group(1))
    if ('WORD_BASE  : natural := WORD_BASE_DEFAULT' not in _read(path)):
        raise Exception('rdl_vs_vhdl: BIASG.vhd no longer takes its WORD_BASE generic default '
                        'from the package, so the base this gate reads is not the one it decodes.')
    names = ['AFExBIASG0', 'AFExBIASG1', 'AFExBIASG2', 'AFExBIASG3', 'AFExBIASGCR'][:n]

    def positional(constName):
        m = re.search(r'constant\s+' + constName + r'\s*:\s*reg_array\s*:=\s*\((.*?)\);', src, re.S)
        vals = [int(v, 16) for v in re.findall(r'x"([0-9A-Fa-f]+)"', m.group(1))]
        if len(vals) != n:
            raise Exception('rdl_vs_vhdl: BIASG.vhd %s has %d entries, N_WORDS is %d'
                            % (constName, len(vals), n))
        return vals

    impl, rst = positional('IMPL'), positional('RSTVAL')
    return dict((names[i], {'word': base + i, 'impl': impl[i], 'reset': rst[i]})
                for i in range(n))


def readUart(vhdlPath, memoryMapPath):
    """UART's decode is split: the slot numbers live in the package the entity
       `use`s -- work.MemoryMap before report R8a, work.uart_regs_pkg after it,
       under the same RegSlotUARTx* identifiers -- and the storage widths and
       resets in the entity."""
    mmSrc = _slotText(vhdlPath, memoryMapPath)
    slots = dict((m.group(1), int(m.group(2)))
                 for m in re.finditer(r'constant\s+RegSlotUARTx(\w+)\s*:\s*natural\s*:=\s*(\d+);', mmSrc))
    if not slots:
        raise Exception('rdl_vs_vhdl: no RegSlotUARTx* constants reachable from '
                        + os.path.basename(vhdlPath))
    src = _read(vhdlPath)
    widths = dict((m.group(1), int(m.group(2)) + 1)
                  for m in re.finditer(r'signal\s+UART_(CR|SR|BR|RX|TX)\s*:\s*std_logic_vector\((\d+)\s+downto\s+0\);', src))
    # The reset branch of the register write process names every storage register.
    wr = re.search(r'reg_write_proc\s*:\s*process.*?begin(.*?)elsif\s+rising_edge', src, re.S)
    zeroed = set(re.findall(r"UART_(CR|SR|BR|RX|TX)\s*<=\s*\(\s*others\s*=>\s*'0'\s*\)", wr.group(1)))
    # Registers software may write: those assigned from write_data in the case arms.
    body = re.search(r'case en_addr_periph is(.*?)end case;', src, re.S).group(1)
    written = set(re.findall(r'UART_(CR|SR|BR|RX|TX)\s*\([^)]*\)\s*<=\s*write_data', body))
    written |= set(re.findall(r'UART_(CR|SR|BR|RX|TX)\s*<=\s*write_data', body))
    out = {}
    for key, slot in slots.items():
        out['UARTx' + key] = {
            'word': slot,
            'width': widths.get(key),
            'reset': 0 if key in zeroed else None,
            'impl': ((1 << widths[key]) - 1) if key in written else 0,
        }
    return out



# ---------------------------------------------------------------------------
# THE GENERIC READER (added by the 20-block sweep, R2 2026-09-10)
#
# The three readers above are bespoke because AFE2 and BIASG declare explicit
# IMPL/RSTVAL tables and UART's decode is split across two files. The other
# twenty blocks share ONE house style, so they share one reader:
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
#   impl    NOT derived. Only AFE2 and BIASG state an implemented-bit table; for
#           the rest the storage mask would have to be inferred from the case
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
    'gpio': dict(vhdl='GPIO.vhd', slots='memmap:Px', name=_prefixed('Px', _GPIO_KEYS),
                 process='reg_write',
                 storage={'PxIES': 'PxIES', 'PxIE': 'PxIE', 'PxTASK': 'PxTASK'},
                 require=[r"PxIES\s*<=\s*\(others\s*=>\s*'0'\)",
                          r'PxOUT\s*<=\s*RstValPxOUT',
                          r'constant\s+RegSlotPxTASK\s*:\s*natural\s*:=\s*12;']),
    'spi': dict(vhdl='SPI.vhd', slots='memmap:SPIx', name=_prefixed('SPIx', _SPI_KEYS),
                process='reg_write',
                storage={'SPIxCR': 'SPIxCR', 'SPIxTX': 'SPIxTX', 'SPIxFOS': 'SPIxFOS'},
                require=[r'signal SPIxCR : std_logic_vector\(19 downto 0\)']),
    'timer': dict(vhdl='TIMER.vhd', slots='memmap:TIMx', name=_prefixed('TIMx', _TIM_KEYS),
                  process='reg_write_proc',
                  storage={'TIMxCR': 'control_reg', 'TIMxCMP0': 'compare0_reg',
                           'TIMxCMP1': 'compare1_reg', 'TIMxCMP2': 'compare2_reg'},
                  require=[r'if wen /= "1111" then']),
    'system': dict(vhdl='SYSTEM.vhd', slots='memmap:', name=_names(_SYS_NAMES),
                   process='reg_write_proc',
                   storage={'SYSCLKCR': 'SYS_CLK_CR', 'CLKDIVCR': 'SYS_CLK_DIV_CR',
                            'BLOCKPWR': 'SYS_BLOCK_PWR', 'WDTCR': 'SYS_WDT_CR',
                            'DCO0BIAS': 'DCO0_BIAS', 'DCO1BIAS': 'DCO1_BIAS'},
                   require=[r'DCO0_BIAS\s*<=\s*DCO0_BIAS_DEFAULT;',
                            r'DCO1_BIAS\s*<=\s*DCO1_BIAS_DEFAULT;',
                            r"if unlocked = '1' and wen\(0\) = '0' then"]),
    'npu': dict(vhdl='NPU.vhd', slots='mmr', name=_names(_NPU_NAMES), process='MMR_WRITE',
                storage={'NPUCR': 'NPUCR', 'NPUIVSAR': 'NPUIVSAR', 'NPUWVSAR': 'NPUWVSAR',
                         'NPUOVSAR': 'NPUOVSAR', 'NPUCFG1': 'NPUCFG1', 'NPUCFG2': 'NPUCFG2'},
                require=[r'NPUTHINK\s*<=\s*MabMmrD\(16\);']),
    'qspi': dict(vhdl='QSPI.vhd', slots='local', name=_prefixed('QSPIx', ['CR', 'CMD', 'ADR', 'TX', 'RX', 'SR']),
                 process='reg_write',
                 storage={'QSPIxCR': 'QSPIxCR', 'QSPIxCMD': 'QSPIxCMD',
                          'QSPIxADR': 'QSPIxADR', 'QSPIxTX': 'QSPIxTX'},
                 require=[r'constant SLOT_SR\s*:\s*natural\s*:=\s*5;']),
    'i2c': dict(vhdl='I2C.vhd', slots='memmap:I2Cx', name=_prefixed('I2Cx', _I2C_KEYS),
                process='reg_write',
                storage={'I2CxCR': 'I2CxCR', 'I2CxMTX': 'I2CxMTX', 'I2CxSTX': 'I2CxSTX',
                         'I2CxAMR': 'I2CxAMR'},
                require=[r'I2CxAR\s*<=\s*default_SAD;']),
    'clint': dict(vhdl=os.path.join('..', 'clint.vhd'), slots='none', name=lambda k: None,
                  literalSlots=_CLINT_SLOTS, storage=_CLINT_RESET, process='clint_proc',
                  require=[r"mtimecmp\s*<=\s*\(others\s*=>\s*\(others\s*=>\s*'1'\)\)",
                           r'constant MTIME_W\s*:\s*natural\s*:=\s*\(\(4\*NHARTS \+ 15\) / 16\) \* 4;',
                           r'constant CMP_W\s*:\s*natural\s*:=\s*MTIME_W \+ 4;']),
    'mutex_bank': dict(vhdl=os.path.join('..', 'mutex_bank.vhd'), slots='none', name=lambda k: None,
                       literalSlots=_MUTEX_SLOTS, storage=_MUTEX_RESET, process='mutex_proc',
                       require=[r"owner\s*<=\s*\(others\s*=>\s*\(others\s*=>\s*'0'\)\)",
                                r'assert 2\*\*AW = NMUTEX']),
    'irq_router': dict(vhdl=os.path.join('..', 'irq_router.vhd'), slots='none', name=lambda k: None,
                       literalSlots=_IRQR_SLOTS, storage=_IRQR_RESET,
                       require=[r'constant W_CLAIM\s*:\s*natural\s*:=\s*512;',
                                r'constant W_PENDL\s*:\s*natural\s*:=\s*516;',
                                r'constant W_INSVCL\s*:\s*natural\s*:=\s*520;',
                                r'constant NUM_EN_WORDS\s*:\s*natural\s*:=\s*\(NUM_SRCS \+ 31\) / 32;']),
    'pwr_ctrl': dict(vhdl=os.path.join('..', 'pwr_ctrl.vhd'), slots='none', name=lambda k: None,
                     literalSlots=_PWR_SLOTS, storage=_PWR_RESET,
                     require=[r'constant W_PWRWAKE\s*:\s*(?:integer|natural)\s*:=\s*5;',
                              r'constant W_PWRSTS\s*:\s*(?:integer|natural)\s*:=\s*6;',
                              r'constant W_TASKWKM\s*:\s*(?:integer|natural)\s*:=\s*7;',
                              r'elsif widx = W_TASKWKM then']),
    'i3c': dict(vhdl='I3C.vhd', slots='local',
                name=_prefixed('I3Cx', ['CR', 'CMD', 'TX', 'RX', 'SR', 'DAT', 'DATPID', 'DATINFO', 'IBI']),
                process='reg_write',
                storage={'I3CxCR': 'I3CxCR', 'I3CxCMD': 'I3CxCMD', 'I3CxTX': 'I3CxTX'},
                require=[r"I3CxCR\s*<=\s*\(2 => '1', others => '0'\)"]),
    'nfc': dict(vhdl='NFC.vhd', slots='local',
                name=_prefixed('NFCx', ['CR', 'SR', 'UID', 'CFG', 'TIM', 'RXST', 'IDX', 'DATA', 'TXCTL', 'DBG']),
                process='reg_write',
                storage={'NFCxCR': 'NFCxCR', 'NFCxUID': 'NFCxUID', 'NFCxCFG': 'NFCxCFG',
                         'NFCxTIM': 'NFCxTIM', 'NFCxIDX': 'NFCxIDX', 'NFCxTXCTL': 'NFCxTXCTL'},
                require=[r'NFCxCFG\s*<=\s*x"000044";', r'NFCxTIM\s*<=\s*x"088004D4";']),
    'rtc': dict(vhdl='RTC.vhd', slots='local',
                name=_prefixed('RTCx', ['CR', 'SEC', 'SUB', 'ALM', 'PER', 'SR', 'TRIM']),
                process='reg_write',
                storage={'RTCxCR': 'rtc_cr', 'RTCxSEC': 'stage_sec', 'RTCxSUB': 'stage_sub',
                         'RTCxALM': 'stage_alm', 'RTCxPER': 'stage_per'},
                require=[r'constant SLOT_TRIM\s*:\s*natural\s*:=\s*6;']),
    'pwm': dict(vhdl='PWM.vhd', slots='local',
                name=_prefixed('PWMx', ['CR', 'PER', 'DTY0', 'DTY1', 'DTY2', 'DTY3', 'POL', 'DT', 'SR']),
                process='reg_write', storage={},
                require=[r'constant SLOT_DT\s*:\s*natural\s*:=\s*7;']),
    'onewire': dict(vhdl='OneWire.vhd', slots='local',
                    name=_prefixed('OWx', ['CR', 'CMD', 'TX', 'RX', 'DIV', 'SR', 'SPU']),
                    process='reg_write',
                    storage={'OWxCR': 'ow_cr', 'OWxTX': 'ow_tx', 'OWxDIV': 'ow_div'},
                    require=[r'constant SLOT_SPU\s*:\s*natural\s*:=\s*6;']),
    'dma': dict(vhdl='DMA.vhd', slots='none', name=lambda k: None, literalSlots=_DMA_SLOTS,
                storage={'DMAxCRC': 0xFFFF},
                require=[r'crc_acc\s*<=\s*X"FFFF";',
                         r'elsif dma_slot >= 2 and dma_slot <= 17 then',
                         r'elsif dma_slot = 18 then']),
    'trng': dict(vhdl='TRNG.vhd', slots='local',
                 name=_prefixed('TRNGx', ['CR', 'SR', 'DR', 'HT']), process='reg_write',
                 storage={'TRNGxCR': 'trng_cr', 'TRNGxHT': 'rct_cutoff'},
                 require=[r'if WEn = "1111" then']),
    'i2ctarget': dict(vhdl='I2CTarget.vhd', slots='local',
                      name=_prefixed('I2CTx', ['CR', 'SR', 'TX', 'RX', 'WDG']), process='reg_write',
                      storage={'I2CTxTX': 'tx_byte', 'I2CTxWDG': 'wdg'},
                      require=[r'constant SLOT_WDG\s*:\s*natural\s*:=\s*4;']),
    'evfab': dict(vhdl='EVFAB.vhd', slots='local',
                  name=_prefixed('EVF', ['CR', 'SR', 'IE', 'CAP', 'CHEN', 'CHENSET', 'CHENCLR',
                                         'CHTRIG', 'FIRED', 'OVR', 'EVSTAT', 'EVTRIG',
                                         'GPIOMASK', 'CH0CFG']),
                  literalSlots=_EVF_SLOTS, process='reg_write',
                  storage={'EVFCHEN': 'chen', 'EVFGPIOMASK': 'gpiomask', 'EVFCAP': 0x010A1008},
                  require=[r'constant CAP_CONST\s*:\s*std_logic_vector\(31 downto 0\)',
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


READERS = {
    'afe2': {
        'rdl': ('afe2.rdl', 'afe2_site'),
        'vhdl': 'AFE2.vhd',
        'read': lambda v, m: readAfe2(v),
    },
    'biasg': {
        'rdl': ('biasg.rdl', 'biasg'),
        'vhdl': 'BIASG.vhd',
        'read': lambda v, m: readBiasg(v),
    },
    'uart': {
        'rdl': ('uart.rdl', 'uart'),
        'vhdl': 'UART.vhd',
        'read': readUart,
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
    READERS[_k] = {
        'rdl': _RDL_FOR[_k],
        'vhdl': _spec['vhdl'],
        'read': _wrapRequire(_spec, makeGenericReader(_spec)),
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
        src = _read(self.vhdlPath)
        self.assertRegex(src, r'type owner_t is array\(0 to NMUTEX-1\) of '
                              r'std_logic_vector\(MW downto 0\);',
                         'mutex_bank.vhd no longer declares the owner array this test reads')
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
        """UART only: the three W1C flags sit where the write process clears them."""
        if PERIPH != 'uart':
            self.skipTest('UART-specific')
        src = _read(self.vhdlPath)
        arm = re.search(r'when RegSlotUARTxSR\s*=>(.*?)when RegSlotUARTxBR', src, re.S).group(1)
        clears = dict((int(b), n) for (b, n) in
                      re.findall(r"write_data\((\d+)\)\s*=\s*'1'\s*then\s*clr_(\w+)\s*<=\s*'1';", arm))
        self.assertEqual(sorted(clears), [0, 1, 2],
                         'UART.vhd clears SR bits %s, expected 0, 1 and 2' % sorted(clears))
        sr = self.rdl['UARTxSR']
        for bit in clears:
            bf = sr.GetBitFieldAt(bit)
            self.assertEqual(bf.Accessibility, 'rw1',
                             'UARTxSR bit %d is cleared by a write-1 in UART.vhd (clr_%s) but the '
                             '.rdl gives it access "%s"' % (bit, clears[bit], bf.Accessibility))


if __name__ == '__main__':
    unittest.main()
