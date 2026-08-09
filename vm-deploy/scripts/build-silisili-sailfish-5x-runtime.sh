#!/usr/bin/env bash
set -euo pipefail

umask 0022
export LC_ALL=C
export TZ=UTC

TARGET="${SAILFISH_TARGET:-SailfishOS-5.0.0.62-aarch64}"
TOOLING_NAME="${SAILFISH_TOOLING:-SailfishOS-5.0.0.62-i486}"
TOOLING="/srv/mer/toolings/$TOOLING_NAME"
SOURCE_ROOT="${SOURCE_ROOT:-$HOME/silisili-5x-work}"
BUILD_ROOT="${BUILD_ROOT:-$HOME/silisili-5x-build}"
PREFIX="${PREFIX:-$BUILD_ROOT/prefix}"
BUILD_JOBS="${BUILD_JOBS:-4}"
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
V4L2_COMPAT_HEADER="${V4L2_COMPAT_HEADER:-$SCRIPT_ROOT/include/sailfish-v4l2-compat.h}"
FFMPEG_V4L2_PATCH="${FFMPEG_V4L2_PATCH:-$SCRIPT_ROOT/patches/ffmpeg-v4l2-legacy-color-fields.patch}"
FFMPEG_V4L2_USERPTR_PATCH="${FFMPEG_V4L2_USERPTR_PATCH:-$SCRIPT_ROOT/patches/ffmpeg-v4l2-userptr-output.patch}"
V4L2_COMPAT_CFLAGS='-DV4L2_BUF_FLAG_LAST=0x00100000 -DV4L2_PIX_FMT_HEVC=0x43564548 -DV4L2_PIX_FMT_VP9=0x30395056'

OPENSSL_SOURCE="${OPENSSL_SOURCE:-$SOURCE_ROOT/openssl}"
CURL_SOURCE="${CURL_SOURCE:-$SOURCE_ROOT/curl}"
FFMPEG_SOURCE="${FFMPEG_SOURCE:-$SOURCE_ROOT/ffmpeg}"
LIBASS_SOURCE="${LIBASS_SOURCE:-$SOURCE_ROOT/libass}"
LIBPLACEBO_SOURCE="${LIBPLACEBO_SOURCE:-$SOURCE_ROOT/libplacebo}"
MPV_SOURCE="${MPV_SOURCE:-$SOURCE_ROOT/mpv037}"

OPENSSL_COMMIT=fa1e5dfb142bb1c26c3c38a10aafa7a095df52e5
CURL_COMMIT=83bedbd730d62b83744cc26fa0433d3f6e2e4cd6
FFMPEG_COMMIT=6338d19eb349e23a2004eb6cdd863bdef454572d
LIBASS_COMMIT=e46aedea0a0d17da4c4ef49d84b94a7994664ab5
LIBPLACEBO_COMMIT=64c1954570f1cd57f8570a57e51fb0249b57bb90
MPV_COMMIT=818ce7c51a6b9179307950e919983e0909942098

MESON_PYTHONPATH="$TOOLING/usr/lib/python3.8/site-packages"
MESON="$TOOLING/usr/bin/meson"
NINJA="$TOOLING/usr/bin/ninja"
CMAKE="$TOOLING/usr/bin/cmake"
MAKE="$TOOLING/usr/bin/make"
PRIVATE_RPATH=/usr/lib64/silisili
OPENSSL_CONFIGURE_PERL="${OPENSSL_CONFIGURE_PERL:-$TOOLING/usr/bin/perl}"
OPENSSL_CONFIGURE_PERL5LIB="${OPENSSL_CONFIGURE_PERL5LIB:-$TOOLING/usr/lib/perl5:$TOOLING/usr/share/perl5:/srv/mer/targets/$TARGET/usr/share/perl5}"
OPENSSL_CONFIGURE_LD_LIBRARY_PATH="${OPENSSL_CONFIGURE_LD_LIBRARY_PATH:-$TOOLING/usr/lib/perl5/CORE}"
CROSS_BIN="$TOOLING/opt/cross/bin"
CROSS_PREFIX="$CROSS_BIN/aarch64-meego-linux-gnu"
TARGET_SYSROOT="/srv/mer/targets/$TARGET"

