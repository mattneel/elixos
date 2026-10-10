# The official Elixos Hex repository

`elixos` is the repository every Elixos box trusts out of the box (ADR-019):
the factory image ships its public key, and `/priv/hex/repos.exs` names it, so
`Elixos.Package.install(:name)` works without anyone adding a repository first.

It is a **static Hex repository** served by **GitHub Pages**:

    https://mattneel.github.io/elixos

`.github/workflows/hex-repo.yml` builds and publishes it on every change under
`hex/`: package tarballs first (`build-packages.sh`), then the signed registry
(`build-repo.sh`), then the Pages deployment. Nothing else may write to it.

## Publishing a package

    hex/packages/<project>/     a Mix project; its mix.exs needs the fields
                                `mix hex.build` asks for (description, licenses,
                                links) — build it with `mix hex.build`
    hex/prebuilt/*.tar          tarballs built elsewhere, copied as they are

Commit the project (or drop the tarball in) and push to `master`: CI rebuilds
the registry, and the new version is installable at the next `mix deps.get` or
`Elixos.Package.install/1`.

Building locally, exactly as CI does:

    mix local.hex --force
    ./hex/build-packages.sh
    ./hex/build-repo.sh                 # uses build/keys/elixos-private.pem
    # a local mirror is now in build/hex-repo/public

## The signing key

`hex/keys/elixos.pub` is the repository's public key (**RSA PUBLIC KEY**, PEM,
the format Hex serves as `public_key`), committed on purpose: the factory ships
this exact file, and `build-repo.sh` refuses to publish a registry signed by
anything else, because every Elixos box would refuse it.

The private half is **not** in this repository. It lives in

  * the GitHub Actions secret `ELIXOS_HEX_PRIVATE_KEY` (CI signs with it), and
  * whoever holds the backup of it, off the machine.

Losing it means the repository can never be updated again for the machines that
shipped with this public key: they would refuse the new registry. Keep a backup.

    # verify a repository's key by fingerprint (sha256 of the DER):
    openssl rsa -pubin -in hex/keys/elixos.pub -outform DER | sha256sum
    # 43164f77e5381b27a2673c022107250dcf15c49c61bdf66eac0a8c46c0191922

## One-time setup on GitHub

1. **Settings → Pages → Source: GitHub Actions.**
2. **Settings → Secrets and variables → Actions → New repository secret:**
   `ELIXOS_HEX_PRIVATE_KEY`, the contents of the private key file.
3. Push a change under `hex/` (or run the workflow manually) and check the
   deployment URL serves `names`, `versions` and `public_key`.
