import Foundation

struct RouteSpeedSegment: Equatable {
    var startDistance: Double
    var endDistance: Double
    var metersPerSecond: Double
    var isEstimated: Bool = false
}

/// A normalized, non-overlapping profile. Gaps use the user's fallback speed.
/// Integrating time across boundaries prevents a high-speed tick from carrying
/// the previous road's speed into a slower road.
struct RouteSpeedProfile {
    private let segments: [RouteSpeedSegment]

    init(segments: [RouteSpeedSegment], length: Double) {
        var normalized: [RouteSpeedSegment] = []
        var cursor = 0.0
        for var segment in segments.sorted(by: { $0.startDistance < $1.startDistance }) {
            guard segment.startDistance.isFinite, segment.endDistance.isFinite,
                  segment.metersPerSecond.isFinite, segment.metersPerSecond > 0 else { continue }
            segment.metersPerSecond = max(0.1, segment.metersPerSecond)
            segment.startDistance = max(cursor, segment.startDistance, 0)
            segment.endDistance = min(length, segment.endDistance)
            guard segment.endDistance > segment.startDistance else { continue }
            normalized.append(segment)
            cursor = segment.endDistance
        }
        self.segments = normalized
    }

    private func safeSpeed(_ speed: Double) -> Double { speed.isFinite ? max(0.1, speed) : 0.1 }

    func speed(at distance: Double, fallbackSpeed: Double) -> Double {
        segments.first { $0.startDistance <= distance && $0.endDistance > distance }?.metersPerSecond
            ?? safeSpeed(fallbackSpeed)
    }

    private func pieces(from start: Double, to end: Double, fallbackSpeed: Double) -> [RouteSpeedSegment] {
        guard end > start else { return [] }
        var result: [RouteSpeedSegment] = []
        var cursor = start
        for segment in segments where segment.endDistance > start && segment.startDistance < end {
            if segment.startDistance > cursor {
                result.append(.init(startDistance: cursor, endDistance: min(end, segment.startDistance), metersPerSecond: safeSpeed(fallbackSpeed)))
            }
            result.append(.init(startDistance: max(cursor, segment.startDistance), endDistance: min(end, segment.endDistance), metersPerSecond: segment.metersPerSecond))
            cursor = min(end, segment.endDistance)
        }
        if cursor < end { result.append(.init(startDistance: cursor, endDistance: end, metersPerSecond: safeSpeed(fallbackSpeed))) }
        return result
    }

    func duration(from start: Double, to end: Double, fallbackSpeed: Double,
                  multiplier: Double = 1, maximumSpeed: Double = .greatestFiniteMagnitude) -> TimeInterval {
        pieces(from: start, to: end, fallbackSpeed: fallbackSpeed).reduce(0) {
            $0 + ($1.endDistance - $1.startDistance) / min(maximumSpeed, $1.metersPerSecond * multiplier)
        }
    }

    func advance(from start: Double, seconds: TimeInterval, upTo end: Double, fallbackSpeed: Double,
                 multiplier: Double = 1, maximumSpeed: Double = .greatestFiniteMagnitude) -> Double {
        var remaining = max(0, seconds)
        for piece in pieces(from: start, to: end, fallbackSpeed: fallbackSpeed) {
            let speed = min(maximumSpeed, piece.metersPerSecond * multiplier)
            let duration = (piece.endDistance - piece.startDistance) / speed
            if duration >= remaining { return piece.startDistance + remaining * speed }
            remaining -= duration
        }
        return max(start, end)
    }
}

struct TrafficLightDecision: Identifiable, Equatable {
    let id: UUID
    var distance: Double
    var delaySeconds: TimeInterval

    init(id: UUID = UUID(), distance: Double, delaySeconds: TimeInterval) {
        self.id = id
        self.distance = distance
        self.delaySeconds = delaySeconds
    }
}

struct SimulationWait: Equatable {
    enum Kind: Equatable {
        case departure
        case stop(title: String)
        case trafficLight
    }
    let kind: Kind
    var remainingSeconds: TimeInterval
}

