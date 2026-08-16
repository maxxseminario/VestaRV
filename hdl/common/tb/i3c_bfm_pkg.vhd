-------------------------------------------------------------------------------
-- i3c_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench helpers for the I3C peripheral testbench and its target-responder model.
-- Slot numbers and field packers are LOCAL to this bench; MemoryMap.vhd carries no I3C constants.
-- Word slots: 0 I3CxCR, 1 I3CxCMD, 2 I3CxTX, 3 I3CxRX, 4 I3CxSR, 5 I3CxDAT, 6 I3CxDATPID, 7 I3CxDATINFO, 8 I3CxIBI, 9 reserved.
-- i3c_parity() and i3c_read_pattern() are the T-bit and read-data reference formulas, shared by the target model that drives them and the tb that expects them.
-- The shared pattern formula is not independently derived, so the tb also checks at least one hand-computed literal.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package i3c_bfm_pkg is

    -- ---- Register word-slot map -------------------------------------------
    constant SlotI3CxCR      : natural := 0;
    constant SlotI3CxCMD     : natural := 1;
    constant SlotI3CxTX      : natural := 2;
    constant SlotI3CxRX      : natural := 3;
    constant SlotI3CxSR      : natural := 4;
    constant SlotI3CxDAT     : natural := 5;   -- Unused by this bench.
    constant SlotI3CxDATPID  : natural := 6;   -- Unused by this bench.
    constant SlotI3CxDATINFO : natural := 7;   -- Unused by this bench.
    constant SlotI3CxIBI     : natural := 8;   -- Unused by this bench.
    -- Slot 9 is reserved and reads 0.

    -- ---- I3CxSR bit positions ----------------------------------------------
    constant SrBitBUSY    : natural := 0;
    constant SrBitTCIF    : natural := 1;
    constant SrBitRXFULL  : natural := 2;
    constant SrBitTXEIF   : natural := 3;
    constant SrBitANACK   : natural := 4;
    constant SrBitEODF    : natural := 5;
    constant SrBitARBLOST : natural := 6;
    constant SrBitDAADONE : natural := 7;
    constant SrBitDAAFULL : natural := 8;
    constant SrBitIBIP    : natural := 9;
    constant SrBitIBIWON  : natural := 10;

    -- ---- Target-model observation array ------------------------------------
    -- Bounded byte array for one transaction's captured or streamed bytes; this bench never programs DLEN above a handful.
    constant I3C_MODEL_MAX_BYTES : natural := 16;
    type i3c_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- The write T bit is the odd parity of the byte, NOT(xor-reduce(data)), so {data,T} carries an odd number of ones.
    -- The target model self-checks received bytes with it and mis-derives it deliberately when cfg_corrupt_wparity injects a fault.
    function i3c_parity(data : std_logic_vector(7 downto 0)) return std_logic;

    -- Deterministic read-data reference for I3C private reads, which carry no memory address, so the target's 7-bit address is the only identity available.
    -- Byte i, counting from the first byte the target drives, is seed xor (zero-extended target_addr + i).
    function i3c_read_pattern(target_addr : std_logic_vector(6 downto 0);
                              seed        : std_logic_vector(7 downto 0);
                              byte_idx    : natural)
        return std_logic_vector;

    -- Build a full 32-bit I3CxCR word: EN bit 0, BUSMODE bit 1, SDAPP bit 2, IBIEN bit 3, ODBR bits 15:8, PPBR bits 23:16, TCIE bit 24, ERRIE bit 25, DAAIE bit 26, IBIIE bit 27, RXFIE bit 28, TXEIE bit 29.
    -- Bit 4 (HDR and hot-join) and bits 7:5 are reserved and stay 0.
    function i3c_mk_cr(i3cen, busmode, sdapp, ibien              : std_logic;
                       tcie, errie, daaie, ibiie, rxfie, txeie   : std_logic;
                       odbr, ppbr                                : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit I3CxCMD word: ADDR bits 6:0, RNW bit 7, SR bit 8, STOPEN bit 9, CCC bit 10, CCCDIR bit 11, DAARUN bit 12, DASA bit 13, DLEN bits 23:16, CCCOP bits 31:24.
    -- Writing this word on lane 0 LAUNCHES the transaction; the write is ignored when I3CEN=0 or BUSY=1.
    function i3c_mk_cmd(addr                                  : std_logic_vector(6 downto 0);
                        rnw, sr, stopen, ccc, cccdir, daarun, dasa : std_logic;
                        dlen                                  : std_logic_vector(7 downto 0);
                        ccop                                  : std_logic_vector(7 downto 0) := (others => '0'))
        return std_logic_vector;

    -- Bounded poll of I3CxSR.BUSY (bit 0); done_ok is false if the guard count expires first.
    procedure i3c_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of I3CxSR.BUSY until it reads '1': catch the IBI service window rising before waiting for it to clear, else the poll can see BUSY=0 before it ever rose.
    procedure i3c_wait_busy_set(signal clk       : in    std_logic;
                                signal b         : inout periph_bus_t;
                                signal read_data : in    std_logic_vector(31 downto 0);
                                done_ok          : out   boolean);

    -- Bounded poll of a single I3CxSR bit until it reads '1', e.g. TXEIF to feed the next TX byte or RXFULL to drain the next RX byte.
    procedure i3c_wait_sr_bit_set(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  bit_idx          : in    natural;
                                  done_ok          : out   boolean);

end package i3c_bfm_pkg;


package body i3c_bfm_pkg is

    function i3c_parity(data : std_logic_vector(7 downto 0)) return std_logic is
        variable p : std_logic := '0';
    begin
        -- XOR-reduce the byte, then invert, which gives odd parity.
        for i in data'range loop
            p := p xor data(i);
        end loop;
        return not p;
    end function;

    function i3c_read_pattern(target_addr : std_logic_vector(6 downto 0);
                              seed        : std_logic_vector(7 downto 0);
                              byte_idx    : natural)
        return std_logic_vector is
        variable addr8 : unsigned(7 downto 0);
    begin
        -- Zero-extend the 7-bit target address to 8 bits, add the byte index, then xor in the seed.
        addr8 := unsigned('0' & target_addr);
        return seed xor std_logic_vector(addr8 + byte_idx);
    end function;

    function i3c_mk_cr(i3cen, busmode, sdapp, ibien            : std_logic;
                       tcie, errie, daaie, ibiie, rxfie, txeie : std_logic;
                       odbr, ppbr                              : std_logic_vector(7 downto 0))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(0)            := i3cen;
        v(1)            := busmode;
        v(2)            := sdapp;
        v(3)            := ibien;
        v(15 downto 8)  := odbr;
        v(23 downto 16) := ppbr;
        v(24)           := tcie;
        v(25)           := errie;
        v(26)           := daaie;
        v(27)           := ibiie;
        v(28)           := rxfie;
        v(29)           := txeie;
        return v;
    end function;

    function i3c_mk_cmd(addr                                       : std_logic_vector(6 downto 0);
                        rnw, sr, stopen, ccc, cccdir, daarun, dasa : std_logic;
                        dlen                                       : std_logic_vector(7 downto 0);
                        ccop                                       : std_logic_vector(7 downto 0) := (others => '0'))
        return std_logic_vector is
        variable v : std_logic_vector(31 downto 0) := (others => '0');
    begin
        v(6 downto 0)   := addr;
        v(7)            := rnw;
        v(8)            := sr;
        v(9)            := stopen;
        v(10)           := ccc;
        v(11)           := cccdir;
        v(12)           := daarun;
        v(13)           := dasa;
        v(23 downto 16) := dlen;
        v(31 downto 24) := ccop;
        return v;
    end function;

    procedure i3c_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotI3CxSR, s);
            if s(SrBitBUSY) = '0' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 4000;   -- Sized for ENTDAA frames, whose multi-round 64-bit arbitration runs far longer than a plain SDR byte.
        end loop;
    end procedure;

    procedure i3c_wait_sr_bit_set(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  bit_idx          : in    natural;
                                  done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotI3CxSR, s);
            if s(bit_idx) = '1' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 4000;   -- Same bound as the BUSY poll above.
        end loop;
    end procedure;

    procedure i3c_wait_busy_set(signal clk       : in    std_logic;
                                signal b         : inout periph_bus_t;
                                signal read_data : in    std_logic_vector(31 downto 0);
                                done_ok          : out   boolean) is
        variable s     : std_logic_vector(31 downto 0);
        variable guard : natural := 0;
    begin
        done_ok := false;
        loop
            bus_read(clk, b, read_data, SlotI3CxSR, s);
            if s(SrBitBUSY) = '1' then
                done_ok := true;
                exit;
            end if;
            guard := guard + 1;
            exit when guard > 4000;   -- Same bound as the BUSY poll above.
        end loop;
    end procedure;

end package body i3c_bfm_pkg;
