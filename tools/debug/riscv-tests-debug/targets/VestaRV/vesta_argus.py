"""VestaRV "Argus" (18 harts) as a riscv-tests/debug harness target.

LOCAL FILE (not vendored upstream) -- see ../../VENDORED.md.

This is `vesta_castalia.py` with FOUR differences and no others, which is the
point: the two chips come out of the same generator, so a target file that
diverged in any further respect would be describing a chip that does not exist.

  1. EIGHTEEN harts, not four.  d5_spec 5.3 asks Argus for the harness ATTACH
     plus a smoke subset -- the full table at N=18 is priced, not owed -- and
     the attach is exactly what a hart count gets wrong if it is guessed.

  2. `openocd_config_path = "vesta_argus.cfg"`, which differs from the
     Castalia .cfg in one number (NHARTS) and one IDCODE (0x1A265EEF).

  3. NO NPU, and it does not appear here because no harness test touches it --
     recorded so the absence reads as deliberate.

  4. `timeout_sec = 600`, not Castalia's 120 -- a MEASURED divergence (D5
     validation wave, agent D; R-D5-12).  The examine walks every hart, so
     the attach cost scales with the hart count, and with `timeout_sec = 120`
     the N=18 attach failed at 240.66 s -- the vMustReplyEmpty signature
     AFTER all 18 harts had examined cleanly.  600 matches
     `server_timeout_sec`, whose N=18 need was itself measured
     (d5 implementation report 2.4).

EVERYTHING ELSE IS DELIBERATELY IDENTICAL, including the one that is easy to
get wrong:

  * `ram = 0x00014000`, `ram_size = 0x4000`.  The shared-window map is
     N-parameterized in the CLINT registers, NOT in the bulk RAM: 0x14000 is
     unclaimed at BOTH N (the N=18 bootrom loader rows end at 0x1061F and the
     debug page at 0x1087F, both far below it).  The link script is shared for
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
    bad_address = 0x1FF00
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
