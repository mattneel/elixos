# The demos

One recording per **visible** milestone — one with a QEMU test — so each can be
watched instead of described. They are scripted, reproducible, and checked
before they count; a demo never shapes the code (a demo that exposes a bug
means a failing test first, then the fix).

| demo | milestone | shows |
|------|-----------|-------|
| `m03-first-boot.mp4` | M3 | PID 1 mounts, plans the factory, persists the attempt and powers off; the second power-on counts another attempt |
| `m04-boot-to-iex.mp4` | M4 | the shim's lines and the banner to the first prompt |
| `m05-beam-supervision.mp4` | M5 | the BEAM exits; the shim plans another attempt and boots it again |
| `m06-live-image.mp4` | M6 | a module defined at the prompt is there after a power cycle |
| `m07-recovery.mp4` | M7 | a boot that raises comes up in rescue instead of looping |
| `m08-shim-self-recovery.mp4` | M8 | the shim comes back without losing the running BEAM |
| `m09-repl-login.mp4` | M9 | a session's directory moves, the VM's never does, and a second shell is the same world |
| `m11-self-hosting.mp4` | M11 | the toolchain is on the box, a Mix project builds in a child ERTS, its service runs in this VM |
| `m12-ssh.mp4` | M12 | a key in `authorized_keys` logs the host into the user's REPL, the same VM as the console |
| `m13-uefi.mp4` | M13 | firmware boots the EFI-stub kernel from the ESP, under EFI, with the built-in command line |
| `m14-packages.mp4` | M14 | the official repository is trusted out of the box; adding one with its key is consent; install by name |
| `m15-jido-agents.mp4` | M15 | jido is part of the OS, an agent is defined and started at the prompt, an action talks to a stub model, and a power cycle keeps its state |
| `m16-aarch64.mp4` | M16 | **ARM64:** the guest shows its aarch64 ERTS target, boots on qemu-system-aarch64, and keeps a module across a power cycle |
| `m17-escape-hatch.mp4` | M17 | uid 1000, refused recovery-file writes and an unknown helper, then a saved module survives a power cycle and its generation is sealed |
| `m18-postgres.mp4` | M18 | PostgreSQL 17 answers from the prompt as uid 70, both extensions load from the read-only `/system` image, and a row survives the power cycle with a clean shutdown |
| `m19-oban.mp4` | M19 | a worker defined at the prompt runs a job now, and a job scheduled for later survives a power cycle and runs on the next boot |
| `m20-ask.mp4` | M20 | an agent asks the human through the Jido action, the console shows the notice line, the prompt answers, and the answer returns into the agent's state |
| `m25-browser.mp4` | M25 | the headless browser ships in the read-only image, comes up with the system, and answers the four verbs - navigate, evaluate, screenshot - over jido_browser and a CDP connection from Hex |

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
* Each demo boots **its own sparse copy** of its architecture's freshly made
  disk: `build/disk.img` for x86_64, `build/aarch64/disk.img` for aarch64.
  A recording cannot drift the pristine disk, and demos that count attempts
  start from the pristine state. `-no-reboot` ends QEMU when the guest reboots,
  so a demo that needs two power-ons spawns QEMU twice inside one recording,
  on the same copy.
* Recordings are 120x36: the guest's serial console assumes 80 columns, but
  the Erlang banner, kernel lines and `[notice]` errors are longer than that
  and were being cut off in the video. They use `-i 2`, so long waits and
  compiles do not eat playback time.
  `demos/render.sh` draws the frames with `agg` and encodes H.264 with `ffmpeg`.
* From M4 on a demo ends with `Elixos.poweroff()`; M12 records the host's ssh
  session instead and keeps QEMU's console out of it.

## Traps

* A pasted multi-line expression needs **its own Return**: `send {...}` types
  the text, and `send "\r"` completes it. Without the Return the guest's
  reader keeps buffering, the *next* command is appended to the same
  expression, and it fails to parse at a line far past the paste - the M15
  demo wasted an hour on this before it was recorded.
* Expect on what this Elixir *prints*, not on what you remember: 1.18+ inspects
  a charlist as `~c"..."`, so `Application.spec(:jido, :vsn)` shows
  `~c"2.4.0"` and an `expect "'2.4.0'"` waits forever.
* `set timeout 900` turns one wrong `expect` into fifteen minutes per step, so
  a wedged demo looks like a slow one. Pace on `expect -re {iex\([0-9]+\)> }`
  or on content that follows from the command, never on a hard-coded prompt
  number: the numbers move when the paste count changes.
* Before recording a demo that defines modules, extract the block and parse it
  on the host (`Code.string_to_quoted/1` on the braced literal); a syntax error
  found here costs seconds, the same error in a recording costs a boot.
