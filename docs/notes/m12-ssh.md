# SSH into the BEAM (M12)

What OTP 29 actually asks of a daemon whose host key we generate ourselves,
and of a shell fun. All of it verified against the pinned OTP source in
`build/toolchain/otp_src_29.1.1/lib/ssh/src`.

## Host keys

- `:crypto.generate_key(:eddsa, :ed25519)` returns `{public, private}` -
  public first. For EdDSA the private key is the 32-byte seed.
- `ssh_file` reads a host key at `SYSDIR/ssh_host_ed25519_key` through
  `public_key:pem_entry_decode/1`, so a classic PEM works:
  `:public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, key)])`
  where `key` is the `ECPrivateKey` record. That record has **five** fields
  (`version, privateKey, parameters, publicKey, attributes`) - the fourth
  field is the *public* key; leave `attributes` as `:asn1_NOVALUE` and set
  `parameters` to `{:namedCurve, {1, 3, 101, 112}}` (`id-Ed25519`).
- `ssh_file:encode(Key, :openssh_key_v1)` looks tempting but does not round
  trip through `ssh_file:decode/2`; the PEM above does, and
  `ssh_file.host_key/2` returns it.
- Signing is `public_key:sign(Data, :undefined, Key)` for ed25519
  (`sha('ssh-ed25519')` is `undefined`).
- Getting the public/private pair swapped still produces valid-looking
  signatures, but every kex fails with `bad_signature` on the client: the
  announced public key is the seed and the "private" key is the public one.

## The shell fun

- The `shell` daemon option wants `{M,F,A}` or a fun of arity 1 or 2.
  `ssh_cli` passes the user and **`{address, port}`** - not a bare address.
  `group:start_shell_fun/1` calls it and requires a **pid** back; that pid is
  linked and gets the group process as its group leader, which is what makes
  the channel its terminal. A process started with `spawn_link` from inside
  the fun inherits that leader, so `IEx.Server.run/1` prints to the channel
  with no extra plumbing.
- Password auth needs a `pwdfun`; with none configured `ssh_options` installs
  a fake checker, so passwords are refused by default.
- `user_dir` (charlist) is where `authorized_keys` is looked up:
  `USERDIR/authorized_keys`, then `authorized_keys2`.
- `:ssh.daemon/2` returns the system supervisor for the address; `:ssh.stop_daemon/1`
  takes it back down.
