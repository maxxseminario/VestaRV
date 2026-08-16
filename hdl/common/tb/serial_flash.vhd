library ieee;
use ieee.std_logic_1164.all;
use std.standard.all;
use std.textio.all;
use std.textio;
use ieee.numeric_std.all;

entity serial_flash is
	generic
	(
		ProgramAddress			: natural;
		RamSizeBytes			: natural;
		SwapBytesIn32BitWord	: boolean
	);
	port
	( 
		CSb		: in	std_logic;	-- Chip select, active low
		SPCLK	: in	std_logic;
		MOSI	: in	std_logic;
		MISO	: out	std_logic;

		-- For Testing Only
		mem_reset 	: in 	std_logic; 
		awake 		: out 	std_logic; -- For testing only, indicates the flash is awake
		RAM_FILE_PATH : in string(1 to 29) := "../rcf/xxxrv32ui-p-simple.rcf"
	);
end serial_flash;

architecture behavioral of serial_flash is

	-- Automatically offset the code from the RCF file to match the MCU memory map.
	-- In the real hardware the linker script does this.

	constant RamSizeWords : natural := RamSizeBytes / 4;

	type memoryt is array (0 to RamSizeWords - 1) of std_logic_vector(31 downto 0);
	signal mem : memoryt;
	type stateT is (Idle, RXAdd1, RXAdd2, RXAdd3, Reading, ReadStatus);
	signal state : stateT;
	signal bitcount : natural range 0 to 8;
	signal RXSr : std_logic_vector(7 downto 0);
	signal TXSr : std_logic_vector(7 downto 0);
	-- Power-state model of the AT45DB021E (DataFlash family): the device starts in deep power-down, so boot code must issue a correctly framed ABh wake-up.
	-- ABh (resume) and B9h (deep power-down) take effect only on the RISING edge of CSb after the opcode is shifted in, and the tRDPD wake-up timer starts at that CSb edge.
	signal PowerOn : boolean := false;
	signal WakePending : boolean := false;
	signal SleepPending : boolean := false;
	signal ReadyBit : std_logic := '0';
begin

	-- The rcf image is re-read on every flash reset: a simulation convenience, not physical-chip behaviour.
	-- It expects the flash contents as binary ASCII strings, one 32-bit word per line.
	read_file: process(mem_reset)
    file ROM_File : text;
    variable ROM_File_line : LINE;
    variable i : natural;
    variable GOOD : boolean;
    variable data : BIT_VECTOR(31 downto 0);
    variable STD_Data : std_logic_vector(31 downto 0);
    variable file_status : FILE_OPEN_STATUS;
begin
    if rising_edge(mem_reset) then
        -- Open the file specified by RAM_FILE_PATH
        file_open(file_status, ROM_File, RAM_FILE_PATH, READ_MODE);
		-- report "Flash Memory opened file: " & RAM_FILE_PATH severity warning;
        
        if file_status = OPEN_OK then
            i := 0;
            -- Clear the memory array before loading new data
            for j in 0 to RamSizeWords - 1 loop
                mem(j) <= (others => '0'); -- Optional: Clear memory to avoid stale data
            end loop;

            -- Read the file line by line
            while not endfile(ROM_File) loop
                readline(ROM_File, ROM_File_line);
                read(ROM_File_line, data, GOOD);
                if GOOD then
                    for j in 31 downto 0 loop
                        if data(j) = '1' then
                            STD_Data(j) := '1';
                        else
                            STD_Data(j) := '0';
                        end if;
                    end loop;
                    if i < RamSizeWords then
                        if SwapBytesIn32BitWord then
                            mem(i) <= STD_Data(7 downto 0) & STD_Data(15 downto 8) & 
                                     STD_Data(23 downto 16) & STD_Data(31 downto 24);
                        else
                            mem(i) <= STD_Data;
                        end if;
                    end if;
                    i := i + 1;
                end if;
            end loop;
            -- Close the file after reading
			-- report "Flash Memory Updated With: " & RAM_FILE_PATH severity warning;
            file_close(ROM_File);
        else
            -- report "Failed to open file: " & RAM_FILE_PATH severity warning;
        end if;
    end if;
