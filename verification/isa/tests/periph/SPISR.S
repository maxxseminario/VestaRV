

#*****************************************************************************
# SPISR.S
#-----------------------------------------------------------------------------
#
# Test SPI peripheral(s) instruction.
#

# ---------------------------------------------------------------
# RISC-V Assembly: SPI Peripheral Master & Slave Mode Test Loops
# - GP register (gp = x3) stores TestNum.
# - In the center of the innermost loop, construct the SPI control word
#   from the loop variables and store it in register s1.
# - The control word format (matching SPIxCR):
#   [18] spi_mode | [17] spi_tx_sb | [16] spi_rx_sb | [15:8] spi_br
#   | [7] spi_en | [6] spi_msb | [5] spi_tcie | [4] spi_teie
#   | [3:2] spi_dl | [1] spi_cpol | [0] spi_cpha
# - For test, use loop variables for relevant bits; others (spi_br, spi_en, spi_tcie, spi_teie) set to 0.
# Test 0: Dummy Transfer
# Test (Odd 1-191) Master (SPI0) RX & Slave (SPI1) TX Tests 
# Test (Even 2-192) Master (SPI1) TX & Slave (SPI0) RX Tests 
# Test (Odd 193-385) Master (SPI1) RX & Slave (SPI0) TX Tests 
# Test (Even 194-384) Master (SPI0) TX & Slave (SPI1) RX Tests 
# ---------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"


RVTEST_RV64U
RVTEST_CODE_BEGIN
INIT_XREG 
 
#  TODO: Test SR correct at all stages

spi_test:

    beqz t0, spi0_m_addr_set
spi1_m_addr_set:

    li a0, PERIPH_SPI1_BASE
    li a1, PERIPH_GPIO1_BASE
    li a2, PERIPH_SPI0_BASE
    li a3, PERIPH_GPIO0_BASE
    jal ra, INIT_GPIO_MSPI
    jal ra, INIT_GPIO_SSPI
    j begin_test_loops

spi0_m_addr_set:
    li a0, PERIPH_SPI0_BASE
    li a1, PERIPH_GPIO0_BASE
    li a2, PERIPH_SPI1_BASE
    li a3, PERIPH_GPIO1_BASE
    jal ra, INIT_GPIO_MSPI
    jal ra, INIT_GPIO_SSPI
    li s0, 0              # SPISM = 0 (master mode)
    li gp, 0              # TestNum = 0  (gp register = x3)

begin_test_loops:

    li t1, 0              # SPITXSB_i = 0
l_SPITXSB_loop:
    li s11, 2
    bgeu t1, s11, l_SPITXSB_end #May need to change, orig bgt

    li t2, 0              # SPIRXSB_i = 0
l_SPIRXSB_loop:
    li s11, 2
    bgeu t2, s11, l_SPIRXSB_end

    li t3, 0              # SPICPOL_i = 0
l_SPICPOL_loop:
    li s11, 2
    bgeu t3, s11, l_SPICPOL_end

    li t4, 0              # SPICPHA_i = 0
l_SPICPHA_loop:
    li s11, 2
    bgeu t4, s11, l_SPICPHA_end

    li t5, 0              # SPIMSB_i = 0
l_SPIMSB_loop:
    li s11, 2
    bgeu t5, s11, l_SPIMSB_end

    li t6, 0              # SPIDL_i = 0
l_SPIDL_loop:
    li s11, 3             # SPIDL_i can take values 0-2 (3 is not allowed)
    bgeu t6, s11, l_SPIDL_end
    

# TODO: Iterate through additional values, such as interrupt enables and sim
    # ----------- Construct SPIxCR Control Word -------------
    # spi_mode (bit 18)    = s0        # (SPISM, 0 for master)
    # spi_tx_sb (bit 17)   = t1        # (SPITXSB_i)
    # spi_rx_sb (bit 16)   = t2        # (SPIRXSB_i)
    # spi_br   (15:8)      = 0         # (set to 0 for test)
    # spi_en   (7)         = 1        
    # spi_msb  (6)         = t5        # (SPIMSB_i)
    # spi_tcie (5)         = 1         # (set to 1 for test)
    # spi_teie (4)         = 1         # (set to 1 for test)
    # spi_dl   (3:2)       = t6        # (SPIDL_i, 2 bits)
    # spi_cpol (1)         = t3        # (SPICPOL_i)
    # spi_cpha (0)         = t4        # (SPICPHA_i)

