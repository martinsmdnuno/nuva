#!/bin/zsh
# One release for every platform: scripts/release.sh X [--dry-run] [--yes]
#  1. Checks: on main, clean, level with origin, vX not tagged yet, CHANGELOG.md already has its "## X" entry.
#  2. Bumps project.yml (MARKETING_VERSION X, CURRENT_PROJECT_VERSION + 1; the Android app reads it too),
#     the site's version and dates and the generated blocks, then runs scripts/check-content.sh.
#  3. Builds each released platform in docs/features.json with its own script (dist/<file> and dist/<file-X>).
#  4. Commits "Version X". --dry-run stops before this and puts the files back (the builds stay in dist/).
#  5. Asks (unless --yes), then pushes, tags vX, publishes the GitHub release with every file and the
#     CHANGELOG.md entry as notes, and deploys the site.
#  6. Checks that every fixed download link and the site answer with X.
# The site's deploy command lives outside the repository: scripts/release.local (git-ignored) can set
# NUVA_DEPLOY=(command and arguments); without it the script says so and leaves the deploy to you.
set -euo pipefail
cd "${0:a:h}/.."

step() { print -P "%B▶ $*%b" }
fail() { print -P "%F{red}✗ $*%f" >&2; exit 1 }

VERSION=${1:-}
(( $# )) && shift
DRY=0 YES=0
for a in "$@"; do
  case $a in --dry-run) DRY=1 ;; --yes) YES=1 ;; *) fail "Unknown option $a" ;; esac
done
[[ $VERSION =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || fail "Usage: scripts/release.sh X [--dry-run] [--yes]   (X like 1.12 or 1.12.1)"
typeset -a NUVA_DEPLOY=()
[[ -f scripts/release.local ]] && source scripts/release.local
SITE=https://nuva.martinsnuno.com
DOWNLOAD=https://github.com/martinsmdnuno/nuva/releases/latest/download

step "Checks"
[[ -z $(git status --porcelain) ]] || fail "Uncommitted changes; commit or set them aside first"
git fetch -q origin --tags
if (( !DRY )); then
  [[ $(git branch --show-current) == main ]] || fail "Not on main"
  [[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || fail "main isn't level with origin/main"
  gh auth status >/dev/null 2>&1 || fail "gh isn't signed in"
fi
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && fail "v$VERSION is already tagged"
grep -qE "^## ${VERSION//./\\.}( |$)" CHANGELOG.md || fail "CHANGELOG.md has no '## $VERSION' entry; write it first"

# From here until the commit, any stop puts the tracked files back as they were.
COMMITTED=0
trap '(( COMMITTED )) || git checkout -q -- .' EXIT

step "Version $VERSION"
build=$(( $(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?$/\1/p' project.yml) + 1 ))
sed -i '' -E -e "s/^( *MARKETING_VERSION: *).*/\1\"$VERSION\"/" -e "s/^( *CURRENT_PROJECT_VERSION: *).*/\1\"$build\"/" project.yml
scripts/update-site.sh
swift scripts/content.swift
scripts/check-content.sh
TITLE=$(swift scripts/content.swift --title)
NOTES=$(mktemp)
swift scripts/content.swift --notes > "$NOTES"

typeset -a FILES=() FIXED=()
start=$(date +%s)
for line in ${(f)"$(swift scripts/content.swift --assets)"}; do
  script=${line%%$'\t'*} rest=${line#*$'\t'}
  fixed=${rest%%$'\t'*} named=${rest#*$'\t'}
  step "Build: $script"
  "$script"
  for f in dist/$fixed dist/$named; do
    [[ -f $f && $(stat -f %m "$f") -ge $start ]] || fail "$script didn't write $f"
  done
  FILES+=(dist/$fixed dist/$named) FIXED+=($fixed)
done

step "Ready: $TITLE"
for f in $FILES; print "  $f  $(du -h "$f" | cut -f1)"
print "\nRelease notes:"
sed 's/^/  /' "$NOTES"
print
if (( DRY )); then
  print "Dry run: nothing committed and the files are back as they were; the builds are in dist/."
  exit 0
fi

git commit -qam "Version $VERSION"
COMMITTED=1
if (( !YES )); then
  read -r "ans?Push main, tag v$VERSION, publish the release and deploy the site? [s/N] "
  [[ $ans == [sSyY]* ]] || { print "Stopped. 'Version $VERSION' is committed here only; undo with: git reset --hard HEAD~1"; exit 0; }
fi

step "Publish"
git push -q origin main
git tag "v$VERSION"
git push -q origin "v$VERSION"
gh release create "v$VERSION" $FILES --title "$TITLE" --notes-file "$NOTES" --latest

step "Site"
if (( ${#NUVA_DEPLOY} )); then
  "${NUVA_DEPLOY[@]}"
else
  print "No NUVA_DEPLOY in scripts/release.local: deploy the site yourself (git pull in its checkout on the server)."
fi

step "Verify"
ok=1
for fixed in $FIXED; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -L -r 0-0 --max-time 30 "$DOWNLOAD/$fixed" || echo 000)
  [[ $code == 20[06] ]] && print "  ✓ $fixed" || { print "  ✗ $DOWNLOAD/$fixed answered $code"; ok=0; }
done
if (( ${#NUVA_DEPLOY} )); then
  for page in / /pt/; do
    curl -s --max-time 15 "$SITE$page" | grep -q "class=\"version\">$VERSION<" \
      && print "  ✓ $SITE$page shows $VERSION" || { print "  ✗ $SITE$page doesn't show $VERSION"; ok=0; }
  done
fi
(( ok )) && print -P "%F{green}NuVa $VERSION is out.%f" || fail "Released, but some checks failed (above)"
