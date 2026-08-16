/* Smoke harness for the `vesta` core (RV32IMAC+Zb*, multicycle, single unified bus): the testbench drives only clk/resetn and observes a0/trap_flag/clk_cpu.
   The core decodes read_data combinationally in its EXECUTE cycle and has no fetch-wait state, so memory MUST return the word exactly one clock after the address; a behavioral RAM clocked in-domain gives that timing where a Python model would race it.
   The wiring mirrors a hart tile's core, address decoder and TCM, minus flash/XIP, power gates, the shared window and the SRAM macro.
   mask = data_addr(1:0), mem_ready tied '1' (single master), 1-cycle registered word reads, byte-masked writes on wen (active-LOW per lane, matching maindec's WEN encoding). */

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vesta_harness is
    port (
        clk       : in  std_logic;
        resetn    : in  std_logic;                     -- async, active-low
        a0        : out std_logic_vector(31 downto 0); -- core's x10 debug export
        trap_flag : out std_logic;
        clk_cpu   : out std_logic                      -- gated core clock (observed)
    );
end entity vesta_harness;

architecture sim of vesta_harness is

    -- core-to-RAM bus
    signal data_addr  : std_logic_vector(31 downto 0);
    signal wen        : std_logic_vector(3 downto 0);
    signal write_data : std_logic_vector(31 downto 0);
    signal read_data  : std_logic_vector(31 downto 0);
    signal mask       : std_logic_vector(1 downto 0);

    /* 64-word (256 B) behavioral RAM preloaded with the smoke program (PC_RST_VAL = 0):
         0x00: CAFEB537  lui  a0, 0xCAFEB      ; a0 = 0xCAFEB000
         0x04: 0BA50513  addi a0, a0, 0x0BA    ; a0 = 0xCAFEB0BA  (magic)
         0x08: 0000006F  jal  x0, 0            ; self-loop (halt) */
    constant DEPTH : natural := 64;
    type ram_t is array (0 to DEPTH-1) of std_logic_vector(31 downto 0);
    signal ram : ram_t := (
        0      => x"CAFEB537",
        1      => x"0BA50513",
        2      => x"0000006F",
        others => x"00000000"
    );
    signal rdata : std_logic_vector(31 downto 0) := (others => '0');

    function ram_idx(addr : std_logic_vector(31 downto 0)) return natural is
    begin
        -- word index; wrap into DEPTH so an out-of-range fetch is harmless
        return to_integer(unsigned(addr(7 downto 2)));
    end function;

begin

    -- Byte position within the word: the same data_addr(1:0) slice the address decoder drives.
    mask <= data_addr(1 downto 0);

    -- Synchronous 1-cycle-latency RAM in the free-running clk domain; with mem_ready tied '1' and no sleep, clk_cpu equals clk so core and RAM advance together.
    -- Writes are byte-masked, wen active-LOW per lane.
    ram_proc : process (clk)
        variable idx : natural;
    begin
        if rising_edge(clk) then
            idx := ram_idx(data_addr);
            if wen(0) = '0' then ram(idx)(7 downto 0)   <= write_data(7 downto 0);   end if;
            if wen(1) = '0' then ram(idx)(15 downto 8)  <= write_data(15 downto 8);  end if;
            if wen(2) = '0' then ram(idx)(23 downto 16) <= write_data(23 downto 16); end if;
            if wen(3) = '0' then ram(idx)(31 downto 24) <= write_data(31 downto 24); end if;
            rdata <= ram(idx);
        end if;
    end process;

    read_data <= rdata;

    -- Device under test: the core, default generics (RV32IMAC+Zb*, NUM_IRQS=16).
    dut : entity work.vesta
        port map (
            clk              => clk,
            resetn           => resetn,
            sleep            => '0',
            clk_cpu          => clk_cpu,
            hart_id          => (others => '0'),

            data_addr        => data_addr,
            wen              => wen,
            write_data       => write_data,
            read_data        => read_data,
            mask             => mask,
            mem_ready        => '1',

            lr_sc_bus        => open,
            sc_fail_ext      => '0',
            amo_lock         => open,

            irq_vector       => (others => '0'),
            irq_priority     => (others => '0'),
            irq_en           => (others => '0'),
            irq_recursion_en => '0',
            isr_ret          => open,

            trap_flag        => trap_flag,
            a0               => a0
        );

end architecture sim;
