library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use ieee.math_real.log2;
use std.textio.all;  
use ieee.std_logic_textio.all;  

package macros is

	----------------------------------------------------------------------------
	-- General attributes and useful macros
	----------------------------------------------------------------------------

	-- Shortcuts for common data types
	subtype sl			is std_logic;
	subtype slv			is std_logic_vector;
	subtype word		is slv(31 downto 0);
	subtype halfword	is slv(15 downto 0);
	subtype quarterword	is slv(07 downto 0);
	subtype byte		is quarterword;
	type word_array		is array (natural range <>) of word;
	type halfword_array	is array (natural range <>) of halfword;
	
	-- Peripheral Memory Address Bus Partition
	subtype PeriphMABPart	is slv(7 downto 2);
	
	-- Reset Standards
	constant rst_assert		: sl	:= '0';
	constant rst_deassert	: sl	:= '1';
	
	-- Memory Assert Standards
	constant mem_assert		: sl	:= '0';	-- The SRAM and ROM IPs use active low signals to select them, so the peripherals were standardized to use the same convention
	constant mem_deassert	: sl	:= '1';

	-- Useful helper functions
	function ceil_log2 (value : positive) return natural;
	function int2slv(x : integer; num_bits : integer) return std_logic_vector;
	function uint2slv(x : integer; num_bits : integer) return std_logic_vector;
	function slv2int(x: slv) return integer;
	function slv2uint(x: slv) return integer;
	function bool2sl(x : boolean) return sl;
	function bit2sl(x : bit) return sl;
	function sl2bit(x : sl) return bit;
	function bitv2slv(x : bit_vector) return slv;
	function slv2bitv(x : slv) return bit_vector;
	function or_reduct(x : slv) return sl;
	function and_reduct(x : slv) return sl;
	function reverse_slv_order(x : slv) return slv;
	function duplicate_bit(x : sl; num_bits : integer) return slv;
	function expandZeros(num_bits : integer range 1 to 32; vector : slv) return slv;
	function to_hex(SlvIn : std_logic_vector) return string;

	-- Attributes
	attribute keep : boolean;

end macros;


