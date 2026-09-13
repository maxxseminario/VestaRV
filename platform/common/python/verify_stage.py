#!/usr/bin/env python3
"""VestaRV: stage the generated RTL into a self-contained Xcelium behavioral smoke flow.

Reads config/ChipConfig.resolved.json and writes ../xcelium/riscv_test/verify_<chipname>/
with the staged hdl, a cell list, a knob-filtered xrun_parallel.sh and smoke.txt. The rcf
symlink name must be exactly 3 characters: riscv_tb's TEST_FILE generic is a fixed 29-char
string. Never writes outside xcelium/riscv_test/. Prints KEY=VALUE for ../verify.sh.
"""

import json
import os
import shutil
import sys

HERE = os.path.abspath(os.path.dirname(__file__))
PC_ROOT = os.path.dirname(HERE)                    # platform/common/
REPO = os.path.dirname(os.path.dirname(PC_ROOT))    # vestarv/
RISCV_TEST = os.path.join(REPO, 'xcelium', 'riscv_test')
# Where image sets live. rcf_mapping() reads the `.imgset` stamps under here to
# probe past a slot collision.
ISA_ROOT = os.path.join(REPO, 'verification', 'isa')
BASE_CELL_LIST = os.path.join(RISCV_TEST, 'behavioral_mp', 'cell_list_behavioral.txt')
TEMPLATE = os.path.join(PC_ROOT, 'verify', 'xrun_parallel.template.sh')
# The record of the last generation. generate.py always writes out/config/ and refreshes
# the tracked config/ copy only for the default configuration, so a CONFIG= build is
# found here and never in config/.
RESOLVED = os.path.join(PC_ROOT, 'out', 'config', 'ChipConfig.resolved.json')
if not os.path.isfile(RESOLVED):
    RESOLVED = os.path.join(PC_ROOT, 'config', 'ChipConfig.resolved.json')

# (package file, the cell-list entry it must precede). Transcribed from
# rdl_vhdl.RTL_PACKAGES rather than imported, because this script runs under the
# host /usr/bin/python3 with no third-party path set up and rdl_vhdl's neighbours
# need the SystemRDL compiler. //platform/common:rdl_vhdl_pkg_test is what keeps
# the package set honest; a package missing from here costs an elaboration error
# in `make verify`, which is loud.
REGS_PACKAGES = (
    ('gpio_regs_pkg.vhd', 'periph/GPIO.vhd'),
    ('spi_regs_pkg.vhd', 'periph/SPI.vhd'),
    ('uart_regs_pkg.vhd', 'periph/UART.vhd'),
    ('i2c_regs_pkg.vhd', 'periph/I2C.vhd'),
    ('timer_regs_pkg.vhd', 'periph/TIMER.vhd'),
    ('system_regs_pkg.vhd', 'periph/SYSTEM.vhd'),
    ('npu_regs_pkg.vhd', 'periph/NPU.vhd'),
    ('qspi_regs_pkg.vhd', 'periph/QSPI.vhd'),
    ('i3c_regs_pkg.vhd', 'periph/I3C.vhd'),
    ('nfc_regs_pkg.vhd', 'periph/NFC.vhd'),
    ('rtc_regs_pkg.vhd', 'periph/RTC.vhd'),
    ('pwm_regs_pkg.vhd', 'periph/PWM.vhd'),
    ('onewire_regs_pkg.vhd', 'periph/OneWire.vhd'),
    ('dma_regs_pkg.vhd', 'periph/DMA.vhd'),
    ('i2ctarget_regs_pkg.vhd', 'periph/I2CTarget.vhd'),
    ('trng_regs_pkg.vhd', 'periph/TRNG.vhd'),
    ('evfab_regs_pkg.vhd', 'periph/EVFAB.vhd'),
    ('clint_regs_pkg.vhd', 'clint.vhd'),
    ('irq_router_regs_pkg.vhd', 'irq_router.vhd'),
    ('mutex_bank_regs_pkg.vhd', 'mutex_bank.vhd'),
    ('pwr_ctrl_regs_pkg.vhd', 'pwr_ctrl.vhd'),
    ('debug_module_regs_pkg.vhd', 'debug_module.vhd'),
)

