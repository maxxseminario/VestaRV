#!/usr/bin/env python3
# ===========================================================================
# gen_directed.py  --  X4 Stage 2c: softfloat-referenced directed FP vectors.
#
# REFERENCE DISCIPLINE (gatekeeper correction C4):
#   The oracle for every ROUNDED result + fflags is a REAL IEEE-754 single-
#   precision engine: glibc's `fmaf` / `sqrtf` (genuine correctly-rounded
#   single-precision ops) reached through ctypes, with libm `fesetround` for
#   the rounding mode and `feclearexcept`/`fetestexcept` for the sticky
#   exception flags. x87 is NOT used (it double-rounds through 80-bit) and no
#   host C compiler is required. FMA is glibc `fmaf` per C4.
#     add(a,b) = fmaf(1,a, b)     sub(a,b) = fmaf(1,a,-b)
#     mul(a,b) = fmaf(a,b, 0)     fma      = fmaf(a,b,c)     sqrt = sqrtf(a)
#   round_to_single(N) for an integer N is computed as fmaf(1, hi, lo) where
#   hi+lo = N split into two EXACTLY-representable floats -- so int->float ties
#   (fcvt.s.w) are referenced by the same real engine.
#   Values that are exact / spec-fixed (fmin/fmax, fsgnj, the fcvt.w.s invalid
#   table [frozen ruling Q5], and the div-by-zero / invalid specials) need no
#   rounding and are written from the architectural definition directly.
#   Every NaN RESULT is forced to the RISC-V canonical qNaN 0x7fc00000 (the
#   host returns a sign-set 0xffc00000), and mul preserves sign-of-zero.
#   Round-to-nearest-max-magnitude (RMM) has no libm mode; it is applied ONLY
#   to exact-tie vectors, where RMM == round-away-from-zero (derived from the
#   RUP/RDN results by magnitude).
#
# The generated tests run on the VestaRV core (Zfinx) and are SELF-CHECKING:
# each embeds the reference result/flags and `bne`s to `fail` on mismatch, so
# a wrong value gives a BOUNDED failure (a0=0xDEADBEEF), never a hang -- this
# is what makes the three Stage-3 negative-control seeds observable.
#
# Deterministic: re-running overwrites the committed .S byte-for-byte.
#   python3 gen_directed.py [output_dir]        (default ../tests/rv32uzf)
#   python3 gen_directed.py --check [output_dir]  (CI determinism gate)
#
# Categories (one .S each): dround dsubnrm dnan dpmzero dfcvttab daccum
#                           drdx0 dsgnj    (see per-emitter comments)
# ===========================================================================
import ctypes, struct, sys, os, tempfile, difflib

# ---- glibc single-precision engine via ctypes ----------------------------
_m = ctypes.CDLL("libm.so.6", use_errno=True)
for _n, _rt, _at in [("fmaf", ctypes.c_float, [ctypes.c_float]*3),
                     ("sqrtf", ctypes.c_float, [ctypes.c_float]),
                     ("fesetround", ctypes.c_int, [ctypes.c_int]),
                     ("feclearexcept", ctypes.c_int, [ctypes.c_int]),
                     ("fetestexcept", ctypes.c_int, [ctypes.c_int])]:
    _f = getattr(_m, _n); _f.restype = _rt; _f.argtypes = _at

# glibc x86 fenv constants
FE = {"rne": 0, "rdn": 0x400, "rup": 0x800, "rtz": 0xc00}
X_INVALID, X_DIVZERO, X_OVERFLOW, X_UNDERFLOW, X_INEXACT = 0x01, 0x04, 0x08, 0x10, 0x20
X_ALL = X_INVALID | X_DIVZERO | X_OVERFLOW | X_UNDERFLOW | X_INEXACT
# RISC-V fflags bits
NX, UF, OF, DZ, NV = 0x01, 0x02, 0x04, 0x08, 0x10
QNAN = 0x7fc00000  # RISC-V canonical qNaN

def b2f(u): return struct.unpack('<f', struct.pack('<I', u & 0xffffffff))[0]
def f2b(f): return struct.unpack('<I', struct.pack('<f', f))[0]

def _x2rv(x):
    f = 0
    if x & X_INVALID:   f |= NV
    if x & X_DIVZERO:   f |= DZ
    if x & X_OVERFLOW:  f |= OF
    if x & X_UNDERFLOW: f |= UF
    if x & X_INEXACT:   f |= NX
    return f

