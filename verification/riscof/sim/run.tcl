# Xcelium batch entry: quiet the arithmetic-package noise, run, exit.
set severity_pack_assert_off {warning}
set pack_assert_off {std_logic_arith numeric_std}
set rangecnst_severity_level {warning}
set intovf_severity_level {warning}
run
exit
