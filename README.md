# Omega LocSim

Omega LocSim is an iPhone location simulator built from [StikDebug](https://github.com/StikDebug/StikDebug), with a native MapKit interface and Liquid Glass controls.

## Version 3.3.0

Version 3.3.0 (build 9) reorganizes the map around a larger Places shelf, Recents, and Saved Routes, with deeper blue accents and a blue location dot with a heading fan. **Build Route** opens an editable stop list with direct removal, Undo, and accessible reordering. Opening Edit Route keeps playback running; a manually paused route stays paused when changes are applied.

Swipe up below a route preview or active trip to find **Route Options**: departure/arrival scheduling, road details, traffic-light probability, and speed. These controls stay in the map sheet. The active card adds current simulated speed. **Arrive By** removes only as many red-light waits as needed before increasing simulated speed, with a finite 250 mph ceiling and an explicit warning when the target cannot be met. Pauses, retained visits, and device interruptions can prevent arrival by the selected time.

- Search Omega with live suggestions; save Home, Work, School, custom pins, and bookmarks.
- Recents records accepted single-location spoofs and route starts/updates locally, deduplicated and limited to the latest 50 entries.
- Saved Routes stores named, ordered stop snapshots and visit durations. Opening one prepares a fresh road preview for review before Go.
- Set a stationary location or drive an ordered route with Leave Later, intermediate stays, sampled traffic lights, Pause/Resume, End holding, and Restore Real Location.
- Choose Road Limits or Constant speed, with US Imperial units by default and one Metric option for all distances and speeds.
- Start with fallback speed while optional OpenStreetMap road/signal details load through the two approved services.
- Keep the existing pairing, tunnel, background support, coordinate import, and vector Liquid Glass icon.

See [FEATURES.md](FEATURES.md) for the full control inventory and [IMPLEMENTATION.md](IMPLEMENTATION.md) for technical details and evidence.

## Validation status

**3.3.0 passed 111 isolated checks** (106 XCTest and 5 Swift Testing) and **12 physical Debug acceptance checks** in 30.34 seconds. The device checks covered stationary location, scheduled departure, natural/skipped visits and lights, playback, arrival retargeting, impossible-arrival feedback, live edits, End holding, and Restore.

The ten-minute device protocol completed in 605.739 seconds with 1,113 accepted movement updates, 586.44 m maximum progress, a 5.339-second maximum report gap, and successful restoration. Diagnostics establish **more than nine minutes actually in the background**: 114 active background samples span 562.17 seconds, with audio and location running throughout, While Using authorization, and no reported errors. Apple Maps independently showed movement and restoration. This does not establish a full ten minutes continuously backgrounded or indefinite endurance.

Light/dark and maximum-text UI audit fixes are implemented. VoiceOver, interruption endurance, and live Overpass data remain unverified. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for evidence and scope.

**Final Release delivery verified:** the 3.3.0 build 9 Release build and signed/unsigned IPA checks passed. Physical installation and launch succeeded; installed-app inventory confirms **Omega LocSim `com.omega.locsim` 3.3.0 (9)**. Physical smoke on the same 3.3.0 engine confirmed public-place autocomplete and accepted stationary location in Recents, a four-minute road preview with Go available before metadata, 30 mph playback with the blue heading dot, editing that continued until natural arrival, saved-route name persistence, and Restore to idle/real location. The final small label/scroll fixes were rebuilt and reinstalled; simulator Go/Apply from lower Route Options returned to the trip summary with Pause visible. These checks do not establish every feature under every device condition.

### Earlier 3.2.1 and 3.2.0 checks — October 23, 2026

**3.2.1 build 3 passed 83 isolated checks** (78 XCTest plus 5 Swift Testing), including 24 road metadata tests. The signed Release build succeeded; physical installation and launch succeeded, and inventory verified **Omega LocSim `com.omega.locsim` 3.2.1 (3)**. The signed/unsigned IPA packages were verified. Physical smoke confirmed public-place autocomplete, a 3.4 mi driving preview with Go available at fallback 30 mph during metadata loading, remaining distance falling to 3.3 mi, Pause, and Restore returning to idle without error. The approved mirror probe timed out after 28.0016 seconds with zero bytes (HTTP 000); live metadata remains unverified.

The completed checks below belong to **3.2.0 build 2**. On October 23, 2026, that development build passed nine foreground checks on iPhone 15 Pro Max, iOS 27.0, using the actual device bridge. A separate background run continued for 605.06 seconds with 1,122 accepted movement updates and 589.05 m of progress at a selected 1 m/s; its largest report gap was 5.33 seconds, and restoration succeeded. These establish accepted device commands and app progress. Apple Maps independently confirmed stationary spoofing, successive movement along one short public test route while Omega was backgrounded, and a return to the real region after Restore. No continuous GPS recording was collected.

The 3.2.0 final isolated engine run passed **76 checks** (71 XCTest and 5 Swift Testing), including 17 road metadata checks. Simulator UI checks also passed. The earlier live Overpass probes failed or timed out; they did not verify mapped road/signal availability. The new approved-mirror probe also timed out without a response. Go remains available with the selected fallback speed while optional metadata loads or fails.

The **3.2.0 build 2 signed Release build succeeded**, its IPA packages were verified, and installation/launch plus installed-app inventory confirmed **Omega LocSim `com.omega.locsim` 3.2.0 (2)**. The freshly installed app resolved Apple Park autocomplete and passed Set Location/Restore; existing pairing remained usable after the update.

Physical manual checks also confirmed 48 km/h and 1.3 km converting to 30 mph and 0.8 mi, Go during metadata loading, progress from 0.8 to 0.5 mi, Pause/Resume, Road Limits selection, and 1/85 mph slider endpoints changing ETA. The route reached Arrived at 0 min/0 ft and was restored. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for evidence and remaining device checks.

## Build and setup

1. Complete Xcode's first-run setup and open `StikDebug.xcodeproj`.
2. Configure the `StikDebug` target's signing team and select a physical iPhone.
3. Build and follow the existing [pairing file guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) and connection setup for that phone.
4. Run `scripts/test-engine.sh` for the isolated engine checks.

The bundled bridge targets physical iOS arm64; simulator UI validation uses a separate harness with fake device transport. Omega LocSim uses `com.omega.locsim` and `group.com.omega.locsim`, so it can coexist with StikDebug. Its display name is Omega LocSim; internal project/module names retain upstream compatibility.

The active icon is `StikDebug/OmegaLocSimPeel.icon`, using 40 individual vector layers for the peeled Maps/Omega blueprint composition. Apple's icon renderer supplies its system mask and tinted appearance. See [artwork and generation notes](branding/omega-locsim-peel/README.md). The earlier vector/glass icon and original reference remain preserved.

## Source and attribution

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published.

Based on StikDebug commit `17b1e1d90d602a228de663a10efa987a9f9e547b`, using [idevice](https://github.com/jkcoxson/idevice) for device communication. Original notices and the [AGPL-3.0 license](LICENSE) are preserved. [README.upstream.md](README.upstream.md) retains upstream documentation; its download links refer to StikDebug.
