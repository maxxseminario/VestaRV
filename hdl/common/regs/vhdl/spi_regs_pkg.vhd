-- VestaRV: SPI register package
-- Serial Peripheral Interface
-- Generated from hdl/common/regs/rdl/spi.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package spi_regs_pkg is

    -- SPIxCR: SPI control register
    constant SPIxCR_WORD              : natural := 0;
    constant SPIxCR_ADDR              : natural := 0;
    constant SPIxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SPIxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000011111111111111111111";
    constant SPIFEN_MSB               : natural := 19;
    constant SPIFEN_LSB               : natural := 19;
    constant SPIFEN_RESET             : std_logic_vector(0 downto 0) := "0";
    constant SPISM_MSB                : natural := 18;
    constant SPISM_LSB                : natural := 18;
    constant SPISM_RESET              : std_logic_vector(0 downto 0) := "0";
    constant SPITXSB_MSB              : natural := 17;
    constant SPITXSB_LSB              : natural := 17;
    constant SPITXSB_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPIRXSB_MSB              : natural := 16;
    constant SPIRXSB_LSB              : natural := 16;
    constant SPIRXSB_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPIBR_MSB                : natural := 15;
    constant SPIBR_LSB                : natural := 8;
    constant SPIBR_RESET              : std_logic_vector(7 downto 0) := "00000000";
    constant SPIEN_MSB                : natural := 7;
    constant SPIEN_LSB                : natural := 7;
    constant SPIEN_RESET              : std_logic_vector(0 downto 0) := "0";
    constant SPIMSB_MSB               : natural := 6;
    constant SPIMSB_LSB               : natural := 6;
    constant SPIMSB_RESET             : std_logic_vector(0 downto 0) := "0";
    constant SPITCIE_MSB              : natural := 5;
    constant SPITCIE_LSB              : natural := 5;
    constant SPITCIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPITEIE_MSB              : natural := 4;
    constant SPITEIE_LSB              : natural := 4;
    constant SPITEIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPIDL_MSB                : natural := 3;
    constant SPIDL_LSB                : natural := 2;
    constant SPIDL_RESET              : std_logic_vector(1 downto 0) := "00";
    constant SPICPOL_MSB              : natural := 1;
    constant SPICPOL_LSB              : natural := 1;
    constant SPICPOL_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPICPHA_MSB              : natural := 0;
    constant SPICPHA_LSB              : natural := 0;
    constant SPICPHA_RESET            : std_logic_vector(0 downto 0) := "0";

    -- SPIxSR: SPI status register
    constant SPIxSR_WORD              : natural := 1;
    constant SPIxSR_ADDR              : natural := 4;
    constant SPIxSR_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant SPIxSR_IMPL              : std_logic_vector(7 downto 0) := "00000000";
    constant SPIBUSY_MSB              : natural := 2;
    constant SPIBUSY_LSB              : natural := 2;
    constant SPIBUSY_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPITCIF_MSB              : natural := 1;
    constant SPITCIF_LSB              : natural := 1;
    constant SPITCIF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant SPITEIF_MSB              : natural := 0;
    constant SPITEIF_LSB              : natural := 0;
    constant SPITEIF_RESET            : std_logic_vector(0 downto 0) := "0";

    -- SPIxTX: SPI transmit buffer register
    constant SPIxTX_WORD              : natural := 2;
    constant SPIxTX_ADDR              : natural := 8;
    constant SPIxTX_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SPIxTX_IMPL              : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant SPITX_MSB                : natural := 31;
    constant SPITX_LSB                : natural := 0;
    constant SPITX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- SPIxRX: SPI receive buffer register
    constant SPIxRX_WORD              : natural := 3;
    constant SPIxRX_ADDR              : natural := 12;
    constant SPIxRX_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SPIxRX_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SPIRX_MSB                : natural := 31;
    constant SPIRX_LSB                : natural := 0;
    constant SPIRX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- SPIxFOS: SPI Flash memory address offset
    constant SPIxFOS_WORD             : natural := 4;
    constant SPIxFOS_ADDR             : natural := 16;
    constant SPIxFOS_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant SPIxFOS_IMPL             : std_logic_vector(31 downto 0) := "00000000111111111111111111111111";
    constant SPIFOS_MSB               : natural := 23;
    constant SPIFOS_LSB               : natural := 0;
    constant SPIFOS_RESET             : std_logic_vector(23 downto 0) := "000000000000000000000000";

    -- SPI.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant RegSlotSPIxCR            : natural := 0;
    constant RegSlotSPIxSR            : natural := 1;
    constant RegSlotSPIxTX            : natural := 2;
    constant RegSlotSPIxRX            : natural := 3;
    constant RegSlotSPIxFOS           : natural := 4;

end package spi_regs_pkg;