# Test catalog: the canonical behavioral_mp regression list, order kept, each entry tagged
# with the config knobs it needs:
#   tiles      numHarts >= 2; tiles are launched through the bootrom msip loader
#   atomics    isa.atomics (rv32ua: LR/SC and AMO)
#   mul/div    isa.mul / isa.div
#   compressed isa.compressed
#   bitmanip   isa.bitmanip (Zba/Zbb/Zbc/Zbs)
#   npu        peripherals.npu
#   i2c1/uart1/spi1/timer1  the droppable second instances
#   cqAfeStubs peripherals.cqAfeStubs (shafe drives the four AFE stubs and EIS)
#   zicond zcb zimop zihint zihpm zawrs zabha zacas zicboz zcmp zcmt
#   zbkb zbkc zbkx zkn zfinx          the 16 X-series isa.* knobs
#   trapCsr umode pmp                 the 3 P-series priv.* knobs
# The ext* probes are adaptive, misa-driven, and double as the stripped-build trap controls,
# so they run on every configuration.
# Which rows carry a knob tag, and why it is not every row that mentions the knob:
#   * both-polarity tests (sh*, ext*, zbk) dispatch at build time on
#     #ifdef CORE_ENABLE_<K> and carry a real #else arm, so they must run on every
#     configuration, with the OFF arm the trap or no-op control and the ON arm the
#     functional check. They carry no knob tag; which arm is compiled is decided by the
#     image build's -DCORE_ENABLE_*, not by selection.
#   * on-polarity-only suites (rv32uzicond, zabha, zacas, zkne, zknd, zknh, zf) emit
#     encodings that take an illegal-instruction trap on an OFF build. They have no OFF arm,
#     so each is tagged with the knob that makes it legal and appears only in a knobs-on row.
#     A zabha row that does not select rv32uzabha-p-* has not been shown to exercise Zabha.
# Every rv32ua row except the adaptive ext* family carries `atomics`: the whole group builds
# -march=rv32imac and is dropped wholesale in an atomics-off world.
# smoke=True marks the subset `make verify` runs by default, 31 tests on the default
# configuration and 26 on Argus. The both-polarity additions are smoke=False and join
# SUITE=full only. Every on-polarity row is smoke=True: it appears only where its knob is on,
# and there it is the cheapest proof the knob is on.
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
    # `cqAfeStubs` keeps it off a configuration that frees slot 12, and
    # `harts_le4` keeps it off the five-hart chip.
    T('rv32ui-p-shafe', 'tiles cqAfeStubs harts_le4'),
    # CP3 (Castalia-Penta): shafe's SUCCESSOR at N>=5, REWRITTEN AND RESTORED at
    # CPR4. The CPR3 deferral (tag `orchLegacy`, which no config_tags() produces)
    # is retired: shorch.S no longer carries the CP2 shape (`MGMT = NHARTS-1`,
    # hart 4 as manager, hart 0 as a plain denied CHANNEL). Per CPR3/R2 the
    # orchestrator is hart 0, the four AFE sites belong to harts 1-4
    # (AFE0 + 0x40*(h-1)), MGMT_HART is never overridden again (entity default 0
    # is correct everywhere), EIS is hart-0-owned, and the NEGATIVE CONTROL
    # INVERTS: a TILE is the denied prober now, and hart 0 is the master that can
    # look. Still `cqAfeStubs`-gated -- the stub bank does not exist on
    # the tape-out configuration, which is why CPR4's `shtcm` (below) and not this
    # file is the tape-out-config orchestrator test.
    T('rv32ui-p-shorch', 'tiles cqAfeStubs orch', True),
    # CPR4/R6: the TCM-aperture test, and THE orchestrator row that survives onto
    # the tape-out configuration. It keys on `orch` alone because the five
    # read-only TCM windows at 0x20000 + 0x4000*h are the memory architecture of
    # an orchestrator chip (R4: not knob-gated), so they exist on every
    # orchestrator config -- unlike the AFE/EIS stubs shorch needs. smoke=True by the
    # R-DK2 knobs-on rule: this row appears ONLY where the orchestrator knob is
    # on, and there it is the cheapest proof that the apertures were built.
    T('rv32ui-p-shtcm', 'tiles orch', True),
    # shdma proves DMA0 inside the full MCU. DMA0 exists ONLY in
    # dma-enabled configs (castalia_dma NCH=2, wound NCH=4) -> tag 'dma' gates it
    # into ONLY those verify runs (filtered out of the default/non-dma configs).
    # Hart-0 directed (tiles parked), so no 'tiles' tag needed.
    T('rv32ui-p-shdma', 'dma', True),
    # shevfab is the flagship event-fabric smoke:
    # TIMER0 compare0 (EV4) -> EVFAB0 CH0 -> DMA0 CH0 GO (T0) -> DMA writes
    # UART0 TX through the arbiter -> DMA0_DONE (vector 118) -> meip -> wake,
    # with hart 0 in `extinguish` for the whole chain. Needs BOTH the fabric
    # and the DMA instantiated, so it is tagged 'eventFabric dma' and appears
    # ONLY in configs carrying both (config/castalia_evfab.json today); TIMER0
    # and UART0 are unconditional. Hart-0 directed (tiles parked) -> no 'tiles'.
    T('rv32ui-p-shevfab', 'eventFabric dma', True),
    # Firmware smoke companions (wound-config additions).
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
    # wi2ct proves I2CT0 (hardware-autonomous I2C target) inside
    # the full MCU via an I2C0-as-host loopback on the shared SDA0/SCL0 pads; it
    # hardcodes the FROZEN vectors 122 (I2CT0_AE) / 123 (I2CT0_DATA). Gated by the
    # 'i2ctarget' knob so it appears ONLY where I2CT0 is instantiated. The test .S is
    # written by a later stage -- this CATALOG row is inert at make-chip time (tags only
    # matter when `make verify` selects/stages tests) and tolerates a not-yet-built test.
    T('rv32ui-p-wi2ct', 'i2ctarget', True),
    # wtrng proves TRNG0 (ring-oscillator entropy harvest engine)
    # inside the full MCU -- register resets, the DR read-CONSUME contract, two
    # successive words (LFSR-stub movement), and the combined data-ready/health-
    # alarm IRQ (vector 121) through the real meip path. Gated by the 'trng' knob
    # so it appears ONLY where TRNG0 is instantiated (castalia_trng.json + wound).
    T('rv32ui-p-wtrng', 'trng', True),
    # wnpuconv proves NPU MODE=1 (conv) inside
    # the full MCU at the MCU/silicon generics (Q0.24 in / Q7.24 weight+acc+out) --
    # NPUCFG1/2 config + 4-bit MabMmrA readback smoke, an exact Q7.24 output check
    # (K=4 Cin=2 Cout=2 Lout=4 S=1 D=1 BEN=1), and the vector-120 think-done IRQ
    # through the real meip path (same idiom as shnpu.S's IRQ leg). Hart-0 directed
    # (tiles parked), so no 'tiles' tag; gated by 'npu' so NPU-less configs (Argus)
    # drop it, identically to shnpu.
    T('rv32ui-p-wnpuconv', 'npu', True),
    # wxnpu proves NPU MODE=2 (xnor)
    # inside the full MCU -- NPUCFG1/2 reinterpreted as THRESH/K, K=40 with
    # ADVERSARIAL tail garbage staged in the partial last word (proven
    # load-bearing: an unmasked-tail DUT would flip 2 of 4 neurons -- see
    # verification/npu/gen_wxnpu_golden.py), exact +-1.0 Q7.24 output check,
    # and the same vector-120 think-done IRQ leg wnpuconv.S/shnpu.S take.
    # Hart-0 directed (tiles parked), so no 'tiles' tag; gated by 'npu' so
    # NPU-less configs (Argus) drop it, identically to shnpu/wnpuconv.
    T('rv32ui-p-wxnpu', 'npu', True),
    # wgemm proves NPU MODE=3 (GEMM) inside the
    # full MCU -- NPUCFG1[7:0] reinterpreted as M-1, two CHAINED THINKs (layer 1
    # AEN=1 sigmoid so its row-major Q0.24 C feeds layer 2's A in place at the
    # same staging-RAM words, the D2 zero-repack proof), exact Q7.24/Q0.24
    # output checks from the validated golden model (verification/npu/
    # gen_wgemm_golden.py), and the same vector-120 think-done IRQ leg
    # shnpu.S/wnpuconv.S/wxnpu.S take. Hart-0 directed (tiles parked), so no
    # 'tiles' tag; gated by 'npu' so NPU-less configs (Argus) drop it,
    # identically to shnpu/wnpuconv/wxnpu.
    T('rv32ui-p-wgemm', 'npu', True),
    # wactf proves the activation mux inside
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
    # shcmppush and shpause derive the CLINT offset from NHARTS, as extzawrs.S does, rather
    # than hardcoding the N=4 layout: MTIME = 0x5000 + roundup16(4*NHARTS), so at N=18 the old
    # literals addressed other harts' msip registers. Neither is deselected on Argus.
    # What each row is on Argus:
    #   * shpause is real coverage. Argus has zihint off, so it runs the #else forward-progress
    #     arm: both bursts timed against real mtime, all 17 tiles reporting DONE. That arm is
    #     what failed at N=18, where the bogus mtime read back 0 and `beqz s4` fired.
    #   * shcmppush is an off-arm cell. Argus has zcmp off, so CORE_ENABLE_ZCMP is undefined and
    #     the whole ON body, timer arm included, is preprocessed away. It joins shcboz, shcmp
    #     and shcmt, which are untagged and off-arm on Argus for the same reason.
    T('rv32ua-p-shcmppush', 'atomics'),
    T('rv32ua-p-shcmt', 'atomics'),
    T('rv32ua-p-shpause', 'tiles atomics'),
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
    # The F10 pair, tagged differently on purpose, because the two rows cover the two polarities
    # of one ruling: a write form aimed at a read-only CSR traps in every build.
    #   rocsrw    on-polarity only. Its #else arm is `li a1, 0x5E10BAD0; j roc_fail`, so it
    #             fails loudly on a build without the knob by design, because it needs a
    #             recoverable trap to assert mcause, mepc and mtval. It carries trapCsr and is
    #             selected only by a trapCsr row. It also writes mtrapctl (0x7C0) to 0 and
    #             asserts the read-back, so its pass is a statement about standard delivery
    #             (vesta.vhd: std_mode <= '1' when ENABLE_TRAPCSR and trap_legacy_mode = '0'),
    #             not merely about a trap having happened.
    #   rocsrwmp  default build, so untagged and in the smoke set: the ruling changes the
    #             default build, so the standing coverage has to be on the default build. It has
    #             no build-time dispatch at all, so it is polarity-neutral and runs everywhere.
    #             Its victims, harts 1 and 2, wedge in the terminal TRAP_STATE by design and
    #             never write a0_1 or a0_2, so riscv_tb reports "tile hart(s) silent/parked",
    #             which is a note and not a failure; hart 0 is the observer and the a0 gate.
    #             It stays out of xrun_parallel.sh's TEST_FILES array, as its own header asks,
    #             so the 136-test floor does not move; this catalog is a different list.
    T('rv32ua-p-rocsrw', 'atomics trapCsr', True),
    T('rv32ua-p-rocsrwmp', 'atomics', True),
    # idcsrmp is the detector for the identity-CSR hole: mvendorid, marchid, mimpid and
    # mconfigptr were absent from csr_addr_valid, so reading a required read-only M-mode CSR
    # wedged the hart in the terminal TrapState. It joins both standing lists,
    # xrun_parallel.sh's TEST_FILES and this catalog, because its own header asks for that.
    # Untagged in the knob sense and therefore in the smoke set: the file has no CORE_ENABLE_*
    # dispatch, every encoding hart 0 executes is unconditionally legal on all matrix rows, and
    # it must run on castalia_notrapcsr, the one row exercising the trapCsr-OFF arm.
    # `atomics` here is a group tag, not a claim that the test executes an AMO: on an rv32ua-p-*
    # row the tag says the row's image comes from the rv32ua group, since test_groups() derives
    # the build set from the selected names.
    T('rv32ua-p-idcsrmp', 'atomics', True),
    # rdtimemp is the detector for the `time` CSR hole: 0xC01 and 0xC81 were admitted by
    # csr_addr_valid with no read arm behind them, so rdtime retired a constant zero, a stopped
    # clock software could not detect. Both are now out of the map and raise
    # illegal-instruction in every build; the file also guards the fix against being over-wide,
    # since 0xC00, 0xC02, 0xC03 and, because 0xC81 shared a source line with them, 0xC80 and
    # 0xC82 must all still retire. Like idcsrmp it joins both standing lists.
    # Untagged for the idcsrmp reason: no CORE_ENABLE_* dispatch anywhere in the file, and the
    # only encodings hart 0, the observer and a0 gate, executes are base ISA plus csrr mhartid,
    # the first ungated term of csr_addr_valid. `atomics` is the group tag, not an AMO claim.
    # Its three victims wedge in the terminal TrapState by design, correct RTL being that the
    # read traps, so "tile hart(s) silent/parked" is the expected note. Deliberately not in
    # either cosim list: trap-poison class, and the oracle --isa always carries _zicntr, so
    # Spike retires what must trap.
    T('rv32ua-p-rdtimemp', 'atomics', True),
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
    # K4 (row C3): the SHAPE_Q stimulus -- the compressed-off
    # instruction-address-misaligned arm, whose predicate is statically false
    # in every previously-built configuration. misa-ADAPTIVE, in the ext*
    # family's idiom, because this tag vocabulary is POSITIVE-ONLY and "needs
    # compressed OFF" cannot be written; `trapCsr` because the trap has to be
    # RECOVERABLE (mtrapctl.LEGACY resets to 1, so a legacy build wedges in the
    # terminal TRAP_STATE and the cell is a watchdog HANG, not a FAIL).
    T('rv32ua-p-shapeq', 'atomics trapCsr', True),
    # K4 (row A3): F5.5, the is_compressed latch's exposed path -- a PMP FETCH
    # denial at an ODD halfword reached by a JUMP (repeat_if='0'), which is a
    # different shape from pmprt6's straddle fault. It also drives the D5
    # load-side arm, which makes it the stimulus for
    # verification/formal/core_pmp_{props,witness}.psl.
    # NOTE WHAT THIS ROW'S TAGS FIX: before it, NO catalog row carried `pmp` or
    # `umode` at all, so rows A2/A3/A3.8 selected exactly the same 142 tests as
    # each other and the P-ladder's top two rungs exercised neither knob.
    T('rv32ua-p-pmpfq', 'atomics trapCsr umode pmp', True),
    T('rv32ua-p-extzihpm'), T('rv32ua-p-extzicond'), T('rv32ua-p-extzcb'),
    T('rv32ua-p-extzihint'), T('rv32ua-p-extzawrs'),
    T('rv32ua-p-shwrs', 'tiles atomics'),
    T('rv32ua-p-extzfinx'),
    # The HPM discriminator. NOT an adaptive
    # probe and NOT a both-polarity test -- it reads `mhpmcounter4` (needs
    # ENABLE_ZIHPM) around a shared-window `amocas.w` (needs ENABLE_ZACAS), so
    # it is tagged with BOTH knobs and is selected only by a config that sets
    # both. Its answer is read off the RTL trace, not off `a0`; see the test
    # header. `atomics` rides along per the rv32ua-group convention.
    T('rv32ua-p-casgrant', 'zacas zihpm atomics', True),

    # The five standing detectors. Each is the regression form of a real finding; none is
    # polarity-sensitive at build time (measured: byte-identical images across the trapCsr
    # polarities), so they carry only the tags their architecture requires.
    #   trapstor  the S-series residue item. `atomics` per the rv32ua-group convention.
    #   packalias the zext.h decode was not qualified on rs2=0, so the Zbkb pack space aliased
    #             onto it and retired on every shipped config. `bitmanip` because zext.h is a
    #             Zbb instruction: on a bitmanip-off build the whole encoding is illegal and
    #             the test's own pass-control cannot run. Measured: it failed on the C1 row,
    #             113 of 115, before this tag existed.
    #   fk51mp    RV32 reserves shamt[5]. Its victims are OP-IMM shift forms decoded under
    #             ENABLE_BITMANIP, so it is bitmanip-tagged and drops on the C1 row. It also
    #             needs `nozkn`: Zknh allocates encodings in exactly the reserved space this
    #             test polices (see config_tags).
    #   dvintmin  the signed-magnitude divide wrap. `div` for the reason every rv32um divide
    #             row carries it: the divider-off row must drop it by set difference, not fail.
    #   dvbubble  the split-fetch bubble re-arming the previous divide's selects. `div`, and
    #             also `compressed`, because the bubble exists only at a divide sitting at
    #             pc = 2 (mod 4), which a no-C build cannot construct. Measured: it failed on
    #             the C3 row, 144 of 146, before this tag existed.
    T('rv32ua-p-trapstor', 'atomics', True),
    T('rv32ua-p-packalias', 'atomics bitmanip', True),
    # RETAGGED bitmanip -> tilebitmanip: this is the MP variant, and
    # its tile arm executes the reserved-shamt encodings on harts 1..N-1. Those
    # harts are rv32iac now, so the encoding is illegal there for a SECOND,
    # unrelated reason and the test cannot distinguish the two -- measured: the
    # tiles park and hart 0 never passes (150/151, failing exactly this row).
    T('rv32ua-p-fk51mp', 'atomics tilebitmanip nozkn', True),
    T('rv32um-p-dvintmin', 'div', True),
    T('rv32um-p-dvbubble', 'div compressed', True),

    # The on-polarity-only suites. Every test here emits an encoding that takes an
    # illegal-instruction trap on a build without its knob, so each row is tagged with that
    # knob and is selected only by a knobs-on config. That is the difference between a config
    # that boots with the knob on and one that has been shown to execute the knob's
    # instructions.
    # These need their image group built (rv32uzicond, rv32uzabha and the rest) and the matching
    # -DCORE_ENABLE_* in RISCV_GCC_OPTS; verify_stage prints GROUPS= and DEFINES= for verify.sh
    # so both follow the config automatically. Until the image build consumes those lines a
    # knobs-on row prints them and still uses the default image set, which is loud rather than
    # silent, because the on-only images simply are not there.
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


