library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity csr_unit is
    port (
        clk              : in  std_logic;
        resetn           : in  std_logic;
        
        -- CSR instruction interface
        csr_addr         : in  std_logic_vector(11 downto 0);  -- CSR address
        csr_write_data   : in  std_logic_vector(31 downto 0);  -- Data to write (from rs1 or immediate)
        csr_op           : in  std_logic_vector(2 downto 0);   -- CSR operation (funct3)
        csr_valid        : in  std_logic;                      -- Valid CSR operation
        csr_read_data    : out std_logic_vector(31 downto 0);  -- Data read from CSR
        
        -- Performance counter input
        inst_retired     : in  std_logic                       -- Instruction retired signal
    );
end csr_unit;

architecture behave of csr_unit is

    -- Performance counters (64-bit)
    signal mcycle     : std_logic_vector(63 downto 0);
    signal minstret   : std_logic_vector(63 downto 0);
    
    -- Internal signals
    signal csr_write_en  : std_logic;
    signal csr_read_val  : std_logic_vector(31 downto 0);
    signal csr_new_val   : std_logic_vector(31 downto 0);

begin

    -- CSR write enable (don't write on read-only operations when rs1/uimm = 0)
    -- csr_write_en <= csr_valid = '1' and 
    --                (csr_op(1) = '1' or csr_op(0) = '1' or  -- Not CSRRW/CSRRWI
    --                 (csr_write_data /= x"00000000"));  -- Or write data is non-zero

    csr_write_en <= csr_valid when (csr_op(1) = '1' or csr_op(0) = '1' 
                                or (csr_write_data /= x"00000000")) 
                                else '0';

    -- CSR read process
    process(csr_addr, mcycle, minstret)
    begin
        case csr_addr is
            -- Machine Counters (Read/Write)
            when CSR_MCYCLE    => csr_read_val <= mcycle(31 downto 0);
            when CSR_MINSTRET  => csr_read_val <= minstret(31 downto 0);
            when CSR_MCYCLEH   => csr_read_val <= mcycle(63 downto 32);
            when CSR_MINSTRETH => csr_read_val <= minstret(63 downto 32);
            
            -- User-readable counters (Read-only shadows of machine counters)
            when CSR_CYCLE     => csr_read_val <= mcycle(31 downto 0);
            when CSR_INSTRET   => csr_read_val <= minstret(31 downto 0);
            when CSR_CYCLEH    => csr_read_val <= mcycle(63 downto 32);
            when CSR_INSTRETH  => csr_read_val <= minstret(63 downto 32);
            
            when others        => csr_read_val <= x"00000000";
        end case;
    end process;

    -- CSR operation computation
    process(csr_op, csr_read_val, csr_write_data)
    begin
        case csr_op is
            when CSRRW_FN3 | CSRRWI_FN3 =>  -- Write
                csr_new_val <= csr_write_data;
            when CSRRS_FN3 | CSRRSI_FN3 =>  -- Set bits
                csr_new_val <= csr_read_val or csr_write_data;
            when CSRRC_FN3 | CSRRCI_FN3 =>  -- Clear bits
                csr_new_val <= csr_read_val and (not csr_write_data);
            when others =>
                csr_new_val <= csr_read_val;
        end case;
    end process;

    -- CSR write process
    process(clk, resetn)
    begin
        if resetn = '0' then
            -- Reset counters to zero
            mcycle <= (others => '0');
            minstret <= (others => '0');
            
        elsif rising_edge(clk) then
            -- Always increment cycle counter
            mcycle <= std_logic_vector(unsigned(mcycle) + 1);
            
            -- Increment instruction counter when instruction retires
            if inst_retired = '1' then
                minstret <= std_logic_vector(unsigned(minstret) + 1);
            end if;
            
            -- Handle CSR writes (allow writing to counters for initialization/adjustment)
            if csr_write_en = '1' then
                case csr_addr is
                    when CSR_MCYCLE =>
                        mcycle(31 downto 0) <= csr_new_val;
                        
                    when CSR_MCYCLEH =>
                        mcycle(63 downto 32) <= csr_new_val;
                        
                    when CSR_MINSTRET =>
                        minstret(31 downto 0) <= csr_new_val;
                        
                    when CSR_MINSTRETH =>
                        minstret(63 downto 32) <= csr_new_val;
                        
                    when others =>
                        null;  -- Read-only CSRs or unimplemented
                end case;
            end if;
        end if;
    end process;

    -- Output read data
    csr_read_data <= csr_read_val;

end behave;