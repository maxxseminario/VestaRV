-------------------------------------------------------------------------------
-- nfc_reader_model.vhd
-------------------------------------------------------------------------------
-- Behavioral ISO 14443A READER (PCD) model for the NFC tag/card-emulation
-- peripheral testbench (tb/NFC_tb.vhd). This is the checker PEER and the heart
-- of the bench: it is an INDEPENDENT implementation of the reader side of the
-- RF link -- it does NOT reuse the DUT's codec (which does not exist yet, and
-- must not share encode/decode logic with the tb's expectations beyond the
-- spec-literal CRC_A/parity utilities in nfc_bfm_pkg). Mirrors the role of
-- tb/i3c_target_model.vhd / tb/qspi_flash_model.vhd (per-transaction cfg_*
-- shape, held stable by the tb across one frame; obs_* results for the
-- scoreboard).
--
-- RF loopback (design doc S13 AFE stub): the AFE is off-die (D2); this bench
-- closes the RF path in behavioral VHDL. The model
--   * generates rf_clk (the compressed carrier-derived protocol clock) and
--     drives field_detect (field on/off scenarios);
--   * ENCODES reader->tag commands as modified-Miller pause coding on rf_rx
--     (D6): within one ETU bit period a carrier pause ('0') sits in the FIRST
--     half (symbol Z), the SECOND half (symbol X), or is absent (symbol Y).
--     Miller symbol rule (D6): SOC = Z out of idle; logic 1 = X; logic 0 = Y if
--     the previous symbol was a 1 (X) else Z; EOC = two idle bit periods.
--   * DECODES tag->reader responses from rf_txmod/rf_tx_en (D7): per half-bit
--     it counts subcarrier toggles on rf_txmod -- "modulated" (running fc/16
--     subcarrier) vs "held". Manchester sequences: D = (mod, held) = logic 1;
--     E = (held, mod) = logic 0; F = (held, held) = no subcarrier = EOF. SOF is
--     a leading D that opens every card frame. Data bits are LSB-first, each
--     followed by its odd parity bit (D9); a trailing 2-byte CRC_A is checked
--     when present (D10). It measures FDT (D16) as the rf_clk tick count from
--     the command EOC to rf_tx_en rising.
--
-- ASSUMPTIONS (flagged -- NFC.vhd does not exist yet to validate cycle timing):
--   * rf_clk is free-running regardless of field_detect (a real "no carrier
--     when no field" gap is NOT modelled) so the DUT's field-loss reset can be
--     observed through the synchronized field level with the core clock alive.
--   * The tag's SOF bit cell begins on the tick rf_tx_en rises (no inter-symbol
--     guard is inserted); half-bit boundaries are counted from there. Subcarrier
--     "modulated" is decided by >= EDGE_THRESH rf_txmod toggles in a half-bit.
--   * A partial (bit-oriented) anticollision response is not fully byte-decoded
--     here -- obs_first_bit + obs_nbits + obs_saw_response carry the offset /
--     silence checks the tb needs (D13 solo collision scenario).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.nfc_bfm_pkg.all;

entity nfc_reader_model is
    generic (
        RF_HALF : time := 25 ns    -- rf_clk half period (compressed carrier)
    );
    port (
        -- driven BY the reader (the RF/AFE side it owns)
        rf_clk       : out std_logic := '0';
        rf_rx        : out std_logic := '1';   -- envelope: '1'=field/no-pause, '0'=pause
        field_detect : out std_logic := '0';

        -- observed FROM the DUT (load-modulation response)
        rf_txmod : in std_logic;
        rf_tx_en : in std_logic;

        -- per-transaction configuration, held stable by the tb across one frame
        cfg_field          : in std_logic := '0';
        cfg_go             : in std_logic := '0';   -- rising edge launches send+receive
        cfg_short          : in boolean   := false; -- 7-bit short frame (REQA/WUPA)
        cfg_bytes          : in nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
        cfg_nbytes         : in natural := 0;        -- whole bytes to send
        cfg_partial_bits   : in natural := 0;        -- extra bits of cfg_bytes(cfg_nbytes) (anticollision split)
        cfg_append_crc     : in boolean := false;    -- append CRC_A over the whole bytes
        cfg_corrupt_parity : in boolean := false;    -- flip byte-0 parity (D23 G3 injection)
        cfg_corrupt_crc    : in boolean := false;    -- corrupt appended CRC (negative CRC path)
        cfg_resp_parity    : in boolean := true;     -- response decode consumes a parity bit per byte
        cfg_etu            : in natural := 16;        -- bit-period ticks (compressed)
        cfg_half           : in natural := 8;         -- ETU/2
        cfg_subcdiv        : in natural := 2;         -- subcarrier half-period ticks
        cfg_pause          : in natural := 3;         -- Miller pause width ticks

        -- observations: valid/held from the end of one transaction until the next go
        obs_busy         : out std_logic := '0';
        obs_txn_count    : out natural   := 0;
        obs_saw_response : out std_logic := '0';
        obs_fdt_ticks    : out natural   := 0;
        obs_sof_ok       : out std_logic := '0';
        obs_nbytes       : out natural   := 0;
        obs_bytes        : out nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
        obs_nbits        : out natural   := 0;
        obs_first_bit    : out std_logic := '0';
        obs_parity_ok    : out std_logic := '0';
        obs_crc_ok       : out std_logic := '0'
    );
