#!/bin/bash
#
# Generate a flashd schema-1 manifest.json from staged firmware images.
#
# Usage: ./scripts/gen-manifest.sh [options]
#
# Options:
#   --staging DIR    Staging directory to scan (default: <repo>/staging)
#   --tag TAG        GitHub release tag for download URLs (required)
#                    e.g. v0.7.0 → https://github.com/<repo>/releases/download/v0.7.0/…
#   --version VER    Firmware version field (default: today's date YYYY.MM.DD)
#   --channel NAME   Release channel field (default: stable)
#   --repo SLUG      GitHub repo slug for URLs (default: snokvist/waybeam-releases)
#   --out FILE       Output file path (default: <staging>/manifest.json)
#
# Scans staging for files matching the pattern:
#   openipc.<board>-<nor|nand>-waybeam-<wifi>.tgz
#   (<wifi> = WiFi card/driver shortcode: eu=rtl88x2eu, cu=rtl88x2cu, … — not a region)
# and emits a flashd schema-1 manifest.json.
#
# Only full firmware images (openipc.*-waybeam-*.tgz) go into the manifest.
# Loose binaries, APKs, ESP32 .bin files, and ground tarballs are excluded.
#
# Requires: jq, sha256sum, stat (or wc -c as fallback)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# Defaults
STAGING="${REPO_DIR}/staging"
TAG=""
VERSION="$(date +%Y.%m.%d)"
CHANNEL="stable"
REPO_SLUG="snokvist/waybeam-releases"
OUT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --staging)  STAGING="$2"; shift 2 ;;
        --tag)      TAG="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        --channel)  CHANNEL="$2"; shift 2 ;;
        --repo)     REPO_SLUG="$2"; shift 2 ;;
        --out)      OUT="$2"; shift 2 ;;
        -h|--help)
            head -20 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [ -z "$TAG" ]; then
    echo "Error: --tag is required (e.g. --tag v0.7.0)" >&2
    exit 1
fi

if [ ! -d "$STAGING" ]; then
    echo "Error: staging directory not found: ${STAGING}" >&2
    exit 1
fi

OUT="${OUT:-${STAGING}/manifest.json}"

# Check for jq
if ! command -v jq &>/dev/null; then
    echo "Error: jq is required but not found in PATH" >&2
    exit 1
fi

echo "[gen-manifest] Scanning ${STAGING} for openipc.*-waybeam-*.tgz" >&2
echo "[gen-manifest] Tag: ${TAG}  Version: ${VERSION}  Channel: ${CHANNEL}" >&2

# Collect images
images_json="[]"
image_count=0

for filepath in "${STAGING}"/openipc.*-waybeam-*.tgz; do
    [ -f "$filepath" ] || continue

    filename="$(basename "$filepath")"

    # Parse: openipc.<board>-<flash>-waybeam-<wifi>.tgz
    # <wifi> is the WiFi card/driver shortcode (eu=rtl88x2eu, cu=rtl88x2cu, …),
    # NOT a geographic region.
    # Strip leading "openipc." and trailing ".tgz"
    inner="${filename#openipc.}"
    inner="${inner%.tgz}"

    # inner = <board>-<flash>-waybeam-<wifi>
    # Split on "-waybeam-" to isolate the wifi shortcode
    board_flash="${inner%-waybeam-*}"
    wifi="${inner##*-waybeam-}"

    # Split board_flash on first "-" to get board and flash type
    board="${board_flash%%-*}"
    flash="${board_flash#*-}"

    # Validate parsed fields
    if [ -z "$board" ] || [ -z "$flash" ] || [ -z "$wifi" ]; then
        echo "[gen-manifest] WARN: could not parse filename ${filename}, skipping" >&2
        continue
    fi

    # Compute sha256 (lowercase 64-hex)
    sha256="$(sha256sum "$filepath" | awk '{print $1}')"

    # Compute size in bytes
    if stat -c%s "$filepath" &>/dev/null 2>&1; then
        size="$(stat -c%s "$filepath")"
    else
        size="$(wc -c < "$filepath")"
    fi

    # Build download URL
    url="https://github.com/${REPO_SLUG}/releases/download/${TAG}/${filename}"

    # Build image id: <board>-waybeam-<wifi>-<version>
    image_id="${board}-waybeam-${wifi}-${VERSION}"

    notes="wifi: ${wifi}; flash: ${flash}"

    echo "[gen-manifest]   + ${image_id} (${filename}, ${size} bytes)" >&2

    # Append to images array using jq
    images_json="$(echo "$images_json" | jq \
        --arg id       "$image_id" \
        --arg board    "$board" \
        --arg flash    "$flash" \
        --arg role     "vehicle" \
        --arg version  "$VERSION" \
        --arg channel  "$CHANNEL" \
        --arg url      "$url" \
        --arg sha256   "$sha256" \
        --argjson size "$size" \
        --arg notes    "$notes" \
        '. + [{
            "id":      $id,
            "board":   $board,
            "flash":   $flash,
            "role":    $role,
            "version": $version,
            "channel": $channel,
            "url":     $url,
            "sha256":  $sha256,
            "size":    $size,
            "notes":   $notes
        }]')"

    image_count=$((image_count + 1))
done

if [ "$image_count" -eq 0 ]; then
    echo "Error: no matching firmware images found in ${STAGING}" >&2
    echo "       Expected files matching: openipc.*-waybeam-*.tgz" >&2
    exit 1
fi

# Emit manifest.json
jq -n \
    --argjson schema  1 \
    --arg     vendor  "waybeam" \
    --argjson images  "$images_json" \
    '{
        "schema":  $schema,
        "vendor":  $vendor,
        "images":  $images
    }' > "$OUT"

echo "[gen-manifest] Wrote ${OUT} (${image_count} image(s))" >&2
