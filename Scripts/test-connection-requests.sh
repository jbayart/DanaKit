#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT
mkdir -p "$package_dir/Sources/DanaConnectionHarness" "$package_dir/Tests/ConnectionTests"
cp "$repo_root/Common/Locked.swift" "$package_dir/Sources/DanaConnectionHarness/"
python3 "$repo_root/Scripts/connection-test-support/build_harness.py" "$repo_root" "$package_dir/Sources/DanaConnectionHarness"
cp "$repo_root/Scripts/connection-test-support/InteractiveConnectionTests.swift" "$package_dir/Tests/ConnectionTests/"
cat > "$package_dir/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DanaConnectionTests",
    targets: [
        .target(name: "DanaConnectionHarness"),
        .testTarget(name: "ConnectionTests", dependencies: ["DanaConnectionHarness"])
    ],
    swiftLanguageModes: [.v5]
)
PACKAGE
if [ -n "${DANA_SOURCE_REF:-}" ]; then
    swift test --package-path "$package_dir" -Xswiftc -DDANA_BASELINE "$@"
else
    swift test --package-path "$package_dir" "$@"
fi
