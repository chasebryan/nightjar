#!/usr/bin/env bash
# Build, test, and sign a sideloadable APK. Keep the release key outside the repo.
set -euo pipefail

cd "$(dirname "$0")"
: "${ANDROID_HOME:=${ANDROID_SDK_ROOT:-}}"
: "${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK directory}"
: "${NIGHTJAR_KEYSTORE:?Set NIGHTJAR_KEYSTORE to an absolute release keystore path}"
: "${NIGHTJAR_KEYSTORE_PASSWORD:?Set NIGHTJAR_KEYSTORE_PASSWORD}"
export ANDROID_HOME NIGHTJAR_KEYSTORE_PASSWORD
key_alias="${NIGHTJAR_KEY_ALIAS:-nightjar-release}"
build_tools="$ANDROID_HOME/build-tools/34.0.0"
output_dir="${1:-$PWD/dist}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

./gradlew --no-daemon testReleaseUnitTest assembleRelease
version="$(python3 - <<'PY'
import json
from pathlib import Path
metadata = json.loads(Path('app/build/outputs/apk/release/output-metadata.json').read_text())
assert metadata['applicationId'] == 'net.nosuchmachine.nightjarhack'
assert len(metadata['elements']) == 1
print(metadata['elements'][0]['versionName'])
PY
)"
apk="$output_dir/nightjar-hack-v$version.apk"
"$build_tools/apksigner" sign \
  --ks "$NIGHTJAR_KEYSTORE" --ks-key-alias "$key_alias" \
  --ks-pass env:NIGHTJAR_KEYSTORE_PASSWORD \
  --out "$apk" app/build/outputs/apk/release/app-release-unsigned.apk
"$build_tools/apksigner" verify --verbose --print-certs "$apk" > "$apk.cert.txt"
"$build_tools/zipalign" -c -p 4 "$apk"
(cd "$output_dir" && sha256sum "$(basename "$apk")" > "$(basename "$apk").sha256")
python3 - "$apk" <<'PY'
import hashlib, json, subprocess, sys
from pathlib import Path
apk = Path(sys.argv[1])
source = subprocess.run(['git', 'rev-parse', 'HEAD'], capture_output=True, text=True)
status = subprocess.run(['git', 'status', '--porcelain', '--untracked-files=no'], capture_output=True, text=True)
manifest = json.loads(Path('app/build/outputs/apk/release/output-metadata.json').read_text())
details = {
    'repository': 'https://github.com/chasebryan/nightjar-hack',
    'sourceCommit': source.stdout.strip() if source.returncode == 0 else None,
    'sourceHasTrackedChanges': bool(status.stdout.strip()) if status.returncode == 0 else None,
    'applicationId': manifest['applicationId'],
    'versionName': manifest['elements'][0]['versionName'],
    'versionCode': manifest['elements'][0]['versionCode'],
    'sha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
    'buildCommand': './gradlew --no-daemon testReleaseUnitTest assembleRelease',
    'gradle': '8.7', 'androidGradlePlugin': '8.5.2', 'kotlin': '2.0.20',
    'minSdk': 26, 'targetSdk': 34,
}
apk.with_name(apk.name + '.build.json').write_text(json.dumps(details, indent=2) + '\n')
PY
printf 'Signed APK: %s\n' "$apk"
