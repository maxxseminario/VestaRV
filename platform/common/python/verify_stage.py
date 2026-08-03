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
#   cqAfeStubs peripherals.cqAfeStubs (shafe drives the four AFE stubs + EIS)
#   zicond zcb zimop zihint zihpm zawrs zabha zacas zicboz zcmp zcmt
#   zbkb zbkc zbkx zkn zfinx          the 16 X-series isa.* knobs   (K2/G1)
#   trapCsr umode pmp                 the 3 P-series priv.* knobs   (K2/G1)
# The ext* probes are ADAPTIVE (misa-driven; double as the stripped-build trap
# controls) and run on every configuration.
#
# K2 (2026-08-03) — WHICH ROWS CARRY A KNOB TAG, AND WHY IT IS NOT "every row
# that mentions the knob". Two populations, and conflating them is exactly the
# defect this CATALOG had:
#   * BOTH-POLARITY tests (`sh*`, `ext*`, `zbk`) dispatch at BUILD TIME on
#     `#ifdef CORE_ENABLE_<K>` and carry a real `#else` arm. They must run on
#     EVERY configuration -- the OFF arm is the trap/no-op control and the ON
#     arm is the functional check -- so they carry NO knob tag. Which arm gets
#     compiled is decided by the image build's `-DCORE_ENABLE_*`, not by
#     selection. All twenty of them are in the standing 136-test suite and were
#     absent from this CATALOG entirely until K2.
#   * ON-POLARITY-ONLY suites (rv32uzicond/zabha/zacas/zkne/zknd/zknh/zf) emit
#     encodings that take an illegal-instruction trap on an OFF build. They have
#     no OFF arm at all, so each is tagged with the knob that makes it legal and
#     appears ONLY in a knobs-on row. THIS is what "selection is evidence"
#     means: a zabha row that does not select rv32uzabha-p-* has not been shown
#     to exercise Zabha.
# rv32ua-suite convention, unchanged: every rv32ua row except the adaptive
# `ext*` family carries `atomics` (the whole group builds -march=rv32imac and
# is dropped wholesale in an atomics-off world; R-DK1 excludes atomics=false
# from the supported set in writing).
# smoke=True marks the smoke subset `make verify` runs by default (31 tests on
# the default Castalia config, 26 on Argus). The twenty both-polarity additions
# are deliberately smoke=False -- they join SUITE=full only, so the default
# smoke number does not move. Every ON-polarity row IS smoke=True: it appears
# only where its knob is on, and there it is the cheapest proof the knob is on
# (R-DK2's knobs-on canary).
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
    # K2: the compressed twin of shexec (C3 -- a 32-bit instruction whose two
    # halves live in different shared words). Needs C on; nothing else.
    T('rv32ui-p-shexecc', 'tiles compressed'),
    T('rv32ui-p-shpwr', 'tiles', True),
    # K2: the CQ AFE/EIS digital-stub test. The four AFE stubs at 0x4C00 and the
    # EIS engine at 0x7C00 exist only when peripherals.cqAfeStubs is true (the
    # Castalia golden master keeps them; a qspi config takes slot 12 instead).
    # `harts_le4` because the stub bank is FOUR instances at any numHarts while
    # the test addresses AFE0 + 0x40*h -- see config_tags.
    T('rv32ui-p-shafe', 'tiles cqAfeStubs harts_le4'),
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
    # K2: the X2/X3 both-polarity sh* block, in the standing runner's order.
    # Each has an ON arm (#ifdef CORE_ENABLE_<K>) and an OFF arm, so NO knob tag
    # -- see the population note above. shcboz/shcmp/shcmppush/shcmt are hart-0
    # directed (no MP_LAUNCH_* in the source), so they carry no `tiles` tag.
    T('rv32ua-p-shzabha', 'tiles atomics'),
    T('rv32ua-p-shzacas', 'tiles atomics'),
    T('rv32ua-p-shcaslr', 'tiles atomics'),
    T('rv32ua-p-shmixw', 'tiles atomics'),
    T('rv32ua-p-shcboz', 'atomics'),
    T('rv32ua-p-shcmp', 'atomics'),
    # shcmppush and shpause HARDCODE the N=4 CLINT layout and say so in their own
    # headers ("CLINT (NHARTS=4): ... mtime lo=0x5010; mtimecmp0 lo/hi =
    # 0x5020/0x5024" / "MTIME_LO 0x5010 // CLINT mtime lo (N=4)"). The layout is
    # N-parameterised -- MTIME = 0x5000 + roundup16(4*NHARTS) -- so at N=18 those
    # literals are msip[4]/msip[8], i.e. OTHER HARTS' software-interrupt
    # registers. Measured on Argus: shpause FAILS; shcmppush passes, which is
    # worse, because its mtip can never have armed. `harts_le4` is exactly the
    # condition under which 0x5010 IS mtime (4*N <= 16). extzawrs is the model
    # for how this should be written -- it derives MTIME_OFF from NHARTS -- and
    # porting these two is Argus-port debt, filed rather than silently tagged
    # away for good.
    T('rv32ua-p-shcmppush', 'atomics harts_le4'),
    T('rv32ua-p-shcmt', 'atomics'),
    T('rv32ua-p-shpause', 'tiles atomics harts_le4'),
    T('rv32ua-p-amoadd_w', 'atomics'),
    # K2: AMO address-aliasing directed test (hart-0, no build-time dispatch).
    T('rv32ua-p-amoalias', 'atomics'),
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
    T('rv32ui-p-sltu'), T('rv32ui-p-xor'),
    # K2: X3 scalar-crypto bit-manip probe. Dispatches on CORE_ENABLE_BITMANIP
    # and CORE_ENABLE_ZBK{B,C,X}/ZKN -- adaptive in every direction, no tag.
    T('rv32ui-p-zbk'),
    T('rv32ui-p-srl'),
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
    # K2: the X-series ext* probes, in the standing runner's order. extzihpm is
    # RUNTIME-adaptive (it dispatches on whether the counter moves, so one image
    # serves both polarities); the rest dispatch at build time on
    # CORE_ENABLE_<K> and carry an OFF arm. None is knob-tagged.
    T('rv32ua-p-extzihpm'), T('rv32ua-p-extzicond'), T('rv32ua-p-extzcb'),
    T('rv32ua-p-extzihint'), T('rv32ua-p-extzawrs'),
    T('rv32ua-p-shwrs', 'tiles atomics'),
    T('rv32ua-p-extzfinx'),

    # -----------------------------------------------------------------------
    # K2 (G1) -- THE ON-POLARITY-ONLY SUITES.
    # Seven suites that have existed in verification/isa/tests/ since the X
    # series and that NO runner has ever selected (each Makefrag says so in
    # those words: "NOT wired into the default (off) suite runner"). Every test
    # here emits an encoding that takes an illegal-instruction trap on a build
    # without its knob, so each row is tagged with that knob and is selected
    # ONLY by a knobs-on config -- which is the whole point: it is the
    # difference between a config that BOOTS with the knob on and a config that
    # has been shown to EXECUTE the knob's instructions.
    # These need their image group built (rv32uzicond, rv32uzabha, ...) and the
    # matching -DCORE_ENABLE_* in RISCV_GCC_OPTS; verify_stage prints GROUPS=
    # and DEFINES= for verify.sh so both follow the config automatically.
    # (K2 stages 1-2 emit those two lines; the image build that CONSUMES them is
    # the G3 commit -- until then a knobs-on row prints them and still uses the
    # default image set, which is loud rather than silent because the ON-only
    # images simply are not there.)
    # -----------------------------------------------------------------------
    T('rv32uzicond-p-cz', 'zicond', True),
    # Basenames renamed at K2 (amoops_b/amoops_h/amomis -> ops_b/ops_h/mis):
    # the old ones were 25/25/23 characters and could not fit the 22-char
    # padded TEST_FILE contract. See tests/rv32uzabha/Makefrag.
    T('rv32uzabha-p-ops_b', 'zabha atomics', True),
    T('rv32uzabha-p-ops_h', 'zabha atomics', True),
    T('rv32uzabha-p-mis', 'zabha atomics', True),
    T('rv32uzacas-p-casw', 'zacas atomics', True),
    # casbh is amocas.b/.h -- sub-word CAS needs Zabha ON as well (its Makefrag
    # says so); tagging it with both keeps a zacas-only row from selecting a
    # test whose encodings that row's RTL would trap.
    T('rv32uzacas-p-casbh', 'zacas zabha atomics', True),
    T('rv32uzkne-p-aes32e', 'zkn', True),
    T('rv32uzknd-p-aes32d', 'zkn', True),
    T('rv32uzknd-p-aeskat', 'zkn', True),
    T('rv32uzknh-p-sha256', 'zkn', True),
    T('rv32uzknh-p-sha512', 'zkn', True),
    T('rv32uzf-p-fadd', 'zfinx', True), T('rv32uzf-p-fdiv', 'zfinx', True),
    T('rv32uzf-p-fclass', 'zfinx', True), T('rv32uzf-p-fcmp', 'zfinx', True),
    T('rv32uzf-p-fcvt', 'zfinx', True), T('rv32uzf-p-fcvt_w', 'zfinx', True),
    T('rv32uzf-p-fmadd', 'zfinx', True), T('rv32uzf-p-fmin', 'zfinx', True),
    T('rv32uzf-p-dround', 'zfinx', True), T('rv32uzf-p-dsubnrm', 'zfinx', True),
    T('rv32uzf-p-dnan', 'zfinx', True), T('rv32uzf-p-dpmzero', 'zfinx', True),
    T('rv32uzf-p-dfcvttab', 'zfinx', True), T('rv32uzf-p-daccum', 'zfinx', True),
    T('rv32uzf-p-drdx0', 'zfinx', True), T('rv32uzf-p-dsgnj', 'zfinx', True),
]


