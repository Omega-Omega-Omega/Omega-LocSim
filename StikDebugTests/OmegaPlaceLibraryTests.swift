import XCTest
import CoreLocation
@testable import StikDebug

@MainActor
final class OmegaPlaceLibraryTests: XCTestCase {
    private func withDefaults(_ work: (UserDefaults) throws -> Void) rethrows {
        let suite = "OmegaPlaceLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try work(defaults)
    }

    func testExistingBookmarksSurvivePinCreationAndRestart() throws {
        try withDefaults { defaults in
            let original = LocationBookmark(name: "Saved park", latitude: 37.33, longitude: -122.03)
            defaults.set(try JSONEncoder().encode([original]), forKey: "locationBookmarks")
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.savePin(kind: .home, place: .init(title: "Home address", coordinate: .init(latitude: 37.4, longitude: -122.1)))
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.bookmarks.first?.id, original.id)
            XCTAssertEqual(reopened.pin(.home)?.placeName, "Home address")
        }
    }

    func testReplacingHomeKeepsOnePinAndPreservesIdentity() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.savePin(kind: .home, place: .init(title: "Old", coordinate: .init(latitude: 37, longitude: -122)))
            let id = library.pin(.home)?.id
            library.savePin(kind: .home, place: .init(title: "New", coordinate: .init(latitude: 38, longitude: -121)))
            XCTAssertEqual(library.pins.count, 1)
            XCTAssertEqual(library.pin(.home)?.id, id)
            XCTAssertEqual(library.pin(.home)?.latitude, 38)
        }
    }

    func testSaveDeduplicatesSameCoordinateAndDeletePersists() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            let point = SimulationStop(title: "Park", coordinate: .init(latitude: 37, longitude: -122))
            library.saveBookmark(point); library.saveBookmark(point)
            XCTAssertEqual(library.bookmarks.count, 1)
            library.removeBookmarks(at: IndexSet(integer: 0))
            XCTAssertTrue(OmegaPlaceLibrary(defaults: defaults).bookmarks.isEmpty)
        }
    }

    func testCorruptStorageAndInvalidCoordinatesDoNotCrashOrPersist() {
        withDefaults { defaults in
            defaults.set(Data("broken".utf8), forKey: "omegaPinnedPlaces")
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.savePin(kind: .work, place: .init(title: "Bad", coordinate: .init(latitude: 200, longitude: 0)))
            library.saveBookmark(.init(title: "Bad", coordinate: .init(latitude: .nan, longitude: 0)))
            XCTAssertTrue(library.pins.isEmpty)
            XCTAssertTrue(library.bookmarks.isEmpty)
        }
    }
}
