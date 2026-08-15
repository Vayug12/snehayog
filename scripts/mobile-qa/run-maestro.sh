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
