#!/bin/zsh
# The objective half of the gauntlet (docs/gauntlet/README.md): runs one platform's gates in order,
# cheapest first, and stops at the first that fails. Writes each gate's log, the screenshots and a
# summary to build/gauntlet/<platform>/; the judge (.claude/agents/gauntlet-judge.md) reads them after.
# Usage: scripts/gauntlet.sh mac
# Exit code 0 when every gate passes, 1 when one fails (its name is in summary.txt).
set -uo pipefail
cd "$(dirname "$0")/.."

platform=${1:-}
case $platform in
  mac) ;;
  tv|windows|site) echo "gauntlet: '$platform' has no gates yet (docs/gauntlet/README.md)"; exit 2 ;;
  *) echo "usage: scripts/gauntlet.sh mac"; exit 2 ;;
esac

out=build/gauntlet/$platform
rm -rf $out
mkdir -p $out/logs
summary=$out/summary.txt
: > $summary

# Runs one gate: gate <name> <command…>. Logs to logs/<name>.log; stops the run on failure.
gate() {
  local name=$1; shift
  local log=$out/logs/$name.log
  local start=$SECONDS
  printf '%-14s ' $name
  if "$@" > $log 2>&1; then
    echo "ok   ($((SECONDS - start))s)"
    echo "$name ok" >> $summary
  else
    echo "FAIL ($((SECONDS - start))s) → $log"
    echo "$name FAIL $log" >> $summary
    echo "--- last lines of $log ---"
    tail -n 30 $log
    exit 1
  fi
}

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

# What the judge reviews: the branch's changes against main.
diff_for_judge() {
  local base
  base=$(git merge-base HEAD main)
  { git log --oneline $base..HEAD; echo; git diff $base -- . ':!docs/screenshots' ':!site/img'; } > $out/diff.patch
  echo "$(git rev-list --count $base..HEAD) commits since main"
}

gate project   xcodegen generate
gate build     xcode_build
gate warnings  no_warnings
gate test      xcode_test
gate strings   swift scripts/strings.swift
gate content   scripts/check-content.sh
gate snapshots snapshots
gate diff      diff_for_judge

echo "all gates passed → $out (for the judge: snapshots/, diff.patch)"
