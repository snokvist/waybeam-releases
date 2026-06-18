#!/bin/bash
#
# serve-mirror.sh — host a flashd firmware mirror on the LAN (ground-station side).
#
# Waybeam vehicles run flashd with NO internet: they fetch manifests + firmware
# from a mirror on the ground station over LAN (flashd `url` sources). This
# script assembles such a mirror and serves it ON DEMAND — it is NOT a
# persistent service. Run it when you want the mirror up; Ctrl-C to stop.
#
# Waybeam firmware is pulled from a published GitHub release (or local staging)
# and the manifest's image URLs are rewritten to point at THIS mirror, so a
# LAN-only vehicle can download them. OpenIPC nightly can be added as a second,
# sha-less (Option B) source.
#
# On an air-gapped ground station (e.g. the RK3566 with no internet), assemble
# the mirror on a machine that CAN reach GitHub, rsync the --dir across, then
# run this script there with --no-assemble to just serve it.
#
# Usage:
#   ./scripts/serve-mirror.sh [options]
#
# Options:
#   --dir DIR          Mirror directory (default: ./mirror)
#   --host IP          LAN IP the vehicle reaches this host at (default: auto-detect)
#   --port PORT        HTTP port (default: 8099)
#   --release TAG      Waybeam release tag to mirror (default: latest)
#   --repo SLUG        Waybeam release repo (default: snokvist/waybeam-releases)
#   --from-staging     Build the waybeam manifest from local staging/ instead of a release
#   --openipc          Also build an OpenIPC nightly (sha-less) manifest
#   --openipc-boards "ssc338q ssc30kq"   Boards to include (default: ssc338q ssc30kq ssc378qe)
#   --cache-openipc    Download OpenIPC images into the mirror + localise their URLs
#                      (heavy — dozens of ~10 MB files; otherwise OpenIPC image
#                       URLs stay on github.com and need vehicle internet to flash)
#   --no-assemble      Skip (re)building manifests; just serve an existing --dir
#   --no-serve         Assemble the mirror but do not start the HTTP server
#
# Requires: jq, python3; gh (for --release); curl (for --openipc).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

DIR="${REPO_DIR}/mirror"
HOST=""
PORT="8099"
RELEASE="latest"
REPO_SLUG="snokvist/waybeam-releases"
FROM_STAGING=false
DO_OPENIPC=false
OPENIPC_BOARDS="ssc338q ssc30kq ssc378qe"
CACHE_OPENIPC=false
ASSEMBLE=true
SERVE=true
OPENIPC_REPO="OpenIPC/builder"
OPENIPC_TAG="nightly"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)            DIR="$2"; shift 2 ;;
        --host)           HOST="$2"; shift 2 ;;
        --port)           PORT="$2"; shift 2 ;;
        --release)        RELEASE="$2"; shift 2 ;;
        --repo)           REPO_SLUG="$2"; shift 2 ;;
        --from-staging)   FROM_STAGING=true; shift ;;
        --openipc)        DO_OPENIPC=true; shift ;;
        --openipc-boards) OPENIPC_BOARDS="$2"; shift 2 ;;
        --cache-openipc)  DO_OPENIPC=true; CACHE_OPENIPC=true; shift ;;
        --no-assemble)    ASSEMBLE=false; shift ;;
        --no-serve)       SERVE=false; shift ;;
        -h|--help)        sed -n '2,40p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

[ -z "$HOST" ] && HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOST" ] && { echo "Could not auto-detect --host; pass it explicitly." >&2; exit 1; }
BASE="http://${HOST}:${PORT}"

command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

