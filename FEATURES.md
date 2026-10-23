# Omega LocSim 3.3.0 — features and controls

Reviewed October 23, 2026 for 3.3.0 build 9. This inventory describes the current implementation. **111 isolated checks passed** (106 XCTest and 5 Swift Testing), followed by 12 physical Debug acceptance checks and a ten-minute device protocol with more than nine minutes confirmed in the background. Current evidence and limits appear below; earlier builds remain dated separately in [IMPLEMENTATION.md](IMPLEMENTATION.md).

**Final Release delivery verified:** the 3.3.0 build 9 Release build and signed/unsigned IPA checks passed. Physical installation and launch succeeded; installed-app inventory confirms **Omega LocSim `com.omega.locsim` 3.3.0 (9)**.

## Browse, search, and map

- **Search Omega:** live MapKit autocomplete for names and addresses, biased toward the visible map. Suggestions show title/address; keyboard **Search** submits a complete query. Matching named pins appear above provider results. Loading, no-results, and connection-error states are visible; obsolete requests cannot replace a newer selection.
- **Clear search:** removes text/results. Search expands the sheet. Contextual prompts identify a starting-location, replacement-stop, added-stop, or pinned-place search.
- **Map tap:** selects a location while browsing or during explicit route/pin search. Existing route stops remain available while replacement search is open; Cancel/Close exits search without replacing them.
- **Map:** native MapKit roads and realistic elevation, pan/zoom, compass, scale, blue route geometry, numbered stops, and native user location when no simulated point is active.
- **Simulated location:** a blue dot, white ring, and translucent heading fan replace the arrow. The fan follows accepted simulated movement and accounts for map rotation.
- **Recenter:** follows the accepted simulated coordinate, or requests the native user-location camera when no simulated point exists. Panning stops following. Route following uses a pitched camera; Reduce Motion keeps the camera level and north-up.
- **Upper map control:** opens Omega Settings while browsing and **Show entire route** during playback. Route overview fits the geometry above the active card; Settings also remains in the route menu.
- **Resizable sheet:** compact/expanded positions keep the map available. Swipe up for more Places/history while browsing, or Route Options below a preview/active trip. Larger text uses taller layouts and flexible rows.

## Places and stationary simulation

The browse screen places **Places**, **Recents**, and **Saved Routes** in that order. Section headings open the complete collection.

**Places** uses large circular Home, Work, School, and custom-pin icons, followed by **Add**. Empty standard slots show **Set Up**. A pin shows **Close By** or distance from the accepted simulated location when one exists; otherwise it shows **Pinned**. These are distance labels, not driving-time estimates. Tap a saved pin to view its place. Add/Set Up starts search or map selection. The pin menu and collection rows offer **Change Location**, **Rename**, and **Remove Pin**. Standard kinds retain one saved location; custom pins can coexist.

The selected-place card contains its name, selectable coordinates, **Build Route**, **Set Location**, **Save or pin place**, Close, and Location options.

- **Build Route** prepares a driving draft from the accepted simulated location. Without an accepted start, **Choose Starting Location** requests an explicit one.
- **Set Location** sends a stationary coordinate; its accessibility label is **Set Spoofed Location**. Only acceptance creates a Recent and the Holding location state. Periodic refreshes maintain the accepted point.
- **Save or pin place** offers **Save Place**, **Pin as Home/School/Work**, and **Add Custom Pin**. The bookmark fills when that coordinate is already saved. Saving a bookmark twice does not create a duplicate.
- **Location options** exposes Settings, Saved Places & Import when available, and Restore Real Location during simulation.
- **Restore Real Location** clears simulation only on successful device acceptance. Failure retains the accepted simulated state and displays recovery guidance.

The complete **Places** collection contains Pinned Places and Saved Places. Pinned rows have direct options; saved rows can be renamed and deleted. Name editors provide Save/Cancel and ignore empty renames. Existing pins/bookmarks persist locally with their prior identities.