if test -x "$CROSS_BIN/ld"; then
    OPENSSL_BUILD_PATH="$CROSS_BIN:$PATH"
    OPENSSL_BUILD_CC="$CROSS_PREFIX-gcc -B$CROSS_PREFIX- --sysroot=$TARGET_SYSROOT"
    OPENSSL_BUILD_AR="$CROSS_PREFIX-ar"
    OPENSSL_BUILD_RANLIB="$CROSS_PREFIX-ranlib"
else
    OPENSSL_BUILD_PATH="$PATH"
    OPENSSL_BUILD_CC="sb2 -t $TARGET gcc"
    OPENSSL_BUILD_AR="sb2 -t $TARGET ar"
    OPENSSL_BUILD_RANLIB="sb2 -t $TARGET ranlib"
fi

fail() {
    echo "Sailfish 5.x runtime build failed: $*" >&2
    exit 1
}

target_run() {
    sb2 -t "$TARGET" "$@"
}

meson_run() {
    target_run env \
        "NINJA=$NINJA" \
        "PYTHONPATH=$MESON_PYTHONPATH" \
        "$MESON" "$@"
}

ninja_run() {
    target_run env "PYTHONPATH=$MESON_PYTHONPATH" "$NINJA" "$@"
}

cmake_run() {
    target_run "$CMAKE" "$@"
}

openssl_make() {
    env LD_LIBRARY_PATH="$OPENSSL_CONFIGURE_LD_LIBRARY_PATH" \
        PATH="$OPENSSL_BUILD_PATH" \
        PERL5LIB="$OPENSSL_CONFIGURE_PERL5LIB" \
        "$MAKE" -C "$openssl_build" \
        PERL="$OPENSSL_CONFIGURE_PERL" \
        CC="$OPENSSL_BUILD_CC" \
        AR="$OPENSSL_BUILD_AR" \
        RANLIB="$OPENSSL_BUILD_RANLIB" \
        "$@"
}

verify_source() {
    local source="$1" commit="$2" name="$3"

    test "$(git -C "$source" rev-parse HEAD)" = "$commit" ||
        fail "$name is not at pinned commit $commit"
    test -z "$(git -C "$source" status --porcelain --untracked-files=no)" ||
        fail "$name source tree is not clean"
}

verify_glibc_ceiling() {
    local root="$1" elf newest maximum=

    while IFS= read -r -d '' elf; do
        readelf -h "$elf" >/dev/null 2>&1 || continue
        newest="$(readelf --version-info "$elf" 2>/dev/null |
            grep -oE 'GLIBC_[0-9]+(\.[0-9]+)+' | sort -Vu | tail -1 || true)"
        test -n "$newest" || continue
        maximum="$(printf '%s\n%s\n' "$maximum" "$newest" |
            sed '/^$/d' | sort -V | tail -1)"
    done < <(find "$root" -type f -print0)

    test "$(printf '%s\nGLIBC_2.30\n' "${maximum:-GLIBC_0}" | sort -V | tail -1)" = \
        GLIBC_2.30 || fail "runtime requires $maximum, newer than GLIBC_2.30"
    echo "Sailfish 5.0 GLIBC ceiling passed: ${maximum:-none}"
}

for tool in awk git readelf sb2 sed sha256sum sort; do
    command -v "$tool" >/dev/null || fail "missing SDK tool: $tool"
done
test -x "$OPENSSL_CONFIGURE_PERL" ||
    fail "OpenSSL configure Perl is unavailable: $OPENSSL_CONFIGURE_PERL"
test -f "/srv/mer/targets/$TARGET/usr/share/perl5/IPC/Cmd.pm" ||
    fail "OpenSSL configure IPC::Cmd is unavailable in $TARGET"
test -x "$MESON" || fail "Meson is not installed in $TOOLING_NAME"
test -x "$NINJA" || fail "Ninja is not installed in $TOOLING_NAME"
test -x "$CMAKE" || fail "CMake is not installed in $TOOLING_NAME"
test -x "$MAKE" || fail "GNU Make is not installed in $TOOLING_NAME"
test -f "$V4L2_COMPAT_HEADER" || fail "missing Sailfish V4L2 compatibility header"
test -f "$FFMPEG_V4L2_PATCH" || fail "missing FFmpeg V4L2 compatibility patch"
test -f "$FFMPEG_V4L2_USERPTR_PATCH" ||
    fail "missing FFmpeg V4L2 USERPTR compatibility patch"

