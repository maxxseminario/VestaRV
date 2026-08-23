"""Shared definitions for the GHDL privileged-polarity (PMP) regression.

The core this package elaborates is the one //opensource_sim/isa elaborates
plus ENABLE_TRAPCSR, ENABLE_UMODE and ENABLE_PMP. ENABLE_PMP instantiates
pmp_unit, so the analysis order is VESTA_ISA_RTL with pmp_unit.vhd inserted;
everything else about the list, including why regfile_sbirq.vhd is the only
correct regfile and why the Zfinx FPU pair must be analyzed, is unchanged and
documented at its source.

The list is DERIVED from VESTA_ISA_RTL rather than copied, so the sync guard
//opensource_sim/isa:source_list_sync_test stays the single authority on the
shared sequence and this package cannot drift away from it.
"""

load("//opensource_sim/isa:defs.bzl", "VESTA_ISA_RTL")

# pmp_unit is a leaf: it reads work.constants and nothing else in the tree, so
# it only has to precede the first unit that instantiates it, which is vesta
# itself. It is placed just before controller.vhd to keep the vesta-level
# components grouped as they are in every other list.
_PMP_UNIT = "hdl/common/vesta/pmp_unit.vhd"

_ANCHOR = "hdl/common/vesta/controller.vhd"

def _with_pmp_unit():
    if _ANCHOR not in VESTA_ISA_RTL:
        fail("opensource_sim/pmp/defs.bzl: %s is no longer in VESTA_ISA_RTL, " % _ANCHOR +
             "so pmp_unit.vhd has no insertion point; re-anchor this list.")
    out = []
    for f in VESTA_ISA_RTL:
        if f == _ANCHOR:
            out.append(_PMP_UNIT)
        out.append(f)
    return out

VESTA_PMP_RTL = _with_pmp_unit()
