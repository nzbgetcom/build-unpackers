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
ZIP7_VERSION="${ZIP7_VERSION:-26.02}"

# build architectures
LINUX_ARCHS="${LINUX_ARCHS:-armel armhf aarch64 i686 x86_64 riscv64 ppc6xx}"
ANDROID_ARCHS="${ANDROID_ARCHS:-i686-ndk x86_64-ndk armhf-ndk aarch64-ndk}"
FREEBSD_ARCHS="${FREEBSD_ARCHS:-x86_64-bsd}"

# freebsd variables
FREEBSD_SYSROOT="${FREEBSD_SYSROOT:-/build/freebsd/sysroot}"
FREEBSD_CLANG_VER="${FREEBSD_CLANG_VER:-18}"

# platforms
PLATFORMS="${PLATFORMS:-linux android freebsd windows macos}"

# build unpackers
UNPACKERS="${UNPACKERS:-unrar 7zip}"

# build variables
BUILDROOT_HOME="${BUILDROOT_HOME:-/build}"
BUILD_DIR=$PWD/build
CORES=$(nproc || echo 1)

setup_toolchain()
{
    export ARCH=$ARCH
    case $ARCH in
        armel)
            export HOST="arm-buildroot-linux-musleabi"
            ;;
        armhf)
            export HOST="arm-buildroot-linux-musleabihf"
            ;;
        aarch64)
            export HOST="aarch64-buildroot-linux-musl"
            ;;
        i686)
            export HOST="i686-buildroot-linux-musl"
            ;;
        x86_64)
            export HOST="x86_64-buildroot-linux-musl"
            ;;
        riscv64)
            export HOST="riscv64-buildroot-linux-musl"
            ;;
        ppc6xx)
            export HOST="powerpc-buildroot-linux-musl"
            ;;
        i686-ndk)
            export HOST="i686-linux-android"
            ;;
        x86_64-ndk)
            export HOST="x86_64-linux-android"
            ;;
        armhf-ndk)
            export HOST="arm-linux-androideabi"
            ;;
        aarch64-ndk)
            export HOST="aarch64-linux-android"
            ;;
        x86_64-bsd)
            export HOST="x86_64-bsd"
            ;;
    esac


    case $PLATFORM in
        android)
            TOOLCHAIN_PATH=$BUILDROOT_HOME/android
            unset CPP
            export CC="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-clang"
            export CXX="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-clang++"
            export AR="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-ar"
            export STRIP="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-strip"
            ;;
        freebsd)
            export CC="clang-$FREEBSD_CLANG_VER"
            export CPP="clang-cpp-$FREEBSD_CLANG_VER"
            export CXX="clang++-$FREEBSD_CLANG_VER"
            unset AR
            unset STRIP
            ;;
        *)
            TOOLCHAIN_PATH=$BUILDROOT_HOME/buildroot
            export CC="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-gcc"
            export CPP="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-cpp"
            export CXX="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-g++"
            export AR="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-ar"
            export STRIP="$TOOLCHAIN_PATH/$ARCH/output/host/usr/bin/$HOST-strip"
            ;;
    esac

    # build flags
    export CXXFLAGS="-Os"
    export CPPFLAGS="-Os"
    export LDFLAGS=""

    if [ "$PLATFORM" == "freebsd" ]; then
        export CXXFLAGS="-Os --sysroot=$FREEBSD_SYSROOT -I$FREEBSD_SYSROOT/usr/include/c++/v1"
        export CFLAGS=$CXXFLAGS
        export CPPFLAGS=$CXXFLAGS
    fi
}

