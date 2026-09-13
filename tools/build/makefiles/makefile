# VestaRV: build every firmware project in this directory.
# `make <name>.c.new` and `make <name>.cpp.new` create a project from the
# template_c and template_cpp directories; those two and testbenches are excluded
# from the default all target because they are templates, not projects.
SUBDIRS := $(wildcard */)

FILTERED_SUBDIRS := $(filter-out testbenches template_c template_cpp,$(SUBDIRS))
.PHONY: all
all: $(FILTERED_SUBDIRS)

.PHONY: $(SUBDIRS)
$(SUBDIRS):
	if [ -f ./$@/makefile ]; then cd $@ && make; fi

.PHONY: tidy
tidy:
	for s in $(SUBDIRS); do if [ -f $$s/makefile ]; then cd $$s && make tidy && cd ..; fi; done

# Remove the build artifacts as well as the junk.
.PHONY: clean
clean:
	for s in $(SUBDIRS); do if [ -f $$s/makefile ]; then cd $$s && make clean && cd ..; fi; done

.PHONY: %.c.new
%.c.new:
	@if [ ! -d $* ] ; then \
		echo "Making new C project \"$*\" from template_c" && \
		mkdir -p $* && \
		cp template_c/makefile $*/makefile && \
		cd $* && make setup && cd .. && \
		cp template_c/src/main.c $*/src/main.c ; \
	else \
		echo "Project \"$*\" already exists" ; \
	fi

.PHONY: %.cpp.new
%.cpp.new:
	@if [ ! -d $* ] ; then \
		echo "Making new C++ project \"$*\" from template_cpp" && \
		mkdir -p $* && \
		cp template_cpp/makefile $*/makefile && \
		cd $* && make setup && cd .. && \
		cp template_cpp/src/main.cpp $*/src/main.cpp ; \
	else \
		echo "Project \"$*\" already exists" ; \
	fi
