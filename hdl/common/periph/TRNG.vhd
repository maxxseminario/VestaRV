library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ===========================================================================
-- TRNG: ring-oscillator entropy source + harvest engine. One combined IRQ
-- (vector 121, data-ready | health-alarm). Zero pins. Base 0x6900.
-- FROZEN design: ~/vesta_docs/digperiphs/trng_design.md (decisions D1-D16,
-- orchestrator ADJUDICATION RULINGS 1-7 -- ALL BINDING; a ruling overrides any
-- conflicting Dn text). Structural template = OneWire/RTC (bus/CDC/flag
-- idiom); the NEW mechanisms this block introduces are the read-CONSUMES
-- data register with an exactly-once consume strobe + DRDY same-cycle
-- blind-window fix (D9), and the sim-stub boundary around a deliberately-
-- oscillating entropy source (D6, TrngRoEnsemble_sim.vhd / TrngRoEnsemble.vhd).
-- -V200X only: NO VHDL-2008 (no to_hstring, no process(all), no unary
-- reduce, no reading of out ports). Every process infers exactly ONE edge of
-- ONE clock; every synchronizer is single-edge (Genus VHDL-601 discipline).
-- NO falling_edge of anything, anywhere (specifically NOT of EnMemPeriph).
--
-- D1/D2 -- ONE clock family: the raw-sample decimator, the 32-bit word-
-- assembly shifter, the RCT health test, the DRDY/word-valid lifecycle, the
-- sticky W1C ALMF flag, the RUN status, and the IRQ combiner ALL ride the
-- free-running `clk`, wired to MCLK at integration (D2). The register file
-- rides the gated `ClkMem` -- the SAME mclk net at integration; every
-- ClkMem<->clk hand-off below is a toggle or a held/quasi-static level
-- (standalone-honest, RTC/OW precedent), never an async-clear crossing a
-- domain (the ROOT-2 UART defect class this library now avoids by
-- construction). The ONE true metastability CDC is the ring-oscillator tap
-- `ro_raw`, which arrives from the free-running, clockless RO ensemble and
-- is 2-FF synchronized into `clk` before any use (D7). NO async FIFO, NO
-- clock gate in the harvest datapath, NO flop clocked by `ro_raw` or any
-- other pad/async bit (ROOT-3 discipline).
--
-- CDC CROSSING INVENTORY (the ONLY crossing paths; all toggle / held-level /
-- quasi-static -- no async FIFO; see the design doc's table for the full
-- rationale of each row):
--   1. ro_raw        async RO -> clk : 2-FF sync -> ro_sync (D7). The ONE
--      genuine async CDC in the block.
--   2. dr_consume_tgl  ClkMem -> clk : toggle + edge-detect -> consume pulse
--      (D9); single mclk family at integration.
--   3. clr_almf_tgl (W1C) ClkMem -> clk : toggle + edge-detect, cleared in
--      ALMF's OWN clk process, SET WINS over a coincident CLEAR (D8, the
--      RTC/OW "later sequential assignment wins" discipline).
--   4. dr_consume_pending ClkMem (read by the ClkMem SR mux) : held level;
--      masks DRDY same-cycle (D9's blind-window fix).
--   5. DRDY / RUN / ALMF / dr_word / RUNLEN  clk -> ClkMem (read mux) : held/
--      quasi-static levels sampled by the registered read mux (D4) -- clk and
--      ClkMem are literally the same physical net at integration (D1).
--   6. EN / ROSEL / DECIM  ClkMem -> clk : held levels (D12); no 2-FF needed
--      for correctness (same mclk family), kept standalone-honest as levels.
--
-- D4 -- Bus contract, xcollapse-clean by construction (per
-- xcollapse_findings.md; BINDING). EnMemPeriph is consumed ONLY as an
-- active-low LEVEL (address decode + write-enable + read-mux gate + the D9
-- DR-read-consume qualifier). It is NEVER a clock and NEVER an edge -- the
-- TRNG SDC has NO EnMemPeriph clock. The read mux registers on rising
-- ClkMem over data already in / coincident with the mclk domain -- NO
-- combinational read, NO MCU-side bridge, NO falling_edge(EnMemPeriph)
-- pre-latch. The DR read side effect (D9) is the ONE exception to "no read
-- side effects" and does NOT reintroduce the banned falling_edge idiom (it
-- is rising-ClkMem-qualified + pending-gated, exactly like every other
-- write-commit toggle in this library).
--
-- Register map (D5; base 0x6900, slot n @ 0x6900 + 4n, decoded off
-- MABPart(7:2)). Slots >=4 read 0.
--   0 TRNG0CR : [0]EN [1]DRDYIE [2]ALMIE [7:4]ROSEL [11:8]DECIM, 31:12 rsvd.
--   1 TRNG0SR : [0]DRDY ro (D9 blind-window-corrected) [1]ALMF W1C [2]RUN ro,
--               31:3 rsvd read 0.
--   2 TRNG0DR : [31:0] entropy word, ro, READ-CONSUMES (D9). Empty read
--               (DRDY=0) returns 0, no consume, no toggle (ruling 6).
--   3 TRNG0HT : [7:0] RCTC rw (0 => hardware default 32, D8) + [21:16] RUNLEN
--               ro diagnostic (saturating), other bits reserved read 0.
--
-- D6 -- Entropy source: TrngRoEnsemble, a separate sub-component with a
-- SIM/REAL architecture split (see TrngRoEnsemble_sim.vhd / .vhd). TRNG's
-- FROZEN entity (D3) exposes it as a genuine EXTERNAL interface --
-- `ro_enable`/`ro_sel`/`ro_sclk` (out) and `ro_raw` (in) -- matching the
-- chipgen integration outline (`u_ro` an MCU.vhd-level sibling instance of
-- `trng0`) and this library's house convention for every other companion
-- entropy/protocol model (i2c_host_model, onewire_target_model,
-- qspi_flash_model, nfc_reader_model, i3c_target_model -- ALL instantiated
-- in the INTEGRATION layer / testbench, wired through real ports, never
-- nested inside the DUT). `ro_raw` is 2-FF synchronized inside TRNG before
-- any use (D7) -- NEVER a clock.
--
-- *** DISCREPANCY (flagged per the task instruction; report this loudly) ***
-- The task's kickoff note asserted "u_ro is INSIDE TRNG.vhd" (reading D6's
-- "the TRNG core instantiates TrngRoEnsemble as a COMPONENT" literally) and
-- expected the TB to need a nested VHDL `configuration` to reach it. Trying
-- that reading against the REST of the frozen material surfaces a hard
-- conflict: (1) an entity's `in` port cannot be driven by a component
-- instantiated inside that same entity -- `ro_raw` would become a dead port
-- under that reading; (2) the design doc's own G5 bench plan calls for
-- "hierarchical `force dut.u_ro.ro_raw`" to script a stuck run -- `-V200X`
-- has NO VHDL-2008 external-name mechanism to reach a signal nested two
-- levels inside a DUT, so that force is only reachable if `u_ro` sits at the
-- SAME level as `dut` (i.e. in the TB, exactly as `force dut.u_ro.ro_raw`
-- literally addresses: siblings `dut` and `u_ro`, not `dut.u_ro` nested
-- inside `dut`'s OWN internals a third level down); (3) it breaks the house
-- convention noted above. Resolution taken here: `u_ro` is instantiated in
-- the TESTBENCH (TRNG_tb.vhd), wired through the frozen ports exactly as
-- D3 spells them -- `ro_raw` is a live, meaningful input; nothing is dead.
-- The TB's default component binding (only the `sim` architecture is ever
-- compiled into the behavioral flow, so VHDL's sole-architecture default
-- binding rule resolves `TrngRoEnsemble` unambiguously) is the PROVEN
-- mechanism (see TRNG_tb.vhd's header for the belt-and-suspenders
-- explicit-configuration attempt, ruling 5).
--
-- D8 -- Health test: SP 800-90B-lite Repetition Count Test (RCT) only (no
-- APT, ruling 3). A clk-domain run-length counter increments while
-- consecutive `ro_sync` samples (at a sample_tick) are IDENTICAL, resets to
-- 1 on any change. Cutoff N = TRNG0HT.RCTC, with RCTC=0 => hardware default
-- 32 (ruling 3). Reaching N sets sticky ALMF (W1C). Ruling 3: ALMF
-- auto-halts harvesting -- `ro_enable <= EN and NOT alm_halt` (D12), so
-- clearing EN or an active alarm both park the rings and freeze RUN/harvest;
-- flags and the last assembled word are preserved. No advisory-only override
-- bit this stage.
--
-- D9 -- TRNG0DR read-CONSUMES (the new library mechanism; see the design
-- doc's full derivation). DRDY lifecycle in the clk domain: the assembler
-- (D7/D10) latches a completed 32-bit word into dr_word and sets
-- word_valid; word_valid clears when the word is consumed. The consume
-- qualifier (ClkMem domain) is `rising ClkMem AND EnMemPeriph='0' AND
-- slot=DR AND WEn="1111"` (a read) -- gated on `word_valid='1' AND
-- dr_consume_pending='0'` so a duplicate edge in one access can never
-- double-pop. On a qualifying read, dr_consume_pending sets the SAME edge
-- and dr_consume_tgl flips; the SR mux computes `DRDY = word_valid AND NOT
-- dr_consume_pending`, so an SR read issued immediately after the DR read
-- sees DRDY=0 in the SAME cycle even though the clk engine has not yet torn
-- down word_valid (closing the D9 blind window). clk 2-FFs dr_consume_tgl,
-- edge-detects -> a one-cycle consume pulse that clears word_valid.
-- dr_consume_pending clears once word_valid=0 has been OBSERVED in ClkMem
-- (read directly -- coincident nets, D1) -- the old word is truly gone
-- before the mask lifts, so the next DRDY assert is a genuinely new word.
--
-- D10 -- depth-1 holding register, not a FIFO. The assembler (asm_reg/
-- asm_cnt) stalls -- holds its just-completed 32 bits without dropping them
-- and without overwriting dr_word -- whenever dr_word is still unconsumed
-- when the 32nd sample lands; it promotes that held candidate into dr_word
-- the moment word_valid frees up, then resumes collecting the NEXT word. No
-- partial word is ever exposed on dr_word.
--
-- D11 -- irq_trng = (DRDY and DRDYIE) or (ALMF and ALMIE), combinational,
-- never latched. DRDY here is the D9 blind-window-corrected level.
--
-- D12 -- CR fields + RO fan-out: EN gates the entropy source
-- (ro_enable <= EN and NOT alm_halt); ROSEL forwards to ro_sel (D6 mask);
-- DECIM sets the decimator (D7); DRDYIE/ALMIE gate the IRQ (D11). All CR
-- bits are quasi-static ClkMem stores.
--
-- D13 -- Reset: resetn (chip async, active-low) applied DIRECTLY to both the
-- clk and ClkMem processes -- no reset synchronizer (same mclk family, no
-- truly-async always-on domain like the RTC's LFXT; the RO ensemble has no
-- state to release, it simply starts oscillating when ro_enable rises, and
-- its async output is covered by the D7 2-FF sync).
--
-- D14 -- Zero pins. D15 -- presence knob `peripherals.trng` (chipgen, out of
-- scope this session); `NRO` generic {4,8} via `peripherals.trngRings`.
-- D16 -- entropy caveat: bring-up-grade only, firmware MUST DRBG + honor
-- ALMF (TRM/firmware concern, not enforced in hardware).
--
-- Architecture (block summary, D3/B1-B5, matches the design doc's grouping):
-- B1 register file (ClkMem) -- CR/HT stores, the SR W1C toggle, the D9
-- dr_consume_pending/dr_consume_tgl, the registered read mux. B2 sync/CDC
-- (clk) -- the ro_raw 2-FF sync, the dr_consume_tgl/clr_almf_tgl 2-FF+edge-
-- detect pulses. B3 decimator + assembler (clk) -- the 2^DECIM sample-tick
-- counter, the 32-bit word-assembly shifter with the D9/D10 stall-on-
-- unconsumed. B4 health test (clk) -- the run-length counter vs RCTC(/32)
-- cutoff -> sticky ALMF; RUNLEN diagnostic; alm_halt gate. B5 status/IRQ
-- (clk) -- DRDY/RUN levels; irq_trng combiner. u_ro TrngRoEnsemble (D6):
-- async rings (real) / deterministic LFSR (sim) -> ro_raw.
-- ===========================================================================

entity TRNG is
    generic (
        NRO : natural := 8    -- ring-oscillator count in the ensemble (D6). {4,8} proven (D15).
    );
    port (
        clk         : in  std_logic;                     -- free-running MCLK at integration (D2):
                                                         -- decimator, word assembler, health test,
                                                         -- DRDY lifecycle, sticky ALMF, IRQ combiner
        resetn      : in  std_logic;                     -- chip reset, active-low (async)
        irq_trng    : out std_logic;                     -- combined data-ready|alarm IRQ (vector 121)

        -- register-file slave port (RTC/OW/DMA/I2CT house idiom, D4)
        ClkMem      : in  std_logic;                     -- gated bus clock (register file)
        EnMemPeriph : in  std_logic;                     -- ACTIVE-LOW select/qualifier (NEVER a clock)
        WEn         : in  std_logic_vector(3 downto 0);  -- ACTIVE-LOW per byte lane
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  std_logic_vector(31 downto 0);
        rdata_out   : out std_logic_vector(31 downto 0); -- registered read (no bridge, D4)

        -- entropy-source interface to the TrngRoEnsemble sub-component (D6). ro_raw is PURE DATA,
        -- 2-FF synchronized inside TRNG before use (D7) -- NEVER a clock.
        ro_enable   : out std_logic;                     -- '1' lets the rings oscillate; '0' gates them
        ro_sel      : out std_logic_vector(3 downto 0);  -- CR.ROSEL forwarded to the ensemble
        ro_sclk     : out std_logic;                     -- = clk, for the SIM arch's deterministic model
                                                         --   ONLY (the real RO ignores it, D6)
        ro_raw      : in  std_logic                      -- XOR-ensembled RO jitter bit (async, D6/D7)
    );
end TRNG;

architecture behavioral of TRNG is

    -- ---- word-slot map (frozen, D5) --------------------------------------
    constant SLOT_CR : natural := 0;
    constant SLOT_SR : natural := 1;
    constant SLOT_DR : natural := 2;
    constant SLOT_HT : natural := 3;

    -- ---- B1 register-file storage (ClkMem domain) --------------------------
    signal trng_cr   : std_logic_vector(11 downto 0);   -- EN/DRDYIE/ALMIE/ROSEL/DECIM (D5/D12)
    signal rct_cutoff: std_logic_vector(7 downto 0);    -- HT.RCTC (D8)
    signal dr_consume_pending : std_logic;              -- D9 blind-window mask
    signal dr_consume_tgl     : std_logic;              -- D9 consume request toggle
    signal clr_almf_tgl       : std_logic;              -- D8/D12 W1C ALMF request toggle
    signal trng_slot          : natural range 0 to 63;  -- decoded word slot

    -- ---- CR field taps (combinational; quasi-static, D12) -----------------
    signal en_cr, drdyie_cr, almie_cr : std_logic;
    signal rosel_cr : std_logic_vector(3 downto 0);
    signal decim_cr : std_logic_vector(3 downto 0);

    -- ---- B2 clk-domain CDC: 2-FF sync + edge-detect (D7/D9/D8) ------------
    signal ro_s1, ro_s2   : std_logic;
    signal ro_sync        : std_logic;
    signal cnstgl_c1, cnstgl_c2, cnstgl_prev   : std_logic;
    signal clralm_c1, clralm_c2, clralm_prev   : std_logic;
    signal consume_pulse, clr_almf_pulse       : std_logic;

    -- ---- B3 decimator + assembler (clk domain, D7/D9/D10) -----------------
    signal decim_reload : std_logic_vector(15 downto 0);
    signal samp_cnt      : std_logic_vector(15 downto 0);
    signal sample_tick    : std_logic;
    signal asm_reg        : std_logic_vector(31 downto 0);
    signal asm_cnt        : natural range 0 to 32;
    signal dr_word        : std_logic_vector(31 downto 0);
    signal word_valid      : std_logic;

    -- ---- B4 health test (clk domain, D8) -----------------------------------
    signal have_prev   : std_logic;
    signal prev_sample  : std_logic;
    signal run_len       : std_logic_vector(7 downto 0);
    signal cutoff_eff    : std_logic_vector(7 downto 0);
    signal almf_flag      : std_logic;
    signal runlen_diag     : std_logic_vector(5 downto 0);

    -- ---- B5 status/IRQ (clk domain, D11/D12) -------------------------------
    signal alm_halt   : std_logic;
    signal run_level   : std_logic;
    signal drdy_level   : std_logic;

begin

    -- ------------------------- Signal Routing ---------------------------------
    -- slot decode (EnMemPeriph-qualified LEVEL, D4; never an edge).
    trng_slot <= conv_integer(MABPart) when EnMemPeriph = '0' else 0;

    -- CR field taps (D12; quasi-static, coincident nets at integration, D1).
    en_cr     <= trng_cr(0);
    drdyie_cr <= trng_cr(1);
    almie_cr  <= trng_cr(2);
    rosel_cr  <= trng_cr(7 downto 4);
    decim_cr  <= trng_cr(11 downto 8);

    -- RCT cutoff: RCTC=0 => hardware default 32 (D8, ruling 3).
    cutoff_eff <= rct_cutoff when rct_cutoff /= x"00" else x"20";

    -- B5: status levels + IRQ combiner (D11/D12), combinational, never latched.
    alm_halt   <= almf_flag;
    run_level  <= en_cr and not alm_halt;             -- RUN = EN and not alarm-halted (D12)
    drdy_level <= word_valid and not dr_consume_pending;   -- D9 blind-window-corrected DRDY
    irq_trng   <= (drdy_level and drdyie_cr) or (almf_flag and almie_cr);   -- D11

    -- entropy-source fan-out (D6/D12): ro_enable gates the ensemble; ro_sel
    -- forwards CR.ROSEL; ro_sclk = clk for the sim arch only (D6, ignored by
    -- rtl). u_ro itself is instantiated externally (TB / MCU.vhd, see the
    -- DISCREPANCY note above) -- these are genuine, live external ports.
    ro_enable <= run_level;
    ro_sel    <= rosel_cr;
    ro_sclk   <= clk;

    -- ------------------------- B1: register write + D9 consume (ClkMem) -------
    -- Rising ClkMem, EnMemPeriph='0' qualified writes (D4). CR/HT stores;
    -- SR lane-0 write of 1 to ALMF flips clr_almf_tgl (W1C-CDC, D8/D12); a
    -- qualifying DR READ (slot=DR, WEn="1111") launches the D9 consume when
    -- word_valid='1' and not already pending. dr_consume_pending's teardown
    -- (independent of EnMemPeriph) clears once word_valid=0 has been
    -- observed (the old word is truly gone, D9). Reset via resetn.
    reg_write: process(resetn, ClkMem)
    begin
        if resetn = '0' then
            trng_cr            <= (others => '0');
            rct_cutoff          <= (others => '0');
            dr_consume_pending  <= '0';
            dr_consume_tgl      <= '0';
            clr_almf_tgl        <= '0';
        elsif rising_edge(ClkMem) then

            -- D9 pending teardown: once the clk engine has torn down
            -- word_valid, the mask lifts (coincident nets, D1 -- read
            -- directly, no crossing needed).
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
                        -- D9 read-consume: qualifying READ only (WEn="1111"), gated on a
                        -- valid, not-already-consumed word (no double-pop on a repeat edge).
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

    -- ------------------------- B1: register read (ClkMem) ---------------------
    -- Registered read mux on rising ClkMem over data already in / coincident
    -- with the mclk domain (D4): no pre-latch, no bridge. DR returns dr_word
    -- ONLY on a currently-valid, not-yet-consumed word (the SAME condition
    -- that gates the consume above, so the read and the pop are atomic and
    -- consistent); otherwise 0 (empty read, ruling 6 -- no consume, no toggle).
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

    -- ------------------------- B2: clk-domain CDC (D7/D8/D9) -------------------
    -- 2-FF sync of the async RO tap (ro_raw, D7 -- the ONE genuine
    -- metastability CDC in this block) plus 2-FF + edge-detect on the two
    -- ClkMem-domain request toggles (dr_consume_tgl, D9; clr_almf_tgl, D8).
    -- Single edge (rising clk) only. Reset via resetn.
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
    ro_sync <= ro_s2;
    consume_pulse  <= '1' when (cnstgl_c2 /= cnstgl_prev) else '0';
    clr_almf_pulse <= '1' when (clralm_c2 /= clralm_prev) else '0';

    -- ------------------------- B3: decimator (clk, D7) --------------------------
    -- Free-running reload down-counter -> one-cycle sample_tick every
    -- decim_reload+1 = 2^DECIM clk cycles (DECIM=0 -> every clk, D7). Plain
    -- counter-compare, NO clock gate, no generated clock. decim_reload is a
    -- combinational lookup off decim_cr (quasi-static CR field, D12).
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
            if run_level = '1' then   -- = ro_enable (D12); never read an out port (-V200X)
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

    -- ------------------------- B3: 32-bit assembler + D10 stall (clk) -----------
    -- asm_reg/asm_cnt continuously packs decimated samples MSB-first
    -- (direct-pack whitening, ruling 1). At the 32nd sample, promote directly
    -- into dr_word/word_valid if the holding register is free; otherwise
    -- STALL (D10): asm_cnt parks at 32, holding the completed candidate in
    -- asm_reg without dropping it and without overwriting dr_word, until
    -- word_valid frees up (checked every cycle), at which point it promotes
    -- and resumes collecting the next word. No partial word ever reaches
    -- dr_word.
    assembler: process(resetn, clk)
    begin
        if resetn = '0' then
            asm_reg    <= (others => '0');
            asm_cnt    <= 0;
            dr_word    <= (others => '0');
            word_valid <= '0';
        elsif rising_edge(clk) then

            if asm_cnt = 32 then
                -- stalled: a completed word waits in asm_reg (D10)
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

            -- D9 consume: clears word_valid one cycle per consume pulse.
            -- Cannot collide with a same-cycle stall-promote above (that
            -- branch requires word_valid='0', the pre-edge value, so a
            -- promote and a consume never target the same edge's word).
            if consume_pulse = '1' then
                word_valid <= '0';
            end if;

        end if;
    end process assembler;

    -- ------------------------- B4: health test -- RCT (clk, D8) ----------------
    -- Run-length counter over consecutive IDENTICAL ro_sync samples (at each
    -- sample_tick); resets to 1 on any change. Reaching cutoff_eff sets the
    -- sticky ALMF (W1C, ruling 3: RCT-only, RCTC=0=>32, auto-halt). SET wins
    -- over a coincident CLEAR (default clear applied first; the case-driven
    -- set below can override the SAME cycle, later sequential assignment
    -- wins -- RTC/OW discipline). RUNLEN (runlen_diag) saturates at 63.
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
                    almf_flag <= '1';   -- SET wins over the clear above (D8/ruling 3)
                end if;
            end if;
        end if;
    end process health;

    runlen_diag <= run_len(5 downto 0) when run_len(7 downto 6) = "00" else "111111";

end architecture behavioral;
