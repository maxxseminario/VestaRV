#include "myshkin_s.h"




//001 0000 1000 1100 0000
#define SPI_CR_INIT 0x108C0 // Initial value for SPI Flash Control Register - 8 bit transfers

//001 0000 1000 1000 1000
#define SPI_CR_LOADBEEF 0x108C8 // Initial value for SPI Flash Control Register - 32 bit transfers 

// Boot by polling instead of interrupts 
#define SPI_TCIF_MASK           0x02 // SPI Transfer Complete Interrupt Flag
#define SPITEIF_MASK            0x01 // Mask for SPI Transfer Complete Interrupt Flag

// SPI Flash Slave Commands
#define FLASH_SLAVE_PU          0xAB // Flash Slave Power Up Command
#define FLASH_SLAVE_SRREAD      0xD7 // Flash Slave Status Register Read Command
#define FLASH_SLAVE_HFREAD      0x0B // Flash Slave High Frequency Read Command
#define FLASH_SLAVE_PU_DELAY    4000 // loop count; must cover AT45DB021E tRDPD = 35 us max from CS deassertion (4000 x 2-insn loop >= 40 us at 100MHz)
#define FLASH_SLAVE_PD          0xB9 // Flash Slave Power Down Command

# For dir, '1' means input on xcelium, write '1' in assembly for output 
#define P1_SEL_BOOT             (GPIO0_MISO_MASK | GPIO0_MOSI_MASK | GPIO0_SCK_MASK | GPIO0_TRAP_MASK) // Set GPIO Select Register for boot mode (MISO and BOOT to alt function, rest to GPIO)
#define SPI0_DIR_MASK           GPIO0_MISO_MASK  
//#define P1_DIR_BOOT             (GPIO0_MISO_MASK | GPIO0_BOOT_MASK) // Inputs 
//define P1_DIR_BOOT             (GPIO0_MOSI_MASK | GPIO0_CS_MASK | GPIO0_SCK_MASK) // Inputs 
#define P1_DIR_BOOT             (GPIO0_CS_MASK | GPIO0_TRAP_MASK) // CSFlash bit 1, Boot 0

// =============================================================================
// M12 single-ROM boot (Castalia, 4 harts). ALL FOUR harts reset to PC 0x0 and
// fetch this code from THE shared boot ROM through the mp_arbiter. _start
// dispatches on mhartid: hart 0 runs the real boot (SPI flash copy or the
// rv4th interpreter); harts 1-3 park in WFI until hart 0 loads and ignites
// them through the CLINT + the boot-loader mailboxes below.
//
// Tile loader protocol (every address is in the shared window; hart 0 writes
// the row FIRST, then sets CLINT msip[h]=1):
//   BOOT_MB_BASE + 0x10*h + 0x0 = SRC   (word-aligned source, shared space)
//   BOOT_MB_BASE + 0x10*h + 0x4 = LEN   (words to copy SRC -> TCM 0x8000;
//                                        0 = no copy, jump straight to ENTRY)
//   BOOT_MB_BASE + 0x10*h + 0x8 = ENTRY (PC the tile enters with)
// Tile entry ABI: sp = TILE_SP_INIT, everything else undefined; the tile's
// msip level is already cleared; the copy (if any) has filled TCM from 0x8000.
//
// Write-before-read contract (user decision, M11): shared RAM powers up
// UNKNOWN on silicon — hart 0 zeroes MB_ZERO_BASE..MB_ZERO_END (the whole
// mailbox/ledger region incl. these loader mailboxes) before any software
// can release a tile, so DONE==0-style parked-proofs are silicon-safe.
// =============================================================================
#define CLINT_MSIP_BASE     0x5000      // CLINT msip[h] = 0x5000 + 4*h
// Loader mailbox rows: {SRC,LEN,ENTRY} at BOOT_MB_BASE + 0x10*h, h=1..N-1.
// N-agnostic base (Argus A3): relocated 0x10400 -> 0x10500 so the rows (up to
// 0x10500+0x10*(N-1); block 0x10500-0x1061F at N=18) clear the sh-test scratch
// words below 0x10500 (shfault/shpwr) and stay inside MB_ZERO_END. This MUST
// stay equal to MP_BOOT_MB_BASE in verification/env/p/mp_boot.h.
#define BOOT_MB_BASE        0x10500     // loader mailbox rows (h=1..N-1 used)
#define MB_ZERO_BASE        0x10000     // zeroed region start
#define MB_ZERO_END         0x10800     // zeroed region end (exclusive)

