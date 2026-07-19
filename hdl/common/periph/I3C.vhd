library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;

-- I3C: MIPI I3C Basic controller peripheral (digital-peripherals program).
-- STAGE 1 (MVP): SDR private read/write + legacy-I2C, per the FROZEN design
-- ~/vesta_docs/digperiphs/i3c_design.md (decisions Dn, rulings R1-R3). The
-- entity is FROZEN (R3) -- a bench (tb/I3C_tb.vhd) is compiled against it.
-- Blocks implemented: B1 register file (this file's reg_write/reg_read),
-- B2 baud gen, B3 bit engine + B4 framer FSM (one process), B7 async bus
-- sensor, B8 combinational pad-drive mux. Stage-2 (DAA) / stage-3 (IBI) fields
-- and slots (5-8) decode + read 0 (D23 inert). House style (registered read,
-- two-chained-ClkGate divider, W1C clear-pulse retirement, transaction-local
-- latching at launch) mirrors QSPI.vhd; T-bit anti-clone rules per D24-D27.

entity I3C is
    port (
        clk         : in  std_logic;   -- smclk-domain serial core clock
        resetn      : in  std_logic;
        irq_tc      : out std_logic;
        irq_rxf     : out std_logic;
        irq_txe     : out std_logic;
        irq_nack    : out std_logic;
        irq_eod     : out std_logic;
        irq_arb     : out std_logic;
        irq_daa     : out std_logic;   -- stage 2 (source stays 0 in MVP)
        irq_ibi     : out std_logic;   -- stage 3 (source stays 0 in MVP)
        ClkMem      : in  std_logic;
        EnMemPeriph : in  std_logic;
        WEn         : in  std_logic_vector(3 downto 0);
        MABPart     : in  std_logic_vector(7 downto 2);
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);
        SDA_IN      : in  std_logic;
        SDA_OUT     : out std_logic;
        SDA_DIR     : out std_logic;
        SCL_IN      : in  std_logic;
        SCL_OUT     : out std_logic;
        SCL_DIR     : out std_logic
    );
end I3C;