# TODO: Is test0 skipping a test case? ie is test 0 and test 1 the same 

spi_test_individual:
    jal ra, set_mcr                
    jal ra, set_scr               
    beqz gp, dummy_tx
    mv a7, gp                           # tx_value for master
    jal ra, spi_srx_comp                # returned in s10
    # Read Slave SR
    jal ra, assert_cs_spi
    jal ra, spi_transmission
    # TEST_SPI_SSR(gp, 7)
    addi gp, gp, 1
    TEST_SPI_TX_SRX(gp, s10);   # Test Slave RX
    addi gp, gp, 1
    # TEST_SPI_MSR(gp, 3)                 # Test Master SR (before reading RX)                   
    not a7, a7                          # tx_value for slave 
    jal ra, spi_srx_comp                # returned in s10
    addi gp, gp, 1                      
    TEST_SPI_MRX(gp, s10)
    jal ra, deassert_cs_spi
  
    addi gp, gp, 1        

    addi t6, t6, 1
    j l_SPIDL_loop
l_SPIDL_end:

    addi t5, t5, 1
    j l_SPIMSB_loop
l_SPIMSB_end:

    addi t4, t4, 1
    j l_SPICPHA_loop
l_SPICPHA_end:

    addi t3, t3, 1
    j l_SPICPOL_loop
l_SPICPOL_end:

    addi t2, t2, 1
    j l_SPIRXSB_loop
l_SPIRXSB_end:

    addi t1, t1, 1
    j l_SPITXSB_loop
l_SPITXSB_end:


# For now, not do this 
# beqz t0, spi_test_master_switch


TEST_PASSFAIL


# Clear SPI Flash Status Register, assumes base address of spi periph is stored in s9.
clr_spisr:
    not a6, zero // a6 = 0xFFFFFFFF
    sw a6, SPI_SR(s9) // Clear SPI Flash Status Register
    ret

dummy_tx:

    jal ra, assert_cs_spi
    not a6, zero                   /* a6 = 0xFFFFFFFF */ 
        sw a6, SPI_SR(a0)       /* Clear SPI0 Flash Status Register */ 
        sw a6, SPI_SR(a2)       /* Clear SPI1 Flash Status Register */ 
        sw zero, SPI_TX(a0)      /* Data Transfer (Transfer anything) */ 
    spi0_wait_until_dummy_tx_complete: 
        lw s3, SPI_SR(a0)          /* Wait for tx to complete: Read Status Register */ 
        andi s3, s3, SPI_TCIF_MASK;                /* Check if tx is complete */ 
        beqz s3, spi0_wait_until_dummy_tx_complete /* If not complete, loop */
        sw a6, SPI_SR(a0)       /* Clear SPI Flash Status Register */ 
        sw a6, SPI_SR(a2)       /* Clear SPI Flash Status Register */ 
        # jal ra, deassert_cs_spi
        li gp, 1
        j spi_test_individual
    
spi_test_master_switch:
    # Store Addresses for the duration of the tests next round of tests
    li t0, 1
    j spi_test

# Assumes MSPI GPIO_base_address is stored in a1
INIT_GPIO_MSPI:
    li t1, 0x0E
    li t2, 0x00
    li t3, 0x0D         //Only miso in, rest out
    sw t1, GPIO_PxSEL(a1)      /*PxSEL - offset 9 bytes  */ 
    sw t2, GPIO_PxOUT(a1)      /*PxOUT - offset 1 bytes  */ 
    sw t3, GPIO_PxDIR(a1)      /*PxDIR - offset 5 bytes  */      
    sw t2, GPIO_PxREN(a1)      /*PxREN - offset 10 bytes  */
    ret

# Assumes SSPI GPIO_base_address is stored in a3
INIT_GPIO_SSPI:
    li t1, 0x0E
    li t2, 0x00
    li t3, 0x02         //Only miso out, rest in
    sw t1, GPIO_PxSEL(a3)      /*PxSEL - offset 9 bytes  */ 
    sw t2, GPIO_PxOUT(a3)      /*PxOUT - offset 1 bytes  */ 
    sw t3, GPIO_PxDIR(a3)      /*PxDIR - offset 5 bytes  */      
    sw t2, GPIO_PxREN(a3)      /*PxREN - offset 10 bytes  */
    ret

# Assume mspi base address in a0
clr_mspi_sr:
    not a6, zero
    sw a6, SPI_SR(a0)
    ret

# Assume sspi base address in a2
clr_sspi_sr:
    not a6, zero
    sw a6, SPI_SR(a2)
    ret

