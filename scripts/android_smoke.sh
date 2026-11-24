#!/usr/bin/env bash
set -euo pipefail
apk="${1:?APK required}"
badging="$("$ANDROID_HOME/build-tools/36.0.0/aapt2" dump badging "$apk")"
pkg="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")"
test "$pkg" = 'com.omniplayer.app.omni_player'
adb logcat -c
adb install "$apk"
adb shell pm path "$pkg"
adb shell am start -W -n "$pkg/.MainActivity"
sleep 15
if ! adb shell pidof "$pkg"; then adb logcat -d -t 800; exit 1; fi
adb exec-out screencap -p > android-smoke.png
test -s android-smoke.png
echo "Installed and process running: $pkg"
python3 scripts/android_playback_smoke.py omni-smoke-video.mp4
