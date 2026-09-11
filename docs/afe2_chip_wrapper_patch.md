# MCU_castalia_penta.v: changes for the AFE2 re-cut (written 2026-09-05, not applied)

Target: `innovus/common/MCU_castalia_penta/in/MCU_castalia_penta.v` (hand-written; this file
is the recipe, the netlist edit is the physical owner's) and
`innovus/common/MCU_castalia_penta/tcl/chip_top_wound_padlists_penta.tcl`.
Generated from `platform/common/config/penta_wound_afe.json`; the ordered pad list is
`bazel-bin/platform/common/chip_artifacts_penta_wound_afe/out/pnr/chip_top_padring.tcl`.

## 1. MCU ports (new on the `MCU` entity, 1.0 V CMOS, no pad)

Per site h = 0..3, from `hdl/common/MCU.vhd` of the AFE configuration:

    afe_ctl_h     : out std_logic_vector(49 downto 0)   -- anatop_pixel symbol order, MSB first
    afe_sar_clk_h : out std_logic                       -- SARADC_clk
    afe_sar_rst_h : out std_logic                       -- SARADC_rst, reset value 1
    afe_sar_rdy_h : in  std_logic := '0'                -- SARADC_rdy
    afe_sar_d_h   : in  std_logic_vector(9 downto 0) := (others => '0')   -- SARADC_d<9:0>, raw (bit 9 inverted by the macro, corrected in AFE2)

    afe_ctl_h(49:44) ResEn<5:0>   (43:40) ThEn<3:0>   (39:28) A_Dac_Vp<11:0>   (27) En_Dac_Vp
    afe_ctl_h(26:15) A_Dac_Vcm<11:0>   (14) En_Dac_Vcm   (13:8) Bias_Adj<5:0>   (7:4) SARADC_SEL<3:0>   (3:0) ATP_SEL<3:0>

All 216 nets connect `mcu0` to the one `anatop_quad` macro instance (D17) and nowhere else.
The 1.0 V to 2.5 V shifters for `afe_ctl_h` are inside the macro (D3); the SAR pins are 1.0 V.
Unconnected inputs default to 0 inside `mcu0`, so a wrapper that omits them elaborates; a
wrapper that omits the outputs leaves the macro's 2.5 V shifter inputs floating (2.5 uA per
select bit from the analog rail, firmware contract 1.1): connect all of them.

## 2. Macro instance

    anatop_quad u_anatop (
      // digital side, per site h
      .ctl_h(afe_ctl_h[49:0]), .sar_clk_h(afe_sar_clk_h), .sar_rst_h(afe_sar_rst_h),
      .sar_rdy_h(afe_sar_rdy_h), .sar_d_h(afe_sar_d_h[9:0]),
      // electrodes, per site h: to the PDB3A_G AIO pins only
      .ce_h(ce_h), .re_h(re_h), .we_h(we_h),
      // test port
      .atp0(atp0), .atp1(atp1),
      // supplies: AVDD/AVSS from PAD_AVDD/PAD_AVSS (TAVDD/TAVSS bus), VDD/VSS core, DVDD10 = VDD
    );

Pin names on `anatop_quad` follow the wrapper schematic once it is drawn; the digital side is
fixed by the MCU entity above.

## 3. North pad band: 8 reserve pads become 14 analog pads (D2)

Delete `PAD_ARSV0..7` (pins 78-85, `PDB3A_G`, pinless). Add fourteen `PDB3A_G` instances,
each with its `AIO` wired to the macro net named:

    pin 78 PAD_CE_0   pin 79 PAD_WE_0   pin 80 PAD_RE_0
    pin 81 PAD_CE_1   pin 82 PAD_WE_1   pin 83 PAD_RE_1
    pin 84 PAD_CE_2   pin 85 PAD_WE_2   pin 86 PAD_RE_2
    pin 87 PAD_CE_3   pin 88 PAD_WE_3   pin 89 PAD_RE_3
    pin 90 PAD_ATP0   pin 91 PAD_ATP1
    pin 76 PAD_AVDD (PVDD3A_G) and pin 77 PAD_AVSS (PVSS3A_G) unchanged; 92-100 NC.

The electrode and ATP nets go to the macro only: never to `mcu0`, never to a digital pad.
Add the 14 nets as `inout` ports of `MCU_castalia_penta` (the PDB3A_G `AIO` terminal is the
pad). PRCUTA_G ring cuts stay where they are; the band grows from 10 to 16 pads and the
`place_side top` list in `chip_top_wound_padlists_penta.tcl` becomes, right to left
(pin-descending, the generated order):

    set TOP [list PAD_ATP1 PAD_ATP0 PAD_RE_3 PAD_WE_3 PAD_CE_3 PAD_RE_2 PAD_WE_2 PAD_CE_2 \
                  PAD_RE_1 PAD_WE_1 PAD_CE_1 PAD_RE_0 PAD_WE_0 PAD_CE_0 PAD_AVSS PAD_AVDD]
    # pins: 91 90 89 88 87 86 85 84 83 82 81 80 79 78 77 76

A check that diffs this list against the generated `chip_top_padring.tcl` TOP block (report 08
finding 5) is the gate that keeps the two from drifting again.

## 4. What does not change

GPIO, JTAG, supply and POC pads; the `mcu0` port list except the additions in section 1; the
CP4b assertion counts (72 pads + 4 corners + 2 cuts) move to 78 + 4 + 2.
