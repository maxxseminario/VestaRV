library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
library work;
use work.constants.ALL;

entity datapath is
    port (
        clk          : in  std_logic;
        resetn       : in  std_logic;
        
        -- ==========================================
        -- Program Counter Interface
        -- ==========================================
        pc           : in  std_logic_vector(31 downto 0);      -- Current PC value
        pc_plus_4    : in  std_logic_vector(31 downto 0);      -- PC + 4 for next sequential instruction
        
        -- ==========================================
        -- Control Signals from Controller
        -- ==========================================
        result_Src   : in  std_logic_vector(2 downto 0);       -- Selects result source (000:ALU, 001:Mem, 010:PC+4, 011:PC_target, 100:CSR)
        pc_src       : in  std_logic;                          -- PC source selection
        ALU_src      : in  std_logic;                          -- ALU operand B source (0:register, 1:immediate)
        reg_write    : in  std_logic;                          -- Register file write enable
        jalr         : in  std_logic;                          -- JALR instruction indicator
        imm_src      : in  std_logic_vector(2 downto 0);       -- Immediate type selector
        funct3       : in  std_logic_vector(2 downto 0);       -- Function field for load/store operations
        mask         : in  std_logic_vector(1 downto 0);       -- Byte/halfword position for loads/stores
        alu_control  : in  std_logic_vector(5 downto 0);       -- ALU operation selector
        div_start    : in  std_logic;                          -- Start signal for division operation
        
        -- ==========================================
        -- Atomic operation control signals
        -- ==========================================
        amo_phase    : in  std_logic_vector(2 downto 0);       -- 000: normal, 001: AMO_READ, 010: AMO_COMPUTE, 011: AMO_WRITE, 100: SC fail, 101: SC success
        
        -- ==========================================
        -- Instruction and Memory Interface
        -- ==========================================
        instr        : in  std_logic_vector(31 downto 0);      -- Current instruction
        read_data    : in  std_logic_vector(31 downto 0);      -- Data from memory (for loads)
        write_data   : out std_logic_vector(31 downto 0);      -- Data to memory (for stores)
        
        -- ==========================================
        -- Datapath Outputs
        -- ==========================================
        Zero         : out std_logic;                          -- ALU zero flag
        pc_target    : out std_logic_vector(31 downto 0);      -- Target PC for branches/jumps
        ALU_result   : out std_logic_vector(31 downto 0);      -- ALU computation result
        alu_done     : out std_logic;                          -- ALU operation complete (for multi-cycle ops)
        
        -- ==========================================
        -- Stack Pointer Management for IRQ
        -- ==========================================
        sp_in        : in  std_logic_vector(31 downto 0);      -- New stack pointer value on irq_save
        sp_out       : out std_logic_vector(31 downto 0);      -- Current stack pointer value
        sp_write_en  : in  std_logic;       
        
        -- ==========================================
        -- CSR Interface
        -- ==========================================
        csr_valid   : in  std_logic;                          -- Valid CSR operation
        csr_rdata   : in  std_logic_vector(31 downto 0);      -- Data read from CSR
        csr_wdata   : out std_logic_vector(31 downto 0);      -- Data to write to CSR
        
        -- ==========================================
        -- Test Output - Stores pass /fail result of instruction tests
        -- ==========================================
        a0           : out std_logic_vector(31 downto 0)       -- Register x10 (a0) value for testing
    );
end datapath;