// DP-S3 harvested boot (stage 4): PWRCTRL sampled the P6.6 strap at reset
// release; PWRSTS @+0x18 reports it. NFC0 (wound config) sits in the mutex
// page at 0x6200; GPIO5 (port 6) at 0x6400. On a config WITHOUT NFC the
// 0x6200 window aliases the MUTEX BANK: writes there are ignored/harmless,
// but a READ would CLAIM a mutex — the harvested path must NEVER read an
// NFC register.
#define PWRCTRL_BASE        0x4B00
#define PWR_STS             0x18        // PWRSTS word offset
#define PWR_STS_STRAP       0x04        // bit 2: 1 = harvested boot
#define PWR_STS_STRAPVLD    0x08        // bit 3: sample complete
#define GPIO5_BASE          0x6400
#define GPIO_PxAFS          0x2C        // AF-plane select (3-bit fields)
#define NFC0_BASE           0x6200
#define NFC_CR              0x00        // NFCEN(0) LISTEN(1); AUTOREAD(12) resets 1
#define NFC_UID             0x08
#define NFC_CFG             0x0C        // [15:0] ATQA, [23:16] SAK
#define NFC_IDX             0x18        // [5:0] IDX, [6] AINC, [8] SEL
#define NFC_DATA            0x1C        // payload byte window (lane 0)
#define IVT_MSIP_SLOT       (IVT_BASE_ADDR + 4*83)  // IVT slot 83 (CLINT msip) = 0x814C
#define RET_INSN            0x00008067  // 'jalr x0,0(ra)' — parked tile's IVT slot 83
#define TILE_SP_INIT        0xBFFC      // tile sp: top word of its own TCM

// vesta custom instructions (opcode 0x0b; encodings match the test env's
// riscv_test.h: iret = funct3 0, extinguish/ignite = funct3 1, funct7 0/1)
#define IRET        .insn r 0x0b, 0, 0, x0, x0, x0
#define EXTINGUISH  .insn r 0x0b, 1, 0, x0, x0, x0
#define IGNITE      .insn r 0x0b, 1, 1, x0, x0, x0

// Globals
.global main

    .section .text
    .globl _start
_start:
    // M12 mhartid dispatch — the very first thing every hart executes.
    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, tile_boot

spi_flash_boot:
    // Upon chip reset, chip will load program from SPI Flash memory to RAM

    //System Setup
    li a0, PERIPH_SYSTEM0_BASE
    sw zero, SYS_IRQ_CR(a0) // Disable all interrupts
    sw zero, SYS_BLOCK_PWR(a0) // Power on all blocks
    li sp, SP_INIT_VAL // Initialize Stack Pointer to the top of the TCM

    // M12 write-before-read contract: zero the shared-RAM mailbox region
    // (test/app ledger 0x10000-0x104FF + the loader mailboxes at 0x10500)
    // BEFORE any path that could release a tile. Tiles are parked in ROM
    // and touch no mailbox until their msip fires, so this cannot race.
    li a2, MB_ZERO_BASE
    li a3, MB_ZERO_END
zero_mailboxes:
    sw zero, 0(a2)
    addi a2, a2, 4
    bltu a2, a3, zero_mailboxes

    // DP-S3 harvested-boot strap: branch BEFORE any SPI/flash work. The
    // one-shot sample landed a few mclk after reset release (long before
    // this code), but poll STRAP_VALID anyway — cheap and robust. On a
    // normal board the strap pull-down reads 0 and this falls straight
    // through to the SPI boot with a4/a5 dead.
    li a3, PWRCTRL_BASE
harv_strap_poll:
    lw a4, PWR_STS(a3)
    andi a5, a4, PWR_STS_STRAPVLD
    beqz a5, harv_strap_poll
    andi a5, a4, PWR_STS_STRAP
    bnez a5, harvested_boot

    // Set Periphearl Base Addresses
    li a0, PERIPH_SPI0_BASE
    li a1, PERIPH_GPIO0_BASE

    //Get ready for SPI Flash Setup / RV4th Boot
    # sb zero, GPIO_PxREN(a1) // Disable GPIO Pullup/Pulldown Resistors
    li a2, P1_DIR_BOOT     // Set GPIO Direction Register for Flash (output)
    sb a2, GPIO_PxDIR(a1)   // Set GPIO Direction Register to output for CS Flash 
    li a2, P1_SEL_BOOT      // Set GPIO PSEL for boot mode
    sb a2, GPIO_PxSEL(a1)   // Set GPIO Select Register for boot mode

    // (myshkin-2025-11 lesson: no "preloaded constants" here. A stale
    // li a2, RAM0_BASE_ADDR in this spot leaked into the "deassert CS"
    // store below, so CS never rose after the ABh wake-up and the
    // AT45DB021E never left deep power-down on silicon. Every CS store
    // now loads its mask explicitly.)