# Assumes the GPIO base address corresponding to the spi mster is stored in a1
assert_cs_spi:
    li s2, GPIO0_CS_MASK
    sw s2, GPIO_PxOUTC(a1)
    ret

# Assumes the GPIO base address corresponding to the spi mster is stored in a1
deassert_cs_spi:
    li s2, GPIO0_CS_MASK
    sw s2, GPIO_PxOUTS(a1)
    ret

# Assumes dl value in t6, data stored in s10 
spi_dl_mask:                              \
    beqz    t6, dl00_mask;              /* if dl == 0, mask 0xFF (1 byte) */ \
    li      s9, 1;                          /* s9 = 1 */ \
    beq     t6, s9, dl01_mask;          /* if dl == 1, mask 0xFFFF (2 bytes) */ \
    j       dl_mask_done;                   /* else (dl == 2), do nothing */ \
dl00_mask:                                                     \
    li      s9, 0xFF;                                      \
    and     s10, s10, s9;                        \
    j       dl_mask_done;                                  \
dl01_mask:                                                     \
    li      s9, 0xFFFF;                                    \
    and     s10, s10, s9;                        \
dl_mask_done:
    ret


set_mcr: \
    sll     s1, s0, 18;                /* s1 = s0 << 18 (spi_mode) */ \
    sll     s2, t1, 17;                /* s2 = t1 << 17 (spi_tx_sb) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    sll     s2, t2, 16;                /* s2 = t2 << 16 (spi_rx_sb) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    li      s2, 1;                     /* s2 = 1 */ \
    sll     s2, s2, 7;                 /* s2 = 1 << 7 (spi_en) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    sll     s2, t5, 6;                 /* s2 = t5 << 6 (spi_msb) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    li      s2, 1;                     /* s2 = 1 */ \
    sll     s2, s2, 5;                 /* s2 = 1 << 5 (tcie) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    li      s2, 1;                     /* s2 = 1 */ \
    sll     s2, s2, 4;                 /* s2 = 1 << 4 (spi_teie) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    andi    s2, t6, 0x3;               /* s2 = t6 & 0x3 (spi_dl) */ \
    sll     s2, s2, 2;                 /* s2 <<= 2 */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    sll     s2, t3, 1;                 /* s2 = t3 << 1 (spi_cpol) */ \
    or      s1, s1, s2;                /* s1 |= s2 */ \
    or      s1, s1, t4;                /* s1 |= t4 (spi_cpha) */ \
    sw      s1, SPI_CR(a0);      /* Write s1 to SPI_CR(a0) */ \
    j clr_mspi_sr

set_scr: \
      li      s2, 0;                          /* s2 = 0 */ \
      li      s3, 0;                          /* s3 = 0 */ \
      li      s4, 0;                          /* s4 = 0 */ \
  compute_scpol: \
      andi    s3, s1, 0x01;                   /* s3 = s1 & 0x01 (spi_cpha) */ \
      andi    s4, s1, 0x02;                   /* s4 = s1 & 0x02 (spi_cpol) */ \
      srai    s4, s4, 1;                      /* s4 = s4 >> 1 (spi_cpol to bit 0) */ \
      xor     s4, s4, s3;                     /* s4 = s4 ^ s3 (invert if spi_cpha set) */ \
      xori    s4, s4, 0x01;                   /* s4 = s4 ^ 1 (invert lsb) */ \
      slli    s4, s4, 1;                      /* s4 = s4 << 1 (spi_cpol to bit 1) */ \
      li      s5, ~0x02;                      /* s5 = ~0x02 */ \
      and     s1, s1, s5;                     /* s1 = s1 & s5 (clear spi_cpol bit) */ \
      or      s1, s1, s4;                     /* s1 = s1 | s4 (set spi_cpol bit) */ \
  compute_sspien: \
      li      s2, SPI_MODE_MASK;                /* s2 = SPI_MODE_MASK */ \
      or      s1, s1, s2;                     /* s1 = s1 | s2 (set enable) */ \
      sw      s1, SPI_CR(a2);           /* Write s1 to SPI_CR(a2) */ \
      j clr_sspi_sr  