def rcf_mapping(nharts, defines=(), march=None, tcm=None):
    """(3-char link name, dest dir) for an image set built at this NHARTS and this ON-knob polarity.
    The link name must be exactly 3 characters, so a polarity becomes two hex digits of a digest
    of the full identity. Empty defines with no march keeps today's mapping bit for bit.
    """
    if not defines and march is None:
        if nharts == 4:
            return 'rcf', 'rcf'
        if nharts == 18:
            return 'rca', 'rcf_argus'
        return 'r%02d' % nharts, 'rcf_n%02d' % nharts
    # The 2-hex tag collides in practice: adding -DCORE_ENABLE_TRAPCSR to nineteen
    # configurations at once re-rolled every identity and three rows aborted on the .imgset
    # guard. Two were stale pre-flip directories squatting on slots; the third, zimop against
    # zihint at k04, is a true sha1-prefix collision between two live configurations, which no
    # cleanup can resolve.
    # The tag cannot widen: the link name must be exactly 3 characters, because the riscv_tb
    # TEST_FILE generic is a fixed 29-character string, and 'k' costs one of them.
    # So the slot is chosen by deterministic linear probing over the 256 slots. The primary slot
    # is the digest, so every existing directory keeps its name and no image set is rebuilt, and
    # a config whose primary slot is held by a different identity walks forward until it finds
    # its own identity (reuse) or a free slot. That makes a collision impossible rather than
    # unlikely. The .imgset guard stays and is still the authority: probing chooses a directory,
    # the stamp proves it is the right one.
    tag = imgset_tag(nharts, defines, march, tcm)
    want = imgset_identity(nharts, defines, march, tcm)
    base = int(tag, 16)
    for step in range(256):
        t = '%02x' % ((base + step) % 256)
        stamp = os.path.join(ISA_ROOT, 'rcf_k' + t, '.imgset')
        if not os.path.isfile(stamp):
            return 'k' + t, 'rcf_k' + t          # free (or not yet built)
        if open(stamp).read().strip() == want:
            return 'k' + t, 'rcf_k' + t          # ours -- reuse
    raise SystemExit(
        'rcf_mapping: all 256 image-set slots are occupied by other identities.\n'
        '  Garbage-collect the sets no configuration claims before adding more.')


