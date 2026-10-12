# Emerge on this box (M27)

Measured while adding the GUI's renderer, so the next session does not
re-derive it.

## The artifact

`mix deps.compile emerge --force` prints which precompiled NIF it takes:

    Downloading NIF from .../libemerge_skia-v0.4.2-nif-2.15-x86_64-unknown-linux-gnu--raster.so.tar.gz

- With no config: the **gnu** artifact, and `ldd` shows `libgbm`,
  `libxkbcommon` and `libstdc++` - the full Wayland/GPU build.
- With `config :emerge, compiled_backends: []`: the **raster** artifact
  (`--raster.so`, 17,214,224 bytes against 23,272,792), CPU raster with
  embedded FreeType; of the earlier three, only `libstdc++` remains. The gnu
  libc is still linked in, which is fine on the host and not in the image.
- The *target* (gnu against musl) is chosen by `EmergeSkia.BuildConfig`:
  `@default_compiled_backends` answers `[:drm]` when `MIX_TARGET` is neither
  empty nor `host`, or `NERVES_SDK_SYSROOT`/`TARGET_ARCH`/`TARGET_OS` is set, or
  `CC` looks like a cross compiler; a plain host build gets `[:wayland]`. The
  factory build runs Mix with `MIX_TARGET=elixos` (`Elixos.Package.build/1`, and
  the melange recipe), so the image's build is on the Nerves path; the artifact
  name in that build's log is what settles which libc it fetched, and it is the
  name to pin.

## The API shape

- Trees render synchronously, with no window: the entry points live in
  `EmergeSkia` (`tree_renderer.ex`, `native.ex`, `headless_prime_session.ex`).
  The renderer takes the tree as **serialized bytes** plus raster options and an
  asset config - not an Elixir struct - which is why the dialog builds its tree
  through Emerge's engine and then asks for pixels.
- For the panel: `backend: :headless, rendering_api: :raster` with
  `headless: [mode: :binary, target: pid]` sends `{:emerge_skia_frame,
  %VideoInterop.Frame{}}` to a local pid; our sink writes each frame to
  `/dev/fb0` itself (no Mesa, no GPU).
- 0.4.2 has **no input injection** - events only flow out (`set_input_target/2`,
  `set_input_mask/2`, `Emerge.handle_input/2`) and a headless raster renderer has
  no input device at all. M27's dialog therefore takes its input from our own
  evdev helper, and the selection logic (which row, which key answers) is Elixir.
