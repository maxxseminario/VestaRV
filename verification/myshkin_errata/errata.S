# Each result is stored to the signature at 0x9000; word n is at offset 4n.
    .option norvc
    .section .text.init
    .globl _start
_start:
    li   s0, 0x9000          # signature
    li   s1, 0x9100          # load data: 0x11223344 0x55667788
    # xori: control immediate, then the defective one
    li   a1, 0xFFF7FFFF
    xori a2, a1, 0x81
    sw   a2, 0(s0)           # 0  expect fff7ff7e
    xori a2, a1, 0x80
    sw   a2, 4(s0)           # 1  expect fff7ff7f
    # loads, aligned control then each offset
    lw   a2, 0(s1)
    sw   a2, 8(s0)           # 2  expect 11223344
    lw   a2, 1(s1)
    sw   a2, 12(s0)          # 3  spec: trap, or 88112233
    lw   a2, 2(s1)
    sw   a2, 16(s0)          # 4  spec: trap, or 77881122
    lw   a2, 3(s1)
    sw   a2, 20(s0)          # 5  spec: trap, or 66778811
    lhu  a2, 1(s1)
    sw   a2, 24(s0)          # 6  spec: trap, or 00002233
    lhu  a2, 3(s1)
    sw   a2, 28(s0)          # 7  spec: trap, or 00008811
    # stores into a zeroed pair of words
    li   s2, 0x9110
    li   a3, 0xAABBCCDD
    sw   a3, 1(s2)
    lw   a2, 0(s2)
    sw   a2, 32(s0)          # 8  spec: trap, or bbccdd00
    lw   a2, 4(s2)
    sw   a2, 36(s0)          # 9  spec: trap, or 000000aa
    sw   zero, 0(s2)
    sw   zero, 4(s2)
    sh   a3, 1(s2)
    lw   a2, 0(s2)
    sw   a2, 40(s0)          # 10 spec: trap, or 00ccdd00
    sw   zero, 0(s2)
    sh   a3, 3(s2)
    lw   a2, 0(s2)
    sw   a2, 44(s0)          # 11 spec: trap, or dd000000
    lw   a2, 4(s2)
    sw   a2, 48(s0)          # 12 spec: trap, or 000000cc
    # CSR: csrrw must return the old value, never the value written
    li   t1, 0x00ABCD00
    csrw mcycle, zero
    nop
    nop
    .globl csr_rw
csr_rw:
    csrrw t2, mcycle, t1
    nop
    nop
    sw   t2, 52(s0)          # 13 expect a small count, never 00abcd00
    # jalr must clear bit 0 of its target; auipc shows whether the PC stayed odd.
    la   a4, odd_target
    addi a4, a4, 1
    jalr a5, 0(a4)
    .align 2
odd_target:
    auipc a4, 0
    andi a4, a4, 3
    sw   a4, 56(s0)          # 14 expect 0
    # Clear the odd PC again so the rest of the run is unaffected.
    la   a4, even_target
    jr   a4
    .align 2
even_target:
    # div/rem with rd equal to a source. Distinct-rd results are the control.
    li   a1, 100
    li   a2, 7
    div  a3, a1, a2
    sw   a3, 60(s0)          # 15 expect 0000000e (control)
    div  a1, a1, a2
    sw   a1, 64(s0)          # 16 expect 0000000e
    li   a1, 100
    div  a2, a1, a2
    sw   a2, 68(s0)          # 17 expect 0000000e
    li   a2, 7
    rem  a1, a1, a2
    sw   a1, 72(s0)          # 18 expect 00000002
    li   a1, 100
    rem  a2, a1, a2
    sw   a2, 76(s0)          # 19 expect 00000002
    # c.addi16sp, negative then positive
    li   sp, 0x9200
    .option rvc
    c.addi16sp sp, -32
    .option norvc
    sw   sp, 80(s0)          # 20 expect 000091e0
    li   sp, 0x9200
    .option rvc
    c.addi16sp sp, 32
    .option norvc
    sw   sp, 84(s0)          # 21 expect 00009220 (control)
    # Compressed jumps must link pc+2. Store the link offset from the jump.
    la   t0, cjalr_tgt
    .option rvc
cjalr_at:
    c.jalr t0
    c.nop
    c.nop
    .option norvc
    .align 2
cjalr_tgt:
    la   t1, cjalr_at
    sub  t1, ra, t1
    sw   t1, 88(s0)          # 22 expect 00000002
    .option rvc
cjal_at:
    c.jal cjal_tgt
    c.nop
    c.nop
    .option norvc
    .align 2
cjal_tgt:
    la   t1, cjal_at
    sub  t1, ra, t1
    sw   t1, 92(s0)          # 23 expect 00000002
#ifdef CHIP
    # Full-chip additions. Results leave through the a0 port: see stream.
    li   s3, 0x4900          # SYSTEM0
    sw   zero, 0(s3)         # SMCLK from HFXT, as the periph tests do
    # Watchdog, cdiv 0: a rising edge of counter bit 0 must set the flag.
    li   t0, 0x5f3759df
    sw   t0, 0x30(s3)
    li   t0, 0x82            # EN | IE
    sw   t0, 0x34(s3)
    li   t1, 400
