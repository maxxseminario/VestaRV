-- =====================================================================
-- Wrapper bench for pmp_unit's grant-function PSL properties.
-- It exposes a `settled` flag and a post-settle `sample` pulse the unclocked properties qualify on.
-- Three instances: 16-entry enabled, 8-entry enabled, disabled.
-- =====================================================================
library ieee; use ieee.std_logic_1164.all; use ieee.numeric_std.all;

entity pmp_formal_tb is end entity;

architecture tb of pmp_formal_tb is
    signal cfg_flat  : std_logic_vector(127 downto 0) := (others => '0');
    signal addr_flat : std_logic_vector(479 downto 0) := (others => '0');
    signal f_addr    : std_logic_vector(31 downto 0)  := (others => '0');
    signal d_addr    : std_logic_vector(31 downto 0)  := (others => '0');
    signal f_priv_m  : std_logic := '1';
    signal d_priv_m  : std_logic := '1';
    signal d_read    : std_logic := '0';
    signal d_write   : std_logic := '0';
    signal f16, d16, f8, d8, foff, doff : std_logic;
    signal settled   : std_logic := '0';   -- guard: low until the first pattern has propagated past the time-0 'U' outputs
    -- Sampling strobe: pmp_unit is combinational, so inputs and outputs settle in different deltas and any continuous unclocked invariant is transiently false while they do.
    -- `sample` pulses only after each input change has propagated; qualify every property on it.
    signal sample    : std_logic := '0';
    -- Stimulus-shape flags telling the properties which region shape the current address is in, so a decode property need not restate pmp_check tautologically.
    signal napot_in  : std_logic := '0';   -- d_addr is inside the NAPOT region
    signal napot_out : std_logic := '0';   -- d_addr is OUTSIDE it (explicitly flagged)
    signal tor_in    : std_logic := '0';   -- d_addr is inside the TOR region
    signal tor_at_hi : std_logic := '0';   -- d_addr == TOR hi (the boundary)
    signal napot_lo, napot_hi, tor_hi : std_logic_vector(31 downto 0) := (others=>'0');

    -- cfg byte: [7]=L [4:3]=A (0 OFF, 1 TOR, 2 NA4, 3 NAPOT) [2]=X [1]=W [0]=R
    constant A_TOR   : std_logic_vector(1 downto 0) := "01";
    constant A_NAPOT : std_logic_vector(1 downto 0) := "11";
    procedure set_e0(signal cfg : out std_logic_vector(127 downto 0);
                     a : std_logic_vector(1 downto 0);
                     x, w, r : std_logic) is
        variable v : std_logic_vector(127 downto 0) := (others => '0');
    begin
        v(4 downto 3) := a; v(2) := x; v(1) := w; v(0) := r;
        cfg <= v;
    end procedure;
