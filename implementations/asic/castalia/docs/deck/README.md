# Castalia short overview deck

33 slides, figure-led, ECEN 222 lecture template (Berkeley theme, beaver colours,
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

The analog top-level slide is a placeholder (`\duckph`) until the Virtuoso
export exists. The concept figure's "5x RISC-V" label was changed in the
paper's own `concept_cand_B.tex` (backup `.bak.20260920_rv32` beside it), so
every document that inputs it agrees.

Deck-local: `fig_cancer_compare.tex` (SEER stage/survival across eight cancers
with USPSTF screening grades; data and sources in its header),
`fig_marker_fusion.tex` (clinical sensitivities the paper carries as
prose), `preamble.tex` (the lecture template) and `trmreuse.tex` (the float- and
caption-stripping machinery, documented in the file; same as the lab talk's but
with repo-relative paths and one fix: the height-bound branch of `\trmfit` uses
`\resizebox*`, since a tabular sits centred on the baseline and the unstarred
form scaled its half-height instead of its total height, enlarging tall tables).

Clinical claims carry bracketed citations resolved on the closing References
slide. Spec-table numbers are transcribed from the TRM build of 2026-09-15 and the
tapeout_review campaign record; each slide names its source in a comment.
`docs/publications/castalia_lab_talk/` is the 39-slide long form.
