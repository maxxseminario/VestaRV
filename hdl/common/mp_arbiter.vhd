-- =============================================================================
-- mp_arbiter.vhd  (M3c)
-- =============================================================================
-- Round-robin, full-handshake SERIALIZING arbiter: N masters (harts) contend for ONE single-port shared slave (shared-RAM window or shared peripheral).
--
-- WHY A SERIALIZER (see ~/vesta_docs/multicore_plan.md "GRANT-SWITCHING HAZARD"): a shared access is a multi-cycle registered transaction.
-- If grant switched mid-transaction, the data cycle would latch another master's access.
-- This arbiter therefore GRANTS ONE MASTER AT A TIME AND HOLDS THE GRANT UNTIL THE WHOLE TRANSACTION COMPLETES, then advances the round-robin pointer.
-- Shared access is infrequent, so serialization is cheap.
--
-- CLOCKING: runs on the FREE-RUNNING mclk (NOT any hart's gated clk_cpu) so it can release a stalled hart, since a hart gated off by its own stall cannot clock its own release.
-- This matches the M2/M3 insight that the stall/arbiter source must live on mclk.
--
-- SLAVE MODEL: a synchronous single-port memory with 1-cycle read latency, address and enable presented on cycle T, read data valid on T+1 (matches the sram1p16k behaviour).
-- s_en/s_we are ACTIVE-HIGH here (arbiter-internal convention); invert at the boundary when driving the active-low SRAM macro.
-- CPR3/R3 added ONE optional escape from that model: `s_stall` (default '0'), which extends the LATCH bubble for a slave that genuinely cannot answer in one cycle.
-- It exists for the read-only TCM apertures and nothing else; see the port comment for the two properties that keep it from being a deadlock.
--
-- HANDSHAKE (per master i):
--   req(i)   in : master i wants the slave; HELD until it sees done(i).
--   we slice in : 4 ACTIVE-HIGH byte-lane strobes (M4a); "0000" is a read, any lane '1' writes those lanes (wdata is lane-positioned by the core's store extender). Sampled at grant.
--   addr/wdata  : master i's address and write data (sampled at grant).
--   gnt(i)  out : master i currently owns the slave (held for the transaction).
--   done(i) out : 1 for exactly one cycle when master i's access completes; for a read, rdata is valid this cycle. The master drops req after.
--   rdata   out : shared return bus, valid for the granted master when done=1.
--
-- Maps to vesta later: on a shared-region access, hold that hart's mem_ready = '0' until done(i) = '1' (one core cycle of release), untouched for private accesses.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mp_arbiter is
    generic (
        N          : natural := 4;    -- number of masters (harts)
        ADDR_WIDTH : natural := 12;   -- shared-slave address width
        DATA_WIDTH : natural := 32;
        -- A2 (Argus): s_master export width, must satisfy 2**MW >= N (checked by the coverage assert below).
        -- Default 2 is the Castalia 4-hart shape, so every existing instantiation is unchanged.
        MW         : natural := 2
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- Master side, flattened: master i occupies bit i or slice i, and we carries 4 active-high byte-lane strobes per master.
        req    : in  std_logic_vector(N-1 downto 0);
        we     : in  std_logic_vector(N*4-1 downto 0);
        addr   : in  std_logic_vector(N*ADDR_WIDTH-1 downto 0);
        wdata  : in  std_logic_vector(N*DATA_WIDTH-1 downto 0);
        -- M8 GRANT-LOCKING (cross-hart AMO atomicity): lock(i) high means master i is inside a read-modify-write pair (the core's amo_lock, asserted from the AMO dispatch through its write).
        -- When a READ transaction completes with the served master's lock high, the arbiter enters LOCKED: no other master is granted until that master's follow-up WRITE transaction completes.
        -- A dropped lock is the release valve for the case where the write can never issue, e.g. the core diverted to a trap.
        -- The all-zeros default reproduces pre-M8 behaviour.
        lock   : in  std_logic_vector(N-1 downto 0) := (others => '0');
        gnt    : out std_logic_vector(N-1 downto 0);
        done   : out std_logic_vector(N-1 downto 0);
        rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Shared single-port slave side: enables are active-high and s_we carries per-byte lane strobes, so invert for the active-low WEN of the real SRAM macro.
        -- s_master (M7c LOCKING): the granted master's index, registered at the IDLE pick alongside s_addr and valid for the whole transaction.
        -- It lets a slave attribute the access to a hart (the mutex_bank's claim-read needs to know WHO is reading).
        -- Its width is the MW generic (A2; it was fixed at 2, which capped N at 4).
        s_en     : out std_logic;
        -- =====================================================================
        -- CPR3/R3: SLAVE-SIDE STALL.
        -- It defaults to '0', so every existing instantiation (hdl/argus/MCU.vhd, the four testbenches, every non-orchestrator MCU.vhd) is bit-identical and need not name this port.
        -- Held HIGH during the LATCH cycle it keeps the arbiter in LATCH: grant stays pinned to the current master, s_addr/s_wdata stay presented, and done/rdata are simply deferred.
        -- It exists because the CPR3 TCM apertures are the FIRST slave that cannot answer in the one-cycle registered-read model everything else here obeys.
        -- A tcm_ext read of a tile's TCM is 6 mclk from request to done (CPR2 R4); without this the arbiter would complete the transaction on cycle 3 with whatever was on s_rdata and hand the management hart a fabricated word.
        -- Two properties make it safe rather than a deadlock risk: (a) nothing else can be granted while we wait, since the serializer was already going to hold the bus for this transaction, and (b) the only slave that asserts it MUST synthesize its own completion when its tile is dark (R4-A2), which is the requirement the aperture FSM is built around.
        -- NEVER wire this to a slave that can wait forever.
        s_stall  : in  std_logic := '0';
        s_master : out std_logic_vector(MW-1 downto 0);
        s_we    : out std_logic_vector(3 downto 0);
        s_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        s_wdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
        s_rdata : in  std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity;

architecture behav of mp_arbiter is

    -- FSM; the grant is held across all three states, which is what makes a transaction atomic.
    --   IDLE  : pick the round-robin winner, present addr and enable to the slave (cycle T)
    --   LATCH : bubble; the single-port slave registers the access at edge T+1 (its 1-cycle read latency) and s_rdata becomes valid in this cycle
    --   DATA  : capture s_rdata, pulse done(cur), advance the round-robin pointer (edge T+2)
    -- M8 adds LOCKED: after a grant-locked master's READ completes, wait there with the grant pinned to it until its follow-up WRITE request arrives (then serve it via LATCH and DATA as usual) or its lock drops.
    type state_t is (IDLE, LATCH, DATA, LOCKED);
    signal state : state_t := IDLE;

    signal cur    : natural range 0 to N-1 := 0;   -- currently granted master
    signal rr_ptr : natural range 0 to N-1 := 0;   -- round-robin start pointer

    -- M5a GHOST-TXN FIX, in its M10 latency-insensitive form.
    -- req(i) is HELD until done(i), and the master's ack flop (sh_acked) only clears req one mclk AFTER the done cycle, so after DATA the just-served master's req is still stalely '1' at the pick edge.
    -- Picking it re-runs a GHOST transaction whose done collides with, and swallows, that master's NEXT real access, so back-to-back shared memory instructions consume stale rdata (found by shspin's owner re-check in M5a).
    -- The original fix masked the served master for exactly ONE pick cycle (mask_last), which is correct ONLY at zero boundary latency: with N register stages on the tile boundary (M13) the stale window is 1+2N pick cycles and the one-shot mask leaks ghosts (proven by arb_lat_tb at N_DELAY>=1).
    -- M10 fix is WAIT-FOR-RELEASE: a served master stays masked until its req is OBSERVED low ("served, awaiting release"), which is latency-insensitive for ANY symmetric boundary depth and cycle-identical to mask_last at depth 0.
    -- A legitimate re-request always follows an observed-low window (the ack flop drops req for at least one cycle between transactions), so this can never starve anyone.
    signal need_release : std_logic_vector(N-1 downto 0) := (others => '0');

    -- M8: shadow of the granted transaction's lane strobes, needed because s_we is an out port and unreadable in -V200X.
    -- LOCKED is entered only after a READ ("0000") completes with lock(cur) high; a locked WRITE completing is the RMW pair's second half and releases normally.
    signal cur_we : std_logic_vector(3 downto 0) := (others => '0');

    -- Slice helpers: pull master i's field out of the flattened input vectors
    function addr_of(a : std_logic_vector; i : natural) return std_logic_vector is
    begin
        return a((i+1)*ADDR_WIDTH-1 downto i*ADDR_WIDTH);
    end function;

    function wdata_of(d : std_logic_vector; i : natural) return std_logic_vector is
    begin
        return d((i+1)*DATA_WIDTH-1 downto i*DATA_WIDTH);
    end function;

    function we_of(w : std_logic_vector; i : natural) return std_logic_vector is
    begin
        return w((i+1)*4-1 downto i*4);
    end function;

begin

    -- A2 coverage assert: the s_master export must be able to name every master (elaboration-time constant condition, no hardware).
    assert 2**MW >= N
        report "mp_arbiter: MW too small for N masters (2**MW must be >= N)"
        severity failure;

    -- Arbitration FSM and slave-side transaction driver, all on the free-running mclk
    process(clk, resetn)
        variable winner    : integer;
        variable idx       : natural;
    begin
        if resetn = '0' then
            state   <= IDLE;
            cur     <= 0;
            rr_ptr  <= 0;
            gnt     <= (others => '0');
            done    <= (others => '0');
            rdata   <= (others => '0');
            s_en    <= '0';
            s_master <= (others => '0');
            s_we    <= (others => '0');
            cur_we  <= (others => '0');
            s_addr  <= (others => '0');
            s_wdata <= (others => '0');
            need_release <= (others => '0');
        elsif rising_edge(clk) then
            -- Defaults: the single-cycle strobes clear themselves
            done <= (others => '0');
            s_en <= '0';

            -- Wait-for-release bookkeeping: a served master becomes eligible again only after its req has been OBSERVED low (see above).
            -- This runs before the FSM so DATA's set of need_release(cur) wins the edge; req(cur) is still held high there anyway.
            for k in 0 to N-1 loop
                if req(k) = '0' then
                    need_release(k) <= '0';
                end if;
            end loop;

            case state is
                -- IDLE: nobody owns the bus; pick a winner and launch its transaction
                when IDLE =>
                    gnt <= (others => '0');
                    -- Round-robin winner: the first requester at or after rr_ptr, skipping served-awaiting-release stale reqs (see above)
                    winner := -1;
                    for k in 0 to N-1 loop
                        idx := (rr_ptr + k) mod N;
                        if winner = -1 and req(idx) = '1'
                           and need_release(idx) = '0' then
                            winner := idx;
                        end if;
                    end loop;

                    if winner >= 0 then
                        cur          <= winner;
                        gnt(winner)  <= '1';
                        -- Present the transaction to the slave this cycle; the slave samples s_en at the next edge, and s_en self-clears via the default above so it is a one-cycle strobe.
                        s_en         <= '1';
                        s_master     <= conv_std_logic_vector(winner, MW);
                        s_we         <= we_of(we, winner);
                        cur_we       <= we_of(we, winner);
                        s_addr       <= addr_of(addr, winner);
                        s_wdata      <= wdata_of(wdata, winner);
                        state        <= LATCH;
                    end if;

                -- LATCH: one-cycle read-latency bubble, grant pinned
                when LATCH =>
                    -- The slave registers the access at the edge entering this state and s_rdata is valid during this cycle, so just hold the grant.
                    gnt      <= (others => '0');
                    gnt(cur) <= '1';
                    -- CPR3/R3: a stalling slave (the TCM apertures) holds us here.
                    -- s_en has already self-cleared, so the slave still sees exactly the one-cycle enable strobe it always did; only the completion moves.
                    -- Every other slave leaves s_stall at its '0' default and this is a no-op.
                    if s_stall = '0' then
                        state <= DATA;
                    end if;

                -- DATA: capture read data, complete the transaction, decide where to go next
                when DATA =>
                    done(cur) <= '1';
                    rdata     <= s_rdata;
                    -- Advance the round-robin pointer past the served master
                    if cur = N-1 then
                        rr_ptr <= 0;
                    else
                        rr_ptr <= cur + 1;
                    end if;
                    gnt   <= (others => '0');
                    gnt(cur) <= '1';   -- hold grant through its done cycle
                    -- Ghost-txn fix: cur has been served, so mask its stale req until it is observed low (latency-insensitive, see above)
                    need_release(cur) <= '1';
                    -- M8: a completed READ by a lock-holding master opens its RMW critical section, so pin the arbiter to cur until its write lands.
                    -- A completed WRITE, locked or not, closes the section and releases normally.
                    if lock(cur) = '1' and cur_we = "0000" then
                        state <= LOCKED;
                    else
                        state <= IDLE;
                    end if;

                -- LOCKED: AMO critical section, bus pinned to cur
                when LOCKED =>
                    -- Wait for the locked master's follow-up write, serving NO ONE ELSE.
                    -- The ghost-txn rule still applies: cur's req is stale-high after its locked READ's done, for 1+2N cycles under an N-deep boundary, so the same wait-for-release mask gates the re-entry.
                    -- Only a FRESH req, one that followed an observed-low window, is honored as the follow-up write.
                    gnt <= (others => '0');
                    if lock(cur) = '0' then
                        -- Release valve: the AMO flow ended without a write (trap or IRQ divert), and the bus must never deadlock.
                        state <= IDLE;
                    elsif req(cur) = '1' and need_release(cur) = '0' then
                        gnt(cur) <= '1';
                        s_en     <= '1';
                        s_master <= conv_std_logic_vector(cur, MW);
                        s_we     <= we_of(we, cur);
                        cur_we   <= we_of(we, cur);
                        s_addr   <= addr_of(addr, cur);
                        s_wdata  <= wdata_of(wdata, cur);
                        state    <= LATCH;
                    end if;
            end case;
        end if;
    end process;

end architecture;
