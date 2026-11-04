#!/bin/zsh
# Fails if the touchpoints or the apps disagree with their sources: the README, the site and llms.txt with
# docs/features.json, the version and the release; every app's colours with tokens.json; every app's text
# in Portuguese and English. Run before every commit that touches a feature; CI runs it on every pull request.
# `swift scripts/content.swift`, `swift scripts/tokens.swift` and `scripts/site-assets.sh` fix what is stale.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/content.swift --check
swift scripts/tokens.swift --check
swift scripts/strings.swift
scripts/site-assets.sh --check
