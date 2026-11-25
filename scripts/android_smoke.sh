#!/usr/bin/env bash
set -euo pipefail
apk="${1:?APK required}"
fixture="${2:?Playback fixture required}"
pkg=com.omniplayer.app.omni_player
mkdir -p android-smoke

collect_diagnostics() {
  local status=$?
  if (( status != 0 )); then
    echo "Android smoke test failed with exit code $status." >&2
    timeout 15s adb devices -l > android-smoke/devices.txt 2>&1 || true
    timeout 20s adb logcat -d -t 1000 > android-smoke/logcat.txt 2>&1 || true
    timeout 15s adb shell dumpsys activity activities > android-smoke/activities.txt 2>&1 || true
    timeout 15s adb exec-out screencap -p > android-smoke/failure.png || true
    if [[ ! -s android-smoke/failure.png ]]; then rm -f android-smoke/failure.png; fi
  fi
}
trap collect_diagnostics EXIT

adb logcat -c
echo 'Installing universal APK'
timeout 120s adb install "$apk"
timeout 20s adb shell pm path "$pkg"
echo 'Launching Omni Player'
launch="$(timeout 90s adb shell am start -W -n "$pkg/.MainActivity")"
printf '%s\n' "$launch"
if ! grep -q '^Status: ok' <<< "$launch"; then exit 1; fi
timeout 20s adb shell pidof "$pkg"
timeout 20s adb exec-out screencap -p > android-smoke/launch.png
test -s android-smoke/launch.png
echo "Installed and process running: $pkg"
python3 scripts/android_playback_smoke.py "$fixture"
