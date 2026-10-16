## Android APK — v3.0.0

[**Download nightjar-hack-v3.0.0.apk**](https://github.com/chasebryan/nightjar-hack/releases/download/v3.0.0/nightjar-hack-v3.0.0.apk)

- Android 8.0+ (API 26), Bluetooth LE; one universal APK.
- Package `net.nosuchmachine.nightjarhack`, version `3.0.0`, version code `300`.
- Release-signed and non-debuggable. SHA-256 checksum and certificate report
  are attached beside the APK.
- Open the downloaded APK on Android and allow your browser/file manager to
  install it when prompted. Alternatively, use `adb install -r nightjar-hack-v3.0.0.apk`.

**Upgrading from the repository’s v2.6.0 APK:** that APK used a debug key.
This build uses a new dedicated release key, so Android cannot install it over
that old APK. Export anything you want to keep, uninstall the old app, then
install v3.0.0. Uninstalling deletes the old app’s local data.

**Feature scope:** this APK builds the Android implementation from the v3.0.0
tag (`4ebabc2cf42a91bca6d83e928d606bc97e0e6f1a`), with Android packaging,
version-label, and build fixes. It has Listen, Send, Serve, Scan, Sessions,
and More, including Network Trace, Centipede, Crosstalk, and presets.
It does not add the iOS-only Recon tab, EMCON, canary/Honeydrop, Knocktalk,
Chirp, brush pass, Blink, or time capsules.

Release certificate SHA-256:

```text
c132ffe3ac88bb52b3340ffa7175d8deb3d05a95b25e05cc6f7ce609264e4fdc
```

Build recipe: [android/README.md](https://github.com/chasebryan/nightjar-hack/blob/main/android/README.md).
The private release key is kept outside the repository; keep using that key
for future in-place updates. `android/verify-release.sh` checks the published
APK’s checksum, signer, alignment, version, SDK levels, and release flags.
