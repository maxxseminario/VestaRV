#!/usr/bin/env python3
"""rdl_vhdl.py -- a VHDL package of one .rdl block's offsets, field ranges and
reset constants.

The package a peripheral could `use` WITHOUT CHANGING BEHAVIOUR. AFE2.vhd and
BIASG.vhd today declare their word offsets, their implemented-bit masks and their
reset tables as file-local constants, deliberately, so each keeps a single-file
closure for its bench. This package emits exactly those constants under exactly
those meanings, so adopting it is a one-line `use work.AFEx_reg_pkg.all;` plus
deleting the local copies -- and the constants it emits are checked against the
local ones by //platform/common:rdl_vs_vhdl_afe2_test, so the swap is provably
inert.

Level 2 (2026-09-10): the two packages the RTL actually `use`s are TRACKED, at
hdl/common/regs/vhdl/afe2_regs_pkg.vhd and hdl/common/regs/vhdl/biasg_regs_pkg.vhd,
and AFE2.vhd / BIASG.vhd have deleted their local copies. Those two carry an
extra AGGREGATE section -- the array type, the word-offset constants and the
IMPL / RSTVAL tables under the identifiers the decode already used -- so the
migration is a context clause plus a deletion and the bodies are untouched.
RTL_PACKAGES below is the table that drives it; //platform/common:rdl_vhdl_pkg_test
regenerates both and fails if the tracked file differs by one byte, and
//platform/common:rdl_pkg_vs_legacy_test compares every emitted value against the
hand-written constants as they stood before the migration.

What is emitted per register:
    <REG>_WORD    natural, the word offset inside the peripheral's sub-slot
    <REG>_ADDR    natural, the byte offset
    <REG>_RESET   std_logic_vector, the reset word
    <REG>_IMPL    std_logic_vector, the software-writable storage mask
and per field:
    <FIELD>_MSB / <FIELD>_LSB   natural
    <FIELD>_RESET               std_logic_vector of the field's own width

`_IMPL` is the mask of bits that hold a software-written flop: a field counts
when software may write it (`sw` includes w), hardware does not drive it
(`hw = r`), and it is not a single-pulse strobe. That is the definition AFE2.vhd
and BIASG.vhd use for their IMPL tables, which is why the two agree bit for bit.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# The generator access codes whose bits are software-written storage.
_STORED_ACCESS = ('rw', 'rw0', 'rw1', 'w', 'w0')
# ... minus the ones hardware owns. A write-1-to-clear flag is set by hardware,
# so its bit is not a software register bit even though software writes it.
_HW_OWNED_ACCESS = ('rw0', 'rw1')


def storageMask(rt):
    """The mask of bits that hold a software-written flop in this register."""
    mask = 0
    for bf in rt.BitFields:
        if bf.Unused:
            continue
        if bf.Accessibility not in _STORED_ACCESS:
            continue
        if bf.Accessibility in _HW_OWNED_ACCESS:
            continue
        if bf.Accessibility in ('w', 'w0') and _isSinglePulse(bf):
            continue
        mask |= bf.BitMask
    return mask


def _isSinglePulse(bf):
    """A `w1` field is the generator's spelling of a self-clearing strobe."""
    return bf.Accessibility == 'w1'


# ---------------------------------------------------------------------------
# The TRACKED packages, and the aggregate section that lets the RTL adopt them
# without touching its body.
#
# AFE2.vhd and BIASG.vhd used to declare, file-locally, a word-offset constant
# per register, an array type over those words and two tables indexed by it
# (IMPL, the software-writable storage mask, and RSTVAL, the reset word). The
# scalar constants above already carry every value in those tables; what the
# aggregate section adds is the SHAPE -- the same type under the same name, and
# the same table under the same name -- so the migration is a `use` clause and a
# deletion, with no edit to a single assignment.
#
# Two spellings, because the two decodes index differently and neither was going
# to be bent to suit a generator:
#   keyed      AFE2: `IMPL(W_MUX)`, a named-association aggregate over absolute
#              word offsets, which is what a nine-register file with a sparse
#              reset table reads best as.
#   positional BIASG: `IMPL(sel)` where `sel = idx - WORD_BASE`, so the table is
#              five entries in slot order and the index is RELATIVE. Its word
#              constants are therefore emitted as IDX_* (relative, what indexes
#              the array) and never as W_* (absolute, what the bus decodes) --
#              one identifier per meaning, so the two cannot be confused.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE 22-PERIPHERAL WAVE (report R8a, 2026-09-11).
#
# Every peripheral gets a tracked package, whether or not its RTL has adopted it
# yet: a package no entity `use`s is inert in every flow, and emitting all of
# them at once means the flow registration (bazel, opensource_sim, Xcelium,
# Genus) is done ONCE rather than twenty-two times. `migrated` says whether the
# RTL carries the context clause today; the gates read it, so a peripheral is
# adopted by flipping one flag and deleting its local constants.
#
# `variants` is the answer to the four blocks whose register set is a function
# of the configuration (CLINT, MUTEX, IRQROUTER, PWRCTRL). The package is
# emitted at the default elaboration and then INTERSECTED with an emission at
# every listed configuration: a constant survives only if it exists, with the
# same value, in all of them. So the file carries exactly the config-independent
# half and nothing has to be hand-curated. The configurations are the ones
# //platform/common:rdl_vs_vhdl_<block>_test already elaborates.
# ---------------------------------------------------------------------------


