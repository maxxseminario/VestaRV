-------------------------------------------------------------------------------
-- st25dv_model.vhd
-------------------------------------------------------------------------------
-- Behavioral model of the ST25DV64KC dynamic NFC tag (64-Kbit EEPROM, fast-transfer-mode mailbox, energy harvesting) as seen from its CONTACT side: the MCU is the I2C master, this model is the I2C slave.
-- Registers, factory values and protocol follow the ST25DV04/16/64KC datasheet DS13519; this is a firmware bring-up aid, not a sign-off model.
-- Implemented: the full I2C slave bit protocol, both memory device-select families (A6h/A7h user space, AEh/AFh system space) plus the RFSwitchOff/On pair, 8 KB user EEPROM behind the tW write cycle, the dynamic registers, the 256-byte FTM mailbox, GPO pulse sources, energy harvesting and the present/write password commands.
-- NOT implemented: the RF / ISO-IEC 15693 side (the rf_* ports are a bench abstraction meaning "a reader did that"), user-memory area and RF protection, the FTM watchdog, configuration locking, the CMOS GPO variant, and all analog / AC timing other than tW (SCL is never stretched and never timing-checked, hence no scl_oe port).
-- Bus convention: open drain, sda_out/gpo_out are tied '0' and only the _oe outputs toggle ('1' = this model pulls the line low); the bench resolves each shared wire with a weak 'H' and every sample is to_X01-normalized.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity st25dv_model is
    generic (
        -- EEPROM internal write time for ONE 16-byte row.
        T_W        : time := 5 ms;
        -- IC_REF 51h is the ST25DV64KC device value; the device leaves IC_REV undefined, so this is a placeholder.
        IC_REF_VAL : std_logic_vector(7 downto 0) := x"51";
        IC_REV_VAL : std_logic_vector(7 downto 0) := x"01"
    );
    port (
        -- ---- power / reset -------------------------------------------------
        resetn : in std_logic := '1';   -- POR, active low; the model boots instantly on the rising edge
        vcc_on : in std_logic := '1';   -- VCC present (EH_CTRL_Dyn.VCC_ON)

        -- ---- I2C slave, open drain (the TB resolves the shared nets) -------
        scl     : in  std_logic;
        sda_in  : in  std_logic;
        sda_out : out std_logic := '0';   -- tied '0'; only sda_oe toggles
        sda_oe  : out std_logic := '0';   -- '1' = this model pulls SDA low

        -- ---- GPO, open drain (8-pin package variant) ----------------------
        gpo_out : out std_logic := '0';   -- tied '0'
        gpo_oe  : out std_logic := '0';   -- '1' = this model pulls GPO low

        -- ---- V_EH energy harvesting ---------------------------------------
        -- eh_enabled = EH_CTRL_Dyn.EH_EN; veh_active = the pin is actually delivering (EH enabled AND an RF field present), '0' = High-Z.
        -- The device encodes no harvested level, so veh_avail_ua merely echoes the bench-supplied cfg_veh_ua while delivering: wire it from a board-level supply model, it is not a device register.
        eh_enabled   : out std_logic := '0';
        veh_active   : out std_logic := '0';
        veh_avail_ua : out natural   := 0;
        cfg_veh_ua   : in  natural   := 0;

        -- ---- RF-side stimulus: BENCH ABSTRACTION, NOT ISO/IEC 15693 --------
        -- rf_field is a level (carrier present, driving FIELD_ON, FIELD_CHANGE and EH delivery); the other three are rising-edge events: a reader wrote rf_put_len mailbox bytes (byte i = rf_put_seed + i), a reader emptied the mailbox (clears HOST_PUT_MSG), a reader completed an EEPROM write.
        -- rf_write_ee raises the RF_WRITE interrupt only: with no RF command set here, user memory is never changed from the RF side.
        rf_field    : in std_logic := '0';
        rf_put_msg  : in std_logic := '0';
        rf_put_len  : in natural   := 0;
        rf_put_seed : in std_logic_vector(7 downto 0) := x"00";
        rf_get_msg  : in std_logic := '0';
        rf_write_ee : in std_logic := '0';

        -- ---- observations (for the bench scoreboard; held until changed) ---
        obs_devsel      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_addr        : out natural   := 0;   -- internal address counter
        obs_txn_count   : out natural   := 0;   -- completed START..STOP frames
        obs_wcommit     : out natural   := 0;   -- committed write operations
        obs_devsel_nack : out natural   := 0;   -- device selects NACKed
        obs_busy        : out std_logic := '0'; -- internal write cycle running
        obs_it_sts      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_mb_ctrl     : out std_logic_vector(7 downto 0) := (others => '0');
        obs_mb_len      : out std_logic_vector(7 downto 0) := (others => '0');
        obs_i2c_sso     : out std_logic := '0';
        obs_rf_off      : out std_logic := '0'  -- last I2C RFSwitchOff/On state
    );
