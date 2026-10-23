# Omega LocSim 3.3.0 implementation and validation

## 3.3.0 build 9 — interface, history, and arrival targets

The map sheet now leads with Places, Recents, and Saved Routes. Large SF Symbol place icons, section navigation, visible row menus, direct stop removal with Undo, deeper blue accent tokens, a blue location dot/heading fan, and current simulated speed align the browsing and route-building flow with the supplied Maps references. The installed `apple-design` and `ui-ux-pro-max` skills informed the audit; this describes implemented changes, not a completed certification of every accessibility/layout scenario.

Route settings live inline below the preview or active-trip card. Expanding/swiping up reveals **Route Options** for departure/arrival, Roads & Traffic Lights, and Speed. The former Route Timing sheet is removed; shortcut rows expand/scroll the existing map sheet. Active arrival changes have explicit Apply/Cancel actions. Stay Duration remains a focused editor attached to an intermediate stop.

**3.3.0 engine and physical Debug acceptance passed.** The isolated suite completed **111 checks: 106 XCTest and 5 Swift Testing, zero failures**. All **12 foreground physical Debug checks** passed in 30.343 seconds. The ten-minute protocol passed with 605.739 seconds elapsed, 1,113 accepted movement updates, 586.44 m maximum progress, and successful restoration; diagnostics separately confirm 562.17 seconds (more than nine minutes) actually backgrounded. Detailed evidence and scope follow below.

**Final Release delivery verified:** the 3.3.0 build 9 Release build and signed/unsigned IPA checks passed. Physical installation and launch succeeded; installed-app inventory confirms **Omega LocSim `com.omega.locsim` 3.3.0 (9)**.

### Local Places, Recents, and Saved Routes

`OmegaPlaceLibrary` retains the established `omegaPinnedPlaces` and `locationBookmarks` keys and IDs. The new `omegaRecentActivities` and `omegaSavedRoutes` collections store `OmegaStoredStop` snapshots: title, latitude/longitude, and dwell duration. They do not persist MapKit geometry, departure/arrival dates, device state, or execution commands. Loading a route yields editable `SimulationStop` values and requires a new road preview before Go.

History recording is explicit after successful stationary acceptance or successful route start/update. Search, selection, saving, and failed actions do not record history. Recents retain timestamps, sort newest first, deduplicate by kind plus coordinate/ordered dwell snapshot, preserve an existing entry's identity, and cap at 50. Saved Routes retain an independent ID and chosen name, update duplicate snapshots, support rename/delete/replacement, and survive removal of their originating Recent. Per-record decoding discards malformed entries without losing valid neighboring records. Existing bookmark/pin persistence and new migration/dedup/delete behavior are covered by the library tests.

### Live editing and accepted progress

Opening or canceling Edit Route does not pause the session. `applyEditedRoute` captures the playback intent, drains the in-flight bridge update, and commits from the latest accepted coordinate. A revision counter preserves a manual Pause that arrives during commit. Stop identity excludes visits completed while editing; a draft can trim a safe, unambiguous future path, but diverged paths, ambiguous self-intersections, and omitted interior legs require fresh road planning. Old enrichment requests cannot apply their prior distance system to the new route identity.

Current waits are retained after awaited replanning rather than from a stale earlier snapshot, so Skip during the await is not undone. A failed road replan leaves the old route/progress and draft intact and resumes only if it was playing and no later manual pause intervened. End/Restore invalidate pending edits; restoration clears state only after device acceptance. These paths use the same serialized transport as normal movement and stationary holding.

### Arrive By model

`ArrivalTimingPlan` receives the remaining travel profile, fixed departure/visit waits, red-light waits, and deadline budget. It first removes the smallest count of red waits required, choosing longest waits first with route order as the tie-breaker, then increases the speed multiplier if removing all available red waits is insufficient. Per-segment integration applies a finite **111.76 m/s (250 mph)** simulator ceiling; positive profile speeds normalize to at least 0.1 m/s so the deadline search uses the same bounds as movement. Invalid/nonfinite deadlines are rejected or treated as infeasible rather than producing infinite speed.

`LocationSimulationSession` refreshes the adjustment against the wall-clock deadline, settled active wait, accepted progress, live speed profile, and a reserve for the last bridge latency plus one tick. Fixed stays and manual pauses remain authoritative. Arrival retargeting can release a current red light without resuming a paused trip. Already-greened signal identities remain stable across progressive metadata snapshots so the same light is not reintroduced by a regenerated provider UUID. Preview exposes infeasible targets; active playback exposes a warning and finite capped pace. This is a simulator deadline controller, not a guarantee across a stopped app, disconnect, indefinite pause, or unbounded transport stall.

