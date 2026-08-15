#!/bin/sh
# Pin: XcodeGen 2.42.0 (installed version may be newer; still generate).
set -eu
cd "$(dirname "$0")/.."
XCODEGEN_VERSION="${XCODEGEN_VERSION:-2.42.0}"
if ! command -v xcodegen >/dev/null; then
  echo "install xcodegen $XCODEGEN_VERSION" >&2
  exit 1
fi
xcodegen generate --spec project.yml
