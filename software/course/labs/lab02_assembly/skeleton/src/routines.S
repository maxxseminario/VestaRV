# lab02_assembly -- STUDENT ASSEMBLY (edit this file).
#
# Implement three routines in pure RV32 assembly. The C harness (src/main.c)
# calls them and checks the results. As shipped, every routine returns 0, so
# the harness FAILS (a0 = 0xDEADBEEF). Replace each stub with a real
# implementation; when all checks match, the harness calls pass()
# (a0 = 0xCAFEBABE).
#
# ABI reminders (ilp32):
#   * arguments arrive in a0, a1, ...   the return value goes in a0.
#   * t0-t6 and a0-a7 are caller-saved -- you may clobber them freely here.
#   * end every routine with `ret`.
#   * the build march is rv32ima: no bit-manip (no `rev`/`clz`), no Zbb. Do the
#     bit reversal with shifts and masks.
#   * strings and arrays live in the TCM (normal memory) -- byte loads (lbu) and
#     word loads (lw) work there. (The WORD-only rule is for PERIPHERAL
#     registers on the 0x4000 bus, not for RAM.)

    .text

# ---------------------------------------------------------------------------
# unsigned my_strlen(const char *s)
#   a0 = pointer to a NUL-terminated string.
#   return the number of bytes before the terminating NUL (0 for "").
# ---------------------------------------------------------------------------
    .globl my_strlen
    .p2align 2
my_strlen:
    # TODO(lab02): walk the string one byte at a time (lbu) until you hit the
    #   NUL (0) byte, and return the count. Hint: keep the original pointer so
    #   you can subtract it from the end pointer.
    li   a0, 0
    ret

# ---------------------------------------------------------------------------
# int my_array_max(const int *a, unsigned n)
#   a0 = pointer to n signed 32-bit ints, a1 = n (n >= 1).
#   return the maximum element (SIGNED comparison -- use blt, not bltu).
# ---------------------------------------------------------------------------
    .globl my_array_max
    .p2align 2
my_array_max:
    # TODO(lab02): load a[0] as the running max, then loop i = 1..n-1 loading
    #   a[i] (each element is 4 bytes -- scale the index by 4) and keep the
    #   larger with a SIGNED compare. Return the max in a0.
    li   a0, 0
    ret

# ---------------------------------------------------------------------------
# unsigned my_bit_reverse(unsigned x)
#   a0 = x. Return x with its 32 bits reversed (bit i -> bit 31-i).
# ---------------------------------------------------------------------------
    .globl my_bit_reverse
    .p2align 2
my_bit_reverse:
    # TODO(lab02): shift the result left, OR in the low bit of x, then shift x
    #   right -- 32 times. No bit-manip instructions on this build.
    li   a0, 0
    ret
