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
| `venc` | [waybeam_venc](https://github.com/OpenIPC/waybeam_venc) | H.265 video encoder/streamer (star6e and maruko builds) |
| `waybeam-pwm` | [infinity6e-pwm](https://github.com/snokvist/infinity6e-pwm) | CRSF-to-servo PWM bridge |

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
| `waybeam-connect.bin` | [esp32-supermini-projects](https://github.com/snokvist/esp32-supermini-projects) | PPM-to-CRSF bridge + BLE gamepad + servo PWM + web config |

### Full firmware images (from OpenIPC builder)

Complete rootfs + kernel images for supported SoCs and WiFi cards.
Tarballs follow OpenIPC's naming grammar: `openipc.<board>-<nor|nand>-waybeam-<wifi>.tgz`.

| SoC | WiFi variants | Tarball example |
|---|---|---|
| SSC338Q | au, bu, cu, eu | `openipc.ssc338q-nor-waybeam-eu.tgz` |
| SSC30KQ | au, bu, cu, eu | `openipc.ssc30kq-nor-waybeam-eu.tgz` |
| SSC378QE | au, bu, cu, eu | `openipc.ssc378qe-nor-waybeam-eu.tgz` |

The `<wifi>` field is the **WiFi card / driver** baked into the image (it
selects the Realtek driver), **not** a geographic region:
- **eu** — rtl88x2eu (RTL8812EU / RTL8822EU)
- **cu** — rtl88x2cu (RTL8812CU / RTL8822CU)
- **au** — rtl8812au family
- **bu** — rtl8812bu family

### flashd manifest

Every release includes `manifest.json` — a [flashd](https://github.com/snokvist/flashd)
schema-1 firmware index describing the flashable camera firmware images in this release.

`flashd` on a Waybeam vehicle reads `manifest.json` automatically when configured with
a `github` source pointing at this repository:

```json
{ "sources": [ { "type": "github", "repo": "snokvist/waybeam-releases", "channel": "stable" } ] }
```

The `version` field inside the manifest uses a date-based scheme (`YYYY.MM.DD`, optionally
`.N` for same-day rebuilds) so `flashd` can correctly determine whether an image is newer
than the device's running firmware.

### Configs and support files

Each release also includes:
- `waybeam_vehicle.conf` — default vehicle configuration
- `venc.json` — video encoder configuration
- `waybeam_vehicle.html` — WebUI page
- `S97waybeam-hub` — init script for waybeam-hub
- `S95venc` — init script for venc
- Sensor tuning profiles (IMX335, IMX415)

## Release naming

Releases are tagged as `vX.Y.Z` (e.g. `v0.5.0`).

Asset naming convention:
```
waybeam-hub-vehicle-arm.tar.gz           # Vehicle hub + config + web + init
waybeam-hub-ground-aarch64.tar.gz        # Ground hub (integrated pixelpilot)
venc-star6e-arm.tar.gz                   # Video encoder (star6e)
venc-maruko-arm.tar.gz                   # Video encoder (maruko)
waybeam-android-vX.Y.Z.apk              # Android app
waybeam-connect-esp32c3.bin              # ESP32 firmware
openipc.ssc338q-nor-waybeam-eu.tgz      # Full firmware (SSC338Q, NOR, rtl88x2eu WiFi)
manifest.json                            # flashd schema-1 firmware index
```

Full firmware images follow OpenIPC's naming grammar:
`openipc.<board>-<nor|nand>-waybeam-<wifi>.tgz` (`<wifi>` = WiFi card/driver shortcode)

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
