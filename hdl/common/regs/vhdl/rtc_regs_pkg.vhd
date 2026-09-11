-- VestaRV: RTC register package
-- Real-Time Clock: a 32.768 kHz always-on wall clock (32-bit seconds + 15-bit subsecond prescaler) with a one-shot alarm compare and a recurring periodic tick, delivered on ONE combined interrupt (vector 114)
-- Generated from hdl/common/regs/rdl/rtc.rdl by platform/common/python/rdl_vhdl.py.
-- Do not edit; regenerate with `bazel run //platform/common/python:rdl_vhdl_pkgs`.
-- _WORD is a word offset, _ADDR a byte offset, _IMPL the mask of bits holding a software-written flop.

library ieee;
use ieee.std_logic_1164.all;

package rtc_regs_pkg is

    -- RTCxCR: RTC control register
    constant RTCxCR_WORD              : natural := 0;
    constant RTCxCR_ADDR              : natural := 0;
    constant RTCxCR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxCR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000011111";
    constant RTCTICKIE_MSB            : natural := 4;
    constant RTCTICKIE_LSB            : natural := 4;
    constant RTCTICKIE_RESET          : std_logic_vector(0 downto 0) := "0";
    constant RTCALMIE_MSB             : natural := 3;
    constant RTCALMIE_LSB             : natural := 3;
    constant RTCALMIE_RESET           : std_logic_vector(0 downto 0) := "0";
    constant RTCTICKEN_MSB            : natural := 2;
    constant RTCTICKEN_LSB            : natural := 2;
    constant RTCTICKEN_RESET          : std_logic_vector(0 downto 0) := "0";
    constant RTCALMEN_MSB             : natural := 1;
    constant RTCALMEN_LSB             : natural := 1;
    constant RTCALMEN_RESET           : std_logic_vector(0 downto 0) := "0";
    constant RTCEN_MSB                : natural := 0;
    constant RTCEN_LSB                : natural := 0;
    constant RTCEN_RESET              : std_logic_vector(0 downto 0) := "0";

    -- RTCxSEC: Wall-clock seconds
    constant RTCxSEC_WORD             : natural := 1;
    constant RTCxSEC_ADDR             : natural := 4;
    constant RTCxSEC_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxSEC_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant RTCSEC_MSB               : natural := 31;
    constant RTCSEC_LSB               : natural := 0;
    constant RTCSEC_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- RTCxSUB: Subsecond prescaler, 0 to 32767 (2^15 - 1)
    constant RTCxSUB_WORD             : natural := 2;
    constant RTCxSUB_ADDR             : natural := 8;
    constant RTCxSUB_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxSUB_IMPL             : std_logic_vector(31 downto 0) := "00000000000000000111111111111111";
    constant RTCSUB_MSB               : natural := 14;
    constant RTCSUB_LSB               : natural := 0;
    constant RTCSUB_RESET             : std_logic_vector(14 downto 0) := "000000000000000";

    -- RTCxALM: Alarm compare value, in seconds
    constant RTCxALM_WORD             : natural := 3;
    constant RTCxALM_ADDR             : natural := 12;
    constant RTCxALM_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxALM_IMPL             : std_logic_vector(31 downto 0) := "11111111111111111111111111111111";
    constant RTCALM_MSB               : natural := 31;
    constant RTCALM_LSB               : natural := 0;
    constant RTCALM_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- RTCxPER: Periodic-tick reload, in subsecond (LFXT) ticks: a tick event fires every reload+1 LFXT ticks (~2 s max interval at 32.768 kHz, adjudication A4)
    constant RTCxPER_WORD             : natural := 4;
    constant RTCxPER_ADDR             : natural := 16;
    constant RTCxPER_RESET            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxPER_IMPL             : std_logic_vector(31 downto 0) := "00000000000000001111111111111111";
    constant RTCPER_MSB               : natural := 15;
    constant RTCPER_LSB               : natural := 0;
    constant RTCPER_RESET             : std_logic_vector(15 downto 0) := "0000000000000000";

    -- RTCxSR: RTC status register
    constant RTCxSR_WORD              : natural := 5;
    constant RTCxSR_ADDR              : natural := 20;
    constant RTCxSR_RESET             : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxSR_IMPL              : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCTICKF_MSB             : natural := 2;
    constant RTCTICKF_LSB             : natural := 2;
    constant RTCTICKF_RESET           : std_logic_vector(0 downto 0) := "0";
    constant RTCALMF_MSB              : natural := 1;
    constant RTCALMF_LSB              : natural := 1;
    constant RTCALMF_RESET            : std_logic_vector(0 downto 0) := "0";
    constant RTCSYNC_MSB              : natural := 0;
    constant RTCSYNC_LSB              : natural := 0;
    constant RTCSYNC_RESET            : std_logic_vector(0 downto 0) := "0";

    -- RTCxTRIM: Reserved for digital fractional-prescaler / ppm calibration (deferred)
    constant RTCxTRIM_WORD            : natural := 6;
    constant RTCxTRIM_ADDR            : natural := 24;
    constant RTCxTRIM_RESET           : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";
    constant RTCxTRIM_IMPL            : std_logic_vector(31 downto 0) := "00000000000000000000000000000000";

    -- RTC.vhd's own decode identifiers: the word each register is
    -- decoded at, spelled the way that file already spells it, so adopting this
    -- package is a context clause plus a deletion and no assignment moves.
    constant SLOT_CR                  : natural := 0;
    constant SLOT_SEC                 : natural := 1;
    constant SLOT_SUB                 : natural := 2;
    constant SLOT_ALM                 : natural := 3;
    constant SLOT_PER                 : natural := 4;
    constant SLOT_SR                  : natural := 5;
    constant SLOT_TRIM                : natural := 6;

end package rtc_regs_pkg;
