library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

/* TRNG: ring-oscillator entropy source plus harvest engine at base 0x6900, zero pins, one combined data-ready/health-alarm IRQ (vector 121).
   The decimator, word assembler, RCT health test, DRDY lifecycle, sticky ALMF and IRQ combiner all ride the free-running `clk`; the register file rides the gated `ClkMem`, the same mclk net at integration.
   Every hand-off between the two domains is a toggle or a held/quasi-static level, NEVER an async clear crossing a domain, and the ONE genuine metastability CDC is the ring tap `ro_raw`, 2-FF synchronized into `clk` before any use and never a clock: no async FIFO, no clock gate in the harvest datapath, no flop clocked by a pad or async bit.
   EnMemPeriph is consumed ONLY as an active-low LEVEL (address decode, write enable, read-mux gate, DR-read-consume qualifier), never as a clock or an edge, and the TRNG SDC has no EnMemPeriph clock.
   -V200X only: no VHDL-2008, no reading of out ports, every process infers exactly ONE rising edge of ONE clock, no falling_edge anywhere, and resetn (async, active-low) is applied directly in both domains. */

/* Register map: base 0x6900, slot n at 0x6900 + 4n, decoded off MABPart(7:2); slots 4 and above read 0.
     0 TRNG0CR : [0]EN [1]DRDYIE [2]ALMIE [7:4]ROSEL [11:8]DECIM, 31:12 rsvd.
     1 TRNG0SR : [0]DRDY ro (blind-window-corrected) [1]ALMF W1C [2]RUN ro, 31:3 rsvd read 0.
     2 TRNG0DR : [31:0] entropy word, ro, READ-CONSUMES. An empty read (DRDY=0) returns 0, with no consume and no toggle.
     3 TRNG0HT : [7:0] RCTC rw (0 selects the hardware default 32) plus [21:16] RUNLEN ro diagnostic (saturating), other bits reserved read 0. */

entity TRNG is
    generic (
        NRO : natural := 8    -- ring-oscillator count in the ensemble; {4,8} supported.
    );
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration: decimator, word assembler,
                                                         -- health test, DRDY lifecycle, sticky ALMF, IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_trng    : out std_logic;                     -- combined data-ready|alarm IRQ (vector 121)

        -- register-file slave port (house slave-port idiom)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read (no bridge)

        -- Entropy-source interface to the TrngRoEnsemble instance, which is a SIBLING of this entity (in MCU.vhd or the testbench, never nested inside it): an `in` port cannot be driven from within the entity that declares it.
        -- ro_raw is PURE DATA, 2-FF synchronized inside TRNG before use, and NEVER a clock; the entropy is bring-up grade, so firmware must run a DRBG and honor ALMF.
        ro_enable   : out std_logic;                     -- '1' lets the rings oscillate; '0' gates them
        ro_sel      : out std_logic_vector(3 downto 0);  -- CR.ROSEL forwarded to the ensemble
        ro_sclk     : out std_logic;                     -- driven from clk, for the SIM architecture's deterministic model ONLY (the real RO ignores it)
        ro_raw      : in  std_logic;                     -- XOR-ensembled RO jitter bit (async)

        -- Event-fabric tap: the blind-window-corrected data-ready LEVEL, taken pre-IE so drdyie_cr never touches it.
        -- The fabric front-end does its own 2-FF and rising-edge detect, so a level held until consumed fires exactly once.
        evt_drdy    : out std_logic
    );
end TRNG;

