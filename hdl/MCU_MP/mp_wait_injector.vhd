library IEEE;
use IEEE.std_logic_1164.all;

-- =============================================================================
-- mp_wait_injector — M2 stall exerciser (single-hart MCU_MP)
-- =============================================================================
-- Purpose: drive a core's `mem_ready` with real, repeating wait states so the
-- vesta clock-gating stall (mem_ready folded into en_clk_cpu) is exercised
-- end-to-end against the full ISA regression BEFORE the real shared-memory
-- arbiter exists. It is NOT the multi-core interconnect — M3 replaces it with
-- `mp_arbiter` (round-robin over shared RAM + peripherals). Keep it dev-only.
--
-- Timing contract (see sim/ClkGate.vhd): `mem_ready` is registered on the
-- free-running `mclk` (the ungated main clock — clk_cpu and every derived
-- clk_mem/clk_periph FREEZE when the core stalls, so the wait source must live
-- on mclk). The ClkGate samples en_clk_cpu during mclk's low phase, so a
-- registered mem_ready is glitch-free into the gate. Each mclk cycle with
-- mem_ready='1' advances the core one cycle; '0' freezes it.
--
-- Pattern: RUN_CYCLES cycles ready, then STALL_CYCLES cycles stalled, repeat.
-- Set STALL_CYCLES=0 to make it a permanent no-op (always ready).
-- =============================================================================
entity mp_wait_injector is
    generic (
        RUN_CYCLES   : natural := 4;   -- mclk cycles mem_ready held HIGH (accesses allowed)
        STALL_CYCLES : natural := 2    -- mclk cycles mem_ready held LOW  (core frozen)
    );
    port (
        mclk      : in  std_logic;
        resetn    : in  std_logic;
        mem_ready : out std_logic
    );
end entity;

architecture behave of mp_wait_injector is
    -- NOTE: RUN_CYCLES must be >= 1 (RUN_CYCLES=0 would hold mem_ready low forever
    -- and deadlock the core). Enforced by contract, not code.
    constant PERIOD : natural := RUN_CYCLES + STALL_CYCLES;
    signal phase : natural range 0 to PERIOD - 1;
begin

    -- Free-running modulo counter on mclk. mem_ready is registered from the
    -- *next* phase so the value presented during each mclk low phase already
    -- reflects the cycle the ClkGate is about to produce.
    process (mclk, resetn)
        variable next_phase : natural range 0 to PERIOD - 1;
    begin
        if resetn = '0' then
            phase     <= 0;
            mem_ready <= '1';                     -- ready out of reset (first fetch proceeds)
        elsif rising_edge(mclk) then
            if phase = PERIOD - 1 then
                next_phase := 0;
            else
                next_phase := phase + 1;
            end if;
            phase <= next_phase;
            if next_phase < RUN_CYCLES then
                mem_ready <= '1';
            else
                mem_ready <= '0';
            end if;
        end if;
    end process;

end architecture;
