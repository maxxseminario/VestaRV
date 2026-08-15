-- =============================================================================
-- irq_router.vhd  (M7a fan-out matrix; M19 PLIC-lite claim/complete rework)
-- =============================================================================
-- THE peripheral interrupt controller: per-hart routing and enable rows (the M7a programming model, addresses unchanged) plus a PLIC-style CLAIM/COMPLETE delivery stage (M19).
-- Before M19 this block was a pure fan-out matrix: NHARTS x NUM_SRCS enable wires to the tiles, and the full deglitched vector at every tile boundary.
-- At Argus N=18 that cost about 258 inbound IRQ boundary flops PER TILE and about 3.1k assembly nets.
-- M19 collapses delivery to ONE registered meip wire per hart:
--
--   meip(h) = OR over peripheral sources i of
--             ( level(i) AND en[h](i) AND NOT in_service(i) )
--
-- and software discovers and settles the source through CLAIM/COMPLETE:
--   * CLAIM (read 0x7800) atomically returns the LOWEST pending source ID enabled for the READING hart, attributed by the arbiter's s_master, which is the mutex-bank idiom.
--     It also sets in_service(id), masking the source out of EVERY hart's meip until it is completed, which is exactly-once delivery: two harts routed to the same source can never both take it, and the M7a "un-route yourself" software dance is retired.
--     It returns x"FFFFFFFF" (CLAIM_NONE) when nothing is pending for the reader, and the dispatcher treats that as spurious and simply irets.
--   * COMPLETE (write the source ID to 0x7800) clears in_service(id).
--     It is owner-UNQUALIFIED by design, following the mutex-release recovery precedent: any hart can complete a hung hart's claim.
--     IDs at or above NUM_SRCS are ignored, so completing a stashed CLAIM_NONE is a harmless no-op.
--   * Level-source gateway semantics come for free: ISRs clear the LEVEL at the peripheral before the dispatcher completes, and if the level is still high at complete, i.e. a new event, the source simply re-pends.
--
-- The CLINT source IDs, slots 83 and 84 at the default source count, NEVER route through meip.
-- CLINT delivery is the per-hart hardwired msip and mtip wires, which is the bootrom park and loader contract and is untouched by M19.
-- Their row bits are writable but inert.
--
-- Priority is fixed: the lowest source ID wins, the same tie-break the in-core encoder used pre-M19.
-- A chatty low-ID source can starve high IDs on the same hart, an accepted v1 limitation and the same property the old scheme had.
--
-- PLACEMENT: page 3 of the shared peripheral window at 0x7000 (M11), as a native arbiter slave.
-- REGISTER MAP, byte address = 0x7000 + 4*word, with ADDR_W=10 decoding the full page since M19, so the old 256B aliasing is GONE:
--   word 4h+0 : HhENL = en[h](31:0)    for hart h  (h = 0..NHARTS-1)  RW
--   word 4h+1 : HhENM = en[h](63:32)                                  RW
--   word 4h+2 : HhENU = en[h](84:64)   (bits 20:0; CONTIGUOUS packing
--               both ways; bits 19 and 20 are the CLINT slots, inert)  RW
--   word 4h+3 : HhENX = en[h](NUM_SRCS-1:96) when NUM_SRCS > 96
--               (digperiphs #3: NFC sources 96 and 97; otherwise
--               reserved, reads 0). NUM_EN_WORDS = ceil(NUM_SRCS/32)
--               words per hart.                                       RW
--   word 512  : 0x7800 CLAIM (read, SIDE EFFECT) or COMPLETE (write)
--   word 516-519 : 0x7810/14/18/1C PENDL/M/U/X  = raw deglitched levels RO
--   word 520-523 : 0x7820/24/28/2C INSVCL/M/U/X = in_service bits       RO
--     (Stage E rider 2026-07-21 added PENDX and INSVCX, so the RO
--      readback now covers ALL sources 0..NUM_SRCS-1. At NUM_SRCS <= 96
--      the X words read 0, so the addition is invisible to
--      3-enable-word configs.)
--   Everything else reads 0 and ignores writes.
--   Row indices at or above NHARTS are dead: they read 0 and ignore writes, as at A2.
-- M19 row 0 is LIVE: hart 0 takes meip(0) like every tile, since SYSTEM0's vectored path is retired by the D1 unification.
--
-- WDT hooks (D2): wdt_routed, the OR over h of en[h](0), tells SYSTEM0 whether the watchdog IRQ is deliverable anywhere, which arms its reset-on-undeliverable behaviour.
-- wdt_complete pulses for one mclk on COMPLETE(0) and replaces SYSTEM0's falling_edge(isr_ret) end-of-interrupt hack.
--
-- BUS CONTRACT, the same as clint.vhd and mutex_bank.vhd: an active-high one-cycle en strobe (the arbiter serializes whole transactions, so claims are atomic for free), 4 active-high byte-lane strobes we (resv_unit-gated in MCU.vhd, because a suppressed SC write must not complete an IRQ either), an MW-wide granted-master index from mp_arbiter s_master, and a 1-cycle registered read: address at cycle T, rdata valid at T+1.
-- Row writes lane-merge; COMPLETE consumes the full word on any lane.
-- The block runs on the free-running mclk, so meip can wake a hart whose gated clk_cpu is OFF.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity irq_router is
    generic (
        NHARTS   : natural := 4;
        -- Peripheral SOURCE count: NUM_IRQ_SRCS, 85 by default and 94 with I3C.
        -- These are deglitched levels 0..NUM_SRCS-1, NOT the core's IVT slot count.
        NUM_SRCS : natural := 85;
        -- The two CLINT source IDs, msip and mtip, delivered per-hart on the hardwired wires and therefore NEVER routed through meip or claim.
        -- digperiphs #2 made them explicit, where they had been hardcoded as "the top two sources", so I3C sources can grow ABOVE the CLINT pair without inheriting the never-route treatment.
        -- Defaults 83 and 84 reproduce the historic behaviour at NUM_SRCS = 85, where the CLINT pair WAS the top two.
        CLINT_SIP : natural := 83;
        CLINT_TIP : natural := 84;
        -- Decoded word-address width, where 10 covers the full 4 KB page.
        -- M19 puts the CLAIM block at fixed word 512, byte 0x800, which is NHARTS-agnostic.
        ADDR_W   : natural := 10;
        -- mp_arbiter s_master width, which must match the arbiter's MW.
        MW       : natural := 2
    );
    port (
        clk    : in  std_logic;   -- Free-running mclk.
        resetn : in  std_logic;

        -- Slave port behind mp_arbiter: enables are active-high and we is resv-gated.
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(ADDR_W-1 downto 0);   -- Word offset.
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        master : in  std_logic_vector(MW-1 downto 0); -- Granted master index from the arbiter.

        -- Deglitched peripheral IRQ levels from MCU.vhd's irq_deglitch.
        -- Since M19 they terminate HERE, with no tile fan-out.
        irq_in : in  std_logic_vector(NUM_SRCS-1 downto 0);

        -- One registered external-IRQ wire per hart, delivered at IVT slot 85.
        meip_out : out std_logic_vector(NHARTS-1 downto 0);

        -- D2 WDT hooks into SYSTEM0, where source 0 is IRQB_SYS_WDT.
        wdt_routed   : out std_logic;  -- OR of en[h](0): the WDT is deliverable somewhere.
        wdt_complete : out std_logic   -- One-mclk pulse on COMPLETE(0).
    );
