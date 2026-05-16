#!/bin/sh
printf '\033c\033]0;%s\a' Mobber
base_path="$(dirname "$(realpath "$0")")"
"$base_path/Mobber.x86_64" "$@"
