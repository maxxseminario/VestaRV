library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
library work;
use work.Constants.all;

package TestbenchLibrary is

	-- Reads from memory at the specified address
	procedure ReadMemory
	(
		constant WordAddress: in	natural;
		variable rdata_out	: out	word;
		signal	Clk			: in	sl;
		signal	MAB			: out	word;
		signal	rdata		: in	word;
		signal	ClkMem		: out	sl;
		signal	EnMem		: out	sl;
		signal	WEn			: out	slv(3 downto 0)
	);

	-- Writes to memory at the specified address
	procedure WriteMemory
	(
		constant WordAddress: in	natural;
		constant wdata_in	: in	word;
		signal	Clk			: in	sl;
		signal	MAB			: out	word;
		signal	wdata		: out	word;
		signal	ClkMem		: out	sl;
		signal	EnMem		: out	sl;
		signal	WEn			: out	slv(3 downto 0)
	);

	-- Delays for a certain number of rising edges of a clock
	procedure WaitForRisingEdges
	(
		constant	Edges	: in	natural;
		signal		Clk		: in	sl
	);
	
	-- Waits for the MCU UART TX line to send a character and returns it
	procedure UartReceiveCharFromTX
	(
		constant baudratePeriod	: in	time;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXChar			: out	character
	);

	-- Sends a character to the MCU UART RX line
	procedure UartSendCharToRX
	(
		constant baudratePeriod	: in	time;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXChar			: in	character
	);

	-- Waits for the MCU UART TX line to send a string of a certain length and returns it
	procedure UartReceiveStringFromTX
	(
		constant baudratePeriod	: in	time;
		constant NumChars		: in	natural;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXStr			: out	string
	);

	-- Waits for the MCU UART TX line to send a string that terminates in a certain char and returns it
	procedure UartReceiveStringFromTXUntil
	(
		constant baudratePeriod	: in	time;
		constant UntilChar		: in	character;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXStr			: out	string
	);

	-- Sends a string of a certain length to the MCU UART RX line
	procedure UartSendStrNToRX
	(
		constant baudratePeriod	: in	time;
		constant NumChars		: in	natural;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXStr			: in	string
	);

	-- Sends a whole string to the MCU UART RX line
	procedure UartSendStrToRX
	(
		constant baudratePeriod	: in	time;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXStr			: in	string
	);

end TestbenchLibrary;