end entity nfc_reader_model;

architecture behavioral of nfc_reader_model is

    -- Manchester cell classification codes (avoid an enum type on a port/var).
    constant DCELL : natural := 1;   -- (mod, held)  = logic 1 / SOF
    constant ECELL : natural := 0;   -- (held, mod)  = logic 0
    constant FCELL : natural := 2;   -- (held, held) = EOF / no subcarrier

    constant EDGE_THRESH : natural := 2;    -- >= this many rf_txmod toggles in a half-bit = modulated
    constant FDT_GUARD   : natural := 4000; -- bounded FDT wait (never hangs)

    signal rf_clk_i : std_logic := '0';

    function to_sl(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

begin

    -- free-running compressed rf_clk (the protocol-core clock domain)
    rfgen : process
    begin
        rf_clk_i <= '0';
        wait for RF_HALF;
        rf_clk_i <= '1';
        wait for RF_HALF;
    end process;
    rf_clk <= rf_clk_i;

    -- field_detect is a plain held level the tb drives via cfg_field
    field_detect <= cfg_field;

    ---------------------------------------------------------------------------
    -- reader engine: on each rising edge of cfg_go, Miller-encode the command
    -- frame onto rf_rx, then decode the tag's load-modulation response.
    ---------------------------------------------------------------------------
    reader : process
        -- latched compressed-timing constants for this transaction
        variable etu_v, half_v, pause_v, subc_v : natural;
        variable prev_one : boolean;
        variable corr_done : boolean;
        variable txn_v : natural := 0;

        -- wait n rising rf_clk edges
        procedure rf_ticks(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(rf_clk_i);
            end loop;
        end procedure;

        -- Miller symbols (pause position within the ETU bit period)
        procedure send_Z is   -- pause in the FIRST half (SOC, or 0-after-0)
        begin
            rf_rx <= '0'; rf_ticks(pause_v);
            rf_rx <= '1'; rf_ticks(etu_v - pause_v);
        end procedure;
        procedure send_X is   -- pause in the SECOND half (logic 1)
        begin
            rf_rx <= '1'; rf_ticks(half_v);
            rf_rx <= '0'; rf_ticks(pause_v);
            rf_rx <= '1'; rf_ticks(etu_v - half_v - pause_v);
        end procedure;
        procedure send_Y is   -- no pause (logic 0 after a 1, or idle)
        begin
            rf_rx <= '1'; rf_ticks(etu_v);
        end procedure;

        -- one logic bit through the modified-Miller rule (prev_one tracked)
        procedure send_bit(bv : std_logic) is
        begin
            if to_X01(bv) = '1' then
                send_X; prev_one := true;
            else
                if prev_one then send_Y; else send_Z; end if;
                prev_one := false;
            end if;
        end procedure;

        -- one byte LSB-first + odd parity (parity of byte 0 flipped if injecting)
        procedure send_byte(bt : std_logic_vector(7 downto 0); with_parity : boolean) is
            variable par : std_logic;
        begin
            for i in 0 to 7 loop
                send_bit(bt(i));
            end loop;
            if with_parity then
                par := nfc_parity(bt);
                if cfg_corrupt_parity and not corr_done then
                    par := not par;          -- G3 injection on the first parity bit
                    corr_done := true;
                end if;
                send_bit(par);
            end if;
        end procedure;

        -- count rf_txmod toggles over n rf_clk ticks
        procedure count_edges(n : natural; cnt : out natural) is
            variable c    : natural := 0;
            variable prev : std_logic;
        begin
            prev := to_X01(rf_txmod);
            for i in 1 to n loop
                wait until rising_edge(rf_clk_i);
                if to_X01(rf_txmod) /= prev then
                    c := c + 1;
                    prev := to_X01(rf_txmod);
                end if;
            end loop;
            cnt := c;
        end procedure;

        -- classify one Manchester bit cell (two half-bit windows)
        procedure decode_cell(kind : out natural; bitval : out std_logic) is
            variable e1, e2 : natural;
        begin
            count_edges(half_v, e1);
            count_edges(half_v, e2);
            if    e1 >= EDGE_THRESH and e2 <  EDGE_THRESH then kind := DCELL; bitval := '1';
            elsif e1 <  EDGE_THRESH and e2 >= EDGE_THRESH then kind := ECELL; bitval := '0';
            elsif e1 <  EDGE_THRESH and e2 <  EDGE_THRESH then kind := FCELL; bitval := '0';
            else  kind := DCELL; bitval := '1';   -- both modulated: unexpected
            end if;
        end procedure;

        -- ---- transaction locals ------------------------------------------
        variable b        : std_logic_vector(7 downto 0);
        variable crc      : std_logic_vector(15 downto 0);
        variable kind     : natural;
        variable bv       : std_logic;
        variable fdt_v    : natural;
        variable saw      : boolean;
        variable rbytes   : nfc_byte_array(0 to NFC_MAX_BYTES - 1);
        variable bidx     : natural;
        variable nbits_v  : natural;
        variable par_ok   : boolean;
        variable crc_ok   : boolean;
        variable got_first : boolean;
        variable cur      : std_logic_vector(7 downto 0);
        variable byte_ok  : boolean;
        variable pv       : std_logic;
    begin
        rf_rx    <= '1';
        obs_busy <= '0';
        loop
            wait until to_X01(cfg_go) = '1';
            obs_busy <= '1';

            -- latch this transaction's compressed timing + reset obs
            etu_v   := cfg_etu;  half_v := cfg_half;
            pause_v := cfg_pause; subc_v := cfg_subcdiv;
            prev_one := false; corr_done := false;
            obs_saw_response <= '0'; obs_sof_ok <= '0';
            obs_nbytes <= 0; obs_nbits <= 0; obs_first_bit <= '0';
            obs_parity_ok <= '0'; obs_crc_ok <= '0'; obs_fdt_ticks <= 0;
            rbytes := (others => (others => '0'));

            ---------------------------------------------------------------
            -- ENCODE the reader command frame
            ---------------------------------------------------------------
            send_Z;                       -- SOC (Z out of idle)
            prev_one := false;
            if cfg_short then
                b := cfg_bytes(0);
                for i in 0 to 6 loop      -- 7 data bits, no parity (short frame)
                    send_bit(b(i));
                end loop;
            else
                for j in 0 to cfg_nbytes - 1 loop
                    send_byte(cfg_bytes(j), true);
                end loop;
                if cfg_append_crc then
                    crc := nfc_crc_a(cfg_bytes, cfg_nbytes);
                    if cfg_corrupt_crc then
                        crc := crc xor x"0100";       -- corrupt the high CRC byte
                    end if;
                    send_byte(crc(7 downto 0),  true);   -- LOW byte first (D10)
                    send_byte(crc(15 downto 8), true);
                end if;
                if cfg_partial_bits > 0 then
                    b := cfg_bytes(cfg_nbytes);   -- split byte, NO parity (D8/D9)
                    for i in 0 to cfg_partial_bits - 1 loop
                        send_bit(b(i));
                    end loop;
                end if;
            end if;
            rf_rx <= '1';                 -- EOC: idle (no modulation) >= 2 ETUs
            rf_ticks(2 * etu_v);

            ---------------------------------------------------------------
            -- MEASURE FDT + DECODE the tag response
            ---------------------------------------------------------------
            fdt_v := 0; saw := false;
            for i in 0 to FDT_GUARD loop
                exit when to_X01(rf_tx_en) = '1';
                wait until rising_edge(rf_clk_i);
                fdt_v := fdt_v + 1;
            end loop;
            saw := (to_X01(rf_tx_en) = '1');
            obs_saw_response <= to_sl(saw);
            obs_fdt_ticks    <= fdt_v;

            if saw then
                bidx := 0; nbits_v := 0; par_ok := true; crc_ok := false;
                got_first := false;
                decode_cell(kind, bv);            -- SOF (expect D = 1)
                obs_sof_ok <= to_sl(kind = DCELL);

                -- data bytes: 8 LSB-first data bits (+ parity) until EOF (F)
                loop
                    byte_ok := true;
                    for i in 0 to 7 loop
                        exit when to_X01(rf_tx_en) = '0';
                        decode_cell(kind, bv);
                        if kind = FCELL then byte_ok := false; exit; end if;
                        cur(i) := bv;
                        nbits_v := nbits_v + 1;
                        if not got_first then
                            got_first := true;
                            obs_first_bit <= bv;
                        end if;
                    end loop;
                    exit when not byte_ok;
                    if cfg_resp_parity then
                        decode_cell(kind, pv);
                        if kind = FCELL then exit; end if;
                        if pv /= nfc_parity(cur) then par_ok := false; end if;
                    end if;
                    rbytes(bidx) := cur;
                    bidx := bidx + 1;
                    exit when bidx >= NFC_MAX_BYTES;
                    exit when to_X01(rf_tx_en) = '0';
                end loop;

                -- CRC_A check: recompute over the payload, compare the trailing
                -- 2 bytes (LOW then HIGH on air). Independent of the tb.
                if bidx >= 2 then
                    crc := nfc_crc_a(rbytes, bidx - 2);
                    crc_ok := (rbytes(bidx - 2) = crc(7 downto 0)) and
                              (rbytes(bidx - 1) = crc(15 downto 8));
                end if;

                obs_bytes     <= rbytes;
                obs_nbytes    <= bidx;
                obs_nbits     <= nbits_v;
                obs_parity_ok <= to_sl(par_ok);
                obs_crc_ok    <= to_sl(crc_ok);
            end if;

            txn_v := txn_v + 1;
            obs_busy      <= '0';
            obs_txn_count <= txn_v;   -- published LAST: the tb's completion handshake
                                      -- (cfg_go is a short pulse, so no wait-for-'0' here
                                      -- -- avoids the wait-until-already-false hang).
        end loop;
    end process reader;

end architecture behavioral;