## Recents and Saved Routes

**Recents** contains accepted single-location spoofs and successful route starts/updates. Searches, viewing a place, saving a route, and failed device actions do not create history. The newest three appear on the browse sheet; the section heading opens the complete list.

- A place Recent opens its place card for review. Its menu offers **View Place**, **Save Place**, and **Remove from Recents**.
- A route Recent opens an editable route preview. Its menu offers **Build Route**, **Save Route**, and **Remove from Recents**.
- History is local, newest first, capped at 50 entries. Repeating the same location or ordered route updates its existing entry. Route stop order and stay durations distinguish route histories; single-location and route entries remain distinct.

**Saved Routes** appears directly below Recents, where Maps-style guide cards would appear. Empty state **Build a Route** starts the editor. Save from a route preview, a route Recent, or an active route's menu. Cards show a chosen name and start/destination; their menu offers **Build Route**, **Rename**, and **Delete Route**. The section heading opens all saved routes.

Saved Routes persists names, stop order, coordinates, and each stay duration. It does not store road geometry, a departure date, an arrival deadline, or a live playback session. Opening a saved/recent route recalculates a road preview; nothing starts until Go. Renaming/replacing a saved card retains its ID, and saving the same stop snapshot again updates its existing card. Removing history does not remove a separately saved route.

## Route building

| Control | Behavior |
|---|---|
| Starting location / stop row | Opens search to replace a place. The starting coordinate is fixed while editing an active route. |
| Add Stop | Opens explicit search and appends the selection. |
| Red remove button | Removes that stop by identity, cancels obsolete previews, and offers **Undo**. Removing down to fewer than two stops clears Go until a valid route exists. |
| Stop options / drag | Replace Stop, Move Up, Move Down, and intermediate Stay Duration. Drag reorders; menu commands provide the same ordering without dragging. |
| Driving / speed row | Identifies driving mode and reveals speed controls in Route Options. |
| Automatic preview | Calculates ordered MapKit driving legs after valid stop changes, showing markers and route geometry. |
| Finding route / Try Again | Shows calculation progress and retries failed geometry loading. |
| Timing / Options row | Expands and scrolls the existing map sheet to **Route Options** below the preview. |
| Preview summary | Shows duration, arrival, distance, speed mode, planned waits, and a Save Route control. An impossible Arrive By target exposes feedback and disables Go. |
| Go / Start Scheduled Route | Sends the start and begins movement, or holds there until departure, only after acceptance. Returns the sheet to the trip summary with Pause visible. |
| Apply Changes | Commits from the latest accepted location, preserves the user's playing/paused state, and returns to the trip summary. |
| Close | Cancels a stop search first; otherwise discards the draft. Closing an edit leaves the current trip's playback state unchanged. |

Existing road legs may be reused. Superseded geometry/metadata cannot publish into a newer draft. Go does not wait for optional road details. Remaining stops completed while an edit is open are pruned when applying; ambiguous, diverged, or reordered geometry is replanned from the accepted position rather than jumping to a stale preview start.

## Inline Route Options

**Swipe up below the preview or active-trip card** for Route Options. Scheduling, Roads & Traffic Lights, and Speed stay in that same map sheet. The timing/Options and speed shortcuts scroll there; they do not open a separate Route Timing settings page.

### Departure and arrival

- **Leave Now** starts when Go is accepted. **Leave Later** and its Departure picker arm a new route at the accepted start until the countdown expires. **Leave Now** in the wait row skips the departure wait. This is an active countdown, not a scheduled launch of a terminated app. Active route edits do not add a new delayed departure.
- **Arrive By** selects an arrival target in either the draft or active Route Options. During a trip, **Apply Arrival Time** commits a changed target; **Cancel** restores the current target. **No Arrival Target** removes it after Apply.
- Omega accounts for remaining travel, stop stays, departure waits, and sampled traffic lights. If needed, it makes the smallest number of red lights green, removing longer waits first; only after exhausting those waits does it increase simulated speed. A small adjustment can preserve most red lights. Green decisions remain stable across progressive road-data updates.
- Automatic pacing is bounded at **250 mph (111.76 m/s)** and does not silently remove stop stays or resume a user pause. If remaining stays or the speed ceiling make a target impossible, the app says so. Connection stalls, manual pauses, or unavailable background execution can prevent on-time arrival. Arrive By is a bounded simulation target, not a physical journey guarantee.

