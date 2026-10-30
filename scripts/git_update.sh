#!/usr/bin/env bash
# Computes the next semantic version tag (vX.Y.Z) from the latest existing tag.
#
#   ./scripts/git_update.sh -v patch   # v0.1.1 -> v0.1.2
#   ./scripts/git_update.sh -v minor   # v0.1.1 -> v0.2.0
#   ./scripts/git_update.sh -v major   # v0.1.1 -> v1.0.0
#
# If HEAD already carries a version tag (e.g. a re-run), that tag is reused.
# The tag is created locally only; push it with `git push origin <tag>`.
# In GitHub Actions the result is written to $GITHUB_OUTPUT as `new-tag`.
set -euo pipefail

BUMP="patch"
# Starting point when the repo has no version tags yet.
INITIAL_VERSION="v0.1.0"

while getopts "v:" opt; do
  case "$opt" in
    v) BUMP="$OPTARG" ;;
    *) echo "usage: $0 -v [major|minor|patch]" >&2; exit 1 ;;
  esac
done

case "$BUMP" in
  major|minor|patch) ;;
  *) echo "invalid bump '$BUMP', expected major, minor or patch" >&2; exit 1 ;;
esac

git fetch --tags --quiet origin 2>/dev/null || true

VERSION_PATTERN='^v[0-9]+\.[0-9]+\.[0-9]+$'

EXISTING_TAG=$(git tag --points-at HEAD | grep -E "$VERSION_PATTERN" | sort -V | tail -n1 || true)
if [[ -n "$EXISTING_TAG" ]]; then
  echo "HEAD is already tagged $EXISTING_TAG, reusing it" >&2
  NEW_TAG="$EXISTING_TAG"
else
  LATEST_TAG=$(git tag -l 'v*' | grep -E "$VERSION_PATTERN" | sort -V | tail -n1 || true)
  LATEST_TAG="${LATEST_TAG:-$INITIAL_VERSION}"

  IFS='.' read -r MAJOR MINOR PATCH <<< "${LATEST_TAG#v}"
  case "$BUMP" in
    major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
    minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
    patch) PATCH=$((PATCH + 1)) ;;
  esac

  NEW_TAG="v${MAJOR}.${MINOR}.${PATCH}"
  echo "Bumping $BUMP: $LATEST_TAG -> $NEW_TAG" >&2
  git tag "$NEW_TAG"
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "new-tag=$NEW_TAG" >> "$GITHUB_OUTPUT"
fi
echo "$NEW_TAG"
