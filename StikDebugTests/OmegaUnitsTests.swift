import XCTest
@testable import StikDebug

final class OmegaUnitsTests: XCTestCase {
    func testImperialDistancesUseFeetNearArrivalAndMilesForTravel() {
        XCTAssertEqual(OmegaUnits.imperial.distanceLabel(30.48), "100 ft")
        XCTAssertEqual(OmegaUnits.imperial.distanceLabel(1609.344), "1.0 mi")
        XCTAssertEqual(OmegaUnits.imperial.distanceLabel(0), "0 ft")
    }

    func testMetricDistancesUseMetersThenKilometers() {
        XCTAssertEqual(OmegaUnits.metric.distanceLabel(450), "450 m")
        XCTAssertEqual(OmegaUnits.metric.distanceLabel(1000), "1.0 km")
        XCTAssertEqual(OmegaUnits.metric.distanceLabel(2500), "2.5 km")
    }

    func testChangingUnitsPreservesPhysicalSpeed() {
        let metersPerSecond = 65 / OmegaUnits.imperial.speedMultiplier
        let kilometersPerHour = metersPerSecond * OmegaUnits.metric.speedMultiplier
        XCTAssertEqual(kilometersPerHour, 104.60736, accuracy: 0.00001)
        XCTAssertEqual(kilometersPerHour / OmegaUnits.metric.speedMultiplier, metersPerSecond, accuracy: 0.000001)
    }

    func testInvalidDistancesNeverRenderNegativeOrNonfiniteValues() {
        for distance in [-10, Double.nan, .infinity] {
            XCTAssertEqual(OmegaUnits.imperial.distanceLabel(distance), "0 ft")
            XCTAssertEqual(OmegaUnits.metric.distanceLabel(distance), "0 m")
        }
    }
}
