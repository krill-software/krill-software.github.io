#!/usr/bin/env bash
# Fill each app card's version tag from the app's latest GitHub Release.
#
# Cards carry `<span class="app-ver" data-app="<slug>">…</span>`; this rewrites
# the span text to the release tag (e.g. v0.2.0). Run locally after a release
# (needs `gh` authenticated) — or let .github/workflows/sync-versions.yml do it
# on its daily schedule. Exit 0 with no change when everything is current.
set -euo pipefail
cd "$(dirname "$0")/.."

for slug in $(grep -o 'data-app="[^"]*"' index.html | sed 's/data-app="//;s/"//' | sort -u); do
  tag=$(gh api "repos/krill-software/$slug/releases/latest" --jq .tag_name 2>/dev/null || true)
  if [[ -z "$tag" ]]; then
    echo "$slug: no release" >&2
    continue
  fi
  sed -i -E "s|(<span class=\"app-ver\" data-app=\"$slug\">)[^<]*(</span>)|\1$tag\2|" index.html
  echo "$slug $tag"
done
