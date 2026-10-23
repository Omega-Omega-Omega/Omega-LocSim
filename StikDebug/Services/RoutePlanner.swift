import MapKit

struct SimulationStop: Identifiable {
    let id: UUID
    var title: String
    var coordinate: CLLocationCoordinate2D
    /// A visit at an intermediate stop. The final destination holds until End or Restore.
    var dwellSeconds: TimeInterval
    init(title: String, coordinate: CLLocationCoordinate2D, dwellSeconds: TimeInterval = 0) {
        id = UUID(); self.title = title; self.coordinate = coordinate
        self.dwellSeconds = dwellSeconds
    }
}

struct PlannedRoute {
    var id = UUID()
    var coordinates: [CLLocationCoordinate2D]
    var stopDistances: [Double]
    var stops: [SimulationStop]
    var departureDate: Date? = nil
    var arrivalDate: Date? = nil
    /// Sampled once during route planning. Zero-delay entries represent green lights.
    var trafficLights: [TrafficLightDecision] = []
    var speedSegments: [RouteSpeedSegment] = []
    var distance: Double { stopDistances.last ?? 0 }

    var plannedDelaySeconds: TimeInterval { timingEvents.reduce(0) { $0 + $1.seconds } }
    func duration(atSpeed speed: Double, useRoadSpeeds: Bool = true) -> TimeInterval {
        let profile = RouteSpeedProfile(segments: useRoadSpeeds ? speedSegments : [], length: distance)
        return profile.duration(from: 0, to: distance, fallbackSpeed: speed) + plannedDelaySeconds
    }
    func waitingUntilDeparture(at date: Date = Date()) -> TimeInterval {
        max(0, departureDate?.timeIntervalSince(date) ?? 0)
    }
}

@MainActor
protocol RouteLegRequest: AnyObject {
    func coordinates() async throws -> [CLLocationCoordinate2D]
    func cancel()
}

@MainActor
private final class MapKitLegRequest: RouteLegRequest {
    private let directions: MKDirections

    init(start: SimulationStop, end: SimulationStop) {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end.coordinate))
        request.transportType = .automobile
        directions = MKDirections(request: request)
    }

    func coordinates() async throws -> [CLLocationCoordinate2D] {
        let response = try await directions.calculate()
        guard let route = response.routes.first else { throw URLError(.resourceUnavailable) }
        var points = Array(repeating: CLLocationCoordinate2D(), count: route.polyline.pointCount)
        route.polyline.getCoordinates(&points, range: NSRange(location: 0, length: points.count))
        return points
    }

    func cancel() { directions.cancel() }
}

@MainActor
final class RoutePlanner {
    typealias LegRequestFactory = @MainActor (SimulationStop, SimulationStop) -> any RouteLegRequest

    private var cache: [String: [CLLocationCoordinate2D]] = [:]
    private var pending: (any RouteLegRequest)?
    private var calculationID: UUID?
    private let makeLegRequest: LegRequestFactory

    init(makeLegRequest: @escaping LegRequestFactory = { MapKitLegRequest(start: $0, end: $1) }) {
        self.makeLegRequest = makeLegRequest
    }

    func cancel() {
        calculationID = nil
        pending?.cancel()
        pending = nil
    }

    func calculate(stops: [SimulationStop]) async throws -> PlannedRoute {
        try Task.checkCancellation()
        cancel()
        guard stops.count >= 2 else { throw URLError(.badURL) }
        let id = UUID()
        calculationID = id
        defer {
            if calculationID == id {
                pending = nil
                calculationID = nil
            }
        }
        var coordinates: [CLLocationCoordinate2D] = []
        var distances: [Double] = []
        var total = 0.0
        for (start, end) in zip(stops, stops.dropFirst()) {
            try checkCurrentCalculation(id)
            let key = "\(start.coordinate.latitude),\(start.coordinate.longitude):\(end.coordinate.latitude),\(end.coordinate.longitude)"
            let leg: [CLLocationCoordinate2D]
            if let saved = cache[key] { leg = saved } else {
                let request = makeLegRequest(start, end)
                pending = request
                let points: [CLLocationCoordinate2D]
                do {
                    points = try await withTaskCancellationHandler {
                        try await request.coordinates()
                    } onCancel: {
                        // Cancel this request only: a later calculation may already own pending.
                        Task { @MainActor in request.cancel() }
                    }
                } catch {
                    try checkCurrentCalculation(id)
                    throw error
                }
                try checkCurrentCalculation(id)
                guard points.count > 1 else { throw URLError(.zeroByteResource) }
                pending = nil
                cache[key] = points
                leg = points
            }
            for point in leg {
                if let previous = coordinates.last {
                    total += CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                        .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
                }
                coordinates.append(point)
            }
            distances.append(total)
        }
        try checkCurrentCalculation(id)
        return PlannedRoute(coordinates: coordinates, stopDistances: distances, stops: stops)
    }

    private func checkCurrentCalculation(_ id: UUID) throws {
        try Task.checkCancellation()
        guard calculationID == id else { throw CancellationError() }
    }
}

