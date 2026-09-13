#!/usr/bin/env python3
"""VestaRV: bit-exact golden model of the NPU's fixed-point arithmetic.

Reproduces NPU.vhd, FPMac.vhd and FPSigmoid.vhd in integer math under the rounding and
saturation rules of hdl/common/commune/fixed_pkg_c.vhdl: round half to even, then saturate
to the target format's two's-complement extremes. A Q(M).(N) value is a plain Python int
`raw` with real_value = raw / 2**N, never masked, and resized only where the RTL resizes.
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
    """Bit-exact replica of fixed_pkg's `resize` for UNRESOLVED_sfixed. raw_in is exact at fraction
    scale n_in, so there is no m_in parameter: the structural overflow check and the magnitude
    check against the target format coincide. Returns raw_out at scale n_out.
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

    # Step 2: rounding (round_fixed, fixed_pkg_c.vhdl 2272-2308)
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
    """Bit-exact replica of fixed_pkg's to_sfixed(INTEGER) at right_index = -n. Not `value << n`:
    with 0 integer bits, integer 1 overflows a 1-bit signed field and saturates to 2**n - 1. That
    quirk is load-bearing, since NPU.vhd's bias tap is to_sfixed(1, X_M_BITS, -N_BITS).
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
    """One FPMac.vhd combinational step and its registered latch:
    Y = resize(acc + A*B, ACC_M_BITS, -N_BITS). The operand widths are untracked because the
    product is exact regardless. Returns the new Q(acc_m).(n_bits) raw accumulator.
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
    """ACTF=1, ReLU on the signed accumulator, max(0, x), with no FPSigmoid involvement. The output
    keeps the accumulator's own Q(y_m).(n_bits) full range and is not clamped to [0,1).
    """
    return x_raw if x_raw >= 0 else 0


def tanh_approx(x_raw, y_m, n_bits, rho=2):
    """ACTF=2, 2*sigma(2x) - 1, built entirely on the exact FPSigmoid replica plus two exact
    primitives. `pre` reproduces the RTL's saturating pre-shift bit for bit, which is what keeps
    the sign correct at large |x|; the post-map is a shift and a subtract, so it is exact.
    """
    pre = resize_sfixed(x_raw, n_bits - 1, y_m, n_bits,
                         round_style=ROUND_NEAREST,
                         overflow_style=SAT_SATURATE)
    y = sigmoid(pre, y_m, n_bits, rho)
    return (y << 1) - (1 << n_bits)


def clamp01(x_raw, n_bits):
    """ACTF=3, hardtanh: a saturating resize of the accumulator down to Q0.(n_bits), reusing the
    same primitive already validated for the MAC path.
    """
    return resize_sfixed(x_raw, n_bits, 0, n_bits,
                          round_style=ROUND_NEAREST,
                          overflow_style=SAT_SATURATE)


def exp_approx(x_raw, y_m, n_bits, rho=2):
    """ACTF=4, the softmax-leg surrogate 2*sigma(x), straight into FPSigmoid with no pre-shift. It is
    exact: a left shift of an output that already fits Q0.(n_bits), so the result fits Q1.(n_bits).
    """
    return sigmoid(x_raw, y_m, n_bits, rho) << 1


def activate(acc, aen, actf, y_m, n_bits, rho=2):
    """The golden-side equivalent of the RTL's ACTF-selected output mux, gated by AEN. aen=0 is
    passthrough and ACTF a don't-care; actf 0 to 4 select sigmoid, relu, tanh, clamp and exp;
    actf 5 to 7 are reserved and decode as sigmoid without trapping.
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
    """One NPU THINK over one layer, matching NPU.vhd's weight walk: the pointer runs contiguously
    from w_offset across all neurons, bias tap first when ben, then inputs 0..ni. Returns
    (outputs, next_w_offset); `trace` collects (neuron_index, acc_raw) before activation.
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


# Debug helpers (never used in the arithmetic path itself -- display only)

def raw_to_float(raw, n_bits):
    """For human-readable trace printing ONLY -- never fed back into the
    integer arithmetic path."""
    return raw / float(1 << n_bits)


def raw_to_hex(raw, m_bits, n_bits):
    width = m_bits + n_bits + 1
    mask = (1 << width) - 1
    return '0x%0*X' % ((width + 3) // 4, raw & mask)