# Recover cleanly if a previous build was interrupted after applying the
# temporary source patch. The pinned source must still pass the normal clean
# tree check before this build is allowed to continue.
if grep -Fq SILISILI_V4L2_USERPTR_OUTPUT \
    "$FFMPEG_SOURCE/libavcodec/v4l2_context.h"; then
    git -C "$FFMPEG_SOURCE" apply --reverse --check --recount \
        "$FFMPEG_V4L2_USERPTR_PATCH" ||
        fail "FFmpeg V4L2 USERPTR patch cannot be cleanly reversed"
    git -C "$FFMPEG_SOURCE" apply --reverse --recount \
        "$FFMPEG_V4L2_USERPTR_PATCH"
fi
if grep -Fq SILISILI_V4L2_LEGACY_COLOR_FIELDS \
    "$FFMPEG_SOURCE/libavcodec/v4l2_buffers.c"; then
    git -C "$FFMPEG_SOURCE" apply --reverse --check --recount \
        "$FFMPEG_V4L2_PATCH" ||
        fail "FFmpeg V4L2 compatibility patch cannot be cleanly reversed"
    git -C "$FFMPEG_SOURCE" apply --reverse --recount "$FFMPEG_V4L2_PATCH"
fi

verify_source "$OPENSSL_SOURCE" "$OPENSSL_COMMIT" OpenSSL
verify_source "$CURL_SOURCE" "$CURL_COMMIT" curl
verify_source "$FFMPEG_SOURCE" "$FFMPEG_COMMIT" FFmpeg
verify_source "$LIBASS_SOURCE" "$LIBASS_COMMIT" libass
verify_source "$LIBPLACEBO_SOURCE" "$LIBPLACEBO_COMMIT" libplacebo
verify_source "$MPV_SOURCE" "$MPV_COMMIT" mpv

ffmpeg_patch_applied=0
ffmpeg_userptr_patch_applied=0
cleanup_ffmpeg_patch() {
    if test "$ffmpeg_userptr_patch_applied" -eq 1; then
        git -C "$FFMPEG_SOURCE" apply --reverse --recount \
            "$FFMPEG_V4L2_USERPTR_PATCH" ||
            echo "warning: failed to restore the FFmpeg USERPTR source patch" >&2
    fi
    if test "$ffmpeg_patch_applied" -eq 1; then
        git -C "$FFMPEG_SOURCE" apply --reverse --recount \
            "$FFMPEG_V4L2_PATCH" ||
            echo "warning: failed to restore the clean FFmpeg source tree" >&2
    fi
}
trap cleanup_ffmpeg_patch EXIT
git -C "$FFMPEG_SOURCE" apply --check --recount "$FFMPEG_V4L2_PATCH" ||
    fail "FFmpeg V4L2 compatibility patch does not match the pinned source"
git -C "$FFMPEG_SOURCE" apply --recount "$FFMPEG_V4L2_PATCH"
ffmpeg_patch_applied=1
git -C "$FFMPEG_SOURCE" apply --check --recount "$FFMPEG_V4L2_USERPTR_PATCH" ||
    fail "FFmpeg V4L2 USERPTR patch does not match the pinned source"
git -C "$FFMPEG_SOURCE" apply --recount "$FFMPEG_V4L2_USERPTR_PATCH"
ffmpeg_userptr_patch_applied=1

test -d "$LIBPLACEBO_SOURCE/3rdparty/fast_float/include" ||
    fail "libplacebo submodules are not initialized"
grep -Fq 'if (gl->FenceSync && !p->params.external_swapchain)' \
    "$MPV_SOURCE/video/out/opengl/context.c" ||
    fail "mpv external-swapchain fence guard is missing"

install -d -m0755 "$BUILD_ROOT" "$PREFIX"