# The historical TCM size every earlier image set was linked against.
# An identity only mentions the TCM when it DIFFERS from this, which is what
# keeps every pre-existing set's identity string byte-identical.
_TCM_HISTORICAL = 16384


def imgset_identity(nharts, defines, march=None, tcm=None):
    """The exact string identifying an image set's polarity, stored in its `.imgset` stamp and
    compared on every reuse. A non-default -march or tcmSizePerHart is appended only when present,
    so every earlier set keeps a byte-identical identity: memory layout is part of the polarity.
    """
    s = 'NHARTS=%d DEFINES=%s' % (nharts, ' '.join(defines) if defines else '(none)')
    if march:
        s += ' MARCH=%s' % march
    if tcm and tcm != _TCM_HISTORICAL:
        s += ' TCM=0x%X' % tcm
    return s


def imgset_tag(nharts, defines, march=None, tcm=None):
    """Two hex digits naming the polarity, from a digest of its identity.
    hashlib, not hash(): Python's str hash is randomised per process, so hash()
    would give a DIFFERENT directory on every run."""
    import hashlib
    h = hashlib.sha1(imgset_identity(nharts, defines, march, tcm).encode('utf-8')).hexdigest()
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

# The five base-ISA knobs default true and the twenty X and P knobs default false. Only the
# ON direction needs a -D on the image build: the tests' #ifdef CORE_ENABLE_<K> idiom is
# presence-based, since generate.py emits the #define only when the generic is true, so the
# ON set is exactly the -D set.
# The five base knobs are deliberately excluded, and the reason is measured. Sweeping every
# test source and the env for a real preprocessor conditional on a base knob,
#   grep -rnE '^\s*#\s*(if|ifdef|ifndef|elif).*CORE_ENABLE_(MUL|DIV|ATOMICS|COMPRESSED|BITMANIP)\b'
# returns exactly one hit in the whole tree: rv32ua/extzimop.S:93, whose
# #ifdef CORE_ENABLE_COMPRESSED guards a two-instruction Zcmop tail inside its already
# Zimop-gated ON arm. The misa-adaptive probes dispatch at run time and need no define, and
# zbk.S names CORE_ENABLE_BITMANIP only in prose.
# Admitting COMPRESSED would buy that one tail, in a test no runner selects today, at the
# price of putting -DCORE_ENABLE_COMPRESSED on every image of every config, since compressed
# defaults true: rebuilding the entire canonical 260-image set at a new polarity and
# re-pinning the lockstep gate. If extzimop is ever wired in it needs either that decision
# taken deliberately or its own explicit -D.
DEFINE_KNOBS = ISA_KNOBS[5:] + PRIV_KNOBS

