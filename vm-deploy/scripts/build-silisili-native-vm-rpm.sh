#!/usr/bin/env bash
set -euo pipefail

project=${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}
output=${OUTPUT_DIR:-$(cd "$project/../.." && pwd)/outputs}
sdk=${SDK_CHROOT:-/opt/sailfish-hadk/platform/sdks/sfossdk/sdk-chroot}
# The active validation device runs 5.1.0.11. Keep TARGET overridable for
# compatibility experiments, but build the development RPM against the tested
# device SDK rather than silently relying on the currently broken 5.0 target.
target="${TARGET:-SailfishOS-5.1.0.11-aarch64}"
build=${BUILD_ROOT:-/home/builder/silisili-native-build}
source_copy=${SOURCE_COPY:-/home/builder/silisili-native-source}
work=${WORK_ROOT:-/home/builder/silisili-native-package}
media_prefix=/opt/sailfish-hadk/home/mersdk/silisili-5x-build/prefix
media_stage=/opt/sailfish-hadk/home/mersdk/silisili-5x-app-build/stage
media_copy=${MEDIA_COPY:-/home/builder/silisili-native-media}
qrcode_source=$project/library/QR-Code-generator/cpp
qrcode_license=$project/library/QR-Code-generator/Readme.markdown
reuse_objects="${REUSE_OBJECTS:-0}"
app_version=$(awk '$1 == "Version:" { print $2; exit }' \
    "$project/packaging/apps/silisili-native/silisili-native.spec")
package_release=${PACKAGE_RELEASE_OVERRIDE:-$(awk '$1 == "Release:" { print $2; exit }' \
    "$project/packaging/apps/silisili-native/silisili-native.spec")}
test -n "$app_version" -a -n "$package_release"
printf '%s\n' "$package_release" | grep -Eq '^[0-9A-Za-z][0-9A-Za-z._+]*$'

sysroot=${SYSROOT:-/home/builder/silisili-native-sysroot}
glibc_ceiling=${GLIBC_CEILING:-GLIBC_2.34}
glibcxx_ceiling=${GLIBCXX_CEILING:-GLIBCXX_3.4.32}
cxxabi_ceiling=${CXXABI_CEILING:-CXXABI_1.3.13}
for path in "$build" "$source_copy" "$work" "$media_copy" "$sysroot"; do
    case "$path" in
        /home/builder/*) ;;
        *) printf 'unsafe builder path: %s\n' "$path" >&2; exit 1 ;;
    esac
done
if test "$reuse_objects" = 1; then
    test -d "$build" -a -d "$source_copy" -a -d "$media_copy" -a -d "$sysroot"
    # Host and VM clocks can differ. Invalidate changed inputs by content
    # before copying, so a newer VM object cannot conceal a source edit.
    for input in "$project/native/src/"*.cpp "$project/native/src/"*.h; do
        relative=${input#"$project/native/"}
        if ! cmp -s "$input" "$source_copy/$relative"; then
            input_name=${input##*/}
            case "$input_name" in
                *.h)
                    generated="$build/moc_${input_name%.h}.cpp"
                    if test -f "$generated"; then
                        mv "$generated" "$generated.previous"
                    fi
                    generated_object="$build/moc_${input_name%.h}.o"
                    if test -f "$generated_object"; then
                        mv "$generated_object" "$generated_object.previous"
                    fi
                    ;;
            esac
            for unit in "$project/native/src/"*.cpp; do
                if test "$unit" = "$input" \
                        || grep -Fq "#include \"$input_name\"" "$unit"; then
                    object="$build/$(basename "$unit" .cpp).o"
                    if test -f "$object"; then
                        mv "$object" "$object.previous"
                    fi
                fi
            done
        fi
    done
    # Refresh changed sources while preserving mtimes. Object checks below can
    # then rebuild touched modules without silently packaging stale sources.
    cp -a "$project/native/." "$source_copy/"
    install -d -m0755 "$source_copy/third_party/qrcodegen"
    cp -a "$qrcode_source/." "$source_copy/third_party/qrcodegen/"
    chown -R builder:builder "$source_copy"
