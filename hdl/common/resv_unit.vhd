/* =============================================================================
   resv_unit.vhd
   =============================================================================
   Global LR/SC reservation table for the shared-RAM window, between mp_arbiter's slave port and the shared RAM, on the free-running mclk.
   An SC to shared memory must be adjudicated here, in the arbiter's serialization order: a per-hart local reservation flop lets two harts pass their own check and both report success.
   A dead SC's write is suppressed (s_we masked to all-zero, so the slave sees a read) and its fail flag returns to the master alongside the arbiter's done, feeding the core's sc_fail_ext.
   An LR read places the reservation; an SC consumes it either way; any committed write kills every matching reservation, foreign ones because they must fail and the writer's own conservatively, which SC permits.
   lr_sc per master: "01" = LR read, "10" = SC write attempt, "00" = plain access, stable for the whole txn because the issuing core is frozen and it is gated by the master's req.
   ============================================================================= */

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

        -- Per-master reservation-valid level, the Zawrs wake source: a hart stalled in wrs.nto or wrs.sto wakes when a foreign committed store drops resv_valid(i).
        -- Pure observation port, registered on mclk here and re-registered across the tile's depth-1 boundary alongside sc_fail, msip and mtip.
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
    -- Combinational is safe here because every input is a registered mclk-domain arbiter output with no feedback.
    s_we_gated <= (others => '0') when (cur_sc = '1' and sc_allowed = '0')
                  else s_we;

    -- Reservation table and SC verdict, updated at the LATCH-to-DATA edge; s_en is high for exactly the LATCH cycle.
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

    -- sc_fail(i) settles a full mclk before the master samples done(i) and holds until that master's next adjudicated SC.
    sc_fail <= sc_fail_r;

    -- Expose the reservation-valid table as a level.
    resv_valid_o <= resv_valid;

end architecture;
