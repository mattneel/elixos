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
# "Covered" is strict: one commit between the baseline and the audited revision
# must mention an ADR *and* touch that file, and the audited content must be
# what that commit left behind. Uncommitted changes to protected material are
# therefore always violations — commit the ADR with the test change, as
# AGENTS.md says. Adding new test files or new Zig test blocks is allowed and
# reported as info.
#
# By default the working tree is audited; AUDIT_HEAD audits a revision instead.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

baseline="$(git rev-list --max-parents=0 HEAD)"
head_rev="${AUDIT_HEAD:-}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

violations=0
info=0

fail() {
  violations=$((violations + 1))
  printf 'audit: %s\n' "$1"
}

note() {
  info=$((info + 1))
  printf 'audit: %s\n' "$1"
}

# --- content access -----------------------------------------------------------
#
# Every path is audited at a revision: AUDIT_HEAD if given, otherwise the
# working tree — except that a path whose working-tree content equals HEAD's is
# audited at HEAD, so a committed ADR-carrying change is covered instead of
# looking uncommitted forever. An empty revision means "as yet uncommitted",
# which is never covered.

# revision <path>: the revision to audit that path at (empty: uncommitted work).
revision() {
  if [ -n "$head_rev" ]; then
    printf '%s' "$head_rev"
  elif git diff --quiet HEAD -- "$1"; then
    git rev-parse HEAD
  fi
}

# content <rev> <path>: the bytes under audit (empty revision: the working tree).
content() {
  if [ -n "$1" ]; then git show "$1:$2"; else cat "$2"; fi
}

# exists <rev> <path>: is it there at all?
exists() {
  if [ -n "$1" ]; then git cat-file -e "$1:$2" 2>/dev/null; else [ -e "$2" ]; fi
}

# changed <rev> <path>: do the audited bytes differ from the baseline's?
changed() {
  local rev="$1" path="$2"
  git show "$baseline:$path" > "$tmp/before" 2>/dev/null || : > "$tmp/before"
  content "$rev" "$path" > "$tmp/after" 2>/dev/null || : > "$tmp/after"
  ! cmp -s "$tmp/before" "$tmp/after"
}

# covered <rev> <path>: a commit in range mentions an ADR and this file, and
# the audited bytes are exactly what it left.
covered() {
  local rev="$1"
  [ -n "$rev" ] || return 1

  local path="$2" sha
  while read -r sha; do
    [ -n "$sha" ] || continue
    git show --pretty=format:%B --name-only "$sha" > "$tmp/commit"
    grep -qE 'ADR-[0-9]+' "$tmp/commit" || continue
    grep -qxF "$path" "$tmp/commit" || continue
    # No later commit may have touched the file again (formatting included):
    # the ADR has to describe the bytes we are looking at.
    if git diff --quiet "$sha" "$rev" -- "$path"; then return 0; fi
  done < <(git log --format=%H "$baseline..$rev" -- "$path")

  return 1
}

# --- shared vectors and shipped test files: whole files -----------------------
while IFS= read -r path; do
  rev="$(revision "$path")"

  if ! exists "$rev" "$path"; then
    fail "deleted: $path"
    continue
  fi

  if changed "$rev" "$path"; then
    summary="$(git diff --shortstat "$baseline" ${rev:+"$rev"} -- "$path" | tr -d '\n')"
    if [ -z "$rev" ]; then
      fail "changed in the working tree: $path ($summary); commit it with an ADR"
    else
      covered "$rev" "$path" || fail "changed without an ADR: $path ($summary)"
    fi
  fi
done < <(git ls-tree -r --name-only "$baseline" -- spec os/test |
  grep -E '\.(exs|vectors)$' | grep -E '^(spec/|os/test/[^/]+_test\.exs|os/test/(elixos|integration)/)' | sort)

# --- Zig test blocks: names and bodies, per file ------------------------------
# Prints "name<TAB>sha256" for every `test` block. Literal contents are kept
# verbatim (only indentation is normalised), and braces inside strings and
# comments do not end a block.
zig_blocks() { # zig_blocks <rev> <path>; <rev> empty means the working tree
  python3 - "$1" "$2" 2>/dev/null <<'PY'
import hashlib, subprocess, sys


def blocks(source):
    lines = source.splitlines()
    found = {}
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("test ") or line.startswith("test{"):
            name = line.split('"')[1] if '"' in line else "<unnamed>"
            body, depth, state = [], 0, None
            while i < len(lines):
                body.append(lines[i])
                depth, state = scan(lines[i], depth, state)
                if len(body) > 1 and depth == 0 and state is None:
                    break
                i += 1
            # Indentation is formatting; everything else, including the
            # whitespace inside string literals, is test data.
            text = "\n".join(l.strip() for l in body)
            found[name] = hashlib.sha256(text.encode()).hexdigest()
        i += 1
    return found


def scan(line, depth, state):
    i = 0
    while i < len(line):
        c = line[i]
        if state is None:
            if c == "/" and line[i + 1 : i + 2] == "/":
                break  # a line comment: braces here do not count
            if c == '"':
                state = '"'
            elif c == "'":
                end = line.find("'", i + 1)
                i = len(line) - 1 if end == -1 else end
            elif c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
        elif c == "\\":
            i += 1  # escaped character inside a string
        elif c == '"':
            state = None
        i += 1
    return depth, state


rev, path = sys.argv[1], sys.argv[2]
if rev:
    source = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True, check=True).stdout
else:
    source = open(path).read()

for name, digest in blocks(source).items():
    print(f"{name}\t{digest}")
PY
}

zig_error() { fail "could not read the Zig test blocks of $2 ($1)"; }

for path in $(git ls-tree -r --name-only "$baseline" -- shim/src | grep '\.zig$'); do
  rev="$(revision "$path")"

  if ! exists "$rev" "$path"; then
    fail "deleted: $path"
    continue
  fi

  zig_blocks "$baseline" "$path" > "$tmp/base" || { zig_error "baseline" "$path"; continue; }
  zig_blocks "$rev" "$path" > "$tmp/have" || { zig_error "audited revision" "$path"; continue; }

  while IFS=$'\t' read -r name digest; do
    [ -n "$name" ] || continue
    new="$(awk -F'\t' -v n="$name" '$1 == n {print $2}' "$tmp/have")"
    if [ -z "$new" ]; then
      fail "Zig test removed from $path: $name"
    elif [ "$new" != "$digest" ] && ! covered "$rev" "$path"; then
      fail "Zig test changed without an ADR: $path: $name"
    fi
  done < "$tmp/base"

  while IFS=$'\t' read -r name _; do
    [ -n "$name" ] || continue
    awk -F'\t' -v n="$name" '$1 == n {found=1} END {exit !found}' "$tmp/base" ||
      note "new Zig test in $path: $name"
  done < "$tmp/have"
done

printf 'audit: %d violation(s), %d addition(s) between %s and %s\n' \
  "$violations" "$info" "${baseline:0:7}" "${head_rev:-the working tree}"
[ "$violations" -eq 0 ]
