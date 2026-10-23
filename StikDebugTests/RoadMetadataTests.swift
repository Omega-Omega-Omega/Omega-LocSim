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

    func testRetryRefreshPreservesExistingDetailsBeyondFetchedCoverage() throws {
        var source = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.965)])
        source.speedSegments = [
            .init(startDistance: 0, endDistance: 1_000, metersPerSecond: 7),
            .init(startDistance: 1_000, endDistance: 2_500, metersPerSecond: 27),
            .init(startDistance: 2_500, endDistance: source.distance, metersPerSecond: 30)
        ]
        let laterLight = TrafficLightDecision(distance: 2_200, delaySeconds: 30)
        source.trafficLights = [.init(distance: 500, delaySeconds: 20), laterLight]
        source.arrivalDate = Date(timeIntervalSince1970: 10_000)
        let elements = try decode("""
        {"elements":[
          {"type":"way","id":1,"nodes":[10,11,12],"tags":{"highway":"primary","maxspeed":"35 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.995},{"lat":37,"lon":-121.99}]},
          {"type":"node","id":11,"lat":37,"lon":-121.995,"tags":{"highway":"traffic_signals"}}
        ]}
        """)
        let partial = RoadMetadataMatcher.makeResult(route: source, elements: elements, coverageEnd: 1_500,
                                                     probability: 1, includeTrafficLights: true)
        let profile = RouteSpeedProfile(segments: partial.route.speedSegments, length: source.distance)
        XCTAssertEqual(profile.speed(at: 100, fallbackSpeed: 5), 35 * 0.44704, accuracy: 0.001)
        XCTAssertEqual(profile.speed(at: 1_000, fallbackSpeed: 5), 5, "Unmatched fresh coverage uses fallback")
        XCTAssertEqual(profile.speed(at: 2_000, fallbackSpeed: 5), 27)
        XCTAssertEqual(profile.speed(at: 2_700, fallbackSpeed: 5), 30)
        XCTAssertTrue(partial.route.speedSegments.contains { $0.startDistance == 1_500 && $0.endDistance == 2_500 && $0.metersPerSecond == 27 })
        XCTAssertEqual(partial.signalCount, 2)
        XCTAssertTrue(partial.route.trafficLights.contains(laterLight), "The unfetched later light keeps its decision and identity")
        XCTAssertFalse(partial.route.trafficLights.contains { $0.distance == 500 })
        XCTAssertEqual(partial.route.arrivalDate, source.arrivalDate)
        XCTAssertEqual(partial.route.id, source.id)

        let disabled = RoadMetadataMatcher.makeResult(route: source, elements: elements, coverageEnd: 1_500,
                                                      probability: 1, includeTrafficLights: false)
        XCTAssertTrue(disabled.route.trafficLights.isEmpty, "Turning lights off must also remove retained future lights")
    }

    private func publicShortRoute() -> PlannedRoute {
        route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.99)])
    }

    private func decodedQuery(_ body: Data) -> String {
        let encoded = String(decoding: body, as: UTF8.self)
        return URLComponents(string: "https://example.invalid/?" + encoded)?.queryItems?.first(where: { $0.name == "data" })?.value ?? ""
    }

    @MainActor
    func testTransientHTTPFailureSwitchesToApprovedMirrorThenCachesDecodedRoads() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [502, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = publicShortRoute()
        var updates = 0
        let result = try await planner.enrich(source, probability: 1, onUpdate: { _ in updates += 1 })
        XCTAssertEqual(fixture.requests.count, 2)
        XCTAssertEqual(updates, 1)
        XCTAssertEqual(result.signalCount, 1)
        XCTAssertEqual(result.route.speedSegments.first!.metersPerSecond, 35 * 0.44704, accuracy: 0.001)
        XCTAssertFalse(result.route.speedSegments.first!.isEstimated)
        let sent = fixture.requests.first!
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.url?.host, "overpass-api.de")
        XCTAssertEqual(sent.timeoutInterval, 10)
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertTrue(sent.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("OmegaLocSim/") == true)
        let mirrored = fixture.requests[1]
        XCTAssertEqual(mirrored.url?.absoluteString, "https://overpass.private.coffee/api/interpreter")
        XCTAssertEqual(mirrored.httpMethod, sent.httpMethod)
        for header in ["Accept", "Content-Type", "User-Agent"] {
            XCTAssertEqual(mirrored.value(forHTTPHeaderField: header), sent.value(forHTTPHeaderField: header))
        }
        XCTAssertFalse(fixture.bodies[0].isEmpty)
        XCTAssertEqual(fixture.bodies[0], fixture.bodies[1], "Only the approved destination may change")
        XCTAssertTrue(decodedQuery(fixture.bodies[0]).contains("[timeout:8]"))
        _ = try await planner.enrich(source, probability: 1)
        XCTAssertEqual(fixture.requests.count, 2, "Only a successful decoded response should be reused")
    }

    @MainActor
    func testCachedRoadDataCanResampleProbabilityWithoutAnotherNetworkRequest() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = publicShortRoute()
        let green = try await planner.enrich(source, probability: 0)
        let red = try await planner.enrich(source, probability: 1)
        XCTAssertEqual(green.signalCount, 1)
        XCTAssertEqual(green.route.trafficLights.first?.delaySeconds, 0)
        XCTAssertTrue((5...90).contains(red.route.trafficLights.first?.delaySeconds ?? 0))
        XCTAssertEqual(green.route.speedSegments, red.route.speedSegments)
        XCTAssertEqual(fixture.requests.count, 1, "Cache decoded source data, not the previous probability decisions")
    }

    @MainActor
    func testTransientConnectionFailureSwitchesToMirrorThenDecodesRoads() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [URLError.timedOut.rawValue, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let result = try await planner.enrich(publicShortRoute(), probability: 1)
        XCTAssertEqual(fixture.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee"])
        XCTAssertEqual(result.signalCount, 1)
    }

    @MainActor
    func testExhaustedProvidersReturnPromptlyAndCooldownPreventsImmediateNetworkRetry() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [503, URLError.timedOut.rawValue, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var now = Date(timeIntervalSince1970: 10_000)
        let planner = TrafficLightPlanner(session: session, now: { now })
        let source = publicShortRoute()
        let started = Date()
        for expectedDelay in [30.0, 30, 1] {
            if expectedDelay == 1 { now += 29 }
            do {
                _ = try await planner.enrich(source, probability: 1, onUpdate: { _ in XCTFail("Failed metadata was published") })
                XCTFail("Both providers are unavailable")
            } catch let error as RoadMetadataError {
                XCTAssertEqual(error.retryAfter ?? -1, expectedDelay, accuracy: 0.001)
            }
            XCTAssertEqual(fixture.requests.count, 2, "One request per provider; cooldown retry does not send or sleep")
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "Bounded fixture failures must return without an internal retry sleep")
        XCTAssertEqual(fixture.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee"])
        now += 2
        let result = try await planner.enrich(source, probability: 1)
        XCTAssertEqual(result.signalCount, 1)
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertEqual(fixture.requests.last?.url?.host, "overpass-api.de")
    }

    @MainActor
    func testClientRejectionDoesNotRetryOrSuggestAServiceCooldown() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [406])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        do {
            _ = try await planner.enrich(publicShortRoute(), probability: 1)
            XCTFail("A rejected request should fail")
        } catch {
            XCTAssertTrue(error is RoadMetadataError)
            XCTAssertNil((error as? RoadMetadataError)?.retryAfter)
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testCancellationAfterFirstChunkStopsFurtherRequestsAndPublication() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.965)])
        var updates = 0
        var task: Task<TrafficLightPlanResult, Error>?
        task = Task {
            try await planner.enrich(source, probability: 1, onUpdate: { _ in
                updates += 1
                task?.cancel()
            })
        }
        do { _ = try await task!.value; XCTFail("Cancellation after publication must stop the next chunk") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
        XCTAssertEqual(updates, 1)
    }

    @MainActor
    func testFirstSmallChunkPublishesBeforeLaterBoundedFailure() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200, 502, 503])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.965)])
        var updates: [TrafficLightPlanResult] = []
        do {
            _ = try await planner.enrich(source, probability: 1, onUpdate: { updates.append($0) })
            XCTFail("The later failed chunk should end enrichment")
        } catch {
            XCTAssertTrue(error is RoadMetadataError)
            XCTAssertNotNil((error as? RoadMetadataError)?.retryAfter)
        }
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates.first?.route.id, source.id)
        XCTAssertTrue(updates.first?.notice.contains("Partial road details") == true)
        XCTAssertEqual(updates.first?.signalCount, 1)
        XCTAssertTrue(updates.first?.route.speedSegments.contains(where: { !$0.isEstimated }) == true)
        let firstQuery = decodedQuery(fixture.bodies[0])
        let endpoint = RouteGeometry(source.coordinates).coordinate(at: 1_500)!
        let formattedEnd = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), endpoint.latitude, endpoint.longitude)
        XCTAssertTrue(firstQuery.contains(formattedEnd), "First request must stop at the 1.5km route point")
        XCTAssertTrue(fixture.requests.allSatisfy { $0.timeoutInterval == 10 })
        XCTAssertTrue(fixture.bodies.allSatisfy { decodedQuery($0).contains("[timeout:8]") })
    }

    @MainActor
    func testSubsequentCoverageAdvancesInSixKilometerChunks() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200, 200, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.9)])
        let geometry = RouteGeometry(source.coordinates)
        var updates = 0
        _ = try await planner.enrich(source, probability: 1, onUpdate: { _ in updates += 1 })
        XCTAssertEqual(fixture.requests.count, 3)
        XCTAssertEqual(updates, 3)
        for (index, distance) in [1_500.0, 7_500, geometry.length].enumerated() {
            let point = geometry.coordinate(at: distance)!
            let endpoint = String(format: "%.6f,%.6f", locale: Locale(identifier: "en_US_POSIX"), point.latitude, point.longitude)
            XCTAssertTrue(decodedQuery(fixture.bodies[index]).contains(endpoint))
        }
    }

    @MainActor
    func testRuntimeRemarkAndMalformedProviderResponseFailOverWithoutCaching() async throws {
        for body in ["{\"elements\":[],\"remark\":\"runtime error: Query timed out\"}", "<html>Provider unavailable</html>"] {
            let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200, 200], responseBodies: [0: body])
            let session = RoadMetadataURLProtocol.session(for: fixture)
            defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
            let planner = TrafficLightPlanner(session: session)
            let source = publicShortRoute()
            let result = try await planner.enrich(source, probability: 1)
            XCTAssertEqual(result.signalCount, 1)
            XCTAssertEqual(fixture.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee"])
            let cached = try await planner.enrich(source, probability: 1)
            XCTAssertEqual(cached.signalCount, 1)
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    @MainActor
    func testSuccessfulMirrorIsReusedForLaterChunksAndFailsBackAfterPrimaryCooldown() async throws {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [502, 200, 200, 502, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var now = Date(timeIntervalSince1970: 10_000)
        let planner = TrafficLightPlanner(session: session, now: { now })
        var updates: [TrafficLightPlanResult] = []
        let longRoute = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.965)])
        _ = try await planner.enrich(longRoute, probability: 1, onUpdate: { updates.append($0) })
        XCTAssertEqual(updates.count, 2)
        XCTAssertTrue(updates[0].notice.contains("Partial road details"))
        XCTAssertFalse(updates[1].notice.contains("Partial road details"))
        XCTAssertEqual(fixture.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee", "overpass.private.coffee"])
        now += 31
        let otherRoute = route([.init(latitude: 37, longitude: -122), .init(latitude: 37, longitude: -121.991)])
        _ = try await planner.enrich(otherRoute, probability: 1)
        XCTAssertEqual(Array(fixture.requests.suffix(2)).map { $0.url!.host! }, ["overpass.private.coffee", "overpass-api.de"])
        XCTAssertEqual(fixture.requests.count, 5)
    }

    @MainActor
    func testBothHostsRespectLongRetryAfterCooldownAndReportRemainingTime() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [429, 503], responseHeaders: [0: ["Retry-After": "120"], 1: ["Retry-After": "120"]])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        var now = Date(timeIntervalSince1970: 10_000)
        let planner = TrafficLightPlanner(session: session, now: { now })
        let source = publicShortRoute()
        for expectedDelay in [120.0, 80] {
            do {
                _ = try await planner.enrich(source, probability: 1, onUpdate: { _ in XCTFail("Failed metadata was published") })
                XCTFail("Both providers are cooling down")
            } catch {
                XCTAssertEqual((error as? RoadMetadataError)?.retryAfter ?? -1, expectedDelay, accuracy: 0.001)
            }
            now += 40
        }
        XCTAssertEqual(fixture.requests.map { $0.url!.host! }, ["overpass-api.de", "overpass.private.coffee"])
    }

    @MainActor
    func testRetryAfterDateAndShortHeaderRespectThirtySecondMinimumWithoutSleeping() async {
        for (header, expectedDelay) in [("12", 30.0), ("Thu, 01 Jan 1970 00:02:00 GMT", 120.0), ("invalid", 30.0)] {
            let fixture = RoadMetadataURLProtocol.Fixture(statuses: [503, 503], responseHeaders: [0: ["Retry-After": header], 1: ["Retry-After": header]])
            let session = RoadMetadataURLProtocol.session(for: fixture)
            defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
            let planner = TrafficLightPlanner(session: session, now: { Date(timeIntervalSince1970: 0) })
            do { _ = try await planner.enrich(publicShortRoute(), probability: 1); XCTFail("Both providers failed") }
            catch { XCTAssertEqual((error as? RoadMetadataError)?.retryAfter ?? -1, expectedDelay, accuracy: 0.001) }
            XCTAssertEqual(fixture.requests.count, 2)
        }
    }

    @MainActor
    func testOfflineFailureOffersDelayedRecovery() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [URLError.notConnectedToInternet.rawValue, URLError.notConnectedToInternet.rawValue])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        do {
            _ = try await planner.enrich(route([.init(latitude:37,longitude:-122),.init(latitude:37,longitude:-121.99)]), probability: 1)
            XCTFail("An offline route must retain fallback and schedule recovery")
        } catch {
            XCTAssertNotNil((error as? RoadMetadataError)?.retryAfter)
            XCTAssertGreaterThan((error as? RoadMetadataError)?.retryAfter ?? 0, 29)
        }
        XCTAssertEqual(fixture.requests.count, 2)
    }

    @MainActor
    func testURLCancellationNeverTriggersFailover() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [URLError.cancelled.rawValue, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        do {
            _ = try await planner.enrich(publicShortRoute(), probability: 1,
                                        onUpdate: { _ in XCTFail("Cancelled metadata was published") })
            XCTFail("Cancellation must propagate")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(fixture.requests.count, 1)
    }

    @MainActor
    func testAlreadyCancelledTaskSendsNoProviderRequest() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        let source = publicShortRoute()
        let task = Task { try await planner.enrich(source, probability: 1,
                                                   onUpdate: { _ in XCTFail("Cancelled metadata was published") }) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(fixture.requests.isEmpty)
    }

    @MainActor
    func testCertificateFailureIsNotBypassedWithFallback() async {
        let fixture = RoadMetadataURLProtocol.Fixture(statuses: [URLError.serverCertificateUntrusted.rawValue, 200])
        let session = RoadMetadataURLProtocol.session(for: fixture)
        defer { session.invalidateAndCancel(); RoadMetadataURLProtocol.remove(fixture) }
        let planner = TrafficLightPlanner(session: session)
        do {
            _ = try await planner.enrich(publicShortRoute(), probability: 1)
            XCTFail("Certificate failure must end the request")
        } catch {
            XCTAssertTrue(error is RoadMetadataError)
            XCTAssertNil((error as? RoadMetadataError)?.retryAfter)
        }
        XCTAssertEqual(fixture.requests.count, 1)
    }

}


