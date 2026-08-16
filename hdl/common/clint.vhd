/* =============================================================================
   clint.vhd: per-hart software interrupts (msip) and a shared 64-bit mtime with per-hart mtimecmp, for NHARTS harts.
   Slave behind mp_arbiter in the shared window, on the free-running mclk, so there is no clock-domain crossing.
   Bus: active-high en, four active-high byte lanes on we, address at cycle T and rdata at T+1, writes lane-merge; only addr(ADDR_W-1:0) decodes, so the page aliases every 2**ADDR_W words.
   msip(h)/mtip(h) are levels into hart h's irq_vector; an ISR must write msip[h]=0 or advance mtimecmp[h] before iret, or the interrupt re-triggers.
   Word map: 0..NHARTS-1 = msip[h] bit 0; MTIME_W and +1 = mtime lo/hi, free-running and writable; CMP_W+2h and +1 = mtimecmp[h] lo/hi, reset all-ones so mtip starts low.
   ============================================================================= */

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity clint is
    generic (
        NHARTS : natural := 4;
        -- Word-address width; 2**ADDR_W must cover the whole register file (asserted below)
        ADDR_W : natural := 4
    );
    port (
        clk    : in  std_logic;   -- free-running mclk
        resetn : in  std_logic;

        -- Slave port behind mp_arbiter; enables are active-high
        en     : in  std_logic;
        we     : in  std_logic_vector(3 downto 0);
        addr   : in  std_logic_vector(ADDR_W-1 downto 0);   -- word offset within block
        wdata  : in  std_logic_vector(31 downto 0);
        rdata  : out std_logic_vector(31 downto 0);

        -- per-hart level interrupts
        msip   : out std_logic_vector(NHARTS-1 downto 0);
        mtip   : out std_logic_vector(NHARTS-1 downto 0)
    );
end entity;

architecture behav of clint is

    -- Word indices of mtime lo and of mtimecmp[0] lo, sized to clear the msip array
    constant MTIME_W : natural := ((4*NHARTS + 15) / 16) * 4;
    constant CMP_W   : natural := MTIME_W + 4;

    type cmp_t is array(0 to NHARTS-1) of std_logic_vector(63 downto 0);

    signal msip_reg  : std_logic_vector(NHARTS-1 downto 0);
    signal mtime     : std_logic_vector(63 downto 0);
    signal mtimecmp  : cmp_t;
    signal mtip_reg  : std_logic_vector(NHARTS-1 downto 0);
    signal rdata_reg : std_logic_vector(31 downto 0);

    -- Merge the enabled write lanes of wd into cur and return the result
    function lane_merge(cur   : std_logic_vector(31 downto 0);
                        wd    : std_logic_vector(31 downto 0);
                        lanes : std_logic_vector(3 downto 0))
        return std_logic_vector is
        variable r : std_logic_vector(31 downto 0);
    begin
        r := cur;
        for l in 0 to 3 loop
            if lanes(l) = '1' then
                r((l+1)*8-1 downto l*8) := wd((l+1)*8-1 downto l*8);
            end if;
        end loop;
        return r;
    end function;

begin

    -- The address port must reach every register of the parameterized layout
    assert 2**ADDR_W >= CMP_W + 2*NHARTS
        report "clint: ADDR_W too small for NHARTS (see the layout formula)"
        severity failure;

    msip  <= msip_reg;
    mtip  <= mtip_reg;
    rdata <= rdata_reg;

    -- Register file, mtime counter and the per-hart timer compares, all on mclk
    clint_proc: process(clk, resetn)
        variable widx   : integer range 0 to 2**ADDR_W - 1;
        variable hidx   : integer range 0 to NHARTS-1;
        variable rd     : std_logic_vector(31 downto 0);
        variable mtime_next : std_logic_vector(63 downto 0);
    begin
        if resetn = '0' then
            msip_reg  <= (others => '0');
            mtime     <= (others => '0');
            mtimecmp  <= (others => (others => '1'));  -- All-ones keeps mtip quiet
            mtip_reg  <= (others => '0');
            rdata_reg <= (others => '0');
        elsif rising_edge(clk) then
            -- mtime free-runs, but a same-cycle write to it wins (see the write section below)
            mtime_next := mtime + 1;

            if en = '1' then
                widx := conv_integer(addr);
                rd   := (others => '0');

                -- ---- Read mux; registered here and valid next cycle, which is the arbiter's DATA state
                if widx < NHARTS then                                -- msip[h]
                    rd(0) := msip_reg(widx);
                elsif widx = MTIME_W then                            -- mtime lo
                    rd := mtime(31 downto 0);
                elsif widx = MTIME_W + 1 then                        -- mtime hi
                    rd := mtime(63 downto 32);
                elsif widx >= CMP_W and widx < CMP_W + 2*NHARTS then -- mtimecmp
                    hidx := (widx - CMP_W) / 2;
                    if (widx mod 2) = 0 then
                        rd := mtimecmp(hidx)(31 downto 0);
                    else
                        rd := mtimecmp(hidx)(63 downto 32);
                    end if;
                end if;
                rdata_reg <= rd;

                -- ---- Lane-merged writes; an undecoded word silently drops the write
                if we /= "0000" then
                    if widx < NHARTS then
                        if we(0) = '1' then          -- msip lives in bit 0, so only lane 0 can write it
                            msip_reg(widx) <= wdata(0);
                        end if;
                    elsif widx = MTIME_W then
                        mtime_next(31 downto 0) :=
                            lane_merge(mtime(31 downto 0), wdata, we);
                    elsif widx = MTIME_W + 1 then
                        mtime_next(63 downto 32) :=
                            lane_merge(mtime(63 downto 32), wdata, we);
                    elsif widx >= CMP_W and widx < CMP_W + 2*NHARTS then
                        hidx := (widx - CMP_W) / 2;
                        if (widx mod 2) = 0 then
                            mtimecmp(hidx)(31 downto 0) <=
                                lane_merge(mtimecmp(hidx)(31 downto 0), wdata, we);
                        else
                            mtimecmp(hidx)(63 downto 32) <=
                                lane_merge(mtimecmp(hidx)(63 downto 32), wdata, we);
                        end if;
                    end if;
                end if;
            end if;

            mtime <= mtime_next;

            -- ---- Registered 64-bit timer compares driving the mtip levels ----
            for h in 0 to NHARTS-1 loop
                if mtime >= mtimecmp(h) then
                    mtip_reg(h) <= '1';
                else
                    mtip_reg(h) <= '0';
                end if;
            end loop;
        end if;
    end process;

end architecture;
