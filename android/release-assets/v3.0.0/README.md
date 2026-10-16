# Signed v3.0.0 release artifact

The signed APK is stored in ordered binary parts because the upload transport
has a per-request size limit. These are not separate APKs. The release workflow
concatenates `apk.part-*`, verifies the complete APK against the root checksum
and pinned certificate, and publishes one ordinary `.apk` on the v3.0.0 release.
Download the release APK; end users do not need to assemble these parts.

The root `nightjar-hack-v3.0.0.apk.build.json` records the exact build source.
The private signing key is not included here.
