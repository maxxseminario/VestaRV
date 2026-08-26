#!/bin/bash
cd ../../ic && \
strmin/strmin.sh MCU_innovus_drc MCU "../innovus/myshkin/out/MCU.gds2" overwrite > /dev/null && \
calibre/silent_drc MCU_innovus_drc MCU celldrc -turbo > /dev/null