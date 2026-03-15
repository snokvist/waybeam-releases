#!/bin/bash
#
# Deploy Waybeam vehicle binaries to SigmaStar target.
#
# Usage: ./install/vehicle/install.sh [staging-dir] [vehicle-ip]
#
# Deploys: waybeam_hub, json_cli, venc, waybeam-pwm, configs, init scripts
# Target: SigmaStar SSC30KQ / SSC338Q (BusyBox dropbear, requires scp -O)

set -euo pipefail

STAGING="${1:-staging}"
VEHICLE_IP="${2:-192.168.2.10}"
SSH_USER="root"

if [ ! -d "$STAGING" ]; then
    echo "Error: staging directory '${STAGING}' not found"
    echo "Usage: $0 [staging-dir] [vehicle-ip]"
    exit 1
fi

echo "=== Deploying to vehicle @ ${VEHICLE_IP} ==="

deploy() {
    local src="$1"
    local dst="$2"
    local mode="${3:-0755}"

    if [ ! -f "$src" ]; then
        echo "  SKIP $(basename "$src") (not found)"
        return
    fi

    echo "  -> $(basename "$src") => ${dst}"
    scp -O "$src" "${SSH_USER}@${VEHICLE_IP}:${dst}"
    ssh "${SSH_USER}@${VEHICLE_IP}" "chmod ${mode} ${dst}"
}

# Binaries
echo "[binaries]"
deploy "${STAGING}/waybeam_hub"   "/usr/bin/waybeam_hub"
deploy "${STAGING}/json_cli"     "/usr/bin/json_cli"
deploy "${STAGING}/venc-star6e"  "/usr/bin/venc"
deploy "${STAGING}/waybeam-pwm"  "/usr/bin/waybeam-pwm"
deploy "${STAGING}/ip2uart"      "/usr/bin/ip2uart"
deploy "${STAGING}/waybeam_osd"  "/usr/bin/waybeam_osd"
deploy "${STAGING}/osd_send"     "/usr/bin/osd_send"

# Config (don't overwrite existing by default)
echo "[configs]"
for conf in waybeam_vehicle.conf venc.json waybeam_osd.json; do
    if [ -f "${STAGING}/${conf}" ]; then
        # Check if config already exists on target
        if ssh "${SSH_USER}@${VEHICLE_IP}" "test -f /etc/${conf}" 2>/dev/null; then
            echo "  KEEP ${conf} (exists on target, use --force to overwrite)"
        else
            deploy "${STAGING}/${conf}" "/etc/${conf}" "0644"
        fi
    fi
done

# WebUI
echo "[web]"
deploy "${STAGING}/waybeam_vehicle.html" "/var/www/waybeam_vehicle.html" "0644"

# Init scripts
echo "[init]"
deploy "${STAGING}/S97waybeam-hub" "/etc/init.d/S97waybeam-hub"
deploy "${STAGING}/S95venc"        "/etc/init.d/S95venc"

# Sensor profiles
echo "[sensors]"
ssh "${SSH_USER}@${VEHICLE_IP}" "mkdir -p /etc/sensors" 2>/dev/null || true
for f in "${STAGING}/"*.bin; do
    [ -f "$f" ] || continue
    deploy "$f" "/etc/sensors/$(basename "$f")" "0644"
done

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Restart services:"
echo "  ssh ${SSH_USER}@${VEHICLE_IP} '/etc/init.d/S95venc restart'"
echo "  ssh ${SSH_USER}@${VEHICLE_IP} '/etc/init.d/S97waybeam-hub restart'"
