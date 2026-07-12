#!/bin/bash
# One-shot: create the pmk (power-management kit) OA layout library from the
# ARM kit GDS. Needed because ~/lib/.../tsmc65_sc_adv10_pmk is an EMPTY stub
# (Myshkin never used pmk cells; Castalia's power gating does: HEADBUF*,
# GPGBUF*, FILLBIAS*, pmk fillers/taps/ties).
set -u
cd "$(dirname "$0")"

PMK_GDS=/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10-pmk/gds2/tsmc65_hvt_sc_adv10_pmk.gds2

strmin \
    -library tsmc65_sc_adv10_pmk \
    -strmFile "$PMK_GDS" \
    -layerMap "strmin/gds2cds.map" \
    -techRefs "tsmcN65" \
    -writeMode overwrite \
    -scaleTextHeight 0.025 \
    -noWarn "75 84 107 174 316 363 81000 80043" \
    -logfile "strmin/tsmc65_sc_adv10_pmk.strmin.log" > /dev/null

sed -n -e '/INFO (XSTRM-234):/,$p' "strmin/tsmc65_sc_adv10_pmk.strmin.log" | head -20
ls tsmc65_sc_adv10_pmk | wc -l
