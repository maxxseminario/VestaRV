/* regfile_firq.vhd
   32-entry architectural register file with a fast-interrupt shadow bank.
   irq_save snapshots the whole file into reg_context and stores the return PC in q0; irq_restore copies the shadow bank back in one cycle. */
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

/* Register | ABI Name | Description
   ---------+----------+--------------------------------------------------------
   x0       | zero     | Hardwired to 0 (read-only)
   x1       | ra       | Return address (for JAL/JALR)
   x2       | sp       | Stack pointer
   x3       | gp       | Global pointer (for static data)
   x4       | tp       | Thread pointer (for TLS)
   x5-x7    | t0-t2    | Temporary registers
   x8       | s0/fp    | Saved register or frame pointer
   x9       | s1       | Saved register
   x10-x11  | a0-a1    | Function arguments and return values
   x12-x17  | a2-a7    | Function arguments
   x18-x27  | s2-s11   | Saved registers
   x28-x31  | t3-t6    | Temporary registers */

entity regfile is
    port (
        clk:  in  STD_LOGIC;
        resetn:  in  STD_LOGIC;
        we3:  in  STD_LOGIC;                        -- Write enable for the write port
        a1:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 1
        a2:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Read address 2
        a3:   in  STD_LOGIC_VECTOR(4 downto 0);     -- Write address
        wd3:  in  STD_LOGIC_VECTOR(XLEN-1 downto 0);    -- Write data
        rd1:  out STD_LOGIC_VECTOR(XLEN-1 downto 0);    -- Read data 1
        rd2:  out STD_LOGIC_VECTOR(XLEN-1 downto 0);     -- Read data 2

        -- IRQ
        irq_save: in std_logic;     -- Must be high for exactly one clock cycle
        irq_restore: in std_logic; -- Must be high for exactly one clock cycle
        pc : in std_logic_vector(XLEN-1 downto 0); -- Current program counter, captured into q0 on irq_save
        q0 : out std_logic_vector(XLEN-1 downto 0); -- Saved interrupt return address

        -- Test export: a0 is the pass/fail word the testbench watches.
        a0: out std_logic_vector(XLEN-1 downto 0)

    );
end entity regfile;

-- TODO: drop the physical x0 entry from the array, since it is hardwired to 0.

architecture behav of regfile is
    type reg_array is array (0 to 31) of std_logic_vector(XLEN-1 downto 0);
    signal registers: reg_array;
    signal reg_context: reg_array;
    signal clk_irq : std_logic;

begin

    -- Synchronous write port; a restore beats an ordinary write in the same cycle.
    reg_wr: process(clk)
    begin
        if resetn = '0' then
            registers <= (others => (others => '0')); -- Clear the whole file on reset
        elsif rising_edge(clk) then
            -- A normal write lands only when we3 is asserted AND the destination is not x0, which stays hardwired to 0.
            if irq_restore = '1' then
                registers <= reg_context; -- Restore every register from the shadow bank
            elsif we3 = '1' and a3 /= "00000" then
                registers(0) <= (others => '0');
                registers(slv2uint(a3)) <= wd3;
            end if;
        end if;
    end process;

    -------- IRQ handling -------

    
    -- irq_save acts as a gated clock from the irq_handler: its rising edge snapshots the file.
    context_save_proc: process(resetn, irq_save)
    begin
        if resetn = '0' then
            reg_context <= (others => (others => '0'));
            q0 <= (others => '0');
        elsif rising_edge(irq_save) then 
            reg_context <= registers; 
            q0 <= pc; -- Keep the interrupted PC as the return address
        end if;
    end process;

    -- Asynchronous read ports.
    rd1 <= registers(slv2uint(a1));
    rd2 <= registers(slv2uint(a2));

    -- Export a0 (x10) for the testbench pass/fail check.
    a0 <=registers(10);

end architecture behav;

