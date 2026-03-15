# Waybeam Releases

Pre-built binaries and firmware for the
[Waybeam FPV ecosystem](https://github.com/snokvist/waybeam-coordination).

Download the latest release from the
[Releases page](https://github.com/snokvist/waybeam-releases/releases).

## What's included

### Vehicle binaries (SigmaStar Infinity6E — ARM)

| Binary | Source repo | Description |
|---|---|---|
| `waybeam_hub` | [waybeam-hub](https://github.com/snokvist/waybeam-hub) | Modular C daemon: OSD, menu, WebUI, telemetry, PWM, sync |
| `json_cli` | [waybeam-hub](https://github.com/snokvist/waybeam-hub) | JSON config query/edit tool |
| `venc` | [venc_star6e](https://github.com/OpenIPC/waybeam_venc) | H.265 video encoder/streamer (star6e and maruko builds) |
| `waybeam-pwm` | [infinity6e-pwm](https://github.com/snokvist/infinity6e-pwm) | CRSF-to-servo PWM bridge |
| `ip2uart` | [ip2uart](https://github.com/snokvist/ip2uart) | UART-to-UDP bridge (CRSF/MSP/MAVLink) |
| `waybeam_osd` | [waybeam_osd](https://github.com/snokvist/waybeam_osd) | LVGL transparent OSD overlay |
| `osd_send` | [waybeam_osd](https://github.com/snokvist/waybeam_osd) | OSD metrics sender utility |

### Ground station binaries (Rockchip RK3566 — aarch64)

| Binary | Source repo | Description |
|---|---|---|
| `waybeam_hub` | [waybeam-hub](https://github.com/snokvist/waybeam-hub) | Ground station build with integrated pixelpilot |

### Android

| Artifact | Source repo | Description |
|---|---|---|
| `waybeam-<version>.apk` | [Waybeam-android](https://github.com/snokvist/Waybeam-android) | FPV ground station app (H.264/H.265 decode, CRSF, recording) |

### ESP32 firmware

| Artifact | Source repo | Description |
|---|---|---|
| `hdzero-headtracker.bin` | [esp32-supermini-projects](https://github.com/snokvist/esp32-supermini-projects) | HDZero PPM-to-CRSF bridge + BLE gamepad + servo PWM |

### Full firmware images (from OpenIPC builder)

Complete rootfs + kernel images for supported SoCs and WiFi regions.

| SoC | Variants | Contents |
|---|---|---|
| SSC338Q | au, bu, cu, eu | `rootfs.squashfs`, `uImage`, firmware tarball |
| SSC30KQ | au, bu, cu, eu | `rootfs.squashfs`, `uImage`, firmware tarball |
| SSC378QE | au, bu, cu, eu | `rootfs.squashfs`, `uImage`, firmware tarball |

WiFi region variants:
- **au** — Australia / New Zealand
- **bu** — Brazil
- **cu** — China
- **eu** — Europe (default for most users)

### Configs and support files

Each release also includes:
- `waybeam_vehicle.conf` — default vehicle configuration
- `waybeam_osd.json` — OSD layout configuration
- `waybeam_vehicle.html` — WebUI page
- `S97waybeam-hub` — init script for waybeam-hub
- `S95venc` — init script for venc
- Sensor tuning profiles (IMX335, IMX415)

## Release naming

Releases are tagged as `vX.Y.Z` (e.g. `v0.5.0`).

Asset naming convention:
```
waybeam-hub-vehicle-arm.tar.gz        # Vehicle hub + config + web + init
waybeam-hub-ground-aarch64.tar.gz     # Ground hub (integrated pixelpilot)
venc-star6e-arm.tar.gz                # Video encoder (star6e)
venc-maruko-arm.tar.gz                # Video encoder (maruko)
waybeam-android-vX.Y.Z.apk           # Android app
hdzero-headtracker-esp32c3.bin        # ESP32 firmware
firmware-ssc338q-eu.tgz              # Full firmware image
```

## Quick install

### Vehicle (SigmaStar)

```bash
# From this repo's install scripts:
./install/vehicle/install.sh <release-dir> [vehicle-ip]

# Or manually:
scp -O waybeam_hub root@192.168.2.10:/usr/bin/
scp -O venc root@192.168.2.10:/usr/bin/
ssh root@192.168.2.10 "killall waybeam_hub; /etc/init.d/S97waybeam-hub restart"
```

### Ground station (RK3566)

```bash
./install/ground/install.sh <release-dir> [ground-ip]

# Or manually:
scp waybeam_hub root@192.168.2.20:/usr/bin/
ssh root@192.168.2.20 "killall waybeam_hub; /etc/init.d/S97waybeam-hub restart"
```

### Android

Transfer the APK to your device and install, or use:
```bash
adb install waybeam-vX.Y.Z.apk
```

## Building from source

This repo distributes pre-built binaries only. To build from source, see the
individual repositories linked in the table above, or the
[waybeam-coordination](https://github.com/snokvist/waybeam-coordination) repo
for the full build matrix.

## License

All Waybeam binaries are released under the
[Autod Personal Use License](https://github.com/snokvist/waybeam-coordination/blob/main/LICENSE).
