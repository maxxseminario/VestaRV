// ============================================================================
// chip_top_sim.v -- A5 pads-in-DUT gate-sim wrapper (SIM ONLY, not P&R input).
//
// Wraps the post-P&R chip netlist (out/chip_top_argus.xsim.clean.v) and
// exports the tb-visibility signals via ALL-VERILOG hierarchical references
// (legal: chip_top, MCU and the tiles are all Verilog below this scope; a
// VHDL tb could not XMR into the DUT directly).
//   a0 buses  : probed at the TILES' OWN ports (mcu0.hart<h>.a0) -- trim-proof
//               (the tile netlist is a hardened leaf; MCU-level a0 nets are
//               dont_touched in the flow but nothing depends on that here).
//   prtN_dir  : probed at the pad instances' OEN pins (leaf ports never get
//               renamed/bit-blasted, unlike internal bus nets) -- the tb's
//               peripheral short-connection machinery keys on these.
// ============================================================================
module chip_top_sim (
    resetn_pad, prt1, prt2, prt3, prt4,
    prt1_dir, prt2_dir, prt3_dir, prt4_dir,
    a0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, a0_8, a0_9, a0_10, a0_11, a0_12, a0_13, a0_14, a0_15, a0_16, a0_17);

    inout        resetn_pad;
    inout  [7:0] prt1, prt2, prt3, prt4;
    output [7:0] prt1_dir, prt2_dir, prt3_dir, prt4_dir;
    output [31:0] a0, a0_1, a0_2, a0_3, a0_4, a0_5, a0_6, a0_7, a0_8, a0_9, a0_10, a0_11, a0_12, a0_13, a0_14, a0_15, a0_16, a0_17;

    wire [11:0] aio;   // analog electrode pads: pass-through, unused in sim

    chip_top chip (
        .resetn (resetn_pad),
        .prt1 (prt1), .prt2 (prt2), .prt3 (prt3), .prt4 (prt4),
        .aio (aio)
    );

    // --- a0 probes: tile ports (hart_tile declares 'output [31:0] a0') ---
    assign a0     = chip.mcu0.hart0.a0;
    assign a0_1   = chip.mcu0.hart1.a0;
    assign a0_2   = chip.mcu0.hart2.a0;
    assign a0_3   = chip.mcu0.hart3.a0;
    assign a0_4   = chip.mcu0.hart4.a0;
    assign a0_5   = chip.mcu0.hart5.a0;
    assign a0_6   = chip.mcu0.hart6.a0;
    assign a0_7   = chip.mcu0.hart7.a0;
    assign a0_8   = chip.mcu0.hart8.a0;
    assign a0_9   = chip.mcu0.hart9.a0;
    assign a0_10  = chip.mcu0.hart10.a0;
    assign a0_11  = chip.mcu0.hart11.a0;
    assign a0_12  = chip.mcu0.hart12.a0;
    assign a0_13  = chip.mcu0.hart13.a0;
    assign a0_14  = chip.mcu0.hart14.a0;
    assign a0_15  = chip.mcu0.hart15.a0;
    assign a0_16  = chip.mcu0.hart16.a0;
    assign a0_17  = chip.mcu0.hart17.a0;

    // --- dir probes: pad OEN pins (per-bit; leaf instance ports) ---
    assign prt1_dir[0] = chip.PAD_prt1_0.OEN;
    assign prt1_dir[1] = chip.PAD_prt1_1.OEN;
    assign prt1_dir[2] = chip.PAD_prt1_2.OEN;
    assign prt1_dir[3] = chip.PAD_prt1_3.OEN;
    assign prt1_dir[4] = chip.PAD_prt1_4.OEN;
    assign prt1_dir[5] = chip.PAD_prt1_5.OEN;
    assign prt1_dir[6] = chip.PAD_prt1_6.OEN;
    assign prt1_dir[7] = chip.PAD_prt1_7.OEN;
    assign prt2_dir[0] = chip.PAD_prt2_0.OEN;
    assign prt2_dir[1] = chip.PAD_prt2_1.OEN;
    assign prt2_dir[2] = chip.PAD_prt2_2.OEN;
    assign prt2_dir[3] = chip.PAD_prt2_3.OEN;
    assign prt2_dir[4] = chip.PAD_prt2_4.OEN;
    assign prt2_dir[5] = chip.PAD_prt2_5.OEN;
    assign prt2_dir[6] = chip.PAD_prt2_6.OEN;
    assign prt2_dir[7] = chip.PAD_prt2_7.OEN;
    assign prt3_dir[0] = chip.PAD_prt3_0.OEN;
    assign prt3_dir[1] = chip.PAD_prt3_1.OEN;
    assign prt3_dir[2] = chip.PAD_prt3_2.OEN;
    assign prt3_dir[3] = chip.PAD_prt3_3.OEN;
    assign prt3_dir[4] = chip.PAD_prt3_4.OEN;
    assign prt3_dir[5] = chip.PAD_prt3_5.OEN;
    assign prt3_dir[6] = chip.PAD_prt3_6.OEN;
    assign prt3_dir[7] = chip.PAD_prt3_7.OEN;
    assign prt4_dir[0] = chip.PAD_prt4_0.OEN;
    assign prt4_dir[1] = chip.PAD_prt4_1.OEN;
    assign prt4_dir[2] = chip.PAD_prt4_2.OEN;
    assign prt4_dir[3] = chip.PAD_prt4_3.OEN;
    assign prt4_dir[4] = chip.PAD_prt4_4.OEN;
    assign prt4_dir[5] = chip.PAD_prt4_5.OEN;
    assign prt4_dir[6] = chip.PAD_prt4_6.OEN;
    assign prt4_dir[7] = chip.PAD_prt4_7.OEN;

endmodule
