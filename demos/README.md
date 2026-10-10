# The demos

One recording per **visible** milestone — one with a QEMU test — so each can be
watched instead of described. They are scripted, reproducible, and checked
before they count; a demo never shapes the code (a demo that exposes a bug
means a failing test first, then the fix).

| demo | milestone | shows |
|------|-----------|-------|
| `m03-first-boot.mp4` | M3 | PID 1 mounts, plans the factory, persists the attempt and powers off; the second power-on counts another attempt |

## Play, record, check

    asciinema play demos/m03-first-boot.cast   # the source, needs asciinema 3.x
    mpv demos/m03-first-boot.mp4               # or any video player
    make demo M=3                              # re-record, render and check one demo
    make demos                                 # every visible milestone up to MILESTONE

Each demo is three files: `mNN-<slug>.exp` (the script), `mNN-<slug>.keys` (what
it must show), and the recording. `mNN-<slug>.cast` is the source of truth and
is committed too; `mNN-<slug>.mp4` is what people watch.

## The tools

`make check-tools` reports all three. Ubuntu's `asciinema` is 2.x, whose flags
differ, so the 3.x static binaries go in `build/tools`:

    curl -sfL -o build/tools/asciinema https://github.com/asciinema/asciinema/releases/download/v3.2.1/asciinema-x86_64-unknown-linux-gnu
    curl -sfL -o build/tools/agg       https://github.com/asciinema/agg/releases/download/v1.9.0/agg-x86_64-unknown-linux-gnu
    chmod +x build/tools/asciinema build/tools/agg
    sudo apt install expect ffmpeg

## How a demo is made

* `mNN-<slug>.exp` spawns QEMU the way `make qemu` does (`-nographic`, serial
  console on stdio) and drives it by **waiting for real output** — prompts,
  shim lines — never by sleeping for the guest. `spawn -noecho` keeps the
  command line out of the recording; anything typed goes out with `send_human`
  timing, and a pause is taken only after the console has gone quiet.
* `mNN-<slug>.keys` lists the lines the recording must show, in order, and
  `demos/check.sh` asserts them against the cast's **raw output events** —
  `asciinema convert -f txt` renders the *screen*, so a burst of output that
  scrolled past inside one frame (a boot's shim lines, say) can be missing from
  it. The check also requires the recording to end on
  `elixos-shim: shutdown poweroff` and to contain no kernel panic.
* Each demo boots **its own sparse copy** of a freshly made `build/disk.img`,
  never that file: a recording cannot drift the disk, and demos that count
  attempts start from the pristine state. `-no-reboot` ends QEMU when the guest
  reboots, so a demo that needs two power-ons spawns QEMU twice inside one
  recording, on the same copy.
* Recordings are 80 columns wide (what the guest's serial console assumes) and
  use `-i 2`, so long waits and compiles do not eat playback time.
  `demos/render.sh` draws the frames with `agg` and encodes H.264 with `ffmpeg`.
* From M4 on a demo ends with `Elixos.poweroff()`; M12 records the host's ssh
  session instead and keeps QEMU's console out of it.
