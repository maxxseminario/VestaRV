-- =============================================================================
-- mp_arbiter.vhd  (M3c)
-- =============================================================================
-- Round-robin, full-handshake SERIALIZING arbiter: N masters (harts) contend
-- for ONE single-port shared slave (shared-RAM window or shared peripheral).
--
-- WHY A SERIALIZER (see ~/vesta_docs/multicore_plan.md "GRANT-SWITCHING HAZARD"):
-- a shared access is a multi-cycle registered transaction. If grant switched
-- mid-transaction the data cycle would latch another master's access. This
-- arbiter therefore GRANTS ONE MASTER AT A TIME AND HOLDS THE GRANT UNTIL THE
-- WHOLE TRANSACTION COMPLETES, then advances the round-robin pointer. Shared
-- access is infrequent, so serialization is cheap.
--
-- CLOCKING: runs on the FREE-RUNNING mclk (NOT any hart's gated clk_cpu) so it
-- can release a stalled hart -- a hart gated off by its own stall can't clock
-- its own release. This matches the M2/M3 insight that the stall/arbiter source
-- must live on mclk.
--
-- SLAVE MODEL: a synchronous single-port memory with 1-cycle read latency --
-- address+enable presented on cycle T, read data valid on T+1 (matches the
-- sram1p16k behaviour). s_en/s_we are ACTIVE-HIGH here (arbiter-internal
-- convention); invert at the boundary when driving the active-low SRAM macro.
--
-- HANDSHAKE (per master i):
--   req(i)   in : master i wants the slave; HELD until it sees done(i).
--   we slice in : 4 ACTIVE-HIGH byte-lane strobes (M4a); "0000" = read,
--                 any lane '1' = write those lanes (wdata is lane-positioned
--                 by the core's store extender). Sampled at grant.
--   addr/wdata  : master i's address / write data (sampled at grant).
--   gnt(i)  out : master i currently owns the slave (held for the transaction).
--   done(i) out : 1 for exactly one cycle when master i's access completes;
--                 for a read, rdata is valid this cycle. Master drops req after.
--   rdata   out : shared return bus, valid for the granted master when done=1.
--
-- Maps to vesta later: on a shared-region access, hold that hart's
-- mem_ready = '0' until done(i) = '1' (one core cycle of release), untouched
-- for private accesses.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity mp_arbiter is
    generic (
        N          : natural := 4;    -- number of masters (harts)
        ADDR_WIDTH : natural := 12;   -- shared-slave address width
        DATA_WIDTH : natural := 32
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- master side (flattened: master i occupies bit i / slice i;
        -- we is 4 byte-lane strobes per master, active-high)
        req    : in  std_logic_vector(N-1 downto 0);
        we     : in  std_logic_vector(N*4-1 downto 0);
        addr   : in  std_logic_vector(N*ADDR_WIDTH-1 downto 0);
        wdata  : in  std_logic_vector(N*DATA_WIDTH-1 downto 0);
        gnt    : out std_logic_vector(N-1 downto 0);
        done   : out std_logic_vector(N-1 downto 0);
        rdata  : out std_logic_vector(DATA_WIDTH-1 downto 0);

        -- shared single-port slave side (active-high enables; s_we = per-byte
        -- lane strobes — invert for the active-low WEN of the real SRAM macro)
        s_en    : out std_logic;
        s_we    : out std_logic_vector(3 downto 0);
        s_addr  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        s_wdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
        s_rdata : in  std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end entity;

architecture behav of mp_arbiter is

    -- FSM (grant held across all three -> transaction-atomic):
    --   IDLE  : pick round-robin winner, present addr/en to the slave (cycle T)
    --   LATCH : bubble; the single-port slave registers the access at edge T+1
    --           (its 1-cycle read latency), s_rdata becomes valid in this cycle
    --   DATA  : capture s_rdata, pulse done(cur), advance round-robin (edge T+2)
    type state_t is (IDLE, LATCH, DATA);
    signal state : state_t := IDLE;

    signal cur    : natural range 0 to N-1 := 0;   -- currently granted master
    signal rr_ptr : natural range 0 to N-1 := 0;   -- round-robin start pointer

    -- slice helpers
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
            s_we    <= (others => '0');
            s_addr  <= (others => '0');
            s_wdata <= (others => '0');
        elsif rising_edge(clk) then
            -- defaults (single-cycle strobes clear themselves)
            done <= (others => '0');
            s_en <= '0';

            case state is
                when IDLE =>
                    gnt <= (others => '0');
                    -- round-robin winner: first requester at or after rr_ptr
                    winner := -1;
                    for k in 0 to N-1 loop
                        idx := (rr_ptr + k) mod N;
                        if winner = -1 and req(idx) = '1' then
                            winner := idx;
                        end if;
                    end loop;

                    if winner >= 0 then
                        cur          <= winner;
                        gnt(winner)  <= '1';
                        -- present the transaction to the slave this cycle; the
                        -- slave samples s_en at the next edge (s_en self-clears
                        -- via the default above, so it is a one-cycle strobe).
                        s_en         <= '1';
                        s_we         <= we_of(we, winner);
                        s_addr       <= addr_of(addr, winner);
                        s_wdata      <= wdata_of(wdata, winner);
                        state        <= LATCH;
                    end if;

                when LATCH =>
                    -- bubble: the slave registers the access at the edge entering
                    -- this state; s_rdata is valid during this cycle. Hold grant.
                    gnt      <= (others => '0');
                    gnt(cur) <= '1';
                    state    <= DATA;

                when DATA =>
                    -- capture read data and complete the transaction.
                    done(cur) <= '1';
                    rdata     <= s_rdata;
                    -- advance the round-robin pointer past the served master
                    if cur = N-1 then
                        rr_ptr <= 0;
                    else
                        rr_ptr <= cur + 1;
                    end if;
                    gnt   <= (others => '0');
                    gnt(cur) <= '1';   -- hold grant through its done cycle
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture;