openssl_build="$BUILD_ROOT/openssl"
if test ! -e "$openssl_build/Makefile"; then
    install -d -m0755 "$openssl_build"
    (
        cd "$openssl_build"
        # Configure only generates build files. Run it with the native SDK
        # Perl; compiling and linking still happen inside the 5.0 target.
        env CC=gcc AR=ar RANLIB=ranlib \
            LD_LIBRARY_PATH="$OPENSSL_CONFIGURE_LD_LIBRARY_PATH" \
            PERL5LIB="$OPENSSL_CONFIGURE_PERL5LIB" \
            "$OPENSSL_CONFIGURE_PERL" "$OPENSSL_SOURCE/Configure" \
            linux-aarch64 shared no-tests \
            "-Wl,-rpath,$PRIVATE_RPATH" \
            --prefix="$PREFIX" --libdir=lib
    )
fi
if test ! -e "$PREFIX/lib/libcrypto.so.3" ||
    test ! -e "$PREFIX/lib/libssl.so.3" ||
    test ! -e "$PREFIX/include/openssl/ssl.h"; then
    openssl_make -s -j"$BUILD_JOBS" build_libs
    openssl_make -s install_dev
fi

curl_build="$BUILD_ROOT/curl"
if test ! -e "$curl_build/build.ninja"; then
    cmake_run -S "$CURL_SOURCE" -B "$curl_build" -G Ninja \
        -DCMAKE_MAKE_PROGRAM="$NINJA" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_BUILD_RPATH="$PRIVATE_RPATH" \
        -DCMAKE_INSTALL_RPATH="$PRIVATE_RPATH" \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_CURL_EXE=OFF \
        -DBUILD_TESTING=OFF \
        -DBUILD_EXAMPLES=OFF \
        -DCURL_USE_OPENSSL=ON \
        -DOPENSSL_ROOT_DIR="$PREFIX" \
        -DCURL_ZLIB=ON \
        -DCURL_USE_LIBPSL=OFF \
        -DCURL_USE_LIBSSH2=OFF \
        -DCURL_USE_LIBSSH=OFF \
        -DUSE_NGHTTP2=OFF \
        -DUSE_NGTCP2=OFF \
        -DUSE_QUICHE=OFF \
        -DUSE_LIBIDN2=OFF \
        -DCURL_BROTLI=OFF \
        -DCURL_ZSTD=OFF \
        -DCURL_DISABLE_LDAP=ON \
        -DCURL_DISABLE_LDAPS=ON \
        -DCURL_DISABLE_DICT=ON \
        -DCURL_DISABLE_FILE=ON \
        -DCURL_DISABLE_FTP=ON \
        -DCURL_DISABLE_GOPHER=ON \
        -DCURL_DISABLE_IMAP=ON \
        -DCURL_DISABLE_MQTT=ON \
        -DCURL_DISABLE_POP3=ON \
        -DCURL_DISABLE_RTSP=ON \
        -DCURL_DISABLE_SMB=ON \
        -DCURL_DISABLE_SMTP=ON \
        -DCURL_DISABLE_TELNET=ON \
        -DCURL_DISABLE_TFTP=ON
fi
if test ! -e "$PREFIX/lib/libcurl.so.4" ||
    test ! -e "$PREFIX/include/curl/curl.h"; then
    cmake_run --build "$curl_build" --parallel "$BUILD_JOBS"
    cmake_run --install "$curl_build"
fi

ffmpeg_build="$BUILD_ROOT/ffmpeg"
ffmpeg_patch_hash="$(sha256sum "$FFMPEG_V4L2_PATCH" "$FFMPEG_V4L2_USERPTR_PATCH" |
    sha256sum | awk '{print $1}')"
ffmpeg_build_stamp="$PREFIX/.silisili-ffmpeg-v4l2-$ffmpeg_patch_hash"
ffmpeg_reconfigured=0
ffmpeg_requires_configure=0
if test -e "$ffmpeg_build/config.h" &&
    { ! grep -Fq '#define CONFIG_V4L2_M2M 1' "$ffmpeg_build/config.h" ||
      ! grep -Fq '#define CONFIG_012V_DECODER 0' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_AEVAL_FILTER 0' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_SCALE_FILTER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_H264_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_HEVC_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_AAC_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_H264_V4L2M2M_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_HEVC_V4L2M2M_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_VP8_V4L2M2M_DECODER 1' "$ffmpeg_build/config_components.h" ||
      ! grep -Fq '#define CONFIG_VP9_V4L2M2M_DECODER 1' "$ffmpeg_build/config_components.h"; }; then
    # Reconfigure in place so format/filter/common objects compiled with the
    # same ABI and flags remain reusable. Only the decoder selection changes.
    ffmpeg_requires_configure=1
