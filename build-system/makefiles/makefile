SUBDIRS := $(wildcard */)

# # Make all projects
# .PHONY: all
# all: $(SUBDIRS)
# Make all projects
# Make all projects
# Make all projects
FILTERED_SUBDIRS := $(filter-out testbenches template_c template_cpp,$(SUBDIRS))
.PHONY: all
all: $(FILTERED_SUBDIRS)

.PHONY: $(SUBDIRS)
$(SUBDIRS):
	if [ -f ./$@/makefile ]; then cd $@ && make; fi

# Clean up unnecessary files
.PHONY: tidy
tidy:
	for s in $(SUBDIRS); do if [ -f $$s/makefile ]; then cd $$s && make tidy && cd ..; fi; done

# Clean up unnecessary files and compiled program files
.PHONY: clean
clean:
	for s in $(SUBDIRS); do if [ -f $$s/makefile ]; then cd $$s && make clean && cd ..; fi; done

# Create a new project using the C template
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

# Create a new project using the C++ template
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
