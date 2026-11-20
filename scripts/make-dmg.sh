#!/bin/zsh
# Builds dist/NuVa-<version>.dmg (and dist/NuVa.dmg) with the Release (universal) app and an Applications shortcut.
# Without a Developer ID the app is ad-hoc signed: recipients have to unblock it (see "Ler primeiro.txt").
set -euo pipefail
cd "${0:a:h}/.."

# Built outside the repo: in an iCloud-synced folder (Desktop, Documents) the build picks up
# Finder attributes and codesign refuses the app. NUVA_BUILD_DIR overrides it.
BUILD_DIR=${NUVA_BUILD_DIR:-${TMPDIR:-/tmp}/nuva-build}

xcodegen generate -q
xcodebuild -project NuVa.xcodeproj -scheme NuVa -configuration Release -derivedDataPath "$BUILD_DIR" \
  ONLY_ACTIVE_ARCH=NO build -quiet

APP=$BUILD_DIR/Build/Products/Release/NuVa.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

ditto "$APP" "$STAGE/NuVa.app"
ln -s /Applications "$STAGE/Aplicações"
cat > "$STAGE/Ler primeiro · Read me first.txt" <<'TXT'
NuVa

PORTUGUÊS

1. Arrastar a NuVa para Aplicações.
2. Abrir a NuVa. O macOS diz que não consegue verificar a app, porque
   a NuVa não está assinada com um certificado pago da Apple. Carregar em OK.
3. Abrir Definições do Sistema › Privacidade e segurança, descer até
   "A NuVa foi bloqueada" e carregar em "Abrir mesmo assim".
   Só é preciso fazer isto uma vez.
4. Na NuVa: "Adicionar pasta" (⌘O) escolhe a pasta da música, no Mac ou
   num disco de rede. "Adicionar Jellyfin" (⇧⌘O) entra num servidor Jellyfin.

Atalhos: Espaço tocar/pausa · ⌘→ ⌘← seguinte/anterior · ⌘↑ ⌘↓ volume
⌘B pastas · ⌘1 ⌘2 ⌘3 tamanho da janela · ⌘L faixa atual
⌥⌘1 ⌥⌘2 ⌥⌘3 skin · ⌥⌘A capas da pasta · ⌘E ejetar CD


ENGLISH

1. Drag NuVa to Applications.
2. Open NuVa. macOS says it can't check the app, because NuVa isn't
   signed with a paid Apple certificate. Click OK.
3. Open System Settings › Privacy & Security, scroll down to
   "NuVa was blocked" and click "Open Anyway".
   You only need to do this once.
4. In NuVa: "Add Folder" (⌘O) picks your music folder, on the Mac or a
   network drive. "Add Jellyfin" (⇧⌘O) signs in to a Jellyfin server.

Shortcuts: Space play/pause · ⌘→ ⌘← next/previous · ⌘↑ ⌘↓ volume
⌘B folders · ⌘1 ⌘2 ⌘3 window size · ⌘L current track
⌥⌘1 ⌥⌘2 ⌥⌘3 skin · ⌥⌘A folder artwork · ⌘E eject CD


Terminal (em vez dos passos 2–3 / instead of steps 2–3):
  xattr -dr com.apple.quarantine /Applications/NuVa.app

https://github.com/martinsmdnuno/nuva
TXT

mkdir -p dist
DMG="dist/NuVa-$VERSION.dmg"
rm -f "$DMG"
# The mounted volume shows NuVa's own disk (docs/brand/VolumeIcon.icns, drawn by make-icons.swift)
# instead of the system's. The "has a custom icon" flag lives on the volume's root folder and
# hdiutil doesn't copy it from the staging folder, so the image is first made writable, flagged
# while mounted, and only then compressed.
cp docs/brand/VolumeIcon.icns "$STAGE/.VolumeIcon.icns"
RW=$(mktemp -d)
MOUNT=$RW/volume
trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$RW"' EXIT
hdiutil create -volname "NuVa $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW/rw.dmg" -quiet
hdiutil attach "$RW/rw.dmg" -nobrowse -noautoopen -mountpoint "$MOUNT" -quiet
# Finder info of the root folder, with kHasCustomIcon (0x0400) in its flags.
xattr -wx com.apple.FinderInfo 0000000000000000040000000000000000000000000000000000000000000000 "$MOUNT"
# No .fseventsd in the image the user opens.
rm -rf "$MOUNT/.fseventsd"
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW/rw.dmg" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" -quiet
hdiutil verify "$DMG" -quiet
# Fixed-name copy for GitHub: releases/latest/download/NuVa.dmg always points to the latest.
cp "$DMG" dist/NuVa.dmg
echo "$DMG"