architecture behavioral of I3C is

    -- ---- register word-slot map (frozen, design doc S3) ------------------
    constant SLOT_CR      : natural := 0;
    constant SLOT_CMD     : natural := 1;
    constant SLOT_TX      : natural := 2;
    constant SLOT_RX      : natural := 3;
    constant SLOT_SR      : natural := 4;
    constant SLOT_DAT     : natural := 5;  -- stage 2, inert read-0 in MVP
    constant SLOT_DATPID  : natural := 6;  -- stage 2, inert read-0 in MVP
    constant SLOT_DATINFO : natural := 7;  -- stage 2, inert read-0 in MVP
    constant SLOT_IBI     : natural := 8;  -- stage 3, inert read-0 in MVP

    -- Framer / bit-engine phases (B3+B4). Each "bit" phase runs a 4-sub-state
    -- SCL cycle (BIT_SETUP sub0 -> SCL_RISE sub1 -> SAMPLE sub2 -> SCL_FALL
    -- sub3), never folding drive+sample onto one edge (QSPI timing lesson, D1).
    type ph_t is (P_IDLE, P_START, P_SR, P_ADDR, P_ACK, P_WLOAD, P_WDATA,
                  P_WT, P_RDATA, P_RT, P_RWAIT, P_STOP, P_DONE,
                  -- stage-2 CCC / DAA sub-sequencer (B5), entered from P_ACK
                  -- when the latched CMD has CCC/DAARUN/DASA. B2/B3/B8 untouched
                  -- (D23 bolt-on) -- these drive the SAME bit engine/pad mux.
                  P_CCCOP, P_CCCOP_T,
                  P_DAA_SR, P_DAA_HDR, P_DAA_HACK, P_DAA_ARB, P_DAA_CAPTURE,
                  P_DAA_ASSIGN, P_DAA_AACK,
                  P_DASA_SR, P_DASA_HDR, P_DASA_HACK, P_DASA_DATA, P_DASA_DT,
                  -- stage-3 IBI monitor (B6), entered from P_IDLE when B7's
                  -- bus-start sensor sees a TARGET-driven START while the
                  -- controller is idle. The controller then provides SCL and
                  -- clocks an OD arbitrated header (release + sample), ACK/NACKs
                  -- per CR.IBIEN (R2), optionally clocks one MDB byte + T when
                  -- the matching DAT entry has BCR[2]=1, captures into I3CxIBI,
                  -- and STOPs. B2/B3/B8 untouched (D23 bolt-on).
                  P_IBI_HDR, P_IBI_ACK, P_IBI_MDB, P_IBI_MDBT, P_IBI_CAP);
    signal ph : ph_t;

    -- ---- register storage ------------------------------------------------
    signal I3CxCR  : std_logic_vector(29 downto 0); -- reset 0 except SDAPP=1
    signal I3CxCMD : std_logic_vector(31 downto 0);
    signal I3CxTX  : std_logic_vector(7 downto 0);
    signal I3CxRX  : std_logic_vector(7 downto 0);  -- volatile (FSM-written)
    signal I3CxSR  : std_logic_vector(10 downto 0); -- assembled status word

    -- Registered-read pre-latch snapshots (QSPI reg_sync idiom): only SR and
    -- RX carry volatile bits; CR/CMD/TX are plain SW registers read straight.
    signal I3CxSR_ltch : std_logic_vector(10 downto 0);
    signal I3CxRX_ltch : std_logic_vector(7 downto 0);

    -- ---- CR field taps (live, combinational) -----------------------------
    signal q_en  : std_logic;
    signal tcie, errie, daaie, ibiie, rxfie, txeie : std_logic;

    -- ---- memory-map decode -----------------------------------------------
    signal i3c_slot : natural range 0 to 63;

    -- ---- launch / handshake / W1C clear pulses ---------------------------
    signal i3c_launch  : std_logic;  -- held level, retired by clr_launch (FSM)
    signal clr_launch  : std_logic;
    signal tx_arm      : std_logic;  -- TX byte pending, retired by clr_tx_arm
    signal clr_tx_arm  : std_logic;
    signal clr_tcif, clr_rxfull, clr_txeif : std_logic;
    signal clr_anack, clr_eodf, clr_arblost : std_logic;

    -- ---- status flip-flops (FSM-set, W1C-cleared) ------------------------
    signal tcif_flag, rxfull_flag, txeif_flag : std_logic;
    signal anack_flag, eodf_flag, arblost_flag : std_logic;
    signal busy : std_logic;

    -- ---- baud generator (B2, D21: two-chained ClkGate, mode-switched reload)
    signal en_clk_baud_src : std_logic;
    signal clk_baud_src    : std_logic;
    signal en_clk_baud     : std_logic;
    signal clk_baud        : std_logic;
    signal baud_counter    : std_logic_vector(7 downto 0);
    signal baud_reload     : std_logic_vector(7 downto 0);
    signal pp_rate         : std_logic; -- '1' => PP data phase reloads PPBR

    -- ---- serial core state (clk_baud domain) -----------------------------
    signal sub    : natural range 0 to 3;   -- SCL sub-phase within a bit
    signal bitno  : natural range 0 to 7;   -- bit index within a byte
    signal dbyte  : natural range 0 to 255; -- current data-byte index
    signal shift  : std_logic_vector(7 downto 0); -- MSB-first transmit reg
    signal rx_acc : std_logic_vector(7 downto 0); -- receive accumulator
    signal tx_byte : std_logic_vector(7 downto 0); -- latched write byte (parity)
    signal ack_r  : std_logic;  -- sampled address ACK (0=ACK)
    signal eod    : std_logic;  -- early end-of-data seen on a read T handshake
    signal wt_parity : std_logic; -- odd-parity T of tx_byte (D24)

    -- ---- transaction-local latched descriptor (frozen at launch, D22) -----
    signal t_addr    : std_logic_vector(6 downto 0);
    signal t_rnw     : std_logic;
    signal t_stopen  : std_logic;
    signal t_busmode : std_logic;  -- 1 = legacy-I2C
    signal t_ppdata  : std_logic;  -- 1 = push-pull SDR data (I3C, SDAPP=1)
    signal t_dlen    : natural range 0 to 255;
    signal t_odbr    : std_logic_vector(7 downto 0);
    signal t_ppbr    : std_logic_vector(7 downto 0);

    -- ---- combinational pad-drive intents (B8, D20) -----------------------
    signal sda_drv     : std_logic; -- value the framer wants on SDA
    signal sda_release : std_logic; -- '1' => high-Z (sample / target drives)
    signal sda_pp      : std_logic; -- '1' => push-pull; else open-drain
    signal scl_r       : std_logic; -- registered SCL level

    -- ---- B7 async bus-condition sensor (D5) ------------------------------
    -- Observes external START/STOP on the resolved bus. In the MVP nothing
    -- consumes these (we are the sole controller); they are the hooks the
    -- stage-3 target-START / IBI detector builds on.
    signal bus_busy  : std_logic;  -- '1' between an external START and STOP
    signal bus_start : std_logic;  -- pulse-ish: START (SDA fall, SCL high)

    -- ---- B5 DAA engine + DAT register file (stage 2, R1 = 4 entries) ------
    -- D18 indexed window (slots 5/6/7 select entry IDX). The DAT storage is
    -- owned by ONE process (dat_proc) on the FREE-RUNNING clk so both firmware
    -- writes (equivalent to reg_write's gated-ClkMem case: ClkMem=clk while
    -- selected) and the DAA-run captures (clk_baud domain, via edge-detected
    -- handshakes) commit through a single driver -- the two writers are
    -- mutually exclusive in time (firmware writes while idle, DAA captures
    -- while busy) but VHDL still needs one driver per signal.
    type dat_addr_arr is array (0 to 3) of std_logic_vector(6 downto 0);
    type dat_pid_arr  is array (0 to 3) of std_logic_vector(47 downto 0);
    type dat_byte_arr is array (0 to 3) of std_logic_vector(7 downto 0);
    signal dat_evalid    : std_logic_vector(0 to 3);
    signal dat_dynaddr   : dat_addr_arr;
    signal dat_dynvalid  : std_logic_vector(0 to 3);
    signal dat_stataddr  : dat_addr_arr;
    signal dat_statvalid : std_logic_vector(0 to 3);
    signal dat_pid       : dat_pid_arr;
    signal dat_bcr       : dat_byte_arr;
    signal dat_dcr       : dat_byte_arr;
    signal dat_idx       : natural range 0 to 7;  -- persisted IDX (slots 5/6/7)

    -- latched CCC/DAA command fields (frozen at launch, D22)
    signal t_ccc, t_cccdir, t_daarun, t_dasa : std_logic;
    signal t_cccop    : std_logic_vector(7 downto 0);
    signal in_ccc_hdr : std_logic;  -- '1' => current P_ACK is the 0x7E CCC header ACK

    -- DAA run state (clk_baud domain)
    signal daa_bit     : natural range 0 to 63;
    signal daa_acc     : std_logic_vector(63 downto 0);  -- {PID[47:0],BCR[7:0],DCR[7:0]}
    signal daa_cap_idx : natural range 0 to 3;           -- DAT entry the round writes

    -- DAT-storage handshakes (fsm clk_baud domain -> dat_proc clk domain,
    -- edge-detected there so a multi-clk_baud-cycle level commits exactly once)
    signal dat_cap_req : std_logic;  -- commit captured PID/BCR/DCR + EVALID/DYNVALID/DAAFULL
    signal dat_dv_req  : std_logic;  -- set DYNVALID only (SETDASA)
    signal dat_dv_idx  : natural range 0 to 3;
    signal dat_cap_req_d, dat_dv_req_d : std_logic;  -- clk-domain edge detectors

    -- combinational DAT lookups (priority-encoded from the storage)
    signal daa_free_idx    : natural range 0 to 3;  -- first EVALID=0 entry
    signal daa_has_free    : std_logic;
    signal dasa_idx        : natural range 0 to 3;   -- first STATVALID entry matching t_addr
    signal dasa_match      : std_logic;
    signal daa_assign_addr : std_logic_vector(6 downto 0);
    signal daa_addr_parity : std_logic;

    -- stage-2 status flags (FSM-set, W1C-cleared)
    signal daadone_flag, daafull_flag : std_logic;
    signal clr_daadone, clr_daafull   : std_logic;

    -- ---- B6 IBI monitor (stage 3) ----------------------------------------
    signal ibien : std_logic;                       -- CR.IBIEN live tap
    -- level request: B7 sensor latches it when a target START arrives while the
    -- controller is idle; retired by the FSM (clr_ibi_req) at service entry.
    signal ibi_req     : std_logic;
    signal clr_ibi_req : std_logic;
    signal t_ibien     : std_logic;                 -- IBIEN latched at detect
    -- IBI service scratch (clk_baud domain)
    signal ibi_acc      : std_logic_vector(7 downto 0);  -- header {addr,RnW}
    signal ibi_mdb_acc  : std_logic_vector(7 downto 0);  -- MDB accumulator
    signal ibi_addr_cap : std_logic_vector(6 downto 0);  -- captured IBI address
    -- I3CxIBI capture registers (slot 8; W1C-invalidated with SR.IBIP). Reset
    -- explicitly like RX/flags (the QSPI unreset-RX trap): never wiped by q_en=0.
    signal ibi_addr    : std_logic_vector(6 downto 0);
    signal ibi_valid   : std_logic;
    signal ibi_mdb     : std_logic_vector(7 downto 0);
    signal ibi_hasdata : std_logic;
    signal ibi_acked   : std_logic;
    signal ibip_flag   : std_logic;                 -- SR.IBIP (rw1)
    signal clr_ibip    : std_logic;
    -- combinational DAT lookup: match captured IBI addr against DYNVALID
    -- entries' DYNADDR; no match => BCR[2]=0 (no MDB) but still capture.
    signal ibi_dat_match : std_logic;
    signal ibi_dat_idx   : natural range 0 to 3;
    signal ibi_bcr2      : std_logic;

