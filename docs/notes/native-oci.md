# Native OCI integration notes

Deployment commands and exercised support are in [TESTING](../TESTING.md#native-oci-images-and-docker-proof). The architecture decision is [ADR-091](../DECISIONS.md#adr-091-native-oci-shares-the-provider-kernel-and-reuses-the-real-os).

## Child Elixir uses the release root

ERTS prepends `/factory/erts/bin:/factory/bin` to PATH. Adding `/usr/local/bin` makes the packaged Elixir CLI discoverable, but its `erl` can still be the release-local launcher with `ROOTDIR=/factory`. Without `/factory/bin/start.boot`, it fails before evaluating any Elixir.

`melange/factory.yaml` links OTP's compiled **clean** boot file as `start.boot` and `start_clean.boot`, alongside `no_dot_erlang.boot`. Do not link the OS application boot file there: a child compiler or test must not start another OS. Do not fix this by mutating the live BEAM's PATH/ROOTDIR. The real child-CLI integration test verifies execution and unchanged VM cwd/environment.

## Read-only seed transfer and initialization

A seed has 0555 directories and 0444/0555 files. Docker's host-side `cp` extraction can set a directory read-only before creating its children, failing for an ordinary host user. The SDK keeps `docker cp ... -` as a tar archive; Docker `ADD --chown=0:0` extracts it inside the build. The final build checks the committed state, selected generation and application before accepting the image. No host extractor or new dependency is needed.

BusyBox `cp -R -P -n source/. existing-destination/` can silently skip the **whole existing destination directory**, returning 0 without copying its children. It is not a valid one-time seed importer. The shim uses ordinary recursive copying only after validating the seed, proving the volume pristine, closing its writable namespace and rechecking it. Allowed initial empty home/PostgreSQL/lost+found directories are disjoint from every allowed seed root.

An initialization marker is durable before copying; `boot.state` publishes last. A partial volume is evidence, not permission to retry copying or erase data. Existing `boot.state` always wins, including state requiring recovery. Image replacement is not an implicit upgrade of a retained application generation.

## Test the real native tools

Cargo link commands exceed 64 arguments. The old bounded compiler bridge failed on a real offline Cargo build despite its environment-echo fixture passing. `toolchain/cc.zig` now borrows every original argument string and allocates only the additional argv pointer vector at startup. ADR-090 replaces the echo fixture with compilation, linking, execution and relative-file effects in an explicit session.

A health worker loads test support from source, not necessarily from compiled Mix ebins. A nested fresh VM must load the support module it calls explicitly; inheriting code paths does not transfer modules compiled only in the parent VM's memory. The container-export scenarios require `test/support/paths.ex` in that child.

PostgreSQL initialization can disappear between procfs operations with either `ENOENT` or `ESRCH`. Both mean the initializer is gone; neither establishes successful startup. The manager must still observe actual SQL readiness.