def _run(mode, thunk):
    _m.fesetround(FE[mode]); _m.feclearexcept(X_ALL)
    r = thunk(); x = _m.fetestexcept(X_ALL); _m.fesetround(FE["rne"])
    return r, _x2rv(x)

def _canon(bits, flags):
    """Force RISC-V canonical qNaN for any NaN result."""
    if (bits & 0x7f800000) == 0x7f800000 and (bits & 0x007fffff) != 0:
        return QNAN, flags
    return bits, flags

# op in {"add","sub","mul","fma","sqrt"}; a,b,c are float bit patterns.
def ref(op, a, b=0, c=0, rm="rne"):
    fa, fb, fc = b2f(a), b2f(b), b2f(c)
    if rm == "rmm":
        # exact-tie only: away-from-zero from RUP/RDN
        up, _ = ref(op, a, b, c, "rup")
        dn, _ = ref(op, a, b, c, "rdn")
        _, fl = ref(op, a, b, c, "rne")
        res = up if abs(b2f(up)) >= abs(b2f(dn)) else dn
        return _canon(res, fl | NX)
    if op == "add":  r, fl = _run(rm, lambda: _m.fmaf(1.0, fa, fb))
    elif op == "sub": r, fl = _run(rm, lambda: _m.fmaf(1.0, fa, -fb))
    elif op == "mul":
        r, fl = _run(rm, lambda: _m.fmaf(fa, fb, 0.0))
        bits = f2b(r)
        if (bits & 0x7fffffff) == 0:  # sign-of-zero fixup for mul
            bits = ((a ^ b) & 0x80000000)
            return bits, fl
        return _canon(bits, fl)
    elif op == "fma": r, fl = _run(rm, lambda: _m.fmaf(fa, fb, fc))
    elif op == "sqrt": r, fl = _run(rm, lambda: _m.sqrtf(fa))
    else: raise ValueError(op)
    return _canon(f2b(r), fl)

# round_to_single(hi+lo) via the real engine (hi,lo exactly representable).
def ref_round_int(hi_bits, lo_bits, rm):
    return ref("add", hi_bits, lo_bits, rm=rm)

# ---- assembly emit -------------------------------------------------------
class T:
    def __init__(self, name, desc):
        self.name, self.desc, self.n = name, desc, 0
        self.body = []
    def line(self, s): self.body.append(s)
    def op2(self, mnem, a, b, rm, res, fl):
        self.n += 1
        self.line("  li TESTNUM,%d" % self.n)
        self.line("  li s2,0x%08x" % a); self.line("  li s3,0x%08x" % b)
        self.line("  csrrw x0,fflags,x0")
        self.line("  %s s5,s2,s3%s" % (mnem, ("," + rm) if rm else ""))
        self.line("  csrr s6,fflags")
        self.line("  li a4,0x%08x" % res); self.line("  bne s5,a4,fail")
        self.line("  li a5,0x%02x" % fl);  self.line("  bne s6,a5,fail")
        self.line("")
    def op1(self, mnem, a, rm, res, fl, rd="s5"):
        self.n += 1
        self.line("  li TESTNUM,%d" % self.n)
        self.line("  li s2,0x%08x" % a)
        self.line("  csrrw x0,fflags,x0")
        self.line("  %s %s,s2%s" % (mnem, rd, ("," + rm) if rm else ""))
        self.line("  csrr s6,fflags")
        if rd != "x0":
            self.line("  li a4,0x%08x" % res); self.line("  bne %s,a4,fail" % rd)
        self.line("  li a5,0x%02x" % fl);  self.line("  bne s6,a5,fail")
        self.line("")
    def text(self):
        return ("".join([
"# GENERATED by verification/isa/tools/gen_directed.py -- DO NOT HAND EDIT.\n",
"# %s\n" % self.desc,
"# Reference: glibc fmaf/sqrtf via ctypes + libm fenv (real IEEE-754 single;\n",
"# x87 not used, glibc fmaf for FMA). See the generator header.\n",
'#include "riscv_test.h"\n',
'#include "test_macros.h"\n\n',
".option arch, +zfinx\n\n",
"RVTEST_RV32U\nRVTEST_CODE_BEGIN\n\n"]) +
                "\n".join(self.body) +
"\n  TEST_PASSFAIL\n\nRVTEST_CODE_END\n\n"
"  .data\nRVTEST_DATA_BEGIN\n  TEST_DATA\nRVTEST_DATA_END\n")

