/* Elaboration-only stand-ins for the compiled memory macros the MCU instantiates.
   The real behavioural models are hdl/common/sim/ARM_IP_ROM.vhd and hdl/common/sim/ARM_IP_RAM.vhd, which are vendor-IP-named and untracked, so a fresh clone does not have them and no hermetic test can name them.
   This file declares the same three macro entities with the same port lists, backed by a plain synchronous array, so //opensource_sim/mcu can prove that MCU.vhd elaborates and that its concurrent asserts hold.
   It is NOT a substitute for the real models in any flow that cares about memory CONTENTS: it holds no boot ROM image, and every macro here powers up all-zero. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

/* The one behaviour every macro below wraps, so the read timing cannot drift between the three depths.
   CEN and the WEN bits are active low and GWEN is the active-low global write enable, matching the compiled macros.
   A read latches the address on the enabled clock edge and Q answers it for the whole next cycle, which is the one-cycle registered read the bus fabric is timed against. */
entity mem_macro_stub is
    generic (
        AddressBits : integer range 1 to 32 := 11;
        Writable    : boolean := true
    );
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        WEN  : in  std_logic_vector(3 downto 0);
        A    : in  std_logic_vector(AddressBits - 1 downto 0);
        D    : in  std_logic_vector(31 downto 0);
        GWEN : in  std_logic;
        PGEN : in  std_logic
    );
end mem_macro_stub;

architecture stub of mem_macro_stub is
    type memory_t is array (0 to 2 ** AddressBits - 1) of std_logic_vector(31 downto 0);
    -- Zero is what a fabricated array reads out of an unwritten word, so an unloaded macro must not read as unknown.
    signal mem    : memory_t := (others => (others => '0'));
    signal adr_lat : std_logic_vector(AddressBits - 1 downto 0) := (others => '0');
begin
    process (CLK)
    begin
        if rising_edge(CLK) then
            if CEN = '0' then
                adr_lat <= A;
                if Writable and GWEN = '0' then
                    for b in 0 to 3 loop
                        if WEN(b) = '0' then
                            mem(to_integer(unsigned(A)))(8 * b + 7 downto 8 * b) <= D(8 * b + 7 downto 8 * b);
                        end if;
                    end loop;
                end if;
            end if;
        end if;
    end process;

    -- A power-gated macro reads back unknown, the same as the real models, so a read through a closed PGEN gate is visible rather than silently plausible.
    Q <= mem(to_integer(unsigned(adr_lat))) when PGEN = '0' else (others => 'X');
end stub;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 2048 x 32 boot ROM at rom0, A(10:0), read only.
entity rom2k_hvt_pg is
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        A    : in  std_logic_vector(10 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        PGEN : in  std_logic
    );
end rom2k_hvt_pg;

architecture stub of rom2k_hvt_pg is
begin
    rom: entity work.mem_macro_stub
        generic map (
            AddressBits => 11,
            Writable    => false
        )
        port map (
            Q    => Q,
            CLK  => CLK,
            CEN  => CEN,
            WEN  => "1111",
            A    => A,
            D    => (others => '0'),
            GWEN => '1',
            PGEN => PGEN
        );
end stub;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 16 KiB single-port RAM, A(11:0), used for the shared banks and the NPU staging RAM.
entity sram1p16k_hvt_pg is
    generic (
        INIT_FILE : string := ""
    );
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        WEN  : in  std_logic_vector(3 downto 0);
        A    : in  std_logic_vector(11 downto 0);
        D    : in  std_logic_vector(31 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        GWEN : in  std_logic;
        RETN : in  std_logic;
        PGEN : in  std_logic
    );
end sram1p16k_hvt_pg;

architecture stub of sram1p16k_hvt_pg is
begin
    /* The real macro preloads its array from an .rcf image when INIT_FILE is set.
       This stub cannot, so an instance that asks for one would run against silently empty memory.
       Refuse instead: a flow that needs real contents needs the real model, not this file. */
    assert INIT_FILE = ""
        report "sram1p16k_hvt_pg (elaboration stub): INIT_FILE is set, but this stub holds no image. "
             & "Use hdl/common/sim/ARM_IP_RAM.vhd for any flow whose result depends on memory contents."
        severity failure;

    ram: entity work.mem_macro_stub
        generic map (
            AddressBits => 12,
            Writable    => true
        )
        port map (
            Q    => Q,
            CLK  => CLK,
            CEN  => CEN,
            WEN  => WEN,
            A    => A,
            D    => D,
            GWEN => GWEN,
            PGEN => PGEN
        );
end stub;

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- The 8 KiB single-port RAM, A(10:0), the per-hart TCM macro hart_tile instantiates.
entity sram1p8k_hvt_pg is
    port (
        Q    : out std_logic_vector(31 downto 0);
        CLK  : in  std_logic;
        CEN  : in  std_logic;
        WEN  : in  std_logic_vector(3 downto 0);
        A    : in  std_logic_vector(10 downto 0);
        D    : in  std_logic_vector(31 downto 0);
        EMA  : in  std_logic_vector(2 downto 0);
        GWEN : in  std_logic;
        RETN : in  std_logic;
        PGEN : in  std_logic
    );
end sram1p8k_hvt_pg;

architecture stub of sram1p8k_hvt_pg is
begin
    ram: entity work.mem_macro_stub
        generic map (
            AddressBits => 11,
            Writable    => true
        )
        port map (
            Q    => Q,
            CLK  => CLK,
            CEN  => CEN,
            WEN  => WEN,
            A    => A,
            D    => D,
            GWEN => GWEN,
            PGEN => PGEN
        );
end stub;
