-- VestaRV: I2C master BFM
-- Bus-functional model for driving an I2C bus as an external master against the I2C peripheral's slave port.
-- Open-drain: the model pulls a line low and the DUT or the pull-up releases it high, so the wired-AND stays in the TB architecture, driven from this record and the DUT's *_DIR outputs:
--     SDA_IN <= '0' when (SDA_DIR = '1' or m.sda_low = '1') else '1';
--     SCL_IN <= '0' when (SCL_DIR = '1' or m.scl_low = '1') else '1';
-- `T` is the bus phase time: the model spends three phases per bit (set data, SCL high, SCL low), so one SCL period is 3*T and the SCL high phase is T.
-- The DUT slave is oversampled on its peripheral clock, so T is not free: the caller must keep 3*T at or above the peripheral-clock-to-SCL ratio the slave asserts, which is 32. I2C_tb states the two ratios it drives and why.

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

    -- Stretch-aware variants. A slave that stretches holds SCL low after the
    -- model has released it, so every phase that needs SCL actually high waits
    -- for the line before it starts counting T. The plain procedures above are
    -- left untouched: they are what the groups written before clock stretching
    -- call, and their timing must not move.
    procedure i2c_wait_scl(signal scl_in : in std_logic);
    procedure i2c_bit_st  (signal m : inout i2c_master_t;
                           signal scl_in : in std_logic;
                           b : in std_logic; T : in time);
    procedure i2c_byte_st (signal m : inout i2c_master_t;
                           signal scl_in : in std_logic;
                           d : in std_logic_vector(7 downto 0); T : in time);
    procedure i2c_get_ack_st(signal m : inout i2c_master_t;
                             signal sda_in : in std_logic;
                             signal scl_in : in std_logic;
                             ack : out std_logic; T : in time);

    -- Repeated START: SDA is released while SCL is low, SCL rises, then SDA
    -- falls. Unlike i2c_start it does not pulse SCL first, because the bus is
    -- already busy and the extra pulse would be a ninth clock.
    procedure i2c_restart(signal m : inout i2c_master_t;
                          signal scl_in : in std_logic; T : in time);

    -- Master receiver: release SDA and clock eight bits out of the slave, MSB
    -- first, then drive the ninth-clock ACK ('0') or NACK ('1').
    procedure i2c_read_byte(signal m : inout i2c_master_t;
                            signal sda_in : in std_logic;
                            signal scl_in : in std_logic;
                            d : out std_logic_vector(7 downto 0); T : in time);
    procedure i2c_put_ack  (signal m : inout i2c_master_t;
                            signal scl_in : in std_logic;
                            ack : in std_logic; T : in time);

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

    -- Block until the wired-AND actually shows SCL high. Returns at once when
    -- nothing is stretching, so it is free to call on every phase.
    procedure i2c_wait_scl(signal scl_in : in std_logic) is
    begin
        if scl_in /= '1' then
            wait until scl_in = '1';
        end if;
    end procedure;

    procedure i2c_bit_st(signal m : inout i2c_master_t;
                         signal scl_in : in std_logic;
                         b : in std_logic; T : in time) is
    begin
        m.scl_low <= '1';                                 -- SCL low, set data
        if b = '1' then m.sda_low <= '0'; else m.sda_low <= '1'; end if;
        wait for T;
        m.scl_low <= '0';                                 -- release SCL
        i2c_wait_scl(scl_in);                             -- the slave may stretch here
        wait for T;                                       -- SCL high (slave samples)
        m.scl_low <= '1'; wait for T;                     -- SCL low (slave shifts)
    end procedure;

    procedure i2c_byte_st(signal m : inout i2c_master_t;
                          signal scl_in : in std_logic;
                          d : in std_logic_vector(7 downto 0); T : in time) is
    begin
        for i in 7 downto 0 loop                          -- MSB first
            i2c_bit_st(m, scl_in, d(i), T);
        end loop;
    end procedure;

    procedure i2c_get_ack_st(signal m : inout i2c_master_t;
                             signal sda_in : in std_logic;
                             signal scl_in : in std_logic;
                             ack : out std_logic; T : in time) is
    begin
        m.scl_low <= '1'; m.sda_low <= '0'; wait for T;   -- release SDA
        m.scl_low <= '0';                                 -- release SCL
        i2c_wait_scl(scl_in);                             -- the ACK state is where the slave stretches
        wait for T;                                       -- SCL high
        ack := sda_in;
        m.scl_low <= '1'; wait for T;                     -- SCL low
    end procedure;

    procedure i2c_restart(signal m : inout i2c_master_t;
                          signal scl_in : in std_logic; T : in time) is
    begin
        m.scl_low <= '1'; wait for T;                     -- SCL low
        m.sda_low <= '0'; wait for T;                     -- release SDA while SCL is low
        m.scl_low <= '0';
        i2c_wait_scl(scl_in);
        wait for T;                                       -- SCL high, SDA high
        m.sda_low <= '1'; wait for T;                     -- SDA falls: repeated START
        m.scl_low <= '1'; wait for T;                     -- SCL low
    end procedure;

    procedure i2c_read_byte(signal m : inout i2c_master_t;
                            signal sda_in : in std_logic;
                            signal scl_in : in std_logic;
                            d : out std_logic_vector(7 downto 0); T : in time) is
        variable acc : std_logic_vector(7 downto 0) := (others => '0');
    begin
        m.sda_low <= '0';                                 -- the slave drives SDA
        for i in 7 downto 0 loop
            m.scl_low <= '1'; wait for T;                 -- SCL low, slave presents the bit
            m.scl_low <= '0';
            i2c_wait_scl(scl_in);
            wait for T;                                   -- SCL high, master samples
            acc(i) := sda_in;
            m.scl_low <= '1'; wait for T;                 -- SCL low
        end loop;
        d := acc;
    end procedure;

    procedure i2c_put_ack(signal m : inout i2c_master_t;
                          signal scl_in : in std_logic;
                          ack : in std_logic; T : in time) is
    begin
        m.scl_low <= '1';                                 -- SCL low, drive the ninth bit
        if ack = '0' then m.sda_low <= '1'; else m.sda_low <= '0'; end if;
        wait for T;
        m.scl_low <= '0';
        i2c_wait_scl(scl_in);
        wait for T;                                       -- SCL high, slave reads it
        m.scl_low <= '1'; m.sda_low <= '0'; wait for T;   -- SCL low, release SDA
    end procedure;

end package body i2c_bfm_pkg;
