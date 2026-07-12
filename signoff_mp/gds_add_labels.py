#!/usr/bin/env python3
"""PG4: inject TEXT labels into a GDS top structure (in place).

Usage: gds_add_labels.py <gds> <top_struct> <labels_file>
Labels file lines: "<gds_layer> <x_um> <y_um> <text>"

WHY: the switched rail VDD_SW is 471 separate layout pieces joined only
through the HEADBUF switches — LVS sees 471 nets vs one schematic net and
every cell on an unmatched piece mismatches (PG3's "ClkGate/tie islands on
VDD_SW" class). The PVS deck runs VIRTUAL_CONNECT -COLON YES and attaches
metal text layers (M1 text = 131), so one "VDD_SW:" text per piece unifies
them by name. Label points come from the piece centers
(innovus: dump_vddsw_labels recipe / hart_tile_lvs_netlist.tcl).
"""
import struct, sys

def records(data):
    i = 0
    while i < len(data):
        (ln, rt) = struct.unpack(">HH", data[i:i+4])
        if ln == 0:
            break
        yield i, ln, rt
        i += ln

def text_element(layer, x_um, y_um, s):
    def rec(rt, payload=b""):
        return struct.pack(">HH", 4 + len(payload), rt) + payload
    if len(s) % 2:
        s += "\0"
    return (rec(0x0C00)                                   # TEXT
            + rec(0x0D02, struct.pack(">h", layer))       # LAYER
            + rec(0x1602, struct.pack(">h", 0))           # TEXTTYPE
            + rec(0x1003, struct.pack(">ii", int(round(x_um*1000)), int(round(y_um*1000))))  # XY
            + rec(0x1906, s.encode())                     # STRING
            + rec(0x1100))                                # ENDEL

def main():
    gds, top, labfile = sys.argv[1], sys.argv[2], sys.argv[3]
    data = open(gds, "rb").read()
    labels = []
    for ln in open(labfile):
        parts = ln.split()
        if len(parts) >= 4:
            labels.append((int(parts[0]), float(parts[1]), float(parts[2]), parts[3]))
    # find top struct's ENDSTR
    cur = None
    endstr_at = None
    for i, ln, rt in records(data):
        if rt == 0x0606:
            cur = data[i+4:i+ln].rstrip(b"\x00").decode()
        elif rt == 0x0700 and cur == top:   # ENDSTR
            endstr_at = i
            break
    if endstr_at is None:
        sys.exit(f"top struct {top} not found in {gds}")
    blob = b"".join(text_element(l, x, y, s) for l, x, y, s in labels)
    out = data[:endstr_at] + blob + data[endstr_at:]
    open(gds, "wb").write(out)
    print(f"injected {len(labels)} TEXT labels into {top} of {gds}")

if __name__ == "__main__":
    main()
