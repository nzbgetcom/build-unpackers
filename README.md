# build-unpackers

Build and package static `unrar` and `7zip` (`7za`) binaries used by NZBGet across multiple platforms and architectures.

Linux, Android, and FreeBSD are cross-compiled in the [`nzbget-musl-builder`](https://github.com/nzbgetcom/nzbget-musl-builder) images. Windows and macOS are official prebuilt binaries, repackaged on the host.

Output archives are written to `./build/` (the directory is wiped and recreated on every run).

## Images

Images are published at `ghcr.io/nzbgetcom/nzbget-musl-builder`. The tag suffix is the image version (`1.0` today). Each image is `linux/amd64`.

| Tag | What it contains |
|---|---|
| `linux-<arch>-1.0` | Musl GCC for one of `armel`, `armhf`, `aarch64`, `i686`, `x86_64`, `riscv64`, `ppc6xx` |
| `android-1.0` | Android LLVM, Bionic sysroot, and static libc++ for `arm64`, `armv7`, `x86_64`, `x86` |
| `freebsd-<arch>-1.0` | FreeBSD 13 sysroot for `x86_64` or `aarch64`, plus host Clang 19 |
| `all-1.0` | Every toolchain above |

Toolchains live at `/opt/nzbget/linux/<arch>`, `/opt/nzbget/android`, and `/opt/nzbget/freebsd`. A per-arch image only contains that one toolchain, so set `PLATFORMS` and the matching arch list. `:all-1.0` can build every cross target in one run.

## Local builds with Docker

`--platform linux/amd64` matters on an Arm host. `-u` keeps the files in `build/` owned by you.

One Linux architecture, using the image that contains only that toolchain:

```bash
docker run --rm --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e PLATFORMS=linux \
  -e LINUX_ARCHS=x86_64 \
  -v "$PWD":/src -w /src \
  ghcr.io/nzbgetcom/nzbget-musl-builder:linux-x86_64-1.0 \
  ./build.sh
```

Several Linux architectures, or any mix of Linux, Android, and FreeBSD, using the image that contains every toolchain:

```bash
docker run --rm --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e PLATFORMS="linux android freebsd" \
  -e LINUX_ARCHS="x86_64 aarch64" \
  -e ANDROID_ARCHS="aarch64-ndk armhf-ndk" \
  -e FREEBSD_ARCHS=x86_64-bsd \
  -e UNPACKERS=unrar \
  -v "$PWD":/src -w /src \
  ghcr.io/nzbgetcom/nzbget-musl-builder:all-1.0 \
  ./build.sh
```

Android only. This image already has all four architectures:

```bash
docker run --rm --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e PLATFORMS=android \
  -v "$PWD":/src -w /src \
  ghcr.io/nzbgetcom/nzbget-musl-builder:android-1.0 \
  ./build.sh
```

One FreeBSD architecture:

```bash
docker run --rm --platform linux/amd64 \
  -u "$(id -u):$(id -g)" \
  -e PLATFORMS=freebsd \
  -e FREEBSD_ARCHS=aarch64-bsd \
  -v "$PWD":/src -w /src \
  ghcr.io/nzbgetcom/nzbget-musl-builder:freebsd-aarch64-1.0 \
  ./build.sh
```

Windows and macOS do not use these images. They need `unrar`, `zip`, `7z`, and `llvm-lipo-18` on the host:

```bash
sudo apt-get update && sudo apt-get install -y \
  curl tar zip unrar p7zip-full xz-utils llvm-18

PLATFORMS="windows macos" ./build.sh
```

The same script runs directly on the host when the toolchains are installed at the image paths (`/opt/nzbget/...`). Override those paths with `NZBGET_LINUX_TOOLCHAIN_DIR`, `NZBGET_ANDROID_TOOLCHAIN_DIR`, and `FREEBSD_PREFIX`.

## Archive names

| Platform | Build target | Archive |
|---|---|---|
| Linux | `x86_64`, `aarch64`, `armhf`, `armel`, `i686`, `ppc6xx`, `riscv64` | `unrar-<arch>.tar.gz`, `7zip-<arch>.tar.gz` |
| Android | `i686-ndk`, `x86_64-ndk`, `armhf-ndk`, `aarch64-ndk` | `unrar-<arch>.tar.gz`, `7zip-<arch>.tar.gz` |
| FreeBSD | `x86_64-bsd`, `aarch64-bsd` | `unrar-<arch>.tar.gz`, `7zip-<arch>.tar.gz` |
| Windows | | `unrar-windows-x64.zip`, `7zip-windows-x86.zip`, `7zip-windows-x64.zip` |
| macOS | | `unrar-macos-arm64.tar.gz`, `unrar-macos-x64.tar.gz`, `unrar-macos-universal.tar.gz`, `7zip-macos-universal.tar.gz` |

## Configuration (environment variables)

| Variable | Default | Description |
|---|---|---|
| `UNRAR_VERSION` | `7.23` | Version string used for downloaded RARLAB unrar/WinRAR binaries (Windows/macOS). |
| `UNRAR_SRC_VERSION` | `7.2.7` | Version of the `unrarsrc` tarball to build from source (Linux/Android/FreeBSD). |
| `ZIP7_VERSION` | `26.03` | Version of 7-Zip to build from source or download prebuilt. |
| `PLATFORMS` | `linux android freebsd windows macos` | Space-separated list of platforms to process. |
| `UNPACKERS` | `unrar 7zip` | Space-separated list of unpackers to build/download. Valid values: `unrar`, `7zip`. |
| `LINUX_ARCHS` | `armel armhf aarch64 i686 x86_64 riscv64 ppc6xx` | Linux architectures. Each one needs that arch in the image. |
| `ANDROID_ARCHS` | `i686-ndk x86_64-ndk armhf-ndk aarch64-ndk` | Android architectures. |
| `FREEBSD_ARCHS` | `x86_64-bsd aarch64-bsd` | FreeBSD architectures. |
| `NZBGET_LINUX_TOOLCHAIN_DIR` | `/opt/nzbget/linux` | Linux musl toolchain root. |
| `NZBGET_ANDROID_TOOLCHAIN_DIR` | `/opt/nzbget/android` | Android LLVM / sysroot / libc++ root. |
| `FREEBSD_PREFIX` | `/opt/nzbget/freebsd` | FreeBSD sysroot root (`sysroot-<arch>`). |

## Reusable GitHub Actions workflow

[`.github/workflows/build.yml`](.github/workflows/build.yml) is a reusable workflow (`workflow_call`) and can also be started by hand (`workflow_dispatch`).

Linux, Android, and FreeBSD jobs run inside the matching musl-builder image. Windows and macOS jobs run on `ubuntu-24.04` and install the packaging tools there.

### Inputs

| Input | Default | Description |
|---|---|---|
| `unpackers` | `"unrar 7zip"` | Space-separated list of unpackers. Valid values: `unrar`, `7zip`. |
| `unrar-version` | `"7.23"` | RARLAB version for Windows/macOS binaries. |
| `unrar-src-version` | `"7.2.7"` | `unrarsrc` version built from source. |
| `zip7-version` | `"26.03"` | 7-Zip version. |
| `platforms` | `"linux android freebsd windows macos"` | Platforms to process. |
| `linux-archs` | `"armel armhf aarch64 i686 x86_64 riscv64 ppc6xx"` | Linux architectures. |
| `android-archs` | `"i686-ndk x86_64-ndk armhf-ndk aarch64-ndk"` | Android architectures. |
| `freebsd-archs` | `"x86_64-bsd aarch64-bsd"` | FreeBSD architectures. The image tag drops the `-bsd` suffix (`freebsd-x86_64-1.0`). |
| `musl-builder-version` | `"1.0"` | Tag suffix of `ghcr.io/nzbgetcom/nzbget-musl-builder`. |
| `release-tag` | `""` | When set, publishes a GitHub release with this tag. Empty skips the release. |

### Example: calling it from another repository

```yaml
name: build unrar

on:
  workflow_dispatch:

jobs:
  build-unrar:
    uses: nzbgetcom/build-unpackers/.github/workflows/build.yml@main
    permissions:
      contents: write
      actions: write
    with:
      unpackers: unrar
      unrar-version: "7.23"
      unrar-src-version: "7.2.7"
      musl-builder-version: "1.0"
      release-tag: v7.23
```
