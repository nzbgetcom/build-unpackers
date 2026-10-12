# build-unpackers

Build and package static `unrar` and `7zip` (`7za`) binaries used by NZBGet across multiple platforms and architectures.

The script either **cross-compiles from source** (Linux, Android, FreeBSD) or **downloads and repackages official prebuilt binaries** (Windows, macOS), then produces ready-to-ship archives in the `build/` directory.

## Requirements

- `bash`, `curl`, `tar`, `sed`, `make`
- For Windows packaging: `unrar` and `zip` available on `PATH`
- For macOS packaging: `7z` and `llvm-lipo-18` available on `PATH`
- Cross-compilation toolchains available under `/build` (configurable via `BUILDROOT_HOME`):
  - `/build/buildroot/<arch>` - buildroot musl toolchains for Linux targets
  - `/build/android/<arch>` - Android NDK toolchains
  - `/build/freebsd/sysroot-x86_64` and `/build/freebsd/sysroot-aarch64` - FreeBSD sysroots, plus `clang`/`clang++`/`lld` version `FREEBSD_CLANG_VER` on `PATH`

### Installing prerequisites on Ubuntu 24.04

The following installs everything the script needs on Ubuntu 24.04 (`noble`), **excluding** the buildroot/Android NDK cross-toolchains (which are not apt packages and must be set up separately under `$BUILDROOT_HOME`):

```bash
sudo apt-get update && sudo apt-get install -y \
    build-essential \
    curl \
    tar \
    sed \
    zip \
    unrar \
    p7zip-full \
    xz-utils \
    clang-18 \
    lld-18 \
    llvm-18
```

## Usage

```bash
./build.sh
```

All configuration is done via environment variables (see below). For example, to build only 7-Zip for Linux x86_64 and arm64:

```bash
PLATFORMS=linux LINUX_ARCHS="x86_64 aarch64" UNPACKERS=7zip ./build.sh
```

Output archives are written to `./build/` (the directory is wiped and recreated on every run).

## Configuration (environment variables)

| Variable | Default | Description |
|---|---|---|
| `UNRAR_VERSION` | `7.23` | Version string used for downloaded RARLAB unrar/WinRAR binaries (Windows/macOS). |
| `UNRAR_SRC_VERSION` | `7.2.7` | Version of the `unrarsrc` tarball to build from source (Linux/Android/FreeBSD). |
| `ZIP7_VERSION` | `26.02` | Version of 7-Zip to build from source or download prebuilt (used for both source and binary URLs). |
| `PLATFORMS` | `linux android freebsd windows macos` | Space-separated list of platforms to process.
| `UNPACKERS` | `unrar 7zip` | Space-separated list of unpackers to build/download. Valid values: `unrar`, `7zip`. |
| `LINUX_ARCHS` | `armel armhf aarch64 i686 x86_64 riscv64 ppc6xx` | Architectures to build for the `linux` platform. |
| `ANDROID_ARCHS` | `i686-ndk x86_64-ndk armhf-ndk aarch64-ndk` | Architectures to build for the `android` platform. |
| `FREEBSD_ARCHS` | `x86_64-bsd aarch64-bsd` | Architectures to build for the `freebsd` platform. |
| `BUILDROOT_HOME` | `/build` | Root path containing the `buildroot` and `android` cross-toolchains. |

## Reusable GitHub Actions workflow

This repository exposes [`.github/workflows/build.yml`](.github/workflows/build.yml) as a **reusable workflow** (`workflow_call`), so other repositories can build/download the unpackers without duplicating the build/toolchain setup logic.

It also runs standalone (`workflow_dispatch`) with the same inputs, so it can be triggered manually from the Actions tab of this repository.

### Inputs

| Input | Default | Description |
|---|---|---|
| `unpackers` | `"unrar 7zip"` | Space-separated list of unpackers to build/download. Valid values: `unrar`, `7zip`. |
| `unrar-version` | `"7.23"` | Version string used for downloaded RARLAB unrar/WinRAR binaries (Windows/macOS). |
| `unrar-src-version` | `"7.2.7"` | Version of the `unrarsrc` tarball to build from source (Linux/Android/FreeBSD). |
| `zip7-version` | `"26.02"` | Version of 7-Zip to build from source or download prebuilt. |
| `platforms` | `"linux android freebsd windows macos"` | Space-separated list of platforms to process. |
| `linux-archs` | `"armel armhf aarch64 i686 x86_64 riscv64 ppc6xx"` | Architectures to build for the `linux` platform. |
| `android-archs` | `"i686-ndk x86_64-ndk armhf-ndk aarch64-ndk"` | Architectures to build for the `android` platform. |
| `freebsd-archs` | `"x86_64-bsd aarch64-bsd"` | Architectures to build for the `freebsd` platform. |
| `release-tag` | `""` | If set, publishes a GitHub release with this tag containing all built/downloaded archives. Left empty (default), no release is created. |

### Example: calling it from another repository

The example below builds **only `unrar`**, for all platforms/architectures (left at their defaults), overriding just the version inputs, and publishes the result as release `v7.23`:

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
      release-tag: v7.23
```
