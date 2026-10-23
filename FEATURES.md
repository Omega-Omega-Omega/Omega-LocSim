# Omega LocSim 3.2.5 — features and controls

Reviewed October 23, 2026 for 3.2.5 build 7. This artwork-only update uses the supplied Maps-peeling-to-Omega-blueprint composition in the app icon and Settings branding. Physical checks below belong to the earlier builds, not 3.2.5. Prior 3.2.1 results and the 3.2.0 build 2 baseline are listed separately below. This inventory describes the current control set; detailed evidence is in [IMPLEMENTATION.md](IMPLEMENTATION.md).

## Browse, search, and map

- **Search Omega:** type a name or address for live MapKit autocomplete, biased toward the visible region. Suggestions show a title/address and resolve to a selected place. Keyboard **Search** submits the full query as a fallback. Matching named pins appear above provider results. Finding places, no-results, and connection-error feedback are visible; obsolete searches cannot replace newer selections.
- **Clear search:** removes text/results. Search expands the sheet; contextual prompts identify starting-location, replacement-stop, added-stop, and pin searches.
- **Map tap:** drops a pin while browsing or supplies a place during an explicit route/pin search. A route's existing stops are retained while replacement search is open. Cancel/Close exits that search without replacing the old place.
- **Map:** standard MapKit map with realistic elevation, pan/zoom, compass, scale, user-location annotation, blue route geometry, numbered stop markers, and a simulated-position arrow.
- **Recenter:** follows the accepted simulated position, or requests the native user-location camera when no simulated point exists. Panning stops follow mode. Active follow uses heading and a pitched camera; the arrow accounts for map rotation.
- **Upper map control:** opens Omega Settings while browsing and **Show entire route** during playback. Overview fits the route above the active card. Settings remains available in the route menu.
- **Resizable sheet:** drag between compact, preview, intermediate, and expanded positions. Waiting/speed states and accessibility text sizes have taller layouts. The main sheet remains present while the map can be manipulated.

## Selected place and stationary location

The place card has the place title, selectable coordinates, **Directions**, **Set Location**, **Save or pin place**, **Close**, and **Location options**.

- **Directions** prepares a driving draft from the accepted simulated coordinate. Without one, **Choose Starting Location** asks for an explicit start.
- **Set Location** sends a stationary coordinate. Its accessibility label is **Set Spoofed Location**. On acceptance, the marker and **Holding location** state remain, with periodic refreshes.
- **Save or pin place** offers **Save to Library**, **Pin as Home/School/Work**, and **Add Custom Pin** with a name editor.
- **Location options** offers Settings, Saved Places & Import when available, and Restore Real Location when simulation is active.
- **Restore Real Location** requests clearing simulation. Success removes its active state; failure preserves the accepted simulated state and reports the error.

## Pins, library, and files

The browse shelf contains Home, School, Work, and custom pins. Empty standard slots show **Add**. Tapping a saved pin opens its place; an empty slot starts search or map selection. A pin's context menu offers **Change Location**, **Rename**, and **Remove Pin**. Changing a standard pin replaces its saved location; custom pins can coexist.

**Library** opens **Omega Library**, with Pinned and Saved Places sections. Pin rows can be selected, renamed, or removed with swipe actions; **Add Pinned Place** creates a custom pin. Saved-place rows can be selected, renamed with a leading swipe, or deleted. Name dialogs provide **Name**, **Save**, and **Cancel**; blank renames are ignored. Duplicate bookmark coordinates are not added twice. Pins and bookmarks persist locally across launches.

**Import Coordinates**, available from the browsing library rather than an active route/draft, opens Files for GPX, KML/XML, GeoJSON, JSON, CSV, and plain-text coordinate files. One coordinate opens a place. Multiple coordinates create a playable path preview with start/end stops, replacing the prior draft and canceling its pending requests. Imported paths use geometry rather than file timestamps. Editing their stops recalculates MapKit road geometry. **Done** closes the library.

## Route preparation

| Control | Behavior |
|---|---|
| Starting location / stop row | Opens search to replace that place. The accepted start is fixed while editing an active route. |
| Add Stop | Opens explicit search and appends the chosen place. |
| Stop options | Replace Stop, Move Up, Move Down, and Remove Stop where applicable. Intermediate stops also offer Stay Duration. |
| Drag a non-start stop | Reorders it. Menu commands provide an alternative. |
| Driving / speed row | Identifies driving mode and opens speed controls. |
| Automatic preview | Calculates ordered MapKit driving legs after valid stop changes, with stop markers and a route line. |
| Finding route / Try Again | Shows calculation progress and retries failed geometry loading. |
| Leave Now / timing row | Opens Route Timing, showing scheduled departure or the configured red-light probability when enabled. |
| Preview summary | Shows projected minutes, arrival time, distance, speed mode, and planned wait duration. |
| GO / Start | Sends the starting point and begins movement or arms a departure wait after that coordinate is accepted. |
| Apply & Resume | Applies an edited remaining route after acceptance. Failure retains the old route/progress, draft, and error. |
| Close | Cancels a stop search first; otherwise discards the draft. Closing an edit keeps the original route paused. |

