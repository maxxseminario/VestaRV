#!/usr/bin/python3.6
"""d5_rbb_client.py -- the D5 bridge's proof client.

Speaks the OpenOCD `remote_bitbang` byte protocol, in the SAME ORDER OpenOCD
emits it (low-phase pin-set carrying TMS/TDI, then 'R', then high-phase
pin-set), so the phase this exercises is the phase OpenOCD will exercise.

Two modes, and the second one is a required bar rather than a convenience:

  IDCODE   (default) -- tap-reset, shift the 32-bit IDCODE, compare.
             A one-phase-late sample returns the whole stream SHIFTED BY ONE
             BIT, which looks structured and reads as an RTL fault, so on a
             mismatch this prints expect>>1 and names the bridge.

  --provoke -- ask for TDO bytes the bridge has been told to withhold
             (D5_NOFLUSH=1) and then block on a reply that can never arrive.
             From the outside this is INDISTINGUISHABLE from a benign
             wait-for-debugger; the only discriminator is `pending_out` inside
             the bridge. d5_spec 2.9 as amended by R-D5-2 requires the
             DEADLOCK verdict to be SEEN TO FIRE, and this is how.

  d5_rbb_client.py <portfile> <expected-idcode-hex>
  d5_rbb_client.py <portfile> --provoke
"""
import socket, sys, time, os

port_file = sys.argv[1]
provoke   = "--provoke" in sys.argv[2:]
expect    = 0 if provoke else int(sys.argv[2], 16)


# wait for the bridge to publish its port
for _ in range(600):
    if os.path.exists(port_file):
        break
    time.sleep(0.5)
else:
    print("CLIENT FATAL: bridge never published a port file"); sys.exit(2)
port = int(open(port_file).read().split()[0])   # file is "<rbb> <ctl>"
print("CLIENT connecting to port %d" % port); sys.stdout.flush()

s = socket.create_connection(("127.0.0.1", port), timeout=600)
s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

s.settimeout(25 if provoke else 600)

buf = bytearray()
nread = 0
def tck(tms, tdi=0, read=False):
    global nread
    buf.append(ord('0') + ((0 << 2) | (tms << 1) | tdi))
    if read:
        buf.append(ord('R')); nread += 1
    buf.append(ord('0') + ((1 << 2) | (tms << 1) | tdi))

if provoke:
    for _ in range(5): tck(1)
    tck(0); tck(1); tck(0); tck(0)
    for _ in range(8): tck(0, 0, read=True)
    s.sendall(bytes(buf))
    print("PROVOKE: sent %d bytes asking for %d replies the bridge will withhold"
          % (len(buf), nread)); sys.stdout.flush()
    try:
        got = s.recv(64)
        print("PROVOKE: UNEXPECTED reply %r -- the withhold did not happen" % got)
        sys.exit(1)
    except socket.timeout:
        print("PROVOKE: blocked and timed out waiting for a reply, as designed.")
        print("PROVOKE: externally this is INDISTINGUISHABLE from a benign idle wait --")
        print("PROVOKE: read the bridge's own RBBSTAT line; it must say verdict=DEADLOCK")
        print("PROVOKE: with pending_out > 0. That counter is the ONLY discriminator.")
    s.close()
    sys.exit(0)

# TLR (5 x TMS=1 is enough from any state), then -> Run-Test/Idle
for _ in range(5): tck(1)
tck(0)
# -> Select-DR -> Capture-DR -> Shift-DR
tck(1); tck(0); tck(0)
# 32 bits of IDCODE.  In Shift-DR TDO presents bit k BEFORE the rising edge,
# so we sample and then clock -- 'R' sits between the two pin-set bytes.
for i in range(32):
    tck(1 if i == 31 else 0, 0, read=True)   # last bit exits to Exit1-DR
tck(1)  # -> Update-DR
tck(0)  # -> Run-Test/Idle
buf.append(ord('Q'))

s.sendall(bytes(buf))
got = b""
while len(got) < nread:
    chunk = s.recv(4096)
    if not chunk:
        break
    got += chunk
s.close()

if len(got) != nread:
    print("CLIENT FATAL: expected %d reply bytes, got %d" % (nread, len(got)))
    sys.exit(2)

# LSB first off the wire
idcode = 0
for i, ch in enumerate(got.decode()):
    if ch == '1':
        idcode |= (1 << i)

shifted = expect >> 1
print("CLIENT idcode_readback=0x%08X expect=0x%08X match=%s"
      % (idcode, expect, idcode == expect))
if idcode != expect:
    print("CLIENT   expect>>1 = 0x%08X  <-- if the readback equals THIS, it is a"
          " BRIDGE PHASE error, not the RTL" % shifted)
    print("CLIENT   raw bits (LSB first): %s" % got.decode())
sys.exit(0 if idcode == expect else 1)