check_boot_mode:
    lw a4, GPIO_PxIN(a1) // Read GPIO0 Input Register
    andi a4, a4, GPIO0_BOOT_MASK // Mask out all but boot mode bit
    beqz a4, main // If boot mode pin is low (rv4th mode), launch forth interpreter from ROM, otherwise, load program from flash


SPI_FlashSetup: 
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    //Setup SPI Mode 
    li a6, SPI_CR_INIT // Load SPI Flash Control Register Initialization Value
    sw a6, SPI_CR(a0) // Set SPI Flash Control Register

    # //Setup SPI1 (For testing.. TODO: Create separate fn for setting up all peripherals in boot)
    # # li a4, PERIPH_SPI1_BASE // Load SPI1 Base Address
    # # mv t0, a6 // Copy SPI Flash Control Register Initialization Value to t2
    # li   t1, 0x00040000    # t1 = 0xFFF7C000   (bit 18 is 0, rest are 1 in upper bits)
    # or   t0, t0, t1     # clear bit 18 of t0, leave other bits unchanged
    # sw t0, SPI_CR(a4) // Set SPI1 Control Register as slave 

    //Assert CS
    li a4, GPIO0_CS_MASK // Load CS Flash mask
    sw a4, GPIO_PxOUTC(a1) // Clear GPIO Output Register to clear (assert) CS bit

    //Write Flash Slave Power Up Command
    li a6, FLASH_SLAVE_PU // Load Flash Slave Power Up Command
    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register

    //Wait for PU command to send
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    //Deassert CS - REQUIRED by the AT45DB021E: the ABh opcode only takes
    //effect on the rising edge of CS, which is what starts the tRDPD
    //wake-up timer. (Fixed 2026-07: this store used to write a2, which
    //held RAM0_BASE_ADDR, so bit 0 (CS) never rose - the myshkin-2025-11
    //flash boot failure.)
    sw a4, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    //Wait for Flash Slave to power up (tRDPD = 35 us max, measured from CS deassertion)
    jal ra, flash_slave_power_up_delay

    //Assert CS
    sw a4, GPIO_PxOUTC(a1) // Clear GPIO Output Register to clear (assert) CS bit
    //Write Flash Slave Status Register Read Command
    //li a6, FLASH_SLAVE_SRREAD // Load Flash Slave Status Register Read Command
    li a6, FLASH_SLAVE_HFREAD // Load Flash Slave High Frequency Read Command
    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register
    //Wait for SRREAD command to send
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete


    li a6, SPI_CR_LOADBEEF // Load SPI Flash Control Register for loading beef command
    sw a6, SPI_CR(a0) // Set SPI Flash Control Register for loading beef command


    //Send 24 bit start address for reading SPI Flash memory, followed by 8 bit dummy byte
    sw zero , SPI_TX(a0) // Send 24 bit start address (0x000000) for reading SPI Flash memory
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    //clear SPI0SR
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    // Send a 0x00000000 to the SPI flash, during which time the SPI flash will respond with the command word
    sw zero, SPI_TX(a0) // Send 0x00000000 to the SPI Flash

    # Prepare for error checkin by loading upper and lower bounds of where SPI Flash may write in RAM
    li s2, RAM0_BASE_ADDR // Load RAM base address
    li s3, RAM0_BASE_ADDR + RAM_SIZE -4 // Load RAM end address


getCommandWord:

    // Get command word from SPI Flash
    jal ra, spi0_complete_read_init_read
    li a7, 0x10adbeef //load beef command 
    beq t0, a7, loadSegmentToRAM // Check if command word is 0x10adbeef
    li a7, 0xdeadbeef
    beq t0, a7, eraseSegmentFromRAM // Check if command word is 0xdeadbeef - Note: This is not tested.
    li a7, 0xcafebabe // Check if command word is 0xcafebabe
    beq t0, a7, executeProgram // Check if command word is
    //Program should never get here, but if it does, just loop forever
    //TODO: Throw trap error here 
    # j getCommandWord
    j force_trap	

