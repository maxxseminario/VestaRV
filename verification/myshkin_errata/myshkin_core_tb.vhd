-- Bare Myshkin core with a 1-cycle RAM on clk_cpu (adddec is clocked by clk_cpu in MCU.vhd).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library std;
use std.textio.all;
use ieee.std_logic_textio.all;

entity myshkin_core_tb is
    generic (
        STALL  : integer := 0;
        CSR_PC : integer := 0
    );
end entity;

architecture tb of myshkin_core_tb is
    type ram_t is array (0 to 2047) of std_logic_vector(31 downto 0);
    signal ram : ram_t := (others => (others => '0'));
    signal clk, clk_cpu : std_logic := '0';
    signal resetn, sleep, trap, ret : std_logic := '0';
    signal addr, wd, rd, a0 : std_logic_vector(31 downto 0) := (others => '0');
    signal wen : std_logic_vector(3 downto 0);
    signal mask : std_logic_vector(1 downto 0);
    signal z16 : std_logic_vector(15 downto 0) := (others => '0');
    signal stop : boolean := false;

    function idx(a : std_logic_vector) return integer is
    begin
        return (to_integer(unsigned(a(15 downto 0))) - 16#8000#) / 4;
    end function;

    function hex(v : std_logic_vector(31 downto 0)) return string is
        constant h : string(1 to 16) := "0123456789abcdef";
        variable s : string(1 to 8);
    begin
        for k in 0 to 7 loop
            if is_x(v(4*k+3 downto 4*k)) then
                s(8-k) := 'x';
            else
                s(8-k) := h(to_integer(unsigned(v(4*k+3 downto 4*k))) + 1);
            end if;
        end loop;
        return s;
    end function;
begin
    clk <= not clk after 5 ns when not stop;
    mask <= addr(1 downto 0);

    dut : entity work.vesta
        generic map (PC_RST_VAL => x"00008200", NUM_IRQS => 16)
        port map (
            clk => clk, resetn => resetn, sleep => sleep, clk_cpu => clk_cpu,
            data_addr => addr, wen => wen, write_data => wd, read_data => rd, mask => mask,
            irq_vector => z16, irq_priority => z16, irq_en => z16, irq_recursion_en => '0',
            isr_ret => ret, trap_flag => trap, a0 => a0
        );

    mem : process(clk_cpu, resetn)
        file f : text;
        variable l : line;
        variable w : std_logic_vector(31 downto 0);
        variable i : integer;
        variable done : boolean := false;
    begin
        if not done then
            file_open(f, "image.hex", read_mode);
            i := 0;
            while not endfile(f) loop
                readline(f, l);
                hread(l, w);
                ram(i) <= w;
                i := i + 1;
            end loop;
            file_close(f);
            done := true;
        elsif rising_edge(clk_cpu) then
            i := idx(addr);
            if i >= 0 and i <= 2047 then
                rd <= ram(i);
                if wen(0) = '0' then ram(i)(7 downto 0)   <= wd(7 downto 0);   end if;
                if wen(1) = '0' then ram(i)(15 downto 8)  <= wd(15 downto 8);  end if;
                if wen(2) = '0' then ram(i)(23 downto 16) <= wd(23 downto 16); end if;
                if wen(3) = '0' then ram(i)(31 downto 24) <= wd(31 downto 24); end if;
            else
                rd <= (others => '0');
            end if;
        end if;
    end process;

    -- The next fetch goes out during the CSR instruction's EXECUTE, so freeze there.
    frz : process
        variable fired : boolean := false;
    begin
        wait until falling_edge(clk);
        if STALL = 1 and not fired and not is_x(addr)
           and to_integer(unsigned(addr(15 downto 0))) = CSR_PC + 4 then
            sleep <= '1';
            fired := true;
            for k in 1 to 6 loop
                wait until falling_edge(clk);
            end loop;
            sleep <= '0';
        end if;
    end process;

    ctl : process
        variable o : line;
        variable c : integer := 0;
    begin
        wait for 40 ns;
        wait until falling_edge(clk);
        resetn <= '1';
        while c < 20000 and a0 /= x"CAFEBABE" and trap /= '1' loop
            wait until rising_edge(clk);
            c := c + 1;
        end loop;
        for k in 1 to 20 loop
            wait until rising_edge(clk);
        end loop;
        write(o, "END a0=" & hex(a0) & " trap=" & std_logic'image(trap) & " cycles=" & integer'image(c));
        writeline(output, o);
        for k in 0 to 23 loop
            write(o, "SIG " & integer'image(k) & " " & hex(ram((16#9000# - 16#8000#) / 4 + k)));
            writeline(output, o);
        end loop;
        stop <= true;
        wait;
    end process;
end architecture;
