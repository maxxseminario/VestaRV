# lab02_assembly -- REFERENCE ASSEMBLY.
#
# PRIVATE -- do not commit. This completed solution moves to the course's
# private repo before any vestarv commit.
#
# Three routines in pure RV32 (rv32ima, no bit-manip). The C harness in
# src/main.c calls them and PASSES (a0 = 0xCAFEBABE) when all checks match.

    .text

# ---------------------------------------------------------------------------
# unsigned my_strlen(const char *s)      a0=s -> a0 = length
# ---------------------------------------------------------------------------
    .globl my_strlen
    .p2align 2
my_strlen:
    mv   t0, a0            # t0 = running pointer, a0 = original base
1:  lbu  t1, 0(t0)        # *p
    beqz t1, 2f           # NUL -> done
    addi t0, t0, 1
    j    1b
2:  sub  a0, t0, a0       # length = end - base
    ret

# ---------------------------------------------------------------------------
# int my_array_max(const int *a, unsigned n)   a0=a, a1=n(>=1) -> a0 = max
# ---------------------------------------------------------------------------
    .globl my_array_max
    .p2align 2
my_array_max:
    lw   a2, 0(a0)        # max = a[0]
    li   t0, 1            # i = 1
1:  bgeu t0, a1, 2f       # i >= n -> done  (n is unsigned)
    slli t1, t0, 2        # i * 4
    add  t1, a0, t1
    lw   t2, 0(t1)        # a[i]
    blt  a2, t2, 3f       # signed: max < a[i] ?
    j    4f
3:  mv   a2, t2           # new max
4:  addi t0, t0, 1
    j    1b
2:  mv   a0, a2
    ret

# ---------------------------------------------------------------------------
# unsigned my_bit_reverse(unsigned x)     a0=x -> a0 = reverse(x)
# ---------------------------------------------------------------------------
    .globl my_bit_reverse
    .p2align 2
my_bit_reverse:
    li   t0, 32           # bit counter
    li   t1, 0            # result accumulator
1:  slli t1, t1, 1        # result <<= 1
    andi t2, a0, 1        # low bit of x
    or   t1, t1, t2       # graft it into result
    srli a0, a0, 1        # x >>= 1
    addi t0, t0, -1
    bnez t0, 1b
    mv   a0, t1
    ret
