#!/usr/bin/env bash
# Puts the "Latest" badge back on the release that owns it.
#
# `gh release create --latest=false` does not keep a platform release away from
# that badge, whatever the comments in windows.yml and linux.yml claimed. The
# flag only declines to *pin* that one release; GitHub then falls back to
# whichever non-draft, non-prerelease release has the newest created_at — and
# created_at is the date of the commit, not of the publish. So the newest tag
# takes the badge regardless. windows-v0.1.8 took it on 2026-10-29 with
# --latest=false passed exactly as written.
#
# The badge has to sit on a macOS release, because two things read it:
#   - SUFeedURL is /releases/latest/download/appcast.xml, and only the notarized
#     `v*` releases scripts/release.sh publishes carry an appcast;
#   - the download page's "Download for Mac" button points at /releases/latest,
#     so a Windows release there hands Mac users an .exe.
# Hence: the newest `v*` wins; failing that the newest `mac-v*`, which at least
# hands a Mac user a .dmg; failing both, leave it alone — there is no macOS
# release to point at and nothing to repair.
#
# Run it after publishing any platform release. It is idempotent, and it is the
# whole fix: the --latest=false flags stay because declining to pin is still
# right, they were just never enough on their own.
#
# Usage: scripts/pin-latest-release.sh [owner/repo]   (defaults to $GITHUB_REPOSITORY)

set -euo pipefail

REPO="${1:-${GITHUB_REPOSITORY:?no repo given and GITHUB_REPOSITORY is unset}}"

# Newest published release whose tag matches $1, by commit date — the same
# ordering GitHub itself uses to pick a fallback.
newest() {
  gh release list --repo "$REPO" --limit 100 \
    --json tagName,isDraft,isPrerelease,createdAt \
    --jq "[.[] | select(.isDraft == false and .isPrerelease == false)
           | select(.tagName | test(\"$1\"))]
          | sort_by(.createdAt) | reverse | .[0].tagName // empty"
}

owner="$(newest '^v[0-9]')"
[ -n "$owner" ] || owner="$(newest '^mac-v[0-9]')"

if [ -z "$owner" ]; then
  echo "No macOS release to hold the Latest badge — leaving it where it is."
  exit 0
fi

current="$(gh api "repos/$REPO/releases/latest" --jq .tag_name 2>/dev/null || true)"
if [ "$current" = "$owner" ]; then
  echo "Latest is already $owner."
  exit 0
fi

gh release edit "$owner" --repo "$REPO" --latest >/dev/null
echo "Latest moved from ${current:-none} to $owner."
