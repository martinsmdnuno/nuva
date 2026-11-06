#!/bin/zsh
# Builds dist/NuVa-AndroidTV-<version>.apk (and dist/NuVa-AndroidTV.apk, the fixed download link),
# the Android TV app signed with the release key.
# The key is ~/.android/nuva-release.jks (NUVA_KEYSTORE overrides it); its password is in
# ~/.android/nuva-release.password (NUVA_KEYSTORE_PASSWORD_FILE overrides it), or else the Keychain
# item "nuva-android-release". Neither is ever in the repository.
set -euo pipefail
cd "${0:a:h}/.."

export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}
# Gradle finds the SDK here even without android/local.properties (git-ignored, so absent in a fresh checkout).
export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
export NUVA_KEYSTORE=${NUVA_KEYSTORE:-$HOME/.android/nuva-release.jks}
[[ -f $NUVA_KEYSTORE ]] || { echo "No release key at $NUVA_KEYSTORE" >&2; exit 1; }
PASSWORD_FILE=${NUVA_KEYSTORE_PASSWORD_FILE:-$HOME/.android/nuva-release.password}
if [[ -f $PASSWORD_FILE ]]; then
  export NUVA_KEYSTORE_PASSWORD=$(<"$PASSWORD_FILE")
else
  export NUVA_KEYSTORE_PASSWORD=$(security find-generic-password -s nuva-android-release -w)
fi

(cd android && ./gradlew -q clean assembleRelease testReleaseUnitTest)

VERSION=$(sed -nE 's/.*MARKETING_VERSION: "([0-9.]+)".*/\1/p' project.yml)
APK=android/app/build/outputs/apk/release/app-release.apk
APKSIGNER=$(ls -d "$ANDROID_HOME"/build-tools/*/apksigner | sort -V | tail -1)
"$APKSIGNER" verify --print-certs "$APK" | grep -m1 "SHA-256"

mkdir -p dist
cp "$APK" "dist/NuVa-AndroidTV-$VERSION.apk"
cp "$APK" dist/NuVa-AndroidTV.apk
echo "dist/NuVa-AndroidTV-$VERSION.apk"
