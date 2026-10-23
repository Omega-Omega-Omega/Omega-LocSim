# Omega LocSim

Omega LocSim is a focused iPhone location simulator derived from [StikDebug](https://github.com/StikDebug/StikDebug). It uses SwiftUI and public MapKit APIs for a Maps-style search, place card, route preview, and active route flow.

Native Liquid Glass is used for floating controls, search, the main sheet, route actions and setup on iOS 26 and later.

## Current scope

- Set a stationary spoofed location from a selected place.
- Prepare driving routes with ordered stops and one adjustable speed.
- Start with Go, pause or resume, edit the remaining stops while paused, and end at the last simulated position.
- Restore Real Location separately, with any connection failure reported.
- Retain StikDebug pairing, device communication, connection setup, and background support.

Version 3.1.15 was signed through Xcode Personal Team and tested on an iPhone 15 Pro Max running iOS 27.0. After refreshing pairing, the app reported successful stationary Set Location, road-route Go, Pause, Edit Route/Apply & Resume with the remaining stop unchanged, End Route holding, and Restore Real Location clearing the simulated state without an error. All 22 prior isolated engine checks pass.

Independent location verification in another app, live speed changes, actual multi-stop edits, arrival, background/lock/disconnection endurance, the second physical phone, and iOS 27.0.1 remain untested. See [IMPLEMENTATION.md](IMPLEMENTATION.md) for the exact smoke-test observations and remaining checks.

## Building and testing

1. Complete Xcode's first-run setup and open `StikDebug.xcodeproj`.
2. Select the `StikDebug` target and configure the available signing identity.
3. Select a physical iPhone and build. The bundled device bridge contains iOS arm64 objects; the full app is built for a physical iPhone.
4. Follow the existing [pairing file guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md) and connection setup as needed for the paired phone.

The app uses the separate `com.omega.locsim` bundle identifier and `group.com.omega.locsim` app group so it can coexist with StikDebug. It does not register StikDebug’s URL schemes. Internal Xcode project/module names and protocol identifiers remain compatible. The installed display name is Omega LocSim, and its identifier is verified as `com.omega.locsim`. Physical smoke checks establish app-reported success and visible state/progress changes; GPS behavior in another app was not independently checked.

Run `scripts/test-engine.sh` for the isolated engine checks. The supplied Omega LocSim icon is preserved in `branding/` and selected by both build configurations.

## Source delivery

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published.

## Attribution and license

This modified project starts from StikDebug commit `17b1e1d90d602a228de663a10efa987a9f9e547b`. Its device communication is powered by [idevice](https://github.com/jkcoxson/idevice). Original author notices and the [AGPL-3.0 license](LICENSE) are preserved. The original project documentation is retained in [README.upstream.md](README.upstream.md); its upstream download links refer to StikDebug, not to an Omega LocSim release.
