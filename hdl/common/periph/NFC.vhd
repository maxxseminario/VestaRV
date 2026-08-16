library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;

/* NFC: ISO/IEC 14443-3 Type A tag and card-emulation digital protocol engine, communications only (no energy harvesting on-die).
   Three clock domains: ClkMem (gated bus, register file), clk (free-running smclk, hosting the CDC synchronizers and the W1C retirement) and rf_clk (AFE carrier-derived, the whole protocol core).
   House style: registered read through a falling-edge EnMemPeriph pre-latch, W1C via a lane-0 write retired on EnMemPeriph='1', transaction-local config latching, and held-level CDC with no async FIFO.
   The analog front end is off-die: the rf_* ports plus field_detect and afe_en are the only link, and rf_txmod is OOK-gated so the AFE needs no separate TX window.
   Firmware arms the block with SYS_CLK_CR=0 (SMCLK on HFXT), the identity in NFCxUID/NFCxCFG, a payload streamed through NFCxIDX/NFCxDATA, then NFCxCR = NFCEN|LISTEN plus the IE bits; with AUTOREAD set, hardware answers a Type-2 READ with no firmware in the loop. */

entity NFC is
    port (
        clk          : in  std_logic;  -- smclk-domain free-running ref (CDC synchronizers)
        resetn       : in  std_logic;
        -- Vectors 94-97 straddle the router's U/X enable-word boundary: routing them needs HhENU bits 30/31 and HhENX bits 0/1.
        irq_field    : out std_logic;  -- RF field detected            (vector 94)
        irq_rxf      : out std_logic;  -- reader frame received        (vector 95)
        irq_txdone   : out std_logic;  -- tag response transmit done   (vector 96)
        irq_crcerr   : out std_logic;  -- RX CRC / parity error        (vector 97)
        ClkMem       : in  std_logic;
        EnMemPeriph  : in  std_logic;
        WEn          : in  std_logic_vector(3 downto 0);
        MABPart      : in  std_logic_vector(7 downto 2);
        wdata        : in  std_logic_vector(31 downto 0);
        rdata_out    : out std_logic_vector(31 downto 0);
        rf_clk       : in  std_logic;  -- AFE carrier-derived clock (fc = 13.56 MHz)
        field_detect : in  std_logic;  -- RF field present (asynchronous, synchronized inside)
        rf_rx        : in  std_logic;  -- demodulated RX envelope: '1'=field, '0'=pause
        rf_txmod     : out std_logic;  -- load-modulation drive: fc/16 subcarrier, OOK-gated
        rf_tx_en     : out std_logic;  -- TX active: frames the tag's load-mod response window
        afe_en       : out std_logic;  -- AFE demod-path enable (listen power gate)

        -- Event-fabric taps: toggles flipped at the fieldf/rxframef set sites (pre-IE) in the smclk domain; the fabric front-end does the smclk to mclk synchronization and edge detect.
        evt_field    : out std_logic;  -- toggles on field-detect rise
        evt_rxframe  : out std_logic   -- toggles on rx-frame arrival
    );
end NFC;

