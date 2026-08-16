-------------------------------------------------------------------------------
-- ntag5_model.vhd
-------------------------------------------------------------------------------
-- Behavioral model of the NXP NTAG 5 dual-interface NFC tag, seen from its I2C SLAVE side only, with Castalia as the I2C master; the [L] and [B] citations below are the NTAG 5 link and boost product data sheets.
-- VARIANT picks NTP5332 (link) or NTA5332 (boost), which differ only on the RF side, so it changes no behavior here; the air interface is NOT modelled at all.
-- The rf_* inputs are a bench abstraction instead, letting a testbench say "a reader showed up and did X" in one signal edge.
-- Implemented: I2C slave framing, the 16-bit block addressing scheme, user EEPROM / config / session registers / SRAM, energy-harvest decode, the ED pin, SRAM pass-through, the I2C write lock and the datasheet NACK causes.
-- Not modelled: SCL stretching, I2C master mode, GPIO/PWM/WDT timeout, NFC-vs-I2C arbiter locking, SRAM mirror/PHDC/COPY, the 16-bit counter, standby, authentication, and real EEPROM programming time (EEPROM_PROG_TIME stands in).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ntag5_model is
    generic (
        -- "NTP5332" (NTAG 5 link) or "NTA5332" (NTAG 5 boost).
        -- See the header: nothing on the I2C side differs between them.
        VARIANT : string := "NTP5332";

        -- 7-bit slave address loaded into config block 103Eh byte 0 at POR.
        -- Datasheet default 54h = "1010100" ([L] Tab. 60, Tab. 229).
        I2C_ADDR : std_logic_vector(6 downto 0) := "1010100";

        -- EEPROM programming-cycle length: an ASSUMPTION, since the datasheet gives write endurance but no programming time, so tune it per bench.
        EEPROM_PROG_TIME : time := 500 us
    );
    port (
        -- resolved open-drain bus (the same nets the master drives)
        scl    : in std_logic;
        sda_in : in std_logic;

        -- This model's drive; '1' on *_oe = this model pulls that pin low, never high, because the bus is open drain and the testbench pulls the released level to a weak 'H'.
        -- Every sample here is normalized through to_X01, so a released 'H' reads as '1'.
        sda_out : out std_logic := '0';
        sda_oe  : out std_logic := '0';
        scl_out : out std_logic := '0';
        scl_oe  : out std_logic := '0';   -- never asserted: no clock stretch

        -- Event Detection pin, open drain, ACTIVE LOW.
        -- '1' = model pulls ED low = datasheet "ED pin state ON".
        ed_n_oe : out std_logic := '0';

        ---------------------------------------------------------------
        -- RF-side stimulus: A BENCH ABSTRACTION, NOT THE AIR INTERFACE
        ---------------------------------------------------------------
        rf_field       : in std_logic := '0';  -- an NFC field is present: drives NFC_FIELD_OK, the ED field-detect source and EH availability
        rf_power_ok    : in std_logic := '1';  -- the field is strong enough for the configured EH_VOUT_V_SEL/EH_VOUT_I_SEL level
        rf_write_sram  : in std_logic := '0';  -- rising edge = the reader wrote rf_sram_len bytes into the SRAM
        rf_read_sram   : in std_logic := '0';  -- rising edge = the reader read the SRAM buffer out
        rf_data        : in std_logic_vector(7 downto 0) := x"00";  -- seed byte for the rf_write_sram fill (seed, seed+1, ...)
        rf_sram_len    : in natural range 0 to 256 := 256;          -- how many bytes rf_write_sram fills
        rf_disable_i2c : in std_logic := '0';  -- the NFC side has set the DISABLE_I2C session bit, so I2C accesses NACK

        ---------------------------------------------------------------
        -- decoded energy-harvesting selections (for a supply model)
        ---------------------------------------------------------------
        eh_enabled    : out std_logic := '0';  -- EH_ENABLE (config or session)
        eh_vout_on    : out std_logic := '0';  -- VOUT actually driven
        eh_vout_mv    : out natural   := 1800; -- 1800 / 2400 / 3000 (0 = RFU code)
        eh_iout_ua    : out natural   := 400;  -- datasheet MINIMUM, microamps
        eh_vout_rfu_v : out std_logic := '0';  -- EH_VOUT_V_SEL = 11b (RFU)

        ---------------------------------------------------------------
        -- observation (for the testbench scoreboard)
        ---------------------------------------------------------------
        obs_variant_ok      : out std_logic := '0'; -- the VARIANT string was recognized
        obs_txn_count       : out natural   := 0;   -- completed START..STOP frames
        obs_addr_acked      : out std_logic := '0'; -- last address phase ACKed?
        obs_last_addr       : out std_logic_vector(6 downto 0) := (others => '0');
        obs_last_rnw        : out std_logic := '0';
        obs_last_block      : out natural   := 0;   -- last 16-bit block address
        obs_nack_count      : out natural   := 0;   -- data/address bytes NACKed
        obs_wbyte_count     : out natural   := 0;   -- data bytes accepted (last frame)
        obs_rbyte_count     : out natural   := 0;   -- data bytes sourced (last frame)
        obs_sram_data_ready : out std_logic := '0';
        obs_pt_dir          : out std_logic := '0'; -- 0 = I2C to NFC, 1 = NFC to I2C
        obs_eep_busy        : out std_logic := '0'
    );
end entity ntag5_model;

