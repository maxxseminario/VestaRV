#!/usr/bin/env python3
"""verify_stage.py -- stage the generated RTL into a self-contained Xcelium
behavioral smoke flow (the staging half of `make verify`).

Reads config/ChipConfig.resolved.json (written by the `make generate` step that
the Makefile runs first) and produces, under ../xcelium/riscv_test/:

  verify_<chipname>/           the runner dir (regenerated every run)
    hdl/MCU.vhd                copies of out/hdl/* -- the CONFIG's RTL
    hdl/MemoryMap.vhd
    hdl/riscv_tb.vhd
    cell_list_behavioral.txt   behavioral_mp's list with the three generated
                               files swapped for the staged copies and NPU.vhd
                               dropped when the config has no NPU
    xrun_parallel.sh           from verify/xrun_parallel.template.sh, with the
                               TEST_FILES list filtered by the config's knobs
    smoke.txt                  the ~26-test smoke subset, same filtering
    batch_run.tcl
  <link> -> ../../verification/isa/<dest>   the 3-char rcf symlink (the
                               riscv_tb TEST_FILE generic is a FIXED 29-char
                               string: "../" + 3-char dir + "/" + 22-char
                               x-padded filename -- the link name MUST be
                               exactly 3 characters)

It never touches hdl/myshkin/ or hdl/common/ and never writes outside
xcelium/riscv_test/. Prints KEY=VALUE lines consumed by ../verify.sh.

This is the A3 Argus hand-staging pattern (hdl/argus +
behavioral_mp_argus), productized. Python 3.6 compatible.
"""

import json
import os
import shutil
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)                    # platform/common/
REPO = os.path.dirname(os.path.dirname(PC_ROOT))    # vestarv/
RISCV_TEST = os.path.join(REPO, 'xcelium', 'riscv_test')
BASE_CELL_LIST = os.path.join(RISCV_TEST, 'behavioral_mp', 'cell_list_behavioral.txt')
TEMPLATE = os.path.join(PC_ROOT, 'verify', 'xrun_parallel.template.sh')
RESOLVED = os.path.join(PC_ROOT, 'config', 'ChipConfig.resolved.json')

# ---------------------------------------------------------------------------
# Test catalog -- the canonical behavioral_mp regression list (order kept),
# each entry tagged with the config knobs it needs:
#   tiles      needs numHarts >= 2 (sh protocol: tiles launched via the
#              bootrom msip loader)
#   atomics    isa.atomics (rv32ua; LR/SC / AMO instructions)
#   mul/div    isa.mul / isa.div
#   compressed isa.compressed
#   bitmanip   isa.bitmanip (Zba/Zbb/Zbc/Zbs)
#   npu        peripherals.npu (shnpu is CASTALIA ONLY -- no NPU, no test)
#   i2c1/uart1/spi1/timer1  the G1a/G1b droppable second instances (shi2c,
#              shperiph, shlock and shtimer exercise them by name)
# The ext* probes are ADAPTIVE (misa-driven; double as the stripped-build trap
# controls) and run on every configuration.
# smoke=True marks the ~26-test smoke subset `make verify` runs by default.
# ---------------------------------------------------------------------------
T = lambda name, tags='', smoke=False: (name, set(tags.split()) if tags else set(), smoke)

