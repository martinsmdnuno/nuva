#!/bin/zsh
# Stamps the site's CSS and JS links with a hash of their content (style.css?v=1a2b3c4d), so a
# browser that cached an older file fetches the new one with the new page. Caddy caches stamped
# files for a year and revalidates the pages. With --check, only fails if a stamp is stale.
set -euo pipefail
cd "$(dirname "$0")/.."
check=false; [[ "${1:-}" == --check ]] && check=true
stale=0
for asset in style.css platform.js feedback.js; do
  hash=$(shasum -a 256 "site/$asset" | cut -c1-8)
  for page in site/**/*.html; do
    grep -q "\"/$asset" "$page" || continue
    if $check; then
      if grep -oE "\"/$asset(\\?v=[0-9a-f]+)?\"" "$page" | grep -vq "?v=$hash\""; then
        echo "$page: /$asset is not stamped with $hash (run scripts/site-assets.sh)"; stale=1
      fi
    else
      sed -i '' -E "s#\"/$asset(\\?v=[0-9a-f]+)?\"#\"/$asset?v=$hash\"#g" "$page"
    fi
  done
done
$check && { (( stale == 0 )) && echo "Site assets are stamped."; exit $stale; }
echo "Site assets stamped."
