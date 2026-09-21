# Castalia short overview deck

39 slides, figure-led, ECEN 222 lecture template (Berkeley theme, beaver colours,
16:9). Built PDF is copied one level up, next to the published `TRM.pdf`.

    make          # two pdflatex passes, then copies ../castalia_deck.pdf
    make clean

## Where the figures come from

Nothing is copied. Every plot, schematic and table fragment is `\input` from the
same sources the TRM builds from, so a regenerated TRM updates the deck:

| Source (relative to this directory) | Holds |
|---|---|
| `../../analog/` | the tracked analog chapter: `fig_*`, `sch_*`, `tab_*` and `data/` (what `LatexUserGuide.CopyAnalogChapter` copies into the TRM build) |
| `../../../../../platform/common/latex/TRM/include/` | the generated digital diagrams and `defines.tex` — gitignored, so run `make generate` in `platform/common` first |
| `../../../../../assets/web/` | the layout renders |
| `~/work/ieee/ISCAS27/latek/` (outside the repo, guarded) | the concept figure and the reader-drawn block diagram; the deck falls back to a placeholder / the generated diagram if absent |

The analog top-level and physical-implementation images are placeholders
(`\duckph`) until the Virtuoso exports exist. The concept figure is the paper's `concept_cand_G.tex`: `concept_cand_B.tex`
(relabelled "5x RISC-V", die redrawn as four AFE+hart rows into one control
plane; backups `.bak.20260920_*` beside it) with the anatomy removed, so the
sample path starts at the bloodstream.

Deck-local: `fig_cancer_compare.tex` (SEER stage/survival across eight cancers
with USPSTF screening grades; data and sources in its header),
`fig_marker_fusion.tex` (clinical sensitivities the paper carries as
prose), `fig_eis_on_schematic.tex` and `fig_dpv_on_schematic.tex` (the TRM's
potentiostat schematic with the EIS excitation/response, respectively the DPV
programme and resolved peaks, sketched above it), `fig_eis_method.tex` (an unused block-chain version of the same), `fig_iq_demod.tex` (I/Q demodulation of one record, sketch),
`fig_eis_error_deck.tex` (the TRM's fig_eis_error with short legend entries,
reading the same data files), `fig_randles_deck.tex` (the three-electrode
Randles network), `fig_eis_noise_vs_m.tex` (sigma of |Z| against periods
averaged, from the TRM's process-gain numbers),
`fig_reporter_window.tex` (the reporter potential window and the
screen-printed-electrode peak-current envelope with our four panel values on
them; sources in its header), `fig_power_gating.tex` (digital power against tiles gated,
from the post-route reports), `tab_blocks_combined.tex` (the TRM's corner
tables for the amplifier, R_f, SAR and DAC with the matching Monte Carlo sigma
appended; sources in its header, regenerate by hand when the TRM tables change), `preamble.tex` (the lecture template) and `trmreuse.tex` (the float- and
caption-stripping machinery, documented in the file; same as the lab talk's but
with repo-relative paths, the TRM's `v*` TikZ styles for the generated diagrams,
`\trmslidestrokes` (heavier circuitikz strokes inside every `\trmfit`, since the
print-weight schematics vanish on a projector) and one fix: the height-bound branch of `\trmfit` uses
`\resizebox*`, since a tabular sits centred on the baseline and the unstarred
form scaled its half-height instead of its total height, enlarging tall tables).

Clinical claims carry bracketed citations resolved on the closing References
slide. Spec-table numbers are transcribed from the TRM build of 2026-09-15 and the
tapeout_review campaign record; each slide names its source in a comment.
`docs/publications/castalia_lab_talk/` is the 39-slide long form.
