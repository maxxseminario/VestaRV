#!/usr/bin/env python3
"""VestaRV: validate npu_fixed.py bit-exactly against the NPU MLP bench golden files.

One network, two fixed-point configurations: 'bench' is NPU_tb.vhd's generic defaults
(X_M=0, W_M=3, Y_M=3, N=15, RHO=2), 'chip' is the MCU instantiation's (W_M=7, Y_M=7,
N=24). NPU.S's get_y_loop still masks to 19 bits, the stale bench width, against the
chip dataset it now reads; harmless on these 201 points but not verified here.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import (  # noqa: E402
    think_layer, raw_to_float, raw_to_hex,
)

# 'bench': hdl/common/tb/NPU_tb.vhd generic defaults.
# 'chip':  hdl/common/MCU.vhd's NPU instantiation generics.
CONFIGS = {
    'bench': dict(x_m=0, w_m=3, y_m=3, n=15, rho=2),
    'chip':  dict(x_m=0, w_m=7, y_m=7, n=24, rho=2),
}

LAYER1_NI, LAYER1_NN, LAYER1_BEN, LAYER1_AEN = 0, 4, 1, 1
LAYER1_NWEIGHTS = (LAYER1_NI + 1 + 1) * (LAYER1_NN + 1)   # (bias+1 input)*5 = 10

LAYER2_NI, LAYER2_NN, LAYER2_BEN, LAYER2_AEN = 4, 0, 0, 0
LAYER2_NWEIGHTS = (LAYER2_NI + 1) * (LAYER2_NN + 1)       # 5 inputs*1 neuron = 5

N_POINTS = 201

FILE_INPUTS = 'npu_fp_inputs.txt'
FILE_WEIGHTS = 'npu_fp_weights.txt'
FILE_EXPECTED = 'npu_expected_fp_outputs.txt'

# (directory, default config) -- validated in this order when no --data-dir
# is given.
DEFAULT_TARGETS = [
    (os.path.expanduser('~/vestarv/xcelium/NPU/behavioral'), 'bench'),
    (os.path.expanduser('~/vestarv/xcelium/periph_test/behavioral'), 'bench'),
    (os.path.expanduser('~/vestarv/xcelium/NPU/genus'), 'bench'),
    (os.path.expanduser('~/vestarv/verification/isa/tests/periph/NPU_data'), 'chip'),
]


def read_int_list(path):
    vals = []
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                vals.append(int(line))
    return vals


def run_one(data_dir, cfg_name):
    cfg = CONFIGS[cfg_name]
    x_m, w_m, y_m, n_bits, rho = cfg['x_m'], cfg['w_m'], cfg['y_m'], cfg['n'], cfg['rho']

    print("=" * 72)
    print("[validate_mlp] data dir: %s  (config=%s: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d)"
          % (data_dir, cfg_name, x_m, w_m, y_m, n_bits, rho))

    inputs = read_int_list(os.path.join(data_dir, FILE_INPUTS))
    weights = read_int_list(os.path.join(data_dir, FILE_WEIGHTS))
    expected = read_int_list(os.path.join(data_dir, FILE_EXPECTED))

    assert len(inputs) == N_POINTS, \
        "expected %d input points, got %d" % (N_POINTS, len(inputs))
    assert len(expected) == N_POINTS, \
        "expected %d expected-output points, got %d" % (N_POINTS, len(expected))
    assert len(weights) == LAYER1_NWEIGHTS + LAYER2_NWEIGHTS, \
        "expected %d weights (%d L1 + %d L2), got %d" % (
            LAYER1_NWEIGHTS + LAYER2_NWEIGHTS, LAYER1_NWEIGHTS,
            LAYER2_NWEIGHTS, len(weights))

    layer1_weights = weights[0:LAYER1_NWEIGHTS]
    layer2_weights = weights[LAYER1_NWEIGHTS:LAYER1_NWEIGHTS + LAYER2_NWEIGHTS]

    n_match = 0
    mismatches = []

    for pt in range(N_POINTS):
        x0 = inputs[pt]

        l1_trace = []
        layer1_out, _ = think_layer(
            [x0], layer1_weights,
            ni=LAYER1_NI, nn=LAYER1_NN, ben=LAYER1_BEN, aen=LAYER1_AEN,
            x_m=x_m, w_m=w_m, y_m=y_m, n_bits=n_bits, rho=rho, trace=l1_trace)

        l2_trace = []
        layer2_out, _ = think_layer(
            layer1_out, layer2_weights,
            ni=LAYER2_NI, nn=LAYER2_NN, ben=LAYER2_BEN, aen=LAYER2_AEN,
            x_m=x_m, w_m=w_m, y_m=y_m, n_bits=n_bits, rho=rho, trace=l2_trace)

        y_model = layer2_out[0]
        y_expected = expected[pt]

        if y_model == y_expected:
            n_match += 1
        else:
            mismatches.append({
                'point': pt, 'x0': x0, 'y_model': y_model,
                'y_expected': y_expected, 'layer1_out': layer1_out,
                'layer1_acc_trace': l1_trace, 'layer2_acc_trace': l2_trace,
            })

    n_total = N_POINTS
    print("N_match / N_total = %d / %d" % (n_match, n_total))

    if mismatches:
        print("First %d mismatch(es):" % min(5, len(mismatches)))
        for m in mismatches[:5]:
            print("-" * 72)
            print("point %d  x0_raw=%d (x0=%.6f, hex=%s)" % (
                m['point'], m['x0'], raw_to_float(m['x0'], n_bits),
                raw_to_hex(m['x0'], x_m, n_bits)))
            print("  layer1 outputs (Q0.%d):" % n_bits)
            for idx, y1 in enumerate(m['layer1_out']):
                print("    n%d: raw=%d hex=%s float=%.8f  (pre-sigmoid acc raw=%d hex=%s)" % (
                    idx, y1, raw_to_hex(y1, 0, n_bits),
                    raw_to_float(y1, n_bits),
                    m['layer1_acc_trace'][idx],
                    raw_to_hex(m['layer1_acc_trace'][idx], y_m, n_bits)))
            print("  layer2 pre-output acc raw=%d hex=%s" % (
                m['layer2_acc_trace'][0],
                raw_to_hex(m['layer2_acc_trace'][0], y_m, n_bits)))
            print("  Y_MODEL    raw=%d hex=%s float=%.8f" % (
                m['y_model'], raw_to_hex(m['y_model'], y_m, n_bits),
                raw_to_float(m['y_model'], n_bits)))
            print("  Y_EXPECTED raw=%d hex=%s float=%.8f" % (
                m['y_expected'], raw_to_hex(m['y_expected'], y_m, n_bits),
                raw_to_float(m['y_expected'], n_bits)))
        print("-" * 72)

    ok = (n_match == n_total)
    verdict = ("100% bit-exact" if ok
               else "NOT bit-exact -- %d mismatched" % len(mismatches))
    print("RESULT: %s (%d/%d)." % (verdict, n_match, n_total))
    print("")
    return ok


def parse_args(argv):
    data_dir = None
    config = None
    i = 0
    while i < len(argv):
        if argv[i] == '--data-dir' and i + 1 < len(argv):
            data_dir = argv[i + 1]
            i += 2
        elif argv[i] == '--config' and i + 1 < len(argv):
            config = argv[i + 1]
            i += 2
        else:
            i += 1
    return data_dir, config


def main():
    data_dir, config = parse_args(sys.argv[1:])

    if data_dir:
        cfg_name = config or 'bench'
        if not all(os.path.isfile(os.path.join(data_dir, f))
                   for f in (FILE_INPUTS, FILE_WEIGHTS, FILE_EXPECTED)):
            raise SystemExit("ERROR: %s does not contain all three golden files" % data_dir)
        ok = run_one(data_dir, cfg_name)
        return 0 if ok else 1

    # No explicit dir: validate every known target.
    all_ok = True
    ran_any = False
    for d, cfg_name in DEFAULT_TARGETS:
        if all(os.path.isfile(os.path.join(d, f))
               for f in (FILE_INPUTS, FILE_WEIGHTS, FILE_EXPECTED)):
            ran_any = True
            all_ok = run_one(d, cfg_name) and all_ok
    if not ran_any:
        raise SystemExit("ERROR: none of the known golden-file directories were found:\n  "
                          + '\n  '.join(d for d, _ in DEFAULT_TARGETS))
    return 0 if all_ok else 1


if __name__ == '__main__':
    sys.exit(main())
