#!/bin/bash
#
#  This file is part of nzbget. See <https://nzbget.com>.
#
#  Copyright (C) 2026 phnzb <pavel@nzbget.com>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#

set -e

# variables and defaults
UNRAR_VERSION="${UNRAR_VERSION:-7.23}"
UNRAR_SRC_VERSION="${UNRAR_SRC_VERSION:-7.2.7}"
ZIP7_VERSION="${ZIP7_VERSION:-26.03}"

# build architectures
LINUX_ARCHS="${LINUX_ARCHS:-armel armhf aarch64 i686 x86_64 riscv64 ppc6xx}"
ANDROID_ARCHS="${ANDROID_ARCHS:-i686-ndk x86_64-ndk armhf-ndk aarch64-ndk}"
FREEBSD_ARCHS="${FREEBSD_ARCHS:-x86_64-bsd aarch64-bsd}"

# toolchain locations inside ghcr.io/nzbgetcom/nzbget-musl-builder
NZBGET_LINUX_TOOLCHAIN_DIR="${NZBGET_LINUX_TOOLCHAIN_DIR:-/opt/nzbget/linux}"
NZBGET_ANDROID_TOOLCHAIN_DIR="${NZBGET_ANDROID_TOOLCHAIN_DIR:-/opt/nzbget/android}"
FREEBSD_PREFIX="${FREEBSD_PREFIX:-/opt/nzbget/freebsd}"

# platforms
PLATFORMS="${PLATFORMS:-linux android freebsd windows macos}"

# build unpackers
UNPACKERS="${UNPACKERS:-unrar 7zip}"

# build variables
BUILD_DIR=$PWD/build
CORES=$(nproc || echo 1)

linux_triple()
{
    case $1 in
        armel) echo "arm-linux-musleabi" ;;
        armhf) echo "arm-linux-musleabihf" ;;
        aarch64) echo "aarch64-linux-musl" ;;
        i686) echo "i686-linux-musl" ;;
        x86_64) echo "x86_64-linux-musl" ;;
        riscv64) echo "riscv64-linux-musl" ;;
        ppc6xx) echo "powerpc-linux-musl" ;;
        *)
            echo "Unknown linux arch: $1" >&2
            exit 1
            ;;
    esac
}

require_compiler()
{
    if [ -x "$1" ] || command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    echo "Compiler not found: $1" >&2
    echo "Use a ghcr.io/nzbgetcom/nzbget-musl-builder image that contains the $PLATFORM toolchain." >&2
    exit 1
}

setup_android()
{
    local root="$NZBGET_ANDROID_TOOLCHAIN_DIR"
    local api_file="$root/libcxx/api-level"
    local api=21
    local triple flags libcxx_arch common libdir

    if [ ! -f "$api_file" ]; then
        api_file="$root/api-level"
    fi
    if [ -f "$api_file" ]; then
        api=$(tr -d '[:space:]' < "$api_file")
    fi

    case $ARCH in
        aarch64-ndk)
            triple="aarch64-linux-android${api}"
            flags=""
            libcxx_arch="arm64"
            ;;
        armhf-ndk)
            triple="armv7a-linux-androideabi${api}"
            flags="-march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb"
            libcxx_arch="armv7"
            ;;
        x86_64-ndk)
            triple="x86_64-linux-android${api}"
            flags=""
            libcxx_arch="x86_64"
            ;;
        i686-ndk)
            triple="i686-linux-android${api}"
            flags="-march=i686"
            libcxx_arch="x86"
            ;;
        *)
            echo "Unknown android arch: $ARCH" >&2
            exit 1
            ;;
    esac

    libdir="$root/libcxx/$libcxx_arch/lib"
    if [ ! -f "$libdir/libc++.a" ]; then
        echo "Android libc++ not found: $libdir/libc++.a" >&2
        exit 1
    fi
    common="--target=${triple} --sysroot=${root}/sysroot"
    if [ -n "$flags" ]; then
        common="$common $flags"
    fi

    export CC="$root/llvm/bin/clang"
    export CXX="$root/llvm/bin/clang++"
    export AR="$root/llvm/bin/llvm-ar"
    export STRIP="$root/llvm/bin/llvm-strip"
    export UNRAR_CXXFLAGS="$common -D__ANDROID__ -fPIE -nostdinc++ -isystem $root/libcxx/include/c++/v1 -D_LIBCPP_DISABLE_AVAILABILITY"
    export UNRAR_LDFLAGS="$common -fuse-ld=lld -rtlib=compiler-rt --unwindlib=none -Wl,--no-dependent-libraries -pie -nostdlib++ -Wl,-z,relro,-z,now -Wl,-z,noexecstack"
    export UNRAR_LIBS="-Wl,--whole-archive $libdir/libc++.a -Wl,--no-whole-archive $libdir/libc++abi.a $libdir/libunwind.a -ldl -lm -llog"
    export ZIP_ARCH_FLAGS="$common -D__ANDROID__ -fPIE"
    export ZIP_CXXFLAGS_EXTRA="-nostdinc++ -isystem $root/libcxx/include/c++/v1 -D_LIBCPP_DISABLE_AVAILABILITY"
    export ZIP_LDFLAGS="$UNRAR_LDFLAGS"
    export ZIP_LIBS="$UNRAR_LIBS"
}

