#!/bin/zsh
# Puts the version from project.yml and today's date into the site (run at each release).
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?$/\1/p' project.yml | head -1)
today=$(date +%Y-%m-%d)
for page in site/index.html site/pt/index.html; do
  sed -i '' -E \
    -e "s|(\"softwareVersion\": \")[^\"]*|\1$version|" \
    -e "s|(<span class=\"version\">)[^<]*|\1$version|" \
    "$page"
done
sed -i '' -E "s|(Current version: )[0-9.]+|\1$version|" site/llms.txt
sed -i '' -E "s|<lastmod>[^<]*</lastmod>|<lastmod>$today</lastmod>|" site/sitemap.xml
scripts/site-assets.sh
echo "Site: version $version, $today"
