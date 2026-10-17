## Android APK — v3.0.0 (discontinued)

**Android development has stopped (October 2026), and this
APK is withdrawn.** The port never reached the flagship's
standard, and the iOS app is the only supported
instrument. What follows is the v3.0.0 build record, kept
as archive.


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
The private release key is kept outside the repository. `android/verify-release.sh` checks the published
APK’s checksum, signer, alignment, version, SDK levels, and release flags.
