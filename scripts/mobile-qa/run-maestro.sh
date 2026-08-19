#!/usr/bin/env bash

set -uo pipefail

RESULTS_DIR="${RESULTS_DIR:-qa-results}"
MAESTRO_TAGS="${MAESTRO_TAGS:-smoke}"
APP_ID="com.snehayog.app"

mkdir -p "$RESULTS_DIR"

mapfile -t apk_files < <(find qa-apk -type f -name '*.apk' | sort)
if [[ ${#apk_files[@]} -eq 0 ]]; then
  printf '%s\n' 'No APK was downloaded into qa-apk.' >&2
  exit 2
fi

apk_path="${apk_files[0]}"
release_tag="$(tr -d '\r\n' < qa-apk/release-tag.txt 2>/dev/null || true)"
printf 'Testing APK: %s\n' "$apk_path"

adb wait-for-device

# A cold-booted emulator keeps updating GMS packages and scanning media for the
# first minute or two. Anything that stalls under that load raises a system
# "isn't responding" dialog, and that dialog owns the accessibility window --
# Maestro then reads the dialog instead of the app and every selector fails.
# Suppressing the dialogs is what keeps an unrelated system stall out of the
# report; the settle wait keeps the app itself off the contended boot window.
adb shell settings put global hide_error_dialogs 1 >/dev/null 2>&1 || true
adb shell settings put global show_first_crash_dialog 0 >/dev/null 2>&1 || true
adb shell settings put secure anr_show_background 0 >/dev/null 2>&1 || true

printf 'Waiting for the device to settle before install...\n'
for _ in $(seq 1 24); do
  load="$(adb shell cat /proc/loadavg 2>/dev/null | awk '{print int($1)}')"
  [[ -z "$load" ]] && load=0
  if [[ "$load" -lt 4 ]]; then
    break
  fi
  sleep 5
done
printf 'Device load average: %s\n' "${load:-unknown}"

adb install -r "$apk_path"

# Avoid unrelated first-run permission dialogs in navigation smoke tests.
# Permission-specific flows should revoke and test these explicitly.
for permission in \
  android.permission.ACCESS_FINE_LOCATION \
  android.permission.ACCESS_COARSE_LOCATION \
  android.permission.POST_NOTIFICATIONS \
  android.permission.READ_MEDIA_IMAGES \
  android.permission.READ_MEDIA_VIDEO; do
  adb shell pm grant "$APP_ID" "$permission" >/dev/null 2>&1 || true
done

adb logcat -c

set +e
"$HOME/.maestro/bin/maestro" test .maestro \
  --include-tags "$MAESTRO_TAGS" \
  --format junit \
  --output "$RESULTS_DIR/maestro-report.xml" \
  --debug-output "$RESULTS_DIR/maestro-debug" \
  --flatten-debug-output \
  2>&1 | tee "$RESULTS_DIR/maestro-console.log"
maestro_status=${PIPESTATUS[0]}
set -e

adb exec-out screencap -p > "$RESULTS_DIR/final-screen.png" 2>/dev/null || true
adb logcat -d -v threadtime '*:W' | tail -n 3000 > "$RESULTS_DIR/logcat.txt" || true

cat > "$RESULTS_DIR/run-metadata.json" <<EOF
{
  "appId": "$APP_ID",
  "apk": "$(basename "$apk_path")",
  "releaseTag": "$release_tag",
  "apiLevel": "$(adb shell getprop ro.build.version.sdk | tr -d '\r')",
  "device": "$(adb shell getprop ro.product.model | tr -d '\r')",
  "maestroTags": "$MAESTRO_TAGS",
  "exitCode": $maestro_status
}
EOF

exit "$maestro_status"
