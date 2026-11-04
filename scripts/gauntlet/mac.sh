# Mac gates for scripts/gauntlet.sh (sourced; `gate`, `$out` and `diff_for_judge` come from there).

derived=build/DerivedData
app=$derived/Build/Products/Debug/NuVa.app

xcode_build() {
  xcodebuild -project NuVa.xcodeproj -scheme NuVa -configuration Debug \
    -derivedDataPath $derived -destination 'platform=macOS' clean build
}

xcode_test() {
  xcodebuild -project NuVa.xcodeproj -scheme NuVa -configuration Debug \
    -derivedDataPath $derived -destination 'platform=macOS' test
}

# Warnings in our own sources (not in Apple's frameworks); any is a failure. The build is clean, so
# every file is compiled and none hides its warnings.
no_warnings() {
  local warnings
  warnings=$(grep -E '^/.*(App|Sources)/.*: warning: ' $out/logs/build.log | sort -u)
  if [[ -n $warnings ]]; then echo $warnings; return 1; fi
  echo "no warnings in App/ or Sources/"
}

# The snapshot views in Portuguese and English, each language in its own folder.
# Fails if a language writes no images or fewer than the other.
snapshots() {
  local lang dir count
  # The app writes to its sandbox's tmp folder, which keeps older runs' images (retired views too).
  rm -f ~/Library/Containers/pt.nunomartins.nuva/Data/tmp/snapshot-*.png
  for lang in pt-PT en; do
    dir=$($app/Contents/MacOS/NuVa --snapshot -AppleLanguages "($lang)" | tail -n 1)
    [[ -d $dir ]] || { echo "no snapshot folder for $lang"; return 1; }
    mkdir -p $out/snapshots/$lang
    mv $dir/snapshot-*.png $out/snapshots/$lang/ 2>/dev/null
    count=$(ls $out/snapshots/$lang | wc -l | tr -d ' ')
    echo "$lang: $count images"
    (( count > 0 )) || return 1
  done
  [[ $(ls $out/snapshots/pt-PT | wc -l) == $(ls $out/snapshots/en | wc -l) ]]
}

gate project   xcodegen generate
gate build     xcode_build
gate warnings  no_warnings
gate test      xcode_test
gate strings   swift scripts/strings.swift
gate content   scripts/check-content.sh
gate snapshots snapshots

