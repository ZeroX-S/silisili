#!/bin/sh
set -eu

brightness_original="$(mcetool -N 2>/dev/null | awk '/Brightness:/ { print $2; exit }')"
if [ -n "$brightness_original" ]; then
    if [ "$brightness_original" -gt 50 ]; then
        brightness_target=$((brightness_original - 5))
    else
        brightness_target=$((brightness_original + 5))
    fi
    mcetool --set-display-brightness="$brightness_target" >/dev/null
    brightness_changed="$(mcetool -N 2>/dev/null | awk '/Brightness:/ { print $2; exit }')"
    mcetool --set-display-brightness="$brightness_original" >/dev/null
    brightness_restored="$(mcetool -N 2>/dev/null | awk '/Brightness:/ { print $2; exit }')"
    printf 'system_controls_transaction_brightness=original:%s,target:%s,changed:%s,restored:%s\n' \
        "$brightness_original" "$brightness_target" "$brightness_changed" "$brightness_restored"
else
    printf 'system_controls_transaction_brightness=unavailable\n'
fi

runtime=/run/user/100000
pulse_server="unix:$runtime/pulse/native"
if [ -S "$runtime/pulse/native" ] && id defaultuser >/dev/null 2>&1; then
    volume_original="$(runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR="$runtime" \
        PULSE_SERVER="$pulse_server" \
        pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
        | grep -o '[0-9][0-9]*%' | head -1 | tr -d '%')"
    if [ -n "$volume_original" ]; then
        if [ "$volume_original" -gt 50 ]; then
            volume_target=$((volume_original - 5))
        else
            volume_target=$((volume_original + 5))
        fi
        runuser -u defaultuser -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="$pulse_server" \
            pactl set-sink-volume @DEFAULT_SINK@ "${volume_target}%" >/dev/null
        volume_changed="$(runuser -u defaultuser -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="$pulse_server" \
            pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
            | grep -o '[0-9][0-9]*%' | head -1 | tr -d '%')"
        runuser -u defaultuser -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="$pulse_server" \
            pactl set-sink-volume @DEFAULT_SINK@ "${volume_original}%" >/dev/null
        volume_restored="$(runuser -u defaultuser -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="$pulse_server" \
            pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null \
            | grep -o '[0-9][0-9]*%' | head -1 | tr -d '%')"
        printf 'system_controls_transaction_volume=original:%s,target:%s,changed:%s,restored:%s\n' \
            "$volume_original" "$volume_target" "$volume_changed" "$volume_restored"
    else
        printf 'system_controls_transaction_volume=unavailable\n'
    fi
else
    printf 'system_controls_transaction_volume=unavailable\n'
fi

printf 'system_controls_transaction=ready|visual_model=unused\n'
