-- VestaRV: shared analog bias generator trim (topology B only)
-- Control registers of the one chip-level anatop_biasgen_g, which drives all four tiles' bn/bnc/bp/bpc rails; its trim is chip state and belongs to no channel.
-- Separate entity, not registers in AFE2: it sits on site 0's enable (shslv_afe0_en), decodes WORD_BASE..WORD_BASE+4 in the words AFE2 reads as zero, and MCU.vhd ORs its read word into afe0's. Bus shape is the afe_stub/AFE2 native slave; a denied read returns 0, a denied write is dropped.
-- The macro takes four independent 14-bit R-2R codes, one per rail, plus a 6-bit generator trim and four mode bits; one shared code would drive all four rails to the same voltage, which is not a cascode bias set.
-- All enables reset to zero, so an unwritten chip has four dead channels rather than four mis-biased ones. bias_adj resets to 0, the adj0 end of the trim range and not the characterised nominal: the power-up sequence must write a trim code before enabling any channel.
-- The 66 outputs are static 1.0 V CMOS, written once and held, so the macro's .lib carries no timing arcs and the chip SDC must false-path every one of its inputs.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Word count, field ranges, IMPL/RSTVAL and WORD_BASE_DEFAULT: generated from hdl/common/regs/rdl/biasg.rdl.
-- The tables are positional, indexed by idx - WORD_BASE, so the package names relative slots IDX_*, never absolute W_*.
use work.biasg_regs_pkg.all;

entity BIASG is
    generic (
        OWNER_HART : natural := 0;     -- hart that, with MGMT_HART, may access these registers
        MGMT_HART  : natural := 0;     -- the management hart
        WORD_BASE  : natural := WORD_BASE_DEFAULT   -- first word offset inside the host sub-slot (AFE2 reads 0 from here up); 9, from biasg.rdl
    );
    port (
        clk        : in  std_logic;                        -- free-running mclk
        resetn     : in  std_logic;

        -- Native arbiter slave port, shared with the host AFE2 site's enable.
        en_bus     : in  std_logic;
        we         : in  std_logic_vector(3 downto 0);
        addr       : in  std_logic_vector(5 downto 0);     -- word offset within the 256 B sub-slot
        wdata      : in  std_logic_vector(31 downto 0);
        master     : in  std_logic_vector;                 -- arbiter s_master, unconstrained
        rdata      : out std_logic_vector(31 downto 0);    -- 0 for every word outside the block, so it OR-merges

        -- To anatop_biasgen_g. Names are the LEF's pin names, verbatim.
        code_bn    : out std_logic_vector(13 downto 0);
        code_bnc   : out std_logic_vector(13 downto 0);
        code_bp    : out std_logic_vector(13 downto 0);
        code_bpc   : out std_logic_vector(13 downto 0);
        bias_adj   : out std_logic_vector(5 downto 0);
        use_dac    : out std_logic;
        en_gen     : out std_logic;
        en_buf_int : out std_logic;
        en         : out std_logic
    );
end entity;

architecture rtl of BIASG is

    -- IMPL is the implemented-bit mask per word: the four codes are 14 bits,
    -- BIASGCR is use_dac/en_gen/en_buf_int/en in 3:0 and bias_adj in 13:8.
    -- RSTVAL is every word zero.

    signal regs      : reg_array;
    signal rdata_reg : std_logic_vector(31 downto 0);

begin

    rdata      <= rdata_reg;
    code_bn    <= regs(IDX_BIASG0)(AFEBGCODE0_MSB downto AFEBGCODE0_LSB);
    code_bnc   <= regs(IDX_BIASG1)(AFEBGCODE1_MSB downto AFEBGCODE1_LSB);
    code_bp    <= regs(IDX_BIASG2)(AFEBGCODE2_MSB downto AFEBGCODE2_LSB);
    code_bpc   <= regs(IDX_BIASG3)(AFEBGCODE3_MSB downto AFEBGCODE3_LSB);
    use_dac    <= regs(IDX_BIASGCR)(AFEBGUSEDAC_LSB);
    en_gen     <= regs(IDX_BIASGCR)(AFEBGENGEN_LSB);
    en_buf_int <= regs(IDX_BIASGCR)(AFEBGENBUFINT_LSB);
    en         <= regs(IDX_BIASGCR)(AFEBGEN_LSB);
    bias_adj   <= regs(IDX_BIASGCR)(AFEBGADJ_MSB downto AFEBGADJ_LSB);

    bus_proc : process(clk, resetn)
        variable allow : boolean;
        variable idx   : integer range 0 to 63;
        variable hit   : boolean;
        variable sel   : integer range 0 to N_WORDS - 1;
    begin
        if resetn = '0' then
            regs      <= RSTVAL;
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            if en_bus = '1' then
                allow := (to_integer(unsigned(master)) = OWNER_HART)
                         or (to_integer(unsigned(master)) = MGMT_HART);
                idx := to_integer(unsigned(addr));
                hit := (idx >= WORD_BASE) and (idx < WORD_BASE + N_WORDS);
                sel := 0;
                if hit then
                    sel := idx - WORD_BASE;
                end if;
                -- Registered read of the pre-write value; anything else reads 0,
                -- which is what lets MCU.vhd OR this word into the host site's.
                if allow and hit then
                    rdata_reg <= regs(sel) and IMPL(sel);
                else
                    rdata_reg <= (others => '0');
                end if;
                if allow and hit then
                    for l in 0 to 3 loop
                        if we(l) = '1' then
                            regs(sel)(l*8+7 downto l*8) <=
                                wdata(l*8+7 downto l*8) and IMPL(sel)(l*8+7 downto l*8);
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process;

end architecture;
