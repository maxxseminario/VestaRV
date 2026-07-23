#!/usr/bin/env python3
"""npu_fixed.py -- bit-exact golden model of the VestaRV NPU's fixed-point
arithmetic (Python 3.6+, no third-party deps, no floats in the arithmetic
path).

This reproduces, in pure integer math, exactly what the synthesizable RTL
computes:

  hdl/common/periph/NPU.vhd    -- MLP FSM (bias-first MAC walk, sigmoid gate)
  hdl/common/commune/FPMac.vhd -- multiply-accumulate: one exact widen +
                                   one fixed_pkg resize (round + saturate)
  hdl/common/commune/FPSigmoid.vhd -- piecewise-quadratic sigmoid (RHO=2)

The rounding/saturation rule being replicated is the David Bishop
`fixed_pkg` compatibility fork actually compiled into this repo:
    hdl/common/commune/fixed_pkg_c.vhdl
Defaults (package constants, lines 28/30):
    fixed_round_style    := fixed_round      (round to nearest)
    fixed_overflow_style := fixed_saturate   (saturate on overflow)

The exact rounding tie-break is in `round_fixed` (fixed_pkg_c.vhdl lines
2272-2308, sfixed overload): the discarded bits are inspected as a
remainder; if the remainder's MSB is '1' AND (any lower remainder bit is
'1' OR the kept LSB is '1'), round up (add 1 ULP); a bare tie (remainder
== exactly half, kept LSB == 0) does NOT round up. That is:

    ROUND-HALF-TO-EVEN (banker's rounding), NOT round-half-up.

  - remainder > half            -> always round up
  - remainder == half, LSB==1   -> round up   (result becomes even)
  - remainder == half, LSB==0   -> stays put  (already even)
  - remainder <  half           -> stays put

Saturation after rounding (round_fixed, `round_overflow`) and saturation
from integer-bit truncation (`resize`, lines 5603-5697, sfixed overload)
both saturate to the two's-complement extremes of the TARGET format:
    max = 2^(M+N) - 1   (0111...1)
    min = -2^(M+N)      (1000...0)
(fixed_pkg_c.vhdl `saturate`, lines 5139-5149: all-ones with the sign bit
forced to '0'; the negative extreme is its bitwise NOT.)

Number-representation convention used throughout this file
-------------------------------------------------------------
A fixed-point value in format Q(M).(N) (M integer bits + 1 implicit sign
bit + N fraction bits, two's-complement, (M+N+1) bits total) is carried
around as a plain Python integer "raw" such that

    real_value = raw / 2**N

`raw` is NEVER masked/truncated to (M+N+1) bits implicitly -- Python ints
are arbitrary precision, and the VHDL `+`/`-`/`*`/`abs`/`scalb` operators
on sfixed are THEMSELVES always exact (the package widens the result type
to hold the full-precision answer; only an explicit `resize` call rounds
or saturates). So every "exact" VHDL operation below is a plain Python
`+`/`-`/`*`/`abs` on `raw`, tracking the implied (M, N) format only far
enough to know how to `resize` when the RTL explicitly does so. This is
the ONLY way both sides can produce identical bits: we are not emulating
finite registers, we are computing the exact rational the hardware's
exact combinational network computes, then rounding at the exact points
the RTL rounds.
"""

ROUND_NEAREST = 'round'      # fixed_round     (package default)
ROUND_TRUNCATE = 'truncate'  # fixed_truncate
SAT_SATURATE = 'saturate'    # fixed_saturate  (package default)
SAT_WRAP = 'wrap'            # fixed_wrap


def _sat_bounds(m_out, n_out):
    """Two's-complement extremes of a Q(m_out).(n_out) format, in raw units
    (i.e. already scaled by 2**n_out). fixed_pkg_c.vhdl `saturate`."""
    max_out = (1 << (m_out + n_out)) - 1
    min_out = -(1 << (m_out + n_out))
    return min_out, max_out