build_unrar()
{
    echo "Building unrar version $UNRAR_VERSION (source version $UNRAR_SRC_VERSION) for $ARCH (using $CORES cores)"
    UNRARSRC=https://www.rarlab.com/rar/unrarsrc-$UNRAR_SRC_VERSION.tar.gz
    curl -sS -o $BUILD_DIR/unrar.tar.gz $UNRARSRC
    cd $BUILD_DIR
    tar zxf unrar.tar.gz
    rm unrar.tar.gz
    cd unrar
    sed "s|^CXX=.*|CXX=$CXX|" -i makefile
    sed "s|^AR=.*|AR=$AR|" -i makefile
    sed "s|^STRIP=.*|STRIP=$STRIP|" -i makefile
    # android specific fixes
    if [ "$PLATFORM" == "android" ] ; then
        sed 's:#ifdef __VMS$:#if defined (__VMS) || defined (__ANDROID__):' -i consio.cpp
        sed 's:^#define USE_LUTIMES$:#undef USE_LUTIMES:' -i os.hpp
    fi
    # freebsd specific fixes
    if [ "$PLATFORM" == "freebsd" ]; then
        sed "s|^CXXFLAGS=.*|CXXFLAGS=-std=c++11 -O2 -nostdlib --target=x86_64-pc-freebsd --sysroot=$FREEBSD_SYSROOT -I$FREEBSD_SYSROOT/usr/include/c++/v1|" -i makefile
        sed "s|^LDFLAGS=.*|LDFLAGS=-static --target=x86_64-pc-freebsd --sysroot=$FREEBSD_SYSROOT -pthread -lc++ -lm -fuse-ld=lld|" -i makefile
        sed "s|^STRIP=.*|STRIP=strip|" -i makefile
    fi
    # unrar7 optimizations
    sed "s|LDFLAGS=-pthread|LDFLAGS=-pthread -static|" -i makefile
    case $ARCH in
        x86_64)
            sed "s|CXXFLAGS=-march=native|CXXFLAGS=-march=x86-64|" -i makefile
            ;;
        aarch64)
            sed "s|CXXFLAGS=-march=native|CXXFLAGS=-march=armv8-a+crypto+crc|" -i makefile
            ;;
        armhf)
            sed "s|CXXFLAGS=-march=native|CXXFLAGS=-march=armv7-a|" -i makefile
            ;;
        *)
            sed "s|CXXFLAGS=-march=native |CXXFLAGS=|" -i makefile
            ;;
    esac

    # build
    make clean
    make -j $CORES > $BUILD_DIR/build.log 2>&1
    OUT_DIR=$BUILD_DIR/$ARCH
    mkdir -p $OUT_DIR
    cp unrar $OUT_DIR
    cp license.txt $OUT_DIR/license-unrar.txt
    rm -rf $BUILD_DIR/unrar
    cd $BUILD_DIR
    tar zcf "unrar-$ARCH.tar.gz" -C $OUT_DIR .
    rm -rf $OUT_DIR
    rm $BUILD_DIR/build.log
}

build_7zip()
{
    echo "Building 7zip version $ZIP7_VERSION for $ARCH (using $CORES cores)"
    curl -sS -o $BUILD_DIR/7z.tar.xz -lL "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-src.tar.xz"
    cd $BUILD_DIR
    mkdir -p 7z
    tar xf 7z.tar.xz -C 7z
    rm 7z.tar.xz
    cd 7z/CPP/7zip
    sed "s|^LDFLAGS_STATIC =.*|LDFLAGS_STATIC = -static|" -i 7zip_gcc.mak
    if [ "$PLATFORM" == "android" ]; then
        sed "s|^#if defined(TIME_UTC)|#if defined(_TIME_UTC)|g" -i ../Windows/TimeUtils.cpp
        sed "s|^LIB2 =.*|LIB2 = |g" -i 7zip_gcc.mak
        sed "s|^CFLAGS_WARN_WALL =.*|CFLAGS_WARN_WALL = -Wall -Wextra|" -i 7zip_gcc.mak
    fi
    if [ "$PLATFORM" == "freebsd" ]; then
        sed "s|^MY_ARCH_2 = .*|MY_ARCH_2 = \$(MY_ARCH) --target=x86_64-pc-freebsd --sysroot=$FREEBSD_SYSROOT -I$FREEBSD_SYSROOT/usr/include/c++/v1|" -i 7zip_gcc.mak
    fi
    cd Bundles/Alone
    make -j $COREX -f makefile.gcc > $BUILD_DIR/build.log 2>&1
    OUT_DIR=$BUILD_DIR/$ARCH
    mkdir -p $OUT_DIR
    cp _o/7za $OUT_DIR/7za
    cp ../../../../DOC/License.txt $OUT_DIR/license-7zip.txt
    chmod -x $OUT_DIR/license-7zip.txt
    rm -rf $BUILD_DIR/7z
    cd $BUILD_DIR
    tar zcf "7zip-$ARCH.tar.gz" -C $OUT_DIR .
    rm -rf $OUT_DIR
    rm $BUILD_DIR/build.log
}

