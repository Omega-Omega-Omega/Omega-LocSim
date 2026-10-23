# Omega LocSim — features and controls

Reviewed October 23, 2026. Omega LocSim 3.1.15 (build 1), `com.omega.locsim`, is installed with Xcode Personal Team signing on iPhone 15 Pro Max, iOS 27.0. All 22 prior isolated engine checks pass. The physical smoke observations and remaining acceptance are listed below.

## Map and place selection

- **Map:** native MapKit standard map with realistic elevation, pan/zoom, compass, scale, user-location annotation, route lines, stop markers, and a simulated-position arrow.
- **Search Maps:** place search with named/addressed results. Select a result to open its place card; Clear search removes the query. Outdated results are discarded.
- **Map tap:** selects a Dropped Pin while browsing, or supplies a place during an explicit stop search.
- **Recenter:** follows the accepted simulated position; otherwise requests the native user-location camera. Panning disables following.
- **Settings/person button:** opens setup. During a route, the upper control becomes **Show entire route**; Settings remains in the route menu.
- **Resizable sheet:** compact, preview, intermediate, and expanded positions. Normal active/preview heights are 170/420 points, with taller accessibility variants.
- **Place card:** selected-place title, selectable coordinates, **Directions**, **Set Location**, **Save place**, **Close**, and an options menu containing Settings, Saved Places & Import when available, and Restore Real Location.

**Set Location** performs stationary spoofing; its accessibility label is Set Spoofed Location. Accepted stationary coordinates are periodically refreshed and identified as Holding location. Restore remains a separate action.

## Preparing a route

| Control | Behavior |
|---|---|
| Directions | Opens a driving draft from the accepted simulated location, or asks for an explicit start. |
| Starting location / stop row | Searches for a replacement without removing the existing place. Cancel preserves the original selection/order. |
| Add Stop | Opens an explicit search; appends the selected stop. |
| Stop options | Replace Stop, Move Up, Move Down, and Remove Stop where applicable. |
| Drag | Reorders non-start stops; menu commands provide an alternative. |
| Driving / speed row | Shows driving mode and opens speed controls. |
| Automatic preview | Recalculates ordered MapKit road legs after valid stop changes, with a blue route and markers. |
| Finding route / Try Again | Loading feedback and recovery after failed calculation. |
| Preview summary | Estimated minutes, projected arrival, distance, and selected speed. |
| Go | Applies the preview and starts movement after the initial location is accepted. |
| Close | Cancels the active stop search first; otherwise discards the route draft. |

Playback uses one constant speed, without a road-speed lookup. Completed legs can be reused; obsolete calculations cannot publish stale results. ETA uses distance and simulation speed, not traffic. It is a projection, not a recorded arrival time.

## Active route and editing

The banner shows **Simulating**, **Paused**, or **Arrived** and the next stop. The trip card shows arrival projection, remaining minutes/distance, Pause/Resume, speed, and route controls. Paused arrival displays a dash.

| Control/state | Behavior |
|---|---|
| Pause | Records pause immediately, lets an already-started device call finish honestly, then holds the accepted position. |
| Resume | Continues accepted progress, excluding paused time. Unavailable after arrival or while edit/end/restore preparation prevents it. |
| Speed button / slider | Expands controls and changes movement speed without recalculating geometry. |
| mph / km/h | Changes displayed units while preserving actual speed. |
| Route menu | Edit Route, End Route, Restore Real Location, and Settings. |
| Edit Route | Pauses, waits for the accepted coordinate, and edits remaining stops from that fixed start. Shows progress while waiting. |
| Apply & Resume | Applies the replacement after acceptance. Failure preserves the old route/progress, draft, and error. |
| Close edit | Discards the draft; preserves the original route paused. |
| End Route | Invalidates pending editing, closes its draft, stops playback, and holds position. |
| Restore Real Location | Invalidates pending editing and requests clearing simulation. Success clears route/position; failure preserves simulation/draft with an error. |
| Arrived | Holds the endpoint; End and Restore remain available. |
| Connection failure | Freezes accepted progress and opens Simulation Unavailable with OK/Settings; inline recovery guidance remains. |

The pitched camera follows accepted position/heading; overview and recenter remain available. Device calls are serialized; canceling playback does not pretend to abort a synchronous call already in progress.

Default speed is approximately **30 mph**. Slider ranges are **1–85 mph** or **1–135 km/h**, in 1-unit steps; the endpoint expands when necessary to preserve a converted speed without changing it.

## Saved places and files

**Saved Places & Import** lists persistent local bookmarks and **Import Coordinates**. GPX, KML/XML, GeoJSON, JSON, CSV, and plain-text coordinate files are supported. One coordinate opens a place; multiple coordinates form a playable geometry preview. Imports use constant speed rather than timestamps. Editing stops recalculates MapKit road geometry. Bookmark rename/delete, folders, cloud sync, and export controls are absent.

## Settings

- Omega LocSim artwork/name, Built on StikDebug attribution, and **StikDebug Source** link.
- **Import Pairing File**, with success/failure feedback and existing tunnel setup.
- **Silent Audio** and **Background Location** support preferences; current handlers retain at least one enabled option.
- **Target Device IP** and **Remote Pairing Port** override/discovery fields; changes restart the tunnel.
- **App Folder** and confirmed **Redownload DDI**, including progress/outcome feedback.
- **Pairing File Guide**, **Download LocalDevVPN**, **Discord Support**, version/device footer, and **Done**.

Pairing, disk-image preparation, foreground reconnect attempts, and background managers remain; indefinite operation is unverified.

## Appearance and scope

iOS 26+ uses native Liquid Glass; earlier systems use material/bordered fallbacks. System text/colors, light/dark appearance, accessibility labels, flexible scrolling layouts, and opaque Reduce Transparency sheet/header surfaces are implemented.

Absent: joystick, schedules, dwell timers, loops, variable movement profiles, timestamp replay, route libraries, offline routing, live route swapping, custom backend, walking/cycling/transit, alternative-route selection, traffic ETAs, spoken/turn-by-turn navigation, lane guidance, Look Around, business reviews/photos, satellite selector, and Apple Maps account sync. Unrelated upstream debugger tools are hidden from the main interface.

## Acceptance

After refreshed pairing resolved initial provider error 3, **Set Location** reported success. **Go** entered Simulating and remaining distance decreased **2.6 → 2.1 km**. **Pause**, **Edit Route**, and **Apply & Resume** with the remaining stop unchanged were exercised; progress continued **2.1 → 1.6 km**. **End Route** removed the route and held position. **Restore Real Location** removed the simulated marker, Holding location label, and Restore control without error.

These are app-reported outcomes and visible state/progress changes. Independent other-app GPS, live speed changes, actual multi-stop edits, arrival, direct Resume-button coverage, failure recovery on hardware, lock/background/disconnection endurance, the second physical phone, and iOS 27.0.1 remain untested. Compare accessibility/light-dark layouts and Maps fidelity on the targets. Source repository: [GitHub fork](https://github.com/Omega-Omega-Omega/Omega-LocSim). This repository contains the implementation; no GitHub Release is published.
