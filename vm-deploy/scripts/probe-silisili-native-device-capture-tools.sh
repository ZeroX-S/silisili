#!/bin/sh
set -u
printf 'capture_tools_user='; id
printf 'capture_tools_screendump='; command -v screendump || true
printf 'capture_tools_lipstick_screenshot='; command -v lipstick-screenshot || true
printf 'capture_tools_screenshot='; command -v screenshot || true
printf 'capture_tools_grim='; command -v grim || true
printf 'capture_tools_tmp='; ls -l /tmp/bonito-* 2>/dev/null || true
