-- VestaRV: clock-domain-crossing synchroniser
-- DEPTH flops in series per bit, one process, asynchronous reset, nothing combinational between stages. The house cell for carrying a signal into this clock domain.
-- areset is ACTIVE LOW, which is the tree's convention and not the name's: every reset port in hdl/common and hdl/common/periph is `resetn : in std_logic`, asynchronous and active low, with no exception, so an instance wires its own resetn straight across. The port name is the owner's.
-- WIDTH is a bundle of INDEPENDENT chains, not a bus: bit k never touches bit j. Use it for unrelated single-bit signals or for a gray-coded bus. Never for a multi-bit binary bus, whose bits resolve on different edges and can present a word that was never sent.
-- ASYNC_REG / DONT_TOUCH / KEEP are declared in the architecture, not in a flow script, so every tool that reads this file sees them: Vivado keeps the chain in one slice, Genus refuses to merge, duplicate or retime the stages.
-- The crossing still needs a timing exception the RTL cannot state (set_false_path or set_clock_groups onto stage(0)'s D); that belongs in the Genus tcl, as the TRNG's does.

library ieee;
use ieee.std_logic_1164.all;

entity sync is
    generic (
        -- Independent single-bit chains carried side by side.
        WIDTH   : positive := 1;

        -- Flops in series per bit. 2 is the classic two-flop synchroniser; go
        -- to 3 where the MTBF budget or the clock ratio asks for it.
        DEPTH   : positive := 2;

        -- Reset value of EVERY stage, so q is stable from the first edge.
        -- The null vector means all zeros; anything else must be WIDTH bits.
        RST_VAL : std_logic_vector := ""
    );
    port (
        clk    : in  std_logic;                              -- destination domain
        areset : in  std_logic;                              -- asynchronous, ACTIVE LOW
        d      : in  std_logic_vector(WIDTH - 1 downto 0);   -- source domain, unconstrained in time
        q      : out std_logic_vector(WIDTH - 1 downto 0)    -- DEPTH clk edges behind d
    );
end entity sync;

architecture rtl of sync is

    -- RST_VAL defaults to the null vector; normalise it to WIDTH bits indexed
    -- from WIDTH-1 downto 0, so the caller may pass any bounds or a literal.
    function normRst(v : std_logic_vector) return std_logic_vector is
        variable r : std_logic_vector(WIDTH - 1 downto 0) := (others => '0');
    begin
        -- Positional, leftmost to leftmost, whatever the caller's bounds: a
        -- bare literal binds with ascending bounds, so "100" must still mean
        -- bit 2 set. Indexing from v'low would reverse it.
        if v'length = WIDTH then
            r := v;
        end if;
        return r;
    end function;

    constant RST_EFF : std_logic_vector(WIDTH - 1 downto 0) := normRst(RST_VAL);

    type stage_arr is array (natural range <>) of std_logic_vector(WIDTH - 1 downto 0);

    -- The chain itself. stage(0) is the sampling flop, stage(DEPTH-1) drives q.
    signal stage : stage_arr(0 to DEPTH - 1);

    /* ---- synthesis attributes -------------------------------------------
       Attribute names are case insensitive in VHDL, so one declaration serves
       Vivado's ASYNC_REG/DONT_TOUCH/KEEP and Genus's dont_touch alike.
       ASYNC_REG is the FPGA half (hdl/fpga): it tells Vivado these flops may go
       metastable, which places them in one slice and bars SRL inference and
       retiming. DONT_TOUCH and KEEP are the ASIC half: they stop Genus merging
       two stages into one, duplicating a stage for fanout, or retiming logic
       across the chain, any of which destroys the settling time the chain is
       for. Genus retiming is off in this flow already (no set_db retime in
       genus/), so the attribute is the belt and not the trousers. */
    attribute ASYNC_REG  : string;
    attribute DONT_TOUCH : string;
    attribute KEEP       : string;

    attribute ASYNC_REG  of stage : signal is "TRUE";
    attribute DONT_TOUCH of stage : signal is "true";
    attribute KEEP       of stage : signal is "true";

begin

    -- Both are static, so they fire at elaboration and not at time 0 of a run.
    assert DEPTH >= 2
        report "sync: DEPTH must be at least 2, got " & integer'image(DEPTH)
        severity failure;

    assert RST_VAL'length = 0 or RST_VAL'length = WIDTH
        report "sync: RST_VAL must be null or WIDTH bits, got "
               & integer'image(RST_VAL'length) & " for WIDTH "
               & integer'image(WIDTH)
        severity failure;

    /* One process, no logic between stages: the whole point of the block is
       that stage(i)'s D pin is stage(i-1)'s Q pin and nothing else, so the
       stage has the full clock period to settle. The loop is per index and
       therefore per bit; nothing crosses from bit to bit. */
    chain : process (clk, areset)
    begin
        if areset = '0' then
            stage <= (others => RST_EFF);
        elsif rising_edge(clk) then
            stage(0) <= d;
            for i in 1 to DEPTH - 1 loop
                stage(i) <= stage(i - 1);
            end loop;
        end if;
    end process chain;

    q <= stage(DEPTH - 1);

end architecture rtl;
