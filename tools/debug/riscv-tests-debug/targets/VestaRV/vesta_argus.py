"""VestaRV: Argus, 18 harts, as a riscv-tests/debug harness target.

Local file, not vendored upstream; see ../../VENDORED.md.

It is vesta_castalia.py with four differences and no others, which is the point: the two
chips come out of the same generator, so any further divergence would describe a chip that
does not exist. Eighteen harts rather than four, and the hart count is exactly what an
attach gets wrong if it is guessed. A different openocd_config_path, whose .cfg differs
from Castalia's in one hart count and one IDCODE. No NPU, recorded here so the absence
reads as deliberate rather than forgotten. And timeout_sec 600 rather than 120, a MEASURED
divergence: the examine walks every hart, so the attach cost scales with the hart count and
at 120 the N=18 attach failed after 240 s.

EVERYTHING ELSE IS DELIBERATELY IDENTICAL, including the one that is easy to get wrong:
ram = 0x14000 with ram_size = 0x4000. The shared-window map is N-parameterised in the CLINT
registers, NOT in the bulk RAM, and 0x14000 is unclaimed at both hart counts, since the
N=18 loader rows and the debug page both end far below it. The link script is shared for
the same reason.
"""

import os

import targets

# The Castalia module owns the bridge class; importing it here keeps ONE
# implementation of "start the sim and wait for its port" rather than two that
# can drift.
from vesta_castalia import VestaBridge


class vesta_argus_hart(targets.Hart):
    xlen = 32
    misa = None                      # autodetected from the chip, not asserted
    ram = 0x00014000
    ram_size = 0x4000
    bad_address = 0x20000        # no address faults; see vesta_castalia.py
    instruction_hardware_breakpoint_count = 0
    reset_vectors = [0x0]
    link_script_path = "vesta_castalia.lds"


class vesta_argus(targets.Target):
    harts = [vesta_argus_hart() for _ in range(18)]
    openocd_config_path = "vesta_argus.cfg"

    timeout_sec = 600                # measured: 120 fails the N=18 attach
    server_timeout_sec = 600         # the N=18 examine is 4.5x Castalia's

    support_memory_sampling = False       # needs SBA; VestaRV has none
    support_manual_hwbp = False           # no triggers until D6
    support_hasel = False                 # dmcontrol.hasel reads back 0
    support_unavailable_control = False   # no DMCUSTOM
    implements_custom_test = False
    implements_page_virtual_memory = False
    test_semihosting = False
    invalid_memory_returns_zero = False

    def create(self):
        verify_dir = os.environ.get("VESTA_VERIFY_DIR", "verify_argusdebug")
        image = os.environ.get("VESTA_IMAGE",
                               "../kf0/xrv32ua-p-d5sessmp.rcf")
        return VestaBridge(verify_dir, image,
                           harness=os.environ.get("VESTA_HARNESS",
                                                  "dbg_sessrun.tcl"))
