#!/usr/bin/env bash
# Fail if any option requested by the Elixos fragment did not survive olddefconfig.
# Usage: check-kernel-config.sh <.config> <fragment>
set -euo pipefail

config="$1"
fragment="$2"
status=0

while IFS= read -r line; do
  case "$line" in
    CONFIG_*=*)
      if ! grep -qxF -- "$line" "$config"; then
        name="${line%%=*}"
        got="$(grep -E "^(# )?${name}[= ]" "$config" || echo 'absent (unknown symbol or unmet dependency)')"
        echo "kernel config: wanted '$line', got '$got'" >&2
        status=1
      fi
      ;;
    "# CONFIG_"*" is not set")
      if ! grep -qxF -- "$line" "$config"; then
        echo "kernel config: wanted '$line'" >&2
        status=1
      fi
      ;;
  esac
done < "$fragment"

if [ "$status" -eq 0 ]; then
  echo "kernel config: all $(grep -cE '^(CONFIG_|# CONFIG_)' "$fragment") fragment options present"
fi
exit "$status"
