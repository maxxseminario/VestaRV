
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.constants.all;
use work.MemoryMap.all;

entity irq_handler is
    generic (
        NUM_IRQS   : integer := 32;    -- Maximum number of interrupt sources
        DATA_WIDTH : integer := 32     -- Data bus width
    );
    port (
        -- ==========================================
        -- System Interface
        -- ==========================================
        clk             : in  std_logic;
        resetn          : in  std_logic;
        
        -- ==========================================
        -- Interrupt Request Inputs
        -- ==========================================
        irq             : in  std_logic_vector(NUM_IRQS-1 downto 0);  -- Interrupt request lines
        irq_en          : in  std_logic_vector(NUM_IRQS-1 downto 0);  -- Interrupt enable mask
        irq_pri         : in  std_logic_vector(NUM_IRQS-1 downto 0);  -- Priority (1=high, 0=low)
        irq_recursion_en: in  std_logic;                              -- Enable interrupt recursion (1=enabled, 0=disabled)
        
        -- ==========================================
        -- CPU Interface
        -- ==========================================
        irq_active      : out std_logic;                              -- IRQ handler is active
        isr_ret         : in  std_logic;                              -- ISR return instruction executed
        irq_save        : out std_logic;                              -- Request CPU to save context
        irq_save_ack    : in  std_logic;                              -- CPU acknowledges context save
        irq_restore     : out std_logic;                              -- Request CPU to restore context
        irq_restore_ack : in  std_logic;                              -- CPU acknowledges context restore
        ivt_jump        : out std_logic;                              -- Jump to interrupt vector
        ivt_entry       : out std_logic_vector(31 downto 0)           -- Interrupt vector address
    );
end irq_handler;

architecture behavioral of irq_handler is
    
    -- ==========================================
    -- State Machine Type Definition
    -- ==========================================
    type irq_state_type is (
        IDLE,              -- No interrupt being serviced
        ISR_TRIGGERED,     -- Interrupt detected, initiate save
        WAIT_SAVE_ACK,     -- Wait for CPU to acknowledge context save
        JUMP_TO_IVT,       -- Jump to interrupt vector table entry
        WAIT_EOI,          -- Wait for end of interrupt (ISR return)
        CHECK_NESTED,      -- Check for higher priority interrupts
        IRQ_REST,          -- Begin context restore
        WAIT_RESTORE_ACK,  -- Wait for CPU to acknowledge restore
        DECIDE_NEXT,       -- Determine next action after restore
        DIRECT_JUMP        -- Direct jump to next IRQ (unused in current logic)
    );
    
    -- ==========================================
    -- State Machine Signals
    -- ==========================================
    signal prev_state    : irq_state_type;
    signal current_state : irq_state_type;
    signal next_state    : irq_state_type;
    
    -- ==========================================
    -- IRQ Management Signals
    -- ==========================================
    -- Registered versions to break combinational loops
    signal pending_irqs_reg          : std_logic_vector(NUM_IRQS-1 downto 0);
    signal highest_priority_irq_reg  : integer range 0 to NUM_IRQS;
    signal latched_irq               : integer range 0 to NUM_IRQS;  -- Currently serviced IRQ
    signal irq_found                 : std_logic;
    signal irq_found_reg             : std_logic;
    
    -- Constants
    constant MAX_IRQ_VALUE : integer := NUM_IRQS;
    
    -- ==========================================
    -- Context and Nesting Management
    -- ==========================================
    signal context_saved    : std_logic;                             -- Context has been saved
    signal context_restored : std_logic;                             -- Context has been restored
    signal nesting_count    : integer range 0 to NUM_IRQS;          -- Interrupt nesting depth
    signal irqs_in_service  : std_logic_vector(NUM_IRQS-1 downto 0); -- Track active ISRs
    
    -- ==========================================
    -- Non-recursive mode management
    -- ==========================================
    signal single_isr_active : std_logic;                            -- Single ISR active in non-recursive mode
    
    -- ==========================================
    -- Combinational Signals
    -- ==========================================
    signal pending_irqs_comb         : std_logic_vector(NUM_IRQS-1 downto 0);
    signal pending_irqs_high_pri     : std_logic_vector(NUM_IRQS-1 downto 0);
    signal highest_priority_irq_comb : integer range 0 to NUM_IRQS;
    signal higher_priority_pending   : std_logic;
    signal any_in_service            : std_logic;
    
    -- ==========================================
    -- Helper Functions
    -- ==========================================
    
    -- Convert integer to std_logic_vector
    function int_to_slv(val : integer; width : integer) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(val, width));
    end function;
    
    -- Check if IRQ A has higher priority than IRQ B
    -- Returns true if A has higher priority (considers priority bit and index)
    function has_higher_priority(irq_a : integer; irq_b : integer; 
                                 pri_vec : std_logic_vector) return boolean is
    begin
        if irq_a >= NUM_IRQS or irq_b >= NUM_IRQS then
            return false;
        end if;
        
        -- Check priority bits first
        if pri_vec(irq_a) = pri_vec(irq_b) then
            -- Same priority level: lower index = higher priority
            return irq_a < irq_b;
        else
            -- High priority (1) beats low priority (0)
            return pri_vec(irq_a) = '1' and pri_vec(irq_b) = '0';
        end if;
    end function;
    
    -- Count number of '1's in a vector
    function count_ones(vec : std_logic_vector) return integer is
        variable count : integer := 0;
    begin
        for i in vec'range loop
            if vec(i) = '1' then
                count := count + 1;
            end if;
        end loop;
        return count;
    end function;