struct RouteTimingEvent {
    let distance: Double
    let kind: SimulationWait.Kind
    var seconds: TimeInterval
    var trafficLightID: UUID? = nil
}

extension PlannedRoute {
    /// The destination is intentionally excluded: arrival already holds indefinitely.
    /// Stable sorting makes co-located lights and stops run once, in a fixed order.
    var timingEvents: [RouteTimingEvent] {
        let length = RouteGeometry(coordinates).length
        var events: [RouteTimingEvent] = trafficLights.compactMap { light in
            guard light.distance.isFinite, light.distance >= 0, light.distance <= length,
                  light.delaySeconds.isFinite, light.delaySeconds > 0 else { return nil }
            return RouteTimingEvent(distance: light.distance, kind: .trafficLight,
                                    seconds: min(90, max(5, light.delaySeconds)), trafficLightID: light.id)
        }
        if stops.count > 2 {
            for index in 1..<(stops.count - 1) where index - 1 < stopDistances.count {
                let stop = stops[index]
                let distance = stopDistances[index - 1]
                guard distance.isFinite, distance >= 0, distance <= length,
                      stop.dwellSeconds.isFinite, stop.dwellSeconds > 0 else { continue }
                events.append(RouteTimingEvent(distance: distance, kind: .stop(title: stop.title),
                                               seconds: min(86_400, stop.dwellSeconds)))
            }
        }
        return events.enumerated().sorted {
            $0.element.distance == $1.element.distance ? $0.offset < $1.offset : $0.element.distance < $1.element.distance
        }.map(\.element)
    }
}

/// A bounded simulator deadline, never a promise about a real journey or a
/// disconnected device. Waits at destinations and user pauses remain authoritative.
struct ArrivalAdjustment: Equatable {
    static let maximumSpeedMetersPerSecond = 111.76 // 250 mph, simulator ceiling
    let speedMultiplier: Double
    let skippedTrafficLightCount: Int
    let isFeasible: Bool
    let warning: String?
}

/// Deterministic, minimal-count red-light removal. Longest waits are removed
/// first, with route order breaking ties; speed changes are a last resort.
struct ArrivalTimingPlan {
    let skippedLightIndices: Set<Int>
    let speedMultiplier: Double
    let isFeasible: Bool

    init(availableSeconds: TimeInterval, fixedWaitSeconds: TimeInterval,
         redLightSeconds: [TimeInterval], travelDuration: (Double) -> TimeInterval) {
        let available = availableSeconds.isFinite ? availableSeconds : 0
        let baseTravel = travelDuration(1)
        var delay = redLightSeconds.reduce(0) { $0 + max(0, $1) }
        var skipped = Set<Int>()
        let candidates = redLightSeconds.indices.sorted {
            redLightSeconds[$0] == redLightSeconds[$1] ? $0 < $1 : redLightSeconds[$0] > redLightSeconds[$1]
        }
        for index in candidates where baseTravel + fixedWaitSeconds + delay > available + 0.001 {
            skipped.insert(index)
            delay -= max(0, redLightSeconds[index])
        }
        skippedLightIndices = skipped
        let movementBudget = available - fixedWaitSeconds - delay
        if baseTravel <= movementBudget + 0.001 {
            speedMultiplier = 1; isFeasible = true
        } else {
            // Profile speeds have a floor of 0.1 m/s and a finite 250 mph cap.
            // This multiplier can reach that cap even for the slowest profile.
            let upper = ArrivalAdjustment.maximumSpeedMetersPerSecond / 0.1
            let fastest = travelDuration(upper)
            if movementBudget <= 0 || fastest > movementBudget + 0.001 {
                speedMultiplier = upper; isFeasible = false
            } else {
                var low = 1.0, high = upper
                for _ in 0..<32 {
                    let mid = (low + high) / 2
                    if travelDuration(mid) > movementBudget { low = mid } else { high = mid }
                }
                speedMultiplier = high; isFeasible = true
            }
        }
    }
}
