/* =============================================================================
   BIASG.vhd: control registers of the ONE shared analog bias generator, `anatop_biasgen_g`.
   Topology B only (chip config afeTopology = "per_tile", 2026-09-06). In that build the four channels have no local bias generator: a single chip-level wide-swing cascode generator drives all four tiles' bn/bnc/bp/bpc rails, so its trim is CHIP state and belongs to no channel.

   WHY IT IS A SEPARATE ENTITY AND NOT REGISTERS IN AFE2.vhd. AFE2 decodes words 0-8 of its 256 B sub-slot and reads ZERO above them, so words 9-13 of SITE 0's sub-slot are free space inside an address range that already exists. This entity sits on site 0's SAME enable (shslv_afe0_en), decodes WORD_BASE..WORD_BASE+4 only, and MCU.vhd ORs its read word into afe0's -- exact, because at most one of the two ever returns a non-zero word. The registers therefore cost no address slot, no IRQ vector and no edit to AFE2.vhd, which the topology-A synthesis flow reads straight out of the working tree.

   THE MACRO HAS 66 STATIC DIGITAL INPUTS, not two (report B7-9, measured from innovus/common/shared/anatop_biasgen_g/anatop_biasgen_g.lef, 74 pins). FOUR INDEPENDENT 14-BIT CODES, one per rail: the four rails are independent voltages produced by four independent R-2R ladders, and one shared code drives all four DACs to the SAME voltage, which is not a cascode bias set (B4 measurement T1). Plus a 6-bit generator trim and four mode/enable bits.

   Register map (word offsets in AFE2 site 0's sub-slot; the generated map calls them AFE0BIASG0..3 and AFE0BIASGCR at 0x6C24, 0x6C28, 0x6C2C, 0x6C30, 0x6C34):
     9  BIASG0  [13:0] code_bn    14-bit R-2R code for the NMOS cascode rail bn
     10 BIASG1  [13:0] code_bnc   ... bnc
     11 BIASG2  [13:0] code_bp    ... bp
     12 BIASG3  [13:0] code_bpc   ... bpc
     13 BIASGCR [0] use_dac  [1] en_gen  [2] en_buf_int  [3] en  [13:8] bias_adj<5:0>
   Bit order of the four mode bits is the LEF's own pin order, so the register and the macro can be compared by eye.
   Everything else reads 0 and drops writes.

   RESET VALUES, and two of them are power-up-sequence duties rather than safe defaults:
     enables  ALL ZERO. The generator is off and its four rails undriven, so a chip that never writes this block has four dead channels rather than four mis-biased ones.
     codes    ZERO on all four, and the value is INERT at reset by construction: BIASGCR resets with `en` = 0 (generator off, rails undriven) and `use_dac` = 0 (the generator core, not the ladders, sets the rails), so nothing reads these words until firmware writes them. B4 publishes no per-rail nominal DAC code because the shipped mission mode is generator mode and needs none.
              MID-SCALE 0x2000 WAS SPECIFIED AND IS NOT WHAT SHIPS HERE, deliberately and reversibly. `rv32ui-p-shafe2` phase 2 asserts that word 9 of EVERY site's sub-slot reads 0 (shafe2.S:133-135, `lw t0, 36(s1); bnez t0, shafe2_fail`) -- true in topology A, where nothing decodes word 9, and false here the moment BIASG0 resets non-zero. That test and its flash image are shared with topology A's regression, so changing them is a cross-topology edit; changing this constant is not. Mid-scale is the better ACCIDENT value (firmware that sets `use_dac` before writing the codes would drive all four rails to 0 V, which turns the PMOS cascodes fully on), so if the owner wants it back the change is this one constant plus deleting those three lines from shafe2.S and rebuilding its image.
     bias_adj ZERO, which is the `adj0` END of the trim range and NOT the characterised nominal: at adj0 the generator draws 56.6 uA and bn sits at 0.678 V, against the 0.6147 V nominal of B4's DC table. The power-up sequence must write a trim code before enabling any channel. This is the same class of duty F7 open item 4 records for the pixel's own Bias_Adj, and it is stated here rather than hidden in a default.

   Bus shape is the afe_stub/AFE2 native slave: one-cycle active-high en, byte-lane we, word address addr(5:0), REGISTERED read (address at T, data at T+1), s_master ownership gate. A denied read returns 0 and a denied write is dropped. OWNER_HART and MGMT_HART both default 0, which is the intended wiring: one generator serves four channels, so only the orchestrator trims it.
   Reads have no side effects (the LR/SC rule the whole native fabric obeys).

   All 66 outputs are 1.0 V CMOS and STATIC: they are written once and held, which is why anatop_biasgen_g's .lib carries no timing arcs and the chip SDC must false-path every input of the macro.
   ============================================================================= */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- SystemRDL level 2 (2026-09-10, report R6). N_WORDS, the array type and the
-- IMPL / RSTVAL tables are GENERATED from hdl/common/regs/rdl/biasg.rdl into
-- biasg_regs_pkg.vhd, under the identifiers this decode already used, together
-- with WORD_BASE_DEFAULT (the generic's default) and the <FIELD>_MSB/_LSB
-- ranges. The tables are POSITIONAL here -- the decode indexes them by
-- idx - WORD_BASE -- so the package names the relative slots IDX_* and never
-- W_*, which would mean the absolute word the bus decodes.
-- ANY FLOW THAT READS THIS FILE MUST ANALYSE biasg_regs_pkg.vhd FIRST.
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

    -- N_WORDS (5: BIASG0..3 + BIASGCR), reg_array, IMPL and RSTVAL come from
    -- biasg_regs_pkg (generated from biasg.rdl). IMPL is the implemented-bit mask
    -- per word -- the four codes are 14 bits, BIASGCR is use_dac/en_gen/
    -- en_buf_int/en in 3:0 and bias_adj in 13:8. RSTVAL is every word zero; see
    -- the header for why zero codes are inert here and why zero adj is a
    -- power-up duty.

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
