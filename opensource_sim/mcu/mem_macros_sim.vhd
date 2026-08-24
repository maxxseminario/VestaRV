/* Tracked behavioural stand-ins for the compiled memory macros the MCU instantiates.
   The vendor-named models are hdl/common/sim/ARM_IP_ROM.vhd and hdl/common/sim/ARM_IP_RAM.vhd, which the .gitignore `*ARM*` pattern hides, so a fresh clone does not have them and no hermetic test can name them.
   This file declares the same three macro entities with the same port lists, backed by a plain synchronous array, so the open-source tier can elaborate and run hdl/common/MCU.vhd.
   The boot ROM here is NOT empty: rom2k_hvt_pg loads the image whose path work.rom_image_pkg carries, which is how a hermetic test reaches the real mask-ROM contents without an absolute path.
   The RAM macros hold no image and refuse an INIT_FILE rather than run silently empty, because nothing in the open-source tier needs a preloaded RAM yet. */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.TEXTIO.ALL;

/* The one behaviour every macro below wraps, so the read timing cannot drift between the three depths.
   CEN and the WEN bits are active low and GWEN is the active-low global write enable, matching the compiled macros.
   A read latches the address on the enabled clock edge and Q answers it for the whole next cycle, which is the one-cycle registered read the bus fabric is timed against. */
entity mem_macro_sim is
    generic (
        AddressBits : integer range 1 to 32 := 11;
        Writable    : boolean := true;
        -- Path to an .rcf code file, one 32-bit binary word per line, or the null string for a macro that powers up all-zero.
        InitFile    : string := ""
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
end mem_macro_sim;

architecture behavioural of mem_macro_sim is
    type memory_t is array (0 to 2 ** AddressBits - 1) of std_logic_vector(31 downto 0);
begin
    /* The array, the code-file load and the read port are ONE process because the array is a variable rather than a signal.
       A second process assigning the same signal would be a second driver on it, and std_logic resolution turns a loaded '1' against an idle driver's '0' into 'X'.
       That is not hypothetical: this file had exactly that shape for one run, and every set bit of the boot ROM read back as X while the elaboration gate stayed green because an all-zero array resolves against an all-zero driver perfectly well. */
    macro: process
        -- Zero is what a fabricated array reads out of an unwritten word, so an unloaded macro must not read as unknown.
        variable mem        : memory_t := (others => (others => '0'));
        variable adr_lat    : natural := 0;
        file     image_file : TEXT;
        variable open_status : FILE_OPEN_STATUS;
        variable image_line : LINE;
        variable word_bits  : BIT_VECTOR(31 downto 0);
        variable ok         : boolean;
        variable i          : integer;

        /* Drives the read port from the currently latched address.
           A power-gated macro reads back unknown, the same as the vendor models, so a read through a closed PGEN gate is visible rather than silently plausible. */
        procedure drive_q is
        begin
            if PGEN = '0' then
                Q <= mem(adr_lat);
            else
                Q <= (others => 'X');
            end if;
        end procedure;
    begin
        /* Loads the code file once at time zero, the same one-shot the vendor model uses.
           An empty InitFile is the normal case for a writable macro and leaves the array at its all-zero power-up value.
           A named file that will not open is a hard failure: a test whose verdict depends on ROM contents must never run against silent zeros. */
        if InitFile /= "" then
            file_open(open_status, image_file, InitFile, READ_MODE);
            assert open_status = OPEN_OK
                report "mem_macro_sim: cannot open code file """ & InitFile & """ (" & FILE_OPEN_STATUS'image(open_status) & ")."
                     & " A hermetic run reaches its image through runfiles; check the data dependency on the image target."
                severity failure;

            i := 0;
            while not endfile(image_file) loop
                /* Stop at the end of the array instead of indexing past it.
                   The code file and AddressBits are set independently, by the firmware build and by the entity the MCU instantiates, so a file deeper than the macro is a real possibility.
                   Reporting it here names the mismatch; running off the end would only produce an index-out-of-range abort with nothing to read. */
                assert i <= 2 ** AddressBits - 1
                    report "mem_macro_sim: the code file """ & InitFile & """ has more than "
                         & integer'image(2 ** AddressBits) & " lines, which is deeper than this "
                         & integer'image(AddressBits) & "-bit macro. Rebuild the image at the macro's depth."
                    severity failure;
                exit when i > 2 ** AddressBits - 1;

                readline(image_file, image_line);
                read(image_line, word_bits, ok);
                assert ok
                    report "mem_macro_sim: line " & integer'image(i + 1) & " of """ & InitFile
                         & """ is not a 32-bit binary word."
                    severity failure;
                mem(i) := To_StdLogicVector(word_bits);
                i := i + 1;
            end loop;
            file_close(image_file);
        end if;

        drive_q;

        loop
            wait on CLK, PGEN;
            if rising_edge(CLK) and CEN = '0' then
                if Writable and GWEN = '0' then
                    for b in 0 to 3 loop
                        if WEN(b) = '0' then
                            mem(to_integer(unsigned(A)))(8 * b + 7 downto 8 * b) := D(8 * b + 7 downto 8 * b);
                        end if;
                    end loop;
                end if;
                adr_lat := to_integer(unsigned(A));
            end if;
            drive_q;
        end loop;
    end process macro;
end behavioural;

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

library work;
use work.rom_image_pkg.all;

/* The image path arrives through a package constant rather than a generic, because MCU.vhd instantiates this macro with no generic map and a testbench cannot reach past it.
   rom_image_pkg is GENERATED per consumer by the rom_image_pkg() macro in opensource_sim/mcu/defs.bzl, which writes the runfiles-relative path of the image target it is given.
   A consumer that passes no image gets the null string and this ROM powers up all-zero, which is all an elaboration gate needs. */
architecture behavioural of rom2k_hvt_pg is
begin
    rom: entity work.mem_macro_sim
        generic map (
            AddressBits => 11,
            Writable    => false,
            InitFile    => ROM_IMAGE_PATH
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
end behavioural;

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

architecture behavioural of sram1p16k_hvt_pg is
begin
    /* The vendor macro preloads its array from an .rcf image when INIT_FILE is set, and nothing in the open-source tier does that yet.
       Refusing here keeps the untested path out of the estate: a flow that needs preloaded RAM must wire the path in and prove it, not discover empty memory at runtime.
       The loader itself is present in mem_macro_sim, so honouring INIT_FILE is a one-line change on the day a flow needs it. */
    assert INIT_FILE = ""
        report "sram1p16k_hvt_pg (opensource_sim model): INIT_FILE is set, but this model is not wired to load one. "
             & "Use hdl/common/sim/ARM_IP_RAM.vhd, or pass the path through to mem_macro_sim's InitFile and prove it."
        severity failure;

    ram: entity work.mem_macro_sim
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
end behavioural;

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

architecture behavioural of sram1p8k_hvt_pg is
begin
    ram: entity work.mem_macro_sim
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
end behavioural;