package body TestbenchLibrary is

	procedure ReadMemory
	(
		constant WordAddress: in	natural;
		variable rdata_out	: out	word;
		signal	Clk			: in	sl;
		signal	MAB			: out	word;
		signal	rdata		: in	word;
		signal	ClkMem		: out	sl;
		signal	EnMem		: out	sl;
		signal	WEn			: out	slv(3 downto 0)
	) is
	begin
		-- Assumes the procedure is initiated just after the rising edge of Clk
		wait until Clk = '1';

		-- Set up the address bus and enable the memory
		MAB(31 downto 2) <= int2slv(WordAddress, 30);
		MAB(1 downto 0) <= "00";
		WEn <= (others => mem_deassert);
		EnMem <= mem_assert;
		wait until rising_edge(Clk);
		
		-- Clock in the address
		ClkMem <= '1';
		wait until falling_edge(Clk);

		-- Read the result and deassert the memory
		ClkMem <= '0';
		rdata_out := rdata;
		EnMem <= mem_deassert;

		-- Ends just after the falling edge of Clk
	end procedure;

	procedure WriteMemory
	(
		constant WordAddress: in	natural;
		constant wdata_in	: in	word;
		signal	Clk			: in	sl;
		signal	MAB			: out	word;
		signal	wdata		: out	word;
		signal	ClkMem		: out	sl;
		signal	EnMem		: out	sl;
		signal	WEn			: out	slv(3 downto 0)
	) is
	begin
		-- Assumes the procedure is initiated just after the rising edge of Clk
		wait until Clk = '1';

		-- Set up the address bus and enable the memory
		MAB(31 downto 2) <= int2slv(WordAddress, 30);
		MAB(1 downto 0) <= "00";
		wdata <= wdata_in;
		WEn <= (others => mem_assert);	-- Enables writing to all bits
		EnMem <= mem_assert;
		wait until rising_edge(Clk);

		-- Clock in the address and the data
		ClkMem <= '1';
		wait until falling_edge(Clk);

		-- Deassert the memory
		ClkMem <= '0';
		EnMem <= mem_deassert;
		WEn <= (others => mem_deassert);

		-- Ends just after the falling edge of Clk
	end procedure;

	procedure WaitForRisingEdges
	(
		constant	Edges	: in	natural;
		signal		Clk		: in	sl
	) is
	begin
		for i in 1 to Edges loop
			wait until rising_edge(Clk);
		end loop;
	end procedure;
	
	-- Waits for the UART TX line to send a character and returns it
	procedure UartReceiveCharFromTX
	(
		constant baudratePeriod	: in	time;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXChar			: out	character
	) is
		variable tmp : slv(7 downto 0) := (others => '0');
	begin
		wait until TX = '0';
		TXing <= '1';
		wait for 1.5 * baudratePeriod;
		for i in 0 to 7 loop
			tmp := TX & tmp(7 downto 1);
			wait for baudratePeriod;
		end loop;
		TXChar := character'val(slv2uint(tmp));
		TXing <= '0';
	end procedure;

	procedure UartSendCharToRX
	(
		constant baudratePeriod	: in	time;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXChar			: in	character
	) is
		variable RXSLV : slv(7 downto 0);
	begin
		RXing <= '1';
		RXSLV := uint2slv(character'pos(RXChar), 8);
		
		-- Send start bit
		RX <= '0';
		wait for baudratePeriod;

		-- Send Data LSB first
		for i in 0 to 7 loop
			RX <= RXSLV(i);
			wait for baudratePeriod;
		end loop;

		-- Send stop bit
		RX <= '1';
		wait for baudratePeriod;
		RXing <= '0';
	end procedure;

	procedure UartReceiveStringFromTX
	(
		constant baudratePeriod	: in	time;
		constant NumChars		: in	natural;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXStr			: out	string
	) is
		variable TXChar : character;
	begin
		-- Fill the string with null terminators
		--TXStr := (others => nul);

		for i in 1 to NumChars loop
			UartReceiveCharFromTX(baudratePeriod, TX, TXing, TXChar);
			TXStr(i) := TXChar;
		end loop;

		-- Fill the rest of the string with null terminators
		for i in NumChars + 1 to TXStr'length loop
			TXStr(i) := nul;
		end loop;
	end procedure;

	procedure UartReceiveStringFromTXUntil
	(
		constant baudratePeriod	: in	time;
		constant UntilChar		: in	character;
		signal TX				: in	sl;
		signal TXing			: out	sl;
		variable TXStr			: out	string
	) is
		variable TXChar : character;
		variable i : integer;
	begin
		-- Fill the string with null terminators
		--TXStr := (others => nul);

		TXChar := nul;
		if UntilChar = nul then
			TXChar := 'a';
		end if;
		
		i := 1;
		while TXChar /= UntilChar loop
			UartReceiveCharFromTX(baudratePeriod, TX, TXing, TXChar);
			TXStr(i) := TXChar;
			i := i + 1;
		end loop;
		
		-- Fill the rest of the string with null terminators
		for j in i to TXStr'length loop
			TXStr(j) := nul;
		end loop;
	end procedure;

	procedure UartSendStrNToRX
	(
		constant baudratePeriod	: in	time;
		constant NumChars		: in	natural;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXStr			: in	string
	) is
		variable RXChar : character;
	begin
		for i in 1 to NumChars loop
			RXChar := RXStr(i);
			UartSendCharToRX(baudratePeriod, RX, RXing, RXChar);
		end loop;
	end procedure;

	procedure UartSendStrToRX
	(
		constant baudratePeriod	: in	time;
		signal RX				: out	sl;
		signal RXing			: out	sl;
		variable RXStr			: in	string
	) is
		variable RXChar : character;
	begin
		UartSendStrNToRX(baudratePeriod, RXStr'length, RX, RXing, RXStr);
	end procedure;

end TestbenchLibrary;