CATALOG = [
    T('rv32ui-p-simple', '', True),
    T('rv32ui-p-shmem', '', True),
    T('rv32ui-p-shmem_mp', 'tiles', True),
    T('rv32ui-p-shboot', 'tiles', True),
    T('rv32ui-p-shwfi', 'tiles', True),
    T('rv32ui-p-shclint', '', True),
    T('rv32ui-p-irqctx', ''),
    T('rv32ui-p-shuart', 'tiles', True),
    T('rv32ui-p-shirq', 'tiles', True),
    T('rv32ui-p-shtimer', 'tiles timer1', True),
    T('rv32ui-p-shperiph', 'tiles spi1 uart1', True),
    T('rv32ui-p-shi2c', 'tiles i2c1', True),
    T('rv32ui-p-shnpu', 'tiles npu', True),
    T('rv32ui-p-shmutex', 'tiles', True),
    T('rv32ui-p-shexec', 'tiles', True),
    T('rv32ui-p-shpwr', 'tiles', True),
    # digperiphs #6: shdma proves DMA0 inside the full MCU. DMA0 exists ONLY in
    # dma-enabled configs (castalia_dma NCH=2, wound NCH=4) -> tag 'dma' gates it
    # into ONLY those verify runs (filtered out of the default/non-dma configs).
    # Hart-0 directed (tiles parked), so no 'tiles' tag needed.
    T('rv32ui-p-shdma', 'dma', True),
    # digperiphs (EVFAB) Stage 5: shevfab is THE flagship event-fabric smoke --
    # TIMER0 compare0 (EV4) -> EVFAB0 CH0 -> DMA0 CH0 GO (T0) -> DMA writes
    # UART0 TX through the arbiter -> DMA0_DONE (vector 118) -> meip -> wake,
    # with hart 0 in `extinguish` for the whole chain. Needs BOTH the fabric
    # and the DMA instantiated, so it is tagged 'eventFabric dma' and appears
    # ONLY in configs carrying both (config/castalia_evfab.json today); TIMER0
    # and UART0 are unconditional. Hart-0 directed (tiles parked) -> no 'tiles'.
    T('rv32ui-p-shevfab', 'eventFabric dma', True),
    # digperiphs Stage E firmware smoke companions (wound-config additions).
    # Each is single-hart directed (hart 0; tiles parked) and hardcodes its
    # peripheral's FROZEN library-tail vectors (A5 GLOBAL VECTOR RULE): RTC0=114,
    # PWM0=115/116, OW0=117, DMA0=118/119. Gated by the peripheral knob so they
    # appear ONLY where that peripheral is instantiated (the single-peripheral
    # proof configs + wound) and never on plain Castalia (where the slot decodes
    # to zero and the vectors are RSVD).
    T('rv32ui-p-wrtc', 'rtc', True),
    T('rv32ui-p-wpwm', 'pwm', True),
    T('rv32ui-p-wow', 'onewire', True),
    T('rv32ui-p-wdma', 'dma', True),
    # digperiphs (I2CT): wi2ct proves I2CT0 (hardware-autonomous I2C target) inside
    # the full MCU via an I2C0-as-host loopback on the shared SDA0/SCL0 pads; it
    # hardcodes the FROZEN vectors 122 (I2CT0_AE) / 123 (I2CT0_DATA). Gated by the
    # 'i2ctarget' knob so it appears ONLY where I2CT0 is instantiated. The test .S is
    # written by a later stage -- this CATALOG row is inert at make-chip time (tags only
    # matter when `make verify` selects/stages tests) and tolerates a not-yet-built test.
    T('rv32ui-p-wi2ct', 'i2ctarget', True),
    # digperiphs (TRNG): wtrng proves TRNG0 (ring-oscillator entropy harvest engine)
    # inside the full MCU -- register resets, the DR read-CONSUME contract, two
    # successive words (LFSR-stub movement), and the combined data-ready/health-
    # alarm IRQ (vector 121) through the real meip path. Gated by the 'trng' knob
    # so it appears ONLY where TRNG0 is instantiated (castalia_trng.json + wound).
    T('rv32ui-p-wtrng', 'trng', True),
    # digperiphs P4.1 (NPU CONV1D, S6): wnpuconv proves NPU MODE=1 (conv) inside
    # the full MCU at the MCU/silicon generics (Q0.24 in / Q7.24 weight+acc+out) --
    # NPUCFG1/2 config + 4-bit MabMmrA readback smoke, an exact Q7.24 output check
    # (K=4 Cin=2 Cout=2 Lout=4 S=1 D=1 BEN=1), and the vector-120 think-done IRQ
    # through the real meip path (same idiom as shnpu.S's IRQ leg). Hart-0 directed
    # (tiles parked), so no 'tiles' tag; gated by 'npu' so NPU-less configs (Argus)
    # drop it, identically to shnpu.
    T('rv32ui-p-wnpuconv', 'npu', True),
    # digperiphs P4.2 (NPU XNOR/popcount, S5): wxnpu proves NPU MODE=2 (xnor)
    # inside the full MCU -- NPUCFG1/2 reinterpreted as THRESH/K, K=40 with
    # ADVERSARIAL tail garbage staged in the partial last word (proven
    # load-bearing: an unmasked-tail DUT would flip 2 of 4 neurons -- see
    # verification/npu/gen_wxnpu_golden.py), exact +-1.0 Q7.24 output check,
    # and the same vector-120 think-done IRQ leg wnpuconv.S/shnpu.S take.
    # Hart-0 directed (tiles parked), so no 'tiles' tag; gated by 'npu' so
    # NPU-less configs (Argus) drop it, identically to shnpu/wnpuconv.
    T('rv32ui-p-wxnpu', 'npu', True),
    # digperiphs P4.3 (NPU GEMM, S5): wgemm proves NPU MODE=3 (GEMM) inside the
    # full MCU -- NPUCFG1[7:0] reinterpreted as M-1, two CHAINED THINKs (layer 1
    # AEN=1 sigmoid so its row-major Q0.24 C feeds layer 2's A in place at the
    # same staging-RAM words, the D2 zero-repack proof), exact Q7.24/Q0.24
    # output checks from the validated golden model (verification/npu/
    # gen_wgemm_golden.py), and the same vector-120 think-done IRQ leg
    # shnpu.S/wnpuconv.S/wxnpu.S take. Hart-0 directed (tiles parked), so no
    # 'tiles' tag; gated by 'npu' so NPU-less configs (Argus) drop it,
    # identically to shnpu/wnpuconv/wxnpu.
    T('rv32ui-p-wgemm', 'npu', True),
    # digperiphs P4.4 (NPU ACTF, S5): wactf proves the activation mux inside
    # the full MCU -- a 7-THINK MLP sweep (sigmoid/ReLU/tanh/clamp/exp/
    # reserved-as-sigmoid/AEN-0-passthrough) with exact 32-bit word checks
    # from the validated golden (verification/npu/gen_wactf_golden.py) and
    # the vector-120 think-done IRQ leg. Hart-0 directed, gated by 'npu'
    # (Argus drops it), identically to the other four NPU smokes.
    T('rv32ui-p-wactf', 'npu', True),
    T('rv32ui-p-afsel', '', True),
    T('rv32ui-p-afselv2', 'spi1', True),
    T('rv32ua-p-shspin', 'tiles atomics', True),
    T('rv32ua-p-shlock', 'tiles atomics uart1', True),
    T('rv32ua-p-shamo', 'tiles atomics', True),
    T('rv32ua-p-amoadd_w', 'atomics'),
    T('rv32ua-p-amoand_w', 'atomics'),
    T('rv32ua-p-amomax_w', 'atomics'),
    T('rv32ua-p-shcount', 'tiles atomics', True),
    T('rv32ua-p-amomaxu_w', 'atomics'),
    T('rv32ua-p-amomin_w', 'atomics'),
    T('rv32ua-p-amominu_w', 'atomics'),
    T('rv32ua-p-amoswap_w', 'atomics'),
    T('rv32ua-p-amoxor_w', 'atomics'),
    T('rv32ua-p-amoor_w', 'atomics'),
    T('rv32ua-p-shlrsc', 'tiles atomics', True),
    T('rv32ua-p-lrsc', 'atomics'),
    T('rv32ui-p-add', '', True),
    T('rv32ui-p-lb'), T('rv32ui-p-lh'),
    T('rv32ui-p-lw', '', True),
    T('rv32ui-p-lbu'), T('rv32ui-p-lhu'),
    T('rv32ui-p-addi'), T('rv32ui-p-slli'), T('rv32ui-p-slti'),
    T('rv32ui-p-sltiu'), T('rv32ui-p-srli'), T('rv32ui-p-srai'),
    T('rv32ui-p-ori'), T('rv32ui-p-andi'), T('rv32ui-p-auipc'),
    T('rv32ui-p-sb'), T('rv32ui-p-sh'),
    T('rv32ui-p-sw', '', True),
    T('rv32ui-p-sub'), T('rv32ui-p-sll'), T('rv32ui-p-slt'),
    T('rv32ui-p-sltu'), T('rv32ui-p-xor'), T('rv32ui-p-srl'),
    T('rv32ui-p-sra'), T('rv32ui-p-or'), T('rv32ui-p-and'),
    T('rv32ui-p-lui'), T('rv32ui-p-beq'), T('rv32ui-p-bne'),
    T('rv32ui-p-blt'), T('rv32ui-p-bge'), T('rv32ui-p-bltu'),
    T('rv32ui-p-bgeu'), T('rv32ui-p-jalr'), T('rv32ui-p-jal'),
    # rv32um -- multiplication/division
    T('rv32um-p-mulhsu', 'mul'), T('rv32um-p-mulhu', 'mul'),
    T('rv32um-p-divu', 'div'), T('rv32um-p-mulh', 'mul'),
    T('rv32um-p-remu', 'div'), T('rv32um-p-div', 'div'),
    T('rv32um-p-mul', 'mul', True), T('rv32um-p-rem', 'div'),
    # rv32uc -- compressed (C extension)
    T('rv32uc-p-rvc', 'compressed', True),
    # rv32uzba/zbb/zbc/zbs -- bitmanip
    T('rv32uzba-p-sh1add', 'bitmanip'), T('rv32uzba-p-sh2add', 'bitmanip'),
    T('rv32uzba-p-sh3add', 'bitmanip'),
    T('rv32uzbb-p-sext_b', 'bitmanip'), T('rv32uzbb-p-sext_h', 'bitmanip'),
    T('rv32uzbb-p-zext_h', 'bitmanip'), T('rv32uzbb-p-orc_b', 'bitmanip'),
    T('rv32uzbb-p-andn', 'bitmanip'), T('rv32uzbb-p-cpop', 'bitmanip'),
    T('rv32uzbb-p-maxu', 'bitmanip'), T('rv32uzbb-p-minu', 'bitmanip'),
    T('rv32uzbb-p-rev8', 'bitmanip'), T('rv32uzbb-p-rori', 'bitmanip'),
    T('rv32uzbb-p-xnor', 'bitmanip'), T('rv32uzbb-p-clz', 'bitmanip'),
    T('rv32uzbb-p-ctz', 'bitmanip'), T('rv32uzbb-p-max', 'bitmanip'),
    T('rv32uzbb-p-min', 'bitmanip'), T('rv32uzbb-p-orn', 'bitmanip'),
    T('rv32uzbb-p-rol', 'bitmanip'), T('rv32uzbb-p-ror', 'bitmanip'),
    T('rv32uzbc-p-clmulh', 'bitmanip'), T('rv32uzbc-p-clmulr', 'bitmanip'),
    T('rv32uzbc-p-clmul', 'bitmanip'),
    T('rv32uzbs-p-bclri', 'bitmanip'), T('rv32uzbs-p-bexti', 'bitmanip'),
    T('rv32uzbs-p-binvi', 'bitmanip'), T('rv32uzbs-p-bseti', 'bitmanip'),
    T('rv32uzbs-p-bclr', 'bitmanip'), T('rv32uzbs-p-bext', 'bitmanip'),
    T('rv32uzbs-p-binv', 'bitmanip'), T('rv32uzbs-p-bset', 'bitmanip'),
    # core-features: misa + per-extension ADAPTIVE probes (pass on any build)
    T('rv32ua-p-extprobe'), T('rv32ua-p-extmul'), T('rv32ua-p-extdiv'),
    T('rv32ua-p-extamo'), T('rv32ua-p-extrvc'), T('rv32ua-p-extzb'),
]


