-------------------------------------------------------------------------------
-- nfc_reader_model.vhd: behavioral ISO 14443A reader (PCD) model closing the RF link for the NFC card-emulation testbench, sharing no encode or decode logic with the DUT beyond the spec-literal CRC_A and parity helpers in nfc_bfm_pkg, and taking a per-transaction cfg_* shape held stable across one frame.
-- It generates the compressed rf_clk and field_detect, Miller pause-encodes commands on rf_rx (Z is a pause in the first ETU half, X in the second, Y no pause: SOC is Z, logic 1 is X, logic 0 is Y after a 1 else Z, EOC is two idle bit periods), then decodes the response from rf_txmod and rf_tx_en per half-bit window (D is logic 1 and the SOF, E is logic 0, F is no subcarrier and ends the frame) LSB-first with odd parity and a trailing CRC_A, measuring FDT in rf_clk ticks from EOC to rf_tx_en rising.
-- rf_clk is free-running regardless of field_detect, so field loss is observed through the synchronized level with the clock alive; the tag SOF cell starts on the tick rf_tx_en rises and a half-bit counts as modulated at EDGE_THRESH toggles or more.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.nfc_bfm_pkg.all;

entity nfc_reader_model is
    generic (
        RF_HALF : time := 25 ns    -- rf_clk half period, the compressed carrier.
    );
    port (
        -- Driven BY the reader: the RF and AFE side it owns.
        rf_clk       : out std_logic := '0';
        rf_rx        : out std_logic := '1';   -- Envelope: '1' is field with no pause, '0' is a pause.
        field_detect : out std_logic := '0';

        -- Observed FROM the DUT: the load-modulation response.
        rf_txmod : in std_logic;
        rf_tx_en : in std_logic;

        -- Per-transaction configuration, held stable by the tb across one frame.
        cfg_field          : in std_logic := '0';
        cfg_go             : in std_logic := '0';   -- A rising edge launches one send then receive.
        cfg_short          : in boolean   := false; -- 7-bit short frame (REQA/WUPA).
        cfg_bytes          : in nfc_byte_array(0 to NFC_MAX_BYTES - 1) := (others => (others => '0'));
        cfg_nbytes         : in natural := 0;        -- Whole bytes to send.
        cfg_partial_bits   : in natural := 0;        -- Extra bits of cfg_bytes(cfg_nbytes), the anticollision split.
        cfg_append_crc     : in boolean := false;    -- Append CRC_A over the whole bytes.
        cfg_corrupt_parity : in boolean := false;    -- Flip byte-0 parity (negative parity path).
        cfg_corrupt_crc    : in boolean := false;    -- Corrupt the appended CRC (negative CRC path).
        cfg_resp_parity    : in boolean := true;     -- Response decode consumes a parity bit per byte.
        cfg_etu            : in natural := 16;        -- Bit-period ticks (compressed).
        cfg_half           : in natural := 8;         -- Half an ETU.
        cfg_subcdiv        : in natural := 2;         -- Subcarrier half-period ticks.
        cfg_pause          : in natural := 3;         -- Miller pause width in ticks.

        -- Observations, valid and held from the end of one transaction until the next go.
        -- A bit-oriented anticollision response is not byte-decoded: obs_first_bit, obs_nbits and obs_saw_response carry its offset and silence checks.
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

    -- Manchester cell classification codes, kept as naturals to avoid an enum type on a port or variable.
    constant DCELL : natural := 1;   -- (mod, held)  = logic 1 or SOF
    constant ECELL : natural := 0;   -- (held, mod)  = logic 0
    constant FCELL : natural := 2;   -- (held, held) = EOF, no subcarrier

    constant EDGE_THRESH : natural := 2;    -- This many rf_txmod toggles in a half-bit, or more, counts as modulated.
    constant FDT_GUARD   : natural := 4000; -- Bounded FDT wait so the model never hangs.

    signal rf_clk_i : std_logic := '0';

    -- Boolean to std_logic helper for publishing pass/fail results on obs_* ports.
    function to_sl(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

begin

    -- Free-running compressed rf_clk, the protocol-core clock domain.
    rfgen : process
    begin
        rf_clk_i <= '0';
        wait for RF_HALF;
        rf_clk_i <= '1';
        wait for RF_HALF;
    end process;
    rf_clk <= rf_clk_i;

    -- field_detect is a plain held level the tb drives through cfg_field.
    field_detect <= cfg_field;

    -- Reader engine: on each rising edge of cfg_go, Miller-encode the command frame onto rf_rx, then decode the tag's load-modulation response.
    reader : process
        -- Compressed-timing constants latched for this transaction.
        variable etu_v, half_v, pause_v, subc_v : natural;
        variable prev_one : boolean;
        variable corr_done : boolean;
        variable txn_v : natural := 0;

        -- Wait for n rising rf_clk edges.
        procedure rf_ticks(n : natural) is
        begin
            for i in 1 to n loop
                wait until rising_edge(rf_clk_i);
            end loop;
        end procedure;

        -- Miller symbols, distinguished by the pause position within the ETU bit period.
        procedure send_Z is   -- Pause in the FIRST half: SOC, or a 0 after a 0.
        begin
            rf_rx <= '0'; rf_ticks(pause_v);
            rf_rx <= '1'; rf_ticks(etu_v - pause_v);
        end procedure;
        procedure send_X is   -- Pause in the SECOND half: logic 1.
        begin
            rf_rx <= '1'; rf_ticks(half_v);
            rf_rx <= '0'; rf_ticks(pause_v);
            rf_rx <= '1'; rf_ticks(etu_v - half_v - pause_v);
        end procedure;
        procedure send_Y is   -- No pause: logic 0 after a 1, or idle.
        begin
            rf_rx <= '1'; rf_ticks(etu_v);
        end procedure;

        -- One logic bit through the modified-Miller rule, with prev_one tracking the previous symbol.
        procedure send_bit(bv : std_logic) is
        begin
            if to_X01(bv) = '1' then
                send_X; prev_one := true;
            else
                if prev_one then send_Y; else send_Z; end if;
                prev_one := false;
            end if;
        end procedure;

        -- One byte LSB-first plus odd parity, with byte 0's parity flipped when injecting.
        procedure send_byte(bt : std_logic_vector(7 downto 0); with_parity : boolean) is
            variable par : std_logic;
        begin
            for i in 0 to 7 loop
                send_bit(bt(i));
            end loop;
            if with_parity then
                par := nfc_parity(bt);
                if cfg_corrupt_parity and not corr_done then
                    par := not par;          -- Injection hits the first parity bit only.
                    corr_done := true;
                end if;
                send_bit(par);
            end if;
        end procedure;

        -- Count rf_txmod toggles over n rf_clk ticks.
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

        -- Classify one Manchester bit cell from its two half-bit windows.
        procedure decode_cell(kind : out natural; bitval : out std_logic) is
            variable e1, e2 : natural;
        begin
            count_edges(half_v, e1);
            count_edges(half_v, e2);
            if    e1 >= EDGE_THRESH and e2 <  EDGE_THRESH then kind := DCELL; bitval := '1';
            elsif e1 <  EDGE_THRESH and e2 >= EDGE_THRESH then kind := ECELL; bitval := '0';
            elsif e1 <  EDGE_THRESH and e2 <  EDGE_THRESH then kind := FCELL; bitval := '0';
            else  kind := DCELL; bitval := '1';   -- Both halves modulated: unexpected, treated as a D cell.
            end if;
        end procedure;

        -- ---- Transaction locals ------------------------------------------
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

            -- Latch this transaction's compressed timing and clear every observation.
            etu_v   := cfg_etu;  half_v := cfg_half;
            pause_v := cfg_pause; subc_v := cfg_subcdiv;
            prev_one := false; corr_done := false;
            obs_saw_response <= '0'; obs_sof_ok <= '0';
            obs_nbytes <= 0; obs_nbits <= 0; obs_first_bit <= '0';
            obs_parity_ok <= '0'; obs_crc_ok <= '0'; obs_fdt_ticks <= 0;
            rbytes := (others => (others => '0'));

            -- ENCODE the reader command frame.
            send_Z;                       -- SOC: a Z symbol out of idle.
            prev_one := false;
            if cfg_short then
                b := cfg_bytes(0);
                for i in 0 to 6 loop      -- Short frame: 7 data bits, no parity.
                    send_bit(b(i));
                end loop;
            else
                for j in 0 to cfg_nbytes - 1 loop
                    send_byte(cfg_bytes(j), true);
                end loop;
                if cfg_append_crc then
                    crc := nfc_crc_a(cfg_bytes, cfg_nbytes);
                    if cfg_corrupt_crc then
                        crc := crc xor x"0100";       -- Corrupt the high CRC byte.
                    end if;
                    send_byte(crc(7 downto 0),  true);   -- LOW byte first.
                    send_byte(crc(15 downto 8), true);
                end if;
                if cfg_partial_bits > 0 then
                    b := cfg_bytes(cfg_nbytes);   -- Split byte, sent with NO parity.
                    for i in 0 to cfg_partial_bits - 1 loop
                        send_bit(b(i));
                    end loop;
                end if;
            end if;
            rf_rx <= '1';                 -- EOC: idle with no modulation for at least 2 ETUs.
            rf_ticks(2 * etu_v);

            -- MEASURE the FDT, then DECODE the tag response.
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
                decode_cell(kind, bv);            -- SOF: expect a D cell, logic 1.
                obs_sof_ok <= to_sl(kind = DCELL);

                -- Data bytes: 8 LSB-first data bits plus parity, repeated until the EOF F cell.
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

                -- CRC_A check, independent of the tb: recompute over the payload and compare the trailing 2 bytes, LOW then HIGH on air.
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
            obs_txn_count <= txn_v;   -- Published LAST: this is the tb's completion handshake.
                                      -- cfg_go is a short pulse, so never wait for it to fall here; the condition is already false and the wait would hang.
        end loop;
    end process reader;

end architecture behavioral;