loadSegmentToRAM:
    // Load segment to RAM
    // FORMAT:
	//	word[0]: dump segment command 0xloadbeef
	//	word[1]: start address of RAM segment to dump to
	//	word[2]: end address of RAM segment to dump to (not inclusive)
	//	word[3, ..., 3 + (end address - start address) / 4]: The words to dump to the RAM segment. Must be exactly (end address - start address) / 4 words long.
	jal ra, spi0_complete_read_init_read
    addi a2, t0, 0 // Store the start address of RAM segment to a2
    jal ra, spi0_complete_read_init_read
    addi a3, t0, 0 // Store the end address of RAM segment to a3

    //TODO: Do some input validation here to see if addresses are valid (RAM).
    bgeu a2, a3, force_trap	// If start address >= stop address, make a trap condition
    # s2 is RamStartAddress
    bltu a2, s2, force_trap	// If start address < peripheral memory start address, make a trap condition
	# s3 is RamStartAddress + RamSize -4 
	bltu s3, a3, force_trap	// If RAM end address < end address, make a trap condition

getNextProgramWord:
    jal ra, spi0_complete_read_init_read // Read next word from SPI Flash
    sw t0, 0(a2) // Store the word to RAM at address a2
    addi a2, a2, 4 // Increment address by 4 bytes (next word)
    bltu a2, a3, getNextProgramWord // If not reached end address, continue reading words

    // CS stays asserted: the whole RCF stream is ONE continuous-read frame
    // and getCommandWord just keeps clocking it. (The old "deassert CS"
    // here wrote the RAM end pointer to PxOUTS - a no-op on the CS bit,
    // and deasserting for real would kill the read in progress.)
    j getCommandWord // Go back to get next command word

eraseSegmentFromRAM:
    // Erase segment from RAM
    // FORMAT:
    //	word[0]: erase segment command 0xdeadbeef
    //	word[1]: start address of RAM segment to erase
    //	word[2]: end address of RAM segment to erase (not inclusive)
    //	word[3]: The value to write each word in the erase segment of the RAM as.
    jal ra, spi0_complete_read_init_read
    addi a2, t0, 0 // Store the start address of RAM segment to a2
    jal ra, spi0_complete_read_init_read
    addi a3, t0, 0 // Store the end address of RAM segment to a3
    //TODO: Do some input validation here to see if addresses are valid (RAM).

    # s2 is RamStartAddress
    # s3 is RamStartAddress + RamSize -4
    bgeu a2, a3, force_trap	// If start address >= stop address, make a trap condition
    bltu a2, s2, force_trap    // If start address < peripheral memory start address, make a trap condition
    bltu s3, a3, force_trap    // If RAM end address < end address, make a trap condition   


    jal ra, spi0_complete_read_init_read // Read next word from SPI Flash
    
eraseWord: 
    sw t0, 0(a2) // Store the word to RAM at address a2
    addi a2, a2, 4 // Increment address by 4 bytes (next word)
    bltu a2, a3, eraseWord // If not reached end address, continue erasing words

    // Deassert CS
    j getCommandWord // Go back to get next command word

clr_spi0sr: 
    not a6, zero // a6 = 0xFFFFFFFF
    sw a6, SPI_SR(a0) // Clear SPI Flash Status Register
    ret


spi0_complete_read_init_read:
    //a0 has spibase
    //Wait for SPIO0TX register to be empty
    lw s9, SPI_SR(a0) // Read SPI0SR
    andi a7, s9, SPITEIF_MASK // Check if SPITXEMT is set
    beqz a7, spi0_complete_read_init_read // If SPITXEMT is not set, loop back

    //Get next word for transmission (dont care about the value)
    sw zero, SPI_TX(a0) // Write 0x00000000 to SPI Flash Transmit Register

    //Wait for the transmission to complete
spi0_wait_until_tx_complete:
	lw a7, SPI_SR(a0)	// (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, SPI_TCIF_MASK	// Zero everything except SPITCIF
	beqz a7, spi0_wait_until_tx_complete	// Loop back again to read SPI0SR if SPITCIF is a 0 (aka wait until SPITCIF == 1, meaning the SPI transfer is complete)

	// Load the received word to register t0
	lw t0, SPI_RX(a0)	// (a0 = SPI_BASE) Read SPI0RX and store in t0. Reading SPI0RX also clears SPITCIF
	ret // pop return address and jump to it

