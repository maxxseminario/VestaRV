library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
use work.constants.all;

entity csr_unit is
    generic (
        -- Core ISA feature switches — advertised through the read-only misa
        -- CSR (0x301) so software can probe what this chip was built with.
        ENABLE_MUL        : boolean := true;
        ENABLE_DIV        : boolean := true;
        ENABLE_ATOMICS    : boolean := true;
        ENABLE_COMPRESSED : boolean := true;
        ENABLE_BITMANIP   : boolean := true;
        -- X1 Zihpm: real 64-bit hardware performance counters 3/4 behind this
        -- generic. Default false => counters 3-31 hardwired zero (read-zero /
        -- write-ignore / no trap), fully back-compatible with the X0 scaffold.
        ENABLE_ZIHPM      : boolean := false;  -- X1 (Zihpm): real hpm counters
        -- X3 Zcmt: the jvt (jump-vector-table base) CSR (0x017, URW) lives here.
        -- Default false => jvt hardwired zero, and maindec's csr_valid map makes
        -- 0x017 an illegal CSR, so read/write traps (both-polarity gate).
        ENABLE_ZCMT       : boolean := false;  -- X3 (Zcmt): jvt CSR
        ENABLE_ZFINX      : boolean := false   -- X4 (Zfinx): consumed from phase X4 on; scaffolded X0
    );
    port (
        clk              : in  std_logic;
        resetn           : in  std_logic;

        -- X3 Zcmt: jvt base exported to vesta's table-jump FSM ({jvt[31:6],6'b0}
        -- is the table base). Held zero when ENABLE_ZCMT is off.
        jvt_value        : out std_logic_vector(31 downto 0);

        -- M13: hart id is a PORT (was the HARTID generic) so all four hart
        -- tiles share ONE netlist (tile hardening, M14); wired per instance.
        hart_id          : in  std_logic_vector(XLEN-1 downto 0) := (others => '0'); -- Value returned by mhartid (0xF14)

        -- CSR instruction interface
        csr_addr         : in  std_logic_vector(11 downto 0);  -- CSR address
        csr_write_data   : in  std_logic_vector(XLEN-1 downto 0);  -- Data to write (from rs1 or immediate)
        csr_op           : in  std_logic_vector(2 downto 0);   -- CSR operation (funct3)
        csr_valid        : in  std_logic;                      -- Valid CSR operation
        csr_read_data    : out std_logic_vector(XLEN-1 downto 0);  -- Data read from CSR

        -- Performance counter input
        inst_retired     : in  std_logic;                      -- Instruction retired signal

        -- X1 Zihpm event inputs (from vesta internal signals — NOT tile/MCU
        -- boundary ports). All default inactive so non-Zihpm instantiations and
        -- the OFF build are unaffected. csr_unit derives the grant/trap edges
        -- internally from these levels (it runs on the free-running clk, so the
        -- levels are sampled every real cycle even while clk_cpu is gated).
        ev_bus_stall     : in  std_logic := '0';  -- '1' = arbiter request asserted, grant not held (mem_ready low)
        ev_sleep         : in  std_logic := '0';  -- '1' = hart in WFI/sleep state
        ev_trap_entry    : in  std_logic := '0'   -- '1' while in a trap-entry state (IRQ_SV / TRAP_STATE)
    );
end csr_unit;

