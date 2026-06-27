#!/bin/bash
#
# build-components.sh — cross-compile the waybeam *vehicle* components from
# their sibling repos and stage them as release tarballs for a waybeam-releases
# release.
#
# These are the prebuilt binaries the `builder` repo vendors (its package .mk
# files download `<name>-arm.tar.gz` / `<name>-vehicle-arm.tar.gz` from a
# waybeam-releases release tag). The firmware build then unpacks them into the
# rootfs. See the end-to-end runbook in the coordination repo:
#   docs/release-vehicle-firmware.md
#
# Buildroot strips ONE leading path component from a vendored tarball, so every
# tarball is wrapped as `<pkg>-<version>/<binary>` (the binary lands at the
# package root after the strip). KEEP THAT SHAPE or the install copies a
# directory instead of the binary.
#
# Usage:
#   ./scripts/build-components.sh --version v0.8.0 [flashd hub venc wfb-air]
#   ./scripts/build-components.sh --version v0.8.0            # all four
#
# Components default to all four. Name a subset to build only those.
# Output: staging/<...>.tar.gz . Upload with `gh release upload <tag> ... --clobber`.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"          # waybeam-releases/
SIBLINGS="$(cd "$REPO_DIR/.." && pwd)"            # coordination/  (sibling repos live here)
STAGING="$REPO_DIR/staging"

# OpenIPC Infinity6E (SigmaStar) cross toolchain. The hub repo ships a
# self-contained copy; reuse its gcc for flashd. NEVER the system
# arm-linux-gnueabihf-gcc — wrong libc/ABI for these boards.
TOOLCHAIN_BIN="${TOOLCHAIN_BIN:-$SIBLINGS/waybeam-hub/toolchain/sigmastar-infinity6e/bin}"
ARM_GCC="$TOOLCHAIN_BIN/arm-openipc-linux-gnueabihf-gcc"
ARM_STRIP="$TOOLCHAIN_BIN/arm-openipc-linux-gnueabihf-strip"

VERSION=""
COMPONENTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        flashd|hub|venc|wfb-air) COMPONENTS+=("$1"); shift ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done
[ -n "$VERSION" ] || { echo "Error: --version is required (e.g. --version v0.8.0)" >&2; exit 2; }
[ ${#COMPONENTS[@]} -gt 0 ] || COMPONENTS=(flashd hub venc wfb-air)

mkdir -p "$STAGING"
WRAP="$(mktemp -d)"
trap 'rm -rf "$WRAP"' EXIT

# wrap <repo-relative-binary-path> <tarball-name> <pkg-dirname> <dest-binary-name>
wrap() {
    local binpath="$1" tarname="$2" pkgdir="$3" destbin="$4"
    [ -f "$binpath" ] || { echo "  ! built binary missing: $binpath" >&2; return 1; }
    rm -rf "$WRAP/$pkgdir"; mkdir -p "$WRAP/$pkgdir"
    cp "$binpath" "$WRAP/$pkgdir/$destbin"
    # Deterministic tarball: fixed mtime/owner + sorted names + gzip -n (no
    # name/timestamp) so an unchanged binary yields a byte-identical tarball
    # (stable sha256 across re-runs). The binary itself is reproducible.
    tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner \
        -C "$WRAP" -cf - "$pkgdir" | gzip -n > "$STAGING/$tarname"
    echo "  + staging/$tarname  ($(tar tzf "$STAGING/$tarname" | tr '\n' ' '))"
    echo "    sha256 $(sha256sum "$STAGING/$tarname" | awk '{print $1}')"
}

build_flashd() {
    echo "== flashd =="
    local d="$SIBLINGS/flashd"
    ( cd "$d" && make clean >/dev/null 2>&1 || true
      make CC="$ARM_GCC" >/dev/null
      "$ARM_STRIP" flashd )
    echo "  flashd @ $(git -C "$d" rev-parse --short HEAD)"
    wrap "$d/flashd" "flashd-arm.tar.gz" "flashd-$VERSION" "flashd"
}

build_hub() {
    echo "== waybeam-hub (vehicle_wfb_ng) =="
    local d="$SIBLINGS/waybeam-hub"
    ( cd "$d" && rm -rf build/vehicle_wfb_ng && make vehicle_wfb_ng >/dev/null )
    echo "  hub @ $(git -C "$d" rev-parse --short HEAD)"
    wrap "$d/build/vehicle_wfb_ng/waybeam_hub" "waybeam-hub-vehicle-arm.tar.gz" "waybeam-hub-$VERSION" "waybeam_hub"
}

build_venc() {
    echo "== waybeam_venc (star6e) =="
    local d="$SIBLINGS/waybeam_venc"
    ( cd "$d" && make build SOC_BUILD=star6e >/dev/null )
    echo "  venc @ $(git -C "$d" rev-parse --short HEAD)"
    wrap "$d/out/star6e/waybeam" "venc-star6e-arm.tar.gz" "venc-star6e-$VERSION" "waybeam"
}

build_wfb_air() {
    echo "== waybeam_wfb_ng (wfb-air mega) =="
    local d="$SIBLINGS/waybeam_wfb_ng"
    # Prereq: cross libsodium/libpcap built once by wfb-ng/build-armv7.sh.
    [ -d "$d/wfb-ng/build-armv7" ] || ( cd "$d/wfb-ng" && ./build-armv7.sh >/dev/null 2>&1 || true )
    ( cd "$d" && make -C vehicle mega >/dev/null )
    echo "  wfb-air @ $(git -C "$d" rev-parse --short HEAD)"
    wrap "$d/vehicle/build/wfb-air" "wfb-air-arm.tar.gz" "wfb-air-$VERSION" "wfb-air"
}

[ -x "$ARM_GCC" ] || { echo "Error: cross gcc not found at $ARM_GCC (set TOOLCHAIN_BIN)" >&2; exit 1; }

echo "Building components for $VERSION: ${COMPONENTS[*]}"
echo "Toolchain: $ARM_GCC"
for c in "${COMPONENTS[@]}"; do
    case "$c" in
        flashd)  build_flashd ;;
        hub)     build_hub ;;
        venc)    build_venc ;;
        wfb-air) build_wfb_air ;;
    esac
done
echo
echo "Done. Tarballs staged in $STAGING. Next:"
echo "  gh release upload $VERSION staging/*-arm.tar.gz --clobber"
echo "  (then rebuild firmware in ../builder, regen manifest, upload — see"
echo "   coordination docs/release-vehicle-firmware.md)"
