-- =============================================================================
-- resv_unit.vhd  (M4b)
-- =============================================================================
-- GLOBAL LR/SC reservation table for the shared-RAM window.
-- Sits between mp_arbiter's slave port and the shared RAM, on the FREE-RUNNING mclk.
--
-- WHY (see ~/vesta_docs/multicore_plan.md M4): vesta's reservation is a LOCAL flop (vesta.vhd reservation_proc), correct for one hart and silently wrong for four.
-- Two harts SC-ing the same word both pass their LOCAL check before the arbiter serializes their writes, so both report success.
-- The success of an SC to SHARED memory must therefore be adjudicated HERE, in the arbiter's serialization order, at the moment the SC's write transaction is granted:
--   * a dead SC's write is SUPPRESSED (s_we masked to all-zero, so the slave sees a read), and
--   * the fail flag is returned to the master alongside the arbiter's done (the tile latches it like sh_rdata_reg and feeds the core's sc_fail_ext, which folds into the SC rd result).
--
-- Table semantics (per master i):
--   * an LR read txn that completes sets resv[i] to that addr and marks it valid.
--   * any master j's committed write kills resv[i] for ALL i /= j with a matching addr, because a foreign write between i's LR and SC must make i's SC fail.
--     A master's own non-SC write also kills its own reservation: conservative but spec-legal, since SC is allowed to fail spuriously.
--   * an adjudicated SC txn by i is allowed when valid(i) is set and the addr matches.
--     resv[i] is always cleared, since an SC consumes the reservation whether it succeeds or fails, and a COMMITTED SC write kills other masters' matching reservations like any other write.
--
-- TIMING (locked to mp_arbiter's IDLE, LATCH, DATA sequence):
--   * s_en/s_we/s_addr are registered by the arbiter in IDLE and are asserted and valid during the LATCH cycle; gnt(cur) is held, so cur is known.
--   * s_we_gated is COMBINATIONAL during that cycle (pure mclk-domain inputs, no feedback), so the slave commits or skips the write at the LATCH-to-DATA edge.
--   * the table update and the sc_fail(cur) register both land at that same LATCH-to-DATA edge, and the arbiter pulses done(cur) in the DATA cycle, so sc_fail(i) is stable one full mclk cycle BEFORE the master samples done.
--     sc_fail(i) holds its value until master i's next adjudicated SC; the tile-side latch clears itself when the core steps off the shared address.
--
-- lr_sc context (per master, 2 bits): "01" means this txn is an LR read, "10" means this txn is an SC write attempt, "00" means a plain access.
-- It is driven by the core and stable for the whole txn, because the issuing core is frozen, and it is gated by the master's req in the tile/MCU wiring.
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity resv_unit is
    generic (
        N          : natural := 4;    -- number of masters (harts)
        ADDR_WIDTH : natural := 8     -- shared-window word-address width
    );
    port (
        clk     : in  std_logic;   -- free-running mclk (same as mp_arbiter)
        resetn  : in  std_logic;

        -- per-master transaction context (flattened; slice i = master i)
        lr_sc   : in  std_logic_vector(N*2-1 downto 0);
        gnt     : in  std_logic_vector(N-1 downto 0);   -- from mp_arbiter

        -- arbiter slave-side pass-through (tapped, then gated)
        s_en    : in  std_logic;
        s_we    : in  std_logic_vector(3 downto 0);
        s_addr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);

        s_we_gated : out std_logic_vector(3 downto 0);  -- to the shared RAM
        sc_fail    : out std_logic_vector(N-1 downto 0); -- valid with done(i)

        -- X1 Zawrs: per-master reservation-valid LEVEL.
        -- Exposes the exact snoop the SC path already relies on, so a hart stalled in wrs.nto or wrs.sto can wake when a FOREIGN committed store kills its reservation and resv_valid(i) falls.
        -- Registered on mclk here; the tile re-registers it across its depth-1 boundary alongside sc_fail, msip and mtip.
        -- This is a pure observation port: it changes no adjudication logic, so LR/SC/AMO behaviour is unaffected.
        resv_valid_o : out std_logic_vector(N-1 downto 0)
    );