end entity;

architecture behav of irq_router is

    -- Routing and enable storage, held as NUM_EN_WORDS 32-bit words per hart.
    -- NUM_EN_WORDS = ceil(NUM_SRCS/32): 3 words (L, M, U) at NUM_SRCS <= 96, which covers the Castalia default of 85 and 94 with I3C, and 4 words (L, M, U, X) at NUM_SRCS = 98, where digperiphs #3 NFC pushes the source list past 96 and a fourth enable word per hart takes the +3 row slot that was reserved.
    -- Only the top word's low NUM_SRCS-32*(NUM_EN_WORDS-1) bits are live.
    -- At NUM_EN_WORDS = 3 every expression below is identical to the historic hardcoded-3 form.
    constant NUM_EN_WORDS : natural := (NUM_SRCS + 31) / 32;
    type en_words_t is array(0 to NHARTS*NUM_EN_WORDS-1) of std_logic_vector(31 downto 0);
    signal en_words  : en_words_t;
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- M19 delivery state: one global in_service bit per source, the PLIC gateway, plus the registered per-hart meip lines.
    signal in_service : std_logic_vector(NUM_SRCS-1 downto 0);
    signal meip_r     : std_logic_vector(NHARTS-1 downto 0);
    signal wdt_cpl_r  : std_logic;

    -- Fixed word offsets of the M19 block, where the byte address is 0x7000 + 4*word.
    constant W_CLAIM  : natural := 512;  -- 0x7800
    constant W_PENDL  : natural := 516;  -- 0x7810
    constant W_PENDM  : natural := 517;
    constant W_PENDU  : natural := 518;
    constant W_PENDX  : natural := 519;  -- 0x781C, sources 127:96, reads 0 below 97 sources.
    constant W_INSVCL : natural := 520;  -- 0x7820
    constant W_INSVCM : natural := 521;
    constant W_INSVCU : natural := 522;
    constant W_INSVCX : natural := 523;  -- 0x782C, sources 127:96, reads 0 below 97 sources.

    constant CLAIM_NONE : std_logic_vector(31 downto 0) := (others => '1');
    -- COMPLETE bounds check: a legal source ID fits in 7 bits, since NUM_SRCS is at most 127.
    constant CPL_HI_ZERO : std_logic_vector(31 downto 7) := (others => '0');

    -- Merge the written word into the current one, one byte lane at a time.
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

    -- One 32-bit read-only slice of a NUM_SRCS-wide status vector, zero-filled past the vector's top bit.
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

    -- D2: the quasi-static "WDT routed anywhere" reduction handed to SYSTEM0.
    wdt_routed_proc: process(en_words)
        variable v : std_logic;
    begin
        v := '0';
        for h in 0 to NHARTS-1 loop
            v := v or en_words(h*NUM_EN_WORDS)(0);
        end loop;
        wdt_routed <= v;
    end process;

    -- Shape asserts on elaboration-time constants: they generate no hardware.
    assert 2**ADDR_W > W_INSVCX
        report "irq_router: ADDR_W too small for the M19 CLAIM block"
        severity failure;
    assert 4*NHARTS <= W_CLAIM
        report "irq_router: NHARTS rows collide with the CLAIM block"
        severity failure;
    assert NUM_SRCS <= 127
        report "irq_router: COMPLETE bounds check assumes 7-bit source IDs"
        severity failure;

    -- Registered per-hart meip reduction over the PERIPHERAL sources only.
    -- The CLINT source IDs CLINT_SIP and CLINT_TIP, 83 and 84 by default, are delivered per-hart by the hardwired msip and mtip wires and never through meip.
    -- Every other source 0..NUM_SRCS-1 is routable: digperiphs #2, where this used to read "the top two sources".
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

    -- Slave port: one access per en strobe, decoded into the routing rows, the CLAIM/COMPLETE word, or the read-only status words.
    router_proc: process(clk, resetn)
        variable widx : integer range 0 to 2**ADDR_W - 1;
        -- The row index can exceed NHARTS-1: dead rows read 0 and ignore writes.
        variable hidx : integer range 0 to 2**ADDR_W / 4;
        variable wsub : integer range 0 to 3;
        variable rd   : std_logic_vector(31 downto 0);
        variable wv   : std_logic_vector(31 downto 0);
        variable cid  : integer range 0 to NUM_SRCS;
        variable mst  : integer range 0 to 2**MW - 1;
    begin
        if resetn = '0' then
            en_words   <= (others => (others => '0'));  -- All masked, so reset is a provable no-op.
            in_service <= (others => '0');
            rdata_reg  <= (others => '0');
            wdt_cpl_r  <= '0';
        elsif rising_edge(clk) then
            wdt_cpl_r <= '0';  -- Default low, so any assertion below is a single-cycle pulse.
            if en = '1' then
                widx := conv_integer(addr);
                hidx := widx / 4;
                wsub := widx mod 4;
                rd   := (others => '0');

                if widx < W_CLAIM then
                    -- ---- M7a routing rows, with addresses and packing unchanged.
                    -- A write strobe still returns the pre-write value on rdata. ---
                    if hidx < NHARTS and wsub < NUM_EN_WORDS then
                        rd := en_words(hidx*NUM_EN_WORDS + wsub);
                        if we /= "0000" then
                            wv := lane_merge(en_words(hidx*NUM_EN_WORDS + wsub), wdata, we);
                            if wsub = NUM_EN_WORDS-1 then
                                -- Top enable word: only the low NUM_SRCS-32*(NUM_EN_WORDS-1) bits are live.
                                -- Store it masked so readback matches the documented "upper bits read 0".
                                -- At NUM_EN_WORDS = 3 this is HhENU's historic wv(31 downto NUM_SRCS-64).
                                wv(31 downto NUM_SRCS-32*(NUM_EN_WORDS-1)) := (others => '0');
                            end if;
                            en_words(hidx*NUM_EN_WORDS + wsub) <= wv;
                        end if;
                    end if;
                    rdata_reg <= rd;

                elsif widx = W_CLAIM then
                    if we = "0000" then
                        -- ---- CLAIM: an atomic lowest-ID search for the READING hart.
                        -- The arbiter serializes whole transactions, so this is race-free. ------------
                        mst := conv_integer(master);
                        cid := NUM_SRCS;  -- Sentinel meaning nothing was found.
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
                            rdata_reg <= CLAIM_NONE;  -- Nothing pending: the dispatcher treats this as spurious and irets.
                        end if;
                    else
                        -- ---- COMPLETE: clear the gateway bit for this source.
                        -- It is unqualified by owner, which is what makes recovery possible.
                        -- IDs at or above NUM_SRCS are ignored, so a stashed CLAIM_NONE completes as a no-op. ----------
                        if wdata(31 downto 7) = CPL_HI_ZERO
                           and conv_integer(wdata(6 downto 0)) < NUM_SRCS then
                            in_service(conv_integer(wdata(6 downto 0))) <= '0';
                            if conv_integer(wdata(6 downto 0)) = 0 then
                                wdt_cpl_r <= '1';  -- D2: the WDT end-of-interrupt pulse.
                            end if;
                        end if;
                        rdata_reg <= (others => '0');
                    end if;

                else
                    -- ---- Read-only status words, and 0 for every unmapped address. ----
                    case widx is
                        when W_PENDL  => rd := status_word(irq_in, 0);
                        when W_PENDM  => rd := status_word(irq_in, 1);
                        when W_PENDU  => rd := status_word(irq_in, 2);
                        when W_PENDX  => rd := status_word(irq_in, 3);
                        when W_INSVCL => rd := status_word(in_service, 0);
                        when W_INSVCM => rd := status_word(in_service, 1);
                        when W_INSVCU => rd := status_word(in_service, 2);
                        when W_INSVCX => rd := status_word(in_service, 3);
                        when others   => rd := (others => '0');
                    end case;
                    rdata_reg <= rd;
                end if;
            end if;
        end if;
    end process;

end architecture;
