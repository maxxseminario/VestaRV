-- VestaRV: synthesis black boxes for the cells ghdl --synth must not look inside
-- MCU.vhd and hart_tile.vhd instantiate three compiled memory macros and three analog cells by direct entity work.<name> association, so each has to be a design unit before the instantiating unit is analyzed; the only other HDL for them is the non-synthesizable behavioural models in hdl/common/sim/.
-- Each stub mirrors the real cell's port names, directions and widths exactly and drives every output to a constant: an undriven output raises -Wnowrite, which toolchains/ghdl/synth_census.py treats as fatal. Nothing is registered, so a stub adds no flop or latch to a census row.
-- A port list changed on the real macro and not mirrored here leaves the gate green. The blackbox list is frozen per target in toolchains/ghdl/synth_census.json, so a cell cannot be added here and quietly dropped from a graded hierarchy.
-- hdl/common/synth is a bazel package and //hdl:vhdl_sources does not descend into a subpackage, so no simulation source list reaches these stubs: only the ghdl_synth_test targets in this package name them by path.

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

-- The current-starved ring oscillator, instance dco0. Its tracked model drives ClkOut from a wait-for loop, which has no synthesis meaning.
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
