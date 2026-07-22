# See LICENSE for license details.

#*****************************************************************************
# wi2ct.S  (digperiphs I2CT — firmware smoke, Stage 5)
#-----------------------------------------------------------------------------
# I2CT0 @0x6A00 hardware-autonomous I2C TARGET (slave) end-to-end smoke via an
# I2C0-as-HOST loopback on the SHARED SDA0/SCL0 pad planes (P4.0/P4.1). Single-
# hart directed (hart 0; tiles park). Proves the CPU can drive the I2C0 master
# AND the I2CT0 target on the same open-drain bus (the D19 wired-AND DIR merge
# makes the loopback legal), and that BOTH target IRQs route through irq_router
# (HhENX bits 26/27) -> meip -> MEIP_DISPATCHER -> IVT -> plain-ret handler ->
# CLAIM/COMPLETE:
#   vector 122 = I2CT0_AE   (address-match / error / framing)
#   vector 123 = I2CT0_DATA (rx-full / tx-ready)
#
# TB CONTRACT: the wound/verify riscv_tb gives P4.0 (SDA0) and P4.1 (SCL0) a
# WEAK 'H' pull so the open-drain bus idles high (the Verilog pad model's buf()
# normalizes the weak-high to a clean '1' at the MCU input). No firmware REN is
# needed. I2C0's serial core is SMCLK -> this test writes SYS_CLK_CR=0 first
# (bootrom parks SMCLK on LFXT); I2CT0 itself is MCLK (D2) and needs no clock
# setup. PAD ROUTING (critical): SDA0/SCL0 are the AF0 (home) function of
# P4.0/P4.1, but a pin only drives its alt-function when GPIO3 PxSEL=1 (reset
# is PxSEL=0 = plain GPIO). This test sets P4SEL bit0/bit1 (P4AFS stays 0 = AF0)
# so the I2C0 master's SDA/SCL actually reach the pads -- without it the master
# reads back an un-driven pad and loses arbitration (I2CMARB) mid-address.
#
# I2CT0 register map (i2ct_design.md AS-BUILT; base 0x6A00, slot n @ +4n):
#   CR 0x6A00 : EN[0] GCEN[1] CSEN[2] AEIE[3] DATAIE[4] SAD[14:8] SADM[22:16]
#   SR 0x6A04 : BUSY[0] TM[1] AMF[2] GCF[3] RXF[4] TXE[5] OVF[6] NACKF[7]
#               STOPF[8] RSTARTF[9] ERRF[10]  (AMF/GCF/RXF/OVF/NACKF/STOPF/
#               RSTARTF/ERRF are W1C; BUSY/TM/TXE read-only)
#   TX 0x6A08 : [7:0] next transmit byte (a write loads the buffer, clears TXE)
#   RX 0x6A0C : [7:0] last received byte (RO, side-effect-free)
#   irq_ae   = (AMF|GCF|OVF|NACKF|STOPF|RSTARTF|ERRF) & AEIE   -> vector 122
#   irq_data = (RXF|TXE) & DATAIE                              -> vector 123
#
# I2C0 master (I2C.vhd AS-BUILT; base 0x4E00):
#   CR 0x4E00 : ... MDIV[16:13] ... MEN[21]
#   FCR 0x4E04: MRB[0] MSP[1] MST[2] SC[3]  (write-1 command bits)
#   SR 0x4E08 : SPR[0] STR[1] MXC[2] MNR[3] ...  (MXC/MNR are W1C)
#   MTX 0x4E0C: master transmit byte (a write with MEN=1 issues MasterWrite);
#               the FIRST byte after a START is the address byte {SAD<<1|RnW}
#   MRX 0x4E10: master receive byte
#
# HANDLER STRATEGY (M19 plain-ret ABI; t0-t2 dispatcher-saved; ra survives):
#   ae_handler (122)  : accumulate the SR snapshot into AE_FLAGS, bump AE_CNT,
#                       then MASK AEIE (drop irq_ae) while LEAVING AMF set so the
#                       DATA handler can still witness the address match; W1C the
#                       framing/error flags EXCEPT AMF.
#   data_handler (123): demux. On RXF -> record AMF-at-RXF, read I2CTRX into
#                       RX_MB, W1C RXF+AMF, set RX_GOT. On TXE -> load I2CTTX with
#                       the staged byte (clears TXE, RELEASES the CSEN TX stretch,
#                       D11), set TX_SERVICED.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SYS_CLK_CR   0x4900
#define I2CT_CR      0x6A00
#define I2CT_SR      0x6A04
#define I2CT_TX      0x6A08
#define I2CT_RX      0x6A0C
#define I2C0_CR      0x4E00
#define I2C0_FCR     0x4E04
#define I2C0_SR      0x4E08
#define I2C0_MTX     0x4E0C
#define I2C0_MRX     0x4E10
#define GPIO3_SEL    0x4D24            /* GPIO3 PxSEL: select SDA0/SCL0 alt-func on P4.0/1 */
#define IRTR_ENX     0x700C            /* HhENX, hart-0 row (sources 96-127) */

