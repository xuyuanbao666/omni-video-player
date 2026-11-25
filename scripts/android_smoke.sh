#!/usr/bin/env bash
set -euo pipefail
apk="${1:?APK required}"
fixture="${2:?Playback fixture required}"
pkg=com.omniplayer.app.omni_player
mkdir -p android-smoke
logcat_pid=''

collect_diagnostics() {
  local status=$?
  if [[ -n "$logcat_pid" ]]; then
    kill "$logcat_pid" 2>/dev/null || true
    wait "$logcat_pid" 2>/dev/null || true
  fi
  if (( status != 0 )); then
    echo "Android smoke test failed with exit code $status." >&2
    timeout 15s adb devices -l > android-smoke/devices.txt 2>&1 || true
    sudo dmesg --ctime | tail -n 120 > android-smoke/host-kernel.txt || true
    grep -Ei 'out of memory|oom-kill|killed process|segfault' android-smoke/host-kernel.txt >&2 || true
    timeout 15s adb shell dumpsys activity activities > android-smoke/activities.txt 2>&1 || true
    timeout 15s adb exec-out screencap -p > android-smoke/failure.png || true
    if [[ ! -s android-smoke/failure.png ]]; then rm -f android-smoke/failure.png; fi
  fi
}
trap collect_diagnostics EXIT

adb logcat -c
adb logcat -b all -v threadtime > android-smoke/logcat.txt 2>&1 &
logcat_pid=$!
echo 'Installing universal APK'
timeout 120s adb install "$apk"
timeout 20s adb shell pm path "$pkg"
echo 'Launching Omni Player'
timeout 90s adb shell am start -W -n "$pkg/.MainActivity" | tee android-smoke/launch.txt
grep -q '^Status: ok' android-smoke/launch.txt
timeout 20s adb shell pidof "$pkg"
timeout 20s adb exec-out screencap -p > android-smoke/launch.png
test -s android-smoke/launch.png
echo "Installed and process running: $pkg"
python3 scripts/android_playback_smoke.py "$fixture"
