#!/bin/sh
set -eu

upload_url=${SILISILI_COVER_STOP_UPLOAD_URL:-http://192.168.2.20:18103}

find_icon() {
    name=$1
    find /usr/share/themes /usr/share/icons -type f \
        \( -name "$name.png" -o -name "$name@2x.png" \) \
        2>/dev/null | head -1
}

export_icon() {
    name=$1
    output=$2
    source=$(find_icon "$name")
    test -n "$source"
    test "$(head -c 8 "$source" | od -An -tx1 | tr -d ' \n')" = 89504e470d0a1a0a
    curl -fsS -X PUT --data-binary @"$source" "$upload_url/$output" >/dev/null
    printf 'native_cover_theme_icon=ready|name=%s|source=%s|output=%s|bytes=%s|sha256=%s|visual_model=unused\n' \
        "$name" "$source" "$output" "$(wc -c <"$source")" \
        "$(sha256sum "$source" | awk '{print $1}')"
}

export_icon icon-cover-cancel silisili-theme-icon-cover-cancel.png
export_icon icon-cover-pause silisili-theme-icon-cover-pause.png
export_icon icon-cover-play silisili-theme-icon-cover-play.png