def padded_rcf(name):
    """x-pad to the fixed 22-char rcf filename of the TEST_FILE contract."""
    fn = name + '.rcf'
    if len(fn) > 22:
        raise SystemExit('test filename longer than the 22-char contract: ' + fn)
    return 'x' * (22 - len(fn)) + fn


def rcf_mapping(nharts, defines=()):
    """(3-char link name under xcelium/riscv_test/, dest dir under
    verification/isa/) for an image set built at this NHARTS and this ON-knob
    polarity. rcf/rca are the pre-existing Castalia/Argus sets -- reuse, never
    rebuild their symlinks.

    K2/G3. The link name MUST be exactly 3 characters (the riscv_tb TEST_FILE
    generic is a fixed 29-char string), which is the whole reason the polarity
    cannot simply be spelled out in the path. So:

      defines EMPTY  -> today's mapping, unchanged, bit for bit. Every existing
                        flow, image set and stamp keeps working and no image is
                        rebuilt. This is the ONLY case any config had before K2.
      defines SET    -> link `k<XX>`, dir `rcf_k<XX>`, where XX is two hex
                        digits of a digest of the FULL identity (NHARTS + the
                        sorted -D list). 256 slots, 1:1 with the directory, so a
                        digest collision is a collision of BOTH and is caught by
                        the `.imgset` identity stored in the directory -- see
                        verify.sh. A silent collision would be the worst
                        possible failure here (two polarities sharing one image
                        set), so it is checked rather than made unlikely.
    """
    if not defines:
        if nharts == 4:
            return 'rcf', 'rcf'
        if nharts == 18:
            return 'rca', 'rcf_argus'
        return 'r%02d' % nharts, 'rcf_n%02d' % nharts
    tag = imgset_tag(nharts, defines)
    return 'k' + tag, 'rcf_k' + tag