architecture struct of datapath is

    -- ==========================================
    -- Component Declarations
    -- ==========================================
    
    component regfile
        port (
            clk      : in  std_logic;
            resetn   : in  std_logic;
            we3      : in  std_logic;
            a1, a2, a3 : in  std_logic_vector(4 downto 0);
            wd3      : in  std_logic_vector(31 downto 0);
            rd1, rd2 : out std_logic_vector(31 downto 0);
            sp_in    : in  std_logic_vector(31 downto 0);
            sp_out   : out std_logic_vector(31 downto 0);
            sp_write : in  std_logic;
            a0       : out std_logic_vector(31 downto 0)
        );
    end component;

    component extend
        port (
            instr    : in  std_logic_vector(31 downto 7);
            imm_src  : in  std_logic_vector(2 downto 0);
            imm_ext  : out std_logic_vector(31 downto 0)
        );
    end component;

    component alu
        port (
            resetn      : in  std_logic;
            clk         : in  std_logic;
            a, b        : in  std_logic_vector(31 downto 0);
            alu_control : in  std_logic_vector(5 downto 0);
            div_start   : in  std_logic;
            ALU_result  : out std_logic_vector(31 downto 0);
            alu_done    : out std_logic;
            Zero        : out std_logic
        );
    end component;

    component loadext
        port (
            clk           : in  std_logic;
            funct3        : in  std_logic_vector(2 downto 0);
            mask          : in  std_logic_vector(1 downto 0);
            read_data     : in  std_logic_vector(31 downto 0);
            extended_data : out std_logic_vector(31 downto 0)
        );
    end component;

    component store_ext
        port (
            funct3        : in  std_logic_vector(2 downto 0);
            read_data     : in  std_logic_vector(31 downto 0);
            extended_data : out std_logic_vector(31 downto 0)
        );
    end component;

    -- ==========================================
    -- Internal Signal Declarations
    -- ==========================================
    
    -- Register file signals
    signal src_a              : std_logic_vector(31 downto 0);  -- Register file output A (rs1)
    signal write_data_reg_val : std_logic_vector(31 downto 0);  -- Register file output B (rs2)
    
    -- Immediate and ALU signals
    signal imm_ext            : std_logic_vector(31 downto 0);  -- Sign-extended immediate
    signal SrcB               : std_logic_vector(31 downto 0);  -- ALU input B (muxed)
    signal ALU_A              : std_logic_vector(31 downto 0);  -- ALU input A (muxed for AMO)
    signal ALU_B              : std_logic_vector(31 downto 0);  -- ALU input B (muxed for AMO)
    
    -- Result signals
    signal Result             : std_logic_vector(31 downto 0);  -- Final result to write back
    signal extended_data      : std_logic_vector(31 downto 0);  -- Load-extended data from memory
    signal ALU_result_internal: std_logic_vector(31 downto 0);  -- Internal ALU result
    
    -- PC calculation signals
    signal PC_targetbase      : std_logic_vector(31 downto 0);  -- Base address for PC target calculation
    
    -- AMO saved values
    signal amo_addr_reg       : std_logic_vector(31 downto 0);  -- Saved address for AMO
    signal amo_read_data_reg  : std_logic_vector(31 downto 0);  -- Saved read data for AMO

    signal rd_amo            : std_logic_vector(31 downto 0);  -- Data read during AMO operations

