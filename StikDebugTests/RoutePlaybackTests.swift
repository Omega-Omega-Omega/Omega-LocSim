import CoreLocation
import XCTest
@testable import StikDebug

@MainActor
final class RoutePlaybackTests: XCTestCase {
    private func route(endLatitude: Double = 33.01) -> PlannedRoute {
        let a = SimulationStop(title: "Start", coordinate: CLLocationCoordinate2D(latitude: 33, longitude: -112))
        let b = SimulationStop(title: "End", coordinate: CLLocationCoordinate2D(latitude: endLatitude, longitude: -112))
        let geometry = RouteGeometry([a.coordinate, b.coordinate])
        return PlannedRoute(coordinates: [a.coordinate, b.coordinate], stopDistances: [geometry.length], stops: [a, b])
    }

    private func assertPlay(_ session: LocationSimulationSession, _ route: PlannedRoute,
                            file: StaticString = #filePath, line: UInt = #line) async {
        let applied = await session.play(route)
        XCTAssertTrue(applied, file: file, line: line)
    }

    private func waitUntil(timeout: Double = 2, file: StaticString = #filePath, line: UInt = #line,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for session state", file: file, line: line)
        guard condition() else { throw WaitError.timedOut }
    }

    private func assertSameCoordinate(_ actual: CLLocationCoordinate2D?, _ expected: CLLocationCoordinate2D?,
                                      file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotNil(actual, file: file, line: line)
        XCTAssertNotNil(expected, file: file, line: line)
        if let actual, let expected {
            XCTAssertEqual(actual.latitude, expected.latitude, accuracy: 0.000000001, file: file, line: line)
            XCTAssertEqual(actual.longitude, expected.longitude, accuracy: 0.000000001, file: file, line: line)
        }
    }

    func testPauseRefreshesHeldPositionAndResumeExcludesPausedTime() async throws {
        let transport = ControlledTransport()
        let session = LocationSimulationSession(tickInterval: 0.1, holdInterval: 0.015, sender: transport.send)
        defer { session.stop() }
        session.speedMetersPerSecond = 10
        await assertPlay(session, route())
        try await waitUntil { session.traveled > 0 }
        let heldPoint = await session.pauseAndWait()
        let heldDistance = session.traveled
        let pausedCallCount = transport.calls.count
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThanOrEqual(transport.calls.count - pausedCallCount, 2)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.traveled, heldDistance)
        for call in transport.calls.dropFirst(pausedCallCount) { assertSameCoordinate(call.point, heldPoint) }