def resize_sfixed(raw_in, n_in, m_out, n_out,
                   round_style=ROUND_NEAREST, overflow_style=SAT_SATURATE):
    """Bit-exact replica of fixed_pkg's `resize` for UNRESOLVED_sfixed
    (fixed_pkg_c.vhdl lines 5603-5697).

    raw_in is an exact two's-complement value at fraction scale n_in
    (real = raw_in / 2**n_in); there is deliberately NO m_in parameter --
    the VHDL structural "extra integer bits" overflow check and the
    value-magnitude check against the target format are mathematically
    identical once raw_in is known exactly (see module docstring), so we
    just compare against the target's own saturation bounds.

    Returns raw_out at fraction scale n_out, format Q(m_out).(n_out).
    """
    min_out, max_out = _sat_bounds(m_out, n_out)
    shift = n_in - n_out

    if shift >= 0:
        # Dropping (shift) fraction bits. Arithmetic right shift == floor
        # division for two's-complement negatives (Python's >> on int does
        # this correctly), matching VHDL's plain bit-slice of invec.
        floor_val = raw_in >> shift
        remainder = raw_in - (floor_val << shift)   # in [0, 2**shift)
    else:
        # Gaining fraction bits: exact, zero-fill, no rounding possible.
        floor_val = raw_in << (-shift)
        remainder = 0

    # --- Step 1: "structural" integer-bit overflow (resize's first two
    # branches: right_index > arghigh / left_index < arglow / arghigh >
    # left_index) -- happens BEFORE rounding and, when it fires, bypasses
    # rounding entirely.
    if floor_val > max_out or floor_val < min_out:
        if overflow_style == SAT_SATURATE:
            return max_out if raw_in >= 0 else min_out
        else:  # fixed_wrap
            width = m_out + n_out + 1
            mask = (1 << width) - 1
            wrapped = floor_val & mask
            if wrapped >= (1 << (width - 1)):
                wrapped -= (1 << width)
            return wrapped

    result = floor_val

    # --- Step 2: rounding (round_fixed, fixed_pkg_c.vhdl 2272-2308) ---
    if shift > 0 and round_style == ROUND_NEAREST:
        half = 1 << (shift - 1)
        if remainder > half:
            result = floor_val + 1
        elif remainder == half:
            if (floor_val & 1) == 1:      # kept LSB is '1' -> round to even
                result = floor_val + 1
            # else kept LSB '0': already even, no round (banker's rounding)
        # else remainder < half: no rounding

    # --- Step 2b: rounding-induced overflow (round_up's `overflowx`,
    # fixed_pkg_c.vhdl 2222-2235: only fires when floor_val WAS exactly the
    # positive saturate value and the +1 carried the sign bit) ---
    if result > max_out:
        if overflow_style == SAT_SATURATE:
            return max_out
        else:
            width = m_out + n_out + 1
            mask = (1 << width) - 1
            wrapped = result & mask
            if wrapped >= (1 << (width - 1)):
                wrapped -= (1 << width)
            return wrapped
    # (result < min_out cannot happen: rounding only ever adds +1, and
    # floor_val was already checked >= min_out above.)
    return result