fi
if test ! -e "$ffmpeg_build/Makefile" || test "$ffmpeg_requires_configure" -eq 1; then
    install -d -m0755 "$ffmpeg_build"
    (
        cd "$ffmpeg_build"
        # Use numeric UAPI constants instead of force-including a C header:
        # FFmpeg also passes extra C flags to .S feature probes, where a
        # videodev2 struct declaration would be parsed as assembler.
        PATH="$CROSS_BIN:$PATH" \
            PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" \
            "$FFMPEG_SOURCE/configure" \
            --prefix="$PREFIX" \
            --libdir="$PREFIX/lib" \
            --shlibdir="$PREFIX/lib" \
            --arch=aarch64 \
            --target-os=linux \
            --enable-cross-compile \
            --cross-prefix="$CROSS_PREFIX-" \
            --cc="$CROSS_PREFIX-gcc -B$CROSS_PREFIX-" \
            --cxx="$CROSS_PREFIX-g++ -B$CROSS_PREFIX-" \
            --pkg-config=/usr/bin/pkg-config \
            --sysroot="$TARGET_SYSROOT" \
            --enable-shared \
            --disable-static \
            --disable-programs \
            --disable-doc \
            --disable-debug \
            --disable-avdevice \
            --disable-postproc \
            --disable-decoders \
            --disable-encoders \
            --disable-filters \
            --disable-muxers \
            --disable-autodetect \
            --enable-v4l2-m2m \
            --enable-decoder=h264_v4l2m2m \
            --enable-decoder=hevc_v4l2m2m \
            --enable-decoder=vp8_v4l2m2m \
            --enable-decoder=vp9_v4l2m2m \
            --enable-decoder=h264 \
            --enable-decoder=hevc \
            --enable-decoder=vp8 \
            --enable-decoder=vp9 \
            --enable-decoder=av1 \
            --enable-decoder=mpeg1video \
            --enable-decoder=mpeg2video \
            --enable-decoder=mpeg4 \
            --enable-decoder=h263 \
            --enable-decoder=theora \
            --enable-decoder=aac \
            --enable-decoder=aac_fixed \
            --enable-decoder=mp3 \
            --enable-decoder=mp3float \
            --enable-decoder=flac \
            --enable-decoder=opus \
            --enable-decoder=vorbis \
            --enable-decoder=alac \
            --enable-decoder=ac3 \
            --enable-decoder=eac3 \
            --enable-decoder=dca \
            --enable-decoder=truehd \
            --enable-decoder=pcm_s16le \
            --enable-decoder=pcm_s24le \
            --enable-decoder=pcm_s32le \
            --enable-decoder=pcm_f32le \
            --enable-decoder=pcm_f64le \
            --enable-decoder=ass \
            --enable-decoder=ssa \
            --enable-decoder=subrip \
            --enable-decoder=webvtt \
            --enable-decoder=movtext \
            --enable-decoder=dvdsub \
            --enable-decoder=dvbsub \
            --enable-decoder=png \
            --enable-decoder=mjpeg \
            --enable-decoder=gif \
            --enable-decoder=webp \
            --enable-filter=aformat \
            --enable-filter=aresample \
            --enable-filter=anull \
            --enable-filter=format \
            --enable-filter=null \
            --enable-filter=scale \
            --enable-filter=fps \
            --enable-filter=framerate \
            --enable-filter=setpts \
            --enable-filter=crop \
            --enable-filter=pad \
            --enable-filter=rotate \
            --enable-filter=transpose \
            --enable-filter=yadif \
            --enable-filter=bwdif \
            --enable-network \
            --enable-openssl \
            --enable-zlib \
            --enable-pthreads \
            --extra-cflags="-I$PREFIX/include $V4L2_COMPAT_CFLAGS -fPIC" \
            --extra-ldflags="-L$PREFIX/lib -Wl,-rpath,$PRIVATE_RPATH -Wl,-rpath-link,$TARGET_SYSROOT/lib64 -Wl,-rpath-link,$TARGET_SYSROOT/usr/lib64" \
            --extra-libs="-ldl -lpthread"
    )
    ffmpeg_reconfigured=1