        session.speedMetersPerSecond = 20
        session.resumePlayback()
        try await waitUntil { session.playbackState == .playing }
        let resumedCallCount = transport.calls.count
        // This spans several holding intervals but ends before the next playback tick.
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(transport.calls.count, resumedCallCount, "Resume must cancel stationary refreshes")
        try await waitUntil { session.traveled > heldDistance }
        _ = await session.pauseAndWait()
        XCTAssertGreaterThan(session.traveled - heldDistance, 1.5)
        XCTAssertLessThan(session.traveled - heldDistance, 4, "Paused time must not advance the route")
        XCTAssertEqual(session.plannedRoute?.stops.count, 2)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testFailedTransmissionFreezesAtLastAcceptedPosition() async throws {
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1, sender: { _ in
            calls += 1
            return calls == 1 ? 0 : -1
        })
        defer { session.stop() }
        await assertPlay(session, route())
        let start = session.coordinate
        try await waitUntil { session.playbackState == .paused && session.playbackError != nil }
        XCTAssertEqual(session.traveled, 0)
        assertSameCoordinate(session.coordinate, start)
        XCTAssertEqual(calls, 2)
    }

    func testPauseDuringInFlightUpdateRecordsItsAcceptedPointThenHolds() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        session.speedMetersPerSecond = 10
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 && transport.activeCalls == 1 }
        let lastAccepted = session.coordinate
        let inFlightPoint = transport.calls[1].point
        session.pausePlayback()
        XCTAssertEqual(session.playbackState, .paused, "Pause intent must take effect before transport returns")
        XCTAssertTrue(session.isSendingLocation)
        assertSameCoordinate(session.coordinate, lastAccepted)
        XCTAssertEqual(session.traveled, 0)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(transport.calls.count, 2, "Holding must wait for the active transmission")
        transport.release(1)
        try await waitUntil { transport.calls.count >= 3 && transport.activeCalls == 0 }
        assertSameCoordinate(session.coordinate, inFlightPoint)
        XCTAssertGreaterThan(session.traveled, 0, "An accepted in-flight update must be reflected after Pause")
        for call in transport.calls.dropFirst(2) { assertSameCoordinate(call.point, inFlightPoint) }
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testPauseDuringInFlightFailureRetainsLastAcceptedPositionAndError() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let lastAccepted = session.coordinate
        session.pausePlayback()
        transport.release(1, code: -1)
        try await waitUntil { !session.isSendingLocation }
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.traveled, 0)
        assertSameCoordinate(session.coordinate, lastAccepted)
        XCTAssertNotNil(session.playbackError, "Pause must not hide an in-flight device failure")
        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.plannedRoute)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testEditAnchorWaitsForInFlightAcceptedPosition() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let inFlightPoint = transport.calls[1].point
        var editAnchorReturned = false
        let pauseTask = Task { @MainActor in
            let point = await session.pauseAndWait()
            editAnchorReturned = true
            return point
        }
        try await waitUntil { session.playbackState == .paused }
        XCTAssertFalse(editAnchorReturned)
        transport.release(1)
        let editAnchor = await pauseTask.value
        assertSameCoordinate(editAnchor, inFlightPoint)
        assertSameCoordinate(session.coordinate, editAnchor)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testResumeDuringEditPauseDrainCannotRestartMovement() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.015, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let inFlightPoint = transport.calls[1].point
        let editTask = Task { @MainActor in await session.pauseAndWait() }
        try await waitUntil { session.playbackState == .paused }
        session.resumePlayback()
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertEqual(transport.calls.count, 2)
        transport.release(1)
        let editAnchor = await editTask.value
        assertSameCoordinate(editAnchor, inFlightPoint)
        let heldDistance = session.traveled
        try await waitUntil { transport.calls.count >= 4 }
        // Allow several playback ticks; all subsequent sends must only hold the edit anchor.
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.traveled, heldDistance)
        assertSameCoordinate(session.coordinate, editAnchor)
        for call in transport.calls.dropFirst(2) { assertSameCoordinate(call.point, editAnchor) }
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testEndWaitsForActiveUpdateAndHoldsItsAcceptedPosition() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let inFlightPoint = transport.calls[1].point
        let endTask = Task { @MainActor in await session.endPlayback() }
        try await waitUntil { session.playbackState == .paused }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertNotNil(session.plannedRoute, "End must await the active operation before clearing progress")
        XCTAssertEqual(transport.calls.count, 2)
        transport.release(1)
        await endTask.value
        XCTAssertNil(session.plannedRoute)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertTrue(session.isActive)
        assertSameCoordinate(session.coordinate, inFlightPoint)
        try await waitUntil { transport.calls.count >= 3 }
        assertSameCoordinate(transport.calls[2].point, inFlightPoint)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testRestoreQueuesBehindActiveUpdateAndStopsAllRefreshesOnSuccess() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let restoreTask = Task { @MainActor in await session.restoreRealLocation() }
        try await waitUntil { session.playbackState == .paused }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.calls.count, 2, "Restore must not overlap the active location update")
        XCTAssertTrue(session.isActive)
        transport.release(1)
        await restoreTask.value
        XCTAssertEqual(transport.calls.count, 3)
        XCTAssertNil(transport.calls.last?.point)
        XCTAssertFalse(session.isActive)
        XCTAssertNil(session.coordinate)
        XCTAssertNil(session.plannedRoute)
        XCTAssertNil(session.playbackError)
        let callCount = transport.calls.count
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(transport.calls.count, callCount, "Successful restore must stop playback and stationary refreshes")
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testRestoreFailureRetainsSimulationAndResumesHoldingWithError() async throws {
        let transport = ControlledTransport()
        transport.restorationCode = -1
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { session.stop() }
        await assertPlay(session, route())
        try await waitUntil { session.traveled > 0 }
        let heldPoint = await session.pauseAndWait()
        let heldDistance = session.traveled
        await session.restoreRealLocation()
        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.plannedRoute)
        XCTAssertNotNil(session.playbackError)
        XCTAssertTrue(session.playbackError?.contains("Restore failed") == true)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.traveled, heldDistance)
        assertSameCoordinate(session.coordinate, heldPoint)
        let afterFailureCount = transport.calls.count
        try await waitUntil { transport.calls.count > afterFailureCount }
        assertSameCoordinate(transport.calls.last?.point, heldPoint)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testStopDrainsInFlightUpdateBeforeFinalCleanup() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        await assertPlay(session, route())
        try await waitUntil { transport.calls.count == 2 }
        let lastAccepted = session.coordinate
        session.stop()
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertTrue(session.isActive, "Lifecycle cleanup must first await the active bridge call")
        assertSameCoordinate(session.coordinate, lastAccepted)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(transport.calls.count, 2)
        transport.release(1)
        try await waitUntil { !session.isActive }
        XCTAssertNil(session.coordinate)
        XCTAssertNil(session.plannedRoute)
        XCTAssertEqual(session.playbackState, .idle)
        XCTAssertFalse(session.isSendingLocation)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(transport.calls.count, 2, "Completed old work must not restart playback or holding")
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testFailedReplacementReturnsFalseAndPreservesOldRouteAndProgress() async throws {
        let transport = ControlledTransport()
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1, sender: transport.send)
        defer { session.stop() }
        let original = route()
        await assertPlay(session, original)
        try await waitUntil { session.traveled > 0 }
        let heldPoint = await session.pauseAndWait()
        let heldDistance = session.traveled
        let originalStopIDs = session.plannedRoute?.stops.map(\.id)
        transport.locationCode = -1
        let draft = route(endLatitude: 33.02)
        let applied = await session.play(draft)
        XCTAssertFalse(applied, "The caller must retain the edit draft when replacement fails")
        XCTAssertEqual(session.plannedRoute?.stops.map(\.id), originalStopIDs)
        XCTAssertEqual(session.traveled, heldDistance)
        assertSameCoordinate(session.coordinate, heldPoint)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertTrue(session.isActive)
        XCTAssertNotNil(session.playbackError)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testTwoSecondTransportMaintainsSelectedSpeedBetweenAcceptedUpdates() async throws {
        struct Acceptance {
            let point: CLLocationCoordinate2D
            let time: Double
        }
        var accepted: [Acceptance] = []
        var calls = 0
        var activeCalls = 0
        var maximumActiveCalls = 0
        let session = LocationSimulationSession(tickInterval: 0.05, holdInterval: 20, sender: { point in
            calls += 1
            activeCalls += 1
            maximumActiveCalls = max(maximumActiveCalls, activeCalls)
            if calls > 1 { try? await Task.sleep(for: .seconds(2)) }
            if let point {
                accepted.append(Acceptance(point: point, time: ProcessInfo.processInfo.systemUptime))
            }
            activeCalls -= 1
            return 0
        })
        defer { session.stop() }
        session.speedMetersPerSecond = 10
        await assertPlay(session, route())
        try await waitUntil(timeout: 6) { accepted.count >= 3 }
        session.pausePlayback()
        let from = accepted[1]
        let to = accepted[2]
        let distance = CLLocation(latitude: from.point.latitude, longitude: from.point.longitude)
            .distance(from: CLLocation(latitude: to.point.latitude, longitude: to.point.longitude))
        let elapsed = to.time - from.time
        print(String(format: "Two-second transport: %.3f m / %.3f s = %.3f m/s (selected 10 m/s)", distance, elapsed, distance / elapsed))
        XCTAssertGreaterThan(elapsed, 2)
        XCTAssertEqual(distance / elapsed, 10, accuracy: 1,
                       "Ordinary awaited transport time must count in route advancement")
        XCTAssertEqual(maximumActiveCalls, 1)
    }

    func testArrivalAndEndHoldTheAcceptedCoordinate() async throws {
        let transport = ControlledTransport()
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { session.stop() }
        session.speedMetersPerSecond = 10
        await assertPlay(session, route(endLatitude: 33.000001))
        try await waitUntil { session.playbackState == .arrived }
        let arrivalPoint = session.coordinate
        let arrivedCallCount = transport.calls.count
        try await waitUntil { transport.calls.count >= arrivedCallCount + 2 }
        for call in transport.calls.dropFirst(arrivedCallCount) { assertSameCoordinate(call.point, arrivalPoint) }
        XCTAssertEqual(session.remainingDistance, 0)
        await session.endPlayback()
        XCTAssertTrue(session.isActive)
        assertSameCoordinate(session.coordinate, arrivalPoint)
        XCTAssertNil(session.plannedRoute)
        let endedCallCount = transport.calls.count
        try await waitUntil { transport.calls.count > endedCallCount }
        assertSameCoordinate(transport.calls.last?.point, arrivalPoint)
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }


    func testLiveEditCommitsFromAcceptedInFlightPositionAndKeepsPlaying() async throws {
        let transport = ControlledTransport(blockedCalls: [1])
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1, sender: transport.send)
        defer { transport.releaseAll(); session.stop() }
        let original = route()
        session.speedMetersPerSecond = 10
        await assertPlay(session, original)
        try await waitUntil { transport.calls.count == 2 }
        let acceptedAfterDrain = transport.calls[1].point
        // This preview still starts at the earlier position, as a real editor does.
        var draft = original
        draft.id = UUID()
        let applying = Task { @MainActor in await session.applyEditedRoute(draft, replacingRouteID: original.id) }
        try await waitUntil { session.playbackState == .paused }
        XCTAssertEqual(session.plannedRoute?.id, original.id)
        transport.release(1)
        let applied = await applying.value
        XCTAssertTrue(applied)
        assertSameCoordinate(session.plannedRoute?.coordinates.first, acceptedAfterDrain)
        XCTAssertNotEqual(session.plannedRoute?.id, draft.id, "Old metadata distances must not be reused after a rebase")
        try await waitUntil { session.playbackState == .playing && transport.calls.count > 2 }
        for call in transport.calls.dropFirst(2) {
            XCTAssertGreaterThanOrEqual(call.point!.latitude, acceptedAfterDrain!.latitude)
        }
        XCTAssertEqual(transport.maximumActiveCalls, 1)
    }

    func testLiveEditPreservesManualPauseAndRejectsStaleEditIdentity() async throws {
        let transport = ControlledTransport()
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 0.02, sender: transport.send)
        defer { session.stop() }
        let original = route()
        await assertPlay(session, original)
        try await waitUntil { session.traveled > 0 }
        let held = await session.pauseAndWait()
        let applied = await session.applyEditedRoute(original, replacingRouteID: original.id)
        XCTAssertTrue(applied)
        XCTAssertEqual(session.playbackState, .paused)
        assertSameCoordinate(session.coordinate, held)
        assertSameCoordinate(session.plannedRoute?.coordinates.first, held)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(session.traveled, 0)
        let newID = session.plannedRoute?.id
        let stale = await session.applyEditedRoute(original, replacingRouteID: original.id)
        XCTAssertFalse(stale)
        XCTAssertEqual(session.plannedRoute?.id, newID)
        assertSameCoordinate(session.coordinate, held)
    }

    func testLiveEditPrunesVisitedStopAndPreservesCurrentDwellOnce() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        let stops = [SimulationStop(title: "Start", coordinate: .init(latitude: 33, longitude: -112)),
                     SimulationStop(title: "Coffee", coordinate: .init(latitude: 33.000001, longitude: -112), dwellSeconds: 30),
                     SimulationStop(title: "End", coordinate: .init(latitude: 33.00001, longitude: -112))]
        let shape = RouteGeometry(stops.map(\.coordinate))
        let original = PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(shape.distances.dropFirst()), stops: stops)
        session.speedMetersPerSecond = 1_000
        await assertPlay(session, original)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        let applied = await session.applyEditedRoute(original, replacingRouteID: original.id)
        XCTAssertTrue(applied)
        XCTAssertEqual(session.plannedRoute?.stops.map(\.title), ["Simulated Location", "End"])
        XCTAssertEqual(session.currentWait?.kind, .stop(title: "Coffee"))
        XCTAssertLessThan(session.remainingDuration, 31)
        try await waitUntil { session.playbackState == .playing }
        session.skipCurrentWait()
        try await waitUntil { session.playbackState == .arrived }
    }

    func testDivergedEditReplansFromLivePointAndHonorsPauseDuringCalculation() async throws {
        var requestedStops: [SimulationStop] = []
        var gate: CheckedContinuation<PlannedRoute, Error>?
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1,
            replanEditedRoute: { stops in
                requestedStops = stops
                return try await withCheckedThrowingContinuation { gate = $0 }
            }, sender: { _ in 0 })
        defer { gate?.resume(throwing: CancellationError()); session.stop() }
        let original = route()
        await assertPlay(session, original)
        try await waitUntil { session.traveled > 0 }
        var draft = route(endLatitude: 34.01)
        draft.coordinates[0] = .init(latitude: 34, longitude: -112)
        draft.stops[0].coordinate = draft.coordinates[0]
        draft.stopDistances = [RouteGeometry(draft.coordinates).length]
        let applying = Task { @MainActor in await session.applyEditedRoute(draft, replacingRouteID: original.id) }
        try await waitUntil { gate != nil }
        assertSameCoordinate(requestedStops.first?.coordinate, session.coordinate)
        session.pausePlayback()
        let geometry = RouteGeometry(requestedStops.map(\.coordinate))
        let fresh = PlannedRoute(coordinates: requestedStops.map(\.coordinate), stopDistances: [geometry.length], stops: requestedStops)
        gate?.resume(returning: fresh); gate = nil
        let applied = await applying.value
        XCTAssertTrue(applied)
        XCTAssertEqual(session.playbackState, .paused)
        assertSameCoordinate(session.plannedRoute?.coordinates.first, requestedStops.first?.coordinate)
    }

    func testFailedLiveEditReplanResumesOriginalTripAndKeepsProgress() async throws {
        let session = LocationSimulationSession(tickInterval: 0.02, holdInterval: 1,
            replanEditedRoute: { _ in throw URLError(.notConnectedToInternet) }, sender: { _ in 0 })
        defer { session.stop() }
        let original = route()
        await assertPlay(session, original)
        try await waitUntil { session.traveled > 0 }
        let before = session.traveled
        var draft = route(endLatitude: 34.01)
        draft.coordinates[0] = .init(latitude: 34, longitude: -112)
        draft.stops[0].coordinate = draft.coordinates[0]
        draft.stopDistances = [RouteGeometry(draft.coordinates).length]
        let applied = await session.applyEditedRoute(draft, replacingRouteID: original.id)
        XCTAssertFalse(applied)
        try await waitUntil { session.playbackState == .playing }
        XCTAssertEqual(session.plannedRoute?.id, original.id)
        XCTAssertGreaterThanOrEqual(session.traveled, before)
        XCTAssertNotNil(session.playbackError)
    }


    func testRebaseDoesNotReplayCompletedOutAndBackLegs() throws {
        let stops = [SimulationStop(title: "Start", coordinate: .init(latitude: 33, longitude: -112)),
                     SimulationStop(title: "B", coordinate: .init(latitude: 33.01, longitude: -112)),
                     SimulationStop(title: "Return", coordinate: .init(latitude: 33, longitude: -112)),
                     SimulationStop(title: "C", coordinate: .init(latitude: 32.99, longitude: -112))]
        let geometry = RouteGeometry(stops.map(\.coordinate))
        let draft = PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(geometry.distances.dropFirst()), stops: stops)
        let rebased = try XCTUnwrap(draft.rebased(at: stops[2].coordinate, omittingStopIDs: [stops[1].id, stops[2].id]))
        XCTAssertEqual(rebased.stops.map(\.title), ["Simulated Location", "C"])
        XCTAssertLessThan(RouteGeometry(rebased.coordinates).length, 1_200)
        XCTAssertTrue(rebased.coordinates.allSatisfy { $0.latitude <= 33 })
        XCTAssertEqual(rebased.distance, RouteGeometry(rebased.coordinates).length, accuracy: 0.00001)
    }


    func testAmbiguousSingleLegLoopRequiresRoadReplan() {
        let points = [CLLocationCoordinate2D(latitude: 33, longitude: -112),
                      CLLocationCoordinate2D(latitude: 33.01, longitude: -112),
                      CLLocationCoordinate2D(latitude: 33, longitude: -112),
                      CLLocationCoordinate2D(latitude: 32.99, longitude: -112)]
        let stops = [SimulationStop(title: "Start", coordinate: points[0]), SimulationStop(title: "End", coordinate: points[3])]
        let draft = PlannedRoute(coordinates: points, stopDistances: [RouteGeometry(points).length], stops: stops)
        XCTAssertNil(draft.rebased(at: points[2]), "Do not choose an arbitrary pass through a self-intersection")
    }

    func testNonPrefixCompletedStopRequiresRoadReplan() {
        let stops = [SimulationStop(title: "A", coordinate: .init(latitude: 33, longitude: -112)),
                     SimulationStop(title: "C", coordinate: .init(latitude: 33.02, longitude: -112)),
                     SimulationStop(title: "B", coordinate: .init(latitude: 33.01, longitude: -112)),
                     SimulationStop(title: "D", coordinate: .init(latitude: 33.03, longitude: -112))]
        let geometry = RouteGeometry(stops.map(\.coordinate))
        let draft = PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(geometry.distances.dropFirst()), stops: stops)
        XCTAssertNil(draft.rebased(at: stops[2].coordinate, omittingStopIDs: [stops[2].id]),
                     "Omitting a row must also remove its road detour")
    }

    func testSkipDuringAwaitedEditDoesNotResurrectVisit() async throws {
        var gate: CheckedContinuation<PlannedRoute, Error>?
        var requestedStops: [SimulationStop] = []
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1,
            replanEditedRoute: { stops in
                requestedStops = stops
                return try await withCheckedThrowingContinuation { gate = $0 }
            }, sender: { _ in 0 })
        defer { gate?.resume(throwing: CancellationError()); session.stop() }
        let stops = [SimulationStop(title: "Start", coordinate: .init(latitude: 33, longitude: -112)),
                     SimulationStop(title: "Coffee", coordinate: .init(latitude: 33.000001, longitude: -112), dwellSeconds: 30),
                     SimulationStop(title: "End", coordinate: .init(latitude: 33.00001, longitude: -112))]
        let geometry = RouteGeometry(stops.map(\.coordinate))
        let original = PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(geometry.distances.dropFirst()), stops: stops)
        session.speedMetersPerSecond = 1_000
        await assertPlay(session, original)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        var draft = route(endLatitude: 34.01)
        draft.coordinates[0] = .init(latitude: 34, longitude: -112)
        draft.stops[0].coordinate = draft.coordinates[0]
        draft.stopDistances = [RouteGeometry(draft.coordinates).length]
        let applying = Task { @MainActor in await session.applyEditedRoute(draft, replacingRouteID: original.id) }
        try await waitUntil { gate != nil }
        session.skipCurrentWait()
        let fresh = PlannedRoute(coordinates: requestedStops.map(\.coordinate),
            stopDistances: [RouteGeometry(requestedStops.map(\.coordinate)).length], stops: requestedStops)
        gate?.resume(returning: fresh); gate = nil
        let applied = await applying.value
        XCTAssertTrue(applied)
        XCTAssertNil(session.currentWait)
        try await waitUntil { session.playbackState == .playing }
    }

    private enum WaitError: Error { case timedOut }
}

