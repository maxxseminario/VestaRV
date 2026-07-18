-------------------------------------------------------------------------------
-- spi_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bus-functional model for driving the SPI peripheral's slave port as an
-- external master: the model drives SCK and MOSI, the DUT (in slave mode) shifts
-- out on MISO. The record members map onto the DUT's slave inputs in the TB:
--     sck_in <= e.sck;  mosi_in <= e.mosi;
-- and the TB observes miso_out. `half` is the SCK half-period.
--
-- Mode here matches SPI_tb's slave-receive test: data LSB-first, the DUT samples
-- MOSI on the trailing (falling) SCK edge, MOSI held past the edge to avoid a
-- sample race. Master-mode transfers are driven by writing the DUT's registers
-- (the DUT generates SCK/MOSI); a MISO<-MOSI loopback for those stays a
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

    constant SPI_EXT_MASTER_IDLE : spi_ext_master_t := (sck => '0', mosi => '0');

    -- Drive one byte into the DUT slave, LSB first, DUT sampling on SCK falling.
    procedure spi_ext_send_byte(signal e : inout spi_ext_master_t;
                                d : in std_logic_vector(7 downto 0);
                                half : in time);

end package spi_bfm_pkg;


package body spi_bfm_pkg is

    procedure spi_ext_send_byte(signal e : inout spi_ext_master_t;
                                d : in std_logic_vector(7 downto 0);
                                half : in time) is
    begin
        for i in 0 to 7 loop
            e.mosi <= d(i);   wait for half;
            e.sck  <= '1';    wait for half;   -- leading edge (slave shifts out)
            e.sck  <= '0';    wait for half;   -- trailing edge (slave samples MOSI)
        end loop;
    end procedure;

end package body spi_bfm_pkg;
