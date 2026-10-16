#!/bin/zsh
# Gera dist/NuVa-<versão>.dmg com a app em Release (universal) e um atalho para Aplicações.
# Sem Developer ID a app vai com assinatura ad-hoc: quem a recebe tem de a desbloquear (ver "Ler primeiro.txt").
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
cat > "$STAGE/Ler primeiro.txt" <<'TXT'
NuVa (versão de teste)

1. Arrastar a NuVa para Aplicações.
2. Abrir a NuVa. O macOS vai dizer que não consegue verificar a app
   (não está assinada com um certificado da Apple). Carregar em OK.
3. Abrir Definições do Sistema › Privacidade e segurança, descer até
   "A NuVa foi bloqueada" e carregar em "Abrir mesmo assim".
4. Na janela da NuVa: ⌘2 abre o navegador. "Adicionar pasta" escolhe
   uma pasta de música no Mac; "Adicionar Jellyfin" entra num servidor
   Jellyfin com o teu utilizador (pasta = álbum nos dois casos).

Alternativa no Terminal, depois do passo 1:
  xattr -dr com.apple.quarantine /Applications/NuVa.app

Atalhos: Espaço tocar/pausa · ⌘→ seguinte · ⌘← anterior · ⌘↑ ⌘↓ volume
⌘1 ⌘2 tamanho da janela · ⌘L faixa atual · ⌘O adicionar pasta
⇧⌘O adicionar Jellyfin
TXT

mkdir -p dist
DMG="dist/NuVa-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "NuVa $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
hdiutil verify "$DMG" -quiet
echo "$DMG"