private final class RoadMetadataURLProtocol: URLProtocol {
    final class Fixture {
        let id = UUID().uuidString
        let statuses: [Int]
        let responseBodies: [Int: String]
        let responseHeaders: [Int: [String: String]]
        private let lock = NSLock()
        private var received: [URLRequest] = []
        private var receivedBodies: [Data] = []
        init(statuses: [Int], responseBodies: [Int: String] = [:], responseHeaders: [Int: [String: String]] = [:]) {
            self.statuses = statuses
            self.responseBodies = responseBodies
            self.responseHeaders = responseHeaders
        }
        var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return received }
        var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return receivedBodies }
        func record(_ request: URLRequest) -> (status: Int, body: String?, headers: [String: String]) {
            lock.lock(); defer { lock.unlock() }
            let index = received.count
            let status = statuses[min(index, statuses.count - 1)]
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            received.append(request)
            receivedBodies.append(body)
            return (status, responseBodies[index], responseHeaders[index] ?? [:])
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
    override class func canInit(with request: URLRequest) -> Bool {
        ["overpass-api.de", "overpass.private.coffee"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let fixture = Self.fixtures[request.value(forHTTPHeaderField: "X-Omega-Fixture") ?? ""]
        Self.lock.unlock()
        guard let fixture else { client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return }
        let result = fixture.record(request)
        let status = result.status
        if status < 0 {
            client?.urlProtocol(self, didFailWithError: URLError(URLError.Code(rawValue: status)))
            return
        }
        let body = result.body ?? """
        {"elements":[
          {"type":"way","id":1,"nodes":[10,11,12],"tags":{"highway":"primary","maxspeed":"35 mph"},"geometry":[{"lat":37,"lon":-122},{"lat":37,"lon":-121.995},{"lat":37,"lon":-121.99}]},
          {"type":"node","id":11,"lat":37,"lon":-121.995,"tags":{"highway":"traffic_signals"}}
        ]}
        """
        let headers = ["Content-Type": "application/json"].merging(result.headers) { _, value in value }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
