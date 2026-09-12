-- VestaRV: DMA register package
-- Configurable multi-channel single-shot DMA controller: it moves words source->dest over the shared arbiter as a stream of single-word transactions, either flat-out under software GO (memory-to-memory) or paced one word per peripheral data-ready event (UART0 RC / QSPI0 RX-full / NFC0 payload-ready), with optional per-channel source/dest auto-increment, a per-channel 2-level priority + word-granular
-- Generated from hdl/common/regs/rdl/dma.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;

package dma_regs_pkg is

    -- DMAxCR: DMA control register
    constant DMAxCR_WORD              : natural := 0;
    constant DMAxCR_ADDR              : natural := 0;
    constant DMAxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000011000111111111";
    constant DMAERRIE_MSB             : natural := 13;
    constant DMAERRIE_LSB             : natural := 13;
    constant DMAERRIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant DMADONEIE_MSB            : natural := 12;
    constant DMADONEIE_LSB            : natural := 12;
    constant DMADONEIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAABORT_MSB             : natural := 8;
    constant DMAABORT_LSB             : natural := 5;
    constant DMAABORT_RESET           : std_logic_vector(3 downto 0) := "0000";
    constant DMAGO_MSB                : natural := 4;
    constant DMAGO_LSB                : natural := 1;
    constant DMAGO_RESET              : std_logic_vector(3 downto 0) := "0000";
    constant DMAEN_MSB                : natural := 0;
    constant DMAEN_LSB                : natural := 0;
    constant DMAEN_RESET              : std_logic_vector(0 downto 0) := "0";

    -- DMAxSR: DMA status register
    constant DMAxSR_WORD              : natural := 1;
    constant DMAxSR_ADDR              : natural := 4;
    constant DMAxSR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxSR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAACTIVECH_MSB          : natural := 11;
    constant DMAACTIVECH_LSB          : natural := 9;
    constant DMAACTIVECH_RESET        : std_logic_vector(2 downto 0) := "000";
    constant DMAERR_MSB               : natural := 8;
    constant DMAERR_LSB               : natural := 5;
    constant DMAERR_RESET             : std_logic_vector(3 downto 0) := "0000";
    constant DMADONE_MSB              : natural := 4;
    constant DMADONE_LSB              : natural := 1;
    constant DMADONE_RESET            : std_logic_vector(3 downto 0) := "0000";
    constant DMABUSY_MSB              : natural := 0;
    constant DMABUSY_LSB              : natural := 0;
    constant DMABUSY_RESET            : std_logic_vector(0 downto 0) := "0";

    -- DMAxC0SRC: Channel 0 source byte address in the 0x0-0x1FFFF shared window (word-aligned: bits[1:0] must be 0; bits[31:17] must be 0)
    constant DMAxC0SRC_WORD           : natural := 2;
    constant DMAxC0SRC_ADDR           : natural := 8;
    constant DMAxC0SRC_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC0SRC_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC0SRC_MSB             : natural := 31;
    constant DMAC0SRC_LSB             : natural := 0;
    constant DMAC0SRC_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC0DST: Channel 0 destination byte address (same word-aligned / in-window / TCM-hole rules as C0SRC, D13/A18)
    constant DMAxC0DST_WORD           : natural := 3;
    constant DMAxC0DST_ADDR           : natural := 12;
    constant DMAxC0DST_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC0DST_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC0DST_MSB             : natural := 31;
    constant DMAC0DST_LSB             : natural := 0;
    constant DMAC0DST_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC0LEN: Channel 0 transfer length in WORDS
    constant DMAxC0LEN_WORD           : natural := 4;
    constant DMAxC0LEN_ADDR           : natural := 16;
    constant DMAxC0LEN_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC0LEN_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC0LEN_MSB             : natural := 31;
    constant DMAC0LEN_LSB             : natural := 0;
    constant DMAC0LEN_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC0CFG: Channel 0 configuration: source/dest auto-increment (SINC/DINC, +4 per word when set, else a fixed peripheral data register), trigger source (TRIG), channel priority class (PRIO) and CRC ride-along enable (CRCEN)
    constant DMAxC0CFG_WORD           : natural := 5;
    constant DMAxC0CFG_ADDR           : natural := 20;
    constant DMAxC0CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC0CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant DMAC0CRCEN_MSB           : natural := 7;
    constant DMAC0CRCEN_LSB           : natural := 7;
    constant DMAC0CRCEN_RESET         : std_logic_vector(0 downto 0) := "0";
    constant DMAC0PRIO_MSB            : natural := 6;
    constant DMAC0PRIO_LSB            : natural := 6;
    constant DMAC0PRIO_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC0TRIG_MSB            : natural := 5;
    constant DMAC0TRIG_LSB            : natural := 2;
    constant DMAC0TRIG_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant DMAC0DINC_MSB            : natural := 1;
    constant DMAC0DINC_LSB            : natural := 1;
    constant DMAC0DINC_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC0SINC_MSB            : natural := 0;
    constant DMAC0SINC_LSB            : natural := 0;
    constant DMAC0SINC_RESET          : std_logic_vector(0 downto 0) := "0";

    -- DMAxC1SRC: Channel 1 source byte address in the 0x0-0x1FFFF shared window (word-aligned: bits[1:0] must be 0; bits[31:17] must be 0)
    constant DMAxC1SRC_WORD           : natural := 6;
    constant DMAxC1SRC_ADDR           : natural := 24;
    constant DMAxC1SRC_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC1SRC_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC1SRC_MSB             : natural := 31;
    constant DMAC1SRC_LSB             : natural := 0;
    constant DMAC1SRC_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC1DST: Channel 1 destination byte address (same word-aligned / in-window / TCM-hole rules as C1SRC, D13/A18)
    constant DMAxC1DST_WORD           : natural := 7;
    constant DMAxC1DST_ADDR           : natural := 28;
    constant DMAxC1DST_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC1DST_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC1DST_MSB             : natural := 31;
    constant DMAC1DST_LSB             : natural := 0;
    constant DMAC1DST_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC1LEN: Channel 1 transfer length in WORDS
    constant DMAxC1LEN_WORD           : natural := 8;
    constant DMAxC1LEN_ADDR           : natural := 32;
    constant DMAxC1LEN_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC1LEN_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC1LEN_MSB             : natural := 31;
    constant DMAC1LEN_LSB             : natural := 0;
    constant DMAC1LEN_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC1CFG: Channel 1 configuration: source/dest auto-increment (SINC/DINC, +4 per word when set, else a fixed peripheral data register), trigger source (TRIG), channel priority class (PRIO) and CRC ride-along enable (CRCEN)
    constant DMAxC1CFG_WORD           : natural := 9;
    constant DMAxC1CFG_ADDR           : natural := 36;
    constant DMAxC1CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC1CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant DMAC1CRCEN_MSB           : natural := 7;
    constant DMAC1CRCEN_LSB           : natural := 7;
    constant DMAC1CRCEN_RESET         : std_logic_vector(0 downto 0) := "0";
    constant DMAC1PRIO_MSB            : natural := 6;
    constant DMAC1PRIO_LSB            : natural := 6;
    constant DMAC1PRIO_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC1TRIG_MSB            : natural := 5;
    constant DMAC1TRIG_LSB            : natural := 2;
    constant DMAC1TRIG_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant DMAC1DINC_MSB            : natural := 1;
    constant DMAC1DINC_LSB            : natural := 1;
    constant DMAC1DINC_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC1SINC_MSB            : natural := 0;
    constant DMAC1SINC_LSB            : natural := 0;
    constant DMAC1SINC_RESET          : std_logic_vector(0 downto 0) := "0";

    -- DMAxC2SRC: Channel 2 source byte address in the 0x0-0x1FFFF shared window (word-aligned: bits[1:0] must be 0; bits[31:17] must be 0)
    constant DMAxC2SRC_WORD           : natural := 10;
    constant DMAxC2SRC_ADDR           : natural := 40;
    constant DMAxC2SRC_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC2SRC_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC2SRC_MSB             : natural := 31;
    constant DMAC2SRC_LSB             : natural := 0;
    constant DMAC2SRC_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC2DST: Channel 2 destination byte address (same word-aligned / in-window / TCM-hole rules as C2SRC, D13/A18)
    constant DMAxC2DST_WORD           : natural := 11;
    constant DMAxC2DST_ADDR           : natural := 44;
    constant DMAxC2DST_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC2DST_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC2DST_MSB             : natural := 31;
    constant DMAC2DST_LSB             : natural := 0;
    constant DMAC2DST_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC2LEN: Channel 2 transfer length in WORDS
    constant DMAxC2LEN_WORD           : natural := 12;
    constant DMAxC2LEN_ADDR           : natural := 48;
    constant DMAxC2LEN_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC2LEN_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC2LEN_MSB             : natural := 31;
    constant DMAC2LEN_LSB             : natural := 0;
    constant DMAC2LEN_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC2CFG: Channel 2 configuration: source/dest auto-increment (SINC/DINC, +4 per word when set, else a fixed peripheral data register), trigger source (TRIG), channel priority class (PRIO) and CRC ride-along enable (CRCEN)
    constant DMAxC2CFG_WORD           : natural := 13;
    constant DMAxC2CFG_ADDR           : natural := 52;
    constant DMAxC2CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC2CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant DMAC2CRCEN_MSB           : natural := 7;
    constant DMAC2CRCEN_LSB           : natural := 7;
    constant DMAC2CRCEN_RESET         : std_logic_vector(0 downto 0) := "0";
    constant DMAC2PRIO_MSB            : natural := 6;
    constant DMAC2PRIO_LSB            : natural := 6;
    constant DMAC2PRIO_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC2TRIG_MSB            : natural := 5;
    constant DMAC2TRIG_LSB            : natural := 2;
    constant DMAC2TRIG_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant DMAC2DINC_MSB            : natural := 1;
    constant DMAC2DINC_LSB            : natural := 1;
    constant DMAC2DINC_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC2SINC_MSB            : natural := 0;
    constant DMAC2SINC_LSB            : natural := 0;
    constant DMAC2SINC_RESET          : std_logic_vector(0 downto 0) := "0";

    -- DMAxC3SRC: Channel 3 source byte address in the 0x0-0x1FFFF shared window (word-aligned: bits[1:0] must be 0; bits[31:17] must be 0)
    constant DMAxC3SRC_WORD           : natural := 14;
    constant DMAxC3SRC_ADDR           : natural := 56;
    constant DMAxC3SRC_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC3SRC_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC3SRC_MSB             : natural := 31;
    constant DMAC3SRC_LSB             : natural := 0;
    constant DMAC3SRC_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC3DST: Channel 3 destination byte address (same word-aligned / in-window / TCM-hole rules as C3SRC, D13/A18)
    constant DMAxC3DST_WORD           : natural := 15;
    constant DMAxC3DST_ADDR           : natural := 60;
    constant DMAxC3DST_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC3DST_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC3DST_MSB             : natural := 31;
    constant DMAC3DST_LSB             : natural := 0;
    constant DMAC3DST_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC3LEN: Channel 3 transfer length in WORDS
    constant DMAxC3LEN_WORD           : natural := 16;
    constant DMAxC3LEN_ADDR           : natural := 64;
    constant DMAxC3LEN_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC3LEN_IMPL           : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant DMAC3LEN_MSB             : natural := 31;
    constant DMAC3LEN_LSB             : natural := 0;
    constant DMAC3LEN_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- DMAxC3CFG: Channel 3 configuration: source/dest auto-increment (SINC/DINC, +4 per word when set, else a fixed peripheral data register), trigger source (TRIG), channel priority class (PRIO) and CRC ride-along enable (CRCEN)
    constant DMAxC3CFG_WORD           : natural := 17;
    constant DMAxC3CFG_ADDR           : natural := 68;
    constant DMAxC3CFG_RESET          : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxC3CFG_IMPL           : std_logic_vector(31 downto 0) := "00000000000000000000000011111111";
    constant DMAC3CRCEN_MSB           : natural := 7;
    constant DMAC3CRCEN_LSB           : natural := 7;
    constant DMAC3CRCEN_RESET         : std_logic_vector(0 downto 0) := "0";
    constant DMAC3PRIO_MSB            : natural := 6;
    constant DMAC3PRIO_LSB            : natural := 6;
    constant DMAC3PRIO_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC3TRIG_MSB            : natural := 5;
    constant DMAC3TRIG_LSB            : natural := 2;
    constant DMAC3TRIG_RESET          : std_logic_vector(3 downto 0) := "0000";
    constant DMAC3DINC_MSB            : natural := 1;
    constant DMAC3DINC_LSB            : natural := 1;
    constant DMAC3DINC_RESET          : std_logic_vector(0 downto 0) := "0";
    constant DMAC3SINC_MSB            : natural := 0;
    constant DMAC3SINC_LSB            : natural := 0;
    constant DMAC3SINC_RESET          : std_logic_vector(0 downto 0) := "0";

    -- DMAxCRC: CRC16-CDMA2000 (poly 0xC857) accumulator / seed, resets to 0xFFFF
    constant DMAxCRC_WORD             : natural := 18;
    constant DMAxCRC_ADDR             : natural := 72;
    constant DMAxCRC_RESET            : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant DMAxCRC_IMPL             : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant DMACRC_MSB               : natural := 15;
    constant DMACRC_LSB               : natural := 0;
    constant DMACRC_RESET             : std_logic_vector(15 downto 0) := "1111111111111111";

    -- DMAxDESC: Reserved for a descriptor-chain head pointer (out of scope this single-shot phase)
    constant DMAxDESC_WORD            : natural := 19;
    constant DMAxDESC_ADDR            : natural := 76;
    constant DMAxDESC_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant DMAxDESC_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- periph_regs tables (hdl/common/periph_regs.vhd), one row per word in slot
    -- order. Every mask below is a property of this description. RDTHRU, WIDEWR,
    -- FULLWR and STROBE_HOLD are the entity's own and are set at the instance;
    -- hdl/common/regs/REGFILE.md says why they cannot come from SystemRDL.
    constant NWORDS                   : natural := 20;
    subtype  reg_arr_t is word_array(0 to NWORDS-1);

    -- reset word, loaded on the asynchronous resetn
    constant RSTVAL   : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"0000FFFF",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- bits that hold a software-written flop; periph_regs stores exactly these
    constant IMPL     : reg_arr_t := (
        x"000031FF",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"FFFFFFFF",   -- DMAxC0SRC
        x"FFFFFFFF",   -- DMAxC0DST
        x"FFFFFFFF",   -- DMAxC0LEN
        x"000000FF",   -- DMAxC0CFG
        x"FFFFFFFF",   -- DMAxC1SRC
        x"FFFFFFFF",   -- DMAxC1DST
        x"FFFFFFFF",   -- DMAxC1LEN
        x"000000FF",   -- DMAxC1CFG
        x"FFFFFFFF",   -- DMAxC2SRC
        x"FFFFFFFF",   -- DMAxC2DST
        x"FFFFFFFF",   -- DMAxC2LEN
        x"000000FF",   -- DMAxC2CFG
        x"FFFFFFFF",   -- DMAxC3SRC
        x"FFFFFFFF",   -- DMAxC3DST
        x"FFFFFFFF",   -- DMAxC3LEN
        x"000000FF",   -- DMAxC3CFG
        x"0000FFFF",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- a written 1 clears (onwrite = woclr): drives w1c_hit
    constant W1C      : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"000001FE",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"00000000",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- a written 1 sets (onwrite = woset): drives woset_hit
    constant WOSET    : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"00000000",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- a written 1 toggles (onwrite = wot): drives wot_hit
    constant WOT      : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"00000000",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- self-clearing strobe (singlepulse): drives wr_pulse, stores nothing
    constant PULSE    : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"00000000",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- a read retires (onread = rclr): drives rd_clr
    constant RCLR     : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000000",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"00000000",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"00000000",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"00000000",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"00000000",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"00000000",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

    -- bits hardware drives (hw = w or rw): what hw_we / hw_set / hw_clr may touch
    constant HWOWN    : reg_arr_t := (
        x"00000000",   -- DMAxCR
        x"00000FFF",   -- DMAxSR
        x"00000000",   -- DMAxC0SRC
        x"00000000",   -- DMAxC0DST
        x"FFFFFFFF",   -- DMAxC0LEN
        x"00000000",   -- DMAxC0CFG
        x"00000000",   -- DMAxC1SRC
        x"00000000",   -- DMAxC1DST
        x"FFFFFFFF",   -- DMAxC1LEN
        x"00000000",   -- DMAxC1CFG
        x"00000000",   -- DMAxC2SRC
        x"00000000",   -- DMAxC2DST
        x"FFFFFFFF",   -- DMAxC2LEN
        x"00000000",   -- DMAxC2CFG
        x"00000000",   -- DMAxC3SRC
        x"00000000",   -- DMAxC3DST
        x"FFFFFFFF",   -- DMAxC3LEN
        x"00000000",   -- DMAxC3CFG
        x"0000FFFF",   -- DMAxCRC
        x"00000000"    -- DMAxDESC
    );

end package dma_regs_pkg;
