# Omega LocSim 3.2.6 implementation and validation

## 3.2.6 icon positioning refinement

Build 8 raises the navigation assembly 100 canvas units, expands the shared peel reveal by about 70–80 units, and uses the same blue blueprint gradient and construction-guide colors in Default and Dark. The map's dark palette remains charcoal with blue navigation. The Omega path and its centering/symmetry are unchanged. The shared mask remains identical across all 18 map/navigation elements. The 40-layer source remains vector-only. Build/package evidence: `../work/omega-3.2.6-release-build.log`, `../work/omega-3.2.6-package-validation.json`. This is an artwork-only change; no phone connection or installation was performed.

## 3.2.5 complete-map masking and dark palette

Build 7 reconstructs the entire map before applying an identical vector peel clip to all 18 geography/navigation elements. The unmasked construction is preserved as `branding/omega-locsim-peel/CompleteMap.icon`. The lower navigation disc, descending diagonal road, route corridor, corner interchange, and colored regions follow the supplied light/dark references. Two separate peel vectors and native group shadow create the fold. Forty vector layers remain individually editable in four groups.

Default and dark colors are now stored exclusively as native fill specializations. The prior base fill silently took precedence over dark overrides; it is removed. Dark mode has charcoal regions, a blue corridor/lens, neutral rim and fold, and white arrow/Omega. The underlying Omega is symmetric around x=512 and its geometric bounding box is centered at (512,512), independently of the asymmetric peel. Full-map and peeled Default/Dark previews were inspected alongside ClearLight/ClearDark/TintedDark and Home Screen sizes. Icon Composer opened/saved the source without warnings. No runtime logic or phone state was changed. Release build/package evidence: `../work/omega-3.2.5-release-build.log`, `../work/omega-3.2.5-package-validation.json`.

## 3.2.4 individual vector materials

Build 6 uses 36 individual SVG geometry layers in four Icon Composer groups. Each map region, road, rim accent, lens, arrow, fold, Omega outline, and construction guide is separately editable. SVG files contain no bitmap images, gradients, opacity, filters, or baked shadows. Colors and surface materials are native Composer properties. The 19 construction guides use native opacity without raised glass edges to keep the diagram legible. The remaining 17 elements have native glass. Default, Dark, ClearLight, ClearDark, and TintedDark exports were inspected, including 60-pixel previews. Icon Composer opened and saved the document without group-limit warnings. No runtime code changed; no device connection or installation was performed. Build and package evidence: `../work/omega-3.2.4-release-build.log`, `../work/omega-3.2.4-package-validation.json`.

## 3.2.3 artwork update

Build 5 selects `OmegaLocSimPeel.icon`, rebuilt from the supplied Maps-peeling-to-Omega-blueprint reference as eight SVG layers in three groups. The construction grid and Omega share a precise center; the map surface, folded edge, separation shadow, navigation rim, lens, and arrow remain independently editable. Native glass effects were configured in Apple's Icon Composer UI; dark Omega/arrow fills preserve contrast. Default, Dark, and TintedDark exports were visually inspected. Settings branding uses the new exports. The previous flattened composition is preserved under `branding/omega-locsim-peel/previous-flattened.icon`. Runtime source is unchanged. The signed Release build and both IPA packaging checks passed (`../work/omega-3.2.3-release-build.log`, `../work/omega-3.2.3-package-validation.json`). The compiled iPhone fallback icon was decoded and visually checked. No phone connection or installation was performed for this artwork update.

## Earlier 3.2.1 validation

This **3.2.1 build 3** update adds the user-approved fixed Overpass fallback under the existing Mapped Road Details opt-in. **83 isolated checks passed**; the signed Release build, physical installation, and launch succeeded. Inventory verified **Omega LocSim `com.omega.locsim` 3.2.1 (3)**. Signed/unsigned IPA packages were verified. Installed-release smoke confirmed public-place autocomplete, a driving preview, Go/progress/Pause at fallback speed, and successful Restore to idle. The approved mirror live probe timed out without a response, so live road data remains unverified. Completed 3.2.0 build 2 engine, foreground/background device, external GPS, and installed-release checks remain recorded separately below.