def int_to_sfixed(value, m, n, overflow_style=SAT_SATURATE):
    """Bit-exact replica of fixed_pkg's `to_sfixed(arg: INTEGER; left_index;
    right_index)` (fixed_pkg_c.vhdl lines 4744-4797), specialised to
    right_index = -n (the only form the RTL uses).

    Converts the *mathematical integer* `value` into the raw Q(m).(n)
    representation. NOTE: this is emphatically NOT the same as
    `value << n` when `value` does not fit in the (m+1)-bit integer
    part -- e.g. int_to_sfixed(1, 0, N) does NOT give 2**N (an exact
    1.0); with 0 integer bits, integer 1 overflows a 1-bit signed field
    ([-1, 0]) and SATURATES to 2**N - 1 (just under 1.0). This exact
    quirk is load-bearing: NPU.vhd's bias tap is
    `to_sfixed(1, X_M_BITS, -N_BITS)`, and at the bench's X_M_BITS=0 the
    "bias input" is actually 0.999969..., not 1.0.
    """
    if value == 0:
        return 0
    max_int = (1 << m) - 1
    min_int = -(1 << m)
    if value > max_int or value < min_int:
        min_out, max_out = _sat_bounds(m, n)
        if overflow_style == SAT_SATURATE:
            return max_out if value > 0 else min_out
        else:
            width_int = m + 1
            mask = (1 << width_int) - 1
            wrapped = value & mask
            if wrapped >= (1 << (width_int - 1)):
                wrapped -= (1 << width_int)
            return wrapped << n
    return value << n


def mac_step(acc_raw, a_raw, b_raw, acc_m, n_bits):
    """One FPMac.vhd combinational step + its registered latch, i.e. the
    Q7.24-style accumulator update:

        Y = resize(acc + A*B, ACC_M_BITS, -N_BITS)

    acc_raw : Q(acc_m).(n_bits) raw accumulator (pre-step)
    a_raw   : Q(*).(n_bits) raw "A" operand (any A_M_BITS -- untracked,
              since the product is exact regardless of the nominal width)
    b_raw   : Q(*).(n_bits) raw "B" operand
    Returns the new Q(acc_m).(n_bits) raw accumulator.
    """
    prod_raw_2n = a_raw * b_raw               # exact, scale 2*n_bits
    sum_raw_2n = (acc_raw << n_bits) + prod_raw_2n   # exact, scale 2*n_bits
    return resize_sfixed(sum_raw_2n, 2 * n_bits, acc_m, n_bits,
                          round_style=ROUND_NEAREST,
                          overflow_style=SAT_SATURATE)


def sigmoid(x_raw, x_m, n_bits, rho=2):
    """Bit-exact replica of FPSigmoid.vhd (piecewise quadratic, Cyganek &
    Socha). x_raw is Q(x_m).(n_bits) (the NPU wires X_M_BITS => Y_M_BITS,
    i.e. the accumulator's own M width). Returns Y_raw in Q0.(n_bits).
    """
    n = n_bits

    # XSFixed <= X (reinterpret only, same bits)                    (m=x_m)
    # XSignBit <= XSFixed(high)
    sign_bit = 1 if x_raw < 0 else 0

    # XAbs <= abs(XSFixed)                                    (m=x_m+1, exact)
    xabs_raw = abs(x_raw)                                    # scale n

    # XOutOfRangeF <= or_reduce(XAbs(high downto RHO))
    # -- true iff |x| >= 2**rho, i.e. any bit at weight >= 2**rho is set.
    out_of_range = (xabs_raw >> (rho + n)) != 0

    # XInRange <= resize(XAbs, RHO downto -N)                        (m=rho)
    xinrange_raw = resize_sfixed(xabs_raw, n, rho, n,
                                  round_style=ROUND_NEAREST,
                                  overflow_style=SAT_SATURATE)

    # YInt1 <= resize(scalb(XInRange, -RHO) + to_sfixed(-1, 0, -(N+RHO)),
    #                 0 downto -N)
    # scalb is an exact reinterpretation: same raw bits, scale becomes n+rho.
    scalb_raw = xinrange_raw                                  # scale n+rho
    neg_one_raw = int_to_sfixed(-1, 0, n + rho)               # scale n+rho
    sum_raw = scalb_raw + neg_one_raw                         # scale n+rho
    yint1_raw = resize_sfixed(sum_raw, n + rho, 0, n,
                               round_style=ROUND_NEAREST,
                               overflow_style=SAT_SATURATE)   # scale n

    # YInt2 <= YInt1 * YInt1                                  (exact, scale 2n)
    yint2_raw = yint1_raw * yint1_raw

    # YInt3 <= resize(scalb(YInt2, -1), 0 downto -N)
    # scalb(-1): same raw bits, scale becomes 2n+1.
    yint3_pre_raw = yint2_raw                                 # scale 2n+1
    yint3_raw = resize_sfixed(yint3_pre_raw, 2 * n + 1, 0, n,
                               round_style=ROUND_NEAREST,
                               overflow_style=SAT_SATURATE)   # scale n

    if sign_bit == 1 and out_of_range:          # "11" negative & OOR
        y_raw = 0
    elif sign_bit == 1 and not out_of_range:    # "10" negative & in range
        y_raw = yint3_raw
    elif sign_bit == 0 and not out_of_range:     # "00" positive & in range
        one_raw = int_to_sfixed(1, 1, n)         # format (YOutTemp'high+1)=1
        sub_raw = one_raw - yint3_raw             # exact, scale n
        y_raw = resize_sfixed(sub_raw, n, 0, n,
                               round_style=ROUND_NEAREST,
                               overflow_style=SAT_SATURATE)
    else:                                        # "01" positive & OOR
        # to_sfixed(1, YOutTemp'high=0, YOutTemp'low=-N): 1 overflows a
        # 0-integer-bit signed field -> saturates to just-under-1.0.
        y_raw = int_to_sfixed(1, 0, n)

    return y_raw


