#!/bin/bash
#
# Collect Waybeam binaries from local builds into staging/
#
# Usage: ./scripts/collect.sh [options]
#
# Options:
#   --builder-dir DIR        Path to OpenIPC builder (default: ../builder)
#   --coordination-dir DIR   Path to waybeam-coordination (default: ../waybeam-coordination)
#   --android-dir DIR        Path to Waybeam-android (default: auto-detect)
#   --esp32-dir DIR          Path to esp32-supermini-projects (default: auto-detect)
#   --device DEVICE          Builder device name (default: ssc338q_waybeam_eu)
#   --version VERSION        Version string for naming (default: dev)
#   --ground-zip FILE        Path to ground build zip (from CI, fallback)
#   --hub-dir DIR            Path to waybeam-hub (default: auto-detect)
#   --sbc-dir DIR            Path to sbc-groundstations (default: auto-detect)
#   --clean                  Remove staging/ before collecting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
STAGING="${REPO_DIR}/staging"

# Defaults
BUILDER_DIR="${REPO_DIR}/../builder"
COORDINATION_DIR="${REPO_DIR}/../waybeam-coordination"
ANDROID_DIR=""
ESP32_DIR=""
HUB_DIR=""
SBC_DIR=""
DEVICE="ssc338q_waybeam_eu"
VERSION="dev"
GROUND_ZIP=""
CLEAN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --builder-dir)    BUILDER_DIR="$2"; shift 2 ;;
        --coordination-dir) COORDINATION_DIR="$2"; shift 2 ;;
        --android-dir)    ANDROID_DIR="$2"; shift 2 ;;
        --esp32-dir)      ESP32_DIR="$2"; shift 2 ;;
        --hub-dir)        HUB_DIR="$2"; shift 2 ;;
        --sbc-dir)        SBC_DIR="$2"; shift 2 ;;
        --device)         DEVICE="$2"; shift 2 ;;
        --version)        VERSION="$2"; shift 2 ;;
        --ground-zip)     GROUND_ZIP="$2"; shift 2 ;;
        --clean)          CLEAN=true; shift ;;
        -h|--help)
            head -10 "$0" | grep '^#' | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Auto-detect android/esp32 dirs from coordination submodules
if [ -z "$ANDROID_DIR" ]; then
    for d in "${COORDINATION_DIR}/Waybeam-android" "${REPO_DIR}/../Waybeam-android"; do
        [ -d "$d" ] && ANDROID_DIR="$d" && break
    done
fi
if [ -z "$ESP32_DIR" ]; then
    for d in "${COORDINATION_DIR}/esp32-supermini-projects" "${REPO_DIR}/../esp32-supermini-projects"; do
        [ -d "$d" ] && ESP32_DIR="$d" && break
    done
fi
if [ -z "$HUB_DIR" ]; then
    for d in "${COORDINATION_DIR}/waybeam-hub" "${REPO_DIR}/../waybeam-hub"; do
        [ -d "$d" ] && HUB_DIR="$d" && break
    done
fi
if [ -z "$SBC_DIR" ]; then
    for d in "${COORDINATION_DIR}/sbc-groundstations" "${REPO_DIR}/../sbc-groundstations"; do
        [ -d "$d" ] && SBC_DIR="$d" && break
    done
fi

echo "=== Waybeam Release Collector ==="
echo "Builder:      ${BUILDER_DIR}"
echo "Coordination: ${COORDINATION_DIR}"
echo "Hub:          ${HUB_DIR:-not found}"
echo "SBC Ground:   ${SBC_DIR:-not found}"
echo "Android:      ${ANDROID_DIR:-not found}"
echo "ESP32:        ${ESP32_DIR:-not found}"
echo "Device:       ${DEVICE}"
echo "Version:      ${VERSION}"
echo ""

if $CLEAN && [ -d "$STAGING" ]; then
    echo "Cleaning staging/"
    rm -rf "$STAGING"
fi
mkdir -p "$STAGING"

collected=0

