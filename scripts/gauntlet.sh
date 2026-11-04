#!/bin/zsh
# The objective half of the gauntlet (docs/gauntlet/README.md): runs one platform's gates in order,
# cheapest first, and stops at the first that fails. Writes each gate's log, the screenshots and a
# summary to build/gauntlet/<platform>/; the judge (.claude/agents/gauntlet-judge.md) reads them after.
# Usage: scripts/gauntlet.sh <platform>   (each platform's gates are in scripts/gauntlet/<platform>.sh)
# Exit code 0 when every gate passes, 1 when one fails (its name is in summary.txt).
set -uo pipefail
cd "$(dirname "$0")/.."

platform=${1:-}
gates=scripts/gauntlet/$platform.sh
if [[ -z $platform || ! -f $gates ]]; then
  echo "usage: scripts/gauntlet.sh <$(cd scripts/gauntlet && ls *.sh | sed 's/\.sh$//' | paste -sd '|' -)>"; exit 2
fi

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

# What the judge reviews: the branch's changes against main.
diff_for_judge() {
  local base
  base=$(git merge-base HEAD main)
  { git log --oneline $base..HEAD; echo; git diff $base -- . ':!docs/screenshots' ':!site/img'; } > $out/diff.patch
  echo "$(git rev-list --count $base..HEAD) commits since main"
}


source $gates
gate diff      diff_for_judge

echo "all gates passed → $out (for the judge: diff.patch$([[ -d $out/snapshots ]] && echo ', snapshots/'))"
