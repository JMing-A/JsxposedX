#!/usr/bin/env bash
#
# Read the version from pubspec.yaml, then create and push the matching Git tag.
# Pushing the tag triggers .github/workflows/build.yml to build all packages
# and publish a GitHub Release.
#
# Usage:
#   ./.buildScript/release.sh              Create and push the tag
#   ./.buildScript/release.sh --force      Overwrite the tag if it already exists
#   ./.buildScript/release.sh --dry-run    Print the actions without executing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

FORCE=false
DRY_RUN=false

usage() {
  printf 'Usage: %s [--force] [--dry-run]\n' "$(basename "$0")"
  printf '  --force    Overwrite the tag if it already exists.\n'
  printf '  --dry-run  Print the actions without executing them.\n'
}

while (($# > 0)); do
  case "$1" in
    --force|-f)
      FORCE=true
      ;;
    --dry-run|-n)
      DRY_RUN=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

PUBSPEC="$PROJECT_DIR/pubspec.yaml"
if [[ ! -f "$PUBSPEC" ]]; then
  printf 'Error: pubspec.yaml not found at %s\n' "$PUBSPEC" >&2
  exit 1
fi

version_line="$(grep -E '^version:[[:space:]]*' "$PUBSPEC" | head -n 1 || true)"
if [[ -z "$version_line" ]]; then
  printf 'Error: no version field found in pubspec.yaml\n' >&2
  exit 1
fi

# version looks like "6.1.0+610": keep the part before "+"
app_version="${version_line#version:}"
app_version="${app_version%%+*}"
app_version="$(printf '%s' "$app_version" | tr -d '[:space:]')"

if [[ ! "$app_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  printf 'Error: unexpected version format in pubspec.yaml: %s\n' "$app_version" >&2
  exit 1
fi

tag="V$app_version"

if [[ -n "$(git status --porcelain)" ]]; then
  printf 'Error: working tree is dirty, commit your changes before releasing\n' >&2
  git status --short >&2
  exit 1
fi

tag_exists=false
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  tag_exists=true
fi

if [[ "$tag_exists" == true && "$FORCE" != true ]]; then
  printf 'Error: tag %s already exists, use --force to overwrite\n' "$tag" >&2
  exit 1
fi

printf 'Releasing %s (pubspec version %s)\n' "$tag" "$app_version"
if [[ "$tag_exists" == true ]]; then
  printf '  git tag -f %s\n' "$tag"
  printf '  git push --force origin %s\n' "$tag"
else
  printf '  git tag %s\n' "$tag"
  printf '  git push origin %s\n' "$tag"
fi

if [[ "$DRY_RUN" == true ]]; then
  printf '\n[dry-run] nothing was executed\n'
  exit 0
fi

if [[ "$tag_exists" == true ]]; then
  git tag -f "$tag"
  git push --force origin "$tag"
else
  git tag "$tag"
  git push origin "$tag"
fi

printf '\nTag %s pushed. GitHub Actions is now building:\n' "$tag"
repo_url="$(git remote get-url origin)"
repo_url="${repo_url#git@github.com:}"
repo_url="${repo_url#https://github.com/}"
repo_url="${repo_url%.git}"
printf '  https://github.com/%s/actions\n' "$repo_url"