def padded_rcf(name):
    """x-pad to the fixed 22-char rcf filename of the TEST_FILE contract."""
    fn = name + '.rcf'
    if len(fn) > 22:
        raise SystemExit('test filename longer than the 22-char contract: ' + fn)
    return 'x' * (22 - len(fn)) + fn


def rcf_mapping(nharts):
    """(3-char link name under xcelium/riscv_test/, dest dir under
    verification/isa/) for an image set built at this NHARTS. rcf/rca are the
    pre-existing Castalia/Argus sets -- reuse, never rebuild their symlinks."""
    if nharts == 4:
        return 'rcf', 'rcf'
    if nharts == 18:
        return 'rca', 'rcf_argus'
    return 'r%02d' % nharts, 'rcf_n%02d' % nharts


def config_tags(cfg):
    """The tag set this configuration satisfies."""
    tags = set()
    isa = cfg.get('isa', {})
    for k in ('mul', 'div', 'atomics', 'compressed', 'bitmanip'):
        if isa.get(k):
            tags.add(k)
    if cfg.get('peripherals', {}).get('npu'):
        tags.add('npu')
    if cfg.get('peripherals', {}).get('i2c1', True):
        tags.add('i2c1')    # G1a: shi2c claims both I2C instances -- gate it
    # G1b droppable second instances. shperiph's claim-based roles exercise
    # SPI1 AND UART1; shtimer's role 1 is the TIMER1 dance; shlock's lock
    # sessions TX on UART1 (kickoff-sanctioned: gate the test when its
    # peripheral is absent -- shuart/afsel survive on UART0/TIMER0 only).
    for knob in ('uart1', 'spi1', 'timer1'):
        if cfg.get('peripherals', {}).get(knob, True):
            tags.add(knob)
    # digperiphs #6: DMA0 is a config-gated ADDED instance (default off). Its
    # DMA.vhd is compiled only when the config enables it (the NPU.vhd pattern);
    # no sh-test tags change (shdma.S is a follow-up).
    if cfg.get('peripherals', {}).get('dma'):
        tags.add('dma')
    # digperiphs (TRNG): TRNG0 is a config-gated ADDED instance (default off), same
    # shape as DMA0. TrngRoEnsemble_sim.vhd + TRNG.vhd are compiled only when the
    # config enables it (below). No sh-test tags change yet -- no shared-suite test
    # uses TRNG0 (this tag exists solely to drive the cell-list injection).
    if cfg.get('peripherals', {}).get('trng'):
        tags.add('trng')
    # digperiphs (EVFAB): EVFAB0 is a config-gated ADDED instance (default off),
    # same shape as DMA0/TRNG0 -- but EVFAB.vhd is UNCONDITIONALLY in the base
    # cell list (it needs no config-gated MemoryMap constants), so this tag
    # drives ONLY test selection: shevfab.S touches 0x6B00 and the DMA task
    # port, so it must never be staged into a fabric-less configuration.
    if cfg.get('peripherals', {}).get('eventFabric'):
        tags.add('eventFabric')
    # digperiphs Stage E: firmware smoke companions gated by their peripheral
    # knob (wrtc/wpwm/wow join only the config(s) that instantiate the block).
    for knob in ('rtc', 'pwm', 'onewire', 'i2ctarget'):
        if cfg.get('peripherals', {}).get(knob):
            tags.add(knob)
    if int(cfg['numHarts']) >= 2:
        tags.add('tiles')
    return tags


