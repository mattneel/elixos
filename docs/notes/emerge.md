# Emerge on this box (M27)

Measured while adding the GUI's renderer dependency. M27 is in progress:
`Elixos.GUI` is still stubbed, and no framebuffer sink or input helper exists.

## The artifact

`mix deps.compile emerge --force` prints which precompiled NIF it takes:

    Downloading NIF from .../libemerge_skia-v0.4.2-nif-2.15-x86_64-unknown-linux-gnu--raster.so.tar.gz

- With no config: the **gnu** artifact, and `ldd` shows `libgbm`,
  `libxkbcommon` and `libstdc++` - the full Wayland/GPU build.
- With `config :emerge, compiled_backends: []`: the **raster** artifact
  (`--raster.so`, 17,214,224 bytes against 23,272,792), CPU raster with
  embedded FreeType; of the earlier three, only `libstdc++` remains. The gnu
  libc is still linked in, which is fine on the host and not in the image.
- **Backend selection is not target selection.**
  `EmergeSkia.BuildConfig.@default_compiled_backends` answers `[:drm]` when
  `MIX_TARGET` is neither empty nor `host`, or the Nerves/cross environment
  is present; `compiled_backends: []` overrides that with the raster profile.
  This does not select musl. `RustlerPrecompiled` derives architecture/ABI
  from `:erlang.system_info(:system_architecture)` and `TARGET_ARCH`,
  `TARGET_VENDOR`, `TARGET_OS`, `TARGET_ABI` overrides.
- `melange/factory.yaml` sets `MIX_ENV=prod`, but does **not** set
  `MIX_TARGET=elixos`; `Elixos.Package.build/1` sets that only for on-box
  project builds. Do not infer the factory's libc target from `MIX_TARGET`.
- Emerge 0.4.2's precompiled target list includes x86_64 musl, but only
  aarch64 GNU, not aarch64 musl. M27 must verify the selected artifact and
  its library dependencies, pin its checksum and build/package for each
  target. Adding this NIF also ends the assumption that the factory tree
  can be reused across architectures unchanged (ADR-066).

## The API shape

- `EmergeSkia.Native.render_tree_to_pixels_nif/2` and
  `render_tree_to_png_nif/2` take **serialized EMRG bytes** plus raster
  options, not an Elixir tree struct, and render synchronously with no window.
  `EmergeSkia.TreeRenderer` handles the higher-level tree path.
- The planned panel path is `backend: :headless, rendering_api: :raster`
  with `headless: [mode: :binary, target: pid]`: frames arrive as
  `{:emerge_skia_frame, %VideoInterop.Frame{}}`. M27's framebuffer sink still
  needs to be implemented; no code currently writes those frames to `/dev/fb0`.
- 0.4.2 has **no input injection** into that headless renderer; events flow
  out through its input APIs. M27 plans an evdev helper feeding
  `Elixos.GUI.input/1`, with selection and answer validation in Elixir.
  The helper and dialog logic are not implemented yet.