architecture behavioral of ntag5_model is

    -- ---- geometry: a block is 4 bytes and every access opens with a 16-bit block address, MSB first ----
    constant EEP_BYTES  : natural := 2048;              -- blocks 0000h..01FFh
    constant CFG_BLOCKS : natural := 160;               -- blocks 1000h..109Fh
    constant REG_BLOCKS : natural := 16;                -- blocks 10A0h..10AFh
    constant SRAM_BYTES : natural := 256;               -- blocks 2000h..203Fh

    constant BLK_USER_LAST_RW : natural := 16#01FE#;    -- 01FFh = counter
    constant BLK_COUNTER      : natural := 16#01FF#;
    constant BLK_CFG_BASE     : natural := 16#1000#;
    constant BLK_CFG_LAST     : natural := 16#109F#;
    constant BLK_REG_BASE     : natural := 16#10A0#;
    constant BLK_REG_LAST     : natural := 16#10AF#;
    constant BLK_SRAM_BASE    : natural := 16#2000#;
    constant BLK_SRAM_TERM    : natural := 16#203F#;    -- terminator block

    -- config-block offsets used by the POR copy / decode (block - 1000h)
    constant CFO_CONFIG   : natural := 16#37#;   -- CONFIG_0/1/2
    constant CFO_SYNC     : natural := 16#38#;
    constant CFO_PWMGPIO  : natural := 16#39#;
    constant CFO_PWM0     : natural := 16#3A#;
    constant CFO_PWM1     : natural := 16#3B#;
    constant CFO_WDT      : natural := 16#3C#;
    constant CFO_EHED     : natural := 16#3D#;   -- byte0 EH_CONFIG, byte2 ED_CONFIG
    constant CFO_I2CSLV   : natural := 16#3E#;   -- byte0 addr, byte1 config
    constant CFO_LOCK_BL  : natural := 16#8A#;   -- I2C_LOCK_BLOCK, 8 blocks

    -- session register block indices (block - 10A0h)
    constant RGO_STATUS : natural := 0;
    constant RGO_CONFIG : natural := 1;
    constant RGO_SYNC   : natural := 2;
    constant RGO_PWMGP  : natural := 3;
    constant RGO_PWM0   : natural := 4;
    constant RGO_PWM1   : natural := 5;
    constant RGO_WDT    : natural := 6;
    constant RGO_EH     : natural := 7;
    constant RGO_ED     : natural := 8;
    constant RGO_I2CSLV : natural := 9;
    constant RGO_RESET  : natural := 10;
    constant RGO_EDCLR  : natural := 11;

    type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);

    ---------------------------------------------------------------------
    -- Per-byte I2C WRITE masks for the session registers ([L] Tab. 87, 88, 90, 91, 92, 97, 99, 100 access columns).
    -- A '1' means the I2C side may change that bit; a '0' means the datasheet marks it R from I2C, so a host write to it is silently dropped.
    --   index = (block - 10A0h)*4 + REGA
    ---------------------------------------------------------------------
    constant REG_I2C_WMASK : byte_arr_t(0 to REG_BLOCKS*4 - 1) := (
        --  A0h STATUS0: EEPROM_WR_ERROR(6), SYNCH_BLOCK_WRITE(4), _READ(3)
         0 => x"58",
        --  A0h STATUS1: I2C_IF_LOCKED(1)
         1 => x"02",
        --  A1h CONFIG_0_REG: DISABLE_NFC(5), AUTO_STANDBY_MODE_EN(0)
         4 => x"21",
        --  A1h CONFIG_1_REG: ARBITER_MODE(3:2), PT_TRANSFER_DIR(0)
         5 => x"0D",
        --  A1h CONFIG_2_REG: all read-only from I2C
         6 => x"00",
        --  A2h SYNC_DATA_BLOCK_REG bytes 0..2: R/W from both interfaces
         8 => x"FF",  9 => x"FF", 10 => x"FF",
        --  A3h PWM_GPIO_CONFIG_REG bytes 0..2
        12 => x"FF", 13 => x"FF", 14 => x"FF",
        --  A4h/A5h PWM duty registers
        16 => x"FF", 17 => x"FF", 18 => x"FF", 19 => x"FF",
        20 => x"FF", 21 => x"FF", 22 => x"FF", 23 => x"FF",
        --  A6h WDT_CONFIG_REG bytes 0..2
        24 => x"FF", 25 => x"FF", 26 => x"FF",
        --  A7h EH_CONFIG_REG: R from I2C in EVERY bit ([L] Tab. 97)
        28 => x"00",
        --  A8h ED_CONFIG_REG: source nibble only, 7:4 are RFU
        32 => x"0F",
        --  A9h I2C_SLAVE_ADDR_REG: R from I2C
        36 => x"00",
        --  A9h I2C_SLAVE_CONFIG_REG: I2C_SOFT_RESET(3), I2C_S_REPEATED_START(2)
        37 => x"0C",
        --  AAh RESET_GEN_REG
        40 => x"FF",
        --  ABh ED_INTR_CLEAR_REG: ED_INTR_CLEAR(0)
        44 => x"01",
        --  ACh I2C master address / length registers
        48 => x"FF", 49 => x"FF",
        --  ADh I2C_M_STATUS_REG: "no write access to these registers"
        52 => x"00",
        others => x"00");

    ---------------------------------------------------------------------
    -- Delivery content of the user EEPROM ([L] Tab. 7 / [B] Tab. 6): the NFC Forum capability container plus the www.nxp.com/nfc NDEF message.
    -- DEVIATION for determinism: the rest of EEPROM and all of SRAM start at 00h, where the real part delivers random EEPROM and uninitialised SRAM.
    ---------------------------------------------------------------------
    function eep_init return byte_arr_t is
        variable e : byte_arr_t(0 to EEP_BYTES - 1) := (others => x"00");
    begin
        --        blk 00h: E1 40 80 09   (capability container)
        e(0)  := x"E1"; e(1)  := x"40"; e(2)  := x"80"; e(3)  := x"09";
        --        blk 01h: 03 10 D1 01
        e(4)  := x"03"; e(5)  := x"10"; e(6)  := x"D1"; e(7)  := x"01";
        --        blk 02h: 0C 55 01 6E
        e(8)  := x"0C"; e(9)  := x"55"; e(10) := x"01"; e(11) := x"6E";
        --        blk 03h: 78 70 2E 63
        e(12) := x"78"; e(13) := x"70"; e(14) := x"2E"; e(15) := x"63";
        --        blk 04h: 6F 6D 2F 6E
        e(16) := x"6F"; e(17) := x"6D"; e(18) := x"2F"; e(19) := x"6E";
        --        blk 05h: 66 63 FE 00
        e(20) := x"66"; e(21) := x"63"; e(22) := x"FE"; e(23) := x"00";
        return e;
    end function;

    ---------------------------------------------------------------------
    -- Configuration-memory reset content.
    -- Only the bytes this model interprets are given non-zero defaults; the rest are 00h.
    ---------------------------------------------------------------------
    function cfg_init return byte_arr_t is
        variable c : byte_arr_t(0 to CFG_BLOCKS*4 - 1) := (others => x"00");
    begin
        -- CONFIG_0 ([L] Tab. 37): EH_MODE = 10b "optimized for low field strength" is the stated default, so bits 3:2 = 10, giving 08h.
        c(CFO_CONFIG*4 + 0) := x"08";
        -- CONFIG_1 ([L] Tab. 38): all defaults are 0 (I2C slave, normal arbiter mode, SRAM disabled, PT direction I2C to NFC).
        c(CFO_CONFIG*4 + 1) := x"00";
        -- CONFIG_2 ([L] Tab. 39): EXTENDED_COMMANDS_SUPPORTED, LOCK_BLOCK_COMMAND_SUPPORTED and both slew-rate bits default to 1.
        -- NOTE: the GPIOx_IN default is self-contradictory in the datasheet (both 00b and 11b are marked "(Default)"), and GPIO is not modelled, so the upper nibble is left 0.
        c(CFO_CONFIG*4 + 2) := x"0F";
        -- WDT_ENABLE ([L] Tab. 51): default 1b = watchdog enabled.
        c(CFO_WDT*4 + 2) := x"01";
        -- EH_CONFIG / ED_CONFIG ([L] Tab. 53 / Tab. 56): all defaults are 0 (>0.4 mA, power check on, 1.8 V, EH disabled, ED disabled).
        c(CFO_EHED*4 + 0) := x"00";
        c(CFO_EHED*4 + 2) := x"00";
        -- I2C_SLAVE_ADDR ([L] Tab. 60), bit 7 RFU.
        c(CFO_I2CSLV*4 + 0) := '0' & I2C_ADDR;
        c(CFO_I2CSLV*4 + 1) := x"00";
        return c;
    end function;

    ---------------------------------------------------------------------
    -- POR copy of the configuration into the session registers ([L] 8.1.4: "After POR, the content of the configuration settings is loaded into the session register").
    -- The block pairing is from [L] Tab. 11 vs Tab. 85.
    ---------------------------------------------------------------------
    function reg_init(c : byte_arr_t) return byte_arr_t is
        variable r : byte_arr_t(0 to REG_BLOCKS*4 - 1) := (others => x"00");
    begin
        for i in 0 to 2 loop
            r(RGO_CONFIG*4 + i) := c(CFO_CONFIG*4  + i);   -- A1h from 1037h
            r(RGO_SYNC*4   + i) := c(CFO_SYNC*4    + i);   -- A2h from 1038h
            r(RGO_PWMGP*4  + i) := c(CFO_PWMGPIO*4 + i);   -- A3h from 1039h
            r(RGO_WDT*4    + i) := c(CFO_WDT*4     + i);   -- A6h from 103Ch
        end loop;
        for i in 0 to 3 loop
            r(RGO_PWM0*4 + i) := c(CFO_PWM0*4 + i);        -- A4h from 103Ah
            r(RGO_PWM1*4 + i) := c(CFO_PWM1*4 + i);        -- A5h from 103Bh
        end loop;
        r(RGO_ED*4     + 0) := c(CFO_EHED*4   + 2);        -- A8h from ED_CONFIG
        r(RGO_I2CSLV*4 + 0) := c(CFO_I2CSLV*4 + 0);        -- A9h from the slave address
        r(RGO_I2CSLV*4 + 1) := c(CFO_I2CSLV*4 + 1);        -- A9h from the slave config
        return r;
    end function;

    -- RFU-only configuration blocks ([L] Tab. 11); writes to them are NACKed.
    -- PARTIAL: only the ranges visible in the extracted table are encoded.
    function cfg_block_is_rfu(blk : natural) return boolean is
    begin
        if blk = 16#100A# or blk = 16#100B# or blk = 16#100F# then
            return true;
        elsif blk >= 16#1018# and blk <= 16#101F# then
            return true;
        elsif blk >= 16#1040# and blk <= 16#1044# then
            return true;
        elsif blk >= 16#1059# and blk <= 16#1069# then
            return true;
        elsif blk >= 16#109A# and blk <= 16#109F# then
            return true;
        end if;
        return false;
    end function;

    -- boolean to std_logic, for driving the observation outputs.
    function to_sl(cond : boolean) return std_logic is
    begin
        if cond then return '1'; else return '0'; end if;
    end function;

    -- True only for the two ordering codes this model claims to cover.
    function variant_known(v : string) return boolean is
    begin
        if v'length /= 7 then
            return false;
        end if;
        return v = "NTP5332" or v = "NTA5332";
    end function;

    -- EEPROM programming-cycle flag: a signal, so the process can schedule its own clear with an `after`.
    signal eep_busy : std_logic := '0';

