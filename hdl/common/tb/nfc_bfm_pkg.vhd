-------------------------------------------------------------------------------
-- nfc_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the NFC ISO 14443A tag / card-emulation peripheral testbench (tb/NFC_tb.vhd) and its behavioral reader model (tb/nfc_reader_model.vhd).
-- As with i3c_bfm_pkg.vhd, NFC.vhd is being written in parallel against the same FROZEN design (~/vesta_docs/digperiphs/nfc_design.md, R3 and S8) this bench targets.
-- The slot numbers, field-packing helpers and SR-bit positions below are therefore LOCAL to this bench and not shared MemoryMap.vhd constants: NFC0 lives at 0x6200, and MemoryMap.vhd has no NFC slot constants yet.
--
-- CHECKER-INDEPENDENCE, the I3C and QSPI-8d lesson and this task's explicit instruction.
-- The ONLY protocol reference this package shares between the reader model, which drives and decodes the wire, and NFC_tb.vhd, which computes expected values, are the spec-LITERAL single-reading utilities nfc_crc_a() (D10), nfc_parity() (D9) and nfc_bcc() (D12).
-- The modified-Miller pause encode (D6) and the Manchester-on-subcarrier decode (D7) live ENTIRELY inside nfc_reader_model.vhd as signal-level logic.
-- They are deliberately NOT provided here as shared formulas, so the reader's decode and the tb's expectations cannot collapse onto one shared codec function.
-- This is a small deviation from the design doc's S13 suggested helper list, which named nfc_miller_encode() and nfc_manchester_decode() as package helpers; it is flagged in the bench author's report, and the over-the-wire hand-computed CRC frame check in NFC_tb.vhd is the independent anchor the doc asked for.
--
-- Frozen register map (word slots at 0x6200, design doc S8/D17):
--   0 NFCxCR   1 NFCxSR   2 NFCxUID  3 NFCxCFG  4 NFCxTIM
--   5 NFCxRXST 6 NFCxIDX  7 NFCxDATA 8 NFCxTXCTL 9 NFCxDBG
-- Slot 8, TXCTL on the firmware-response path, is INERT in the AUTOREAD=1 MVP (D17) and is declared here for completeness but not exercised by this bench.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package nfc_bfm_pkg is

    -- ---- Register word-slot map, frozen by design doc S8 ------------------
    constant SlotNFCxCR    : natural := 0;
    constant SlotNFCxSR    : natural := 1;
    constant SlotNFCxUID   : natural := 2;
    constant SlotNFCxCFG   : natural := 3;
    constant SlotNFCxTIM   : natural := 4;
    constant SlotNFCxRXST  : natural := 5;
    constant SlotNFCxIDX   : natural := 6;
    constant SlotNFCxDATA  : natural := 7;
    constant SlotNFCxTXCTL : natural := 8;   -- Inert in the AUTOREAD MVP.
    constant SlotNFCxDBG   : natural := 9;

    -- ---- NFCxSR bit positions, design doc D17; r is read-only, rw1c is write-1-to-clear.
    constant SrBitBUSY     : natural := 0;   -- r
    constant SrBitFIELDF   : natural := 1;   -- rw1c
    constant SrBitRXFRAMEF : natural := 2;   -- rw1c
    constant SrBitTXDONEF  : natural := 3;   -- rw1c
    constant SrBitCRCERRF  : natural := 4;   -- rw1c
    constant SrBitPARERRF  : natural := 5;   -- rw1c
    constant SrBitFIELDLIVE : natural := 6;  -- r
    constant SrBitHALTED   : natural := 7;   -- r
    constant SrStateLo     : natural := 8;   -- Low bit of the read-only STATE field, bits 11:8.

    -- ---- NFCxCR bit positions, design doc D17 -----------------------------
    constant CrBitNFCEN    : natural := 0;
    constant CrBitLISTEN   : natural := 1;
    constant CrBitHALTCLR  : natural := 2;
    constant CrBitFIELDIE  : natural := 8;
    constant CrBitRXFIE    : natural := 9;
    constant CrBitTXIE     : natural := 10;
    constant CrBitCRCIE    : natural := 11;
    constant CrBitAUTOREAD : natural := 12;

    -- ---- FSM state encodings reported in SR bits 11:8, design doc D11/D17 --
    constant StPOWEROFF : natural := 0;
    constant StIDLE     : natural := 1;
    constant StREADY    : natural := 2;
    constant StACTIVE   : natural := 3;
    constant StHALT     : natural := 4;

    -- ---- Byte array shared with the reader model --------------------------
    constant NFC_MAX_BYTES : natural := 32;   -- Generously above a 16-byte READ response plus its CRC.
    type nfc_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- D9: odd per-byte parity, sent LSB-first on air, chosen so {8 data bits, parity} carries an ODD number of ones, i.e. parity = not(b0 xor ... xor b7).
    -- Spec-literal with a single reading, so it is shared by the reader model and the tb.
    function nfc_parity(data : std_logic_vector(7 downto 0)) return std_logic;

    -- D12: the block check character BCC is uid0 xor uid1 xor uid2 xor uid3, derived in hardware.
    function nfc_bcc(u0, u1, u2, u3 : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- D10: CRC_A per ISO/IEC 14443-3, reflected polynomial 0x8408 with init 0x6363.
    -- Returns the 16-bit register; on air the LOW byte crc(7:0) is sent first, then the HIGH byte crc(15:8), each LSB-first.
    -- ISO Annex B gives the reference value CRC_A of {00,00} as 0x1EA0.
    function nfc_crc_a(data : nfc_byte_array; n : natural)
        return std_logic_vector;

    -- Build a full 32-bit NFCxCR word in the D17 field layout.
    function nfc_mk_cr(nfcen, listen, autoread            : std_logic;
                       fieldie, rxfie, txie, crcie        : std_logic;
                       rfdiv                              : std_logic_vector(3 downto 0) := (others => '0'))
        return std_logic_vector;

    -- Build a full 32-bit NFCxCFG word (D17): ATQA in bits 15:0, SAK in bits 23:16.
    function nfc_mk_cfg(atqa : std_logic_vector(15 downto 0);
                        sak  : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit NFCxTIM word (D17): FDT in bits 15:0, ETU in bits 23:16, SUBCDIV in bits 31:24.
    function nfc_mk_tim(fdt : natural; etu : natural; subcdiv : natural)
        return std_logic_vector;

    -- Build a full 32-bit NFCxIDX word (D17): IDX in bits 5:0, IDXAINC in bit 6, IDXSEL in bit 8.
    function nfc_mk_idx(idx : natural; ainc : std_logic; sel : std_logic)
        return std_logic_vector;

    -- Bounded poll of NFCxSR.BUSY (bit 0) until it reads '0'.
    -- It never hangs: done_ok comes back false if BUSY has not cleared within the guard count, mirroring i3c_wait_busy_clear.
    procedure nfc_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of a single NFCxSR bit until it reads '1'.
    -- It never hangs: done_ok comes back false if the bit has not set within the guard count.
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
        return not p;                 -- Inverting the XOR-reduce gives odd parity over {data, parity}.
    end function;

    function nfc_bcc(u0, u1, u2, u3 : std_logic_vector(7 downto 0))
        return std_logic_vector is
    begin
        return u0 xor u1 xor u2 xor u3;
    end function;

    function nfc_crc_a(data : nfc_byte_array; n : natural)
        return std_logic_vector is
        variable crc : std_logic_vector(15 downto 0) := x"6363";   -- ISO 14443-3 initial value.
        variable b   : std_logic_vector(7 downto 0);
    begin
        -- Fold each byte into the low half, then run eight LFSR steps.
        for j in 0 to n - 1 loop
            b := data(data'low + j);
            crc(7 downto 0) := crc(7 downto 0) xor b;
            for i in 0 to 7 loop            -- Bit-serial reflected LFSR, polynomial 0x8408.
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
            exit when guard > 8000;    -- Bounded, so it never hangs.
                                       -- A full 16-byte READ response is the longest wait here and clears well inside this budget.
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
            exit when guard > 8000;    -- Same bound as the BUSY poll above.
        end loop;
    end procedure;

end package body nfc_bfm_pkg;
