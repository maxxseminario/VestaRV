/* Synthesis BLACK BOXES for the cells `ghdl --synth` must not look inside.

   WHAT A BLACK BOX IS HERE, AND WHY THE GATE NEEDS ONE.
   hdl/common/MCU.vhd and hdl/common/hart_tile.vhd instantiate three compiled
   memory macros and three analog cells by direct `entity work.<name>`
   association, so every one of them has to be a design unit in the library
   before the instantiating unit is analyzed.  In the physical flow those six
   are not HDL at all: genus reads their timing libraries and elaborates them
   as blackboxes (`set_db hdl_error_on_blackbox false`,
   genus/MCU_WOUND/tcl/MCU_WOUND_hier.genus.tcl:163), and the only HDL that
   exists for them is BEHAVIOURAL -- hdl/common/sim/ARM_IP_RAM.vhd and
   hdl/common/sim/ARM_IP_ROM.vhd for the macros (untracked, hidden by the
   .gitignore `*ARM*` pattern, so no hermetic target can name them), and the
   _behav / _simulation models in hdl/common/sim/ for the analog cells.  Those
   models are not synthesizable and are not meant to be: the oscillator's
   architecture is a `wait for` loop, and an 8 KiB array modelled as RTL would
   census as 65536 flop bits of silicon that does not exist.

   THE CONTRACT EACH STUB KEEPS.  Port names, directions and widths match the
   real cell exactly -- an MCU that names a pin no macro has still fails at
   analysis, which is the direction that matters.  Every output is DRIVEN, to
   a constant: an undriven output raises -Wnowrite naming the port, which
   toolchains/ghdl/synth_census.py treats as fatal.  Nothing is registered, so
   a stub contributes no flop and no latch to any census row.

   WHAT A STUB CANNOT CATCH, stated so it is not mistaken for coverage: a port
   list changed on the real macro and not mirrored here leaves the gate green,
   the same limitation opensource_sim/mcu/mem_macros_sim.vhd documents for the
   behavioural models.  The census freezes the blackbox list per target
   (`blackboxes` in toolchains/ghdl/synth_census.json), so a cell cannot be
   added to this file and quietly removed from a graded hierarchy.

   THIS FILE IS DELIBERATELY OUTSIDE //hdl:vhdl_sources.  hdl/common/synth is
   a bazel package, and //hdl:vhdl_sources is a glob rooted at hdl/ that does
   not descend into a subpackage, so no simulation source list can reach these
   stubs by accident.  They are named directly, by path, only by the
   ghdl_synth_test targets in this package's BUILD file. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 8 KiB single-port TCM macro, one per hart_tile (hart_tile.vhd:821).
entity sram1p8k_hvt_pg is
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        WEN  : in  std_logic_vector(3 downto 0);
        A    : in  std_logic_vector(10 downto 0);
        D    : in  std_logic_vector(31 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        GWEN : in  std_logic;
        RETN : in  std_logic;
        PGEN : in  std_logic
    );
end sram1p8k_hvt_pg;

architecture blackbox of sram1p8k_hvt_pg is
begin
    Q <= (others => '0');
end architecture blackbox;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 16 KiB single-port macro: the shared RAM banks and the NPU staging RAM.
entity sram1p16k_hvt_pg is
    generic (
        INIT_FILE : string := ""
    );
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        WEN  : in  std_logic_vector(3 downto 0);
        A    : in  std_logic_vector(11 downto 0);
        D    : in  std_logic_vector(31 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        GWEN : in  std_logic;
        RETN : in  std_logic;
        PGEN : in  std_logic
    );
end sram1p16k_hvt_pg;

architecture blackbox of sram1p16k_hvt_pg is
begin
    Q <= (others => '0');
end architecture blackbox;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 2048 x 32 mask boot ROM at rom0, read only.
entity rom2k_hvt_pg is
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        A    : in  std_logic_vector(10 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        PGEN : in  std_logic
    );
end rom2k_hvt_pg;

architecture blackbox of rom2k_hvt_pg is
begin
    Q <= (others => '0');
end architecture blackbox;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

/* The current-starved ring oscillator, instance dco0.  The tracked model
   hdl/common/sim/OscillatorCurrentStarved_simulation.vhd drives ClkOut from a
   `wait for ClkDCODelay` loop, which has no synthesis meaning at all. */
entity OscillatorCurrentStarved is
    port (
        Reset  : in  std_logic;
        En     : in  std_logic;
        Freq   : in  std_logic_vector(11 downto 0);
        ClkOut : out std_logic
    );
end OscillatorCurrentStarved;

architecture blackbox of OscillatorCurrentStarved is
begin
    ClkOut <= '0';
end architecture blackbox;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The power-on reset cell, instance por.
entity PowerOnResetCheng is
    port (
        resetn_in  : in  std_logic;
        resetn_out : out std_logic
    );
end PowerOnResetCheng;

architecture blackbox of PowerOnResetCheng is
begin
    resetn_out <= '0';
end architecture blackbox;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The analog IRQ deglitch filter, instance irq_gf0.
entity GlitchFilter is
    port (
        IrqGlitchy    : in  std_logic_vector(31 downto 0);
        IrqDeglitched : out std_logic_vector(31 downto 0)
    );
end GlitchFilter;

architecture blackbox of GlitchFilter is
begin
    IrqDeglitched <= (others => '0');
end architecture blackbox;
