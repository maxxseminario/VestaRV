-------------------------------------------------------------------------------
-- qspi_flash_model.vhd
-------------------------------------------------------------------------------
-- Generic-configured behavioral SPI/QSPI flash responder for the QSPI
-- peripheral testbench (tb/QSPI_tb.vhd). Unlike tb/serial_flash.vhd (the real
-- AT45DB021E model used by SPI_flash_tb, which decodes actual opcodes), this
-- model does NOT decode flash opcodes at all: the TB tells it, per launch, the
-- exact phase shape to expect (lane widths + edge counts for CMD/ADDR/DUMMY/
-- DATA and the transfer direction) via the cfg_* inputs, held stable for the
-- duration of one CS-framed transaction. That keeps the model reusable across
-- every width/AWID/DLEN combination in the test plan without needing a real
-- opcode table.
--
-- Bus ownership: the TB resolves io_in/io_out/io_dir from the DUT against
-- this model's io_out/io_oe the way the top-level comment in QSPI_tb.vhd
-- describes -- io_in fed to BOTH the DUT and this model is the same resolved
-- 4-bit bus. This model drives ONLY during the DATA phase of a READ
-- (cfg_dir_read=true); every other phase it holds io_oe at "0000" (matches
-- the frozen contract: "It must NOT drive the bus outside the data phase of a
-- READ").
--
-- CS / SCK polarity ASSUMPTION (not stated in the frozen entity contract --
-- flagged in the bench author's report): cs is ACTIVE-LOW (mirrors every
-- other CS-style pin in this codebase, e.g. serial_flash.vhd's CSb), wired
-- directly from the DUT's cs_out (cs_dir is NOT consulted, matching how
-- SPI_flash_tb.vhd wires serial_flash's CSb straight from cs_flash_out).
-- Likewise sck is wired directly from sck_out (sck_dir not consulted).
--
-- SPI mode / edge-role ASSUMPTION: standard CPOL/CPHA mode semantics --
-- "leading edge" is the first SCK transition away from the CPOL idle level;
-- CPHA=0 samples on the leading edge (drives changed data on the trailing
-- edge), CPHA=1 drives on the leading edge (samples on the trailing edge).
-- SIMPLIFICATION (flagged): this model performs BOTH capture (CMD/ADDR/
-- write-DATA) and its own drive-value advance (read-DATA) on the SAME
-- "sample-role" edge (see the qualifying `samp` variable below) rather than
-- splitting capture and drive across the two edge roles the way a real SPI
-- transmitter/receiver pair would. In event-driven VHDL this still resolves
-- correctly via delta-cycle ordering for THIS model's own bus turnaround, but
-- it has never been run against a real DUT (QSPI.vhd doesn't exist yet) and
-- may need retiming once it does.
--
-- DUMMY-field granularity ASSUMPTION (flagged): the frozen CR.DUMMY field is
-- documented only as "[15:11] DUMMY edges" with no stated unit. This model
-- treats one DUMMY count as one "sample-role" edge (i.e. effectively one SCK
-- period), the same granularity used for CMD/ADDR/DATA edge counts.
--
-- Deterministic READ pattern and MSB-first byte/nibble packing are exactly
-- the frozen-contract examples; see qspi_bfm_pkg.qspi_read_pattern.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.qspi_bfm_pkg.all;

entity QSPI_flash_model is
    port (
        cs   : in std_logic;                     -- DUT cs_out, ASSUMED active-low
        sck  : in std_logic;                      -- DUT sck_out
        cpol : in std_logic;
        cpha : in std_logic;

        io_in  : in  std_logic_vector(3 downto 0);  -- resolved bus (DUT-driven bits visible here)
        io_out : out std_logic_vector(3 downto 0) := (others => '0');
        io_oe  : out std_logic_vector(3 downto 0) := (others => '0');  -- '1' = this model drives that bit

        -- shape configuration: set by the TB before each launch and held
        -- stable for the duration of that one transaction.
        cfg_cmd_lanes   : in natural range 1 to 4 := 1;
        cfg_cmd_edges   : in natural := 8;               -- edges to shift the 8-bit opcode
        cfg_addr_lanes  : in natural range 1 to 4 := 1;
        cfg_addr_edges  : in natural := 0;                -- 0 => no address phase
        cfg_dummy_edges : in natural := 0;
        cfg_data_lanes  : in natural range 1 to 4 := 1;
        cfg_data_edges  : in natural := 0;                -- 0 => command-only, no data phase
        cfg_dir_read    : in boolean := false;             -- true => this model drives the data phase
        cfg_read_seed   : in std_logic_vector(7 downto 0) := x"A5";

        -- observed results: obs_valid pulses/holds high from the CS rising
        -- edge that completed a transaction until the next CS falling edge.
        obs_valid     : out std_logic := '0';
        obs_cmd       : out std_logic_vector(7 downto 0)  := (others => '0');
        obs_addr      : out std_logic_vector(31 downto 0) := (others => '0');
        obs_wdata     : out std_logic_vector(31 downto 0) := (others => '0');
        obs_txn_count : out natural := 0
    );
end entity QSPI_flash_model;

architecture behavioral of QSPI_flash_model is

    -- Per-phase OE mask + nibble presentation for the read-DATA phase.
    -- lanes=1 drives IO1 only ("MISO position" per the frozen contract);
    -- lanes=2 drives IO1,IO0; lanes=4 drives IO3..IO0. word is MSB-first;
    -- nibble_idx counts completed lane-groups from the top of word.
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
            return v;   -- past the end of the pattern; hold released-looking 0s
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

    resp : process (cs, sck)
        variable phase_edge : natural := 0;                       -- sample-role edges completed since CS fell
        variable b1, b2, b3, b4 : natural := 0;                   -- cumulative phase-boundary edge counts
        variable shift_cmd   : std_logic_vector(7 downto 0)  := (others => '0');
        variable shift_addr  : std_logic_vector(31 downto 0) := (others => '0');
        variable shift_wdata : std_logic_vector(31 downto 0) := (others => '0');
        variable tx_word     : std_logic_vector(31 downto 0) := (others => '0');
        variable txn_count   : natural := 0;
        variable leading : boolean;
        variable samp    : boolean;
    begin
        if cs'event and cs = '0' then
            -- CS asserted: start of a new transaction. Latch the phase
            -- boundaries from the (assumed stable) cfg_* inputs.
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
                -- SAMPLE edge: a real mode-0/mode-3 flash CAPTURES its inputs
                -- here (CMD/ADDR/write-DATA). Read data is NOT driven on this
                -- edge -- it was presented on the preceding DRIVE edge (below)
                -- and held stable across this sample edge for the DUT to latch.
                if phase_edge < b1 then                          -- CMD: DUT drives, model captures
                    for k in cfg_cmd_lanes - 1 downto 0 loop
                        shift_cmd := shift_cmd(6 downto 0) & io_in(k);
                    end loop;

                elsif phase_edge < b2 then                        -- ADDR: DUT drives, model captures
                    for k in cfg_addr_lanes - 1 downto 0 loop
                        shift_addr := shift_addr(30 downto 0) & io_in(k);
                    end loop;

                elsif phase_edge < b3 then                        -- DUMMY: nobody drives
                    null;

                elsif phase_edge < b4 then                        -- write-DATA capture (reads: nothing here)
                    if not cfg_dir_read then
                        for k in cfg_data_lanes - 1 downto 0 loop
                            shift_wdata := shift_wdata(30 downto 0) & io_in(k);
                        end loop;
                    end if;
                end if;
                phase_edge := phase_edge + 1;

            else
                -- DRIVE edge (opposite of the sample edge). A real flash changes
                -- its output here so it is stable before the master's next
                -- sample edge. `phase_edge` currently equals the index of the
                -- UPCOMING sample edge, so present the read nibble for that
                -- sample. Never drive outside the READ data window.
                if cfg_dir_read and phase_edge >= b3 and phase_edge < b4 then
                    if phase_edge = b3 then
                        -- entering the data phase: build the deterministic
                        -- pattern from the address just captured (seed alone if
                        -- there was no address phase, shift_addr stays 0).
                        tx_word := qspi_read_pattern(shift_addr, cfg_read_seed);
                    end if;
                    io_oe  <= drive_oe_mask(cfg_data_lanes);
                    io_out <= drive_nibble(tx_word, phase_edge - b3, cfg_data_lanes);
                else
                    io_oe  <= (others => '0');
                    io_out <= (others => '0');
                end if;
            end if;
        end if;
    end process resp;

end architecture behavioral;
