#if DEBUG
import Foundation
import CoreLocation
import Combine

/// Explicit, debug-build-only hardware checks. Nothing runs during normal app
/// launches. All locations are public Cupertino fixtures, never recorded GPS.
@MainActor
enum OmegaDeviceAcceptanceRunner {
    private static var didRun = false

    static func runIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        let background = arguments.contains("--omega-background-acceptance")
        let roadOnly = arguments.contains("--omega-road-acceptance")
        guard !didRun, background || roadOnly || arguments.contains("--omega-device-acceptance") else { return }
        didRun = true
        await Run(background: background, roadOnly: roadOnly).execute()
    }

    @MainActor
    private final class Run {
        struct Check: Codable {
            var name: String
            var status: String
            var seconds: Double = 0
            var detail: String? = nil
        }
        struct Report: Codable {
            var schema = 1
            var mode: String
            var startedAt = Date()
            var finishedAt: Date?
            var status = "running"
            var checks: [Check] = []
            var elapsedSeconds = 0.0
            var acceptedLocationUpdates = 0
            var acceptedMovementUpdates = 0
            var traveledMeters = 0.0
            var maximumTraveledMeters = 0.0
            var backgroundDistanceMeters: Double?
            var maximumProgressGapSeconds = 0.0
            var restored = false
            var limitation = "Checks device-command acceptance and app state; does not independently verify other apps' GPS."
        }
        enum Failure: Error { case assertion(String), timedOut(String) }

        let background: Bool
        let roadOnly: Bool
        let session = LocationSimulationSession.shared
        var report: Report
        var observer: AnyCancellable?
        var movementObserver: AnyCancellable?
        var progressTask: Task<Void, Never>?
        var lastProgressDate = Date()
        var lastDistance = 0.0
        let destination: URL

        init(background: Bool, roadOnly: Bool = false) {
            self.background = background
            self.roadOnly = roadOnly
            report = Report(mode: roadOnly ? "late-road-metadata" : background ? "background-ten-minutes" : "foreground")
            destination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("omega-device-acceptance.json")
        }

        func execute() async {
            let previousSpeed = session.speedMetersPerSecond
            let previousRoadMode = session.useRoadSpeeds
            session.useRoadSpeeds = false
            session.speedMetersPerSecond = 10
            observer = session.$coordinate.dropFirst().sink { [weak self] coordinate in
                guard coordinate != nil else { return }
                self?.report.acceptedLocationUpdates += 1
            }
            movementObserver = session.$traveled.sink { [weak self] distance in
                guard let self else { return }
                if distance > lastDistance { report.acceptedMovementUpdates += 1 }
                lastDistance = distance
            }
            writeReport()
            progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    guard let self else { return }
                    let now = Date()
                    report.maximumProgressGapSeconds = max(report.maximumProgressGapSeconds, now.timeIntervalSince(lastProgressDate))
                    lastProgressDate = now
                    writeReport()
                }
            }
            do {
                if roadOnly { try await roadMetadataChecks() }
                else if background { try await backgroundChecks() }
                else { try await foregroundChecks() }
                report.status = "passed"
            } catch {
                report.status = "failed"
            }
            // A timeout only stops the check. Restoration remains serialized
            // behind any actual FFI already in progress; never queue a retry.
            report.checks.append(Check(name: "Restore Real Location", status: "running"))
            writeReport()
            let restoreStarted = Date()
            await session.restoreRealLocation()
            report.restored = !session.isActive && session.coordinate == nil && session.plannedRoute == nil
            report.checks[report.checks.count - 1] = Check(name: "Restore Real Location", status: report.restored ? "passed" : "failed", seconds: Date().timeIntervalSince(restoreStarted))
            if !report.restored { report.status = "failed" }
            session.speedMetersPerSecond = previousSpeed
            session.useRoadSpeeds = previousRoadMode
            progressTask?.cancel()
            observer?.cancel(); movementObserver?.cancel()
            report.finishedAt = Date()
            writeReport()
        }

        func check(_ name: String, _ operation: () async throws -> Void) async throws {
            let index = report.checks.count
            report.checks.append(Check(name: name, status: "running"))
            writeReport()
            let started = Date()
            do {
                try await operation()
                report.checks[index] = Check(name: name, status: "passed", seconds: Date().timeIntervalSince(started))
                writeReport()
            } catch {
                let detail: String
                switch error {
                case Failure.assertion(let message), Failure.timedOut(let message): detail = message
                default: detail = "Check interrupted."
                }
                report.checks[index] = Check(name: name, status: "failed", seconds: Date().timeIntervalSince(started), detail: detail)
                writeReport()
                throw error
            }
        }

        func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure.assertion(message) }
        }

        func wait(_ name: String, timeout: Double = 45, until predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(timeout)
            while !predicate(), Date() < deadline {
                try Task.checkCancellation()
                if session.playbackError != nil { throw Failure.assertion("Device transport reported an error.") }
                try await Task.sleep(for: .milliseconds(50))
            }
            try require(predicate(), "Timed out: \(name).")
        }

        func apply(_ route: PlannedRoute) async throws {
            let accepted = await session.play(route)
            try require(accepted, "Device rejected the route starting point.")
        }

        func foregroundChecks() async throws {
            try await check("Stationary position") {
                let point = fixture().coordinates[0]
                let accepted = await session.setStationary(point)
                try require(accepted && session.isActive && session.coordinate != nil, "Device rejected stationary position.")
            }
            try await check("Leave later, Pause and Leave Now") {
                var route = fixture()
                route.departureDate = Date().addingTimeInterval(30)
                try await apply(route)
                try await wait("scheduled departure") { session.currentWait?.kind == .departure }
                _ = await session.pauseAndWait()
                let remaining = session.currentWait!.remainingSeconds
                try await Task.sleep(for: .seconds(1))
                try require(session.currentWait?.remainingSeconds == remaining && session.traveled == 0, "Paused schedule changed.")
                session.resumePlayback()
                try await wait("schedule resume") { session.playbackState == .playing }
                session.skipCurrentWait()
                try await wait("leave now arrival") { session.playbackState == .arrived }
            }
            try await check("Intermediate visit expires naturally") {
                try await apply(fixture(dwell: 1))
                try await wait("visit begins") { session.currentWait?.kind == .stop(title: "Public Test Stop") }
                let start = Date()
                try await wait("visit completes") { session.playbackState == .arrived }
                try require(Date().timeIntervalSince(start) >= 0.9, "Visit completed before its configured delay.")
            }
            try await check("Skip intermediate visit") {
                try await apply(fixture(dwell: 60))
                try await wait("visit begins") { session.currentWait?.kind == .stop(title: "Public Test Stop") }
                session.skipCurrentWait()
                try await wait("skip visit arrival") { session.playbackState == .arrived }
            }
            try await check("Red light expires naturally") {
                var route = fixture()
                route.trafficLights = [.init(distance: route.stopDistances[0], delaySeconds: 5)]
                try await apply(route)
                try await wait("red light begins") { session.currentWait?.kind == .trafficLight }
                let start = Date()
                try await wait("red light completes") { session.playbackState == .arrived }
                try require(Date().timeIntervalSince(start) >= 4.8, "Red light completed before five seconds.")
            }
            try await check("Skip red light") {
                var route = fixture()
                route.trafficLights = [.init(distance: route.stopDistances[0], delaySeconds: 90)]
                try await apply(route)
                try await wait("red light begins") { session.currentWait?.kind == .trafficLight }
                session.skipCurrentWait()
                try await wait("skip red arrival") { session.playbackState == .arrived }
            }
            try await check("Playback Pause, Resume and live road metadata") {
                var route = fixture(lengthScale: 100)
                try await apply(route)
                try await wait("route progress") { session.traveled > 0 }
                _ = await session.pauseAndWait()
                let held = session.traveled
                try await Task.sleep(for: .seconds(1))
                try require(session.traveled == held, "Paused route advanced.")
                route.speedSegments = [.init(startDistance: 0, endDistance: route.distance, metersPerSecond: 5)]
                try require(session.applyRoadMetadata(route), "Current route metadata was rejected.")
                session.useRoadSpeeds = true
                try require(session.traveled == held && session.effectiveSpeedMetersPerSecond == 5, "Metadata reset progress or did not set road speed.")
                session.resumePlayback()
                try await wait("resume movement") { session.traveled > held }
            }
            try await check("Arrive By retargets lights and speed") {
                session.useRoadSpeeds = false
                session.speedMetersPerSecond = 10
                var route = fixture(lengthScale: 50)
                route.trafficLights = [.init(distance: route.distance * 0.7, delaySeconds: 90)]
                route.arrivalDate = Date().addingTimeInterval(40)
                try await apply(route)
                try await wait("arrival-target progress") { session.traveled > 0 }
                try require(session.arrivalAdjustment?.skippedTrafficLightCount == 1,
                            "Arrival target did not remove the red-light delay.")
                let deadline = Date().addingTimeInterval(8)
                session.updateArrivalDate(deadline)
                try require(session.arrivalAdjustment?.isFeasible == true && session.effectiveSpeedMetersPerSecond > 10,
                            "Earlier arrival target did not increase simulation speed.")
                try await wait("arrival target completes", timeout: 15) { session.playbackState == .arrived }
                try require(Date().timeIntervalSince(deadline) <= 2,
                            "Arrival exceeded the hardware-check transport tolerance.")
            }
            try await check("Impossible arrival retains stop stays and reports a warning") {
                var route = fixture(dwell: 60, lengthScale: 2)
                route.arrivalDate = Date().addingTimeInterval(5)
                try await apply(route)
                try require(session.arrivalAdjustment?.isFeasible == false && session.arrivalAdjustment?.warning != nil,
                            "Impossible arrival did not report a timing warning.")
                try await wait("required stay begins") { session.currentWait?.kind == .stop(title: "Public Test Stop") }
                try require((session.currentWait?.remainingSeconds ?? 0) > 50,
                            "Arrival target silently removed the requested stay.")
                await session.endPlayback()
            }
            try await check("Live route edits preserve progress and user pause") {
                try await apply(fixture(lengthScale: 100))
                try await wait("edit route progress") { session.traveled > 2 }
                let original = session.plannedRoute!
                let acceptedLatitude = session.coordinate!.latitude
                let updated = await session.applyEditedRoute(original, replacingRouteID: original.id)
                try require(updated, "Editing a running route was rejected.")
                try await wait("edited route resumes", timeout: 5) { session.playbackState == .playing }
                try require(session.coordinate!.latitude >= acceptedLatitude,
                            "Applying route edits moved back to an earlier position.")
                _ = await session.pauseAndWait()
                let paused = session.plannedRoute!
                let heldLatitude = session.coordinate!.latitude
                let pausedUpdate = await session.applyEditedRoute(paused, replacingRouteID: paused.id)
                try require(pausedUpdate && session.playbackState == .paused,
                            "Applying route edits resumed a user-paused route.")
                try await Task.sleep(for: .seconds(1))
                try require(session.coordinate!.latitude == heldLatitude,
                            "Paused route moved during or after its edit.")
            }
            try await check("End Route holds the last accepted position") {
                await session.endPlayback()
                let held = session.coordinate
                try require(session.plannedRoute == nil && session.isActive && held != nil, "End did not leave a held position.")
                let count = report.acceptedLocationUpdates
                try await wait("holding refresh", timeout: 30) { report.acceptedLocationUpdates > count }
                try require(session.coordinate?.latitude == held?.latitude && session.coordinate?.longitude == held?.longitude, "Held position changed.")
            }
        }

        /// Controlled late responses exercise the real device bridge. Provider
        /// availability is tested separately, so a fixture cannot pass as live OSM.
        func roadMetadataChecks() async throws {
            session.useRoadSpeeds = true
            session.speedMetersPerSecond = 10
            try await check("Late mapped speed and light after fallback start") {
                var route = fixture(lengthScale: 100)
                try await apply(route)
                try await wait("fallback movement") { session.traveled > 5 }
                let held = session.traveled
                route.speedSegments = [.init(startDistance: 0, endDistance: route.distance, metersPerSecond: 35 * 0.44704)]
                route.trafficLights = [.init(distance: 100, delaySeconds: 5)]
                try require(session.applyRoadMetadata(route), "Late mapped road details were rejected.")
                try await wait("late speed commits") { abs(session.effectiveSpeedMetersPerSecond - 35 * 0.44704) < 0.01 }
                try require(session.playbackState == .playing && session.traveled >= held,
                            "Late metadata paused or restarted playback.")
                try await wait("late red light begins", timeout: 15) { session.currentWait?.kind == .trafficLight }
                let redStarted = Date()
                try await wait("late red light completes", timeout: 10) { session.currentWait == nil && session.traveled > 100 }
                try require(Date().timeIntervalSince(redStarted) >= 4.5, "Late light did not retain its five-second wait.")
                await session.endPlayback()
            }
            try await check("Late slower limits preserve the latest Arrive By") {
                var route = fixture(lengthScale: 50)
                route.arrivalDate = Date().addingTimeInterval(30)
                try await apply(route)
                try await wait("deadline fallback movement") { session.traveled > 5 }
                let deadline = Date().addingTimeInterval(12)
                session.updateArrivalDate(deadline)
                route.speedSegments = [.init(startDistance: 0, endDistance: route.distance, metersPerSecond: 5)]
                route.trafficLights = [.init(distance: route.distance * 0.6, delaySeconds: 90),
                                       .init(distance: route.distance * 0.8, delaySeconds: 90)]
                try require(session.applyRoadMetadata(route), "Deadline route rejected late road details.")
                try await wait("deadline late metadata commits") { session.plannedRoute?.trafficLights.count == 2 }
                try require(session.plannedRoute?.arrivalDate == deadline && session.playbackState == .playing,
                            "Late metadata replaced the latest deadline or paused playback.")
                try require(session.arrivalAdjustment?.skippedTrafficLightCount == 2 && session.effectiveSpeedMetersPerSecond > 5,
                            "Arrive By did not turn the necessary lights green and adjust pace.")
                try await wait("deadline arrival", timeout: 18) { session.playbackState == .arrived }
                try require(Date().timeIntervalSince(deadline) <= 2, "Late limits missed the deadline transport tolerance.")
            }
        }

        func backgroundChecks() async throws {
            try await check("Ten-minute background route playback") {
                session.speedMetersPerSecond = 1
                try await apply(fixture(lengthScale: 2_000))
                try await wait("initial background route progress") { session.traveled > 0 }
                let start = Date()
                let startDistance = session.traveled
                let startUpdates = report.acceptedMovementUpdates
                writeReport() // The operator can now send the app to the background.
                while Date().timeIntervalSince(start) < 600 {
                    try Task.checkCancellation()
                    if session.playbackError != nil { throw Failure.assertion("Background device transport reported an error.") }
                    try await Task.sleep(for: .seconds(5))
                }
                _ = await session.pauseAndWait()
                report.backgroundDistanceMeters = session.traveled - startDistance
                try require(session.traveled - startDistance >= 480, "Background distance was below 80 percent of the selected speed.")
                try require(report.acceptedMovementUpdates - startUpdates >= 60, "Too few accepted background updates.")
                try require(report.maximumProgressGapSeconds <= 20, "Background execution had a scheduling gap longer than twenty seconds.")
            }
        }

        func fixture(dwell: Double = 0, lengthScale: Double = 1) -> PlannedRoute {
            let stops = [
                SimulationStop(title: "Public Test Start", coordinate: .init(latitude: 37.3317, longitude: -122.0301)),
                SimulationStop(title: "Public Test Stop", coordinate: .init(latitude: 37.3317 + 0.00001 * lengthScale, longitude: -122.0301), dwellSeconds: dwell),
                SimulationStop(title: "Public Test Finish", coordinate: .init(latitude: 37.3317 + 0.00005 * lengthScale, longitude: -122.0301))
            ]
            let geometry = RouteGeometry(stops.map(\.coordinate))
            return PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(geometry.distances.dropFirst()), stops: stops)
        }

        func writeReport() {
            report.elapsedSeconds = Date().timeIntervalSince(report.startedAt)
            report.traveledMeters = session.traveled
            report.maximumTraveledMeters = max(report.maximumTraveledMeters, session.traveled)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) { try? data.write(to: destination, options: .atomic) }
        }
    }
}
#endif