#define I2CT_CR_VAL  0x00002A1D        /* EN|CSEN|AEIE|DATAIE | SAD=0x2A<<8 */
#define I2C0_CR_VAL  0x00202000        /* MEN(21) | MDIV=1 (SCL ~ mclk/32) */
#define ENX_I2CT     0x0C000000        /* bit26=src122, bit27=src123 */

/* I2CT0 SR bits */
#define TSR_AMF      0x004
#define TSR_RXF      0x010
#define TSR_STOPF    0x100
#define TSR_RXF_AMF  0x014             /* W1C RXF(4)+AMF(2) */
#define TSR_CLR_NOTAMF 0x7C8           /* W1C GCF/OVF/NACKF/STOPF/RSTARTF/ERRF (keep AMF) */
#define TSR_CLR_ALL  0x7FC             /* W1C AMF..ERRF */

/* I2C0 SR bits */
#define MSR_MXC      0x4
#define MSR_MNR      0x8

/* I2C0 FCR command bits */
#define FCR_MST      0x4
#define FCR_MSP      0x2
#define FCR_MRB      0x1

/* address bytes {SAD<<1 | RnW} */
#define ADDR_WR      0x54              /* write to 0x2A */
#define ADDR_RD      0x55              /* read  from 0x2A */
#define ADDR_NM      0x66              /* write to 0x33 (non-matching) */

#define WR_BYTE      0xC3              /* host -> target write payload */
#define TX_BYTE      0x5A              /* target -> host staged read byte */

/* private-TCM mailboxes (all in the 0x8000-0xBFFF TCM) */
#define AE_FLAGS     0xA000            /* ae_handler: OR of every SR it saw */
#define AE_CNT       0xA004            /* ae_handler invocation counter */
#define RX_MB        0xA008            /* data_handler: RXF byte captured */
#define RX_GOT       0xA00C            /* data_handler: RXF serviced flag */
#define RXF_AMF      0xA010            /* data_handler: AMF bit sampled at RXF */
#define TX_SERVICED  0xA014            /* data_handler: TXE serviced flag */

# ---- bounded poll of I2C0 SR MXC (bit2); s3 = countdown -------------------
.macro PMXC failt
    li   s3, 20000
.Lpmxc_lp\@:
    li   t0, I2C0_SR
    lw   t0, 0(t0)
    andi t0, t0, MSR_MXC
    bnez t0, .Lpmxc_done\@
    addi s3, s3, -1
    bnez s3, .Lpmxc_lp\@
    j    \failt
.Lpmxc_done\@:
.endm

# ---- bounded poll of a TCM word until nonzero -----------------------------
.macro WAITNZ addr, failt
    li   s3, 20000
    li   a0, \addr
.Lwn_lp\@:
    lw   t0, 0(a0)
    bnez t0, .Lwn_done\@
    addi s3, s3, -1
    bnez s3, .Lwn_lp\@
    j    \failt
.Lwn_done\@:
.endm

# ---- bounded poll of (word@addr & mask) != 0 ------------------------------
.macro WBIT addr, mask, failt
    li   s3, 20000
    li   a0, \addr
.Lwb_lp\@:
    lw   t0, 0(a0)
    andi t0, t0, \mask
    bnez t0, .Lwb_done\@
    addi s3, s3, -1
    bnez s3, .Lwb_lp\@
    j    \failt