setup_freebsd()
{
    local triple sysroot common sysroot_arch

    if [ -d /usr/lib/llvm-19/bin ]; then
        export PATH="/usr/lib/llvm-19/bin:$PATH"
    fi

    case $ARCH in
        x86_64-bsd)
            triple="x86_64-pc-freebsd13"
            sysroot_arch="x86_64"
            ;;
        aarch64-bsd)
            triple="aarch64-pc-freebsd13"
            sysroot_arch="aarch64"
            ;;
        *)
            echo "Unknown freebsd arch: $ARCH" >&2
            exit 1
            ;;
    esac

    sysroot="$FREEBSD_PREFIX/sysroot-$sysroot_arch"
    if [ ! -f "$sysroot/usr/include/stdio.h" ]; then
        echo "FreeBSD sysroot not found: $sysroot" >&2
        exit 1
    fi
    common="--target=${triple} --sysroot=${sysroot}"

    export CC="clang"
    export CXX="clang++"
    export AR="llvm-ar"
    export STRIP="llvm-strip"
    export UNRAR_CXXFLAGS="$common -isystem $sysroot/usr/include/c++/v1"
    export UNRAR_LDFLAGS="-pthread -static $common -fuse-ld=lld"
    export ZIP_ARCH_FLAGS="$common -isystem $sysroot/usr/include/c++/v1"
    export ZIP_LDFLAGS="-static -fuse-ld=lld"
}

setup_toolchain()
{
    unset UNRAR_CXXFLAGS UNRAR_LIBS ZIP_ARCH_FLAGS ZIP_CXXFLAGS_EXTRA ZIP_LIBS
    export UNRAR_LDFLAGS=""
    export ZIP_LDFLAGS=""

    case $PLATFORM in
        linux)
            local host bin
            host=$(linux_triple "$ARCH")
            bin="$NZBGET_LINUX_TOOLCHAIN_DIR/$ARCH/bin"
            export CC="$bin/$host-gcc"
            export CXX="$bin/$host-g++"
            export AR="$bin/$host-ar"
            export STRIP="$bin/$host-strip"
            export UNRAR_LDFLAGS="-pthread -static"
            export ZIP_LDFLAGS="-static"
            case $ARCH in
                x86_64) export UNRAR_CXXFLAGS="-march=x86-64" ;;
                aarch64) export UNRAR_CXXFLAGS="-march=armv8-a+crypto+crc" ;;
                armhf) export UNRAR_CXXFLAGS="-march=armv7-a" ;;
            esac
            ;;
        android)
            setup_android
            ;;
        freebsd)
            setup_freebsd
            ;;
        *)
            echo "Unknown platform: $PLATFORM" >&2
            exit 1
            ;;
    esac

    require_compiler "$CC"
    require_compiler "$CXX"
}

