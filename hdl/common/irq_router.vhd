-- =============================================================================
-- irq_router.vhd  (M7a fan-out matrix; M19 PLIC-lite claim/complete rework)
-- =============================================================================
-- THE peripheral interrupt controller: per-hart routing/enable rows (the M7a
-- programming model, addresses unchanged) + a PLIC-style CLAIM/COMPLETE
-- delivery stage (M19). Before M19 this block was a pure fan-out matrix
-- (NHARTS x NUM_SRCS enable wires to the tiles, the full deglitched vector
-- to every tile boundary); at Argus N=18 that cost ~258 inbound IRQ boundary
-- flops PER TILE and ~3.1k assembly nets. M19 collapses delivery to ONE
-- registered meip wire per hart:
--
--   meip(h) = OR over peripheral sources i of
--             ( level(i) AND en[h](i) AND NOT in_service(i) )
--
-- and software discovers/settles the source through CLAIM/COMPLETE:
--   * CLAIM (read 0x7800): atomically returns the LOWEST pending source ID
--     enabled for the READING hart (the arbiter's s_master attributes the
--     read - the mutex-bank idiom) and sets in_service(id), masking the
--     source out of EVERY hart's meip until completed - exactly-once
--     delivery; two harts routed to the same source can never both take it
--     (the M7a "un-route yourself" software dance is retired). Returns
--     x"FFFFFFFF" (CLAIM_NONE) when nothing is pending for the reader -
--     the dispatcher treats that as spurious and simply irets.
--   * COMPLETE (write source ID to 0x7800): clears in_service(id).
--     Owner-UNQUALIFIED by design (mutex-release recovery precedent): any
--     hart can complete a hung hart's claim. IDs >= NUM_SRCS are ignored,
--     so completing a stashed CLAIM_NONE is a harmless no-op.
--   * Level-source gateway semantics for free: ISRs clear the LEVEL at the
--     peripheral before the dispatcher completes; if the level is still
--     high at complete (a new event) the source simply re-pends.
--
-- The top two sources (NUM_SRCS-2/-1 = the CLINT slots 83/84) NEVER route
-- through meip - CLINT delivery is the per-hart hardwired msip/mtip wires
-- (bootrom park/loader contract, untouched by M19). Their row bits are
-- writable but inert.
--
-- Priority = lowest source ID wins, fixed (same tie-break the in-core
-- encoder used pre-M19). A chatty low-ID source can starve high IDs on the
-- same hart - accepted v1 limitation, same property the old scheme had.
--
-- PLACEMENT: page 3 of the shared peripheral window @0x7000 (M11), a native
-- arbiter slave. REGISTER MAP (byte address = 0x7000 + 4*word; ADDR_W=10
-- decodes the full page since M19 - the old 256B aliasing is GONE):
--   word 4h+0 : HhENL = en[h](31:0)    for hart h  (h = 0..NHARTS-1)  RW
--   word 4h+1 : HhENM = en[h](63:32)                                  RW
--   word 4h+2 : HhENU = en[h](84:64)   (bits 20:0; CONTIGUOUS packing
--               both ways; bits 19/20 = the CLINT slots, inert)        RW
--   word 4h+3 : HhENX = en[h](NUM_SRCS-1:96) when NUM_SRCS > 96
--               (digperiphs #3: NFC sources 96/97; ELSE reserved,
--               reads 0). NUM_EN_WORDS = ceil(NUM_SRCS/32) words per hart. RW
--   word 512  : 0x7800 CLAIM (read, SIDE EFFECT) / COMPLETE (write)
--   word 516-518 : 0x7810/14/18 PENDL/M/U  = raw deglitched levels     RO
--   word 520-522 : 0x7820/24/28 INSVCL/M/U = in_service bits           RO
--     (the PEND/INSVC readback words expose sources 0..95 only; sources
--      96/97 are still fully deliverable via meip/CLAIM and enable-writable
--      through HhENX — they are simply not in the RO debug readback)
--   everything else reads 0, writes ignored. Row indices >= NHARTS are
--   dead (read 0, ignore writes) as at A2.
-- M19 row 0 is LIVE: hart 0 takes meip(0) like every tile (SYSTEM0's
-- vectored path is retired - D1 unification).
--
-- WDT hooks (D2): wdt_routed = OR over h of en[h](0) tells SYSTEM0 whether
-- the watchdog IRQ is deliverable anywhere (its reset-on-undeliverable
-- arm); wdt_complete pulses one mclk on COMPLETE(0) and replaces SYSTEM0's
-- falling_edge(isr_ret) end-of-interrupt hack.
--
-- BUS CONTRACT (same as clint.vhd / mutex_bank.vhd): active-high en
-- one-cycle strobe (the arbiter serializes whole transactions - claims are
-- atomic for free), 4 active-high byte-lane strobes we (resv_unit-gated in
-- MCU.vhd - a suppressed SC write must not complete an IRQ either), MW-wide
-- granted-master index (mp_arbiter s_master), 1-cycle registered read:
-- address at cycle T, rdata valid at T+1. Row writes lane-merge; COMPLETE
-- consumes the full word (any lane). Runs on the free-running mclk - meip
-- can wake a hart whose gated clk_cpu is OFF.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity irq_router is
    generic (
        NHARTS   : natural := 4;
        -- Peripheral SOURCE count (NUM_IRQ_SRCS = 85 default, 94 with I3C):
        -- deglitched levels 0..NUM_SRCS-1. NOT the core's IVT slot count.
        NUM_SRCS : natural := 85;
        -- The two CLINT source IDs (msip/mtip): delivered per-hart on the
        -- hardwired wires, so they are NEVER routed through meip/claim.
        -- digperiphs #2: made explicit (was hardcoded as "the top two sources")
        -- so I3C sources can grow ABOVE the CLINT pair without inheriting the
        -- never-route treatment. Defaults 83/84 reproduce the historic behaviour
        -- at NUM_SRCS = 85 (the CLINT pair WAS the top two there).
        CLINT_SIP : natural := 83;
        CLINT_TIP : natural := 84;
        -- Decoded word-address width. 10 = the full 4 KB page (M19: the
        -- CLAIM block sits at fixed word 512 = byte 0x800, NHARTS-agnostic).
        ADDR_W   : natural := 10;
        -- mp_arbiter s_master width (must match the arbiter's MW).
        MW       : natural := 2
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- slave port (behind mp_arbiter; enables active-high, we resv-gated)
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(ADDR_W-1 downto 0);   -- word offset
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        master : in  std_logic_vector(MW-1 downto 0); -- granted master (arbiter)

        -- deglitched peripheral IRQ levels (MCU.vhd irq_deglitch). Since M19
        -- they terminate HERE - no tile fan-out.
        irq_in : in  std_logic_vector(NUM_SRCS-1 downto 0);

        -- one registered external-IRQ wire per hart -> IVT slot 85
        meip_out : out std_logic_vector(NHARTS-1 downto 0);

        -- D2 WDT hooks into SYSTEM0 (source 0 = IRQB_SYS_WDT)
        wdt_routed   : out std_logic;  -- OR of en[h](0): WDT deliverable somewhere
        wdt_complete : out std_logic   -- 1-mclk pulse on COMPLETE(0)
    );
end entity;

architecture behav of irq_router is

    -- routing/enable storage as NUM_EN_WORDS 32-bit words per hart. NUM_EN_WORDS =
    -- ceil(NUM_SRCS/32): 3 (L/M/U) at NUM_SRCS <= 96 (Castalia default 85,
    -- +I3C 94), 4 (L/M/U/X) at NUM_SRCS = 98 (digperiphs #3 NFC pushes the
    -- source list past 96 -> a 4th enable word per hart uses the +3 row slot
    -- that was reserved). Only the top word's low NUM_SRCS-32*(NUM_EN_WORDS-1)
    -- bits are live. At NUM_EN_WORDS = 3 every expression below is identical to
    -- the historic hardcoded-3 form.
    constant NUM_EN_WORDS : natural := (NUM_SRCS + 31) / 32;
    type en_words_t is array(0 to NHARTS*NUM_EN_WORDS-1) of std_logic_vector(31 downto 0);
    signal en_words  : en_words_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- M19 delivery state: one global in_service bit per source (the PLIC
    -- gateway) + the registered per-hart meip lines
    signal in_service : std_logic_vector(NUM_SRCS-1 downto 0);
    signal meip_r     : std_logic_vector(NHARTS-1 downto 0);
    signal wdt_cpl_r  : std_logic;

    -- fixed word offsets of the M19 block (byte = 0x7000 + 4*word)
    constant W_CLAIM  : natural := 512;  -- 0x7800
    constant W_PENDL  : natural := 516;  -- 0x7810
    constant W_PENDM  : natural := 517;
    constant W_PENDU  : natural := 518;
    constant W_INSVCL : natural := 520;  -- 0x7820
    constant W_INSVCM : natural := 521;
    constant W_INSVCU : natural := 522;

    constant CLAIM_NONE : std_logic_vector(31 downto 0) := (others => '1');
    -- COMPLETE bounds check: a legal source ID fits 7 bits (NUM_SRCS <= 127)
    constant CPL_HI_ZERO : std_logic_vector(31 downto 7) := (others => '0');

    function lane_merge(cur   : std_logic_vector(31 downto 0);
                        wd    : std_logic_vector(31 downto 0);
                        lanes : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable r : std_logic_vector(31 downto 0);
    begin
        r := cur;
        for l in 0 to 3 loop
            if lanes(l) = '1' then
                r((l+1)*8-1 downto l*8) := wd((l+1)*8-1 downto l*8);
            end if;
        end loop;
        return r;
    end function;

    -- 32-bit RO slice of a NUM_SRCS-wide status vector (word 0/1/2)
    function status_word(vec : std_logic_vector; word : natural)
        return std_logic_vector is
        variable r : std_logic_vector(31 downto 0) := (others => '0');
    begin
        for b in 0 to 31 loop
            if word*32 + b <= vec'high then
                r(b) := vec(word*32 + b);
            end if;
        end loop;
        return r;
    end function;

begin

    rdata <= rdata_reg;
    meip_out <= meip_r;
    wdt_complete <= wdt_cpl_r;

    -- D2: quasi-static "WDT routed anywhere" reduction for SYSTEM0
    wdt_routed_proc: process(en_words)
        variable v : std_logic;
    begin
        v := '0';
        for h in 0 to NHARTS-1 loop
            v := v or en_words(h*NUM_EN_WORDS)(0);
        end loop;
        wdt_routed <= v;
    end process;

    -- coverage asserts (elaboration-time constant conditions; no hardware)
    assert 2**ADDR_W > W_INSVCU
        report "irq_router: ADDR_W too small for the M19 CLAIM block"
        severity failure;
    assert 4*NHARTS <= W_CLAIM
        report "irq_router: NHARTS rows collide with the CLAIM block"
        severity failure;
    assert NUM_SRCS <= 127
        report "irq_router: COMPLETE bounds check assumes 7-bit source IDs"
        severity failure;

    -- Registered per-hart meip reduction over the PERIPHERAL sources only
    -- (the CLINT source IDs CLINT_SIP/CLINT_TIP = 83/84 are delivered per-hart
    -- by the hardwired msip/mtip wires, never through meip; every other source
    -- 0..NUM_SRCS-1 is routable — digperiphs #2, was "the top two sources").
    meip_proc: process(clk, resetn)
        variable v : std_logic;
    begin
        if resetn = '0' then
            meip_r <= (others => '0');
        elsif rising_edge(clk) then
            for h in 0 to NHARTS-1 loop
                v := '0';
                for i in 0 to NUM_SRCS-1 loop
                    if i /= CLINT_SIP and i /= CLINT_TIP then
                        v := v or (irq_in(i) and en_words(h*NUM_EN_WORDS + i/32)(i mod 32)
                                   and not in_service(i));
                    end if;
                end loop;
                meip_r(h) <= v;
            end loop;
        end if;
    end process;

    router_proc: process(clk, resetn)
        variable widx : integer range 0 to 2**ADDR_W - 1;
        -- row index can exceed NHARTS-1 (dead rows read 0, ignore writes)
        variable hidx : integer range 0 to 2**ADDR_W / 4;
        variable wsub : integer range 0 to 3;
        variable rd   : std_logic_vector(31 downto 0);
        variable wv   : std_logic_vector(31 downto 0);
        variable cid  : integer range 0 to NUM_SRCS;
        variable mst  : integer range 0 to 2**MW - 1;
    begin
        if resetn = '0' then
            en_words   <= (others => (others => '0'));  -- all masked: NO-OP
            in_service <= (others => '0');
            rdata_reg  <= (others => '0');
            wdt_cpl_r  <= '0';
        elsif rising_edge(clk) then
            wdt_cpl_r <= '0';  -- pulse default
            if en = '1' then
                widx := conv_integer(addr);
                hidx := widx / 4;
                wsub := widx mod 4;
                rd   := (others => '0');

                if widx < W_CLAIM then
                    -- ---- M7a routing rows (addresses/packing unchanged;
                    -- read returns the pre-write value on a write strobe) ---
                    if hidx < NHARTS and wsub < NUM_EN_WORDS then
                        rd := en_words(hidx*NUM_EN_WORDS + wsub);
                        if we /= "0000" then
                            wv := lane_merge(en_words(hidx*NUM_EN_WORDS + wsub), wdata, we);
                            if wsub = NUM_EN_WORDS-1 then
                                -- top enable word: only the low
                                -- NUM_SRCS-32*(NUM_EN_WORDS-1) bits are live —
                                -- store masked so readback matches the
                                -- documented "upper bits read 0" (at NUM_EN_WORDS=3
                                -- this is HhENU's historic wv(31 downto NUM_SRCS-64))
                                wv(31 downto NUM_SRCS-32*(NUM_EN_WORDS-1)) := (others => '0');
                            end if;
                            en_words(hidx*NUM_EN_WORDS + wsub) <= wv;
                        end if;
                    end if;
                    rdata_reg <= rd;

                elsif widx = W_CLAIM then
                    if we = "0000" then
                        -- ---- CLAIM: atomic lowest-ID search for the READING
                        -- hart (arbiter-serialized => race-free) ------------
                        mst := conv_integer(master);
                        cid := NUM_SRCS;  -- none
                        if mst < NHARTS then
                            for i in 0 to NUM_SRCS-1 loop
                                if cid = NUM_SRCS
                                   and i /= CLINT_SIP and i /= CLINT_TIP
                                   and irq_in(i) = '1'
                                   and en_words(mst*NUM_EN_WORDS + i/32)(i mod 32) = '1'
                                   and in_service(i) = '0' then
                                    cid := i;
                                end if;
                            end loop;
                        end if;
                        if cid < NUM_SRCS then
                            in_service(cid) <= '1';
                            rdata_reg <= conv_std_logic_vector(cid, 32);
                        else
                            rdata_reg <= CLAIM_NONE;  -- spurious: just iret
                        end if;
                    else
                        -- ---- COMPLETE: clear the gateway. Unqualified by
                        -- owner (recovery); IDs >= NUM_SRCS ignored (so a
                        -- stashed CLAIM_NONE completes as a no-op) ----------
                        if wdata(31 downto 7) = CPL_HI_ZERO
                           and conv_integer(wdata(6 downto 0)) < NUM_SRCS then
                            in_service(conv_integer(wdata(6 downto 0))) <= '0';
                            if conv_integer(wdata(6 downto 0)) = 0 then
                                wdt_cpl_r <= '1';  -- D2: WDT end-of-interrupt
                            end if;
                        end if;
                        rdata_reg <= (others => '0');
                    end if;

                else
                    -- ---- RO status words --------------------------------
                    case widx is
                        when W_PENDL  => rd := status_word(irq_in, 0);
                        when W_PENDM  => rd := status_word(irq_in, 1);
                        when W_PENDU  => rd := status_word(irq_in, 2);
                        when W_INSVCL => rd := status_word(in_service, 0);
                        when W_INSVCM => rd := status_word(in_service, 1);
                        when W_INSVCU => rd := status_word(in_service, 2);
                        when others   => rd := (others => '0');
                    end case;
                    rdata_reg <= rd;
                end if;
            end if;
        end if;
    end process;

end architecture;
