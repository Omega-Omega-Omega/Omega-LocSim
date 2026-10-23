import XCTest
import CoreLocation
@testable import StikDebug

final class RoadMetadataTests: XCTestCase {
    private func route(_ points: [CLLocationCoordinate2D]) -> PlannedRoute {
        .init(coordinates:points,stopDistances:[RouteGeometry(points).length],stops:[
            .init(title:"Start",coordinate:points.first!),.init(title:"End",coordinate:points.last!)])
    }
    private func decode(_ text: String) throws -> [RoadMetadataElement] {
        try JSONDecoder().decode(RoadMetadataResponse.self,from:Data(text.utf8)).elements
    }

    func testSpeedUnitsAndUnknownRestrictions() {
        XCTAssertEqual(RoadMetadataMatcher.parseSpeed("65 mph")!,29.0576,accuracy:0.0001)
        XCTAssertEqual(RoadMetadataMatcher.parseSpeed("90")!,25,accuracy:0.0001)
        XCTAssertEqual(RoadMetadataMatcher.parseSpeed("50 km/h")!,50/3.6,accuracy:0.0001)
        for value in ["signals","none","US:urban","50;70","30 @ (school)","nan","-5","5000 mph"] {
            XCTAssertNil(RoadMetadataMatcher.parseSpeed(value),value)
        }
        XCTAssertGreaterThan(RoadMetadataMatcher.estimatedSpeed(for:"motorway"),RoadMetadataMatcher.estimatedSpeed(for:"residential"))
    }

    func testStableProbabilityEndpointsAndWaitRange() {
        let id=UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
        var red=0
        for signal in Int64(0)..<1000 {
            XCTAssertEqual(RoadMetadataMatcher.delay(routeID:id,signalID:signal,visit:0,probability:0),0)
            let forced=RoadMetadataMatcher.delay(routeID:id,signalID:signal,visit:0,probability:1)
            XCTAssertTrue((5...90).contains(forced))
            let sampled=RoadMetadataMatcher.delay(routeID:id,signalID:signal,visit:0,probability:0.5)
            XCTAssertEqual(sampled,RoadMetadataMatcher.delay(routeID:id,signalID:signal,visit:0,probability:0.5))
            if sampled>0 { red+=1; XCTAssertTrue((5...90).contains(sampled)) }
        }
        XCTAssertTrue((430...570).contains(red),"Fixed-seed sampling should remain close to 50 percent, got \(red)")
    }

    func testWayDirectionAndMappedLightsProduceStableProfile() throws {
        let points=[CLLocationCoordinate2D(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)]
        let source=route(points)
        let elements=try decode("""
        {"elements":[
          {"type":"way","id":1,"nodes":[10,11,12],"tags":{"highway":"primary","maxspeed:forward":"45 mph","maxspeed:backward":"25 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.99}]},
          {"type":"node","id":11,"lat":37,"lon":-121.995,"tags":{"highway":"traffic_signals"}},
          {"type":"node","id":12,"lat":37,"lon":-121.9949,"tags":{"highway":"traffic_signals"}}
        ]}
        """)
        let result=RoadMetadataMatcher.makeResult(route:source,elements:elements,coverageEnd:source.distance,probability:1,includeTrafficLights:true)
        XCTAssertEqual(result.route.id,source.id)
        XCTAssertEqual(result.signalCount,1,"Two signals at one junction must not double-wait")
        XCTAssertEqual(result.route.speedSegments.first!.metersPerSecond,45*0.44704,accuracy:0.001)
        XCTAssertFalse(result.route.speedSegments.first!.isEstimated)
        let again=RoadMetadataMatcher.makeResult(route:source,elements:elements,coverageEnd:source.distance,probability:1,includeTrafficLights:true)
        XCTAssertEqual(result.route.trafficLights.map(\.delaySeconds),again.route.trafficLights.map(\.delaySeconds))
        let reversed=route(Array(points.reversed()))
        let backwards=RoadMetadataMatcher.makeResult(route:reversed,elements:elements,coverageEnd:reversed.distance,probability:0,includeTrafficLights:true)
        XCTAssertEqual(backwards.route.speedSegments.first!.metersPerSecond,25*0.44704,accuracy:0.001)
    }

