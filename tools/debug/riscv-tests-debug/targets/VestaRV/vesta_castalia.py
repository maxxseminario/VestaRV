"""VestaRV: Castalia, 4 harts, as a riscv-tests/debug harness target.

Local file, not vendored upstream; see ../../VENDORED.md.

The "simulator" is not a process this file launches and talks to directly: it is an
Xcelium simulation of the RTL, with the OpenOCD remote_bitbang server running INSIDE
xmsim's own Tcl interpreter. So create() starts the sim through the tree's own runner and
waits for the bridge to publish its port, the way testlib.Spike waits for spike's port line.

Each capability declared below is a structural fact about the chip, not a convenience.
instruction_hardware_breakpoint_count is 0 because VestaRV has no triggers at all, which
is what makes the hardware-breakpoint family report NOT APPLICABLE instead of failing.
support_memory_sampling is False because sampling needs System Bus Access, which this chip
has none of by design: sbcs reads all-zeros and the access-memory abstract command answers
NOT_SUPPORTED, so every memory access goes through the program buffer. support_manual_hwbp,
support_hasel, support_unavailable_control, implements_custom_test,
implements_page_virtual_memory and test_semihosting are all False for the same kind of
reason: no triggers to write by hand, dmcontrol.hasel READS BACK 0, which is the real
discriminator for whether OpenOCD ever touches those registers, no DMCUSTOM, M-mode only
so no page-based virtual memory, and no semihosting.

timeout_sec = 120 IS NOT A ROUND NUMBER AND NOT OPTIONAL. The harness default is 2 s and
is what it passes as gdb's remotetimeout, while a 256-byte memory read through the program
buffer over this transport measures about 3.8 s, so the default fails on a correct chip.
The .cfg's own command timeout is the other half of the same requirement: set both or
neither.
"""

import os
import re
import subprocess
import tempfile
import time

import targets
import testlib


# Where the tree's own debug runner lives, derived from this file rather than
# from the cwd, so the target can be passed to gdbserver.py by absolute path.
_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.abspath(os.path.join(_HERE, "..", "..", "..", "..", ".."))
_RUNNER_DIR = os.path.join(_REPO, "xcelium", "riscv_test", "behavioral_mp")


class VestaBridge:
    """Starts the Xcelium sim whose Tcl interpreter is the rbb server.

    Deliberately shaped like testlib.Spike from the outside: it exposes
    `.lognames`, sets REMOTE_BITBANG_HOST/PORT, and cleans up in __del__.
    """

    def __init__(self, verify_dir, image, harness="dbg_sessrun.tcl",
                 profile="d5sess", extra_env=None, timeout=1800):
        self.process = None
        self.logfile = tempfile.NamedTemporaryFile(prefix="vestarv-bridge-",
                                                   suffix=".log")
        self.lognames = [self.logfile.name]
        self.portfile = tempfile.NamedTemporaryFile(prefix="vestarv-port-",
                                                    suffix=".txt", delete=False)
        self.portfile.close()
        os.unlink(self.portfile.name)

        env = dict(os.environ)
        env["D5_PORTFILE"] = self.portfile.name
        env["D5_PROFILE"] = profile
        if extra_env:
            env.update(extra_env)

        cmd = ["./xrun_dbg_verify.sh", verify_dir, image, harness]
        self.logfile.write(("+ " + " ".join(cmd) + "\n").encode())
        self.logfile.flush()
        # pylint: disable-next=consider-using-with
        self.process = subprocess.Popen(cmd, cwd=_RUNNER_DIR, env=env,
                                        stdin=subprocess.PIPE,
                                        stdout=self.logfile,
                                        stderr=self.logfile)

        # Wait for the bridge to publish "<rbb_port> <ctl_port>".  Elaboration
        # of the debug-ON tree dominates this; it is minutes, not seconds, so
        # the wait is generous AND it checks the child is still alive rather
        # than sleeping blindly into a crash.
        self.port = None
        self.ctl_port = None
        deadline = time.time() + timeout
        while time.time() < deadline:
            if os.path.exists(self.portfile.name):
                fields = open(self.portfile.name).read().split()
                if len(fields) >= 2:
                    self.port, self.ctl_port = int(fields[0]), int(fields[1])
                    break
            if self.process.poll() is not None:
                raise testlib.TestLibError(
                    "the VestaRV bridge sim exited before it published a port; "
                    "see %s" % self.logfile.name)
            time.sleep(0.5)
        if self.port is None:
            raise testlib.TestLibError(
                "the VestaRV bridge never published a port within %ds; see %s"
                % (timeout, self.logfile.name))

        os.environ["REMOTE_BITBANG_HOST"] = "localhost"
        os.environ["REMOTE_BITBANG_PORT"] = str(self.port)
        os.environ["VESTA_CTL_PORT"] = str(self.ctl_port)

    def __del__(self):
        if self.process:
            try:
                self.process.kill()
                self.process.wait()
            except OSError:
                pass

    def wait(self, *args, **kwargs):
        return self.process.wait(*args, **kwargs)


class vesta_castalia_hart(targets.Hart):
    xlen = 32
    # M-mode RV32IMAC, no F/D/V.  Left as None so ExamineTarget autodetects it
    # from the chip rather than from an assertion in this file -- the toolchain
    # probe lost a measurement to a hand-declared misa that disagreed with the
    # machine, and recorded it as its own miss.
    misa = None
    # Shared bulk RAM, above everything the session image and the DM claim.
    ram = 0x00014000
    ram_size = 0x4000
    # There is NO faulting read-address class on this fabric: every in-window
    # address hits a slave, and >=0x20000 answers without stalling (zeros from
    # a tile; flash bytes via hart 0's XIP decode).  The previous value
    # 0x1FF00 claimed a hole that is actually shared bulk RAM bank 3
    # (0x10000-0x1FFFF) -- the T5 "failure" was a SUCCESSFUL read of a valid
    # zero-filled word.  The only consumers, MemTest*Invalid, are structurally
    # excluded (R-D5-12); the field is kept because the harness requires it,
    # pointed at the least-claimed address there is.
    bad_address = 0x20000
    instruction_hardware_breakpoint_count = 0
    reset_vectors = [0x0]
    link_script_path = "vesta_castalia.lds"


class vesta_castalia(targets.Target):
    harts = [vesta_castalia_hart(), vesta_castalia_hart(),
             vesta_castalia_hart(), vesta_castalia_hart()]
    openocd_config_path = "vesta_castalia.cfg"

    # See the module docstring: this is HALF of the timeout requirement.
    timeout_sec = 120
    server_timeout_sec = 300

    support_memory_sampling = False       # needs SBA; VestaRV has none
    support_manual_hwbp = False           # no triggers until D6
    support_hasel = False                 # dmcontrol.hasel reads back 0
    support_unavailable_control = False   # no DMCUSTOM
    implements_custom_test = False        # Spike's custom debug registers
    implements_page_virtual_memory = False
    test_semihosting = False
    invalid_memory_returns_zero = False

    def create(self):
        verify_dir = os.environ.get("VESTA_VERIFY_DIR", "verify_castaliadebug")
        image = os.environ.get("VESTA_IMAGE",
                               "../kba/xrv32ua-p-d5sessmp.rcf")
        return VestaBridge(verify_dir, image,
                           harness=os.environ.get("VESTA_HARNESS",
                                                  "dbg_sessrun.tcl"))
