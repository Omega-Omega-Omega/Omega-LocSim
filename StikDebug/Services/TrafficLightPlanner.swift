import Foundation
import CoreLocation

struct TrafficLightPlanResult {
    var route: PlannedRoute
    var notice: String
    var signalCount: Int
}

/// Loads optional road details after MapKit geometry is ready. The first short
/// section is published before subsequent sections; Go never depends on this.
@MainActor
final class TrafficLightPlanner {
    private var cache: [String: (Date, RoadMetadataResponse)] = [:]
    private var prefersMirror = false
    private var providerCooldowns: [String: Date] = [:]
    private let session: URLSession
    private let pause: @MainActor (Double) async throws -> Void

    init(session: URLSession = .shared,
         pause: @escaping @MainActor (Double) async throws -> Void = { seconds in
             try await Task.sleep(for: .seconds(seconds))
         }) {
        self.session = session
        self.pause = pause
    }

    func enrich(_ route: PlannedRoute, probability: Double,
                includeTrafficLights: Bool = true,
                onUpdate: (@MainActor (TrafficLightPlanResult) -> Void)? = nil) async throws -> TrafficLightPlanResult {
        let geometry = RouteGeometry(route.coordinates)
        guard geometry.length > 0 else {
            return .init(route: route, notice: "No road details for this route.", signalCount: 0)
        }
        // Bound public-service work. Long trips keep their explicit fallback
        // beyond the fetched corridor rather than inventing speed limits.
        let coverageEnd = min(geometry.length, 300_000)
        var start = 0.0
        var elements: [String: RoadMetadataElement] = [:]
        var result = TrafficLightPlanResult(route: route, notice: "Loading road details…", signalCount: 0)
        while start < coverageEnd {
            try Task.checkCancellation()
            let end = min(coverageEnd, start + (start == 0 ? 8_000 : 20_000))
            let points = RoadMetadataMatcher.queryPoints(geometry, from: start, to: end)
            let query = Self.query(points: points, includeLights: includeTrafficLights)
            let response: RoadMetadataResponse
            if let saved = cache[query], Date().timeIntervalSince(saved.0) < 3_600 {
                response = saved.1
            } else {
                response = try await fetch(query: query)
                if cache.count >= 24 { cache.removeAll(keepingCapacity: true) }
                cache[query] = (Date(), response)
            }
            try Task.checkCancellation()
            for element in response.elements { elements["\(element.type):\(element.id)"] = element }
            let currentElements = Array(elements.values)
            let currentEnd = end
            result = await Task.detached(priority: .utility) {
                RoadMetadataMatcher.makeResult(route: route, elements: currentElements, coverageEnd: currentEnd,
                                               probability: probability, includeTrafficLights: includeTrafficLights)
            }.value
            try Task.checkCancellation()
            onUpdate?(result)
            start = end
        }
        return result
    }

    private func fetch(query: String) async throws -> RoadMetadataResponse {
        let primary = "https://overpass-api.de/api/interpreter"
        let mirror = "https://overpass.private.coffee/api/interpreter"
        let providers = prefersMirror ? [mirror, primary] : [primary, mirror]
        // One primary attempt and at most two mirror attempts per chunk, always
        // sequential. Reuse a working mirror for later chunks, but allow the
        // primary to recover if that mirror later fails.
        for provider in providers {
            try Task.checkCancellation()
            if let until = providerCooldowns[provider], until > Date() { continue }
            let attemptLimit = provider == primary ? 1 : 2
            for attempt in 0..<attemptLimit {
                try Task.checkCancellation()
                do {
                    let response = try await fetch(query: query, provider: provider)
                    prefersMirror = provider == mirror
                    providerCooldowns[provider] = nil
                    return response
                } catch let failure as ProviderFailure {
                    if failure.cooldown {
                        providerCooldowns[provider] = Date().addingTimeInterval(failure.delay)
                    }
                    // A cooldown applies only to its host. Fail over immediately
                    // instead of delaying the first request to the other host.
                    guard attempt + 1 < attemptLimit, failure.delay <= 30 else { break }
                    try await pause(failure.delay)
                }
            }
        }
        try Task.checkCancellation()
        throw RoadMetadataError.unavailable
    }

    private struct ProviderFailure: Error {
        var delay: Double = 2
        var cooldown = false
    }

    private static let transientStatuses = [408, 429, 500, 502, 503, 504]