## Historical artwork and release evidence — October 23, 2026

### 3.2.6 icon positioning refinement

Build 8 raises the navigation assembly 100 canvas units, expands the shared peel reveal by about 70–80 units, and uses the same blue blueprint gradient and construction-guide colors in Default and Dark. The map's dark palette remains charcoal with blue navigation. The Omega path and its centering/symmetry are unchanged. The shared mask remains identical across all 18 map/navigation elements. The 40-layer source remains vector-only. Build/package evidence: `../work/omega-3.2.6-release-build.log`, `../work/omega-3.2.6-package-validation.json`. This is an artwork-only change; no phone connection or installation was performed.

### 3.2.5 complete-map masking and dark palette

Build 7 reconstructs the entire map before applying an identical vector peel clip to all 18 geography/navigation elements. The unmasked construction is preserved as `branding/omega-locsim-peel/CompleteMap.icon`. The lower navigation disc, descending diagonal road, route corridor, corner interchange, and colored regions follow the supplied light/dark references. Two separate peel vectors and native group shadow create the fold. Forty vector layers remain individually editable in four groups.

Default and dark colors are now stored exclusively as native fill specializations. The prior base fill silently took precedence over dark overrides; it is removed. Dark mode has charcoal regions, a blue corridor/lens, neutral rim and fold, and white arrow/Omega. The underlying Omega is symmetric around x=512 and its geometric bounding box is centered at (512,512), independently of the asymmetric peel. Full-map and peeled Default/Dark previews were inspected alongside ClearLight/ClearDark/TintedDark and Home Screen sizes. Icon Composer opened/saved the source without warnings. No runtime logic or phone state was changed. Release build/package evidence: `../work/omega-3.2.5-release-build.log`, `../work/omega-3.2.5-package-validation.json`.

### 3.2.4 individual vector materials

Build 6 uses 36 individual SVG geometry layers in four Icon Composer groups. Each map region, road, rim accent, lens, arrow, fold, Omega outline, and construction guide is separately editable. SVG files contain no bitmap images, gradients, opacity, filters, or baked shadows. Colors and surface materials are native Composer properties. The 19 construction guides use native opacity without raised glass edges to keep the diagram legible. The remaining 17 elements have native glass. Default, Dark, ClearLight, ClearDark, and TintedDark exports were inspected, including 60-pixel previews. Icon Composer opened and saved the document without group-limit warnings. No runtime code changed; no device connection or installation was performed. Build and package evidence: `../work/omega-3.2.4-release-build.log`, `../work/omega-3.2.4-package-validation.json`.

### 3.2.3 artwork update

Build 5 selects `OmegaLocSimPeel.icon`, rebuilt from the supplied Maps-peeling-to-Omega-blueprint reference as eight SVG layers in three groups. The construction grid and Omega share a precise center; the map surface, folded edge, separation shadow, navigation rim, lens, and arrow remain independently editable. Native glass effects were configured in Apple's Icon Composer UI; dark Omega/arrow fills preserve contrast. Default, Dark, and TintedDark exports were visually inspected. Settings branding uses the new exports. The previous flattened composition is preserved under `branding/omega-locsim-peel/previous-flattened.icon`. Runtime source is unchanged. The signed Release build and both IPA packaging checks passed (`../work/omega-3.2.3-release-build.log`, `../work/omega-3.2.3-package-validation.json`). The compiled iPhone fallback icon was decoded and visually checked. No phone connection or installation was performed for this artwork update.

### Earlier 3.2.1 validation

This **3.2.1 build 3** update adds the user-approved fixed Overpass fallback under the existing Mapped Road Details opt-in. **83 isolated checks passed**; the signed Release build, physical installation, and launch succeeded. Inventory verified **Omega LocSim `com.omega.locsim` 3.2.1 (3)**. Signed/unsigned IPA packages were verified. Installed-release smoke confirmed public-place autocomplete, a driving preview, Go/progress/Pause at fallback speed, and successful Restore to idle. The approved mirror live probe timed out without a response, so live road data remains unverified. Completed 3.2.0 build 2 engine, foreground/background device, external GPS, and installed-release checks remain recorded separately below.

## Source, identity, and artwork

