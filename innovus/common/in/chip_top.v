// ============================================================================
// chip_top.v -- STUB structural netlist for the M15 pad-ring floorplan
// prototype (Flavor A: geometry only).
//
// This is NOT the functional chip wrapper. It exists ONLY to give Innovus a
// set of real pad instances to place into a ring. The MCU core is deliberately
// absent -- the interior is reserved with a placement blockage in the
// chip_top.innovus.tcl run. The core-facing pins of the signal pads (I/OEN/
// REN/C) are intentionally left unconnected; the deliverable is the physical
// ring, not connectivity.
//
// Pad cells are the tphn65gpgv2od3_sl library (the SAME cells the gate tb
// instantiates, PDUW16SDGZ_G etc.) -- LEF macros carry matching names in
// tphn65gpgv2od3_sl_210a/mt_2/9lm/lef. (constants.tcl's IO_PAD_DIR still points
// at the tpfn* twin, whose macros lack the _G suffix and the SD signal pad --
// chip_top.innovus.tcl overrides IO_PAD_DIR to the tphn LEF.)
//
// Pinout (analog domain isolated on the BOTTOM edge):
//   BOTTOM : AVSS, aio[0..11] (4 sensors x 3 electrodes), AVDD
//   TOP    : VSSIO, resetn, prt1[7:0], VDD, prt2[7:0], VDDIO
//   LEFT   : VSS,  prt3[7:0], VDDIO, POC
//   RIGHT  : VSS,  prt4[7:0], VSSIO, VDD
//   corners+fillers : added physically in the tcl (no netlist rep)
// ============================================================================
module chip_top (
    resetn,
    prt1, prt2, prt3, prt4,
    aio,
    vdd, vss, vddio, vssio, avdd, avss
);
    inout        resetn;
    inout [7:0]  prt1;
    inout [7:0]  prt2;
    inout [7:0]  prt3;
    inout [7:0]  prt4;
    inout [11:0] aio;      // 12 analog electrodes: {WE,RE,CE} x 4 channels
    inout        vdd;      // digital core supply
    inout        vss;
    inout        vddio;    // digital IO (3.3V) supply
    inout        vssio;
    inout        avdd;     // analog supply
    inout        avss;

    // -- digital bidirectional signal pads (reset + 32 GPIO) --------------
    PDUW16SDGZ_G PAD_resetn (.PAD(resetn));

    PDUW16SDGZ_G PAD_prt1_0 (.PAD(prt1[0]));
    PDUW16SDGZ_G PAD_prt1_1 (.PAD(prt1[1]));
    PDUW16SDGZ_G PAD_prt1_2 (.PAD(prt1[2]));
    PDUW16SDGZ_G PAD_prt1_3 (.PAD(prt1[3]));
    PDUW16SDGZ_G PAD_prt1_4 (.PAD(prt1[4]));
    PDUW16SDGZ_G PAD_prt1_5 (.PAD(prt1[5]));
    PDUW16SDGZ_G PAD_prt1_6 (.PAD(prt1[6]));
    PDUW16SDGZ_G PAD_prt1_7 (.PAD(prt1[7]));

    PDUW16SDGZ_G PAD_prt2_0 (.PAD(prt2[0]));
    PDUW16SDGZ_G PAD_prt2_1 (.PAD(prt2[1]));
    PDUW16SDGZ_G PAD_prt2_2 (.PAD(prt2[2]));
    PDUW16SDGZ_G PAD_prt2_3 (.PAD(prt2[3]));
    PDUW16SDGZ_G PAD_prt2_4 (.PAD(prt2[4]));
    PDUW16SDGZ_G PAD_prt2_5 (.PAD(prt2[5]));
    PDUW16SDGZ_G PAD_prt2_6 (.PAD(prt2[6]));
    PDUW16SDGZ_G PAD_prt2_7 (.PAD(prt2[7]));

    PDUW16SDGZ_G PAD_prt3_0 (.PAD(prt3[0]));
    PDUW16SDGZ_G PAD_prt3_1 (.PAD(prt3[1]));
    PDUW16SDGZ_G PAD_prt3_2 (.PAD(prt3[2]));
    PDUW16SDGZ_G PAD_prt3_3 (.PAD(prt3[3]));
    PDUW16SDGZ_G PAD_prt3_4 (.PAD(prt3[4]));
    PDUW16SDGZ_G PAD_prt3_5 (.PAD(prt3[5]));
    PDUW16SDGZ_G PAD_prt3_6 (.PAD(prt3[6]));
    PDUW16SDGZ_G PAD_prt3_7 (.PAD(prt3[7]));

    PDUW16SDGZ_G PAD_prt4_0 (.PAD(prt4[0]));
    PDUW16SDGZ_G PAD_prt4_1 (.PAD(prt4[1]));
    PDUW16SDGZ_G PAD_prt4_2 (.PAD(prt4[2]));
    PDUW16SDGZ_G PAD_prt4_3 (.PAD(prt4[3]));
    PDUW16SDGZ_G PAD_prt4_4 (.PAD(prt4[4]));
    PDUW16SDGZ_G PAD_prt4_5 (.PAD(prt4[5]));
    PDUW16SDGZ_G PAD_prt4_6 (.PAD(prt4[6]));
    PDUW16SDGZ_G PAD_prt4_7 (.PAD(prt4[7]));

    // -- analog electrode pads (12: 4x 3-electrode) -----------------------
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

    // -- supply pads ------------------------------------------------------
    PVDD1DGZ_G PAD_vdd_0   (.VDD(vdd));      // digital core
    PVDD1DGZ_G PAD_vdd_1   (.VDD(vdd));
    PVSS1DGZ_G PAD_vss_0   (.VSS(vss));
    PVSS1DGZ_G PAD_vss_1   (.VSS(vss));
    PVDD2DGZ_G PAD_vddio_0 (.VDDPST(vddio)); // digital IO 3.3V
    PVDD2DGZ_G PAD_vddio_1 (.VDDPST(vddio));
    PVSS2DGZ_G PAD_vssio_0 (.VSSPST(vssio));
    PVSS2DGZ_G PAD_vssio_1 (.VSSPST(vssio));
    PVDD2ANA_G PAD_avdd    (.AVDD(avdd));    // analog
    PVSS2ANA_G PAD_avss    (.AVSS(avss));
    PVDD2POC_G PAD_poc     (.VDDPST(vddio)); // power-on-control (IO domain)

    // -- corners (pinless; placed at the 4 die corners in the tcl) --------
    PCORNER_G PAD_CORNER_BL ();
    PCORNER_G PAD_CORNER_TL ();
    PCORNER_G PAD_CORNER_TR ();
    PCORNER_G PAD_CORNER_BR ();

endmodule
