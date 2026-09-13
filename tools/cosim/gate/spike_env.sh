# VestaRV: Spike runtime environment for the lockstep flow. Source before any
# spike run.
# The bare binary needs two things the host does not supply: conda-forge gcc 13's
# libstdc++.so.6, and `dtc`, which spike forks at startup to build the DTB. Without
# dtc every run dies on "Failed to run dtc" before the --isa string is parsed, so
# an --isa probe reports nothing useful. Only ~/local/bin goes on PATH (spike plus
# a dtc symlink), not the whole conda env, so Cadence and Calibre PATHs survive.
export SPIKE_ENV_PREFIX=$HOME/local
export SPIKE_CONDA_ENV=$HOME/local/mamba/envs/spike13
export LD_LIBRARY_PATH=$SPIKE_ENV_PREFIX/lib:$SPIKE_CONDA_ENV/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export PATH=$SPIKE_ENV_PREFIX/bin:$PATH