package body macros is

	----------------------------------------------------------------------------
	-- Converts a std_logic_vector to a hexidecimal string. 
	----------------------------------------------------------------------------
	function to_hex(SlvIn : std_logic_vector) return string is
		variable L : LINE;  -- LINE is a pointer to a dynamically allocated string
		variable result : string(1 to (SlvIn'length + 3)/4);  -- Prevents memory issues
	begin
		-- Write the hex value into the LINE buffer
		hwrite(L, SlvIn);
		
		-- Extract the string content (L.all) and store it in 'result'
		result := L.all;
		
		-- Deallocate the LINE to prevent memory leaks
		DEALLOCATE(L);
		
		-- Return the hex string
		return result;
	end function to_hex;


	----------------------------------------------------------------------------
	-- Finds the MSbit index required to represent a given positive number.
	----------------------------------------------------------------------------
	function ceil_log2 (value : positive) return natural is
		variable result : natural;
	begin
		result := 0;
		while (value > (2**result)) loop
			result := result + 1;
		end loop;
		return result;
	end function ceil_log2;

	----------------------------------------------------------------------------
	-- Converts a signed integer into a standard logic vector (uses numeric_std)
	----------------------------------------------------------------------------
	function int2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_signed(x, num_bits));
	end int2slv;

	----------------------------------------------------------------------------
	-- Converts an unsigned integer into a standard logic vector (uses numeric_std)
	----------------------------------------------------------------------------
	function uint2slv(x : integer; num_bits : integer) return std_logic_vector is
	begin
		return std_logic_vector(to_unsigned(x, num_bits));
	end uint2slv;

	----------------------------------------------------------------------------
	-- Converts a standard logic vector into a signed integer (uses numeric_std)
	----------------------------------------------------------------------------
	function slv2int(x: slv) return integer is
	begin
		return to_integer(signed(x));
	end slv2int;

	----------------------------------------------------------------------------
	-- Converts a standard logic vector into an unsigned integer (uses numeric_std)
	----------------------------------------------------------------------------
	function slv2uint(x: slv) return integer is
	begin
		return to_integer(unsigned(x));
	end slv2uint;

	----------------------------------------------------------------------------
	-- Converts a boolean into a std_logic
	----------------------------------------------------------------------------
	function bool2sl(x : boolean) return sl is
	begin
		if x then
			return('1');
		else
			return('0');
		end if;
	end bool2sl;

	----------------------------------------------------------------------------
	-- Converts a bit into a std_logic
	----------------------------------------------------------------------------
	function bit2sl(x : bit) return sl is
	begin
		if x = '1' then
			return('1');
		else
			return('0');
		end if;
	end bit2sl;

	----------------------------------------------------------------------------
	-- Converts a std_logic into a bit
	----------------------------------------------------------------------------
	function sl2bit(x : sl) return bit is
	begin
		if x = '1' then
			return('1');
		else
			return('0');
		end if;
	end sl2bit;

	----------------------------------------------------------------------------
	-- Converts a bit_vector into a std_logic_vector
	----------------------------------------------------------------------------
	function bitv2slv(x : bit_vector) return slv is
		variable ret_val : slv(x'high downto x'low);
	begin
		for i in x'range loop
			ret_val(i) := bit2sl(x(i));
		end loop;
		return ret_val;
	end bitv2slv;

	----------------------------------------------------------------------------
	-- Converts a std_logic_vector into a bit_vector
	----------------------------------------------------------------------------
	function slv2bitv(x : slv) return bit_vector is
		variable ret_val : bit_vector(x'high downto x'low);
	begin
		for i in x'range loop
			ret_val(i) := sl2bit(x(i));
		end loop;
		return ret_val;
	end slv2bitv;
	
	----------------------------------------------------------------------------
	-- ORs all bits in a std_logic_vector together
	----------------------------------------------------------------------------
	function or_reduct(x : slv) return sl is
		variable ret_val : sl := '0';
	begin
		for i in x'range loop
			ret_val := ret_val or x(i);
		end loop;
		return ret_val;
	
	end or_reduct;
	
	----------------------------------------------------------------------------
	-- ANDs all bits in a std_logic_vector together
	----------------------------------------------------------------------------
	function and_reduct(x : slv) return sl is
		variable ret_val : sl := '1';
	begin
		for i in x'range loop
			ret_val := ret_val and x(i);
		end loop;
		return ret_val;
	end and_reduct;
	
	----------------------------------------------------------------------------
	-- Reverses the ordering of the bits in a standard logic vector
	----------------------------------------------------------------------------
	function reverse_slv_order(x : slv) return slv is
		variable result : slv(x'high downto x'low);
	begin
		for index in x'high downto x'low loop
			result(index) := x(x'high - index);
		end loop;
		return result;
	end reverse_slv_order;

	----------------------------------------------------------------------------
	-- Duplicates a bit into an SLV (for sign extension)
	----------------------------------------------------------------------------
	function duplicate_bit(x : sl; num_bits : integer) return slv is
		variable result : slv(num_bits - 1 downto 0);
	begin
		for index in num_bits - 1 downto 0 loop
			result(index) := x;
		end loop;
		return result;
	end duplicate_bit;

	----------------------------------------------------------------------------
	-- Expands a slv to the desired number of bits, padding with '0's if necessary
	----------------------------------------------------------------------------
	function expandZeros(num_bits : integer range 1 to 32; vector : slv) return slv is
		variable vector_num_bits : integer;
	begin
		vector_num_bits := vector'high - vector'low + 1;
		if vector_num_bits = num_bits then
			return vector;
		else
			return (num_bits - 1 downto vector_num_bits => '0') & vector;
		end if;
	end expandZeros;
	
end macros;