def relu(x_raw):
    """ACTF=1 (P4.4 D2): ReLU on the signed Q(y_m).(n_bits) accumulator --
    `max(0, x)`, no FPSigmoid involvement. Output format is the SAME
    Q(y_m).(n_bits) as the accumulator (full range, NOT clamped to [0,1) --
    a ReLU'd accumulator can still be up to +128 real at the MCU generics)."""
    return x_raw if x_raw >= 0 else 0


def tanh_approx(x_raw, y_m, n_bits, rho=2):
    """ACTF=2 (P4.4 D3): `2*sigma(2x) - 1`, built ENTIRELY on the exact
    FPSigmoid replica (`sigmoid()`) plus the two literal, exact primitives
    already validated for the MAC path -- no new arithmetic.

    `pre` reproduces the RTL's saturating pre-shift bit-for-bit: `scalb(x,
    +1)` (same raw bits, scale becomes n_bits-1) then a saturating resize
    back to the FPSigmoid input format Q(y_m).(n_bits) -- this is exactly
    what keeps the sign correct for |x| >= 64 (GA4). The post-map `2y - 1`
    is exact (a left-shift and a subtract only, no rounding of its own --
    sigmoid()'s own output already fits Q0.(n_bits))."""
    pre = resize_sfixed(x_raw, n_bits - 1, y_m, n_bits,
                         round_style=ROUND_NEAREST,
                         overflow_style=SAT_SATURATE)
    y = sigmoid(pre, y_m, n_bits, rho)
    return (y << 1) - (1 << n_bits)


def clamp01(x_raw, n_bits):
    """ACTF=3 (P4.4 D4): hardtanh -- saturating resize of the Q(y_m).
    (n_bits) accumulator down to Q0.(n_bits) (clamp to [-1, 1-2**-n_bits]).
    Reuses the same saturating-resize primitive already validated for the
    MAC path (resize_sfixed) -- no new arithmetic."""
    return resize_sfixed(x_raw, n_bits, 0, n_bits,
                          round_style=ROUND_NEAREST,
                          overflow_style=SAT_SATURATE)


def exp_approx(x_raw, y_m, n_bits, rho=2):
    """ACTF=4 (P4.4 D5): the softmax-leg surrogate `exp~(x) = 2*sigma(x)`
    (no pre-shift, unlike tanh -- straight into FPSigmoid, same as the
    sigmoid path). Exact: a left-shift of sigmoid()'s own output, which
    already fits Q0.(n_bits), so `2*sigma(x)` fits Q1.(n_bits) with no
    further rounding/saturation."""
    return sigmoid(x_raw, y_m, n_bits, rho) << 1


