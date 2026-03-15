#!/bin/bash
#
# Create a GitHub Release and attach all staged binaries.
#
# Usage: ./scripts/upload-release.sh <version> [options]
#
# Options:
#   --notes TEXT       Release notes (default: auto-generated)
#   --draft            Create as draft release
#   --prerelease       Mark as pre-release
#   --latest           Also update the 'latest' tag
#
# Requires: gh (GitHub CLI), authenticated

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
STAGING="${REPO_DIR}/staging"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <version> [--notes TEXT] [--draft] [--prerelease] [--latest]"
    echo "Example: $0 v0.5.0 --notes 'Initial release'"
    exit 1
fi

VERSION="$1"
shift

NOTES=""
DRAFT=false
PRERELEASE=false
UPDATE_LATEST=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --notes)      NOTES="$2"; shift 2 ;;
        --draft)      DRAFT=true; shift ;;
        --prerelease) PRERELEASE=true; shift ;;
        --latest)     UPDATE_LATEST=true; shift ;;
        *)            echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ ! -d "$STAGING" ] || [ -z "$(ls -A "$STAGING" 2>/dev/null)" ]; then
    echo "Error: staging/ is empty. Run scripts/collect.sh first."
    exit 1
fi

# Check gh is available and authenticated
if ! command -v gh &>/dev/null; then
    echo "Error: gh (GitHub CLI) not found. Install from https://cli.github.com/"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "Error: gh not authenticated. Run 'gh auth login' first."
    exit 1
fi

echo "=== Creating release ${VERSION} ==="
echo ""
echo "Files to upload:"
ls -lh "$STAGING/"
echo ""

# Build gh release create command
GH_ARGS=("gh" "release" "create" "$VERSION")
GH_ARGS+=("--repo" "snokvist/waybeam-releases")
GH_ARGS+=("--title" "Waybeam ${VERSION}")

if [ -n "$NOTES" ]; then
    GH_ARGS+=("--notes" "$NOTES")
else
    # Auto-generate notes
    AUTO_NOTES="Waybeam FPV ecosystem release ${VERSION}.

## Included artifacts

$(ls -1 "$STAGING/" | sed 's/^/- /')"
    GH_ARGS+=("--notes" "$AUTO_NOTES")
fi

$DRAFT && GH_ARGS+=("--draft")
$PRERELEASE && GH_ARGS+=("--prerelease")

# Add all staging files as assets
for f in "${STAGING}"/*; do
    [ -f "$f" ] && GH_ARGS+=("$f")
done

echo "Creating release..."
"${GH_ARGS[@]}"

echo ""
echo "Release ${VERSION} created successfully!"
echo "URL: https://github.com/snokvist/waybeam-releases/releases/tag/${VERSION}"

# Optionally update the 'latest' tag
if $UPDATE_LATEST; then
    echo ""
    echo "Updating 'latest' tag..."

    # Delete existing latest release if it exists
    gh release delete latest --repo snokvist/waybeam-releases --yes 2>/dev/null || true

    # Create new latest release with same files
    LATEST_ARGS=("gh" "release" "create" "latest")
    LATEST_ARGS+=("--repo" "snokvist/waybeam-releases")
    LATEST_ARGS+=("--title" "Waybeam Latest (${VERSION})")
    LATEST_ARGS+=("--notes" "Rolling release tracking ${VERSION}. For stable releases, use versioned tags.")
    LATEST_ARGS+=("--prerelease")

    for f in "${STAGING}"/*; do
        [ -f "$f" ] && LATEST_ARGS+=("$f")
    done

    "${LATEST_ARGS[@]}"
    echo "Latest tag updated to ${VERSION}"
fi