# ---- categories ----------------------------------------------------------
def gen_dround():
    t = T("dround", "corner rounding RNE/RTZ/RDN/RUP/RMM on exact ties")
    # exact ties via fcvt.s.w AND fadd of the two exact components.
    # 2^24+1 = 16777216 + 1  (tie: RNE->even=2^24) ; +3, and negatives.
    HI = 0x4b800000  # 2^24 = 16777216.0f
    ties = [(1, "16777217"), (3, "16777219"), (-1, "-16777217"), (-3, "-16777219")]
    for lo_int, label in ties:
        neg = lo_int < 0
        hi = HI | (0x80000000 if neg else 0)
        lo = f2b(float(abs(lo_int))) | (0x80000000 if neg else 0)
        mag = 16777216 + abs(lo_int)          # exact integer magnitude (a tie)
        intval = -mag if neg else mag
        for rm in ("rne", "rtz", "rdn", "rup", "rmm"):
            res, fl = ref_round_int(hi, lo, rm)
            # DUT: fcvt.s.w from the actual integer
            t.n += 1
            t.line("  li TESTNUM,%d" % t.n)
            t.line("  li a0,%d" % intval)
            t.line("  csrrw x0,fflags,x0")
            t.line("  fcvt.s.w s5,a0,%s" % rm)
            t.line("  csrr s6,fflags")
            t.line("  li a4,0x%08x" % res); t.line("  bne s5,a4,fail")
            t.line("  li a5,0x%02x" % fl);  t.line("  bne s6,a5,fail")
            t.line("")
            # DUT: fadd of the two exact components (same tie, same reference)
            t.op2("fadd.s", hi, lo, rm, res, fl)
    return t

def gen_dsubnrm():
    t = T("dsubnrm", "subnormal operands / gradual-underflow results")
    MIN_SUB, MAX_SUB, MIN_NRM = 0x00000001, 0x007fffff, 0x00800000
    HALF, TWO = f2b(0.5), f2b(2.0)
    for (op, a, b) in [("mul", MAX_SUB, HALF),            # subnormal*0.5 exact
                       ("mul", MIN_NRM, f2b(0.75)),       # normal*0.75 -> subnormal (UF|NX)
                       ("add", MIN_SUB, MIN_SUB),         # 2*smallest subnormal (exact)
                       ("mul", MAX_SUB, f2b(1e30)),       # subnormal*big -> normal
                       ("sub", MIN_NRM, MIN_SUB)]:        # normal-tiny -> largest subnormal
        res, fl = ref(op, a, b)
        t.op2({"add":"fadd.s","sub":"fsub.s","mul":"fmul.s"}[op], a, b, "rne", res, fl)
    for a in [MAX_SUB]:                                    # sqrt of subnormal
        res, fl = ref("sqrt", a)
        t.op1("fsqrt.s", a, "", res, fl)
    return t

def gen_dnan():
    t = T("dnan", "canonical-NaN propagation, sNaN->NV, invalid ops")
    QN, SN, INF, NINF, ONE, ZERO = 0x7fc00000, 0x7f800001, 0x7f800000, 0xff800000, f2b(1.0), 0
    # qNaN propagates -> canonical qNaN, NO flag
    t.op2("fadd.s", QN, ONE, "rne", QNAN, 0)
    # sNaN operand -> NV + canonical qNaN
    t.op2("fadd.s", SN, ONE, "rne", QNAN, NV)
    t.op2("fmul.s", ONE, SN, "rne", QNAN, NV)
    # invalid arithmetic -> NV + canonical qNaN (spec-fixed)
    t.op2("fmul.s", ZERO, INF, "rne", QNAN, NV)      # 0*inf
    t.op2("fsub.s", INF, INF, "rne", QNAN, NV)       # inf-inf
    t.op2("fadd.s", INF, NINF, "rne", QNAN, NV)      # inf+(-inf)
    # division specials (DZ / NV) -- spec-fixed, no rounding engine needed
    t.op2("fdiv.s", ZERO, ZERO, "", QNAN, NV)        # 0/0
    t.op2("fdiv.s", INF, INF, "", QNAN, NV)          # inf/inf
    t.op2("fdiv.s", ONE, ZERO, "", INF, DZ)          # x/0 -> +inf, DZ (not NV)
    t.op2("fdiv.s", f2b(-1.0), ZERO, "", NINF, DZ)   # -x/0 -> -inf, DZ
    # sqrt specials
    t.op1("fsqrt.s", f2b(-1.0), "", QNAN, NV)        # sqrt(-1) -> NV, qNaN
    t.op1("fsqrt.s", 0x80000000, "", 0x80000000, 0)  # sqrt(-0) -> -0, no flag
    return t