    func testCrossingRoadSignalDoesNotStopHighway() throws {
        let source=route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)])
        let elements=try decode("""
        {"elements":[
          {"type":"way","id":1,"nodes":[100,101],"tags":{"highway":"motorway","maxspeed":"65 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.99}]},
          {"type":"way","id":2,"nodes":[20,21,22],"tags":{"highway":"secondary","maxspeed":"35 mph"},"geometry":[{"lat":36.999,"lon":-121.995},{"lat":37.001,"lon":-121.995}]},
          {"type":"node","id":21,"lat":37,"lon":-121.995,"tags":{"highway":"traffic_signals"}}
        ]}
        """)
        let result=RoadMetadataMatcher.makeResult(route:source,elements:elements,coverageEnd:source.distance,probability:1,includeTrafficLights:true)
        XCTAssertEqual(result.signalCount,0)
        XCTAssertEqual(result.route.speedSegments.first!.metersPerSecond,65*0.44704,accuracy:0.001)
    }

    func testMissingSpeedUsesMarkedRoadClassEstimate() throws {
        let source=route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)])
        let elements=try decode("""
        {"elements":[{"type":"way","id":1,"tags":{"highway":"motorway"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.99}]}]}
        """)
        let result=RoadMetadataMatcher.makeResult(route:source,elements:elements,coverageEnd:source.distance,probability:1,includeTrafficLights:false)
        XCTAssertTrue(result.route.speedSegments.allSatisfy(\.isEstimated))
        XCTAssertEqual(result.route.speedSegments.first!.metersPerSecond,65*0.44704,accuracy:0.001)
        XCTAssertTrue(result.notice.contains("0% mapped limits"))
    }

    func testQuerySimplificationKeepsBothBendsAndEndpoints() {
        let points=[CLLocationCoordinate2D(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.998),.init(latitude:37.002,longitude:-121.998),.init(latitude:37.002,longitude:-121.996),.init(latitude:37.004,longitude:-121.996)]
        let geometry=RouteGeometry(points)
        let selected=RoadMetadataMatcher.queryPoints(geometry,from:0,to:geometry.length)
        XCTAssertEqual(selected.count,points.count)
        XCTAssertEqual(selected.first!.longitude,points.first!.longitude)
        XCTAssertEqual(selected.last!.latitude,points.last!.latitude)
    }

    func testInvalidRemoteGeometryIsIgnoredWithoutCrashingOrReplacingValidLimits() throws {
        let source = route([.init(latitude:37,longitude:-122), .init(latitude:37,longitude:-121.99)])
        var elements = try decode("""
        {"elements":[
          {"type":"way","id":1,"tags":{"highway":"primary","maxspeed":"35 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.99}]},
          {"type":"way","id":2,"tags":{"highway":"motorway","maxspeed":"80 mph"},"geometry":[{"lat":1e100,"lon":-122},{"lat":37,"lon":-121.99}]},
          {"type":"way","id":3,"tags":{"highway":"motorway","maxspeed":"80 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":500}]},
          {"type":"node","id":9,"lat":1e100,"lon":-121.995,"tags":{"highway":"traffic_signals"}}
        ]}
        """)
        elements.append(.init(type: "way", id: 4, tags: ["highway":"primary"],
                              geometry: [.init(lat: .nan, lon: -122), .init(lat: 37, lon: -121.99)]))
        let result = RoadMetadataMatcher.makeResult(route:source, elements:elements, coverageEnd:source.distance,
                                                    probability:1, includeTrafficLights:true)
        XCTAssertEqual(result.signalCount, 0)
        XCTAssertFalse(result.route.speedSegments.isEmpty)
        XCTAssertTrue(result.route.speedSegments.allSatisfy { !$0.isEstimated && abs($0.metersPerSecond - 35 * 0.44704) < 0.001 })
    }

    func testWholeRemoteWayIsClippedToCoveredRouteRatherThanTruncatedFromDistantStart() throws {
        let source = route([.init(latitude:37,longitude:-122), .init(latitude:37,longitude:-121.99)])
        let elements = try decode("""
        {"elements":[
          {"type":"way","id":1,"tags":{"highway":"primary","maxspeed:forward":"45 mph","maxspeed:backward":"25 mph"},"geometry":[{"lat":37,"lon":-150},{"lat":37,"lon":-90}]},
          {"type":"way","id":2,"tags":{"highway":"motorway","maxspeed":"80 mph"},"geometry":[{"lat":70,"lon":-150},{"lat":70,"lon":-90}]}
        ]}
        """)
        let result = RoadMetadataMatcher.makeResult(route:source, elements:elements, coverageEnd:150,
                                                    probability:1, includeTrafficLights:false)
        XCTAssertFalse(result.route.speedSegments.isEmpty)
        XCTAssertTrue(result.route.speedSegments.allSatisfy { $0.startDistance >= 0 && $0.endDistance <= 150 })
        let profile = RouteSpeedProfile(segments:result.route.speedSegments, length:source.distance)
        XCTAssertEqual(profile.speed(at:75, fallbackSpeed:5), 45 * 0.44704, accuracy:0.001)
        XCTAssertEqual(profile.speed(at:200, fallbackSpeed:5), 5)
        let backwards = route(Array(source.coordinates.reversed()))
        let reversed = RoadMetadataMatcher.makeResult(route:backwards, elements:elements, coverageEnd:150,
                                                      probability:1, includeTrafficLights:false)
        XCTAssertEqual(reversed.route.speedSegments.first?.metersPerSecond ?? 0, 25 * 0.44704, accuracy:0.001)
    }

    func testDistantDateLineEdgeDoesNotCrossUnrelatedRouteWhenClipped() throws {
        let source = route([.init(latitude:0,longitude:0), .init(latitude:0,longitude:0.01)])
        let elements = try decode("""
        {"elements":[{"type":"way","id":1,"tags":{"highway":"motorway","maxspeed":"80 mph"},"geometry":[{"lat":0,"lon":179.9},{"lat":0,"lon":-179.9}]}]}
        """)
        let result = RoadMetadataMatcher.makeResult(route:source, elements:elements, coverageEnd:source.distance,
                                                    probability:1, includeTrafficLights:false)
        XCTAssertTrue(result.route.speedSegments.isEmpty)
    }

    @MainActor
    func testTransientHTTPFailureRetriesThenCachesDecodedRoads() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [502, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var pauses: [Double] = []
        let planner = TrafficLightPlanner(session: session, pause: { pauses.append($0) })
        let source = route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)])
        var updates = 0
        let result = try await planner.enrich(source, probability: 1, onUpdate: { _ in updates += 1 })
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertEqual(pauses, [2])
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(result.signalCount, 1)
        XCTAssertEqual(result.route.speedSegments.first!.metersPerSecond, 35*0.44704, accuracy: 0.001)
        XCTAssertFalse(result.route.speedSegments.first!.isEstimated)
        let sent = fixture.requests.first!
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.host, "overpass-api.de")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(sent.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("OmegaLocSim/") == true)
        _ = try await planner.enrich(source, probability: 1)
        XCTAssertEqual(fixture.requests.count, 2, "Only a successful decoded response should be reused")
    }

    @MainActor
    func testTransientConnectionFailureRetriesThenDecodesRoads() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [URLError.timedOut.rawValue, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var pauses: [Double] = []
        let planner = TrafficLightPlanner(session: session, pause: { pauses.append($0) })
        let result = try await planner.enrich(route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)]), probability: 1)
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertEqual(pauses, [2])
        XCTAssertEqual(result.signalCount, 1)
    }

    @MainActor
    func testRetryBudgetIsBoundedAndDoesNotPublishFailure() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [503, 502, 504])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var pauses: [Double] = []
        let planner = TrafficLightPlanner(session: session, pause: { pauses.append($0) })
        let source = route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)])
        do {
            _ = try await planner.enrich(source, probability: 1, onUpdate: { _ in XCTFail("Failed metadata was published") })
            XCTFail("An exhausted retry budget should fail")
        } catch { XCTAssertTrue(error is RoadMetadataError) }
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertEqual(pauses, [2, 4])
    }

    @MainActor
    func testClientRejectionDoesNotRetry() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [406])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session, pause: { _ in XCTFail("A 406 must not be retried") })
        do {
            _ = try await planner.enrich(route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)]), probability: 1)
            XCTFail("A rejected request should fail")
        } catch { XCTAssertTrue(error is RoadMetadataError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testCancellationDuringBackoffStopsRequestsAndPublication() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [502, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session, pause: { _ in throw CancellationError() })
        do {
            _ = try await planner.enrich(route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)]), probability: 1,
                                        onUpdate: { _ in XCTFail("Cancelled metadata was published") })
            XCTFail("Cancellation during sleep should propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testThirtySecondRateLimitBackoffCancelsImmediately() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [429, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let sleeping = expectation(description: "Rate-limit backoff started")
        let planner = TrafficLightPlanner(session: session, pause: { seconds in
            XCTAssertEqual(seconds, 30)
            sleeping.fulfill()
            try await Task.sleep(for: .seconds(seconds))
        })
        let source = route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)])
        let task = Task { try await planner.enrich(source, probability: 1,
                                                   onUpdate: { _ in XCTFail("Cancelled metadata was published") }) }
        await fulfillment(of: [sleeping], timeout: 2)
        let cancelledAt = Date()
        task.cancel()
        do { _ = try await task.value; XCTFail("A cancelled backoff should fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertLessThan(Date().timeIntervalSince(cancelledAt), 1)
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testFirstChunkPublishesUsablePartialBeforeLaterFailure() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200, 502, 503, 504])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session, pause: { _ in })
        let source = route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.8)])
        var updates: [TrafficLightPlanResult] = []
        do {
            _ = try await planner.enrich(source, probability: 1, onUpdate: { updates.append($0) })
            XCTFail("The later failed chunk should end enrichment")
        } catch { XCTAssertTrue(error is RoadMetadataError) }
        XCTAssertEqual(fixture.requests.count, 4)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.route.id, source.id)
        XCTAssertTrue(updates.first?.notice.contains("Partial road details") == true)
        XCTAssertEqual(updates.first?.signalCount, 1)
        XCTAssertTrue(updates.first?.route.speedSegments.contains(where: { !$0.isEstimated }) == true)
    }

    @MainActor
    func testRateLimitCooldownAndRetryAfterAreRespected() {
        let url = URL(string: "https://overpass-api.de/api/interpreter")!
        func response(_ status: Int, _ header: String? = nil) -> HTTPURLResponse {
            HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: header.map { ["Retry-After": $0] })!
        }
        XCTAssertEqual(TrafficLightPlanner.retryDelay(response: response(429), attempt: 0), 30)
        XCTAssertEqual(TrafficLightPlanner.retryDelay(response: response(503, "12"), attempt: 0), 12)
        XCTAssertNil(TrafficLightPlanner.retryDelay(response: response(429, "120"), attempt: 0))
        XCTAssertNil(TrafficLightPlanner.retryDelay(response: response(502), attempt: 2))
        let now = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(TrafficLightPlanner.retryDelay(response: response(503, "Thu, 01 Jan 1970 00:00:15 GMT"), attempt: 0, now: now), 15)
    }

}


