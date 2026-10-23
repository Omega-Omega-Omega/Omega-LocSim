import XCTest
import CoreLocation
@testable import StikDebug

@MainActor
final class OmegaPlaceLibraryTests: XCTestCase {
    private func stop(_ title: String, latitude: Double, dwell: TimeInterval = 0) -> SimulationStop {
        .init(title: title, coordinate: .init(latitude: latitude, longitude: -112), dwellSeconds: dwell)
    }

    private var route: [SimulationStop] {
        [stop("Home", latitude: 33), stop("Coffee", latitude: 33.01, dwell: 120), stop("Work", latitude: 33.02)]
    }

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

    func testRecentRoutesAndSpotsPersistWithTheirKindAndOrderedDwell() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordRoute(route, at: Date(timeIntervalSince1970: 100))
            library.recordSpot(stop("Park", latitude: 34, dwell: 90), at: Date(timeIntervalSince1970: 200))
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.recents.map(\.kind), [.place, .route])
            XCTAssertEqual(reopened.recents.map(\.title), ["Park", "Work"])
            XCTAssertEqual(reopened.recents[0].place?.dwellSeconds, 0)
            XCTAssertNil(reopened.recents[1].place)
            XCTAssertEqual(reopened.recents[1].simulationStops.map(\.title), ["Home", "Coffee", "Work"])
            XCTAssertEqual(reopened.recents[1].simulationStops.map(\.dwellSeconds), [0, 120, 0])
            XCTAssertEqual(reopened.recents[1].simulationStops.map(\.coordinate.latitude), [33, 33.01, 33.02])
            XCTAssertEqual(reopened.recents[1].subtitle, "From Home · 2 stops")
        }
    }

    func testDeduplicatingRecentKeepsIdentityAndCustomNameButRefreshesSnapshot() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordRoute(route, at: Date(timeIntervalSince1970: 100))
            let id = library.recents[0].id
            library.renameRecent(id, name: "Morning commute")
            var renamedStops = route
            renamedStops[1].title = "Coffee shop"
            library.recordRoute(renamedStops, at: Date(timeIntervalSince1970: 200))
            XCTAssertEqual(library.recents.count, 1)
            XCTAssertEqual(library.recents[0].id, id)
            XCTAssertEqual(library.recents[0].title, "Morning commute")
            XCTAssertEqual(library.recents[0].occurredAt, Date(timeIntervalSince1970: 200))
            XCTAssertEqual(library.recents[0].simulationStops[1].title, "Coffee shop")
        }
    }

    func testSamePlaceDeduplicatesAcrossNamesAndDifferentKindsRemainDistinct() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordSpot(stop("Park", latitude: 33))
            let id = library.recents[0].id
            library.recordSpot(stop("Marked Location", latitude: 33.0000001))
            library.recordRoute(route)
            XCTAssertEqual(library.recents.count, 2)
            XCTAssertEqual(library.recents.first(where: { $0.kind == .place })?.id, id)
            XCTAssertEqual(library.recents.first(where: { $0.kind == .place })?.title, "Marked Location")
        }
    }

    func testRouteOrderAndDwellDistinguishRecents() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordRoute(route)
            library.recordRoute(Array(route.reversed()))
            var changedDwell = route
            changedDwell[1].dwellSeconds = 300
            library.recordRoute(changedDwell)
            XCTAssertEqual(library.recents.count, 3)
        }
    }

    func testRecentLimitKeepsNewestEntriesAndPersistsDeletes() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            for index in 0..<(OmegaPlaceLibrary.recentLimit + 5) {
                library.recordSpot(stop("Place \(index)", latitude: 30 + Double(index) / 100), at: Date(timeIntervalSince1970: Double(index)))
            }
            XCTAssertEqual(library.recents.count, OmegaPlaceLibrary.recentLimit)
            XCTAssertEqual(library.recents.first?.title, "Place 54")
            XCTAssertEqual(library.recents.last?.title, "Place 5")
            let removed = library.recents[0].id
            library.removeRecent(removed)
            XCTAssertFalse(OmegaPlaceLibrary(defaults: defaults).recents.contains { $0.id == removed })
            library.clearRecents()
            XCTAssertTrue(OmegaPlaceLibrary(defaults: defaults).recents.isEmpty)
        }
    }

    func testSaveRoutePreservesIdentityNameAndStopsAndDoesNotCreateARecent() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            let saved = library.saveRoute(stops: route, name: " Commute ")!
            let again = library.saveRoute(stops: route)!
            XCTAssertEqual(saved.id, again.id)
            XCTAssertEqual(again.name, "Commute")
            XCTAssertEqual(library.savedRoutes.count, 1)
            XCTAssertTrue(library.recents.isEmpty, "Saving and reviewing never imply successful playback")
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.savedRoutes[0].id, saved.id)
            XCTAssertEqual(reopened.savedRoutes[0].simulationStops.map(\.dwellSeconds), [0, 120, 0])
            XCTAssertEqual(reopened.savedRoutes[0].stopCount, 3)
            XCTAssertEqual(reopened.savedRoutes[0].subtitle, "Home → Work")
        }
    }

    func testEditingSavedRouteKeepsItsIDAndRenameAndDeletePersist() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            let saved = library.saveRoute(stops: route, name: "Commute")!
            let changed = [route[0], route[2]]
            let replacement = library.saveRoute(stops: changed, replacing: saved.id)!
            XCTAssertEqual(replacement.id, saved.id)
            XCTAssertEqual(replacement.name, "Commute")
            XCTAssertEqual(replacement.stopCount, 2)
            library.renameSavedRoute(saved.id, name: "Direct commute")
            XCTAssertEqual(OmegaPlaceLibrary(defaults: defaults).savedRoutes.first?.name, "Direct commute")
            library.renameSavedRoute(saved.id, name: "   ")
            XCTAssertEqual(library.savedRoutes.first?.name, "Direct commute")
            library.removeSavedRoute(saved.id)
            XCTAssertTrue(OmegaPlaceLibrary(defaults: defaults).savedRoutes.isEmpty)
        }
    }

    func testSavingRecentRouteKeepsSnapshotIndependentOfRecentDeletion() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordRoute(route, name: "Morning")
            let saved = library.saveRoute(library.recents[0])!
            library.clearRecents()
            XCTAssertEqual(library.savedRoutes[0].id, saved.id)
            XCTAssertEqual(library.savedRoutes[0].name, "Morning")
            library.recordSpot(route[0])
            XCTAssertNil(library.saveRoute(library.recents[0]))
            XCTAssertEqual(library.savedRoutes.count, 1)
        }
    }

    func testInvalidHistoryAndSavedRouteRequestsDoNotMutateStorage() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.recordRoute([])
            library.recordRoute([route[0]])
            library.recordRoute([route[0], stop("Bad wait", latitude: 33.1, dwell: -1)])
            library.recordRoute([route[0], stop("Bad wait", latitude: 33.1, dwell: .infinity)])
            library.recordSpot(stop("Invalid", latitude: 999))
            library.recordRoute(route, at: Date(timeIntervalSinceReferenceDate: .infinity))
            XCTAssertNil(library.saveRoute(stops: [route[0]]))
            XCTAssertNil(library.saveRoute(stops: [route[0], stop("Invalid", latitude: .nan)]))
            XCTAssertTrue(library.recents.isEmpty)
            XCTAssertTrue(library.savedRoutes.isEmpty)
            XCTAssertNil(defaults.data(forKey: "omegaRecentActivities"))
        }
    }

    func testMalformedRecordDoesNotEraseValidNeighborsInAnyCollection() throws {
        try withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.savePin(kind: .home, place: route[0])
            library.saveBookmark(route[1])
            library.recordRoute(route)
            library.saveRoute(stops: route)
            let pinID = library.pins[0].id
            let bookmarkID = library.bookmarks[0].id
            let recentID = library.recents[0].id
            let savedID = library.savedRoutes[0].id
            for key in ["omegaPinnedPlaces", "locationBookmarks", "omegaRecentActivities", "omegaSavedRoutes"] {
                var values = try XCTUnwrap(JSONSerialization.jsonObject(with: defaults.data(forKey: key)!) as? [Any])
                values.insert(["invalid": true], at: 0)
                values.append(NSNull())
                defaults.set(try JSONSerialization.data(withJSONObject: values), forKey: key)
            }
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.pins.map(\.id), [pinID])
            XCTAssertEqual(reopened.bookmarks.map(\.id), [bookmarkID])
            XCTAssertEqual(reopened.recents.map(\.id), [recentID])
            XCTAssertEqual(reopened.savedRoutes.map(\.id), [savedID])
        }
    }

    func testMalformedButDecodableHistoryIsFilteredAndDuplicateIDsAreRemoved() throws {
        try withDefaults { defaults in
            let valid = OmegaRecentActivity(kind: .route, stops: route.map(OmegaStoredStop.init), occurredAt: Date(timeIntervalSince1970: 100))
            var invalidCoordinate = valid
            invalidCoordinate.id = UUID()
            invalidCoordinate.stops[0].latitude = 500
            var invalidKind = valid
            invalidKind.id = UUID()
            invalidKind.kind = .place
            var duplicate = valid
            duplicate.stops[0].latitude = 32
            duplicate.occurredAt = Date(timeIntervalSince1970: 50)
            defaults.set(try JSONEncoder().encode([invalidCoordinate, invalidKind, duplicate, valid]), forKey: "omegaRecentActivities")
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.recents.count, 1)
            XCTAssertEqual(reopened.recents[0].stops[0].latitude, 33)
        }
    }

    func testAllExistingPlaceIDsSurviveUsingNewCollections() {
        withDefaults { defaults in
            let library = OmegaPlaceLibrary(defaults: defaults)
            library.savePin(kind: .school, place: route[0])
            library.saveBookmark(route[1])
            let pinID = library.pins[0].id
            let bookmarkID = library.bookmarks[0].id
            library.recordRoute(route)
            library.saveRoute(stops: route)
            library.clearRecents()
            let reopened = OmegaPlaceLibrary(defaults: defaults)
            XCTAssertEqual(reopened.pins.map(\.id), [pinID])
            XCTAssertEqual(reopened.bookmarks.map(\.id), [bookmarkID])
        }
    }
}