.Lwb_done\@:
.endm

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                   # valid stack before any IRQ (IRQ_SV + dispatcher push)

    # zero the private mailboxes
    li   t0, AE_FLAGS
    sw   x0, 0(t0)
    li   t0, AE_CNT
    sw   x0, 0(t0)
    li   t0, RX_MB
    sw   x0, 0(t0)
    li   t0, RX_GOT
    sw   x0, 0(t0)
    li   t0, RXF_AMF
    sw   x0, 0(t0)
    li   t0, TX_SERVICED
    sw   x0, 0(t0)

    # ================= L0: clocks + reset defaults ====================
    li   a0, SYS_CLK_CR
    sw   x0, 0(a0)                    # SMCLK -> HFXT (I2C0 host core is smclk)

    # route P4.0/P4.1 to their SDA0/SCL0 alt-function (AF0). PxSEL selects the
    # alt-func plane; without it the I2C0 master's drive never reaches the pad.
    li   a0, GPIO3_SEL
    li   t1, 0x3
    sw   t1, 0(a0)

    li   a0, I2CT_CR
    lw   t0, 0(a0)
    bnez t0, wi2ct_fail              # I2CT0 CR resets 0
    li   a0, I2CT_SR
    lw   t0, 0(a0)
    bnez t0, wi2ct_fail              # I2CT0 SR resets 0

    # ================= L1: configure I2CT0 + route ====================
    li   a0, I2CT_CR
    li   t1, I2CT_CR_VAL
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wi2ct_fail          # CR readback proves the register path

    li   t0, IRTR_ENX
    li   t1, ENX_I2CT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wi2ct_fail          # HhENX bits 26/27 readback

    # ================= L2: configure I2C0 as master ===================
    li   a0, I2C0_CR
    li   t1, I2C0_CR_VAL
    sw   t1, 0(a0)                    # MEN | MDIV=1

    # ================= L3: master WRITE 0xC3 to 0x2A ==================
    li   a0, I2C0_FCR
    li   t1, FCR_MST
    sw   t1, 0(a0)                    # send START
    li   a0, I2C0_MTX
    li   t1, ADDR_WR
    sw   t1, 0(a0)                    # address byte (write) -> MasterWrite

    PMXC wi2ct_fail                  # wait address-byte transfer complete
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, MSR_MNR
    bnez t0, wi2ct_fail              # target must have ACKed its address (no NACK)
    li   t1, MSR_MXC
    sw   t1, 0(a0)                    # W1C MXC before the data byte

    li   a0, I2C0_MTX
    li   t1, WR_BYTE
    sw   t1, 0(a0)                    # data byte 0xC3

    # data_handler (vec 123, RXF) fires; with CSEN the target RX-stretches SCL
    # until the handler W1C-clears RXF -> proves D9/D11 on the write side.
    WAITNZ RX_GOT, wi2ct_fail
    li   a0, RX_MB
    lw   t0, 0(a0)
    li   t1, WR_BYTE
    bne  t0, t1, wi2ct_fail          # target received 0xC3
    li   a0, RXF_AMF
    lw   t0, 0(a0)
    li   t1, TSR_AMF
    bne  t0, t1, wi2ct_fail          # AMF was set at RXF time (address matched)
    li   a0, AE_CNT
    lw   t0, 0(a0)
    beqz t0, wi2ct_fail              # ae_handler (vec 122) ran on the match
    li   a0, AE_FLAGS
    lw   t0, 0(a0)
    andi t0, t0, TSR_AMF
    beqz t0, wi2ct_fail              # AE_FLAGS witnessed AMF

    PMXC wi2ct_fail                  # data-byte transfer complete
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)                    # W1C MXC
    li   a0, I2C0_FCR
    li   t1, FCR_MSP
    sw   t1, 0(a0)                    # STOP

    # ================= L4: master READ 0x5A from 0x2A (TX stretch) =====
    # clear the read-phase mailboxes and re-enable AEIE (the write's
    # ae_handler masked it). Do NOT preload I2CTTX -> the TXE handler stages
    # the byte while the target stretches SCL (CSEN=1), proving D11 end-to-end.
    li   t0, RX_GOT
    sw   x0, 0(t0)
    li   t0, TX_SERVICED
    sw   x0, 0(t0)
    li   t0, AE_FLAGS
    sw   x0, 0(t0)
    li   a0, I2CT_CR
    li   t1, I2CT_CR_VAL
    sw   t1, 0(a0)                    # re-enable AEIE

    li   a0, I2C0_FCR
    li   t1, FCR_MST
    sw   t1, 0(a0)                    # START
    li   a0, I2C0_MTX
    li   t1, ADDR_RD
    sw   t1, 0(a0)                    # address byte (read)

    PMXC wi2ct_fail                  # address transfer complete
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, MSR_MNR
    bnez t0, wi2ct_fail              # target ACKed the read-address
    li   t1, MSR_MXC
    sw   t1, 0(a0)                    # W1C MXC

    li   a0, I2C0_FCR
    li   t1, FCR_MRB
    sw   t1, 0(a0)                    # read one byte (target stretches -> TXE handler)

    PMXC wi2ct_fail                  # byte received
    li   a0, TX_SERVICED
    lw   t0, 0(a0)
    beqz t0, wi2ct_fail              # TXE handler staged I2CTTX under the stretch
    li   a0, I2C0_MRX
    lw   t0, 0(a0)
    li   t1, TX_BYTE
    bne  t0, t1, wi2ct_fail          # host received 0x5A
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)                    # W1C MXC
    li   a0, I2C0_FCR
    li   t1, FCR_MSP
    sw   t1, 0(a0)                    # STOP (NACK the last byte)

    WBIT I2CT_SR, TSR_STOPF, wi2ct_fail   # target saw the STOP (STOPF sticky)

    # ================= L5: negative check — write to 0x33 =============
    # a non-matching address must NOT set AMF and the master must see a NACK.
    li   a0, I2CT_SR
    li   t1, TSR_CLR_ALL
    sw   t1, 0(a0)                    # clear all target event flags first
    li   a0, AE_CNT
    lw   s5, 0(a0)                    # snapshot AE_CNT (must not advance)

    li   a0, I2C0_FCR
    li   t1, FCR_MST
    sw   t1, 0(a0)                    # START
    li   a0, I2C0_MTX
    li   t1, ADDR_NM
    sw   t1, 0(a0)                    # address 0x33 (write) — no target owns it

    PMXC wi2ct_fail                  # address transfer complete
    li   a0, I2C0_SR
    lw   t0, 0(a0)
    andi t0, t0, MSR_MNR
    beqz t0, wi2ct_fail              # master MUST see a NACK (nobody ACKed 0x33)
    li   a0, I2CT_SR
    lw   t0, 0(a0)
    andi t0, t0, TSR_AMF
    bnez t0, wi2ct_fail              # target AMF must stay CLEAR (no match)
    li   a0, AE_CNT
    lw   t0, 0(a0)
    bne  t0, s5, wi2ct_fail          # no AE IRQ fired for the mismatch
    li   a0, I2C0_SR
    li   t1, MSR_MXC
    sw   t1, 0(a0)                    # W1C MXC
    li   a0, I2C0_FCR
    li   t1, FCR_MSP
    sw   t1, 0(a0)                    # STOP

    RVTEST_PASS