Based on [StikDebug](https://github.com/StikDebug/StikDebug) commit `17b1e1d90d602a228de663a10efa987a9f9e547b`, with [idevice](https://github.com/jkcoxson/idevice) for device communication. `README.upstream.md`, original notices, and [AGPL-3.0](LICENSE) remain preserved.

Omega LocSim uses `com.omega.locsim` and `group.com.omega.locsim`, including legacy group-storage callers. StikDebug URL registrations were removed to avoid intercepting the original app's links. Internal project/module names, protocol Bonjour declarations, preferences, and file identifiers retain compatibility. Current release version is **3.3.0, build 9**; engine, physical Debug, interface-smoke, and final Release delivery evidence are recorded here. The prior **3.2.0, build 2** release is documented in the separate baseline below.

The active icon is `StikDebug/OmegaLocSimPeel.icon`, retaining the 40-layer vector construction and shared blue light/dark blueprint from 3.2.6. Settings uses its Default/Dark exports. The previous 3.2 icon is retained as historical artwork. `StikDebug/OmegaLocSimGlass.icon` contains original Ω and navigation SVG layers assembled, previewed, and saved with Apple's Icon Composer. Native group glass effects and a cyan-to-cobalt background produce Default, Dark, and tintable appearances. The historical 3.2 build selected `OmegaLocSimGlass`; current configurations select `OmegaLocSimPeel`. The synchronized target includes the selected document automatically. `OmegaLocSimBrand.imageset` uses resized Default/Dark renders for Settings. Original SVGs, workflow details, and Apple references are in [branding/omega-locsim-glass/README.md](branding/omega-locsim-glass/README.md).

For the historical 3.2 glass artwork, isolated Xcode 27.1 `actool` compilation passed for iPhone/iPad, deployment target 17.4. Generated metadata names `OmegaLocSimGlass`; `Assets.car` contains native light/dark/tintable icon stacks and both SVGs. The generated iPhone fallback was decoded and visually checked. The prior supplied JPEG, raster icon, and upstream `StikDebug.icon` remain preserved; they are not the selected new icon.

## Application behavior

[FEATURES.md](FEATURES.md) is the full user-facing control inventory.

- Native MapKit browsing, autocomplete and explicit search, selected-place cards, accepted stationary spoofing, ordered driving stops, automatic preview, and active trip controls. Home/Work/School/custom pins, persistent bookmarks, successful-action Recents, named Saved Routes, and coordinate import share the browsing flow.
- Native Liquid Glass on iOS 26+ with earlier material/bordered fallbacks, deeper blue accents, semantic light/dark surfaces, accessibility labels, Dynamic Type layouts, non-drag alternatives, flexible scrolling, Reduce Motion camera handling, and Reduce Transparency surfaces.
- One measurement preference controls distances and speeds. Road Limits applies per-segment speed metadata; Constant applies the slider speed. Missing/unloaded sections use fallback speed. Unit changes preserve physical speed.
- Inline Route Options below the preview/active card contains Leave Later/Arrive By, road/light controls, and speed. Intermediate visits, simulated red lights, countdowns/skips, Pause/Resume, and ETA share the session timing model; arrival targets adjust light waits and bounded simulated pace. Final arrival holds until End or Restore.
- Session-owned movement and stationary holding serialize all device commands. Accepted position is authoritative; an already-started synchronous bridge call finishes before the next command. Transport duration contributes to movement timing; excess scheduling gaps are handled separately.
- Pause intent is immediate. Opening Edit Route preserves playback; committing drains accepted progress, rebases/replans remaining stops, and restores the playing/paused intent. Apply retains current waits without resurrecting a skipped one and protects the old progress/draft on failure. End/Restore invalidate pending edits; restoration clears state only on success.
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

The 3.3.0 protocol recorded both audio/location support with While Using authorization throughout its confirmed background samples. The historical 3.2.0 run used Always authorization. Each is evidence for its particular session and device, rather than indefinite operation under every interruption or permission combination.

## Recorded 3.3.0 verification — October 23, 2026

| Check | Result and practical scope |
|---|---|
| Final isolated engine run | **111 passed, zero failures:** 106 XCTest and 5 Swift Testing checks. Includes stable green decisions across progressive metadata, deadline feasibility, live-edit/skip/pause races, geometry rebasing, history/saved-route persistence, and prior transport/road-data coverage. Evidence: `../work/arrival-engine-verified-tests.log`. |
| Foreground physical Debug acceptance | **12 checks passed in 30.3429 s:** stationary; Leave Later/Pause/Leave Now; natural intermediate visit; skipped visit; natural red; skipped red; movement/Pause/Resume/runtime speed metadata; Arrive By lights/speed retarget; impossible arrival retaining stays; live edits preserving progress/pause; End holding; Restore. Evidence: `../work/omega-3.3.0-device-acceptance.json`. |
| Foreground scope | The runner used the actual device bridge with controlled route coordinates, light waits, and speed profiles. The runtime metadata check is fixture injection, not a successful Overpass response. It recorded 52 accepted location updates, including 29 movement updates; restoration succeeded. |
| Ten-minute protocol | **Passed**, 605.7392 s elapsed with 1,113 accepted movement updates, 586.4400 m maximum traveled distance, and 5.3393 s maximum report/progress gap. Restore passed in 0.0928 s and `restored` is true. Evidence: `../work/omega-3.3.0-background-acceptance.json`. |
| Confirmed background portion | **114 active background samples**, 20:01:38–20:11:01 UTC, spanning **562.1681 s by monotonic uptime**. Audio and location were running in every sample, authorization was **While Using**, and no errors were reported. This proves more than nine minutes backgrounded within the ten-minute protocol; it does not prove ten full minutes continuously backgrounded. Evidence: `../work/omega-3.3.0-background-diagnostics.json`. |
| External location observation | Apple Maps independently showed movement and restoration. This is separate from bridge command acceptance. No continuous GPS recording was collected; private location details are excluded. |
| Final Release build | **Succeeded** for 3.3.0 build 9, including the final small UI label/scroll fixes. Evidence: `../work/omega-3.3.0-release-build.log`. |
| Signed/unsigned IPA packages | **Passed** strict extracted signature verification, removed-signature checks for the unsigned copy, content/file-mode matching, and private/debug audit. Evidence: `../work/omega-3.3.0-package-validation.json`. |
| Final install, launch, inventory | **Succeeded**; inventory confirms **Omega LocSim, `com.omega.locsim`, 3.3.0 (9)**. The final small label/scroll changes were rebuilt and reinstalled. Evidence: `../work/omega-3.3.0-final-install.json`, `../work/omega-3.3.0-final-launch.json`, `../work/omega-3.3.0-final-installed-app.json`. |
| Physical interface smoke | On the same 3.3.0 engine: public Cupertino autocomplete resolved; accepted stationary simulation appeared in Recents; a four-minute road preview offered Go before metadata; playback displayed 30 mph and the blue heading dot; Edit Route kept movement running until natural Arrived; a saved-route name persisted; Restore returned to idle and the real region. These selected observations do not prove every control under every condition. |
| Simulator interface handoff | Go and Apply from lower Route Options returned to the trip summary with Pause visible. This verifies the final scroll/handoff behavior with fake transport; physical command acceptance is established separately above. |
| UI audit | Light/dark and maximum-text audit fixes are implemented. Complete VoiceOver and interruption/endurance coverage remain unverified. |

## Recorded 3.2.1 build 3 verification — October 23, 2026

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

It copies actual engine/test files into a temporary package outside the Documents file-provider folder, uses Xcode's Swift toolchain, and removes the temporary build. Test stubs fail if real device transport is attempted. No new production package is required. The suite covers geometry and ambiguous-loop rebasing, transport/holding/edit serialization, pause/skip races, failed replacement/restore, deadline feasibility and minimal light removal, timing/clock behavior, capped speed integration, progressive metadata, units, pins/bookmarks/history/saved-route persistence, stale request cancellation, and network retry/partial behavior.

Build an unsigned physical-device release:

```sh
xcodebuild -project StikDebug.xcodeproj -scheme StikDebug -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath ../work/release-build \
  CODE_SIGNING_ALLOWED=NO build
```

For signed installation, choose the appropriate Apple signing team and connected phone in Xcode, or sign a separate unsigned IPA with the chosen sideloading tool. An unsigned IPA remains distinct from the development-signed app. The bundled bridge contains physical iOS arm64 objects and no simulator slice, so simulator UI testing uses a separate harness excluded from the delivered app.

## Remaining verification

Final Release build, packages, installation, launch, and installed-version inventory are verified above. The selected physical and simulator interface observations complement the engine/Debug acceptance results; they do not establish exhaustive device coverage.

VoiceOver, locked-screen behavior, system interruptions/audio route changes, disconnect/reconnect endurance, prolonged operation beyond the measured protocol, the second physical phone, and iOS 27.0.1 remain separate checks. Live mapped road/signal data still requires a responding provider; fixture acceptance and successful fallback operation do not verify it. Apple Maps independently showed movement and restoration on the observed route, but a continuous GPS recording and broader route coverage remain untested. Owner targets are iPhone 15 Pro Max and iPhone 18 Pro Max on iOS 27.0/27.0.1; only iPhone 15 Pro Max on iOS 27.0 is established here.

Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the Omega LocSim implementation; no GitHub Release is published. Private pairing files, account/device identifiers, and device logs are excluded from public delivery.

### Final library navigation check

A first-open sheet selection defect was reproduced in the simulator: Show all saved routes opened Places. The library now presents one optional section through an item-driven sheet; Saved Routes on first open and subsequent Recents navigation were verified after rebuilding. Recent single-location selection reopened its place card without starting a spoof. The final Release was rebuilt, packaged, reinstalled and launched after this fix.