private final class RoadMetadataURLProtocol: URLProtocol {
    final class Fixture {
        let id = UUID().uuidString
        let statuses: [Int]
        private let lock = NSLock()
        private var received: [URLRequest] = []
        init(statuses: [Int]) { self.statuses = statuses }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
        func record(_ request: URLRequest) -> Int {
            lock.lock(); defer { lock.unlock() }
            let status = statuses[min(received.count, statuses.count - 1)]
            received.append(request)
            return status
        }
    }
    private static let lock = NSLock()
    private static var fixtures: [String: Fixture] = [:]
    static func session(for fixture: Fixture) -> URLSession {
        lock.lock(); fixtures[fixture.id] = fixture; lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        configuration.httpAdditionalHeaders = ["X-Omega-Fixture": fixture.id]
        return URLSession(configuration: configuration)
    }
    static func remove(_ fixture: Fixture) { lock.lock(); fixtures[fixture.id] = nil; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "overpass-api.de" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.value(forHTTPHeaderField: "X-Omega-Fixture") ?? ""]
        Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let status = fixture.record(request)
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let body = """
        {"elements":[
          {"type":"way","id":1,"nodes":[10,11,12],"tags":{"highway":"primary","maxspeed":"35 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.995},{"lat":37,"lon":-121.99}]},
          {"type":"node","id":11,"lat":37,"lon":-121.995,"tags":{"highway":"traffic_signals"}}
        ]}
        """
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
