/* =============================================================================
   sar_macro_model.vhd: SIMULATION-ONLY behavioural model of one anatop_pixel SAR converter, the analog macro side of an AFE2 site.
   Ported verbatim in protocol from hdl/common/tb/AFE2_tb.vhd's inline model (2026-09-05); the bench signals that steered that copy (per-site input code, READY suppression) are generics here so the entity can be instantiated from the generated riscv_tb.vhd with no bench plumbing.

   PROTOCOL (SIM_STATUS 2.4, firmware contract section 4, measured in F14 section 1):
     One bit trial per FALLING edge of sar_clk. Twelve falling edges per conversion: 1 clear, 1 sample (the APERTURE, where the input is captured), then ten trials.
     sar_rdy rises 1 ns after the twelfth falling edge and is held RDY_HOLD; the bus is valid only inside that window and reads all ones outside it, exactly as the macro does (a missed capture therefore returns raw 1023 = code 511, not an error).
     The bus carries the RAW code, i.e. the true code with bit 9 inverted; AFE2.vhd un-inverts it. Measured hold after the READY rise is 2 sar_clk periods (100.0 ns at 20 MHz, 166.7 ns at 12 MHz), so RDY_HOLD defaults to the 20 MHz figure and is the pessimistic case for a 12 MHz trigger.
     QUIET is the macro's settling requirement after sar_rst releases; a trigger clock inside it is an assertion failure, which is what AFE2.vhd's QUIET_CYCLES counter exists to prevent.

   RETURNED CODE. Predictable by construction, so a directed test can compare an exact word:
     normal      code = CODE when CODE >= 0, else (BASE_CODE + SITE) mod 1024. Site h therefore returns 0x155 + h with the defaults.
     ctl echo    when SARADC_SEL (ctl(7 downto 4)) = ECHO_SEL and ATP_SEL (ctl(3 downto 0)) is 0..4, the code is instead the 10-bit window ctl(10*w+9 downto 10*w) selected by w = ATP_SEL.
   The echo is the ONLY path by which software can read the 50 control bits back: they leave the MCU for the analog macro and never return. Five windows cover all 50 bits, window 0 including the SARADC_SEL/ATP_SEL field itself, so a test can prove every ctl bit reaches the pin. ECHO_SEL is a MODEL convention, not silicon: the real macro treats all 16 SARADC_SEL codes as analog mux selects.
   ============================================================================= */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sar_macro_model is
    generic (
        SITE      : natural := 0;          -- site index, added to BASE_CODE
        BASE_CODE : natural := 16#155#;    -- site h returns BASE_CODE + h
        CODE      : integer := -1;         -- >= 0 overrides BASE_CODE + SITE
        ECHO_SEL  : natural := 14;         -- SARADC_SEL value that switches the model into ctl echo
        RDY_HOLD  : time := 100 ns;        -- measured macro READY width, 20 MHz trigger
        QUIET     : time := 2 us           -- required settling after sar_rst releases
    );
    port (
        ctl     : in  std_logic_vector(49 downto 0);   -- the site's 50 control bits, anatop_pixel symbol order
        sar_clk : in  std_logic;
        sar_rst : in  std_logic;                       -- active high
        sar_rdy : out std_logic;
        sar_d   : out std_logic_vector(9 downto 0)     -- raw bus: true code with bit 9 inverted
    );
end entity;

architecture sim of sar_macro_model is

    -- The code this conversion returns, sampled at the aperture.
    function aperture_code(c : std_logic_vector(49 downto 0)) return integer is
        variable sel : integer;
        variable w   : integer;
        variable v   : std_logic_vector(9 downto 0) := (others => '0');
    begin
        sel := to_integer(unsigned(c(7 downto 4)));
        w   := to_integer(unsigned(c(3 downto 0)));
        if sel = ECHO_SEL and w <= 4 then
            for b in 0 to 9 loop
                v(b) := c(10*w + b);
            end loop;
            return to_integer(unsigned(v));
        end if;
        if CODE >= 0 then
            return CODE mod 1024;
        end if;
        return (BASE_CODE + SITE) mod 1024;
    end function;

begin

    model : process
        variable n     : integer := 0;     -- falling edges into the current conversion
        variable code  : integer := 0;
        variable t_rel : time := 0 ns;
    begin
        sar_rdy <= '0';
        sar_d   <= (others => '1');
        wait until sar_rst = '0';
        t_rel := now;
        n := 0;
        loop
            wait until falling_edge(sar_clk) or sar_rst = '1';
            if sar_rst = '1' then
                exit;                      -- the process restarts and re-arms on the next release
            end if;
            assert now - t_rel >= QUIET
                report "sar_macro_model(site " & integer'image(SITE)
                     & "): trigger clock inside the quiet window after sar_rst released"
                severity error;
            n := n + 1;
            if n = 2 then
                code := aperture_code(ctl);        -- aperture: the sample pulse's falling edge
            elsif n = 12 then
                n := 0;
                wait for 1 ns;
                sar_d   <= std_logic_vector(to_unsigned(code, 10) xor "1000000000");
                sar_rdy <= '1';
                wait for RDY_HOLD;
                sar_rdy <= '0';
                sar_d   <= (others => '1');
            end if;
        end loop;
    end process;

end architecture;