def imgset_identity(nharts, defines):
    """The EXACT string that identifies an image set's polarity. Stored in the
    set's `.imgset` stamp and compared on every reuse: this is the record the
    K0 probes found missing entirely (`rcf/`'s 260 images were rebuildable
    'only if the exact RISCV_GCC_OPTS polarity is known, which is nowhere
    recorded')."""
    return 'NHARTS=%d DEFINES=%s' % (nharts, ' '.join(defines) if defines else '(none)')


def imgset_tag(nharts, defines):
    """Two hex digits naming the polarity, from a digest of its identity.
    hashlib, not hash(): Python's str hash is randomised per process, so hash()
    would give a DIFFERENT directory on every run."""
    import hashlib
    h = hashlib.sha1(imgset_identity(nharts, defines).encode('utf-8')).hexdigest()
    return h[:2]


# K2 (G1/G3): the schema keys that reach a `vesta` feature generic and that a
# test can dispatch on at build time. Order is the CORE_ENABLE_* emission order
# of ChipGenerator.py; it is also the order of the -DCORE_ENABLE_* list, so an
# image-set identity is stable across runs.
ISA_KNOBS = (
    'mul', 'div', 'atomics', 'compressed', 'bitmanip',
    'zicond', 'zcb', 'zimop', 'zihint', 'zihpm', 'zawrs',
    'zabha', 'zacas',
    'zicboz', 'zcmp', 'zcmt', 'zbkb', 'zbkc', 'zbkx', 'zkn',
    'zfinx',
)
PRIV_KNOBS = ('trapCsr', 'umode', 'pmp')