### Visits and traffic lights

- **Stay Duration** in an intermediate stop's options opens No delay, wheel presets, and a one-minute stepper from 0 to 1,440 minutes. Save applies it; Cancel preserves it. Reordering carries the duration. Final arrival holds until End or Restore and has no visit timer.
- **Mapped Road Details** is off by default. Enabling it permits route corridor coordinates to go to `overpass-api.de` and the approved fixed fallback `overpass.private.coffee` for OpenStreetMap road limits/signals. A working mirror can be reused, with primary fallback if needed. Both services are covered by this opt-in; there is no separate mirror switch. See the [Private.coffee service and privacy policy](https://overpass.private.coffee/).
- **Traffic Lights** enables mapped signals. **Red-light probability** ranges from 0–100% in 1% steps, default 50%. Stable route sampling assigns green or a simulated red wait of 5–90 seconds. These are simulated colors, not live signal phases. Changing the road/light options refreshes applicable metadata while retaining accepted progress.
- **Metadata status / Retry** shows loading, mapped-limit coverage, light count, partial coverage, or unavailable data. Loading/failure leaves Go available at fallback speed. Successful chunks remain usable if later loading fails. Uncached chunks use at most three sequential HTTP calls across the approved services; cancellation ends retries.

A wait row shows the countdown plus **Leave Now** for departures/visits or **Skip Light** for red lights. Pause freezes the remaining countdown; skipping while paused does not resume movement. Active waits survive route changes, and a wait skipped during replanning is not restored.

## Speed, units, and ETA

- **Road Limits** (default) uses mapped limits and road-type estimates for matched sections. Missing, unsupported, unloaded, or unmatched sections use estimates or selected fallback speed. Coverage text identifies estimates; mapping does not establish every physical restriction.
- **Constant** uses the selected slider speed, with simulated signals and stays still included. Arrive By can raise the effective simulated pace when necessary.
- The slider controls constant/fallback speed, normally 1–85 mph or 1–135 km/h in whole units; default 30 mph. Unit conversion can extend an endpoint to retain the exact physical speed.
- **Settings → Measurement System** selects US Imperial (miles/feet/mph, default) or Metric (kilometers/meters/km/h) consistently. Switching units preserves physical speed/distance.
- The active trip card shows **current simulated speed** beside arrival, remaining time, and distance. It reads zero while paused, waiting, or arrived; it reflects the effective road/arrival-adjusted pace while moving.
- ETA integrates the speed profile and outstanding visits/lights, including delayed departure in preview. Road-data changes, speed changes, and arrival targets update the projection. It is not a traffic-based travel forecast.

## Active route, editing, and recovery

The banner shows Simulating, Paused, Leaving later, Staying at stop, Red light, or Arrived, with destination/wait text. The trip card has Pause/Resume, Edit Route, route menu, arrival feedback, and inline options below. A paused arrival time displays a dash.

- **Edit Route** immediately opens the remaining-stop draft while playback continues. A visible Pause/Resume control still lets the user decide. Opening or discarding the editor does not pause the trip.
- **Apply Changes** briefly drains the in-flight device call and commits from its accepted point, then restores the prior playing/paused state. A Pause pressed during commit remains authoritative. Completed stops and obsolete geometry cannot move the simulation backward. A failed replan retains the original route/progress and draft, resuming the previous trip if it was playing and the user did not pause.
- **Pause** takes intent immediately; an already-started device call finishes before accepted progress settles. Resume excludes paused time from movement.
- **End Route** invalidates pending edit work, removes the route/draft, and keeps holding the last accepted coordinate.
- **Restore Real Location** invalidates pending work and clears simulation on success; failure retains the accepted state and exposes recovery guidance.
- **Arrived** holds the endpoint; End/Restore remain available. Device failures freeze accepted progress and surface a Simulation Unavailable alert plus inline recovery information.

## Coordinate import and Omega Settings

**Places → Import Coordinates**, while browsing, opens Files for GPX, KML/XML, GeoJSON, JSON, CSV, and plain-text coordinates. One coordinate opens a place. Multiple coordinates prepare a path preview with start/end stops and cancel previous draft work. Imported paths use geometry rather than timestamps; changing their stops recalculates MapKit road geometry.

Settings retains the Omega icon/branding, version/iOS footer, Built on StikDebug and Omega Source links, Measurement System, pairing-file import and tunnel outcome, Target Device IP and Remote Pairing Port, App Folder, confirmed Redownload DDI and progress, and support/attribution links. **Road Data Backup & Privacy** opens the official fallback-service privacy/terms page. General Settings does not contain the route's scheduling, speed, or traffic-light controls.

**Silent Audio** and **Background Location** retain upstream background support and recovery paths. At least one stays enabled; denied location access falls back to audio. These mechanisms do not establish indefinite background operation under every interruption or permission combination.

## Appearance and limits

The map interface uses deeper Apple-style blue, SF Symbols, semantic system surfaces, and native Liquid Glass on iOS 26+ with earlier material/bordered fallbacks. Dynamic Type, accessibility names, non-drag ordering controls, Reduce Motion camera behavior, and Reduce Transparency surfaces are implemented. Light/dark and maximum-text UI audit fixes are implemented; complete VoiceOver and interruption/endurance coverage remain unverified. The existing 40-layer peeled Maps/Omega icon remains selected, including its blue blueprint in both light and dark mode.

Not implemented: joystick, automatic route looping, cloud place sync, coordinate export, offline road lookup/routing, imported timestamp replay, custom acceleration curves, walking/cycling/transit modes, alternative-route selection, spoken navigation, or Apple Maps account sync.

## Recorded 3.3.0 checks — October 23, 2026

- **Engine:** 111 passed, zero failures — 106 XCTest plus 5 Swift Testing checks, including persistence, timing/arrival, live-edit races, geometry, and progressive metadata. Evidence: `../work/arrival-engine-verified-tests.log`.
- **Physical Debug acceptance:** all 12 checks passed in 30.34 seconds using actual device commands. Coverage includes stationary simulation; delayed departure/Pause/Leave Now; natural/skipped visits and red lights; playback/Pause/Resume/runtime speed metadata; Arrive By; impossible-deadline warnings without dropping stays; live editing with preserved progress/pause; End holding; and Restore. Signal/speed cases use controlled fixtures rather than live Overpass. Evidence: `../work/omega-3.3.0-device-acceptance.json`.
- **Ten-minute protocol:** elapsed 605.739 seconds, 1,113 accepted movement updates, 586.44 m maximum progress, 5.339 seconds maximum report/progress gap, and successful Restore. Diagnostics show 114 active background samples from 20:01:38–20:11:01 UTC spanning 562.17 seconds — **more than nine minutes confirmed background execution**, not a full ten minutes continuously backgrounded. Audio/location stayed running, While Using authorization was recorded, and no errors were reported. Evidence: `../work/omega-3.3.0-background-acceptance.json` and `../work/omega-3.3.0-background-diagnostics.json`.
- **Independent observation:** Apple Maps showed movement and restoration. This complements accepted bridge commands; no continuous GPS recording was collected.

- **Release delivery:** final Release build and signed/unsigned package verification passed. Install/launch succeeded, and inventory confirms Omega LocSim `com.omega.locsim` **3.3.0 (9)**. Final small label/scroll changes were rebuilt and reinstalled.
- **Physical interface smoke:** public Cupertino autocomplete resolved; an accepted single-location spoof appeared in Recents; a four-minute road preview offered Go before road metadata; playback showed 30 mph and the blue heading dot; opening Edit Route kept movement running through natural arrival; a saved-route name persisted; Restore returned to idle and the real region. These observations use the same 3.3.0 engine as the final delivery.
- **Simulator handoff:** Go and Apply from lower Route Options returned to the trip summary with Pause visible. Light/dark and maximum-text audit fixes were also implemented.

The evidence combines isolated tests, physical Debug acceptance, observed interface flows, and final Release installation; it does not prove every feature under every condition. VoiceOver, locked-screen/system-interruption/disconnect endurance, longer operation, the second phone, iOS 27.0.1, and live provider data are not established by these checks.

## Historical validation

The records below describe the named earlier builds only. They do not confirm the new 3.3.0 controls or final installation.

### Recorded 3.2.0 build 2 validation — October 23, 2026

The 3.2.0 build passed **76 isolated checks** (71 XCTest and 5 Swift Testing), including 17 road metadata checks. A development build passed nine foreground device checks and a 605-second background run on iPhone 15 Pro Max, iOS 27.0, followed by successful restoration. Foreground light/speed metadata checks used controlled fixture data. Simulator interaction covered autocomplete, Home pin creation/rename/removal, three stops, a one-minute visit, Leave Later, 0/100% probability, Start during metadata loading, Leave Now, speed-mode selection, and Apply & Resume with a retained visit.

Physical manual checks confirmed Metric 48 km/h and 1.3 km converting to Imperial 30 mph and 0.8 mi; Go while road metadata was loading with fallback speed; progress from 0.8 to 0.5 mi; Pause and Resume returning to Simulating; Road Limits selection; and 1/85 mph slider endpoints changing ETA. Omega reached **Arrived, 0 min, 0 ft** and Restore cleared simulation.

Apple Maps independently confirmed stationary spoofing, successive movement along one short public test route while Omega was backgrounded, and return to the real region after Restore. A continuous GPS recording was not collected. The 3.2.0 live Overpass probes did not establish data availability. New mirror availability, locked-screen/interruption/disconnection endurance, the second physical phone, and iOS 27.0.1 still need separate verification.

The final **3.2.0 build 2 signed Release** was built, packaged, installed, and launched. Inventory verified **Omega LocSim, `com.omega.locsim`, 3.2.0 (2)**. The freshly installed app resolved Apple Park autocomplete; Set Location showed the simulated marker/Holding location; Restore removed them without error. Existing pairing remained usable after the update, and simulation was cleared after the smoke check.

### Recorded 3.2.1 build 3 verification — October 23, 2026

**83 isolated checks passed** (78 XCTest plus 5 Swift Testing), including **24 road metadata tests**. The signed Release build succeeded. Physical installation and launch succeeded; inventory verified **Omega LocSim, `com.omega.locsim`, 3.2.1 (3)**. The signed/unsigned IPA packages were verified.

The installed app's autocomplete found Apple Infinite Loop Campus and Apple Park Visitor Center and prepared a **3.4 mi driving route**. Go was immediately available at **fallback 30 mph** while metadata loaded. Route Timing visibly named both providers, with Mapped Road Details and Traffic Lights enabled and probability at 50%. Go started simulation with a marker and remaining distance falling to **3.3 mi**; Pause displayed Paused.

After the bounded loading attempt, the app displayed **“Road details unavailable. Using fallback speed; traffic lights are not included.”** and Retry. Restore returned to idle Search Omega/Home/School/Work/Library, removing the route, simulated marker, and active banner without error. Simulation was left cleared.

Live road data was **not** successfully received. The approved Mac mirror probe also timed out after 28.0016 seconds with zero bytes (HTTP 000). Fixture transport checks remain separate from a live provider response. The earlier external GPS and ten-minute background observations belong to the 3.2.0 baseline; they were not repeated for 3.2.1.