// Function to delay for FLASH_SLAVE_PU_DELAY cycles
flash_slave_power_up_delay:
    // Delay loop for FLASH_SLAVE_PU_DELAY cycles
    li a6, FLASH_SLAVE_PU_DELAY // Load delay count
delay_loop:
    addi a6, a6, -1 // Decrement delay count
    bnez a6, delay_loop // If delay count is not zero, loop back
    ret

executeProgram:

    // Clear SPI0SR
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    //Deassert CS (Needed to put Flash slave in Idle state)
    li a2, GPIO0_CS_MASK // Load CS Flash mask
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    li a6, FLASH_SLAVE_PD // Load Flash Slave Power Down Command

    //assert CS
    sw a2, GPIO_PxOUTC(a1) // Set GPIO Output Register to clear (assert) CS bit

    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    // M19c bootrom fix (a): quiesce SPI0 across the PxSEL pin flip, then restore
    // the CR byte-identical. The flip releases GPIO0's SPI pads; the flip-instant
    // transient could otherwise reach FlashActive -> disable_clk_cpu
    // (= FlashActive, SPI.vhd:653) -> hart0 clk_cpu -> chip death (boot-end
    // "HAZARD 1"; pre-fix this killed irqctx/shirq at ~13.41 ms). Writing
    // SPI_CR=0 (spi_en=spi_fen=0) async-holds FlashActive=0 (SPI.vhd:555-564)
    // across the flip; the restore returns the post-boot CR byte-identical
    // (0x108C8) so the XIP state apps may rely on is preserved.
    // NOTE (2026-07-13): this closes HAZARD 1 but does NOT get the binding gate
    // smoke to 7/7 — irqctx/shirq are ALSO killed by a SEPARATE core X at the
    // IRET (M19 irtr0 in_service, the worst setup path), which is RTL, not
    // bootrom. See .devlog/2026-07-13-m19c-physical-reharden.md.
    // t2 is dead here (a0=SPI0 base, a1=GPIO0 base stay live; a2 is the only reg
    // clobbered between save and restore).
    lw t2, SPI_CR(a0)   // save SPI0 control register
    sw zero, SPI_CR(a0) // spi_en=0, spi_fen=0 -> FlashActive held 0 across the flip

    //Set GPIO0 to not alternative function mode (save TRAP pin)
    li a2, GPIO0_TRAP_MASK  // Load GPIO0 TRAP and CS Flash mask
    sw a2, GPIO_PxSEL(a1) // Set GPIO Select Register to not alternative function mode

    //Deassert CS
    li a2, GPIO0_CS_MASK // Load CS Flash mask
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    //Restore SPI0 CR byte-identical (post-boot XIP contract preserved)
    sw t2, SPI_CR(a0)   // post-boot SPI_CR == 0x108C8, unchanged from pre-M19c


    
    # //Set smclk to lfxt 
    li t0, PERIPH_SYSTEM0_BASE
    # li t1, 0x02 // Set smclk to lfxt
    # Set mclk to hfxt, and smclk to lftxt
    li t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    sw t1, SYS_CLK_CR(t0) // Write to System Clock Control Register
    li t1, 0X080 
    sw t1, SYS_DCO0_BIAS(t0) // Write to System DCO0 Bias Register
    sw t1, SYS_DCO1_BIAS(t0) // Write to System DCO1 Bias Register


    # # For testing 
    # li t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    # sw t1, SYS_CLK_CR(t0) // Write to System Clock Control Register

#     # Wait a while for clk to settle (For debugging, not needed in real application)
#     li t2, 1000
# wait_clk_settle:
#     addi t2, t2, -1
#     bnez t2, wait_clk_settle

    //Jump to the start of the program in RAM

    clear_regs:
	li x1, 0
	li sp, SP_INIT_VAL	
	li x3, 0
	li x4, 0
	li x5, 0
	li x6, 0
	li x7, 0
	li x8, 0
	li x9, 0
	li x10, 0
	li x11, 0
	li x12, 0
	li x13, 0
	li x14, 0
	li x15, 0
	li x16, 0
	li x17, 0
	li x18, 0
	li x19, 0
	li x20, 0
	li x21, 0
	li x22, 0
	li x23, 0
	li x24, 0
	li x25, 0
	li x26, 0
	li x27, 0
	li x28, 0
	li x29, 0
	li x30, 0
	li x31, 0

    j PROG_BASE_ADDR // Jump to the start of the program in RAM


    # TODO: Perhaps Delay for clk sel to settle. 

