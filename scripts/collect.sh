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
#   --ground-zip FILE        Path to ground build zip (from CI)
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

echo "=== Waybeam Release Collector ==="
echo "Builder:      ${BUILDER_DIR}"
echo "Coordination: ${COORDINATION_DIR}"
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

# --- Ground station binary (from CI zip) ---
if [ -n "$GROUND_ZIP" ] && [ -f "$GROUND_ZIP" ]; then
    echo "[ground] Extracting from ${GROUND_ZIP}"
    GROUND_TMP=$(mktemp -d)
    unzip -q "$GROUND_ZIP" -d "$GROUND_TMP"
    if [ -f "${GROUND_TMP}/waybeam_hub" ]; then
        cp "${GROUND_TMP}/waybeam_hub" "${STAGING}/waybeam_hub_ground"
        tar czf "${STAGING}/waybeam-hub-ground-aarch64.tar.gz" \
            -C "$GROUND_TMP" waybeam_hub
        echo "  -> waybeam-hub-ground-aarch64.tar.gz"
        collected=$((collected + 1))
    fi
    rm -rf "$GROUND_TMP"
else
    echo "[ground] No ground build zip provided (use --ground-zip), skipping"
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
