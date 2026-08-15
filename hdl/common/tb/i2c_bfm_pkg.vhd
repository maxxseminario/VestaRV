-------------------------------------------------------------------------------
-- i2c_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bus-functional model for driving an I2C bus as an external master against the I2C peripheral's slave port.
-- Open-drain: the model pulls a line low, and the DUT or the pull-up releases it high.
-- The wired-AND itself stays in the TB architecture, driven from this record and the DUT's *_DIR outputs, for example:
--     SDA_IN <= '0' when (SDA_DIR = '1' or m.sda_low = '1') else '1';
--     SCL_IN <= '0' when (SCL_DIR = '1' or m.scl_low = '1') else '1';
-- `T` is the bus phase time, roughly a quarter to an eighth of an SCL period.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

package i2c_bfm_pkg is

    -- TB-driven open-drain pulls: a '1' means the model actively pulls that line low.
    type i2c_master_t is record
        sda_low : std_logic;
        scl_low : std_logic;
    end record;

    -- Idle value: both lines released.
    constant I2C_MASTER_IDLE : i2c_master_t := (sda_low => '0', scl_low => '0');

    procedure i2c_start(signal m : inout i2c_master_t; T : in time);
    procedure i2c_stop (signal m : inout i2c_master_t; T : in time);
    procedure i2c_bit  (signal m : inout i2c_master_t; b : in std_logic; T : in time);
    procedure i2c_byte (signal m : inout i2c_master_t; d : in std_logic_vector(7 downto 0); T : in time);
    -- Ninth clock: release SDA, let the slave drive ACK, and sample it, where 0 means ACK.
    procedure i2c_get_ack(signal m : inout i2c_master_t;
                          signal sda_in : in std_logic;
                          ack : out std_logic; T : in time);

end package i2c_bfm_pkg;


package body i2c_bfm_pkg is

    -- Bring the bus to a clean idle, pulse SCL low once to clear any stale start-detect left by a data-less transaction, then generate START by dropping SDA while SCL is high.
    procedure i2c_start(signal m : inout i2c_master_t; T : in time) is
    begin
        m.sda_low <= '0'; m.scl_low <= '0'; wait for T;   -- idle, both high
        m.scl_low <= '1'; wait for T;                     -- SCL low pulse
        m.scl_low <= '0'; wait for T;                     -- both high again
        m.sda_low <= '1'; wait for T;                     -- SDA falls, which is the START condition
        m.scl_low <= '1'; wait for T;                     -- SCL low
    end procedure;

    -- STOP: SDA rises while SCL is high.
    procedure i2c_stop(signal m : inout i2c_master_t; T : in time) is
    begin
        m.scl_low <= '1'; m.sda_low <= '1'; wait for T;   -- SCL low, SDA low
        m.scl_low <= '0'; wait for T;                     -- SCL high
        m.sda_low <= '0'; wait for T;                     -- SDA rises, which is the STOP condition
    end procedure;

    -- One data bit: set SDA while SCL is low, then clock it out.
    procedure i2c_bit(signal m : inout i2c_master_t; b : in std_logic; T : in time) is
    begin
        m.scl_low <= '1';                                 -- SCL low, set data
        if b = '1' then m.sda_low <= '0'; else m.sda_low <= '1'; end if;
        wait for T;
        m.scl_low <= '0'; wait for T;                     -- SCL high (slave samples)
        m.scl_low <= '1'; wait for T;                     -- SCL low (slave shifts)
    end procedure;

    -- Eight data bits, most significant first.
    procedure i2c_byte(signal m : inout i2c_master_t; d : in std_logic_vector(7 downto 0); T : in time) is
    begin
        for i in 7 downto 0 loop                          -- MSB first
            i2c_bit(m, d(i), T);
        end loop;
    end procedure;

    -- Ninth clock: release SDA and sample what the slave drives while SCL is high.
    procedure i2c_get_ack(signal m : inout i2c_master_t;
                          signal sda_in : in std_logic;
                          ack : out std_logic; T : in time) is
    begin
        m.scl_low <= '1'; m.sda_low <= '0'; wait for T;   -- release SDA
        m.scl_low <= '0'; wait for T;                     -- SCL high
        ack := sda_in;
        m.scl_low <= '1'; wait for T;                     -- SCL low
    end procedure;

end package body i2c_bfm_pkg;
