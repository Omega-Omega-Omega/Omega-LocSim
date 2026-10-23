# Omega LocSim

Omega LocSim is an iPhone location simulator built from [StikDebug](https://github.com/StikDebug/StikDebug), with a native MapKit interface and Liquid Glass controls.

## Version 3.2.1

Version 3.2.1 (build 3) adds an approved Overpass fallback for optional mapped road details: the app initially tries `overpass-api.de`, then may send the same route query to `overpass.private.coffee`. A working backup can be reused for later requests; if it fails, the primary can be tried again. The existing Mapped Road Details opt-in covers both named services; it remains off by default. See the [Private.coffee service and privacy policy](https://overpass.private.coffee/).

- Search with live place suggestions, drop pins, and save Home, School, Work, custom pins, and a local place library.
- Set a stationary location or prepare driving routes with ordered stops, drag/menu reordering, and editable remaining stops.
- Choose constant speed or road speeds. Optional mapped road details supply available OpenStreetMap limits and estimated speeds for other matched road types.
- Leave now or arm a later departure, set intermediate stop durations, and simulate red lights with a configurable probability and skippable waits.
- Pause, resume, edit, end while holding position, or Restore Real Location. ETA includes selected speeds, stop durations, and simulated light delays.
- Use US Imperial or Metric consistently for distance and speed.
- Import coordinate files and use existing pairing, tunnel, and background support.

See [FEATURES.md](FEATURES.md) for every control and the practical limits.

## Validation status

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

The new original Ω/navigation icon is editable in `StikDebug/OmegaLocSimGlass.icon`. It was assembled with Apple's Icon Composer and uses native glass, dark, and tinted appearances. Original vectors and workflow notes are in [branding/omega-locsim-glass](branding/omega-locsim-glass/README.md). Previous artwork and upstream assets remain preserved.

## Source and attribution

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published.

Based on StikDebug commit `17b1e1d90d602a228de663a10efa987a9f9e547b`, using [idevice](https://github.com/jkcoxson/idevice) for device communication. Original notices and the [AGPL-3.0 license](LICENSE) are preserved. [README.upstream.md](README.upstream.md) retains upstream documentation; its download links refer to StikDebug.