# --- Builder: firmware images ---
if [ -d "${BUILDER_DIR}/archive/${DEVICE}" ]; then
    # Find latest build by timestamp directory name
    LATEST=$(ls -1d "${BUILDER_DIR}/archive/${DEVICE}"/*/ 2>/dev/null | sort | tail -1)
    if [ -n "$LATEST" ]; then
        SOC=$(echo "$DEVICE" | cut -d_ -f1)
        VARIANT=$(echo "$DEVICE" | rev | cut -d_ -f1 | rev)
        echo "[firmware] Collecting from ${LATEST}"
        for f in "${LATEST}"/*; do
            [ -f "$f" ] || continue
            cp "$f" "$STAGING/"
            collected=$((collected + 1))
        done
        # Create a tarball of the firmware
        FIRMWARE_TGZ="firmware-${SOC}-${VARIANT}.tgz"
        (cd "$LATEST" && tar czf "${STAGING}/${FIRMWARE_TGZ}" .)
        echo "  -> ${FIRMWARE_TGZ}"
    fi
else
    echo "[firmware] No builder archive found for ${DEVICE}, skipping"
fi

# --- Builder: individual vehicle binaries from buildroot output ---
BR_TARGET="${BUILDER_DIR}/openipc/output/target"
if [ -d "$BR_TARGET" ]; then
    echo "[vehicle] Collecting from buildroot output"

    # waybeam_hub + json_cli
    for bin in waybeam_hub json_cli; do
        if [ -f "${BR_TARGET}/usr/bin/${bin}" ]; then
            cp "${BR_TARGET}/usr/bin/${bin}" "${STAGING}/${bin}"
            echo "  -> ${bin}"
            collected=$((collected + 1))
        fi
    done

    # venc
    if [ -f "${BR_TARGET}/usr/bin/venc" ]; then
        cp "${BR_TARGET}/usr/bin/venc" "${STAGING}/venc-star6e"
        echo "  -> venc-star6e"
        collected=$((collected + 1))
    fi

    # waybeam-pwm
    if [ -f "${BR_TARGET}/usr/bin/waybeam-pwm" ]; then
        cp "${BR_TARGET}/usr/bin/waybeam-pwm" "${STAGING}/waybeam-pwm"
        echo "  -> waybeam-pwm"
        collected=$((collected + 1))
    fi

    # Config files
    for f in "${BR_TARGET}/etc/waybeam_hub/waybeam_vehicle.conf" \
             "${BR_TARGET}/etc/venc.json"; do
        if [ -f "$f" ]; then
            cp "$f" "${STAGING}/$(basename "$f")"
            echo "  -> $(basename "$f")"
            collected=$((collected + 1))
        fi
    done

    # Init scripts
    for f in "${BR_TARGET}/etc/init.d/S97waybeam-hub" \
             "${BR_TARGET}/etc/init.d/S95venc"; do
        if [ -f "$f" ]; then
            cp "$f" "${STAGING}/$(basename "$f")"
            echo "  -> $(basename "$f")"
            collected=$((collected + 1))
        fi
    done

    # WebUI
    if [ -f "${BR_TARGET}/var/www/waybeam_vehicle.html" ]; then
        cp "${BR_TARGET}/var/www/waybeam_vehicle.html" "${STAGING}/"
        echo "  -> waybeam_vehicle.html"
        collected=$((collected + 1))
    fi

    # Sensor profiles
    for f in "${BR_TARGET}/etc/sensors/"*.bin; do
        if [ -f "$f" ]; then
            cp "$f" "${STAGING}/$(basename "$f")"
            echo "  -> $(basename "$f")"
            collected=$((collected + 1))
        fi
    done

    # Create vehicle bundle tarball
    echo "[vehicle] Creating waybeam-hub-vehicle-arm.tar.gz"
    VEHICLE_FILES=""
    for f in waybeam_hub json_cli waybeam_vehicle.conf venc.json \
             waybeam_vehicle.html S97waybeam-hub; do
        [ -f "${STAGING}/${f}" ] && VEHICLE_FILES="${VEHICLE_FILES} ${f}"
    done
    if [ -n "$VEHICLE_FILES" ]; then
        (cd "$STAGING" && tar czf waybeam-hub-vehicle-arm.tar.gz $VEHICLE_FILES)
        echo "  -> waybeam-hub-vehicle-arm.tar.gz"
    fi
else
    echo "[vehicle] No buildroot output found, skipping individual binaries"
fi

# --- Ground station binaries (local build preferred, CI zip fallback) ---
#
# Local build uses the sbc-groundstations Buildroot toolchain for aarch64
# and native gcc for x86_64. Requires up-to-date waybeam-hub source.
#
SBC_SYSROOT=""
if [ -n "$SBC_DIR" ]; then
    # Find the Buildroot output directory (try common defconfigs)
    for defconfig in waybeam_radxa3e_defconfig; do
        candidate="${SBC_DIR}/output/${defconfig}"
        if [ -d "$candidate/host/bin" ] && [ -d "$candidate/staging/usr/lib/pkgconfig" ]; then
            SBC_SYSROOT="$candidate"
            break
        fi
    done
fi

GROUND_BUILT=false

# aarch64 ground: local cross-compile
if [ -n "$HUB_DIR" ] && [ -n "$SBC_SYSROOT" ]; then
    CROSS_CC="${SBC_SYSROOT}/host/bin/aarch64-none-linux-gnu-gcc"
    CROSS_STRIP="${SBC_SYSROOT}/host/bin/aarch64-none-linux-gnu-strip"
    CROSS_PKG="${SBC_SYSROOT}/host/bin/pkg-config"
    if [ -x "$CROSS_CC" ] && [ -x "$CROSS_PKG" ]; then
        echo "[ground-aarch64] Building from ${HUB_DIR} using ${SBC_SYSROOT} toolchain"
        (
            cd "$HUB_DIR"
            PKG_CONFIG_SYSROOT_DIR="${SBC_SYSROOT}/staging" \
            PKG_CONFIG_PATH="${SBC_SYSROOT}/staging/usr/lib/pkgconfig" \
            PKG_CONFIG_LIBDIR="${SBC_SYSROOT}/staging/usr/lib/pkgconfig" \
            make ground \
                CC="${CROSS_CC} --sysroot=${SBC_SYSROOT}/staging" \
                PKG_CONFIG="$CROSS_PKG"
        )
        if [ -f "${HUB_DIR}/build/ground/waybeam_hub" ]; then
            GROUND_TMP=$(mktemp -d)
            mkdir -p "${GROUND_TMP}/waybeam-hub-ground-aarch64"
            cp "${HUB_DIR}/build/ground/waybeam_hub" "${GROUND_TMP}/waybeam-hub-ground-aarch64/"
            "$CROSS_STRIP" "${GROUND_TMP}/waybeam-hub-ground-aarch64/waybeam_hub"
            [ -f "${HUB_DIR}/configs/waybeam_ground.conf" ] && \
                cp "${HUB_DIR}/configs/waybeam_ground.conf" "${GROUND_TMP}/waybeam-hub-ground-aarch64/"
            [ -f "${HUB_DIR}/web/waybeam_hub_c.html" ] && \
                cp "${HUB_DIR}/web/waybeam_hub_c.html" "${GROUND_TMP}/waybeam-hub-ground-aarch64/"
            tar czf "${STAGING}/waybeam-hub-ground-aarch64.tar.gz" \
                -C "$GROUND_TMP" waybeam-hub-ground-aarch64/
            rm -rf "$GROUND_TMP"
            echo "  -> waybeam-hub-ground-aarch64.tar.gz"
            collected=$((collected + 1))
            GROUND_BUILT=true
        else
            echo "  [WARN] aarch64 ground build failed"
        fi
    else
        echo "[ground-aarch64] Cross-compiler not found in ${SBC_SYSROOT}, skipping local build"
    fi
fi

# aarch64 ground: CI zip fallback
if ! $GROUND_BUILT && [ -n "$GROUND_ZIP" ] && [ -f "$GROUND_ZIP" ]; then
    echo "[ground-aarch64] Extracting from CI zip ${GROUND_ZIP}"
    GROUND_TMP=$(mktemp -d)
    unzip -q "$GROUND_ZIP" -d "$GROUND_TMP"
    if [ -f "${GROUND_TMP}/waybeam_hub" ]; then
        mkdir -p "${GROUND_TMP}/waybeam-hub-ground-aarch64"
        cp "${GROUND_TMP}/waybeam_hub" "${GROUND_TMP}/waybeam-hub-ground-aarch64/"
        tar czf "${STAGING}/waybeam-hub-ground-aarch64.tar.gz" \
            -C "$GROUND_TMP" waybeam-hub-ground-aarch64/
        echo "  -> waybeam-hub-ground-aarch64.tar.gz (from CI)"
        collected=$((collected + 1))
    fi
    rm -rf "$GROUND_TMP"
elif ! $GROUND_BUILT; then
    echo "[ground-aarch64] No toolchain or CI zip available, skipping"
fi

# x86_64 ground: native build
if [ -n "$HUB_DIR" ] && command -v pkg-config >/dev/null 2>&1 && \
   pkg-config --exists gstreamer-1.0 2>/dev/null; then
    echo "[ground-x86_64] Building natively from ${HUB_DIR}"
    (cd "$HUB_DIR" && make ground_x86)
    if [ -f "${HUB_DIR}/build/ground_x86/waybeam_hub" ]; then
        GROUND_TMP=$(mktemp -d)
        mkdir -p "${GROUND_TMP}/waybeam-hub-ground-x86_64"
        cp "${HUB_DIR}/build/ground_x86/waybeam_hub" "${GROUND_TMP}/waybeam-hub-ground-x86_64/"
        strip "${GROUND_TMP}/waybeam-hub-ground-x86_64/waybeam_hub"
        [ -f "${HUB_DIR}/configs/waybeam_ground.conf" ] && \
            cp "${HUB_DIR}/configs/waybeam_ground.conf" "${GROUND_TMP}/waybeam-hub-ground-x86_64/"
        [ -f "${HUB_DIR}/web/waybeam_hub_c.html" ] && \
            cp "${HUB_DIR}/web/waybeam_hub_c.html" "${GROUND_TMP}/waybeam-hub-ground-x86_64/"
        tar czf "${STAGING}/waybeam-hub-ground-x86_64.tar.gz" \
            -C "$GROUND_TMP" waybeam-hub-ground-x86_64/
        rm -rf "$GROUND_TMP"
        echo "  -> waybeam-hub-ground-x86_64.tar.gz"
        collected=$((collected + 1))
    else
        echo "  [WARN] x86_64 ground build failed"
    fi
else
    echo "[ground-x86_64] GStreamer dev packages not found, skipping"
fi

# --- Android APK ---
if [ -n "$ANDROID_DIR" ] && [ -d "${ANDROID_DIR}/build_archive" ]; then
    echo "[android] Collecting APKs from ${ANDROID_DIR}/build_archive/"
    LATEST_APK=$(ls -1t "${ANDROID_DIR}/build_archive/"*.apk 2>/dev/null | head -1)
    if [ -n "$LATEST_APK" ]; then
        cp "$LATEST_APK" "${STAGING}/"
        echo "  -> $(basename "$LATEST_APK")"
        collected=$((collected + 1))
    fi
else
    echo "[android] No Android build archive found, skipping"
fi

# --- ESP32 firmware ---
if [ -n "$ESP32_DIR" ]; then
    HT_BIN="${ESP32_DIR}/projects/waybeam-connect/.pio/build/esp32c3_supermini/firmware.bin"
    if [ -f "$HT_BIN" ]; then
        echo "[esp32] Collecting waybeam-connect firmware"
        cp "$HT_BIN" "${STAGING}/waybeam-connect-esp32c3.bin"
        echo "  -> waybeam-connect-esp32c3.bin"
        collected=$((collected + 1))
    else
        echo "[esp32] No PlatformIO build output found, skipping"
    fi
else
    echo "[esp32] ESP32 directory not found, skipping"
fi

echo ""
echo "=== Collected ${collected} files into staging/ ==="
ls -la "$STAGING/"