1:  addi t1, t1, -1
    bnez t1, 1b
    lw   t0, 0x38(s3)
    sw   t0, 96(s0)          # 24 WDT_SR, expect bit 1 set
    lw   t0, 0x3c(s3)
    sw   t0, 100(s0)         # 25 WDT_VAL, nonzero: the counter runs (control)
    li   t0, 0x5f3759df
    sw   t0, 0x30(s3)
    sw   zero, 0x34(s3)
    # UART: the bench cross-wires UART0 and UART1, so UART0 can receive without transmitting.
    li   s4, 0x4400
    li   s5, 0x4500
    li   s6, 0x4100
    li   t0, 0xF0
    sw   t0, 0x24(s6)        # GPIO1 PxSEL
    li   t0, 1
    sw   t0, 8(s4)
    sw   t0, 8(s5)
    li   t0, 0x20
    sw   t0, 0(s4)
    sw   t0, 0(s5)
    li   t0, 3
    sw   t0, 4(s4)
    sw   t0, 4(s5)
    # Real overrun: two frames into UART0, the first left unread.
    li   t0, 0x5A
    sw   t0, 0x10(s5)
1:  lw   t0, 4(s4)
    andi t0, t0, 4
    beqz t0, 1b
    li   t0, 3
    sw   t0, 4(s5)
    li   t0, 0xA6
    sw   t0, 0x10(s5)
1:  lw   t0, 4(s5)
    andi t0, t0, 1
    beqz t0, 1b
    li   t1, 400
1:  addi t1, t1, -1
    bnez t1, 1b
    lw   t0, 4(s4)
    sw   t0, 104(s0)         # 26 UART0 SR, expect OVF (bit 3) set
    lw   t0, 0xC(s4)
    # False overrun: UART0 transmits, keeps UTCIF, then receives one frame into an empty buffer.
    li   t0, 3
    sw   t0, 4(s4)
    li   t0, 0x33
    sw   t0, 0x10(s4)
1:  lw   t0, 4(s4)
    andi t0, t0, 1
    beqz t0, 1b
    li   t1, 400
1:  addi t1, t1, -1
    bnez t1, 1b
    lw   t0, 0xC(s5)
    li   t0, 0x44
    sw   t0, 0x10(s5)
1:  lw   t0, 4(s4)
    andi t0, t0, 4
    beqz t0, 1b
    li   t1, 40
1:  addi t1, t1, -1
    bnez t1, 1b
    lw   t0, 4(s4)
    sw   t0, 108(s0)         # 27 UART0 SR, expect OVF (bit 3) clear
    lw   t0, 0xC(s4)
    sw   t0, 112(s0)         # 28 received byte, expect 00000044 (control)
    li   s8, 0
    li   s9, 29
    jal  ra, stream
    # NPU run with the CSR read at each offset after the start, to land in the freeze.
    li   s7, 0x4A00
    li   t1, 0x00ABCD00
    .macro NPUTRY n, off
    csrw mcycle, zero
    li   t0, 0x10101
    sw   t0, 0(s7)
    .rept \n
    nop
    .endr
    csrrw t2, mcycle, t1
    sw   t2, \off(s0)
    .endm
    NPUTRY 0, 116            # 29
    NPUTRY 1, 120            # 30
    NPUTRY 2, 124            # 31
    NPUTRY 3, 128            # 32
    NPUTRY 4, 132            # 33
    # mcycle runs on the free clock, so a large count shows the CPU was frozen.
    csrw mcycle, zero
    nop
    nop
    nop
    nop
    csrr t2, mcycle
    sw   t2, 136(s0)         # 34 idle count (control)
    li   t0, 0x10101
    csrw mcycle, zero
    sw   t0, 0(s7)
    nop
    nop
    nop
    nop
    csrr t2, mcycle
    sw   t2, 140(s0)         # 35 count across an NPU run
    lw   t0, 0(s7)
    sw   t0, 144(s0)         # 36 NPUCR straight after the run
    li   s8, 29
    li   s9, 37
    jal  ra, stream
#endif
    # c.lui x0,1 is a HINT: legal code continues. The defect stops the core.
    li   a0, 0x600D0001
    .option rvc
    .hword 0x6005
    .option norvc
    li   a0, 0xCAFEBABE
1:  j    1b
#ifdef CHIP
    # Send words s8..s9-1 through a0 as marker A5A50000+n, then the value, with a gap
    # long enough for the bench to sample each one.
stream:
    mv   s10, ra
2:  li   a0, 0xA5A50000
    add  a0, a0, s8
    jal  ra, gap
    slli t0, s8, 2
    add  t0, t0, s0
    lw   a0, 0(t0)
    jal  ra, gap
    addi s8, s8, 1
    bne  s8, s9, 2b
    jr   s10
gap:
    li   t1, 60
1:  addi t1, t1, -1
    bnez t1, 1b
    ret
#endif