fi
if test "$ffmpeg_reconfigured" -eq 1 ||
    test ! -e "$ffmpeg_build_stamp" ||
    test ! -e "$PREFIX/lib/libavformat.so.59" ||
    test ! -e "$PREFIX/include/libavformat/avformat.h"; then
    env PATH="$CROSS_BIN:$PATH" "$MAKE" -C "$ffmpeg_build" -j"$BUILD_JOBS"
    env PATH="$CROSS_BIN:$PATH" "$MAKE" -C "$ffmpeg_build" install
    touch "$ffmpeg_build_stamp"
fi
grep -Fq '#define CONFIG_V4L2_M2M 1' "$ffmpeg_build/config.h" ||
    fail 'private FFmpeg hardware support missing: CONFIG_V4L2_M2M'
for define in \
    CONFIG_H264_DECODER \
    CONFIG_HEVC_DECODER \
    CONFIG_VP8_DECODER \
    CONFIG_VP9_DECODER \
    CONFIG_AV1_DECODER \
    CONFIG_AAC_DECODER \
    CONFIG_FLAC_DECODER \
    CONFIG_OPUS_DECODER; do
    grep -Fq "#define $define 1" "$ffmpeg_build/config_components.h" ||
        fail "private FFmpeg software fallback missing: $define"
done
for define in \
    CONFIG_AFORMAT_FILTER \
    CONFIG_ARESAMPLE_FILTER \
    CONFIG_FORMAT_FILTER \
    CONFIG_SCALE_FILTER \
    CONFIG_TRANSPOSE_FILTER; do
    grep -Fq "#define $define 1" "$ffmpeg_build/config_components.h" ||
        fail "private FFmpeg playback filter missing: $define"
done
for define in \
    CONFIG_H264_V4L2M2M_DECODER \
    CONFIG_HEVC_V4L2M2M_DECODER \
    CONFIG_VP8_V4L2M2M_DECODER \
    CONFIG_VP9_V4L2M2M_DECODER; do
    grep -Fq "#define $define 1" "$ffmpeg_build/config_components.h" ||
        fail "private FFmpeg hardware decoder missing: $define"
done

libass_build="$BUILD_ROOT/libass"
if test ! -e "$libass_build/build.ninja"; then
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" meson_run setup \
        "$libass_build" "$LIBASS_SOURCE" \
        --buildtype=release \
        --prefix="$PREFIX" \
        --libdir=lib \
        -Ddefault_library=shared \
        -Dfontconfig=enabled \
        -Ddirectwrite=disabled \
        -Dcoretext=disabled \
        -Dlibunibreak=disabled \
        -Dtest=false \
        -Dprofile=false \
        "-Dc_link_args=-Wl,-rpath,$PRIVATE_RPATH"
fi
ninja_run -C "$libass_build" -j"$BUILD_JOBS"
DESTDIR= ninja_run -C "$libass_build" install

libplacebo_build="$BUILD_ROOT/libplacebo"
if test ! -e "$libplacebo_build/build.ninja"; then
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" meson_run setup \
        "$libplacebo_build" "$LIBPLACEBO_SOURCE" \
        --buildtype=release \
        --prefix="$PREFIX" \
        --libdir=lib \
        -Ddefault_library=shared \
        -Dvulkan=disabled \
        -Dopengl=enabled \
        -Dgl-proc-addr=enabled \
        -Dglslang=disabled \
        -Dshaderc=disabled \
        -Dlcms=disabled \
        -Ddovi=disabled \
        -Dlibdovi=disabled \
        -Ddemos=false \
        -Dtests=false \
        -Dbench=false \
        -Dfuzz=false \
        -Dunwind=disabled \
        -Dxxhash=disabled \
        "-Dc_link_args=-Wl,-rpath,$PRIVATE_RPATH" \
        "-Dcpp_link_args=-Wl,-rpath,$PRIVATE_RPATH"
