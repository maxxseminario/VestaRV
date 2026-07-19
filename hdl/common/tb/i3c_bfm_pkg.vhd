-------------------------------------------------------------------------------
-- i3c_bfm_pkg.vhd
-------------------------------------------------------------------------------
-- Bench-support helpers for the I3C peripheral testbench (tb/I3C_tb.vhd) and
-- its target-responder model (tb/i3c_target_model.vhd). Like qspi_bfm_pkg.vhd,
-- I3C.vhd is being written in parallel against the same frozen design
-- (~/vesta_docs/digperiphs/i3c_design.md) this bench targets -- the slot
-- numbers and field-packing helpers below are LOCAL to this bench, not shared
-- MemoryMap.vhd constants (I3C has no MemoryMap.vhd register-slot constants
-- yet either).
--
-- Frozen register map (word slots, design doc S3):
--   0 I3CxCR   1 I3CxCMD   2 I3CxTX   3 I3CxRX   4 I3CxSR
--   5 I3CxDAT  6 I3CxDATPID  7 I3CxDATINFO  8 I3CxIBI  9 reserved
-- Stage-1 (MVP, this bench) drives slots 0-4 only; 5-9 are stage-2/3 (D23,
-- inert/read-0 in the MVP) and are declared here for completeness but unused.
--
-- i3c_parity() and i3c_read_pattern() are the T-BIT / READ-DATA reference
-- formulas shared by tb/i3c_target_model.vhd (drives/self-checks with them)
-- and I3C_tb.vhd (computes expected values with them). As with
-- qspi_read_pattern, that means most of the tb's "expected" and the model's
-- "actual" are NOT independently derived for the pattern formula itself --
-- deliberate scope trade-off (flagged in the bench author's report), mitigated
-- for the read pattern by at least one HAND-COMPUTED literal check in
-- I3C_tb.vhd (the QSPI GROUP 8d lesson) and for parity by i3c_parity() being a
-- one-line, spec-literal (D24) formula with no plausible alternate reading.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.periph_tb_pkg.all;

package i3c_bfm_pkg is

    -- ---- register word-slot map (frozen, design doc S3) -------------------
    constant SlotI3CxCR      : natural := 0;
    constant SlotI3CxCMD     : natural := 1;
    constant SlotI3CxTX      : natural := 2;
    constant SlotI3CxRX      : natural := 3;
    constant SlotI3CxSR      : natural := 4;
    constant SlotI3CxDAT     : natural := 5;   -- stage 2, unused in this bench
    constant SlotI3CxDATPID  : natural := 6;   -- stage 2, unused in this bench
    constant SlotI3CxDATINFO : natural := 7;   -- stage 2, unused in this bench
    constant SlotI3CxIBI     : natural := 8;   -- stage 3, unused in this bench
    -- slot 9 reserved (reads 0)

    -- ---- I3CxSR bit positions (design doc S3) ------------------------------
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

    -- ---- target-model observation array ------------------------------------
    -- Bounded byte array for a single transaction's captured/streamed bytes.
    -- Sized generously above D32's "small DLEN, <1 min" test plan (this bench
    -- never programs DLEN above a handful of bytes).
    constant I3C_MODEL_MAX_BYTES : natural := 16;
    type i3c_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);

    -- D24: WRITE T = odd parity of the byte, i.e. NOT(xor-reduce(data)) so
    -- {data,T} has an odd number of 1s. Shared by i3c_target_model.vhd (both
    -- to self-check received write bytes and, when cfg_corrupt_wparity
    -- injects a fault, to deliberately mis-derive the expected value) and
    -- I3C_tb.vhd (to hand-verify at least one case).
    function i3c_parity(data : std_logic_vector(7 downto 0)) return std_logic;

    -- Deterministic READ-data reference for I3C private reads. Unlike QSPI
    -- there is no address PHASE in an I3C private transfer (D33: private
    -- transfers do not prepend 0x7E and carry no memory address) -- the only
    -- per-target identity available is the target's own 7-bit address, so the
    -- pattern is built from {target_addr, seed, byte_idx} instead of a memory
    -- address. byte i (i=0 is the first byte the target drives) =
    -- seed xor (target_addr(7:0), zero-extended, + i). Shared by
    -- i3c_target_model.vhd (drives it) and I3C_tb.vhd (expects it).
    function i3c_read_pattern(target_addr : std_logic_vector(6 downto 0);
                              seed        : std_logic_vector(7 downto 0);
                              byte_idx    : natural)
        return std_logic_vector;

    -- Build a full 32-bit I3CxCR word (S3 field layout): EN=0, BUSMODE=1,
    -- SDAPP=2, IBIEN=3, ODBR=15:8, PPBR=23:16, TCIE=24, ERRIE=25, DAAIE=26,
    -- IBIIE=27, RXFIE=28, TXEIE=29. Bit 4 (HDR/hot-join) and 7:5 stay 0
    -- (reserved, D34 out of scope).
    function i3c_mk_cr(i3cen, busmode, sdapp, ibien              : std_logic;
                       tcie, errie, daaie, ibiie, rxfie, txeie   : std_logic;
                       odbr, ppbr                                : std_logic_vector(7 downto 0))
        return std_logic_vector;

    -- Build a full 32-bit I3CxCMD word (S3 field layout): ADDR=6:0, RNW=7,
    -- SR=8, STOPEN=9, CCC=10, CCCDIR=11, DAARUN=12, DASA=13, DLEN=23:16,
    -- CCCOP=31:24. Writing this word (lane 0, true of every bus_write here)
    -- LAUNCHES the transaction (D16; ignored if I3CEN=0 or BUSY=1).
    function i3c_mk_cmd(addr                                  : std_logic_vector(6 downto 0);
                        rnw, sr, stopen, ccc, cccdir, daarun, dasa : std_logic;
                        dlen                                  : std_logic_vector(7 downto 0);
                        ccop                                  : std_logic_vector(7 downto 0) := (others => '0'))
        return std_logic_vector;

    -- Bounded poll of I3CxSR.BUSY (bit 0) via the shared register-bus BFM.
    -- done_ok=false (never hangs) if BUSY hasn't cleared within the guard
    -- count -- mirrors qspi_wait_busy_clear.
    procedure i3c_wait_busy_clear(signal clk       : in    std_logic;
                                  signal b         : inout periph_bus_t;
                                  signal read_data : in    std_logic_vector(31 downto 0);
                                  done_ok          : out   boolean);

    -- Bounded poll of I3CxSR.BUSY until it reads '1' (used to catch a
    -- controller-provided IBI service window rising before waiting for it to
    -- clear -- avoids the "poll sees BUSY=0 before it ever rose" race).
    procedure i3c_wait_busy_set(signal clk       : in    std_logic;
                                signal b         : inout periph_bus_t;
                                signal read_data : in    std_logic_vector(31 downto 0);
                                done_ok          : out   boolean);

    -- Bounded poll of a single I3CxSR bit until it reads '1' (TXEIF ready to
    -- feed the next TX byte, RXFULL ready to drain the next RX byte, etc.).
    -- done_ok=false (never hangs) if the bit hasn't set within the guard count.
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
            exit when guard > 4000;   -- stage-2 ENTDAA frames (64-bit arb x
                                      -- multiple rounds) run far longer than a
                                      -- stage-1 SDR byte; still bounded (never
                                      -- hangs) and trivial in wall-clock time.
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
            exit when guard > 4000;
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
            exit when guard > 4000;
        end loop;
    end procedure;

end package body i3c_bfm_pkg;