architecture behavioral of NFC is

    -- ---- register word-slot map ------------------------------------------
    constant SLOT_CR    : natural := 0;
    constant SLOT_SR    : natural := 1;
    constant SLOT_UID   : natural := 2;
    constant SLOT_CFG   : natural := 3;
    constant SLOT_TIM   : natural := 4;
    constant SLOT_RXST  : natural := 5;
    constant SLOT_IDX   : natural := 6;
    constant SLOT_DATA  : natural := 7;
    constant SLOT_TXCTL : natural := 8;
    constant SLOT_DBG   : natural := 9;

    /* ---- CRC_A per ISO/IEC 14443-3 (reflected 0x8408, init 0x6363) -------
       Bit-serial reflected LFSR, one data byte LSB-first at a time; this is NOT the house CRC16.
       Self-check vector: the CRC over {0x00,0x00} is 0x1EA0. */
    function crc_a_byte(crc_in : std_logic_vector(15 downto 0);
                        b      : std_logic_vector(7 downto 0)) return std_logic_vector is
        variable c : std_logic_vector(15 downto 0);
    begin
        c := crc_in;
        c(7 downto 0) := c(7 downto 0) xor b;
        for i in 0 to 7 loop
            if c(0) = '1' then c := ('0' & c(15 downto 1)) xor x"8408";
            else                c := ('0' & c(15 downto 1));
            end if;
        end loop;
        return c;
    end function;

    -- Odd parity bit: the 8 data bits plus parity carry an odd number of ones.
    function odd_parity(b : std_logic_vector(7 downto 0)) return std_logic is
    begin
        return not (b(7) xor b(6) xor b(5) xor b(4) xor
                    b(3) xor b(2) xor b(1) xor b(0));
    end function;

    -- ---- ISO tag FSM states ----------------------------------------------
    type iso_t is (POWER_OFF, ISO_IDLE, ISO_READY, ISO_ACTIVE, ISO_HALT);
    signal iso_state : iso_t;
    -- Protocol-core activity sub-FSM, in order: parse, byte-count, CRC-check, FDT, compose, TX.
    -- ACT_NBYTES and the phased ACT_COMPOSE keep the /9 byte divide and the tx_bits scatter plus CRC chain serial, one step per rf_clk; do not collapse either back into a single combinational cone.
    type act_t is (ACT_LISTEN, ACT_PARSE, ACT_NBYTES, ACT_CRC, ACT_DECIDE,
                   ACT_FDT, ACT_COMPOSE, ACT_TX, ACT_TXWAIT);
    signal act : act_t;

    -- ---- register storage (ClkMem domain) --------------------------------
    signal NFCxCR    : std_logic_vector(19 downto 0); -- reset AUTOREAD(12)=1
    signal NFCxUID   : std_logic_vector(31 downto 0);
    signal NFCxCFG   : std_logic_vector(23 downto 0); -- [15:0]ATQA [23:16]SAK
    signal NFCxTIM   : std_logic_vector(31 downto 0); -- [15:0]FDT [23:16]ETU [31:24]SUBCDIV
    signal NFCxIDX   : std_logic_vector(8 downto 0);  -- [5:0]IDX [6]AINC [8]SEL
    signal NFCxTXCTL : std_logic_vector(9 downto 0);  -- software-only, no hardware consumer

    -- Assembled status word (volatile, read through the pre-latch).
    signal NFCxSR    : std_logic_vector(11 downto 0);

    -- 64-byte indexed windows, one driver each: the payload TX window (firmware writes, hardware reads) and the RX frame buffer (hardware writes, firmware reads).
    type mem64_t is array (0 to 63) of std_logic_vector(7 downto 0);
    signal payload_mem : mem64_t;   -- driven ONLY by reg_write (ClkMem)
    signal rxbuf_mem   : mem64_t;   -- driven ONLY by the rf-domain FSM

    -- Pre-latch snapshots of the volatile registers: SR, RXST, DATA and DBG.
    signal NFCxSR_ltch : std_logic_vector(11 downto 0);
    signal rxst_ltch   : std_logic_vector(23 downto 0);
    signal data_ltch   : std_logic_vector(7 downto 0);
    signal dbg_ltch    : std_logic_vector(31 downto 0);

    -- ---- CR / IDX field taps (live, combinational) -----------------------
    signal nfcen, listen_bit, autoread_bit           : std_logic;
    signal fieldie, rxfie, txie, crcie               : std_logic;
    signal idx     : natural range 0 to 63;
    signal idx_ainc, idx_sel                         : std_logic;

    signal nfc_slot : natural range 0 to 63;

    -- ---- W1C clear pulses + HALTCLR toggle (ClkMem set, retired) ----------
    signal clr_fieldf, clr_rxframef, clr_txdonef     : std_logic;
    signal clr_crcerrf, clr_parerrf                  : std_logic;
    signal halt_req_tgl : std_logic;  -- toggle-CDC for the HALTCLR W-pulse (event)

    -- ---- clk (smclk) domain: CDC synchronizers + sticky W1C flags --------
    signal field_s1, field_s2, field_live, field_prev : std_logic;
    signal fieldf_flag, rxframef_flag, txdonef_flag    : std_logic;
    signal evt_field_tgl, evt_rxf_tgl                  : std_logic;  -- event-fabric toggles
    signal crcerrf_flag, parerrf_flag                  : std_logic;
    -- 2-FF synchronizers of the rf-domain held event levels, plus their edge detectors.
    signal rxframe_s1, rxframe_s2, rxframe_prev         : std_logic;
    signal txdone_s1, txdone_s2, txdone_prev            : std_logic;
    signal crcerr_s1, crcerr_s2, crcerr_prev            : std_logic;
    signal parerr_s1, parerr_s2, parerr_prev            : std_logic;
    -- 2-FF synchronizers of the rf-domain status levels for SR readback.
    signal busy_s1, busy_s2, halted_s1, halted_s2       : std_logic;
    signal state_s1, state_s2 : std_logic_vector(3 downto 0);

    -- ---- rf_clk domain: synchronized clk/config levels -------------------
    signal nfcen_r1, nfcen_r2, listen_r1, listen_r2     : std_logic;
    signal field_r1, field_r2                           : std_logic;
    signal halt_r1, halt_r2, halt_rprev, halt_pulse     : std_logic;

    -- ---- rf-domain held EVENT levels (rf FSM drives; clk edge-detects) ----
    -- Set at the event, cleared at the next rx_soc so each frame gives one edge.
    signal rf_rxframe_lvl, rf_txdone_lvl                : std_logic;
    signal rf_crcerr_lvl, rf_parerr_lvl                 : std_logic;
    -- rf-domain status levels (combinational, synchronized into clk for SR).
    signal rf_busy, rf_halted   : std_logic;
    signal rf_state             : std_logic_vector(3 downto 0);

    -- ---- rf-domain RX Miller decoder -------------------------------------
    signal rx_s1, rx_s2, rx_prev  : std_logic;
    signal rx_active, soc_period  : std_logic;
    signal etu_cnt      : std_logic_vector(15 downto 0);
    signal pause_seen, pause_second, prev_nopause : std_logic;
    signal since_pause  : std_logic_vector(16 downto 0);
    signal t_etu        : std_logic_vector(15 downto 0); -- latched ETU (RX copy)
    signal t_etu_half   : std_logic_vector(15 downto 0);
    signal t_eoc_thresh : std_logic_vector(16 downto 0); -- 1.5*ETU
    signal rx_raw       : std_logic_vector(255 downto 0); -- bits, LSB=index0=first-on-air
    signal rx_nbits     : natural range 0 to 256;
    signal rx_soc, rx_eoc : std_logic;      -- 1-rf_clk pulses
    signal last_rx_bit  : std_logic;        -- last decoded data bit (selects the FDT adjust)

    -- ---- rf-domain FSM config, latched per transaction -------------------
    signal t_uid  : std_logic_vector(31 downto 0);
    signal t_atqa : std_logic_vector(15 downto 0);
    signal t_sak  : std_logic_vector(7 downto 0);
    signal t_fdt  : std_logic_vector(15 downto 0);
    signal t_autoread : std_logic;
    signal fdt_cnt : std_logic_vector(16 downto 0);

    -- RX inspection exports (RXST, pre-latched into ClkMem) and the DBG counters.
    signal rx_cmd   : std_logic_vector(7 downto 0);
    signal rx_len   : std_logic_vector(7 downto 0);
    signal rx_crcok, rx_parok : std_logic;
    signal rx_frame_count, tx_frame_count : std_logic_vector(15 downto 0);

    -- Response composition scratch (driven by the FSM, consumed by the TX encoder).
    signal resp_bytes  : mem64_t;                 -- source bytes for the reply
    signal resp_len    : natural range 0 to 32;   -- number of source bytes
    signal resp_start  : natural range 0 to 32;   -- first byte to send (anticollision)
    signal resp_split  : std_logic;               -- first byte is a bit-split partial
    signal resp_splitb : natural range 0 to 7;    -- start bit within the split byte
    signal resp_appcrc : std_logic;               -- append CRC_A
    signal do_respond  : std_logic;               -- FDT/TX only when set
    signal next_state  : iso_t;                   -- iso_state to adopt after the reply
    signal crc_reg     : std_logic_vector(15 downto 0);
    signal crc_idx     : natural range 0 to 32;   -- byte index for the RX CRC pass
    signal rx_nbytes   : natural range 0 to 32;   -- assembled byte count (standard frame)
    signal is_short    : std_logic;               -- 7-bit short frame (REQA/WUPA)
    signal shortval    : std_logic_vector(6 downto 0);

    /* ---- serial /9 byte-count divide (ACT_NBYTES) ------------------------
       Repeated subtraction, one per rf_clk: a single-cycle rx_nbits/9 would infer a divider datapath.
       rx_nbits of at most 256 takes at most 28 cycles, and real frames of 2-7 bytes take 2-7. */
    signal div_rem : natural range 0 to 256;      -- running remainder
    signal div_q   : natural range 0 to 32;       -- accumulated quotient (byte count)

    /* ---- serial response composer (ACT_COMPOSE phases) -------------------
       One source byte per rf_clk: append its 9 framed bits (fewer on a split byte) at a running write pointer and fold it into the CRC LFSR.
       Keep it serial: an unrolled scatter plus a chained combinational CRC is a synthesis-heavy cone. */
    type cmp_t is (CMP_BYTES, CMP_CRCLO, CMP_CRCHI, CMP_FIN);
    signal cmp_ph  : cmp_t;
    signal cmp_k   : natural range 0 to 32;       -- source byte index being framed
    signal cmp_wr  : natural range 0 to 511;      -- running tx_bits write pointer
    signal crc_cmp : std_logic_vector(15 downto 0); -- compose-time CRC accumulator

    -- ---- rf-domain TX Manchester/subcarrier encoder ----------------------
    type txph_t is (TXP_IDLE, TXP_SOF, TXP_DATA, TXP_EOF, TXP_DONE);
    signal txph      : txph_t;
    signal tx_start, tx_active, tx_done : std_logic;
    signal tx_bits   : std_logic_vector(511 downto 0); -- raw framed bitstream (data+parity)
    signal tx_nbits  : natural range 0 to 512;
    signal tx_bidx   : natural range 0 to 511;   -- current bit index
    signal tx_half   : natural range 0 to 1;     -- half-bit within a symbol
    signal tx_tick   : std_logic_vector(15 downto 0); -- ticks within a half-bit
    signal t_subc    : std_logic_vector(7 downto 0);  -- latched SUBCDIV (TX copy)
    signal subc_cnt  : std_logic_vector(7 downto 0);
    signal subc_lvl  : std_logic;                -- current subcarrier toggle level
    signal tx_modnow : std_logic;                -- '1' means this half-bit is modulated