# The five base-ISA knobs default TRUE and the twenty X/P knobs default FALSE.
# Only the ON direction needs a -D on the image build: the tests' `#ifdef
# CORE_ENABLE_<K>` idiom is presence-based (generate.py emits the #define only
# when the generic is true), so the ON set is exactly the -D set.
#
# THE FIVE BASE KNOBS ARE DELIBERATELY EXCLUDED, and the reason is measured, not
# assumed. Sweeping every test source and the env for a real preprocessor
# conditional (not a comment) on a base knob --
#   grep -rnE '^\s*#\s*(if|ifdef|ifndef|elif).*CORE_ENABLE_(MUL|DIV|ATOMICS|COMPRESSED|BITMANIP)\b'
# -- returns exactly ONE hit in the whole tree: `rv32ua/extzimop.S:93`, whose
# `#ifdef CORE_ENABLE_COMPRESSED` guards a two-instruction Zcmop tail INSIDE its
# already-Zimop-gated ON arm. The misa-adaptive probes (extmul/extdiv/extamo/
# extrvc/extzb) dispatch at RUNTIME and need no define at all, and zbk.S names
# CORE_ENABLE_BITMANIP only in prose.
# Admitting COMPRESSED to this set would therefore buy that one tail -- in a
# test no runner selects today (it is in neither the standing 136 nor this
# CATALOG) -- at the price of putting `-DCORE_ENABLE_COMPRESSED` on EVERY image
# of EVERY config (compressed defaults true), i.e. rebuilding the entire
# canonical 260-image set at a new polarity and re-pinning the lockstep gate.
# Named and deferred, not overlooked: if extzimop is ever wired in, it needs
# either that decision taken deliberately or its own explicit -D.
DEFINE_KNOBS = ISA_KNOBS[5:] + PRIV_KNOBS


def image_defines(cfg):
    """The -DCORE_ENABLE_* list this configuration's images must be built with.

    K2/G3. This is the SOFTWARE half of the switch whose HARDWARE half is the
    staged MemoryMap.vhd's `CORE_ENABLE_<K> : boolean := true`. The ISA
    Makefile deliberately refuses to auto-derive these from the gitignored
    make-chip header (verification/isa/Makefile: "a stale header would silently
    compile the ON arm against OFF RTL and hang the suite") and that refusal
    STAYS -- what K2 changes is that the explicit pairing is now produced from
    ONE resolved config and CHECKED, instead of typed by hand.
    """
    isa = cfg.get('isa', {})
    priv = cfg.get('priv', {})
    out = []
    for k in DEFINE_KNOBS:
        on = priv.get(k) if k in PRIV_KNOBS else isa.get(k)
        if on:
            out.append('-DCORE_ENABLE_' + k.upper())
    return out


def memorymap_on_knobs(path):
    """The CORE_ENABLE_* knobs a MemoryMap.vhd actually declares TRUE.

    K2/G3, the HARDWARE half of the polarity pair. The K0 harness probe's §3.4
    is the reason this is a one-file read: every knob that changes core
    behaviour reaches the RTL as a VHDL constant in MemoryMap.vhd -- NOT as a
    generic -- so a per-config simulation needs exactly one substituted file,
    and that file is the whole truth about the build's polarity.

    Read from the STAGED file, never recomputed from the config, so that a
    generator that failed to emit a constant is caught rather than agreed with.
    Deliberately literal: `constant CORE_ENABLE_<K> : boolean := true;` with any
    spacing. VHDL is case-insensitive, hence the lowercasing.
    """
    import re
    pat = re.compile(r'constant\s+CORE_ENABLE_([A-Z0-9_]+)\s*:\s*boolean\s*:=\s*(\w+)',
                     re.IGNORECASE)
    on = set()
    with open(path) as f:
        for line in f:
            line = line.split('--', 1)[0]        # strip VHDL comments
            m = pat.search(line)
            if m and m.group(2).lower() == 'true':
                on.add(m.group(1).upper())
    # Only the knobs a test can dispatch on at build time are comparable; the
    # five base-ISA constants are true in almost every build and no test
    # #ifdefs on them (see DEFINE_KNOBS).
    return sorted(on & set(k.upper() for k in DEFINE_KNOBS))


def test_groups(names):
    """The verification/isa test groups the selected tests live in, in the
    order build_mp_images.sh wants them (base groups first, ON-polarity suites
    after -- the extprobe_template build-order trap: base images FIRST, then
    the ON suites on top)."""
    base = ['rv32ui', 'rv32ua', 'rv32um', 'rv32uc',
            'rv32uzba', 'rv32uzbb', 'rv32uzbc', 'rv32uzbs']
    need = set(n.split('-p-')[0] for n in names)
    groups = [g for g in base if g in need]
    for g in sorted(need - set(base)):
        groups.append(g)
    return groups