else
    rm -rf "$build" "$source_copy" "$work" "$media_copy"
    install -d -m0755 -o builder -g builder "$build"
    cp -a "$project/native" "$source_copy"
    install -d -m0755 "$source_copy/third_party/qrcodegen"
    cp -a "$qrcode_source/." "$source_copy/third_party/qrcodegen/"
    chown -R builder:builder "$source_copy"
    install -d -m0755 -o builder -g builder "$media_copy/include"
    cp -a "$media_prefix/include/mpv" "$media_copy/include/"
    cp -a "$media_stage/lib" "$media_copy/lib"
    chown -R builder:builder "$media_copy"
    if mountpoint -q "$sysroot"; then umount "$sysroot"; fi
    rm -rf "$sysroot"
    install -d -m0755 "$sysroot"
    cp -al "/opt/sailfish-hadk/platform/targets/$target/." "$sysroot/"
    chown builder:builder "$sysroot"
fi
install -d -m0755 "$work/stage" "$work/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS} "$output"

# Compile the small Android compatibility shim from the current checkout.
arm-linux-gnueabihf-gcc -march=armv7-a -mfloat-abi=softfp \
    -fPIC -fvisibility=hidden -nostdlib -nodefaultlibs -shared \
    -Wl,--hash-style=both -Wl,-soname,libminimedia-audiosource-shim.so \
    "$project/packaging/apps/silisili-native/minimediaservice-audiosource-shim.c" \
    -o "$output/libminimedia-audiosource-shim.so"
identity="$app_version-$package_release"
if test "$reuse_objects" = 1 \
        && test "$(cat "$build/.package-identity" 2>/dev/null || true)" != "$identity"; then
    # main.cpp is the only source consuming the package-version defines.
    if test -f "$build/main.o"; then mv "$build/main.o" "$build/main.o.previous"; fi
fi

