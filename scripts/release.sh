#!/usr/bin/env bash
# Cut a release: bump the version, build the universal DMG, publish it to
# GitHub, and update the Homebrew cask to match.
#
#   bash scripts/release.sh 1.1.0
#   bash scripts/release.sh 1.1.0 --notarize    # needs a Developer ID
#
# Requires: gh (authenticated), a git remote, and a clean-ish working tree.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "Usage: bash scripts/release.sh <version> [--notarize]"; exit 1; }
NOTARIZE=""
[ "${2:-}" = "--notarize" ] && NOTARIZE="--notarize"

command -v gh >/dev/null || { echo "gh CLI not installed: brew install gh"; exit 1; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository. Run: git init && gh repo create"; exit 1; }

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
[ -n "$REPO" ] || { echo "No GitHub remote. Run: gh repo create --source=. --public"; exit 1; }
echo "==> Releasing v$VERSION to $REPO"

echo "==> Stamping version"
sed -i '' "s/MARKETING_VERSION = \".*\"/MARKETING_VERSION = \"$VERSION\"/" \
  WaterBar/Sources/WaterBar/Version.swift
sed -i '' "s/^  version \".*\"/  version \"$VERSION\"/" Casks/waterbar.rb
sed -i '' "s|github.com/[^/]*/[^/]*/releases|github.com/$REPO/releases|" Casks/waterbar.rb
sed -i '' "s|homepage \"https://github.com/.*\"|homepage \"https://github.com/$REPO\"|" Casks/waterbar.rb

echo "==> Verifying the two engines still agree"
bash scripts/parity-check.sh >/dev/null && echo "    parity ok"

bash WaterBar/package.sh $NOTARIZE

DMG="dist/WaterBar-$VERSION.dmg"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

# A stable filename as well as the versioned one, so
# /releases/latest/download/WaterBar.dmg keeps working - that's the URL the
# website's download button points at, and it must not move every release.
STABLE="dist/WaterBar.dmg"
cp "$DMG" "$STABLE"
sed -i '' "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" Casks/waterbar.rb
echo "==> Cask updated: version $VERSION, sha256 $SHA"

git add -A
git commit -m "Release v$VERSION" >/dev/null || echo "    (nothing to commit)"
git tag -f "v$VERSION"
git push origin HEAD --tags

NOTES="$(cat <<NOTE
WaterBar $VERSION - a menu bar readout of the water Claude Code is estimated to drink.

**Install**

    brew install --cask $(dirname "$REPO")/tap/waterbar

or download \`WaterBar-$VERSION.dmg\` below and drag it to Applications.

The app is ad-hoc signed, so macOS blocks it on first launch.

On **macOS 15 Sequoia and later**: System Settings -> Privacy & Security ->
scroll to Security -> **Open Anyway**. (Apple removed the Control-click
shortcut in Sequoia.) On macOS 13-14: Control-click the app -> Open -> Open.

Once, not every launch. Homebrew avoids the detour entirely.

\`sha256\` \`$SHA\`
NOTE
)"

gh release create "v$VERSION" "$DMG" "$STABLE" "$DMG.sha256" \
  --title "WaterBar $VERSION" --notes "$NOTES" || \
gh release upload "v$VERSION" "$DMG" "$STABLE" "$DMG.sha256" --clobber

echo "==> Rebuilding the website"
WATERBAR_REPO="$REPO" python3 site/build.py
cp docs/waterbar.png site/waterbar.png
if command -v vercel >/dev/null && [ -d site/.vercel ]; then
  (cd site && vercel deploy --prod --yes >/dev/null 2>&1) && echo "    deployed"
else
  echo "    skipped (run: cd site && vercel deploy --prod)"
fi

echo
echo "Released: https://github.com/$REPO/releases/tag/v$VERSION"
echo "Now copy Casks/waterbar.rb into your homebrew tap repo (see docs/DISTRIBUTION.md)."
