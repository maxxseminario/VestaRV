-- VestaRV: shared peripheral register file
-- The house memory-mapped register protocol, written once: falling-EnMemPeriph select, byte-lane writes on the ClkMem edge, a registered read mux, write-1 arms and strobe retirement.
-- A peripheral instantiates this with the tables its .rdl single-sources (NWORDS / RSTVAL / IMPL / W1C / WOSET / WOT / PULSE / RCLR / HWOWN, emitted into <block>_regs_pkg.vhd) and keeps only its datapath.
-- This module holds exactly the IMPL bits, the software-written storage. A hardware-set flag keeps its flop in the peripheral that sets it; the module emits w1c_hit and the peripheral clears with it.
-- Design note, property-to-mask table and the migration recipe: hdl/common/regs/REGFILE.md.

library ieee;
use ieee.std_logic_1164.all;
library work;
use work.constants.all;   -- word, word_array, slv2uint

entity periph_regs is
    generic (
        -- Words in the decode window, and the first word inside the sub-slot.
        NWORDS      : natural;
        WORD_BASE   : natural := 0;

        -- One row per word, slot order, from <block>_regs_pkg. Every one of
        -- these is a property of the .rdl description.
        RSTVAL      : word_array;   -- asynchronous reset value
        IMPL        : word_array;   -- bits that hold a software-written flop
        W1C         : word_array;   -- a written 1 clears (onwrite = woclr)
        WOSET       : word_array;   -- a written 1 sets   (onwrite = woset)
        WOT         : word_array;   -- a written 1 toggles(onwrite = wot)
        PULSE       : word_array;   -- self-clearing strobe (singlepulse)
        RCLR        : word_array;   -- a read retires      (onread = rclr)
        HWOWN       : word_array;   -- bits hardware drives (hw = w or rw)

        -- In ADDITION to HWOWN: stored bits this block's own RTL may drive
        -- through the hooks because the driver is ANOTHER WORD of the same
        -- register file -- a set/clear/toggle alias -- and not hardware.
        -- SystemRDL has no way to say that, so it is the RTL's. EVFAB's
        -- EVFCHENSET/EVFCHENCLR onto EVFCHEN are the case; GPIO's PxOUT needs
        -- none only because the event fabric really does drive that word.
        HWALIAS     : word_array := (0 to 0 => (others => '0'));

        -- The RTL's own, which SystemRDL cannot express. Any of the three
        -- per-word vectors may be left at "" for all-zero; see REGFILE.md.
        -- OR-ed onto RSTVAL, for the one thing a reset value can be that
        -- SystemRDL cannot say: a GENERIC of the peripheral. I2C's slave address
        -- resets to default_SAD and GPIO's PxOUT to RstValPxOUT, both per
        -- instance. Left at its one-row default it is all zero and RSTVAL stands.
        RSTVAL_OR   : word_array := (0 to 0 => (others => '0'));

        RDTHRU      : std_logic_vector := "";  -- per word: read hw_rd, not storage
        WIDEWR      : std_logic_vector := "";  -- per word: any enabled lane writes 32 bits
        FULLWR      : std_logic_vector := "";  -- per word: only WEn = "0000" is a write at all
        STROBE_HOLD : boolean := false;        -- true: strobes retire on deselect, not on the next edge

        -- false: rdata_out is the combinational read mux, not a flop. For a
        -- block whose read the FABRIC registers (I2C, whose MCU.vhd bridge
        -- captures rdata at the access edge); see REGFILE.md.
        REGISTERED_READ : boolean := true
    );
    port (
        ClkMem      : in  std_logic;
        resetn      : in  std_logic;                     -- asynchronous, active low
        EnMemPeriph : in  std_logic;                     -- select, active low
        WEn         : in  std_logic_vector(3 downto 0);  -- byte lanes, active low
        MABPart     : in  std_logic_vector(7 downto 2);  -- word slot in the 256 B window
        wdata       : in  word;
        rdata_out   : out word;                          -- registered on ClkMem

        -- The stored words, for the peripheral's datapath.
        regs        : out word_array(0 to NWORDS-1);

        -- Per-word write qualifier, active high: while it is '1' the word is not
        -- writable and the access is neither a write nor a read of it. Storage,
        -- wr_strobe and every write-1 arm are suppressed together, because a
        -- refused write is not half an access. SYSTEM's WDTCR takes the inverse
        -- of its unlock window here.
        wr_inhibit  : in  std_logic_vector(0 to NWORDS-1) := (others => '0');

        -- Read source for every bit the module does not store, and for RDTHRU words.
        hw_rd       : in  word_array(0 to NWORDS-1) := (others => (others => '0'));

        -- Hardware access to stored bits. Only bits in IMPL and HWOWN; anything
        -- else is an assertion failure rather than a silent drop.
        hw_we       : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_wdata    : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_set      : in  word_array(0 to NWORDS-1) := (others => (others => '0'));
        hw_clr      : in  word_array(0 to NWORDS-1) := (others => (others => '0'));

        -- Hooks. All are flops set on the access edge; STROBE_HOLD picks the
        -- retirement. rd_strobe is a read, wr_strobe any lane write; their OR is
        -- "any access to this slot".
        -- Combinational, unregistered: selected and addressed, this cycle. The
        -- hook for a write that LAUNCHES something on the same edge it lands
        -- (QSPIxCMD, UARTxTX, OWxCMD): those set their request from the raw
        -- decode today, and a registered strobe would delay them a cycle.
        acc_hit     : out std_logic_vector(0 to NWORDS-1);

        rd_strobe   : out std_logic_vector(0 to NWORDS-1);
        wr_strobe   : out std_logic_vector(0 to NWORDS-1);
        wr_pulse    : out word_array(0 to NWORDS-1);   -- PULSE bits written 1
        w1c_hit     : out word_array(0 to NWORDS-1);   -- W1C   bits written 1
        woset_hit   : out word_array(0 to NWORDS-1);   -- WOSET bits written 1
        wot_hit     : out word_array(0 to NWORDS-1);   -- WOT   bits written 1
        rd_clr      : out word_array(0 to NWORDS-1)    -- RCLR bits on a read
    );