architecture behave of csr_unit is

    function b2sl(b : boolean) return std_logic is
    begin
        if b then
            return '1';
        else
            return '0';
        end if;
    end function;

    -- misa: MXL=01 (RV32) in bits 31:30; extension letters A(0), B(1), C(2),
    -- I(8), M(12). M is advertised only when BOTH mul and div are present
    -- (the M extension is all-or-nothing per the spec). B (ratified 2024) =
    -- Zba+Zbb+Zbs, all of which this core implements when ENABLE_BITMANIP
    -- (Zbc rides the same switch but has no misa letter). Read-only — writes
    -- are ignored like the other fixed CSRs. Zihpm adds NO misa bit.
    -- NOTE: misa is XLEN-wide but the MXL field POSITION is XLEN-relative
    -- (bits XLEN-1:XLEN-2) and its VALUE differs per width (01=RV32, 10=RV64)
    -- — bit 30 here is the RV32 encoding, revisit with any real RV64 work.
    constant MISA_VALUE : std_logic_vector(XLEN-1 downto 0) := (
        30 => '1',                                -- MXL = 01 (RV32)
        12 => b2sl(ENABLE_MUL and ENABLE_DIV),    -- M
        8  => '1',                                -- I (always)
        2  => b2sl(ENABLE_COMPRESSED),            -- C
        1  => b2sl(ENABLE_BITMANIP),              -- B = Zba/Zbb/Zbs
        0  => b2sl(ENABLE_ATOMICS),               -- A
        others => '0');

    -- Performance counters (64-bit)
    signal mcycle     : std_logic_vector(63 downto 0);
    signal minstret   : std_logic_vector(63 downto 0);

    -- X1 Zihpm: real counters 3 and 4 + their event selectors + mcountinhibit.
    -- When ENABLE_ZIHPM is false these signals are held at reset (zero) and
    -- never written, so every read arm below returns zero for BOTH polarities.
    signal hpm3       : std_logic_vector(63 downto 0);
    signal hpm4       : std_logic_vector(63 downto 0);
    signal mhpmevent3 : std_logic_vector(XLEN-1 downto 0);
    signal mhpmevent4 : std_logic_vector(XLEN-1 downto 0);
    signal mcountinhibit : std_logic_vector(XLEN-1 downto 0);

    -- X3 Zcmt jvt CSR (0x017). WARL: mode = bits(5:0) pinned 0 (Jump Table Mode
    -- only), base = bits(31:6) writable (64-byte aligned). Held zero and never
    -- written when ENABLE_ZCMT is false, so both read arm and export return zero.
    signal jvt        : std_logic_vector(XLEN-1 downto 0);
    -- Edge trackers (clk domain) for the grant (stall falling edge) and
    -- trap-entry (rising edge) events.
    signal prev_stall : std_logic;
    signal prev_trap  : std_logic;

    -- Internal signals
    signal csr_write_en  : std_logic;
    signal csr_read_val  : std_logic_vector(XLEN-1 downto 0);
    signal csr_new_val   : std_logic_vector(XLEN-1 downto 0);

    -- XLEN-wide comparison/mask constants (slv "=" on unequal lengths is
    -- silently false — never compare against a literal of another width)
    constant CSR_ZERO_X : std_logic_vector(XLEN-1 downto 0) := (others => '0');
    -- mcountinhibit implemented bits: 0 (cycle), 2 (instret), 3/4 (hpm3/4)
    constant MCOUNTINHIBIT_MASK : std_logic_vector(XLEN-1 downto 0) :=
        (0 => '1', 2 => '1', 3 => '1', 4 => '1', others => '0');

    -- Event decode: returns true when the counter whose selector is `sel`
    -- should increment this cycle. Event set is FIXED (X1.5 spec / D2):
    --   0 off | 1 arbiter-stall cycles | 2 shared-bus grants |
    --   3 sleep cycles | 4 trap entries. Unsupported values count nothing.
    function hpm_fires(sel        : std_logic_vector(XLEN-1 downto 0);
                       stall_lvl  : std_logic;
                       stall_fell : std_logic;
                       sleep_lvl  : std_logic;
                       trap_rose  : std_logic) return boolean is
    begin
        case sel is
            when x"00000001" => return stall_lvl  = '1';  -- arbiter-stall cycles
            when x"00000002" => return stall_fell = '1';  -- shared-bus grants (one per completed txn)
            when x"00000003" => return sleep_lvl  = '1';  -- sleep cycles
            when x"00000004" => return trap_rose  = '1';  -- trap entries taken
            when others      => return false;             -- 0 = off; unsupported = count nothing
        end case;
    end function;