# Invalid intstruction that will induce trap state in the core.
force_trap:
	.word 0xFFFFFFFF


// =============================================================================
// M12 tile boot (harts 1-3): park in WFI until hart 0 ignites us, then run
// the ROM-resident loader and enter the program. Executes entirely from the
// shared ROM through the arbiter; the ONLY private state used is our own TCM
// (sp + one IVT slot) — nothing here depends on preloaded RAM.
// =============================================================================
tile_boot:
    // sp must be valid BEFORE any IRQ: IRQ_SV pushes the return PC at sp-4
    // and decrements sp (M5b contract).
    li sp, TILE_SP_INIT

    // Arm the msip vector in OUR private TCM. The IVT slot is one executable
    // word; 'jalr x0,0(ra)' lands in tile_msip_isr as long as ra holds its
    // address across the park — registers survive into the ISR, and nothing
    // in the park loop touches ra. (mtip, the only other hardwired-enabled
    // tile vector, cannot fire: mtimecmp resets all-ones.)
    li t0, IVT_MSIP_SLOT
    li t1, RET_INSN
    sw t1, 0(t0)
    la ra, tile_msip_isr

tile_park:
    EXTINGUISH                  // sleep; only our msip (IVT slot 83) wakes us
    j tile_park                 // paranoia: if ever resumed un-dispatched, re-park

tile_msip_isr:
    // msip IRQ entry (vectored through the slot-83 'ret'). The interrupted
    // context is the park loop, which we never return to — every register is
    // ours. The saved return PC sits at 0(sp) (IRQ_SV pushed at old sp-4 and
    // sp was decremented); we REDIRECT it to ENTRY before iret.
    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop

    // Clear OUR msip LEVEL through the arbiter first (or the IRQ re-fires
    // the moment we iret).
    slli t1, t0, 2
    li   t2, CLINT_MSIP_BASE
    add  t1, t1, t2
    sw   zero, 0(t1)

    // Read our loader mailbox row: BOOT_MB_BASE + 0x10*mhartid
    slli t1, t0, 4
    li   t2, BOOT_MB_BASE
    add  t1, t1, t2
    lw   t3, 0(t1)              // SRC   (shared-space word address)
    lw   t4, 4(t1)              // LEN   (words; 0 = no copy)
    lw   t5, 8(t1)              // ENTRY (PC to enter with)

    beqz t4, tile_isr_go
    li   t6, RAM0_BASE_ADDR     // our private TCM base (0x8000)
tile_copy:
    lw   t2, 0(t3)              // shared read through the arbiter
    sw   t2, 0(t6)              // private TCM write
    addi t3, t3, 4
    addi t6, t6, 4
    addi t4, t4, -1
    bnez t4, tile_copy

tile_isr_go:
    sw   t5, 0(sp)              // redirect the saved return PC to ENTRY
                                // (AFTER the copy — a full-TCM image overwrites
                                // the stack word too)
    IGNITE                      // cancel the sleep re-entry (M5b: ignite-before-iret)
    IRET                        // pops ENTRY -> the tile enters the program


