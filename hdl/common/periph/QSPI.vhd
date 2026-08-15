library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;

-- QSPI: quad-SPI controller peripheral (digital-peripherals program, MVP).
-- Register map, entity and FSM shape are FROZEN by the spec: a bench is being written against this entity in parallel.
-- The idioms below (registered read path, two-chained-ClkGate baud divider, write clear-pulse retirement) are reused verbatim from SPI.vhd.
-- See the inline notes for exactly what mirrors SPI and what is a deliberate QSPI-specific deviation.

entity QSPI is
    port (
        clk         : in  std_logic;   -- smclk-domain serial core clock
        resetn      : in  std_logic;
        irq_tc      : out std_logic;
        irq_rxf     : out std_logic;
        ClkMem      : in  std_logic;
        EnMemPeriph : in  std_logic;
        WEn         : in  std_logic_vector(3 downto 0);
        MABPart     : in  std_logic_vector(7 downto 2);
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0);
        sck_out     : out std_logic;
        sck_dir     : out std_logic;
        cs_out      : out std_logic;   -- active-low chip select (CS0 only in MVP)
        cs_dir      : out std_logic;
        io_in       : in  std_logic_vector(3 downto 0);
        io_out      : out std_logic_vector(3 downto 0);
        io_dir      : out std_logic_vector(3 downto 0)
    );
end QSPI;