## Source, identity, and artwork

Based on [StikDebug](https://github.com/StikDebug/StikDebug) commit `17b1e1d90d602a228de663a10efa987a9f9e547b`, with [idevice](https://github.com/jkcoxson/idevice) for device communication. `README.upstream.md`, original notices, and [AGPL-3.0](LICENSE) remain preserved.

Omega LocSim uses `com.omega.locsim` and `group.com.omega.locsim`, including legacy group-storage callers. StikDebug URL registrations were removed to avoid intercepting the original app's links. Internal project/module names, protocol Bonjour declarations, preferences, and file identifiers retain compatibility. Current source version is **3.2.6, build 8**. The prior **3.2.0, build 2** release is documented in the separate baseline below.

The previous 3.2 icon is retained as historical artwork. `StikDebug/OmegaLocSimGlass.icon` contains original Ω and navigation SVG layers assembled, previewed, and saved with Apple's Icon Composer. Native group glass effects and a cyan-to-cobalt background produce Default, Dark, and tintable appearances. Both build configurations select `OmegaLocSimGlass`; the synchronized target includes the document automatically. `OmegaLocSimBrand.imageset` uses resized Default/Dark renders for Settings. Original SVGs, workflow details, and Apple references are in [branding/omega-locsim-glass/README.md](branding/omega-locsim-glass/README.md).

For the historical 3.2 glass artwork, isolated Xcode 27.1 `actool` compilation passed for iPhone/iPad, deployment target 17.4. Generated metadata names `OmegaLocSimGlass`; `Assets.car` contains native light/dark/tintable icon stacks and both SVGs. The generated iPhone fallback was decoded and visually checked. The prior supplied JPEG, raster icon, and upstream `StikDebug.icon` remain preserved; they are not the selected new icon.

## Application behavior

[FEATURES.md](FEATURES.md) is the full user-facing control inventory.

- Native MapKit browsing, autocomplete and explicit search, selected-place card, stationary spoofing, ordered driving stops, automatic route preview, and active trip controls. Home/School/Work/custom pins and rename/remove controls supplement persistent bookmarks and coordinate import.
- Native Liquid Glass on iOS 26+ with earlier material/bordered fallbacks, light/dark semantic colors, accessibility labels, flexible scrolling, and Reduce Transparency handling.
- One measurement preference controls distances and speeds. Road Limits applies per-segment speed metadata; Constant applies the slider speed. Missing/unloaded sections use fallback speed. Unit changes preserve physical speed.
- Leave Later arms a route at its accepted start. Intermediate visits, simulated red lights, remaining waits, skips, Pause/Resume, and ETA share the session timing model. Final arrival holds indefinitely until an explicit End or Restore.
- Session-owned movement and stationary holding serialize all device commands. Accepted position is authoritative; an already-started synchronous bridge call finishes before the next command. Transport duration contributes to movement timing; excess scheduling gaps are handled separately.
- Pause intent is immediate. Edit waits for settled accepted progress, anchors there, and edits remaining stops. Apply retains an active wait and protects original progress/draft on failure. End/Restore invalidate pending edit preparation; restoration clears state only on success.
- Metadata updates can arrive while previewing or playing without resetting progress. In-flight movement boundaries prevent late metadata from moving backward to a newly discovered light. Completed/past events remain excluded. Import and draft replacement invalidate stale geometry/metadata work.
- Native Simulation Unavailable alerts on the main sheet expose device errors with OK/Settings actions, while inline feedback remains.

## Optional road metadata

`TrafficLightPlanner` uses two fixed user-approved endpoints: primary `https://overpass-api.de/api/interpreter`, then fallback `https://overpass.private.coffee/api/interpreter` when eligible primary failures occur. The primary is used first initially; a successful mirror is preferred for later chunks/calls, with a return to the primary if the mirror later fails. Mapped Road Details is off by default; its existing opt-in names both services and covers sending the route corridor coordinates to either for OpenStreetMap road/light lookup. There is no separate mirror toggle or arbitrary endpoint entry. Settings → Road Data → **Road Data Backup & Privacy** opens the official mirror service/terms/privacy page. The [Private.coffee service page](https://overpass.private.coffee/) documents its endpoint, terms, and privacy policy. Traffic-light sampling is simulated, not live signal phase information.

The pipeline fetches the first 8 km, then 20 km corridors, capped at 300 km. It publishes each successful chunk independently; Go does not depend on it. Geometry simplification retains bends within 10 m. Local road matching considers proximity, direction, one-way restrictions, and node membership to reject crossing-road signals. Mapped `maxspeed` values support km/h, mph, and knots; unsupported, conditional, and lane-dependent values fall back to marked estimates. Road-class estimates and user fallback fill the remaining profile. Probability sampling is stable for a route, with exact 0/100% behavior and red waits of 5–90 seconds.

The client sends a custom identifying User-Agent, URL-encoded POST body, and JSON Accept header. Each uncached chunk has a maximum of three sequential HTTP calls: one primary attempt and at most two mirror attempts. Eligible primary failure switches to the mirror immediately. A mirror retry waits 2 seconds, or at least 30 seconds after HTTP 429; Retry-After seconds/date can increase the wait. A requested cooldown longer than 30 seconds ends automatic attempts for that host rather than sleeping through it. Cooldowns are tracked independently per host across calls, so a new Retry action does not bypass a provider's deadline.

Transient HTTP 408/429/500/502/503/504 responses, selected connection/DNS/timeouts, and HTTP 200 runtime remarks or malformed JSON can trigger retry/failover. Other HTTP errors, oversized payloads, certificate/authentication failures, and cancellation do not continue to another provider. Cancellation interrupts both requests and retry waits. Only successfully decoded responses enter the one-hour, bounded in-memory cache. Failed later chunks leave earlier published metadata usable, with partial/fallback coverage text and Retry.

The completed 3.2.0 investigation used public Cupertino coordinates. The primary returned a concrete HTTP 502 capacity/queue-full response, followed by timeouts. Separate public-fixture requests to the proposed mirror also timed out through curl and Apple's URLSession at that time. No real road/signal JSON was received in those earlier probes. The newly approved mirror POST probe also timed out after **28.0016 seconds**, with zero bytes, HTTP 000, and curl exit 28. It produced no response body; its header file is empty (`../work/road-network/approved-mirror-headers.txt`). **Live road/signal data remains unverified.** Fixture decoding/matching/transport tests are separate evidence from live provider availability. Investigation files remain local in `../work/road-network/`.

## Background execution

The retained background support now builds a valid fixed-format PCM buffer and explicitly zeroes every channel for silence. Audio interruption, media-services reset, configuration change, and stopped-engine/player recovery are handled. Location support starts an authorized foreground session with either While Using or Always access, requests an upgrade where appropriate, and falls back to audio if location is denied. At least one keep-alive preference stays enabled. Diagnostic state is available to the acceptance runner.

The measured background acceptance below used both audio/location support and Always authorization. It is evidence for that session and device, rather than indefinite operation under every interruption or permission combination.

## 3.2.1 build 3 verification

| Check | Status |
|---|---|
| Engine and fallback transport | **83 passed, 0 failures:** 78 XCTest plus 5 Swift Testing checks, including **24 road metadata tests**. Evidence: `../work/omega-3.2.1-fallback-tests.log`. |
| Live mirror response and mapping | Approved public Cupertino POST probe timed out after **28.0016 s**, zero bytes, HTTP 000, curl exit 28. No JSON or live mapping result. |
| Signed Release build | **Succeeded** for 3.2.1 build 3. Evidence: `../work/omega-3.2.1-release-build.log`. |
| IPA packages | **Verified** signed and unsigned 3.2.1 build 3 archives. Strict signed codesign passed; archived contents/file modes match; the unsigned copy has signatures/profile removed. Evidence: `../work/omega-3.2.1-package-validation.json`. |
| Physical install/launch | Installation and launch succeeded; installed-app inventory verified **Omega LocSim, `com.omega.locsim`, 3.2.1 (3)**. Evidence: `../work/omega-3.2.1-install.json`, `../work/omega-3.2.1-launch.json`, `../work/omega-3.2.1-installed-app.json`. |
| Installed UI / driving smoke | Autocomplete found Apple Infinite Loop Campus and Apple Park Visitor Center. A **3.4 mi driving preview** showed Go immediately at **fallback 30 mph** while metadata loaded. Route Timing named overpass-api.de and Private.coffee, with mapped details/lights on and probability 50%. Go displayed the simulated marker and remaining distance falling to **3.3 mi**; Pause displayed Paused. Evidence: `../work/omega-3.2.1-physical-smoke.txt`. |
| On-device road metadata | After the bounded loading attempt, UI displayed **“Road details unavailable. Using fallback speed; traffic lights are not included.”** and Retry. No live road/signal data was successfully received. Fixture failover tests are separate evidence. |
| Installed Restore / cleanup | Restore settled to idle Search Omega/Home/School/Work/Library; the route line, simulated marker, and active banner disappeared without error. Simulation was left cleared. Evidence: `../work/omega-3.2.1-physical-smoke.txt`. |

## Recorded 3.2.0 build 2 validation — October 23, 2026

| Check | Result and practical scope |
|---|---|
| Toolchain/device target | Xcode 27.1 with iOS SDK 27.1; the real app links the bundled physical-iOS arm64 bridge. |
| 3.2.0 final engine run | **76 passed, 0 failures:** 71 XCTest plus 5 Swift Testing checks, including 17 road metadata tests. Evidence: `../work/omega-3.2-final-tests.log`. |
| Foreground physical acceptance | Nine checks passed on iPhone 15 Pro Max, iOS 27.0: stationary; scheduled wait/Pause/Leave Now; natural intermediate visit; skipped visit; natural red light; skipped red light; movement/Pause/Resume/runtime speed-profile update; End holding; Restore. Evidence: `../work/omega-foreground-acceptance.json`. |
| Foreground scope | The runner used the actual device bridge with controlled public coordinates, short visits, injected light decisions, and an injected road-speed profile. “Live road metadata” in its check name means a runtime profile update, not a successful Overpass fetch. |
| Ten-minute physical background | Route check passed in 605.06 s: 1,122 accepted movement updates, 589.0468 m progress at selected 1 m/s, maximum report/progress gap 5.3309 s. Audio and location stayed running with Always authorization and no reported error. Restore passed in 0.080 s and `restored` is true. Evidence: `../work/omega-background-acceptance.json`. |
| Simulator UI | Actual map/view/planner/session sources in a separate harness with fake device transport. Interactive checks covered live autocomplete/resolution; Home pin creation/rename/removal; third stop; one-minute visit and ETA change; Leave Later/date control; 0/100% probability; Start while metadata loads; scheduled countdown/Leave Now; speed-mode selection; edit/apply retaining the visit. Evidence: `../work/ui-preview/omega-3.2-ui-validation.md`. |
| Simulator limits | Settings uses setup stubs; its units preference was verified separately on the physical phone. Numeric speed-slider adjustment was not established by that harness. No real device FFI or background endurance is inferred from simulator screenshots. |
| 3.2.0 live road service | Unavailable/unverified in the earlier probes described above. Fixture tests pass for decoding, unit/directional matching, crossing-road rejection, estimates, simplification, stable probability, retry/cache behavior, and partial retention. |
| Retry cancellation | A real 30-second rate-limit sleep was cancelled in approximately 0.001 s; no next request or publication occurred. A first successful chunk stayed published when all later retries failed. |
| 3.2.0 Release build/packages | **3.2.0 build 2 signed Release build succeeded** (`../work/omega-3.2-final-release-build.log`). Final signed/unsigned IPA packages were separately verified. |
| 3.2.0 physical install/launch | `devicectl` installation and launch succeeded. Installed-app inventory confirms **Omega LocSim, `com.omega.locsim`, 3.2.0 (2)**. Evidence: `../work/omega-3.2-final-release-install.json`, `../work/omega-3.2-final-release-launch.json`, `../work/omega-3.2-final-installed-app.json`. |
| 3.2.0 installed-release smoke | Apple Park autocomplete resolved correctly. Set Location displayed the simulated arrow and Holding location; Restore cleared both without error. Existing pairing remained usable after the update. Simulation was cleared after the check. |
| Physical manual units / route controls | Metric showed 48 km/h and 1.3 km; US Imperial showed 30 mph and 0.8 mi. Go remained usable during metadata loading with fallback speed; progress decreased from 0.8 to 0.5 mi. Pause and Resume changed state back to Simulating; Road Limits was selected again; slider endpoints of 1 and 85 mph changed ETA. Omega reached Arrived at 0 min/0 ft, and Restore cleared simulation. Live Overpass data remains unverified. |
| External GPS / Restore | Apple Maps recentered its blue user dot at the public test area, then visibly moved through successive positions along one short public route while Omega was backgrounded and reached the public endpoint. Restore returned the Maps dot to the real region. Stationary spoofing, movement on this route, and restoration were independently observed. No continuous GPS recording was collected; private real-location details/screenshots are omitted. |

Earlier 3.1.15 physical UI smoke checks also exercised Set Location, a driving route, Pause, Edit Route/Apply & Resume with unchanged remaining stops, End holding, and Restore after refreshed pairing resolved provider error 3. The 3.2 acceptance expands timing and background coverage; the earlier manual checks do not prove every current control on final hardware.

## Repeatable checks and builds

Run the isolated engine suite:

```sh
scripts/test-engine.sh
```

It copies actual engine/test files into a temporary package outside the Documents file-provider folder, uses Xcode's Swift toolchain, and removes the temporary build. Test stubs fail if real device transport is attempted. No new production package is required. The suite covers geometry, transport/holding/edit serialization, immediate pause races, failed replacement/restore, timing and clock behavior, speed integration, late metadata, units, local library persistence, stale request cancellation, and network retry/partial behavior.

Build an unsigned physical-device release:

```sh
xcodebuild -project StikDebug.xcodeproj -scheme StikDebug -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ../work/release-build \
  CODE_SIGNING_ALLOWED=NO build
```

For signed installation, choose the appropriate Apple signing team and connected phone in Xcode, or sign a separate unsigned IPA with the chosen sideloading tool. An unsigned IPA remains distinct from the development-signed app. The bundled bridge contains physical iOS arm64 objects and no simulator slice, so simulator UI testing uses a separate harness excluded from the delivered app.

## Remaining verification

Live mapped road/signal data still requires a responding provider. The 3.2.1 installed smoke used fallback speed and did not repeat the 3.2.0 external GPS or background run. External movement was observed on one short route; a continuous GPS recording and broader route coverage remain untested. Locked-screen behavior, system interruptions/audio route changes, disconnect/reconnect endurance, prolonged operation beyond this ten-minute session, the second physical phone, and iOS 27.0.1 remain separate checks. Owner targets are iPhone 15 Pro Max and iPhone 18 Pro Max on iOS 27.0/27.0.1; only iPhone 15 Pro Max on iOS 27.0 is established here.

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published. Private pairing files, account/device identifiers, and device logs are excluded from public delivery.
