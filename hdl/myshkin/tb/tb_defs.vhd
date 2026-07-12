-- RISC-V Testbench Definitions and Functions Package
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.math_real.all;
use ieee.numeric_std.all;
use std.textio.all;

package tb_defs is

    -- Note: All instruction tests passed compressed post genus 
    -- Note: All Peripheral Tests pass uncompressed post genus except SPI and SPISR - HF glitch on SCK in TB
    -- Note: All periph test pass compressed post Innovus 

    



    -- Function declarations
    function contains_gpio1(s : string) return boolean;
    function contains_gpio2(s : string) return boolean;
    function contains_spi(s : string) return boolean;
    function contains_uart(s : string) return boolean;
    function contains_timer(s : string) return boolean;
    function contains_spifem(s : string) return boolean;
    function get_pass_logo return string;

    procedure check_file_exists(
        constant filename : in string;
        variable exists : out boolean
    );
    
end package tb_defs;

package body tb_defs is

    -- Peripheral detection functions - for external MCU routing in TB

    function contains_spifem(s : string) return boolean is
        constant substr : string := "SPIFM";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function;      
    
    function contains_gpio1(s : string) return boolean is
        constant substr : string := "GPIO1";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function;   
    
    function contains_gpio2(s : string) return boolean is
        constant substr : string := "GPIO2";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function;   
    
    function contains_spi(s : string) return boolean is
        constant substr : string := "SPI";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function;   

    function contains_uart(s : string) return boolean is
        constant substr : string := "UART";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function; 

    function contains_timer(s : string) return boolean is
        constant substr : string := "TIMER";
        variable found : boolean := false;
        begin
            for i in s'range loop
                -- Check if there are enough characters left for substr
                if i + substr'length - 1 <= s'high then
                    if s(i to i+substr'length-1) = substr then
                        found := true;
                        exit;
                    end if;
                end if;
            end loop;
            return found;
    end function; 


    procedure check_file_exists(
            constant filename : in string;
            variable exists : out boolean
        ) is
            file test_file : text;
            variable file_status : file_open_status;
        begin
            file_open(file_status, test_file, filename, read_mode);
            if file_status = open_ok then
                exists := true;
                file_close(test_file);
            else
                exists := false;
            end if;
    end procedure;


    
    function get_pass_logo return string is
    begin
        return LF & 
            "  _____         _____ _____        .-'''-." & LF &
            " |  __ \ /\    / ____/ ____|      / .===. \ " & LF &
            " | |__) /  \  | (___| (___        \/ 6 6 \/ " & LF &
            " |  ___/ /\ \  \___ \\___ \       ( \___/ ) " & LF &
            " | |  / ____ \ ____) |___) |  _ooo__\_____/______" & LF &
            " |_| /_/    \_\_____/_____/  /                   \ " & LF &
            "                            |   ALL TESTS PASS!   |" & LF &
            "                             \___________________/" & LF;
    end function;

end package body tb_defs;