wi2ct_fail:
    RVTEST_FAIL

    # ---- I2CT0 AE handler (vec 122, plain-ret). Accumulate the SR snapshot,
    # ---- bump the counter, MASK AEIE so irq_ae drops while AMF is preserved
    # ---- for the DATA handler, then W1C the framing/error flags EXCEPT AMF.
    # ---- t0-t2 dispatcher-saved; ra survives (ret). ----------------------
    .section .text.init
i2ct_ae_h:
    li   t0, I2CT_SR
    lw   t1, 0(t0)                   # SR snapshot
    li   t0, AE_FLAGS
    lw   t2, 0(t0)
    or   t2, t2, t1
    sw   t2, 0(t0)                   # accumulate every AE source ever seen
    li   t0, AE_CNT
    lw   t2, 0(t0)
    addi t2, t2, 1
    sw   t2, 0(t0)
    li   t0, I2CT_CR
    lw   t1, 0(t0)
    andi t1, t1, -9                  # clear AEIE (bit3) -> drop irq_ae, keep AMF sticky
    sw   t1, 0(t0)
    li   t0, I2CT_SR
    li   t1, TSR_CLR_NOTAMF
    sw   t1, 0(t0)                   # W1C framing/error flags (NOT AMF)
    ret

    # ---- I2CT0 DATA handler (vec 123, plain-ret). Demux RXF vs TXE. --------
i2ct_data_h:
    li   t0, I2CT_SR
    lw   t1, 0(t0)                   # SR snapshot
    andi t2, t1, TSR_RXF
    beqz t2, i2ct_dh_txe
    # RXF path: witness AMF, capture the byte, W1C RXF+AMF, flag done
    andi t2, t1, TSR_AMF
    li   t0, RXF_AMF
    sw   t2, 0(t0)                   # AMF bit as seen at RXF time (expect 0x4)
    li   t0, I2CT_RX
    lw   t2, 0(t0)
    li   t0, RX_MB
    sw   t2, 0(t0)                   # received byte
    li   t0, I2CT_SR
    li   t1, TSR_RXF_AMF
    sw   t1, 0(t0)                   # W1C RXF+AMF -> drop irq_data, release RX stretch
    li   t0, RX_GOT
    li   t1, 1
    sw   t1, 0(t0)
    ret
i2ct_dh_txe:
    andi t2, t1, 0x20                # TXE (bit5)
    beqz t2, i2ct_dh_ret            # neither RXF nor TXE -> spurious, just return
    li   t0, I2CT_TX
    li   t1, TX_BYTE
    sw   t1, 0(t0)                   # load I2CTTX -> clears TXE, releases TX stretch
    li   t0, TX_SERVICED
    li   t1, 1
    sw   t1, 0(t0)
i2ct_dh_ret:
    ret

    # ---- per-test IVT tail: arm 83/84/85 then slots 122/123 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00               # 83 msip -> park
    jal  zero, 0x0BB00               # 84 mtip -> park
    jal  zero, 0x0B100               # 85 meip -> env dispatcher (.isr_meip)
    .org 4*122                       # slot 122 @ 0x1E8
    jal  zero, i2ct_ae_h             # 122 = IRQB_I2CT0_AE
    jal  zero, i2ct_data_h           # 123 = IRQB_I2CT0_DATA
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
