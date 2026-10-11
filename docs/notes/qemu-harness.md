# The QEMU test harness

## ExUnit's `tmp_dir` paths contain commas

`@moduletag :tmp_dir` gives `tmp/<module>/<test name>-<hash>`, and test names
contain commas ("invalid elixos.* parameters are reported, never fatal").
QEMU's option parser splits `-drive file=<path>,if=virtio,...` on every comma,
so the disk path was truncated and QEMU exited before the guest started:

```
Could not open '.../test-invalid-elixos.--parameters-are-reported': No such file or directory
```

QEMU's escape for a literal comma in an option value is to double it
(verified: `-drive file=/a,,b,if=none` opens `/a,b`; a single comma tries to
open `/a`). `Elixos.Test.QEMU.drive_path/1` doubles them in every `file=` we
pass. Any new QEMU argument that takes a host path needs the same treatment.

## One `boot/2` is one power-on

`-no-reboot` means a guest reboot ends the QEMU process; tests boot again with
the same disk. So "persistence across power cycles" is tested by booting twice,
and a test that wants a reboot must expect the process to exit first.

## Reading the console

`expect/3` matches on ANSI-stripped text and *consumes* up to the match;
`await_log/3` searches everything this boot printed and consumes nothing (shim
log lines can arrive while a test waits for something else). IEx redraws the
prompt with the typed input after Enter, so `iex/3` waits for a prompt numbered
higher than the last one seen.

`iex/3` groups multiline input in parentheses. Without a block, IEx completes
the first top-level statement and prints a new prompt while the remaining
statements are still queued. M18's database ownership probe exposed this:
the returned output contained only the postmaster pid, not the final map.
Grouping keeps bindings in the same session and makes the returned output
cover the whole expression. `send_line/2` and `send_raw/2` remain ungrouped
for tests which intentionally drive interactive input (ADR-054).
