# Castalia short overview deck

17 slides, figure-led, ECEN 222 lecture template (Berkeley theme, beaver colours,
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

Deck-local: `fig_marker_fusion.tex` (clinical sensitivities the paper carries as
prose), `preamble.tex` (the lecture template) and `trmreuse.tex` (the float- and
caption-stripping machinery, documented in the file; same as the lab talk's but
with repo-relative paths).

Spec-table numbers are transcribed from the TRM build of 2026-09-15 and the
tapeout_review campaign record; each slide names its source in a comment.
`docs/publications/castalia_lab_talk/` is the 39-slide long form.
