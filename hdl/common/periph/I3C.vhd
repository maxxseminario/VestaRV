library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;

-- I3C: MIPI I3C Basic controller peripheral, SDR private read/write plus legacy-I2C.
-- Contains the register file, baud generator, bit engine and framer FSM, the dynamic-address (DAA) engine with its DAT, the in-band-interrupt (IBI) monitor and the combinational pad-drive mux.
-- House style: registered read, two chained ClkGates for the baud divider, W1C clear pulses, and a transaction descriptor latched at launch.

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
        irq_daa     : out std_logic;   -- dynamic-address assignment done
        irq_ibi     : out std_logic;   -- in-band interrupt pending
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

    -- ---- register word-slot map ------------------------------------------
    constant SLOT_CR      : natural := 0;
    constant SLOT_CMD     : natural := 1;
    constant SLOT_TX      : natural := 2;
    constant SLOT_RX      : natural := 3;
    constant SLOT_SR      : natural := 4;
    constant SLOT_DAT     : natural := 5;  -- DAT window, entry selected by IDX
    constant SLOT_DATPID  : natural := 6;  -- DAT provisional-ID low word
    constant SLOT_DATINFO : natural := 7;  -- DAT PID high word, BCR, DCR
    constant SLOT_IBI     : natural := 8;  -- IBI capture

    -- Framer and bit-engine phases.
    -- Each bit phase runs a 4-sub-state SCL cycle (sub0 setup, sub1 SCL rise, sub2 sample, sub3 SCL fall); never fold drive and sample onto one edge.
    type ph_t is (P_IDLE, P_START, P_SR, P_ADDR, P_ACK, P_WLOAD, P_WDATA,
                  P_WT, P_RDATA, P_RT, P_RWAIT, P_STOP, P_DONE,
                  -- CCC/DAA sub-sequencer, entered from P_ACK when the latched CMD has CCC/DAARUN/DASA; it drives the same bit engine and pad mux.
                  P_CCCOP, P_CCCOP_T,
                  P_DAA_SR, P_DAA_HDR, P_DAA_HACK, P_DAA_ARB, P_DAA_CAPTURE,
                  P_DAA_ASSIGN, P_DAA_AACK,
                  P_DASA_SR, P_DASA_HDR, P_DASA_HACK, P_DASA_DATA, P_DASA_DT,
                  -- IBI monitor, entered from P_IDLE when the bus-start sensor sees a target-driven START while the controller is idle.
                  -- It provides SCL, clocks the open-drain arbitrated header, ACK/NACKs per CR.IBIEN, clocks one MDB byte plus T when the matching DAT entry has BCR[2]=1, captures into I3CxIBI and STOPs.
                  P_IBI_HDR, P_IBI_ACK, P_IBI_MDB, P_IBI_MDBT, P_IBI_CAP);
    signal ph : ph_t;

    -- ---- register storage ------------------------------------------------
    signal I3CxCR  : std_logic_vector(29 downto 0); -- reset 0 except SDAPP=1
    signal I3CxCMD : std_logic_vector(31 downto 0);
    signal I3CxTX  : std_logic_vector(7 downto 0);
    signal I3CxRX  : std_logic_vector(7 downto 0);  -- volatile (FSM-written)
    signal I3CxSR  : std_logic_vector(10 downto 0); -- assembled status word

    -- Registered-read pre-latch snapshots: only SR and RX carry volatile bits, CR/CMD/TX are plain software registers read straight.
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

    -- ---- baud generator (two-chained ClkGate, mode-switched reload) ------
    signal en_clk_baud_src : std_logic;
    signal clk_baud_src    : std_logic;
    signal en_clk_baud     : std_logic;
    signal clk_baud        : std_logic;
    signal baud_counter    : std_logic_vector(7 downto 0);
    signal baud_reload     : std_logic_vector(7 downto 0);
    signal pp_rate         : std_logic; -- '1' means the PP data phase reloads PPBR

    -- ---- serial core state (clk_baud domain) -----------------------------
    signal sub    : natural range 0 to 3;   -- SCL sub-phase within a bit
    signal bitno  : natural range 0 to 7;   -- bit index within a byte
    signal dbyte  : natural range 0 to 255; -- current data-byte index
    signal shift  : std_logic_vector(7 downto 0); -- MSB-first transmit reg
    signal rx_acc : std_logic_vector(7 downto 0); -- receive accumulator
    signal tx_byte : std_logic_vector(7 downto 0); -- latched write byte (parity)
    signal ack_r  : std_logic;  -- sampled address ACK (0=ACK)
    signal eod    : std_logic;  -- early end-of-data seen on a read T handshake
    signal wt_parity : std_logic; -- odd-parity T of tx_byte

    -- ---- transaction-local descriptor, latched at launch -----------------
    signal t_addr    : std_logic_vector(6 downto 0);
    signal t_rnw     : std_logic;
    signal t_stopen  : std_logic;
    signal t_busmode : std_logic;  -- 1 = legacy-I2C
    signal t_ppdata  : std_logic;  -- 1 = push-pull SDR data (I3C, SDAPP=1)
    signal t_dlen    : natural range 0 to 255;
    signal t_odbr    : std_logic_vector(7 downto 0);
    signal t_ppbr    : std_logic_vector(7 downto 0);

    -- ---- combinational pad-drive intents ---------------------------------
    signal sda_drv     : std_logic; -- value the framer wants on SDA
    signal sda_release : std_logic; -- '1' means high-Z (sample, the target drives)
    signal sda_pp      : std_logic; -- '1' means push-pull, otherwise open-drain
    signal scl_r       : std_logic; -- registered SCL level

    -- ---- async target-START / IBI sensor ---------------------------------
    -- Observes an external START (SDA fall while SCL is high) on the resolved bus; the only consumer is the IBI request below.

    -- ---- DAA engine + DAT register file (4 entries) ----------------------
    -- Slots 5/6/7 are an indexed window onto the entry selected by IDX.
    -- One process (dat_proc) on the free-running clk owns the DAT storage: firmware writes and the DAA-run captures from the clk_baud domain need a single driver per signal.
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

    -- CCC/DAA command fields, latched at launch.
    signal t_ccc, t_cccdir, t_daarun, t_dasa : std_logic;
    signal t_cccop    : std_logic_vector(7 downto 0);
    signal in_ccc_hdr : std_logic;  -- '1' means the current P_ACK is the 0x7E CCC header ACK

    -- DAA run state (clk_baud domain).
    signal daa_bit     : natural range 0 to 63;
    signal daa_acc     : std_logic_vector(63 downto 0);  -- {PID[47:0],BCR[7:0],DCR[7:0]}
    signal daa_cap_idx : natural range 0 to 3;           -- DAT entry the round writes

    -- DAT-storage handshakes from the FSM clk_baud domain into the dat_proc clk domain, edge-detected there so a multi-clk_baud-cycle level commits exactly once.
    signal dat_cap_req : std_logic;  -- commit captured PID/BCR/DCR + EVALID/DYNVALID/DAAFULL
    signal dat_dv_req  : std_logic;  -- set DYNVALID only (SETDASA)
    signal dat_dv_idx  : natural range 0 to 3;
    signal dat_cap_req_d, dat_dv_req_d : std_logic;  -- clk-domain edge detectors

    -- Combinational DAT lookups (priority-encoded from the storage).
    signal daa_free_idx    : natural range 0 to 3;  -- first EVALID=0 entry
    signal daa_has_free    : std_logic;
    signal dasa_idx        : natural range 0 to 3;   -- first STATVALID entry matching t_addr
    signal dasa_match      : std_logic;
    signal daa_assign_addr : std_logic_vector(6 downto 0);
    signal daa_addr_parity : std_logic;

    -- DAA status flags (FSM-set, W1C-cleared).
    signal daadone_flag, daafull_flag : std_logic;
    signal clr_daadone, clr_daafull   : std_logic;

    -- ---- IBI monitor -----------------------------------------------------
    signal ibien : std_logic;                       -- CR.IBIEN live tap
    -- Level request: the START sensor latches it when a target START arrives while the controller is idle, and the FSM retires it with clr_ibi_req at service entry.
    signal ibi_req     : std_logic;
    signal clr_ibi_req : std_logic;
    signal t_ibien     : std_logic;                 -- IBIEN latched at detect
    -- IBI service scratch (clk_baud domain).
    signal ibi_acc      : std_logic_vector(7 downto 0);  -- header {addr,RnW}
    signal ibi_mdb_acc  : std_logic_vector(7 downto 0);  -- MDB accumulator
    signal ibi_addr_cap : std_logic_vector(6 downto 0);  -- captured IBI address
    -- I3CxIBI capture registers (slot 8), W1C-invalidated together with SR.IBIP.
    -- Reset explicitly like RX and the status flags; q_en=0 never wipes them.
    signal ibi_addr    : std_logic_vector(6 downto 0);
    signal ibi_valid   : std_logic;
    signal ibi_mdb     : std_logic_vector(7 downto 0);
    signal ibi_hasdata : std_logic;
    signal ibi_acked   : std_logic;
    signal ibip_flag   : std_logic;                 -- SR.IBIP (rw1)
    signal clr_ibip    : std_logic;
    -- Combinational DAT lookup: match the captured IBI address against the DYNVALID entries' DYNADDR.
    -- No match is treated as BCR[2]=0 (no MDB), but the capture still happens.
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

    -- I3CxSR assembly: bits 7-10 are DAADONE, DAAFULL, IBIP and the live IBIWON.
    I3CxSR(0)  <= busy;
    I3CxSR(1)  <= tcif_flag;
    I3CxSR(2)  <= rxfull_flag;
    I3CxSR(3)  <= txeif_flag;
    I3CxSR(4)  <= anack_flag;
    I3CxSR(5)  <= eodf_flag;
    I3CxSR(6)  <= arblost_flag;
    I3CxSR(7)  <= daadone_flag;
    I3CxSR(8)  <= daafull_flag;
    I3CxSR(9)  <= ibip_flag;
    -- IBIWON (live): high across the whole IBI service window (header..capture).
    I3CxSR(10) <= '1' when (ph = P_IBI_HDR or ph = P_IBI_ACK or ph = P_IBI_MDB or
                            ph = P_IBI_MDBT or ph = P_IBI_CAP) else '0';

    -- Odd-parity T of the latched write byte: T is the inverted xor of the data bits, so the byte plus T carries an odd number of ones.
    wt_parity <= not (tx_byte(7) xor tx_byte(6) xor tx_byte(5) xor tx_byte(4) xor
                      tx_byte(3) xor tx_byte(2) xor tx_byte(1) xor tx_byte(0));

    -- ---- combinational DAT lookups ---------------------------------------
    -- The first entry with EVALID=0 is the round's capture target.
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
    -- The ENTDAA assigned address is the free entry's pre-programmed DYNADDR driven push-pull as 7 address bits followed by odd parity.
    daa_assign_addr <= dat_dynaddr(daa_free_idx);
    daa_addr_parity <= not (daa_assign_addr(6) xor daa_assign_addr(5) xor
                            daa_assign_addr(4) xor daa_assign_addr(3) xor
                            daa_assign_addr(2) xor daa_assign_addr(1) xor
                            daa_assign_addr(0));

    -- IBI DAT lookup: does any DYNVALID entry own the captured IBI address?
    -- No match is treated as BCR[2]=0, i.e. no MDB, but the capture still happens.
    ibi_dat_match <= '1' when ((dat_dynvalid(0) = '1' and dat_dynaddr(0) = ibi_addr_cap) or
                               (dat_dynvalid(1) = '1' and dat_dynaddr(1) = ibi_addr_cap) or
                               (dat_dynvalid(2) = '1' and dat_dynaddr(2) = ibi_addr_cap) or
                               (dat_dynvalid(3) = '1' and dat_dynaddr(3) = ibi_addr_cap)) else '0';
    ibi_dat_idx <= 0 when (dat_dynvalid(0) = '1' and dat_dynaddr(0) = ibi_addr_cap) else
                   1 when (dat_dynvalid(1) = '1' and dat_dynaddr(1) = ibi_addr_cap) else
                   2 when (dat_dynvalid(2) = '1' and dat_dynaddr(2) = ibi_addr_cap) else 3;
    -- BCR[2]=1 means the IBI carries a mandatory data byte (MDB).
    ibi_bcr2 <= ibi_dat_match and dat_bcr(ibi_dat_idx)(2);

    ---------------------- End Signal Routing -------------------------------

    -- Registered-read pre-latch: the volatile registers are snapshotted (inverted) at deselect.
    reg_sync: process(EnMemPeriph, I3CxRX, I3CxSR)
    begin
        if falling_edge(EnMemPeriph) then
            I3CxRX_ltch <= not I3CxRX;
            I3CxSR_ltch <= not I3CxSR;
        end if;
    end process;

    -------------------------- Memory Logic ---------------------------------
    i3c_slot <= slv2uint(MABPart) when EnMemPeriph = '0' else 0;

    -- Register write: a CMD lane-0 write is the sole launch trigger, and the content is always captured while the launch pulse is suppressed when I3CEN=0 or BUSY=1.
    -- clr_launch, clr_tx_arm and the clr_* flag pulses retire asynchronously (level-sensitive) so the gated ClkMem never has to consume an FSM pulse.
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
                                i3c_launch <= '1'; -- launch guard
                            end if;
                        end if;
                        if WEn(1) = '0' then I3CxCMD(15 downto 8)  <= wdata(15 downto 8);  end if;
                        if WEn(2) = '0' then I3CxCMD(23 downto 16) <= wdata(23 downto 16); end if;
                        if WEn(3) = '0' then I3CxCMD(31 downto 24) <= wdata(31 downto 24); end if;
                    when SLOT_TX =>
                        if WEn(0) = '0' then
                            I3CxTX <= wdata(7 downto 0);
                            tx_arm <= '1'; -- arm the byte-pending handshake
                        end if;
                    when SLOT_SR =>
                        if WEn(0) = '0' then -- W1C: writing a 1 clears, and BUSY(0) is read-only
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
                        null; -- RX is read-only, and the DAT and IBI slots are written elsewhere
                end case;
            end if;
        end if;

        -- Async clear-pulse retirement.
        if resetn = '0' or clr_launch = '1' then
            i3c_launch <= '0';
        end if;
        -- Do not gate tx_arm on q_en: a TX byte armed before I3CEN is raised must survive to be consumed by P_WLOAD, so only reset or the FSM consume-pulse retires it.
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

    -- Synchronous register read: the volatile SR and RX come from the pre-latch (un-inverted), reserved slots read 0.
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case i3c_slot is
                when SLOT_CR      => rdata_out <= (31 downto 30 => '0') & I3CxCR;
                when SLOT_CMD     => rdata_out <= I3CxCMD;
                when SLOT_TX      => rdata_out <= (31 downto 8 => '0') & I3CxTX;
                when SLOT_RX      => rdata_out <= (31 downto 8 => '0') & (not I3CxRX_ltch);
                when SLOT_SR      => rdata_out <= (31 downto 11 => '0') & (not I3CxSR_ltch);
                -- DAT window, entry selected by the persisted IDX.
                -- Only 4 entries exist, so indices 4-7 read back the IDX field alone.
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
                -- IBI capture: [17]IBIACKED [16]IBIHASDATA [15:8]IBIMDB [7]IBIVALID [6:0]IBIADDR.
                -- Read straight from the capture registers, which are written only while BUSY and read only while idle.
                when SLOT_IBI     =>
                    rdata_out <= (31 downto 18 => '0') &
                        ibi_acked & ibi_hasdata & ibi_mdb & ibi_valid & ibi_addr;
                when others       => rdata_out <= (others => '0');
            end case;
        end if;
    end process;

    ---------- DAT register file storage (free-running clk domain) ----------
    -- Single driver for all DAT entries: firmware writes to slots 5/6/7 land on rising_edge(clk) under EnMemPeriph='0' (ClkMem=clk while selected), DAA-run commits arrive as edge-detected handshakes from the clk_baud FSM.
    -- Disable (q_en=0) does not wipe the table: entries persist across frames and across disable.
    dat_proc: process(clk, resetn)
        variable idx_sel : natural range 0 to 7;
    begin
        if resetn = '0' then
            dat_evalid    <= (others => '0');
            dat_dynvalid  <= (others => '0');
            dat_statvalid <= (others => '0');
            dat_idx       <= 0;
        elsif rising_edge(clk) then
            -- Firmware register writes (the gated-select equivalent of reg_write).
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

    ---------- baud generator (two chained ClkGates) ------------------------
    -- Reload is muxed by the latched phase drive-mode pp_rate: open-drain phases reload ODBR, push-pull data phases reload PPBR, and pp_rate flips only on phase boundaries so it cannot glitch mid-bit.
    -- baud_counter is held cleared while idle so the first clk_baud edge after a launch, or after an ibi_req wake, is prompt and BUSY rises within a couple of clk cycles.
    en_clk_baud_src <= q_en and (busy or i3c_launch or ibi_req);

    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn  => not clk,
            En     => en_clk_baud_src,
            ClkOut => clk_baud_src
        );

    baud_reload <= t_ppbr when pp_rate = '1' else t_odbr;

    -- Bit-rate down-counter: it reloads at terminal count, so one clk_baud edge is produced every baud_reload+1 source edges.
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

    -- Terminal count enables the second gate stage, producing the one serial-core clock edge for this bit sub-phase.
    en_clk_baud <= '1' when baud_counter = "00000000" and en_clk_baud_src = '1' else '0';

    cg_clk_baud: entity work.ClkGate
        port map (
            ClkIn  => not clk,
            En     => en_clk_baud,
            ClkOut => clk_baud
        );

    ---------- bit engine + framer FSM (clk_baud domain) --------------------
    -- One bit occupies a full 4-sub-state SCL cycle; sample slots (address ACK, read data, non-final read T, legacy write ACK) release SDA and read SDA_IN at sub2.
    -- Drive policy: address header and START/Sr/STOP SDA are open-drain (drive a 0, release a 1 to the wired-AND 'H'), SDR write data and the write-T are push-pull, and legacy-I2C mode is open-drain in every phase.
    -- An I3C frame carries exactly ONE address-header ACK and no per-byte ACK: a write drives an odd-parity T, a read samples the T handshake and drives it low on the final byte.
    fsm_proc: process(resetn, clk_baud, q_en, i3c_launch,
                      clr_tcif, clr_rxfull, clr_txeif, clr_anack, clr_eodf, clr_arblost,
                      clr_daadone, clr_daafull, clr_ibip)
    begin
        if resetn = '0' or q_en = '0' then
            -- I3CEN=0 holds the serial core in reset but does NOT wipe RX or the status flags, which clear only on resetn=0 or an explicit W1C.
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
                -- IDLE: bus released, waiting for a CMD launch or a target-driven IBI.
                when P_IDLE =>
                    scl_r <= '1'; sda_release <= '1'; sda_pp <= '0'; sub <= 0;
                    pp_rate <= '0';
                    if i3c_launch = '1' then
                        clr_launch <= '1';
                        eod <= '0';
                        -- Latch the transaction descriptor (frozen at launch).
                        t_addr    <= I3CxCMD(6 downto 0);
                        t_rnw     <= I3CxCMD(7);
                        t_stopen  <= I3CxCMD(9);
                        t_dlen    <= slv2uint(I3CxCMD(23 downto 16));
                        t_busmode <= I3CxCR(1);
                        t_ppdata  <= I3CxCR(2) and (not I3CxCR(1));
                        t_odbr    <= I3CxCR(15 downto 8);
                        t_ppbr    <= I3CxCR(23 downto 16);
                        -- CCC/DAA descriptor fields.
                        t_ccc     <= I3CxCMD(10);
                        t_cccdir  <= I3CxCMD(11);
                        t_daarun  <= I3CxCMD(12);
                        t_dasa    <= I3CxCMD(13);
                        t_cccop   <= I3CxCMD(31 downto 24);
                        bitno     <= 0;
                        -- CCC/ENTDAA/SETDASA prepend the 0x7E broadcast plus W header; private transfers do not.
                        -- in_ccc_hdr routes that header ACK into the CCC/DAA sub-sequencer.
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
                        -- Bus-available IBI: a target drove a START while we were idle, so take over SCL and clock the open-drain arbitrated header.
                        -- There is no CMD launch here, so latch the context directly: I3C-SDR with push-pull SCL, header at the ODBR baud.
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
                        -- Open-drain: drive SDA low (release=0, pp=0, drv=0) while SCL is high.
                        scl_r <= '1'; sda_pp <= '0'; sda_release <= '0'; sda_drv <= '0';
                        sub <= 1;
                    else
                        scl_r <= '0'; sub <= 0; ph <= P_ADDR;
                    end if;

                -- Repeated START: release SDA high, take SCL high, then let SDA fall (open-drain).
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
                -- Address header (7 address bits then RnW), open-drain: release on a 1, drive a 0.
                -- The sub2 compare (drove a 1 but read a 0) is the arbitration-lost detect; with no competing controller it never fires.
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

                -- Single address ACK, the only ACK in an I3C frame.
                when P_ACK =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; ack_r <= SDA_IN; sub <= 3;
                        when others =>
                            scl_r <= '0'; sub <= 0;
                            if ack_r = '0' then          -- ACKed
                                if in_ccc_hdr = '1' then
                                    -- 0x7E CCC header ACK: send the CCC opcode byte next, with the DAA phases at the ODBR baud.
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
                -- Write-byte load: hold SCL low until a TX byte is armed, then consume it, set TXEIF (the register is now empty) and retire tx_arm.
                when P_WLOAD =>
                    scl_r <= '0'; sda_release <= '1'; sda_pp <= '0';
                    if tx_arm = '1' then
                        shift <= I3CxTX; tx_byte <= I3CxTX;
                        clr_tx_arm <= '1'; txeif_flag <= '1';
                        bitno <= 0; sub <= 0; ph <= P_WDATA;
                    end if;

                -- Write data, 8 bits with no per-byte ACK.
                -- Push-pull in I3C-SDR, open-drain in legacy-I2C.
                when P_WDATA =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= not t_busmode; sda_release <= '0';
                                  sda_drv <= shift(7); sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;   -- no sample on a push-pull write
                        when others =>
                                  scl_r <= '0'; shift <= shift(6 downto 0) & '0';
                                  if bitno = 7 then bitno <= 0; ph <= P_WT;
                                  else bitno <= bitno + 1; end if;
                                  sub <= 0;
                    end case;

                -- Write T slot: I3C drives the odd-parity T push-pull with no sample, legacy-I2C releases and samples a real per-byte ACK.
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
                -- Read data, 8 bits: the controller releases, the target drives push-pull, sampled MSB-first at sub2.
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

                -- Read T handshake: a non-final byte releases and samples, and a target T=0 there means an EODF short read.
                -- The final wanted byte drives T low to terminate, then Sr or STOP follows.
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

                -- Read drain wait: hold SCL low until software drains RX (RXFULL cleared) before the next byte overwrites it.
                when P_RWAIT =>
                    scl_r <= '0'; sda_release <= '1'; sda_pp <= '0';
                    if rxfull_flag = '0' then
                        bitno <= 0; sub <= 0; ph <= P_RDATA;
                    end if;

                ------------------------------------------------------------
                -- STOP: SDA driven low open-drain, SCL high, then SDA released so it rises to the wired-AND 'H', which is the STOP edge.
                -- It relies on the target having released SDA after its final read T.
                when P_STOP =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_pp <= '0'; sda_release <= '0';
                                  sda_drv <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sda_release <= '1'; sub <= 3;
                        when others => scl_r <= '1'; sub <= 0; ph <= P_DONE;
                    end case;

                -- DONE: one-edge settle tail, release the bus, drop BUSY.
                -- Backstop clear of the DAT handshakes (ENTDAA also clears them once per round).
                when P_DONE =>
                    scl_r <= '1'; sda_release <= '1'; sda_pp <= '0'; sub <= 0;
                    dat_cap_req <= '0'; dat_dv_req <= '0';
                    ph <= P_IDLE;

                ------------------------------------------------------------
                -- CCC/DAA sub-sequencer: drives the same bit engine and pad mux as the framer.
                ------------------------------------------------------------
                -- CCC opcode byte: 8 bits push-pull SDR, the same shape as P_WDATA.
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

                -- CCC opcode parity T (odd parity, push-pull), then branch to the ENTDAA rounds, the SETDASA send or the plain-CCC payload.
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
                                    ph <= P_SR;                 -- then P_ADDR, then P_ACK (data)
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
                -- ENTDAA rounds (CMD.DAARUN).
                -- Each round runs Sr, the 0x7E+R header, the ACK (a NACK means no more devices, so DAADONE), a 64-bit open-drain arbitration capture, the assignment of a 7-bit dynamic address plus parity (push-pull), and a final ACK.
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

                -- 0x7E+R header, open-drain, the same shape as P_ADDR.
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

                -- Round ACK (open-drain): a NACK means every device is assigned, so DAADONE then STOP.
                -- An ACK with no free DAT entry also gives DAADONE then STOP (table exhausted).
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

                -- 64-bit open-drain arbitration capture (wired-AND, so the lowest PID wins on the resolved bus); the controller releases and samples.
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

                -- Commit the winner's PID/BCR/DCR into the free DAT entry (via dat_proc), set DAAFULL, and prime the assign shift register.
                when P_DAA_CAPTURE =>
                    daa_cap_idx  <= daa_free_idx;
                    dat_cap_req  <= '1';
                    daafull_flag <= '1';
                    shift <= daa_assign_addr & daa_addr_parity;  -- 7-bit addr + odd parity
                    bitno <= 0; sub <= 0;
                    ph <= P_DAA_ASSIGN;

                -- Drive the assigned dynamic address plus parity, push-pull.
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

                -- Assign ACK (open-drain): an ACK starts the next round, a NACK sets DAADONE then STOPs.
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
                -- SETDASA (CMD.DASA): direct CCC 0x87.
                -- After the opcode it runs Sr, the static address plus W, the ACK, then one data byte (dyn addr << 1) from the matching DAT entry, which is marked DYNVALID on that ACK.
                ------------------------------------------------------------
                -- Repeated START ahead of the static address.
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

                -- Static-address ACK: on an ACK mark the entry DYNVALID and send the dynamic-address byte.
                -- A NACK sets ANACK and DAADONE, then STOPs.
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

                -- Data byte (dyn addr << 1), push-pull SDR data phase.
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

                -- Data-byte parity T (odd parity, push-pull), then STOP.
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
                -- IBI monitor, bus-available path only.
                -- The target has already driven the START, so the controller provides SCL, releases and samples the 7 address bits plus RnW, then ACKs or NACKs per IBIEN.
                ------------------------------------------------------------
                -- IBI header: 8 bits (addr[6:0] then RnW), sampled open-drain.
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

                -- IBI ACK/NACK (open-drain): IBIEN=1 drives low to ACK and then reads the MDB only if the matching DAT entry has BCR[2]=1.
                -- IBIEN=0 releases (NACK) for a clean STOP with no capture and no flag.
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

                -- MDB byte: the controller releases and samples 8 bits while the target drives.
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

                -- MDB T handshake: release and sample one bit, captured but not checked.
                when P_IBI_MDBT =>
                    case sub is
                        when 0 => scl_r <= '0'; sda_release <= '1'; sda_pp <= '0'; sub <= 1;
                        when 1 => scl_r <= '1'; sub <= 2;
                        when 2 => scl_r <= '1'; sub <= 3;
                        when others => scl_r <= '0'; sub <= 0; ph <= P_IBI_CAP;
                    end case;

                -- Capture {addr, MDB, hasdata, acked} into I3CxIBI, set IBIP, then STOP.
                -- hasdata reflects BCR[2] and is 0 when there is no DAT match.
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

        -- RX has no write-side reset elsewhere and the FSM only assigns it, so reset it here or its readback is 'X' until the first received byte.
        if resetn = '0' then
            I3CxRX <= (others => '0');
        end if;

        -- Status-flag W1C application and reset (async level-sensitive, with clr_* in the sensitivity list).
        -- Disable (q_en=0) does NOT clear the flags: only resetn=0 or the explicit W1C pulse does.
        if resetn = '0' or clr_tcif = '1'    then tcif_flag    <= '0'; end if;
        if resetn = '0' or clr_rxfull = '1'  then rxfull_flag  <= '0'; end if;
        if resetn = '0' or clr_txeif = '1'   then txeif_flag   <= '0'; end if;
        if resetn = '0' or clr_anack = '1'   then anack_flag   <= '0'; end if;
        if resetn = '0' or clr_eodf = '1'    then eodf_flag    <= '0'; end if;
        if resetn = '0' or clr_arblost = '1' then arblost_flag <= '0'; end if;
        if resetn = '0' or clr_daadone = '1' then daadone_flag <= '0'; end if;
        if resetn = '0' or clr_daafull = '1' then daafull_flag <= '0'; end if;

        -- An IBIP W1C also invalidates the I3CxIBI capture fields, and reset clears both.
        -- Not gated by q_en: disable never wipes the flags or the IBI capture.
        if resetn = '0' or clr_ibip = '1' then
            ibip_flag   <= '0';
            ibi_valid   <= '0';
            ibi_hasdata <= '0';
            ibi_acked   <= '0';
            ibi_addr    <= (others => '0');
            ibi_mdb     <= (others => '0');
        end if;
    end process;

    ---------- async target-START / IBI sensor ------------------------------
    -- START is SDA falling while SCL is high; one seen while the controller is idle and enabled is a target-driven IBI, so ibi_req wakes the framer and clr_ibi_req retires it at service entry (controller STARTs run with busy=1 and never latch it).
    -- Keep the single-edge shape (async reset/retire plus one falling_edge(SDA_IN) set clause): synthesis rejects a process referencing two clock edges, and SDA_IN is this flop's clock pin, so it needs its own async SDC group.
    ibi_sensor: process(resetn, SDA_IN, clr_ibi_req)
    begin
        if resetn = '0' or clr_ibi_req = '1' then
            ibi_req <= '0';
        elsif falling_edge(SDA_IN) then
            if SCL_IN = '1' and busy = '0' and q_en = '1' then
                ibi_req <= '1';
            end if;
        end if;
    end process;

    ---------- combinational pad-drive mux ----------------------------------
    -- SDA: release means high-Z (sampling, the target drives), push-pull means a strong drive, otherwise open-drain (drive only a 0, release a 1 to the wired-AND 'H').
    SDA_OUT <= sda_drv;
    SDA_DIR <= '0'         when sda_release = '1'
          else '1'         when sda_pp = '1'
          else not sda_drv;
    -- SCL: I3C-SDR mode is push-pull with no stretch, legacy-I2C mode is open-drain so a target may stretch by holding SCL_IN low.
    -- t_busmode is 'U' before the first launch, so the comparison is false and the default is I3C-SDR push-pull.
    SCL_OUT <= '0'         when t_busmode = '1' else scl_r;
    SCL_DIR <= (not scl_r) when t_busmode = '1' else '1';

    ---------- IRQ lines: combinational status AND enable -------------------
    irq_tc   <= tcif_flag    and tcie;
    irq_rxf  <= rxfull_flag  and rxfie;
    irq_txe  <= txeif_flag   and txeie;
    irq_nack <= anack_flag   and errie;
    irq_eod  <= eodf_flag    and errie;
    irq_arb  <= arblost_flag and errie;
    irq_daa  <= daadone_flag and daaie;
    irq_ibi  <= ibip_flag and ibiie;

end behavioral;
