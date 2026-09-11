-- VestaRV: IRQ_ROUTER register package
-- THE peripheral interrupt controller (M19): per-hart interrupt routing/enable rows plus a claim/complete delivery stage, programmable by any hart through the shared window
-- Generated from hdl/common/regs/rdl/irq_router.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.
-- Configuration-dependent: only what is common to (NHARTS, VECTORS) = (1, 114), (5, 125), (18, 114), (32, 121) is emitted, the rest stays a generic in irq_router.vhd.

library ieee;
use ieee.std_logic_1164.all;

package irq_router_regs_pkg is

    -- H0ENL: Hart 0 interrupt routing register, vectors 31:0. Each bit enables delivery of the corresponding interrupt vector to hart 0 via its meip wire (vector 85) and the CLAIM/COMPLETE mechanism
    constant H0ENL_WORD               : natural := 0;
    constant H0ENL_ADDR               : natural := 0;
    constant H0ENL_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant H0ENL_IMPL               : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant IRQRH0ENL_MSB            : natural := 31;
    constant IRQRH0ENL_LSB            : natural := 0;
    constant IRQRH0ENL_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- H0ENM: Hart 0 interrupt routing register, vectors 63:32.
    constant H0ENM_WORD               : natural := 1;
    constant H0ENM_ADDR               : natural := 4;
    constant H0ENM_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant H0ENM_IMPL               : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant IRQRH0ENM_MSB            : natural := 31;
    constant IRQRH0ENM_LSB            : natural := 0;
    constant IRQRH0ENM_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- H0ENU: Hart 0 interrupt routing register, vectors 95:64. Bits 19 and 20 correspond to the CLINT vectors 83 and 84, which are delivered on dedicated hardwired wires and never through meip: these two bits are writable but have no effect
    constant H0ENU_WORD               : natural := 2;
    constant H0ENU_ADDR               : natural := 8;
    constant H0ENU_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant H0ENU_IMPL               : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant IRQRH0ENU_MSB            : natural := 31;
    constant IRQRH0ENU_LSB            : natural := 0;
    constant IRQRH0ENU_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- H0ENX: Hart 0 interrupt routing register, vectors 123:96 (bits 27:0; upper bits read as 0)
    constant H0ENX_WORD               : natural := 3;
    constant H0ENX_ADDR               : natural := 12;
    constant H0ENX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRH0ENX_LSB            : natural := 0;

    -- CLAIM: Interrupt claim/complete register (M19)
    constant CLAIM_WORD               : natural := 512;
    constant CLAIM_ADDR               : natural := 2048;
    constant CLAIM_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant CLAIM_IMPL               : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant IRQRCLAIM_MSB            : natural := 31;
    constant IRQRCLAIM_LSB            : natural := 0;
    constant IRQRCLAIM_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PENDL: Raw pending interrupt levels, vectors 31:0 (read-only; deglitched peripheral levels before enable/claim masking)
    constant PENDL_WORD               : natural := 516;
    constant PENDL_ADDR               : natural := 2064;
    constant PENDL_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PENDL_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRPENDL_MSB            : natural := 31;
    constant IRQRPENDL_LSB            : natural := 0;
    constant IRQRPENDL_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PENDM: Raw pending interrupt levels, vectors 63:32 (read-only)
    constant PENDM_WORD               : natural := 517;
    constant PENDM_ADDR               : natural := 2068;
    constant PENDM_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PENDM_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRPENDM_MSB            : natural := 31;
    constant IRQRPENDM_LSB            : natural := 0;
    constant IRQRPENDM_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PENDU: Raw pending interrupt levels, vectors 95:64 (read-only)
    constant PENDU_WORD               : natural := 518;
    constant PENDU_ADDR               : natural := 2072;
    constant PENDU_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PENDU_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRPENDU_MSB            : natural := 31;
    constant IRQRPENDU_LSB            : natural := 0;
    constant IRQRPENDU_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- PENDX: Raw pending interrupt levels, vectors 123:96 (bits 27:0, read-only; upper bits read as 0)
    constant PENDX_WORD               : natural := 519;
    constant PENDX_ADDR               : natural := 2076;
    constant PENDX_RESET              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant PENDX_IMPL               : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRPENDX_LSB            : natural := 0;

    -- INSVCL: Under-service (claimed, not yet completed) flags, vectors 31:0 (read-only)
    constant INSVCL_WORD              : natural := 520;
    constant INSVCL_ADDR              : natural := 2080;
    constant INSVCL_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant INSVCL_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRINSVCL_MSB           : natural := 31;
    constant IRQRINSVCL_LSB           : natural := 0;
    constant IRQRINSVCL_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- INSVCM: Under-service flags, vectors 63:32 (read-only)
    constant INSVCM_WORD              : natural := 521;
    constant INSVCM_ADDR              : natural := 2084;
    constant INSVCM_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant INSVCM_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRINSVCM_MSB           : natural := 31;
    constant IRQRINSVCM_LSB           : natural := 0;
    constant IRQRINSVCM_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- INSVCU: Under-service flags, vectors 95:64 (read-only)
    constant INSVCU_WORD              : natural := 522;
    constant INSVCU_ADDR              : natural := 2088;
    constant INSVCU_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant INSVCU_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRINSVCU_MSB           : natural := 31;
    constant IRQRINSVCU_LSB           : natural := 0;
    constant IRQRINSVCU_RESET         : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- INSVCX: Under-service flags, vectors 123:96 (bits 27:0, read-only; upper bits read as 0)
    constant INSVCX_WORD              : natural := 523;
    constant INSVCX_ADDR              : natural := 2092;
    constant INSVCX_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant INSVCX_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant IRQRINSVCX_LSB           : natural := 0;

    -- irq_router.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant W_CLAIM                  : natural := 512;
    constant W_PENDL                  : natural := 516;
    constant W_PENDM                  : natural := 517;
    constant W_PENDU                  : natural := 518;
    constant W_PENDX                  : natural := 519;
    constant W_INSVCL                 : natural := 520;
    constant W_INSVCM                 : natural := 521;
    constant W_INSVCU                 : natural := 522;
    constant W_INSVCX                 : natural := 523;

    -- No periph_regs table section: the register set is a function of the hart and vector counts,
    -- so its words are not a dense array. See hdl/common/regs/REGFILE.md.

end package irq_router_regs_pkg;