    private func fetch(query: String, provider: String) async throws -> RoadMetadataResponse {
        var request = URLRequest(url: URL(string: provider)!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OmegaLocSim/3.2 (https://github.com/Omega-Omega-Omega/Omega-LocSim)", forHTTPHeaderField: "User-Agent")
        var body = URLComponents()
        body.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            guard let error = error as? URLError,
                  [.timedOut, .networkConnectionLost, .cannotConnectToHost,
                   .cannotFindHost, .dnsLookupFailed].contains(error.code) else { throw RoadMetadataError.unavailable }
            throw ProviderFailure()
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw RoadMetadataError.unavailable }
        if Self.transientStatuses.contains(http.statusCode) {
            throw ProviderFailure(delay: Self.providerDelay(response: http, attempt: 0, now: Date()),
                                  cooldown: http.statusCode == 429 || http.value(forHTTPHeaderField: "Retry-After") != nil)
        }
        guard (200...299).contains(http.statusCode), data.count < 24_000_000 else {
            throw RoadMetadataError.unavailable
        }
        // Overpass can return HTTP 200 with a runtime-error remark, or an HTML
        // provider error. Neither is usable metadata and neither is cached.
        guard let decoded = try? JSONDecoder().decode(RoadMetadataResponse.self, from: data),
              decoded.remark == nil else { throw ProviderFailure() }
        return decoded
    }

    static func retryDelay(response: HTTPURLResponse, attempt: Int, now: Date = Date()) -> Double? {
        guard (0..<2).contains(attempt), transientStatuses.contains(response.statusCode) else { return nil }
        let delay = providerDelay(response: response, attempt: attempt, now: now)
        return delay <= 30 ? delay : nil
    }

    private static func providerDelay(response: HTTPURLResponse, attempt: Int, now: Date) -> Double {
        let backoff = response.statusCode == 429 ? 30.0 : Double(2 << attempt)
        guard let header = response.value(forHTTPHeaderField: "Retry-After") else { return backoff }
        let seconds: Double
        if let value = Double(header.trimmingCharacters(in: .whitespaces)), value.isFinite {
            seconds = value
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            guard let date = formatter.date(from: header) else { return backoff }
            seconds = date.timeIntervalSince(now)
        }
        // Retain long cooldowns for subsequent calls, while fetch() declines
        // to sleep or retry this host automatically for more than 30 seconds.
        return max(backoff, seconds)
    }

    private static func query(points: [CLLocationCoordinate2D], includeLights: Bool) -> String {
        let path = points.map { String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), $0.latitude, $0.longitude) }.joined(separator: ",")
        let roads = "way(around:45,\(path))[\"highway\"~\"^(motorway|motorway_link|trunk|trunk_link|primary|primary_link|secondary|secondary_link|tertiary|tertiary_link|residential|unclassified|service|living_street)$\"];"
        let lights = includeLights ? "node(around:35,\(path))[\"highway\"=\"traffic_signals\"];" : ""
        return "[out:json][timeout:18][maxsize:33554432];(\(roads)\(lights));out body geom;"
    }
}

enum RoadMetadataError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Road details are unavailable. The route can use your fallback speed; retry to add mapped limits and lights." }
}

struct RoadMetadataResponse: Decodable {
    var elements: [RoadMetadataElement]
    var remark: String?
}

struct RoadMetadataElement: Decodable {
    struct Point: Decodable { var lat: Double; var lon: Double }
    var type: String
    var id: Int64
    var lat: Double?
    var lon: Double?
    var tags: [String: String]?
    var geometry: [Point]?
    var nodes: [Int64]?
}

enum RoadMetadataMatcher {
    struct XY { var x: Double; var y: Double }
    struct Projection { var distance: Double; var offset: Double; var alignment: Double; var forward: Bool }
    private struct RoadPiece { var a: XY; var b: XY; var tags: [String: String]; var wayID: Int64 }
    private struct Cell: Hashable { var x: Int; var y: Int }
    private struct Plane {
        var reference: CLLocationCoordinate2D
        func point(_ coordinate: CLLocationCoordinate2D) -> XY {
            var delta = coordinate.longitude - reference.longitude
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            return XY(x: delta * cos(reference.latitude * .pi / 180) * 111_195,
                      y: (coordinate.latitude - reference.latitude) * 111_195)
        }