begin

    -- CSR write enable (don't write on read-only operations when rs1/uimm = 0)
    csr_write_en <= csr_valid when (csr_op(1) = '1' or csr_op(0) = '1'
                                or (csr_write_data /= CSR_ZERO_X))
                                else '0';

    -- CSR read process
    process(csr_addr, mcycle, minstret, hart_id,
            hpm3, hpm4, mhpmevent3, mhpmevent4, mcountinhibit, jvt)
    begin
        case csr_addr is
            -- Machine Information Registers (Read-only)
            when CSR_MHARTID   => csr_read_val <= hart_id;
            when CSR_MISA      => csr_read_val <= MISA_VALUE;

            -- X3 Zcmt jvt (read arm unconditional; jvt is held zero when
            -- ENABLE_ZCMT is off, and 0x017 is an illegal CSR there anyway).
            when CSR_JVT       => csr_read_val <= jvt;

            -- Machine Counters (Read/Write)
            when CSR_MCYCLE    => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_MINSTRET  => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_MCYCLEH   => csr_read_val <= mcycle(63 downto 32);
            when CSR_MINSTRETH => csr_read_val <= minstret(63 downto 32);

            -- User-readable counters (Read-only shadows of machine counters).
            -- This M-mode-only core implements NO mcounteren: cycle/instret read
            -- unconditionally, so the hpm user-view arms below do the same (see
            -- report -- mcounteren reads zero rather than gating/trapping).
            when CSR_CYCLE     => csr_read_val <= mcycle(XLEN-1 downto 0);
            when CSR_INSTRET   => csr_read_val <= minstret(XLEN-1 downto 0);
            when CSR_CYCLEH    => csr_read_val <= mcycle(63 downto 32);
            when CSR_INSTRETH  => csr_read_val <= minstret(63 downto 32);

            -- X1 Zihpm counters 3/4 (machine + user-view alias). Read zero when
            -- ENABLE_ZIHPM is false (signals held at reset). Counters 5-31 and
            -- time/timeh fall through to `others` => zero (legal, no trap).
            when CSR_MHPMEVENT3    => csr_read_val <= mhpmevent3;
            when CSR_MHPMEVENT4    => csr_read_val <= mhpmevent4;
            when CSR_MHPMCOUNTER3  | CSR_HPMCOUNTER3  => csr_read_val <= hpm3(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER4  | CSR_HPMCOUNTER4  => csr_read_val <= hpm4(XLEN-1 downto 0);
            when CSR_MHPMCOUNTER3H | CSR_HPMCOUNTER3H => csr_read_val <= hpm3(63 downto 32);
            when CSR_MHPMCOUNTER4H | CSR_HPMCOUNTER4H => csr_read_val <= hpm4(63 downto 32);
            when CSR_MCOUNTINHIBIT => csr_read_val <= mcountinhibit;

            when others        => csr_read_val <= CSR_ZERO_X;
        end case;
    end process;

    -- CSR operation computation
    process(csr_op, csr_read_val, csr_write_data)
    begin
        case csr_op is
            when CSRRW_FN3 | CSRRWI_FN3 =>  -- Write
                csr_new_val <= csr_write_data;
            when CSRRS_FN3 | CSRRSI_FN3 =>  -- Set bits
                csr_new_val <= csr_read_val or csr_write_data;
            when CSRRC_FN3 | CSRRCI_FN3 =>  -- Clear bits
                csr_new_val <= csr_read_val and (not csr_write_data);
            when others =>
                csr_new_val <= csr_read_val;
        end case;
    end process;

    -- CSR write process
    process(clk, resetn)
        variable v_stall_fell : std_logic;
        variable v_trap_rose  : std_logic;
    begin
        if resetn = '0' then
            -- Reset counters to zero
            mcycle   <= (others => '0');
            minstret <= (others => '0');
            hpm3     <= (others => '0');
            hpm4     <= (others => '0');
            mhpmevent3 <= (others => '0');
            mhpmevent4 <= (others => '0');
            mcountinhibit <= (others => '0');
            jvt        <= (others => '0');
            prev_stall <= '0';
            prev_trap  <= '0';

        elsif rising_edge(clk) then
            -- Cycle counter: free-running, optionally inhibited by
            -- mcountinhibit(0) (only reachable when ENABLE_ZIHPM writes it).
            if not (ENABLE_ZIHPM and mcountinhibit(0) = '1') then
                mcycle <= std_logic_vector(unsigned(mcycle) + 1);
            end if;

            -- Instruction counter: on retire, optionally inhibited by bit 2.
            if inst_retired = '1' and not (ENABLE_ZIHPM and mcountinhibit(2) = '1') then
                minstret <= std_logic_vector(unsigned(minstret) + 1);
            end if;

            -- X1 Zihpm: real counters 3/4. Whole block prunes when the generic
            -- is false (constant-false conditions), leaving hpm3/4 at zero.
            if ENABLE_ZIHPM then
                -- Derive the two edge events from the sampled levels. prev_*
                -- still holds LAST cycle's value at this point (the updates
                -- below schedule next-cycle values).
                v_stall_fell := prev_stall and (not ev_bus_stall);  -- a stalled txn just completed = one grant
                v_trap_rose  := ev_trap_entry and (not prev_trap);  -- entered a trap-handling state
                prev_stall <= ev_bus_stall;
                prev_trap  <= ev_trap_entry;

                -- Counter 3
                if mcountinhibit(3) = '0' then
                    if hpm_fires(mhpmevent3, ev_bus_stall, v_stall_fell, ev_sleep, v_trap_rose) then
                        hpm3 <= std_logic_vector(unsigned(hpm3) + 1);
                    end if;
                end if;

                -- Counter 4
                if mcountinhibit(4) = '0' then
                    if hpm_fires(mhpmevent4, ev_bus_stall, v_stall_fell, ev_sleep, v_trap_rose) then
                        hpm4 <= std_logic_vector(unsigned(hpm4) + 1);
                    end if;
                end if;
            end if;

            -- Handle CSR writes. A later assignment to a counter half here wins
            -- over the increment above (write precedence, same as mcycle today).
            if csr_write_en = '1' then
                case csr_addr is
                    when CSR_MCYCLE =>
                        mcycle(XLEN-1 downto 0) <= csr_new_val;
                    when CSR_MCYCLEH =>
                        mcycle(63 downto 32) <= csr_new_val;
                    when CSR_MINSTRET =>
                        minstret(XLEN-1 downto 0) <= csr_new_val;
                    when CSR_MINSTRETH =>
                        minstret(63 downto 32) <= csr_new_val;

                    -- X1 Zihpm writable CSRs (ignored when ENABLE_ZIHPM off so
                    -- they stay hardwired zero for the OFF polarity).
                    when CSR_MHPMEVENT3 =>
                        if ENABLE_ZIHPM then mhpmevent3 <= csr_new_val; end if;
                    when CSR_MHPMEVENT4 =>
                        if ENABLE_ZIHPM then mhpmevent4 <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER3 =>
                        if ENABLE_ZIHPM then hpm3(XLEN-1 downto 0) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER3H =>
                        if ENABLE_ZIHPM then hpm3(63 downto 32) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER4 =>
                        if ENABLE_ZIHPM then hpm4(XLEN-1 downto 0) <= csr_new_val; end if;
                    when CSR_MHPMCOUNTER4H =>
                        if ENABLE_ZIHPM then hpm4(63 downto 32) <= csr_new_val; end if;
                    when CSR_MCOUNTINHIBIT =>
                        -- Only bits 0,2,3,4 are implemented; 1 and 5-31 read-only zero.
                        if ENABLE_ZIHPM then
                            mcountinhibit <= csr_new_val and MCOUNTINHIBIT_MASK;
                        end if;

                    -- X3 Zcmt jvt write (WARL): mode(5:0) pinned 0, base(31:6)
                    -- writable. Gated on ENABLE_ZCMT so it stays hardwired zero for
                    -- the OFF polarity (and 0x017 traps illegal there via csr_valid).
                    when CSR_JVT =>
                        if ENABLE_ZCMT then
                            jvt <= csr_new_val(31 downto 6) & "000000";
                        end if;

                    when others =>
                        null;  -- Read-only CSRs, user-view aliases, or hardwired-zero hpm indices
                end case;
            end if;
        end if;
    end process;

    -- Output read data
    csr_read_data <= csr_read_val;

    -- X3 Zcmt: export the jvt base (held zero when ENABLE_ZCMT is off).
    jvt_value <= jvt;

end behave;
