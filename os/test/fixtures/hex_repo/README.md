# A static Hex repo, built with Hex's own tooling

The M14 acceptance tests add this repo (with its public key) and install
`hello_pkg` from it. It is a real repository v2 layout, so the tests exercise
the same bytes a self-hosted repo serves.

Built with:

    mix new hello_pkg            # description + licenses, see its mix.exs
    mix hex.build                # -> hello_pkg-0.1.0.tar
    openssl genrsa -out private_key.pem 2048
    cp hello_pkg-0.1.0.tar public/tarballs/
    mix hex.registry build public --name=elixos-test --private-key=private_key.pem

`private_key.pem` is a throwaway key for this fixture only: it exists so the
repo can be rebuilt (new package version) without invalidating the tests. It
signs nothing but the test repository.
