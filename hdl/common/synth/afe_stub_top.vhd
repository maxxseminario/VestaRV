/* Synthesis top for afe_stub, whose own entity GHDL refuses as a top level.

   afe_stub.vhd:32 declares `master : in std_logic_vector` UNCONSTRAINED, so
   that one entity serves any arbiter master-index width; the width arrives
   from the instantiation.  `ghdl --synth afe_stub` therefore fails with
   "entity \"afe_stub\" cannot be at the top of a design (port \"master\" is
   unconstrained and has no default value)", and GHDL's -g reaches generics
   only, never a port width.

   This wrapper adds nothing but the constraint.  MW = 3 is the shipped master
   width (MCU.vhd:827, `signal sh_master : std_logic_vector(2 downto 0)`), and
   OWNER_HART = 1 is afe0's, MCU.vhd:3111.  The census row that matters is
   still afe_stub's: the wrapper contributes no flop, no latch and no cell of
   its own, so `afe_stub_top` and the `afe_stub_Bbehav_*` module inside it
   carry the same counts.

   This file is outside //hdl:vhdl_sources for the reason
   hdl/common/synth/macro_blackbox.vhd documents: hdl/common/synth is a bazel
   package and that glob does not descend into one, so no simulation source
   list can pick a synthesis-only wrapper up by accident. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity afe_stub_top is
    generic (
        OWNER_HART : natural := 1;
        MGMT_HART  : natural := 0;
        NREG       : natural := 16;
        MW         : natural := 3
    );
    port (
        clk    : in  std_logic;
        resetn : in  std_logic;
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(3 downto 0);
        wdata  : in  std_logic_vector(31 downto 0);
        master : in  std_logic_vector(MW - 1 downto 0);
        rdata  : out std_logic_vector(31 downto 0);
        irq    : out std_logic
    );
end entity afe_stub_top;

architecture synth_top of afe_stub_top is
begin
    dut: entity work.afe_stub
        generic map (
            OWNER_HART => OWNER_HART,
            MGMT_HART  => MGMT_HART,
            NREG       => NREG
        )
        port map (
            clk    => clk,
            resetn => resetn,
            en     => en,
            we     => we,
            addr   => addr,
            wdata  => wdata,
            master => master,
            rdata  => rdata,
            irq    => irq
        );
end architecture synth_top;