# --- assemble -----------------------------------------------------------------
if $ASSEMBLE; then
    mkdir -p "$DIR"

    echo "[mirror] Assembling into ${DIR} (advertised base: ${BASE})"

    # --- Waybeam source -------------------------------------------------------
    if $FROM_STAGING; then
        echo "[mirror] waybeam: from local staging/"
        cp -f "${REPO_DIR}/staging/"openipc.*-waybeam-*.tgz "$DIR/" 2>/dev/null || {
            echo "  no openipc.*-waybeam-*.tgz in staging/ — run collect.sh first" >&2; exit 1; }
        "${SCRIPT_DIR}/gen-manifest.sh" --staging "$DIR" --tag local \
            --version "$(date +%Y.%m.%d)" --out "$DIR/manifest-waybeam.json" >/dev/null
    else
        command -v gh >/dev/null || { echo "gh required for --release (or use --from-staging)" >&2; exit 1; }
        local_tag="$RELEASE"
        if [ "$local_tag" = "latest" ]; then
            local_tag="$(gh release view --repo "$REPO_SLUG" --json tagName --jq .tagName)"
        fi
        echo "[mirror] waybeam: downloading release ${local_tag} from ${REPO_SLUG}"
        gh release download "$local_tag" --repo "$REPO_SLUG" --dir "$DIR" --clobber \
            --pattern 'openipc.*-waybeam-*.tgz' --pattern 'manifest.json'
        # Rewrite the release manifest's GitHub image URLs to point at this mirror.
        sed "s#https://github.com/${REPO_SLUG}/releases/download/${local_tag}/#${BASE}/#g" \
            "$DIR/manifest.json" > "$DIR/manifest-waybeam.json"
    fi
    echo "[mirror] waybeam manifest: $(jq '.images|length' "$DIR/manifest-waybeam.json") image(s)"

    # --- OpenIPC nightly source (optional) ------------------------------------
    if $DO_OPENIPC; then
        command -v curl >/dev/null || { echo "curl required for --openipc" >&2; exit 1; }
        echo "[mirror] openipc: building sha-less nightly manifest for: ${OPENIPC_BOARDS}"
        board_re="$(echo "$OPENIPC_BOARDS" | tr ' ' '|')"
        ndate="$(gh api "repos/${OPENIPC_REPO}/releases/tags/${OPENIPC_TAG}" --jq '.published_at' 2>/dev/null | cut -dT -f1 | tr '-' '.')"
        [ -z "$ndate" ] && ndate="$(date +%Y.%m.%d)"
        imgs='[]'
        while IFS=$'\t' read -r name size; do
            [ -n "$name" ] || continue
            x="${name%.tgz}"
            if [ "${name#openipc.}" != "$name" ]; then
                y="${x#openipc.}"; board="${y%%-*}"; rest="${y#*-}"; flash="${rest%%-*}"; profile="${rest#*-}"
            else
                board="${x%%_*}"; flash="${x##*-}"; profile="${x#*_}"; profile="${profile%-*}"
            fi
            case "$flash" in nor|nand) ;; *) flash="" ;; esac
            url="https://github.com/${OPENIPC_REPO}/releases/download/${OPENIPC_TAG}/${name}"
            if $CACHE_OPENIPC; then
                echo "  caching ${name}"
                curl -fsSL --max-time 180 -o "$DIR/$name" "$url"
                url="${BASE}/${name}"
            fi
            imgs="$(echo "$imgs" | jq \
                --arg id "openipc-${x}-${ndate}" --arg board "$board" --arg flash "$flash" \
                --arg ver "$ndate" --arg url "$url" --argjson size "${size:-0}" \
                --arg notes "OpenIPC nightly · ${profile}" \
                '. + [{id:$id,board:$board,flash:$flash,role:"",version:$ver,channel:"stable",url:$url,sha256:"",size:$size,notes:$notes}]')"
        done < <(gh api "repos/${OPENIPC_REPO}/releases/tags/${OPENIPC_TAG}" \
                    --jq ".assets[]|select(.name|test(\"\\\\.tgz\$\"))|select(.name|test(\"${board_re}\"))|\"\\(.name)\t\\(.size)\"")
        jq -n --argjson images "$imgs" '{schema:1,vendor:"",images:$images}' > "$DIR/manifest-openipc.json"
        echo "[mirror] openipc manifest: $(jq '.images|length' "$DIR/manifest-openipc.json") image(s)$($CACHE_OPENIPC && echo ' (cached locally)' || echo ' (images on github.com — needs vehicle internet to flash)')"
    fi
fi

[ -f "$DIR/manifest-waybeam.json" ] || { echo "No mirror in ${DIR} (run without --no-assemble first)." >&2; exit 1; }

# --- vehicle sources.json snippet --------------------------------------------
SRC_OPENIPC=""
[ -f "$DIR/manifest-openipc.json" ] && SRC_OPENIPC=",
    { \"id\": \"openipc-nightly\", \"label\": \"OpenIPC (nightly)\", \"type\": \"url\", \"url\": \"${BASE}/manifest-openipc.json\", \"channel\": \"stable\", \"priority\": 0 }"
cat <<SNIP

=== Put this in /etc/flashd/sources.json on the vehicle ===
{ "sources": [
    { "id": "waybeam-stable", "label": "Waybeam (stable)", "type": "url", "url": "${BASE}/manifest-waybeam.json", "channel": "stable", "priority": 10 }${SRC_OPENIPC}
] }
$( [ -f "$DIR/manifest-openipc.json" ] && echo "(OpenIPC images are sha-less → set \"require_sha256\": false in /etc/flashd.json)" )
===========================================================
SNIP

# --- serve --------------------------------------------------------------------
if $SERVE; then
    echo "[mirror] serving ${DIR} on ${BASE}  (Ctrl-C to stop)"
    cd "$DIR"
    exec python3 -m http.server "$PORT" --bind 0.0.0.0
fi
