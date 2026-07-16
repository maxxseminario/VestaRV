// ============================================================================
// chip_top_quad.v -- CONNECTED structural chip-top netlist for Castalia-Quad
// (CQ), the 4xAFE quadrant-symmetric respin. M15 "Flavor B", QFN64 pad ring.
//
// CQ3b deliverable -- REPLACES the CQ3a provisional (which was a byte-copy of
// the C0 chip_top.v: 12 aio / 32 GPIO / C0 supply set). This is the REAL CQ
// pinout: 24 analog pads (16 PDB3A_G electrodes + 4 PVDD2ANA_G + 4 PVSS2ANA_G),
// symmetric digital supplies, resetn + 30 GPIO (2 dropped). Pin map + rationale:
// ~/vesta_docs/castalia_quad/cq3b_pin_map.md; placement order:
// tcl/chip_top_quad_padlists.tcl.
//
// The Castalia 4-hart MCU (mcu0, module MCU -- UNCHANGED from C0/M19c; the tile
// harden is orientation-only for CQ) inside the tphn65gpgv2od3_sl pad ring,
// WIRED: every digital pad's core-side pins (I/OEN/REN/C) connect to the MCU's
// resetn/prt1-4 quartets exactly as in the taped-out Myshkin vesta_chip
// (I<-prt_out, OEN<-prt_dir, REN<-prt_ren, C->prt_in; OEN active-low, baked
// into the GPIO RTL -- proven in silicon). Use the 8lm PDUW16SDGZ_G pad LEF.
//
// This file + in/MCU_MP_hier.pnr.v are the init_verilog set for the FLAT chip
// run (tcl/chip_top_quad.innovus.tcl, CQ4): the MCU hierarchy places/routes
// directly (tiles stay hardened LEF macros); there is NO MCU-as-macro level.
//
// a0/a0_1/a0_2/a0_3 (4x32 tb-visibility buses) are LEFT OPEN on mcu0 -- the
// Myshkin vesta_chip precedent (a<31:0> lands on internal nets that go nowhere).
// The flow dont_touches their driver logic; the pads-in-DUT gate tb observes
// them at the tiles' own ports (mcu0/hart<h>/a0, trim-proof).
//
// mcu0's module is named MCU -- the SAME name as the Myshkin tape-out cell. The
// collision lives at signoff strmin (topcell chip_top_quad != MCU triggers the
// guarded signoff_mp/strmin_gds.sh cellMap/topcell-pin/hard-gate, which pins
// mcu0's internal MCU cell AND the tphn P*_G pad family). NEVER raw-strmin this.
//
// ANALOG (digital-only tapeout: electrodes are pass-through, no core connection
// until the AFE IP exists -- cq_architecture.md "a re-cut, not a redesign"):
//   * 16 PDB3A_G electrodes -> flat aio[15:0] top port. Index map (aio[4*h+e],
//     e = 0:WE 1:RE 2:RE2 3:CE), h = quadrant/hart (0 TL,1 TR,2 BL,3 BR):
//        aio[0..3]  = WE_0 RE_0 RE2_0 CE_0   (AFE0, top-left  notch)
//        aio[4..7]  = WE_1 RE_1 RE2_1 CE_1   (AFE1, top-right notch)
//        aio[8..11] = WE_2 RE_2 RE2_2 CE_2   (AFE2, bot-left  notch)
//        aio[12..15]= WE_3 RE_3 RE2_3 CE_3   (AFE3, bot-right notch)
//     Flat bus chosen over per-quadrant buses for strmin/streamOut simplicity
//     (single inout bus, minimal diff from C0's aio[11:0]); the electrodes carry
//     no core net so per-quadrant naming would buy nothing structurally.
//   * 4x PVDD2ANA_G (AVDD_0..3) + 4x PVSS2ANA_G (AVSS_0..3): per-quadrant analog
//     supply pads (CQ1 decision #1). NO netlist connection -- same LEF rule as
//     C0's AVDD/AVSS: no USE class, ring-bus by abutment (Option A: no ring
//     cuts, isolation is nets-only). Per-quadrant net separation is a bond-map /
//     future-AFE concern; the digital-only netlist leaves them unconnected.
//
// DROPPED GPIO (30 of 32): prt3[0]=P2.0/GPIO16/T0CMP0 and prt3[4]=P2.4/GPIO20/
// T1CMP0 -- shallowest AF loss (timer-compare outputs, 0 globally-unique funcs,
// replicated across the AF spread). No pad. Handled below via the a0-dangle
// precedent EXTENDED to an input: mcu0.prt3_in[0]/[4] TIED 1'b0 (an input can't
// float); mcu0.prt3_out/dir/ren[0]/[4] left DANGLING (driven, unloaded, dont_
// touched). Top-level prt3[0]/[4] port bits are UNBONDED (no die pad).
// ============================================================================
module chip_top_quad (
    resetn,
    prt1, prt2, prt3, prt4,
    aio
);
    inout        resetn;
    inout [7:0]  prt1;    // P0: hart-0 SPI-flash boot quartet + LFXT/HFXT/TRAP/BOOT
    inout [7:0]  prt2;    // P1: SPI1 / UART0 / UART1
    inout [7:0]  prt3;    // P2: TIMER0/1 cap/cmp  -- bits [0],[4] UNBONDED (dropped)
    inout [7:0]  prt4;    // P3: I2C0/1 + DTP0-3
    inout [15:0] aio;     // 16 analog electrodes (4 quadrants x {WE,RE,RE2,CE})

    // -- core-side nets (MCU quartets) -------------------------------------
    wire        resetn_in, resetn_out, resetn_dir, resetn_ren;
    wire [7:0]  prt1_in, prt1_out, prt1_dir, prt1_ren;
    wire [7:0]  prt2_in, prt2_out, prt2_dir, prt2_ren;
    wire [7:0]  prt3_in, prt3_out, prt3_dir, prt3_ren;   // prt3_in[0],[4] tied at mcu0
    wire [7:0]  prt4_in, prt4_out, prt4_dir, prt4_ren;

    // -- digital bidirectional signal pads (resetn + 30 GPIO) --------------
    PDUW16SDGZ_G PAD_resetn (.I(resetn_out), .OEN(resetn_dir), .REN(resetn_ren),
                             .C(resetn_in), .PAD(resetn));

    // prt1[7:0] -- ALL kept (boot flash, upper-left edge)
    PDUW16SDGZ_G PAD_prt1_0 (.I(prt1_out[0]), .OEN(prt1_dir[0]), .REN(prt1_ren[0]), .C(prt1_in[0]), .PAD(prt1[0]));
    PDUW16SDGZ_G PAD_prt1_1 (.I(prt1_out[1]), .OEN(prt1_dir[1]), .REN(prt1_ren[1]), .C(prt1_in[1]), .PAD(prt1[1]));
    PDUW16SDGZ_G PAD_prt1_2 (.I(prt1_out[2]), .OEN(prt1_dir[2]), .REN(prt1_ren[2]), .C(prt1_in[2]), .PAD(prt1[2]));
    PDUW16SDGZ_G PAD_prt1_3 (.I(prt1_out[3]), .OEN(prt1_dir[3]), .REN(prt1_ren[3]), .C(prt1_in[3]), .PAD(prt1[3]));
    PDUW16SDGZ_G PAD_prt1_4 (.I(prt1_out[4]), .OEN(prt1_dir[4]), .REN(prt1_ren[4]), .C(prt1_in[4]), .PAD(prt1[4]));
    PDUW16SDGZ_G PAD_prt1_5 (.I(prt1_out[5]), .OEN(prt1_dir[5]), .REN(prt1_ren[5]), .C(prt1_in[5]), .PAD(prt1[5]));
    PDUW16SDGZ_G PAD_prt1_6 (.I(prt1_out[6]), .OEN(prt1_dir[6]), .REN(prt1_ren[6]), .C(prt1_in[6]), .PAD(prt1[6]));
    PDUW16SDGZ_G PAD_prt1_7 (.I(prt1_out[7]), .OEN(prt1_dir[7]), .REN(prt1_ren[7]), .C(prt1_in[7]), .PAD(prt1[7]));

    // prt2[7:0] -- ALL kept (right edge)
    PDUW16SDGZ_G PAD_prt2_0 (.I(prt2_out[0]), .OEN(prt2_dir[0]), .REN(prt2_ren[0]), .C(prt2_in[0]), .PAD(prt2[0]));
    PDUW16SDGZ_G PAD_prt2_1 (.I(prt2_out[1]), .OEN(prt2_dir[1]), .REN(prt2_ren[1]), .C(prt2_in[1]), .PAD(prt2[1]));
    PDUW16SDGZ_G PAD_prt2_2 (.I(prt2_out[2]), .OEN(prt2_dir[2]), .REN(prt2_ren[2]), .C(prt2_in[2]), .PAD(prt2[2]));
    PDUW16SDGZ_G PAD_prt2_3 (.I(prt2_out[3]), .OEN(prt2_dir[3]), .REN(prt2_ren[3]), .C(prt2_in[3]), .PAD(prt2[3]));
    PDUW16SDGZ_G PAD_prt2_4 (.I(prt2_out[4]), .OEN(prt2_dir[4]), .REN(prt2_ren[4]), .C(prt2_in[4]), .PAD(prt2[4]));
    PDUW16SDGZ_G PAD_prt2_5 (.I(prt2_out[5]), .OEN(prt2_dir[5]), .REN(prt2_ren[5]), .C(prt2_in[5]), .PAD(prt2[5]));
    PDUW16SDGZ_G PAD_prt2_6 (.I(prt2_out[6]), .OEN(prt2_dir[6]), .REN(prt2_ren[6]), .C(prt2_in[6]), .PAD(prt2[6]));
    PDUW16SDGZ_G PAD_prt2_7 (.I(prt2_out[7]), .OEN(prt2_dir[7]), .REN(prt2_ren[7]), .C(prt2_in[7]), .PAD(prt2[7]));

    // prt3 -- bits [0] and [4] DROPPED (no pad); [1,2,3,5,6] on LEFT, [7] on RIGHT
    PDUW16SDGZ_G PAD_prt3_1 (.I(prt3_out[1]), .OEN(prt3_dir[1]), .REN(prt3_ren[1]), .C(prt3_in[1]), .PAD(prt3[1]));
    PDUW16SDGZ_G PAD_prt3_2 (.I(prt3_out[2]), .OEN(prt3_dir[2]), .REN(prt3_ren[2]), .C(prt3_in[2]), .PAD(prt3[2]));
    PDUW16SDGZ_G PAD_prt3_3 (.I(prt3_out[3]), .OEN(prt3_dir[3]), .REN(prt3_ren[3]), .C(prt3_in[3]), .PAD(prt3[3]));
    PDUW16SDGZ_G PAD_prt3_5 (.I(prt3_out[5]), .OEN(prt3_dir[5]), .REN(prt3_ren[5]), .C(prt3_in[5]), .PAD(prt3[5]));
    PDUW16SDGZ_G PAD_prt3_6 (.I(prt3_out[6]), .OEN(prt3_dir[6]), .REN(prt3_ren[6]), .C(prt3_in[6]), .PAD(prt3[6]));
    PDUW16SDGZ_G PAD_prt3_7 (.I(prt3_out[7]), .OEN(prt3_dir[7]), .REN(prt3_ren[7]), .C(prt3_in[7]), .PAD(prt3[7]));

    // prt4[7:0] -- ALL kept ([0-3] I2C on RIGHT, [4,5] DTP on TOP, [6,7] DTP on BOTTOM)
    PDUW16SDGZ_G PAD_prt4_0 (.I(prt4_out[0]), .OEN(prt4_dir[0]), .REN(prt4_ren[0]), .C(prt4_in[0]), .PAD(prt4[0]));
    PDUW16SDGZ_G PAD_prt4_1 (.I(prt4_out[1]), .OEN(prt4_dir[1]), .REN(prt4_ren[1]), .C(prt4_in[1]), .PAD(prt4[1]));
    PDUW16SDGZ_G PAD_prt4_2 (.I(prt4_out[2]), .OEN(prt4_dir[2]), .REN(prt4_ren[2]), .C(prt4_in[2]), .PAD(prt4[2]));
    PDUW16SDGZ_G PAD_prt4_3 (.I(prt4_out[3]), .OEN(prt4_dir[3]), .REN(prt4_ren[3]), .C(prt4_in[3]), .PAD(prt4[3]));
    PDUW16SDGZ_G PAD_prt4_4 (.I(prt4_out[4]), .OEN(prt4_dir[4]), .REN(prt4_ren[4]), .C(prt4_in[4]), .PAD(prt4[4]));
    PDUW16SDGZ_G PAD_prt4_5 (.I(prt4_out[5]), .OEN(prt4_dir[5]), .REN(prt4_ren[5]), .C(prt4_in[5]), .PAD(prt4[5]));
    PDUW16SDGZ_G PAD_prt4_6 (.I(prt4_out[6]), .OEN(prt4_dir[6]), .REN(prt4_ren[6]), .C(prt4_in[6]), .PAD(prt4[6]));
    PDUW16SDGZ_G PAD_prt4_7 (.I(prt4_out[7]), .OEN(prt4_dir[7]), .REN(prt4_ren[7]), .C(prt4_in[7]), .PAD(prt4[7]));

    // -- analog electrode pads (PDB3A_G; pass-through, no core connection) --
    // AFE0 (top-left notch)
    PDB3A_G PAD_we_0  (.AIO(aio[0]));    // WE_0
    PDB3A_G PAD_re_0  (.AIO(aio[1]));    // RE_0
    PDB3A_G PAD_re2_0 (.AIO(aio[2]));    // RE2_0
    PDB3A_G PAD_ce_0  (.AIO(aio[3]));    // CE_0
    // AFE1 (top-right notch)
    PDB3A_G PAD_we_1  (.AIO(aio[4]));    // WE_1
    PDB3A_G PAD_re_1  (.AIO(aio[5]));    // RE_1
    PDB3A_G PAD_re2_1 (.AIO(aio[6]));    // RE2_1
    PDB3A_G PAD_ce_1  (.AIO(aio[7]));    // CE_1
    // AFE2 (bottom-left notch)
    PDB3A_G PAD_we_2  (.AIO(aio[8]));    // WE_2
    PDB3A_G PAD_re_2  (.AIO(aio[9]));    // RE_2
    PDB3A_G PAD_re2_2 (.AIO(aio[10]));   // RE2_2
    PDB3A_G PAD_ce_2  (.AIO(aio[11]));   // CE_2
    // AFE3 (bottom-right notch)
    PDB3A_G PAD_we_3  (.AIO(aio[12]));   // WE_3
    PDB3A_G PAD_re_3  (.AIO(aio[13]));   // RE_3
    PDB3A_G PAD_re2_3 (.AIO(aio[14]));   // RE2_3
    PDB3A_G PAD_ce_3  (.AIO(aio[15]));   // CE_3

    // -- supply pads (NO netlist connections; same LEF rules as C0) ---------
    // PVDD1DGZ_G.VDD=USE POWER / PVSS1DGZ_G.VSS=USE GROUND -> the flow's
    // globalNetConnect -type pgpin binds the core pair and a sroute -connect
    // padPin ties them to the core ring (2 pairs, left+right verticals).
    // VDDPST/VSSPST/AVDD/AVSS/POC have no USE class -> ring-bus by abutment,
    // netlist-UNCONNECTED (wiring them makes multi-pin signal nets the tracer
    // calls opens; filler ring metal is OBS, not pins).
    PVDD1DGZ_G PAD_vdd_l    ();               // core VDD, LEFT
    PVDD1DGZ_G PAD_vdd_r    ();               // core VDD, RIGHT
    PVSS1DGZ_G PAD_vss_l    ();               // core VSS, LEFT
    PVSS1DGZ_G PAD_vss_r    ();               // core VSS, RIGHT
    PVDD2DGZ_G PAD_vddpst_t ();               // IO 3.3V, TOP digital stretch
    PVDD2DGZ_G PAD_vddpst_b ();               // IO 3.3V, BOTTOM digital stretch
    PVSS2DGZ_G PAD_vsspst_t ();               // IO ground, TOP
    PVSS2DGZ_G PAD_vsspst_b ();               // IO ground, BOTTOM
    PVDD2ANA_G PAD_avdd_0   ();               // per-quadrant analog supply AVDD_0
    PVDD2ANA_G PAD_avdd_1   ();               // AVDD_1
    PVDD2ANA_G PAD_avdd_2   ();               // AVDD_2
    PVDD2ANA_G PAD_avdd_3   ();               // AVDD_3
    PVSS2ANA_G PAD_avss_0   ();               // AVSS_0
    PVSS2ANA_G PAD_avss_1   ();               // AVSS_1
    PVSS2ANA_G PAD_avss_2   ();               // AVSS_2
    PVSS2ANA_G PAD_avss_3   ();               // AVSS_3
    PVDD2POC_G PAD_poc      ();               // power-on-control (IO domain), RIGHT

    // -- corners (pinless; placed at the 4 die corners by the flow tcl) -----
    PCORNER_G PAD_CORNER_BL ();
    PCORNER_G PAD_CORNER_TL ();
    PCORNER_G PAD_CORNER_TR ();
    PCORNER_G PAD_CORNER_BR ();

    // -- the MCU (4-hart Castalia assembly; hierarchy from MCU_MP_hier.pnr.v)
    // a0/a0_1/a0_2/a0_3 tb-visibility buses LEFT OPEN (Myshkin precedent).
    // prt3_in[0] and prt3_in[4] TIED 1'b0 (dropped GPIO inputs cannot float);
    // prt3_out/dir/ren[0]/[4] are driven but unloaded (dangle, dont_touched).
    MCU mcu0 (
        .resetn_in  (resetn_in),
        .resetn_out (resetn_out),
        .resetn_dir (resetn_dir),
        .resetn_ren (resetn_ren),
        .prt1_in  (prt1_in),  .prt1_out (prt1_out), .prt1_dir (prt1_dir), .prt1_ren (prt1_ren),
        .prt2_in  (prt2_in),  .prt2_out (prt2_out), .prt2_dir (prt2_dir), .prt2_ren (prt2_ren),
        .prt3_in  ({prt3_in[7], prt3_in[6], prt3_in[5], 1'b0,
                    prt3_in[3], prt3_in[2], prt3_in[1], 1'b0}),
        .prt3_out (prt3_out), .prt3_dir (prt3_dir), .prt3_ren (prt3_ren),
        .prt4_in  (prt4_in),  .prt4_out (prt4_out), .prt4_dir (prt4_dir), .prt4_ren (prt4_ren)
    );

endmodule
