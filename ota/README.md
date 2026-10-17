# Staying installed — over-the-air updates

Why the app used to die every week, and how it never has to again.

A build installed from Xcode with a free Personal Team account is
signed with a certificate that lives **7 days**. When it lapses,
iOS refuses to launch the app — the app is fine; its papers are
not. There are two roads out, and this repo carries both.

## Road one — ad hoc over-the-air (the in-app Update button)

Needs the paid Apple Developer Program ($99/year). In exchange:
provisioning profiles that live **a year**, installs that happen
from a link with no Xcode and no cable, and a true **Update**
button inside the app.

How it works: each GitHub release carries two extra assets —
`nightjar-hack.ipa` (an ad hoc build) and `manifest.plist`
(its install manifest). The app already watches for new
releases; when it finds one, it probes for the manifest. If the
manifest is there, the banner and About's Version section show
**Update now** / **Update to … — install now**. Tapping hands
iOS an `itms-services` address; iOS verifies this device is in
the build's provisioning profile and installs the new build
over the old one. Logs, notes, settings — all kept. No app can
install a package itself on iOS; this is the one mechanism
Apple provides, and it is a genuine one-tap update.

### One-time setup

1. Enroll in the Apple Developer Program.
2. Register your device: developer portal → Devices → add your
   iPhone's UDID (Finder shows it when the phone is connected).
   Up to 100 devices per year; a friend's phone is a one-time
   add here, plus a re-export below.
3. Create an **Apple Distribution** certificate (Xcode →
   Settings → Accounts → Manage Certificates → +).
4. Create an **Ad Hoc** provisioning profile for
   `net.nosuchmachine.nightjarhack` with that certificate and
   your device(s); download it.

### Per release

1. Xcode → Product → Archive → Distribute App → **Ad Hoc** →
   export. Name the result `nightjar-hack.ipa`.
2. Copy `ota/manifest.plist` and replace `__VERSION__` with the
   release's version (e.g. `5.0.0`). The manifest already points
   at `releases/latest/download/nightjar-hack.ipa`, so it never
   needs a new address.
3. Attach **both** files to the GitHub release. Done — every
   phone running the app sees the Update button light up.

### Automating it

`ota/build-adhoc.yml` is a GitHub Actions workflow that does
the per-release steps on every version tag: archive, export the
ad hoc IPA, fill the manifest, attach both to the release. To
arm it:

1. Move it to `.github/workflows/build-adhoc.yml` and push from
   your own git (the repo's automation token cannot create
   workflow files — that step is deliberately yours).
2. Fill `__TEAM_ID__` and `__PROFILE_NAME__` in
   `ota/ExportOptions.plist`.
3. Add the repository secrets it lists: an App Store Connect
   API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8_BASE64`)
   and the distribution certificate (`CERT_P12_BASE64`,
   `CERT_PASSWORD`).

It is a scaffold, not a promise: the first run or two will
teach us what Apple's current portal wants, and the file
should be adjusted where it speaks up. The manual ritual above
always works regardless.

Profiles and the distribution certificate expire after a year;
renew them before they lapse and no install ever notices.

## Road two — SideStore (free)

[SideStore](https://sidestore.io) re-signs apps **on the phone
itself** before the 7-day certificate lapses, over a local VPN
loopback. Install once (a computer is needed only for the
one-time setup and pairing file) and the app stays alive
indefinitely. Updates then live in SideStore rather than in
this app's button.

Add this repo as a source in SideStore and new versions will
surface there on their own:

```
https://raw.githubusercontent.com/chasebryan/nightjar-hack/main/sidestore-source.json
```

The source serves the same `nightjar-hack.ipa` the releases
carry; SideStore signs it with your own account at install
time. Honest limits: SideStore holds one of the free account's
3 app slots, and its refresh depends on community anisette
servers staying up.

## Not roads

- **TestFlight** — same $99, but every build hard-expires
  after 90 days. Fails "stays until uninstalled."
- **Enterprise Program** — $299, for large organizations'
  own employees only.
- **TrollStore / jailbreak installers** — the exploits they
  ride were patched years before iOS 26.
- **Leaked-certificate signing apps** — certificates get
  revoked in batches; the app dies fleet-wide overnight.
