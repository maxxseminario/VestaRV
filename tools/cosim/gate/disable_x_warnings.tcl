# VestaRV: demote the simulator's arithmetic-package, range and overflow errors
# to warnings so an X-propagating gate netlist runs to completion.
set severity_pack_assert_off {warning}
set pack_assert_off {std_logic_arith numeric_std}
puts "Arithmetic package warnings disabled"
set rangecnst_severity_level {warning}
puts "Range constraint errors converted to warnings"
set intovf_severity_level {warning}
puts "Integer Overflow errors converted to warnings"