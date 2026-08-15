-------------------------------------------------------------------------------
-- i3c_target_model.vhd
-------------------------------------------------------------------------------
-- Generic-configured behavioral I3C/legacy-I2C TARGET responder for the I3C peripheral testbench (tb/I3C_tb.vhd), stage 1 (D29).
-- It mirrors tb/qspi_flash_model.vhd's role: per launch the TB states the exact shape to expect through cfg_* inputs held stable for one START..STOP framed transaction.
-- Those are its own 7-bit address, legacy versus I3C-SDR mode, how many bytes IT has available to source on a read, the read pattern seed, and a write-parity-corruption injection flag.
-- The stage-1 model does NOT implement DAA/IBI (stage 2 and 3, D34, out of scope for stage 1) or HDR modes.
--
-- BUS-LEVEL PROTOCOL MODEL, this designer's own read of D19 and D24-D27, since I3C.vhd does not exist yet to validate cycle-level behavior against; ASSUMPTIONS are flagged below.
--   Every 9-edge "group" on SCL is either the address+RnW group (group 0: 7 address bits MSB-first, 1 RnW bit, 1 ACK slot) or a data-byte group (group N of 1 or more: 8 data bits MSB-first, 1 ACK/T slot).
--   This model tracks a single `edge` counter (SCL rising-edge count since the last START/Sr) and derives group_idx = edge/9 and bit_in_group = edge mod 9 from it.
--   That is exactly qspi_flash_model's b1/b2/b3/b4 boundary technique, applied to a 9-edge cadence instead of CMD/ADDR/DUMMY/DATA phase boundaries.
--   * SAMPLE happens on the SCL RISING edge, with setup on SCL low, matching B3's BIT_SETUP, BIT_SCL_RISE, BIT_SAMPLE, BIT_SCL_FALL sequence (D1).
--   * DRIVE, this model's own output setup for the NEXT sample, happens on the SCL FALLING edge.
--   * START always RESETS `edge` to 0 and restarts the address group; a repeated START (Sr) is electrically identical to a first START, namely SDA falling while SCL is high.
--     That is exactly the Sr behavior D16/D19 need, with no special-casing.
--   * ADDRESS ACK (group 0, bit 8) is open-drain: this model drives SDA low iff the captured 7-bit address matches cfg_target_addr, else it releases, giving a NACK into the DUT's ANACK path (address-NACK test group).
--   * WRITE byte T-bit (D24, non-legacy): the CONTROLLER drives 9th-bit odd parity.
--     This model only SAMPLES it, never drives it, and compares against i3c_parity() of the captured byte, or of a locally corrupted copy when cfg_corrupt_wparity is set (D29's self-test of the checker, not a real DUT fault).
--   * READ byte T-bit (D25, non-legacy) is an ASSUMPTION, flagged: the frozen D19 table describes the CONTROLLER's drive action, "release and sample" for continue and "drive low" for the final or abort byte, not the target's.
--     This model drives T=0 (SDA low) on ITS OWN last configured byte (byte_idx = cfg_num_read_bytes-1, announcing end-of-data) and RELEASES otherwise, never driving high, relying on the D19-mandated weak-'H' pull for the T=1 continue case.
--     So a controller that wants to terminate EARLY (its own final byte, per D19 "drive low") always wins the wired-AND regardless of what this model intends, and a target that wants to end early (EODF) can assert T=0 without knowing the controller's DLEN.
--     This model never drives an ACTIVE HIGH.
--   * Legacy-I2C mode (cfg_legacy_mode, BUSMODE=1, D29): the ACK/T slot becomes a real bidirectional per-byte ACK.
--     On a WRITE byte this model, the addressed target, DRIVES the ACK (open-drain low = ack, no parity concept).
--     On a READ byte it only SAMPLES the controller's ACK/NACK and drives nothing, symmetric with I2C.vhd's L504-513 recipe minus the slave FSM (D10).
--   * SCL is SAMPLE/DRIVE clocked entirely from the DUT in I3C-SDR mode (D19: push-pull, no stretch, D11).
--     This model may assert scl_oe (stretch) only when cfg_legacy_mode AND cfg_legacy_stretch are both true, and then only as an ILLUSTRATIVE fixed-duration stretch right after the address ACK (LEGACY_STRETCH_TIME below).
--     There is no real processing delay to model in a combinational bench responder, so that stretch exists to prove the scl_oe/scl_out wiring is present and exercised in at least one test group, not to model a specific real duration.
--
-- Bus ownership: sda_oe/scl_oe follow the qspi_flash_model io_oe convention, where '1' means this model drives that pin.
-- The TB resolves sda_in and scl, this model's inputs, the same way QSPI_tb.vhd's io_res generate does, extended with a weak 'H' release level (see the I3C_tb.vhd header).
-- The D19/D20 push-pull WDATA and DAA-assign phases are NOT driven by this model at all: the DUT is the single driver, and sda_oe stays '0' through those bit groups here.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.i3c_bfm_pkg.all;

entity I3C_target_model is
    port (
        -- Resolved bus, the same nets fed to the DUT's SDA_IN/SCL_IN.
        scl    : in std_logic;
        sda_in : in std_logic;

        -- This model's drive; '1' on an *_oe port means this model drives the matching *_out.
        sda_out : out std_logic := '0';
        sda_oe  : out std_logic := '0';
        scl_out : out std_logic := '0';
        scl_oe  : out std_logic := '0';

        -- Per-transaction configuration, held stable by the TB across one START..STOP framed transaction.
        cfg_target_addr     : in std_logic_vector(6 downto 0) := "1010000";  -- 0x50
        cfg_legacy_mode     : in boolean                      := false;     -- BUSMODE=1
        cfg_legacy_stretch  : in boolean                      := false;     -- D11 stretch demo, legacy only
        cfg_num_read_bytes  : in natural                      := 1;         -- target's OWN last-byte boundary
        cfg_read_seed       : in std_logic_vector(7 downto 0) := x"A5";     -- seed for the generated read pattern
        cfg_corrupt_wparity : in boolean                      := false;     -- D29 injection flag

        -- Stage-2 DAA config (D18/task): the 48-bit PID plus BCR and DCR, streamed open-drain during an ENTDAA round.
        -- cfg_daa_enable also makes this model ACK the 0x7E broadcast header (CCC / ENTDAA / SETDASA).
        cfg_daa_enable : in boolean                       := false;
        cfg_pid        : in std_logic_vector(47 downto 0) := (others => '0');
        cfg_bcr        : in std_logic_vector(7 downto 0)  := (others => '0');
        cfg_dcr        : in std_logic_vector(7 downto 0)  := (others => '0');

        -- Stage-3 IBI (D-doc S3, R2): a rising edge on cfg_ibi_trigger makes this model INITIATE a bus-available IBI.
        -- It drives a START (SDA low while SCL high), then streams its STAGE-2-ASSIGNED dynamic address plus RnW=1 open-drain as the controller clocks SCL, samples the controller's ACK/NACK, and on ACK, when cfg_ibi_has_data, drives cfg_ibi_mdb followed by a released T.
        -- The TB only pulses the trigger when the bus is idle.
        cfg_ibi_trigger  : in std_logic                     := '0';
        cfg_ibi_mdb      : in std_logic_vector(7 downto 0)  := (others => '0');
        cfg_ibi_has_data : in boolean                       := true;

        -- Observed results, valid and held from the STOP that ended a transaction until the next START.
        obs_addr       : out std_logic_vector(6 downto 0) := (others => '0');
        obs_rnw        : out std_logic                    := '0';
        obs_addr_acked : out std_logic                    := '0';
        obs_wdata      : out i3c_byte_array(0 to I3C_MODEL_MAX_BYTES - 1) := (others => (others => '0'));
        obs_wparity_ok : out std_logic_vector(0 to I3C_MODEL_MAX_BYTES - 1) := (others => '1');
        obs_wcount     : out natural := 0;
        obs_rcount     : out natural := 0;
        obs_txn_count  : out natural := 0;

        -- Stage-2 DAA observations; these persist once an address is assigned.
        obs_daa_assigned  : out std_logic                    := '0';
        obs_daa_dynaddr   : out std_logic_vector(6 downto 0) := (others => '0');
        obs_daa_parity_ok : out std_logic                    := '0';

        -- Stage-3 IBI observations: obs_ibi_acked is the ACK/NACK this model sampled from the controller on its last IBI (1=ACK, 0=NACK), held until the next IBI.
        -- obs_ibi_count increments once per completed IBI.
        obs_ibi_acked : out std_logic := '0';
        obs_ibi_count : out natural   := 0
    );
end entity I3C_target_model;

architecture behavioral of I3C_target_model is

    -- Illustrative legacy-mode SCL stretch length, held after the address ACK.
    constant LEGACY_STRETCH_TIME : time := 200 ns;

    -- Boolean to std_logic, for driving the obs_* flag ports.
    function to_sl(cond : boolean) return std_logic is
    begin
        if cond then return '1'; else return '0'; end if;
    end function;

begin

    -- Single responder process: every bus action is an edge on scl, sda_in or the IBI trigger.
    resp : process (scl, sda_in, cfg_ibi_trigger)
        variable active   : boolean := false;   -- inside a START..STOP frame
        variable edge     : natural := 0;   -- SCL rising-edge count since last START/Sr
        variable shift    : std_logic_vector(7 downto 0) := (others => '0');  -- bit-serial capture register
        variable is_read  : boolean := false;   -- RnW bit of the current frame
        variable addr_ok  : boolean := false;   -- the frame addressed this target
        variable legacy_l : boolean := false;   -- cfg_legacy_mode latched at START
        -- Ruling 3: once this model has driven its final read T=0 it releases SDA for the rest of the frame, until the next START.
        -- That way no phantom read byte fights the STOP or the idle bus.
        variable read_done : boolean := false;

        variable wdata_v : i3c_byte_array(0 to I3C_MODEL_MAX_BYTES - 1) := (others => (others => '0'));
        variable wpok_v  : std_logic_vector(0 to I3C_MODEL_MAX_BYTES - 1) := (others => '1');
        variable wcount_v, rcount_v, txn_v : natural := 0;

        variable byte_v, corrupted_v : std_logic_vector(7 downto 0);
        variable exp_t : std_logic;             -- expected parity T-bit for a write byte
        variable g, bp, byte_idx : natural;     -- group index, bit position in group, data-byte index
        variable pat : std_logic_vector(7 downto 0);  -- generated read-pattern byte

        -- ---- stage-2 DAA state ----------------------------------------
        -- `assigned` persists for the whole test once this device wins an ENTDAA round; it then NACKs further 7E+R headers and ACKs its adopted dynamic address for directed transfers.
        -- The per-round state resets on every START/Sr.
        -- daa_id = {PID[47:0], BCR, DCR} is the 64-bit value streamed MSB-first under open-drain arbitration.
        variable assigned    : boolean := false;
        variable daa_dynaddr : std_logic_vector(6 downto 0) := (others => '0');
        variable daa_round   : boolean := false;   -- participating in this 7E+R round
        variable daa_lost    : boolean := false;   -- lost arbitration this round
        variable daa_id      : std_logic_vector(63 downto 0) := (others => '0');
        variable daa_rx_addr : std_logic_vector(6 downto 0) := (others => '0');  -- address the controller is assigning
        variable daa_rx_par  : std_logic := '0';   -- parity bit that followed it
        variable k           : natural;            -- bit index within the 64-bit arbitration ID
        variable par_v       : std_logic;          -- locally recomputed assign parity

        -- ---- stage-3 IBI initiator state ------------------------------
        -- in_ibi spans the START..STOP of a model-initiated IBI.
        -- ibi_fall counts SCL falling edges since the START; on fall k the model sets up header or MDB bit k, mapped as follows:
        --   k=0..6 address MSB-first, k=7 RnW=1, k=8 ACK slot (controller drives),
        --   k=9..16 MDB MSB-first, k=17 T slot, k=18 and beyond released.
        -- The ACK is sampled on the rising edge where ibi_fall=9.
        variable in_ibi      : boolean := false;
        variable ibi_fall    : natural := 0;
        variable ibi_acked_v : boolean := false;
        variable ibi_cnt     : natural := 0;
    begin
        ------------------------------------------------------------------
        -- Stage-3 IBI: initiate on a trigger edge, then drive the frame off the controller's SCL.
        -- Handled BEFORE the normal branches so the model's own START is not mis-parsed as an incoming transaction.
        ------------------------------------------------------------------
        if cfg_ibi_trigger'event and to_X01(cfg_ibi_trigger) = '1'
           and (not active) and (not in_ibi) and to_X01(scl) = '1' then
            in_ibi      := true;
            ibi_fall    := 0;
            ibi_acked_v := false;
            sda_oe  <= '1';   -- START: pull SDA low while SCL is high
            sda_out <= '0';
            scl_oe  <= '0';
        elsif in_ibi then
            if scl'event and to_X01(scl) = '0' then
                -- SCL falling edge: set up bit ibi_fall for the next sample.
                if ibi_fall <= 6 then                          -- address, MSB first (OD)
                    if daa_dynaddr(6 - ibi_fall) = '0' then
                        sda_oe <= '1'; sda_out <= '0';
                    else
                        sda_oe <= '0';                          -- release a 1
                    end if;
                elsif ibi_fall = 7 then                        -- RnW = 1 (release)
                    sda_oe <= '0';
                elsif ibi_fall = 8 then                        -- ACK slot: the controller drives it
                    sda_oe <= '0';
                elsif ibi_fall >= 9 and ibi_fall <= 16 then    -- MDB byte, MSB first
                    if ibi_acked_v and cfg_ibi_has_data then
                        sda_oe  <= '1';
                        sda_out <= cfg_ibi_mdb(16 - ibi_fall);
                    else
                        sda_oe <= '0';
                    end if;
                else                                           -- T slot and tail: release
                    sda_oe <= '0';
                end if;
                ibi_fall := ibi_fall + 1;
            elsif scl'event and to_X01(scl) = '1' then
                -- SCL rising edge: sample the controller's ACK at the ACK slot.
                if ibi_fall = 9 then
                    ibi_acked_v := (to_X01(sda_in) = '0');
                    obs_ibi_acked <= to_sl(ibi_acked_v);
                end if;
            elsif sda_in'event and to_X01(scl) = '1' and to_X01(sda_in) = '1' then
                -- STOP: SDA rises while SCL is high, ending the IBI frame.
                in_ibi   := false;
                ibi_fall := 0;
                ibi_cnt  := ibi_cnt + 1;
                obs_ibi_count <= ibi_cnt;
                sda_oe  <= '0'; sda_out <= '0';
                scl_oe  <= '0'; scl_out <= '0';
            end if;

        ------------------------------------------------------------------
        ------------------------------------------------------------------
        -- START, repeated-START and STOP detection: SDA transitions while SCL is high.
        ------------------------------------------------------------------
        -- Weak-level correct (ruling 2): every sda and scl sample is normalized through to_X01, so a released wired-AND 'H' reads as '1'.
        elsif sda_in'event and to_X01(scl) = '1' then
            if to_X01(sda_in) = '0' then
                -- START, or a repeated START: resynchronize the frame from bit 0.
                edge      := 0;
                shift     := (others => '0');
                is_read   := false;
                addr_ok   := false;
                legacy_l  := cfg_legacy_mode;
                read_done := false;
                wcount_v := 0;
                rcount_v := 0;
                -- Per-round DAA reset; `assigned` is deliberately left alone, since it persists.
                daa_round   := false;
                daa_lost    := false;
                daa_rx_addr := (others => '0');
                daa_id      := cfg_pid & cfg_bcr & cfg_dcr;
                active   := true;
                sda_oe  <= '0';
                sda_out <= '0';
                scl_oe  <= '0';
                scl_out <= '0';
            else
                -- STOP: publish this transaction's observations.
                if active then
                    txn_v := txn_v + 1;
                    obs_txn_count  <= txn_v;
                    obs_wdata      <= wdata_v;
                    obs_wparity_ok <= wpok_v;
                    obs_wcount     <= wcount_v;
                    obs_rcount     <= rcount_v;
                end if;
                active := false;
                sda_oe  <= '0';
                sda_out <= '0';
                scl_oe  <= '0';
                scl_out <= '0';
            end if;

        ------------------------------------------------------------------
        -- SCL RISING edge: SAMPLE.
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '1' and daa_round then
            -- DAA-round SAMPLE, where edge counts rising edges since this repeated START.
            -- Header address bits 0..7 and the ACK at 8 precede daa_round; this arm handles arbitration (9..72), the assigned address (73..79), its parity (80) and the assign ACK (81).
            if edge >= 9 and edge <= 72 then
                -- Open-drain arbitration: releasing a 1 while the bus reads 0 means a lower-value device won this bit, so this model backs off for the rest of the round.
                k := edge - 9;
                if (not daa_lost) and daa_id(63 - k) = '1' and to_X01(sda_in) = '0' then
                    daa_lost := true;
                end if;
            elsif edge >= 73 and edge <= 79 then
                daa_rx_addr := daa_rx_addr(5 downto 0) & to_X01(sda_in);  -- assigned addr MSB-first
            elsif edge = 80 then
                daa_rx_par := to_X01(sda_in);                            -- assign parity bit
            elsif edge = 81 then
                -- Assign ACK slot: the winner, i.e. the device that never lost a bit, adopts the address.
                if not daa_lost then
                    par_v := not (daa_rx_addr(6) xor daa_rx_addr(5) xor daa_rx_addr(4) xor
                                  daa_rx_addr(3) xor daa_rx_addr(2) xor daa_rx_addr(1) xor
                                  daa_rx_addr(0));
                    assigned    := true;
                    daa_dynaddr := daa_rx_addr;
                    obs_daa_assigned  <= '1';
                    obs_daa_dynaddr   <= daa_rx_addr;
                    obs_daa_parity_ok <= to_sl(daa_rx_par = par_v);
                end if;
            end if;
            edge := edge + 1;

        -- Ordinary SAMPLE arm: address group and data-byte groups.
        elsif active and scl'event and to_X01(scl) = '1' then
            g  := edge / 9;
            bp := edge mod 9;

            if bp < 8 then
                if g = 0 then
                    shift := shift(6 downto 0) & to_X01(sda_in);   -- address+RnW byte
                elsif not is_read then
                    shift := shift(6 downto 0) & to_X01(sda_in);   -- write-data byte (controller drives)
                end if;
                -- Read-data bits are driven by this model, so there is nothing to sample.
            else
                -- bp = 8: the ACK or T slot is sampled here.
                if g = 0 then
                    null;   -- address ACK: this model drove it at the preceding falling edge
                elsif not is_read then
                    if not legacy_l then
                        -- I3C non-legacy WRITE: sample the controller's parity T-bit.
                        byte_v := shift;
                        if cfg_corrupt_wparity then
                            corrupted_v := byte_v xor "00000001";   -- D29 injection: corrupt before recompute
                        else
                            corrupted_v := byte_v;
                        end if;
                        exp_t := i3c_parity(corrupted_v);
                        if wcount_v < I3C_MODEL_MAX_BYTES then
                            wdata_v(wcount_v) := byte_v;
                            wpok_v(wcount_v)  := to_sl(to_X01(sda_in) = exp_t);
                        end if;
                        wcount_v := wcount_v + 1;
                    else
                        -- Legacy WRITE: this model drove the per-byte ACK itself, open-drain with no parity concept, so only the byte is recorded here.
                        if wcount_v < I3C_MODEL_MAX_BYTES then
                            wdata_v(wcount_v) := shift;
                            wpok_v(wcount_v)  := '1';   -- no parity in legacy mode, so this is not a failure
                        end if;
                        wcount_v := wcount_v + 1;
                    end if;
                else
                    -- READ ACK/T slot: a legacy ACK/NACK from the controller, or in non-legacy mode the controller's own drive on its final byte.
                    -- Neither needs any action here beyond bumping the count.
                    rcount_v := rcount_v + 1;
                end if;
            end if;

            edge := edge + 1;

        ------------------------------------------------------------------
        -- SCL FALLING edge: DRIVE, i.e. set up this model's output for the UPCOMING sample, using the just-incremented `edge`.
        ------------------------------------------------------------------
        elsif active and scl'event and to_X01(scl) = '0' then
            g  := edge / 9;
            bp := edge mod 9;

            if read_done then
                -- Ruling 3: released for the remainder of the frame.
                sda_oe <= '0';
            elsif daa_round and edge >= 9 then
                -- DAA-round DRIVE; edge has already been incremented to the upcoming sample index.
                -- Arbitration 9..72 is open-drain: drive a 0, release a 1, and back off once lost.
                -- Assign 73..80 is controller push-pull, so this model only samples; the assign ACK at 81 is driven low by the winner.
                if edge <= 72 then
                    k := edge - 9;
                    if daa_lost then
                        sda_oe <= '0';
                    elsif daa_id(63 - k) = '0' then
                        sda_oe <= '1'; sda_out <= '0';
                    else
                        sda_oe <= '0';
                    end if;
                elsif edge <= 80 then
                    sda_oe <= '0';
                elsif edge = 81 then
                    if not daa_lost then
                        sda_oe <= '1'; sda_out <= '0';
                    else
                        sda_oe <= '0';
                    end if;
                else
                    sda_oe <= '0';
                end if;

            elsif g = 0 then
                if bp = 8 then
                    -- Address ACK decision.
                    -- cfg_daa_enable adds 0x7E broadcast participation, ACKing while unassigned, with a 7E+R header starting an ENTDAA round, plus adoption of the assigned dynamic address.
                    is_read := (shift(0) = '1');
                    addr_ok := (shift(7 downto 1) = cfg_target_addr) or
                               (assigned and shift(7 downto 1) = daa_dynaddr);
                    obs_addr <= shift(7 downto 1);
                    obs_rnw  <= shift(0);
                    if cfg_daa_enable and shift(7 downto 1) = "1111110" then
                        obs_addr_acked <= to_sl(not assigned);
                        if not assigned then
                            sda_oe  <= '1'; sda_out <= '0';   -- ACK the broadcast
                            if is_read then                   -- a 7E+R header opens an ENTDAA round
                                daa_round := true;
                                daa_lost  := false;
                                daa_id    := cfg_pid & cfg_bcr & cfg_dcr;
                            end if;
                        else
                            sda_oe <= '0';                    -- already assigned, so NACK the broadcast
                        end if;
                        scl_oe <= '0';
                    elsif addr_ok then
                        obs_addr_acked <= '1';
                        sda_oe  <= '1'; sda_out <= '0';
                        if legacy_l and cfg_legacy_stretch then
                            -- D11: SCL stretch is legacy-only, and this is an illustrative fixed hold, flagged in the file header.
                            scl_oe  <= '1', '0' after LEGACY_STRETCH_TIME;
                            scl_out <= '0';
                        else
                            scl_oe <= '0';
                        end if;
                    else
                        obs_addr_acked <= '0';
                        sda_oe <= '0';
                    end if;
                else
                    sda_oe <= '0';   -- address and RnW bits are controller-driven, so always released here
                end if;

            else
                -- Data-byte groups: group 1 is data byte 0.
                byte_idx := g - 1;
                if bp < 8 then
                    if is_read then
                        if addr_ok and byte_idx < cfg_num_read_bytes then
                            pat := i3c_read_pattern(cfg_target_addr, cfg_read_seed, byte_idx);
                            sda_oe  <= '1';
                            sda_out <= pat(7 - bp);
                        else
                            sda_oe <= '0';   -- not addressed, or past our last byte, so release
                        end if;
                    else
                        sda_oe <= '0';   -- write-data bits are controller-driven
                    end if;
                else
                    -- bp = 8: this model's drive for the ACK or T slot.
                    if is_read then
                        if legacy_l then
                            sda_oe <= '0';   -- the controller drives ACK/NACK in legacy mode
                        else
                            if addr_ok and byte_idx = cfg_num_read_bytes - 1 then
                                sda_oe  <= '1';
                                sda_out <= '0';   -- T=0 on OUR last byte, which is an EODF when it comes early
                                read_done := true;  -- release for the rest of the frame (ruling 3)
                            else
                                sda_oe <= '0';    -- T=1, continue, expressed by releasing
                            end if;
                        end if;
                    else
                        if legacy_l and addr_ok then
                            sda_oe  <= '1';
                            sda_out <= '0';       -- legacy per-byte ACK from the target
                        else
                            sda_oe <= '0';        -- in I3C mode the controller drives the parity T-bit
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process resp;

end architecture behavioral;
