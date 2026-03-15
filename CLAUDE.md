# Waybeam Releases

Distribution repository for pre-built Waybeam FPV ecosystem binaries.
This repo contains no source code — only release tooling, install scripts,
and GitHub Releases with binary assets.

## Purpose

Single download point for all Waybeam binaries across platforms:
- Vehicle firmware + binaries (SigmaStar ARM, built via OpenIPC builder)
- Ground station binary (RK3566 aarch64, built via GitHub Actions CI)
- Android APK (built via Gradle)
- ESP32 firmware (built via PlatformIO)

## Repository structure

```
waybeam-releases/
  README.md              # User-facing: what's available, install instructions
  CLAUDE.md              # This file: agentic workflow
  scripts/
    collect.sh           # Gather binaries from local builds into staging/
    upload-release.sh    # Create GitHub Release + attach assets via gh CLI
  install/
    vehicle/install.sh   # Deploy binaries to SigmaStar target via scp
    ground/install.sh    # Deploy binaries to RK3566 target via scp
```

Binaries are NOT stored in git. They live in GitHub Releases as attached
assets, downloaded by users from the Releases page.

## Agentic workflow: Creating a release

### 1. Collect binaries

Run `scripts/collect.sh` to gather all built artifacts into `staging/`:

```bash
./scripts/collect.sh [--builder-dir ../builder] [--coordination-dir ../waybeam-coordination]
```

Sources:
- **Builder archive**: `../builder/archive/<device>/<timestamp>/` — firmware images
- **Builder output**: OpenIPC buildroot `output/target/usr/bin/` — individual binaries
- **Android build_archive**: `../Waybeam-android/build_archive/` — APKs
- **waybeam-hub CI**: GitHub Actions artifact from waybeam-hub repo — ground binary
- **ESP32**: PlatformIO `.pio/build/` output — firmware .bin files

The collect script stages everything into `staging/` with the correct
naming convention, ready for upload.

### 2. Upload release

```bash
./scripts/upload-release.sh v0.5.0 [--notes "Release notes here"]
```

This creates a GitHub Release tagged `vX.Y.Z` and attaches all files
from `staging/`.

### 3. Deploy to devices

After downloading a release (or directly from staging):

```bash
./install/vehicle/install.sh staging/ 192.168.2.10
./install/ground/install.sh staging/ 192.168.2.20
```

## Binary sources and build commands

### Vehicle binaries (ARM, cross-compiled via OpenIPC toolchain)

All vehicle binaries are cross-compiled using the OpenIPC Buildroot
toolchain (`arm-openipc-linux-gnueabihf-gcc`). The builder repo handles
this automatically via Buildroot package definitions.

| Binary | Build package | Build trigger |
|---|---|---|
| `waybeam_hub` | `package/waybeam-hub/` | `make waybeam-hub-rebuild` |
| `json_cli` | `package/waybeam-hub/` | Built alongside waybeam_hub |
| `venc` | `package/waybeam-venc-star6e/` | `make waybeam-venc-star6e-rebuild` |
| `waybeam-pwm` | `package/infinity6e-pwm/` | `make infinity6e-pwm-rebuild` |
| sensor bins | `package/waybeam-distribution-star6e/` | Static files, no build |

Full firmware build (kernel + rootfs with all packages):
```bash
cd builder && ./builder.sh
# Select: ssc338q_waybeam_eu (or other variant)
```

### Ground station binary (aarch64, built via GitHub Actions)

The ground waybeam_hub build requires GStreamer, libdrm, Rockchip MPP,
and libudev. It is built by GitHub Actions CI in the waybeam-hub repo.

Fetch the latest CI artifact:
```bash
# Use GitHub API to download (not gh run download — has known bugs)
gh api repos/snokvist/waybeam-hub/actions/artifacts \
  --jq '.artifacts[] | select(.name=="waybeam_hub_ground") | .archive_download_url' \
  | head -1 | xargs -I{} curl -L -H "Authorization: token $(gh auth token)" {} -o ground.zip
unzip ground.zip
```

### Android APK

Built via Gradle in the Waybeam-android repo:
```bash
cd Waybeam-android && ./gradlew assembleRelease
# Output: app/build/outputs/apk/release/
```

Or grab from `build_archive/` if already built.

### ESP32 firmware

Built via PlatformIO in esp32-supermini-projects:
```bash
cd esp32-supermini-projects/projects/waybeam-connect
pio run -e esp32c3_supermini
# Output: .pio/build/esp32c3_supermini/firmware.bin
```

## Asset naming convention

```
waybeam-hub-vehicle-arm.tar.gz
waybeam-hub-ground-aarch64.tar.gz
venc-star6e-arm.tar.gz
venc-maruko-arm.tar.gz
waybeam-pwm-arm
waybeam-android-vX.Y.Z.apk
waybeam-connect-esp32c3.bin
firmware-ssc338q-eu.tgz
firmware-ssc338q-au.tgz
firmware-ssc30kq-eu.tgz
...
```

Tarballs (`.tar.gz`) are used when a binary ships with config files,
init scripts, or web assets. Standalone binaries are uploaded as-is.

## Coordination with other repos

This repo is referenced from
[waybeam-coordination](https://github.com/snokvist/waybeam-coordination).

The release workflow is:
1. Develop and test in individual sub-repos
2. Build via builder (vehicle) or CI (ground/android)
3. Collect and upload here
4. Users download from this repo's Releases page

## Target devices

| Target | IP | SoC | Access |
|---|---|---|---|
| Vehicle | 192.168.2.10 | SSC30KQ (Infinity6E) | `ssh root@` / `scp -O` |
| Ground | 192.168.2.20 | RK3566 | `ssh root@` / `scp` |

Note: Vehicle requires `scp -O` (legacy protocol) due to BusyBox dropbear.

## WiFi region variants

The builder produces firmware for multiple WiFi regulatory domains.
Each variant includes the appropriate WiFi driver and regulatory config:

- `au` — Australia / New Zealand
- `bu` — Brazil
- `cu` — China
- `eu` — Europe (most common)

The variant only affects the full firmware image, not individual binaries.
