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

    
    -- Type definitions
    type file_array is array (natural range <>) of string(1 to 29);

        -- List of RCF test files
    constant test_files : file_array := (
        -- "../rcf/xxxrv32ui-p-simple.rcf", -- Simplest Test
        -- "../rcf/xxxxxrv32ua-p-lrsc.rcf", -- Currently only working if ran on its own - signature section overwritten by previous tests. Also - need to zero foo section of memory to work post genus. Fail innovus
        "../rcf/xxxxxxxrv32ui-p-lb.rcf", -- Load Instructions
        "../rcf/xxxxxxxrv32ui-p-lh.rcf",
        "../rcf/xxxxxxxrv32ui-p-lw.rcf", 
        "../rcf/xxxxxxrv32ui-p-lbu.rcf",
        "../rcf/xxxxxxrv32ui-p-lhu.rcf",
        "../rcf/xxxxxrv32ui-p-addi.rcf",  -- Immediete Instructions
        "../rcf/xxxxxrv32ui-p-slli.rcf",
        "../rcf/xxxxxrv32ui-p-slti.rcf",
        "../rcf/xxxxrv32ui-p-sltiu.rcf",
        "../rcf/xxxxxrv32ui-p-srli.rcf",
        "../rcf/xxxxxrv32ui-p-srai.rcf",
        "../rcf/xxxxxxrv32ui-p-ori.rcf",
        "../rcf/xxxxxrv32ui-p-andi.rcf",
        "../rcf/xxxxrv32ui-p-auipc.rcf", -- AUIPC
        "../rcf/xxxxxxxrv32ui-p-sb.rcf", -- Store Instructions
        "../rcf/xxxxxxxrv32ui-p-sh.rcf",
        "../rcf/xxxxxxxrv32ui-p-sw.rcf",
        "../rcf/xxxxxxrv32ui-p-add.rcf", -- Arithmetic Instructions
        "../rcf/xxxxxxrv32ui-p-sub.rcf",
        "../rcf/xxxxxxrv32ui-p-sll.rcf",
        "../rcf/xxxxxxrv32ui-p-slt.rcf",
        "../rcf/xxxxxrv32ui-p-sltu.rcf",
        "../rcf/xxxxxxrv32ui-p-xor.rcf",
        "../rcf/xxxxxxrv32ui-p-srl.rcf",
        "../rcf/xxxxxxrv32ui-p-sra.rcf",
        "../rcf/xxxxxxxrv32ui-p-or.rcf",
        "../rcf/xxxxxxrv32ui-p-and.rcf",
        "../rcf/xxxxxxrv32ui-p-lui.rcf", 
        "../rcf/xxxxxxrv32ui-p-beq.rcf", --Branch Instructions
        "../rcf/xxxxxxrv32ui-p-bne.rcf",
        "../rcf/xxxxxxrv32ui-p-blt.rcf",
        "../rcf/xxxxxxrv32ui-p-bge.rcf",
        "../rcf/xxxxxrv32ui-p-bltu.rcf",
        "../rcf/xxxxxrv32ui-p-bgeu.rcf",
        "../rcf/xxxxxrv32ui-p-jalr.rcf", --Jump Instructions
        "../rcf/xxxxxxrv32ui-p-jal.rcf", 
        "../rcf/xxxxxxrv32uc-p-rvc.rcf", 
        "../rcf/xxxxxxrv32um-p-div.rcf", -- Division Instructions
        "../rcf/xxxxxrv32um-p-divu.rcf",
        "../rcf/xxxxxxrv32um-p-mul.rcf", -- Multiplication Instructions
        "../rcf/xxxxxrv32um-p-mulh.rcf",
        "../rcf/xxxrv32um-p-mulhsu.rcf",
        "../rcf/xxxxrv32um-p-mulhu.rcf", 
        "../rcf/xxxxxxrv32um-p-rem.rcf", -- Remainder Instructions 
        "../rcf/xxxxxrv32um-p-remu.rcf",
        "../rcf/xrv32ua-p-amoadd_w.rcf", -- Atomic Instructions
        "../rcf/xrv32ua-p-amoand_w.rcf",
        "../rcf/xrv32ua-p-amomax_w.rcf",
        "../rcf/rv32ua-p-amomaxu_w.rcf",
        "../rcf/xrv32ua-p-amomin_w.rcf",
        "../rcf/rv32ua-p-amominu_w.rcf",
        "../rcf/xxrv32ua-p-amoor_w.rcf",
        "../rcf/xrv32ua-p-amoxor_w.rcf",
        "../rcf/rv32ua-p-amoswap_w.rcf",
        "../rcf/xrv32uzba-p-sh1add.rcf", -- Bit Manipulation - Address Generation Instructions - pass start innovus
        "../rcf/xrv32uzba-p-sh2add.rcf",
        "../rcf/xrv32uzba-p-sh3add.rcf",
        "../rcf/xxxxrv32uzbb-p-ror.rcf", -- Bit Manipulation - Basic Instructions
        "../rcf/xrv32uzbb-p-sext_b.rcf",
        "../rcf/xrv32uzbb-p-sext_h.rcf",
        "../rcf/xrv32uzbb-p-zext_h.rcf",
        "../rcf/xxrv32uzbb-p-orc_b.rcf",
        "../rcf/xxxrv32uzbb-p-andn.rcf",
        "../rcf/xxxrv32uzbb-p-cpop.rcf",
        "../rcf/xxxrv32uzbb-p-maxu.rcf",
        "../rcf/xxxrv32uzbb-p-minu.rcf",
        "../rcf/xxxrv32uzbb-p-rev8.rcf",
        "../rcf/xxxrv32uzbb-p-rori.rcf", 
        "../rcf/xxxrv32uzbb-p-xnor.rcf", -- pass end innovus
        "../rcf/xxxxrv32uzbb-p-clz.rcf",
        "../rcf/xxxxrv32uzbb-p-ctz.rcf",
        "../rcf/xxxxrv32uzbb-p-max.rcf",
        "../rcf/xxxxrv32uzbb-p-min.rcf",
        "../rcf/xxxxrv32uzbb-p-orn.rcf",
        "../rcf/xxxxrv32uzbb-p-rol.rcf", 
        "../rcf/xxrv32uzbs-p-bclri.rcf", -- Bit Manipulation - Single Bit Instructions
        "../rcf/xxrv32uzbs-p-bexti.rcf",
        "../rcf/xxrv32uzbs-p-binvi.rcf",
        "../rcf/xxrv32uzbs-p-bseti.rcf",
        "../rcf/xxxrv32uzbs-p-bclr.rcf",
        "../rcf/xxxrv32uzbs-p-bext.rcf",
        "../rcf/xxxrv32uzbs-p-binv.rcf",
        "../rcf/xxxrv32uzbs-p-bset.rcf", -- inn
        "../rcf/xrv32uzbc-p-clmulh.rcf", -- Bit Manipulation - Carryless Mult Instructions
        "../rcf/xrv32uzbc-p-clmulr.rcf", -- Fail Genus 11/01/25
        "../rcf/xxrv32uzbc-p-clmul.rcf",
        "../rcf/xxxrv32ziscr-p-csr.rcf", -- CSR Instructions (Custom)
        "../rcf/xxxxxxperiph-p-NPU.rcf", -- Peripheral Tests
        "../rcf/xxxxperiph-p-SPIFM.rcf",
        "../rcf/xxxxxxperiph-p-AFE.rcf",  
        "../rcf/xxxperiph-p-SARADC.rcf",  
        "../rcf/xxxxperiph-p-GPIO1.rcf",   
        "../rcf/xxxxperiph-p-GPIO2.rcf",   
        "../rcf/xxxxxperiph-p-UART.rcf", 
        "../rcf/xxxperiph-p-SYSTEM.rcf", 
        "../rcf/xxxxperiph-p-TIMER.rcf",
        "../rcf/xxxrv32ziscr-p-csr.rcf",     -- CSR Instructions (Custom)    
        -- "../rcf/xxxxxxperiph-p-SPI.rcf",  -- not tested here down
        "../rcf/xxxxperiph-p-SPISR.rcf" -- New SPI Slave test - SCK hf glitch in tb
       
    );



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








