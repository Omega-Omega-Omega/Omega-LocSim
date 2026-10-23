# Omega LocSim implementation and validation

The signed release passed an on-device smoke session on iPhone 15 Pro Max, iOS 27.0: stationary Set Location, road-route movement, Pause, Edit Route/Apply & Resume with the remaining stop unchanged, End holding, and Restore clearing simulated state without error. These are app-reported outcomes and observed UI/progress changes; another app's GPS was not independently checked. Broader physical acceptance remains below. Source is maintained in the [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim); no GitHub Release is published.

## Source and branding

Derived from [StikDebug](https://github.com/StikDebug/StikDebug) commit `17b1e1d90d602a228de663a10efa987a9f9e547b`. Live upstream HEAD was verified at that commit. The original README is preserved byte-for-byte as `README.upstream.md`; original author notices, LICENSE and device bridge remain. AGPL-3.0 applies.

The owner chose **Omega LocSim** and supplied the icon. `branding/omega-locsim-icon-source.jpg` is the unchanged 1254-pixel JPEG, SHA256 `9b28537f310494d2f9d32e02d1eec790f5fa7bf5cac6cdde1290a73b8562f124`. App icon and Settings image assets use full-square resizes of that artwork. The compiled iPhone icon was decoded and visually inspected; built Info.plist selects `OmegaLocSim` as the primary icon and `Omega LocSim` as its display name.

The installed app has its own `com.omega.locsim` bundle identifier and `group.com.omega.locsim` app group, including all legacy group-storage callers. StikDebug URL registrations are removed to avoid intercepting the original app’s links. Internal project/module names, protocol Bonjour declarations, saved preference keys, shared file-format identifiers and upstream assets remain compatible. The installed app was verified as `com.omega.locsim`, version 3.1.15, build 1.

## Implemented behavior

- Native full-screen MapKit map, translucent glass sheet, centered place/route headers, compact stop rows, search, stationary spoofing, Directions, automatic road-route preview and compact Go tile. The active screen has a destination/status banner, pitched heading-follow map and three-column arrival/time/distance card. Speed expands on demand; route actions live in its menu. The owner’s three Maps screenshots guide the layout.
- Native Liquid Glass on map controls, search, the main sheet, route actions and setup branding/actions on iOS 26+. System glass and semantic surfaces preserve readable contrast; earlier systems use native material/bordered fallbacks.
- Ordered driving legs and multiple stops, explicit Add Stop/replacement, drag reordering, cancellation of obsolete requests and reuse of unchanged legs. No Overpass lookup or road-speed matching pipeline.
- One adjustable speed in mph or km/h; changing speed does not recalculate geometry.
- Session-owned playback and periodic stationary holding. Only one transport call can run at a time. Known transport duration contributes fully to the next movement step; excess scheduling gaps are treated separately.
- Pause intent is immediate. A synchronous call already started must finish, and its accepted coordinate or failure is recorded honestly. End and Restore wait behind that call.
- Edit pauses and waits for the accepted position, then changes remaining stops. Resume cannot race that edit preparation. Cancel or failed replacement keeps the old route/progress paused and preserves the draft on Apply failure.
- Arrival and End retain position. Restore clears simulation on success and reports a failure without pretending restoration succeeded. Session errors also open a native Simulation Unavailable alert with OK and Settings actions on the main sheet; the inline error remains.
- Follow/recenter uses accepted simulated coordinates; user panning stops following. Intermediate stops have map markers.
- Existing pairing, tunnel, disk-image mount, background managers, bookmark storage and coordinate import parser are retained. Unrelated debugger tools are absent from the main interface.

## Verified on October 23, 2026

| Check | Evidence |
|---|---|
| Xcode setup | Xcode 27.1 (27A9275); first-launch status passed; iOS SDK 27.1 available |
| Unchanged upstream | Debug generic iPhone build succeeded without signing |
| Modified app | Debug and Release generic iPhone builds succeeded without signing; bundled arm64 device bridge linked |
| Signed release | Xcode Personal Team development-signed Release build succeeded (`../work/signed-build.log`); incremental native-error-alert update also built successfully (`../work/final-signed-build.log`) |
| Physical install | `devicectl` reports successful installation of `com.omega.locsim`; installed-app inventory reports Omega LocSim 3.1.15, build 1 (`../work/install-result.json`, `../work/installed-omega.log`) |
| Physical launch | `devicectl` reports successful launch on the connected iPhone 15 Pro Max, iOS 27.0 (`../work/device-launch.json`, `../work/device-details.log`) |
| Physical UI | Redesigned place, Directions and active-route states observed on the physical phone through Device Hub |
| Pairing recovery / stationary | Initial provider error 3 was resolved after refreshing pairing; Set Location then reported success |
| Road-route Go | Entered Simulating; remaining distance visibly decreased from 2.6 to 2.1 km |
| Pause / edit / apply | Pause used; Edit Route opened from the held position; Apply & Resume accepted the unchanged remaining stop; progress continued from 2.1 to 1.6 km. Actual stop-list changes were not tested |
| End Route | Removed the route and retained stationary Holding location state |
| Restore Real Location | Simulated marker, Holding location label and Restore control disappeared without an error. External-app GPS was not independently checked |
| Engine tests | 22 passed: 13 playback XCTest, 4 geometry XCTest, 5 planner Swift Testing checks (`../work/final-engine-tests.log`) |
| Delayed transport | Two-second transport at selected 10 m/s measured approximately 10 m/s, replacing the reproduced approximately 3.9 m/s drift |
| Regression coverage | Holding while paused; resume cancellation of holding; paused in-flight failure; honest edit anchor; Edit/Resume race; End/Restore serialization; restore outcomes; failed replacement retention; arrival; stop teardown; cancellation and cache isolation |
| Geometry | Empty/single-point paths, unequal segments, repeated coordinates, arrival bounds and date-line crossing |
| Simulator UI | Actual map/view/planner/session sources rendered in an isolated harness with a fake device transport. Public Apple Park–Cupertino Library routing returned live road geometry. This is not physical spoofing validation. |
| Icon | Original hash matched; opaque asset sizes checked; compiled primary icon decoded and visually inspected |

The device archive contains 900 arm64 Mach-O objects targeting iOS, with no simulator slice. The real app is built for iPhone. The simulator harness replaces only device/setup dependencies and is excluded from the delivered app.

## Repeatable checks

From the repository root, run the dependency-free isolated engine suite:

```sh
scripts/test-engine.sh
```

The script copies the actual engine and test files into a temporary package outside the Documents file-provider directory, runs the checks with Xcode's Swift toolchain, then removes the temporary build. Test-only stubs fail if real device transport is attempted. No new production package is required.

Build an unsigned device release:

```sh
xcodebuild -project StikDebug.xcodeproj -scheme StikDebug -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ../work/release-build \
  CODE_SIGNING_ALLOWED=NO build
```

For this run, Xcode Personal Team signing produced the signed release that was installed and launched on the connected phone. For another device/build, select the appropriate Apple signing team and phone in Xcode, or sign the separate unsigned IPA with the chosen sideloading tool. The output named `omega-locsim-unsigned.ipa` remains unsigned; it is separate from the signed build installed in this run.

## Physical-device acceptance still required

Owner targets: iPhone 15 Pro Max and iPhone 18 Pro Max, using iOS 27.0 and 27.0.1. The connected physical iPhone 15 Pro Max was verified as iOS 27.0 (24A435), wired, paired, with Developer Mode enabled. Omega LocSim 3.1.15 (build 1), `com.omega.locsim`, is installed and launched through Xcode Personal Team signing. The iPhone 18 Pro Max/version pairing has not been observed. Earlier iLoader sign-in/restart blocks are superseded by this successful Xcode installation.

The physical smoke session established the exact app-side observations in the table above. It did not independently verify location in another app. The successful edit application left the remaining stop unchanged; it does not establish actual multi-stop addition/replacement/reordering on the phone. Resumption was exercised through Apply & Resume rather than a separate test of the Resume button.

Still required: independent external-app GPS checks; live speed-slider changes; actual multi-stop edits; arrival; canceled/failed edit and restore recovery on hardware; direct Resume-button coverage; lock/background/disconnection endurance; the second physical phone; and iOS 27.0.1. Record measured background duration and behavior. Indefinite background reliability remains unverified.

Compare browsing, search, place, route-preview and active-route screens against Maps on the target phones, including dark appearance and larger text. Simulator rendering and physical place/Directions/active-route observations are visual evidence, not a verified exact Maps match.

## Source repository and remaining acceptance

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published. Local `origin` points to this fork and `upstream` points to StikDebug.

Installation, launch and the recorded physical smoke session on iPhone 15 Pro Max are complete. Remaining acceptance covers the explicit untested cases above, second-phone/iOS 27.0.1 validation, and final Maps comparison. No additional iLoader restart or sign-in is required for the completed installation.
