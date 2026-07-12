-- MCU.template.timer1.vhd -- TIMER1-conditional verbatim blocks (G1b, 2026-07-11).
-- Spliced into MCU.template.vhd by python/mcu_vhd.py ONLY when the config has
-- peripherals.timer1=true (the Castalia default). Same mechanism as the I2C1
-- side template: @TIMER1BLOCK:<name>@ markers delimit the blocks; with timer1
-- absent the markers in the main template emit nothing (window slot 7 reads
-- zero via the mux fall-through, vectors 22-27 become IRQB_RSVD*, the
-- T1CMP0/T1CMP1/T1CAP0/T1CAP1 pad planes go hi-Z and P3.4-7 revert to plain
-- GPIO20-23).

--@TIMER1BLOCK:timer1-pad-decls@
        -- P3.4: T1_CMP0 (output)
        signal t1_cmp0_out           : std_logic;
        signal t1_cmp0_dir           : std_logic;
        signal t1_cmp0_ren           : std_logic;
        signal t1_cmp0_ren_in        : std_logic;

        -- P3.5: T1_CMP1 (output)
        signal t1_cmp1_out           : std_logic;
        signal t1_cmp1_dir           : std_logic;
        signal t1_cmp1_ren           : std_logic;
        signal t1_cmp1_ren_in       : std_logic;

        -- P3.6: T1_CAP0 (input)
        signal t1_cap0_in            : std_logic;
        signal t1_cap0_dir           : std_logic;
        signal t1_cap0_ren           : std_logic;
        signal t1_cap0_ren_in       : std_logic;

        -- P3.7: T1_CAP1 (input and output (double as dtp for SARADC))
        signal t1_cap1_in            : std_logic;
        signal t1_cap1_dir           : std_logic;
        signal t1_cap1_ren           : std_logic;
        signal t1_cap1_ren_in        : std_logic;
        signal t1_cap1_out           : std_logic;

--@TIMER1BLOCK:timer1-instance@
    timer1 : TIMER
        port map (
            -- System Signals
            mclk         => mclk,
            smclk        => smclk,
            clk_lfxt     => clk_lfxt,
            clk_hfxt     => clk_hfxt,
            resetn       => resetn,

            -- IRQ Signals  
            irq_cap0     => irq_tim1_cap0,
            irq_cap1     => irq_tim1_cap1,
            irq_ovf      => irq_tim1_ovf,
            irq_cmp0     => irq_tim1_cmp0,
            irq_cmp1     => irq_tim1_cmp1,
            irq_cmp2     => irq_tim1_cmp2,

            --@GEN:bus:timer1@

            -- Pad Interface
            cmp0_ren_in  => t1_cmp0_ren_in,
            cmp0_out     => t1_cmp0_out,
            cmp0_dir     => t1_cmp0_dir,
            cmp0_ren     => t1_cmp0_ren,

            cmp1_ren_in  => t1_cmp1_ren_in,
            cmp1_out     => t1_cmp1_out,
            cmp1_dir     => t1_cmp1_dir,
            cmp1_ren     => t1_cmp1_ren,

            cap0_ren_in  => t1_cap0_ren_in,
            cap0_ren     => t1_cap0_ren,
            cap0_dir     => t1_cap0_dir,
            cap0_in      => t1_cap0_in,

            cap1_ren_in  => t1_cap1_ren_in,
            cap1_ren     => t1_cap1_ren,
            cap1_dir     => t1_cap1_dir,
            cap1_in      => t1_cap1_in
    );
