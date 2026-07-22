-------------------------------------------------------------------------------
-- i2c_host_model.vhd
-------------------------------------------------------------------------------
-- Bit-banged I2C CONTROLLER (master) model for the I2C TARGET peripheral
-- testbench (tb/I2CTarget_tb.vhd). This is the ROLE-INVERSE of
-- i3c_target_model.vhd: there the model was the addressed target reacting to a
-- controller's SCL; here the model IS the controller -- it generates
-- START/STOP/repeated-START, drives SCL at a bench-chosen period, drives/samples
-- SDA open-drain, sends address+RnW, writes bytes, reads bytes (ACK/NACK per its
-- config), and honours the target's clock stretch.
--
-- CHECKER INDEPENDENCE (mandatory, the task's binding instruction): every SCL
-- half-period / setup / sample point is derived from the TB's OWN clk period
-- (cfg_tick_period) times the frozen-doc-derived tick constants in
-- i2ct_bfm_pkg -- NEVER from the DUT's SDA_DIR/SCL_DIR or any internal state.
-- The model measures the DUT's driven levels (address ACK, per-byte ACK, TX
-- data) off the RESOLVED bus at its OWN mid-SCL-high sample point, to_X01
-- normalized, and exposes them as obs_* for the TB scoreboard to judge. Its one
-- internal checker (obs_viol) flags a DUT level that is unstable across the
-- SCL-high sample window; cfg_corrupt forces that flag high as a self-test that
-- proves the checker path fires (the OneWire cfg_corrupt_window idiom).
--
-- OPEN-DRAIN BUS: sda_out/scl_out are fixed '0'; only sda_oe/scl_oe toggle
-- ('1' = pull that net low, '0' = release to the bench's weak 'H' pull). The
-- model NEVER drives either net high. Clock stretch is honoured by
-- scl_release_wait: after releasing SCL the model SAMPLES the resolved net and
-- waits for it to actually rise (the DUT may be holding it low, D11), with a
-- bounded guard that raises obs_timeout rather than hanging.
--
-- HANDSHAKE: a rising edge on cfg_go launches ONE framed segment against the
-- captured cfg_* descriptor; obs_count increments when the segment completes.
-- A segment with cfg_stop='false' ends by LEAVING SCL held low (this model's
-- scl_oe stays '1') so a following cfg_sr='true' segment can issue a genuine
-- repeated-START -- the classic write-then-read direction reversal (G5). While
-- the model is blocked on a genuine target stretch, obs_wait_scl='1' so the TB
-- can service the DUT (load I2CTTX / read+W1C I2CTRX) exactly during the stall.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.i2ct_bfm_pkg.all;

entity i2c_host_model is
    port (
        -- resolved bus (the same nets fed to the DUT's SDA_IN/SCL_IN)
        scl_in : in std_logic;
        sda_in : in std_logic;

        -- this model's open-drain drive ('1' on *_oe pulls *_out='0' onto the net)
        sda_out : out std_logic := '0';
        sda_oe  : out std_logic := '0';
        scl_out : out std_logic := '0';
        scl_oe  : out std_logic := '0';

        -- per-transaction configuration, held stable by the TB across one segment
        cfg_go          : in std_logic := '0';                                   -- rising edge launches
        cfg_op          : in natural   := I2CT_OP_XFER;
        cfg_sr          : in boolean   := false;                                 -- begin with repeated-START (bus held low by us)
        cfg_stop        : in boolean   := true;                                  -- end with STOP (else leave SCL held low)
        cfg_addr        : in std_logic_vector(6 downto 0) := (others => '0');
        cfg_rnw         : in std_logic := '0';                                   -- 0=host writes, 1=host reads
        cfg_nbytes      : in natural   := 0;
        cfg_wdata       : in i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1) := (others => (others => '0'));
        cfg_rd_ack      : in std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1) := (others => '0'); -- per read byte: '1'=ACK/continue, '0'=NACK/last
        cfg_hold        : in natural   := 0;                                     -- OP_WDOG: SCL-low hold in clk ticks
        cfg_corrupt     : in boolean   := false;                                 -- checker self-test: force obs_viol high
        cfg_tick_period : in time      := 40 ns;                                 -- TB's OWN clk period (never a DUT read)

        -- observations (held from the segment's last edge until the next go)
        obs_count     : out natural := 0;                                        -- ++ per completed segment (start/wait handshake)
        obs_addr_ack  : out std_logic := '0';                                    -- '1' = DUT drove the address ACK (SDA low)
        obs_wr_ack    : out std_logic_vector(0 to I2CT_MODEL_MAX_BYTES-1) := (others => '0'); -- per written byte: DUT ACK
        obs_rdata     : out i2ct_byte_array(0 to I2CT_MODEL_MAX_BYTES-1) := (others => (others => '0'));
        obs_wait_scl  : out std_logic := '0';                                    -- '1' while blocked on a genuine stretch
        obs_stretched : out std_logic := '0';                                    -- '1' if a real stretch occurred this segment (latched)
        obs_timeout   : out std_logic := '0';                                    -- '1' if the stretch wait hit its bounded guard
        obs_viol      : out std_logic := '0'                                     -- '1' = DUT level unstable across the sample window / self-test
    );
end entity i2c_host_model;

architecture behavioral of i2c_host_model is
    -- SCL-low ticks past the immediate release before the model calls it a
    -- genuine stretch (a normal release resolves to 'H' within ~1 tick).
    constant STRETCH_THRESH : natural := 4;
begin

    -- open-drain-only: the model never drives either net high.
    sda_out <= '0';
    scl_out <= '0';

    ctrl : process
        variable tickp       : time := 40 ns;
        variable addr_byte   : std_logic_vector(7 downto 0);
        variable wb, rb      : std_logic_vector(7 downto 0);
        variable got         : std_logic;
        variable stretched_v : std_logic := '0';
        variable timeout_v   : std_logic := '0';
        variable cnt         : natural   := 0;

        -- ---- primitive drives ------------------------------------------
        procedure tk(n : natural) is
        begin
            if n > 0 then wait for n * tickp; end if;
        end procedure;

        procedure sda_low is begin sda_oe <= '1'; end procedure;
        procedure sda_rel is begin sda_oe <= '0'; end procedure;
        procedure scl_low is begin scl_oe <= '1'; end procedure;

        -- Release SCL and wait for it to ACTUALLY rise (honour DUT stretch, D11)
        -- off the RESOLVED net, to_X01-normalized. Bounded: raises timeout_v (=>
        -- obs_timeout => a scoreboard error) rather than hanging.
        procedure scl_release_wait is
            variable g : natural := 0;
        begin
            scl_oe <= '0';
            loop
                exit when to_X01(scl_in) = '1';
                g := g + 1;
                if g = STRETCH_THRESH then
                    stretched_v  := '1';
                    obs_wait_scl <= '1';   -- genuine stretch in progress
                end if;
                wait for tickp;
                exit when g > I2CT_STRETCH_GUARD;
            end loop;
            if g > I2CT_STRETCH_GUARD then timeout_v := '1'; end if;
            obs_wait_scl <= '0';
        end procedure;

        -- ---- bit slots -------------------------------------------------
        -- Drive one bit the HOST sources (address / write data / host-ACK):
        -- set SDA while SCL is low, pulse SCL high then low.
        procedure wr_bit(level : std_logic) is
        begin
            if level = '1' then sda_rel; else sda_low; end if;
            tk(I2CT_SCL_HALF_TICKS);       -- tLOW: SDA setup + DUT sees SCL low
            scl_release_wait;              -- raise SCL (honour stretch)
            tk(I2CT_SCL_HALF_TICKS);       -- tHIGH
            scl_low;                       -- SCL low
        end procedure;

        -- Read one bit the DUT drives (address ACK / per-byte ACK / TX data):
        -- release SDA so the DUT owns it, pulse SCL, sample at mid-high, and
        -- re-sample at end-of-high for the stability (out-of-window) check.
        procedure rd_bit(bitval : out std_logic) is
            variable s1, s2 : std_logic;
        begin
            sda_rel;                                        -- host releases SDA
            tk(I2CT_SCL_HALF_TICKS);                        -- tLOW: DUT sets SDA_DIR
            scl_release_wait;                               -- raise SCL (honour stretch)
            tk(I2CT_SCL_SAMPLE_TICKS);                      -- into mid-high
            s1 := to_X01(sda_in);                           -- SAMPLE the DUT-driven level
            tk(I2CT_SCL_HALF_TICKS - I2CT_SCL_SAMPLE_TICKS);-- rest of tHIGH
            s2 := to_X01(sda_in);                           -- out-of-window re-sample
            if cfg_corrupt then
                obs_viol <= '1';                            -- self-test: force the checker path
            elsif s1 /= s2 then
                obs_viol <= '1';                            -- DUT level unstable across the window
            end if;
            scl_low;
            bitval := s1;
        end procedure;

        -- ---- framing ---------------------------------------------------
        procedure do_start is
        begin
            sda_rel; scl_release_wait;     -- both released high
            tk(I2CT_SCL_HALF_TICKS);
            sda_low;                       -- SDA falls while SCL high => START
            tk(I2CT_SCL_HALF_TICKS);
            scl_low;                       -- SCL low, ready for the address
        end procedure;

        procedure do_rstart is
        begin
            -- bus currently held low by us (SCL low from the prior segment)
            sda_rel;                       -- release SDA high while SCL low
            tk(I2CT_SCL_HALF_TICKS);
            scl_release_wait;              -- SCL high
            tk(I2CT_SCL_HALF_TICKS);
            sda_low;                       -- SDA falls while SCL high => repeated-START
            tk(I2CT_SCL_HALF_TICKS);
            scl_low;
        end procedure;

        procedure do_stop is
        begin
            sda_low;                       -- SCL low here; pull SDA low first
            tk(I2CT_SCL_HALF_TICKS);
            scl_release_wait;              -- SCL high, SDA still low
            tk(I2CT_SCL_HALF_TICKS);
            sda_rel;                       -- SDA rises while SCL high => STOP
            tk(I2CT_SCL_HALF_TICKS);
        end procedure;

    begin
        wait until cfg_go'event and to_X01(cfg_go) = '1';

        -- per-segment reset of observations / latches
        tickp        := cfg_tick_period;
        stretched_v  := '0';
        timeout_v    := '0';
        obs_stretched <= '0';
        obs_timeout   <= '0';
        obs_viol      <= '0';
        obs_addr_ack  <= '0';
        obs_wr_ack    <= (others => '0');
        obs_rdata     <= (others => (others => '0'));

        if cfg_op = I2CT_OP_WDOG then
            -- START + address(write) so the DUT enters BUSY and ACKs, then hold
            -- SCL low past WDTO (the DUT's watchdog counts SCL-low while BUSY),
            -- then STOP (D13 stimulus).
            do_start;
            addr_byte := cfg_addr & '0';
            for i in 7 downto 0 loop wr_bit(addr_byte(i)); end loop;
            rd_bit(got);
            obs_addr_ack <= not got;               -- '0' bus level = ACK => obs '1'
            scl_low;                               -- hold SCL low ...
            tk(cfg_hold);                          -- ... past the watchdog timeout
            do_stop;

        else
            -- normal framed segment
            if cfg_sr then do_rstart; else do_start; end if;
            addr_byte := cfg_addr & cfg_rnw;
            for i in 7 downto 0 loop wr_bit(addr_byte(i)); end loop;
            rd_bit(got);
            obs_addr_ack <= not got;               -- address ACK

            if cfg_rnw = '0' then
                -- HOST WRITE: drive cfg_nbytes bytes, sample the DUT's ACK each
                for k in 0 to cfg_nbytes - 1 loop
                    wb := cfg_wdata(k);
                    for i in 7 downto 0 loop wr_bit(wb(i)); end loop;  -- MSB-first
                    rd_bit(got);
                    obs_wr_ack(k) <= not got;
                end loop;
            else
                -- HOST READ: sample cfg_nbytes bytes MSB-first, then drive the
                -- host ACK/NACK per cfg_rd_ack (D10 host handshake).
                for k in 0 to cfg_nbytes - 1 loop
                    rb := (others => '0');
                    for i in 7 downto 0 loop
                        rd_bit(got);
                        rb(i) := got;              -- MSB-first assembly
                    end loop;
                    obs_rdata(k) <= rb;
                    wr_bit(not cfg_rd_ack(k));     -- '1'=ACK => drive low; '0'=NACK => release
                end loop;
            end if;

            if cfg_stop then
                do_stop;
            else
                -- leave SCL held low for a following repeated-START (G5); the
                -- next cfg_sr segment picks the bus up from here.
                sda_rel;
                scl_low;
            end if;
        end if;

        obs_stretched <= stretched_v;
        obs_timeout   <= timeout_v;
        cnt := cnt + 1;
        obs_count <= cnt;
    end process ctrl;

end architecture behavioral;
