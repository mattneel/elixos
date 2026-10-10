#!/usr/bin/env bash
# Audit the roadmap's acceptance tests against the scaffold baseline.
#
# The tests in this repo were validated against reference implementations
# (docs/TESTING.md), so they are the contract, not a scratchpad: changing one
# needs an ADR first (AGENTS.md, hard rules). Reviewing that by hand does not
# scale, so this target compares the protected material against the baseline
# commit and fails when something changed without an ADR covering it:
#
#   * spec/*                       shared golden vectors, byte for byte
#   * os/test/**/*_test.exs        every shipped test file, whole file
#   * shim/src/*.zig               the test blocks only (implementations are
#                                  expected to change; the tests are not)
#
# A change is "covered" when a commit between the baseline and HEAD mentions
# both an ADR and the file it changes (the procedure in AGENTS.md: an ADR in
# docs/DECISIONS.md, the test changed in its own commit, the change called out).
# Adding new test files or new test blocks is allowed and reported as info.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

baseline="$(git rev-list --max-parents=0 HEAD)"
# Audit the working tree by default: uncommitted edits are exactly the case
# this is meant to catch. AUDIT_HEAD audits a revision instead.
head_rev="${AUDIT_HEAD:-}"
content() { printf '%s' "${head_rev:+$head_rev:}$1"; }
violations=0
info=0

# Commits whose message claims an ADR and names a file: the escape hatch.
covered() {
  local name="$1"
  git log --format='%B' "$baseline..$head_rev" 2>/dev/null |
    grep -qE 'ADR-[0-9]+' &&
    git log --format='%B' "$baseline..$head_rev" 2>/dev/null | grep -qF "$name"
}

fail() {
  violations=$((violations + 1))
  printf 'audit: %s\n' "$1"
}

note() {
  info=$((info + 1))
  printf 'audit: %s\n' "$1"
}

# --- shared vectors and shipped test files: whole files -----------------------
while IFS= read -r path; do
  if ! git cat-file -e "$(content "$path")" 2>/dev/null && [ ! -e "$path" ]; then
    fail "deleted: $path"
    continue
  fi
  if ! git diff --quiet "$baseline" -- "$path"; then
    covered "$(basename "$path")" ||
      fail "changed without an ADR: $path ($(git diff --shortstat "$baseline" -- "$path" | tr -d '\n'))"
  fi
done < <(git ls-tree -r --name-only "$baseline" -- spec os/test |
  grep -E '\.(exs|vectors)$' | grep -E '^(spec/|os/test/[^/]+_test\.exs|os/test/(elixos|integration)/)' | sort)

# --- Zig test blocks: names and bodies, per file ------------------------------
zig_blocks() { # <spec> where spec is <rev>:<path> or a working-tree path
  python3 - "$1" <<'PY'
import hashlib, subprocess, sys

spec = sys.argv[1]
if ":" in spec and not spec.startswith("/"):
    rev, path = spec.split(":", 1)
    source = subprocess.run(["git", "show", f"{rev}:{path}"],
                            capture_output=True, text=True, check=True).stdout
else:
    source = open(spec).read()

lines = source.splitlines()
blocks = {}
i = 0
while i < len(lines):
    line = lines[i]
    if line.startswith("test ") or line.startswith("test{"):
        name = line.split('"')[1] if '"' in line else "<unnamed>"
        depth = 0
        body = []
        while i < len(lines):
            body.append(lines[i])
            depth += lines[i].count("{") - lines[i].count("}")
            # The first line opens the block; stop when it closes again.
            if depth == 0 and len(body) > 1:
                break
            i += 1
        # Normalise whitespace so formatting alone is not a change.
        text = "\n".join(" ".join(b.split()) for b in body)
        blocks[name] = hashlib.sha256(text.encode()).hexdigest()
    i += 1

for name, digest in blocks.items():
    print(f"{name}\t{digest}")
PY
}

for path in $(git ls-tree -r --name-only "$baseline" -- shim/src | grep '\.zig$'); do
  while IFS=$'\t' read -r name digest; do
    [ -n "$name" ] || continue
    new_digest="$(zig_blocks "$(content "$path")" | awk -F'\t' -v n="$name" '$1 == n {print $2}')"
    if [ -z "$new_digest" ]; then
      fail "Zig test removed from $path: $name"
    elif [ "$new_digest" != "$digest" ]; then
      covered "$(basename "$path")" ||
        fail "Zig test changed without an ADR: $path: $name"
    fi
  done < <(zig_blocks "$baseline:$path")

  # New test blocks are fine, but say so.
  while IFS=$'\t' read -r name _; do
    [ -n "$name" ] || continue
    zig_blocks "$baseline:$path" | awk -F'\t' -v n="$name" '$1 == n {found=1} END {exit !found}' ||
      note "new Zig test in $path: $name"
  done < <(zig_blocks "$(content "$path")")
done

printf 'audit: %d violation(s), %d addition(s) between %s and %s\n' \
  "$violations" "$info" "${baseline:0:7}" "${head_rev:-the working tree}"
[ "$violations" -eq 0 ]
