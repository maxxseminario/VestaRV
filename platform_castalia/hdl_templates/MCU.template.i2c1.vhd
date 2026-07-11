-- MCU.template.i2c1.vhd -- I2C1-conditional verbatim blocks (G1a, 2026-07-11).
-- Spliced into MCU.template.vhd by python/mcu_vhd.py ONLY when the config has
-- peripherals.i2c1=true (the Castalia default). Same mechanism as the NPU side
-- template: @I2C1BLOCK:<name>@ markers delimit the blocks; with i2c1 absent the
-- markers in the main template emit nothing (slot 15 reads zero via the mux
-- fall-through, vectors 70-82 become IRQB_RSVD*, the SDA1/SCL1 planes go hi-Z).

--@I2C1BLOCK:i2c1-pad-decls@
        -- P4.2: SDA1 (input and output)
        signal sda1_in               : std_logic;
        signal sda1_out              : std_logic;
        signal sda1_dir              : std_logic;
        signal sda1_ren              : std_logic;
        signal sda1_ren_in          : std_logic;
        
        -- P4.3: SCL1 (input and output)
        signal scl1_in               : std_logic;
        signal scl1_out              : std_logic;
        signal scl1_dir              : std_logic;
        signal scl1_ren              : std_logic;
        signal scl1_ren_in          : std_logic;

--@I2C1BLOCK:i2c1-instance@
    i2c1: I2C
        generic map (
            default_SAD => i2c1_default_SAD
        )
        port map
        (
            -- System Signals
            smclk			=> smclk,	
            resetn			=> resetn,	

            irq_str			=> irq_i2c1_str,
            irq_spr			=> irq_i2c1_spr,
            irq_msts		=> irq_i2c1_msts,
            irq_msps		=> irq_i2c1_msps,
            irq_marb		=> irq_i2c1_marb,
            irq_mtxe		=> irq_i2c1_mtxe,
            irq_mnr			=> irq_i2c1_mnr,
            irq_mxc			=> irq_i2c1_mxc,
            irq_sa			=> irq_i2c1_sa,
            irq_stxe		=> irq_i2c1_stxe,
            irq_sovf		=> irq_i2c1_sovf,
            irq_snr			=> irq_i2c1_snr,
            irq_sxc			=> irq_i2c1_sxc,
            
            --@GEN:bus:i2c1@

            -- Pin Inputs/Outputs
            SCL_IN			=> scl1_in,
            SCL_OUT			=> scl1_out,
            SCL_DIR			=> scl1_dir,
            SCL_REN_in		=> scl1_ren_in,
            SCL_REN			=> scl1_ren,
            
            SDA_IN			=> sda1_in,
            SDA_OUT			=> sda1_out,
            SDA_DIR			=> sda1_dir,
            SDA_REN_in		=> sda1_ren_in,
            SDA_REN			=> sda1_ren
	);
