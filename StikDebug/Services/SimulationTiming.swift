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

    func duration(from start: Double, to end: Double, fallbackSpeed: Double) -> TimeInterval {
        pieces(from: start, to: end, fallbackSpeed: fallbackSpeed).reduce(0) {
            $0 + ($1.endDistance - $1.startDistance) / $1.metersPerSecond
        }
    }

    func advance(from start: Double, seconds: TimeInterval, upTo end: Double, fallbackSpeed: Double) -> Double {
        var remaining = max(0, seconds)
        for piece in pieces(from: start, to: end, fallbackSpeed: fallbackSpeed) {
            let duration = (piece.endDistance - piece.startDistance) / piece.metersPerSecond
            if duration >= remaining { return piece.startDistance + remaining * piece.metersPerSecond }
            remaining -= duration
        }
        return max(start, end)
    }
}

struct TrafficLightDecision: Identifiable, Equatable {
    let id: UUID
    var distance: Double
    var delaySeconds: TimeInterval

    init(distance: Double, delaySeconds: TimeInterval) {
        id = UUID()
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
    let seconds: TimeInterval
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
                                    seconds: min(90, max(5, light.delaySeconds)))
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