Unchanged road legs may be reused. Superseded geometry and metadata requests cannot publish into a newer route. Starting playback does not wait for optional road details.

## Departure, visits, and traffic lights

**Route Timing** is available in a route draft or edit and closes with **Done**.

- **Leave Later** and the **Departure** date/time picker schedule an already-started route. Tap **Start** to accept and hold its starting point until the countdown completes. **Leave Now** skips that wait. This is an active simulation countdown; it does not launch a terminated app. New departures cannot be scheduled from Edit Route.
- **Stay Duration**, in an intermediate stop's menu, provides **No delay**, wheel presets, and a one-minute stepper from 0 to 1,440 minutes. **Save** applies the visit; **Cancel** preserves it. Reordering carries each stop's duration. The final destination holds until End or Restore and has no visit-duration control.
- **Mapped Road Details** is an opt-in and is off by default. It initially sends route corridor coordinates to `overpass-api.de` and may send the same query to the approved fixed fallback, `overpass.private.coffee`, to query OpenStreetMap road limits and mapped traffic signals. A working mirror can be reused for later requests, with the primary available if the mirror fails. The single opt-in names and covers both services; there is no separate mirror switch. See the [Private.coffee service and privacy policy](https://overpass.private.coffee/).
- **Traffic Lights** enables mapped signal timing. **Red-light probability** ranges from 0–100% in 1% steps, defaulting to 50%. Stable per-route sampling assigns each matched light green or a simulated red wait of 5–90 seconds. These are simulated colors, not live signal phases. **Skip Light** skips a current red wait.
- The metadata status shows loading, mapped-limit coverage, mapped-light count, partial coverage, or unavailable data. **Retry** retries the relevant draft/active route. Loading or failure leaves Go available. Successful earlier chunks remain usable if a later chunk fails. Uncached chunks use at most three sequential HTTP calls across both approved services; cancellation stops retries and fallback work.

Pause freezes departure, visit, and light countdowns; Resume continues their remaining time. **Leave Now** also skips an intermediate visit. Timers use elapsed simulation time rather than replaying imported timestamps.

## Speed, units, and ETA

The expanded speed panel offers **Road Limits** (default) or **Constant**.

- Road Limits uses available mapped limits and road-type estimates for matched roads. Unsupported/missing restrictions, unmatched sections, and unavailable/unloaded metadata use estimates or the selected fallback speed. Estimates are identified by the coverage/status text; there is no guarantee that every physical road restriction is mapped.
- Constant uses the selected slider speed throughout geometry. Mapped simulated lights and stop durations can still add waits.
- The slider controls constant or fallback speed: normally 1–85 mph or 1–135 km/h, in one-unit steps. Default speed is 30 mph. Conversion may extend a slider endpoint to preserve the exact physical speed.
- **Settings → Measurement System** selects **US Imperial** (miles/feet/mph, default) or **Metric** (kilometers/meters/km/h) for the entire interface. Switching units preserves speed and distance.
- Active speed shows the effective road speed in Road Limits mode. Mode/slider changes affect movement and ETA without recalculating route geometry.
- ETA integrates the speed profile plus intermediate visits and sampled red-light delays; preview arrival also includes the scheduled departure. It updates as metadata arrives. This is a simulation projection rather than a traffic-based travel forecast.

## Active route, editing, and recovery

The top banner shows **Simulating**, **Paused**, **Leaving later**, **Staying at stop**, **Red light**, or **Arrived**, with the next stop or remaining wait. The trip card shows arrival, remaining minutes/distance, Pause/Resume, speed, and route controls. Paused arrival displays a dash.

- **Pause** records intent immediately and holds accepted progress after any device call already in flight finishes. **Resume** continues without counting paused time as movement. End/Restore/edit preparation temporarily prevents conflicting actions.
- A wait row shows remaining time plus **Leave Now** or **Skip Light**. Paused waits can be skipped while the route remains paused.
- **Edit Route** pauses and waits for the accepted coordinate, then exposes remaining stops, visits, and timing options. Active waits are retained through Apply & Resume. Failed edits preserve the previous route/progress and draft.
- **End Route** invalidates pending edit work, removes the route/draft, and holds the last accepted coordinate.
- **Restore Real Location** invalidates pending edit work and clears simulation only after success. A failed restoration retains the route/draft and exposes the error.
- **Arrived** holds the endpoint; End and Restore remain available.
- Connection failures freeze accepted progress. **Simulation Unavailable** presents **OK** and **Settings**, with inline recovery guidance retained. A synchronous device call is allowed to finish honestly before the next command runs.

## Omega Settings

- New Ω/navigation artwork, **Built on StikDebug**, **Omega Source**, and version/iOS footer.
- **Measurement System** as described above.
- **Import Pairing File**, import progress/outcome, and tunnel startup after successful import.
- **Silent Audio** and **Background Location** preferences. At least one option stays enabled; denied location access falls back to silent audio. The background managers recover stopped audio/session state where possible.
- **Target Device IP** and **Remote Pairing Port** overrides, with discovered/fallback port feedback. Changes restart the tunnel.
- **App Folder**, confirmed **Redownload DDI**, and download progress/outcome.
- **OpenStreetMap attribution**, **Road Data Backup & Privacy** (official Private.coffee service/terms/privacy page), **Pairing File Guide**, **Download LocalDevVPN**, **Discord Support**, and **Done**.

## Appearance, limits, and validation

Native Liquid Glass is used on iOS 26+ with native material/bordered fallbacks earlier. Light/dark, semantic text/colors, accessibility labels, scrolling layouts, and opaque Reduce Transparency surfaces are implemented. The peeled Maps/Omega blueprint icon uses Apple's system mask and default/dark/tinted rendering.

Not implemented: joystick, looping routes, saved route libraries, cloud place sync, coordinate export, offline road lookup/routing, timestamp replay, custom acceleration curves, walking/cycling/transit selection, alternative routes, spoken navigation, or Apple Maps account sync.

### Recorded 3.2.0 build 2 validation

The 3.2.0 build passed **76 isolated checks** (71 XCTest and 5 Swift Testing), including 17 road metadata checks. A development build passed nine foreground device checks and a 605-second background run on iPhone 15 Pro Max, iOS 27.0, followed by successful restoration. Foreground light/speed metadata checks used controlled fixture data. Simulator interaction covered autocomplete, Home pin creation/rename/removal, three stops, a one-minute visit, Leave Later, 0/100% probability, Start during metadata loading, Leave Now, speed-mode selection, and Apply & Resume with a retained visit.

Physical manual checks confirmed Metric 48 km/h and 1.3 km converting to Imperial 30 mph and 0.8 mi; Go while road metadata was loading with fallback speed; progress from 0.8 to 0.5 mi; Pause and Resume returning to Simulating; Road Limits selection; and 1/85 mph slider endpoints changing ETA. Omega reached **Arrived, 0 min, 0 ft** and Restore cleared simulation.

Apple Maps independently confirmed stationary spoofing, successive movement along one short public test route while Omega was backgrounded, and return to the real region after Restore. A continuous GPS recording was not collected. The 3.2.0 live Overpass probes did not establish data availability. New mirror availability, locked-screen/interruption/disconnection endurance, the second physical phone, and iOS 27.0.1 still need separate verification.

The final **3.2.0 build 2 signed Release** was built, packaged, installed, and launched. Inventory verified **Omega LocSim, `com.omega.locsim`, 3.2.0 (2)**. The freshly installed app resolved Apple Park autocomplete; Set Location showed the simulated marker/Holding location; Restore removed them without error. Existing pairing remained usable after the update, and simulation was cleared after the smoke check.

### 3.2.1 build 3 verification

**83 isolated checks passed** (78 XCTest plus 5 Swift Testing), including **24 road metadata tests**. The signed Release build succeeded. Physical installation and launch succeeded; inventory verified **Omega LocSim, `com.omega.locsim`, 3.2.1 (3)**. The signed/unsigned IPA packages were verified.

The installed app's autocomplete found Apple Infinite Loop Campus and Apple Park Visitor Center and prepared a **3.4 mi driving route**. Go was immediately available at **fallback 30 mph** while metadata loaded. Route Timing visibly named both providers, with Mapped Road Details and Traffic Lights enabled and probability at 50%. Go started simulation with a marker and remaining distance falling to **3.3 mi**; Pause displayed Paused.

After the bounded loading attempt, the app displayed **“Road details unavailable. Using fallback speed; traffic lights are not included.”** and Retry. Restore returned to idle Search Omega/Home/School/Work/Library, removing the route, simulated marker, and active banner without error. Simulation was left cleared.

Live road data was **not** successfully received. The approved Mac mirror probe also timed out after 28.0016 seconds with zero bytes (HTTP 000). Fixture transport checks remain separate from a live provider response. The earlier external GPS and ten-minute background observations belong to the 3.2.0 baseline; they were not repeated for 3.2.1.
