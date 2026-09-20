# Castalia short overview deck.  Two passes: \inserttotalframenumber and the
# sidebar navigation need the .aux/.nav of a previous run.
#
# Figures come from the shared TRM sources (see trmreuse.tex):
#   ../../analog/                              tracked analog fragments
#   ../../../../../platform/common/latex/TRM/  GENERATED -- run `make generate`
#                                              in platform/common first
# The finished PDF is copied one level up, next to the published TRM.pdf.
#
# NOTE: never redirect a build log to $(NAME).out -- that is hyperref's
# bookmark file, and clobbering it makes beamer typeset the shell log.
NAME     = castalia_deck
LOG      = build.log
PUBLISH  = ../$(NAME).pdf
PDFLATEX := $(shell command -v pdflatex 2>/dev/null || ls $(HOME)/texlive/*/bin/*/pdflatex 2>/dev/null | head -1)
TRMINC   = ../../../../../platform/common/latex/TRM/include

.PHONY: all publish clean view

all: publish

$(NAME).pdf: $(NAME).tex preamble.tex trmreuse.tex fig_*.tex
	@test -f $(TRMINC)/defines.tex || { echo "$(TRMINC)/defines.tex missing: run 'make generate' in platform/common"; false; }
	$(PDFLATEX) -interaction=nonstopmode $(NAME).tex > $(LOG) 2>&1 || (tail -40 $(LOG); false)
	$(PDFLATEX) -interaction=nonstopmode $(NAME).tex > $(LOG) 2>&1 || (tail -40 $(LOG); false)
	@echo "--- $(NAME).pdf: $$(pdfinfo $(NAME).pdf | awk '/^Pages/{print $$2}') slides ---"
	@grep -n "^! " $(LOG) || echo "no LaTeX errors"

publish: $(NAME).pdf
	cp $(NAME).pdf $(PUBLISH)
	@echo "published $(PUBLISH)"

clean:
	rm -f $(NAME).aux $(NAME).log $(NAME).nav $(NAME).out $(NAME).snm \
	      $(NAME).toc $(NAME).vrb $(NAME).fls $(NAME).fdb_latexmk $(LOG)

view: $(NAME).pdf
	xdg-open $(NAME).pdf
