/* -----------------------------------------------------------------------------
   qspi_flash_model.vhd
   -----------------------------------------------------------------------------
   Behavioral SPI/QSPI flash responder for the QSPI peripheral testbench; it decodes no flash opcodes.
   The TB names the phase shape per launch through the cfg_* inputs, held stable across one CS-framed transaction: lane widths and edge counts for CMD/ADDR/DUMMY/DATA plus the direction, so one model covers every width/AWID/DLEN combination.
   cs is ACTIVE-LOW and comes straight from the DUT's cs_out, sck straight from sck_out; the matching direction outputs are not consulted.
   Standard CPOL/CPHA semantics, leading edge being the first SCK transition away from the CPOL idle level: CPHA=0 samples leading and drives trailing, CPHA=1 the other way round, and one DUMMY count is one sample-role edge.
   This model drives ONLY during the DATA phase of a READ (cfg_dir_read true) and holds io_oe at "0000" in every other phase; capture and its own drive-value advance both happen on the sample-role edge.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_bfm_pkg.all;

entity QSPI_flash_model is
    port (
        cs   : in std_logic;                     -- DUT cs_out, ASSUMED active-low.
        sck  : in std_logic;                      -- DUT sck_out.
        cpol : in std_logic;
        cpha : in std_logic;

        io_in  : in  std_logic_vector(3 downto 0);  -- Resolved bus; the DUT-driven bits are visible here.
        io_out : out std_logic_vector(3 downto 0) := (others => '0');
        io_oe  : out std_logic_vector(3 downto 0) := (others => '0');  -- '1' means this model drives that bit.

        -- Shape configuration: set by the TB before each launch and held stable for the duration of that one transaction.
        cfg_cmd_lanes   : in natural range 1 to 4 := 1;
        cfg_cmd_edges   : in natural := 8;               -- Edges used to shift the 8-bit opcode.
        cfg_addr_lanes  : in natural range 1 to 4 := 1;
        cfg_addr_edges  : in natural := 0;                -- 0 means no address phase.
        cfg_dummy_edges : in natural := 0;
        cfg_data_lanes  : in natural range 1 to 4 := 1;
        cfg_data_edges  : in natural := 0;                -- 0 means command-only, no data phase.
        cfg_dir_read    : in boolean := false;             -- True makes this model drive the data phase.
        cfg_read_seed   : in std_logic_vector(7 downto 0) := x"A5";

        -- Observed results: obs_valid goes high on the CS rising edge that completed a transaction and holds until the next CS falling edge.
        obs_valid     : out std_logic := '0';
        obs_cmd       : out std_logic_vector(7 downto 0)  := (others => '0');
        obs_addr      : out std_logic_vector(31 downto 0) := (others => '0');
        obs_wdata     : out std_logic_vector(31 downto 0) := (others => '0');
        obs_txn_count : out natural := 0
    );
end entity QSPI_flash_model;

architecture behavioral of QSPI_flash_model is

    -- Per-phase OE mask for the read-DATA phase: lanes=1 drives IO1 only (the MISO position), lanes=2 drives IO1 and IO0, lanes=4 drives IO3 down to IO0.
    -- word is MSB-first and nibble_idx counts completed lane-groups from the top of word.
    function drive_oe_mask(lanes : natural) return std_logic_vector is
    begin
        case lanes is
            when 1      => return "0010";
            when 2      => return "0011";
            when others => return "1111";
        end case;
    end function;

    function drive_nibble(word : std_logic_vector(31 downto 0);
                          nibble_idx : natural; lanes : natural)
        return std_logic_vector is
        variable hi : integer;
        variable v  : std_logic_vector(3 downto 0) := "0000";
    begin
        hi := 31 - nibble_idx * lanes;
        if hi < 0 then
            return v;   -- Past the end of the pattern: hold released-looking zeros.
        end if;
        case lanes is
            when 1 =>
                v(1) := word(hi);
            when 2 =>
                v(1) := word(hi);
                v(0) := word(hi - 1);
            when others =>
                v(3) := word(hi);
                v(2) := word(hi - 1);
                v(1) := word(hi - 2);
                v(0) := word(hi - 3);
        end case;
        return v;
    end function;

begin

    -- One process runs the whole responder: CS framing plus the per-SCK-edge phase walk.
    resp : process (cs, sck)
        variable phase_edge : natural := 0;                       -- Sample-role edges completed since CS fell.
        variable b1, b2, b3, b4 : natural := 0;                   -- Cumulative phase-boundary edge counts.
        variable shift_cmd   : std_logic_vector(7 downto 0)  := (others => '0');
        variable shift_addr  : std_logic_vector(31 downto 0) := (others => '0');
        variable shift_wdata : std_logic_vector(31 downto 0) := (others => '0');
        variable tx_word     : std_logic_vector(31 downto 0) := (others => '0');
        variable txn_count   : natural := 0;
        variable leading : boolean;
        variable samp    : boolean;
    begin
        if cs'event and cs = '0' then
            -- CS asserted: start a new transaction and latch the phase boundaries from the cfg_* inputs.
            phase_edge  := 0;
            shift_cmd   := (others => '0');
            shift_addr  := (others => '0');
            shift_wdata := (others => '0');
            tx_word     := (others => '0');
            b1 := cfg_cmd_edges;
            b2 := b1 + cfg_addr_edges;
            b3 := b2 + cfg_dummy_edges;
            b4 := b3 + cfg_data_edges;
            io_oe     <= (others => '0');
            io_out    <= (others => '0');
            obs_valid <= '0';

        elsif cs'event and cs = '1' then
            -- CS deasserted: finalize observed results, release the bus.
            io_oe         <= (others => '0');
            io_out        <= (others => '0');
            obs_cmd       <= shift_cmd;
            obs_addr      <= shift_addr;
            obs_wdata     <= shift_wdata;
            txn_count     := txn_count + 1;
            obs_txn_count <= txn_count;
            obs_valid     <= '1';

        elsif cs = '0' and sck'event then
            leading := (cpol = '0' and sck = '1') or (cpol = '1' and sck = '0');
            samp    := (cpha = '0' and leading) or (cpha = '1' and not leading);

            if samp then
                -- SAMPLE edge: capture CMD/ADDR/write-DATA here.
                -- Read data is never driven on this edge; it was presented on the preceding drive edge and is held stable across it for the DUT to latch.
                if phase_edge < b1 then                          -- CMD phase: the DUT drives, the model captures.
                    for k in cfg_cmd_lanes - 1 downto 0 loop
                        shift_cmd := shift_cmd(6 downto 0) & io_in(k);
                    end loop;

                elsif phase_edge < b2 then                        -- ADDR phase: the DUT drives, the model captures.
                    for k in cfg_addr_lanes - 1 downto 0 loop
                        shift_addr := shift_addr(30 downto 0) & io_in(k);
                    end loop;

                elsif phase_edge < b3 then                        -- DUMMY phase: nobody drives.
                    null;

                elsif phase_edge < b4 then                        -- Write-DATA capture; on a read there is nothing to do here.
                    if not cfg_dir_read then
                        for k in cfg_data_lanes - 1 downto 0 loop
                            shift_wdata := shift_wdata(30 downto 0) & io_in(k);
                        end loop;
                    end if;
                end if;
                phase_edge := phase_edge + 1;

            else
                -- DRIVE edge: change the output here so it is stable before the master's next sample edge, and never drive outside the READ data window.
                -- `phase_edge` equals the index of the UPCOMING sample edge, so present the read nibble for that sample.
                if cfg_dir_read and phase_edge >= b3 and phase_edge < b4 then
                    if phase_edge = b3 then
                        -- Entering the data phase: build the pattern from the address just captured; with no address phase shift_addr stays 0 and the seed alone determines it.
                        tx_word := qspi_read_pattern(shift_addr, cfg_read_seed);
                    end if;
                    io_oe  <= drive_oe_mask(cfg_data_lanes);
                    io_out <= drive_nibble(tx_word, phase_edge - b3, cfg_data_lanes);
                else
                    -- Outside the read data window this model keeps the bus released.
                    io_oe  <= (others => '0');
                    io_out <= (others => '0');
                end if;
            end if;
        end if;
    end process resp;

end architecture behavioral;
