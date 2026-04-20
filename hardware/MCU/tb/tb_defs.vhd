-- RISC-V Testbench Definitions and Functions Package
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;

package tb_defs is

    -- Note: All instruction tests passed compressed post genus 
    -- Note: All Peripheral Tests pass uncompressed post genus except SPI and SPISR - HF glitch on SCK in TB
    -- Note: All periph test pass compressed post Innovus 

    
    -- Type definitions
    type file_array is array (natural range <>) of string(1 to 44);

        -- List of RCF test files
    constant test_files : file_array := (
        -- "../../../verification/isa/rcf/rv32ui-p-simple.rcf", -- Simplest Test
        -- "../../../verification/isa/rcf/invalid.rcf", -- Invalid SPI Flash Command Tests
        -- "../../../verification/isa/rcf/load_stpgtram.rcf", -- Start address greater than RAM end
        -- "../../../verification/isa/rcf/load_strtgtstp.rcf", -- Start address greater than stop address
        -- "../../../verification/isa/rcf/load_strtltram.rcf", -- Start address less than RAM lower bound
        "../../../verification/isa/rcf/rv32ua-p-lrsc.rcf", -- Currently only working if ran on its own - signature section overwritten by previous tests. Also - need to zero foo section of memory to work post genus. Fail innovus
        "../../../verification/isa/rcf/rv32ui-p-lb.rcf", -- Load Instructions - Start innovus pass 11/11
        "../../../verification/isa/rcf/rv32ui-p-lh.rcf",
        "../../../verification/isa/rcf/rv32ui-p-lw.rcf", 
        "../../../verification/isa/rcf/rv32ui-p-lbu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-lhu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-addi.rcf",  -- Immediete Instructions
        "../../../verification/isa/rcf/rv32ui-p-slli.rcf",
        "../../../verification/isa/rcf/rv32ui-p-slti.rcf",
        "../../../verification/isa/rcf/rv32ui-p-sltiu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-srli.rcf",
        "../../../verification/isa/rcf/rv32ui-p-srai.rcf",
        "../../../verification/isa/rcf/rv32ui-p-ori.rcf",
        "../../../verification/isa/rcf/rv32ui-p-andi.rcf",
        "../../../verification/isa/rcf/rv32ui-p-auipc.rcf", -- AUIPC
        "../../../verification/isa/rcf/rv32ui-p-sb.rcf", -- Store Instructions
        "../../../verification/isa/rcf/rv32ui-p-sh.rcf",
        "../../../verification/isa/rcf/rv32ui-p-sw.rcf",
        "../../../verification/isa/rcf/rv32ui-p-add.rcf", -- Arithmetic Instructions
        "../../../verification/isa/rcf/rv32ui-p-sub.rcf",
        "../../../verification/isa/rcf/rv32ui-p-sll.rcf",
        "../../../verification/isa/rcf/rv32ui-p-slt.rcf",
        "../../../verification/isa/rcf/rv32ui-p-sltu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-xor.rcf",
        "../../../verification/isa/rcf/rv32ui-p-srl.rcf",
        "../../../verification/isa/rcf/rv32ui-p-sra.rcf",
        "../../../verification/isa/rcf/rv32ui-p-or.rcf",
        "../../../verification/isa/rcf/rv32ui-p-and.rcf",
        "../../../verification/isa/rcf/rv32ui-p-lui.rcf", 
        "../../../verification/isa/rcf/rv32ui-p-beq.rcf", --Branch Instructions
        "../../../verification/isa/rcf/rv32ui-p-bne.rcf",
        "../../../verification/isa/rcf/rv32ui-p-blt.rcf",
        "../../../verification/isa/rcf/rv32ui-p-bge.rcf",
        "../../../verification/isa/rcf/rv32ui-p-bltu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-bgeu.rcf",
        "../../../verification/isa/rcf/rv32ui-p-jalr.rcf", --Jump Instructions
        "../../../verification/isa/rcf/rv32ui-p-jal.rcf", 
        "../../../verification/isa/rcf/rv32uc-p-rvc.rcf", -- NO longer needed - all tests are compiled compressed
        "../../../verification/isa/rcf/rv32um-p-div.rcf", -- Division Instructions
        "../../../verification/isa/rcf/rv32um-p-divu.rcf",
        "../../../verification/isa/rcf/rv32um-p-mul.rcf", -- Multiplication Instructions
        "../../../verification/isa/rcf/rv32um-p-mulh.rcf",
        "../../../verification/isa/rcf/rv32um-p-mulhsu.rcf",
        "../../../verification/isa/rcf/rv32um-p-mulhu.rcf", 
        "../../../verification/isa/rcf/rv32um-p-rem.rcf", -- Remainder Instructions 
        "../../../verification/isa/rcf/rv32um-p-remu.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amoadd_w.rcf", -- Atomic Instructions
        "../../../verification/isa/rcf/rv32ua-p-amoand_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amomax_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amomaxu_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amomin_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amominu_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amoor_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amoxor_w.rcf",
        "../../../verification/isa/rcf/rv32ua-p-amoswap_w.rcf",
        "../../../verification/isa/rcf/rv32uzba-p-sh1add.rcf", -- Bit Manipulation - Address Generation Instructions - pass start innovus
        "../../../verification/isa/rcf/rv32uzba-p-sh2add.rcf",
        "../../../verification/isa/rcf/rv32uzba-p-sh3add.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-ror.rcf", -- Bit Manipulation - Basic Instructions
        "../../../verification/isa/rcf/rv32uzbb-p-sext_b.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-sext_h.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-zext_h.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-orc_b.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-andn.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-cpop.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-maxu.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-minu.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-rev8.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-rori.rcf", 
        "../../../verification/isa/rcf/rv32uzbb-p-xnor.rcf", -- pass end innovus
        "../../../verification/isa/rcf/rv32uzbb-p-clz.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-ctz.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-max.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-min.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-orn.rcf",
        "../../../verification/isa/rcf/rv32uzbb-p-rol.rcf", 
        "../../../verification/isa/rcf/rv32uzbs-p-bclri.rcf", -- Bit Manipulation - Single Bit Instructions
        "../../../verification/isa/rcf/rv32uzbs-p-bexti.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-binvi.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-bseti.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-bclr.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-bext.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-binv.rcf",
        "../../../verification/isa/rcf/rv32uzbs-p-bset.rcf", -- inn
        "../../../verification/isa/rcf/rv32uzbc-p-clmulh.rcf", -- Bit Manipulation - Carryless Mult Instructions
        "../../../verification/isa/rcf/rv32uzbc-p-clmulr.rcf", -- Fail Genus 11/01/25
        "../../../verification/isa/rcf/rv32uzbc-p-clmul.rcf",
        "../../../verification/isa/rcf/rv32ziscr-p-csr.rcf", -- CSR Instructions (Custom)
        "../../../verification/isa/rcf/periph-p-UART.rcf",  
        "../../../verification/isa/rcf/periph-p-UARTIRQ.rcf", 
        "../../../verification/isa/rcf/periph-p-SYSTEM.rcf", 
        "../../../verification/isa/rcf/periph-p-TIMER.rcf",
        "../../../verification/isa/rcf/periph-p-NPU.rcf", -- Peripheral Tests
        "../../../verification/isa/rcf/periph-p-SPIFM.rcf",
        "../../../verification/isa/rcf/periph-p-AFE.rcf",  
        "../../../verification/isa/rcf/periph-p-SARADC.rcf",  
        "../../../verification/isa/rcf/periph-p-GPIO1.rcf",   
        "../../../verification/isa/rcf/periph-p-GPIO2.rcf",   
        "../../../verification/isa/rcf/rv32ziscr-p-csr.rcf"     -- CSR Instructions (Custom)    
        -- "../../../verification/isa/rcf/periph-p-SPI.rcf",  -- not tested here down
        -- "../../../verification/isa/rcf/periph-p-SPISR.rcf", -- New SPI Slave test - SCK hf glitch in tb
        -- "../../../verification/isa/rcf/periph-p-SPI.rcf" 
       
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
        constant NL : character := character'val(10);
    begin
        return NL & 
            "  _____         _____ _____        .-'''-." & NL &
            " |  __ \ /\    / ____/ ____|      / .===. \ " & NL &
            " | |__) /  \  | (___| (___        \/ 6 6 \/ " & NL &
            " |  ___/ /\ \  \___ \\___ \       ( \___/ ) " & NL &
            " | |  / ____ \ ____) |___) |  _ooo__\_____/______" & NL &
            " |_| /_/    \_\_____/_____/  /                   \ " & NL &
            "                            |   ALL TESTS PASS!   |" & NL &
            "                             \___________________/" & NL;
    end function;

end package body tb_defs;








