# Debug tests

Vendored riscv-tests `debug/` suite ([`VENDORED.md`](VENDORED.md)): end-to-end debug tests
through gdb and OpenOCD. Needs `riscv64-unknown-elf-gcc`/`-gdb` (override with
`RISCV_TESTS_DEBUG_GCC`/`_GDB`), `spike`, `openocd` and Python `pexpect` on `PATH`.

```sh
make                                          # smoke test against Spike
make all                                      # pylint + all Spike configurations
./gdbserver.py targets/<file>.py [NAME]       # one target; NAME filters tests by substring
```

`--sim_cmd`, `--server_cmd` and `--gdb` override the Spike, OpenOCD and gdb commands.
Per-test logs: `logs/`. Target variables: `Targets` class in `targets.py`.