// =============================================================================
// DP-S3 harvested boot (hart 0, strap-selected): the chip runs on harvested
// field power — NO SPI flash (the single most power-hungry cold-start step),
// no download. Provision the NFC tag identity + payload from ROM, arm LISTEN
// (AUTOREAD hardware then serves Type-2 READs with zero firmware in the
// loop), gate the tile rails, slow mclk, and sleep. The PGOOD boot gate
// (PWRCTRL hold-in-reset) already guaranteed the supercap can carry us.
// CLOCK STORY (kickoff landmine): the SPI path's SMCLK->LFXT switch is
// skipped, so choose EXPLICITLY — both MCLK and SMCLK stay on HFXT
// (= the SYS_CLK_CR reset value, written anyway to make the choice robust),
// then mclk divides /8 at the END (the parked loop needs no speed; dynamic
// power scales with the divide, the go/no-go verdict's service-loop point).
// Mailboxes were already zeroed above (write-before-read contract holds).
// =============================================================================
harvested_boot:
    li   a0, PERIPH_SYSTEM0_BASE
    sw   zero, SYS_CLK_CR(a0)      // EXPLICIT: MCLK=HFXT, SMCLK=HFXT

    // Gate every tile hart's switched rail: they are ROM-parked in WFI
    // (= quiesced, the sanctioned gating state). PWRCR masks the write to
    // bits NHARTS-1:1 and bit 0 is RO, so all-ones gates all tiles at ANY
    // hart count (this ROM is shared by every config, incl. N=18 Argus).
    li   a1, PWRCTRL_BASE
    li   a2, -1                    // 0xFFFFFFFF
    sw   a2, 0(a1)                 // PWRCR: gate harts 1..N-1

    // GPIO5 (port 6) AF plane for the six off-die NFC AFE wires P6.0-P6.5:
    // PxSEL=1 selects the AF planes for the outputs, PxAFS field=AF1 routes
    // both directions (input muxes key on AFS alone). P6.6/P6.7 (strap /
    // PGOOD) stay plain inputs. Benign when NFC is absent (planes are '0').
    li   a1, GPIO5_BASE
    li   a2, 0x3F
    sw   a2, GPIO_PxSEL(a1)
    li   a2, 0x9249                // pins 0-5 3-bit AFS fields = "001" (AF1)
    sw   a2, GPIO_PxAFS(a1)

    // NFC0 tag provisioning (WRITES ONLY — see the alias warning at the
    // #defines). UID/ATQA/SAK are the ROM defaults a fielded app replaces
    // by relaunching with real firmware; the payload is an honest 3-byte
    // status record: 'H','V' + the PWRSTS snapshot from the strap poll
    // (still live in a4: pgood/field/strap bits — the "sensor read" of the
    // base chip).
    li   a1, NFC0_BASE
    li   a2, 0xC0FFEE01            // 4-byte UID (ROM default identity)
    sw   a2, NFC_UID(a1)
    li   a2, 0x00000044            // ATQA=0x0044, SAK=0x00 (Type-2 profile)
    sw   a2, NFC_CFG(a1)
    li   a2, 0x40                  // IDXSEL=0 (payload), AINC=1, IDX=0
    sw   a2, NFC_IDX(a1)
    li   a2, 0x48                  // 'H'
    sw   a2, NFC_DATA(a1)
    li   a2, 0x56                  // 'V'
    sw   a2, NFC_DATA(a1)
    sw   a4, NFC_DATA(a1)          // PWRSTS low byte (lane 0 only is consumed)
    // Arm LISTEN with a BYTE store to CR lane 0 (NFCEN|LISTEN): a full-word
    // store's lane-1 zeros would CLEAR the AUTOREAD reset default (bit 12).
    li   a2, 0x03
    sb   a2, NFC_CR(a1)

    // Arm IVT slot 83 (our own TCM) with 'ret' + ra -> the stray-msip ISR
    // below, so an unexpected msip is harmless: clear the level, iret with
    // NO ignite — the hart returns to its sleep (M5b: iret without ignite
    // resumes the sleeping state). sp has been valid since spi_flash_boot.
    li   a2, RET_INSN
    li   a3, IVT_MSIP_SLOT
    sw   a2, 0(a3)
    la   ra, harv_stray_isr

    // Slow the service clock LAST (the management hart may reconfigure:
    // tiles are gated, no other master in flight): mclk /8, smclk undivided.
    li   a2, 0x03
    sw   a2, SYS_CLK_DIV_CR(a0)

harv_park:
    EXTINGUISH                     // sleep; AUTOREAD serves readers in HW
    j harv_park                    // paranoia: re-park if ever resumed

harv_stray_isr:
    li   t0, CLINT_MSIP_BASE
    sw   zero, 0(t0)               // clear msip[0] (or the IRQ re-fires)
    IRET                           // no IGNITE: return to the sleep state


# VestaRV Documentation
.section .vestarv_doc, "ax"
vestarv_id:
    .asciz "Myshkin \November, 2025\nThe first instantiation of VestaRV.\nDesigned by Maxx Seminario featuring ECS by Seth McRobert.\nShe herself is my best apology for all her accusations. \n\nWhat beautiful things there are at every step, even the most hopeless man must feel so beautiful! \n"

# for now, 4th code here 
# main: 
#     jal zero, main // Jump to the start of the forth interpreter in ROM