/// A gate represents an actual, uncancelable bridge call already in progress.
/// Requests remain counted as active until released, even if playback is canceled.
@MainActor
private final class ControlledTransport {
    struct Call { let point: CLLocationCoordinate2D? }
    private(set) var calls: [Call] = []
    private(set) var activeCalls = 0
    private(set) var maximumActiveCalls = 0
    var locationCode: Int32 = 0
    var restorationCode: Int32 = 0
    private let blockedCalls: Set<Int>
    private var gates: [Int: CheckedContinuation<Int32, Never>] = [:]

    init(blockedCalls: Set<Int> = []) { self.blockedCalls = blockedCalls }

    func send(_ point: CLLocationCoordinate2D?) async -> Int32 {
        let index = calls.count
        calls.append(Call(point: point))
        activeCalls += 1
        maximumActiveCalls = max(maximumActiveCalls, activeCalls)
        let result: Int32
        if blockedCalls.contains(index) {
            result = await withCheckedContinuation { gates[index] = $0 }
        } else { result = point == nil ? restorationCode : locationCode }
        activeCalls -= 1
        return result
    }

    func release(_ index: Int, code: Int32 = 0) { gates.removeValue(forKey: index)?.resume(returning: code) }
    func releaseAll() {
        let pending = Array(gates.values)
        gates.removeAll()
        for gate in pending { gate.resume(returning: 0) }
    }
}