flags="-O2 -g0 -fPIC -fPIE -fno-ident -ffile-prefix-map=$source_copy=/usr/src/silisili-native-1.1.0 -ffile-prefix-map=$build=/usr/src/silisili-native-build -DSILISILI_NATIVE_APP_VERSION='\"$app_version\"' -DSILISILI_NATIVE_PACKAGE_RELEASE='\"$package_release\"' -DSILISILI_NATIVE_PACKAGE_NAME='\"silisili-native-devel\"' -DSILISILI_NATIVE_HAVE_DROIDMEDIA=1"
ldflags="-pie -Wl,-z,relro,-z,now,--build-id=none"
"$sdk" -u builder -m all /bin/bash -lc "
set -euo pipefail
cd '$build'
tooling=/srv/mer/toolings/SailfishOS-5.0.0.62-i486
targetroot='$sysroot'
cross=/opt/cross/bin/aarch64-meego-linux-gnu
crossdir=/home/builder/silisili-cross-bin
mkdir -p \"\$crossdir\"
ln -sf /opt/cross/bin/aarch64-meego-linux-gnu-as \"\$crossdir/as\"
ln -sf /opt/cross/bin/aarch64-meego-linux-gnu-ld \"\$crossdir/ld\"
export PATH=\"\$crossdir:\$PATH\"
sb2 -t '$target' -m tools test -f \"\$targetroot/usr/include/qt5/QtCore/QString\"
moc_if_needed() {
    input=\"\$1\"
    output=\"\$2\"
    if test '$reuse_objects' != 1 || test ! -f \"\$output\" || test \"\$input\" -nt \"\$output\"; then
        sb2 -t '$target' -m tools /usr/lib/qt5/bin/moc \"\$input\" -o \"\$output\"
    fi
}
moc_if_needed '$source_copy/src/bilibiliimagenetwork.h' moc_bilibiliimagenetwork.cpp
moc_if_needed '$source_copy/src/homefeedmodel.h' moc_homefeedmodel.cpp
moc_if_needed '$source_copy/src/searchmodel.h' moc_searchmodel.cpp
moc_if_needed '$source_copy/src/videodetailmodel.h' moc_videodetailmodel.cpp
moc_if_needed '$source_copy/src/accountservice.h' moc_accountservice.cpp
moc_if_needed '$source_copy/src/accountlibrarymodel.h' moc_accountlibrarymodel.cpp
moc_if_needed '$source_copy/src/qrcodeitem.h' moc_qrcodeitem.cpp
moc_if_needed '$source_copy/src/regionfeedmodel.h' moc_regionfeedmodel.cpp
moc_if_needed '$source_copy/src/dynamicfeedmodel.h' moc_dynamicfeedmodel.cpp
moc_if_needed '$source_copy/src/inboxmodel.h' moc_inboxmodel.cpp
moc_if_needed '$source_copy/src/commentmodel.h' moc_commentmodel.cpp
moc_if_needed '$source_copy/src/relatedmodel.h' moc_relatedmodel.cpp
moc_if_needed '$source_copy/src/playbackresolver.h' moc_playbackresolver.cpp
moc_if_needed '$source_copy/src/mpvvideoitem.h' moc_mpvvideoitem.cpp
moc_if_needed '$source_copy/src/playbacksession.h' moc_playbacksession.cpp
moc_if_needed '$source_copy/src/mpriscontroller.h' moc_mpriscontroller.cpp
moc_if_needed '$source_copy/src/displayframemonitor.h' moc_displayframemonitor.cpp
moc_if_needed '$source_copy/src/systempipcontroller.h' moc_systempipcontroller.cpp
moc_if_needed '$source_copy/src/appsettings.h' moc_appsettings.cpp
moc_if_needed '$source_copy/src/systemcontrols.h' moc_systemcontrols.cpp
moc_if_needed '$source_copy/src/danmakumodel.h' moc_danmakumodel.cpp
moc_if_needed '$source_copy/src/livefeedmodel.h' moc_livefeedmodel.cpp
moc_if_needed '$source_copy/src/liveresolver.h' moc_liveresolver.cpp
moc_if_needed '$source_copy/src/pgcfeedmodel.h' moc_pgcfeedmodel.cpp
moc_if_needed '$source_copy/src/pgcdetailmodel.h' moc_pgcdetailmodel.cpp
moc_if_needed '$source_copy/src/authorspacemodel.h' moc_authorspacemodel.cpp
if test '$reuse_objects' != 1 || test ! -f qrc_qml.cpp \
        || find '$source_copy/qml' -type f -newer qrc_qml.cpp -print -quit | grep -q .; then
    sb2 -t '$target' -m tools /usr/lib/qt5/bin/rcc -name qml '$source_copy/qml/qml.qrc' -o qrc_qml.cpp