def config_tags(cfg):
    """The tag set this configuration satisfies."""
    tags = set()
    isa = cfg.get('isa', {})
    for k in ('mul', 'div', 'atomics', 'compressed', 'bitmanip'):
        if isa.get(k):
            tags.add(k)
    # K2 (G1): the 16 X-series isa.* knobs and the 3 P-series priv.* knobs. A
    # tag appears iff the resolved config turns the knob ON, so a knob-tagged
    # row is selected only by a knobs-on config. Tag name == the schema key's
    # leaf (isa.zicboz -> 'zicboz', priv.trapCsr -> 'trapCsr').
    for k in ISA_KNOBS[5:]:
        if isa.get(k):
            tags.add(k)
    priv = cfg.get('priv', {})
    for k in PRIV_KNOBS:
        if priv.get(k):
            tags.add(k)
    # cqAfeStubs defaults TRUE (the Castalia golden master keeps the AFE/EIS
    # stubs); a qspi config sets it false and shafe must not be staged there.
    if cfg.get('peripherals', {}).get('cqAfeStubs', True):
        tags.add('cqAfeStubs')
    # K2: `harts_le4` is a STRUCTURAL bound, not a knob -- "this row's addresses
    # are only correct while 4*numHarts <= 16". Two independent reasons a test
    # needs it, both measured:
    #   * the AFE stub bank. mcu_vhd.py emits exactly FOUR afe_stub instances
    #     (afe0..afe3) whatever numHarts is -- the bank is NOT N-parameterised --
    #     while shafe.S addresses its own stub as `AFE0 + 0x40*h`. At h=4 that is
    #     0x4D00, which is GPIO3's slot, so shafe on an 18-hart config would not
    #     merely fail, it would write another peripheral.
    #   * the CLINT mtime/mtimecmp offset. MTIME sits at
    #     `0x5000 + roundup16(4*NHARTS)`, so the familiar 0x5010/0x5020 literals
    #     are mtime/mtimecmp ONLY at N<=4; at N=18 they are msip[4]/msip[8].
    #     shpause and shcmppush hardcode them (and say so in their headers).
    # Deliberately a numeric bound rather than `numHarts == 4`: the predicate
    # that is actually true is 4*N <= 16, and a hypothetical 2-hart config is
    # fine for both reasons.
    if int(cfg['numHarts']) <= 4:
        tags.add('harts_le4')
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
    defines = image_defines(cfg)
    link, dest = rcf_mapping(nharts, defines)

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
        # K2 TRUTH FIX. This message used to read "(tracked in git -- checkout?)"
        # and that was FALSE: `.gitignore:312`'s bare `xcelium/` covers this file,
        # so a fresh clone has never had it and `git checkout` cannot produce it.
        # A wrong rationale is worse than none -- the next reader trusts it.
        raise SystemExit(
            'base cell list missing: %s\n'
            '  This file is NOT tracked in git (.gitignore:312, the bare `xcelium/`\n'
            '  rule), so `git checkout` will not bring it back. Restore it from the\n'
            '  canonical copy instead:\n'
            '      /usr/bin/python3.6 tools/cosim/check_gate_files.py --restore'
            % BASE_CELL_LIST)
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
    # K2/G3: the image half of the configuration. GROUPS is what
    # build_mp_images.sh must build for THIS selection (the ON-polarity suites
    # are not in its default group list); DEFINES is the -DCORE_ENABLE_* set the
    # config's ON knobs require. Printed unconditionally so a reader of the
    # verify banner can see the exact polarity the images were asked for.
    print('GROUPS=%s' % ' '.join(test_groups(name for (name, _s) in sel)))
    print('DEFINES=%s' % ' '.join(defines))
    print('IMGSET=%s' % imgset_identity(nharts, defines))
    # The staged RTL's own ON-knob set, read back out of the file that was just
    # written rather than recomputed from the config. That is the point: the
    # polarity gate must compare the SOFTWARE side against what the HARDWARE
    # side actually says, so that a generator bug which fails to emit a
    # CORE_ENABLE_* constant is caught instead of being agreed with.
    print('RTL_ON=%s' % ' '.join(memorymap_on_knobs(
        os.path.join(stage, 'hdl', 'MemoryMap.vhd'))))


if __name__ == '__main__':
    main()