architecture behavioral of TRNG is

    -- ---- word-slot map ---------------------------------------------------
    constant SLOT_CR : natural := 0;
    constant SLOT_SR : natural := 1;
    constant SLOT_DR : natural := 2;
    constant SLOT_HT : natural := 3;

    -- ---- register-file storage (ClkMem domain) -----------------------------
    signal trng_cr   : std_logic_vector(11 downto 0);   -- EN/DRDYIE/ALMIE/ROSEL/DECIM
    signal rct_cutoff: std_logic_vector(7 downto 0);    -- HT.RCTC
    signal dr_consume_pending : std_logic;              -- blind-window mask
    signal dr_consume_tgl     : std_logic;              -- consume request toggle
    signal clr_almf_tgl       : std_logic;              -- W1C ALMF request toggle
    signal trng_slot          : natural range 0 to 63;  -- decoded word slot

    -- ---- CR field taps (combinational, quasi-static) ----------------------
    signal en_cr, drdyie_cr, almie_cr : std_logic;
    signal rosel_cr : std_logic_vector(3 downto 0);
    signal decim_cr : std_logic_vector(3 downto 0);

    -- ---- clk-domain CDC: 2-FF sync + edge-detect --------------------------
    signal ro_s1, ro_s2   : std_logic;
    signal ro_sync        : std_logic;
    signal cnstgl_c1, cnstgl_c2, cnstgl_prev   : std_logic;
    signal clralm_c1, clralm_c2, clralm_prev   : std_logic;
    signal consume_pulse, clr_almf_pulse       : std_logic;

    -- ---- decimator + assembler (clk domain) -------------------------------
    signal decim_reload : std_logic_vector(15 downto 0);
    signal samp_cnt      : std_logic_vector(15 downto 0);
    signal sample_tick    : std_logic;
    signal asm_reg        : std_logic_vector(31 downto 0);
    signal asm_cnt        : natural range 0 to 32;
    signal dr_word        : std_logic_vector(31 downto 0);
    signal word_valid      : std_logic;

    -- ---- health test (clk domain) ------------------------------------------
    signal have_prev   : std_logic;
    signal prev_sample  : std_logic;
    signal run_len       : std_logic_vector(7 downto 0);
    signal cutoff_eff    : std_logic_vector(7 downto 0);
    signal almf_flag      : std_logic;
    signal runlen_diag     : std_logic_vector(5 downto 0);

    -- ---- status/IRQ (clk domain) -------------------------------------------
    signal alm_halt   : std_logic;
    signal run_level   : std_logic;
    signal drdy_level   : std_logic;

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, never an edge).
    trng_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- CR field taps (quasi-static, coincident nets at integration).
    en_cr     <= trng_cr(0);
    drdyie_cr <= trng_cr(1);
    almie_cr  <= trng_cr(2);
    rosel_cr  <= trng_cr(7 downto 4);
    decim_cr  <= trng_cr(11 downto 8);

    -- RCT cutoff: RCTC=0 selects the hardware default 32.
    cutoff_eff <= rct_cutoff when rct_cutoff /= x"00" else x"20";

    -- Status levels + IRQ combiner, combinational, never latched.
    alm_halt   <= almf_flag;
    run_level  <= en_cr and not alm_halt;             -- RUN = EN and not alarm-halted
    drdy_level <= word_valid and not dr_consume_pending;   -- blind-window-corrected DRDY
    irq_trng   <= (drdy_level and drdyie_cr) or (almf_flag and almie_cr);   -- data-ready or alarm
    evt_drdy   <= drdy_level;                           -- event-fabric tap (pre-IE level)

    -- Entropy-source fan-out: ro_enable gates the ensemble, ro_sel forwards CR.ROSEL, and ro_sclk is clk for the sim architecture only (the real RTL ignores it).
    -- u_ro itself is instantiated externally, in the TB or in MCU.vhd, so these are genuine, live external ports.
    ro_enable <= run_level;
    ro_sel    <= rosel_cr;
    ro_sclk   <= clk;

    /* ------------------------- register write + consume (ClkMem) -------------
       Rising ClkMem, EnMemPeriph='0' qualified writes: the CR/HT stores, an SR lane-0 write of 1 to ALMF flipping clr_almf_tgl (W1C across domains), and a qualifying DR READ (slot=DR, WEn="1111") launching the consume when word_valid='1' and nothing is already pending.
       dr_consume_pending's teardown, independent of EnMemPeriph, clears once word_valid=0 has been observed, i.e. the old word is truly gone. */
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            trng_cr            <= (others => '0');
            rct_cutoff          <= (others => '0');
            dr_consume_pending  <= '0';
            dr_consume_tgl      <= '0';
            clr_almf_tgl        <= '0';
        elsif rising_edge(ClkMem) then

            -- Pending teardown: once the clk engine has torn down word_valid the mask lifts (coincident nets, read directly with no crossing needed).
            if dr_consume_pending = '1' and word_valid = '0' then
                dr_consume_pending <= '0';
            end if;

            if EnMemPeriph = '0' then
                case trng_slot is
                    when SLOT_CR =>
                        if WEn(0) = '0' then
                            trng_cr <= wdata(11 downto 0);   -- bits 31:12 reserved
                        end if;
                    when SLOT_SR =>
                        -- W1C: writing 1 clears ALMF; DRDY(0)/RUN(2) are read-only, ignored.
                        if WEn(0) = '0' then
                            if wdata(1) = '1' then clr_almf_tgl <= not clr_almf_tgl; end if;
                        end if;
                    when SLOT_DR =>
                        -- Read-consume: qualifying READ only (WEn="1111"), gated on a valid, not-already-consumed word (no double-pop on a repeat edge).
                        if WEn = "1111" then
                            if word_valid = '1' and dr_consume_pending = '0' then
                                dr_consume_pending <= '1';
                                dr_consume_tgl      <= not dr_consume_tgl;
                            end if;
                        end if;
                    when SLOT_HT =>
                        -- RCTC (rw) only; RUNLEN (ro diagnostic) ignores writes.
                        if WEn(0) = '0' then
                            rct_cutoff <= wdata(7 downto 0);
                        end if;
                    when others =>
                        null;   -- slots >=4 no effect
                end case;
            end if;
        end if;
    end process reg_write;

    /* ------------------------- register read (ClkMem) -------------------------
       Registered read mux on rising ClkMem over data already in, or coincident with, the mclk domain: no pre-latch, no bridge.
       DR returns dr_word ONLY on a currently-valid, not-yet-consumed word, the SAME condition that gates the consume above, so the read and the pop are atomic; otherwise it returns 0, an empty read with no consume and no toggle. */
    reg_read: process(ClkMem)
    begin
        if rising_edge(ClkMem) then
            case trng_slot is
                when SLOT_CR =>
                    rdata_out <= (31 downto 12 => '0') & trng_cr;
                when SLOT_SR =>
                    rdata_out <= (31 downto 3 => '0') & run_level & almf_flag & drdy_level;
                when SLOT_DR =>
                    if word_valid = '1' and dr_consume_pending = '0' then
                        rdata_out <= dr_word;
                    else
                        rdata_out <= (others => '0');
                    end if;
                when SLOT_HT =>
                    rdata_out <= (31 downto 22 => '0') & runlen_diag & (15 downto 8 => '0') & rct_cutoff;
                when others =>
                    rdata_out <= (others => '0');   -- slots >=4 read 0
            end case;
        end if;
    end process reg_read;

    /* ------------------------- clk-domain CDC ----------------------------------
       2-FF sync of the async RO tap ro_raw, the ONE genuine metastability CDC in this block, plus 2-FF and edge-detect on the two ClkMem-domain request toggles (dr_consume_tgl, clr_almf_tgl).
       Single edge (rising clk) only, reset via resetn. */
    clk_cdc: process(resetn, clk)
    begin
        if resetn = '0' then
            ro_s1 <= '0'; ro_s2 <= '0';
            cnstgl_c1 <= '0'; cnstgl_c2 <= '0'; cnstgl_prev <= '0';
            clralm_c1 <= '0'; clralm_c2 <= '0'; clralm_prev <= '0';
        elsif rising_edge(clk) then
            ro_s1 <= ro_raw; ro_s2 <= ro_s1;
            cnstgl_c1 <= dr_consume_tgl; cnstgl_c2 <= cnstgl_c1; cnstgl_prev <= cnstgl_c2;
            clralm_c1 <= clr_almf_tgl;   clralm_c2 <= clralm_c1;   clralm_prev <= clralm_c2;
        end if;
    end process clk_cdc;
    -- Synchronized RO sample, and the two edge-detected request pulses.
    ro_sync <= ro_s2;
    consume_pulse  <= '1' when (cnstgl_c2 /= cnstgl_prev) else '0';
    clr_almf_pulse <= '1' when (clralm_c2 /= clralm_prev) else '0';

    /* ------------------------- decimator (clk) ----------------------------------
       Free-running reload down-counter producing a one-cycle sample_tick every decim_reload+1 = 2^DECIM clk cycles (DECIM=0 gives every clk), a plain counter-compare with NO clock gate and no generated clock.
       decim_reload is a combinational lookup off decim_cr, a quasi-static CR field. */
    decim_lut: process(decim_cr)
    begin
        case decim_cr is
            when "0000" => decim_reload <= x"0000";
            when "0001" => decim_reload <= x"0001";
            when "0010" => decim_reload <= x"0003";
            when "0011" => decim_reload <= x"0007";
            when "0100" => decim_reload <= x"000F";
            when "0101" => decim_reload <= x"001F";
            when "0110" => decim_reload <= x"003F";
            when "0111" => decim_reload <= x"007F";
            when "1000" => decim_reload <= x"00FF";
            when "1001" => decim_reload <= x"01FF";
            when "1010" => decim_reload <= x"03FF";
            when "1011" => decim_reload <= x"07FF";
            when "1100" => decim_reload <= x"0FFF";
            when "1101" => decim_reload <= x"1FFF";
            when "1110" => decim_reload <= x"3FFF";
            when "1111" => decim_reload <= x"7FFF";
            when others => decim_reload <= x"0000";
        end case;
    end process decim_lut;

    decimator: process(resetn, clk)
    begin
        if resetn = '0' then
            samp_cnt    <= (others => '0');
            sample_tick <= '0';
        elsif rising_edge(clk) then
            if run_level = '1' then   -- same net as ro_enable; never read an out port under -V200X
                if samp_cnt = x"0000" then
                    samp_cnt    <= decim_reload;
                    sample_tick <= '1';
                else
                    samp_cnt    <= samp_cnt - 1;
                    sample_tick <= '0';
                end if;
            else
                samp_cnt    <= decim_reload;   -- park at reload while disabled/halted
                sample_tick <= '0';
            end if;
        end if;
    end process decimator;

    /* ------------------------- 32-bit assembler + stall (clk) -------------------
       asm_reg/asm_cnt continuously packs decimated samples MSB-first (direct-pack whitening) and at the 32nd sample promotes directly into dr_word/word_valid if the depth-1 holding register is free.
       Otherwise it STALLs, parking asm_cnt at 32 and holding the completed candidate in asm_reg without dropping it or overwriting dr_word, until word_valid frees up; no partial word ever reaches dr_word. */
    assembler: process(resetn, clk)
    begin
        if resetn = '0' then
            asm_reg    <= (others => '0');
            asm_cnt    <= 0;
            dr_word    <= (others => '0');
            word_valid <= '0';
        elsif rising_edge(clk) then

            if asm_cnt = 32 then
                -- stalled: a completed word waits in asm_reg
                if word_valid = '0' then
                    dr_word    <= asm_reg;
                    word_valid <= '1';
                    asm_cnt    <= 0;
                end if;
            elsif sample_tick = '1' then
                if asm_cnt = 31 then
                    if word_valid = '0' then
                        dr_word    <= asm_reg(30 downto 0) & ro_sync;
                        word_valid <= '1';
                        asm_cnt    <= 0;
                    else
                        asm_reg <= asm_reg(30 downto 0) & ro_sync;   -- hold the completed candidate
                        asm_cnt <= 32;
                    end if;
                else
                    asm_reg <= asm_reg(30 downto 0) & ro_sync;
                    asm_cnt <= asm_cnt + 1;
                end if;
            end if;

            -- Consume: clears word_valid for one cycle per consume pulse.
            -- It cannot collide with a same-cycle stall-promote above, because that branch requires word_valid='0', the pre-edge value, so a promote and a consume never target the same edge's word.
            if consume_pulse = '1' then
                word_valid <= '0';
            end if;

        end if;
    end process assembler;

    /* ------------------------- health test, RCT (clk) --------------------------
       Run-length counter over consecutive IDENTICAL ro_sync samples at each sample_tick, resetting to 1 on any change; reaching cutoff_eff sets the sticky ALMF (W1C), which auto-halts harvesting through alm_halt.
       SET wins over a coincident CLEAR: the clear is applied first and the set below overrides it in the SAME cycle, the later sequential assignment winning; RUNLEN (runlen_diag) saturates at 63. */
    health: process(resetn, clk)
        variable new_run : std_logic_vector(7 downto 0);
    begin
        if resetn = '0' then
            have_prev   <= '0';
            prev_sample <= '0';
            run_len     <= (others => '0');
            almf_flag   <= '0';
        elsif rising_edge(clk) then

            if clr_almf_pulse = '1' then
                almf_flag <= '0';
            end if;

            if sample_tick = '1' then
                if have_prev = '0' then
                    new_run   := x"01";
                    have_prev <= '1';
                elsif ro_sync = prev_sample then
                    if run_len = x"FF" then
                        new_run := run_len;
                    else
                        new_run := run_len + 1;
                    end if;
                else
                    new_run := x"01";
                end if;

                run_len     <= new_run;
                prev_sample <= ro_sync;

                if new_run >= cutoff_eff then
                    almf_flag <= '1';   -- SET wins over the clear above
                end if;
            end if;
        end if;
    end process health;

    -- RUNLEN diagnostic: the low 6 bits of run_len, saturating at 63.
    runlen_diag <= run_len(5 downto 0) when run_len(7 downto 6) = "00" else "111111";

end architecture behavioral;