def activate(acc, aen, actf, y_m, n_bits, rho=2):
    """P4.4 D9 dispatcher: the golden-side equivalent of the RTL's
    ACTF-selected `act_out` mux (TP1), gated by the AEN master enable (D1).

    aen=0            -> passthrough (acc unchanged), ACTF is a don't-care.
    aen=1, actf=0     -> sigmoid (legacy).
    aen=1, actf=1..4  -> relu / tanh_approx / clamp01 / exp_approx.
    aen=1, actf=5..7  -> reserved: decode as sigmoid, no trap (D6).
    """
    if not aen:
        return acc
    if actf == 1:
        return relu(acc)
    if actf == 2:
        return tanh_approx(acc, y_m, n_bits, rho)
    if actf == 3:
        return clamp01(acc, n_bits)
    if actf == 4:
        return exp_approx(acc, y_m, n_bits, rho)
    return sigmoid(acc, y_m, n_bits, rho)   # actf==0 and reserved 5/6/7


def think_layer(x_list, w_list, ni, nn, ben, aen, x_m, w_m, y_m, n_bits,
                 rho=2, w_offset=0, trace=None, actf=0):
    """One NPU THINK over one layer, exactly matching NPU.vhd's FSM weight
    walk: weight pointer runs contiguously from WVSAR across ALL neurons,
    bias tap first (if BEN) then inputs 0..ni in order, per neuron.

    x_list  : list of Q(x_m).(n_bits) raw inputs, length >= ni+1
    w_list  : full weight raw array (as loaded in the staging RAM); reading
              starts at w_offset (mirrors WVSAR) and walks forward
    ni, nn  : NPUNI/NPUNN register values (per-neuron loop count is ni+1,
              neuron count is nn+1)
    ben,aen : NPUBEN/NPUAEN
    actf    : NPUCR ACTF field (P4.4 D9; default 0 = sigmoid-legacy). When
              aen and actf==0 this calls the SAME `sigmoid(acc, y_m, n_bits,
              rho)` line the pre-P4.4 golden always called (the 4-legacy-set
              validation stays bit-for-bit untouched); nonzero actf
              dispatches through `activate()`.
    trace   : optional list to append (neuron_index, acc_raw) tuples to,
              for debug (pre-activation accumulator per neuron)

    Returns (outputs, next_w_offset) where outputs has length nn+1, each
    entry Q(y_m).(n_bits) raw (post-activation if aen else the accumulator
    itself, pass-through).
    """
    outputs = []
    widx = w_offset
    for _neuron in range(nn + 1):
        acc = 0  # AccResetN clears the accumulator to 0 between neurons
        if ben:
            bias_x = int_to_sfixed(1, x_m, n_bits)   # CurrX bias tap
            w = w_list[widx]
            widx += 1
            acc = mac_step(acc, bias_x, w, y_m, n_bits)
        for i in range(ni + 1):
            xi = x_list[i]
            w = w_list[widx]
            widx += 1
            acc = mac_step(acc, xi, w, y_m, n_bits)
        if trace is not None:
            trace.append(acc)
        if aen:
            if actf == 0:
                y = sigmoid(acc, y_m, n_bits, rho)
            else:
                y = activate(acc, 1, actf, y_m, n_bits, rho)
        else:
            y = acc
        outputs.append(y)
    return outputs, widx


# --------------------------------------------------------------------------
# Debug helpers (never used in the arithmetic path itself -- display only)
# --------------------------------------------------------------------------

def raw_to_float(raw, n_bits):
    """For human-readable trace printing ONLY -- never fed back into the
    integer arithmetic path."""
    return raw / float(1 << n_bits)


def raw_to_hex(raw, m_bits, n_bits):
    width = m_bits + n_bits + 1
    mask = (1 << width) - 1
    return '0x%0*X' % ((width + 3) // 4, raw & mask)