fi
includes=\"-I$source_copy/src -I$source_copy/third_party/qrcodegen -I$media_copy/include -I\$targetroot/usr/include/droidmedia -I\$targetroot/usr/include/sailfishapp -I\$targetroot/usr/include/mdeclarativecache5 -I\$targetroot/usr/include/qt5 -I\$targetroot/usr/include/qt5/QtCore -I\$targetroot/usr/include/qt5/QtDBus -I\$targetroot/usr/include/qt5/QtGui -I\$targetroot/usr/include/qt5/QtGui/5.6.3 -I\$targetroot/usr/include/qt5/QtGui/5.6.3/QtGui -I\$targetroot/usr/include/qt5/QtMultimedia -I\$targetroot/usr/include/qt5/QtNetwork -I\$targetroot/usr/include/qt5/QtQml -I\$targetroot/usr/include/qt5/QtQuick\"
compile_count=0
for source in '$source_copy/src/main.cpp' '$source_copy/src/bilibiliimagenetwork.cpp' '$source_copy/src/networkutils.cpp' '$source_copy/src/homefeedmodel.cpp' '$source_copy/src/searchmodel.cpp' '$source_copy/src/videodetailmodel.cpp' '$source_copy/src/accountservice.cpp' '$source_copy/src/accountlibrarymodel.cpp' '$source_copy/src/qrcodeitem.cpp' '$source_copy/src/regionfeedmodel.cpp' '$source_copy/src/dynamicfeedmodel.cpp' '$source_copy/src/inboxmodel.cpp' '$source_copy/src/commentmodel.cpp' '$source_copy/src/relatedmodel.cpp' '$source_copy/src/playbackresolver.cpp' '$source_copy/src/mpvvideoitem.cpp' '$source_copy/src/droidvideodecoder.cpp' '$source_copy/src/playbacksession.cpp' '$source_copy/src/mpriscontroller.cpp' '$source_copy/src/displayframemonitor.cpp' '$source_copy/src/systempipcontroller.cpp' '$source_copy/src/appsettings.cpp' '$source_copy/src/systemcontrols.cpp' '$source_copy/src/danmakumodel.cpp' '$source_copy/src/livefeedmodel.cpp' '$source_copy/src/liveresolver.cpp' '$source_copy/src/pgcfeedmodel.cpp' '$source_copy/src/pgcdetailmodel.cpp' '$source_copy/src/authorspacemodel.cpp' '$source_copy/src/configmigration.cpp' '$source_copy/third_party/qrcodegen/qrcodegen.cpp' moc_bilibiliimagenetwork.cpp moc_homefeedmodel.cpp moc_searchmodel.cpp moc_videodetailmodel.cpp moc_accountservice.cpp moc_accountlibrarymodel.cpp moc_qrcodeitem.cpp moc_regionfeedmodel.cpp moc_dynamicfeedmodel.cpp moc_inboxmodel.cpp moc_commentmodel.cpp moc_relatedmodel.cpp moc_playbackresolver.cpp moc_mpvvideoitem.cpp moc_playbacksession.cpp moc_mpriscontroller.cpp moc_displayframemonitor.cpp moc_systempipcontroller.cpp moc_appsettings.cpp moc_systemcontrols.cpp moc_danmakumodel.cpp moc_livefeedmodel.cpp moc_liveresolver.cpp moc_pgcfeedmodel.cpp moc_pgcdetailmodel.cpp moc_authorspacemodel.cpp qrc_qml.cpp; do
    object=\"\$(basename \"\$source\" .cpp).o\"
    companion=\"\${source%.cpp}.h\"
    if test '$reuse_objects' = 1 && test -f \"\$object\" \
            && test \"\$object\" -nt \"\$source\"; then
        if test ! -f \"\$companion\" || test \"\$object\" -nt \"\$companion\"; then
            continue
        fi
    fi
    sb2 -t '$target' -m tools \"\$cross-g++\" -B\"\$crossdir/\" --sysroot=\"\$targetroot\" $flags -std=gnu++11 -fvisibility=hidden -fvisibility-inlines-hidden -DQT_NO_DEBUG -DQT_QUICK_LIB -DQT_GUI_LIB -DQT_MULTIMEDIA_LIB -DQT_QML_LIB -DQT_NETWORK_LIB -DQT_CORE_LIB \$includes -c \"\$source\" -o \"\$object\" &
    compile_count=\$((compile_count + 1))
    if test \"\$compile_count\" -ge 4; then
        wait -n
        compile_count=\$((compile_count - 1))
    fi
done
while test \"\$compile_count\" -gt 0; do
    wait -n
    compile_count=\$((compile_count - 1))