build_unrar()
{
    echo "Building unrar version $UNRAR_VERSION (source version $UNRAR_SRC_VERSION) for $PLATFORM/$ARCH -> unrar-$ARCH.tar.gz (using $CORES cores)"
    curl -fsSL -o "$BUILD_DIR/unrar.tar.gz" "https://www.rarlab.com/rar/unrarsrc-$UNRAR_SRC_VERSION.tar.gz"
    cd "$BUILD_DIR"
    tar zxf unrar.tar.gz
    rm unrar.tar.gz
    cd unrar
    sed "s|^CXX=.*|CXX=$CXX|" -i makefile
    sed "s|^AR=.*|AR=$AR|" -i makefile
    sed "s|^STRIP=.*|STRIP=$STRIP|" -i makefile
    sed "s|^LDFLAGS=.*|LDFLAGS=$UNRAR_LDFLAGS|" -i makefile
    if [ -n "${UNRAR_CXXFLAGS:-}" ]; then
        sed "s|^CXXFLAGS=.*|& $UNRAR_CXXFLAGS|" -i makefile
    fi
    if [ -n "${UNRAR_LIBS:-}" ]; then
        printf 'LIBS=%s\n' "$UNRAR_LIBS" >> makefile
    fi
    # android specific fixes
    if [ "$PLATFORM" == "android" ] ; then
        sed 's:#ifdef __VMS$:#if defined (__VMS) || defined (__ANDROID__):' -i consio.cpp
        sed 's:^#define USE_LUTIMES$:#undef USE_LUTIMES:' -i os.hpp
    fi

    # build
    make clean
    make -j "$CORES" > "$BUILD_DIR/build.log" 2>&1
    OUT_DIR=$BUILD_DIR/$ARCH
    mkdir -p "$OUT_DIR"
    cp unrar "$OUT_DIR"
    cp license.txt "$OUT_DIR/license-unrar.txt"
    rm -rf "$BUILD_DIR/unrar"
    cd "$BUILD_DIR"
    tar zcf "unrar-$ARCH.tar.gz" -C "$OUT_DIR" .
    rm -rf "$OUT_DIR"
    rm "$BUILD_DIR/build.log"
}

build_7zip()
{
    echo "Building 7zip version $ZIP7_VERSION for $PLATFORM/$ARCH -> 7zip-$ARCH.tar.gz (using $CORES cores)"
    curl -fsSL -o "$BUILD_DIR/7z.tar.xz" -L "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-src.tar.xz"
    cd "$BUILD_DIR"
    mkdir -p 7z
    tar xf 7z.tar.xz -C 7z
    rm 7z.tar.xz
    cd 7z/CPP/7zip
    if [ -n "${ZIP_ARCH_FLAGS:-}" ]; then
        sed "s|^MY_ARCH_2 = .*|MY_ARCH_2 = \$(MY_ARCH) $ZIP_ARCH_FLAGS|" -i 7zip_gcc.mak
    fi
    if [ -n "${ZIP_LDFLAGS:-}" ]; then
        sed "s|^LDFLAGS_STATIC =.*|LDFLAGS_STATIC = $ZIP_LDFLAGS|" -i 7zip_gcc.mak
    fi
    if [ -n "${ZIP_LIBS:-}" ]; then
        sed "s|^LIB2 =.*|LIB2 = $ZIP_LIBS|" -i 7zip_gcc.mak
    fi
    if [ "$PLATFORM" == "android" ]; then
        sed "s|^#if defined(TIME_UTC)|#if defined(_TIME_UTC)|g" -i ../Windows/TimeUtils.cpp
    fi
    cd Bundles/Alone
    make -j "$CORES" -f makefile.gcc > "$BUILD_DIR/build.log" 2>&1
    OUT_DIR=$BUILD_DIR/$ARCH
    mkdir -p "$OUT_DIR"
    cp _o/7za "$OUT_DIR/7za"
    "$STRIP" "$OUT_DIR/7za"
    cp ../../../../DOC/License.txt "$OUT_DIR/license-7zip.txt"
    chmod -x "$OUT_DIR/license-7zip.txt"
    rm -rf "$BUILD_DIR/7z"
    cd "$BUILD_DIR"
    tar zcf "7zip-$ARCH.tar.gz" -C "$OUT_DIR" .
    rm -rf "$OUT_DIR"
    rm "$BUILD_DIR/build.log"
}