struct RouteGeometry {
    let points: [CLLocationCoordinate2D]
    let distances: [Double]
    init(_ points: [CLLocationCoordinate2D]) {
        self.points = points
        var distances = [0.0]
        for (a, b) in zip(points, points.dropFirst()) {
            distances.append(distances.last! + CLLocation(latitude: a.latitude, longitude: a.longitude)
                .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude)))
        }
        self.distances = points.isEmpty ? [] : distances
    }
    var length: Double { distances.last ?? 0 }
    func coordinate(at distance: Double) -> CLLocationCoordinate2D? {
        guard let first = points.first else { return nil }
        if distance <= 0 { return first }
        guard distance < length else { return points.last }
        var low = 1, high = distances.count - 1
        while low < high {
            let mid = (low + high) / 2
            if distances[mid] < distance { low = mid + 1 } else { high = mid }
        }
        let span = distances[low] - distances[low - 1]
        let fraction = span > 0 ? (distance - distances[low - 1]) / span : 1
        let a = points[low - 1], b = points[low]
        var delta = b.longitude - a.longitude
        if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
        let longitude = (a.longitude + delta * fraction + 540).truncatingRemainder(dividingBy: 360) - 180
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * fraction, longitude: longitude)
    }
}

extension PlannedRoute {
    /// Trim a preview from the live accepted position, keeping route distances
    /// and timing metadata in the same coordinate system. A far-off preview must
    /// be replanned on roads instead of drawing a long straight-line shortcut.
    func rebased(at point: CLLocationCoordinate2D, omittingStopIDs: Set<UUID> = []) -> PlannedRoute? {
        let allVisits = Array(zip(stops.dropFirst(), stopDistances))
        guard let firstPendingIndex = allVisits.firstIndex(where: { !omittingStopIDs.contains($0.0.id) }) else { return nil }
        // Removing an interior stop changes road choice. Replan rather than
        // retaining the old detour through a stop that is no longer pending.
        guard !allVisits.dropFirst(firstPendingIndex).contains(where: { omittingStopIDs.contains($0.0.id) }) else { return nil }
        let visits = Array(allVisits.dropFirst(firstPendingIndex))
        let lowerBound = firstPendingIndex > 0 ? allVisits[firstPendingIndex - 1].1 : 0
        let geometry = RouteGeometry(coordinates)
        guard let projection = geometry.projection(of: point, from: lowerBound, upTo: visits[0].1), projection.offset <= 35 else { return nil }
        let tail = zip(coordinates, geometry.distances).filter { $0.1 > projection.distance + 0.000_001 }.map(\.0)
        let newCoordinates = [point, projection.coordinate] + tail
        let connector = CLLocation(latitude: point.latitude, longitude: point.longitude)
            .distance(from: CLLocation(latitude: projection.coordinate.latitude, longitude: projection.coordinate.longitude))
        let shift = connector - projection.distance
        var replacement = self
        // Old enrichment requests refer to the original distance system.
        replacement.id = UUID()
        replacement.coordinates = newCoordinates
        replacement.stops = [SimulationStop(title: "Simulated Location", coordinate: point)] + visits.map(\.0)
        replacement.stopDistances = visits.map { max(0, $0.1 + shift) }
        replacement.trafficLights = trafficLights.filter { $0.distance > projection.distance + 0.000_001 }.map {
            var light = $0; light.distance += shift; return light
        }
        replacement.speedSegments = speedSegments.filter { $0.endDistance > projection.distance }.map {
            var segment = $0
            segment.startDistance = max(connector, segment.startDistance + shift)
            segment.endDistance += shift
            return segment
        }
        return replacement
    }
}

extension RouteGeometry {
    struct Projection {
        let coordinate: CLLocationCoordinate2D
        let distance: Double
        let offset: Double
    }

    /// Search only the next leg so a looping route cannot jump to a later lap.
    func projection(of point: CLLocationCoordinate2D, from lowerBound: Double = 0, upTo limit: Double) -> Projection? {
        guard points.count > 1 else { return nil }
        var best: Projection?
        var candidates: [Projection] = []
        let longitudeScale = cos(point.latitude * .pi / 180)
        func longitudeDelta(_ value: Double) -> Double {
            var delta = value - point.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return delta * longitudeScale
        }
        for index in 1..<points.count where distances[index - 1] <= limit && distances[index] >= lowerBound {
            let a = points[index - 1], b = points[index]
            let ax = longitudeDelta(a.longitude), ay = a.latitude - point.latitude
            let bx = longitudeDelta(b.longitude), by = b.latitude - point.latitude
            let dx = bx - ax, dy = by - ay
            let squared = dx * dx + dy * dy
            let span = distances[index] - distances[index - 1]
            let upper = span > 0 ? min(1, max(0, limit - distances[index - 1]) / span) : 0
            let lower = span > 0 ? max(0, min(1, (lowerBound - distances[index - 1]) / span)) : 0
            let fraction = squared > 0 ? min(upper, max(lower, -(ax * dx + ay * dy) / squared)) : lower
            let distance = distances[index - 1] + fraction * span
            guard let coordinate = coordinate(at: distance) else { continue }
            let offset = CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let candidate = Projection(coordinate: coordinate, distance: distance, offset: offset)
            candidates.append(candidate)
            if best == nil || offset < best!.offset { best = candidate }
        }
        // A single road leg can double back over itself. Coordinates alone do
        // not identify which pass is current, so ambiguous projections replan.
        if let best, candidates.contains(where: {
            $0.offset <= best.offset + 2 && abs($0.distance - best.distance) > 35
        }) { return nil }
        return best
    }
}
