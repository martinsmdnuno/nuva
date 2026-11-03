#!/bin/zsh
# Builds windows/dist/NuVa-<version>-windows-<arch>.zip: one self-contained NuVa.exe (nothing to install),
# the font licences and a read-me. Runs on macOS (or Linux, or Windows) with the .NET 10 SDK:
#   brew install dotnet
# Usage: scripts/make-windows-zip.sh [x64|arm64]   (default x64). Runs the Core tests first.
set -euo pipefail
cd "${0:a:h}/.."
ARCH=${1:-x64}
export DOTNET_ROOT=${DOTNET_ROOT:-/opt/homebrew/opt/dotnet/libexec}
export DOTNET_CLI_TELEMETRY_OPTOUT=1

VERSION=$(sed -nE 's/.*MARKETING_VERSION: "([^"]+)".*/\1/p' project.yml)
OUT=windows/dist
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

dotnet run --project windows/NuVa.Core.Tests -c Release
dotnet publish windows/NuVa/NuVa.csproj -c Release -r "win-$ARCH" -o "$STAGE/publish" -nologo -v quiet

mkdir -p "$STAGE/NuVa" "$OUT"
cp "$STAGE/publish/NuVa.exe" "$STAGE/NuVa/"
cp -R windows/NuVa/Licenses "$STAGE/NuVa/Licenses"
cp LICENSE "$STAGE/NuVa/Licenses/NuVa-LICENSE.txt"
cat > "$STAGE/NuVa/Ler primeiro · Read me first.txt" <<TXT
NuVa $VERSION para Windows · for Windows

PORTUGUÊS

1. Descompactar esta pasta para onde quiseres (por exemplo, Documentos ou Programas).
2. Abrir NuVa.exe. O Windows pode avisar que a app é de um editor desconhecido, porque
   a NuVa não está assinada com um certificado pago. Carregar em "Mais informações"
   e depois em "Executar mesmo assim". Só é preciso fazê-lo uma vez.
3. Para desinstalar, apagar a pasta. As definições ficam em %APPDATA%\\NuVa e as capas
   em %LOCALAPPDATA%\\NuVa.

Se algo não funcionar, enviar o ficheiro %LOCALAPPDATA%\\NuVa\\nuva.log.

ENGLISH

1. Unzip this folder wherever you like (for example, Documents or Programs).
2. Open NuVa.exe. Windows may warn that the app is from an unknown publisher, because
   NuVa isn't signed with a paid certificate. Click "More info", then "Run anyway".
   You only need to do this once.
3. To uninstall, delete the folder. Settings are in %APPDATA%\\NuVa and covers in
   %LOCALAPPDATA%\\NuVa.

If something doesn't work, send the file %LOCALAPPDATA%\\NuVa\\nuva.log.

https://nuva.martinsnuno.com · https://github.com/martinsmdnuno/nuva
TXT

ZIP="$OUT/NuVa-$VERSION-windows-$ARCH.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr -X "$OLDPWD/$ZIP" NuVa)
cp "$ZIP" "$OUT/NuVa-windows-$ARCH.zip"
ls -la "$ZIP"