begin

    --------------------------- Signal Routing ------------------------------
    nfcen        <= NFCxCR(0);
    listen_bit   <= NFCxCR(1);
    fieldie      <= NFCxCR(8);
    rxfie        <= NFCxCR(9);
    txie         <= NFCxCR(10);
    crcie        <= NFCxCR(11);
    autoread_bit <= NFCxCR(12);

    idx      <= slv2uint(NFCxIDX(5 downto 0));
    idx_ainc <= NFCxIDX(6);
    idx_sel  <= NFCxIDX(8);

    -- SR assembly: every volatile and rf-status bit arrives pre-synchronized.
    NFCxSR(0)          <= busy_s2;
    NFCxSR(1)          <= fieldf_flag;
    NFCxSR(2)          <= rxframef_flag;
    NFCxSR(3)          <= txdonef_flag;
    NFCxSR(4)          <= crcerrf_flag;
    NFCxSR(5)          <= parerrf_flag;
    NFCxSR(6)          <= field_live;
    NFCxSR(7)          <= halted_s2;
    NFCxSR(11 downto 8) <= state_s2;

    -- rf-domain status levels (combinational, synchronized into clk for SR).
    rf_busy   <= '1' when (rx_active = '1' or tx_active = '1' or act /= ACT_LISTEN) else '0';
    rf_halted <= '1' when iso_state = ISO_HALT else '0';
    rf_state  <= x"0" when iso_state = POWER_OFF else
                 x"1" when iso_state = ISO_IDLE  else
                 x"2" when iso_state = ISO_READY else
                 x"3" when iso_state = ISO_ACTIVE else x"4";

    -- AFE demod enable: listen while armed (NFCEN and LISTEN), so afe_en is the listen power gate.
    afe_en <= nfcen and listen_bit;

    -- Event-fabric exports: the raw toggles, pre-IE by construction.
    evt_field   <= evt_field_tgl;
    evt_rxframe <= evt_rxf_tgl;

    -- Each irq_* is status AND enable, combinational and never latched.
    -- CRCERR folds the parity and CRC errors onto one line while the two flags stay separate.
    irq_field   <= fieldf_flag and fieldie;
    irq_rxf     <= rxframef_flag and rxfie;
    irq_txdone  <= txdonef_flag and txie;
    irq_crcerr  <= (crcerrf_flag or parerrf_flag) and crcie;

    ------------------------- End Signal Routing ----------------------------

    -- Registered-read pre-latch: capture the volatile snapshots inverted on falling_edge(EnMemPeriph); the read mux un-inverts them.
    reg_sync: process(EnMemPeriph, NFCxSR, rx_parok, rx_crcok, rx_len, rx_cmd,
                      idx_sel, idx, rxbuf_mem, payload_mem, tx_frame_count, rx_frame_count)
    begin
        if falling_edge(EnMemPeriph) then
            NFCxSR_ltch <= not NFCxSR;
            rxst_ltch   <= not ("000000" & rx_parok & rx_crcok & rx_len & rx_cmd);
            if idx_sel = '1' then data_ltch <= not rxbuf_mem(idx);
            else                  data_ltch <= not payload_mem(idx);
            end if;
            dbg_ltch <= not (tx_frame_count & rx_frame_count);
        end if;
    end process;

    ---------------------------- Memory Logic -------------------------------
    nfc_slot <= slv2uint(MABPart) when EnMemPeriph = '0' else 0;

    -- Register write: CR bit 2 (HALTCLR) is a self-clearing write pulse that reads back 0 and toggles halt_req_tgl into the rf domain, and the DATA slot auto-increments IDX on any access when IDXAINC=1.
    -- Payload-window writes commit here; RX-buffer writes are ignored because that buffer is hardware-owned.
    reg_write: process(resetn, ClkMem, EnMemPeriph)
    begin
        if resetn = '0' then
            NFCxCR    <= (12 => '1', others => '0'); -- AUTOREAD reset default
            NFCxUID   <= (others => '0');
            NFCxCFG   <= x"000044";                  -- ATQA=0x0044, SAK=0x00
            NFCxTIM   <= x"088004D4";                -- SUBCDIV=8, ETU=128, FDT=1236
            NFCxIDX   <= (others => '0');
            NFCxTXCTL <= (others => '0');
            halt_req_tgl <= '0';
            for i in 0 to 63 loop payload_mem(i) <= (others => '0'); end loop;
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case nfc_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            NFCxCR(1 downto 0) <= wdata(1 downto 0);
                            NFCxCR(3 downto 2) <= "00"; -- bit2 is self-clearing, bit3 is reserved
                            if wdata(2) = '1' then halt_req_tgl <= not halt_req_tgl; end if;
                        end if;
                        if WEn(1) = '0' then NFCxCR(13 downto 8)  <= wdata(13 downto 8);  end if;
                        if WEn(2) = '0' then NFCxCR(19 downto 16) <= wdata(19 downto 16); end if;
                    when SLOT_UID =>
                        if WEn(0) = '0' then NFCxUID(7 downto 0)   <= wdata(7 downto 0);   end if;
                        if WEn(1) = '0' then NFCxUID(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then NFCxUID(23 downto 16) <= wdata(23 downto 16); end if;
                        if WEn(3) = '0' then NFCxUID(31 downto 24) <= wdata(31 downto 24); end if;
                    when SLOT_CFG =>
                        if WEn(0) = '0' then NFCxCFG(7 downto 0)   <= wdata(7 downto 0);   end if;
                        if WEn(1) = '0' then NFCxCFG(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then NFCxCFG(23 downto 16) <= wdata(23 downto 16); end if;
                    when SLOT_TIM =>
                        if WEn(0) = '0' then NFCxTIM(7 downto 0)   <= wdata(7 downto 0);   end if;
                        if WEn(1) = '0' then NFCxTIM(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then NFCxTIM(23 downto 16) <= wdata(23 downto 16); end if;
                        if WEn(3) = '0' then NFCxTIM(31 downto 24) <= wdata(31 downto 24); end if;
                    when SLOT_IDX =>
                        if WEn(0) = '0' then NFCxIDX(7 downto 0) <= wdata(7 downto 0); end if;
                        if WEn(1) = '0' then NFCxIDX(8)          <= wdata(8);          end if;
                    when SLOT_DATA =>
                        if WEn(0) = '0' and idx_sel = '0' then
                            payload_mem(idx) <= wdata(7 downto 0);
                        end if;
                        if idx_ainc = '1' then
                            NFCxIDX(5 downto 0) <= uint2slv((idx + 1) mod 64, 6);
                        end if;
                    when SLOT_TXCTL =>
                        if WEn(0) = '0' then NFCxTXCTL(7 downto 0) <= wdata(7 downto 0); end if;
                        if WEn(1) = '0' then NFCxTXCTL(9 downto 8) <= wdata(9 downto 8); end if;
                    when SLOT_SR =>
                        if WEn(0) = '0' then -- W1C: writing a 1 clears, read-only bits are ignored
                            if wdata(1) = '1' then clr_fieldf   <= '1'; end if;
                            if wdata(2) = '1' then clr_rxframef <= '1'; end if;
                            if wdata(3) = '1' then clr_txdonef  <= '1'; end if;
                            if wdata(4) = '1' then clr_crcerrf  <= '1'; end if;
                            if wdata(5) = '1' then clr_parerrf  <= '1'; end if;
                        end if;
                    when others =>
                        null; -- RXST and DBG are read-only
                end case;
            end if;
        end if;

        -- Async clear-pulse retirement.
        if resetn = '0' or EnMemPeriph = '1' then
            clr_fieldf   <= '0';
            clr_rxframef <= '0';
            clr_txdonef  <= '0';
            clr_crcerrf  <= '0';
            clr_parerrf  <= '0';
        end if;
    end process;

    -- Synchronous register read: SR/RXST/DATA/DBG are un-inverted from the pre-latch, plain software registers read straight, reserved slots read 0.
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case nfc_slot is
                when SLOT_CR    => rdata_out <= (31 downto 20 => '0') & NFCxCR;
                when SLOT_SR    => rdata_out <= (31 downto 12 => '0') & (not NFCxSR_ltch);
                when SLOT_UID   => rdata_out <= NFCxUID;
                when SLOT_CFG   => rdata_out <= (31 downto 24 => '0') & NFCxCFG;
                when SLOT_TIM   => rdata_out <= NFCxTIM;
                when SLOT_RXST  => rdata_out <= (31 downto 24 => '0') & (not rxst_ltch);
                when SLOT_IDX   => rdata_out <= (31 downto 9 => '0') & NFCxIDX;
                when SLOT_DATA  => rdata_out <= (31 downto 8 => '0') & (not data_ltch);
                when SLOT_TXCTL => rdata_out <= (31 downto 10 => '0') & NFCxTXCTL;
                when SLOT_DBG   => rdata_out <= not dbg_ltch;
                when others     => rdata_out <= (others => '0');
            end case;
        end if;
    end process;

    /* -------- clk (smclk) domain synchronizers + W1C flags -----------------
       All CDC lives on the free-running smclk: ClkMem is gated and cannot host synchronizers.
       The rf-domain held event levels are 2-FF synchronized and rising-edge-detected to set the sticky W1C flags, and the rf side lowers each level at rx_soc so every frame gives a fresh edge; a metastable sample only delays a flag by one clk edge.
       The clr_* pulses retire the sticky flags asynchronously, so a clear dominates a coincident set. */
    bcdc: process(clk, resetn, clr_fieldf, clr_rxframef, clr_txdonef,
                  clr_crcerrf, clr_parerrf)
    begin
        if resetn = '0' then
            field_s1 <= '0'; field_s2 <= '0'; field_live <= '0'; field_prev <= '0';
            fieldf_flag <= '0'; rxframef_flag <= '0'; txdonef_flag <= '0';
            crcerrf_flag <= '0'; parerrf_flag <= '0';
            rxframe_s1 <= '0'; rxframe_s2 <= '0'; rxframe_prev <= '0';
            txdone_s1  <= '0'; txdone_s2  <= '0'; txdone_prev  <= '0';
            crcerr_s1  <= '0'; crcerr_s2  <= '0'; crcerr_prev  <= '0';
            parerr_s1  <= '0'; parerr_s2  <= '0'; parerr_prev  <= '0';
            busy_s1 <= '0'; busy_s2 <= '0'; halted_s1 <= '0'; halted_s2 <= '0';
            state_s1 <= (others => '0'); state_s2 <= (others => '0');
            evt_field_tgl <= '0'; evt_rxf_tgl <= '0';
        elsif rising_edge(clk) then
            -- field_detect double-flop into FIELD_LIVE, whose rising edge sets FIELDF.
            field_s1 <= field_detect;
            field_s2 <= field_s1;
            field_live <= field_s2;
            field_prev <= field_live;
            if field_live = '1' and field_prev = '0' then
                fieldf_flag   <= '1';
                evt_field_tgl <= not evt_field_tgl;   -- event-fabric toggle; the fabric does the smclk to mclk CDC
            end if;

            -- rf-domain event levels: 2-FF synchronize, then a rising edge sets the sticky flag.
            rxframe_s1 <= rf_rxframe_lvl; rxframe_s2 <= rxframe_s1; rxframe_prev <= rxframe_s2;
            if rxframe_s2 = '1' and rxframe_prev = '0' then
                rxframef_flag <= '1';
                evt_rxf_tgl   <= not evt_rxf_tgl;     -- event-fabric toggle
            end if;
            txdone_s1  <= rf_txdone_lvl;  txdone_s2  <= txdone_s1;  txdone_prev  <= txdone_s2;
            if txdone_s2  = '1' and txdone_prev  = '0' then txdonef_flag <= '1'; end if;
            crcerr_s1  <= rf_crcerr_lvl;  crcerr_s2  <= crcerr_s1;  crcerr_prev  <= crcerr_s2;
            if crcerr_s2  = '1' and crcerr_prev  = '0' then crcerrf_flag <= '1'; end if;
            parerr_s1  <= rf_parerr_lvl;  parerr_s2  <= parerr_s1;  parerr_prev  <= parerr_s2;
            if parerr_s2  = '1' and parerr_prev  = '0' then parerrf_flag <= '1'; end if;

            -- rf status levels double-flopped for SR readback (BUSY, HALTED, STATE).
            busy_s1 <= rf_busy; busy_s2 <= busy_s1;
            halted_s1 <= rf_halted; halted_s2 <= halted_s1;
            state_s1 <= rf_state; state_s2 <= state_s1;
        end if;

        -- W1C tail-clear (async, level-sensitive, and a clear dominates a coincident set).
        if resetn = '0' or clr_fieldf   = '1' then fieldf_flag   <= '0'; end if;
        if resetn = '0' or clr_rxframef = '1' then rxframef_flag <= '0'; end if;
        if resetn = '0' or clr_txdonef  = '1' then txdonef_flag  <= '0'; end if;
        if resetn = '0' or clr_crcerrf  = '1' then crcerrf_flag  <= '0'; end if;
        if resetn = '0' or clr_parerrf  = '1' then parerrf_flag  <= '0'; end if;
    end process;

    /* -------- CDC into rf_clk: config / field / HALTCLR synchronizers ------
       NFCEN, LISTEN and field are held levels on a 2-FF path into rf_clk; HALTCLR is an event, so it uses a toggle-CDC that survives regardless of the ClkMem pulse width.
       UID, ATQA, SAK and TIM are quasi-static and latched transaction-locally in the rf FSM and RX decoder, so those multi-bit words get no synchronizer. */
    rfsync: process(rf_clk, resetn)
    begin
        if resetn = '0' then
            nfcen_r1 <= '0'; nfcen_r2 <= '0';
            listen_r1 <= '0'; listen_r2 <= '0';
            field_r1 <= '0'; field_r2 <= '0';
            halt_r1 <= '0'; halt_r2 <= '0'; halt_rprev <= '0';
        elsif rising_edge(rf_clk) then
            nfcen_r1  <= nfcen;       nfcen_r2  <= nfcen_r1;
            listen_r1 <= listen_bit;  listen_r2 <= listen_r1;
            field_r1  <= field_live;  field_r2  <= field_r1;
            halt_r1   <= halt_req_tgl; halt_r2  <= halt_r1; halt_rprev <= halt_r2;
        end if;
    end process;
    halt_pulse <= halt_r2 xor halt_rprev; -- 1-rf_clk pulse on a HALTCLR request

    /* -------- RX: modified-Miller decoder + bit assembler ------------------
       rf_rx is the raw pause envelope ('0' = pause), 2-FF synchronized and classified once per bit period on a free-running ETU grid started at the first pause (SOC, which emits no data bit): a pause in the second half is a 1, a pause in the first half or none at all is a 0.
       A single no-pause period is deferred one period and flushed as a 0 only if a pause-bearing period follows; two consecutive no-pause periods are the EOC, flushing the deferred 0 as the last bit.
       Bits land LSB-first in rx_raw, all timing is register-programmed (t_etu latched at SOC), and field loss quiesces the decoder. */
    rx_decode: process(rf_clk, resetn, nfcen_r2)
        variable nb    : natural range 0 to 256;
        variable pedge : boolean;
        variable etu16 : std_logic_vector(15 downto 0);
        variable half  : std_logic_vector(15 downto 0);
    begin
        if resetn = '0' or nfcen_r2 = '0' then
            rx_s1 <= '1'; rx_s2 <= '1'; rx_prev <= '1';
            rx_active <= '0'; soc_period <= '0'; prev_nopause <= '0';
            etu_cnt <= (others => '0'); pause_seen <= '0'; pause_second <= '0';
            since_pause <= (others => '0'); rx_nbits <= 0;
            rx_soc <= '0'; rx_eoc <= '0'; last_rx_bit <= '0';
            t_etu <= x"0080"; t_etu_half <= x"0040"; t_eoc_thresh <= '0' & x"0140";
        elsif rising_edge(rf_clk) then
            rx_soc <= '0';
            rx_eoc <= '0';
            rx_s1  <= rf_rx;  rx_s2 <= rx_s1;  rx_prev <= rx_s2;

            if field_r2 = '0' then
                rx_active <= '0'; soc_period <= '0'; prev_nopause <= '0';
                etu_cnt <= (others => '0'); pause_seen <= '0'; pause_second <= '0';
                since_pause <= (others => '0');
            else
                pedge := (rx_prev = '1' and rx_s2 = '0'); -- pause falling edge

                if rx_active = '0' then
                    if pedge then          -- the first pause out of idle is the SOC
                        etu16 := x"00" & NFCxTIM(23 downto 16);
                        half  := "000000000" & NFCxTIM(23 downto 17);
                        rx_active <= '1'; soc_period <= '1'; rx_soc <= '1';
                        -- Seed etu_cnt=4 so the bit-period boundary lands in the inter-symbol dead zone with balanced margin for first-half and second-half pauses.
                        -- Do not seed 0: the pause edge is seen about 2 rf_clk late, which would put the boundary on every first-half pause and misclassify its position.
                        etu_cnt <= conv_std_logic_vector(4, 16); rx_nbits <= 0;
                        pause_seen <= '0'; pause_second <= '0'; prev_nopause <= '0';
                        since_pause <= (others => '0');
                        t_etu <= etu16; t_etu_half <= half;
                        t_eoc_thresh <= ('0' & etu16) + ('0' & etu16) + ('0' & half);
                    end if;
                else
                    -- Pause tracking within the current bit period.
                    if pedge then
                        pause_seen <= '1';
                        if etu_cnt >= t_etu_half then pause_second <= '1';
                        else                          pause_second <= '0'; end if;
                        since_pause <= (others => '0');
                    else
                        since_pause <= since_pause + 1;
                    end if;

                    -- Bit-period boundary: classify the period and emit any resulting bits.
                    if etu_cnt = t_etu - 1 then
                        etu_cnt <= (others => '0');
                        nb := rx_nbits;
                        if soc_period = '1' then
                            soc_period <= '0'; prev_nopause <= '0';
                        elsif pause_seen = '1' then
                            if prev_nopause = '1' and nb < 256 then
                                rx_raw(nb) <= '0'; last_rx_bit <= '0'; nb := nb + 1;
                            end if;
                            if nb < 256 then
                                rx_raw(nb) <= pause_second; last_rx_bit <= pause_second;
                                nb := nb + 1;
                            end if;
                            prev_nopause <= '0';
                        else
                            if prev_nopause = '1' then   -- two no-pause periods in a row close the frame
                                if nb < 256 then
                                    rx_raw(nb) <= '0'; last_rx_bit <= '0'; nb := nb + 1;
                                end if;
                                rx_eoc <= '1'; rx_active <= '0'; prev_nopause <= '0';
                            else
                                prev_nopause <= '1';
                            end if;
                        end if;
                        rx_nbits <= nb;
                        pause_seen <= '0'; pause_second <= '0';
                    else
                        etu_cnt <= etu_cnt + 1;
                    end if;

                    -- Safety-net EOC (grid-drift guard; the boundary rule normally fires first).
                    if since_pause >= t_eoc_thresh then
                        rx_eoc <= '1'; rx_active <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    /* -------- TX: Manchester-on-subcarrier encoder -------------------------
       tx_bits is the raw framed bitstream (data plus inserted parity and CRC, LSB-first) composed by the FSM; this encoder is a plain Manchester serializer that brackets it with SOF (sequence D) and EOF (sequence F), with rf_tx_en high across both.
       Each symbol is 2 half-bits of t_etu_half rf_clk ticks: a 1 is modulated then unmodulated, a 0 is unmodulated then modulated, EOF is unmodulated in both halves.
       A modulated half runs the fc/16 subcarrier as a divide-by-2*SUBCDIV toggle of rf_clk, an unmodulated half holds rf_txmod steady, and all timing is register-programmed. */
    tx_encode: process(rf_clk, resetn, nfcen_r2)
    begin
        if resetn = '0' or nfcen_r2 = '0' then
            txph <= TXP_IDLE; tx_active <= '0'; tx_done <= '0';
            tx_bidx <= 0; tx_half <= 0; tx_tick <= (others => '0');
            subc_cnt <= (others => '0'); subc_lvl <= '0'; t_subc <= x"08";
        elsif rising_edge(rf_clk) then
            tx_done <= '0';
            case txph is
                -- IDLE: wait for the FSM's tx_start pulse, then latch the TX timing config.
                when TXP_IDLE =>
                    tx_active <= '0';
                    if tx_start = '1' then
                        t_subc   <= NFCxTIM(31 downto 24);
                        tx_bidx  <= 0; tx_half <= 0; tx_tick <= (others => '0');
                        subc_cnt <= (others => '0'); subc_lvl <= '0';
                        tx_active <= '1'; txph <= TXP_SOF;
                    end if;
                -- The three transmitting phases share one half-bit timer and one subcarrier divider.
                when TXP_SOF | TXP_DATA | TXP_EOF =>
                    -- Subcarrier divide-by-2*SUBCDIV toggle.
                    if subc_cnt = t_subc - 1 then
                        subc_cnt <= (others => '0'); subc_lvl <= not subc_lvl;
                    else
                        subc_cnt <= subc_cnt + 1;
                    end if;
                    -- Half-bit timer: at its terminal count advance the half, then the symbol.
                    if tx_tick = t_etu_half - 1 then
                        tx_tick  <= (others => '0');
                        subc_cnt <= (others => '0'); subc_lvl <= '0'; -- start each half on a clean phase
                        if tx_half = 0 then
                            tx_half <= 1;
                        else
                            tx_half <= 0;
                            case txph is
                                when TXP_SOF =>
                                    if tx_nbits = 0 then txph <= TXP_EOF;
                                    else tx_bidx <= 0; txph <= TXP_DATA; end if;
                                when TXP_DATA =>
                                    if tx_bidx = tx_nbits - 1 then txph <= TXP_EOF;
                                    else tx_bidx <= tx_bidx + 1; end if;
                                when others => -- TXP_EOF
                                    txph <= TXP_DONE;
                            end case;
                        end if;
                    else
                        tx_tick <= tx_tick + 1;
                    end if;
                -- DONE: one-cycle tx_done pulse back to the FSM, then park in idle.
                when TXP_DONE =>
                    tx_active <= '0'; tx_done <= '1'; txph <= TXP_IDLE;
            end case;
        end if;
    end process;

    -- Per-half-bit "modulate?" gate (combinational) and the subcarrier OOK output.
    tx_modnow <= '1' when ((txph = TXP_SOF  and tx_half = 0) or
                           (txph = TXP_DATA and tx_half = 0 and tx_bits(tx_bidx) = '1') or
                           (txph = TXP_DATA and tx_half = 1 and tx_bits(tx_bidx) = '0'))
                      else '0';
    rf_txmod <= subc_lvl when tx_modnow = '1' else '0';
    rf_tx_en <= '1' when (txph = TXP_SOF or txph = TXP_DATA or txph = TXP_EOF) else '0';

    /* -------- ISO 14443-3 Type A tag state machine -------------------------
       rf_clk domain, config latched transaction-locally at rx_soc; on rx_eoc the frame is de-framed into bytes plus per-byte odd parity (a short frame is 7 bits with no parity), CRC-checked, decided on, delayed by FDT, composed and transmitted.
       ACT_DECIDE answers REQA/WUPA with ATQA, anticollision CL1 with bit-oriented NVB, SELECT with SAK, READ from the payload window, and HLTA by going silent.
       The rf event levels are held from their event until the next rx_soc, so the clk-domain synchronizers edge-detect exactly one set per frame. */
    bfsm: process(rf_clk, resetn, nfcen_r2)
        variable pk       : std_logic;
        variable bytev    : std_logic_vector(7 downto 0);
        variable nbytes_v : natural range 0 to 32;
        variable respond_v : std_logic;
        variable nstate_v : iso_t;
        variable nvb      : std_logic_vector(7 downto 0);
        variable bytecnt, bitcnt, nvbits, blk, off : natural;
        variable matchv   : std_logic;
        variable bccv     : std_logic_vector(7 downto 0);
        variable uidbcc   : std_logic_vector(39 downto 0);
        variable local    : natural range 0 to 8;   -- split-byte bit position (compose)
        variable srcb     : std_logic_vector(7 downto 0); -- source byte being framed
    begin
        if resetn = '0' or nfcen_r2 = '0' then
            iso_state <= POWER_OFF; act <= ACT_LISTEN;
            rf_rxframe_lvl <= '0'; rf_txdone_lvl <= '0';
            rf_crcerr_lvl <= '0'; rf_parerr_lvl <= '0';
            tx_start <= '0'; do_respond <= '0'; next_state <= POWER_OFF;
            resp_len <= 0; resp_start <= 0; resp_split <= '0'; resp_splitb <= 0;
            resp_appcrc <= '0'; tx_nbits <= 0;
            rx_cmd <= (others => '0'); rx_len <= (others => '0'); rx_nbytes <= 0;
            rx_crcok <= '0'; rx_parok <= '0'; is_short <= '0'; shortval <= (others => '0');
            crc_reg <= (others => '0'); crc_idx <= 0; fdt_cnt <= (others => '0');
            div_rem <= 0; div_q <= 0;
            cmp_ph <= CMP_BYTES; cmp_k <= 0; cmp_wr <= 0; crc_cmp <= (others => '0');
            t_uid <= (others => '0'); t_atqa <= x"0044"; t_sak <= x"00";
            t_fdt <= x"04D4"; t_autoread <= '1';
            rx_frame_count <= (others => '0'); tx_frame_count <= (others => '0');
            for i in 0 to 63 loop
                rxbuf_mem(i) <= (others => '0'); resp_bytes(i) <= (others => '0');
            end loop;
        elsif rising_edge(rf_clk) then
            tx_start <= '0'; -- 1-cycle launch pulse default

            -- Transaction-local config latch and per-frame event-level clear.
            if rx_soc = '1' then
                rf_rxframe_lvl <= '0'; rf_txdone_lvl <= '0';
                rf_crcerr_lvl <= '0'; rf_parerr_lvl <= '0';
                t_uid  <= NFCxUID;
                t_atqa <= NFCxCFG(15 downto 0);
                t_sak  <= NFCxCFG(23 downto 16);
                t_fdt  <= NFCxTIM(15 downto 0);
                t_autoread <= autoread_bit;
            end if;

            if field_r2 = '0' then
                iso_state <= POWER_OFF; act <= ACT_LISTEN;   -- field loss returns the tag to IDLE
            else
                if iso_state = POWER_OFF then iso_state <= ISO_IDLE; end if;
                if halt_pulse = '1' and iso_state = ISO_HALT then
                    iso_state <= ISO_IDLE;                   -- HALTCLR W-pulse
                end if;

                case act is
                    -- LISTEN: idle until the decoder closes a reader frame.
                    when ACT_LISTEN =>
                        if rx_eoc = '1' then act <= ACT_PARSE; end if;

                    -- PARSE: split short frames from standard frames and count the frame in.
                    when ACT_PARSE =>
                        rf_rxframe_lvl <= '1';               -- reader frame landed
                        rx_frame_count <= rx_frame_count + 1;
                        if rx_nbits <= 8 then                -- 7-bit short frame
                            is_short <= '1'; shortval <= rx_raw(6 downto 0);
                            rx_cmd <= '0' & rx_raw(6 downto 0);
                            rx_len <= x"00"; rx_nbytes <= 0;
                            rx_parok <= '1'; rx_crcok <= '0';
                            act <= ACT_DECIDE;
                        else                                 -- standard/anticollision frame
                            -- Launch the serial byte-count divide; the byte de-frame and parity check run once the quotient lands.
                            div_rem <= rx_nbits; div_q <= 0;
                            act <= ACT_NBYTES;
                        end if;

                    when ACT_NBYTES =>
                        -- One subtraction per rf_clk: once div_rem drops below 9 the quotient div_q is floor(rx_nbits/9), the whole-byte count.
                        -- Then de-frame the bytes with constant rx_raw bit-picks, not a crossbar, and check their parity.
                        if div_rem >= 9 then
                            div_rem <= div_rem - 9; div_q <= div_q + 1;
                        else
                            nbytes_v := div_q;
                            pk := '1';
                            for k in 0 to 8 loop
                                if k < nbytes_v then
                                    for j in 0 to 7 loop bytev(j) := rx_raw(k*9 + j); end loop;
                                    rxbuf_mem(k) <= bytev;
                                    if odd_parity(bytev) /= rx_raw(k*9 + 8) then pk := '0'; end if;
                                end if;
                            end loop;
                            is_short <= '0';
                            rx_nbytes <= nbytes_v;
                            rx_len <= uint2slv(nbytes_v, 8);
                            rx_cmd <= rx_raw(7 downto 0);
                            rx_parok <= pk;
                            if pk = '0' then rf_parerr_lvl <= '1'; end if;
                            if nbytes_v >= 2 then
                                crc_reg <= x"6363"; crc_idx <= 0; act <= ACT_CRC;
                            else
                                rx_crcok <= '0'; act <= ACT_DECIDE;
                            end if;
                        end if;

                    -- CRC: one frame byte per rf_clk through the LFSR, then check the trailing pair.
                    when ACT_CRC =>
                        if crc_idx >= rx_nbytes - 2 then     -- LFSR done: compare the residue
                            if crc_reg(7 downto 0) = rxbuf_mem(rx_nbytes - 2) and
                               crc_reg(15 downto 8) = rxbuf_mem(rx_nbytes - 1) then
                                rx_crcok <= '1';
                            else
                                rx_crcok <= '0';
                            end if;
                            act <= ACT_DECIDE;
                        else
                            crc_reg <= crc_a_byte(crc_reg, rxbuf_mem(crc_idx));
                            crc_idx <= crc_idx + 1;
                        end if;

                    -- DECIDE: run the ISO tag state machine and stage the reply, if any.
                    when ACT_DECIDE =>
                        respond_v := '0';
                        nstate_v  := iso_state;
                        resp_split <= '0'; resp_start <= 0; resp_appcrc <= '0';
                        resp_splitb <= 0;
                        bccv := t_uid(7 downto 0) xor t_uid(15 downto 8) xor
                                t_uid(23 downto 16) xor t_uid(31 downto 24);

                        if is_short = '1' then
                            if shortval = "0100110" then          -- REQA 0x26
                                if iso_state = ISO_IDLE or iso_state = ISO_READY then
                                    resp_bytes(0) <= t_atqa(7 downto 0);
                                    resp_bytes(1) <= t_atqa(15 downto 8);
                                    resp_len <= 2; nstate_v := ISO_READY;
                                    if listen_r2 = '1' then respond_v := '1'; end if;
                                end if;
                            elsif shortval = "1010010" then        -- WUPA 0x52
                                if iso_state = ISO_IDLE or iso_state = ISO_READY or
                                   iso_state = ISO_HALT then
                                    resp_bytes(0) <= t_atqa(7 downto 0);
                                    resp_bytes(1) <= t_atqa(15 downto 8);
                                    resp_len <= 2; nstate_v := ISO_READY;
                                    if listen_r2 = '1' then respond_v := '1'; end if;
                                end if;
                            end if;
                        elsif rx_parok = '1' then
                            if iso_state = ISO_READY and rx_cmd = x"93" then
                                nvb := rxbuf_mem(1);
                                if nvb = x"70" then               -- SELECT CL1
                                    if rx_crcok = '0' then rf_crcerr_lvl <= '1'; end if;
                                    matchv := '1';
                                    if rxbuf_mem(2) /= t_uid(7 downto 0)   then matchv := '0'; end if;
                                    if rxbuf_mem(3) /= t_uid(15 downto 8)  then matchv := '0'; end if;
                                    if rxbuf_mem(4) /= t_uid(23 downto 16) then matchv := '0'; end if;
                                    if rxbuf_mem(5) /= t_uid(31 downto 24) then matchv := '0'; end if;
                                    if rxbuf_mem(6) /= bccv then matchv := '0'; end if;
                                    if matchv = '1' and rx_crcok = '1' then
                                        resp_bytes(0) <= t_sak; resp_len <= 1;
                                        resp_appcrc <= '1'; nstate_v := ISO_ACTIVE;
                                        if listen_r2 = '1' then respond_v := '1'; end if;
                                    end if;
                                else                              -- ANTICOLLISION CL1
                                    bytecnt := slv2uint(nvb(7 downto 4));
                                    bitcnt  := slv2uint(nvb(3 downto 0));
                                    if bytecnt >= 2 then nvbits := (bytecnt - 2) * 8 + bitcnt;
                                    else nvbits := 0; end if;
                                    if nvbits > 32 then nvbits := 32; end if;
                                    uidbcc := bccv & t_uid;       -- on-air order, LSB-first
                                    -- Compare the reader's partial UID bit-for-bit straight from the raw Miller stream, not from the reassembled bytes: a bit-split anticollision frame omits parity on the split byte, which byte reassembly would drop.
                                    -- Reader UID bit m sits at 18 (SEL and NVB, 9 bits each) + (m/8)*9 + (m mod 8), a formula that also lands the split byte's parity-less leading bits.
                                    matchv := '1';
                                    for i in 0 to 31 loop
                                        if i < nvbits then
                                            if rx_raw(18 + (i / 8) * 9 + (i mod 8)) /= uidbcc(i) then
                                                matchv := '0';
                                            end if;
                                        end if;
                                    end loop;
                                    if matchv = '1' then          -- resume UID at the split
                                        resp_bytes(0) <= t_uid(7 downto 0);
                                        resp_bytes(1) <= t_uid(15 downto 8);
                                        resp_bytes(2) <= t_uid(23 downto 16);
                                        resp_bytes(3) <= t_uid(31 downto 24);
                                        resp_bytes(4) <= bccv;
                                        resp_len <= 5; resp_appcrc <= '0';
                                        resp_start <= nvbits / 8;
                                        if (nvbits mod 8) /= 0 then
                                            resp_split <= '1'; resp_splitb <= nvbits mod 8;
                                        end if;
                                        nstate_v := ISO_READY;
                                        if listen_r2 = '1' then respond_v := '1'; end if;
                                    end if;                       -- a mismatch stays silent
                                end if;
                            elsif iso_state = ISO_ACTIVE and rx_cmd = x"30" then  -- READ
                                if rx_crcok = '0' then rf_crcerr_lvl <= '1'; end if;
                                if rx_crcok = '1' and t_autoread = '1' then
                                    blk := slv2uint(rxbuf_mem(1)); off := (blk * 4) mod 64;
                                    for i in 0 to 15 loop
                                        resp_bytes(i) <= payload_mem((off + i) mod 64);
                                    end loop;
                                    resp_len <= 16; resp_appcrc <= '1'; nstate_v := ISO_ACTIVE;
                                    if listen_r2 = '1' then respond_v := '1'; end if;
                                end if;                           -- AUTOREAD=0 leaves the answer to firmware
                            elsif iso_state = ISO_ACTIVE and rx_cmd = x"50" then  -- HLTA
                                if rx_crcok = '0' then rf_crcerr_lvl <= '1'; end if;
                                if rx_crcok = '1' and rxbuf_mem(1) = x"00" then
                                    nstate_v := ISO_HALT;         -- go silent and enter HALT
                                end if;
                            end if;
                        end if;

                        do_respond <= respond_v;
                        next_state <= nstate_v;
                        if respond_v = '1' then
                            if last_rx_bit = '1' then
                                fdt_cnt <= ('0' & t_fdt) + ('0' & t_etu_half);
                            else
                                fdt_cnt <= '0' & t_fdt;
                            end if;
                            act <= ACT_FDT;
                        else
                            iso_state <= nstate_v; act <= ACT_LISTEN;
                        end if;

                    -- FDT: count out the Frame-Delay-Time before the reply may start.
                    when ACT_FDT =>
                        if fdt_cnt = conv_std_logic_vector(0, 17) then
                            -- FDT elapsed: launch the composer, which hands over to ACT_TX at CMP_FIN.
                            -- The reply therefore lands FDT plus the compose latency (at most about 19 rf_clk ticks) after the reader's EOF, so program FDT short by that much if a reader demands the exact ISO grid.
                            cmp_k  <= resp_start;      -- skip bytes already sent (split)
                            cmp_wr <= 0;               -- tx_bits write pointer
                            crc_cmp <= x"6363";        -- CRC_A init
                            cmp_ph <= CMP_BYTES;
                            act <= ACT_COMPOSE;
                        else
                            fdt_cnt <= fdt_cnt - 1;
                        end if;

                    when ACT_COMPOSE =>
                        -- Frame composer: one source byte per rf_clk appended at the running cmp_wr pointer and folded into the CRC LFSR crc_cmp.
                        -- Bit layout is 8 data bits LSB-first plus parity per byte, the split byte omitting parity, then the CRC_A low and high bytes each with parity when resp_appcrc=1.
                        srcb := resp_bytes(cmp_k);
                        case cmp_ph is
                            when CMP_BYTES =>
                                if cmp_k < resp_len then
                                    if cmp_k = resp_start and resp_split = '1' then
                                        -- Split byte: bits resp_splitb through 7, with NO parity.
                                        local := 0;
                                        for j in 0 to 7 loop
                                            if j >= resp_splitb then
                                                tx_bits(cmp_wr + local) <= srcb(j);
                                                local := local + 1;
                                            end if;
                                        end loop;
                                        cmp_wr <= cmp_wr + local;
                                    else
                                        for j in 0 to 7 loop
                                            tx_bits(cmp_wr + j) <= srcb(j);
                                        end loop;
                                        tx_bits(cmp_wr + 8) <= odd_parity(srcb);
                                        cmp_wr <= cmp_wr + 9;
                                    end if;
                                    if resp_appcrc = '1' then
                                        crc_cmp <= crc_a_byte(crc_cmp, srcb);
                                    end if;
                                    cmp_k <= cmp_k + 1;
                                else
                                    if resp_appcrc = '1' then cmp_ph <= CMP_CRCLO;
                                    else                      cmp_ph <= CMP_FIN; end if;
                                end if;
                            when CMP_CRCLO =>              -- CRC_A low byte, LSB-first
                                for j in 0 to 7 loop
                                    tx_bits(cmp_wr + j) <= crc_cmp(j);
                                end loop;
                                tx_bits(cmp_wr + 8) <= odd_parity(crc_cmp(7 downto 0));
                                cmp_wr <= cmp_wr + 9; cmp_ph <= CMP_CRCHI;
                            when CMP_CRCHI =>             -- CRC_A high byte
                                for j in 0 to 7 loop
                                    tx_bits(cmp_wr + j) <= crc_cmp(8 + j);
                                end loop;
                                tx_bits(cmp_wr + 8) <= odd_parity(crc_cmp(15 downto 8));
                                cmp_wr <= cmp_wr + 9; cmp_ph <= CMP_FIN;
                            -- Frame complete: publish the bit count and hand the frame to the encoder.
                            when CMP_FIN =>
                                tx_nbits <= cmp_wr; act <= ACT_TX;
                        end case;

                    -- TX: one-cycle launch pulse into the Manchester encoder.
                    when ACT_TX =>
                        tx_start <= '1'; act <= ACT_TXWAIT;

                    -- TXWAIT: on the encoder's done, flag TXDONE, count the frame, adopt the pending ISO state.
                    when ACT_TXWAIT =>
                        if tx_done = '1' then
                            rf_txdone_lvl <= '1';
                            tx_frame_count <= tx_frame_count + 1;
                            iso_state <= next_state;
                            act <= ACT_LISTEN;
                        end if;
                end case;
            end if;
        end if;
    end process;

end behavioral;
