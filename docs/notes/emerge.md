# Emerge on this box (M27)

M27 remains in progress. The dialogs now show Oh-My-Jido approvals from
`Elixos.Approvals` (ADR-093), not the retired Ask queue. The four request
kinds, framebuffer output, evdev input and console handover are implemented
and exercised on x86_64. ARM64 renderer packaging and the full milestone gate
are not yet complete.

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
- Emerge 0.4.2 ships x86_64 musl but not aarch64 musl. The image's separate
  `elixos-gui-renderer` package pins the x86_64 archive checksum and builds
  ARM64 from the checksum-verified Hex source with its Cargo.lock and pinned
  rust-skia revision. It installs the renderer below
  `/system/gui/<arch>-unknown-linux-musl`, with a private ELF dependency
  closure and relative RUNPATHs (ADR-069).
- Factory builds use `ELIXOS_GUI_PACKAGED=1` and disable Rustler's build-time
  compilation/download path. Each target's Emerge `priv/native` points at its
  packaged renderer; the factory APK is no longer reused across architectures.
  Renderer inputs have their own cache key, independent of kernel and OTP.

## Alpine packaging traps

- Alpine 3.24 calls its Python ELF dependency resolver `lddtreepax`;
  installing `pax-utils` does not supply the old `lddtree` command.
- A DSO has no `PT_INTERP`, and Alpine has no glibc `ld.so.conf`. Give the
  static resolver `LD_LIBRARY_PATH=/lib:/usr/local/lib:/usr/lib` for that
  build step only, then copy the actual resolved closure. Runtime library
  lookup uses the package's relative RUNPATHs, not a VM environment change.
- Skia's bundled ARM64 GN executable is glibc-linked. The first source build
  failed looking for `/lib/ld-linux-aarch64.so.1`; the recipe now installs
  Alpine's native musl GN and sets `SKIA_GN_COMMAND=/usr/bin/gn`.
- Clang's `--target=aarch64-linux-musl` searches a nonexistent
  `aarch64-linux-musl` C++ header directory; Alpine installs the headers under
  `aarch64-alpine-linux-musl`. Set the build-only `CPLUS_INCLUDE_PATH` to
  `/usr/include/c++/$(g++ -dumpfullversion)/$(g++ -dumpmachine)`. A small
  ARM64 C++20 probe reproduced the missing `bits/c++config.h`, then compiled,
  linked and executed successfully with that correction.

## The API shape

- `EmergeSkia.Native.render_tree_to_pixels_nif/2` and
  `render_tree_to_png_nif/2` take **serialized EMRG bytes** plus raster
  options, not an Elixir tree struct, and render synchronously with no window.
  `EmergeSkia.TreeRenderer` handles the higher-level tree path.
- The live panel uses `backend: :headless, rendering_api: :raster` with
  `headless: [mode: :binary, target: pid, pixel_format: :rgba8888]`. Frames
  arrive as `{:emerge_skia_frame, %VideoInterop.Frame{}}`; `Elixos.GUI`
  validates them and feeds the framebuffer helper with presentation
  acknowledgements and bounded backpressure.
- For an Elixir tree, use `EmergeSkia.TreeRenderer.render_to_pixels/3`.
  The top-level `render_to_pixels` path expects the lower-level serialized
  form. Runtime patches use `TreeRenderer.patch_tree_runtime/3`; that
  function is not exported by the top-level `EmergeSkia` module.
- 0.4.2 has no input injection into the headless renderer. The evdev helper
  feeds Elixir's dialog state directly; Arrow/Tab navigation, grapheme
  editing, multi-choice toggles, pointer hit testing and answer validation
  are independent of Emerge's outbound input APIs.
