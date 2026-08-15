-------------------------------------------------------------------------------
-- spi_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bus-functional model for driving the SPI peripheral's slave port as an external master: the model drives SCK and MOSI, and the DUT in slave mode shifts out on MISO.
-- The record members map onto the DUT's slave inputs in the TB:
--     sck_in <= e.sck;  mosi_in <= e.mosi;
-- The TB observes miso_out, and `half` is the SCK half-period.
--
-- The mode here matches SPI_tb's slave-receive test: data is LSB-first, the DUT samples MOSI on the trailing (falling) SCK edge, and MOSI is held past that edge to avoid a sample race.
-- Master-mode transfers are driven by writing the DUT's registers, so the DUT itself generates SCK and MOSI, and a loopback of MOSI back onto MISO for those stays a
-- concurrent assignment in the TB: miso_in <= mosi_out when loopback else ...
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package spi_bfm_pkg is

    -- TB-driven external-master lines into the DUT slave port.
    type spi_ext_master_t is record
        sck  : std_logic;
        mosi : std_logic;
    end record;

    -- Idle value: clock and data both low.
    constant SPI_EXT_MASTER_IDLE : spi_ext_master_t := (sck => '0', mosi => '0');

    -- Drive one byte into the DUT slave, LSB first, with the DUT sampling on the falling SCK edge.
    procedure spi_ext_send_byte(signal e : inout spi_ext_master_t;
                                d : in std_logic_vector(7 downto 0);
                                half : in time);

end package spi_bfm_pkg;


package body spi_bfm_pkg is

    procedure spi_ext_send_byte(signal e : inout spi_ext_master_t;
                                d : in std_logic_vector(7 downto 0);
                                half : in time) is
    begin
        -- One bit per SCK period: set MOSI, raise SCK, then drop it.
        for i in 0 to 7 loop
            e.mosi <= d(i);   wait for half;
            e.sck  <= '1';    wait for half;   -- leading edge (slave shifts out)
            e.sck  <= '0';    wait for half;   -- trailing edge (slave samples MOSI)
        end loop;
    end procedure;

end package body spi_bfm_pkg;