end entity;

architecture behav of resv_unit is

    type addr_arr is array (0 to N-1) of std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal resv_addr  : addr_arr := (others => (others => '0'));
    signal resv_valid : std_logic_vector(N-1 downto 0) := (others => '0');
    signal sc_fail_r  : std_logic_vector(N-1 downto 0) := (others => '0');

    -- Current granted master (one-hot gnt decoded to an index) and its txn context.
    signal cur        : natural range 0 to N-1;
    signal cur_lr     : std_logic;   -- this txn is an LR read
    signal cur_sc     : std_logic;   -- this txn is an SC write attempt
    signal sc_allowed : std_logic;   -- SC adjudication (pre-state)
    signal is_write   : std_logic;   -- any lane strobe set (pre-gating)

begin

    -- Decode the one-hot grant to an index; it reads 0 when nothing is granted, which is harmless because every use is qualified by s_en.
    process(gnt)
        variable idx : natural range 0 to N-1;
    begin
        idx := 0;
        for i in 0 to N-1 loop
            if gnt(i) = '1' then
                idx := i;
            end if;
        end loop;
        cur <= idx;
    end process;

    -- Decode the granted master's 2-bit LR/SC context slice.
    cur_lr <= '1' when lr_sc((cur+1)*2-1 downto cur*2) = "01" else '0';
    cur_sc <= '1' when lr_sc((cur+1)*2-1 downto cur*2) = "10" else '0';

    -- Any lane strobe means a write, and an SC is allowed only against a live matching reservation.
    is_write   <= '1' when s_we /= "0000" else '0';
    sc_allowed <= '1' when resv_valid(cur) = '1' and resv_addr(cur) = s_addr
                  else '0';

    -- Write suppression: a dead SC's write must not commit.
    -- This is combinational, which is safe because all inputs are mclk-domain registered arbiter outputs with no feedback.
    s_we_gated <= (others => '0') when (cur_sc = '1' and sc_allowed = '0')
                  else s_we;

    -- Reservation table and SC verdict, updated at the LATCH-to-DATA edge.
    -- s_en is high for exactly the LATCH cycle.
    table: process(clk, resetn)
    begin
        if resetn = '0' then
            resv_valid <= (others => '0');
            resv_addr  <= (others => (others => '0'));
            sc_fail_r  <= (others => '0');
        elsif rising_edge(clk) then
            if s_en = '1' then
                if cur_sc = '1' then
                    -- SC attempt: adjudicate against the pre-state, and consume the reservation either way.
                    sc_fail_r(cur)  <= not sc_allowed;
                    resv_valid(cur) <= '0';
                    if sc_allowed = '1' then
                        -- A committed SC write kills every other matching reservation.
                        for i in 0 to N-1 loop
                            if i /= cur and resv_valid(i) = '1'
                               and resv_addr(i) = s_addr then
                                resv_valid(i) <= '0';
                            end if;
                        end loop;
                    end if;
                elsif is_write = '1' then
                    -- Plain committed write: kill EVERY matching reservation.
                    -- Killing a foreign one is required; killing the writer's own is conservative but spec-legal.
                    for i in 0 to N-1 loop
                        if resv_valid(i) = '1' and resv_addr(i) = s_addr then
                            resv_valid(i) <= '0';
                        end if;
                    end loop;
                elsif cur_lr = '1' then
                    -- LR read: place the reservation on this address.
                    resv_valid(cur) <= '1';
                    resv_addr(cur)  <= s_addr;
                end if;
            end if;
        end if;
    end process;

    sc_fail <= sc_fail_r;

    -- X1 Zawrs: expose the reservation-valid table as a level (Zawrs wake source).
    resv_valid_o <= resv_valid;

end architecture;