download_unrar_windows()
{
    echo -n "Downloading unrar windows binaries version $UNRAR_VERSION ... "
    curl -fsSL -o "$BUILD_DIR/winrar-x64.exe" -L "https://www.rarlab.com/rar/winrar-x64-${UNRAR_VERSION//./}.exe"
    cd "$BUILD_DIR"
    OUT_DIR=$BUILD_DIR/winrar-x64
    mkdir -p "$OUT_DIR"
    unrar x winrar-x64.exe "$OUT_DIR" > "$BUILD_DIR/build.log" 2>&1
    mv "$OUT_DIR/UnRAR.exe" "$BUILD_DIR/unrar.exe"
    zip -j unrar-windows-x64.zip "$BUILD_DIR/unrar.exe" >> "$BUILD_DIR/build.log" 2>&1
    rm -rf "$OUT_DIR"
    rm "$BUILD_DIR"/*.exe
    rm "$BUILD_DIR/build.log"
    echo "done"
}

download_7zip_windows()
{
    echo -n "Downloading 7zip windows binaries version $ZIP7_VERSION ... "
    curl -fsSL -o "$BUILD_DIR/7zip.7z" -L "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-extra.7z"
    cd "$BUILD_DIR"
    OUT_DIR=$BUILD_DIR/7zip
    7z x 7zip.7z -o"$OUT_DIR" > "$BUILD_DIR/build.log" 2>&1
    X86_DIR=$BUILD_DIR/x86
    X64_DIR=$BUILD_DIR/x64
    mkdir -p "$X86_DIR"
    mkdir -p "$X64_DIR"
    mv "$OUT_DIR/7za.exe" "$X86_DIR/7za.exe"
    mv "$OUT_DIR/x64/7za.exe" "$X64_DIR/7za.exe"
    zip -j 7zip-windows-x86.zip "$X86_DIR/7za.exe" >> "$BUILD_DIR/build.log" 2>&1
    zip -j 7zip-windows-x64.zip "$X64_DIR/7za.exe" >> "$BUILD_DIR/build.log" 2>&1
    rm -rf "$OUT_DIR" "$X86_DIR" "$X64_DIR"
    rm "$BUILD_DIR"/*.7z
    rm "$BUILD_DIR/build.log"
    echo "done"
}

download_7zip_macos()
{
    echo -n "Downloading 7zip macos binaries version $ZIP7_VERSION ... "
    curl -fsSL -o "$BUILD_DIR/7z.tar.xz" -L "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-mac.tar.xz"
    cd "$BUILD_DIR"
    OUT_DIR=$BUILD_DIR/7zip
    mkdir -p "$OUT_DIR"
    tar xf 7z.tar.xz -C "$OUT_DIR"
    cp "$OUT_DIR/7zz" "$BUILD_DIR/7za"
    tar zcf 7zip-macos-universal.tar.gz 7za > "$BUILD_DIR/build.log" 2>&1
    rm -rf "$OUT_DIR"
    rm "$BUILD_DIR"/*.tar.xz
    rm "$BUILD_DIR/build.log"
    rm "$BUILD_DIR/7za"
    echo "done"
}

download_unrar_macos()
{
    echo -n "Downloading unrar macos binaries version $UNRAR_VERSION ... "
    curl -fsSL -o "$BUILD_DIR/unrar-arm64.tar.gz" -L "https://www.rarlab.com/rar/rarmacos-arm-${UNRAR_VERSION//./}.tar.gz"
    curl -fsSL -o "$BUILD_DIR/unrar-x64.tar.gz" -L "https://www.rarlab.com/rar/rarmacos-x64-${UNRAR_VERSION//./}.tar.gz"
    cd "$BUILD_DIR"
    ARM64_DIR=$BUILD_DIR/arm64
    X64_DIR=$BUILD_DIR/x64
    mkdir -p "$ARM64_DIR"
    mkdir -p "$X64_DIR"
    tar zxf unrar-arm64.tar.gz -C "$ARM64_DIR"
    tar zxf unrar-x64.tar.gz -C "$X64_DIR"
    cp "$ARM64_DIR/rar/unrar" "$ARM64_DIR/unrar"
    cp "$X64_DIR/rar/unrar" "$X64_DIR/unrar"
    llvm-lipo-18 -create -output "$BUILD_DIR/unrar" "$ARM64_DIR/unrar" "$X64_DIR/unrar"
    tar -C "$ARM64_DIR" -zcf unrar-macos-arm64.tar.gz unrar
    tar -C "$X64_DIR" -zcf unrar-macos-x64.tar.gz unrar
    tar -C "$BUILD_DIR" -zcf unrar-macos-universal.tar.gz unrar
    rm -rf "$ARM64_DIR" "$X64_DIR" "$BUILD_DIR/unrar"
    rm "$BUILD_DIR/unrar-arm64.tar.gz" "$BUILD_DIR/unrar-x64.tar.gz"
    echo "done"
}

build_unpackers()
{
    for ARCH in $ARCHS; do
        setup_toolchain
        for UNPACKER in $UNPACKERS; do
            "build_$UNPACKER"
        done
    done
}

# clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# build/download binaries
for PLATFORM in $PLATFORMS; do
    case $PLATFORM in
        linux)
            ARCHS=$LINUX_ARCHS
            build_unpackers
            ;;
        android)
            ARCHS=$ANDROID_ARCHS
            build_unpackers
            ;;
        freebsd)
            ARCHS=$FREEBSD_ARCHS
            build_unpackers
            ;;
        windows)
            for UNPACKER in $UNPACKERS; do
                "download_${UNPACKER}_windows"
            done
            ;;
        macos)
            for UNPACKER in $UNPACKERS; do
                "download_${UNPACKER}_macos"
            done
            ;;
        *)
            echo "Unknown platform: $PLATFORM" >&2
            exit 1
            ;;
    esac
done
