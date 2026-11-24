#!/usr/bin/env bash
# Verify a real package replacement with no uninstall and unchanged first install time.
set -euo pipefail
apk="${1:?APK required}"
previous="${2:?Previous APK required}"
tools="$ANDROID_HOME/build-tools/36.0.0"
pkg=com.omniplayer.app.omni_player
badging() { "$tools/aapt2" dump badging "$1"; }
metadata="$(badging "$apk")"
oldmetadata="$(badging "$previous")"
for info in "$metadata" "$oldmetadata"; do
  grep -F "package: name='$pkg'" <<< "$info"
done
version() { sed -n "s/^package: .*versionCode='\([0-9]*\)'.*/\1/p"; }
new="$(version <<< "$metadata")"
old="$(version <<< "$oldmetadata")"
[[ "$new" =~ ^[0-9]+$ && "$old" =~ ^[0-9]+$ ]]
(( new > old ))
adb logcat -c
adb install "$previous"
adb shell am start -W -n "$pkg/.MainActivity"
sleep 12
adb shell pidof "$pkg"
first="$(adb shell dumpsys package "$pkg" | sed -n 's/^[[:space:]]*firstInstallTime=//p' | head -1)"
test -n "$first"
adb install -r "$apk"
second="$(adb shell dumpsys package "$pkg" | sed -n 's/^[[:space:]]*firstInstallTime=//p' | head -1)"
test "$first" = "$second"
adb shell dumpsys package "$pkg" | grep -F "versionCode=$new "
adb shell am start -W -n "$pkg/.MainActivity"
sleep 15
if ! adb shell pidof "$pkg"; then adb logcat -d -t 800; exit 1; fi
adb exec-out screencap -p > android-smoke.png
test -s android-smoke.png
echo "In-place upgrade passed: $old -> $new, original firstInstallTime preserved."