fi
ninja_run -C "$libplacebo_build" -j"$BUILD_JOBS"
DESTDIR= ninja_run -C "$libplacebo_build" install

mpv_build="$BUILD_ROOT/mpv"
mpv_meson_log="$mpv_build/meson-logs/meson-log.txt"
if test -e "$mpv_build/build.ninja" &&
    ! grep -Fq -- "-L$PREFIX/lib -lavcodec" "$mpv_meson_log"; then
    find "$mpv_build" -mindepth 1 -depth -delete
fi
if test ! -e "$mpv_build/build.ninja"; then
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" meson_run setup \
        "$mpv_build" "$MPV_SOURCE" \
        --buildtype=release \
        --prefix="$PREFIX" \
        --libdir=lib \
        -Ddefault_library=shared \
        -Dcplayer=false \
        -Dlibmpv=true \
        -Dbuild-date=false \
        -Dtests=false \
        -Dcplugins=disabled \
        -Djavascript=disabled \
        -Dlcms2=disabled \
        -Dlibarchive=disabled \
        -Dlibavdevice=disabled \
        -Dlibbluray=disabled \
        -Dlua=disabled \
        -Drubberband=disabled \
        -Duchardet=disabled \
        -Dvapoursynth=disabled \
        -Dzimg=disabled \
        -Dalsa=disabled \
        -Djack=disabled \
        -Dpipewire=disabled \
        -Dpulse=enabled \
        -Doss-audio=disabled \
        -Dsndio=disabled \
        -Dcaca=disabled \
        -Ddrm=disabled \
        -Degl=disabled \
        -Degl-drm=disabled \
        -Degl-wayland=disabled \
        -Dgbm=disabled \
        -Dgl=enabled \
        -Dplain-gl=enabled \
        -Djpeg=disabled \
        -Dshaderc=disabled \
        -Dspirv-cross=disabled \
        -Dsixel=disabled \
        -Dvaapi=disabled \
        -Dvdpau=disabled \
        -Dvulkan=disabled \
        -Dwayland=disabled \
        -Dx11=disabled \
        -Dxv=disabled \
        -Dmanpage-build=disabled \
        "-Dc_link_args=-Wl,-rpath,$PRIVATE_RPATH"
fi
grep -Fq -- "-L$PREFIX/lib -lavcodec" "$mpv_meson_log" ||
    fail "mpv Meson configuration does not use the private FFmpeg"
ninja_run -C "$mpv_build" -j"$BUILD_JOBS"
DESTDIR= ninja_run -C "$mpv_build" install

for library in \
    libcrypto.so.3 libssl.so.3 libcurl.so.4 libass.so.9 \
    libavcodec.so.59 libavfilter.so.8 libavformat.so.59 libavutil.so.57 \
    libswresample.so.4 libswscale.so.6 libplacebo.so.338 libmpv.so.2; do
    test -e "$PREFIX/lib/$library" || fail "missing private runtime: $library"
done

grep -aFq 'https' "$PREFIX/lib/libavformat.so.59" ||
    fail "private FFmpeg lacks HTTPS protocol support"
for decoder in h264_v4l2m2m hevc_v4l2m2m vp8_v4l2m2m vp9_v4l2m2m; do
    grep -aFq "$decoder" "$PREFIX/lib/libavcodec.so.59" ||
        fail "installed private FFmpeg lacks $decoder"
done

while IFS= read -r -d '' elf; do
    readelf -h "$elf" >/dev/null 2>&1 || continue
    readelf -h "$elf" | grep -Fq AArch64 || fail "non-AArch64 ELF: $elf"
    readelf -d "$elf" | grep -Fq "$PRIVATE_RPATH" ||
        fail "private RPATH missing: $elf"
done < <(find "$PREFIX/lib" -maxdepth 1 -type f -name '*.so.*' -print0)

verify_glibc_ceiling "$PREFIX/lib"
echo "Sailfish 5.0/5.1 private runtime ready: $PREFIX"