def _clintVariants():
    out = []
    for n in (1, 4, 5, 18, 32):
        mtimeW = ((4 * n + 15) // 16) * 4
        out.append({'NHARTS': n, 'MTIME_W': mtimeW, 'CMP_W': mtimeW + 4})
    return tuple(out)


def _irqrVariants():
    return tuple({'NHARTS': h, 'VECTORS': v, 'UMSB': 31, 'UTOP': 95, 'XMSB': v - 97}
                 for (h, v) in ((1, 114), (5, 125), (18, 114), (32, 121)))


def _pwrVariants():
    out = []
    for n in (1, 5, 8, 9, 18, 32):
        words = (n + 7) // 8
        defines = {}
        if words > 1:
            defines['VESTA_PWR_MULTIWORD'] = ''
        if words > 2:
            defines['VESTA_PWR_MIDWORDS'] = ''
        out.append(({'NHARTS': n}, defines))
    return tuple(out)


RTL_PACKAGES = (
    {
        'package': 'afe2_regs_pkg',
        'file': 'hdl/common/regs/vhdl/afe2_regs_pkg.vhd',
        'source': 'afe2.rdl',
        'top': 'afe2_site',
        'rtl': 'hdl/common/periph/AFE2.vhd',
        'periph': 'afe2',
        'migrated': True,
    },
    {
        'package': 'biasg_regs_pkg',
        'file': 'hdl/common/regs/vhdl/biasg_regs_pkg.vhd',
        'source': 'biasg.rdl',
        'top': 'biasg',
        'rtl': 'hdl/common/periph/BIASG.vhd',
        'periph': 'biasg',
        'migrated': True,
    },
    # --- the memory-map-package convention -------------------------------
    # These six read their word offsets from work.MemoryMap's RegSlot* /
    # MmrAddr* constants. Their package re-declares the SAME identifiers, so
    # adoption swaps the context clause instead of adding one: an entity that
    # `use`s BOTH packages sees two homographs and every reference to them
    # stops being directly visible (VHDL LRM 12.4), which is a compile error,
    # not a silent wrong value. rdl_vhdl_pkg_test enforces the swap.
    {
        'package': 'uart_regs_pkg',
        'file': 'hdl/common/regs/vhdl/uart_regs_pkg.vhd',
        'source': 'uart.rdl',
        'top': 'uart',
        'rtl': 'hdl/common/periph/UART.vhd',
        'periph': 'uart',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    {
        'package': 'spi_regs_pkg',
        'file': 'hdl/common/regs/vhdl/spi_regs_pkg.vhd',
        'source': 'spi.rdl',
        'top': 'spi',
        'rtl': 'hdl/common/periph/SPI.vhd',
        'periph': 'spi',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    {
        'package': 'timer_regs_pkg',
        'file': 'hdl/common/regs/vhdl/timer_regs_pkg.vhd',
        'source': 'timer.rdl',
        'top': 'timer',
        'rtl': 'hdl/common/periph/TIMER.vhd',
        'periph': 'timer',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    {
        'package': 'i2c_regs_pkg',
        'file': 'hdl/common/regs/vhdl/i2c_regs_pkg.vhd',
        'source': 'i2c.rdl',
        'top': 'i2c',
        'rtl': 'hdl/common/periph/I2C.vhd',
        'periph': 'i2c',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    {
        'package': 'system_regs_pkg',
        'file': 'hdl/common/regs/vhdl/system_regs_pkg.vhd',
        'source': 'system.rdl',
        'top': 'system',
        'rtl': 'hdl/common/periph/SYSTEM.vhd',
        'periph': 'system',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    {
        'package': 'npu_regs_pkg',
        'file': 'hdl/common/regs/vhdl/npu_regs_pkg.vhd',
        'source': 'npu.rdl',
        'top': 'npu',
        'rtl': 'hdl/common/periph/NPU.vhd',
        'periph': 'npu',
        'migrated': True,
        'replacesMemoryMap': True,
    },
    # GPIO IS PARKED AND CANNOT BE ADOPTED AS THINGS STAND. Its ENTITY PORTS are
    # GPIO_NUM_AFS * num_pins wide and GPIO_NUM_AFS is a work.MemoryMap constant,
    # so GPIO.vhd cannot drop that context clause -- and the memory-map package
    # also publishes a <FIELD>_MSB / <FIELD>_LSB pair for every GPIO field
    # (MemoryMap.vhd:422 PxAFS0_LSB and its neighbours), which is exactly what
    # this package emits. Using both would make every one of those names an
    # ambiguous homograph. The package is emitted and gated like the rest; the
    # unblocking move is to give GPIO.vhd a NUM_AFS generic (defaulted by its
    # instantiator, which already `use`s the memory map) so the entity can drop
    # the clause. Its RegSlotPx* constants are omitted for the same reason.
    {
        'package': 'gpio_regs_pkg',
        'file': 'hdl/common/regs/vhdl/gpio_regs_pkg.vhd',
        'source': 'gpio.rdl',
        'top': 'gpio',
        'rtl': 'hdl/common/periph/GPIO.vhd',
        'periph': 'gpio',
        'migrated': False,
    },
    # --- the local-SLOT_ convention --------------------------------------
    {
        'package': 'qspi_regs_pkg',
        'file': 'hdl/common/regs/vhdl/qspi_regs_pkg.vhd',
        'source': 'qspi.rdl',
        'top': 'qspi',
        'rtl': 'hdl/common/periph/QSPI.vhd',
        'periph': 'qspi',
        'migrated': True,
    },
    {
        'package': 'i3c_regs_pkg',
        'file': 'hdl/common/regs/vhdl/i3c_regs_pkg.vhd',
        'source': 'i3c.rdl',
        'top': 'i3c',
        'rtl': 'hdl/common/periph/I3C.vhd',
        'periph': 'i3c',
        'migrated': True,
    },
    {
        'package': 'nfc_regs_pkg',
        'file': 'hdl/common/regs/vhdl/nfc_regs_pkg.vhd',
        'source': 'nfc.rdl',
        'top': 'nfc',
        'rtl': 'hdl/common/periph/NFC.vhd',
        'periph': 'nfc',
        'migrated': True,
    },
    {
        'package': 'rtc_regs_pkg',
        'file': 'hdl/common/regs/vhdl/rtc_regs_pkg.vhd',
        'source': 'rtc.rdl',
        'top': 'rtc',
        'rtl': 'hdl/common/periph/RTC.vhd',
        'periph': 'rtc',
        'migrated': True,
    },
    {
        'package': 'pwm_regs_pkg',
        'file': 'hdl/common/regs/vhdl/pwm_regs_pkg.vhd',
        'source': 'pwm.rdl',
        'top': 'pwm',
        'rtl': 'hdl/common/periph/PWM.vhd',
        'periph': 'pwm',
        'migrated': True,
    },
    {
        'package': 'onewire_regs_pkg',
        'file': 'hdl/common/regs/vhdl/onewire_regs_pkg.vhd',
        'source': 'onewire.rdl',
        'top': 'onewire',
        'rtl': 'hdl/common/periph/OneWire.vhd',
        'periph': 'onewire',
        'migrated': True,
    },
    {
        'package': 'trng_regs_pkg',
        'file': 'hdl/common/regs/vhdl/trng_regs_pkg.vhd',
        'source': 'trng.rdl',
        'top': 'trng',
        'rtl': 'hdl/common/periph/TRNG.vhd',
        'periph': 'trng',
        'migrated': True,
    },
    {
        'package': 'i2ctarget_regs_pkg',
        'file': 'hdl/common/regs/vhdl/i2ctarget_regs_pkg.vhd',
        'source': 'i2ctarget.rdl',
        'top': 'i2ctarget',
        'rtl': 'hdl/common/periph/I2CTarget.vhd',
        'periph': 'i2ctarget',
        'migrated': True,
    },
    {
        'package': 'evfab_regs_pkg',
        'file': 'hdl/common/regs/vhdl/evfab_regs_pkg.vhd',
        'source': 'evfab.rdl',
        'top': 'evfab',
        'rtl': 'hdl/common/periph/EVFAB.vhd',
        'periph': 'evfab',
        'migrated': True,
    },
    # --- decodes with no named slot constants ----------------------------
    # DMA, CLINT and MUTEX decode a bare integer word index, so there is no
    # local constant to delete and adoption would be a body edit. Their
    # packages are emitted and gated like the rest; nothing `use`s them yet.
    {
        'package': 'dma_regs_pkg',
        'file': 'hdl/common/regs/vhdl/dma_regs_pkg.vhd',
        'source': 'dma.rdl',
        'top': 'dma',
        'rtl': 'hdl/common/periph/DMA.vhd',
        'periph': 'dma',
        'migrated': False,
    },
    # --- the four configuration-dependent blocks -------------------------
    {
        'package': 'clint_regs_pkg',
        'file': 'hdl/common/regs/vhdl/clint_regs_pkg.vhd',
        'source': 'clint.rdl',
        'top': 'clint',
        'rtl': 'hdl/common/clint.vhd',
        'periph': 'clint',
        'migrated': False,
        'variants': tuple((p, None) for p in _clintVariants()),
        'variantNote': 'NHARTS 1, 4, 5, 18, 32 (MTIME_W = ceil(4*NHARTS/16)*4, CMP_W = MTIME_W + 4)',
    },
    {
        'package': 'mutex_bank_regs_pkg',
        'file': 'hdl/common/regs/vhdl/mutex_bank_regs_pkg.vhd',
        'source': 'mutex_bank.rdl',
        'top': 'mutex_bank',
        'rtl': 'hdl/common/mutex_bank.vhd',
        'periph': 'mutex_bank',
        'migrated': False,
        'variants': (({'NMUTEX': 16, 'MW': 3, 'NHARTS': 5}, None),
                     ({'NMUTEX': 32, 'MW': 5, 'NHARTS': 18}, None),
                     ({'NMUTEX': 16, 'MW': 2, 'NHARTS': 1}, None)),
        'variantNote': '(NMUTEX, MW, NHARTS) = (16, 3, 5), (32, 5, 18), (16, 2, 1)',
    },
    {
        'package': 'irq_router_regs_pkg',
        'file': 'hdl/common/regs/vhdl/irq_router_regs_pkg.vhd',
        'source': 'irq_router.rdl',
        'top': 'irq_router',
        'rtl': 'hdl/common/irq_router.vhd',
        'periph': 'irq_router',
        'migrated': True,
        'variants': tuple((p, None) for p in _irqrVariants()),
        'variantNote': '(NHARTS, VECTORS) = (1, 114), (5, 125), (18, 114), (32, 121)',
    },
    {
        'package': 'pwr_ctrl_regs_pkg',
        'file': 'hdl/common/regs/vhdl/pwr_ctrl_regs_pkg.vhd',
        'source': 'pwr_ctrl.rdl',
        'top': 'pwr_ctrl',
        'rtl': 'hdl/common/pwr_ctrl.vhd',
        'periph': 'pwr_ctrl',
        'migrated': True,
        'variants': _pwrVariants(),
        'variantNote': 'NHARTS 1, 5, 8, 9, 18, 32 (the PWRSR word count is ceil(NHARTS/8))',
    },
    # --- not a memory-mapped peripheral ----------------------------------
    # debug_module.vhd decodes DMI addresses as 7-bit vectors (A_DATA0 ...), not
    # word offsets, and rdl.json marks it registerSource "none". The package is
    # emitted for completeness and has no adoption path; see the report.
    {
        'package': 'debug_module_regs_pkg',
        'file': 'hdl/common/regs/vhdl/debug_module_regs_pkg.vhd',
        'source': 'debug_module.rdl',
        'top': 'debug_module',
        'rtl': 'hdl/common/debug_module.vhd',
        'periph': None,
        'migrated': False,
    },
)

# Keyed by the .rdl addrmap (block.Name). A block with no entry gets the scalar
# constants only, which is what every out/rdl/ emission has always been.
_AGGREGATE = {
    'afe2_site': {
        'shortPrefix': 'AFEx',
        'indexPrefix': 'W_',
        'countName': 'NSTORED',
        'arrayType': 'reg_arr_t',
        'keyed': True,
        'wordBaseName': None,
        'rtl': 'AFE2.vhd',
    },
    'biasg': {
        'shortPrefix': 'AFEx',
        'indexPrefix': 'IDX_',
        'countName': 'N_WORDS',
        'arrayType': 'reg_array',
        'keyed': False,
        'wordBaseName': 'WORD_BASE_DEFAULT',
        'rtl': 'BIASG.vhd',
    },
}


# ---------------------------------------------------------------------------
# THE DECODE IDENTIFIERS, per block.
#
# _AGGREGATE above covers the two blocks that declare an array type and two
# tables indexed by it. The other twenty-two declare, at most, one natural
# constant per register, and the spelling is the block's own: a local `SLOT_CR`,
# the memory-map package's `RegSlotUARTxCR`, NPU's `MmrAddrNPUCR`, irq_router's
# `W_CLAIM`. This table says which, so the emitted package can be adopted by a
# context clause and a deletion, with no identifier renamed anywhere.
#
#   style 'strip'  identifier = prefix + (register name minus `strip`)
#   style 'map'    identifier = names[register name]; a register absent from the
#                  map gets no decode constant, which is how a block that names
#                  only some of its words (irq_router, pwr_ctrl, evfab) is
#                  described without inventing constants it does not have.
#   absent         the decode uses bare integers (CLINT, MUTEX, DMA) or is not
#                  memory mapped (debug_module); scalar constants only.
# ---------------------------------------------------------------------------

_SYSTEM_RTL_SPELLING = {
    'SYSCLKCR': 'RegSlotSYS_CLK_CR',
    'CLKDIVCR': 'RegSlotSYS_CLK_DIV_CR',
    'BLOCKPWR': 'RegSlotSYS_BLOCK_PWR',
    'CRCDATA': 'RegSlotSYS_CRC_DATA',
    'CRCSTATE': 'RegSlotSYS_CRC_STATE',
    'WDTPASS': 'RegSlotSYS_WDT_PASS',
    'WDTCR': 'RegSlotSYS_WDT_CR',
    'WDTSR': 'RegSlotSYS_WDT_SR',
    'WDTVAL': 'RegSlotSYS_WDT_VAL',
    'DCO0BIAS': 'RegSlotDCO0_BIAS',
    'DCO1BIAS': 'RegSlotDCO1_BIAS',
}

_IRQR_NAMED_WORDS = dict([('CLAIM', 'W_CLAIM')] +
                         [('PEND' + w, 'W_PEND' + w) for w in 'LMUX'] +
                         [('INSVC' + w, 'W_INSVC' + w) for w in 'LMUX'])

_DECODE = {
    # local SLOT_<key>, the key being the register name without the template prefix
    'qspi': {'rtl': 'QSPI.vhd', 'style': 'strip', 'strip': 'QSPIx', 'prefix': 'SLOT_'},
    'i3c': {'rtl': 'I3C.vhd', 'style': 'strip', 'strip': 'I3Cx', 'prefix': 'SLOT_'},
    'nfc': {'rtl': 'NFC.vhd', 'style': 'strip', 'strip': 'NFCx', 'prefix': 'SLOT_'},
    'rtc': {'rtl': 'RTC.vhd', 'style': 'strip', 'strip': 'RTCx', 'prefix': 'SLOT_'},
    'pwm': {'rtl': 'PWM.vhd', 'style': 'strip', 'strip': 'PWMx', 'prefix': 'SLOT_'},
    'onewire': {'rtl': 'OneWire.vhd', 'style': 'strip', 'strip': 'OWx', 'prefix': 'SLOT_'},
    'trng': {'rtl': 'TRNG.vhd', 'style': 'strip', 'strip': 'TRNGx', 'prefix': 'SLOT_'},
    'i2ctarget': {'rtl': 'I2CTarget.vhd', 'style': 'strip', 'strip': 'I2CTx', 'prefix': 'SLOT_'},
    # EVFAB names its thirteen fixed words and then ONE channel-config word,
    # SLOT_CH0CFG, because the fifteen above it are SLOT_CH0CFG + n.
    'evfab': {'rtl': 'EVFAB.vhd', 'style': 'map',
              'names': dict([(n, 'SLOT_' + n[3:]) for n in
                             ('EVFCR', 'EVFSR', 'EVFIE', 'EVFCAP', 'EVFCHEN', 'EVFCHENSET',
                              'EVFCHENCLR', 'EVFCHTRIG', 'EVFFIRED', 'EVFOVR', 'EVFEVSTAT',
                              'EVFEVTRIG', 'EVFGPIOMASK', 'EVFCH0CFG')])},
    # the memory-map package's spelling, re-declared here so the entity can swap
    # `use work.MemoryMap.all` for `use work.<x>_regs_pkg.all`
    'uart': {'rtl': 'UART.vhd', 'style': 'strip', 'strip': '', 'prefix': 'RegSlot'},
    'spi': {'rtl': 'SPI.vhd', 'style': 'strip', 'strip': '', 'prefix': 'RegSlot'},
    'timer': {'rtl': 'TIMER.vhd', 'style': 'strip', 'strip': '', 'prefix': 'RegSlot'},
    'i2c': {'rtl': 'I2C.vhd', 'style': 'strip', 'strip': '', 'prefix': 'RegSlot'},
    'system': {'rtl': 'SYSTEM.vhd', 'style': 'map', 'names': _SYSTEM_RTL_SPELLING},
    'npu': {'rtl': 'NPU.vhd', 'style': 'strip', 'strip': '', 'prefix': 'MmrAddr'},
    # GPIO gets none: see the RTL_PACKAGES note. Its entity keeps
    # `use work.MemoryMap.all` for GPIO_NUM_AFS, so a RegSlotPx* here would be an
    # ambiguous homograph rather than a constant.
    #
    # The two blocks that name only their configuration-independent words. The
    # per-hart rows (irq_router) and the PWRSR words (pwr_ctrl) are computed
    # from a generic in the RTL and are filtered out by `variants` anyway.
    'irq_router': {'rtl': 'irq_router.vhd', 'style': 'map', 'names': _IRQR_NAMED_WORDS},
    'pwr_ctrl': {'rtl': 'pwr_ctrl.vhd', 'style': 'map',
                 'names': {'PWRWAKE': 'W_PWRWAKE', 'PWRSTS': 'W_PWRSTS',
                           'TASKWKM': 'W_TASKWKM'}},
}


def _decodeIdent(spec, name):
    if spec['style'] == 'map':
        return spec['names'].get(name)
    if not name.startswith(spec['strip']):
        raise Exception('rdl_vhdl: %s does not start with the template prefix %r'
                        % (name, spec['strip']))
    return spec['prefix'] + name[len(spec['strip']):]


def _decodeLines(block):
    """The block's own word-offset constants, under the spelling its decode uses."""
    spec = _DECODE.get(block.Name)
    if spec is None:
        return []
    rows = []
    for rt in block.RegisterTemplates:
        ident = _decodeIdent(spec, rt.NameTemplate)
        if ident is not None:
            rows.append((ident, rt.Offset // 4))
    if not rows:
        return []
    L = []
    L.append('    -- ' + spec['rtl'] + "'s own decode identifiers: the word each register is")
    L.append('    -- decoded at, spelled the way that file already spells it, so adopting this')
    L.append('    -- package is a context clause plus a deletion and no assignment moves.')
    for ident, word in rows:
        L.append('    constant %-24s : natural := %d;' % (ident, word))
    L.append('')
    return L


def singlePulseMask(rt):
    """The mask of bits that are write-1 strobes: written by software, stored by
       nothing, and therefore absent from the storage mask above."""
    mask = 0
    for bf in rt.BitFields:
        if bf.Unused:
            continue
        if _isSinglePulse(bf):
            mask |= bf.BitMask
    return mask


def _hex32(value, width):
    return 'x"' + format(value & ((1 << width) - 1), '0' + str((width + 3) // 4) + 'X') + '"'


def _shortName(rt, prefix):
    n = rt.NameTemplate
    return n[len(prefix):] if prefix and n.startswith(prefix) else n


def _aggregateLines(block):
    """The array type, index constants and IMPL / RSTVAL tables, under the
       identifiers the peripheral's decode already uses."""
    spec = _AGGREGATE.get(block.Name)
    if spec is None:
        return []
    regs = list(block.RegisterTemplates)
    words = [rt.Offset // 4 for rt in regs]
    base = min(words)
    if words != list(range(base, base + len(regs))):
        raise Exception('rdl_vhdl: %s does not occupy a contiguous run of words (%s); the '
                        'aggregate tables index a dense array and cannot describe a hole.'
                        % (block.Name, words))
    width = regs[0].Size
    for rt in regs:
        if rt.Size != width:
            raise Exception('rdl_vhdl: %s mixes register widths (%d and %d); the aggregate '
                            'tables are one array of one width.' % (block.Name, width, rt.Size))
    names = [_shortName(rt, spec['shortPrefix']) for rt in regs]
    idx = [w if spec['keyed'] else w - base for w in words]
    keyName = [spec['indexPrefix'] + n for n in names]

    L = []
    L.append('    -- ' + spec['rtl'] + "'s own decode identifiers. The index constants, the")
    L.append('    -- array type over them and the two tables indexed by it, so the entity')
    L.append('    -- declares none of them itself and no assignment in its body changes.')
    for k, i in zip(keyName, idx):
        L.append('    constant %-24s : natural := %d;' % (k, i))
    L.append('    constant %-24s : natural := %d;' % (spec['countName'], len(regs)))
    if spec['wordBaseName']:
        L.append('    constant %-24s : natural := %d;   -- first word inside the host sub-slot'
                 % (spec['wordBaseName'], base))
    L.append('')
    L.append('    type %s is array(0 to %s-1) of std_logic_vector(%d downto 0);'
             % (spec['arrayType'], spec['countName'], width - 1))
    L.append('')
    for constName, valueOf, note in (
            ('IMPL', storageMask,
             'bits that hold a software-written flop; everything else reads 0 and drops writes'),
            ('RSTVAL', lambda rt: rt.ResetValue or 0, 'reset word')):
        L.append('    -- ' + note)
        L.append('    constant %-8s : %s := (' % (constName, spec['arrayType']))
        rows = []
        for rt, k in zip(regs, keyName):
            v = _hex32(valueOf(rt), width)
            rows.append(('        %-14s => %s' % (k, v)) if spec['keyed'] else ('        ' + v))
        L.append((',' + chr(10)).join(rows) + ');')
        L.append('')
    sp = [(rt, singlePulseMask(rt)) for rt in regs]
    if any(m for _, m in sp):
        L.append('    -- Write-1 strobes: software writes them, nothing stores them, so they are')
        L.append('    -- absent from IMPL. <FIELD>_LSB above is the bit each one occupies.')
        for rt, m in sp:
            if not m:
                continue
            L.append('    constant %-24s : %s := %s;'
                     % (rt.NameTemplate + '_SINGLEPULSE',
                        'std_logic_vector(%d downto 0)' % (width - 1), _hex32(m, width)))
        L.append('')
    return L


def _firstSentence(text):
    """The leading sentence of a description. Splitting on '.' alone cuts
       `610.35 uV per code` in half, so a period between two digits does not end
       a sentence here."""
    m = re.split(r'(?<!\d)\.(?!\d)', text, 1)
    return m[0].strip()


def _slv(value, width):
    return '"' + format(value & ((1 << width) - 1), '0' + str(width) + 'b') + '"'


def _registerGroups(block):
    """One (headerComment, [(constantName, line), ...]) per register.

       Grouped rather than flat because the variant intersection below drops
       whole registers at some configurations, and a register header comment
       with nothing under it is worse than no comment."""
    regNames = set(rt.NameTemplate for rt in block.RegisterTemplates)
    groups = []
    for rt in block.RegisterTemplates:
        n = rt.NameTemplate
        w = rt.Size
        head = '    -- ' + n + (': ' + _firstSentence(rt.Description) if rt.Description else '')
        items = [
            (n + '_WORD', '    constant %-24s : natural := %d;' % (n + '_WORD', rt.Offset // 4)),
            (n + '_ADDR', '    constant %-24s : natural := %d;' % (n + '_ADDR', rt.Offset)),
            (n + '_RESET', '    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                           % (n + '_RESET', w - 1, _slv(rt.ResetValue or 0, w))),
            (n + '_IMPL', '    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                          % (n + '_IMPL', w - 1, _slv(storageMask(rt), w))),
        ]
        for bf in rt.BitFields:
            if bf.Unused:
                continue
            items.append((bf.Name + '_MSB',
                          '    constant %-24s : natural := %d;' % (bf.Name + '_MSB', bf.MSB)))
            items.append((bf.Name + '_LSB',
                          '    constant %-24s : natural := %d;' % (bf.Name + '_LSB', bf.LSB)))
            if bf.Name in regNames:
                # A single field carrying the register's own name. Emitting
                # <NAME>_RESET twice is an illegal duplicate declaration, and the
                # two are not even the same width where the field is narrower
                # than the register (NPUIVSAR: 12 bits of 32), so the field's
                # copy is dropped and said to be dropped.
                items.append((bf.Name + '_RESET',
                              '    -- %s_RESET is the register constant above; this field carries '
                              'the register name.' % bf.Name))
            else:
                items.append((bf.Name + '_RESET',
                              '    constant %-24s : std_logic_vector(%d downto 0) := %s;'
                              % (bf.Name + '_RESET', bf.Size - 1, _slv(bf.ResetValue, bf.Size))))
        groups.append((head, items))
    return groups


def _bodyLines(block):
    """The register groups plus the block's own decode identifiers, as they are
       emitted at ONE elaboration."""
    groups = _registerGroups(block)
    tail = _aggregateLines(block) + _decodeLines(block)
    return groups, tail


def _intersect(groups, tail, variantBodies):
    """Keep only what every listed configuration emits identically.

       A configuration-dependent block (CLINT, MUTEX, IRQROUTER, PWRCTRL) has a
       register set and, in places, a field geometry that is a function of a
       generic. Rather than curate by hand which of its constants are safe to
       publish, the package is emitted at every shipped configuration and the
       result is the intersection: a constant survives only where its name AND
       its text are the same everywhere. What is dropped stays a generic in the
       entity, which is where a configuration-dependent number belongs."""
    common = None
    for vgroups, vtail in variantBodies:
        here = {}
        for _, items in vgroups:
            for name, text in items:
                here[name] = text
        for line in vtail:
            m = re.match(r'\s+constant\s+(\w+)\s', line)
            if m:
                here['tail:' + m.group(1)] = line
        common = here if common is None else \
            dict((k, v) for k, v in common.items() if here.get(k) == v)
    keptGroups = []
    for head, items in groups:
        kept = [(n, t) for (n, t) in items if common.get(n) == t]
        if kept:
            keptGroups.append((head, kept))
    keptTail = []
    for line in tail:
        m = re.match(r'\s+constant\s+(\w+)\s', line)
        if m and common.get('tail:' + m.group(1)) != line:
            continue
        keptTail.append(line)
    while keptTail and not keptTail[-1].strip():
        keptTail.pop()
    if keptTail:
        keptTail.append('')
    return keptGroups, keptTail


def emitString(block, packageName=None, spec=None):
    pkg = packageName or (block.Name + '_reg_pkg')
    spec = spec or {}
    # The .rdl this package came from. RTL_PACKAGES states it; the untracked
    # out/rdl/ emissions, which pass no spec, fall back to the addrmap name,
    # which is the file stem for every house-style block.
    source = spec.get('source') or (block.Name + '.rdl')
    short = re.sub(r'_regs?_pkg$', '', pkg).upper()
    groups, tail = _bodyLines(block)
    variants = spec.get('variants')
    if variants:
        bodies = []
        for params, defines in variants:
            import rdl_model
            bodies.append(_bodyLines(rdl_model.loadBlock(spec['source'], spec['top'],
                                                         params, defines)))
        groups, tail = _intersect(groups, tail, bodies)
    L = []
    L.append('-- VestaRV: ' + short + ' register package')
    L.append('-- ' + (block.Description or block.Name))
    L.append('-- Generated from hdl/common/regs/rdl/' + source
             + ' by platform/common/python/rdl_vhdl.py.')
    L.append('-- Do not edit; regenerate with'
             ' `bazel run //platform/common/python:rdl_vhdl_pkgs`.')
    L.append('-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a'
             ' software-written flop.')
    if variants:
        L.append('-- Configuration-dependent: only what is common to '
                 + spec.get('variantNote', '') + ' is emitted, the rest stays a generic in '
                 + os.path.basename(spec.get('rtl', '')) + '.')
    L.append('')
    L.append('library ieee;')
    L.append('use ieee.std_logic_1164.all;')
    L.append('')
    L.append('package ' + pkg + ' is')
    L.append('')
    for head, items in groups:
        L.append(head)
        for _, text in items:
            L.append(text)
        L.append('')
    L.extend(tail)
    L.append('end package ' + pkg + ';')
    L.append('')
    return '\n'.join(L)


def emit(block, outPath, packageName=None):
    with open(outPath, 'w') as f:
        f.write(emitString(block, packageName))
    return outPath