end entity st25dv_model;


architecture behavioral of st25dv_model is

    -- One byte store, used for user EEPROM, system registers, mailbox and the frame write buffer.
    type byte_mem_t is array (natural range <>) of std_logic_vector(7 downto 0);

    -- address-space landmarks
    constant A_USER_TOP : natural := 16#1FFF#;
    constant A_DYN_LO   : natural := 16#2000#;
    constant A_DYN_HI   : natural := 16#2007#;
    constant A_MB_LO    : natural := 16#2008#;
    constant A_MB_HI    : natural := 16#2107#;
    constant A_SYS_TOP  : natural := 16#0023#;
    constant A_SYS_RO   : natural := 16#0010#;   -- 0010h..0023h are read-only
    constant A_PWD      : natural := 16#0900#;

begin

    -- Open drain only: this model never drives either pin high.
    sda_out <= '0';
    gpo_out <= '0';

    -- The whole device: I2C slave protocol, memories, dynamic registers, mailbox, GPO and energy harvesting.
    dev : process (scl, sda_in, resetn, vcc_on,
                   rf_field, rf_put_msg, rf_get_msg, rf_write_ee, cfg_veh_ua)

        ------------------------------------------------------------------
        -- NONVOLATILE state (EEPROM; survives resetn)
        ------------------------------------------------------------------
        variable umem : byte_mem_t(0 to 8191) := (others => x"00");  -- user EEPROM, factory-initialized to 00h
        variable pwd  : byte_mem_t(0 to 7)    := (others => x"00");  -- factory password is all zeros

        -- System configuration area 0000h..0023h at its factory values; 0010h..0023h are read-only.
        variable sysr : byte_mem_t(0 to 35) := (
            16#00# => x"11",              -- GPO1   : GPO_EN + FIELD_CHANGE_EN
            16#01# => x"0C",              -- GPO2   : IT_TIME = 011b
            16#02# => x"01",              -- EH_MODE: 1 = EH on demand
            16#0E# => x"1A",              -- I2C_CFG: code 1010b, E0=1, RFSW off
            16#14# => x"FF",              -- MEM_SIZE LSB (07FFh = 2048 blocks)
            16#15# => x"07",              -- MEM_SIZE MSB
            16#16# => x"03",              -- BLK_SIZE
            16#17# => IC_REF_VAL,         -- IC_REF
            16#18# => x"11", 16#19# => x"22", 16#1A# => x"33",   -- UID 0..2, synthetic serial number
            16#1B# => x"44", 16#1C# => x"55",                     -- UID 3..4, synthetic serial number
            16#1D# => x"51", 16#1E# => x"02", 16#1F# => x"E0",    -- UID 5..7, the ST25DV64KC-IE values
            16#20# => IC_REV_VAL,         -- IC_REV (placeholder)
            others => x"00");

        ------------------------------------------------------------------
        -- VOLATILE state (dynamic registers + mailbox; reset at boot)
        ------------------------------------------------------------------
        variable mbox        : byte_mem_t(0 to 255) := (others => x"00");
        variable gpo_dyn_en  : std_logic := '1';   -- GPO_CTRL_Dyn b0, loaded from GPO1 b0
        variable eh_en       : std_logic := '0';   -- EH_MODE=01h ("on demand") boots with EH_EN=0
        variable rf_mngt_dyn : std_logic_vector(7 downto 0) := (others => '0');
        variable sso         : std_logic := '0';   -- I2C_SSO_Dyn b0
        variable it_sts      : std_logic_vector(7 downto 0) := (others => '0');
        variable mb_ctrl     : std_logic_vector(7 downto 0) := (others => '0');
        variable mb_len      : std_logic_vector(7 downto 0) := (others => '0');
        variable rf_off_v    : std_logic := '0';

        ------------------------------------------------------------------
        -- I2C frame state
        ------------------------------------------------------------------
        variable active    : boolean := false;   -- inside START..STOP
        variable edge      : natural := 0;       -- SCL rising edges since START/Sr
        variable shift     : std_logic_vector(7 downto 0) := (others => '0');
        variable dev_ok    : boolean := false;   -- device select matched (ACKed)
        variable rfsw      : boolean := false;   -- this frame is an RFSwitch cmd
        variable is_read   : boolean := false;
        variable e2v       : std_logic := '0';
        variable base_hi   : std_logic_vector(7 downto 0) := (others => '0');
        variable base_addr : natural := 0;
        variable addr_ctr  : natural := 0;
        variable wcnt      : natural := 0;       -- data bytes accepted this frame
        variable wbuf      : byte_mem_t(0 to 255) := (others => x"00");
        variable dead      : boolean := false;   -- a byte was inhibited: the whole write is dead
        variable rbyte     : std_logic_vector(7 downto 0) := (others => '0');
        variable rd_dead   : boolean := false;
        variable mb_end_rd : boolean := false;   -- last mailbox message byte read
        variable busy_to   : time    := 0 ns;    -- internal write cycle end time

        variable txn_v, wcommit_v, dsnack_v : natural := 0;

        -- scratch
        variable g, bp, kk, k : natural;
        variable ackit, okv   : boolean;

        ------------------------------------------------------------------
        -- helpers (declared AFTER the variables they read)
        ------------------------------------------------------------------

        -- GPO pulse width = 301 us - IT_TIME * 37.65 us, with IT_TIME = GPO2[4:2].
        impure function gpo_pulse_len return time is
        begin
            return 301 us - to_integer(unsigned(sysr(16#01#)(4 downto 2))) * 37650 ns;
        end function;

        -- Emit one GPO pulse if `src_en` (the per-source GPO1/GPO2 enable) is set AND the output is enabled.
        -- GPO_CTRL_Dyn.GPO_EN is the ONLY output gate, GPO1.GPO_EN alone cannot enable the pin, and overlapping sources re-trigger the pulse instead of merging.
        procedure gpo_pulse(src_en : in std_logic) is
        begin
            if src_en = '1' and gpo_dyn_en = '1' then
                gpo_oe <= '1', '0' after gpo_pulse_len;
            end if;
        end procedure;

        -- Read one byte at address `a` in space `e2`: a sequential read walks off user memory into the dynamic registers and mailbox, and anything above 2107h reads FFh.
        -- ok=false means an UNSUCCESSFUL read: the master sees FFh and the internal address counter freezes (I2C dead state).
        procedure rd_fetch(a  : in  natural;
                           e2 : in  std_logic;
                           d  : out std_logic_vector(7 downto 0);
                           ok : out boolean) is
        begin
            d  := x"FF";
            ok := false;
            if e2 = '1' then
                if a <= A_SYS_TOP then
                    d := sysr(a); ok := true;
                elsif a >= A_PWD and a <= A_PWD + 7 then
                    -- password bytes are readable only with the session open
                    if sso = '1' then
                        d := pwd(a - A_PWD); ok := true;
                    end if;
                end if;
            else
                if a <= A_USER_TOP then
                    d := umem(a); ok := true;
                elsif a = 16#2000# then                    -- GPO_CTRL_Dyn
                    d := "0000000" & gpo_dyn_en; ok := true;
                elsif a = 16#2001# then                    -- ST reserved
                    d := x"00"; ok := true;
                elsif a = 16#2002# then                    -- EH_CTRL_Dyn
                    d := "0000" & to_X01(vcc_on) & to_X01(rf_field) & eh_en & eh_en;
                    ok := true;
                elsif a = 16#2003# then                    -- RF_MNGT_Dyn
                    d := rf_mngt_dyn; ok := true;
                elsif a = 16#2004# then                    -- I2C_SSO_Dyn
                    d := "0000000" & sso; ok := true;
                elsif a = 16#2005# then                    -- IT_STS_Dyn
                    d := it_sts; ok := true;
                elsif a = 16#2006# then                    -- MB_CTRL_Dyn
                    d := mb_ctrl; ok := true;
                elsif a = 16#2007# then                    -- MB_LEN_Dyn
                    d := mb_len; ok := true;
                elsif a >= A_MB_LO and a <= A_MB_HI then   -- FTM mailbox
                    if mb_ctrl(0) = '1' then
                        ok := true;                        -- mailbox is enabled, so the read succeeds
                        if (a - A_MB_LO) <= to_integer(unsigned(mb_len)) then
                            d := mbox(a - A_MB_LO);
                        else
                            d := x"FF";                    -- past the message end, no rollover
                        end if;
                    end if;
                end if;
            end if;
        end procedure;

        -- Write inhibition for data byte index `k` of the current frame; ok=true means ACK.
        procedure wr_allowed(k : in natural; ok : out boolean) is
            variable aa : natural;
        begin
            ok := false;
            aa := base_addr + k;
            if e2v = '1' then
                if base_addr = A_PWD then
                    -- present / write password command: 17 data bytes, NotACKed while FTM is active
                    if mb_ctrl(0) = '1' then
                        ok := false;
                    elsif k < 17 then
                        ok := true;
                    end if;
                elsif base_addr <= A_SYS_TOP then
                    if k > 0 then                 ok := false;   -- one byte only
                    elsif sso = '0' then          ok := false;   -- session closed
                    elsif base_addr >= A_SYS_RO then ok := false; -- read-only register
                    else                          ok := true;
                    end if;
                end if;
            else
                if base_addr <= A_USER_TOP then
                    if mb_ctrl(0) = '1' then      ok := false;   -- FTM active
                    elsif k >= 256 then           ok := false;   -- 256-byte limit
                    elsif aa > A_USER_TOP then    ok := false;   -- no rollover
                    else                          ok := true;
                    end if;
                elsif base_addr >= A_DYN_LO and base_addr <= A_DYN_HI then
                    if k > 0 then                 ok := false;   -- not written in continuity
                    elsif base_addr = 16#2001# or base_addr = 16#2004# or
                          base_addr = 16#2005# or base_addr = 16#2007# then
                        ok := false;                             -- read-only dynamic register
                    else                          ok := true;
                    end if;
                elsif base_addr = A_MB_LO then
                    if mb_ctrl(0) = '0' then      ok := false;   -- FTM not activated
                    elsif mb_ctrl(1) = '1' or mb_ctrl(2) = '1' then
                        ok := false;                             -- mailbox busy
                    elsif aa > A_MB_HI then       ok := false;   -- mailbox border
                    else                          ok := true;
                    end if;
                end if;
                -- base_addr in 2009h..2107h: a mailbox write must start at 2008h, so ok stays false.
            end if;
        end procedure;

        -- Commit the accepted write bytes at the STOP condition.
        procedure commit_write is
            variable n, r0, r1, rows : natural;
            variable wt              : time;
            variable code            : std_logic_vector(7 downto 0);
            variable same            : boolean;
        begin
            n := wcnt;
            if dead or n = 0 then
                return;                                  -- one NACKed byte voids the frame: nothing is programmed
            end if;

            wt := 0 ns;

            if e2v = '1' and base_addr = A_PWD then
                ------------------------------------------------------------
                -- I2C present / write password
                ------------------------------------------------------------
                if n = 17 then
                    code := wbuf(8);
                    same := true;
                    for j in 0 to 7 loop
                        if wbuf(j) /= wbuf(9 + j) then same := false; end if;
                    end loop;
                    if same then
                        if code = x"09" then                  -- PRESENT
                            sso := '1';
                            for j in 0 to 7 loop
                                if wbuf(j) /= pwd(j) then sso := '0'; end if;
                            end loop;
                            -- a present is a comparison only: no write cycle, effective at the STOP
                        elsif code = x"07" then               -- WRITE password
                            if sso = '1' then
                                for j in 0 to 7 loop pwd(j) := wbuf(j); end loop;
                                wt := T_W;
                            end if;
                        end if;
                    end if;
                end if;

            elsif e2v = '1' then
                ------------------------------------------------------------
                -- system configuration EEPROM, single byte, session open
                ------------------------------------------------------------
                sysr(base_addr) := wbuf(0);
                wt := T_W;
                -- side effects of the static registers that have a dynamic image
                if base_addr = 16#00# then
                    gpo_dyn_en := wbuf(0)(0);            -- GPO1.GPO_EN is copied into GPO_CTRL_Dyn on every GPO1 write
                elsif base_addr = 16#02# then
                    if wbuf(0)(0) = '0' then eh_en := '1'; end if;  -- writing EH_MODE=0 forces EH_EN
                elsif base_addr = 16#0D# then
                    if wbuf(0)(0) = '0' then mb_ctrl(0) := '0'; end if; -- clearing FTM.MB_MODE drops MB_EN
                end if;

            elsif base_addr <= A_USER_TOP then
                ------------------------------------------------------------
                -- user EEPROM
                ------------------------------------------------------------
                for j in 0 to n - 1 loop
                    umem(base_addr + j) := wbuf(j);
                end loop;
                r0   := base_addr / 16;
                r1   := (base_addr + n - 1) / 16;
                rows := r1 - r0 + 1;                     -- 16-byte EEPROM rows touched; do not calibrate firmware timing against this
                wt   := rows * T_W;

            elsif base_addr >= A_DYN_LO and base_addr <= A_DYN_HI then
                ------------------------------------------------------------
                -- dynamic registers: immediate, single byte, no tW
                ------------------------------------------------------------
                if base_addr = 16#2000# then
                    gpo_dyn_en := wbuf(0)(0);
                elsif base_addr = 16#2002# then
                    eh_en := wbuf(0)(0);
                elsif base_addr = 16#2003# then
                    rf_mngt_dyn := wbuf(0);
                elsif base_addr = 16#2006# then
                    -- MB_EN can only be set while FTM.MB_MODE is 1
                    mb_ctrl(0) := wbuf(0)(0) and sysr(16#0D#)(0);
                    if mb_ctrl(0) = '0' then
                        mb_ctrl(7 downto 1) := (others => '0');   -- dropping MB_EN clears the whole MB_CTRL_Dyn
                        mb_len := (others => '0');
                    end if;
                end if;

            elsif base_addr = A_MB_LO then
                ------------------------------------------------------------
                -- FTM mailbox message from I2C: immediate, no tW
                ------------------------------------------------------------
                for j in 0 to n - 1 loop
                    mbox(j) := wbuf(j);
                end loop;
                mb_len     := std_logic_vector(to_unsigned(n - 1, 8));
                mb_ctrl(1) := '1';                        -- HOST_PUT_MSG
                mb_ctrl(6) := '1';                        -- HOST_CURRENT_MSG
                mb_ctrl(7) := '0';                        -- RF_CURRENT_MSG
            end if;

            wcommit_v := wcommit_v + 1;

            if wt > 0 ns then
                busy_to  := now + wt;
                obs_busy <= '1', '0' after wt;
                -- I2C_WRITE fires at COMPLETION of the write, and the GPO2 enable is sampled after the byte is stored.
                -- Arming I2C_WRITE_EN by writing GPO2 therefore makes that write raise its own pulse.
                if sysr(16#01#)(0) = '1' and gpo_dyn_en = '1' then
                    gpo_oe <= '0', '1' after wt, '0' after wt + gpo_pulse_len;
                end if;
            end if;
        end procedure;

        -- Full boot / power-on reset of the VOLATILE state, instantaneous: there is no unresponsive window after POR.
        procedure do_boot is
        begin
            gpo_dyn_en  := sysr(16#00#)(0);         -- GPO_EN copied from GPO1
            eh_en       := not sysr(16#02#)(0);     -- EH_MODE=0 boots EH on, EH_MODE=1 boots it off
            rf_mngt_dyn := sysr(16#03#);
            sso         := '0';
            it_sts      := (others => '0');
            mb_ctrl     := (others => '0');
            mb_len      := (others => '0');
            rf_off_v    := '0';
            active      := false;
            dev_ok      := false;
            rfsw        := false;
            is_read     := false;
            dead        := false;
            rd_dead     := false;
            mb_end_rd   := false;
            edge        := 0;
            wcnt        := 0;
            addr_ctr    := 0;
            base_addr   := 0;
            busy_to     := 0 ns;
            sda_oe      <= '0';
            gpo_oe      <= '0';
            obs_busy    <= '0';
        end procedure;

    begin
        ------------------------------------------------------------------
        -- POR / boot
        ------------------------------------------------------------------
        if resetn'event and to_X01(resetn) = '1' then
            do_boot;
        end if;

        ------------------------------------------------------------------
        -- RF-side stimulus: BENCH ABSTRACTION, no ISO/IEC 15693 here
        ------------------------------------------------------------------
        if rf_field'event then
            if to_X01(rf_field) = '1' then
                it_sts(4) := '1';                       -- FIELD_RISING
            else
                it_sts(3) := '1';                       -- FIELD_FALLING
            end if;
            gpo_pulse(sysr(16#00#)(4));                 -- FIELD_CHANGE_EN
        end if;

        if rf_put_msg'event and to_X01(rf_put_msg) = '1' then
            -- "an RF reader wrote a message into the mailbox": needs FTM enabled and a free mailbox.
            if mb_ctrl(0) = '1' and mb_ctrl(1) = '0' and mb_ctrl(2) = '0'
               and rf_put_len > 0 and rf_put_len <= 256 then
                for i in 0 to rf_put_len - 1 loop
                    mbox(i) := std_logic_vector(unsigned(rf_put_seed) +
                                                to_unsigned(i mod 256, 8));
                end loop;
                mb_len     := std_logic_vector(to_unsigned(rf_put_len - 1, 8));
                mb_ctrl(2) := '1';                      -- RF_PUT_MSG
                mb_ctrl(7) := '1';                      -- RF_CURRENT_MSG
                mb_ctrl(6) := '0';                      -- HOST_CURRENT_MSG
                it_sts(5)  := '1';
                gpo_pulse(sysr(16#00#)(5));             -- RF_PUT_MSG_EN
            end if;
        end if;

        if rf_get_msg'event and to_X01(rf_get_msg) = '1' then
            -- "an RF reader read the whole I2C message": frees the mailbox by clearing HOST_PUT_MSG.
            -- RF_CURRENT_MSG/HOST_CURRENT_MSG are NOT cleared.
            if mb_ctrl(0) = '1' and mb_ctrl(1) = '1' then
                mb_ctrl(1) := '0';
                it_sts(6)  := '1';
                gpo_pulse(sysr(16#00#)(6));             -- RF_GET_MSG_EN
            end if;
        end if;

        if rf_write_ee'event and to_X01(rf_write_ee) = '1' then
            it_sts(7) := '1';                           -- RF_WRITE
            gpo_pulse(sysr(16#00#)(7));                 -- RF_WRITE_EN
        end if;

        ------------------------------------------------------------------
        -- I2C bus: START / Sr / STOP, then SAMPLE (rising) / DRIVE (falling)
        -- `edge` counts SCL rising edges since the last START/Sr, so g = edge/9 is the byte group (g=0 is the device select) and bp = edge mod 9 is the bit position (bp=8 is the ACK slot).
        ------------------------------------------------------------------
        if sda_in'event and to_X01(scl) = '1' then
            if to_X01(sda_in) = '0' then
                -- START or repeated START: (re)synchronize the frame.
                -- The internal ADDRESS COUNTER deliberately survives an Sr, which is exactly how a random address read works.
                edge      := 0;
                shift     := (others => '0');
                dev_ok    := false;
                rfsw      := false;
                is_read   := false;
                dead      := false;
                rd_dead   := false;
                mb_end_rd := false;
                wcnt      := 0;
                active    := true;
                sda_oe    <= '0';
            else
                -- STOP
                if active then
                    if not is_read then
                        commit_write;
                    end if;
                    if mb_end_rd then
                        -- RF_PUT_MSG is cleared at the STOP that follows the read of the last message byte.
                        mb_ctrl(2) := '0';
                        mb_end_rd  := false;
                    end if;
                    txn_v := txn_v + 1;
                end if;
                active := false;
                sda_oe <= '0';
            end if;

        ------------------------------------------------------------------
        -- SCL RISING edge: SAMPLE
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '1' then
            g  := edge / 9;
            bp := edge mod 9;

            if bp < 8 then
                if g = 0 or (dev_ok and (not rfsw) and (not is_read)) then
                    shift := shift(6 downto 0) & to_X01(sda_in);
                end if;
                -- read-data bits: this model is the driver, nothing to sample.
            else
                if g = 0 then
                    null;                       -- address ACK: driven at the falling edge
                elsif dev_ok and (not rfsw) and is_read then
                    -- The byte just clocked out is complete.
                    -- Apply its read side effects and advance the counter, THEN look at the master's ACK/NACK.
                    if not rd_dead then
                        if e2v = '0' and addr_ctr = 16#2005# then
                            it_sts := (others => '0');    -- IT_STS_Dyn is cleared by reading it
                        end if;
                        if e2v = '0' and addr_ctr >= A_MB_LO and addr_ctr <= A_MB_HI
                           and mb_ctrl(0) = '1'
                           and (addr_ctr - A_MB_LO) = to_integer(unsigned(mb_len)) then
                            mb_end_rd := true;
                        end if;
                        addr_ctr := addr_ctr + 1;
                    end if;
                    if to_X01(sda_in) = '1' then
                        rd_dead := true;                  -- master NACK = last byte
                    end if;
                end if;
            end if;

            edge := edge + 1;

        ------------------------------------------------------------------
        -- SCL FALLING edge: DRIVE (set up the UPCOMING sample; `edge` has already been incremented by the preceding rising edge)
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '0' then
            g  := edge / 9;
            bp := edge mod 9;

            if g = 0 then
                if bp = 8 then
                    ----------------------------------------------------------
                    -- DEVICE SELECT decision: 1010 E2 E1 E0 R/notW, with the code and E0 taken live from I2C_CFG
                    ----------------------------------------------------------
                    obs_devsel <= shift;
                    is_read    := (shift(0) = '1');
                    e2v        := shift(3);
                    dev_ok     := false;
                    rfsw       := false;

                    if now < busy_to then
                        dev_ok := false;                  -- busy programming: NACK every device select
                    elsif shift(7 downto 4) = sysr(16#0E#)(3 downto 0)
                          and shift(1) = sysr(16#0E#)(4) then
                        if shift(2) = '1' then
                            dev_ok := true;               -- memory access
                        elsif shift(0) = '0' and sysr(16#0E#)(5) = '1' then
                            -- I2C RFSwitchOff (E2=0) / RFSwitchOn (E2=1); with no RF side here the only effect is obs_rf_off
                            dev_ok := true;
                            rfsw   := true;
                            if shift(3) = '0' then
                                rf_off_v := '1';
                                gpo_pulse(sysr(16#01#)(1));  -- I2C_RF_OFF_EN
                            else
                                rf_off_v := '0';
                            end if;
                        end if;
                    end if;

                    if dev_ok then
                        sda_oe <= '1';                    -- ACK (pull SDA low)
                    else
                        sda_oe   <= '0';                  -- NACK (release)
                        dsnack_v := dsnack_v + 1;
                    end if;
                else
                    sda_oe <= '0';                        -- master drives the address bits
                end if;

            elsif dev_ok and (not rfsw) and (not is_read) then
                ----------------------------------------------------------
                -- WRITE frame: group 1 = address MSB, group 2 = address LSB, groups 3 and up = data bytes.
                ----------------------------------------------------------
                if bp = 8 then
                    kk    := g - 1;
                    ackit := false;
                    if kk = 0 then
                        base_hi := shift;
                        ackit   := true;
                    elsif kk = 1 then
                        base_addr := to_integer(unsigned(base_hi)) * 256 +
                                     to_integer(unsigned(shift));
                        addr_ctr  := base_addr;
                        obs_addr  <= base_addr;
                        ackit     := true;
                    else
                        k := kk - 2;
                        if dead then
                            ackit := false;
                        else
                            wr_allowed(k, ackit);
                            if ackit then
                                wbuf(k) := shift;
                                wcnt    := k + 1;
                            else
                                dead := true;             -- NACK every later byte and commit nothing
                            end if;
                        end if;
                    end if;
                    if ackit then sda_oe <= '1'; else sda_oe <= '0'; end if;
                else
                    sda_oe <= '0';                        -- master drives the data bits
                end if;

            elsif dev_ok and (not rfsw) and is_read then
                ----------------------------------------------------------
                -- READ frame: this model sources the data bytes.
                ----------------------------------------------------------
                if bp = 0 then
                    if rd_dead then
                        rbyte := x"FF";
                    else
                        rd_fetch(addr_ctr, e2v, rbyte, okv);
                        if not okv then
                            rd_dead := true;              -- I2C dead state: FFh from here on
                            rbyte   := x"FF";
                        end if;
                    end if;
                    obs_addr <= addr_ctr;
                end if;
                if bp < 8 then
                    if rbyte(7 - bp) = '0' then
                        sda_oe <= '1';                    -- drive a 0 low
                    else
                        sda_oe <= '0';                    -- release a 1
                    end if;
                else
                    sda_oe <= '0';                        -- master drives ACK/NACK
                end if;

            else
                sda_oe <= '0';                            -- not addressed: stay off the bus
            end if;
        end if;

        ------------------------------------------------------------------
        -- Publish observations and the V_EH bench abstraction
        ------------------------------------------------------------------
        obs_txn_count   <= txn_v;
        obs_wcommit     <= wcommit_v;
        obs_devsel_nack <= dsnack_v;
        obs_it_sts      <= it_sts;
        obs_mb_ctrl     <= mb_ctrl;
        obs_mb_len      <= mb_len;
        obs_i2c_sso     <= sso;
        obs_rf_off      <= rf_off_v;

        eh_enabled <= eh_en;
        if eh_en = '1' and to_X01(rf_field) = '1' then
            veh_active   <= '1';
            veh_avail_ua <= cfg_veh_ua;
        else
            veh_active   <= '0';
            veh_avail_ua <= 0;
        end if;
    end process dev;

end architecture behavioral;