def main():
    if not os.path.isfile(RESOLVED):
        raise SystemExit('config/ChipConfig.resolved.json not found -- run make generate first')
    with open(RESOLVED) as f:
        cfg = json.load(f)

    chip = cfg['chipName'].strip().lower().replace(' ', '_') or 'chip'
    nharts = int(cfg['numHarts'])
    have = config_tags(cfg)
    link, dest = rcf_mapping(nharts)

    sel = [(name, smoke) for (name, need, smoke) in CATALOG if need <= have]
    smoke_sel = [name for (name, smoke) in sel if smoke]
    rel = lambda name: '../%s/%s' % (link, padded_rcf(name))

    stage = os.path.join(RISCV_TEST, 'verify_' + chip)
    # fresh hdl/ + wrappers/ (stale wrappers from another config linger
    # harmlessly, but a stale staged MCU.vhd would silently test old RTL)
    for sub in ('hdl', 'wrappers'):
        d = os.path.join(stage, sub)
        if os.path.isdir(d):
            shutil.rmtree(d)
    os.makedirs(os.path.join(stage, 'hdl'))

    # --- staged RTL: the generated MCU + MemoryMap + testbench --------------
    out_hdl = os.path.join(PC_ROOT, 'out', 'hdl')
    for fn in ('MCU.vhd', 'MemoryMap.vhd', 'riscv_tb.vhd'):
        src = os.path.join(out_hdl, fn)
        if not os.path.isfile(src):
            raise SystemExit('missing %s -- run make generate first' % src)
        shutil.copy(src, os.path.join(stage, 'hdl', fn))

    # --- cell list: behavioral_mp's, with the generated files swapped -------
    if not os.path.isfile(BASE_CELL_LIST):
        raise SystemExit('base cell list missing: %s (tracked in git -- checkout?)' % BASE_CELL_LIST)
    swaps = {
        'hdl/common/MemoryMap.vhd': 'hdl/MemoryMap.vhd',
        'hdl/common/MCU.vhd': 'hdl/MCU.vhd',
        'hdl/common/tb/riscv_tb.vhd': 'hdl/riscv_tb.vhd',
    }
    seen = set()
    lines = []
    dma_seen = False
    trng_seen = False
    crc16_idx = None
    uart0_idx = None
    with open(BASE_CELL_LIST) as f:
        for raw in f:
            p = raw.strip()
            if not p:
                continue
            swapped = False
            for suffix, repl in swaps.items():
                if p.endswith(suffix):
                    lines.append(repl)
                    seen.add(suffix)
                    swapped = True
                    break
            if swapped:
                continue
            if p.endswith('periph/NPU.vhd') and 'npu' not in have:
                continue    # NPU.vhd needs the MmrAddrNPU* constants -- NPU-less
            # digperiphs #6: DMA.vhd is compiled only when the config enables the
            # DMA (the NPU.vhd gate pattern). It depends on CRC16.vhd (already in the
            # base list, before the periph block); if the base list ever carries
            # DMA.vhd it is passed through when dma is on and dropped otherwise.
            if p.endswith('periph/DMA.vhd'):
                if 'dma' not in have:
                    continue    # DMA off -> MCU.vhd has no dma0 instance
                dma_seen = True
            # digperiphs (TRNG): TrngRoEnsemble_sim.vhd + TRNG.vhd are compiled only
            # when the config enables TRNG (the NPU.vhd/DMA.vhd gate pattern). The
            # RTL ensemble file (TrngRoEnsemble.vhd, the genus/gate-only `rtl` arch)
            # must NEVER be referenced here -- if the base list ever carries it, drop
            # it unconditionally (behavioral flows compile the `sim` arch only, D6).
            if p.endswith('periph/TrngRoEnsemble.vhd'):
                continue    # the rtl (real-ring) architecture NEVER enters verify staging
            if p.endswith('periph/TrngRoEnsemble_sim.vhd') or p.endswith('periph/TRNG.vhd'):
                if 'trng' not in have:
                    continue    # TRNG off -> MCU.vhd has no trng0/u_ro instance
                trng_seen = True
            if p.endswith('commune/CRC16.vhd'):
                crc16_idx = len(lines)
            if p.endswith('periph/UART.vhd') and uart0_idx is None:
                uart0_idx = len(lines)
            lines.append(p)  # common cells: same ../../../ depth as behavioral_mp
    if len(seen) != 3:
        raise SystemExit('cell list swap points not all found in %s: got %s'
                         % (BASE_CELL_LIST, sorted(seen)))
    # digperiphs (TRNG): inject TrngRoEnsemble_sim.vhd then TRNG.vhd (dependency
    # order -- TRNG.vhd instantiates TrngRoEnsemble as a component) when the config
    # enables TRNG but the base list lacks them. Anchored just before UART.vhd (the
    # rest of the digperiphs periph family -- RTC/PWM/OneWire/I2CTarget -- already
    # sits there in the base list); NEVER TrngRoEnsemble.vhd (the rtl arch, D6). Done
    # BEFORE the DMA injection below: uart0_idx/crc16_idx were both captured against
    # the ORIGINAL (pre-insertion) `lines`, and uart0_idx > crc16_idx in that base
    # list, so inserting at the LATER index first keeps the EARLIER crc16_idx valid
    # for the DMA insertion that follows (inserting in the other order would shift
    # uart0_idx out from under this block).
    if 'trng' in have and not trng_seen:
        sim_cell = '../../../hdl/common/periph/TrngRoEnsemble_sim.vhd'
        trng_cell = '../../../hdl/common/periph/TRNG.vhd'
        if uart0_idx is None:
            raise SystemExit('TRNG config but periph/UART.vhd not in %s (no anchor to inject before)'
                             % BASE_CELL_LIST)
        lines.insert(uart0_idx, trng_cell)
        lines.insert(uart0_idx, sim_cell)
    # digperiphs #6: inject DMA.vhd (after CRC16.vhd, its only dependency, and well
    # before MCU.vhd) when the config enables the DMA but the base list lacks it.
    if 'dma' in have and not dma_seen:
        dma_cell = '../../../hdl/common/periph/DMA.vhd'
        if crc16_idx is None:
            raise SystemExit('DMA config but commune/CRC16.vhd not in %s (DMA.vhd needs it)'
                             % BASE_CELL_LIST)
        lines.insert(crc16_idx + 1, dma_cell)
    with open(os.path.join(stage, 'cell_list_behavioral.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')

    # --- runner script from the template -------------------------------------
    with open(TEMPLATE) as f:
        tpl = f.read()
    test_lines = '\n'.join('    "%s"' % rel(name) for (name, _s) in sel)
    script = tpl.replace('@CHIP@', cfg['chipName']).replace('@TEST_FILES@', test_lines)
    runner = os.path.join(stage, 'xrun_parallel.sh')
    with open(runner, 'w') as f:
        f.write(script)
    os.chmod(runner, 0o755)

    with open(os.path.join(stage, 'smoke.txt'), 'w') as f:
        f.write('# GENERATED smoke subset for %s (make verify) -- %d test(s)\n'
                % (cfg['chipName'], len(smoke_sel)))
        for name in smoke_sel:
            f.write(rel(name) + '\n')

    with open(os.path.join(stage, 'batch_run.tcl'), 'w') as f:
        f.write('source ../../disable_x_warnings.tcl\nrun\nexit\n')

    with open(os.path.join(stage, 'README.generated'), 'w') as f:
        f.write('GENERATED by platform/common `make verify` (verify_stage.py).\n'
                'Config: %s  numHarts=%d  npu=%s\n'
                'Everything here is regenerable -- do not hand-edit.\n'
                % (cfg['chipName'], nharts, 'npu' in have))

    # --- the 3-char rcf symlink ----------------------------------------------
    link_path = os.path.join(RISCV_TEST, link)
    target = os.path.join('..', '..', 'verification', 'isa', dest)
    if os.path.islink(link_path):
        if os.readlink(link_path) != target:
            raise SystemExit('symlink %s points at %s, expected %s -- refusing to retarget'
                             % (link_path, os.readlink(link_path), target))
    elif os.path.exists(link_path):
        raise SystemExit('%s exists and is not a symlink' % link_path)
    else:
        os.symlink(target, link_path)

    # --- hand off to verify.sh ------------------------------------------------
    print('CHIP=%s' % cfg['chipName'])
    print('STAGE_DIR=%s' % stage)
    print('NHARTS=%d' % nharts)
    print('RCF_LINK=%s' % link)
    print('RCF_DEST=%s' % os.path.join(REPO, 'verification', 'isa', dest))
    print('NTESTS_FULL=%d' % len(sel))
    print('NTESTS_SMOKE=%d' % len(smoke_sel))


if __name__ == '__main__':
    main()
