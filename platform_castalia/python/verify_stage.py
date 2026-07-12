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

It never touches hdl/MCU/ or hdl/MCU_MP/ and never writes outside
xcelium/riscv_test/. Prints KEY=VALUE lines consumed by ../verify.sh.

This is the A3 Argus hand-staging pattern (hdl/MCU_ARGUS +
behavioral_mp_argus), productized. Python 3.6 compatible.
"""

import json
import os
import shutil
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)                    # platform_castalia/
REPO = os.path.dirname(PC_ROOT)                    # vestarv/
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
        'hdl/MCU_MP/MemoryMap.vhd': 'hdl/MemoryMap.vhd',
        'hdl/MCU_MP/MCU.vhd': 'hdl/MCU.vhd',
        'hdl/MCU_MP/tb/riscv_tb.vhd': 'hdl/riscv_tb.vhd',
    }
    seen = set()
    lines = []
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
            lines.append(p)  # common cells: same ../../../ depth as behavioral_mp
    if len(seen) != 3:
        raise SystemExit('cell list swap points not all found in %s: got %s'
                         % (BASE_CELL_LIST, sorted(seen)))
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
        f.write('GENERATED by platform_castalia `make verify` (verify_stage.py).\n'
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
