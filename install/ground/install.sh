#!/bin/bash
#
# Deploy Waybeam ground station binary to RK3566 target.
#
# Usage: ./install/ground/install.sh [staging-dir] [ground-ip]
#
# Deploys: waybeam_hub (ground build with integrated pixelpilot)
# Target: Rockchip RK3566 (aarch64 Linux)

set -euo pipefail

STAGING="${1:-staging}"
GROUND_IP="${2:-192.168.2.20}"
SSH_USER="root"

if [ ! -d "$STAGING" ]; then
    echo "Error: staging directory '${STAGING}' not found"
    echo "Usage: $0 [staging-dir] [ground-ip]"
    exit 1
fi

echo "=== Deploying to ground station @ ${GROUND_IP} ==="

deploy() {
    local src="$1"
    local dst="$2"
    local mode="${3:-0755}"

    if [ ! -f "$src" ]; then
        echo "  SKIP $(basename "$src") (not found)"
        return
    fi

    echo "  -> $(basename "$src") => ${dst}"
    scp "$src" "${SSH_USER}@${GROUND_IP}:${dst}"
    ssh "${SSH_USER}@${GROUND_IP}" "chmod ${mode} ${dst}"
}

# Ground binary (from CI or extracted from tarball)
echo "[binaries]"
if [ -f "${STAGING}/waybeam_hub_ground" ]; then
    deploy "${STAGING}/waybeam_hub_ground" "/usr/bin/waybeam_hub"
elif [ -f "${STAGING}/waybeam-hub-ground-aarch64.tar.gz" ]; then
    echo "  Extracting waybeam-hub-ground-aarch64.tar.gz"
    TMP=$(mktemp -d)
    tar xzf "${STAGING}/waybeam-hub-ground-aarch64.tar.gz" -C "$TMP"
    deploy "${TMP}/waybeam_hub" "/usr/bin/waybeam_hub"
    rm -rf "$TMP"
else
    echo "  ERROR: No ground binary found in staging/"
    echo "  Expected: waybeam_hub_ground or waybeam-hub-ground-aarch64.tar.gz"
    exit 1
fi

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Restart service:"
echo "  ssh ${SSH_USER}@${GROUND_IP} 'killall waybeam_hub; /etc/init.d/S97waybeam-hub restart'"