begin
    dut16 : entity work.pmp_unit generic map (ENABLE_PMP => true,  PMP_ENTRIES => 16)
        port map (cfg_flat, addr_flat, f_addr, f_priv_m, f16, d_addr, d_priv_m, d_read, d_write, d16);
    dut8  : entity work.pmp_unit generic map (ENABLE_PMP => true,  PMP_ENTRIES => 8)
        port map (cfg_flat, addr_flat, f_addr, f_priv_m, f8,  d_addr, d_priv_m, d_read, d_write, d8);
    dutoff: entity work.pmp_unit generic map (ENABLE_PMP => false, PMP_ENTRIES => 16)
        port map (cfg_flat, addr_flat, f_addr, f_priv_m, foff, d_addr, d_priv_m, d_read, d_write, doff);

    stim : process
        procedure step is begin
            wait for 700 ps;            -- let the combinational tree settle
            sample <= '1'; wait for 100 ps;
            sample <= '0'; wait for 200 ps;
        end procedure;
    begin
        -- t=0 pattern, then declare settled once outputs have resolved.
        cfg_flat <= (others => '0'); addr_flat <= (others => '0');
        d_read <= '1'; d_write <= '0'; d_priv_m <= '1'; f_priv_m <= '1';
        step; settled <= '1'; step;

        -- 1. EMPTY BANK, M-MODE: must GRANT.
        d_priv_m <= '1'; f_priv_m <= '1'; step;
        -- 2. EMPTY BANK, U-MODE: must DENY (the security half).
        d_priv_m <= '0'; f_priv_m <= '0'; step;
        -- 3. NAPOT entry 0, no permissions, U-mode: DENY on a match.
        set_e0(cfg_flat, A_NAPOT, '0', '0', '0');
        addr_flat(31 downto 0) <= x"00000FFF"; d_addr <= x"00001000"; step;
        -- 4. NAPOT entry 0 WITH R, U-mode read: the permitted shape.
        set_e0(cfg_flat, A_NAPOT, '1', '1', '1'); step;
        -- 5. TOR entry 0, U-mode
        set_e0(cfg_flat, A_TOR, '0', '0', '0');
        addr_flat(31 downto 0) <= x"00001000"; d_addr <= x"00000004"; step;
        set_e0(cfg_flat, A_TOR, '1', '1', '1'); step;
        -- 6. write and fetch shapes
        d_read <= '0'; d_write <= '1'; step;
        d_read <= '1'; d_write <= '1'; step;
        f_addr <= x"00000004"; step;
        -- 7. Upper-half-only config: lower 8 entries zero, entry 8 NAPOT-permissive.
        -- dut8 must ignore it entirely and deny in U-mode.
        cfg_flat <= (others => '0');
        cfg_flat(68 downto 67) <= A_NAPOT; cfg_flat(66) <= '1';
        cfg_flat(65) <= '1'; cfg_flat(64) <= '1';
        d_priv_m <= '0'; f_priv_m <= '0'; step; step;
        -- 8. back to M-mode with the empty bank
        cfg_flat <= (others => '0'); d_priv_m <= '1'; f_priv_m <= '1'; step;

        -- Decode-sensitive stimulus: matched in-region and out-of-region addresses, so a wrong decode must change an observable grant.
        -- NAPOT region base 0x1000, size 16 bytes: pmpaddr = 0x400|0x1, the word encoding with one trailing 1, covering 0x1000..0x100F.
        napot_lo <= x"00001000"; napot_hi <= x"0000100F";
        set_e0(cfg_flat, A_NAPOT, '1', '1', '1');     -- RWX permitted
        addr_flat(29 downto 0) <= "00" & x"0000401";  -- NAPOT: 0x1000/16B
        d_priv_m <= '0'; f_priv_m <= '0'; d_read <= '1'; d_write <= '0';
        -- IN region (must GRANT under U-mode because the entry permits R)
        d_addr <= x"00001000"; napot_in <= '1'; step;
        d_addr <= x"00001008"; step;
        d_addr <= x"0000100C"; step;
        -- OUT of region (must DENY: no other entry matches, U-mode)
        napot_in <= '0'; napot_out <= '1';
        d_addr <= x"00000FFC"; step;
        d_addr <= x"00001010"; step;
        d_addr <= x"00002000"; step;
        napot_out <= '0';

        -- TOR entry 0: lo = 0, hi = 0x1000.  Region is [0, 0x1000).
        cfg_flat <= (others => '0'); step;
        set_e0(cfg_flat, A_TOR, '1', '1', '1');
        addr_flat(29 downto 0) <= "00" & x"0000400";  -- hi = 0x1000 (word addr)
        tor_hi <= x"00001000";
        -- inside
        tor_in <= '1'; d_addr <= x"00000000"; step;
        d_addr <= x"00000FFC"; step;
        -- The boundary a = hi: RISC-V TOR is [lo,hi), so this address is OUTSIDE the region and must be denied.
        tor_in <= '0'; tor_at_hi <= '1'; d_addr <= x"00001000"; step;
        tor_at_hi <= '0'; d_addr <= x"00001004"; step;
        napot_in <= '0'; tor_in <= '0'; cfg_flat <= (others => '0'); step;

        report "pmp_formal_tb: stimulus complete" severity note;
        wait;
    end process;
end architecture;