# Assumes tx value is stored in a7 and rx_expected is s10
spi_srx_comp: \
    li      s5, 0;                          /* s2 = 0 */ \
    andi    s9, t6, 0x3;                             /* s9 = t6(SPIDL_i) & 0x3 */ \
    beqz    s9, spi_srx_comp_dl00;                    /* if SPIDL == 0 ("00"): 8 bits */ \
    li      s5, 1;                                   /* s5 = 1 */ \
    beq     s9, s5, spi_srx_comp_dl01;                /* if SPIDL == 1 ("01"): 16 bits */ \
    /* case others (24/32 bits) */ \
    xor     s4, t1, t2;                              /* s4 = t1 ^ t2 */ \
    beqz    s4, spi_srx_comp_dl_others_no_swap;       /* If t1 == t2, no swap */ \
    /* Otherwise, swap */ \
    andi    s6, a7, 0xFF;                    /* s6 = a7[7:0] */ \
    srli    s7, a7, 8;                       /* s7 = a7 >> 8 */ \
    andi    s7, s7, 0xFF;                            /* s7 = a7[15:8] */ \
    srli    s8, a7, 16;                      /* s8 = a7 >> 16 */ \
    andi    s8, s8, 0xFF;                            /* s8 = a7[23:16] */ \
    srli    s5, a7, 24;                      /* s5 = a7 >> 24 */ \
    andi    s5, s5, 0xFF;                            /* s5 = a7[31:24] */ \
    slli    s6, s6, 24;                              /* s6 = a7[7:0]   << 24 */ \
    slli    s7, s7, 16;                              /* s7 = a7[15:8]  << 16 */ \
    slli    s8, s8, 8;                               /* s8 = a7[23:16] << 8  */ \
    or      s6, s6, s7;                              /* s6 = s6 | s7 */ \
    or      s6, s6, s8;                              /* s6 = s6 | s8 */ \
    or      s10, s6, s5;                 /* s10 = s6 | s5 (reversed bytes) */ \
    j       spi_srx_comp_done;                        /* done */ \
spi_srx_comp_dl_others_no_swap: \
    mv      s10, a7;             /* s10 = a7 (no rearrange) */ \
    j       spi_srx_comp_done;                        /* done */ \
spi_srx_comp_dl01: \
    xor     s4, t1, t2;                              /* s4 = t1 ^ t2 */ \
    beqz    s4, spi_srx_comp_dl01_no_swap;            /* If t1 == t2, no swap */ \
    /* Otherwise swap */ \
    andi    s6, a7, 0x00FF;                  /* s6 = a7[7:0] */ \
    srli    s7, a7, 8;                       /* s7 = a7 >> 8 */ \
    andi    s7, s7, 0x00FF;                          /* s7 = a7[15:8] */ \
    slli    s6, s6, 8;                               /* s6 = a7[7:0] << 8 */ \
    or      s10, s6, s7;                 /* s10 = [15:8]:a7[7:0], [7:0]:a7[15:8] */ \
    j       spi_srx_comp_done;                        /* done */ \
spi_srx_comp_dl01_no_swap: \
    mv      s10, a7;             /* s10 = a7 (no rearrange) */ \
    j       spi_srx_comp_done;                        /* done */ \
spi_srx_comp_dl00: \
    mv      s10, a7;             /* s10 = a7 (8-bit, never swap) */ \
    j       spi_srx_comp_done;                        /* done */ \
spi_srx_comp_done: \
    j spi_dl_mask 

# Assumes tx_value is in a7, computes slave tx value and stores it in a5
spi_transmission:
    not a6, zero;                   /* a6 = 0xFFFFFFFF */ \
    sw a6, SPI_SR(a0);       /* Clear SPI0 Flash Status Register */ \
    sw a6, SPI_SR(a2);       /* Clear SPI1 Flash Status Register */ \
    # # ASSERT_SPI_CS(a1);         /* Assert CS for SPI0 */ \
    # li s2, GPIO0_CS_MASK
    # sw s2, GPIO_PxOUTC(a1)         #Assert CS
    not a5, a7;               /* s7 = ~a7 */ \
    sw a5, SPI_TX(a2);      /* Slave should transmit inverse of a7 to master*/ \
    sw a7, SPI_TX(a0);      /* Data Transfer */ \
spi0_wait_until_mtx_complete: \
    lw s3, SPI_SR(a0);          /* Wait for tx to complete: Read Status Register */ \
    andi s3, s3, SPI_TCIF_MASK;                /* Check if tx is complete */ \
    beqz s3, spi0_wait_until_mtx_complete; \
    ret


RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

tdat:
tdat1:  .byte 0xff
tdat2:  .byte 0x00
tdat3:  .byte 0xf0
tdat4:  .byte 0x0f

RVTEST_DATA_END