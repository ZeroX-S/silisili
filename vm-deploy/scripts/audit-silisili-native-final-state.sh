#!/bin/sh
set -eu

printf 'audit_package='
rpm -q --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}' silisili-native-devel
printf 'audit_verify='
rpm -V silisili-native-devel
printf 'audit_session='
if test -f /home/defaultuser/.config/cn.silisili.native/account_session.json; then
    sed -n 's/.*"logged_out"[[:space:]]*:[[:space:]]*\(true\|false\).*/logged_out=\1/p' \
        /home/defaultuser/.config/cn.silisili.native/account_session.json | head -1
    grep -o '"SESSDATA"' \
        /home/defaultuser/.config/cn.silisili.native/account_session.json | head -1 || true
    grep -o '"DedeUserID"' \
        /home/defaultuser/.config/cn.silisili.native/account_session.json | head -1 || true
else
    printf 'absent\n'
fi
printf 'audit_settings='
settings=/home/defaultuser/.config/cn.silisili.native/silisili-native.conf
if test -f "$settings"; then
    printf 'background_mode=%s|content_columns=%s|font_size_mode=%s\n' \
        "$(sed -n 's/^backgroundPresentationMode=//p' "$settings" | tail -1)" \
        "$(sed -n 's/^contentColumns=//p' "$settings" | tail -1)" \
        "$(sed -n 's/^fontSizeMode=//p' "$settings" | tail -1)"
else
    printf 'absent\n'
fi
printf 'audit_processes='
pgrep -af '^/usr/bin/silisili-native' 2>/dev/null | tr '\n' ',' || true
printf '\n'
