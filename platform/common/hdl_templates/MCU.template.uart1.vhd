-- MCU.template.uart1.vhd -- UART1-conditional verbatim blocks (G1b, 2026-07-11).
-- Spliced into MCU.template.vhd by python/mcu_vhd.py ONLY when the config has
-- peripherals.uart1=true (the Castalia default). Same mechanism as the I2C1
-- side template: @UART1BLOCK:<name>@ markers delimit the blocks; with uart1
-- absent the markers in the main template emit nothing (window slot 5 reads
-- zero via the mux fall-through, vectors 52-54 become IRQB_RSVD*, the TX1/RX1
-- pad planes go hi-Z and P2.6/7 revert to plain GPIO14/15).

--@UART1BLOCK:uart1-pad-decls@
        -- P2.6: TX1
        signal tx1_out              : std_logic;
        signal tx1_dir              : std_logic;
        signal tx1_ren              : std_logic;
        signal tx1_ren_in          : std_logic;

        -- P2.7: RX1
        signal rx1_in               : std_logic;
        signal rx1_out              : std_logic;
        signal rx1_dir              : std_logic;
        signal rx1_ren              : std_logic;
        signal rx1_ren_in           : std_logic;

--@UART1BLOCK:uart1-instance@
    uart1: UART
        port map (
            -- System Signals
            clk         => smclk,
            resetn       => resetn,

            -- Interrupt Signals
            irq_rc       => irq_uart1_rc,
            irq_te       => irq_uart1_te,
            irq_tc       => irq_uart1_tc,

            --@GEN:bus:uart1@

            -- Pad Interface
            TX_OUT      => tx1_out,
            TX_DIR      => tx1_dir,
            TX_REN      => tx1_ren,

            RX_IN       => rx1_in,
            RX_OUT      => rx1_out,
            RX_DIR      => rx1_dir,
            RX_REN      => rx1_ren
    );
