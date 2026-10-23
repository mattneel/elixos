# The inter-core ring on the host (M31)

What the host tests for docs/PROTOCOL.md §11 rely on, and what took time.

## Capacity is a power of two

The first draft of §11 had `capacity = S/2 - 64` with `head`/`tail` wrapping
at 2^32 and byte `p` at `64 + (p mod capacity)`. Unless the capacity divides
2^32 the slot sequence jumps when a counter wraps: with `r = 2^32 mod
capacity != 0`, unread bytes just before the wrap sit at `r-a .. r-1` and new
bytes after it start at 0, so they collide once `a + b > r`. The capacity is
now the largest power of two not above `S/2 - 64`; size the region as
`S = 2 × capacity + 4096`. `spec/ring.vectors` has a `wrap` vector crossing
2^32 and the end of the data area at once.

## Helpers without root

`elixos-link` needs `/dev/net/tun` and `CAP_NET_ADMIN`. The tests run each
helper as

    unshare --user --map-root-user --net sh -c 'echo 1 > .../disable_ipv6 && exec elixos-link ...'

and enter the namespace with `nsenter --target <pid> --user --net
--preserve-credentials` (without `--preserve-credentials`, nsenter's
`setgroups` fails with EPERM). IPv6 is turned off first so the kernel sends no
router solicitations or MLD reports through the TUN device: with it off, a
helper's `tx`/`rx` counters are exactly the test's packets. `unshare` and `sh`
exec, so the port's OS pid is the helper's: SIGUSR1, SIGSTOP and `nsenter`
all target it.

## The BEAM side of the file

The BEAM cannot mmap, so `Elixos.Test.Ring` uses `pread`/`pwrite`, coherent
with the helper's `MAP_SHARED` mapping through the page cache. Small
`pread`/`pwrite` copies are not atomic on x86 (`rep_movs_alternative` copies
fewer than 8 bytes a byte at a time; FSRM uses `rep movsb`), so:

- the Elixir side reads the other side's counter until two reads agree;
- a test writing frames for a running helper SIGSTOPs it (and waits for state
  `T` in `/proc/<pid>/stat`, since `kill` returns before the stop lands)
  around the write. A torn `tail` read by the helper's writer is harmless: it
  can only under-report free space.

On the board both sides use aligned 32-bit atomics and none of this applies.

## Numbers (host, WSL2, 32 threads)

- Zig writer (`elixos-link` fed by python3 UDP) → Elixir reader, 256 KiB
  ring, 1052-byte frames: 54-81 MB/s over the whole run including python3
  start-up. The acceptance test asserts 5 MB/s.
- Two helpers, TCP over the link, 128 KiB rings: 8 MiB in 0.116-0.135 s
  (62-72 MB/s), some hundred `full` drops recovered by TCP.
- Ping across two helpers: 1.1-2.2 ms round trip, the 1 ms idle poll on each
  side dominating.
