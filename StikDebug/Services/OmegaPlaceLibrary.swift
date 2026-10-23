import Foundation
import CoreLocation
import Combine

enum OmegaPinKind: String, Codable, CaseIterable, Identifiable {
    case home, school, work, custom
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .school: return "graduationcap.fill"
        case .work: return "briefcase.fill"
        case .custom: return "mappin.and.ellipse"
        }
    }
}

struct OmegaPinnedPlace: Identifiable, Codable {
    var id = UUID()
    var kind: OmegaPinKind
    var name: String
    var placeName: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

@MainActor
final class OmegaPlaceLibrary: ObservableObject {
    @Published private(set) var pins: [OmegaPinnedPlace] = []
    @Published private(set) var bookmarks: [LocationBookmark] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "omegaPinnedPlaces"),
           let values = try? JSONDecoder().decode([OmegaPinnedPlace].self, from: data) {
            pins = values.filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        }
        if let data = defaults.data(forKey: "locationBookmarks"),
           let values = try? JSONDecoder().decode([LocationBookmark].self, from: data) {
            bookmarks = values.filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        }
    }

    func pin(_ kind: OmegaPinKind) -> OmegaPinnedPlace? { pins.first { $0.kind == kind } }

    func savePin(kind: OmegaPinKind, name: String? = nil, place: SimulationStop, replacing id: UUID? = nil) {
        guard CLLocationCoordinate2DIsValid(place.coordinate) else { return }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        var pin = OmegaPinnedPlace(kind: kind,
            name: (name?.isEmpty == false ? name! : kind == .custom ? place.title : kind.title),
            placeName: place.title, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        if let index = pins.firstIndex(where: { $0.id == id || (kind != .custom && $0.kind == kind) }) {
            pin.id = pins[index].id
            pins[index] = pin
        } else { pins.append(pin) }
        persist()
    }

    func renamePin(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = pins.firstIndex(where: { $0.id == id }) else { return }
        pins[index].name = name
        persist()
    }

    func removePin(_ id: UUID) { pins.removeAll { $0.id == id }; persist() }

    func saveBookmark(_ place: SimulationStop) {
        guard CLLocationCoordinate2DIsValid(place.coordinate) else { return }
        guard !bookmarks.contains(where: {
            abs($0.latitude - place.coordinate.latitude) < 0.000001 && abs($0.longitude - place.coordinate.longitude) < 0.000001
        }) else { return }
        bookmarks.append(.init(name: place.title, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
        persist()
    }

    func renameBookmark(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[index].name = name
        persist()
    }

    func removeBookmarks(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) where bookmarks.indices.contains(index) { bookmarks.remove(at: index) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: "omegaPinnedPlaces") }
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: "locationBookmarks") }
    }
}
