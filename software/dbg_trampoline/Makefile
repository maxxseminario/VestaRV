# =============================================================================
# software/dbg_trampoline/Makefile  (D2)
# Builds the debug entry trampoline into the plantable word list the D2
# acceptance harnesses read (d2_instruments_for_implementer.md 3.1).
#
#   make            -> bin/dbg_trampoline.words (+ .elf, .bin, .dump)
#   make clean
#
# The word list is 64 lines, one per word of the entry page 0x10780-0x1087F:
#   * words  0..39  the trampoline, emitted as 32 binary characters -> PLANTED
#   * words 40..63  a single '-' -> LEFT WRITABLE.  The Debug Module writes the
#     abstract body (40..47) and the epilogue (48..56) there, and a forced word
#     is read-only, so planting them would break the DM outright.
# TRAMP_WORDS grew 24 -> 40 on 2026-08-06 when the trampoline gained the
# session-mirror repair for the F-D2-0 exception re-entry (see the .S header);
# debug_module.vhd's W_ABST/W_EPILOG moved in the same change and the two must
# agree -- the trampoline's `jal x0, _start + 4*W_ABST_INDEX` is the coupling.
# =============================================================================
PREFIX  ?= riscv-none-elf-
ARCH    ?= -march=rv32imac -mabi=ilp32
TRAMP_WORDS ?= 40

all: bin/dbg_trampoline.words

bin/dbg_trampoline.elf: dbg_trampoline.S
	@mkdir -p bin
	$(PREFIX)gcc $(ARCH) -nostdlib -nostartfiles -Wl,-Ttext=0x00010780 \
	    -o $@ $<

bin/dbg_trampoline.words: bin/dbg_trampoline.elf
	$(PREFIX)objdump -d --disassemble-zeroes $< > bin/dbg_trampoline.dump
	$(PREFIX)objcopy -O binary --gap-fill=0x00 $< bin/dbg_trampoline.bin
	@od -v -An -tx4 -w4 bin/dbg_trampoline.bin | awk -v n=$(TRAMP_WORDS) '\
	  { if (NR > n) next; hex=$$1; bin="";                                \
	    for (i=1;i<=8;i++) { c=substr(hex,i,1);                           \
	      if      (c=="0") bin=bin "0000"; else if (c=="1") bin=bin "0001";\
	      else if (c=="2") bin=bin "0010"; else if (c=="3") bin=bin "0011";\
	      else if (c=="4") bin=bin "0100"; else if (c=="5") bin=bin "0101";\
	      else if (c=="6") bin=bin "0110"; else if (c=="7") bin=bin "0111";\
	      else if (c=="8") bin=bin "1000"; else if (c=="9") bin=bin "1001";\
	      else if (c=="a") bin=bin "1010"; else if (c=="b") bin=bin "1011";\
	      else if (c=="c") bin=bin "1100"; else if (c=="d") bin=bin "1101";\
	      else if (c=="e") bin=bin "1110"; else if (c=="f") bin=bin "1111";}\
	    print bin; }' > $@.tmp
	@lines=$$(wc -l < $@.tmp); \
	 if [ "$$lines" -ne "$(TRAMP_WORDS)" ]; then \
	   echo "FATAL: trampoline is $$lines words, expected $(TRAMP_WORDS)"; \
	   rm -f $@.tmp; exit 2; fi
	@{ cat $@.tmp; \
	   i=$(TRAMP_WORDS); while [ $$i -lt 64 ]; do \
	     echo "-   word $$i: DM-written, MUST stay writable"; i=$$((i+1)); done; } > $@
	@rm -f $@.tmp
	@echo "wrote $@ ($$(wc -l < $@) lines; $(TRAMP_WORDS) planted, $$((64-$(TRAMP_WORDS))) left writable)"

clean:
	rm -rf bin

.PHONY: all clean