        func edge(from a: RoadMetadataElement.Point, to b: RoadMetadataElement.Point) -> (XY, XY) {
            let start = point(.init(latitude: a.lat, longitude: a.lon))
            var delta = b.lon - a.lon
            if delta > 180 { delta -= 360 }; if delta < -180 { delta += 360 }
            // Keep each remote edge continuous at the date line. Independently
            // wrapping both endpoints can draw a distant edge across the world.
            let end = XY(x: start.x + delta * cos(reference.latitude * .pi / 180) * 111_195,
                         y: (b.lat - reference.latitude) * 111_195)
            return (start, end)
        }
    }

    static func parseSpeed(_ raw: String?) -> Double? {
        guard let raw = raw?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // Conditional and lane-dependent restrictions are not represented as a
        // single known limit. They deliberately use the estimated fallback.
        guard !raw.contains(";"), !raw.contains("|"), !raw.contains("@") else { return nil }
        let parts = raw.split(separator: " ")
        guard let first = parts.first, let value = Double(first), value.isFinite, value > 0 else { return nil }
        let unit = parts.dropFirst().joined(separator: " ")
        let multiplier: Double
        switch unit {
        case "mph": multiplier = 0.44704
        case "", "km/h", "kph", "kmh": multiplier = 1 / 3.6
        case "knots": multiplier = 0.514444
        default: return nil
        }
        let speed = value * multiplier
        return speed <= 60 ? speed : nil
    }

    static func estimatedSpeed(for highway: String) -> Double {
        let mph: Double
        switch highway {
        case "motorway": mph = 65
        case "trunk": mph = 55
        case "primary": mph = 45
        case "secondary": mph = 35
        case "tertiary", "unclassified": mph = 30
        case "motorway_link", "trunk_link": mph = 35
        case "primary_link", "secondary_link", "tertiary_link", "residential": mph = 25
        case "service": mph = 15
        case "living_street": mph = 10
        default: mph = 30
        }
        return mph * 0.44704
    }

    /// Stable per-route sampling keeps partial results, retries and ETA updates
    /// consistent. 0% is always green and 100% always red.
    static func delay(routeID: UUID, signalID: Int64, visit: Int, probability: Double) -> Double {
        var state: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(routeID.uuidString):\(signalID):\(visit)".utf8 { state = (state ^ UInt64(byte)) &* 1_099_511_628_211 }
        func next() -> Double {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return Double(z ^ (z >> 31)) / Double(UInt64.max)
        }
        let probability = probability.isFinite ? min(1, max(0, probability)) : 0.5
        let red = next() < probability || probability == 1
        return red ? Double(5 + min(85, Int(next() * 86))) : 0
    }