begin
    
    -- ==========================================
    -- Pending IRQ Detection 
    -- ==========================================
    -- Mask out IRQs based on recursion mode
    process(irq, irq_en, irqs_in_service, irq_recursion_en, single_isr_active)
    begin
        if irq_recursion_en = '1' then
            -- Recursive mode: original behavior - mask out IRQs that are already being serviced
            pending_irqs_comb <= irq and irq_en and (not irqs_in_service);
        else
            -- Non-recursive mode: mask all IRQs if any ISR is active
            if single_isr_active = '1' then
                pending_irqs_comb <= (others => '0');
            else
                -- No ISR active, allow all enabled IRQs
                pending_irqs_comb <= irq and irq_en;
            end if;
        end if;
    end process;
    
    -- Filter high priority pending IRQs
    pending_irqs_high_pri <= pending_irqs_comb and irq_pri;
    
    -- Check if any interrupts are currently in service
    any_in_service <= '0' when irqs_in_service = (irqs_in_service'range => '0') else '1';

    -- ==========================================
    -- Priority Encoder 
    -- ==========================================
    -- Finds highest priority pending interrupt and checks for nesting
    priority_encoder: process(pending_irqs_high_pri, pending_irqs_comb, irq_pri, 
                             latched_irq, current_state, irqs_in_service, 
                             irq_recursion_en)
        variable temp_irq     : integer range 0 to NUM_IRQS;
        variable found        : boolean;
        variable is_servicing : boolean;
    begin
        temp_irq := NUM_IRQS;  -- Default: no IRQ
        found := false;
        higher_priority_pending <= '0';
        
        -- Check if we're currently servicing an interrupt
        is_servicing := (current_state = WAIT_EOI or current_state = CHECK_NESTED) 
                       and latched_irq < NUM_IRQS;
        
        -- First pass: Find highest priority pending interrupt
        -- Priority 1: Check high priority interrupts (pri bit = 1)
        for i in 0 to NUM_IRQS-1 loop
            if pending_irqs_comb(i) = '1' and irq_pri(i) = '1' and not found then
                temp_irq := i;
                found := true;
            end if;
        end loop;
        
        -- Priority 2: Check normal priority interrupts if no high priority found
        if not found then
            for i in 0 to NUM_IRQS-1 loop
                if pending_irqs_comb(i) = '1' and not found then
                    temp_irq := i;
                    found := true;
                end if;
            end loop;
        end if;
        
        -- Second pass: Check if found IRQ can preempt current ISR
        if found and is_servicing then
            if irq_recursion_en = '1' then
                -- Recursive mode: check for higher priority
                if has_higher_priority(temp_irq, latched_irq, irq_pri) then
                    higher_priority_pending <= '1';
                else
                    -- Don't report lower/equal priority IRQs while servicing
                    if not is_servicing then
                        null;  -- Keep the found interrupt
                    else
                        temp_irq := NUM_IRQS;  -- Ignore lower/equal priority
                        found := false;
                    end if;
                end if;
            else
                -- Non-recursive mode: no preemption allowed
                temp_irq := NUM_IRQS;
                found := false;
            end if;
        end if;
        
        highest_priority_irq_comb <= temp_irq;
    end process;

    -- IRQ found indicator
    irq_found <= '0' when highest_priority_irq_comb = MAX_IRQ_VALUE else '1';
    
    -- ==========================================
    -- Main State Machine Sequential Process
    -- ==========================================
    sm_proc: process(clk, resetn)
    begin
        if resetn = '0' then
            current_state <= IDLE;
            pending_irqs_reg <= (others => '0');
            highest_priority_irq_reg <= NUM_IRQS;
            latched_irq <= NUM_IRQS;
            irq_found_reg <= '0';
            context_saved <= '0';    
            context_restored <= '0';       
            nesting_count <= 0;
            irqs_in_service <= (others => '0');
            single_isr_active <= '0';
            
        elsif rising_edge(clk) then
            -- Latch combinational signals
            pending_irqs_reg <= pending_irqs_comb;
            highest_priority_irq_reg <= highest_priority_irq_comb;
            irq_found_reg <= irq_found;  
            
            -- Update state machine
            prev_state <= current_state;
            current_state <= next_state;
            
            -- State-specific actions
            case current_state is
                when IDLE =>
                    -- Starting new interrupt service
                    if next_state = ISR_TRIGGERED then
                        latched_irq <= highest_priority_irq_comb;
                        if highest_priority_irq_comb < NUM_IRQS then
                            irqs_in_service(highest_priority_irq_comb) <= '1';
                        end if;
                        context_saved <= '0';
                        nesting_count <= 1;
                        single_isr_active <= '1';  -- Mark ISR as active
                    end if;
                    
                when ISR_TRIGGERED =>
                    -- Mark context as saved when acknowledged
                    if irq_save_ack = '1' then
                        context_saved <= '1';
                    end if;
                    
                when WAIT_SAVE_ACK =>
                    -- Wait for save acknowledgment
                    if irq_save_ack = '1' then
                        context_saved <= '1';
                    end if;
                    
                when JUMP_TO_IVT =>
                    -- Jump cycle - no special action needed
                    null;
                    
                when CHECK_NESTED =>
                    -- Handle nested interrupt (only if recursion enabled)
                    if irq_recursion_en = '1' and irq_found_reg = '1' and highest_priority_irq_reg < NUM_IRQS then
                        latched_irq <= highest_priority_irq_reg;
                        irqs_in_service(highest_priority_irq_reg) <= '1';
                        nesting_count <= nesting_count + 1;
                        context_saved <= '0';  -- Need new context save
                    end if;
                    
                when WAIT_EOI =>
                    -- Waiting for ISR to complete
                    null;

                when IRQ_REST =>
                    -- Begin restore process
                    context_restored <= '0';
                    
                when WAIT_RESTORE_ACK =>
                    -- Complete restore process
                    if irq_restore_ack = '1' then
                        context_restored <= '1';
                        
                        -- Decrement nesting count
                        if nesting_count > 0 then
                            nesting_count <= nesting_count - 1;
                        end if;
                    end if;
                    
                when DECIDE_NEXT =>
                    -- Determine next action after restore
                    if any_in_service = '1' then
                        -- Returning to previous nested ISR (only possible in recursive mode)
                        latched_irq <= NUM_IRQS;
                    elsif irq_found_reg = '1' and highest_priority_irq_reg < NUM_IRQS then
                        -- New interrupt to service
                        latched_irq <= highest_priority_irq_reg;
                        irqs_in_service(highest_priority_irq_reg) <= '1';
                        nesting_count <= 1;
                        context_saved <= '0';
                        -- Keep single_isr_active set if in non-recursive mode
                    else
                        -- All interrupts complete
                        latched_irq <= NUM_IRQS;
                        context_saved <= '0';
                        irqs_in_service <= (others => '0');
                        single_isr_active <= '0';  -- Clear ISR active flag
                    end if;
                    
                when DIRECT_JUMP =>  
                    -- Direct jump to next IRQ (currently unused path)
                    if highest_priority_irq_reg < NUM_IRQS then
                        latched_irq <= highest_priority_irq_reg;
                        irqs_in_service(highest_priority_irq_reg) <= '1';
                    end if;
                    
                when others =>
                    null;
            end case;
            
            -- Handle End-Of-Interrupt
            if current_state = WAIT_EOI and isr_ret = '1' then
                -- Clear the in-service flag for completed IRQ
                if latched_irq < NUM_IRQS then
                    irqs_in_service(latched_irq) <= '0';
                end if;
                
                -- In non-recursive mode, clear active flag only when no more interrupts
                -- This will be properly handled in DECIDE_NEXT state
            end if;
        end if;
    end process;

    -- ==========================================
    -- Next State Logic 
    -- ==========================================
    next_state_logic: process(current_state, irq_found_reg, isr_ret, irq_save_ack, 
                             context_saved, highest_priority_irq_reg, latched_irq,
                             nesting_count, irqs_in_service, higher_priority_pending,
                             pending_irqs_reg, irq_restore_ack, context_restored,
                             any_in_service, irq_recursion_en)
        variable any_irq_pending  : boolean;
        variable in_service_count : integer;
    begin
        next_state <= current_state;  -- Default: stay in current state
        
        -- Check for any unserviced pending IRQs
        any_irq_pending := false;
        for i in 0 to NUM_IRQS-1 loop
            if pending_irqs_reg(i) = '1' and irqs_in_service(i) = '0' then
                any_irq_pending := true;
            end if;
        end loop;
        
        -- Count active interrupt services
        in_service_count := count_ones(irqs_in_service);
        
        case current_state is
            when IDLE =>
                -- Wait for interrupt request
                if irq_found_reg = '1' then
                    next_state <= ISR_TRIGGERED;
                end if;

            when ISR_TRIGGERED =>
                -- Initiate context save
                if irq_save_ack = '1' then
                    next_state <= JUMP_TO_IVT;
                elsif context_saved = '0' then
                    next_state <= WAIT_SAVE_ACK;
                else
                    next_state <= JUMP_TO_IVT;
                end if;
                
            when WAIT_SAVE_ACK =>
                -- Wait for CPU to save context
                if irq_save_ack = '1' then
                    next_state <= JUMP_TO_IVT;
                end if;
                
            when JUMP_TO_IVT =>
                -- Jump to interrupt vector
                next_state <= WAIT_EOI;
                
            when CHECK_NESTED =>
                -- Handle nested interrupts (only if recursion enabled)
                if irq_recursion_en = '1' and higher_priority_pending = '1' and irq_found_reg = '1' then
                    next_state <= ISR_TRIGGERED;
                else
                    next_state <= WAIT_EOI;
                end if;

            when WAIT_EOI =>
                -- Wait for ISR completion or preemption
                if irq_recursion_en = '1' and higher_priority_pending = '1' and irq_found_reg = '1' then
                    -- Higher priority interrupt arrived (recursive mode only)
                    next_state <= CHECK_NESTED;
                elsif isr_ret = '1' then
                    -- ISR completed
                    next_state <= IRQ_REST;
                end if;
                
            when IRQ_REST =>
                -- Initiate context restore
                next_state <= WAIT_RESTORE_ACK;
                
            when WAIT_RESTORE_ACK =>
                -- Wait for restore acknowledgment
                if irq_restore_ack = '1' then
                    next_state <= DECIDE_NEXT;
                else
                    next_state <= WAIT_RESTORE_ACK;
                end if;
                
            when DECIDE_NEXT =>
                -- Determine next action - same logic for both modes
                if in_service_count > 1 then
                    -- Return to previous nested ISR (only happens in recursive mode)
                    next_state <= WAIT_EOI;
                elsif any_irq_pending then
                    -- Service next interrupt (return to IDLE to allow one instruction)
                    next_state <= IDLE;
                else
                    -- All interrupts complete
                    next_state <= IDLE;
                end if;
                
            when DIRECT_JUMP =>  
                -- Direct jump path (currently unused)
                next_state <= JUMP_TO_IVT;
                
            when others =>
                next_state <= IDLE;
        end case;
    end process;

    -- ==========================================
    -- Output Signal Generation
    -- ==========================================
    
    -- Request context save
    irq_save <= '1' when ((current_state = ISR_TRIGGERED or current_state = WAIT_SAVE_ACK) 
                          and context_saved = '0') else '0';
    
    -- Request context restore
    irq_restore <= '1' when (current_state = IRQ_REST or 
                            (current_state = WAIT_RESTORE_ACK and context_restored = '0')) else '0';
    
    -- Signal jump to interrupt vector
    ivt_jump <= '1' when (current_state = JUMP_TO_IVT or 
                         current_state = DIRECT_JUMP) else '0';
    
    -- Calculate interrupt vector address
    ivt_entry <= int_to_slv(IVT_BASE_ADDR + (latched_irq * 4), 32) 
                when latched_irq < NUM_IRQS else (others => '0');
    
    -- IRQ handler active indicator
    irq_active <= '0' when (current_state = IDLE) else '1';

end behavioral;