end process read_file;

	-- SPI slave shift engine: samples MOSI on the rising SPCLK edge, drives MISO on the falling edge, and runs the opcode/address/read state machine.
	process(CSb, SPCLK)
		-- The memory map address.
		variable Address : std_logic_vector(23 downto 0) := (others=>'0');
		-- The memory map address shifted so the RAM data begins at address 0.
		variable AddressInt : natural;
		variable AddressOffset : natural;
		variable AddressShifted : natural;
	begin
		if CSb = '0' then
			if rising_edge(SPCLK) then
				bitcount <= bitcount + 1;
				RXSr <= RXSr(6 downto 0) & MOSI;

				-- Once a power-mode opcode has been latched, the real device ignores everything else on the bus until CSb is deasserted.
				if state = Idle and bitcount = 7 and (WakePending or SleepPending) then
					if RXSr(6 downto 0) & MOSI = X"03" or RXSr(6 downto 0) & MOSI = X"0B"
							or RXSr(6 downto 0) & MOSI = X"D7" then
						report "serial_flash: opcode ignored - an ABh/B9h power-mode command is still " &
							"pending in this CSb frame. The host must DEASSERT CSb after ABh/B9h for it " &
							"to take effect (this is the myshkin-2025-11 boot ROM bug)."
							severity warning;
					end if;
				elsif state = Idle and bitcount = 7 then
					if RXSr(6 downto 0) & MOSI = X"AB" then
						-- Resume from Deep Power-Down, taking effect only after CSb deassertion (see the CSb = '1' branch below).
						WakePending <= true;
					elsif RXSr(6 downto 0) & MOSI = X"B9" then
						-- Deep Power-Down. Also deferred until CSb deassertion.
						SleepPending <= true;
					elsif RXSr(6 downto 0) & MOSI = X"D7" and PowerOn then
						-- Status register read command (D7h).
						state <= ReadStatus;
					elsif (RXSr(6 downto 0) & MOSI = X"03" or RXSr(6 downto 0) & MOSI = X"0B"
							or RXSr(6 downto 0) & MOSI = X"D7") and not PowerOn then
						report "serial_flash: read/status opcode ignored - device is in deep power-down. " &
							"The ABh wake-up takes effect only after CSb is deasserted (tRDPD)."
							severity warning;
					end if;
				end if;
			elsif falling_edge(SPCLK) then
				TXSr <= TXSr(6 downto 0) & '0';
				if bitcount = 8 then
					bitcount <= 0;
					if PowerOn and ReadyBit = '1' then
						if state = Idle then
							if (RXSr = X"03") or (RXSr = X"0B") then	-- Read Low Frequency or Read High Frequency command
								state <= RXAdd1;
							end if;
						elsif state = RXAdd1 then
							state <= RXAdd2;
							Address(23 downto 16) := RXSr;
						elsif state = RXAdd2 then
							state <= RXAdd3;
							Address(15 downto 8) := RXSr;
						elsif state = RXAdd3 then
							if state = RXAdd3 then
								Address(7 downto 0) := RXSr;
							end if;
							state <= Reading;
						elsif state = Reading then
							AddressInt := to_integer(unsigned(Address(Address'high downto 2)));
							--AddressOffset := to_integer(unsigned(ProgramAddress(ProgramAddress'high downto 2)));
							AddressOffset := ProgramAddress / 4;
							AddressShifted := AddressInt - AddressOffset;
							if AddressShifted < RamSizeWords then
								case Address(1 downto 0) is
									when "00" =>
										TXSr <= mem(AddressShifted)(7 downto 0);
									when "01" =>
										TXSr <= mem(AddressShifted)(15 downto 8);
									when "10" =>
										TXSr <= mem(AddressShifted)(23 downto 16);
									when "11" =>
										TXSr <= mem(AddressShifted)(31 downto 24);
									when others =>
										null;
								end case;
							else
								TXSr <= (others => 'U');
							end if;
							Address := std_logic_vector(unsigned(Address) + 1);
						elsif state = ReadStatus then
							TXSr <= (7 => ReadyBit, others => '0');
						end if;
					else
						TXSr <= (others => '0');
					end if;
				end if;
			end if;
		else
			-- CSb deasserted: a pending power-mode opcode takes effect NOW.
			-- For a wake-up this is the point where the real part starts its tRDPD timer, and the ReadyBit process below adds that delay.
			if WakePending then
				PowerOn <= true;
				WakePending <= false;
			elsif SleepPending then
				PowerOn <= false;
				SleepPending <= false;
			end if;
			state <= Idle;
			TXSr <= "00000000";
			bitcount <= 0;
		end if;
	end process;
	MISO <= TXSr(7);   -- MISO is the top bit of the transmit shift register

	-- tRDPD wake-up timer: the device only answers reads once this delay has elapsed after the resume took effect.
	process
	begin
		ReadyBit <= '0';
		wait until PowerOn = true;
		wait for 35 us;	-- AT45DB021E tRDPD max: exit-deep-power-down time, measured from CSb deassertion
		if PowerOn = true then
			ReadyBit <= '1';
			wait until PowerOn = false;
		end if;
	end process;

	awake <= ReadyBit; -- For testing only, indicates the flash is awake

end behavioral;

