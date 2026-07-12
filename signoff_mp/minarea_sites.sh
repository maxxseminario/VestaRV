#!/bin/bash
# PG4: extract metal min-AREA violation sites (the marker box IS the violating
# sliver for area rules) from a Calibre results .db into a sites file for
# innovus/common/tcl/mcu_minarea_patch.tcl. Usage:
#   ./minarea_sites.sh calibre/MCU_MP_signoff/MCU/results/blockdrc.db > sites.txt
# Output lines: "<layer> <x0> <y0> <x1> <y1>" in um (chip coords).
set -u
db=$1
awk '
/^M[0-9]\.A\.[0-9]+$/ { cls=$1; sub(/\..*/,"",cls); next }
/^p / && cls != "" {
    n=$3
    minx=1e18; miny=1e18; maxx=-1e18; maxy=-1e18
    for (i=0; i<n; i++) {
        getline
        x=$1/1000.0; y=$2/1000.0
        if (x<minx) minx=x; if (x>maxx) maxx=x
        if (y<miny) miny=y; if (y>maxy) maxy=y
    }
    printf "%s %.3f %.3f %.3f %.3f\n", cls, minx, miny, maxx, maxy
    next
}
/^[A-Z]/ && $0 !~ /^p / { if ($0 !~ /\.A\./) cls="" }
' "$db"