architecture behavioral of QSPI is

    -- Transfer FSM, frozen shape: IDLE, CMD, ADDR, DUMMY, DATA, DONE, back to IDLE, with zero-length phases skipped by construction.
    -- DONE is a 1 clk_baud-edge tail state that gives TCIF/RXFULL/QSPIxRX a clean, simultaneous settle edge before BUSY drops (BUSY = state /= IDLE, so DONE still reads busy).
    type QState_t is (ST_IDLE, ST_CMD, ST_ADDR, ST_DUMMY, ST_DATA, ST_DONE);
    signal state : QState_t;

    -- Local register-slot numbering: word slots inside this peripheral's 256B window.
    -- QSPI is not wired into MemoryMap.vhd yet, so these are private constants; MABPart(7:2) is decoded against them the same way SPI.vhd decodes addr_periph against its RegSlotSPIx* constants.
    constant SLOT_CR  : natural := 0;
    constant SLOT_CMD : natural := 1;
    constant SLOT_ADR : natural := 2;
    constant SLOT_TX  : natural := 3;
    constant SLOT_RX  : natural := 4;
    constant SLOT_SR  : natural := 5;

    -- Lane-width encoding: 00 = 1-bit, 01 = 2-bit, 10 = 4-bit, 11 reserved and treated as 1-bit.
    function width_bits(w : std_logic_vector(1 downto 0)) return natural is
    begin
        case w is
            when "01"   => return 2;
            when "10"   => return 4;
            when others => return 1; -- "00" and reserved "11"
        end case;
    end function;

    -- DLEN encoding: 00 = no data phase, 01 = 8-bit, 10 = 16-bit, 11 = 32-bit.
    function dlen_bits_f(d : std_logic_vector(1 downto 0)) return natural is
    begin
        case d is
            when "01"   => return 8;
            when "10"   => return 16;
            when "11"   => return 32;
            when others => return 0; -- "00" no data phase
        end case;
    end function;

    -- Determines the next active phase after leaving `from_st`, skipping any zero-length phase by construction.
    -- Pure function over the LATCHED transaction-local fields, never the live CR, so mid-transaction CR/CMD writes cannot redirect an in-flight transaction.
    function next_phase(awid       : std_logic_vector(1 downto 0);
                         dummy_val : natural;
                         dlen      : std_logic_vector(1 downto 0);
                         from_st   : QState_t) return QState_t is
    begin
        if from_st = ST_CMD then
            if awid = "01" or awid = "10" then
                return ST_ADDR;
            end if;
        end if;
        if from_st = ST_CMD or from_st = ST_ADDR then
            if dummy_val > 0 then
                return ST_DUMMY;
            end if;
        end if;
        if dlen /= "00" then
            return ST_DATA;
        end if;
        return ST_DONE;
    end function;

    -- Register signals.
    signal QSPIxCR  : std_logic_vector(28 downto 0); -- control register (bits 31:29 unused)
    signal QSPIxCMD : std_logic_vector(10 downto 0); -- [7:0] CMD, [9:8] DLEN, [10] DIR
    signal QSPIxADR : std_logic_vector(31 downto 0);
    signal QSPIxTX  : std_logic_vector(31 downto 0);
    signal QSPIxRX  : std_logic_vector(31 downto 0);
    signal QSPIxSR  : std_logic_vector(3 downto 0);  -- [0]BUSY [1]TXEIF [2]RXFULL [3]TCIF

    -- Registered-read pre-latch snapshots, the SPI.vhd:694-700 idiom reused verbatim.
    -- falling_edge(EnMemPeriph) latches the INVERTED value of any register with hardware-driven or volatile bits, and the read process un-inverts it on the next rising_edge(ClkMem).
    -- Only SR and RX carry volatile bits (BUSY/flags, and RX's serial-core-written data); CR/CMD/ADR/TX are plain software registers, read straight out of the write-side register in the read process, exactly like SPI.vhd's SPIxTX/SPIxCR.
    signal QSPIxSR_ltch : std_logic_vector(3 downto 0);
    signal QSPIxRX_ltch : std_logic_vector(31 downto 0);

    -- QSPIxCR bit-field taps, live and combinational.
    signal q_en    : std_logic;
    signal q_cmdw  : std_logic_vector(1 downto 0);
    signal q_adrw  : std_logic_vector(1 downto 0);
    signal q_datw  : std_logic_vector(1 downto 0);
    signal q_cpol  : std_logic;
    signal q_cpha  : std_logic;
    signal q_awid  : std_logic_vector(1 downto 0);
    signal q_dummy : std_logic_vector(4 downto 0);
    -- q_cssel (CR[18:16]) is reserved and ignored in the MVP: only CS0 exists and the firmware contract is "write 0".
    -- It is captured in QSPIxCR for readback but never consumed.
    signal q_br    : std_logic_vector(7 downto 0);
    signal q_tcie  : std_logic;
    signal q_rxfie : std_logic;

    -- Memory-map decode.
    signal qspi_slot : natural range 0 to 63;

    -- Write-side clear-pulse and launch-trigger signals, the SPI.vhd:784-787 clr_* idiom.
    -- Each is asserted for one ClkMem edge on a qualifying write and retired on `resetn='0' or EnMemPeriph='1'`, so a one-cycle pulse never straddles two selections.
    -- qspi_launch instead retires on clr_qspi_launch, set by the clk_baud-domain FSM once it accepts the launch, mirroring SPI.vhd's start_tx / clr_start_tx split exactly (SPI.vhd:781-783).
    signal clr_txeif    : std_logic;
    signal clr_rxfull   : std_logic;
    signal clr_tcif     : std_logic;
    signal qspi_launch  : std_logic;
    signal clr_qspi_launch : std_logic;

    -- Status flip-flops: set by the serial-core FSM, W1C-cleared via clr_*.
    signal txeif_flag  : std_logic;
    signal rxfull_flag : std_logic;
    signal tcif_flag   : std_logic;
    signal busy        : std_logic;

    -- Baud-rate divider: the SPI.vhd:224-274 two-chained-ClkGate scheme, reused verbatim including the `not clk` edge-family choice.
    -- See SPI.vhd's VERDICT comment at line 230 for why; baud = SMCLK/(2*(1+BR)).
    signal en_clk_baud_src : std_logic;
    signal clk_baud_src    : std_logic;
    signal en_clk_baud     : std_logic;
    signal clk_baud        : std_logic;
    signal baud_counter    : std_logic_vector(7 downto 0);

    -- Serial core, clk_baud domain.
    signal sck      : std_logic;
    -- edge_cnt counts clk_baud EDGES, two per bit-group, which is one full SCK cycle.
    -- A 32-bit single-width phase is therefore 64 edges; it was 32 when the FSM folded drive and sample onto one edge, the known timing bug.
    signal edge_cnt : natural range 0 to 64;
    signal t_sreg   : std_logic_vector(31 downto 0); -- CMD/ADDR/DATA-write shift-out reg
    signal rx_sreg  : std_logic_vector(31 downto 0); -- DATA-read shift-in accumulator

    -- Transaction-local latched fields, frozen list: widths, AWID, DUMMY, DIR, DLEN, cmd byte, address.
    -- They are latched at launch so mid-transaction CR/CMD/ADR writes cannot corrupt an in-flight transfer.
    -- QSPIxTX is deliberately NOT in this list; see the DATA-phase fold-in note below.
    signal t_cmdw      : std_logic_vector(1 downto 0);
    signal t_adrw      : std_logic_vector(1 downto 0);
    signal t_datw      : std_logic_vector(1 downto 0);
    signal t_awid      : std_logic_vector(1 downto 0);
    signal t_dummy_val : natural range 0 to 31;
    signal t_dlen      : std_logic_vector(1 downto 0);
    signal t_dir       : std_logic;
    signal t_cmd       : std_logic_vector(7 downto 0);
    signal t_addr      : std_logic_vector(31 downto 0);

begin

    --------------------- Signal routing ---------------------
    q_en    <= QSPIxCR(0);
    q_cmdw  <= QSPIxCR(2 downto 1);
    q_adrw  <= QSPIxCR(4 downto 3);
    q_datw  <= QSPIxCR(6 downto 5);
    q_cpol  <= QSPIxCR(7);
    q_cpha  <= QSPIxCR(8);
    q_awid  <= QSPIxCR(10 downto 9);
    q_dummy <= QSPIxCR(15 downto 11);
    -- QSPIxCR(18 downto 16) = CSSEL, reserved and ignored in the MVP (CS0 only).
    q_br    <= QSPIxCR(26 downto 19);
    q_tcie  <= QSPIxCR(27);
    q_rxfie <= QSPIxCR(28);

    QSPIxSR(0) <= busy;
    QSPIxSR(1) <= txeif_flag;
    QSPIxSR(2) <= rxfull_flag;
    QSPIxSR(3) <= tcif_flag;

    busy <= '0' when state = ST_IDLE else '1';

    sck_out <= sck;
    sck_dir <= '1'; -- constant, per frozen entity note
    cs_dir  <= '1'; -- constant, per frozen entity note
    cs_out  <= '0' when state /= ST_IDLE else '1'; -- low only while a transaction is active

    -- Each irq_* is status AND enable, combinational and never latched (the I2C.vhd:241-253 form).
    irq_tc  <= tcif_flag  and q_tcie;
    irq_rxf <= rxfull_flag and q_rxfie;

    -- Baud clock generation: gate on qspi_en and either busy or the launch pulse.
    -- The launch must spin the baud clock up BEFORE `busy` itself transitions, exactly mirroring SPI.vhd:224-226's `spi_en and (tx_in_progress or start_tx or StartTXFlash)`.
    en_clk_baud_src <= q_en and (busy or qspi_launch);

    ---------------------End signal routing ---------------------

    -- Two-chained-ClkGate baud divider, reused verbatim from SPI.vhd:244-274 including the `not clk` edge-family choice.
    -- See SPI.vhd's VERDICT comment there; the choice is frozen and not re-litigated here.
    cg_clk_baud_src: entity work.ClkGate
        port map (
            ClkIn   => not clk,
            En      => en_clk_baud_src,
            ClkOut  => clk_baud_src
        );

    -- Baud reload counter: free-runs from q_br down to zero while the gated source clock ticks.
    baud_cntr_proc: process(clk_baud_src, resetn, q_en)
    begin
        if resetn = '0' or q_en = '0' then
            baud_counter <= (others => '0');
        elsif rising_edge(clk_baud_src) then
            if baud_counter = "00000000" then
                baud_counter <= q_br;
            else
                baud_counter <= baud_counter - 1;
            end if;
        end if;
    end process;

    en_clk_baud <= '1' when baud_counter = "00000000" and en_clk_baud_src = '1' else '0';
    cg_clk_baud: entity work.ClkGate
        port map (
            ClkIn   => not clk,
            En      => en_clk_baud,
            ClkOut  => clk_baud
        );

    -- Registered-read pre-latch, the SPI.vhd:693-700 idiom reused verbatim.
    reg_sync: process(EnMemPeriph, QSPIxRX, QSPIxSR)
    begin
        if falling_edge(EnMemPeriph) then
            QSPIxRX_ltch <= not QSPIxRX;
            QSPIxSR_ltch <= not QSPIxSR;
        end if;
    end process;

    --------------------------  Memory logic ---------------------------
    qspi_slot <= slv2uint(MABPart) when EnMemPeriph = '0' else 0;

    -- Register write process, following the SPI.vhd:706-788 structure.
    reg_write: process(resetn, ClkMem, EnMemPeriph, clr_qspi_launch)
    begin
        if resetn = '0' then
            QSPIxCR  <= (others => '0');
            QSPIxCMD <= (others => '0');
            QSPIxADR <= (others => '0');
            QSPIxTX  <= (others => '0');
        elsif rising_edge(ClkMem) then
            if EnMemPeriph = '0' then
                case qspi_slot is
                    when SLOT_SR =>
                        if WEn(0) = '0' then
                            -- W1C: writing a 1 to a bit clears it.
                            -- BUSY (bit 0) is read-only and hardware-driven, so writes to it are ignored.
                            if wdata(1) = '1' then
                                clr_txeif <= '1';
                            end if;
                            if wdata(2) = '1' then
                                clr_rxfull <= '1';
                            end if;
                            if wdata(3) = '1' then
                                clr_tcif <= '1';
                            end if;
                        end if;
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            QSPIxCR(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            QSPIxCR(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(2) = '0' then
                            QSPIxCR(23 downto 16) <= wdata(23 downto 16);
                        end if;
                        if WEn(3) = '0' then
                            QSPIxCR(28 downto 24) <= wdata(28 downto 24);
                        end if;
                    when SLOT_CMD =>
                        -- The SOLE trigger: a write with WEn(0)='0' launches the transaction.
                        -- Register content is always captured, but the launch pulse itself is suppressed (a no-op, no corruption) when QSPIEN=0 or BUSY=1.
                        -- TX/ADR/CR writes never trigger a launch.
                        if WEn(0) = '0' then
                            QSPIxCMD(7 downto 0) <= wdata(7 downto 0);
                            if q_en = '1' and busy = '0' then
                                qspi_launch <= '1';
                            end if;
                        end if;
                        if WEn(1) = '0' then
                            QSPIxCMD(10 downto 8) <= wdata(10 downto 8);
                        end if;
                    when SLOT_ADR =>
                        if WEn(0) = '0' then
                            QSPIxADR(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            QSPIxADR(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(2) = '0' then
                            QSPIxADR(23 downto 16) <= wdata(23 downto 16);
                        end if;
                        if WEn(3) = '0' then
                            QSPIxADR(31 downto 24) <= wdata(31 downto 24);
                        end if;
                    when SLOT_TX =>
                        if WEn(0) = '0' then
                            QSPIxTX(7 downto 0) <= wdata(7 downto 0);
                        end if;
                        if WEn(1) = '0' then
                            QSPIxTX(15 downto 8) <= wdata(15 downto 8);
                        end if;
                        if WEn(2) = '0' then
                            QSPIxTX(23 downto 16) <= wdata(23 downto 16);
                        end if;
                        if WEn(3) = '0' then
                            QSPIxTX(31 downto 24) <= wdata(31 downto 24);
                        end if;
                    when SLOT_RX =>
                        null; -- RX is read-only: writes are ignored and have no side effect
                    when others =>
                        null;
                end case;
            end if;
        end if;

        -- Clear-pulse retirement, the SPI.vhd:780-787 idiom reused verbatim.
        if resetn = '0' or clr_qspi_launch = '1' then
            qspi_launch <= '0';
        end if;
        if resetn = '0' or EnMemPeriph = '1' then
            clr_txeif  <= '0';
            clr_rxfull <= '0';
            clr_tcif   <= '0';
        end if;
    end process;

    -- Register read process, synchronous, following the SPI.vhd:791-817 structure.
    process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case qspi_slot is
                when SLOT_SR =>
                    rdata_out <= (31 downto QSPIxSR_ltch'high + 1 => '0') & (not QSPIxSR_ltch);
                when SLOT_RX =>
                    rdata_out <= not QSPIxRX_ltch;
                when SLOT_CR =>
                    rdata_out <= (31 downto QSPIxCR'high + 1 => '0') & QSPIxCR;
                when SLOT_CMD =>
                    rdata_out <= (31 downto QSPIxCMD'high + 1 => '0') & QSPIxCMD;
                when SLOT_ADR =>
                    rdata_out <= QSPIxADR;
                when SLOT_TX =>
                    rdata_out <= QSPIxTX;
                when others =>
                    rdata_out <= (others => '0');
            end case;
        end if;
    end process;

    ---------- QSPI serial core, clk_baud domain ----------
    -- CDC note: qspi_launch is set combinationally by the ClkMem-domain write process above and read DIRECTLY here in the clk_baud domain, with no explicit 2-FF synchronizer.
    -- This is SPI.vhd's own start_tx/clr_start_tx CDC approach (SPI.vhd:353-366, 706 notes), copied exactly and frozen.
    -- Safety rests on the same properties SPI.vhd relies on: qspi_launch is a registered, held level, not a single-cycle glitch, and it only retires once clr_qspi_launch acks it.
    -- A metastable sample therefore delays launch detection by at most one clk_baud edge instead of corrupting state.
    fsm_proc: process(resetn, clk_baud, q_en, qspi_launch, clr_txeif, clr_rxfull, clr_tcif, q_cpol)
        variable w : natural;

        -- Shared "leaving a phase" transition: decides the next phase from the LATCHED fields and performs that phase's entry setup on the same clk_baud edge as the outgoing phase's last transfer.
        -- This is the SPI master FSM's m_counter=0 fold pattern (SPI.vhd:413-452).
        procedure fold_from(from_st : in QState_t) is
            variable np : QState_t;
        begin
            np := next_phase(t_awid, t_dummy_val, t_dlen, from_st);
            case np is
                when ST_ADDR =>
                    if t_awid = "01" then
                        t_sreg   <= t_addr(23 downto 0) & x"00";
                        edge_cnt <= 2 * (24 / width_bits(t_adrw));
                    else -- t_awid = "10" (32-bit); "00"/"11" never reach ST_ADDR
                        t_sreg   <= t_addr;
                        edge_cnt <= 2 * (32 / width_bits(t_adrw));
                    end if;
                    state <= ST_ADDR;
                when ST_DUMMY =>
                    -- DUMMY counts full SCK cycles (the datasheet's "N dummy cycles"), so 2 clk_baud edges per counted cycle.
                    edge_cnt <= 2 * t_dummy_val;
                    state    <= ST_DUMMY;
                when ST_DATA =>
                    if t_dir = '0' then
                        -- WRITE: QSPIxTX is read LIVE here, not latched at launch, a deliberate deviation from the CMD/ADDR latch list (see the file-header note above).
                        -- Byte ordering matches SPI.vhd's spi_dl MSB-first, no-byte-swap convention: the low DLEN bits of the 32-bit register are the significant field.
                        case t_dlen is
                            when "01"   => t_sreg <= QSPIxTX(7 downto 0) & x"000000";
                            when "10"   => t_sreg <= QSPIxTX(15 downto 0) & x"0000";
                            when others => t_sreg <= QSPIxTX; -- "11" (32-bit)
                        end case;
                    else
                        rx_sreg <= (others => '0');
                    end if;
                    edge_cnt <= 2 * (dlen_bits_f(t_dlen) / width_bits(t_datw));
                    state    <= ST_DATA;
                when others => -- ST_DONE: no address, dummy or data phase remained
                    tcif_flag <= '1';
                    state     <= ST_DONE;
            end case;
        end procedure;

    begin
        if resetn = '0' or q_en = '0' then
            state         <= ST_IDLE;
            edge_cnt      <= 0;
            sck           <= q_cpol;
            clr_qspi_launch <= '0';
        elsif rising_edge(clk_baud) then
            clr_qspi_launch <= '0';

            case state is
                -- Idle: wait for a launch pulse, then latch the transaction and enter CMD.
                when ST_IDLE =>
                    sck <= q_cpol; -- track live CPOL while idle
                    if qspi_launch = '1' then
                        txeif_flag      <= '1'; -- TXEIF is set as the FSM leaves IDLE, i.e. the launch was accepted
                        clr_qspi_launch <= '1';
                        if q_cpha = '1' then
                            -- CPHA=1 pre-toggle, once per transaction, mirroring SPI.vhd:393-395's `if spi_cpha='1' then sck<=not sck` at start_tx.
                            sck <= not q_cpol;
                        end if;
                        -- Latch the CR/CMD-derived transaction-local fields (frozen list): widths, AWID, DUMMY, DIR, DLEN, cmd byte, address.
                        t_cmdw      <= q_cmdw;
                        t_adrw      <= q_adrw;
                        t_datw      <= q_datw;
                        t_awid      <= q_awid;
                        t_dummy_val <= slv2uint(q_dummy);
                        t_dlen      <= QSPIxCMD(9 downto 8);
                        t_dir       <= QSPIxCMD(10);
                        t_cmd       <= QSPIxCMD(7 downto 0);
                        t_addr      <= QSPIxADR;
                        -- CMD phase is never zero-length: always entered first.
                        t_sreg      <= QSPIxCMD(7 downto 0) & x"000000";
                        edge_cnt    <= 2 * (8 / width_bits(q_cmdw));
                        state       <= ST_CMD;
                    end if;

                -- Each bit-group occupies one FULL SCK cycle, i.e. two clk_baud edges (SPI.vhd master timing generalized to N-bit groups).
                -- sck toggles every edge, and with the CPHA pre-toggle folded in at launch the SAMPLE edge (flash captures, DUT samples reads) is always the EVEN edge_cnt value while the DRIVE edge (DUT advances its output shift register) is the ODD value.
                -- The final edge_cnt=1 drive edge folds into the next phase.
                -- Output for the group is held across its sample edge and advanced on the following drive edge, exactly as SPI shifts m_tx_sreg on the m_counter(0)='0' drive edges only.
                -- Command phase: shift the opcode out at CMD width.
                when ST_CMD =>
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_CMD);
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 1 then   -- drive edge: advance output
                            w := width_bits(t_cmdw);
                            case w is
                                when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                when others => t_sreg <= t_sreg(30 downto 0) & '0';
                            end case;
                        end if;
                    end if;

                -- Address phase: shift the 24- or 32-bit address out at ADDR width.
                when ST_ADDR =>
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_ADDR);
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 1 then   -- drive edge: advance output
                            w := width_bits(t_adrw);
                            case w is
                                when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                when others => t_sreg <= t_sreg(30 downto 0) & '0';
                            end case;
                        end if;
                    end if;

                -- Dummy phase: turnaround cycles between the address and read data.
                when ST_DUMMY =>
                    -- The bus is released for the whole dummy phase (io_dir all '0', driven combinationally below) while sck still toggles.
                    -- There is no sample or drive work here, just 2*DUMMY edges to burn.
                    sck <= not sck;
                    if edge_cnt = 1 then
                        fold_from(ST_DUMMY);
                    else
                        edge_cnt <= edge_cnt - 1;
                    end if;

                -- Data phase: shift the write word out, or accumulate the read word in.
                when ST_DATA =>
                    sck <= not sck;
                    w := width_bits(t_datw);
                    if edge_cnt = 1 then
                        -- Final drive edge of the data phase: rx_sreg already holds every sampled bit, the last sample having happened at edge_cnt=2.
                        -- Latch QSPIxRX and the flags together so RXFULL and TCIF settle on the same edge (single-word MVP).
                        if t_dir = '1' then
                            QSPIxRX     <= rx_sreg;
                            rxfull_flag <= '1';
                        end if;
                        tcif_flag <= '1';
                        state     <= ST_DONE;
                    else
                        edge_cnt <= edge_cnt - 1;
                        if (edge_cnt mod 2) = 0 then
                            -- Sample edge: capture read data; writes hold their output.
                            if t_dir = '1' then
                                case w is
                                    when 2      => rx_sreg <= rx_sreg(29 downto 0) & io_in(1 downto 0);
                                    when 4      => rx_sreg <= rx_sreg(27 downto 0) & io_in(3 downto 0);
                                    when others => rx_sreg <= rx_sreg(30 downto 0) & io_in(1);
                                end case;
                            end if;
                        else
                            -- Drive edge: advance the write output; reads stay released.
                            if t_dir = '0' then
                                case w is
                                    when 2      => t_sreg <= t_sreg(29 downto 0) & "00";
                                    when 4      => t_sreg <= t_sreg(27 downto 0) & "0000";
                                    when others => t_sreg <= t_sreg(30 downto 0) & '0';
                                end case;
                            end if;
                        end if;
                    end if;

                -- Done: one tail edge with BUSY still high, then back to idle and CS released.
                when ST_DONE =>
                    state <= ST_IDLE;
                    sck   <= q_cpol;

            end case;
        end if;

        -- QSPIxRX holds serial-core-written read data and is otherwise a plain volatile register.
        -- It has no write-side reset (reg_write resets only CR/CMD/ADR/TX) and the FSM only ever ASSIGNS it, so it must be reset here or its readback is 'X' until the first READ completes (caught by QSPI_tb GROUP 0, "RX resets to 0").
        -- Reset-only, deliberately not q_en=0, matching the flag clears' rule that disabling does not wipe data.
        if resetn = '0' then
            QSPIxRX <= (others => '0');
        end if;

        -- Status flag W1C application, the SPI.vhd:460-468 level-sensitive tail-clear idiom reused verbatim.
        -- Note that QSPIEN=0 does NOT clear these flags, a deliberate deviation from SPI's spi_en=0 clear: the frozen QSPIxSR spec defines only reset and explicit W1C as clear conditions.
        if resetn = '0' or clr_txeif = '1' then
            txeif_flag <= '0';
        end if;
        if resetn = '0' or clr_rxfull = '1' then
            rxfull_flag <= '0';
        end if;
        if resetn = '0' or clr_tcif = '1' then
            tcif_flag <= '0';
        end if;
    end process;

    ---------- IO lane drive and direction mux, combinational ----------
    -- io_dir handoff per the frozen contract: single-width (width=1) phases always drive IO0 and always read IO1, the MISO position, regardless of DATA DIR.
    -- IO2/IO3 stay driven high (WP# and HOLD# deasserted) whenever they are not carrying data.
    -- Dual and quad phases drive io_dir(width-1:0) while driving (CMD, ADDR, DATA-WRITE) and release everything (all io_dir='0') during DUMMY and DATA-READ.
    -- It is derived combinationally off `state` plus the latched cmd fields, so it flips on the same edge the state changes, with no hidden turnaround cycle.
    -- DUMMY_CYCLES=0 with a dual or quad READ is documented firmware misuse.
    io_mux: process(state, t_cmdw, t_adrw, t_datw, t_dir, t_sreg)
        variable w : natural;
    begin
        io_out <= (others => '0');
        io_dir <= (others => '0'); -- default: released (IDLE, DUMMY, DONE)

        case state is
            when ST_CMD =>
                w := width_bits(t_cmdw);
                if w = 1 then
                    io_dir <= "1101"; -- IO3,IO2 driven high; IO1 input; IO0 drives
                    io_out(0) <= t_sreg(31);
                    io_out(2) <= '1';
                    io_out(3) <= '1';
                elsif w = 2 then
                    io_dir <= "1111";
                    io_out(1 downto 0) <= t_sreg(31 downto 30);
                    io_out(3 downto 2) <= "11"; -- WP# and HOLD# deasserted; dual does not use IO2/IO3
                else -- w = 4
                    io_dir <= "1111";
                    io_out(3 downto 0) <= t_sreg(31 downto 28);
                end if;

            when ST_ADDR =>
                w := width_bits(t_adrw);
                if w = 1 then
                    io_dir <= "1101";
                    io_out(0) <= t_sreg(31);
                    io_out(2) <= '1';
                    io_out(3) <= '1';
                elsif w = 2 then
                    io_dir <= "1111";
                    io_out(1 downto 0) <= t_sreg(31 downto 30);
                    io_out(3 downto 2) <= "11";
                else
                    io_dir <= "1111";
                    io_out(3 downto 0) <= t_sreg(31 downto 28);
                end if;

            when ST_DATA =>
                w := width_bits(t_datw);
                if t_dir = '0' then -- WRITE: same drive rules as CMD/ADDR
                    if w = 1 then
                        io_dir <= "1101";
                        io_out(0) <= t_sreg(31);
                        io_out(2) <= '1';
                        io_out(3) <= '1';
                    elsif w = 2 then
                        io_dir <= "1111";
                        io_out(1 downto 0) <= t_sreg(31 downto 30);
                        io_out(3 downto 2) <= "11";
                    else
                        io_dir <= "1111";
                        io_out(3 downto 0) <= t_sreg(31 downto 28);
                    end if;
                else -- READ
                    if w = 1 then
                        -- Single-width read: IO0 stays the driving line, held low since there is nothing meaningful to send, IO1 stays the input/MISO position, IO2 and IO3 are deasserted high.
                        io_dir <= "1101";
                        io_out(0) <= '0';
                        io_out(2) <= '1';
                        io_out(3) <= '1';
                    else
                        io_dir <= (others => '0'); -- dual/quad READ: fully released
                    end if;
                end if;

            when others => -- ST_IDLE, ST_DUMMY, ST_DONE: bus released
                null;
        end case;
    end process;

end behavioral;
