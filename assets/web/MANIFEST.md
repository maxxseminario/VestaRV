# VestaRV showcase — web imagery manifest (S5)

Cleared, metadata-stripped, web-ready image assets for the showcase landing page and
gallery. Every file in this directory has a row below. Assets were reviewed against the
user-resolved D2 asset clearances; nothing from a non-cleared `docs/publications/` path
was copied. All PNGs have had EXIF/XMP metadata stripped (`exiftool -all=`); SVGs were
confirmed standalone (no external file/image/font references) and carry only benign
Inkscape editor attributes (no author / rights / document-title metadata).

Generated 2026-07-16 by work package S5 (imagery pipeline).

---

## Gallery slot mapping (landing page)

| Landing-page slot     | Asset filename                     | Notes |
|-----------------------|------------------------------------|-------|
| `gallery-die-shot`    | `die_shot_myshkin_labeled.png`     | Labeled Myshkin single-core die photograph — the hero image. |
| `gallery-tile-layout` | `layout_hart_tile.png`             | One hardened `hart_tile` (RISC-V core + TCM SRAM) — the replicated unit. |
| `gallery-mcu-layout`  | `layout_castalia_mcu_assembly.png` | Castalia 4-hart MCU core assembly (4 tiles + shared bulk-RAM bank row). |
| `gallery-chip-top`    | `layout_castalia_chip_top.png`     | Castalia `chip_top` — the 4-hart assembly inside the connected pad ring. |
| `gallery-argus`       | `layout_argus_array.png`           | Argus many-core teaching chip — full replicated-tile array + pad ring. |
| `gallery-block-diagram` | `block_mcu_clock_system.svg`     | MCU clock-system block diagram (scalable, theme-neutral line art). |

Secondary / detail-view assets available (not a primary slot): the remaining `block_*.svg`
diagrams (NPU, bias generator, MCA + focus variants), the AFE characterization plots
(`plot_cv/ca/transient.png`), and the silicon comparison table (`fig_comparison_table.png`).

---

## Full asset table

Columns: asset → source path → what it shows → provenance/note → cleared.