    static func queryPoints(_ geometry: RouteGeometry, from start: Double, to end: Double) -> [CLLocationCoordinate2D] {
        guard let first = geometry.coordinate(at: start), let last = geometry.coordinate(at: end) else { return [] }
        var points = [first]
        for (point, distance) in zip(geometry.points, geometry.distances) where distance > start && distance < end { points.append(point) }
        points.append(last)
        // Ramer-Douglas-Peucker retains bends within 10 m instead of cutting
        // corners with equally-spaced samples.
        let plane = Plane(reference: first)
        let xy = points.map(plane.point)
        var keep = Set([0, points.count - 1])
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var farthest = 0.0, index = a
            for i in (a + 1)..<b {
                let offset = project(xy[i], onto: xy[a], xy[b]).offset
                if offset > farthest { farthest = offset; index = i }
            }
            if farthest > 10 { keep.insert(index); stack.append((a,index)); stack.append((index,b)) }
        }
        return keep.sorted().map { points[$0] }
    }

    private static func project(_ p: XY, onto a: XY, _ b: XY) -> (fraction: Double, offset: Double) {
        let dx = b.x - a.x, dy = b.y - a.y
        let squared = dx * dx + dy * dy
        let fraction = squared > 0 ? min(1, max(0, ((p.x-a.x)*dx + (p.y-a.y)*dy) / squared)) : 0
        return (fraction, hypot(p.x - (a.x + fraction * dx), p.y - (a.y + fraction * dy)))
    }

    /// Overpass returns whole ways, including geometry well outside the queried
    /// corridor. Clip before subdivision so long or irrelevant remote edges
    /// cannot allocate a world-sized spatial index.
    private static func clip(_ a: XY, _ b: XY, minimum: XY, maximum: XY) -> (XY, XY)? {
        var lower = 0.0, upper = 1.0
        for (origin, delta, minimum, maximum) in [
            (a.x, b.x - a.x, minimum.x, maximum.x),
            (a.y, b.y - a.y, minimum.y, maximum.y)
        ] {
            if delta == 0 {
                guard origin >= minimum, origin <= maximum else { return nil }
            } else {
                let first = (minimum - origin) / delta, second = (maximum - origin) / delta
                lower = max(lower, min(first, second))
                upper = min(upper, max(first, second))
                guard lower <= upper else { return nil }
            }
        }
        return (XY(x: a.x + (b.x - a.x) * lower, y: a.y + (b.y - a.y) * lower),
                XY(x: a.x + (b.x - a.x) * upper, y: a.y + (b.y - a.y) * upper))
    }

    private static func validCoordinate(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite
            && CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude))
    }

    static func makeResult(route: PlannedRoute, elements: [RoadMetadataElement], coverageEnd: Double,
                           probability: Double, includeTrafficLights: Bool) -> TrafficLightPlanResult {
        let geometry = RouteGeometry(route.coordinates)
        guard let origin = geometry.points.first else { return .init(route: route, notice: "No route.", signalCount: 0) }
        let plane = Plane(reference: origin)
        let routeXY = geometry.points.map(plane.point)
        let end = coverageEnd.isFinite ? max(0, min(geometry.length, coverageEnd)) : 0
        var coveredPoints = zip(routeXY, geometry.distances).prefix { $0.1 <= end }.map(\.0)
        if let endpoint = geometry.coordinate(at: end) { coveredPoints.append(plane.point(endpoint)) }
        let minimum = XY(x: (coveredPoints.map(\.x).min() ?? 0) - 50,
                         y: (coveredPoints.map(\.y).min() ?? 0) - 50)
        let maximum = XY(x: (coveredPoints.map(\.x).max() ?? 0) + 50,
                         y: (coveredPoints.map(\.y).max() ?? 0) + 50)
        let cellSize = 120.0
        func cell(_ point: XY) -> Cell { Cell(x: Int(floor(point.x / cellSize)), y: Int(floor(point.y / cellSize))) }
        var roadPieces: [RoadPiece] = []
        var roadGrid: [Cell: [Int]] = [:]
        var nodeWays: [Int64: Set<Int64>] = [:]
        for element in elements where element.type == "way" {
            guard let points = element.geometry, let tags = element.tags, tags["highway"] != nil,
                  points.allSatisfy({ validCoordinate(latitude: $0.lat, longitude: $0.lon) }) else { continue }
            for node in element.nodes ?? [] { nodeWays[node, default: []].insert(element.id) }
            for (a, b) in zip(points, points.dropFirst()) {
                let (rawStart, rawEnd) = plane.edge(from: a, to: b)
                guard let (start, end) = clip(rawStart, rawEnd, minimum: minimum, maximum: maximum) else { continue }
                let count = max(1, min(2_000, Int(ceil(hypot(end.x-start.x,end.y-start.y) / 100))))
                // Split long ways into small pieces to keep spatial matching local.
                for part in 0..<count {
                    let f = Double(part)/Double(count), g = Double(part+1)/Double(count)
                    let aa = XY(x:start.x+(end.x-start.x)*f,y:start.y+(end.y-start.y)*f)
                    let bb = XY(x:start.x+(end.x-start.x)*g,y:start.y+(end.y-start.y)*g)
                    let index=roadPieces.count
                    roadPieces.append(.init(a:aa,b:bb,tags:tags,wayID:element.id))
                    let ca=cell(aa), cb=cell(bb)
                    for x in min(ca.x,cb.x)...max(ca.x,cb.x) { for y in min(ca.y,cb.y)...max(ca.y,cb.y) { roadGrid[Cell(x:x,y:y),default:[]].append(index) } }
                }
            }
        }
        var profile: [RouteSpeedSegment] = []
        var matchedRoads: [Int: (id: Int64, highway: String)] = [:]
        var distance=0.0
        while distance < end {
            let next=min(end,distance+30), middle=(distance+next)/2
            guard let c=geometry.coordinate(at:middle), let ca=geometry.coordinate(at:distance), let cb=geometry.coordinate(at:next) else { break }
            let p=plane.point(c), a=plane.point(ca), b=plane.point(cb), center=cell(p)
            let dx=b.x-a.x, dy=b.y-a.y, routeLength=max(0.001,hypot(dx,dy))
            var best: (score:Double,tags:[String:String],forward:Bool,wayID:Int64)?
            var visited=Set<Int>()
            for x in (center.x-1)...(center.x+1) { for y in (center.y-1)...(center.y+1) {
                for index in roadGrid[Cell(x:x,y:y)] ?? [] where visited.insert(index).inserted {
                    let road=roadPieces[index], projection=project(p,onto:road.a,road.b)
                    guard projection.offset < 28 else { continue }
                    let rx=road.b.x-road.a.x, ry=road.b.y-road.a.y
                    let dot=(dx*rx+dy*ry)/(routeLength*max(0.001,hypot(rx,ry)))
                    guard abs(dot) > 0.72 else { continue }
                    if ["yes","1","true"].contains(road.tags["oneway"] ?? ""), dot < 0 { continue }
                    if road.tags["highway"] == "motorway", road.tags["oneway"] == nil, dot < 0 { continue }
                    if road.tags["oneway"] == "-1", dot > 0 { continue }
                    let score=projection.offset+(1-abs(dot))*20
                    if best == nil || score < best!.score { best=(score,road.tags,dot>=0,road.wayID) }
                }
            } }
            if let match=best {
                matchedRoads[Int(distance/30)] = (match.wayID,match.tags["highway"] ?? "")
                let directional=match.tags[match.forward ? "maxspeed:forward" : "maxspeed:backward"]
                let known=parseSpeed(directional ?? match.tags["maxspeed"])
                let speed=known ?? estimatedSpeed(for:match.tags["highway"] ?? "")
                let segment=RouteSpeedSegment(startDistance:distance,endDistance:next,metersPerSecond:speed,isEstimated:known==nil)
                if let previous=profile.last, abs(previous.endDistance-distance)<0.01,
                   abs(previous.metersPerSecond-speed)<0.001, previous.isEstimated==segment.isEstimated {
                    profile[profile.count-1].endDistance=next
                } else { profile.append(segment) }
            }
            distance=next
        }
        var candidates: [(distance:Double,id:Int64)] = []
        if includeTrafficLights {
            for element in elements where element.type == "node" && element.tags?["highway"] == "traffic_signals" {
                guard let lat=element.lat, let lon=element.lon,
                      validCoordinate(latitude: lat, longitude: lon) else { continue }
                let point=plane.point(.init(latitude:lat,longitude:lon))
                var visits: [(Double,Double)] = []
                for index in 1..<routeXY.count {
                    let hit=project(point,onto:routeXY[index-1],routeXY[index])
                    guard hit.offset <= 24 else { continue }
                    let along=geometry.distances[index-1]+hit.fraction*(geometry.distances[index]-geometry.distances[index-1])
                    guard along>8,along<end-8 else { continue }
                    if let road=matchedRoads[Int(along/30)] {
                        if let ways=nodeWays[element.id], !ways.contains(road.id) { continue }
                        if road.highway == "motorway", nodeWays[element.id]?.contains(road.id) != true { continue }
                    }
                    if let previous=visits.last, abs(previous.0-along)<50 {
                        if hit.offset<previous.1 { visits[visits.count-1]=(along,hit.offset) }
                    } else { visits.append((along,hit.offset)) }
                }
                candidates.append(contentsOf:visits.map { ($0.0,element.id) })
            }
        }
        candidates.sort { $0.distance == $1.distance ? $0.id<$1.id : $0.distance<$1.distance }
        var grouped: [(distance:Double,id:Int64)] = []
        for candidate in candidates {
            if let previous=grouped.last, candidate.distance-previous.distance<40 { continue }
            grouped.append(candidate)
        }
        var updated=route
        updated.speedSegments=profile
        updated.trafficLights=grouped.map { signal in
            .init(distance:signal.distance,delaySeconds:delay(routeID:route.id,signalID:signal.id,visit:Int((signal.distance/100).rounded()),probability:probability))
        }
        let known=profile.filter { !$0.isEstimated }.reduce(0) { $0+$1.endDistance-$1.startDistance }
        let partial=end+1<geometry.length
        let percent=end>0 ? Int((known/end*100).rounded()) : 0
        let notice="\(partial ? "Partial road details" : "Road details ready") · \(percent)% mapped limits" + (includeTrafficLights ? " · \(grouped.count) mapped lights" : "") + ". Other speeds are estimates; light coverage may be incomplete."
        return .init(route:updated,notice:notice,signalCount:grouped.count)
    }
}