# The other half of the same classification. DEFINE_KNOBS above is a list of schema keys;
# what a polarity comparison holds is a set of RTL constant suffixes read out of
# MemoryMap.vhd. The two are not the same alphabet, and they looked the same only because
# every stampable knob happened to satisfy CORE_ENABLE_<key.upper()> == <constant name>.
# What makes a knob stampable, all three required:
#   1. the generator emits a matching C #define CORE_ENABLE_<X>, in MemoryMap.h and the
#      assembly-safe core_features.h companion, so an image can be built at a polarity;
#   2. some test source dispatches on that define at build time, so the two polarities
#      produce different images. That is the whole content of the defect the stamp catches:
#      OFF-arm software against ON-polarity hardware, whose failure mode is a pass;
#   3. the RTL polarity is observable as constant CORE_ENABLE_<X> : boolean in the one
#      staged MemoryMap.vhd, so the hardware half can be read back rather than recomputed.
# Property 3 alone is not enough. A knob that fails any of the three can never appear in an
# .imgset stamp, so a guard that compares the raw RTL ON-set against the stamp refuses every
# row that exists the moment such a knob is declared true: that is what took boot-mode cosim
# down for eight days between the debug merge and the fetch-ahead merge, reporting a polarity
# mismatch that was an artefact of its own arithmetic.
# The exempt set is therefore written down rather than inlined in a shell case, and
# memorymap_on_knobs refuses a constant that is in neither list, so a new CORE_ENABLE_* must
# be classified in the commit that adds it. Each entry carries the measurement that put it
# here.
NON_DEFINE_KNOBS = (
    # The five base-ISA knobs, for the reasons measured in the DEFINE_KNOBS
    # comment above. They fail property 2 (one #ifdef, in a test no runner
    # selects) at a price of rebuilding the whole canonical image set.
    'MUL', 'DIV', 'ATOMICS', 'COMPRESSED', 'BITMANIP',
    # IF_AHEAD fails property 1 outright and by design: ChipGenerator.py emits no
    # #define CORE_ENABLE_IF_AHEAD in either header, because it is microarchitecture only, with
    # no CSR, no instruction and no memory-map change, so nothing in software can dispatch on
    # it. Measured against the same sweep the base knobs got, IF_AHEAD does not occur in
    # verification/isa or software/ at all. It is a straddling-fetch stall elision worth one
    # flip-flop, and verification/cpi records it as a cycle-count difference with identical
    # retired-instruction counts either way. A knob that cannot change a retired value cannot
    # make the reference and the DUT execute different arms, which is the only thing the stamp
    # is for. Permanently exempt: delete it from this list only if fetch-ahead ever grows a CSR
    # or an instruction.
    'IF_AHEAD',
    # DEBUG fails property 2, and is deferred rather than permanently exempt.
    # Property 1 it satisfies: ChipGenerator.py emits #define CORE_ENABLE_DEBUG into
    # MemoryMap.h and the core_features.h list carries it, so an image could be built at a debug
    # polarity. Property 2 it does not: the sweep
    #   grep -rnE '^\s*#\s*(if|ifdef|ifndef|elif).*CORE_ENABLE_DEBUG\b'
    # returns zero hits, and CORE_ENABLE_DEBUG appears nowhere in verification/ or software/.
    # That is structural, not a coverage accident: every debug instrument needs a tcl harness to
    # force dbg_haltreq or the DMI port, so no catalog row carries the `debug` tag and none can;
    # the Debug Module is proven by xrun_dbg.sh and the dbg_*.tcl harnesses instead.
    # Admitting DEBUG to DEFINE_KNOBS would buy zero #ifdef arms at a high price: debug.enable
    # defaults true, so every image of every config gains -DCORE_ENABLE_DEBUG, every .imgset
    # stamp changes, every rcf_* directory moves to a new tag digit, and the whole canonical set
    # is rebuilt at a new polarity.
    # The trigger is written down: the first #ifdef CORE_ENABLE_DEBUG in a test source a runner
    # selects moves 'debug' into DEFINE_KNOBS, as a third section alongside isa.* and priv.*,
    # since the schema key is debug.enable and 'CORE_ENABLE_' + key.upper() does not name the
    # constant, and pays the rebuild deliberately. tools/cosim/check_knob_classes.py fails on
    # that day rather than leaving it to be noticed.
    'DEBUG',
)


def knob_classes():
    """(stampable, exempt) as the RTL constant suffixes a MemoryMap.vhd holds. The one place that
    maps schema keys onto CORE_ENABLE_<X> names, so the shell half of the polarity guard reads
    the classification instead of carrying its own copy.
    """
    stampable = tuple(k.upper() for k in DEFINE_KNOBS)
    return stampable, tuple(NON_DEFINE_KNOBS)


def image_defines(cfg):
    """The -DCORE_ENABLE_* list this configuration's images must be built with, the software half of
    the switch whose hardware half is the staged MemoryMap.vhd. The ISA Makefile still refuses to
    auto-derive these; what is new is that the explicit pairing is produced once and checked.
    """
    isa = cfg.get('isa', {})
    priv = cfg.get('priv', {})
    out = []
    for k in DEFINE_KNOBS:
        on = priv.get(k) if k in PRIV_KNOBS else isa.get(k)
        if on:
            out.append('-DCORE_ENABLE_' + k.upper())
    return out


# The one place where the image build's -march is wrong for the configuration.
# verification/isa/Makefile fixes a per-group march (rv32imc, rv32imac, rv32gc_zba and so
# on) and emits $(RISCV_GCC_OPTS) after it on the gcc command line, so a -march= carried in
# RISCV_GCC_OPTS wins. Exactly one supported configuration needs it: with isa.compressed
# false the core cannot decode a 16-bit instruction, and gas auto-compresses under a `c`
# march (measured: addi a0,a0,1 assembles to the 16-bit 0505), so the default image set is
# full of encodings that build's RTL traps on.
# Deliberately narrow, and it must not grow into deriving the march from the config:
#   * the five base knobs stay excluded from DEFINE_KNOBS for the reasons measured there;
#   * a mul=div=false row cannot drop `m` from the march, because the rv32um sources would
#     stop assembling, so those rows' images stay byte-identical to the default set. That is
#     a known and different gap and is not fixed here;
#   * one global march has to cover every group a selection builds, so it is a superset of
#     what any of them asks for. Measured: all 232 sources across the seven groups a
#     compressed-off selection needs assemble under it, and 149 of those 232 images differ
#     from their default-march twins.
NORVC_MARCH = 'rv32ima_zicsr_zifencei_zba_zbb_zbc_zbs'


def image_march(cfg):
    """The -march override this configuration's images need, or None, which means the ISA Makefile's
    per-group march.
    """
    isa = cfg.get('isa', {})
    if isa.get('compressed', True):
        return None
    for k in ('mul', 'div', 'atomics', 'bitmanip'):
        if not isa.get(k, True):
            raise SystemExit(
                'compressed=false is combined with %s=false, and ONE global '
                '-march cannot express that: dropping %s from the march stops '
                'the matching test sources assembling, while keeping it lets '
                'the build emit encodings this core will trap on. Refusing '
                'rather than staging a silently wrong image set.' % (k, k))
    return NORVC_MARCH


