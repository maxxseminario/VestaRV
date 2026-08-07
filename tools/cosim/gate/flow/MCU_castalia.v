// MCU_castalia -- the WOUND-PATCH SoC (MCU_WOUND assembly) in the tphn
// LQFP-100 pad ring, on the QUADRANT-SYMMETRIC Castalia-Quad floorplan.
// BYTE-IDENTICAL to in/chip_top_wound.v except the module NAME on line 28:
// the pad ring, the pad cell types (incl. the two PDDW16SDGZ_G pull-DOWN pads),
// the mcu0 port map and the dangling a0 buses are all unchanged -- the quad
// re-cut changes only where things sit on the die, never the netlist.
// (chip_top_wound.v itself was cloned from in/chip_top_dp.v, the Stage-G2
// golden example; its ONLY functional delta over DP is the PDDW16SDGZ_G
// pull-DOWN swap on PAD_P5_6/PAD_P5_7 -- see below.)
// Pattern = C0 in/chip_top.v (M15 Flavor B): PDUW16SDGZ_G bidi pads for
// RESETN + 48 GPIO; supply pads instantiated PINLESS (netlist-wiring them
// creates phantom tracer opens -- the C0 comment block rationale holds) and
// bound only by globalNetConnect + the sroute padPin pass; ARSV0-7 are
// PDB3A_G analog pass-throughs with NO core-side connection (reserve band).
// a0/a0_1..3 dangle (Myshkin precedent; dont_touch in the chip SDC) -- NEVER
// route them to pads.
//
// MCU PORT LIST: verified 2026-07-26 IDENTICAL between genus/out/
// MCU_WOUND.genus.v and genus/out/MCU_DP_hier.genus.v (module MCU header +
// all input/output declarations byte-identical; the first difference is an
// internal `wire` declaration). The wound deltas (QSPI/I3C/NFC/OW/I2CT/TRNG/
// EVFAB, 4ch DMA) are all internal or ride AF spread slots on the SAME
// prt1-6 quartets. So the mcu0 port map below is unchanged from DP.
//
// PIN-COMMENT CAVEAT: the alt-function names in the per-pad comments come
// from the LQFP-100 padring emission, which names GPIO PRIMARY functions only
// -- it does not carry the wound AF planes. Notably OW0's 1-Wire DQ is on
// register P4.7 = padring P3_7 = pin 44, AF2 (2026-07-26 re-pin); it keeps the
// pull-UP PDUW16SDGZ_G cell, which is what an idle 1-Wire bus wants.
//
// DP-S3 (BINDING): PAD_P5_6/PAD_P5_7 (pins 68/69) are the claimed
// field/harvest strap + PGOOD pins and MUST be pull-DOWN cells.
//
// ===========================================================================
// D3 JTAG PAD ADDITION -- 2026-08-06 (R-DD4(2), USER decision; d3_spec 5).
// FIVE new pads: 47=TCK, 48=TMS, 49=TDI, 50=TDO on the SOUTH edge and
// 51=TRSTn on the EAST edge -- all five were package NC balls with no die-side
// pad instance at all before this edit. Cells (R-DD1 as annotated): TCK and
// TRSTn are PDDW16SDGZ_G (pull-DOWN), TMS/TDI/TDO are PDUW16SDGZ_G (pull-UP).
// TMS pull-up is IEEE 1149.1 conformant; TRSTn pull-DOWN is the DOCUMENTED
// DEVIATION from 1149.1's idle-high -- floating or unbonded TRSTn holds the
// TAP in reset, so the debug transport is inert unless a probe deliberately
// drives it. The pull direction is invisible in LEF (the two cells are
// footprint-identical, 25x135), so it lives in these cell names and nowhere
// else -- do not "normalise" them.
//
// ***** THIS NETLIST NOW REQUIRES A DEBUG-ON MCU. ***** The five mcu0
// connections below name MCU entity ports that exist ONLY in a
// debug.enable build. It is an INPUT to the close-of-programme re-cut
// (DD6), where the debug-ON wound build decision is made; running the
// current debug-OFF MCU_WOUND netlist through this file will fail loudly on
// unknown mcu0 pins, and that is the intended, visible outcome rather than a
// silent mis-wire. The SIGNED-OFF reference cut is NOT touched: its DB, GDS
// and reports still describe the pre-JTAG ring, and the pre-edit netlist is
// preserved verbatim beside this file as MCU_castalia.v.pre_d3.
//
// GEOMETRY CONSEQUENCE, stated because it is not a drop-in: place_pad CENTRES
// each side's contiguous pad block, so adding four pads to SOUTH and one to
// EAST re-centres those rows and MOVES EVERY ALREADY-PLACED PAD on them
// (-50 um on S, -12.5 um on E). Die-side room is ample (the S row's block
// occupied ~500 um of a 2690 um span); the binding constraint was always the
// package model, which gains the five balls in the same change.
// NOTHING LANDS ON THE NORTH EDGE -- absolutely, for two independent reasons:
// inside the PRCUT-isolated analog island there is no digital VDDPST/VSSPST
// to power a pad, and outside the cuts the north segment is severed from the
// digital IO ring. No place_side change accompanies this edit.
// ===========================================================================
module MCU_castalia(resetn, prt1, prt2, prt3, prt4, prt5, prt6,
                   tck, tms, tdi, tdo, trstn);
  inout resetn;
  inout [7:0] prt1, prt2, prt3, prt4, prt5, prt6;
  // D3 JTAG pins. Declared inout like every other pad-backed port here (the
  // PAD terminal is the bidirectional cell pin); tck/tms/tdi/trstn are inputs
  // in function and tdo is an output.
  inout tck, tms, tdi, tdo, trstn;

  wire resetn_in, resetn_out, resetn_dir, resetn_ren;
  wire [7:0] prt1_in, prt1_out, prt1_dir, prt1_ren;
  wire [7:0] prt2_in, prt2_out, prt2_dir, prt2_ren;
  wire [7:0] prt3_in, prt3_out, prt3_dir, prt3_ren;
  wire [7:0] prt4_in, prt4_out, prt4_dir, prt4_ren;
  wire [7:0] prt5_in, prt5_out, prt5_dir, prt5_ren;
  wire [7:0] prt6_in, prt6_out, prt6_dir, prt6_ren;
  wire [31:0] a0, a0_1, a0_2, a0_3;
  // D3: core-side JTAG nets. The four inputs come off the pads' C receivers;
  // tdo_out drives the TDO pad's I.
  wire tck_in, tms_in, tdi_in, trstn_in, tdo_out;

  PDUW16SDGZ_G PAD_RESETN (.I(resetn_out), .OEN(resetn_dir), .REN(resetn_ren), .C(resetn_in), .PAD(resetn));
  PDUW16SDGZ_G PAD_P1_7 (.I(prt2_out[7]), .OEN(prt2_dir[7]), .REN(prt2_ren[7]), .C(prt2_in[7]), .PAD(prt2[7]));  // pin 22: P1.7(GPIO15)/RX1
  PDUW16SDGZ_G PAD_P1_6 (.I(prt2_out[6]), .OEN(prt2_dir[6]), .REN(prt2_ren[6]), .C(prt2_in[6]), .PAD(prt2[6]));  // pin 21: P1.6(GPIO14)/TX1
  PDUW16SDGZ_G PAD_P1_5 (.I(prt2_out[5]), .OEN(prt2_dir[5]), .REN(prt2_ren[5]), .C(prt2_in[5]), .PAD(prt2[5]));  // pin 20: P1.5(GPIO13)/RX0
  PDUW16SDGZ_G PAD_P1_4 (.I(prt2_out[4]), .OEN(prt2_dir[4]), .REN(prt2_ren[4]), .C(prt2_in[4]), .PAD(prt2[4]));  // pin 19: P1.4(GPIO12)/TX0
  PDUW16SDGZ_G PAD_P1_3 (.I(prt2_out[3]), .OEN(prt2_dir[3]), .REN(prt2_ren[3]), .C(prt2_in[3]), .PAD(prt2[3]));  // pin 18: P1.3(GPIO11)/SCK1
  PDUW16SDGZ_G PAD_P1_2 (.I(prt2_out[2]), .OEN(prt2_dir[2]), .REN(prt2_ren[2]), .C(prt2_in[2]), .PAD(prt2[2]));  // pin 17: P1.2(GPIO10)/MOSI1
  PDUW16SDGZ_G PAD_P1_1 (.I(prt2_out[1]), .OEN(prt2_dir[1]), .REN(prt2_ren[1]), .C(prt2_in[1]), .PAD(prt2[1]));  // pin 16: P1.1(GPIO9)/MISO1
  PDUW16SDGZ_G PAD_P1_0 (.I(prt2_out[0]), .OEN(prt2_dir[0]), .REN(prt2_ren[0]), .C(prt2_in[0]), .PAD(prt2[0]));  // pin 15: P1.0(GPIO8)/CS1
  PDUW16SDGZ_G PAD_P0_7 (.I(prt1_out[7]), .OEN(prt1_dir[7]), .REN(prt1_ren[7]), .C(prt1_in[7]), .PAD(prt1[7]));  // pin 12: P0.7(BOOT)
  PDUW16SDGZ_G PAD_P0_6 (.I(prt1_out[6]), .OEN(prt1_dir[6]), .REN(prt1_ren[6]), .C(prt1_in[6]), .PAD(prt1[6]));  // pin 11: P0.6(GPIO6)/TRAP
  PDUW16SDGZ_G PAD_P0_5 (.I(prt1_out[5]), .OEN(prt1_dir[5]), .REN(prt1_ren[5]), .C(prt1_in[5]), .PAD(prt1[5]));  // pin 10: P0.5(GPIO5)/HFXT
  PDUW16SDGZ_G PAD_P0_4 (.I(prt1_out[4]), .OEN(prt1_dir[4]), .REN(prt1_ren[4]), .C(prt1_in[4]), .PAD(prt1[4]));  // pin 9: P0.4(GPIO4)/LFXT
  PDUW16SDGZ_G PAD_P0_3 (.I(prt1_out[3]), .OEN(prt1_dir[3]), .REN(prt1_ren[3]), .C(prt1_in[3]), .PAD(prt1[3]));  // pin 8: P0.3(GPIO3)/SCK0
  PDUW16SDGZ_G PAD_P0_2 (.I(prt1_out[2]), .OEN(prt1_dir[2]), .REN(prt1_ren[2]), .C(prt1_in[2]), .PAD(prt1[2]));  // pin 7: P0.2(GPIO2)/MOSI0
  PDUW16SDGZ_G PAD_P0_1 (.I(prt1_out[1]), .OEN(prt1_dir[1]), .REN(prt1_ren[1]), .C(prt1_in[1]), .PAD(prt1[1]));  // pin 6: P0.1(GPIO1)/MISO0
  PDUW16SDGZ_G PAD_P0_0 (.I(prt1_out[0]), .OEN(prt1_dir[0]), .REN(prt1_ren[0]), .C(prt1_in[0]), .PAD(prt1[0]));  // pin 5: P0.0(GPIO0)/CS_FLASH
  PDUW16SDGZ_G PAD_P2_0 (.I(prt3_out[0]), .OEN(prt3_dir[0]), .REN(prt3_ren[0]), .C(prt3_in[0]), .PAD(prt3[0]));  // pin 27: P2.0(GPIO16)/T0CMP0
  PDUW16SDGZ_G PAD_P2_1 (.I(prt3_out[1]), .OEN(prt3_dir[1]), .REN(prt3_ren[1]), .C(prt3_in[1]), .PAD(prt3[1]));  // pin 28: P2.1(GPIO17)/T0CMP1
  PDUW16SDGZ_G PAD_P2_2 (.I(prt3_out[2]), .OEN(prt3_dir[2]), .REN(prt3_ren[2]), .C(prt3_in[2]), .PAD(prt3[2]));  // pin 29: P2.2(GPIO18)/T0CAP0
  PDUW16SDGZ_G PAD_P2_3 (.I(prt3_out[3]), .OEN(prt3_dir[3]), .REN(prt3_ren[3]), .C(prt3_in[3]), .PAD(prt3[3]));  // pin 30: P2.3(GPIO19)/T0CAP1
  PDUW16SDGZ_G PAD_P2_4 (.I(prt3_out[4]), .OEN(prt3_dir[4]), .REN(prt3_ren[4]), .C(prt3_in[4]), .PAD(prt3[4]));  // pin 31: P2.4(GPIO20)/T1CMP0
  PDUW16SDGZ_G PAD_P2_5 (.I(prt3_out[5]), .OEN(prt3_dir[5]), .REN(prt3_ren[5]), .C(prt3_in[5]), .PAD(prt3[5]));  // pin 32: P2.5(GPIO21)/T1CMP1
  PDUW16SDGZ_G PAD_P2_6 (.I(prt3_out[6]), .OEN(prt3_dir[6]), .REN(prt3_ren[6]), .C(prt3_in[6]), .PAD(prt3[6]));  // pin 33: P2.6(GPIO22)/T1CAP0
  PDUW16SDGZ_G PAD_P2_7 (.I(prt3_out[7]), .OEN(prt3_dir[7]), .REN(prt3_ren[7]), .C(prt3_in[7]), .PAD(prt3[7]));  // pin 34: P2.7(GPIO23)/T1CAP1
  PDUW16SDGZ_G PAD_P3_0 (.I(prt4_out[0]), .OEN(prt4_dir[0]), .REN(prt4_ren[0]), .C(prt4_in[0]), .PAD(prt4[0]));  // pin 37: P3.0(GPIO24)/SDA0
  PDUW16SDGZ_G PAD_P3_1 (.I(prt4_out[1]), .OEN(prt4_dir[1]), .REN(prt4_ren[1]), .C(prt4_in[1]), .PAD(prt4[1]));  // pin 38: P3.1(GPIO25)/SCL0
  PDUW16SDGZ_G PAD_P3_2 (.I(prt4_out[2]), .OEN(prt4_dir[2]), .REN(prt4_ren[2]), .C(prt4_in[2]), .PAD(prt4[2]));  // pin 39: P3.2(GPIO26)/SDA1
  PDUW16SDGZ_G PAD_P3_3 (.I(prt4_out[3]), .OEN(prt4_dir[3]), .REN(prt4_ren[3]), .C(prt4_in[3]), .PAD(prt4[3]));  // pin 40: P3.3(GPIO27)/SCL1
  PDUW16SDGZ_G PAD_P3_4 (.I(prt4_out[4]), .OEN(prt4_dir[4]), .REN(prt4_ren[4]), .C(prt4_in[4]), .PAD(prt4[4]));  // pin 41: P3.4(GPIO28)/DTP0
  PDUW16SDGZ_G PAD_P3_5 (.I(prt4_out[5]), .OEN(prt4_dir[5]), .REN(prt4_ren[5]), .C(prt4_in[5]), .PAD(prt4[5]));  // pin 42: P3.5(GPIO29)/DTP1
  PDUW16SDGZ_G PAD_P3_6 (.I(prt4_out[6]), .OEN(prt4_dir[6]), .REN(prt4_ren[6]), .C(prt4_in[6]), .PAD(prt4[6]));  // pin 43: P3.6(GPIO30)/DTP2
  PDUW16SDGZ_G PAD_P3_7 (.I(prt4_out[7]), .OEN(prt4_dir[7]), .REN(prt4_ren[7]), .C(prt4_in[7]), .PAD(prt4[7]));  // pin 44: P3.7(GPIO31)/DTP3
  PDUW16SDGZ_G PAD_P4_0 (.I(prt5_out[0]), .OEN(prt5_dir[0]), .REN(prt5_ren[0]), .C(prt5_in[0]), .PAD(prt5[0]));  // pin 52: P4.0(GPIO32)
  PDUW16SDGZ_G PAD_P4_1 (.I(prt5_out[1]), .OEN(prt5_dir[1]), .REN(prt5_ren[1]), .C(prt5_in[1]), .PAD(prt5[1]));  // pin 53: P4.1(GPIO33)
  PDUW16SDGZ_G PAD_P4_2 (.I(prt5_out[2]), .OEN(prt5_dir[2]), .REN(prt5_ren[2]), .C(prt5_in[2]), .PAD(prt5[2]));  // pin 54: P4.2(GPIO34)
  PDUW16SDGZ_G PAD_P4_3 (.I(prt5_out[3]), .OEN(prt5_dir[3]), .REN(prt5_ren[3]), .C(prt5_in[3]), .PAD(prt5[3]));  // pin 55: P4.3(GPIO35)
  PDUW16SDGZ_G PAD_P4_4 (.I(prt5_out[4]), .OEN(prt5_dir[4]), .REN(prt5_ren[4]), .C(prt5_in[4]), .PAD(prt5[4]));  // pin 56: P4.4(GPIO36)
  PDUW16SDGZ_G PAD_P4_5 (.I(prt5_out[5]), .OEN(prt5_dir[5]), .REN(prt5_ren[5]), .C(prt5_in[5]), .PAD(prt5[5]));  // pin 57: P4.5(GPIO37)
  PDUW16SDGZ_G PAD_P4_6 (.I(prt5_out[6]), .OEN(prt5_dir[6]), .REN(prt5_ren[6]), .C(prt5_in[6]), .PAD(prt5[6]));  // pin 58: P4.6(GPIO38)
  PDUW16SDGZ_G PAD_P4_7 (.I(prt5_out[7]), .OEN(prt5_dir[7]), .REN(prt5_ren[7]), .C(prt5_in[7]), .PAD(prt5[7]));  // pin 59: P4.7(GPIO39)
  PDUW16SDGZ_G PAD_P5_0 (.I(prt6_out[0]), .OEN(prt6_dir[0]), .REN(prt6_ren[0]), .C(prt6_in[0]), .PAD(prt6[0]));  // pin 62: P5.0(GPIO40)
  PDUW16SDGZ_G PAD_P5_1 (.I(prt6_out[1]), .OEN(prt6_dir[1]), .REN(prt6_ren[1]), .C(prt6_in[1]), .PAD(prt6[1]));  // pin 63: P5.1(GPIO41)
  PDUW16SDGZ_G PAD_P5_2 (.I(prt6_out[2]), .OEN(prt6_dir[2]), .REN(prt6_ren[2]), .C(prt6_in[2]), .PAD(prt6[2]));  // pin 64: P5.2(GPIO42)
  PDUW16SDGZ_G PAD_P5_3 (.I(prt6_out[3]), .OEN(prt6_dir[3]), .REN(prt6_ren[3]), .C(prt6_in[3]), .PAD(prt6[3]));  // pin 65: P5.3(GPIO43)
  PDUW16SDGZ_G PAD_P5_4 (.I(prt6_out[4]), .OEN(prt6_dir[4]), .REN(prt6_ren[4]), .C(prt6_in[4]), .PAD(prt6[4]));  // pin 66: P5.4(GPIO44)
  PDUW16SDGZ_G PAD_P5_5 (.I(prt6_out[5]), .OEN(prt6_dir[5]), .REN(prt6_ren[5]), .C(prt6_in[5]), .PAD(prt6[5]));  // pin 67: P5.5(GPIO45)
  // pull-DOWN cell (PDDW16SDGZ_G, NOT PDUW16SDGZ_G): DP-S3 field-power contract -- unconnected must read 0
  PDDW16SDGZ_G PAD_P5_6 (.I(prt6_out[6]), .OEN(prt6_dir[6]), .REN(prt6_ren[6]), .C(prt6_in[6]), .PAD(prt6[6]));  // pin 68: P5.6(GPIO46) = P6.6 field/harvest strap
  // pull-DOWN cell (PDDW16SDGZ_G, NOT PDUW16SDGZ_G): DP-S3 field-power contract -- unconnected must read 0
  PDDW16SDGZ_G PAD_P5_7 (.I(prt6_out[7]), .OEN(prt6_dir[7]), .REN(prt6_ren[7]), .C(prt6_in[7]), .PAD(prt6[7]));  // pin 69: P5.7(GPIO47) = P6.7 PGOOD

  // ---- D3 JTAG pads (R-DD4(2)) ------------------------------------------
  // Control-pin tie-off, from the CELL definitions rather than from analogy:
  // OEN is the active-low output enable (PAD is three-state on OEN), so
  // OEN=1'b1 is a pure INPUT pad and OEN=1'b0 drives; the pull is active when
  // REN is LOW (pull_down_function/pull_up_function = "!REN"). So the four
  // input pads take OEN=1/REN=0 (receiver on, pull ENGAGED -- that is the
  // whole fail-safe story: TRSTn reads 0 unbonded and the TAP stays in reset)
  // and TDO takes OEN=0/REN=1 (driven output, pull disengaged).
  // pull-DOWN cell (PDDW16SDGZ_G): TCK idles low.
  PDDW16SDGZ_G PAD_TCK (.I(1'b0), .OEN(1'b1), .REN(1'b0), .C(tck_in), .PAD(tck));  // pin 47: TCK
  // pull-UP cell (PDUW16SDGZ_G): IEEE 1149.1 wants TMS high when floating, so
  // five TCKs from a disconnected probe still return the TAP to Test-Logic-Reset.
  PDUW16SDGZ_G PAD_TMS (.I(1'b0), .OEN(1'b1), .REN(1'b0), .C(tms_in), .PAD(tms));  // pin 48: TMS
  PDUW16SDGZ_G PAD_TDI (.I(1'b0), .OEN(1'b1), .REN(1'b0), .C(tdi_in), .PAD(tdi));  // pin 49: TDI
  PDUW16SDGZ_G PAD_TDO (.I(tdo_out), .OEN(1'b0), .REN(1'b1), .C(), .PAD(tdo));  // pin 50: TDO (driven output)
  // pull-DOWN cell (PDDW16SDGZ_G): UNBONDED OR FLOATING TRSTn HOLDS THE TAP IN
  // RESET. Documented deviation from 1149.1's pull-up idle -- fail-safe-inert
  // beats fail-safe-attachable on a chip whose debug transport is optional.
  PDDW16SDGZ_G PAD_TRSTN (.I(1'b0), .OEN(1'b1), .REN(1'b0), .C(trstn_in), .PAD(trstn));  // pin 51: TRSTn

  // supply + POC pads: pinless (see header)
  PVSS2DGZ_G PAD_VSSPST_0 ();  // pin 14: VSSPST
  PVDD2DGZ_G PAD_VDDPST_0 ();  // pin 13: VDDPST
  PVSS1DGZ_G PAD_VSS_0 ();  // pin 4: VSS
  PVDD1DGZ_G PAD_VDD_0 ();  // pin 3: VDD
  PVDD2POC_G PAD_POC ();  // pin 2: POC
  PVDD1DGZ_G PAD_VDD_1 ();  // pin 35: VDD
  PVSS1DGZ_G PAD_VSS_1 ();  // pin 36: VSS
  PVDD2DGZ_G PAD_VDDPST_1 ();  // pin 45: VDDPST
  PVSS2DGZ_G PAD_VSSPST_1 ();  // pin 46: VSSPST
  PVDD1DGZ_G PAD_VDD_2 ();  // pin 60: VDD
  PVSS1DGZ_G PAD_VSS_2 ();  // pin 61: VSS
  PVDD2DGZ_G PAD_VDDPST_2 ();  // pin 70: VDDPST
  PVSS2DGZ_G PAD_VSSPST_2 ();  // pin 71: VSSPST
  PDB3A_G PAD_ARSV7 ();  // pin 85: ARSV7 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV6 ();  // pin 84: ARSV6 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV5 ();  // pin 83: ARSV5 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV4 ();  // pin 82: ARSV4 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV3 ();  // pin 81: ARSV3 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV2 ();  // pin 80: ARSV2 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV1 ();  // pin 79: ARSV1 (analog reserve, no core connection)
  PDB3A_G PAD_ARSV0 ();  // pin 78: ARSV0 (analog reserve, no core connection)
  PVSS2ANA_G PAD_AVSS ();  // pin 77: AVSS
  PVDD2ANA_G PAD_AVDD ();  // pin 76: AVDD

  PCORNER_G PAD_CORNER_BL ();
  PCORNER_G PAD_CORNER_BR ();
  PCORNER_G PAD_CORNER_TR ();
  PCORNER_G PAD_CORNER_TL ();
  // Stage J LVS fix: PRCUT_G ring-break cells bracketing the north analog band
  // (AVDD/AVSS/ARSV0-7). The G2-era LQFP-100 band order leaves PDB3A_G abutting
  // the UNBROKEN digital guard bands, and PDB3A's internal guard-ring strap
  // hard-bridges the n-well band (core VDD via PVDD1DGZ) to the p-sub band
  // (core VSS) -- a real metal1 VDD-VSS short, found by Pegasus dual-text
  // FIND_SHORTS at the PAD_ARSV0/PAD_AVSS abutment (x=1420, north row).
  // The proven Myshkin/C0/quad rings avoid it with the AVSS..PDB3A..AVDD
  // bracket motif; here the cut cells isolate the analog island instead
  // (PRCUT_G is geometrically EMPTY -- it breaks every abutment bus and both
  // guard bands by absence). Deviceless spice subckt exists in the tphn spice;
  // pinless instances per the PCORNER precedent.
  PRCUT_G RING_CUT_W ();
  PRCUT_G RING_CUT_E ();

  MCU mcu0 (
    .resetn_in(resetn_in), .resetn_out(resetn_out), .resetn_dir(resetn_dir), .resetn_ren(resetn_ren),
    .prt1_in(prt1_in), .prt1_out(prt1_out), .prt1_dir(prt1_dir), .prt1_ren(prt1_ren),
    .prt2_in(prt2_in), .prt2_out(prt2_out), .prt2_dir(prt2_dir), .prt2_ren(prt2_ren),
    .prt3_in(prt3_in), .prt3_out(prt3_out), .prt3_dir(prt3_dir), .prt3_ren(prt3_ren),
    .prt4_in(prt4_in), .prt4_out(prt4_out), .prt4_dir(prt4_dir), .prt4_ren(prt4_ren),
    .prt5_in(prt5_in), .prt5_out(prt5_out), .prt5_dir(prt5_dir), .prt5_ren(prt5_ren),
    .prt6_in(prt6_in), .prt6_out(prt6_out), .prt6_dir(prt6_dir), .prt6_ren(prt6_ren),
    .a0(a0), .a0_1(a0_1), .a0_2(a0_2), .a0_3(a0_3),
    // D3: debug-ON MCU ports (see the banner -- this is what makes the file
    // require a debug.enable build).
    .tck(tck_in), .tms(tms_in), .tdi(tdi_in), .tdo(tdo_out), .trstn(trstn_in)
  );

endmodule