end entity periph_regs;

architecture rtl of periph_regs is

    constant ZERO32 : word := (others => '0');
    constant ONES32 : word := (others => '1');

    function slBool(b : boolean) return std_logic is
    begin
        if b then return '1'; else return '0'; end if;
    end function;

    -- RDTHRU / WIDEWR default to the null vector; normalise both to NWORDS bits
    -- indexed from 0. They are read in GENERATE CONDITIONS, which is why they end
    -- up as constants rather than as a function call on the generic: a generate
    -- condition takes an indexed constant and not a function.
    function normBits(v : std_logic_vector) return std_logic_vector is
        variable r : std_logic_vector(0 to NWORDS - 1) := (others => '0');
    begin
        if v'length = NWORDS then
            for i in r'range loop
                r(i) := v(v'low + i);
            end loop;
        end if;
        return r;
    end function;

    -- A definite 1 somewhere in the vector. Used by the ownership assertion
    -- below, which must not fire on the 'U's every signal carries at time 0.
    function anyOne(v : std_logic_vector) return boolean is
    begin
        for i in v'range loop
            if v(i) = '1' then
                return true;
            end if;
        end loop;
        return false;
    end function;

    constant HOLDB    : std_logic := slBool(STROBE_HOLD);
    constant RDTHRU_N : std_logic_vector(0 to NWORDS-1) := normBits(RDTHRU);
    constant WIDEWR_N : std_logic_vector(0 to NWORDS-1) := normBits(WIDEWR);
    constant FULLWR_N : std_logic_vector(0 to NWORDS-1) := normBits(FULLWR);

    -- The table generics are unconstrained, so the actual decides their index
    -- range. Normalise to 0 .. NWORDS-1 once, here, rather than writing
    -- T'low + i at every use and getting one of them wrong.
    function norm(t : word_array) return word_array is
        variable r : word_array(0 to t'length - 1);
    begin
        for i in r'range loop
            r(i) := t(t'low + i);
        end loop;
        return r;
    end function;

    -- RSTVAL_OR is optional, so it is normalised to all-zero unless it carries a
    -- row per word: `norm` would raise on a length mismatch, and the point of the
    -- default is that a block that does not need it says nothing.
    function normOpt(t : word_array) return word_array is
        variable r : word_array(0 to NWORDS - 1) := (others => (others => '0'));
    begin
        if t'length = NWORDS then
            for i in r'range loop
                r(i) := t(t'low + i);
            end loop;
        end if;
        return r;
    end function;

    constant RSTOR_N : word_array(0 to NWORDS-1) := normOpt(RSTVAL_OR);
    constant ALIAS_N : word_array(0 to NWORDS-1) := normOpt(HWALIAS);
    constant RST_N   : word_array(0 to NWORDS-1) := norm(RSTVAL);
    constant IMPL_N  : word_array(0 to NWORDS-1) := norm(IMPL);
    constant W1C_N   : word_array(0 to NWORDS-1) := norm(W1C);
    constant WOSET_N : word_array(0 to NWORDS-1) := norm(WOSET);
    constant WOT_N   : word_array(0 to NWORDS-1) := norm(WOT);
    constant PULSE_N : word_array(0 to NWORDS-1) := norm(PULSE);
    constant RCLR_N  : word_array(0 to NWORDS-1) := norm(RCLR);
    constant HWOWN_N : word_array(0 to NWORDS-1) := norm(HWOWN);

    -- The reset the flops actually take.
    function rstEff return word_array is
        variable r : word_array(0 to NWORDS-1);
    begin
        for i in r'range loop
            r(i) := RST_N(i) or RSTOR_N(i);
        end loop;
        return r;
    end function;

    constant RST_EFF : word_array(0 to NWORDS-1) := rstEff;

    -- The bits a hook may drive: software storage, owned by hardware or aliased
    -- from another word. Everything else gets no hook logic and asserts.
    function hookMask return word_array is
        variable r : word_array(0 to NWORDS-1);
    begin
        for i in r'range loop
            r(i) := IMPL_N(i) and (HWOWN_N(i) or ALIAS_N(i));
        end loop;
        return r;
    end function;

    constant HOOK_N : word_array(0 to NWORDS-1) := hookMask;

    -- Every bit any write-1 arm can act on, over all words. The written pattern
    -- is registered ONCE, masked to this, and the per-word arms are cut out of it
    -- combinationally. Registering a full 32-bit strobe word per arm per word
    -- instead would be NWORDS*4*32 flops of which a handful are ever non-zero,
    -- and no synthesiser is obliged to prove the rest are constant.
    function actAny return word is
        variable r : word := (others => '0');
    begin
        for i in 0 to NWORDS-1 loop
            r := r or W1C_N(i) or WOSET_N(i) or WOT_N(i) or PULSE_N(i);
        end loop;
        return r;
    end function;

    constant ACT_ANY : word := actAny;

    -- Decoded word slot, held at WORD_BASE while deselected: an idle read
    -- register therefore holds word 0, which is what every hand-written decode
    -- in the tree does.
    signal slot     : natural range 0 to 63;
    signal sel_hit  : std_logic_vector(0 to NWORDS-1);   -- selected and addressed
    signal wr_hit   : std_logic_vector(0 to NWORDS-1);   -- ... with a lane enabled
    signal rd_hit   : std_logic_vector(0 to NWORDS-1);   -- ... with WEn = "1111"
    signal lane_en  : word;                              -- per-bit lane enable
    signal any_lane : std_logic;                         -- at least one lane enabled
    signal all_lane : std_logic;                         -- all four enabled, WEn = "0000"
    signal rd_comb  : word;                              -- the read mux, before the flop

    signal stored     : word_array(0 to NWORDS-1);
    signal wmask      : word_array(0 to NWORDS-1);   -- bits this access writes
    signal sw_nxt     : word_array(0 to NWORDS-1);   -- after the lane write
    signal we_m, set_m, clr_m : word_array(0 to NWORDS-1);
    signal nxt_w      : word_array(0 to NWORDS-1);   -- next state
    signal rdsrc      : word_array(0 to NWORDS-1);
    signal strobe_clr : std_logic;

    signal rd_q, wr_q : std_logic_vector(0 to NWORDS-1);
    signal sw1_q      : word;   -- the written-1 pattern, lane-gated, ACT_ANY-masked
    signal wr_any     : std_logic;

begin

    -- Elaboration contract: one row per word in every table.
    assert RSTVAL'length = NWORDS and IMPL'length = NWORDS and W1C'length = NWORDS
       and WOSET'length = NWORDS and WOT'length = NWORDS and PULSE'length = NWORDS
       and RCLR'length = NWORDS and HWOWN'length = NWORDS
        report "periph_regs: a table is not NWORDS rows long"
        severity failure;
    assert RDTHRU'length = 0 or RDTHRU'length = NWORDS
        report "periph_regs: RDTHRU must be the null vector or NWORDS bits"
        severity failure;
    assert WIDEWR'length = 0 or WIDEWR'length = NWORDS
        report "periph_regs: WIDEWR must be the null vector or NWORDS bits"
        severity failure;
    assert FULLWR'length = 0 or FULLWR'length = NWORDS
        report "periph_regs: FULLWR must be the null vector or NWORDS bits"
        severity failure;
    assert RSTVAL_OR'length = 0 or RSTVAL_OR'length = 1 or RSTVAL_OR'length = NWORDS
        report "periph_regs: RSTVAL_OR must be left at its default or carry NWORDS rows"
        severity failure;
    assert HWALIAS'length = 0 or HWALIAS'length = 1 or HWALIAS'length = NWORDS
        report "periph_regs: HWALIAS must be left at its default or carry NWORDS rows"
        severity failure;
    assert WORD_BASE + NWORDS <= 64
        report "periph_regs: the window runs past the 64-word peripheral slot"
        severity failure;
    ovrchk: for i in 0 to NWORDS-1 generate
        assert (RSTOR_N(i) and not IMPL_N(i)) = ZERO32
            report "periph_regs: RSTVAL_OR sets a bit outside IMPL, which holds no "
                 & "software flop; the generic reset would not be readable"
            severity failure;
    end generate;

    ------------------------------------------------------------------------
    -- Decode
    ------------------------------------------------------------------------
    slot <= slv2uint(MABPart) when EnMemPeriph = '0' else WORD_BASE;

    -- One lane reduction and one lane fan-out for the whole block. Written per
    -- word or per bit inside a generate they are correct and eight or thirty-two
    -- times over, because a netlist writer is under no obligation to notice.
    any_lane <= not (WEn(0) and WEn(1) and WEn(2) and WEn(3));
    all_lane <= not (WEn(0) or  WEn(1) or  WEn(2) or  WEn(3));

    lane_en(7 downto 0)   <= (others => not WEn(0));
    lane_en(15 downto 8)  <= (others => not WEn(1));
    lane_en(23 downto 16) <= (others => not WEn(2));
    lane_en(31 downto 24) <= (others => not WEn(3));

    -- A FULLWR word takes a write only from a four-lane access; a partial write
    -- to one is dropped whole, which is what `if wen = "0000"` says at SYSTEM's
    -- password slot. wr_inhibit refuses the write on top of that. Neither turns
    -- the access into a read: rd_hit still needs WEn = "1111".
    dec: for i in 0 to NWORDS-1 generate
        sel_hit(i) <= '1' when EnMemPeriph = '0' and slot = WORD_BASE + i else '0';
        wide: if FULLWR_N(i) = '0' generate
            wr_hit(i) <= sel_hit(i) and any_lane and not wr_inhibit(i);
        end generate wide;
        fullw: if FULLWR_N(i) = '1' generate
            wr_hit(i) <= sel_hit(i) and all_lane and not wr_inhibit(i);
        end generate fullw;
        rd_hit(i)  <= sel_hit(i) and not any_lane;
    end generate;

    ------------------------------------------------------------------------
    -- Read source. Storage for the IMPL bits of a word that is not RDTHRU;
    -- hw_rd for everything else, which is what makes a status register, a
    -- capture word or a FIFO head cost no flop here.
    ------------------------------------------------------------------------
    -- The three cases are separated by a CONSTANT, so a status word reads its
    -- hardware copy with no mask logic and a fully implemented word reads its
    -- storage with none either. Written as one expression it is correct and
    -- carries two 32-bit mask operations per word that fold to nothing.
    rdmux: for i in 0 to NWORDS-1 generate
        thru: if RDTHRU_N(i) = '1' or IMPL_N(i) = ZERO32 generate
            rdsrc(i) <= hw_rd(i);
        end generate thru;
        full: if RDTHRU_N(i) = '0' and IMPL_N(i) = ONES32 generate
            rdsrc(i) <= stored(i);
        end generate full;
        part: if RDTHRU_N(i) = '0' and IMPL_N(i) /= ZERO32
                                         and IMPL_N(i) /= ONES32 generate
            rdsrc(i) <= (stored(i) and IMPL_N(i)) or (hw_rd(i) and not IMPL_N(i));
        end generate part;
    end generate;

    -- One read mux, then either a flop on it or the bare mux. The registered arm
    -- is the flop every hand-written decode in the tree has; the combinational
    -- arm exists because I2C's read is combinational and MCU.vhd's bridge is the
    -- flop, and registering it here as well would land the data a cycle late.
    read_mux: process(slot, rdsrc)
    begin
        rd_comb <= (others => '0');
        for i in 0 to NWORDS-1 loop
            if slot = WORD_BASE + i then
                rd_comb <= rdsrc(i);
            end if;
        end loop;
    end process;

    rdreg: if REGISTERED_READ generate
        read_proc: process(ClkMem)
        begin
            if rising_edge(ClkMem) then
                rdata_out <= rd_comb;
            end if;
        end process;
    end generate rdreg;

    rdcomb: if not REGISTERED_READ generate
        rdata_out <= rd_comb;
    end generate rdcomb;

    ------------------------------------------------------------------------
    -- Storage. A bit outside IMPL is a CONSTANT, not a register loaded with a
    -- constant: the generate below gives it no process at all, because a
    -- synthesiser is not obliged to prove that a flop whose D is its reset value
    -- can be deleted, and GHDL does not. NWORDS*32 one-bit generates cost
    -- elaboration time and nothing else.
    -- Resolution order on a coincident access: lane write, hw_we, hw_set,
    -- hw_clr. Hardware beats the CPU, and clear beats set.
    ------------------------------------------------------------------------
    -- Next state, one vector expression per word, then ONE FLOP PER IMPLEMENTED
    -- BIT. Splitting it that way is deliberate on both counts: the logic stays
    -- vectorised, and a bit outside IMPL gets no process at all rather than a
    -- register whose D is its own reset value, which a synthesiser is not
    -- obliged to delete and ghdl --synth does not.
    -- Resolution order on a coincident access: lane write, hw_we, hw_set,
    -- hw_clr. Hardware beats the CPU, and clear beats set.
    nxt: for i in 0 to NWORDS-1 generate

        -- The bits this access writes: the enabled lanes, or all 32 on a WIDEWR word.
        gen_lane: if WIDEWR_N(i) = '0' generate
            wmask(i) <= lane_en when wr_hit(i) = '1' else ZERO32;
        end generate gen_lane;
        gen_wide: if WIDEWR_N(i) = '1' generate
            wmask(i) <= ONES32 when wr_hit(i) = '1' else ZERO32;
        end generate gen_wide;

        sw_nxt(i) <= (stored(i) and not wmask(i)) or (wdata and wmask(i));

        -- The hooks, masked to what the description says hardware may touch. A
        -- word no hook can reach gets none of this logic at all, rather than four
        -- 32-bit mask operations that every bit ties off.
        hooked: if HOOK_N(i) /= ZERO32 generate
            we_m(i)  <= hw_we(i)  and HOOK_N(i);
            set_m(i) <= hw_set(i) and HOOK_N(i);
            clr_m(i) <= hw_clr(i) and HOOK_N(i);
            nxt_w(i) <= ((((sw_nxt(i) and not we_m(i)) or (hw_wdata(i) and we_m(i)))
                          or set_m(i)) and not clr_m(i));
        end generate hooked;
        swonly: if HOOK_N(i) = ZERO32 generate
            nxt_w(i) <= sw_nxt(i);
        end generate swonly;

    end generate;

    store: for i in 0 to NWORDS-1 generate
        bits: for b in 0 to 31 generate

            held: if IMPL_N(i)(b) = '1' generate
                process(ClkMem, resetn)
                begin
                    if resetn = '0' then
                        stored(i)(b) <= RST_EFF(i)(b);
                    elsif rising_edge(ClkMem) then
                        stored(i)(b) <= nxt_w(i)(b);
                    end if;
                end process;
            end generate held;

            tied: if IMPL_N(i)(b) = '0' generate
                stored(i)(b) <= RST_EFF(i)(b);
            end generate tied;

        end generate bits;
    end generate store;

    regs <= stored;

    ------------------------------------------------------------------------
    -- Strobes. STROBE_HOLD = false retires them on the next ClkMem edge (one
    -- cycle, for a consumer clocked on ClkMem); true retires them
    -- asynchronously on deselect (for a level-sensitive consumer in another
    -- clock domain). See REGFILE.md; the two are not interchangeable.
    ------------------------------------------------------------------------
    strobe_clr <= '1' when resetn = '0' or (HOLDB = '1' and EnMemPeriph = '1') else '0';

    wr_any <= '0' when wr_hit = (wr_hit'range => '0') else '1';

    strobe_proc: process(ClkMem, strobe_clr)
    begin
        if strobe_clr = '1' then
            rd_q <= (others => '0');
            wr_q <= (others => '0');
        elsif rising_edge(ClkMem) then
            if HOLDB = '0' then
                rd_q <= (others => '0');
                wr_q <= (others => '0');
            end if;
            for i in 0 to NWORDS-1 loop
                if rd_hit(i) = '1' then rd_q(i) <= '1'; end if;
                if wr_hit(i) = '1' then wr_q(i) <= '1'; end if;
            end loop;
        end if;
    end process;

    -- The written-1 pattern, registered once for every bit any arm can act on
    -- and tied off for the rest, for the reason the storage generate above gives.
    act: for b in 0 to 31 generate

        live: if ACT_ANY(b) = '1' generate
            process(ClkMem, strobe_clr)
            begin
                if strobe_clr = '1' then
                    sw1_q(b) <= '0';
                elsif rising_edge(ClkMem) then
                    if HOLDB = '0' then
                        sw1_q(b) <= '0';
                    end if;
                    if wr_any = '1' then
                        sw1_q(b) <= lane_en(b) and wdata(b);
                    end if;
                end if;
            end process;
        end generate live;

        dead: if ACT_ANY(b) = '0' generate
            sw1_q(b) <= '0';
        end generate dead;

    end generate act;

    acc_hit   <= sel_hit;
    rd_strobe <= rd_q;
    wr_strobe <= wr_q;

    -- The arms, cut out of the one registered pattern. Exactly one word can be
    -- selected at a time, so wr_q / rd_q pick which row is live.
    -- A word with an empty mask is tied off rather than given a 32-bit mux, on
    -- the same argument as the storage and hook generates above: most words in
    -- most blocks arm nothing at all.
    arms: for i in 0 to NWORDS-1 generate

        p1: if PULSE_N(i) /= ZERO32 generate
            wr_pulse(i) <= (PULSE_N(i) and sw1_q) when wr_q(i) = '1' else ZERO32;
        end generate p1;
        p0: if PULSE_N(i) = ZERO32 generate wr_pulse(i) <= ZERO32; end generate p0;

        c1: if W1C_N(i) /= ZERO32 generate
            w1c_hit(i) <= (W1C_N(i) and sw1_q) when wr_q(i) = '1' else ZERO32;
        end generate c1;
        c0: if W1C_N(i) = ZERO32 generate w1c_hit(i) <= ZERO32; end generate c0;

        s1: if WOSET_N(i) /= ZERO32 generate
            woset_hit(i) <= (WOSET_N(i) and sw1_q) when wr_q(i) = '1' else ZERO32;
        end generate s1;
        s0: if WOSET_N(i) = ZERO32 generate woset_hit(i) <= ZERO32; end generate s0;

        t1: if WOT_N(i) /= ZERO32 generate
            wot_hit(i) <= (WOT_N(i) and sw1_q) when wr_q(i) = '1' else ZERO32;
        end generate t1;
        t0: if WOT_N(i) = ZERO32 generate wot_hit(i) <= ZERO32; end generate t0;

        r1: if RCLR_N(i) /= ZERO32 generate
            rd_clr(i) <= RCLR_N(i) when rd_q(i) = '1' else ZERO32;
        end generate r1;
        r0: if RCLR_N(i) = ZERO32 generate rd_clr(i) <= ZERO32; end generate r0;

    end generate;

    ------------------------------------------------------------------------
    -- A hardware hook outside IMPL and HWOWN would be dropped silently by the
    -- storage generate above; say so instead.
    --
    -- Fenced with translate_off, which nothing else in this tree uses yet and
    -- which is not decoration: a synthesiser drops the assert STATEMENT but
    -- still builds the logic that computes its condition, and ghdl --synth
    -- emitted 2488 nets of it before the fence went in. They drive nothing and
    -- would be swept, but they are not free to carry through every flow.
    ------------------------------------------------------------------------
    -- pragma translate_off
    hwchk: for i in 0 to NWORDS-1 generate
        assert not anyOne((hw_we(i) or hw_set(i) or hw_clr(i)) and not HOOK_N(i))
            report "periph_regs: a hardware hook drives a bit that is not "
                 & "software storage (IMPL) and is neither hardware owned (HWOWN) "
                 & "nor declared an alias (HWALIAS); the .rdl and the RTL disagree "
                 & "about who owns it"
            severity error;
    end generate;
    -- pragma translate_on

end architecture rtl;
