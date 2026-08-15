#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
if [ -x "$ROOT/.build/debug/candela-cli" ]; then
  exec "$ROOT/.build/debug/candela-cli" "$@"
fi
exec swift run --package-path "$ROOT" candela-cli -- "$@"
