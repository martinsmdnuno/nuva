#!/bin/zsh
# Builds dist/NuVa-<version>.dmg (and dist/NuVa.dmg) with the Release (universal) app and an Applications shortcut.
# Without a Developer ID the app is ad-hoc signed: recipients have to unblock it (see "Ler primeiro.txt").
set -euo pipefail
cd "${0:a:h}/.."

xcodegen generate -q
xcodebuild -project NuVa.xcodeproj -scheme NuVa -configuration Release -derivedDataPath build \
  ONLY_ACTIVE_ARCH=NO build -quiet

APP=build/Build/Products/Release/NuVa.app
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


Terminal (em vez dos passos 2–3 / instead of steps 2–3):
  xattr -dr com.apple.quarantine /Applications/NuVa.app

https://github.com/martinsmdnuno/nuva
TXT

mkdir -p dist
DMG="dist/NuVa-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "NuVa $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet
# Fixed-name copy for GitHub: releases/latest/download/NuVa.dmg always points to the latest.
cp "$DMG" dist/NuVa.dmg
echo "$DMG"
