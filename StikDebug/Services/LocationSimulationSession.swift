import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationSimulationSession: ObservableObject {
    static let shared = LocationSimulationSession()

    enum PlaybackState { case idle, playing, paused, arrived }
    @Published private(set) var isActive = false
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var routeCoordinates: [CLLocationCoordinate2D]?
    @Published private(set) var playbackState = PlaybackState.idle
    @Published private(set) var playbackError: String?
    @Published private(set) var traveled = 0.0
    @Published var speedMetersPerSecond = 13.4112 {
        didSet { refreshArrivalAdjustment() }
    }
    @Published var useRoadSpeeds = true {
        didSet {
            if managesBackground { UserDefaults.standard.set(useRoadSpeeds, forKey: "omegaUseRoadSpeeds") }
            refreshArrivalAdjustment()
        }
    }
    @Published private(set) var plannedRoute: PlannedRoute?
    @Published private(set) var isSendingLocation = false
    @Published private(set) var currentWait: SimulationWait?
    @Published private(set) var arrivalAdjustment: ArrivalAdjustment?

    private var adjustedSpeedMultiplier = 1.0
    private var greenLightIDs = Set<UUID>()
    private var currentWaitLightID: UUID?
    private var lastTransportSeconds = 0.0
    private let replanEditedRoute: @MainActor ([SimulationStop]) async throws -> PlannedRoute

    private var timingEvents: [RouteTimingEvent] = []
    private var nextTimingEvent = 0
    private var pendingMovementDistance: Double?
    private var pendingRoadMetadata: PlannedRoute?
    private var roadSpeedProfile = RouteSpeedProfile(segments: [], length: 0)
    private var waitClock: TimeInterval?
    private let monotonicNow: @MainActor () -> TimeInterval
    private let wallNow: @MainActor () -> Date

    private var playbackTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var holdTask: Task<Void, Never>?
    private var geometry = RouteGeometry([])
    private var routeID: UUID?
    private var actionID = UUID()
    private var pauseRevision = 0
    private var settlingPauseCount = 0
    private var transportWaiters: [CheckedContinuation<Void, Never>] = []
    private var resendTimer: Timer?
    private let sender: (@MainActor (CLLocationCoordinate2D?) async -> Int32)?
    private let managesBackground: Bool
    private let tickInterval: Double
    private let holdInterval: Double

    private init() {
        sender = nil; managesBackground = true
        tickInterval = 0.5; holdInterval = 4
        monotonicNow = { ProcessInfo.processInfo.systemUptime }
        wallNow = { Date() }
        replanEditedRoute = { try await RoutePlanner().calculate(stops: $0) }
        useRoadSpeeds = UserDefaults.standard.object(forKey: "omegaUseRoadSpeeds") as? Bool ?? true
    }

    // The same holding and playback paths run with an injected test transport.
    init(tickInterval: Double = 0.5, holdInterval: Double = 4,
         monotonicNow: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallNow: @escaping @MainActor () -> Date = { Date() },
         replanEditedRoute: @escaping @MainActor ([SimulationStop]) async throws -> PlannedRoute = {
             try await RoutePlanner().calculate(stops: $0)
         },
         sender: @escaping @MainActor (CLLocationCoordinate2D?) async -> Int32) {
        self.sender = sender; managesBackground = false
        self.tickInterval = tickInterval; self.holdInterval = holdInterval
        self.monotonicNow = monotonicNow; self.wallNow = wallNow
        self.replanEditedRoute = replanEditedRoute
    }

    private struct Transmission {
        let code: Int32
        let seconds: Double
    }

    private func acquireTransport() async {
        if isSendingLocation {
            await withCheckedContinuation { transportWaiters.append($0) }
        } else { isSendingLocation = true }
    }

    private func releaseTransport() {
        if transportWaiters.isEmpty { isSendingLocation = false }
        else { transportWaiters.removeFirst().resume() }
    }

    private func waitForTransport() async {
        await acquireTransport()
        releaseTransport()
    }

    /// A canceled waiter does not send. An FFI call already started must finish;
    /// its successful coordinate is always recorded before the next command runs.
    private func transmit(_ point: CLLocationCoordinate2D?, valid: () -> Bool = { true }) async -> Transmission? {
        await acquireTransport()
        defer { releaseTransport() }
        guard !Task.isCancelled, valid() else { return nil }
        let result: Transmission
        if let sender {
            let started = monotonicNow()
            let code = await sender(point)
            result = Transmission(code: code, seconds: max(0, monotonicNow() - started))
        } else {
            let ip = DeviceConnectionContext.targetIPAddress
            let path = PairingFileStore.prepareURL().path
            result = await withCheckedContinuation { continuation in
                LocationSimulationCommandQueue.shared.async {
                    // Measure inside the bridge queue, excluding app scheduling delay.
                    let started = ProcessInfo.processInfo.systemUptime
                    let code = point.map { simulate_location(ip, $0.latitude, $0.longitude, path) }
                        ?? clear_simulated_location()
                    continuation.resume(returning: Transmission(code: code,
                        seconds: ProcessInfo.processInfo.systemUptime - started))
                }
            }
        }
        if result.code == 0 {
            if let point { start(at: point) }
            else { finishRestoration() }
        }
        return result
    }

    private func beginAction() -> UUID {
        actionID = UUID()
        pausePlayback()
        stopHolding()
        pauseResending()
        return actionID
    }

    @discardableResult
    func setStationary(_ point: CLLocationCoordinate2D) async -> Bool {
        let id = beginAction()
        guard let result = await transmit(point, valid: { self.actionID == id }), actionID == id else { return false }
        guard result.code == 0 else {
            playbackError = "Could not set location (error \(result.code)). Check pairing, VPN, and developer disk image."
            holdPosition(); return false
        }
        clearPlaybackRoute()
        playbackError = nil
        holdPosition()
        return true
    }

    /// Returns true only when this route was accepted. A failed replacement
    /// leaves the original route/progress paused and lets the UI retain its draft.
    @discardableResult
    func play(_ route: PlannedRoute, preservingCurrentWait: Bool = false) async -> Bool {
        guard route.coordinates.count > 1, let first = route.coordinates.first else {
            playbackError = "Choose a route with a starting location and a destination."
            return false
        }
        let id = beginAction()
        let requestedPauseRevision = pauseRevision
        guard let result = await transmit(first, valid: { self.actionID == id }), actionID == id else { return false }
        guard result.code == 0 else {
            playbackError = "Could not apply route (error \(result.code)). Check the connection and try again." + (plannedRoute == nil ? "" : " Your previous route is paused.")
            holdPosition(); return false
        }
        let retainedWait = preservingCurrentWait ? currentWait : nil
        let retainedLightID = preservingCurrentWait ? currentWaitLightID : nil
        greenLightIDs = []; currentWaitLightID = nil; lastTransportSeconds = result.seconds
        plannedRoute = route
        geometry = RouteGeometry(route.coordinates)
        roadSpeedProfile = RouteSpeedProfile(segments: route.speedSegments, length: geometry.length)
        traveled = 0
        timingEvents = route.timingEvents
        nextTimingEvent = 0
        currentWait = nil; waitClock = nil
        _ = startRoute(at: first, coordinates: route.coordinates)
        playbackState = .paused
        let departureDelay = route.waitingUntilDeparture(at: wallNow())
        if let retainedWait { currentWaitLightID = retainedLightID; beginWait(retainedWait.kind, seconds: retainedWait.remainingSeconds) }
        else if departureDelay > 0 { beginWait(.departure, seconds: departureDelay) }
        refreshArrivalAdjustment()
        if pauseRevision == requestedPauseRevision { resumePlayback() }
        else { holdPosition() }
        return true
    }

    /// Editing does not interrupt playback. Only committing the draft drains
    /// the active transport, then swaps in a route from its last accepted point.
    /// A user-paused route remains paused; stale edits cannot replace a new trip.
    @discardableResult
    func applyEditedRoute(_ draft: PlannedRoute, replacingRouteID originalID: UUID) async -> Bool {
        guard plannedRoute?.id == originalID, draft.stops.count > 1 else {
            playbackError = "This route changed while you were editing. Open Edit Route again."
            return false
        }
        let wasPlaying = playbackState == .playing
        let oldLoop = playbackTask
        let id = beginAction()
        let requestedPauseRevision = pauseRevision
        settlingPauseCount += 1
        defer { settlingPauseCount -= 1 }
        await oldLoop?.value
        await waitForTransport()
        guard actionID == id, plannedRoute?.id == originalID, let point = coordinate else { return false }
        let completedIDs = Set(zip(plannedRoute!.stops.dropFirst(), plannedRoute!.stopDistances)
            .filter { $0.1 <= traveled + 0.000_001 }.map { $0.0.id })
        var replacement: PlannedRoute
        if let rebased = draft.rebased(at: point, omittingStopIDs: completedIDs) {
            replacement = rebased
        } else {
            let futureStops = draft.stops.dropFirst().filter { !completedIDs.contains($0.id) }
            guard !futureStops.isEmpty else {
                playbackError = "All remaining stops were completed while editing. Add a destination to continue."
                holdPosition()
                return false
            }
            do {
                replacement = try await replanEditedRoute([SimulationStop(title: "Simulated Location", coordinate: point)] + futureStops)
                replacement.departureDate = draft.departureDate
                replacement.arrivalDate = draft.arrivalDate
            } catch {
                guard actionID == id else { return false }
                // End the temporary commit lock before resuming the original trip.
                settlingPauseCount -= 1
                if wasPlaying && pauseRevision == requestedPauseRevision { resumePlayback(clearError: false) }
                settlingPauseCount += 1
                playbackError = "Could not update this route. Your previous route is unchanged. Try again."
                return false
            }
        }
        guard actionID == id, plannedRoute?.id == originalID else { return false }
        if Task.isCancelled {
            settlingPauseCount -= 1
            if wasPlaying && pauseRevision == requestedPauseRevision { resumePlayback(clearError: false) }
            settlingPauseCount += 1
            return false
        }
        // Skip/Leave Now remains authoritative even while a road replan awaits.
        let retainedWait = currentWait
        let retainedWaitLightID = currentWaitLightID
        plannedRoute = replacement
        geometry = RouteGeometry(replacement.coordinates)
        roadSpeedProfile = RouteSpeedProfile(segments: replacement.speedSegments, length: geometry.length)
        traveled = 0
        timingEvents = replacement.timingEvents
        nextTimingEvent = 0
        pendingRoadMetadata = nil
        currentWait = retainedWait; currentWaitLightID = retainedWaitLightID; waitClock = nil
        _ = startRoute(at: point, coordinates: replacement.coordinates)
        playbackState = .paused
        playbackError = nil
        refreshArrivalAdjustment()
        settlingPauseCount -= 1
        if wasPlaying && pauseRevision == requestedPauseRevision { resumePlayback() }
        else { holdPosition() }
        settlingPauseCount += 1
        return true
    }

    /// A deadline changes the simulation, not the user's pause or visit choices.
    func updateArrivalDate(_ date: Date?) {
        guard var route = plannedRoute else { return }
        guard date?.timeIntervalSinceReferenceDate.isFinite != false else { return }
        route.arrivalDate = date
        plannedRoute = route
        refreshArrivalAdjustment()
    }

    func pausePlayback() {
        settleWait()
        waitClock = nil
        pauseRevision += 1
        resumeTask?.cancel(); resumeTask = nil
        playbackTask?.cancel(); playbackTask = nil
        if playbackState == .playing { playbackState = .paused }
        refreshArrivalAdjustment()
        holdPosition()
    }

    /// Editing waits for the one in-flight update, so the edit anchor is honest.
    func pauseAndWait() async -> CLLocationCoordinate2D? {
        settlingPauseCount += 1
        defer { settlingPauseCount -= 1 }
        pausePlayback()
        await waitForTransport()
        return coordinate
    }

    func resumePlayback(clearError: Bool = true) {
        guard settlingPauseCount == 0, plannedRoute != nil, playbackState != .playing, playbackState != .arrived else { return }
        stopHolding()
        resumeTask?.cancel()
        let id = actionID
        resumeTask = Task { @MainActor in
            await waitForTransport()
            guard !Task.isCancelled, actionID == id, plannedRoute != nil else { return }
            if clearError { playbackError = nil }
            playbackState = .playing
            refreshArrivalAdjustment()
            if currentWait != nil { waitClock = monotonicNow(); holdPosition() }
            startPlaybackLoop()
        }
    }

    private func startPlaybackLoop() {
        let activeRouteID = routeID
        playbackTask = Task { @MainActor in
            var transportSeconds = 0.0
            while !Task.isCancelled, playbackState == .playing {
                let sleepStarted = monotonicNow()
                do { try await Task.sleep(for: .seconds(tickInterval)) } catch { return }
                guard !Task.isCancelled, routeID == activeRouteID else { return }
                let wasWaiting = currentWait != nil
                settleWait()
                refreshArrivalAdjustment()
                if wasWaiting {
                    // Waiting time never becomes movement, even after an interrupted
                    // timer or a slow hold transmission. Pause freezes this countdown.
                    transportSeconds = 0
                    continue
                }
                if beginReachedWait() {
                    transportSeconds = 0
                    continue
                }
                if traveled >= geometry.length {
                    playbackState = .arrived; holdPosition(); return
                }
                let scheduledSeconds = max(0, monotonicNow() - sleepStarted)
                // Only unexpected scheduling gaps are capped. A slow, active device
                // transmission contributes its full measured duration to the next step.
                let elapsed = transportSeconds + min(scheduledSeconds, tickInterval * 2)
                let speed = speedMetersPerSecond.isFinite ? max(plannedRoute?.arrivalDate == nil ? 0 : 0.1, speedMetersPerSecond) : 0.1
                let barrier = nextTimingEvent < timingEvents.count ? timingEvents[nextTimingEvent].distance : geometry.length
                let limit = min(geometry.length, barrier)
                let next = useRoadSpeeds
                    ? roadSpeedProfile.advance(from: traveled, seconds: elapsed, upTo: limit, fallbackSpeed: speed,
                        multiplier: adjustedSpeedMultiplier, maximumSpeed: arrivalMaximumSpeed)
                    : min(limit, traveled + min(arrivalMaximumSpeed, speed * adjustedSpeedMultiplier) * elapsed)
                guard let point = geometry.coordinate(at: next) else { return }
                pendingMovementDistance = next
                let transmission = await transmit(point)
                pendingMovementDistance = nil
                guard let result = transmission else {
                    if let metadata = pendingRoadMetadata {
                        pendingRoadMetadata = nil
                        _ = applyRoadMetadata(metadata)
                    }
                    return
                }
                lastTransportSeconds = result.seconds
                if result.code == 0, routeID == activeRouteID {
                    traveled = next
                    // Record a wait even if Pause happened during the uninterruptible
                    // transport: the accepted stop must not be silently skipped.
                    _ = beginReachedWait()
                    refreshArrivalAdjustment()
                }
                if let metadata = pendingRoadMetadata {
                    pendingRoadMetadata = nil
                    _ = applyRoadMetadata(metadata)
                }
                if result.code != 0, routeID == activeRouteID {
                    playbackState = .paused
                    playbackError = "Location update failed (error \(result.code)). Check the connection, then Resume."
                    holdPosition(); return
                }
                guard !Task.isCancelled, routeID == activeRouteID else { return }
                transportSeconds = currentWait == nil ? result.seconds : 0
                if next >= geometry.length, currentWait == nil {
                    playbackState = .arrived; holdPosition(); return
                }
            }
        }
    }

    private func beginWait(_ kind: SimulationWait.Kind, seconds: TimeInterval) {
        currentWait = SimulationWait(kind: kind, remainingSeconds: seconds)
        waitClock = playbackState == .playing ? monotonicNow() : nil
        holdPosition()
    }

    @discardableResult
    private func beginReachedWait() -> Bool {
        while nextTimingEvent < timingEvents.count, timingEvents[nextTimingEvent].seconds <= 0 { nextTimingEvent += 1 }
        guard currentWait == nil, nextTimingEvent < timingEvents.count else { return false }
        let event = timingEvents[nextTimingEvent]
        guard event.distance <= traveled + 0.000_001 else { return false }
        nextTimingEvent += 1
        currentWaitLightID = event.trafficLightID
        beginWait(event.kind, seconds: event.seconds)
        return true
    }

    private func settleWait() {
        guard var wait = currentWait, let last = waitClock else { return }
        let now = monotonicNow()
        wait.remainingSeconds = max(0, wait.remainingSeconds - max(0, now - last))
        waitClock = now
        if wait.remainingSeconds <= 0 {
            currentWait = nil; waitClock = nil; currentWaitLightID = nil
            if playbackState == .playing { stopHolding() }
        } else { currentWait = wait }
    }

    var canSkipWait: Bool { currentWait != nil }

    /// Skip only the current wait. A paused route stays paused until Resume.
    func skipCurrentWait() {
        guard currentWait != nil else { return }
        currentWait = nil; waitClock = nil; currentWaitLightID = nil
        refreshArrivalAdjustment()
        if playbackState == .playing { stopHolding() }
    }

    private var arrivalMaximumSpeed: Double {
        plannedRoute?.arrivalDate == nil ? .greatestFiniteMagnitude : ArrivalAdjustment.maximumSpeedMetersPerSecond
    }

    private func travelDuration(multiplier: Double) -> TimeInterval {
        let speed = speedMetersPerSecond.isFinite ? max(0.1, speedMetersPerSecond) : 0.1
        return useRoadSpeeds
            ? roadSpeedProfile.duration(from: traveled, to: geometry.length, fallbackSpeed: speed,
                multiplier: multiplier, maximumSpeed: arrivalMaximumSpeed)
            : remainingDistance / min(arrivalMaximumSpeed, speed * multiplier)
    }

    var remainingDuration: TimeInterval {
        travelDuration(multiplier: adjustedSpeedMultiplier) + (currentWait?.remainingSeconds ?? 0)
            + timingEvents.dropFirst(nextTimingEvent).reduce(0) { $0 + $1.seconds }
    }

    var effectiveSpeedMetersPerSecond: Double {
        let base = useRoadSpeeds ? roadSpeedProfile.speed(at: traveled, fallbackSpeed: speedMetersPerSecond) : max(plannedRoute?.arrivalDate == nil ? 0 : 0.1, speedMetersPerSecond)
        return min(arrivalMaximumSpeed, max(0, base.isFinite ? base : 0) * adjustedSpeedMultiplier)
    }

    private func refreshArrivalAdjustment() {
        guard let deadline = plannedRoute?.arrivalDate else {
            arrivalAdjustment = nil; adjustedSpeedMultiplier = 1
            return
        }
        settleWait()
        var fixedWait = currentWait?.kind == .trafficLight ? 0 : currentWait?.remainingSeconds ?? 0
        var lights: [(index: Int?, id: UUID, seconds: Double)] = []
        if currentWait?.kind == .trafficLight, let lightID = currentWaitLightID {
            lights.append((nil, lightID, currentWait!.remainingSeconds))
        }
        for index in timingEvents.indices where index >= nextTimingEvent {
            let event = timingEvents[index]
            if let lightID = event.trafficLightID {
                if greenLightIDs.contains(lightID) { timingEvents[index].seconds = 0 }
                else if event.seconds > 0 { lights.append((index, lightID, event.seconds)) }
            } else { fixedWait += event.seconds }
        }
        // Reserve the last observed bridge latency and a playback tick. This
        // makes the target conservative, while stalled transport remains visible.
        let transportReserve = remainingDistance > 0 ? max(0, lastTransportSeconds) + tickInterval : 0
        let plan = ArrivalTimingPlan(availableSeconds: deadline.timeIntervalSince(wallNow()) - transportReserve,
            fixedWaitSeconds: fixedWait, redLightSeconds: lights.map(\.seconds), travelDuration: travelDuration)
        for index in plan.skippedLightIndices {
            let light = lights[index]
            greenLightIDs.insert(light.id)
            if let eventIndex = light.index { timingEvents[eventIndex].seconds = 0 }
            else {
                currentWait = nil; currentWaitLightID = nil; waitClock = nil
                if playbackState == .playing { stopHolding() }
            }
        }
        adjustedSpeedMultiplier = plan.speedMultiplier
        let warning: String?
        if !plan.isFeasible {
            warning = "This arrival time cannot be met with the remaining stays and simulation speed limit. Choose a later time or shorten stays."
        } else if playbackState == .paused {
            warning = "Paused. Resume to keep this arrival time."
        } else { warning = nil }
        arrivalAdjustment = ArrivalAdjustment(speedMultiplier: plan.speedMultiplier,
            skippedTrafficLightCount: greenLightIDs.count, isFeasible: plan.isFeasible, warning: warning)
    }

    /// Metadata is optional and may arrive after Go. Identity prevents an old
    /// network response from modifying an edited/replaced route. Accepted
    /// progress, the active wait and pending visits remain untouched.
    @discardableResult
    func applyRoadMetadata(_ metadataRoute: PlannedRoute) -> Bool {
        guard var route = plannedRoute, route.id == metadataRoute.id else { return false }
        route.speedSegments = metadataRoute.speedSegments
        // Progressive Overpass batches rebuild their value objects. Keep the
        // identity of an already known intersection so a green decision is not
        // lost or counted twice when later road details arrive.
        let knownLights = route.trafficLights
        route.trafficLights = metadataRoute.trafficLights.map { light in
            guard let known = knownLights.first(where: { abs($0.distance - light.distance) < 2 }) else { return light }
            return TrafficLightDecision(id: known.id, distance: light.distance, delaySeconds: light.delaySeconds)
        }
        plannedRoute = route
        roadSpeedProfile = RouteSpeedProfile(segments: route.speedSegments, length: geometry.length)
        if pendingMovementDistance != nil {
            // Only the result decides whether newly discovered lights were
            // crossed. Keep them pending rather than discarding a light behind
            // an in-flight target which the device might reject.
            pendingRoadMetadata = metadataRoute
            return true
        }
        let pendingVisits = timingEvents.dropFirst(nextTimingEvent).filter {
            if case .stop = $0.kind { return true }
            return false
        }
        let futureLights = route.timingEvents.filter { event in
            event.kind == .trafficLight && event.distance > traveled + 0.000_001
        }.map { event in
            var event = event
            if let id = event.trafficLightID, greenLightIDs.contains(id) { event.seconds = 0 }
            return event
        }
        timingEvents = (futureLights + pendingVisits).enumerated().sorted {
            $0.element.distance == $1.element.distance ? $0.offset < $1.offset : $0.element.distance < $1.element.distance
        }.map(\.element)
        nextTimingEvent = 0
        refreshArrivalAdjustment()
        return true
    }

    func endPlayback() async {
        let id = beginAction()
        await waitForTransport()
        guard actionID == id else { return }
        clearPlaybackRoute()
        holdPosition()
    }

    func restoreRealLocation() async {
        let id = beginAction()
        guard let result = await transmit(nil, valid: { self.actionID == id }) else { return }
        guard actionID == id else { return }
        if result.code != 0 {
            playbackError = "Restore failed (error \(result.code)). The last simulated location may still be active. Check the connection and try again."
            holdPosition()
        } else { playbackError = nil }
    }

    private func stopHolding() { holdTask?.cancel(); holdTask = nil }

    private func holdPosition() {
        stopHolding()
        guard coordinate != nil else { return }
        holdTask = Task { @MainActor in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(holdInterval)) } catch { return }
                await waitForTransport()
                guard !Task.isCancelled, let point = coordinate else { return }
                guard let result = await transmit(point) else { return }
                guard !Task.isCancelled else { return }
                if result.code != 0 {
                    if playbackState == .playing, currentWait != nil {
                        settleWait(); waitClock = nil
                        playbackTask?.cancel(); playbackTask = nil
                        playbackState = .paused
                    }
                    playbackError = "Could not hold location (error \(result.code)). Check the device connection."
                    return
                }
            }
        }
    }

    private func clearPlaybackRoute() {
        plannedRoute = nil; clearRoute(); geometry = RouteGeometry([])
        traveled = 0; playbackState = .idle
        timingEvents = []; nextTimingEvent = 0; currentWait = nil; waitClock = nil
        pendingRoadMetadata = nil
        roadSpeedProfile = RouteSpeedProfile(segments: [], length: 0)
        greenLightIDs = []; currentWaitLightID = nil; arrivalAdjustment = nil; adjustedSpeedMultiplier = 1
    }

    private func finishRestoration() {
        stopHolding(); pauseResending(); clearPlaybackRoute()
        let wasActive = isActive
        isActive = false; coordinate = nil
        if managesBackground, wasActive {
            BackgroundAudioManager.shared.requestStop()
            BackgroundLocationManager.shared.requestStop()
        }
    }

    var remainingStops: [SimulationStop] {
        guard let route = plannedRoute else { return [] }
        return zip(route.stops.dropFirst(), route.stopDistances).filter { $0.1 > traveled }.map { $0.0 }
    }
    var remainingDistance: Double { max(0, geometry.length - traveled) }

    // Preserve upstream lifecycle entry points used by external location actions.
    func start(at coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        if !isActive {
            isActive = true
            if managesBackground {
                BackgroundAudioManager.shared.requestStart()
                BackgroundLocationManager.shared.requestStart()
            }
        }
    }
    func startResending(at coordinate: CLLocationCoordinate2D, _ operation: @escaping () -> Void) {
        start(at: coordinate); pauseResending()
        let timer = Timer(timeInterval: 4, repeats: true) { _ in operation() }
        RunLoop.main.add(timer, forMode: .common); resendTimer = timer
    }
    func startRoute(at coordinate: CLLocationCoordinate2D, coordinates: [CLLocationCoordinate2D]) -> UUID {
        let id = UUID(); routeID = id; routeCoordinates = coordinates; start(at: coordinate); return id
    }
    func isCurrentRoute(_ id: UUID) -> Bool { routeID == id }
    func clearRoute() { routeID = nil; routeCoordinates = nil }
    func pauseResending() { resendTimer?.invalidate(); resendTimer = nil }
    func updateCoordinate(_ coordinate: CLLocationCoordinate2D) { self.coordinate = coordinate }
    func stop() {
        let id = beginAction()
        Task { @MainActor in
            await waitForTransport()
            guard actionID == id else { return }
            finishRestoration()
        }
    }
}
