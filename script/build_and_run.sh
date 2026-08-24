#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Candela"
BUNDLE_ID="app.candela.macos"
CONFIGURATION="${CONFIGURATION:-Debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$ROOT_DIR/DerivedData}"
APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"
STATUS_LOG="$HOME/Library/Logs/Candela/status-item.txt"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

if [[ ! -d "$ROOT_DIR/Candela.xcodeproj" || "${REGENERATE_PROJECT:-0}" == "1" ]]; then
  xcodegen generate --spec "$ROOT_DIR/project.yml"
fi
xcodebuild \
  -project "$ROOT_DIR/Candela.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  ONLY_ACTIVE_ARCH=YES \
  build

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

wait_for_process() {
  for _ in {1..10}; do
    if pgrep -x "$APP_NAME" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "$APP_NAME did not launch" >&2
  return 1
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    open_app
    wait_for_process
    exec lldb -p "$(pgrep -x "$APP_NAME" | head -1)"
    ;;
  --logs|logs)
    open_app
    wait_for_process
    exec /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    wait_for_process
    exec /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    start_line=0
    if [[ -f "$STATUS_LOG" ]]; then
      start_line="$(wc -l < "$STATUS_LOG" | tr -d ' ')"
    fi
    open_app
    wait_for_process
    for _ in {1..12}; do
      if [[ -f "$STATUS_LOG" ]] && \
         tail -n "+$((start_line + 1))" "$STATUS_LOG" | grep -q 'onBar=true'; then
        echo "$APP_NAME launched and its status item is on the menu bar."
        exit 0
      fi
      sleep 1
    done
    echo "$APP_NAME launched, but its status item did not reach the menu bar." >&2
    if [[ -f "$STATUS_LOG" ]]; then
      tail -n "+$((start_line + 1))" "$STATUS_LOG" >&2
    fi
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
