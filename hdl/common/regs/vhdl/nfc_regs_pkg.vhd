-- VestaRV: NFC register package
-- NFC controller: ISO/IEC 14443 Type A (14443A) tag / card-emulation digital protocol engine
-- Generated from hdl/common/regs/rdl/nfc.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package nfc_regs_pkg is

    -- NFCxCR: NFC control register
    constant NFCxCR_WORD              : natural := 0;
    constant NFCxCR_ADDR              : natural := 0;
    constant NFCxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000001000000000000";
    constant NFCxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000011110001111100000011";
    constant NFCRFDIV_MSB             : natural := 19;
    constant NFCRFDIV_LSB             : natural := 16;
    constant NFCRFDIV_RESET           : std_logic_vector(3 downto 0) := "0000";
    constant NFCAUTOREAD_MSB          : natural := 12;
    constant NFCAUTOREAD_LSB          : natural := 12;
    constant NFCAUTOREAD_RESET        : std_logic_vector(0 downto 0) := "1";
    constant NFCCRCIE_MSB             : natural := 11;
    constant NFCCRCIE_LSB             : natural := 11;
    constant NFCCRCIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant NFCTXIE_MSB              : natural := 10;
    constant NFCTXIE_LSB              : natural := 10;
    constant NFCTXIE_RESET            : std_logic_vector(0 downto 0) := "0";
    constant NFCRXFIE_MSB             : natural := 9;
    constant NFCRXFIE_LSB             : natural := 9;
    constant NFCRXFIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant NFCFIELDIE_MSB           : natural := 8;
    constant NFCFIELDIE_LSB           : natural := 8;
    constant NFCFIELDIE_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCHALTCLR_MSB           : natural := 2;
    constant NFCHALTCLR_LSB           : natural := 2;
    constant NFCHALTCLR_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCLISTEN_MSB            : natural := 1;
    constant NFCLISTEN_LSB            : natural := 1;
    constant NFCLISTEN_RESET          : std_logic_vector(0 downto 0) := "0";
    constant NFCEN_MSB                : natural := 0;
    constant NFCEN_LSB                : natural := 0;
    constant NFCEN_RESET              : std_logic_vector(0 downto 0) := "0";

    -- NFCxSR: NFC status register
    constant NFCxSR_WORD              : natural := 1;
    constant NFCxSR_ADDR              : natural := 4;
    constant NFCxSR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxSR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCSTATE_MSB             : natural := 11;
    constant NFCSTATE_LSB             : natural := 8;
    constant NFCSTATE_RESET           : std_logic_vector(3 downto 0) := "0000";
    constant NFCHALTED_MSB            : natural := 7;
    constant NFCHALTED_LSB            : natural := 7;
    constant NFCHALTED_RESET          : std_logic_vector(0 downto 0) := "0";
    constant NFCFIELDLIVE_MSB         : natural := 6;
    constant NFCFIELDLIVE_LSB         : natural := 6;
    constant NFCFIELDLIVE_RESET       : std_logic_vector(0 downto 0) := "0";
    constant NFCPARERRF_MSB           : natural := 5;
    constant NFCPARERRF_LSB           : natural := 5;
    constant NFCPARERRF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCCRCERRF_MSB           : natural := 4;
    constant NFCCRCERRF_LSB           : natural := 4;
    constant NFCCRCERRF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCTXDONEF_MSB           : natural := 3;
    constant NFCTXDONEF_LSB           : natural := 3;
    constant NFCTXDONEF_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCRXFRAMEF_MSB          : natural := 2;
    constant NFCRXFRAMEF_LSB          : natural := 2;
    constant NFCRXFRAMEF_RESET        : std_logic_vector(0 downto 0) := "0";
    constant NFCFIELDF_MSB            : natural := 1;
    constant NFCFIELDF_LSB            : natural := 1;
    constant NFCFIELDF_RESET          : std_logic_vector(0 downto 0) := "0";
    constant NFCBUSY_MSB              : natural := 0;
    constant NFCBUSY_LSB              : natural := 0;
    constant NFCBUSY_RESET            : std_logic_vector(0 downto 0) := "0";

    -- NFCxUID: Provisioned single-size 4-byte tag UID, used by bit-frame anticollision
    constant NFCxUID_WORD             : natural := 2;
    constant NFCxUID_ADDR             : natural := 8;
    constant NFCxUID_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxUID_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant NFCUID_MSB               : natural := 31;
    constant NFCUID_LSB               : natural := 0;
    constant NFCUID_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- NFCxCFG: Tag identity response configuration: the ATQA answer-to-request word and the SAK select-acknowledge byte
    constant NFCxCFG_WORD             : natural := 3;
    constant NFCxCFG_ADDR             : natural := 12;
    constant NFCxCFG_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000001000100";
    constant NFCxCFG_IMPL             : std_logic_vector(31 downto 0) := "00000000111111111111111111111111";
    constant NFCSAK_MSB               : natural := 23;
    constant NFCSAK_LSB               : natural := 16;
    constant NFCSAK_RESET             : std_logic_vector(7 downto 0) := "00000000";
    constant NFCATQA_MSB              : natural := 15;
    constant NFCATQA_LSB              : natural := 0;
    constant NFCATQA_RESET            : std_logic_vector(15 downto 0) := "0000000001000100";

    -- NFCxTIM: Protocol timing divisors, all in rf_clk ticks, latched transaction-locally so a mid-count reload never glitches
    constant NFCxTIM_WORD             : natural := 4;
    constant NFCxTIM_ADDR             : natural := 16;
    constant NFCxTIM_RESET            : std_logic_vector(31 downto 0) := "00001000100000000000010011010100";
    constant NFCxTIM_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant NFCSUBCDIV_MSB           : natural := 31;
    constant NFCSUBCDIV_LSB           : natural := 24;
    constant NFCSUBCDIV_RESET         : std_logic_vector(7 downto 0) := "00001000";
    constant NFCETU_MSB               : natural := 23;
    constant NFCETU_LSB               : natural := 16;
    constant NFCETU_RESET             : std_logic_vector(7 downto 0) := "10000000";
    constant NFCFDT_MSB               : natural := 15;
    constant NFCFDT_LSB               : natural := 0;
    constant NFCFDT_RESET             : std_logic_vector(15 downto 0) := "0000010011010100";

    -- NFCxRXST: Received-frame inspection, for firmware-handled frames (NFCAUTOREAD = 0 or an unrecognized command)
    constant NFCxRXST_WORD            : natural := 5;
    constant NFCxRXST_ADDR            : natural := 20;
    constant NFCxRXST_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxRXST_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCRXPAROK_MSB           : natural := 17;
    constant NFCRXPAROK_LSB           : natural := 17;
    constant NFCRXPAROK_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCRXCRCOK_MSB           : natural := 16;
    constant NFCRXCRCOK_LSB           : natural := 16;
    constant NFCRXCRCOK_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCRXLEN_MSB             : natural := 15;
    constant NFCRXLEN_LSB             : natural := 8;
    constant NFCRXLEN_RESET           : std_logic_vector(7 downto 0) := "00000000";
    constant NFCCMD_MSB               : natural := 7;
    constant NFCCMD_LSB               : natural := 0;
    constant NFCCMD_RESET             : std_logic_vector(7 downto 0) := "00000000";

    -- NFCxIDX: Byte-index pointer into one of the two 64-byte windows accessed through NFCxDATA
    constant NFCxIDX_WORD             : natural := 6;
    constant NFCxIDX_ADDR             : natural := 24;
    constant NFCxIDX_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxIDX_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000101111111";
    constant NFCIDXSEL_MSB            : natural := 8;
    constant NFCIDXSEL_LSB            : natural := 8;
    constant NFCIDXSEL_RESET          : std_logic_vector(0 downto 0) := "0";
    constant NFCIDXAINC_MSB           : natural := 6;
    constant NFCIDXAINC_LSB           : natural := 6;
    constant NFCIDXAINC_RESET         : std_logic_vector(0 downto 0) := "0";
    constant NFCIDX_MSB               : natural := 5;
    constant NFCIDX_LSB               : natural := 0;
    constant NFCIDX_RESET             : std_logic_vector(5 downto 0) := "000000";

    -- NFCxDATA: The byte at NFCIDX in the window selected by NFCIDXSEL
    constant NFCxDATA_WORD            : natural := 7;
    constant NFCxDATA_ADDR            : natural := 28;
    constant NFCxDATA_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxDATA_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant NFCDATA_MSB              : natural := 7;
    constant NFCDATA_LSB              : natural := 0;
    constant NFCDATA_RESET            : std_logic_vector(7 downto 0) := "00000000";

    -- NFCxTXCTL: Firmware-composed response control (used when NFCAUTOREAD = 0 or for a vendor command)
    constant NFCxTXCTL_WORD           : natural := 8;
    constant NFCxTXCTL_ADDR           : natural := 32;
    constant NFCxTXCTL_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxTXCTL_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000001111111111";
    constant NFCTXAPPCRC_MSB          : natural := 9;
    constant NFCTXAPPCRC_LSB          : natural := 9;
    constant NFCTXAPPCRC_RESET        : std_logic_vector(0 downto 0) := "0";
    constant NFCTXGO_MSB              : natural := 8;
    constant NFCTXGO_LSB              : natural := 8;
    constant NFCTXGO_RESET            : std_logic_vector(0 downto 0) := "0";
    constant NFCTXLEN_MSB             : natural := 7;
    constant NFCTXLEN_LSB             : natural := 0;
    constant NFCTXLEN_RESET           : std_logic_vector(7 downto 0) := "00000000";

    -- NFCxDBG: Debug telemetry / bench cross-checks: frame counters
    constant NFCxDBG_WORD             : natural := 9;
    constant NFCxDBG_ADDR             : natural := 36;
    constant NFCxDBG_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCxDBG_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant NFCTXFRAMECNT_MSB        : natural := 31;
    constant NFCTXFRAMECNT_LSB        : natural := 16;
    constant NFCTXFRAMECNT_RESET      : std_logic_vector(15 downto 0) := "0000000000000000";
    constant NFCRXFRAMECNT_MSB        : natural := 15;
    constant NFCRXFRAMECNT_LSB        : natural := 0;
    constant NFCRXFRAMECNT_RESET      : std_logic_vector(15 downto 0) := "0000000000000000";

    -- NFC.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_SR                  : natural := 1;
    constant SLOT_UID                 : natural := 2;
    constant SLOT_CFG                 : natural := 3;
    constant SLOT_TIM                 : natural := 4;
    constant SLOT_RXST                : natural := 5;
    constant SLOT_IDX                 : natural := 6;
    constant SLOT_DATA                : natural := 7;
    constant SLOT_TXCTL               : natural := 8;
    constant SLOT_DBG                 : natural := 9;

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 10;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00001000",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000044",   -- NFCxCFG
        x"088004D4",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"000F1F03",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"FFFFFFFF",   -- NFCxUID
        x"00FFFFFF",   -- NFCxCFG
        x"FFFFFFFF",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"0000017F",   -- NFCxIDX
        x"000000FF",   -- NFCxDATA
        x"000003FF",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- NFCxCR
        x"0000003E",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000004",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- NFCxCR
        x"00000000",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"00000000",   -- NFCxRXST
        x"00000000",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"00000000"    -- NFCxDBG
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- NFCxCR
        x"00000FFF",   -- NFCxSR
        x"00000000",   -- NFCxUID
        x"00000000",   -- NFCxCFG
        x"00000000",   -- NFCxTIM
        x"0003FFFF",   -- NFCxRXST
        x"0000003F",   -- NFCxIDX
        x"00000000",   -- NFCxDATA
        x"00000000",   -- NFCxTXCTL
        x"FFFFFFFF"    -- NFCxDBG
    );

end package nfc_regs_pkg;
