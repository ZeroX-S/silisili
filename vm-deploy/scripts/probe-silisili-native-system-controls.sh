#!/bin/sh
set -eu

printf 'system_controls_probe_user='
id
printf 'system_controls_release='
cat /etc/sailfish-release 2>/dev/null | tr '\n' '|' || true
printf '\n'
printf 'system_controls_defaultuser='
id defaultuser 2>/dev/null || true
printf 'system_controls_users='
getent passwd 2>/dev/null \
    | awk -F: '$3 >= 1000 || $1 ~ /^(defaultuser|nemo)$/ {print $1 ":" $3 ":" $6}' \
    | tr '\n' ','
printf '\n'
printf 'system_controls_backlight_paths='
find /sys/class/backlight /sys/class/leds -maxdepth 2 \
    \( -name brightness -o -name max_brightness \) -print 2>/dev/null \
    | tr '\n' ','
printf '\n'
printf 'system_controls_any_brightness_paths='
find /sys /sys/devices /sys/kernel -maxdepth 6 \
    \( -name brightness -o -name max_brightness -o -name bl_power \) \
    -print 2>/dev/null | head -120 | tr '\n' ','
printf '\n'

for brightness_file in $(find /sys/class/backlight /sys/class/leds \
        -maxdepth 2 -name brightness -print 2>/dev/null | head -10); do
    max_file=${brightness_file%/brightness}/max_brightness
    printf 'system_controls_brightness_file=path:%s,readable:%s,writable:%s,value:' \
        "$brightness_file" \
        "$(test -r "$brightness_file" && echo 1 || echo 0)" \
        "$(test -w "$brightness_file" && echo 1 || echo 0)"
    cat "$brightness_file" 2>/dev/null || true
    printf 'system_controls_brightness_max=path:%s,readable:%s,value:' \
        "$max_file" \
        "$(test -r "$max_file" && echo 1 || echo 0)"
    cat "$max_file" 2>/dev/null || true
done

printf 'system_controls_pactl='
command -v pactl || true
printf 'system_controls_run_user_tree='
find /run/user -maxdepth 4 \( -type d -o -type s \) -print 2>/dev/null \
    | sort | tr '\n' ','
printf '\n'
for runtime in /run/user/*; do
    test -d "$runtime" || continue
    uid=${runtime##*/}
    printf 'system_controls_pulse_socket=uid:%s,' "$uid"
    ls -l "$runtime/pulse/native" 2>/dev/null || true
    for user in defaultuser nemo root; do
        id "$user" >/dev/null 2>&1 || continue
        printf 'system_controls_pactl_info=user:%s,uid:%s,' "$user" "$uid"
        runuser -u "$user" -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="unix:$runtime/pulse/native" \
            pactl info 2>&1 | tr '\n' '|' || true
        printf '\n'
        printf 'system_controls_default_sink=user:%s,uid:%s,' "$user" "$uid"
        runuser -u "$user" -- env \
            XDG_RUNTIME_DIR="$runtime" \
            PULSE_SERVER="unix:$runtime/pulse/native" \
            pactl get-default-sink 2>&1 | tr '\n' '|' || true
        printf '\n'
    done
done
pactl info 2>&1 | sed 's/^/system_controls_pactl_root_default=/' || true
pactl get-default-sink 2>&1 | sed 's/^/system_controls_root_default_sink=/' || true
pactl list sinks 2>/dev/null \
    | grep -E 'Sink #|Name:|Volume:|Mute:' \
    | sed 's/^/system_controls_sink_line=/' \
    | head -80 || true
printf 'system_controls_audio_commands='
for command in pacmd pulseaudio pactl wpctl pw-cli amixer; do
    command -v "$command" >/dev/null 2>&1 && printf '%s:%s,' "$command" "$(command -v "$command")"
done
printf '\n'

printf 'system_controls_mce_methods='
gdbus introspect --system --dest com.nokia.mce \
    --object-path /com/nokia/mce/request 2>/dev/null \
    | grep -Ei 'brightness|display|blank|dim' | tr '\n' ';' || true
printf '\n'
printf 'system_controls_mcetool_help='
mcetool --help 2>&1 | grep -Ei 'brightness|display|blank|dim' | tr '\n' ';' || true
printf '\n'
printf 'system_controls_mcetool_status='
mcetool -N 2>&1 | grep -Ei 'brightness|display|blank|dim' | tr '\n' ';' || true
printf '\n'
printf 'system_controls_probe=ready|visual_model=unused\n'