done
sb2 -t '$target' -m tools \"\$cross-g++\" -B\"\$crossdir/\" --sysroot=\"\$targetroot\" $ldflags -L\"\$targetroot/usr/lib64\" \
    -Wl,-rpath-link,\"\$targetroot/usr/lib64\" -Wl,-rpath-link,\"\$targetroot/lib64\" \
    -L$media_copy/lib -Wl,-rpath-link,$media_copy/lib -Wl,-rpath,/usr/lib64/silisili-native,--disable-new-dtags \
    -o silisili-native main.o bilibiliimagenetwork.o networkutils.o homefeedmodel.o searchmodel.o videodetailmodel.o accountservice.o accountlibrarymodel.o qrcodeitem.o qrcodegen.o regionfeedmodel.o dynamicfeedmodel.o inboxmodel.o commentmodel.o relatedmodel.o playbackresolver.o mpvvideoitem.o droidvideodecoder.o playbacksession.o mpriscontroller.o displayframemonitor.o systempipcontroller.o appsettings.o systemcontrols.o danmakumodel.o livefeedmodel.o liveresolver.o pgcfeedmodel.o pgcdetailmodel.o authorspacemodel.o configmigration.o moc_bilibiliimagenetwork.o moc_homefeedmodel.o moc_searchmodel.o moc_videodetailmodel.o moc_accountservice.o moc_accountlibrarymodel.o moc_qrcodeitem.o moc_regionfeedmodel.o moc_dynamicfeedmodel.o moc_inboxmodel.o moc_commentmodel.o moc_relatedmodel.o moc_playbackresolver.o moc_mpvvideoitem.o moc_playbacksession.o moc_mpriscontroller.o moc_displayframemonitor.o moc_systempipcontroller.o moc_appsettings.o moc_systemcontrols.o moc_danmakumodel.o moc_livefeedmodel.o moc_liveresolver.o moc_pgcfeedmodel.o moc_pgcdetailmodel.o moc_authorspacemodel.o qrc_qml.o \
    -lmpv -lavformat -lavcodec -lavutil -ldroidmedia -ldl -lsailfishapp -lmdeclarativecache5 -lQt5Multimedia -lQt5Quick -lQt5DBus -lQt5Gui -lQt5Qml -lQt5Network -lQt5Core -lEGL -lGLESv2 -lpthread
test -x '$build/silisili-native'
"
printf '%s\n' "$identity" >"$build/.package-identity"

rm -rf "$work/stage" "$work/rpmbuild"
install -d -m0755 "$work/stage" "$work/stage/libexec" \
    "$work/stage/systemd" "$work/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
install -m0755 "$build/silisili-native" "$work/stage/silisili-native"
install -m0644 "$project/packaging/apps/silisili-native/silisili-native.desktop" "$work/stage/silisili-native.desktop"
install -m0644 "$project/packaging/apps/silisili-native/silisili-native.privileges" "$work/stage/silisili-native.privileges"
install -m0644 "$project/packaging/apps/silisili-native/silisili-native-devel.png" "$work/stage/silisili-native-devel.png"
install -m0644 "$project/native/qml/assets/cover-action-pip.png" "$work/stage/silisili-native-cover-pip.png"
install -m0644 "$project/native/qml/assets/cover-action-cover.png" "$work/stage/silisili-native-cover-cover.png"
install -m0755 "$output/libminimedia-audiosource-shim.so" "$work/stage/libexec/libminimedia-audiosource-shim.so"
install -m0755 "$project/packaging/apps/silisili-native/silisili-native-minimedia-wrapper.sh" \
    "$work/stage/libexec/silisili-native-minimedia-wrapper"
install -m0644 "$project/packaging/apps/silisili-native/silisili-native-minimedia.service" \
    "$work/stage/systemd/silisili-native-minimedia.service"
