import CoreLocation
import XCTest
@testable import StikDebug

@MainActor
final class SimulationTimingTests: XCTestCase {
    private func route(dwell: Double = 0) -> PlannedRoute {
        let stops = [
            SimulationStop(title: "Start", coordinate: .init(latitude: 33, longitude: -112)),
            SimulationStop(title: "Coffee", coordinate: .init(latitude: 33.000001, longitude: -112), dwellSeconds: dwell),
            SimulationStop(title: "Finish", coordinate: .init(latitude: 33.00001, longitude: -112), dwellSeconds: 60)
        ]
        let geometry = RouteGeometry(stops.map(\.coordinate))
        return PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: Array(geometry.distances.dropFirst()), stops: stops)
    }

    private func waitUntil(_ predicate: @MainActor () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(predicate(), "Timed out waiting for playback")
        if !predicate() { throw CancellationError() }
    }

    func testETAIncludesIntermediateDwellAndStableRedLightsButNotFinalHold() {
        var planned = route(dwell: 30)
        planned.trafficLights = [.init(distance: 0.05, delaySeconds: 5), .init(distance: 0.07, delaySeconds: 0)]
        XCTAssertEqual(planned.plannedDelaySeconds, 35)
        XCTAssertEqual(planned.duration(atSpeed: 10), planned.distance / 10 + 35, accuracy: 0.0001)
        XCTAssertEqual(planned.duration(atSpeed: 20), planned.distance / 20 + 35, accuracy: 0.0001)
        let date = Date(timeIntervalSince1970: 1_000)
        planned.departureDate = date.addingTimeInterval(120)
        XCTAssertEqual(planned.waitingUntilDeparture(at: date), 120)
        XCTAssertEqual(planned.waitingUntilDeparture(at: date.addingTimeInterval(121)), 0)
        XCTAssertEqual(planned.trafficLights.map(\.delaySeconds), [5, 0], "ETA calculations must not reroll lights")
    }

    func testScheduledDepartureHoldsAndPauseFreezesThenSkipStartsMovement() async throws {
        var accepted: [CLLocationCoordinate2D?] = []
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 0.02, sender: { accepted.append($0); return 0 })
        defer { session.stop() }
        var planned = route()
        planned.departureDate = Date().addingTimeInterval(30)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.playbackState == .playing && accepted.count > 1 }
        XCTAssertEqual(session.currentWait?.kind, .departure)
        XCTAssertEqual(session.traveled, 0)
        _ = await session.pauseAndWait()
        let pausedSeconds = session.currentWait!.remainingSeconds
        try await Task.sleep(for: .milliseconds(90))
        XCTAssertEqual(session.currentWait!.remainingSeconds, pausedSeconds)
        session.resumePlayback()
        try await waitUntil { session.currentWait!.remainingSeconds < pausedSeconds - 0.02 }
        session.skipCurrentWait()
        try await waitUntil { session.traveled > 0 }
        XCTAssertNil(session.currentWait)
    }

    func testHighSpeedCannotLeapOverStopAndSkipContinuesWithoutWaitingAgain() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        let planned = route(dwell: 30)
        session.speedMetersPerSecond = 1_000
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        XCTAssertEqual(session.traveled, planned.stopDistances[0], accuracy: 0.000001)
        XCTAssertEqual(session.coordinate!.latitude, planned.stops[1].coordinate.latitude, accuracy: 0.00000001)
        XCTAssertGreaterThan(session.remainingDuration, 29)
        session.skipCurrentWait()
        try await waitUntil { session.playbackState == .arrived }
        XCTAssertNil(session.currentWait)
        XCTAssertEqual(session.remainingDuration, 0)
        XCTAssertEqual(session.remainingDistance, 0)
    }

    func testColocatedRedLightAndStopRunOnceInOrderAndPausedSkipDoesNotMove() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route(dwell: 30)
        planned.trafficLights = [.init(distance: planned.stopDistances[0], delaySeconds: 90)]
        session.speedMetersPerSecond = 1_000
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .trafficLight }
        XCTAssertGreaterThan(session.remainingDuration, 119)
        session.pausePlayback()
        let held = session.traveled
        session.skipCurrentWait()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.traveled, held)
        session.resumePlayback()
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        XCTAssertLessThan(session.remainingDuration, 31)
        session.skipCurrentWait()
        try await waitUntil { session.playbackState == .arrived }
    }

    func testWaitStartsOnlyAfterDeviceAcceptsStopAndPauseCannotLoseIt() async throws {
        var gate: CheckedContinuation<Int32, Never>?
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { gate = $0 } }
            return 0
        })
        defer { gate?.resume(returning: 0); session.stop() }
        session.speedMetersPerSecond = 1_000
        let applied = await session.play(route(dwell: 30))
        XCTAssertTrue(applied)
        try await waitUntil { gate != nil }
        XCTAssertNil(session.currentWait)
        XCTAssertEqual(session.traveled, 0)
        session.pausePlayback()
        gate?.resume(returning: 0); gate = nil
        try await waitUntil { session.currentWait != nil }
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.currentWait?.kind, .stop(title: "Coffee"))
        XCTAssertEqual(session.currentWait?.remainingSeconds, 30)
    }

    func testFailedStopTransmissionDoesNotStartItsWait() async throws {
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in
            calls += 1
            return calls == 1 ? 0 : -1
        })
        defer { session.stop() }
        session.speedMetersPerSecond = 1_000
        let applied = await session.play(route(dwell: 30))
        XCTAssertTrue(applied)
        try await waitUntil { session.playbackError != nil }
        XCTAssertNil(session.currentWait)
        XCTAssertEqual(session.traveled, 0)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertGreaterThan(session.remainingDuration, 30)
    }

    func testElapsedWaitDoesNotTurnIntoMovementAndWallClockChangeDoesNotAlterWait() async throws {
        var clock = 100.0
        var date = Date(timeIntervalSince1970: 1_000)
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, monotonicNow: { clock }, wallNow: { date }, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route()
        planned.departureDate = date.addingTimeInterval(10)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.playbackState == .playing }
        date = date.addingTimeInterval(3_600)
        clock += 9
        try await waitUntil { session.currentWait?.remainingSeconds == 1 }
        XCTAssertEqual(session.traveled, 0)
        clock += 10
        try await waitUntil { session.currentWait == nil }
        XCTAssertEqual(session.traveled, 0, "Expired scheduling time must not jump the route")
    }

    func testEndAndRestoreClearPendingWaits() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 0.02, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route(dwell: 30)
        planned.departureDate = Date().addingTimeInterval(30)
        var applied = await session.play(planned)
        XCTAssertTrue(applied)
        XCTAssertNotNil(session.currentWait)
        await session.endPlayback()
        XCTAssertNil(session.currentWait)
        XCTAssertNil(session.plannedRoute)
        XCTAssertTrue(session.isActive)
        applied = await session.play(planned)
        XCTAssertTrue(applied)
        await session.restoreRealLocation()
        XCTAssertNil(session.currentWait)
        XCTAssertNil(session.plannedRoute)
        XCTAssertFalse(session.isActive)
    }

    func testRoadProfileIntegratesTimeAcrossBoundariesAndFallbackGaps() {
        let profile = RouteSpeedProfile(segments: [
            .init(startDistance: 0, endDistance: 100, metersPerSecond: 10),
            .init(startDistance: 100, endDistance: 200, metersPerSecond: 20)
        ], length: 300)
        XCTAssertEqual(profile.duration(from: 0, to: 300, fallbackSpeed: 5), 35)
        XCTAssertEqual(profile.advance(from: 50, seconds: 7, upTo: 300, fallbackSpeed: 5), 140)
        XCTAssertEqual(profile.advance(from: 50, seconds: 100, upTo: 150, fallbackSpeed: 5), 150)
        XCTAssertEqual(profile.speed(at: 100, fallbackSpeed: 5), 20)
        XCTAssertEqual(profile.speed(at: 250, fallbackSpeed: 5), 5)
        var planned = route()
        planned.speedSegments = [.init(startDistance: 0, endDistance: planned.distance, metersPerSecond: 25)]
        XCTAssertEqual(planned.duration(atSpeed: 10), planned.distance / 25, accuracy: 0.00001)
        XCTAssertEqual(planned.duration(atSpeed: 10, useRoadSpeeds: false), planned.distance / 10, accuracy: 0.00001)
    }

    func testLateMetadataPreservesCurrentDwellAndIgnoresPastLightsAndStaleRoute() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route(dwell: 30)
        session.speedMetersPerSecond = 1_000
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        session.pausePlayback()
        let held = session.traveled
        let remainingWait = session.currentWait!.remainingSeconds
        planned.trafficLights = [.init(distance: 0.01, delaySeconds: 90), .init(distance: held + 0.1, delaySeconds: 5)]
        planned.speedSegments = [.init(startDistance: 0, endDistance: planned.distance, metersPerSecond: 10)]
        XCTAssertTrue(session.applyRoadMetadata(planned))
        XCTAssertEqual(session.traveled, held)
        XCTAssertEqual(session.currentWait?.remainingSeconds, remainingWait)
        XCTAssertEqual(session.effectiveSpeedMetersPerSecond, 10)
        XCTAssertEqual(session.remainingDuration, (planned.distance - held) / 10 + remainingWait + 5, accuracy: 0.000001)
        XCTAssertTrue(session.applyRoadMetadata(planned), "Reapplying metadata must not duplicate delays")
        XCTAssertEqual(session.remainingDuration, (planned.distance - held) / 10 + remainingWait + 5, accuracy: 0.000001)
        XCTAssertFalse(session.applyRoadMetadata(route()), "A stale route cannot replace metadata")
        session.useRoadSpeeds = false
        XCTAssertEqual(session.effectiveSpeedMetersPerSecond, 1_000)
        XCTAssertEqual(session.remainingDuration, (planned.distance - held) / 1_000 + remainingWait + 5, accuracy: 0.000001)
        session.skipCurrentWait()
        session.resumePlayback()
        try await waitUntil { session.currentWait?.kind == .trafficLight }
        XCTAssertEqual(session.traveled, held + 0.1, accuracy: 0.000001)
        session.skipCurrentWait()
        try await waitUntil { session.playbackState == .arrived }
    }

    func testMetadataDuringInFlightUpdateDoesNotMoveBackToNewlyDiscoveredLight() async throws {
        var gate: CheckedContinuation<Int32, Never>?
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { gate = $0 } }
            return 0
        })
        defer { gate?.resume(returning: 0); session.stop() }
        var planned = route()
        session.speedMetersPerSecond = 10
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { gate != nil }
        planned.trafficLights = [.init(distance: 0.01, delaySeconds: 90)]
        XCTAssertTrue(session.applyRoadMetadata(planned))
        gate?.resume(returning: 0); gate = nil
        try await waitUntil { session.traveled > 0 }
        session.pausePlayback()
        XCTAssertNil(session.currentWait)
        XCTAssertLessThan(session.remainingDuration, 1)
    }

    func testFailedRefreshDuringScheduledWaitPausesCountdownAndReportsError() async throws {
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 0.02, sender: { _ in
            calls += 1
            return calls == 1 ? 0 : -1
        })
        defer { session.stop() }
        var planned = route()
        planned.departureDate = Date().addingTimeInterval(30)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.playbackError != nil }
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertTrue(session.isActive)
        let remaining = session.currentWait!.remainingSeconds
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertEqual(session.currentWait!.remainingSeconds, remaining)
        XCTAssertEqual(session.traveled, 0)
    }

    func testMetadataDuringRejectedUpdateRetainsUncrossedRedLightForResume() async throws {
        var gate: CheckedContinuation<Int32, Never>?
        var calls = 0
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in
            calls += 1
            if calls == 2 { return await withCheckedContinuation { gate = $0 } }
            return 0
        })
        defer { gate?.resume(returning: 0); session.stop() }
        var planned = route()
        session.speedMetersPerSecond = 10
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { gate != nil }
        planned.trafficLights = [.init(distance: 0.01, delaySeconds: 90)]
        XCTAssertTrue(session.applyRoadMetadata(planned))
        gate?.resume(returning: -1); gate = nil
        try await waitUntil { session.playbackError != nil }
        XCTAssertEqual(session.traveled, 0)
        XCTAssertGreaterThan(session.remainingDuration, 90)
        session.resumePlayback()
        try await waitUntil { session.currentWait?.kind == .trafficLight }
        XCTAssertEqual(session.traveled, 0.01, accuracy: 0.000001)
    }

    func testEditingScheduledRoutePreservesPausedDepartureCountdown() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route()
        planned.departureDate = Date().addingTimeInterval(30)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        _ = await session.pauseAndWait()
        let remaining = session.currentWait!.remainingSeconds
        try await Task.sleep(for: .milliseconds(40))
        let replacement = route()
        let edited = await session.play(replacement, preservingCurrentWait: true)
        XCTAssertTrue(edited)
        XCTAssertEqual(session.currentWait?.kind, .departure)
        XCTAssertEqual(session.currentWait!.remainingSeconds, remaining, accuracy: 0.02)
        XCTAssertEqual(session.traveled, 0)
        XCTAssertEqual(session.plannedRoute?.id, replacement.id)
    }

    func testEditingDuringVisitPreservesRemainingVisitWithoutDuplicatingStartDwell() async throws {
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1, sender: { _ in 0 })
        defer { session.stop() }
        session.speedMetersPerSecond = 1_000
        let planned = route(dwell: 30)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        _ = await session.pauseAndWait()
        let remaining = session.currentWait!.remainingSeconds
        let stops = Array(planned.stops.dropFirst())
        let replacement = PlannedRoute(coordinates: stops.map(\.coordinate), stopDistances: [RouteGeometry(stops.map(\.coordinate)).length], stops: stops)
        let edited = await session.play(replacement, preservingCurrentWait: true)
        XCTAssertTrue(edited)
        XCTAssertEqual(session.currentWait?.kind, .stop(title: "Coffee"))
        XCTAssertEqual(session.currentWait!.remainingSeconds, remaining, accuracy: 0.02)
        XCTAssertLessThan(session.remainingDuration, 31, "The anchor must not create a duplicate visit.")
        session.skipCurrentWait()
        try await waitUntil { session.playbackState == .arrived }
    }
    func testArrivalPlanSkipsMinimumNumberOfLightsBeforeIncreasingSpeed() {
        let travel: (Double) -> Double = { 100 / min(5, $0) }
        let noChange = ArrivalTimingPlan(availableSeconds: 205, fixedWaitSeconds: 10,
            redLightSeconds: [5, 30, 60], travelDuration: travel)
        XCTAssertTrue(noChange.skippedLightIndices.isEmpty)
        XCTAssertEqual(noChange.speedMultiplier, 1)
        let small = ArrivalTimingPlan(availableSeconds: 200, fixedWaitSeconds: 10,
            redLightSeconds: [5, 30, 60], travelDuration: travel)
        XCTAssertEqual(small.skippedLightIndices, [2], "One long red is enough; preserve the others")
        XCTAssertEqual(small.speedMultiplier, 1)
        let medium = ArrivalTimingPlan(availableSeconds: 125, fixedWaitSeconds: 10,
            redLightSeconds: [5, 30, 60], travelDuration: travel)
        XCTAssertEqual(medium.skippedLightIndices, [1, 2])
        XCTAssertEqual(medium.speedMultiplier, 1)
        let short = ArrivalTimingPlan(availableSeconds: 60, fixedWaitSeconds: 10,
            redLightSeconds: [5, 30, 60], travelDuration: travel)
        XCTAssertEqual(short.skippedLightIndices, [0, 1, 2])
        XCTAssertEqual(short.speedMultiplier, 2, accuracy: 0.00001)
        XCTAssertTrue(short.isFeasible)
    }

    func testArrivalPlanReportsImpossibleWaitsAndSpeedWithoutInfinity() {
        let travel: (Double) -> Double = { 100 / min(5, $0) }
        for budget in [0.0, -1, 10, 29, .nan, .infinity] {
            let plan = ArrivalTimingPlan(availableSeconds: budget, fixedWaitSeconds: 10,
                redLightSeconds: [30], travelDuration: travel)
            XCTAssertFalse(plan.isFeasible)
            XCTAssertTrue(plan.speedMultiplier.isFinite)
            XCTAssertEqual(plan.skippedLightIndices, [0])
        }
        let exact = ArrivalTimingPlan(availableSeconds: 30, fixedWaitSeconds: 10,
            redLightSeconds: [], travelDuration: travel)
        XCTAssertTrue(exact.isFeasible)
    }

    func testAdjustedProfileRespectsPerSegmentCapAndSameETAIntegration() {
        let profile = RouteSpeedProfile(segments: [
            .init(startDistance: 0, endDistance: 100, metersPerSecond: 10),
            .init(startDistance: 100, endDistance: 300, metersPerSecond: 100)
        ], length: 300)
        let duration = profile.duration(from: 0, to: 300, fallbackSpeed: 10, multiplier: 2, maximumSpeed: 100)
        XCTAssertEqual(duration, 7, accuracy: 0.00001)
        XCTAssertEqual(profile.advance(from: 0, seconds: duration, upTo: 300,
            fallbackSpeed: 10, multiplier: 2, maximumSpeed: 100), 300, accuracy: 0.00001)
    }

    func testLiveArrivalRetargetPreservesPauseAndDwellThenRecoversWithLaterDeadline() async throws {
        var now = Date(timeIntervalSince1970: 10_000)
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1,
            wallNow: { now }, sender: { _ in 0 })
        defer { session.stop() }
        session.speedMetersPerSecond = 1_000
        var planned = route(dwell: 30)
        planned.trafficLights = [.init(distance: planned.distance * 0.8, delaySeconds: 60)]
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .stop(title: "Coffee") }
        _ = await session.pauseAndWait()
        let wait = session.currentWait!.remainingSeconds
        session.updateArrivalDate(now.addingTimeInterval(35))
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.currentWait?.remainingSeconds, wait)
        XCTAssertTrue(session.arrivalAdjustment!.isFeasible)
        XCTAssertEqual(session.arrivalAdjustment?.skippedTrafficLightCount, 1)
        XCTAssertNotNil(session.arrivalAdjustment?.warning)
        now += 40
        session.updateArrivalDate(planned.arrivalDate ?? now.addingTimeInterval(-5))
        XCTAssertFalse(session.arrivalAdjustment!.isFeasible)
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertEqual(session.currentWait?.remainingSeconds, wait)
        session.updateArrivalDate(now.addingTimeInterval(120))
        XCTAssertTrue(session.arrivalAdjustment!.isFeasible)
        session.resumePlayback()
        try await waitUntil { session.playbackState == .playing }
        XCTAssertNil(session.arrivalAdjustment?.warning)
        session.updateArrivalDate(nil)
        XCTAssertNil(session.arrivalAdjustment)
        XCTAssertEqual(session.currentWait?.kind, .stop(title: "Coffee"))
    }

    func testArrivalRetargetCanReleaseCurrentRedWithoutResumingPausedTrip() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1,
            wallNow: { now }, sender: { _ in 0 })
        defer { session.stop() }
        session.speedMetersPerSecond = 10
        var planned = route()
        planned.trafficLights = [.init(distance: 0, delaySeconds: 60)]
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        try await waitUntil { session.currentWait?.kind == .trafficLight }
        _ = await session.pauseAndWait()
        session.updateArrivalDate(now.addingTimeInterval(1))
        XCTAssertEqual(session.playbackState, .paused)
        XCTAssertNil(session.currentWait)
        XCTAssertEqual(session.traveled, 0)
        XCTAssertEqual(session.arrivalAdjustment?.skippedTrafficLightCount, 1)
        XCTAssertLessThanOrEqual(session.effectiveSpeedMetersPerSecond, ArrivalAdjustment.maximumSpeedMetersPerSecond)
    }

    func testTinyPositiveRoadSpeedStillCanReachDeadlineSpeedCap() {
        let profile = RouteSpeedProfile(segments: [.init(startDistance: 0, endDistance: 1_000, metersPerSecond: 0.01)], length: 1_000)
        let plan = ArrivalTimingPlan(availableSeconds: 10, fixedWaitSeconds: 0, redLightSeconds: []) {
            profile.duration(from: 0, to: 1_000, fallbackSpeed: 0.01, multiplier: $0,
                             maximumSpeed: ArrivalAdjustment.maximumSpeedMetersPerSecond)
        }
        XCTAssertTrue(plan.isFeasible)
        XCTAssertEqual(profile.duration(from: 0, to: 1_000, fallbackSpeed: 0.01,
            multiplier: plan.speedMultiplier, maximumSpeed: ArrivalAdjustment.maximumSpeedMetersPerSecond), 10, accuracy: 0.00001)
    }

    func testProgressiveMetadataDoesNotReviveOrDoubleCountGreenedLight() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let session = LocationSimulationSession(tickInterval: 0.01, holdInterval: 1,
            wallNow: { now }, sender: { _ in 0 })
        defer { session.stop() }
        var planned = route()
        planned.trafficLights = [.init(distance: planned.distance * 0.8, delaySeconds: 60)]
        planned.arrivalDate = now.addingTimeInterval(1)
        let applied = await session.play(planned)
        XCTAssertTrue(applied)
        _ = await session.pauseAndWait()
        XCTAssertEqual(session.arrivalAdjustment?.skippedTrafficLightCount, 1)
        var metadata = planned
        metadata.trafficLights = [.init(distance: planned.distance * 0.8, delaySeconds: 60)]
        XCTAssertTrue(session.applyRoadMetadata(metadata))
        XCTAssertEqual(session.arrivalAdjustment?.skippedTrafficLightCount, 1)
        XCTAssertLessThan(session.remainingDuration, 1)
        session.updateArrivalDate(nil)
        XCTAssertTrue(session.applyRoadMetadata(metadata))
        XCTAssertLessThan(session.remainingDuration, 1, "Clearing a deadline does not reroll an already green light")
    }

}
