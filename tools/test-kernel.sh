#!/usr/bin/env bash
set -euo pipefail

# Compile the actual kernel and its app XCTest file in an isolated,
# dependency-free Swift package. This keeps Stop regressions testable even
# when the full app's MLX/Metal dependencies are unavailable on a machine.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_PACKAGE="$(mktemp -d "${TMPDIR:-/tmp}/nightjar-kernel.XXXXXX")"
trap 'rm -rf "$TEST_PACKAGE"' EXIT
mkdir -p "$TEST_PACKAGE/Sources/nightjar" "$TEST_PACKAGE/Tests/KernelTests"
cp "$REPO_ROOT/ios/nightjar/BlacksiteKernel.swift" "$TEST_PACKAGE/Sources/nightjar/"
cp "$REPO_ROOT/ios/nightjarTests/KernelLifecycleTests.swift" "$TEST_PACKAGE/Tests/KernelTests/"
cat > "$TEST_PACKAGE/Package.swift" <<'SWIFT'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NightjarKernelTests",
    targets: [
        .target(name: "nightjar"),
        .testTarget(name: "KernelTests", dependencies: ["nightjar"]),
    ])
SWIFT
swift test --package-path "$TEST_PACKAGE" "$@"
