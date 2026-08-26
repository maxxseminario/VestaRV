define_metric -name rail.ir.worstiv.net:<net> -description "The worst instance voltage in the report file" -cmp lessBetter
set_metric -name rail.ir.static.min.net:VSS -value "0 V"
set_metric -name rail.ir.static.max.net:VSS -value "0 V"
set_metric -name rail.ir.static.avg.net:VSS -value "0 V"
set_metric -name rail.ir.static.violations.net:VSS -value 0
set_metric -name rail.thresholdvoltage.net:VSS -value "0.027 V"
set_metric -name rail.referencevoltage.net:VSS -value "0 V"
set_metric -name rail.worstircycle.net:VSS -value "0.000 S"
set_metric -name rail.rj.min.net:VSS -value NA
set_metric -name rail.rj.max.net:VSS -value NA
set_metric -name rail.rj.avg.net:VSS -value NA
set_metric -name rail.rj.violations.net:VSS -value 0