def memorymap_on_knobs(path):
    """The CORE_ENABLE_* knobs a MemoryMap.vhd actually declares true, the hardware half of the
    polarity pair. Read from the staged file, never recomputed from the config, so a generator
    that failed to emit a constant is caught rather than agreed with. VHDL is case-insensitive.
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
    # Only the knobs a test can dispatch on at build time are comparable (see
    # DEFINE_KNOBS and NON_DEFINE_KNOBS for the three properties and for the
    # measurement behind every exemption).
    #
    # This used to be a bare `on & DEFINE_KNOBS` intersection, which SILENTLY
    # dropped anything unrecognised. Silence is what let CORE_ENABLE_IF_AHEAD
    # land unclassified: this function agreed with it, while the shell guard's
    # negative filter did not, and the two halves of one comparison drifted
    # apart without either of them saying so. An unclassified constant is now a
    # refusal, here and in xrun_cosim.sh, in the same words.
    unknown = sorted(on - set(k.upper() for k in DEFINE_KNOBS)
                        - set(NON_DEFINE_KNOBS))
    if unknown:
        raise SystemExit(
            '%s declares CORE_ENABLE_%s true, and that knob is classified\n'
            '  neither STAMPABLE (verify_stage.DEFINE_KNOBS) nor EXEMPT\n'
            '  (verify_stage.NON_DEFINE_KNOBS). A polarity comparison cannot\n'
            '  guess which it is: treated as stampable it refuses every image\n'
            '  set that exists, treated as exempt it hides a real mismatch.\n'
            '  Classify it in the commit that adds it. It is STAMPABLE only if\n'
            '  all three hold: the generator emits a matching\n'
            '  `#define CORE_ENABLE_%s`, some test source dispatches on that\n'
            '  define at build time, and the constant is readable here.\n'
            '  Otherwise it is EXEMPT, with the measurement written down.'
            % (path, unknown[0], unknown[0]))
    return sorted(on & set(k.upper() for k in DEFINE_KNOBS))


def test_groups(names):
    """The verification/isa test groups the selected tests live in, ordered as build_mp_images.sh
    wants them: base groups first, then the ON-polarity suites on top.
    """
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
    # ASYMMETRIC ISA. `bitmanip` above answers "does THE CHIP have
    # B?", which since the minimal-tiles decision is no longer the same question
    # as "does a TILE have B?": harts 1..N-1 are built rv32iac while hart 0 keeps
    # the full ISA. An MP test whose TILE ARM executes B needs this tag, not
    # `bitmanip`. Same shape as `nozkn` below and NOT the "tag a real
    # constraint away" anti-pattern: the tiles genuinely do not implement B, so
    # the property the test asserts is false BY DESIGN on them, and no edit
    # inside the test can make it true.
    if isa.get('bitmanip') and not isa.get('minimalTiles'):
        tags.add('tilebitmanip')
    # `nozkn` is a NEGATIVE structural predicate, and the only
    # one in this table. It exists because Zknh ALLOCATES ENCODINGS IN THE SPACE
    # RV32 RESERVES for shamt[5]=1, which is exactly the space `fk51mp` exists to
    # prove still traps. `fk51mp`'s own control encoding is annotated in its
    # source as "funct7=SHA256_FN7, ZKN off": with Zkn ON that word is a legal
    # `sha256sum0` and the control hart correctly walks past it, so the test
    # reports FAIL for a reason that is not a defect. Measured on the B15 and D2
    # rows before this tag existed (152/153 and 176/177, both failing exactly
    # fk51mp).
    #
    # This is NOT the "tag a real constraint away" anti-pattern: the
    # constraint is architectural and unfixable inside the test, and the tag
    # states it rather than hiding it. If Zkn's encodings ever move, delete this.
    if not isa.get('zkn'):
        tags.add('nozkn')
    # cqAfeStubs defaults FALSE: the tape-out chip became the
    # generator's built-in default and it ships QSPI0 in page-0 slot 12 instead
    # of the AFE/EIS stub bank, so shafe/shorch must not be staged there. The
    # fallback is belt and braces -- this reads the RESOLVED config, which
    # always states every knob.
    if cfg.get('peripherals', {}).get('cqAfeStubs', False):
        tags.add('cqAfeStubs')
    # K2: `harts_le4` is a STRUCTURAL bound, not a knob -- "this row's addresses
    # are only correct while 4*numHarts <= 16". ONE test needs it now:
    #   * the AFE stub bank. mcu_vhd.py emits exactly FOUR afe_stub instances
    #     (afe0..afe3) whatever numHarts is -- the bank is NOT N-parameterised --
    #     while shafe.S addresses its own stub as `AFE0 + 0x40*h`. At h=4 that is
    #     0x4D00, which is GPIO3's slot, so shafe on an 18-hart config would not
    #     merely fail, it would write another peripheral.
    # The SECOND reason this tag used to carry -- the CLINT mtime/mtimecmp
    # offset, which sits at `0x5000 + roundup16(4*NHARTS)` and is only 0x5010/
    # 0x5020 at N<=4 -- is GONE at K5: shpause and shcmppush now derive it from
    # NHARTS (see their rows above). If a future
    # test hardcodes 0x5010 again, PORT IT rather than tagging it away -- the tag
    # is for structure the GENERATOR does not parameterise, not for a literal a
    # test could simply compute.
    # Deliberately a numeric bound rather than `numHarts == 4`: the predicate
    # that is actually true is 4*N <= 16, and a hypothetical 2-hart config is
    # fine for the reason above.
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
    # DMA0 is a config-gated ADDED instance (default off). Its
    # DMA.vhd is compiled only when the config enables it (the NPU.vhd pattern);
    # no sh-test tags change (shdma.S is a follow-up).
    if cfg.get('peripherals', {}).get('dma'):
        tags.add('dma')
    # D2: the Debug Module. The tag exists to gate the debug_module.vhd cell
    # (below) -- NO CATALOG ROW CARRIES IT AND NONE CAN: every D-series debug
    # instrument needs a tcl harness to force dbg_haltreq or the DMI port, and
    # this staging grades a0 from a plain xrun_parallel run with no harness, so
    # a CATALOG row for one would hang or fail by construction. The DM is
    # proven by xrun_dbg.sh + the dbg_*.tcl harnesses instead.
    if cfg.get('debug', {}).get('enable'):
        tags.add('debug')
    # CPR3/R1 (Castalia-Penta rework): the soft ORCHESTRATOR hart, now a
    # PRESENCE BOOLEAN and now HART 0. It drives the CELL-LIST injection
    # (orch_tile.vhd) AND, since CPR4, two CATALOG rows: `shtcm` (the TCM
    # apertures, which exist on EVERY orchestrator config -- so this is the row
    # that runs on the tape-out configuration too) and the rewritten `shorch`,
    # which additionally needs `cqAfeStubs` and therefore stops at penta.
    # NOTE what the knob still does to an EXISTING row: it comes with
    # numHarts=5, so `harts_le4` drops out and `shafe` is deselected -- by
    # plan (CP1 D8), because the AFE bank is FOUR sites at any hart count
    # while shafe.S addresses AFE0 + 0x40*h, and h=4 would land on GPIO3.
    if cfg.get('orchestrator'):
        tags.add('orch')
    # TRNG0 is a config-gated ADDED instance (default off), same
    # shape as DMA0. TrngRoEnsemble_sim.vhd + TRNG.vhd are compiled only when the
    # config enables it (below). No sh-test tags change yet -- no shared-suite test
    # uses TRNG0 (this tag exists solely to drive the cell-list injection).
    if cfg.get('peripherals', {}).get('trng'):
        tags.add('trng')
    # EVFAB0 is a config-gated ADDED instance (default off),
    # same shape as DMA0/TRNG0 -- but EVFAB.vhd is UNCONDITIONALLY in the base
    # cell list (it needs no config-gated MemoryMap constants), so this tag
    # drives ONLY test selection: shevfab.S touches 0x6B00 and the DMA task
    # port, so it must never be staged into a fabric-less configuration.
    if cfg.get('peripherals', {}).get('eventFabric'):
        tags.add('eventFabric')
    # Firmware smoke companions gated by their peripheral
    # knob (wrtc/wpwm/wow join only the config(s) that instantiate the block).
    for knob in ('rtc', 'pwm', 'onewire', 'i2ctarget'):
        if cfg.get('peripherals', {}).get(knob):
            tags.add(knob)
    if int(cfg['numHarts']) >= 2:
        tags.add('tiles')
    return tags


def _print_knob_classes():
    """The classification, for the shell: two lines of RTL constant suffixes, shell-word-safe by
    construction. xrun_cosim.sh reads this instead of hardcoding half of it, so the two halves of
    the polarity comparison cannot drift apart. Needs no resolved config and touches nothing.
    """
    stampable, exempt = knob_classes()
    print('STAMPABLE_KNOBS=%s' % ' '.join(stampable))
    print('EXEMPT_KNOBS=%s' % ' '.join(exempt))


def main():
    if '--knob-classes' in sys.argv[1:]:
        _print_knob_classes()
        return
    if not os.path.isfile(RESOLVED):
        raise SystemExit('config/ChipConfig.resolved.json not found -- run make generate first')
    with open(RESOLVED) as f:
        cfg = json.load(f)

    chip = cfg['chipName'].strip().lower().replace(' ', '_') or 'chip'
    nharts = int(cfg['numHarts'])
    have = config_tags(cfg)
    defines = image_defines(cfg)
    march = image_march(cfg)
    # The memory layout is the fourth half of the polarity. The
    # images are LINKED against memory.x, so the TCM size decides __stack_top
    # and the RAM region length; reusing another size's images is reusing a
    # different chip's binaries.
    tcm = int(cfg.get('memory', {}).get('tcmSizePerHart') or _TCM_HISTORICAL)
    link, dest = rcf_mapping(nharts, defines, march, tcm)

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

    # staged RTL: the generated MCU + MemoryMap + testbench
    out_hdl = os.path.join(PC_ROOT, 'out', 'hdl')
    for fn in ('MCU.vhd', 'MemoryMap.vhd', 'riscv_tb.vhd'):
        src = os.path.join(out_hdl, fn)
        if not os.path.isfile(src):
            raise SystemExit('missing %s -- run make generate first' % src)
        shutil.copy(src, os.path.join(stage, 'hdl', fn))

    # cell list: behavioral_mp's, with the generated files swapped
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
    # ALREADY-SWAPPED ANCHORS. behavioral_mp's own cell list may
    # already point at the generated pair -- `hdl/MCU.vhd` / `hdl/MemoryMap.vhd`
    # as symlinks into bazel-bin -- instead of the tracked `hdl/common/` drop-in
    # copies. Staging read that list as a template and required all three
    # `hdl/common/...` spellings verbatim, so a repointed base list aborted with
    #     cell list swap points not all found in ...: got ['hdl/common/tb/riscv_tb.vhd']
    # even though the line it was looking for was present in its POST-swap form.
    # A line already in the destination spelling satisfies its anchor and is
    # passed through unchanged: the stage copies out/hdl/{MCU,MemoryMap,
    # riscv_tb}.vhd into <stage>/hdl/ regardless, so `hdl/MCU.vhd` resolves to
    # the file this run generated, exactly as the swap would have made it.
    already = dict((repl, suffix) for suffix, repl in swaps.items())
    seen = set()
    lines = []
    dma_seen = False
    trng_seen = False
    dm_seen = False          # D2: debug_module.vhd was present in the base list
    orch_seen = False        # CP2: orch_tile.vhd was present in the base list
    dtm_seen = False         # D3: jtag_dtm.vhd was present in the base list
    afe_stub_seen = False    # AFE: hdl/common/afe_stub.vhd was present in the base list
    mcu_idx = None           # D2: where the staged MCU.vhd landed
    crc16_idx = None
    uart0_idx = None
    with open(BASE_CELL_LIST) as f:
        for raw in f:
            p = raw.strip()
            if not p:
                continue
            if p in already:
                # the base list already carries the post-swap spelling
                if p == 'hdl/MCU.vhd':
                    mcu_idx = len(lines)
                lines.append(p)
                seen.add(already[p])
                continue
            swapped = False
            for suffix, repl in swaps.items():
                if p.endswith(suffix):
                    if suffix == 'hdl/common/MCU.vhd':
                        mcu_idx = len(lines)
                    lines.append(repl)
                    seen.add(suffix)
                    swapped = True
                    break
            if swapped:
                continue
            if p.endswith('periph/NPU.vhd') and 'npu' not in have:
                continue    # NPU.vhd needs the MmrAddrNPU* constants -- NPU-less
            # DMA.vhd is compiled only when the config enables the
            # DMA (the NPU.vhd gate pattern). It depends on CRC16.vhd (already in the
            # base list, before the periph block); if the base list ever carries
            # DMA.vhd it is passed through when dma is on and dropped otherwise.
            if p.endswith('periph/DMA.vhd'):
                if 'dma' not in have:
                    continue    # DMA off -> MCU.vhd has no dma0 instance
                dma_seen = True
            # TrngRoEnsemble_sim.vhd and TRNG.vhd are compiled only
            # when the config enables TRNG (the NPU.vhd/DMA.vhd gate pattern). The
            # RTL ensemble file (TrngRoEnsemble.vhd, the genus/gate-only `rtl` arch)
            # must NEVER be referenced here -- if the base list ever carries it, drop
            # it unconditionally (behavioral flows compile the `sim` arch only, D6).
            # D2: debug_module.vhd is compiled only when the config enables
            # debug (the NPU.vhd / DMA.vhd gate pattern). It has no dependency
            # beyond ieee, and MCU.vhd instantiates it as `entity work.` so a
            # missing file is a hard error rather than a silent blackbox.
            if p.endswith('hdl/common/debug_module.vhd'):
                if 'debug' not in have:
                    continue    # debug off -> MCU.vhd has no dm0 instance
                dm_seen = True
            # D3: jtag_dtm.vhd rides the SAME knob as debug_module.vhd (there
            # is no debug.jtag sub-knob) and is compiled under the same gate.
            # It has no dependency beyond ieee; MCU.vhd instantiates it as
            # `entity work.` so a missing file is a hard error, never a
            # silent blackbox.
            if p.endswith('hdl/common/jtag_dtm.vhd'):
                if 'debug' not in have:
                    continue    # debug off -> MCU.vhd has no dtm0 instance
                dtm_seen = True
            # CP2: orch_tile.vhd is compiled only when the config names a
            # management hart (the debug_module.vhd / DMA.vhd gate pattern).
            # It is a bare wrapper around hart_tile, so it must come AFTER
            # hart_tile.vhd and BEFORE MCU.vhd -- both hold in the base list.
            if p.endswith('hdl/common/orch_tile.vhd'):
                if 'orch' not in have:
                    continue    # no orchestrator -> MCU.vhd has no orch_tile instance
                orch_seen = True
            # The AFE register-stub bank. Gated on its own knob (the NPU.vhd /
            # DMA.vhd pattern) so an unused entity never reaches xmvhdl.
            if p.endswith('hdl/common/afe_stub.vhd'):
                if 'cqAfeStubs' not in have:
                    continue    # stubs off -> MCU.vhd has no afe0..3/eis0 instance
                afe_stub_seen = True
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
        raise SystemExit(
            'cell list swap points not all found in %s: got %s\n'
            '  Each of hdl/common/MemoryMap.vhd, hdl/common/MCU.vhd and\n'
            '  hdl/common/tb/riscv_tb.vhd must appear either in that spelling or\n'
            '  already swapped to hdl/MemoryMap.vhd / hdl/MCU.vhd / hdl/riscv_tb.vhd.'
            % (BASE_CELL_LIST, sorted(seen)))
    # Inject TrngRoEnsemble_sim.vhd then TRNG.vhd (dependency
    # order -- TRNG.vhd instantiates TrngRoEnsemble as a component) when the config
    # enables TRNG but the base list lacks them. Anchored just before UART.vhd (the
    # rest of the periph family, RTC/PWM/OneWire/I2CTarget, already
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
    # Inject DMA.vhd (after CRC16.vhd, its only dependency, and well
    # before MCU.vhd) when the config enables the DMA but the base list lacks it.
    # D2: inject debug_module.vhd (immediately before MCU.vhd, its only
    # consumer) when the config enables debug but the base list lacks it.
    if 'debug' in have and not dm_seen:
        if mcu_idx is None:
            raise SystemExit('debug config but hdl/MCU.vhd not in the staged list')
        lines.insert(mcu_idx, '../../../hdl/common/debug_module.vhd')
    # D3: same injection point for the DTM (immediately before MCU.vhd, its
    # only consumer). Done AFTER the debug_module insertion so mcu_idx is
    # recomputed from the list it actually has to land in.
    if 'debug' in have and not dtm_seen:
        if 'hdl/MCU.vhd' not in lines:
            raise SystemExit('debug config but hdl/MCU.vhd not in the staged list')
        lines.insert(lines.index('hdl/MCU.vhd'), '../../../hdl/common/jtag_dtm.vhd')
    # CP2: same injection point as the DM (immediately before MCU.vhd, its only
    # consumer, and after hart_tile.vhd which it wraps). Done after the debug
    # insertions so the index is recomputed from the list it lands in.
    if 'orch' in have and not orch_seen:
        if 'hdl/MCU.vhd' not in lines:
            raise SystemExit('orchestrator config but hdl/MCU.vhd not in the staged list')
        lines.insert(lines.index('hdl/MCU.vhd'), '../../../hdl/common/orch_tile.vhd')
    # Inject afe_stub.vhd immediately before MCU.vhd (its only consumer) when the
    # config keeps the stub bank but the base list lacks it. Same injection point
    # and same reasoning as the DM/DTM/orch_tile blocks above, and done after them
    # so the index is recomputed from the list it lands in.
    if 'cqAfeStubs' in have and not afe_stub_seen:
        if 'hdl/MCU.vhd' not in lines:
            raise SystemExit('cqAfeStubs config but hdl/MCU.vhd not in the staged list')
        lines.insert(lines.index('hdl/MCU.vhd'), '../../../hdl/common/afe_stub.vhd')
    if 'dma' in have and not dma_seen:
        dma_cell = '../../../hdl/common/periph/DMA.vhd'
        if crc16_idx is None:
            raise SystemExit('DMA config but commune/CRC16.vhd not in %s (DMA.vhd needs it)'
                             % BASE_CELL_LIST)
        lines.insert(crc16_idx + 1, dma_cell)
    # SystemRDL level 2: every peripheral has a GENERATED
    # register package -- hdl/common/regs/vhdl/<x>_regs_pkg.vhd -- carrying its word
    # offsets, field ranges, IMPL masks and reset constants. A package must be
    # analysed before the entity that uses it, so each one is inserted
    # immediately ahead of its entity WHEREVER that entity ended up: the base
    # list may already carry it, or one of the injections above may have placed
    # it. This runs LAST, after every other injection, so the index it reads is
    # off the finished list -- and so it cannot shift crc16_idx, which the DMA
    # injection above holds as a number taken from the base-list scan.
    #
    # All twenty-four are injected, adopted or not: an unused package is one
    # extra xmvhdl analysis and nothing else, and it means a peripheral's
    # adoption never has to touch this file. An entity the configuration does not
    # instantiate is absent from the list, and its package is skipped with it.
    for pkg, entity in REGS_PACKAGES:
        pkg_cell = '../../../hdl/common/regs/vhdl/' + pkg
        if pkg_cell in lines:
            continue
        at = [i for i, ln in enumerate(lines) if ln.endswith(entity)]
        if not at:
            continue        # the entity is not in this configuration; neither is its package
        lines.insert(at[0], pkg_cell)
    # The shared register file. It is an ENTITY, not a package, but
    # `entity work.periph_regs` binds at ANALYSIS, so it goes ahead of the first
    # thing that could instantiate it -- which, after the loop above, is the first
    # register package in the list.
    regs_cell = '../../../hdl/common/periph_regs.vhd'
    if regs_cell not in lines:
        at = [i for i, ln in enumerate(lines) if '/regs/vhdl/' in ln]
        if at:
            lines.insert(at[0], regs_cell)
    with open(os.path.join(stage, 'cell_list_behavioral.txt'), 'w') as f:
        f.write('\n'.join(lines) + '\n')

    # runner script from the template
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

    # the 3-char rcf symlink
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

    # hand off to verify.sh
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
    # K4: the third half of the polarity (see image_march). Empty for every
    # configuration but C3; printed unconditionally so the verify banner always
    # says which march the images were asked for instead of leaving it implicit
    # in the ISA Makefile.
    print('MARCH=%s' % (march or ''))
    print('TCM=0x%X' % tcm)
    print('IMGSET=%s' % imgset_identity(nharts, defines, march, tcm))
    # The staged RTL's own ON-knob set, read back out of the file that was just
    # written rather than recomputed from the config. That is the point: the
    # polarity gate must compare the SOFTWARE side against what the HARDWARE
    # side actually says, so that a generator bug which fails to emit a
    # CORE_ENABLE_* constant is caught instead of being agreed with.
    print('RTL_ON=%s' % ' '.join(memorymap_on_knobs(
        os.path.join(stage, 'hdl', 'MemoryMap.vhd'))))


if __name__ == '__main__':
    main()
