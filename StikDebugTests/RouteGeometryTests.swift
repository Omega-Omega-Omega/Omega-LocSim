import CoreLocation
import XCTest
@testable import StikDebug

final class RouteGeometryTests: XCTestCase {
    func testEmptyAndSinglePointRoutesAreSafe() {
        XCTAssertNil(RouteGeometry([]).coordinate(at: 10))
        let point = CLLocationCoordinate2D(latitude: 33.4, longitude: -111.9)
        let geometry = RouteGeometry([point])
        XCTAssertEqual(geometry.length, 0)
        XCTAssertEqual(geometry.coordinate(at: 100)?.latitude, point.latitude)
    }

    func testInterpolationUsesDistanceAndClampsArrival() throws {
        let points = [CLLocationCoordinate2D(latitude: 0, longitude: 0),
                      CLLocationCoordinate2D(latitude: 0, longitude: 0.01),
                      CLLocationCoordinate2D(latitude: 0, longitude: 0.03)]
        let geometry = RouteGeometry(points)
        let halfway = try XCTUnwrap(geometry.coordinate(at: geometry.length / 2))
        XCTAssertEqual(halfway.longitude, 0.015, accuracy: 0.00001)
        XCTAssertEqual(geometry.coordinate(at: -100)?.longitude, 0)
        XCTAssertEqual(geometry.coordinate(at: geometry.length + 100)?.longitude, 0.03)
    }

    func testRepeatedPointsDoNotProduceInvalidCoordinates() throws {
        let a = CLLocationCoordinate2D(latitude: 33, longitude: -112)
        let b = CLLocationCoordinate2D(latitude: 33.01, longitude: -112)
        let geometry = RouteGeometry([a, a, b, b])
        let point = try XCTUnwrap(geometry.coordinate(at: geometry.length * 0.4))
        XCTAssertTrue(point.latitude.isFinite)
        XCTAssertEqual(point.latitude, 33.004, accuracy: 0.00001)
    }

    func testDateLineCrossingTakesTheShortPath() throws {
        let geometry = RouteGeometry([CLLocationCoordinate2D(latitude: 0, longitude: 179.9),
                                      CLLocationCoordinate2D(latitude: 0, longitude: -179.9)])
        let point = try XCTUnwrap(geometry.coordinate(at: geometry.length / 2))
        XCTAssertEqual(abs(point.longitude), 180, accuracy: 0.00001)
        XCTAssertLessThan(geometry.length, 23000)
    }
}
