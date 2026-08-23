#!/bin/sh
set -eu

runtime=/run/user/100000
pulse_server="unix:$runtime/pulse/native"
pactl_user() {
    runuser -u defaultuser -- env \
        XDG_RUNTIME_DIR="$runtime" \
        PULSE_SERVER="$pulse_server" \
        pactl "$@"
}

printf 'volume_diag_package='
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' silisili-native-devel || true
printf 'volume_diag_pids='
pidof silisili-native 2>/dev/null || true
printf '\n'
printf 'volume_diag_pulse_socket='
ls -l "$runtime/pulse/native" 2>/dev/null || true
printf 'volume_diag_pactl_info='
pactl_user info 2>&1 | tr '\n' '|' || true
printf '\n'
printf 'volume_diag_default_sink='
pactl_user get-default-sink 2>&1 | tr '\n' '|' || true
printf '\n'
printf 'volume_diag_sink_volume='
pactl_user get-sink-volume @DEFAULT_SINK@ 2>&1 | tr '\n' '|' || true
printf '\n'
printf 'volume_diag_sink_mute='
pactl_user get-sink-mute @DEFAULT_SINK@ 2>&1 | tr '\n' '|' || true
printf '\n'
printf 'volume_diag_server_modules='
pactl_user list short modules 2>&1 \
    | grep -Ei 'stream-restore|device-restore|role|policy|droid|sink' \
    | tr '\n' ';' || true
printf '\n'
printf 'volume_diag_stream_restore_dbus='
pulse_dbus_address="$(runuser -u defaultuser -- env \
    XDG_RUNTIME_DIR="$runtime" \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$runtime/dbus/user_bus_socket" \
    gdbus call --session --dest org.PulseAudio1 \
    --object-path /org/pulseaudio/server_lookup1 \
    --method org.freedesktop.DBus.Properties.Get \
    org.PulseAudio.ServerLookup1 Address 2>/dev/null \
    | sed -n "s/.*<['\"]\([^'\"]*\)['\"]>.*/\1/p")"
printf 'address:%s,' "$pulse_dbus_address"
if [ -n "$pulse_dbus_address" ]; then
    runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        gdbus introspect --address "$pulse_dbus_address" \
        --object-path /org/pulseaudio/stream_restore1 2>&1 \
        | grep -E 'org.PulseAudio.Ext.StreamRestore1|Entries|GetEntryByName|AddEntry' \
        | tr '\n' ';' || true
fi
printf '\n'
printf 'volume_diag_stream_restore_dbus_raw='
if [ -n "$pulse_dbus_address" ]; then
    runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        dbus-send --peer="$pulse_dbus_address" --print-reply \
        /org/pulseaudio/stream_restore1 \
        org.freedesktop.DBus.Introspectable.Introspect 2>&1 \
        | head -24 | tr '\n' ';' || true
fi
printf '\n'
printf 'volume_diag_stream_restore_entries_begin\n'
if [ -n "$pulse_dbus_address" ]; then
    entry_paths="$(runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        dbus-send --peer="$pulse_dbus_address" --print-reply \
        /org/pulseaudio/stream_restore1 \
        org.freedesktop.DBus.Properties.Get \
        string:org.PulseAudio.Ext.StreamRestore1 string:Entries 2>/dev/null \
        | sed -n 's/.*object path "\([^"]*\)".*/\1/p')"
    for entry_path in $entry_paths; do
        printf 'volume_diag_stream_restore_entry=path:%s,' "$entry_path"
        runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
            dbus-send --peer="$pulse_dbus_address" --print-reply \
            "$entry_path" org.freedesktop.DBus.Properties.GetAll \
            string:org.PulseAudio.Ext.StreamRestore1.RestoreEntry 2>&1 \
            | grep -E 'string "(Name|Device|Volume|Mute)"|string "sink-input|uint32|boolean' \
            | tr '\n' ';' || true
        printf '\n'
    done
fi
printf 'volume_diag_stream_restore_entries_end\n'
printf 'volume_diag_mainvolume_dbus='
if [ -n "$pulse_dbus_address" ]; then
    runuser -u defaultuser -- env XDG_RUNTIME_DIR="$runtime" \
        gdbus introspect --address "$pulse_dbus_address" \
        --object-path /com/meego/mainvolume2 2>&1 \
        | grep -E 'com.Meego.MainVolume2|CurrentStep|StepCount|MediaState' \
        | tr '\n' ';' || true
fi
printf '\n'
pactl_user list sinks 2>&1 \
    | grep -E 'Sink #|Name:|State:|Volume:|Base Volume:|Mute:|device.description|device.class' \
    | sed 's/^/volume_diag_sink=/' \
    | head -220 || true
pactl_user list sink-inputs 2>&1 \
    | sed 's/^/volume_diag_sink_input=/' \
    | head -260 || true
pactl_user list clients 2>&1 \
    | sed 's/^/volume_diag_client=/' \
    | grep -Ei 'Client #|application.name|process.binary|process.id|media.role|application.process' \
    | head -200 || true
printf 'volume_diag_commands='
for command in lipstick-volume-control volumecontrol pulseaudio pactl pacmd dbus-send gdbus busctl; do
    if command -v "$command" >/dev/null 2>&1; then
        printf '%s:%s,' "$command" "$(command -v "$command")"
    fi
done
printf '\n'
printf 'volume_diag_system_services='
busctl --system list 2>/dev/null \
    | grep -Ei 'audio|pulse|volume|media|lipstick|jolla|mce|ohm|route' \
    | tr '\n' ';' || true
printf '\n'
printf 'volume_diag_user_services='
busctl --user --address="unix:path=$runtime/dbus/user_bus_socket" list 2>/dev/null \
    | grep -Ei 'audio|pulse|volume|media|lipstick|jolla|mce|ohm|route' \
    | tr '\n' ';' || true
printf '\n'
printf 'volume_diag_app_journal_begin\n'
for app_pid in $(pidof silisili-native 2>/dev/null || true); do
    journalctl _PID="$app_pid" -n 180 --no-pager 2>/dev/null \
        | grep -Ei 'native system controls|native gesture|pulse|audio|volume' \
        | tail -100 || true
done
printf 'volume_diag_app_journal_end\n'
printf 'volume_diag=ready|visual_model=unused\n'
