# Development checks

The native CI job uses Xcode 27.0 on the `xcode-27` runner and installs the Metal
toolchain. The checked-in Swift package resolutions require Swift tools
6.4; the default Xcode 16.4 on the macOS 15 runner cannot resolve them.
Xcode 27 supplies Swift 6.4. CI uses the checked-in resolutions rather than
silently upgrading packages; the app's deployment targets stay unchanged.
Unattended CI passes `-skipMacroValidation` for the MLX Hugging Face macro
plugin in those pinned dependencies. In Xcode, approve that package's macro
when prompted on the first build.

Run the app's tests on a Mac with that toolchain:

```bash
xcodebuild test \
  -project ios/nightjar.xcodeproj \
  -scheme nightjar \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator from `xcrun simctl list devices available`
if its name differs. `ServeLifecycleTests` creates unlisted local listeners,
restores the settings and delegates it touches, and needs no remote peer.
`BlacksiteCancellationTests` uses unique files in the console's `/tmp` and
removes them when done.

The kernel's cancellation tests can also run independently of the app:

```bash
tools/test-kernel.sh
tools/test-kernel.sh --sanitize=thread
```

This script builds the production `BlacksiteKernel.swift` and the same
`KernelLifecycleTests.swift` used by the app in a temporary Swift package.
It needs Swift 5.9 or later and XCTest, with no MLX, Metal, simulator, radio,
or downloaded model. The temporary package is removed after the run. The
CI kernel job runs it under Thread Sanitizer. Native changes also build the
`nightjar-mac` scheme without code signing on the same Xcode 27 toolchain.

The desktop overlay has its own suite:

```bash
python3 -m pip install pytest
python3 -m pytest tests/ -q
```

Optional WebSocket and serial tests skip when their transport dependencies
are not installed. Passing the kernel or Python suite does not replace the
native app tests. Bluetooth restoration and actual background suspension
also need checks on a physical device.
