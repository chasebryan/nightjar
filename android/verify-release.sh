#!/usr/bin/env bash
# Verify the distributed v3.0.0 APK before publishing it.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
apk="${1:-$project_root/nightjar-hack-v3.0.0.apk}"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
: "${ANDROID_HOME:?Set ANDROID_HOME}"
build_tools="$ANDROID_HOME/build-tools/34.0.0"
expected_signer=c132ffe3ac88bb52b3340ffa7175d8deb3d05a95b25e05cc6f7ce609264e4fdc

(cd "$(dirname "$apk")" && sha256sum --check "$(basename "$apk").sha256")
certificate_report="$("$build_tools/apksigner" verify --verbose --print-certs "$apk")"
printf '%s\n' "$certificate_report"
actual_signer="$(printf '%s\n' "$certificate_report" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p')"
[[ "$actual_signer" == "$expected_signer" ]] || { echo 'Unexpected signing certificate' >&2; exit 1; }
"$build_tools/zipalign" -c -p 4 "$apk"
"$build_tools/aapt" dump badging "$apk" | python3 -c '
import re, sys
badging = sys.stdin.read()
package = re.search(r"^package: (.+)$", badging, re.M)
assert package, "Missing package metadata"
fields = dict(re.findall(r"(\w+)=\x27([^\x27]*)\x27", package[1]))
assert fields["name"] == "net.nosuchmachine.nightjarhack", fields
assert fields["versionName"] == "3.0.0", fields
assert fields["versionCode"] == "300", fields
assert "sdkVersion:\x2726\x27" in badging, "Unexpected minimum Android version"
assert "targetSdkVersion:\x2734\x27" in badging, "Unexpected target Android version"
assert "application-debuggable" not in badging, "Release must not be debuggable"
assert "launchable-activity:" in badging, "No launcher activity"
print("Verified: net.nosuchmachine.nightjarhack 3.0.0 (300), Android 8.0+, non-debuggable")
'
