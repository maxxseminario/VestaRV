# VestaRV lockstep — Spike RUNTIME environment.  `source` this before any spike run.
#
# Two runtime dependencies that are NOT satisfied by the bare binary:
#   1. libstdc++.so.6 — spike is linked against conda-forge gcc 13's libstdc++,
#      newer than this host's system one.
#   2. `dtc` — spike FORKS the device-tree compiler at startup to build the DTB.
#      Without it every run dies with "Failed to run dtc: No such file or
#      directory / Child dtc_output process failed" BEFORE the --isa string is
#      even parsed (which is why an --isa probe must be read carefully).
#      `--disable-dtb` also avoids it, but the DTB is harmless for our purposes.
#
# Deliberately does NOT put the whole conda env on PATH — only ~/local/bin,
# which holds spike plus a `dtc` symlink. Keeps Cadence/Calibre PATHs intact.
export SPIKE_ENV_PREFIX=$HOME/local
export SPIKE_CONDA_ENV=$HOME/local/mamba/envs/spike13
export LD_LIBRARY_PATH=$SPIKE_ENV_PREFIX/lib:$SPIKE_CONDA_ENV/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=$SPIKE_ENV_PREFIX/bin:$PATH
