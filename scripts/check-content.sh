#!/bin/zsh
# Fails if the README, the site or llms.txt disagree with docs/features.json, the version or the release.
# Run before every commit that touches a feature, and in the release; `swift scripts/content.swift` fixes stale blocks.
set -euo pipefail
cd "$(dirname "$0")/.."
swift scripts/content.swift --check
