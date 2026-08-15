-------------------------------------------------------------------------------
-- qspi_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the QSPI peripheral testbench (tb/QSPI_tb.vhd) and its flash-responder model (tb/qspi_flash_model.vhd).
-- QSPI has no MemoryMap.vhd register-slot constants yet, because the RTL (hdl/common/periph/QSPI.vhd) is being written in parallel against the same frozen register map this package encodes.
-- The slot numbers and field-packing helpers below are therefore LOCAL to this bench, not shared package constants, and should be reconciled with MemoryMap.vhd once QSPI.vhd lands if the peripheral ever gets folded into the shared register map.
--
-- Frozen register map (word slots): see the QSPI_tb.vhd header for the full field layout this package's mk_cr and mk_cmd functions implement.
--
-- qspi_read_pattern() is the ONE shared formula for the flash model's deterministic READ data: both qspi_flash_model.vhd (to drive it) and QSPI_tb.vhd (to compute the expected value for each check) call this same function.
-- That means the tb's "expected" value and the model's "actual" value are NOT independently derived, so a bug shared between the formula's intent and its one implementation would not be caught by these checks.
-- This is a deliberate scope trade-off (flagged in the bench author's report) given QSPI.vhd does not exist yet to validate cycle-level behavior against anyway.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package qspi_bfm_pkg is

    -- ---- register word-slot map (frozen) ----------------------------------
    constant SlotQSPIxCR  : natural := 0;
    constant SlotQSPIxCMD : natural := 1;
    constant SlotQSPIxADR : natural := 2;
    constant SlotQSPIxTX  : natural := 3;
    constant SlotQSPIxRX  : natural := 4;
    constant SlotQSPIxSR  : natural := 5;

    -- CMDW/ADRW/DATW field decode: 00=1-bit, 01=2-bit, 10=4-bit.
    -- "11" is UNDEFINED in the frozen contract and is never driven by this bench; it is decoded here as 1-bit purely so the helper is total (see the QSPI_tb.vhd ambiguity note).
    function qspi_width_lanes(w : std_logic_vector(1 downto 0)) return natural;

    -- AWID field decode: 00=none, 01=24-bit, 10=32-bit.
    -- "11" is undefined and yields 0 (no address phase); it is never driven by this bench.
    function qspi_awid_bits(w : std_logic_vector(1 downto 0)) return natural;

    -- CMD.DLEN field decode: 00=none, 01=8-bit, 10=16-bit, 11=32-bit.
    function qspi_dlen_bits(w : std_logic_vector(1 downto 0)) return natural;

    -- Build a full 32-bit CR word from named fields.
    -- Bit positions per the frozen map: EN=0, CMDW=2:1, ADRW=4:3, DATW=6:5, CPOL=7, CPHA=8, AWID=10:9, DUMMY=15:11, CSSEL=18:16 (written 0), BR=26:19, TCIE=27, RXFIE=28.
    function qspi_mk_cr(en, cpol, cpha, tcie, rxfie : std_logic;
                        cmdw, adrw, datw, awid       : std_logic_vector(1 downto 0);
                        dummy                        : std_logic_vector(4 downto 0);
                        br                           : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit CMD word (opcode=7:0, DLEN=9:8, DIR=10).
    -- Writing this word with byte lane 0 enabled, which is true of every bus_write since it enables all four lanes, LAUNCHES the transaction.
    function qspi_mk_cmd(opcode : std_logic_vector(7 downto 0);
                         dlen   : std_logic_vector(1 downto 0);
                         dir    : std_logic)
        return std_logic_vector;

    -- Deterministic READ-data reference: 4 MSB-first bytes, byte i = seed xor (addr(7:0) + i), where i=0 is the FIRST and most significant byte shifted out.
    -- Shared by qspi_flash_model.vhd, which drives it, and QSPI_tb.vhd, which expects it.
    function qspi_read_pattern(addr : std_logic_vector(31 downto 0);
                               seed : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Bounded poll of SR.BUSY (bit 0) via the shared register-bus BFM.
    -- done_ok comes back false (the poll never hangs) if BUSY has not cleared within the guard count, mirroring the wait_master_done idiom in SPI_flash_tb.vhd.
    procedure qspi_wait_busy_clear(signal clk       : in    std_logic;
                                   signal b         : inout periph_bus_t;
                                   signal read_data : in    std_logic_vector(31 downto 0);
                                   done_ok          : out   boolean);

end package qspi_bfm_pkg;


package body qspi_bfm_pkg is

    function qspi_width_lanes(w : std_logic_vector(1 downto 0)) return natural is
    begin
        case w is
            when "00"   => return 1;
            when "01"   => return 2;
            when "10"   => return 4;
            when others => return 1;   -- "11" reserved/undefined
        end case;
    end function;

    function qspi_awid_bits(w : std_logic_vector(1 downto 0)) return natural is
    begin
        case w is
            when "00"   => return 0;
            when "01"   => return 24;
            when "10"   => return 32;
            when others => return 0;   -- "11" reserved/undefined
        end case;
    end function;

    function qspi_dlen_bits(w : std_logic_vector(1 downto 0)) return natural is
    begin
        case w is
            when "00"   => return 0;
            when "01"   => return 8;
            when "10"   => return 16;
            when others => return 32;
        end case;
    end function;

    function qspi_mk_cr(en, cpol, cpha, tcie, rxfie : std_logic;
                        cmdw, adrw, datw, awid       : std_logic_vector(1 downto 0);
                        dummy                        : std_logic_vector(4 downto 0);
                        br                           : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(0)            := en;
        v(2 downto 1)   := cmdw;
        v(4 downto 3)   := adrw;
        v(6 downto 5)   := datw;
        v(7)            := cpol;
        v(8)            := cpha;
        v(10 downto 9)  := awid;
        v(15 downto 11) := dummy;
        v(18 downto 16) := "000";        -- CSSEL: write 0
        v(26 downto 19) := br;
        v(27)           := tcie;
        v(28)           := rxfie;
        return v;
    end function;

    function qspi_mk_cmd(opcode : std_logic_vector(7 downto 0);
                         dlen   : std_logic_vector(1 downto 0);
                         dir    : std_logic)
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(7 downto 0) := opcode;
        v(9 downto 8) := dlen;
        v(10)         := dir;
        return v;
    end function;

    function qspi_read_pattern(addr : std_logic_vector(31 downto 0);
                               seed : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable w : std_logic_vector(31 downto 0);
    begin
        -- Byte 0 is the most significant, matching the MSB-first shift order on the wire.
        for i in 0 to 3 loop
            w(31 - 8 * i downto 24 - 8 * i) :=
                seed xor std_logic_vector(unsigned(addr(7 downto 0)) + i);
        end loop;
        return w;
    end function;

    procedure qspi_wait_busy_clear(signal clk       : in    std_logic;
                                   signal b         : inout periph_bus_t;
                                   signal read_data : in    std_logic_vector(31 downto 0);
                                   done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotQSPIxSR, s);
            if s(0) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 500;   -- bounded (never hangs)
        end loop;
    end procedure;

end package body qspi_bfm_pkg;