def gen_dpmzero():
    t = T("dpmzero", "+/-0 fmin/fmax quirks and signed-zero addition")
    PZ, NZ, ONE, NONE = 0, 0x80000000, f2b(1.0), f2b(-1.0)
    QN, SN = 0x7fc00000, 0x7f800001
    # fmin(-0,+0)=-0 ; fmax(-0,+0)=+0
    for (m, a, b, r) in [("fmin.s", NZ, PZ, NZ), ("fmin.s", PZ, NZ, NZ),
                         ("fmax.s", NZ, PZ, PZ), ("fmax.s", PZ, NZ, PZ),
                         ("fmin.s", ONE, NONE, NONE), ("fmax.s", ONE, NONE, ONE),
                         ("fmin.s", QN, ONE, ONE), ("fmax.s", ONE, QN, ONE)]:
        t.op2(m, a, b, "", r, 0)
    # sNaN in min/max -> NV, returns the number
    t.op2("fmin.s", SN, ONE, "", ONE, NV)
    t.op2("fmax.s", ONE, SN, "", ONE, NV)
    t.op2("fmin.s", SN, QN, "", QNAN, NV)         # both NaN (one sNaN) -> qNaN+NV
    # signed-zero add
    t.op2("fadd.s", PZ, NZ, "rne", *ref("add", PZ, NZ))  # +0 + -0 = +0
    t.op2("fadd.s", NZ, NZ, "rne", *ref("add", NZ, NZ))  # -0 + -0 = -0
    return t

def gen_dfcvttab():
    t = T("dfcvttab", "fcvt.w/wu.s invalid-result table (frozen ruling Q5)")
    # POSBIG (3e9) overflows SIGNED (>2^31-1) but FITS unsigned (<2^32); POSBIGU
    # (5e9) overflows UNSIGNED too (>2^32-1). Using POSBIG for the fcvt.wu.s
    # overflow case was a generator bug: 3e9 converts exactly to 0xB2D05E00 with
    # no NV, so the unsigned-overflow row must use a genuine >2^32 value.
    QN, INF, NINF, POSBIG, NEGBIG = 0x7fc00000, 0x7f800000, 0xff800000, f2b(3e9), f2b(-3e9)
    POSBIGU = f2b(5e9)
    tab = [("fcvt.w.s",  QN,     0x7fffffff, NV),
           ("fcvt.w.s",  INF,    0x7fffffff, NV),
           ("fcvt.w.s",  POSBIG, 0x7fffffff, NV),
           ("fcvt.w.s",  NINF,   0x80000000, NV),
           ("fcvt.w.s",  NEGBIG, 0x80000000, NV),
           ("fcvt.wu.s", QN,     0xffffffff, NV),
           ("fcvt.wu.s", INF,    0xffffffff, NV),
           ("fcvt.wu.s", POSBIGU, 0xffffffff, NV),
           ("fcvt.wu.s", NINF,   0x00000000, NV),
           ("fcvt.wu.s", NEGBIG, 0x00000000, NV),
           ("fcvt.wu.s", f2b(-0.5), 0x00000000, NX)]  # -0.5->0 (rtz), inexact only
    for mn, inb, res, fl in tab:
        t.n += 1
        t.line("  li TESTNUM,%d" % t.n)
        t.line("  li s2,0x%08x" % inb)
        t.line("  csrrw x0,fflags,x0")
        t.line("  %s a0,s2,rtz" % mn)
        t.line("  csrr s6,fflags")
        t.line("  li a4,0x%08x" % res); t.line("  bne a0,a4,fail")
        t.line("  li a5,0x%02x" % fl);  t.line("  bne s6,a5,fail")
        t.line("")
    return t

