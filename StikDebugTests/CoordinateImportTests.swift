import XCTest
import CoreLocation
@testable import StikDebug

final class CoordinateImportTests: XCTestCase {
    private func parse(_ text: String, extension suffix: String,
                       encoding: String.Encoding = .utf8) throws -> [CLLocationCoordinate2D] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        defer { try? FileManager.default.removeItem(at: url) }
        try XCTUnwrap(text.data(using: encoding)).write(to: url)
        return try CoordinateImportParser.parse(url: url)
    }

    private func assertCoordinates(_ actual: [CLLocationCoordinate2D], _ expected: [(Double, Double)],
                                   file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (point, pair) in zip(actual, expected) {
            XCTAssertEqual(point.latitude, pair.0, accuracy: 0.0000001, file: file, line: line)
            XCTAssertEqual(point.longitude, pair.1, accuracy: 0.0000001, file: file, line: line)
        }
    }

    func testGPXPreservesTrackRouteAndWaypointOrder() throws {
        let points = try parse("""
        <?xml version="1.0"?><gpx version="1.1">
        <wpt lat="37.3" lon="-122.1"/><rte><rtept lat="37.4" lon="-122.2"/></rte>
        <trk><trkseg><trkpt lat="37.5" lon="-122.3"><ele>88</ele><time>2026-10-23</time></trkpt></trkseg></trk>
        </gpx>
        """, extension: "gpx")
        assertCoordinates(points, [(37.3, -122.1), (37.4, -122.2), (37.5, -122.3)])
    }

    func testNamespacedGPXAndKMLAreRecognized() throws {
        let gpx = try parse(#"<g:gpx xmlns:g="http://www.topografix.com/GPX/1/1"><g:trkpt lat="37.3" lon="-122.1"/></g:gpx>"#, extension: "xml")
        let kml = try parse(#"<k:kml xmlns:k="http://www.opengis.net/kml/2.2"><k:LineString><k:coordinates>-122.1,37.3,9 -122.2,37.4,10</k:coordinates></k:LineString></k:kml>"#, extension: "kml")
        assertCoordinates(gpx, [(37.3, -122.1)])
        assertCoordinates(kml, [(37.3, -122.1), (37.4, -122.2)])
    }

    func testGeoJSONUsesLongitudeFirstEvenWhenBothOrdersAreValid() throws {
        let points = try parse(#"{"type":"FeatureCollection","features":[{"type":"Feature","geometry":{"type":"Point","coordinates":[10,20]},"properties":{"number":2026}},{"type":"Feature","geometry":{"type":"LineString","coordinates":[[11,21,5],[12,22,6]]}}]}"#, extension: "geojson")
        assertCoordinates(points, [(20, 10), (21, 11), (22, 12)])
    }

    func testGeoJSONGeometryCollectionAndUnknownFileExtension() throws {
        let points = try parse(#"{"type":"GeometryCollection","geometries":[{"type":"Point","coordinates":[10,20]},{"type":"MultiPoint","coordinates":[[11,21],[12,22]]}]}"#, extension: "txt")
        assertCoordinates(points, [(20, 10), (21, 11), (22, 12)])
    }

    func testGenericJSONSupportsNamedObjectsAndCoordinateArrays() throws {
        let points = try parse(#"[{"latitude":"37.3","longitude":"-122.1"},[37.4,-122.2],{"Lat":37.5,"Lng":-122.3}]"#, extension: "json")
        assertCoordinates(points, [(37.3, -122.1), (37.4, -122.2), (37.5, -122.3)])
    }

    func testCaseVariantJSONKeysDoNotCrashAndPreferCanonicalSpelling() throws {
        let points = try parse(#"{"lat":37.3,"Lat":38.3,"lon":-122.1,"LON":-121.1}"#, extension: "json")
        assertCoordinates(points, [(37.3, -122.1)])
    }

    func testJSONBooleansCannotBecomeCoordinates() throws {
        XCTAssertThrowsError(try parse(#"{"lat":true,"lon":false}"#, extension: "json"))
        XCTAssertThrowsError(try parse("[[true,false]]", extension: "json"))
    }

    func testCSVPreservesEmptyColumnsAndQuotedCommas() throws {
        let points = try parse("""
        name,description,longitude,latitude
        Coffee,,-122.1,37.3
        "Library, main",public,-122.2,37.4
        "Park \"\"North\"\"",,-122.3,37.5
        """, extension: "csv")
        assertCoordinates(points, [(37.3, -122.1), (37.4, -122.2), (37.5, -122.3)])
    }

    func testCSVInvalidNamedColumnsDoNotFallBackToOtherNumbers() throws {
        let points = try parse("name,lat,lon\nStop 88,,10\nStop 99,33,\nGood,34,12", extension: "csv")
        assertCoordinates(points, [(34, 12)])
    }

    func testPlainTextSupportsScientificNotationAndAdjacentDeduplication() throws {
        let points = CoordinateImportParser.parseInline("3.73e1, -1.221E2\n37.3 -122.1\n37.4; -122.2\n999,999\n37.3,-122.1")
        assertCoordinates(points, [(37.3, -122.1), (37.4, -122.2), (37.3, -122.1)])
    }

    func testInvalidStructuredFilesDoNotInventCoordinatesFromNumbers() throws {
        XCTAssertThrowsError(try parse(#"{"version":1,"lat":37.3,"lon":-122.1"#, extension: "json"))
        XCTAssertThrowsError(try parse(#"<?xml version="1.0"?><gpx version="1.1"><trkpt lat="37.3" lon="-122.1">"#, extension: "gpx"))
        XCTAssertThrowsError(try parse(#"<gpx version="1.1"><metadata><time>2026-10-23</time></metadata></gpx>"#, extension: "gpx"))
    }

    func testExplicitLatitudeIsNeverSilentlySwapped() throws {
        XCTAssertThrowsError(try parse(#"{"lat":100,"lon":10}"#, extension: "json"))
        XCTAssertThrowsError(try parse(#"<gpx><trkpt lat="100" lon="10"/></gpx>"#, extension: "gpx"))
        XCTAssertThrowsError(try parse("lat,lon\n100,10", extension: "csv"))
        XCTAssertThrowsError(try parse(#"{"type":"Point","coordinates":[10,100]}"#, extension: "geojson"))
    }

    func testKMLDoesNotSubstituteAltitudeForMissingLatitude() throws {
        XCTAssertThrowsError(try parse("<kml><coordinates>-122.1,,37.3</coordinates></kml>", extension: "kml"))
        XCTAssertThrowsError(try parse("<kml><coordinates>-122.1,bad,37.3</coordinates></kml>", extension: "kml"))
    }

    func testUTF16TextAndEmptyFileHandling() throws {
        assertCoordinates(try parse("37.3,-122.1\n37.4,-122.2", extension: "txt", encoding: .utf16), [(37.3, -122.1), (37.4, -122.2)])
        XCTAssertThrowsError(try parse("", extension: "txt"))
    }
}