download_unrar_windows()
{
    echo -n "Downloading unrar windows binaries version $UNRAR_VERSION ... "
    curl -sS -o $BUILD_DIR/winrar-x64.exe -lL "https://www.rarlab.com/rar/winrar-x64-${UNRAR_VERSION//./}.exe"
    cd $BUILD_DIR
    OUT_DIR=$BUILD_DIR/winrar-x64
    mkdir -p $OUT_DIR
    unrar x winrar-x64.exe $OUT_DIR > $BUILD_DIR/build.log 2>&1
    mv $OUT_DIR/UnRAR.exe $BUILD_DIR/unrar.exe
    zip -j unrar-windows-x64.zip $BUILD_DIR/unrar.exe >> $BUILD_DIR/build.log 2>&1
    rm -rf $OUT_DIR
    rm $BUILD_DIR/*.exe
    rm $BUILD_DIR/build.log
    echo "done"
}

download_7zip_windows()
{
    echo -n "Downloading 7zip windows binaries version $ZIP7_VERSION ... "
    curl -sS -o $BUILD_DIR/7zip.7z -lL "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-extra.7z"
    cd $BUILD_DIR
    OUT_DIR=$BUILD_DIR/7zip
    7z x 7zip.7z -o$OUT_DIR > $BUILD_DIR/build.log 2>&1
    X86_DIR=$BUILD_DIR/x86
    X64_DIR=$BUILD_DIR/x64
    mkdir -p $X86_DIR
    mkdir -p $X64_DIR
    mv $OUT_DIR/7za.exe $X86_DIR/7za.exe
    mv $OUT_DIR/x64/7za.exe $X64_DIR/7za.exe
    zip -j 7zip-windows-x86.zip $X86_DIR/7za.exe >> $BUILD_DIR/build.log 2>&1
    zip -j 7zip-windows-x64.zip $X64_DIR/7za.exe >> $BUILD_DIR/build.log 2>&1
    rm -rf $OUT_DIR $X86_DIR $X64_DIR
    rm $BUILD_DIR/*.7z
    rm $BUILD_DIR/build.log
    echo "done"
}

download_7zip_macos()
{
    echo -n "Downloading 7zip macos binaries version $ZIP7_VERSION ... "
    curl -sS -o $BUILD_DIR/7z.tar.xz -lL "https://github.com/ip7z/7zip/releases/download/$ZIP7_VERSION/7z${ZIP7_VERSION//./}-mac.tar.xz"
    cd $BUILD_DIR
    OUT_DIR=$BUILD_DIR/7zip
    mkdir -p $OUT_DIR
    tar xf 7z.tar.xz -C $OUT_DIR
    cp $OUT_DIR/7zz $BUILD_DIR/7za
    tar zcf 7zip-macos-universal.tar.gz 7za > $BUILD_DIR/build.log 2>&1
    rm -rf $OUT_DIR
    rm $BUILD_DIR/*.tar.xz
    rm $BUILD_DIR/build.log
    rm $BUILD_DIR/7za
    echo "done"
}

download_unrar_macos()
{
    echo -n "Downloading unrar macos binaries version $UNRAR_VERSION ... "
    curl -sS -o $BUILD_DIR/unrar-arm64.tar.gz -lL "https://www.rarlab.com/rar/rarmacos-arm-${UNRAR_VERSION//./}.tar.gz"
    curl -sS -o $BUILD_DIR/unrar-x64.tar.gz -lL "https://www.rarlab.com/rar/rarmacos-x64-${UNRAR_VERSION//./}.tar.gz"
    cd $BUILD_DIR
    ARM64_DIR=$BUILD_DIR/arm64
    X64_DIR=$BUILD_DIR/x64    
    mkdir -p $ARM64_DIR
    mkdir -p $X64_DIR
    tar zxf unrar-arm64.tar.gz -C $ARM64_DIR
    tar zxf unrar-x64.tar.gz -C $X64_DIR
    cp $ARM64_DIR/rar/unrar $ARM64_DIR/unrar
    cp $X64_DIR/rar/unrar $X64_DIR/unrar
    llvm-lipo-18 -create -output $BUILD_DIR/unrar $ARM64_DIR/unrar $X64_DIR/unrar
    tar -C $ARM64_DIR -zcf unrar-macos-arm64.tar.gz unrar
    tar -C $X64_DIR -zcf unrar-macos-x64.tar.gz unrar
    tar -C $BUILD_DIR -zcf unrar-macos-universal.tar.gz unrar
    rm -rf $ARM64_DIR $X64_DIR $BUILD_DIR/unrar
    rm $BUILD_DIR/unrar-arm64.tar.gz $BUILD_DIR/unrar-x64.tar.gz
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
rm -rf $BUILD_DIR
mkdir -p $BUILD_DIR

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
    esac
done
