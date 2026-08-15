-------------------------------------------------------------------------------
-- dma_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the DMA controller testbench (tb/DMA_tb.vhd).
-- DMA.vhd is being written in parallel against the same FROZEN design this bench targets (~/vesta_docs/digperiphs/dma_design.md, D1-D21 plus orchestrator A1-A19).
-- The slot numbers, CR/SR/CFG field positions, the deny, TCM-hole and out-of-window byte addresses, and the modeled peripheral-window byte addresses below are therefore LOCAL to this bench (mirroring rtc_bfm_pkg.vhd and onewire_bfm_pkg.vhd), not shared MemoryMap.vhd constants.
-- DMA0 lives at 0x6800, and MemoryMap.vhd has no DMA slot constants until the generator knob is turned on (D20).
--
-- CHECKER INDEPENDENCE (the task's binding instruction, and the OW/RTC/NFC lesson): this package provides ONLY bus-level plumbing, register-map constants, config and CR packers, byte-and-word helpers, the bounded SR polls, and an INDEPENDENT CRC16-CDMA2000 reference (dma_crc_ref, built from the SAME LFSR math as work.CRC16 in SYSTEM0).
-- It NEVER reads a DUT internal.
-- The bench additionally wires the FOUR chained work.CRC16 COMPONENTS (bytes b0 through b3, seed 0xFFFF) in DMA_tb.vhd as the primary reference "model" (design doc D14, the task's binding instruction); dma_crc_ref here is a redundant, equally independent cross-check of that component chain.
--
-- The calling convention for the bounded polls copies rtc_bfm_pkg and onewire_bfm_pkg exactly: (signal clk, signal b, signal read_data, [args], done_ok : out boolean).
-- The caller turns done_ok into a scoreboard pass or fail (sb.check_true), so a poll that never satisfies its condition FAILS the run instead of hanging.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package dma_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc D5; base 0x6800) --------
    -- Slot n @ 0x6800 + 4n, decoded off MABPart(7:2).
    constant DMA_SLOT_CR   : natural := 0;
    constant DMA_SLOT_SR   : natural := 1;
    -- Per-channel blocks {SRC,DST,LEN,CFG} at a fixed stride of 4: CH0 = 2..5, CH1 = 6..9, CH2 = 10..13, CH3 = 14..17.
    constant DMA_SLOT_CRC  : natural := 18;   -- rw, reset 0xFFFF (D14)
    constant DMA_SLOT_DESC : natural := 19;   -- reserved, reads 0 (D5)

    -- Per-channel slot accessor (which: 0=SRC, 1=DST, 2=LEN, 3=CFG).
    function dma_ch_slot(ch : natural; which : natural) return natural;

    -- ---- DMA0CR bit positions (design doc D5, slot 0) ----------------------
    constant DMA_CR_DMAEN  : natural := 0;
    -- CHnGO    = bits 4:1  (CH0GO = bit 1),     self-clearing command, reads 0
    -- CHnABORT = bits 8:5  (CH0ABORT = bit 5),  self-clearing command, reads 0
    constant DMA_CR_GO0    : natural := 1;
    constant DMA_CR_ABORT0 : natural := 5;
    constant DMA_CR_DONEIE : natural := 12;
    constant DMA_CR_ERRIE  : natural := 13;

    -- ---- DMA0SR bit positions (design doc D5, slot 1) ----------------------
    constant DMA_SR_BUSY   : natural := 0;
    -- CHnDONE  = bits 4:1  (CH0DONE = bit 1),  W1C
    -- CHnERR   = bits 8:5  (CH0ERR  = bit 5),  W1C
    -- ACTIVECH = bits 11:9, read-only
    constant DMA_SR_DONE0  : natural := 1;
    constant DMA_SR_ERR0   : natural := 5;
    constant DMA_SR_ACTLO  : natural := 9;   -- ACTIVECH low bit

    -- ---- DMA0CnCFG bit fields (design doc D5) ------------------------------
    constant DMA_CFG_SINC  : natural := 0;
    constant DMA_CFG_DINC  : natural := 1;
    -- TRIG = bits 5:2
    constant DMA_CFG_PRIO  : natural := 6;
    constant DMA_CFG_CRCEN : natural := 7;

    -- TRIG source encodings (design doc D9/D10).
    constant DMA_TRIG_MEM  : std_logic_vector(3 downto 0) := "0000";  -- sw / mem-to-mem
    constant DMA_TRIG_UART : std_logic_vector(3 downto 0) := "0001";  -- UART0 RC
    constant DMA_TRIG_QSPI : std_logic_vector(3 downto 0) := "0010";  -- QSPI0 RXFULL
    constant DMA_TRIG_NFC  : std_logic_vector(3 downto 0) := "0011";  -- NFC0 payload-ready

    -- ---- modeled peripheral-window BYTE addresses (real map + A9) -----------
    -- These are the REAL peripheral register byte addresses that the DMA's paced SRC and hardcoded M_CLR target land on (UART0 at 0x4400, QSPI0 at 0x4C00, NFC0 at 0x6200: the wound A9 knob layout).
    -- The bench models each window at these exact addresses, and the DUT's per-TRIG hardcoded SR-clear target (D10: "WRITE QSPIxSR", "W1Cs NFCxSR bit 2") must agree.
    -- That agreement is a BENCH ASSUMPTION, recorded in the bench author's report: the M_CLR target derivation is a DUT detail the frozen doc leaves to the implementer.
    constant DMA_UART_RX_BYTE  : natural := 16#440C#;  -- UART0 RX  (slot 3, read-to-clear)
    constant DMA_QSPI_RX_BYTE  : natural := 16#4C10#;  -- QSPI0 RX  (slot 4, side-effect-free)
    constant DMA_QSPI_SR_BYTE  : natural := 16#4C14#;  -- QSPI0 SR  (slot 5, W1C bit 2)
    constant DMA_NFC_DATA_BYTE : natural := 16#621C#;  -- NFC0 DATA (slot 7, IDX auto-advance)
    constant DMA_NFC_SR_BYTE   : natural := 16#6204#;  -- NFC0 SR   (slot 1, W1C bit 2)

    -- ---- deny / hole / range BYTE addresses (design doc D12/D13/A5/A18) -----
    constant DMA_MUTEX_LO_BYTE : natural := 16#6000#;  -- mutex sub-slot window lo (deny read)
    constant DMA_MUTEX_HI_BYTE : natural := 16#60FF#;  -- mutex sub-slot window hi (deny read)
    constant DMA_ROUTER_CLAIM  : natural := 16#7800#;  -- irq_router CLAIM word (deny read, EXACT)
    constant DMA_TCM_LO_BYTE   : natural := 16#8000#;  -- TCM hole lo (reject at GO, A18)
    constant DMA_TCM_HI_BYTE   : natural := 16#BFFF#;  -- TCM hole hi
    constant DMA_OOW_BYTE      : natural := 16#20000#; -- out-of-window (>= 0x20000, reject at GO)

    -- Master-port word-address width (SH_AW, D19).
    constant DMA_AW : natural := 15;

    -- ---- modeled pacing-source data (shared by the model + the stim) --------
    -- Each source delivers a KNOWN, checkable byte or word stream so the destination buffer can be verified independently.
    -- UART and QSPI deliver seed+k on the k-th event (byte in the low lane, D10/A12), while NFC delivers base+i on the i-th payload read within a frame (auto-advancing IDX, D10/A10).
    constant DMA_UART_SEED : natural := 16#10#;   -- UART byte stream 0x10,0x11,...
    constant DMA_QSPI_SEED : natural := 16#A0#;   -- QSPI word stream 0xA0,0xA1,...
    constant DMA_NFC_BASE  : natural := 16#50#;   -- NFC payload word i = 0x50+i
    -- Modeled QSPI SR non-rxfull sticky bits (A11): the M_CLR W1C of bit 2 must clear ONLY bit 2 and leave these set.
    -- rxfull is bit 2 and is added when it is ready.
    constant DMA_QSPI_SR_OTHER : std_logic_vector(7 downto 0) := x"0B"; -- bits 0,1,3

    -- ---- packers -----------------------------------------------------------
    -- Full 32-bit DMA0CnCFG word (D5 field layout).
    function dma_mk_cfg(sinc, dinc : std_logic;
                        trig        : std_logic_vector(3 downto 0);
                        prio, crcen : std_logic) return std_logic_vector;

    -- Full 32-bit DMA0CR word.
    -- go_mask and abort_mask are 4-bit per-channel masks (bit c is channel c), and the launch and abort commands self-clear (D8/D15).
    function dma_mk_cr(dmaen        : std_logic;
                       go_mask      : std_logic_vector(3 downto 0);
                       abort_mask   : std_logic_vector(3 downto 0);
                       doneie, errie: std_logic) return std_logic_vector;

    -- Byte address to 15-bit master-port word address (D19: m_addr = byte(16:2)).
    function dma_word_addr(byte_addr : natural) return std_logic_vector;
    -- Byte address to RAM-model word index (natural).
    function dma_word_idx(byte_addr : natural) return natural;

    -- ---- INDEPENDENT CRC16-CDMA2000 reference (checker-independent) ---------
    -- Fold one 32-bit word into the accumulator, bytes b0 through b3 (little-endian, low byte first; design doc D14/A14).
    -- Identical LFSR math to work.CRC16 in SYSTEM0, via periph_tb_pkg.crc16_byte, and it NEVER reads the DUT.
    -- Seed the first call with 0xFFFF (D14).
    function dma_crc_word(word : std_logic_vector(31 downto 0);
                          acc  : std_logic_vector(15 downto 0))
        return std_logic_vector;

    -- ---- bounded SR polls (never hang; fail on guard) ----------------------
    -- Guard sizing: a few-word mem-to-mem copy completes in well under 100 clk, and a paced or multi-channel run in a few hundred.
    -- Each poll iteration is one bus_read (about 4 clk), so 8000 iterations is about 32000 clk: bounded, and well inside the tb watchdog.
    constant DMA_POLL_GUARD : natural := 8000;

    -- Poll DMA0SR.BUSY (bit 0) until it reads '0' (D8/D16).
    -- done_ok comes back false, and the poll never hangs, if BUSY has not cleared within the guard count.
    procedure dma_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Poll a single DMA0SR flag bit until it reads exp_val (SET or stays CLEAR).
    procedure dma_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean);

