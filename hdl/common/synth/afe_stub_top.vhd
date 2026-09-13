-- VestaRV: synthesis top for afe_stub
-- afe_stub.vhd declares master : in std_logic_vector UNCONSTRAINED so one entity serves any arbiter master-index width, and ghdl --synth refuses an unconstrained port on a top level (-g reaches generics only, never a port width). This wrapper adds nothing but the constraint.
-- MW = 3 is the shipped master width and OWNER_HART = 1 is afe0's. The wrapper contributes no flop, latch or cell, so afe_stub_top and the afe_stub instance inside it carry the same census counts.
-- It sits outside //hdl:vhdl_sources for the reason macro_blackbox.vhd gives: hdl/common/synth is a bazel package that glob does not descend into, so no simulation source list can pick a synthesis-only wrapper up by accident.

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