| Asset | Source path (repo-relative) | Shows | Provenance / note | Cleared |
|-------|-----------------------------|-------|-------------------|---------|
| `die_shot_myshkin_labeled.png` | `docs/publications/neuralink-presentation/svg/myshkin_labeled.png` | Labeled die photo of the Myshkin single-core tape-out (annotated blocks). | D2-a explicit clearance. 1549x2191. EXIF/XMP stripped. | YES |
| `layout_hart_tile.png` | render of `signoff_mp/pvs/hart_tile_mp/hart_tile/hart_tile.gds` | Single hardened hart tile: standard-cell fabric + TCM SRAM macros + power straps. | NEW render, strategy (c): klayout headless GDS→PNG (see "Render method"). Top power mesh (M6-M8) hidden to reveal routing. 1200x1600. | YES |
| `layout_castalia_mcu_assembly.png` | render of `signoff_mp/pvs/MCU_MP_signoff/MCU/MCU.gds` | Castalia 4-hart MCU assembly: four identical tiles + shared bulk-RAM bank row. | NEW render, strategy (c) klayout GDS→PNG. 1600x1600. | YES |
| `layout_castalia_chip_top.png` | render of `signoff_mp/pvs/chip_top_signoff/chip_top/chip_top.gds` | Castalia connected chip-top: MCU core inside the tphn pad ring. | NEW render, strategy (c) klayout GDS→PNG. 1600x1600. | YES |
| `layout_argus_array.png` | render of `signoff_mp/pvs/chip_argus_signoff/chip_top/chip_top.gds` | Argus many-core teaching chip: full replicated-tile array + pad ring. | NEW render, strategy (c) klayout GDS→PNG. 1600x1600. | YES |
| `block_mcu_clock_system.svg` | `docs/publications/neuralink-presentation/svg/mcu-clock-system.svg` | MCU clock-generation / distribution block diagram. | D2-b explicit clearance. Standalone SVG. | YES |
| `block_npu.svg` | `docs/publications/neuralink-presentation/svg/npu-block-diagram.svg` | Neural Processing Unit datapath block diagram. | D2-b explicit clearance. Standalone SVG. | YES |
| `block_bias_generator.svg` | `docs/publications/neuralink-presentation/svg/bias-generator.svg` | Analog bias-generator block diagram. | D2-b explicit clearance. Standalone SVG. | YES |
| `block_mca_full.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-full.svg` | Full multi-channel analyzer / analog-front-end block diagram. | D2-b explicit clearance (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_adc.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-adc.svg` | MCA diagram, ADC block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_cm.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-cm.svg` | MCA diagram, current-mirror block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_comp.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-comp.svg` | MCA diagram, comparator block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_csa.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-csa.svg` | MCA diagram, charge-sensitive-amplifier block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_dpp.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-digital-pulse-processing.svg` | MCA diagram, digital-pulse-processing block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `block_mca_focus_sample_hold.svg` | `docs/publications/neuralink-presentation/svg/mca/mca-block-diagram-focus-sample-hold.svg` | MCA diagram, sample-and-hold block highlighted. | D2-b (MCA diagrams). Standalone SVG. | YES |
| `fig_comparison_table.png` | `docs/publications/ISCAS26_lecture/Figures/comparison_table.png` | Silicon comparison table (This Work / VestaRV vs prior electrochemical SoCs). | D2-c clearance; best-paper (ISCAS 2026) context allowed. 2394x578. EXIF stripped. | YES |
| `plot_cv.png` | `docs/publications/ISCAS26_lecture/Figures/cv_plot.png` | Cyclic-voltammetry forward/reverse current plot. | D2-c clearance; best-paper context allowed. 833x684. EXIF stripped. | YES |
| `plot_ca.png` | `docs/publications/ISCAS26_lecture/Figures/ca_plot.png` | Chronoamperometry current-response plot. | D2-c clearance; best-paper context allowed. 803x680. EXIF stripped. | YES |
| `plot_transient.png` | `docs/publications/ISCAS26_lecture/Figures/transient_response_plot.png` | AFE transient-response plot (i_cell / v_out / v_fb). | D2-c clearance; best-paper context allowed. 830x696. EXIF stripped. | YES |

All 19 files above exist with size > 0 and are cleared for public use.

---

## Render method (new layout images, strategy c)

The four `layout_*.png` renders were produced from the signed-off top-level GDS
(`signoff_mp/pvs/.../*.gds`, PG4 signoff artifacts) using **klayout in headless batch
mode** — strategy (c) in the S5 brief. No Innovus database was opened, restored, or
modified; no Cadence license was used. Method:

- `klayout -z -nc -rm <macro.py>` driven against an existing `Xvfb :99` virtual display
  (this klayout build has no Ruby and needs an X connection even in `-z` hidden mode; the
  offscreen Qt platform plugin was unavailable, so the virtual framebuffer was used).
- The macro loads the GDS, expands full hierarchy, hides the M6-M8 power/fill layers
  (GDS layer numbers per `innovus/common/streamOut.map`) so the standard-cell routing and
  SRAM macros are visible instead of an opaque top-metal power mesh, then `zoom_fit` +
  `save_image`.

Strategy (a) — existing images — was checked: `innovus/common/chip_top_quad/out/chip_top_quad.*.{png,gif}`
exist (Castalia-Quad 4-hart Innovus screenshots, 640x480, floorplan + routed). They were
NOT promoted to the gallery because they are the CQ-respin variant and low-resolution;
the GDS renders give higher-resolution, on-target, stylistically-consistent images for all
four requested subjects. Strategy (b) — a fresh Innovus batch render — was deliberately not
attempted (no display for the GUI capture path, and the read-only/no-save + license
discipline made the GDS route strictly safer and sufficient).

---

## Reviewed but NOT copied (BLOCKED / omitted, with reason)

No file below was copied into `assets/web/`.

| Item | Path | Reason |
|------|------|--------|
| Full analog circuit schematics | `docs/publications/neuralink-presentation/svg/circuitSchems.svg` | BLOCKED — 66 MB detailed schematic, not a cleared block diagram (D2-b lists only the named block diagrams + MCA). |
| Potentiostat/best-paper figures beyond the D2-c set (NPU/MLP posters, activation-function figures, package/post-fab photos, `three_panel_figure`, `arm_w_SoC`) | `docs/publications/ISCAS26_lecture/Figures/*` | BLOCKED — outside the D2-c cleared category (comparison figures/tables + CV/CA/transient plots only). `three_panel_figure.png` also has overlapping-text render artifacts. |
| Castalia-deck raster figures (concept diagram, CV_Sim, ASIC/NPU/DPSRAM/training/potentiostat schematics) | `docs/publications/<castalia-deck>/Figures/*` | OMITTED — a paper figure clearance exists (D2-d) but is bound to that paper; its only paper-external raster (a shared potentiostat concept diagram) is not needed for any gallery slot and CV is already covered by `plot_cv.png` (D2-c). Omitted to keep zero paper/venue attribution and zero forbidden path tokens in this manifest, per the D2-d hard constraint. |
| All other decks | `docs/publications/{3in5,committee_chips,iscas26-potentiostat,...}/` | BLOCKED — not in the D2 clearance list. |
