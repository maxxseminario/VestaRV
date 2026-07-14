// ============================================================================
// chip_top.v -- CONNECTED structural chip-top netlist (Castalia C0, M15
// "Flavor B").
//
// The Castalia 4-hart MCU_MP assembly inside the M15 tphn65gpgv2od3_sl pad
// ring, WIRED: every digital pad's core-side pins (I/OEN/REN/C) connect to the
// MCU's resetn/prt1-4 quartets exactly as in the taped-out Myshkin vesta_chip
// (pad_ring CDL: I<-prt_out, OEN<-prt_dir, REN<-prt_ren, C->prt_in; the OEN
// polarity contract is baked into the GPIO RTL -- proven in silicon). This is
// the same pad ring + wiring as the Argus A5 chip_top_argus.v (shared M15 pad
// machinery, Flavor A / Myshkin die-ring side order); the ONLY delta is the
// mcu0 instance is the 4-hart Castalia MCU (a0..a0_3, not a0..a0_17).
//
// This file + in/MCU_MP_hier.pnr.v together are the init_verilog set for the
// FLAT chip run (tcl/chip_top.innovus.tcl): the MCU hierarchy is placed/routed
// directly (tiles stay hardened LEF macros); there is NO MCU-as-macro level.
// See .devlog/2026-07-1X-castalia-c0-chip-top.md.
//
// a0/a0_1/a0_2/a0_3 (4x32 tb-visibility buses) are LEFT OPEN on the mcu0
// instance -- the Myshkin tape-out precedent (vesta_chip leaves a<31:0> on
// internal nets that go nowhere). The flow dont_touches their driver logic;
// the pads-in-DUT gate tb observes them via a Verilog XMR probe wrapper
// (primary probe path: the tiles' own ports mcu0/hart<h>/a0, trim-proof).
//
// mcu0's cell/module is named MCU -- the SAME name as the Myshkin tape-out
// cell. That collision is real but lives at signoff strmin, NOT here: the
// guarded signoff_mp/strmin_gds.sh cellMap/topcell-pin/hard-gate covers it
// (a chip_top wrapper does NOT exempt mcu0). NEVER stream this chip with a
// raw strmin.
//
// Analog electrode pads (PDB3A_G) pass through to top aio ports and have no
// core-side connection (Castalia C0 is DIGITAL-only; the ring is kept = shared
// Flavor A geometry, and the bottom aio band is reserved for the future 4xAFE
// potentiostat drop-in -- see the devlog "regions reserved for analog").
// POC + supply pads: ring-bus by abutment; the two core-domain VDD/VSS pad
// pairs are additionally hooked to the core grid in the tcl (padPin sroute).
//
// Pinout (Flavor A, Myshkin die-ring reference -- chip_top_padlists.tcl):
//   BOTTOM : AVSS, aio[0..11], AVDD          (analog, isolated)
//   TOP    : VSSIO, resetn, prt1[7:0], VDD, prt2[7:0], VDDIO
//   LEFT   : VSS,  prt3[7:0], VDDIO, POC
//   RIGHT  : VSS,  prt4[7:0], VSSIO, VDD
// ============================================================================
module chip_top (
    resetn,
    prt1, prt2, prt3, prt4,
    aio
);
    inout        resetn;
    inout [7:0]  prt1;
    inout [7:0]  prt2;
    inout [7:0]  prt3;
    inout [7:0]  prt4;
    inout [11:0] aio;      // 12 analog electrodes (reserved for the 4xAFE future)

    // -- core-side nets (MCU quartets) -------------------------------------
    wire        resetn_in, resetn_out, resetn_dir, resetn_ren;
    wire [7:0]  prt1_in, prt1_out, prt1_dir, prt1_ren;
    wire [7:0]  prt2_in, prt2_out, prt2_dir, prt2_ren;
    wire [7:0]  prt3_in, prt3_out, prt3_dir, prt3_ren;
    wire [7:0]  prt4_in, prt4_out, prt4_dir, prt4_ren;

    // -- digital bidirectional signal pads (reset + 32 GPIO) ---------------
    PDUW16SDGZ_G PAD_resetn (.I(resetn_out), .OEN(resetn_dir), .REN(resetn_ren),
                             .C(resetn_in), .PAD(resetn));

    PDUW16SDGZ_G PAD_prt1_0 (.I(prt1_out[0]), .OEN(prt1_dir[0]), .REN(prt1_ren[0]), .C(prt1_in[0]), .PAD(prt1[0]));
    PDUW16SDGZ_G PAD_prt1_1 (.I(prt1_out[1]), .OEN(prt1_dir[1]), .REN(prt1_ren[1]), .C(prt1_in[1]), .PAD(prt1[1]));
    PDUW16SDGZ_G PAD_prt1_2 (.I(prt1_out[2]), .OEN(prt1_dir[2]), .REN(prt1_ren[2]), .C(prt1_in[2]), .PAD(prt1[2]));
    PDUW16SDGZ_G PAD_prt1_3 (.I(prt1_out[3]), .OEN(prt1_dir[3]), .REN(prt1_ren[3]), .C(prt1_in[3]), .PAD(prt1[3]));
    PDUW16SDGZ_G PAD_prt1_4 (.I(prt1_out[4]), .OEN(prt1_dir[4]), .REN(prt1_ren[4]), .C(prt1_in[4]), .PAD(prt1[4]));
    PDUW16SDGZ_G PAD_prt1_5 (.I(prt1_out[5]), .OEN(prt1_dir[5]), .REN(prt1_ren[5]), .C(prt1_in[5]), .PAD(prt1[5]));
    PDUW16SDGZ_G PAD_prt1_6 (.I(prt1_out[6]), .OEN(prt1_dir[6]), .REN(prt1_ren[6]), .C(prt1_in[6]), .PAD(prt1[6]));
    PDUW16SDGZ_G PAD_prt1_7 (.I(prt1_out[7]), .OEN(prt1_dir[7]), .REN(prt1_ren[7]), .C(prt1_in[7]), .PAD(prt1[7]));

    PDUW16SDGZ_G PAD_prt2_0 (.I(prt2_out[0]), .OEN(prt2_dir[0]), .REN(prt2_ren[0]), .C(prt2_in[0]), .PAD(prt2[0]));
    PDUW16SDGZ_G PAD_prt2_1 (.I(prt2_out[1]), .OEN(prt2_dir[1]), .REN(prt2_ren[1]), .C(prt2_in[1]), .PAD(prt2[1]));
    PDUW16SDGZ_G PAD_prt2_2 (.I(prt2_out[2]), .OEN(prt2_dir[2]), .REN(prt2_ren[2]), .C(prt2_in[2]), .PAD(prt2[2]));
    PDUW16SDGZ_G PAD_prt2_3 (.I(prt2_out[3]), .OEN(prt2_dir[3]), .REN(prt2_ren[3]), .C(prt2_in[3]), .PAD(prt2[3]));
    PDUW16SDGZ_G PAD_prt2_4 (.I(prt2_out[4]), .OEN(prt2_dir[4]), .REN(prt2_ren[4]), .C(prt2_in[4]), .PAD(prt2[4]));
    PDUW16SDGZ_G PAD_prt2_5 (.I(prt2_out[5]), .OEN(prt2_dir[5]), .REN(prt2_ren[5]), .C(prt2_in[5]), .PAD(prt2[5]));
    PDUW16SDGZ_G PAD_prt2_6 (.I(prt2_out[6]), .OEN(prt2_dir[6]), .REN(prt2_ren[6]), .C(prt2_in[6]), .PAD(prt2[6]));
    PDUW16SDGZ_G PAD_prt2_7 (.I(prt2_out[7]), .OEN(prt2_dir[7]), .REN(prt2_ren[7]), .C(prt2_in[7]), .PAD(prt2[7]));

    PDUW16SDGZ_G PAD_prt3_0 (.I(prt3_out[0]), .OEN(prt3_dir[0]), .REN(prt3_ren[0]), .C(prt3_in[0]), .PAD(prt3[0]));
    PDUW16SDGZ_G PAD_prt3_1 (.I(prt3_out[1]), .OEN(prt3_dir[1]), .REN(prt3_ren[1]), .C(prt3_in[1]), .PAD(prt3[1]));
    PDUW16SDGZ_G PAD_prt3_2 (.I(prt3_out[2]), .OEN(prt3_dir[2]), .REN(prt3_ren[2]), .C(prt3_in[2]), .PAD(prt3[2]));
    PDUW16SDGZ_G PAD_prt3_3 (.I(prt3_out[3]), .OEN(prt3_dir[3]), .REN(prt3_ren[3]), .C(prt3_in[3]), .PAD(prt3[3]));
    PDUW16SDGZ_G PAD_prt3_4 (.I(prt3_out[4]), .OEN(prt3_dir[4]), .REN(prt3_ren[4]), .C(prt3_in[4]), .PAD(prt3[4]));
    PDUW16SDGZ_G PAD_prt3_5 (.I(prt3_out[5]), .OEN(prt3_dir[5]), .REN(prt3_ren[5]), .C(prt3_in[5]), .PAD(prt3[5]));
    PDUW16SDGZ_G PAD_prt3_6 (.I(prt3_out[6]), .OEN(prt3_dir[6]), .REN(prt3_ren[6]), .C(prt3_in[6]), .PAD(prt3[6]));
    PDUW16SDGZ_G PAD_prt3_7 (.I(prt3_out[7]), .OEN(prt3_dir[7]), .REN(prt3_ren[7]), .C(prt3_in[7]), .PAD(prt3[7]));

    PDUW16SDGZ_G PAD_prt4_0 (.I(prt4_out[0]), .OEN(prt4_dir[0]), .REN(prt4_ren[0]), .C(prt4_in[0]), .PAD(prt4[0]));
    PDUW16SDGZ_G PAD_prt4_1 (.I(prt4_out[1]), .OEN(prt4_dir[1]), .REN(prt4_ren[1]), .C(prt4_in[1]), .PAD(prt4[1]));
    PDUW16SDGZ_G PAD_prt4_2 (.I(prt4_out[2]), .OEN(prt4_dir[2]), .REN(prt4_ren[2]), .C(prt4_in[2]), .PAD(prt4[2]));
    PDUW16SDGZ_G PAD_prt4_3 (.I(prt4_out[3]), .OEN(prt4_dir[3]), .REN(prt4_ren[3]), .C(prt4_in[3]), .PAD(prt4[3]));
    PDUW16SDGZ_G PAD_prt4_4 (.I(prt4_out[4]), .OEN(prt4_dir[4]), .REN(prt4_ren[4]), .C(prt4_in[4]), .PAD(prt4[4]));
    PDUW16SDGZ_G PAD_prt4_5 (.I(prt4_out[5]), .OEN(prt4_dir[5]), .REN(prt4_ren[5]), .C(prt4_in[5]), .PAD(prt4[5]));
    PDUW16SDGZ_G PAD_prt4_6 (.I(prt4_out[6]), .OEN(prt4_dir[6]), .REN(prt4_ren[6]), .C(prt4_in[6]), .PAD(prt4[6]));
    PDUW16SDGZ_G PAD_prt4_7 (.I(prt4_out[7]), .OEN(prt4_dir[7]), .REN(prt4_ren[7]), .C(prt4_in[7]), .PAD(prt4[7]));

    // -- analog electrode pads (pass-through; no core connection) ----------
    // Reserved for the future 4xAFE potentiostat channels ({WE,RE,CE} x 4).
    PDB3A_G PAD_aio_0  (.AIO(aio[0]));
    PDB3A_G PAD_aio_1  (.AIO(aio[1]));
    PDB3A_G PAD_aio_2  (.AIO(aio[2]));
    PDB3A_G PAD_aio_3  (.AIO(aio[3]));
    PDB3A_G PAD_aio_4  (.AIO(aio[4]));
    PDB3A_G PAD_aio_5  (.AIO(aio[5]));
    PDB3A_G PAD_aio_6  (.AIO(aio[6]));
    PDB3A_G PAD_aio_7  (.AIO(aio[7]));
    PDB3A_G PAD_aio_8  (.AIO(aio[8]));
    PDB3A_G PAD_aio_9  (.AIO(aio[9]));
    PDB3A_G PAD_aio_10 (.AIO(aio[10]));
    PDB3A_G PAD_aio_11 (.AIO(aio[11]));

    // -- supply pads ---------------------------------------------------------
    // NO netlist connections. LEF facts (8lm tphn, verified 2026-07-12 -- the
    // M15 "supply pins are signal PINs" note is WRONG for this variant):
    // PVDD1DGZ_G.VDD = USE POWER and PVSS1DGZ_G.VSS = USE GROUND, so the
    // flow's existing globalNetConnect -type pgpin -inst * binds the
    // core-domain pair onto VDD/VSS and a dedicated sroute -connect padPin
    // pass ties them to the core ring. VDDPST/VSSPST/AVDD/AVSS/POC pins have
    // no USE class and no core-side consumer: they are ring-bus rails by
    // pad/filler abutment only -- netlist-wiring them (the M15 stub form)
    // would create multi-pin signal nets that regular verifyConnectivity
    // reports as opens (filler ring metal is OBS, not pins).
    PVDD1DGZ_G PAD_vdd_0   ();               // digital core
    PVDD1DGZ_G PAD_vdd_1   ();
    PVSS1DGZ_G PAD_vss_0   ();
    PVSS1DGZ_G PAD_vss_1   ();
    PVDD2DGZ_G PAD_vddio_0 ();               // digital IO 3.3V
    PVDD2DGZ_G PAD_vddio_1 ();
    PVSS2DGZ_G PAD_vssio_0 ();
    PVSS2DGZ_G PAD_vssio_1 ();
    PVDD2ANA_G PAD_avdd    ();               // analog
    PVSS2ANA_G PAD_avss    ();
    PVDD2POC_G PAD_poc     ();               // power-on-control (IO domain)

    // -- corners (pinless; placed at the 4 die corners in the tcl) ----------
    PCORNER_G PAD_CORNER_BL ();
    PCORNER_G PAD_CORNER_TL ();
    PCORNER_G PAD_CORNER_TR ();
    PCORNER_G PAD_CORNER_BR ();

    // -- the MCU (4-hart Castalia assembly; hierarchy from MCU_MP_hier.pnr.v)
    // a0/a0_1/a0_2/a0_3 tb-visibility buses LEFT OPEN (Myshkin vesta_chip
    // precedent); their driver logic is dont_touched in the flow.
    MCU mcu0 (
        .resetn_in  (resetn_in),
        .resetn_out (resetn_out),
        .resetn_dir (resetn_dir),
        .resetn_ren (resetn_ren),
        .prt1_in  (prt1_in),  .prt1_out (prt1_out), .prt1_dir (prt1_dir), .prt1_ren (prt1_ren),
        .prt2_in  (prt2_in),  .prt2_out (prt2_out), .prt2_dir (prt2_dir), .prt2_ren (prt2_ren),
        .prt3_in  (prt3_in),  .prt3_out (prt3_out), .prt3_dir (prt3_dir), .prt3_ren (prt3_ren),
        .prt4_in  (prt4_in),  .prt4_out (prt4_out), .prt4_dir (prt4_dir), .prt4_ren (prt4_ren)
    );

endmodule