end package dma_bfm_pkg;


package body dma_bfm_pkg is

    -- Channel blocks start at slot 2 and repeat every 4 slots.
    function dma_ch_slot(ch : natural; which : natural) return natural is
    begin
        return 2 + 4*ch + which;
    end function;

    function dma_mk_cfg(sinc, dinc : std_logic;
                        trig        : std_logic_vector(3 downto 0);
                        prio, crcen : std_logic) return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(DMA_CFG_SINC)     := sinc;
        v(DMA_CFG_DINC)     := dinc;
        v(5 downto 2)       := trig;
        v(DMA_CFG_PRIO)     := prio;
        v(DMA_CFG_CRCEN)    := crcen;
        return v;
    end function;

    function dma_mk_cr(dmaen        : std_logic;
                       go_mask      : std_logic_vector(3 downto 0);
                       abort_mask   : std_logic_vector(3 downto 0);
                       doneie, errie: std_logic) return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(DMA_CR_DMAEN)   := dmaen;
        v(4 downto 1)     := go_mask;
        v(8 downto 5)     := abort_mask;
        v(DMA_CR_DONEIE)  := doneie;
        v(DMA_CR_ERRIE)   := errie;
        return v;
    end function;

    function dma_word_addr(byte_addr : natural) return std_logic_vector is
        variable w : unsigned(31 downto 0);
    begin
        w := to_unsigned(byte_addr, 32) srl 2;   -- drop the low 2 bits
        return std_logic_vector(w(DMA_AW-1 downto 0));
    end function;

    function dma_word_idx(byte_addr : natural) return natural is
    begin
        return byte_addr / 4;
    end function;

    function dma_crc_word(word : std_logic_vector(31 downto 0);
                          acc  : std_logic_vector(15 downto 0))
        return std_logic_vector is
        variable c : std_logic_vector(15 downto 0);
    begin
        -- Bytes b0 through b3, low byte first (D14/A14); crc16_byte is the exact work.CRC16 LFSR (poly 0xC857, MSB-first, no reflection, no final xor).
        c := crc16_byte(word(7  downto 0),  acc);
        c := crc16_byte(word(15 downto 8),  c);
        c := crc16_byte(word(23 downto 16), c);
        c := crc16_byte(word(31 downto 24), c);
        return c;
    end function;

    procedure dma_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        -- BUSY asserts on the SAME cycle as the GO write (D8: busy OR go_pending), so unlike OW there is no launch-latency blind window to guard against here and we poll straight for the clear.
        loop
            bus_read(clk, b, read_data, DMA_SLOT_SR, s);
            if to_X01(s(DMA_SR_BUSY)) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > DMA_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

    procedure dma_wait_flag(signal clk       : in    std_logic;
                            signal b         : inout periph_bus_t;
                            signal read_data : in    std_logic_vector(31 downto 0);
                            bit_idx          : in    natural;
                            exp_val          : in    std_logic;
                            done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        -- Re-read SR until the selected bit matches; a bit that is already correct exits on the first pass.
        loop
            bus_read(clk, b, read_data, DMA_SLOT_SR, s);
            if to_X01(s(bit_idx)) = exp_val then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > DMA_POLL_GUARD;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body dma_bfm_pkg;