begin

    ------------------------- Signal Routing --------------------------------
    q_en  <= I3CxCR(0);
    ibien <= I3CxCR(3);
    tcie  <= I3CxCR(24);
    errie <= I3CxCR(25);
    daaie <= I3CxCR(26);
    ibiie <= I3CxCR(27);
    rxfie <= I3CxCR(28);
    txeie <= I3CxCR(29);

    busy <= '0' when ph = P_IDLE else '1';

    -- I3CxSR assembly (S3): bits 7-10 (DAADONE/DAAFULL/IBIP/IBIWON) are
    -- stage-2/3, constant 0 in the MVP (D23).
    I3CxSR(0)  <= busy;
    I3CxSR(1)  <= tcif_flag;
    I3CxSR(2)  <= rxfull_flag;
    I3CxSR(3)  <= txeif_flag;
    I3CxSR(4)  <= anack_flag;
    I3CxSR(5)  <= eodf_flag;
    I3CxSR(6)  <= arblost_flag;
    I3CxSR(7)  <= daadone_flag;  -- stage 2 (D23: activated)
    I3CxSR(8)  <= daafull_flag;  -- stage 2
    I3CxSR(9)  <= ibip_flag;     -- IBIP (stage 3, D23: activated)
    -- IBIWON (live): high across the whole IBI service window (header..capture).
    I3CxSR(10) <= '1' when (ph = P_IBI_HDR or ph = P_IBI_ACK or ph = P_IBI_MDB or
                            ph = P_IBI_MDBT or ph = P_IBI_CAP) else '0';

    -- odd-parity T of the latched write byte (D24: T = not(xor of data bits),
    -- so {data,T} carries an odd number of 1s).
    wt_parity <= not (tx_byte(7) xor tx_byte(6) xor tx_byte(5) xor tx_byte(4) xor
                      tx_byte(3) xor tx_byte(2) xor tx_byte(1) xor tx_byte(0));

    -- ---- B5 combinational DAT lookups ------------------------------------
    -- First entry with EVALID=0 = the round's capture target (D18/task rule).
    daa_free_idx <= 0 when dat_evalid(0) = '0' else
                    1 when dat_evalid(1) = '0' else
                    2 when dat_evalid(2) = '0' else 3;
    daa_has_free <= '1' when (dat_evalid(0) = '0' or dat_evalid(1) = '0' or
                              dat_evalid(2) = '0' or dat_evalid(3) = '0') else '0';
    -- SETDASA: first STATVALID entry whose STATADDR matches CMD.ADDR (t_addr).
    dasa_idx <= 0 when (dat_statvalid(0) = '1' and dat_stataddr(0) = t_addr) else
                1 when (dat_statvalid(1) = '1' and dat_stataddr(1) = t_addr) else
                2 when (dat_statvalid(2) = '1' and dat_stataddr(2) = t_addr) else 3;
    dasa_match <= '1' when ((dat_statvalid(0) = '1' and dat_stataddr(0) = t_addr) or
                            (dat_statvalid(1) = '1' and dat_stataddr(1) = t_addr) or
                            (dat_statvalid(2) = '1' and dat_stataddr(2) = t_addr) or
                            (dat_statvalid(3) = '1' and dat_stataddr(3) = t_addr)) else '0';
    -- ENTDAA assigned address = the free entry's pre-programmed DYNADDR + odd
    -- parity bit (D19 assign: 7-bit addr followed by odd-parity, push-pull).
    daa_assign_addr <= dat_dynaddr(daa_free_idx);
    daa_addr_parity <= not (daa_assign_addr(6) xor daa_assign_addr(5) xor
                            daa_assign_addr(4) xor daa_assign_addr(3) xor
                            daa_assign_addr(2) xor daa_assign_addr(1) xor
                            daa_assign_addr(0));

    -- B6 IBI DAT lookup: does any DYNVALID entry own the captured IBI address?
    -- (no match => treat BCR[2]=0, i.e. no MDB, but the capture still happens.)
    ibi_dat_match <= '1' when ((dat_dynvalid(0) = '1' and dat_dynaddr(0) = ibi_addr_cap) or
                               (dat_dynvalid(1) = '1' and dat_dynaddr(1) = ibi_addr_cap) or
                               (dat_dynvalid(2) = '1' and dat_dynaddr(2) = ibi_addr_cap) or
                               (dat_dynvalid(3) = '1' and dat_dynaddr(3) = ibi_addr_cap)) else '0';
    ibi_dat_idx <= 0 when (dat_dynvalid(0) = '1' and dat_dynaddr(0) = ibi_addr_cap) else
                   1 when (dat_dynvalid(1) = '1' and dat_dynaddr(1) = ibi_addr_cap) else
                   2 when (dat_dynvalid(2) = '1' and dat_dynaddr(2) = ibi_addr_cap) else 3;
    -- BCR[2]=1 => the IBI carries a mandatory data byte (MDB).
    ibi_bcr2 <= ibi_dat_match and dat_bcr(ibi_dat_idx)(2);

    ---------------------- End Signal Routing -------------------------------

    -- Registered-read pre-latch (QSPI reg_sync idiom, verbatim shape).
    reg_sync: process(EnMemPeriph, I3CxRX, I3CxSR)
    begin
        if falling_edge(EnMemPeriph) then
            I3CxRX_ltch <= not I3CxRX;
            I3CxSR_ltch <= not I3CxSR;
        end if;
    end process;

    -------------------------- Memory Logic ---------------------------------
    i3c_slot <= slv2uint(MABPart) when EnMemPeriph = '0' else 0;

    -- Register Write Process (QSPI reg_write structure). CMD lane-0 write is
    -- the SOLE launch trigger (D16): content is always captured; the launch
    -- pulse is suppressed (no corruption) when I3CEN=0 or BUSY=1. clr_launch /
    -- clr_tx_arm / clr_* retire ASYNCHRONOUSLY (level-sensitive, in the
    -- sensitivity list) so the gated ClkMem never has to consume an FSM pulse.
    reg_write: process(resetn, ClkMem, EnMemPeriph, clr_launch, clr_tx_arm, q_en)
    begin
        if resetn = '0' then
            I3CxCR  <= (2 => '1', others => '0'); -- SDAPP=1 reset default
            I3CxCMD <= (others => '0');
            I3CxTX  <= (others => '0');
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case i3c_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then I3CxCR(7 downto 0)   <= wdata(7 downto 0);   end if;
                        if WEn(1) = '0' then I3CxCR(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then I3CxCR(23 downto 16) <= wdata(23 downto 16); end if;
                        if WEn(3) = '0' then I3CxCR(29 downto 24) <= wdata(29 downto 24); end if;
                    when SLOT_CMD =>
                        if WEn(0) = '0' then
                            I3CxCMD(7 downto 0) <= wdata(7 downto 0);
                            if q_en = '1' and busy = '0' then
                                i3c_launch <= '1'; -- launch guard (D16)
                            end if;
                        end if;
                        if WEn(1) = '0' then I3CxCMD(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then I3CxCMD(23 downto 16) <= wdata(23 downto 16); end if;
                        if WEn(3) = '0' then I3CxCMD(31 downto 24) <= wdata(31 downto 24); end if;
                    when SLOT_TX =>
                        if WEn(0) = '0' then
                            I3CxTX <= wdata(7 downto 0);
                            tx_arm <= '1'; -- arm the byte-pending handshake (D7/D17)
                        end if;
                    when SLOT_SR =>
                        if WEn(0) = '0' then -- W1C: writing 1 clears; BUSY(0) is RO
                            if wdata(1) = '1' then clr_tcif    <= '1'; end if;
                            if wdata(2) = '1' then clr_rxfull  <= '1'; end if;
                            if wdata(3) = '1' then clr_txeif   <= '1'; end if;
                            if wdata(4) = '1' then clr_anack   <= '1'; end if;
                            if wdata(5) = '1' then clr_eodf    <= '1'; end if;
                            if wdata(6) = '1' then clr_arblost <= '1'; end if;
                            if wdata(7) = '1' then clr_daadone <= '1'; end if;
                            if wdata(8) = '1' then clr_daafull <= '1'; end if;
                            if wdata(9) = '1' then clr_ibip    <= '1'; end if;
                        end if;
                    when others =>
                        null; -- RX read-only; DAT/DATPID/DATINFO/IBI inert (D23)
                end case;
            end if;
        end if;

        -- Async clear-pulse retirement (QSPI/I2C level-sensitive idiom).
        if resetn = '0' or clr_launch = '1' then
            i3c_launch <= '0';
        end if;
        -- A TX byte armed BEFORE I3CEN is raised (bench writes TX, then CR, then
        -- CMD) must survive to be consumed by P_WLOAD; only reset or the FSM's
        -- own consume-pulse retires it. (Gating on q_en='0' here silently
        -- dropped the first streamed byte and hung P_WLOAD -- found in sim.)
        if resetn = '0' or clr_tx_arm = '1' then
            tx_arm <= '0';
        end if;
        if resetn = '0' or EnMemPeriph = '1' then
            clr_tcif    <= '0';
            clr_rxfull  <= '0';
            clr_txeif   <= '0';
            clr_anack   <= '0';
            clr_eodf    <= '0';
            clr_arblost <= '0';
            clr_daadone <= '0';
            clr_daafull <= '0';
            clr_ibip    <= '0';
        end if;
    end process;

    -- Register Read Process (synchronous). Volatile SR/RX come from the
    -- pre-latch (un-inverted); DAT/DATPID/DATINFO/IBI/reserved read 0 (D23).
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case i3c_slot is
                when SLOT_CR      => rdata_out <= (31 downto 30 => '0') & I3CxCR;
                when SLOT_CMD     => rdata_out <= I3CxCMD;
                when SLOT_TX      => rdata_out <= (31 downto 8 => '0') & I3CxTX;
                when SLOT_RX      => rdata_out <= (31 downto 8 => '0') & (not I3CxRX_ltch);
                when SLOT_SR      => rdata_out <= (31 downto 11 => '0') & (not I3CxSR_ltch);
                -- stage-2 DAT window (D18), entry selected by the persisted IDX.
                -- Entries 4-7 read invalid (R1: 4 entries) -> only IDX field.
                when SLOT_DAT     =>
                    if dat_idx < 4 then
                        rdata_out <= x"000" &
                            dat_statvalid(dat_idx) & dat_stataddr(dat_idx) &
                            dat_dynvalid(dat_idx)  & dat_dynaddr(dat_idx)  &
                            dat_evalid(dat_idx)    &
                            conv_std_logic_vector(dat_idx, 3);
                    else
                        rdata_out <= (31 downto 3 => '0') &
                            conv_std_logic_vector(dat_idx, 3);
                    end if;
                when SLOT_DATPID  =>
                    if dat_idx < 4 then rdata_out <= dat_pid(dat_idx)(31 downto 0);
                    else                rdata_out <= (others => '0'); end if;
                when SLOT_DATINFO =>
                    if dat_idx < 4 then
                        rdata_out <= dat_dcr(dat_idx) & dat_bcr(dat_idx) &
                                     dat_pid(dat_idx)(47 downto 32);
                    else
                        rdata_out <= (others => '0');
                    end if;
                -- stage-3 IBI capture (slot 8): [17]IBIACKED [16]IBIHASDATA
                -- [15:8]IBIMDB [7]IBIVALID [6:0]IBIADDR. Read straight from the
                -- capture regs (written only while BUSY, read only while idle).
                when SLOT_IBI     =>
                    rdata_out <= (31 downto 18 => '0') &
                        ibi_acked & ibi_hasdata & ibi_mdb & ibi_valid & ibi_addr;
                when others       => rdata_out <= (others => '0');
            end case;
        end if;
    end process;

    ---------- B5 DAT register file storage (free-running clk domain) -------
    -- Single driver for all DAT entries. Firmware writes (slots 5/6/7) are
    -- captured on rising_edge(clk) under EnMemPeriph='0' -- identical to
    -- reg_write's rising_edge(ClkMem)+EnMemPeriph='0' since ClkMem=clk while
    -- selected. DAA-run commits arrive via edge-detected handshakes from the
    -- clk_baud FSM (dat_cap_req = PID/BCR/DCR+EVALID/DYNVALID/DAAFULL capture;
    -- dat_dv_req = SETDASA DYNVALID mark). Disable (q_en=0) does NOT wipe the
    -- table (D23: entries persist across frames / disable).
    dat_proc: process(clk, resetn)
        variable idx_sel : natural range 0 to 7;
    begin
        if resetn = '0' then
            dat_evalid    <= (others => '0');
            dat_dynvalid  <= (others => '0');
            dat_statvalid <= (others => '0');
            dat_idx       <= 0;
        elsif rising_edge(clk) then
            -- firmware register writes (gated-select equivalent of reg_write)
            if EnMemPeriph = '0' and WEn(0) = '0' then
                case i3c_slot is
                    when SLOT_DAT =>
                        idx_sel := slv2uint(wdata(2 downto 0));
                        dat_idx <= idx_sel;
                        if idx_sel < 4 then
                            dat_evalid(idx_sel)    <= wdata(3);
                            dat_dynaddr(idx_sel)   <= wdata(10 downto 4);
                            dat_dynvalid(idx_sel)  <= wdata(11);
                            dat_stataddr(idx_sel)  <= wdata(18 downto 12);
                            dat_statvalid(idx_sel) <= wdata(19);
                        end if;
                    when SLOT_DATPID =>
                        if dat_idx < 4 then
                            dat_pid(dat_idx)(31 downto 0) <= wdata;
                        end if;
                    when SLOT_DATINFO =>
                        if dat_idx < 4 then
                            dat_pid(dat_idx)(47 downto 32) <= wdata(15 downto 0);
                            dat_bcr(dat_idx)               <= wdata(23 downto 16);
                            dat_dcr(dat_idx)               <= wdata(31 downto 24);
                        end if;
                    when others => null;
                end case;
            end if;

            -- DAA capture commit (rising edge of the held request only).
            dat_cap_req_d <= dat_cap_req;
            if dat_cap_req = '1' and dat_cap_req_d = '0' then
                dat_pid(daa_cap_idx)      <= daa_acc(63 downto 16);
                dat_bcr(daa_cap_idx)      <= daa_acc(15 downto 8);
                dat_dcr(daa_cap_idx)      <= daa_acc(7 downto 0);
                dat_evalid(daa_cap_idx)   <= '1';
                dat_dynvalid(daa_cap_idx) <= '1';
            end if;

            -- SETDASA DYNVALID mark (rising edge of the held request only).
            dat_dv_req_d <= dat_dv_req;
            if dat_dv_req = '1' and dat_dv_req_d = '0' then
                dat_dynvalid(dat_dv_idx) <= '1';
            end if;
        end if;
    end process;

    ---------- B2 baud generator (D21, QSPI two-chained-ClkGate) ------------
    -- Reload is muxed by the LATCHED phase drive-mode (pp_rate, set by the
    -- framer at data-phase entry and stable across a bit): OD phases (address,
    -- start/stop, and all legacy phases) reload ODBR; PP data phases reload
    -- PPBR. pp_rate flips only on phase boundaries (= counter-reload edges),
    -- so it cannot glitch mid-bit. baud_counter is reset while idle (busy='0')
    -- so the first clk_baud edge after a launch is prompt -- this makes BUSY
    -- rise within a couple of clk cycles, closing the GROUP 9b launch-guard
    -- race regardless of the value the counter idled at.
    -- ibi_req wakes the serial core out of P_IDLE to service a target IBI
    -- (busy=0 there, so the baud counter is held at 0 -> prompt first edge,
    -- same trick the launch path uses).
    en_clk_baud_src <= q_en and (busy or i3c_launch or ibi_req);

    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn  => not clk,
            En     => en_clk_baud_src,
            ClkOut => clk_baud_src
        );

    baud_reload <= t_ppbr when pp_rate = '1' else t_odbr;

    baud_cntr_proc: process(clk_baud_src, resetn, q_en, busy)
    begin
        if resetn = '0' or q_en = '0' or busy = '0' then
            baud_counter <= (others => '0');
        elsif rising_edge(clk_baud_src) then
            if baud_counter = "00000000" then
                baud_counter <= baud_reload;
            else
                baud_counter <= baud_counter - 1;
            end if;
        end if;
    end process;

    en_clk_baud <= '1' when baud_counter = "00000000" and en_clk_baud_src = '1' else '0';

    cg_clk_baud: entity work.ClkGate
        port map (
            ClkIn  => not clk,
            En     => en_clk_baud,
            ClkOut => clk_baud
        );

    ---------- B3 bit engine + B4 framer FSM (clk_baud domain) --------------
    -- One bit occupies a full 4-sub-state SCL cycle. Drive policy is the FROZEN
    -- D19 phase table via the D20 pad mux: the address header + START/Sr/STOP
    -- SDA are OPEN-DRAIN (sda_pp=0, sda_release=0: drive only 0, release=1 for
    -- SDA_IN='H'); SDR WRITE data + the odd-parity write-T are PUSH-PULL
    -- (sda_pp=1); in LEGACY-I2C mode (t_busmode=1) SDA is open-drain in every
    -- phase (sda_pp<=not t_busmode on the data phase). SAMPLE slots (address
    -- ACK, read data, non-final read T, legacy write ACK) RELEASE and read
    -- SDA_IN at sub2. The wired-AND 'H' pull is the bus contract (S7); a weak
    -- 'H' released bit reads as '1' at every sampler. D27 anti-clone: exactly
    -- ONE address-header ACK per frame; the data path has NO per-byte ACK --
    -- WRITE drives odd-parity T (D24, wt_parity, PP, no sample); READ
    -- samples/drives the T handshake (D25).
    fsm_proc: process(resetn, clk_baud, q_en, i3c_launch,
                      clr_tcif, clr_rxfull, clr_txeif, clr_anack, clr_eodf, clr_arblost,
                      clr_daadone, clr_daafull, clr_ibip)
    begin
        if resetn = '0' or q_en = '0' then
            -- I3CEN=0 holds the serial core in reset but does NOT wipe
            -- RX/flags (those clear only on resetn=0 or explicit W1C).
            ph          <= P_IDLE;
            sub         <= 0;
            bitno       <= 0;
            dbyte       <= 0;
            scl_r       <= '1';
            sda_release <= '1';
            sda_pp      <= '0';
            sda_drv     <= '1';
            pp_rate     <= '0';
            eod         <= '0';
            ack_r       <= '0';
            clr_launch  <= '0';
            clr_tx_arm  <= '0';
            in_ccc_hdr  <= '0';
            dat_cap_req <= '0';
            dat_dv_req  <= '0';
            daa_bit     <= 0;
            daa_cap_idx <= 0;
            dat_dv_idx  <= 0;
            clr_ibi_req <= '0';
            t_ibien     <= '0';
            ibi_acc     <= (others => '0');
            ibi_mdb_acc <= (others => '0');
            ibi_addr_cap <= (others => '0');
        elsif rising_edge(clk_baud) then
            clr_launch  <= '0';
            clr_tx_arm  <= '0';
            clr_ibi_req <= '0';

            case ph is
                ------------------------------------------------------------
                when P_IDLE =>
                    scl_r <= '1'; sda_release <= '1'; sda_pp <= '0'; sub <= 0;
                    pp_rate <= '0';
                    if i3c_launch = '1' then
                        clr_launch <= '1';
                        eod <= '0';
                        -- latch the transaction descriptor (frozen at launch)
                        t_addr    <= I3CxCMD(6 downto 0);
                        t_rnw     <= I3CxCMD(7);
                        t_stopen  <= I3CxCMD(9);
                        t_dlen    <= slv2uint(I3CxCMD(23 downto 16));
                        t_busmode <= I3CxCR(1);
                        t_ppdata  <= I3CxCR(2) and (not I3CxCR(1));
                        t_odbr    <= I3CxCR(15 downto 8);
                        t_ppbr    <= I3CxCR(23 downto 16);
                        -- stage-2 CCC/DAA descriptor (D23: latched, no longer inert)
                        t_ccc     <= I3CxCMD(10);
                        t_cccdir  <= I3CxCMD(11);
                        t_daarun  <= I3CxCMD(12);
                        t_dasa    <= I3CxCMD(13);
                        t_cccop   <= I3CxCMD(31 downto 24);
                        bitno     <= 0;
                        -- CCC/ENTDAA/SETDASA prepend the 0x7E broadcast + W header
                        -- (D33: private transfers do NOT); the header ACK routes
                        -- into the B5 sub-sequencer via in_ccc_hdr.
                        if (I3CxCMD(10) or I3CxCMD(12) or I3CxCMD(13)) = '1' then
                            shift      <= "1111110" & '0';   -- 0x7E + W
                            in_ccc_hdr <= '1';
                        else
                            shift      <= I3CxCMD(6 downto 0) & I3CxCMD(7); -- {addr,RnW}
                            in_ccc_hdr <= '0';
                        end if;
                        if I3CxCMD(8) = '1' then   -- CMD.SR: repeated-START entry
                            ph <= P_SR;
                        else
                            ph <= P_START;
                        end if;
                    elsif ibi_req = '1' then
                        -- Bus-available IBI: a target drove a START while we were
                        -- idle. Take over SCL and clock the OD arbitrated header.
                        -- Latch the IBI baud/mode context (no CMD launch here):
                        -- I3C-SDR (SCL push-pull), header runs at ODBR.
                        clr_ibi_req <= '1';
                        t_busmode   <= '0';
                        t_ppdata    <= '0';
                        t_odbr      <= I3CxCR(15 downto 8);
                        t_ppbr      <= I3CxCR(23 downto 16);
                        t_ibien     <= ibien;
                        pp_rate     <= '0';
                        ibi_acc     <= (others => '0');
                        ibi_mdb_acc <= (others => '0');
                        bitno       <= 0;
                        sub         <= 0;
                        ph          <= P_IBI_HDR;
                    end if;

                ------------------------------------------------------------
                -- START: SDA falls while SCL high, then SCL falls.
                when P_START =>
                    if sub = 0 then
                        -- OD: drive SDA low (release=0, pp=0, drv=0) while SCL high.
                        scl_r <= '1'; sda_pp <= '0'; sda_release <= '0'; sda_drv <= '0';
                        sub <= 1;
                    else
                        scl_r <= '0'; sub <= 0; ph <= P_ADDR;
                    end if;

                -- Repeated START: release SDA high, SCL high, SDA falls (OD).
                when P_SR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '1';
                                  sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sda_release <= '0'; sda_drv <= '0';
                                  sub <= 3;
                        when others => scl_r <= '0'; sub <= 0; ph <= P_ADDR;
                    end case;

                ------------------------------------------------------------
                -- Address header (7 addr + RnW), OPEN-DRAIN per D19 (release on
                -- a 1, drive a 0); arb-compare hook per D3 (load-bearing for
                -- stage 3 -- never fires here, no competing driver).
                when P_ADDR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if shift(7) = '1' and SDA_IN = '0' then
                                      arblost_flag <= '1'; ph <= P_DONE; sub <= 0;
                                  else
                                      sub <= 3;
                                  end if;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_ACK;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Single address ACK (D27: the ONLY ACK in an I3C frame).
                when P_ACK =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; ack_r <= SDA_IN; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            if ack_r = '0' then          -- ACKed
                                if in_ccc_hdr = '1' then
                                    -- 0x7E CCC header ACK: send the CCC opcode
                                    -- byte next (B5). DAA phases use ODBR baud.
                                    in_ccc_hdr <= '0';
                                    shift   <= t_cccop;
                                    tx_byte <= t_cccop;   -- parity source for the T
                                    pp_rate <= '0';
                                    bitno   <= 0;
                                    ph      <= P_CCCOP;
                                else
                                    dbyte <= 0;
                                    pp_rate <= t_ppdata;      -- data phases pick PPBR
                                    if t_dlen = 0 then         -- no data phase
                                        tcif_flag <= '1';
                                        if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                    elsif t_rnw = '1' then
                                        ph <= P_RDATA;
                                    else
                                        ph <= P_WLOAD;
                                    end if;
                                end if;
                            else                          -- address NACK
                                anack_flag <= '1'; tcif_flag <= '1';
                                if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                            end if;
                    end case;

                ------------------------------------------------------------
                -- WRITE-BYTE LOAD: byte-streaming handshake (D7/D17). Hold SCL
                -- low until a TX byte is armed; consume it, set TXEIF (register
                -- now empty), retire tx_arm.
                when P_WLOAD =>
                    scl_r <= '0'; sda_release <= '1'; sda_pp <= '0';
                    if tx_arm = '1' then
                        shift <= I3CxTX; tx_byte <= I3CxTX;
                        clr_tx_arm <= '1'; txeif_flag <= '1';
                        bitno <= 0; sub <= 0; ph <= P_WDATA;
                    end if;

                -- WRITE data (8 bits, D24 -- NO per-byte ACK). PP in I3C-SDR,
                -- open-drain in legacy-I2C (sda_pp = not t_busmode).
                when P_WDATA =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= not t_busmode; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;   -- no sample (PP write)
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_WT;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- WRITE T slot: I3C drives odd-parity T (D24, PP, no sample);
                -- legacy releases + samples a real per-byte ACK (D27 contrast).
                when P_WT =>
                    case sub is
                        when 0 => scl_r <= '0';
                                  if t_busmode = '0' then
                                      sda_pp <= '1'; sda_release <= '0'; sda_drv <= wt_parity;
                                  else
                                      sda_release <= '1'; sda_pp <= '0';
                                  end if;
                                  sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if t_busmode = '1' and SDA_IN /= '0' then
                                      anack_flag <= '1'; -- legacy per-byte NACK
                                  end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0'; sub <= 0;
                                  if dbyte = t_dlen - 1 then
                                      tcif_flag <= '1';
                                      if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                  else
                                      dbyte <= dbyte + 1; ph <= P_WLOAD;
                                  end if;
                    end case;

                ------------------------------------------------------------
                -- READ data (8 bits): controller releases, target drives (PP);
                -- sample MSB-first at sub2.
                when P_RDATA =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if SDA_IN = '0' then rx_acc <= rx_acc(6 downto 0) & '0';
                                  else                 rx_acc <= rx_acc(6 downto 0) & '1'; end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0';
                                  if bitno = 7 then
                                      bitno <= 0; I3CxRX <= rx_acc; rxfull_flag <= '1';
                                      ph <= P_RT;
                                  else
                                      bitno <= bitno + 1;
                                  end if;
                                  sub <= 0;
                    end case;

                -- READ T handshake (D25): non-final byte releases + samples
                -- (target T=0 => EODF short read); final wanted byte DRIVES T
                -- low (terminate) then Sr/STOP.
                when P_RT =>
                    case sub is
                        when 0 => scl_r <= '0';
                                  if dbyte = t_dlen - 1 then
                                      sda_pp <= '1'; sda_release <= '0'; sda_drv <= '0';
                                  else
                                      sda_release <= '1'; sda_pp <= '0';
                                  end if;
                                  sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if dbyte /= t_dlen - 1 and SDA_IN = '0' then
                                      eod <= '1';
                                  end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0'; sub <= 0;
                                  if dbyte = t_dlen - 1 then
                                      tcif_flag <= '1';
                                      if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                  elsif eod = '1' then
                                      eodf_flag <= '1'; tcif_flag <= '1';
                                      if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                  else
                                      dbyte <= dbyte + 1; ph <= P_RWAIT;
                                  end if;
                    end case;

                -- READ drain wait: hold SCL low until software drains RX
                -- (RXFULL cleared) before overwriting it with the next byte.
                when P_RWAIT =>
                    scl_r <= '0'; sda_release <= '1'; sda_pp <= '0';
                    if rxfull_flag = '0' then
                        bitno <= 0; sub <= 0; ph <= P_RDATA;
                    end if;

                ------------------------------------------------------------
                -- STOP: SDA driven low (OD), SCL high, then SDA released so it
                -- rises to the wired-AND 'H' -- the STOP edge (D19: OD frame
                -- boundary). Relies on the model releasing after its final
                -- read T (no phantom read-byte drive, D-note / bench ruling 3).
                when P_STOP =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '0';
                                  sda_drv <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sda_release <= '1'; sub <= 3;
                        when others => scl_r <= '1'; sub <= 0; ph <= P_DONE;
                    end case;

                -- DONE: 1-edge settle tail, release bus, drop BUSY. Backstop
                -- clear of the DAT handshakes (ENTDAA also clears per round).
                when P_DONE =>
                    scl_r <= '1'; sda_release <= '1'; sda_pp <= '0'; sub <= 0;
                    dat_cap_req <= '0'; dat_dv_req <= '0';
                    ph <= P_IDLE;

                ------------------------------------------------------------
                -- B5 CCC / DAA sub-sequencer (stage 2). Drives the SAME bit
                -- engine + D20 pad mux as the MVP framer (D23 bolt-on).
                ------------------------------------------------------------
                -- CCC opcode byte: 8 bits push-pull (SDR), like P_WDATA.
                when P_CCCOP =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '1'; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_CCCOP_T;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- CCC opcode parity T (odd parity, PP, D24), then branch to the
                -- ENTDAA rounds / SETDASA send / plain-CCC payload.
                when P_CCCOP_T =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '1'; sda_release <= '0';
                                  sda_drv <= wt_parity; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            if t_daarun = '1' then
                                ph <= P_DAA_SR;                 -- ENTDAA rounds
                            elsif t_dasa = '1' then
                                if dasa_match = '1' then
                                    shift <= t_addr & '0';      -- static addr + W
                                    bitno <= 0; ph <= P_DASA_SR;
                                else                            -- no DAT entry: error
                                    anack_flag <= '1'; daadone_flag <= '1'; tcif_flag <= '1';
                                    if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                end if;
                            else                                -- plain CCC write
                                if t_cccdir = '1' then          -- direct: Sr + target addr
                                    shift <= t_addr & t_rnw;
                                    bitno <= 0; in_ccc_hdr <= '0';
                                    ph <= P_SR;                 -- -> P_ADDR -> P_ACK (data)
                                else                            -- broadcast payload
                                    dbyte <= 0; pp_rate <= t_ppdata;
                                    if t_dlen = 0 then
                                        tcif_flag <= '1';
                                        if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                                    else
                                        ph <= P_WLOAD;
                                    end if;
                                end if;
                            end if;
                    end case;

                ------------------------------------------------------------
                -- ENTDAA rounds (CMD.DAARUN). Each round: Sr -> 0x7E+R header
                -- -> ACK (NACK => no more devices => DAADONE) -> 64-bit OD arb
                -- capture -> assign 7-bit dyn addr + parity (PP) -> ACK.
                ------------------------------------------------------------
                -- Repeated START before the 0x7E+R header.
                when P_DAA_SR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '1'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sda_release <= '0'; sda_drv <= '0'; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            shift <= "1111110" & '1';   -- 0x7E + R
                            bitno <= 0; ph <= P_DAA_HDR;
                    end case;

                -- 0x7E+R header, open-drain (like P_ADDR).
                when P_DAA_HDR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_DAA_HACK;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Round ACK (OD). NACK => all assigned => DAADONE + STOP.
                -- ACK but no free DAT entry => DAADONE + STOP (exhausted).
                when P_DAA_HACK =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; ack_r <= SDA_IN; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            if ack_r = '0' and daa_has_free = '1' then
                                daa_bit <= 0; daa_acc <= (others => '0');
                                ph <= P_DAA_ARB;
                            else
                                daadone_flag <= '1'; tcif_flag <= '1';
                                if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                            end if;
                    end case;

                -- 64-bit open-drain arbitration capture (wired-AND: lowest PID
                -- wins on the resolved bus). Controller releases + samples.
                when P_DAA_ARB =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if SDA_IN = '0' then daa_acc <= daa_acc(62 downto 0) & '0';
                                  else                 daa_acc <= daa_acc(62 downto 0) & '1'; end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0'; sub <= 0;
                                  if daa_bit = 63 then daa_bit <= 0; ph <= P_DAA_CAPTURE;
                                  else daa_bit <= daa_bit + 1; end if;
                    end case;

                -- Commit the winner's PID/BCR/DCR into the free DAT entry (via
                -- dat_proc), set DAAFULL, and prime the assign shift register.
                when P_DAA_CAPTURE =>
                    daa_cap_idx  <= daa_free_idx;
                    dat_cap_req  <= '1';
                    daafull_flag <= '1';
                    shift <= daa_assign_addr & daa_addr_parity;  -- 7-bit addr + odd parity
                    bitno <= 0; sub <= 0;
                    ph <= P_DAA_ASSIGN;

                -- Drive the assigned dynamic address + parity, push-pull (D19).
                when P_DAA_ASSIGN =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '1'; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_DAA_AACK;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Assign ACK (OD). ACK => next round; NACK => DAADONE + STOP.
                when P_DAA_AACK =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; ack_r <= SDA_IN; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            dat_cap_req <= '0';   -- re-arm the capture handshake
                            if ack_r = '0' then
                                ph <= P_DAA_SR;   -- next round
                            else
                                daadone_flag <= '1'; tcif_flag <= '1';
                                if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                            end if;
                    end case;

                ------------------------------------------------------------
                -- SETDASA (CMD.DASA): direct CCC 0x87. After the CCC opcode:
                -- Sr -> static addr + W -> ACK -> one data byte (dyn addr << 1)
                -- from the matching DAT entry; mark that entry DYNVALID on ACK.
                ------------------------------------------------------------
                when P_DASA_SR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '1'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sda_release <= '0'; sda_drv <= '0'; sub <= 3;
                        when others => scl_r <= '0'; sub <= 0; bitno <= 0; ph <= P_DASA_HDR;
                    end case;

                -- Static address + W, open-drain.
                when P_DASA_HDR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_DASA_HACK;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Static-addr ACK. ACK => mark DYNVALID, send dyn-addr byte.
                -- NACK => ANACK + DAADONE + STOP.
                when P_DASA_HACK =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; ack_r <= SDA_IN; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            if ack_r = '0' then
                                dat_dv_req <= '1'; dat_dv_idx <= dasa_idx;   -- DYNVALID
                                shift   <= dat_dynaddr(dasa_idx) & '0';       -- dyn addr << 1
                                tx_byte <= dat_dynaddr(dasa_idx) & '0';       -- parity source
                                bitno <= 0; ph <= P_DASA_DATA;
                            else
                                anack_flag <= '1'; daadone_flag <= '1'; tcif_flag <= '1';
                                if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                            end if;
                    end case;

                -- Data byte (dyn addr << 1), push-pull SDR.
                when P_DASA_DATA =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '1'; sda_release <= '0';
                                  sda_drv <= shift(7); dat_dv_req <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_DASA_DT;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Data byte parity T (odd, PP), then STOP.
                when P_DASA_DT =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '1'; sda_release <= '0';
                                  sda_drv <= wt_parity; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; sub <= 0; tcif_flag <= '1';
                                  if t_stopen = '1' then ph <= P_STOP; else ph <= P_DONE; end if;
                    end case;

                ------------------------------------------------------------
                -- B6 IBI monitor (stage 3). Bus-available path only: the
                -- target has already driven the START; we provide SCL and
                -- clock the OD arbitrated header (release + sample the 7 addr
                -- bits + RnW=1 the target drives), then ACK/NACK per IBIEN.
                ------------------------------------------------------------
                -- IBI header: 8 bits (addr[6:0] then RnW), open-drain sample.
                when P_IBI_HDR =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if SDA_IN = '0' then ibi_acc <= ibi_acc(6 downto 0) & '0';
                                  else                 ibi_acc <= ibi_acc(6 downto 0) & '1'; end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0';
                                  if bitno = 7 then
                                      bitno <= 0;
                                      ibi_addr_cap <= ibi_acc(7 downto 1);  -- {addr,RnW}
                                      ph <= P_IBI_ACK;
                                  else
                                      bitno <= bitno + 1;
                                  end if;
                                  sub <= 0;
                    end case;

                -- IBI ACK/NACK (OD, R2): IBIEN=1 => drive low (ACK) then read
                -- MDB iff the matching DAT entry has BCR[2]=1; IBIEN=0 => release
                -- (NACK), clean STOP, no capture, no flag.
                when P_IBI_ACK =>
                    case sub is
                        when 0 => scl_r <= '0';
                                  if t_ibien = '1' then
                                      sda_pp <= '0'; sda_release <= '0'; sda_drv <= '0';  -- ACK
                                  else
                                      sda_release <= '1'; sda_pp <= '0';                  -- NACK
                                  end if;
                                  sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others =>
                                  scl_r <= '0'; sub <= 0;
                                  if t_ibien = '1' then
                                      if ibi_bcr2 = '1' then
                                          bitno <= 0; ph <= P_IBI_MDB;   -- clock MDB
                                      else
                                          ph <= P_IBI_CAP;               -- capture, no MDB
                                      end if;
                                  else
                                      ph <= P_STOP;                      -- NACKed: no capture
                                  end if;
                    end case;

                -- MDB byte: controller releases + samples 8 bits (target drives).
                when P_IBI_MDB =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1';
                                  if SDA_IN = '0' then ibi_mdb_acc <= ibi_mdb_acc(6 downto 0) & '0';
                                  else                 ibi_mdb_acc <= ibi_mdb_acc(6 downto 0) & '1'; end if;
                                  sub <= 3;
                        when others =>
                                  scl_r <= '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_IBI_MDBT;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- MDB T handshake: release + sample one bit, captured not checked (D26).
                when P_IBI_MDBT =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others => scl_r <= '0'; sub <= 0; ph <= P_IBI_CAP;
                    end case;

                -- Capture {addr, MDB, hasdata, acked} into I3CxIBI + set IBIP,
                -- then STOP. hasdata reflects BCR[2] (0 when no DAT match).
                when P_IBI_CAP =>
                    ibi_addr    <= ibi_addr_cap;
                    ibi_mdb     <= ibi_mdb_acc;
                    ibi_hasdata <= ibi_bcr2;
                    ibi_acked   <= '1';
                    ibi_valid   <= '1';
                    ibip_flag   <= '1';
                    ph          <= P_STOP;

            end case;
        end if;

        -- RX has no write-side reset elsewhere and the FSM only assigns it;
        -- reset here or its readback is 'X' until the first read (QSPI trap).
        if resetn = '0' then
            I3CxRX <= (others => '0');
        end if;

        -- Status-flag W1C application + reset (async level-sensitive, clr_* in
        -- the sensitivity list; disable q_en=0 does NOT clear flags, only
        -- resetn=0 or the explicit W1C pulse).
        if resetn = '0' or clr_tcif = '1'    then tcif_flag    <= '0'; end if;
        if resetn = '0' or clr_rxfull = '1'  then rxfull_flag  <= '0'; end if;
        if resetn = '0' or clr_txeif = '1'   then txeif_flag   <= '0'; end if;
        if resetn = '0' or clr_anack = '1'   then anack_flag   <= '0'; end if;
        if resetn = '0' or clr_eodf = '1'    then eodf_flag    <= '0'; end if;
        if resetn = '0' or clr_arblost = '1' then arblost_flag <= '0'; end if;
        if resetn = '0' or clr_daadone = '1' then daadone_flag <= '0'; end if;
        if resetn = '0' or clr_daafull = '1' then daafull_flag <= '0'; end if;

        -- IBIP W1C also INVALIDATES the I3CxIBI capture fields (slot-8 spec);
        -- reset clears both. Not gated by q_en (disable never wipes flags/IBI).
        if resetn = '0' or clr_ibip = '1' then
            ibip_flag   <= '0';
            ibi_valid   <= '0';
            ibi_hasdata <= '0';
            ibi_acked   <= '0';
            ibi_addr    <= (others => '0');
            ibi_mdb     <= (others => '0');
        end if;
    end process;

    ---------- B7 async bus-condition sensor (D5, I2C L257-303 form) --------
    -- START = SDA falling while SCL high; STOP = SDA rising while SCL high.
    -- Stage 3: a START seen while the controller is IDLE (busy=0, enabled) is a
    -- TARGET-driven IBI -- latch ibi_req to wake the framer (retired by the FSM
    -- clr_ibi_req at service entry). Controller-driven STARTs happen with
    -- ph/=P_IDLE (busy=1), so they never latch ibi_req.
    bus_sensor: process(resetn, SDA_IN, clr_ibi_req)
    begin
        if resetn = '0' then
            bus_busy  <= '0';
            bus_start <= '0';
            ibi_req   <= '0';
        else
            if falling_edge(SDA_IN) then
                if SCL_IN = '1' then
                    bus_busy  <= '1';
                    bus_start <= '1';
                    if busy = '0' and q_en = '1' then
                        ibi_req <= '1';
                    end if;
                end if;
            elsif rising_edge(SDA_IN) then
                if SCL_IN = '1' then
                    bus_busy  <= '0';
                    bus_start <= '0';
                end if;
            end if;
            if clr_ibi_req = '1' then
                ibi_req <= '0';
            end if;
        end if;
    end process;

    ---------- B8 combinational pad-drive mux (D20) -------------------------
    -- SDA: release => high-Z (sample / target drives); push-pull => strong
    -- drive; else open-drain (drive only 0, release a 1 to the wired-AND 'H').
    SDA_OUT <= sda_drv;
    SDA_DIR <= '0'         when sda_release = '1'
          else '1'         when sda_pp = '1'
          else not sda_drv;
    -- SCL (D20): I3C-SDR mode = push-pull, NO stretch; legacy-I2C mode =
    -- open-drain (SCL_DIR = not scl_r, SCL_OUT = '0') so a target may stretch
    -- by holding SCL_IN low. t_busmode is latched at launch; before the first
    -- launch ('U') the comparison is false => I3C-SDR push-pull default.
    SCL_OUT <= '0'         when t_busmode = '1' else scl_r;
    SCL_DIR <= (not scl_r) when t_busmode = '1' else '1';

    ---------- IRQ lines (D28, combinational = status AND enable) -----------
    irq_tc   <= tcif_flag    and tcie;
    irq_rxf  <= rxfull_flag  and rxfie;
    irq_txe  <= txeif_flag   and txeie;
    irq_nack <= anack_flag   and errie;
    irq_eod  <= eodf_flag    and errie;
    irq_arb  <= arblost_flag and errie;
    irq_daa  <= daadone_flag and daaie;   -- stage 2 (D28)
    irq_ibi  <= ibip_flag and ibiie;      -- stage 3 (D28)

end behavioral;
