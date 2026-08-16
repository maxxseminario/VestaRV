/* -----------------------------------------------------------------------------
   qspi_bfm_pkg.vhd
   -----------------------------------------------------------------------------
   Bench-support helpers for the QSPI peripheral testbench (tb/QSPI_tb.vhd) and its flash-responder model (tb/qspi_flash_model.vhd).
   The slot numbers and field-packing helpers are LOCAL to this bench, not shared MemoryMap.vhd constants; QSPI_tb.vhd's header carries the full field layout.
   qspi_read_pattern is the ONE shared formula for the flash model's deterministic READ data, called both to drive it and to expect it, so a bug in the formula itself cannot be caught by these checks.
   ----------------------------------------------------------------------------- */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package qspi_bfm_pkg is

    -- ---- register word-slot map -------------------------------------------
    constant SlotQSPIxCR  : natural := 0;
    constant SlotQSPIxCMD : natural := 1;
    constant SlotQSPIxADR : natural := 2;
    constant SlotQSPIxTX  : natural := 3;
    constant SlotQSPIxRX  : natural := 4;
    constant SlotQSPIxSR  : natural := 5;

    -- CMDW/ADRW/DATW field decode: 00=1-bit, 01=2-bit, 10=4-bit.
    -- "11" is undefined and never driven by this bench; it decodes as 1-bit only so the helper is total.
    function qspi_width_lanes(w : std_logic_vector(1 downto 0)) return natural;

    -- AWID field decode: 00=none, 01=24-bit, 10=32-bit.
    -- "11" is undefined and yields 0 (no address phase); it is never driven by this bench.
    function qspi_awid_bits(w : std_logic_vector(1 downto 0)) return natural;

    -- CMD.DLEN field decode: 00=none, 01=8-bit, 10=16-bit, 11=32-bit.
    function qspi_dlen_bits(w : std_logic_vector(1 downto 0)) return natural;

    -- Build a full 32-bit CR word from named fields.
    -- EN=0, CMDW=2:1, ADRW=4:3, DATW=6:5, CPOL=7, CPHA=8, AWID=10:9, DUMMY=15:11, CSSEL=18:16 (written 0), BR=26:19, TCIE=27, RXFIE=28.
    function qspi_mk_cr(en, cpol, cpha, tcie, rxfie : std_logic;
                        cmdw, adrw, datw, awid       : std_logic_vector(1 downto 0);
                        dummy                        : std_logic_vector(4 downto 0);
                        br                           : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit CMD word (opcode=7:0, DLEN=9:8, DIR=10).
    -- Writing it with byte lane 0 enabled launches the transaction, and every bus_write enables all four lanes.
    function qspi_mk_cmd(opcode : std_logic_vector(7 downto 0);
                         dlen   : std_logic_vector(1 downto 0);
                         dir    : std_logic)
        return std_logic_vector;

    -- Deterministic READ-data reference: 4 MSB-first bytes, byte i = seed xor (addr(7:0) + i), i=0 being the first byte shifted out.
    function qspi_read_pattern(addr : std_logic_vector(31 downto 0);
                               seed : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Bounded poll of SR.BUSY (bit 0) via the shared register-bus BFM.
    -- done_ok comes back false, never a hang, if BUSY has not cleared within the guard count.
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
