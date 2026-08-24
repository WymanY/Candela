#!/bin/sh
# Build a drag-and-drop UDZO DMG: Candela.app + /Applications symlink.
# Usage: package_dmg.sh <App.app> <output.dmg> [volume name]
set -eu

if [ "$#" -lt 2 ]; then
  echo "usage: $0 <App.app> <output.dmg> [volume name]" >&2
  exit 1
fi

APP_PATH=$1
DMG_PATH=$2
VOL_NAME=${3:-Candela}

case "$APP_PATH" in
  /*) ;;
  *) APP_PATH=$(pwd)/$APP_PATH ;;
esac
case "$DMG_PATH" in
  /*) ;;
  *) DMG_PATH=$(pwd)/$DMG_PATH ;;
esac

if [ ! -d "$APP_PATH/Contents/MacOS" ]; then
  echo "not a macOS app bundle: $APP_PATH" >&2
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
STAGING=$(mktemp -d)
RW_DMG=$STAGING/rw.dmg
MOUNT=$STAGING/mnt
mkdir -p "$MOUNT" "$(dirname "$DMG_PATH")"

cleanup() {
  if [ -d "$MOUNT" ]; then
    hdiutil detach "$MOUNT" -force -quiet >/dev/null 2>&1 || true
  fi
  rm -rf "$STAGING"
}
trap cleanup EXIT INT HUP TERM

APP_KB=$(du -sk "$APP_PATH" | awk '{print $1}')
SIZE_MB=$((APP_KB / 1024 + 40))
if [ "$SIZE_MB" -lt 60 ]; then
  SIZE_MB=60
fi

hdiutil create \
  -size "${SIZE_MB}m" \
  -fs HFS+ \
  -volname "$VOL_NAME" \
  -ov \
  "$RW_DMG" >/dev/null

hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT" >/dev/null

ditto "$APP_PATH" "$MOUNT/$APP_NAME"
xattr -cr "$MOUNT/$APP_NAME" 2>/dev/null || true
ln -s /Applications "$MOUNT/Applications"
chmod -R a+rX "$MOUNT/$APP_NAME"
sync

DETACHED=false
for _ in 1 2 3 4 5 6 7 8; do
  if hdiutil detach "$MOUNT" -quiet; then
    DETACHED=true
    break
  fi
  sleep 1
done
if [ "$DETACHED" != true ]; then
  echo "could not detach temporary disk image: $MOUNT" >&2
  exit 1
fi

rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null
echo "wrote $DMG_PATH"