def gen_daccum():
    t = T("daccum", "sticky-flag accumulation across a sequence (OR, not clear)")
    L = t.line
    L("  li TESTNUM,1")
    L("  csrrw x0,fflags,x0        # clear ONCE")
    L("  li s2,0x%08x" % f2b(1.0)); L("  li s3,0x30000000"); L("  fadd.s s5,s2,s3,rne   # NX")
    L("  li s2,0x%08x" % f2b(1.0)); L("  li s3,0x00000000"); L("  fdiv.s s5,s2,s3       # DZ")
    L("  li s2,0x7f800000"); L("  li s3,0x7f800000"); L("  fsub.s s5,s2,s3       # NV")
    L("  li s2,0x%08x" % f2b(3e38)); L("  li s3,0x%08x" % f2b(3e38)); L("  fmul.s s5,s2,s3,rne   # OF|NX")
    L("  li s2,0x%08x" % f2b(1e-30)); L("  li s3,0x%08x" % f2b(1e-30)); L("  fmul.s s5,s2,s3,rne   # UF|NX")
    L("  csrr s6,fflags           # read ONCE at the end")
    L("  li a5,0x1f"); L("  bne s6,a5,fail   # must be the OR of every op's flags")
    L("")
    return t

def gen_drdx0():
    t = T("drdx0", "rd=x0 fp op still sets fflags (results discarded)")
    L = t.line
    L("  li TESTNUM,1")
    L("  csrrw x0,fflags,x0")
    L("  li s2,0x%08x" % f2b(1.0)); L("  li s3,0x30000000")
    L("  fadd.s x0,s2,s3,rne       # rd=x0, sum inexact")
    L("  csrr s6,fflags")
    L("  li a5,0x%02x" % NX); L("  bne s6,a5,fail   # NX must set even with rd=x0")
    L("")
    L("  li TESTNUM,2")
    L("  csrrw x0,fflags,x0")
    L("  li s2,0x7f800000"); L("  li s3,0x7f800000")
    L("  fsub.s x0,s2,s3           # inf-inf, rd=x0")
    L("  csrr s6,fflags")
    L("  li a5,0x%02x" % NV); L("  bne s6,a5,fail   # NV must set even with rd=x0")
    L("")
    return t

def gen_dsgnj():
    t = T("dsgnj", "fsgnj / fsgnjn / fsgnjx sign injection (no flags)")
    A, NA, B, NB = f2b(3.5), f2b(-3.5), f2b(1.0), f2b(-1.0)
    for (m, a, b, r) in [("fsgnj.s",  A, NB, NA), ("fsgnj.s",  NA, B, A),
                         ("fsgnjn.s", A, B, NA), ("fsgnjn.s", A, NB, A),
                         ("fsgnjx.s", A, NB, NA), ("fsgnjx.s", NA, NB, A),
                         ("fsgnjn.s", A, A, NA),  # fneg
                         ("fsgnjx.s", NA, NA, A)]:  # fabs
        t.op2(m, a, b, "", r, 0)
    return t

GENS = [gen_dround, gen_dsubnrm, gen_dnan, gen_dpmzero,
        gen_dfcvttab, gen_daccum, gen_drdx0, gen_dsgnj]

def emit(outdir):
    os.makedirs(outdir, exist_ok=True)
    out = {}
    for g in GENS:
        t = g(); out[t.name + ".S"] = t.text()
        with open(os.path.join(outdir, t.name + ".S"), "w") as f:
            f.write(out[t.name + ".S"])
    return out

def main():
    args = [a for a in sys.argv[1:] if a != "--check"]
    check = "--check" in sys.argv[1:]
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = args[0] if args else os.path.normpath(os.path.join(here, "..", "tests", "rv32uzf"))
    if not check:
        emit(outdir)
        sys.stderr.write("gen_directed: wrote %d directed tests to %s\n" % (len(GENS), outdir))
        return 0
    tmp = tempfile.mkdtemp(); gen = emit(tmp); rc = 0
    for fn, txt in gen.items():
        p = os.path.join(outdir, fn)
        cur = open(p).read() if os.path.exists(p) else ""
        if cur != txt:
            rc = 1; sys.stderr.write("DIFF in %s\n" % fn)
    print("gen_directed --check: %s" % ("CLEAN" if rc == 0 else "DIFFERENCES"))
    return rc

if __name__ == "__main__":
    sys.exit(main())
