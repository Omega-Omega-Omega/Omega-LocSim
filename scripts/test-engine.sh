#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
engine_scratch="$(mktemp -d "${TMPDIR:-/tmp}/omega-locsim-engine.XXXXXX")"
trap 'rm -rf "$engine_scratch"' EXIT
mkdir -p "$engine_scratch/Sources/StikDebug" "$engine_scratch/Tests/StikDebugTests"
cp "$project_root/StikDebug/Services/RoutePlanner.swift" "$project_root/StikDebug/Services/LocationSimulationSession.swift" "$project_root/scripts/engine-test-support/DeviceStubs.swift" "$engine_scratch/Sources/StikDebug/"
cp "$project_root/StikDebugTests/RouteGeometryTests.swift" "$project_root/StikDebugTests/RoutePlaybackTests.swift" "$project_root/StikDebugTests/RoutePlannerTests.swift" "$engine_scratch/Tests/StikDebugTests/"
cat > "$engine_scratch/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "OmegaLocSimEngineChecks", platforms: [.macOS(.v14)], targets: [
    .target(name: "StikDebug"), .testTarget(name: "StikDebugTests", dependencies: ["StikDebug"])
], swiftLanguageModes: [.v5])
PACKAGE
swift test --package-path "$engine_scratch" --scratch-path "$engine_scratch/.build"
