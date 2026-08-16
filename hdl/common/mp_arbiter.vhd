/* =============================================================================
   mp_arbiter.vhd: round-robin serializing arbiter, N masters (harts) onto ONE single-port shared slave.
   Exactly one master is granted at a time and the grant is held for its whole multi-cycle transaction, so a data cycle can never latch another master's access.
   Runs on the free-running mclk, never a hart's gated clk_cpu, because a hart gated off by its own stall cannot clock its own release.
   Slave model: synchronous single port, address and enable at cycle T and read data at T+1; s_en/s_we are active-high here, so invert at an active-low SRAM macro.
   Handshake per master i: req(i) is held until done(i); we is four active-high byte lanes ("0000" is a read); addr/wdata/we are sampled at grant; done(i) pulses for one cycle with rdata valid, and the hart holds its mem_ready low until it lands.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mp_arbiter is
    generic (
        N          : natural := 4;    -- number of masters (harts)
        ADDR_WIDTH : natural := 12;   -- shared-slave address width
        DATA_WIDTH : natural := 32;
        -- Width of the s_master export; 2**MW must be >= N (asserted below)
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
        -- Grant locking for cross-hart AMO atomicity: lock(i) high means master i is inside a read-modify-write pair, so a completing READ pins the bus to it until its follow-up WRITE completes.
        -- A dropped lock is the release valve for the case where that write can never issue, e.g. the core diverted to a trap.
        lock   : in  std_logic_vector(N-1 downto 0) := (others => '0');
        gnt    : out std_logic_vector(N-1 downto 0);
        done   : out std_logic_vector(N-1 downto 0);
        rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- Shared single-port slave side: enables are active-high and s_we carries per-byte lane strobes, so invert for the active-low WEN of a real SRAM macro.
        -- s_master: the granted master's index, registered at the IDLE pick alongside s_addr and valid for the whole transaction, so a slave can attribute an access to a hart (the mutex bank's claim-read needs it).
        s_en     : out std_logic;
        -- Slave-side stall: held high during LATCH it keeps the arbiter there with the grant pinned and s_addr/s_wdata presented, deferring done/rdata; a one-cycle slave leaves it at its '0' default.
        -- Only for a multi-cycle slave that always synthesizes its own completion (the TCM apertures answer for a dark tile); NEVER wire it to a slave that can wait forever.
        s_stall  : in  std_logic := '0';
        s_master : out std_logic_vector(MW-1 downto 0);
        s_we    : out std_logic_vector(3 downto 0);
        s_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        s_wdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
        s_rdata : in  std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity;

architecture behav of mp_arbiter is

    -- The grant is held across every state, which is what makes a transaction atomic.
    -- IDLE picks the round-robin winner and presents the access; LATCH is the slave's read-latency bubble; DATA captures s_rdata, pulses done and advances the pointer; LOCKED holds the bus for a locked master's follow-up write.
    type state_t is (IDLE, LATCH, DATA, LOCKED);
    signal state : state_t := IDLE;

    signal cur    : natural range 0 to N-1 := 0;   -- currently granted master
    signal rr_ptr : natural range 0 to N-1 := 0;   -- round-robin start pointer

    -- A just-served master's req is still stale-high at the next pick edge (its ack flop clears req a cycle after done), and picking it runs a ghost transaction whose done swallows that master's next real access.
    -- So a served master stays masked until its req is OBSERVED low: do not weaken this to a one-shot mask, which leaks ghosts as soon as the tile boundary is registered, and it cannot starve anyone since a real re-request always follows an observed-low window.
    signal need_release : std_logic_vector(N-1 downto 0) := (others => '0');

    -- Shadow of the granted transaction's lane strobes, because s_we is an out port and unreadable in -V200X
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

    -- The s_master export must be able to name every master; elaboration-time only, no hardware
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

            -- A served master becomes eligible again only once its req has been observed low.
            -- This runs before the FSM so DATA's set of need_release(cur) wins the edge.
            for k in 0 to N-1 loop
                if req(k) = '0' then
                    need_release(k) <= '0';
                end if;
            end loop;

            case state is
                -- IDLE: nobody owns the bus; pick a winner and launch its transaction
                when IDLE =>
                    gnt <= (others => '0');
                    -- Round-robin winner: the first requester at or after rr_ptr, skipping any master still awaiting release
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
                        -- Present the transaction; the slave samples s_en at the next edge and s_en self-clears, so it is a one-cycle strobe
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
                    -- The slave registered the access at the edge into this state and s_rdata is valid during this cycle, so just hold the grant.
                    gnt      <= (others => '0');
                    gnt(cur) <= '1';
                    -- A stalling slave holds us here; s_en has already self-cleared, so it still sees exactly one enable strobe and only the completion moves.
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
                    -- cur has been served, so mask its stale req until it is observed low
                    need_release(cur) <= '1';
                    -- A completed READ by a lock-holding master opens its read-modify-write section, so pin the bus to cur until its write lands.
                    -- A completed WRITE, locked or not, closes the section and releases normally.
                    if lock(cur) = '1' and cur_we = "0000" then
                        state <= LOCKED;
                    else
                        state <= IDLE;
                    end if;

                -- LOCKED: AMO critical section, bus pinned to cur
                when LOCKED =>
                    -- Wait for the locked master's follow-up write, serving no one else.
                    -- Its req is stale-high after the locked read's done, so only a fresh req, one that followed an observed-low window, is honored here.
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
