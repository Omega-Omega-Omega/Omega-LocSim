import CoreLocation
import Testing
@testable import StikDebug

@MainActor
struct RoutePlannerTests {
    private var stops: [SimulationStop] {
        [SimulationStop(title: "Start", coordinate: CLLocationCoordinate2D(latitude: 33, longitude: -112)),
         SimulationStop(title: "Finish", coordinate: CLLocationCoordinate2D(latitude: 33.01, longitude: -112))]
    }

    @Test func cancelRejectsLateResponseWithoutCachingIt() async throws {
        let requestedStops = stops
        let points = requestedStops.map(\.coordinate)
        let first = ControlledRouteLeg()
        let second = ControlledRouteLeg(readyCoordinates: points)
        var calls = 0
        let planner = RoutePlanner { _, _ in
            calls += 1
            return calls == 1 ? first : second
        }
        let task = Task { try await planner.calculate(stops: requestedStops) }
        await first.waitUntilStarted()
        planner.cancel()
        #expect(first.cancelCount == 1)
        first.complete(points) // Simulate a provider returning after cancellation.
        await expectCancellation(of: task)

        let replacement = try await planner.calculate(stops: requestedStops)
        #expect(calls == 2)
        #expect(replacement.coordinates.count == points.count)
    }

    @Test func staleCompletionAndCancellationCannotAffectTheNewRequest() async {
        let requestedStops = stops
        let points = requestedStops.map(\.coordinate)
        let first = ControlledRouteLeg()
        let second = ControlledRouteLeg()
        var calls = 0
        let planner = RoutePlanner { _, _ in
            calls += 1
            return calls == 1 ? first : second
        }
        let oldTask = Task { try await planner.calculate(stops: requestedStops) }
        await first.waitUntilStarted()
        let newTask = Task { try await planner.calculate(stops: requestedStops) }
        await second.waitUntilStarted()
        #expect(first.cancelCount == 1)
        #expect(second.cancelCount == 0)
        oldTask.cancel()
        await first.waitUntilCancelled(count: 2)
        #expect(second.cancelCount == 0)
        first.complete(points)
        await expectCancellation(of: oldTask)

        planner.cancel()
        #expect(second.cancelCount == 1)
        second.complete(points)
        await expectCancellation(of: newTask)
    }

    @Test func taskCancellationCancelsOnlyItsOwnLeg() async {
        let requestedStops = stops
        let request = ControlledRouteLeg()
        let planner = RoutePlanner { _, _ in request }
        let task = Task { try await planner.calculate(stops: requestedStops) }
        await request.waitUntilStarted()
        task.cancel()
        await request.waitUntilCancelled()
        #expect(request.cancelCount == 1)
        request.complete(requestedStops.map(\.coordinate))
        await expectCancellation(of: task)
    }

    @Test func alreadyCancelledCallerDoesNotInterruptCurrentCalculation() async throws {
        let requestedStops = stops
        let request = ControlledRouteLeg()
        var calls = 0
        let planner = RoutePlanner { _, _ in
            calls += 1
            return request
        }
        let current = Task { try await planner.calculate(stops: requestedStops) }
        await request.waitUntilStarted()
        let cancelled = Task { try await planner.calculate(stops: requestedStops) }
        cancelled.cancel()
        await expectCancellation(of: cancelled)
        #expect(request.cancelCount == 0)
        #expect(calls == 1)
        request.complete(requestedStops.map(\.coordinate))
        _ = try await current.value
    }

    @Test func unchangedCompletedLegIsReused() async throws {
        let requestedStops = stops
        var calls = 0
        let planner = RoutePlanner { start, end in
            calls += 1
            return ControlledRouteLeg(readyCoordinates: [start.coordinate, end.coordinate])
        }
        _ = try await planner.calculate(stops: requestedStops)
        let route = try await planner.calculate(stops: requestedStops)
        #expect(calls == 1)
        #expect(route.stops.map(\.id) == requestedStops.map(\.id))
    }

    private func expectCancellation(of task: Task<PlannedRoute, Error>) async {
        switch await task.result {
        case .success:
            Issue.record("A cancelled route calculation published a result.")
        case .failure(let error):
            #expect(error is CancellationError)
        }
    }
}

@MainActor
private final class ControlledRouteLeg: RouteLegRequest {
    private let readyCoordinates: [CLLocationCoordinate2D]?
    private var result: CheckedContinuation<[CLLocationCoordinate2D], Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var cancelWaiter: CheckedContinuation<Void, Never>?
    private var awaitedCancelCount = 1
    private var didStart = false
    private(set) var cancelCount = 0

    init(readyCoordinates: [CLLocationCoordinate2D]? = nil) {
        self.readyCoordinates = readyCoordinates
    }

    func coordinates() async throws -> [CLLocationCoordinate2D] {
        didStart = true
        startWaiter?.resume()
        startWaiter = nil
        if let readyCoordinates { return readyCoordinates }
        return try await withCheckedThrowingContinuation { result = $0 }
    }

    func waitUntilStarted() async {
        if didStart { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func waitUntilCancelled(count: Int = 1) async {
        if cancelCount >= count { return }
        awaitedCancelCount = count
        await withCheckedContinuation { cancelWaiter = $0 }
    }

    func complete(_ coordinates: [CLLocationCoordinate2D]) {
        result?.resume(returning: coordinates)
        result = nil
    }

    func cancel() {
        cancelCount += 1
        if cancelCount >= awaitedCancelCount {
            cancelWaiter?.resume()
            cancelWaiter = nil
        }
        // Intentionally retain the result continuation to model late provider completion.
    }
}
