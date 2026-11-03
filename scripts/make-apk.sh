#!/bin/zsh
# Builds dist/NuVa-AndroidTV-<version>.apk (and dist/NuVa-AndroidTV.apk, the fixed download link),
# the Android TV app signed with the release key.
# The key is ~/.android/nuva-release.jks (NUVA_KEYSTORE overrides it); its password is the Keychain
# item "nuva-android-release". Neither is ever in the repository.
set -euo pipefail
cd "${0:a:h}/.."

export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
export NUVA_KEYSTORE=${NUVA_KEYSTORE:-$HOME/.android/nuva-release.jks}
[[ -f $NUVA_KEYSTORE ]] || { echo "No release key at $NUVA_KEYSTORE" >&2; exit 1; }
export NUVA_KEYSTORE_PASSWORD=$(security find-generic-password -s nuva-android-release -w)

(cd android && ./gradlew -q clean assembleRelease testReleaseUnitTest)

VERSION=$(sed -nE 's/.*MARKETING_VERSION: "([0-9.]+)".*/\1/p' project.yml)
APK=android/app/build/outputs/apk/release/app-release.apk
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
APKSIGNER=$(ls -d "$SDK"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs "$APK" | grep -m1 "SHA-256"

mkdir -p dist
cp "$APK" "dist/NuVa-AndroidTV-$VERSION.apk"
cp "$APK" dist/NuVa-AndroidTV.apk
echo "dist/NuVa-AndroidTV-$VERSION.apk"