test -f "$work/stage/libexec/libminimedia-audiosource-shim.so"
test -f "$work/stage/systemd/silisili-native-minimedia.service"
test -f "$work/stage/silisili-native.privileges"
test -f "$work/stage/silisili-native-cover-pip.png"
test -f "$work/stage/silisili-native-cover-cover.png"
cp -a "$media_stage/lib" "$work/stage/lib"
install -d -m0755 "$work/stage/licenses"
install -m0644 "$media_stage/licenses/LICENSE.silisili-GPLv3" "$media_stage/licenses/LICENSE.mpv" \
    "$media_stage/licenses/LICENSE.ffmpeg-LGPLv2.1" "$media_stage/licenses/LICENSE.libass" \
    "$media_stage/licenses/LICENSE.libplacebo" "$media_stage/licenses/LICENSE.curl" \
    "$media_stage/licenses/LICENSE.openssl-Apache-2.0" "$work/stage/licenses/"
install -m0644 "$qrcode_license" "$work/stage/licenses/LICENSE.qrcodegen-MIT"
find "$work/stage/lib" -type f -name '*.so*' -exec patchelf --set-rpath /usr/lib64/silisili-native {} +
strip --strip-unneeded --remove-section=.note.gnu.build-id --remove-section=.comment "$work/stage/silisili-native"
readelf -h "$work/stage/silisili-native" | grep -Fq AArch64
readelf -h "$work/stage/silisili-native" | grep -Fq 'Position-Independent Executable'
readelf -l "$work/stage/silisili-native" | grep -Fq GNU_RELRO
readelf -d "$work/stage/silisili-native" | grep -Eq 'BIND_NOW|FLAGS.*NOW'
maximum_symbol() {
    file="$1"
    prefix="$2"
    readelf --version-info "$file" 2>/dev/null |
        grep -oE "${prefix}_[0-9]+(\.[0-9]+)+" | sort -Vu | tail -1 || :
}
assert_symbol_ceiling() {
    file="$1"
    prefix="$2"
    ceiling="$3"
    actual="$(maximum_symbol "$file" "$prefix")"
    if test -n "$actual" \
            && test "$(printf '%s\n%s\n' "$actual" "$ceiling" | sort -V | tail -1)" != "$ceiling"; then
        printf 'ABI ceiling exceeded: file=%s symbol=%s ceiling=%s\n' \
            "$file" "$actual" "$ceiling" >&2
        exit 1
    fi
    printf 'abi_file=%s|family=%s|max=%s|ceiling=%s\n' \
        "${file#$work/stage/}" "$prefix" "${actual:-none}" "$ceiling"
}
abi_files=("$work/stage/silisili-native")
while IFS= read -r file; do
    abi_files+=("$file")
done < <(find "$work/stage/lib" "$work/stage/libexec" -type f -name '*.so*' -print | sort)
for file in "${abi_files[@]}"; do
    readelf -h "$file" >/dev/null
    assert_symbol_ceiling "$file" GLIBC "$glibc_ceiling"
    assert_symbol_ceiling "$file" GLIBCXX "$glibcxx_ceiling"
    assert_symbol_ceiling "$file" CXXABI "$cxxabi_ceiling"
done

temporary_spec="$work/rpmbuild/SPECS/silisili-native.spec"
awk -v release="$package_release" '
    BEGIN { replaced = 0 }
    !replaced && $1 == "Release:" {
        printf "Release:        %s\n", release
        replaced = 1
        next
    }
    { print }
    END { if (!replaced) exit 1 }
' "$project/packaging/apps/silisili-native/silisili-native.spec" >"$temporary_spec"
test "$(awk '$1 == "Release:" { print $2; exit }' "$temporary_spec")" = "$package_release"

rpmbuild -bb \
    --define "_topdir $work/rpmbuild" \
    --define "_buildhost sailfish-native-build" \
    --define "_build_id_links none" \
    --define "stagingdir $work/stage" \
    "$temporary_spec"
rpm_path="$work/rpmbuild/RPMS/aarch64/silisili-native-devel-$app_version-$package_release.aarch64.rpm"
test -f "$rpm_path"
output_rpm="$output/$(basename "$rpm_path")"
install -m0644 "$rpm_path" "$output_rpm"
rpm -K --nosignature "$output_rpm"
rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' "$output_rpm"
sha256sum "$output_rpm"
