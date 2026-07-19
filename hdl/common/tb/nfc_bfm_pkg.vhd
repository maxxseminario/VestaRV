-------------------------------------------------------------------------------
-- nfc_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the NFC ISO 14443A tag/card-emulation peripheral
-- testbench (tb/NFC_tb.vhd) and its behavioral reader model
-- (tb/nfc_reader_model.vhd). Like i3c_bfm_pkg.vhd, NFC.vhd is being written in
-- parallel against the same FROZEN design (~/vesta_docs/digperiphs/nfc_design.md,
-- R3 + S8) this bench targets -- the slot numbers, field-packing helpers and
-- SR-bit positions below are LOCAL to this bench, not shared MemoryMap.vhd
-- constants (NFC0 lives at 0x6200; MemoryMap.vhd has no NFC slot constants yet).
--
-- CHECKER-INDEPENDENCE (the I3C / QSPI-8d lesson, and this task's explicit
-- instruction): the ONLY protocol reference this package shares between the
-- reader model (which drives/decodes the wire) and NFC_tb.vhd (which computes
-- expected values) are the two spec-LITERAL, single-reading utilities
-- nfc_crc_a() (D10) and nfc_parity()/nfc_bcc() (D9/D12). The modified-Miller
-- pause encode (D6) and the Manchester-on-subcarrier decode (D7) live ENTIRELY
-- inside nfc_reader_model.vhd as signal-level logic -- they are deliberately
-- NOT provided here as shared formulas, so the reader's decode and the tb's
-- expectations cannot collapse onto one shared codec function. (This is a small
-- deviation from the design doc's S13 suggested helper list, which named
-- nfc_miller_encode()/nfc_manchester_decode() as pkg helpers -- flagged in the
-- bench author's report; the over-the-wire hand-computed CRC frame check in
-- NFC_tb.vhd is the independent anchor the doc asked for.)
--
-- Frozen register map (word slots @0x6200, design doc S8/D17):
--   0 NFCxCR   1 NFCxSR   2 NFCxUID  3 NFCxCFG  4 NFCxTIM
--   5 NFCxRXST 6 NFCxIDX  7 NFCxDATA 8 NFCxTXCTL 9 NFCxDBG
-- Slot 8 (TXCTL, firmware-response path) is INERT in the AUTOREAD=1 MVP (D17)
-- and is declared here for completeness but not exercised by this bench.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package nfc_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc S8) -------------------
    constant SlotNFCxCR    : natural := 0;
    constant SlotNFCxSR    : natural := 1;
    constant SlotNFCxUID   : natural := 2;
    constant SlotNFCxCFG   : natural := 3;
    constant SlotNFCxTIM   : natural := 4;
    constant SlotNFCxRXST  : natural := 5;
    constant SlotNFCxIDX   : natural := 6;
    constant SlotNFCxDATA  : natural := 7;
    constant SlotNFCxTXCTL : natural := 8;   -- inert in the AUTOREAD MVP
    constant SlotNFCxDBG   : natural := 9;

    -- ---- NFCxSR bit positions (design doc D17) ----------------------------
    constant SrBitBUSY     : natural := 0;   -- r
    constant SrBitFIELDF   : natural := 1;   -- rw1c
    constant SrBitRXFRAMEF : natural := 2;   -- rw1c
    constant SrBitTXDONEF  : natural := 3;   -- rw1c
    constant SrBitCRCERRF  : natural := 4;   -- rw1c
    constant SrBitPARERRF  : natural := 5;   -- rw1c
    constant SrBitFIELDLIVE : natural := 6;  -- r
    constant SrBitHALTED   : natural := 7;   -- r
    constant SrStateLo     : natural := 8;   -- [11:8] STATE (r)

    -- ---- NFCxCR bit positions (design doc D17) ----------------------------
    constant CrBitNFCEN    : natural := 0;
    constant CrBitLISTEN   : natural := 1;
    constant CrBitHALTCLR  : natural := 2;
    constant CrBitFIELDIE  : natural := 8;
    constant CrBitRXFIE    : natural := 9;
    constant CrBitTXIE     : natural := 10;
    constant CrBitCRCIE    : natural := 11;
    constant CrBitAUTOREAD : natural := 12;

    -- ---- FSM state encodings (design doc D11/D17, SR[11:8]) ---------------
    constant StPOWEROFF : natural := 0;
    constant StIDLE     : natural := 1;
    constant StREADY    : natural := 2;
    constant StACTIVE   : natural := 3;
    constant StHALT     : natural := 4;

    -- ---- byte array shared with the reader model --------------------------
    constant NFC_MAX_BYTES : natural := 32;   -- generously above a 16-byte READ + CRC
    type nfc_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- D9: odd per-byte parity, LSB-first on air. parity chosen so {8 data bits,
    -- parity} has an ODD number of 1s: parity = not(b0 xor .. xor b7). Spec-
    -- literal, single reading; shared by the reader model and the tb.
    function nfc_parity(data : std_logic_vector(7 downto 0)) return std_logic;

    -- D12: BCC = uid0 xor uid1 xor uid2 xor uid3 (block check char, HW-derived).
    function nfc_bcc(u0, u1, u2, u3 : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- D10: CRC_A per ISO/IEC 14443-3 (reflected 0x8408, init 0x6363). Returns
    -- the 16-bit register; on air the LOW byte crc(7:0) is sent first, then the
    -- HIGH byte crc(15:8), each LSB-first. ISO Annex B: CRC_A({00,00})=0x1EA0.
    function nfc_crc_a(data : nfc_byte_array; n : natural)
        return std_logic_vector;

    -- Build a full 32-bit NFCxCR word (D17 field layout).
    function nfc_mk_cr(nfcen, listen, autoread            : std_logic;
                       fieldie, rxfie, txie, crcie        : std_logic;
                       rfdiv                              : std_logic_vector(3 downto 0) := (others => '0'))
        return std_logic_vector;

    -- Build a full 32-bit NFCxCFG word (D17): [15:0]ATQA [23:16]SAK.
    function nfc_mk_cfg(atqa : std_logic_vector(15 downto 0);
                        sak  : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit NFCxTIM word (D17): [15:0]FDT [23:16]ETU [31:24]SUBCDIV.
    function nfc_mk_tim(fdt : natural; etu : natural; subcdiv : natural)
        return std_logic_vector;

    -- Build a full 32-bit NFCxIDX word (D17): [5:0]IDX [6]IDXAINC [8]IDXSEL.
    function nfc_mk_idx(idx : natural; ainc : std_logic; sel : std_logic)
        return std_logic_vector;

    -- Bounded poll of NFCxSR.BUSY (bit 0) until it reads '0'. done_ok=false
    -- (never hangs) if BUSY has not cleared within the guard count -- mirrors
    -- i3c_wait_busy_clear.
    procedure nfc_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of a single NFCxSR bit until it reads '1'. done_ok=false
    -- (never hangs) if the bit has not set within the guard count.
    procedure nfc_wait_sr_bit_set(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  bit_idx          : in    natural;
                                  done_ok          : out   boolean);

end package nfc_bfm_pkg;


package body nfc_bfm_pkg is

    function nfc_parity(data : std_logic_vector(7 downto 0)) return std_logic is
        variable p : std_logic := '0';
    begin
        for i in data'range loop
            p := p xor data(i);
        end loop;
        return not p;                 -- odd parity of {data, parity}
    end function;

    function nfc_bcc(u0, u1, u2, u3 : std_logic_vector(7 downto 0))
        return std_logic_vector is
    begin
        return u0 xor u1 xor u2 xor u3;
    end function;

    function nfc_crc_a(data : nfc_byte_array; n : natural)
        return std_logic_vector is
        variable crc : std_logic_vector(15 downto 0) := x"6363";   -- init
        variable b   : std_logic_vector(7 downto 0);
    begin
        for j in 0 to n - 1 loop
            b := data(data'low + j);
            crc(7 downto 0) := crc(7 downto 0) xor b;
            for i in 0 to 7 loop            -- bit-serial reflected LFSR, poly 0x8408
                if crc(0) = '1' then
                    crc := ('0' & crc(15 downto 1)) xor x"8408";
                else
                    crc := ('0' & crc(15 downto 1));
                end if;
            end loop;
        end loop;
        return crc;
    end function;

    function nfc_mk_cr(nfcen, listen, autoread     : std_logic;
                       fieldie, rxfie, txie, crcie : std_logic;
                       rfdiv                       : std_logic_vector(3 downto 0) := (others => '0'))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(CrBitNFCEN)    := nfcen;
        v(CrBitLISTEN)   := listen;
        v(CrBitFIELDIE)  := fieldie;
        v(CrBitRXFIE)    := rxfie;
        v(CrBitTXIE)     := txie;
        v(CrBitCRCIE)    := crcie;
        v(CrBitAUTOREAD) := autoread;
        v(19 downto 16)  := rfdiv;
        return v;
    end function;

    function nfc_mk_cfg(atqa : std_logic_vector(15 downto 0);
                        sak  : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(15 downto 0)  := atqa;
        v(23 downto 16) := sak;
        return v;
    end function;

    function nfc_mk_tim(fdt : natural; etu : natural; subcdiv : natural)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(15 downto 0)  := std_logic_vector(to_unsigned(fdt, 16));
        v(23 downto 16) := std_logic_vector(to_unsigned(etu, 8));
        v(31 downto 24) := std_logic_vector(to_unsigned(subcdiv, 8));
        return v;
    end function;

    function nfc_mk_idx(idx : natural; ainc : std_logic; sel : std_logic)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(5 downto 0) := std_logic_vector(to_unsigned(idx, 6));
        v(6)          := ainc;
        v(8)          := sel;
        return v;
    end function;

    procedure nfc_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotNFCxSR, s);
            if to_X01(s(SrBitBUSY)) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 8000;    -- bounded (never hangs); a full 16-byte
                                       -- READ response is the longest wait and
                                       -- clears well inside this budget.
        end loop;
    end procedure;

    procedure nfc_wait_sr_bit_set(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  bit_idx          : in    natural;
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotNFCxSR, s);
            if to_X01(s(bit_idx)) = '1' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 8000;
        end loop;
    end procedure;

end package body nfc_bfm_pkg;