begin

    -- No clock stretching: scl_out/scl_oe exist only to keep the house open-drain port shape and stay released.
    scl_out <= '0';
    scl_oe  <= '0';
    sda_out <= '0';          -- open drain: the model only ever pulls low

    obs_variant_ok <= to_sl(variant_known(VARIANT));
    obs_eep_busy   <= eep_busy;

    assert variant_known(VARIANT)
        report "ntag5_model: unknown VARIANT """ & VARIANT &
               """ (expected NTP5332 or NTA5332); I2C behavior is identical " &
               "for both, so the model still runs."
        severity warning;

    ---------------------------------------------------------------------
    -- One process owns the bus FSM, all four memories, the RF stimulus reactions and every derived output.
    -- Memories live in process variables; the derived outputs (ED pin, EH decode, observation) are recomputed unconditionally at the BOTTOM of every activation.
    ---------------------------------------------------------------------
    slave : process (scl, sda_in, rf_field, rf_power_ok,
                     rf_write_sram, rf_read_sram, rf_disable_i2c)

        -- ---- memories --------------------------------------------------
        variable eep  : byte_arr_t(0 to EEP_BYTES - 1)      := eep_init;
        variable cfg  : byte_arr_t(0 to CFG_BLOCKS*4 - 1)   := cfg_init;
        variable regs : byte_arr_t(0 to REG_BLOCKS*4 - 1)   := reg_init(cfg_init);
        variable sram : byte_arr_t(0 to SRAM_BYTES - 1)     := (others => x"00");

        -- ---- bus framing -----------------------------------------------
        variable active     : boolean := false;
        variable edge       : natural := 0;   -- SCL rising edges since START/Sr
        variable shift      : std_logic_vector(7 downto 0) := (others => '0');
        variable is_read    : boolean := false;
        variable addr_ok    : boolean := false;
        variable read_done  : boolean := false;   -- host NACKed: release
        variable frame_dead : boolean := false;   -- we NACKed: stay silent

        -- ---- addressing state, which PERSISTS across STOP so a read frame can use the pointer a preceding write frame set ----
        variable ptr_valid : boolean := false;
        variable ptr_blk   : natural := 0;
        variable ptr_byt   : natural := 0;
        variable is_reg    : boolean := false;
        variable reg_rega  : natural := 0;
        variable reg_mask  : std_logic_vector(7 downto 0) := x"00";

        -- ---- EEPROM/config write staging (committed at STOP) ------------
        variable stg      : byte_arr_t(0 to 3) := (others => x"00");
        variable stg_blk  : natural := 0;
        variable stg_pend : boolean := false;

        -- ---- device state ----------------------------------------------
        variable eep_err  : std_logic := '0';   -- EEPROM_WR_ERROR
        variable sram_rdy : std_logic := '0';   -- SRAM_DATA_READY
        variable ed_i2c   : std_logic := '0';   -- ED source 3h latch
        variable ed_nfc   : std_logic := '0';   -- ED source 4h latch
        variable ed_swi   : std_logic := '0';   -- ED source Dh latch

        -- ---- observation counters --------------------------------------
        variable txn_v   : natural := 0;
        variable nack_v  : natural := 0;
        variable wcnt_v  : natural := 0;
        variable rcnt_v  : natural := 0;

        -- ---- scratch ----------------------------------------------------
        variable g, bp, n, d : natural;
        variable blk_v, idx  : natural;
        variable rd_v        : std_logic_vector(7 downto 0) := x"FF";
        variable ack_v       : boolean;
        variable ehb         : std_logic_vector(7 downto 0);
        variable cfg1        : std_logic_vector(7 downto 0);
        variable st0, st1    : std_logic_vector(7 downto 0);
        variable eh_en_v     : std_logic;
        variable ed_src      : natural;
        variable ed_on       : std_logic;
        variable lock_bit    : natural;
        variable lock_byte   : natural;
        variable wmask       : std_logic_vector(7 downto 0);
        variable oldb, newb  : std_logic_vector(7 downto 0);
        variable nfill       : natural;

        ---------------------------------------------------------------
        -- Read one byte of MEMORY space (not registers).
        -- A restricted or unmapped block, and SRAM while SRAM_ENABLE is 0, reads FFh ([L] 8.3.1.5); extending that rule to unmapped blocks is an ASSUMPTION.
        ---------------------------------------------------------------
        procedure mem_read(blk : in natural; byt : in natural;
                           val : out std_logic_vector(7 downto 0)) is
        begin
            if blk <= BLK_USER_LAST_RW then
                val := eep(blk*4 + byt);
            elsif blk = BLK_COUNTER then
                val := x"FF";                     -- not I2C accessible
            elsif blk >= BLK_CFG_BASE and blk <= BLK_CFG_LAST then
                val := cfg((blk - BLK_CFG_BASE)*4 + byt);
            elsif blk >= BLK_SRAM_BASE and blk <= BLK_SRAM_TERM then
                if regs(RGO_CONFIG*4 + 1)(1) = '1' then    -- SRAM_ENABLE
                    val := sram((blk - BLK_SRAM_BASE)*4 + byt);
                else
                    val := x"FF";
                end if;
            else
                val := x"FF";                     -- unmapped
            end if;
        end procedure;

    begin
        -------------------------------------------------------------------
        -- RF-SIDE BENCH STIMULUS, not the air interface
        -------------------------------------------------------------------
        if rf_write_sram'event and to_X01(rf_write_sram) = '1' then
            -- "a reader wrote the SRAM buffer"
            nfill := rf_sram_len;
            if nfill > SRAM_BYTES then
                nfill := SRAM_BYTES;
            end if;
            for i in 0 to SRAM_BYTES - 1 loop
                if i < nfill then
                    sram(i) := std_logic_vector(unsigned(rf_data) +
                                                to_unsigned(i mod 256, 8));
                end if;
            end loop;
            if regs(RGO_CONFIG*4 + 1)(0) = '1' then   -- PT dir = NFC to I2C
                sram_rdy := '1';
                ed_nfc   := '1';                      -- ED source 4h asserts
            end if;
        end if;

        if rf_read_sram'event and to_X01(rf_read_sram) = '1' then
            -- "a reader read the SRAM buffer out"
            if regs(RGO_CONFIG*4 + 1)(0) = '0' then   -- PT dir = I2C to NFC
                sram_rdy := '0';
                ed_i2c   := '1';   -- "last byte read via NFC; host can access SRAM again" ([L] Tab. 56, source 3h)
            end if;
        end if;

        if rf_field'event and to_X01(rf_field) = '0' then
            -- "NFC off" clears both pass-through ED sources ([L] Tab. 56)
            ed_i2c := '0';
            ed_nfc := '0';
        end if;

        -------------------------------------------------------------------
        -- I2C BUS FSM.
        -- Two frame shapes, chosen purely from the captured block address: memory write = SL_AD+W BL_AD1 BL_AD0 then one 4-byte block (SRAM takes multiples of 4); register write (block 10A0h..10AFh) inserts REGA and a MASK byte before the single REGDAT byte.
        -- A read is addressed by such a write frame without data, then repeated-START SL_AD+R; memory reads auto-increment until the host NACKs, a register read returns the one REGDAT byte.
        -------------------------------------------------------------------
        if sda_in'event and to_X01(scl) = '1' then
            ------------------------------------------------------------
            -- START / repeated-START / STOP: SDA moves while SCL is high
            ------------------------------------------------------------
            if to_X01(sda_in) = '0' then
                -- START or repeated-START.
                -- I2C_S_REPEATED_START ([L] Tab. 100 bit 2): when set, the slave "resets internal state machine on repeated start".
                -- ASSUMPTION: modelled as invalidating the address pointer.
                if active and regs(RGO_I2CSLV*4 + 1)(2) = '1' then
                    ptr_valid := false;
                end if;
                edge       := 0;
                shift      := (others => '0');
                is_read    := false;
                addr_ok    := false;
                read_done  := false;
                frame_dead := false;
                active     := true;
                sda_oe <= '0';
            else
                -- STOP: commit any staged EEPROM/config block write.
                -- The datasheet ties the internal write cycle to the STOP ([L] 8.3.1.1.2).
                if active then
                    if stg_pend then
                        if stg_blk <= BLK_USER_LAST_RW then
                            for i in 0 to 3 loop
                                eep(stg_blk*4 + i) := stg(i);
                            end loop;
                        elsif stg_blk >= BLK_CFG_BASE and stg_blk <= BLK_CFG_LAST then
                            for i in 0 to 3 loop
                                idx := (stg_blk - BLK_CFG_BASE)*4 + i;
                                if stg_blk >= 16#108A# and stg_blk <= 16#1091#
                                   and i <= 1 then
                                    -- I2C_LOCK_BLOCK bytes are ONE-TIME PROGRAMMABLE ([L] 8.1.3.31): set only.
                                    cfg(idx) := cfg(idx) or stg(i);
                                else
                                    cfg(idx) := stg(i);
                                end if;
                            end loop;
                            -- The ED software-interrupt source is armed by writing Dh into ED_CONFIG ([L] Tab. 56, source Dh).
                            if stg_blk = BLK_CFG_BASE + CFO_EHED then
                                if stg(2)(3 downto 0) = "1101" then
                                    ed_swi := '1';
                                end if;
                            end if;
                        end if;
                        stg_pend := false;
                        eep_busy <= '1', '0' after EEPROM_PROG_TIME;
                    end if;
                    txn_v := txn_v + 1;
                    obs_txn_count   <= txn_v;
                    obs_wbyte_count <= wcnt_v;
                    obs_rbyte_count <= rcnt_v;
                end if;
                active := false;
                sda_oe <= '0';
            end if;

        elsif active and scl'event and to_X01(scl) = '1' then
            ------------------------------------------------------------
            -- SCL RISING edge: SAMPLE
            ------------------------------------------------------------
            g  := edge / 9;
            bp := edge mod 9;
            if bp < 8 then
                if g = 0 or (not is_read) then
                    shift := shift(6 downto 0) & to_X01(sda_in);
                end if;
            else
                if g > 0 and is_read then
                    -- host's ACK/NACK on a read byte
                    if to_X01(sda_in) = '1' then
                        read_done := true;   -- NACK ends the read
                    end if;
                end if;
            end if;
            edge := edge + 1;

        elsif active and scl'event and to_X01(scl) = '0' then
            ------------------------------------------------------------
            -- SCL FALLING edge: process the sampled bit, then set up this model's next drive.
            -- edge has already been incremented, so g/bp name the UPCOMING sample slot: the tb/i3c_target_model idiom.
            ------------------------------------------------------------
            g  := edge / 9;
            bp := edge mod 9;

            if read_done or frame_dead then
                sda_oe <= '0';                  -- silent for the rest of frame

            elsif g = 0 then
                if bp = 8 then
                    ------------------------------------------------------
                    -- address ACK slot
                    ------------------------------------------------------
                    is_read := (shift(0) = '1');
                    addr_ok := (shift(7 downto 1) = regs(RGO_I2CSLV*4 + 0)(6 downto 0));
                    obs_last_addr <= shift(7 downto 1);
                    obs_last_rnw  <= shift(0);
                    wcnt_v := 0;
                    rcnt_v := 0;
                    if addr_ok then
                        obs_addr_acked <= '1';
                        sda_oe <= '1';
                    else
                        -- "If the IC does not match the device select code, it deselects itself from the bus" ([L] 8.3.1.1.5)
                        obs_addr_acked <= '0';
                        nack_v := nack_v + 1;
                        obs_nack_count <= nack_v;
                        frame_dead := true;
                        sda_oe <= '0';
                    end if;
                else
                    sda_oe <= '0';              -- address bits: master drives
                end if;

            else
                n := g - 1;                     -- data-byte index in this frame

                if is_read then
                    ------------------------------------------------------
                    -- READ direction
                    ------------------------------------------------------
                    if bp = 0 then
                        -- fetch the byte we are about to shift out
                        if not ptr_valid then
                            rd_v := x"FF";
                        elsif is_reg then
                            -- REGISTER read: the datasheet's frame carries exactly one REGDAT byte.
                            -- ASSUMPTION: further reads without a new pointer repeat that byte.
                            idx := (ptr_blk - BLK_REG_BASE)*4 + reg_rega;
                            if ptr_blk = BLK_REG_BASE and reg_rega = 0 then
                                -- STATUS0_REG is computed live ([L] Tab. 87)
                                st0 := (others => '0');
                                st0(7) := eep_busy;
                                st0(6) := eep_err;
                                st0(5) := sram_rdy;
                                st0(4) := regs(RGO_STATUS*4 + 0)(4);
                                st0(3) := regs(RGO_STATUS*4 + 0)(3);
                                st0(2) := regs(RGO_CONFIG*4 + 1)(0);
                                st0(1) := '1';               -- VCC_SUPPLY_OK
                                st0(0) := to_X01(rf_field);  -- NFC_FIELD_OK
                                rd_v := st0;
                            elsif ptr_blk = BLK_REG_BASE and reg_rega = 1 then
                                -- STATUS1_REG ([L] Tab. 88)
                                st1 := (others => '0');
                                st1(7) := '1';               -- VCC_BOOT_OK
                                st1(6) := to_X01(rf_field);  -- NFC_BOOT_OK
                                st1(1) := regs(RGO_STATUS*4 + 1)(1);
                                rd_v := st1;
                            elsif ptr_blk = BLK_REG_BASE + RGO_EH and reg_rega = 0 then
                                -- EH_CONFIG_REG ([L] Tab. 97): EH_LOAD_OK (bit 7) reads rf_field AND rf_power_ok while EH_ENABLE is 0, and clears once EH is enabled.
                                -- ASSUMPTION: the real part wants an EH_TRIGGER write first, and that is NFC-only, so this model reports EH_LOAD_OK untriggered.
                                ehb := (others => '0');
                                ehb(0) := regs(RGO_EH*4 + 0)(0);   -- EH_ENABLE
                                if ehb(0) = '0' then
                                    ehb(7) := to_X01(rf_field) and to_X01(rf_power_ok);
                                end if;
                                rd_v := ehb;
                            else
                                rd_v := regs(idx);
                            end if;
                        else
                            mem_read(ptr_blk, ptr_byt, rd_v);
                            -- MEMORY reads auto-increment and "respond until host's NACK" ([L] 8.3.1.4)
                            if ptr_byt = 3 then
                                ptr_byt := 0;
                                ptr_blk := ptr_blk + 1;
                            else
                                ptr_byt := ptr_byt + 1;
                            end if;
                            -- Pass-through consume: the I2C host reading the terminator block clears SRAM_DATA_READY.
                            -- ASSUMPTION, since the datasheet defers the handshake to an application note: block 203Fh is the terminator, and whichever side fills the buffer sets the flag while the other side's read of it clears it.
                            if ptr_blk = BLK_SRAM_TERM + 1 and ptr_byt = 0
                               and regs(RGO_CONFIG*4 + 1)(0) = '1' then
                                sram_rdy := '0';
                                ed_nfc   := '0';
                            end if;
                        end if;
                        rcnt_v := rcnt_v + 1;
                        sda_oe  <= not rd_v(7);
                    elsif bp < 8 then
                        sda_oe  <= not rd_v(7 - bp);
                    else
                        sda_oe <= '0';          -- ACK slot: master drives
                    end if;

                else
                    ------------------------------------------------------
                    -- WRITE direction (master to model)
                    ------------------------------------------------------
                    if bp /= 8 then
                        sda_oe <= '0';          -- data bits: master drives
                    else
                        ack_v := true;

                        if n = 0 then
                            -- BL_AD1 (MSB of the 16-bit block address)
                            ptr_blk := to_integer(unsigned(shift)) * 256;

                        elsif n = 1 then
                            -- BL_AD0 (LSB): the whole block address is known now
                            blk_v   := ptr_blk + to_integer(unsigned(shift));
                            ptr_blk := blk_v;
                            ptr_byt := 0;
                            is_reg  := (blk_v >= BLK_REG_BASE and blk_v <= BLK_REG_LAST);
                            ptr_valid := true;
                            obs_last_block <= blk_v;
                            -- NACK causes on BL_AD0 ([L] 8.3.1.5)
                            if to_X01(rf_disable_i2c) = '1' then
                                ack_v := false;                 -- I2C disabled
                            elsif (not is_reg) and eep_busy = '1' then
                                ack_v := false;                 -- EEP cycle on
                            end if;

                        elsif is_reg then
                            ----------------------------------------------
                            -- REGISTER write frame: REGA, MASK, REGDAT
                            ----------------------------------------------
                            if n = 2 then
                                reg_rega := to_integer(unsigned(shift(1 downto 0)));
                            elsif n = 3 then
                                reg_mask := shift;
                            elsif n = 4 then
                                idx   := (ptr_blk - BLK_REG_BASE)*4 + reg_rega;
                                wmask := reg_mask and REG_I2C_WMASK(idx);
                                oldb  := regs(idx);
                                newb  := (oldb and (not wmask)) or (shift and wmask);
                                if ptr_blk = BLK_REG_BASE + RGO_RESET
                                   and reg_rega = 0 and shift = x"E7" then
                                    -- System reset ([L] Tab. 101): DATA NACK ([L] 8.3.1.5), then redo the POR copy.
                                    ack_v    := false;
                                    regs     := reg_init(cfg);
                                    ed_i2c   := '0';
                                    ed_nfc   := '0';
                                    ed_swi   := '0';
                                    sram_rdy := '0';
                                    eep_err  := '0';
                                    ptr_valid := false;
                                else
                                    regs(idx) := newb;
                                    -- side effects
                                    if ptr_blk = BLK_REG_BASE + RGO_EDCLR
                                       and reg_rega = 0 and newb(0) = '1' then
                                        -- "write 1b to release ED pin", and the bit self-clears ([L] Tab. 58)
                                        ed_i2c := '0';
                                        ed_nfc := '0';
                                        ed_swi := '0';
                                        regs(idx)(0) := '0';
                                    end if;
                                    if ptr_blk = BLK_REG_BASE + RGO_ED
                                       and reg_rega = 0
                                       and newb(3 downto 0) = "1101" then
                                        ed_swi := '1';   -- software interrupt
                                    end if;
                                    if ptr_blk = BLK_REG_BASE + RGO_I2CSLV
                                       and reg_rega = 1 and newb(3) = '1' then
                                        -- I2C_SOFT_RESET self-clears
                                        regs(idx)(3) := '0';
                                    end if;
                                end if;
                                wcnt_v := wcnt_v + 1;
                            else
                                ack_v := false;   -- extra bytes in a reg frame
                            end if;

                        else
                            ----------------------------------------------
                            -- MEMORY write frame: data bytes
                            ----------------------------------------------
                            d := n - 2;

                            if ptr_blk >= BLK_SRAM_BASE and ptr_blk <= BLK_SRAM_TERM then
                                -- SRAM: volatile, committed byte by byte.
                                -- NACK is "generated on the first byte if the block is not writable" ([L] 8.3.1.5).
                                if regs(RGO_CONFIG*4 + 1)(1) = '0' then
                                    ack_v := false;              -- SRAM disabled
                                elsif d >= SRAM_BYTES then
                                    ack_v := false;
                                else
                                    idx := (ptr_blk - BLK_SRAM_BASE)*4 + ptr_byt;
                                    sram(idx) := shift;
                                    if ptr_blk = BLK_SRAM_TERM and ptr_byt = 3
                                       and regs(RGO_CONFIG*4 + 1)(0) = '0' then
                                        -- I2C to NFC: writing the terminator block hands the buffer to the reader.
                                        sram_rdy := '1';
                                        ed_i2c   := '0';
                                    end if;
                                    if ptr_byt = 3 then
                                        ptr_byt := 0;
                                        ptr_blk := ptr_blk + 1;
                                    else
                                        ptr_byt := ptr_byt + 1;
                                    end if;
                                    wcnt_v := wcnt_v + 1;
                                end if;

                            elsif (ptr_blk <= BLK_USER_LAST_RW) or
                                  (ptr_blk >= BLK_CFG_BASE and ptr_blk <= BLK_CFG_LAST) then
                                -- EEPROM / configuration: exactly ONE 4-byte block per frame ("N shall be 3", [L] 8.3.1.4)
                                if d > 3 then
                                    ack_v := false;
                                else
                                    stg(d) := shift;
                                    if d = 3 then
                                        -- Writability is decided on the FOURTH data byte ([L] 8.3.1.5).
                                        -- Each I2C_LOCK_BLOCK bit locks FOUR user blocks, and the bits are one-time programmable.
                                        ack_v := true;
                                        if ptr_blk <= BLK_USER_LAST_RW then
                                            lock_bit  := ptr_blk / 4;
                                            lock_byte := lock_bit / 8;
                                            idx := (CFO_LOCK_BL + lock_byte/2)*4
                                                   + (lock_byte mod 2);
                                            if cfg(idx)(lock_bit mod 8) = '1' then
                                                ack_v   := false;   -- locked
                                                eep_err := '1';
                                            end if;
                                        elsif cfg_block_is_rfu(ptr_blk) then
                                            ack_v   := false;       -- RFU block
                                            eep_err := '1';
                                        end if;
                                        if ack_v then
                                            stg_blk  := ptr_blk;
                                            stg_pend := true;
                                        end if;
                                    end if;
                                    if ack_v then
                                        wcnt_v := wcnt_v + 1;
                                    end if;
                                end if;

                            else
                                -- Unmapped block; the datasheet enumerates NACK causes but not this one, so NACKing it is an ASSUMPTION.
                                ack_v := false;
                            end if;
                        end if;

                        if ack_v then
                            sda_oe <= '1';
                        else
                            sda_oe <= '0';
                            nack_v := nack_v + 1;
                            obs_nack_count <= nack_v;
                            frame_dead := true;
                        end if;
                    end if;
                end if;
            end if;
        end if;

        -------------------------------------------------------------------
        -- DERIVED OUTPUTS, recomputed on EVERY activation
        -------------------------------------------------------------------
        -- Energy harvesting: EH_CONFIG (config block 103Dh byte 0) is bit 0 EH_ENABLE, bits 2:1 EH_VOUT_V_SEL, bit 3 DISABLE_POWER_CHECK, bits 6:4 EH_VOUT_I_SEL ([L] Tab. 53).
        -- The V/I selections live ONLY in the config byte; the session register carries just EH_ENABLE/LOAD_OK.
        ehb  := cfg(CFO_EHED*4 + 0);
        cfg1 := regs(RGO_CONFIG*4 + 1);

        -- EH_VOUT_I_SEL: the codes are datasheet MINIMA ("> 0.4 mA"), and eh_iout_ua carries that minimum in microamps.
        case ehb(6 downto 4) is
            when "000"  => eh_iout_ua <= 400;
            when "001"  => eh_iout_ua <= 600;
            when "010"  => eh_iout_ua <= 1400;
            when "011"  => eh_iout_ua <= 2700;
            when "100"  => eh_iout_ua <= 4000;
            when "101"  => eh_iout_ua <= 6500;
            when "110"  => eh_iout_ua <= 9000;
            when others => eh_iout_ua <= 12500;
        end case;

        -- EH_VOUT_V_SEL: the harvested output voltage, in millivolts.
        -- The RFU code 11b drives 0 mV and eh_vout_rfu_v, an ASSUMPTION: the part's behavior for an RFU code is undefined.
        case ehb(2 downto 1) is
            when "00"   => eh_vout_mv <= 1800; eh_vout_rfu_v <= '0';
            when "01"   => eh_vout_mv <= 2400; eh_vout_rfu_v <= '0';
            when "10"   => eh_vout_mv <= 3000; eh_vout_rfu_v <= '0';
            when others => eh_vout_mv <= 0;    eh_vout_rfu_v <= '1';  -- RFU
        end case;

        eh_en_v := ehb(0) or regs(RGO_EH*4 + 0)(0);
        eh_enabled <= eh_en_v;
        if eh_en_v = '1' and to_X01(rf_field) = '1' and
           (ehb(3) = '1' or to_X01(rf_power_ok) = '1') then
            eh_vout_on <= '1';
        else
            eh_vout_on <= '0';
        end if;

        -- Event detection pin: open drain and ACTIVE LOW, so ed_n_oe = '1' pulls ED low, the datasheet's "ED pin state ON".
        -- Source is ED_CONFIG_REG(3:0), POR-copied from ED_CONFIG ([L] Tab. 56); every source not listed below is left unmodelled and releases the pin.
        ed_src := to_integer(unsigned(regs(RGO_ED*4 + 0)(3 downto 0)));
        case ed_src is
            when 1      => ed_on := to_X01(rf_field);              -- 1h NFC field detect
            when 3      => ed_on := ed_i2c and to_X01(rf_field);   -- 3h I2C-to-NFC pass-through: the reader has read the last SRAM byte
            when 4      => ed_on := ed_nfc and to_X01(rf_field);   -- 4h NFC-to-I2C pass-through: the reader wrote the last SRAM byte
            when 13     => ed_on := ed_swi;                        -- Dh software interrupt, cleared only via ED_INTR_CLEAR_REG
            when others => ed_on := '0';   -- disabled or source not modelled
        end case;
        ed_n_oe <= ed_on;

        obs_sram_data_ready <= sram_rdy;
        obs_pt_dir          <= cfg1(0);
    end process slave;

end architecture behavioral;
