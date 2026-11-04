#!/usr/bin/env bash
# Build Portly release packages:
#   dist/portly_<version>_amd64.deb
#   dist/Portly-<version>-x86_64.AppImage   (needs appimagetool)
#
# Usage: tool/package.sh [deb|appimage|all]   (default: all)
#
# appimagetool is looked up as $APPIMAGETOOL, then on PATH, then in tools/.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
TARGET=${1:-all}

VERSION=$(sed -n 's/^version: *\([0-9.]*\).*/\1/p' pubspec.yaml)
APP_ID=dev.dosss.portly
BUNDLE=$ROOT/build/linux/x64/release/bundle
WORK=$ROOT/build/package
DIST=$ROOT/dist

echo "==> Portly $VERSION"
flutter build linux --release
mkdir -p "$DIST"

install_icons() { # <usr dir>
  local usr=$1
  for size in 128 256 512; do
    install -Dm644 "assets/icons/portly_$size.png" \
      "$usr/share/icons/hicolor/${size}x${size}/apps/portly.png"
  done
  install -Dm644 assets/icons/portly.svg "$usr/share/icons/hicolor/scalable/apps/portly.svg"
}

build_deb() {
  local name="portly_${VERSION}_amd64"
  local root="$WORK/deb/$name"
  rm -rf "$root"

  # The bundle needs its lib/ and data/ next to the binary.
  mkdir -p "$root/usr/lib/portly" "$root/usr/bin"
  cp -a "$BUNDLE/." "$root/usr/lib/portly/"
  ln -s ../lib/portly/portly "$root/usr/bin/portly"

  install -Dm644 "linux/packaging/$APP_ID.desktop" \
    "$root/usr/share/applications/$APP_ID.desktop"
  install_icons "$root/usr"
  install -Dm644 LICENSE "$root/usr/share/doc/portly/copyright"

  chmod -R u+rwX,go+rX,go-w "$root"
  local size
  size=$(du -sk "$root/usr" | cut -f1)
  mkdir -p "$root/DEBIAN"
  cat > "$root/DEBIAN/control" <<EOF
Package: portly
Version: $VERSION
Architecture: amd64
Maintainer: dosss
Installed-Size: $size
Section: utils
Priority: optional
Depends: libgtk-3-0t64 | libgtk-3-0, libnotify4, iproute2, pkexec | policykit-1
Description: See what's running on your ports — and free them in one click.
 Portly lists listening TCP and UDP ports with the process behind each one,
 lets you stop that process (with pkexec for root-owned ones) and lives in
 the system tray.
EOF

  dpkg-deb --build --root-owner-group "$root" "$DIST/$name.deb"
  echo "==> $DIST/$name.deb"
}

find_appimagetool() {
  if [[ -n ${APPIMAGETOOL:-} ]]; then echo "$APPIMAGETOOL"; return; fi
  if command -v appimagetool >/dev/null; then command -v appimagetool; return; fi
  local local_tool
  local_tool=$(ls "$ROOT"/tools/appimagetool*.AppImage 2>/dev/null | head -1 || true)
  [[ -n $local_tool ]] && echo "$local_tool"
  return 0
}

build_appimage() {
  local appdir="$WORK/Portly.AppDir"
  rm -rf "$appdir"
  mkdir -p "$appdir/usr/lib/portly" "$appdir/usr/bin"
  cp -a "$BUNDLE/." "$appdir/usr/lib/portly/"
  ln -s ../lib/portly/portly "$appdir/usr/bin/portly"
  install_icons "$appdir/usr"
  install -Dm644 "linux/packaging/$APP_ID.desktop" \
    "$appdir/usr/share/applications/$APP_ID.desktop"

  # AppImage root: desktop file, icon and an AppRun entry point.
  cp "linux/packaging/$APP_ID.desktop" "$appdir/$APP_ID.desktop"
  cp assets/icons/portly_256.png "$appdir/portly.png"
  ln -s portly.png "$appdir/.DirIcon"
  cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE=$(dirname "$(readlink -f "$0")")
exec "$HERE/usr/lib/portly/portly" "$@"
EOF
  chmod +x "$appdir/AppRun"

  local tool
  tool=$(find_appimagetool)
  if [[ -z $tool ]]; then
    echo "!! appimagetool not found: AppDir left at $appdir, AppImage skipped."
    echo "   Download it from https://github.com/AppImage/appimagetool/releases"
    echo "   into tools/ (chmod +x), or set APPIMAGETOOL=/path/to/appimagetool."
    return 0
  fi
  local out="$DIST/Portly-$VERSION-x86_64.AppImage"
  ARCH=x86_64 "$tool" --no-appstream "$appdir" "$out"
  echo "==> $out"
}

case $TARGET in
  deb) build_deb ;;
  appimage) build_appimage ;;
  all) build_deb; build_appimage ;;
  *) echo "usage: $0 [deb|appimage|all]" >&2; exit 2 ;;
esac
