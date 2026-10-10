#!/usr/bin/env bash
# Fail if any option requested by an Elixos fragment did not survive olddefconfig.
# Usage: check-kernel-config.sh <.config> <fragment>...
#
# Since M16 the fragment is per architecture: the common fragment plus one arch
# fragment (ADR-041) - pass both, and the count below covers both.
set -euo pipefail

config="$1"
shift
status=0
count=0

for fragment in "$@"; do
  while IFS= read -r line; do
    case "$line" in
      CONFIG_*=*)
        count=$((count + 1))
        if ! grep -qxF -- "$line" "$config"; then
          name="${line%%=*}"
          got="$(grep -E "^(# )?${name}[= ]" "$config" || echo 'absent (unknown symbol or unmet dependency)')"
          echo "kernel config: wanted '$line' (in ${fragment##*/}), got '$got'" >&2
          status=1
        fi
        ;;
      "# CONFIG_"*" is not set")
        count=$((count + 1))
        if ! grep -qxF -- "$line" "$config"; then
          echo "kernel config: wanted '$line' (in ${fragment##*/})" >&2
          status=1
        fi
        ;;
    esac
  done < "$fragment"
done

if [ "$status" -eq 0 ]; then
  echo "kernel config: all $count fragment options present"
fi
exit "$status"