begin

    -- ==========================================
    -- AMO Data Registers
    -- ==========================================
    -- Save address and read data during AMO operations
    amo_reg_proc: process(clk, resetn)
    begin
        if resetn = '0' then
            amo_addr_reg <= (others => '0');
            amo_read_data_reg <= (others => '0');
        elsif rising_edge(clk) then
            -- Save address during AMO_READ phase
            if amo_phase = "001" then  -- AMO_READ
                amo_addr_reg <= src_a;  -- Save rs1 (address)
                amo_read_data_reg <= read_data;  -- Save memory data
            end if;

            rd_amo <= Result; -- clock cycle delayed version of Result for AMO COMPUTE
        end if;

    end process;

    -- ==========================================
    -- CSR Data - TODO: This can be better abstracted !
    -- ==========================================
    csr_wdata <= (31 downto 5 => '0') & instr(19 downto 15) when (csr_valid = '1' and funct3(2) = '1') else
                src_a;  -- rs1 value       
    

    -- ==========================================
    -- PC Target Calculation
    -- ==========================================
    -- For JALR: use register value as base
    -- For branches/JAL: use current PC as base
    PC_targetbase <= src_a when jalr = '1' else pc;
    
    -- Calculate target PC by adding immediate to base
    pc_target <= std_logic_vector(unsigned(PC_targetbase) + unsigned(imm_ext));

    -- ==========================================
    -- Register File Instance
    -- ==========================================
    -- 32 general-purpose registers with special stack pointer handling
    rf: regfile
        port map (
            clk      => clk,
            resetn   => resetn,
            we3      => reg_write,                    -- Write enable
            a1       => instr(19 downto 15),         -- rs1 address
            a2       => instr(24 downto 20),         -- rs2 address
            a3       => instr(11 downto 7),          -- rd address
            wd3      => Result,                       -- Write data
            rd1      => src_a,                       -- Read data 1 (rs1)
            rd2      => write_data_reg_val,          -- Read data 2 (rs2)
            sp_in    => sp_in,                       -- Stack pointer input for IRQ
            sp_out   => sp_out,                      -- Stack pointer output
            sp_write => sp_write_en,                 -- Stack pointer write enable
            a0       => a0                            -- Debug output (x10/a0)
        );
    
    -- ==========================================
    -- Immediate Extension Unit
    -- ==========================================
    -- Sign-extends immediate values based on instruction type
    ext: extend
        port map (
            instr   => instr(31 downto 7),           -- Instruction bits containing immediate
            imm_src => imm_src,                       -- Immediate type selector
            imm_ext => imm_ext                        -- Extended 32-bit immediate
        );

    -- ==========================================
    -- ALU Source B Multiplexer (before AMO mux)
    -- ==========================================
    -- Select between register value and immediate for ALU input B
    SrcB <= imm_ext when ALU_src = '1' else          -- Use immediate
            write_data_reg_val;                       -- Use register rs2

    -- ==========================================
    -- ALU Input Multiplexers for AMO Support
    -- ==========================================
    -- ALU input A selection based on AMO phase
    ALU_A <= src_a           when amo_phase = "000" else  -- Normal: use rs1
             src_a           when amo_phase = "001" else  -- AMO_READ: use rs1 for address
             rd_amo          when amo_phase = "010" else  -- AMO_COMPUTE: use saved read data
             amo_addr_reg    when amo_phase = "011" else  -- AMO_WRITE: use saved address
             src_a;

    -- ALU input B selection based on AMO phase
    ALU_B <= SrcB                     when amo_phase = "000" else  -- Normal: use SrcB (rs2 or immediate)
            x"00000001"               when amo_phase = "100" else  -- SC fail: write nonzero to rd
            (others => '0')           when amo_phase = "101" else  -- SC success: write 0 to rd
             SrcB;

    -- ==========================================
    -- Arithmetic Logic Unit Instance
    -- ==========================================
    -- Performs all arithmetic and logical operations including multiply/divide
    mainalu: alu
        port map (
            resetn      => resetn,
            clk         => clk,
            a           => ALU_A,                     -- Muxed for AMO operations
            b           => ALU_B,                     -- Muxed for AMO operations
            alu_control => alu_control,               -- Operation selector
            div_start   => div_start,                 -- Start division
            ALU_result  => ALU_result_internal,       -- Operation result
            alu_done    => alu_done,                  -- Multi-cycle operation complete
            Zero        => Zero                       -- Zero flag for branches
        );

    -- Output ALU result
    ALU_result <= ALU_result_internal;

    -- ==========================================
    -- Result Source Multiplexer
    -- ==========================================
    -- Select the final result to write back to register file
    -- For SC, need to write success (0) or failure (1) based on reservation check
    Result <= ALU_result_internal when result_Src = "000" else  -- ALU operation result
            extended_data       when result_Src = "001" else  -- Load from memory
            pc_plus_4           when result_Src = "010" else  -- Return address (JAL/JALR)
            pc_target           when result_Src = "011" else  -- PC + immediate (AUIPC)
            csr_rdata           when result_Src = "100" else  -- CSR read data
            (others => '0');    
    
    -- ==========================================
    -- Load Extension Unit Instance
    -- ==========================================
    -- Sign/zero extends loaded data based on load type (LB/LBU/LH/LHU/LW)
    loadextender: loadext
        port map(
            clk           => clk,
            funct3        => funct3,                 -- Load type (byte/halfword/word)
            mask          => mask,                    -- Byte position
            read_data     => read_data,              -- Raw data from memory
            extended_data => extended_data           -- Properly extended 32-bit value
        );

    -- ==========================================
    -- Store Extension Unit Instance
    -- ==========================================
    -- Formats store data based on store type (SB/SH/SW)
    storeextender: store_ext
        port map(
            funct3        => funct3,                 -- Store type (byte/halfword/word)
            read_data     => write_data_reg_val,     -- Data from rs2
            extended_data => write_data              -- Formatted data for memory
        );

end architecture struct;



