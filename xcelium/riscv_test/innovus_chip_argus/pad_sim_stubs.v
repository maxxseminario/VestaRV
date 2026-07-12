// Sim stubs for physical-only pad cells the chip netlist instantiates but
// the tphn functional verilog model does not define (checked 2026-07-12:
// tphn65gpgv2od3_sl.v has no PCORNER_G -- corners are metal-only).
module PCORNER_G ();
endmodule
