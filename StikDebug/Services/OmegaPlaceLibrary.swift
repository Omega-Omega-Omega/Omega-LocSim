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
    var simulationStop: SimulationStop { .init(title: name, coordinate: coordinate) }
}

/// A destination snapshot, not a cached MapKit route or a command to start playback.
/// Loading a recent or saved route always produces a draft that can be reviewed.
struct OmegaStoredStop: Codable, Equatable {
    var title: String
    var latitude: Double
    var longitude: Double
    var dwellSeconds: TimeInterval

    init(_ stop: SimulationStop) {
        title = stop.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Marked Location" }
        latitude = stop.coordinate.latitude
        longitude = stop.coordinate.longitude
        dwellSeconds = stop.dwellSeconds
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var simulationStop: SimulationStop { .init(title: title, coordinate: coordinate, dwellSeconds: dwellSeconds) }
    fileprivate var isValid: Bool {
        CLLocationCoordinate2DIsValid(coordinate) && dwellSeconds.isFinite && dwellSeconds >= 0
    }
    fileprivate var routeKey: String {
        // Match places within about 11 cm without depending on mutable display names.
        "\(Int64((latitude * 1_000_000).rounded())):\(Int64((longitude * 1_000_000).rounded())):\(dwellSeconds)"
    }
    fileprivate var placeKey: String {
        "\(Int64((latitude * 1_000_000).rounded())):\(Int64((longitude * 1_000_000).rounded()))"
    }
}

struct OmegaRecentActivity: Identifiable, Codable {
    enum Kind: String, Codable { case place, route }
    var id = UUID()
    var kind: Kind
    var name: String?
    var stops: [OmegaStoredStop]
    var occurredAt: Date

    var title: String { name ?? stops.last?.title ?? "Marked Location" }
    var subtitle: String {
        if kind == .place { return "Single location" }
        let origin = stops.first?.title ?? "Starting point"
        return stops.count > 2 ? "From \(origin) · \(stops.count - 1) stops" : "From \(origin)"
    }
    var symbol: String { kind == .route ? "arrow.triangle.turn.up.right.diamond.fill" : "mappin.circle.fill" }
    var stopCount: Int { stops.count }
    var simulationStops: [SimulationStop] { stops.map(\.simulationStop) }
    var place: SimulationStop? { kind == .place ? stops.first?.simulationStop : nil }
    fileprivate var isValid: Bool {
        occurredAt.timeIntervalSinceReferenceDate.isFinite && stops.allSatisfy(\.isValid)
            && (kind == .place ? stops.count == 1 : stops.count >= 2)
    }
    fileprivate var deduplicationKey: String {
        kind.rawValue + ":" + stops.map { kind == .place ? $0.placeKey : $0.routeKey }.joined(separator: "|")
    }
}

struct OmegaSavedRoute: Identifiable, Codable {
    var id = UUID()
    var name: String
    var stops: [OmegaStoredStop]
    var updatedAt: Date

    var title: String { name }
    var subtitle: String {
        let origin = stops.first?.title ?? "Starting point"
        let destination = stops.last?.title ?? "Destination"
        return "\(origin) → \(destination)"
    }
    var stopCount: Int { stops.count }
    var simulationStops: [SimulationStop] { stops.map(\.simulationStop) }
    fileprivate var isValid: Bool {
        stops.count >= 2 && stops.allSatisfy(\.isValid) && updatedAt.timeIntervalSinceReferenceDate.isFinite
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    fileprivate var deduplicationKey: String { stops.map(\.routeKey).joined(separator: "|") }
}

@MainActor
final class OmegaPlaceLibrary: ObservableObject {
    static let recentLimit = 50
    @Published private(set) var pins: [OmegaPinnedPlace] = []
    @Published private(set) var bookmarks: [LocationBookmark] = []
    @Published private(set) var recents: [OmegaRecentActivity] = []
    @Published private(set) var savedRoutes: [OmegaSavedRoute] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Keep the established keys and IDs. A bad record must not discard its valid neighbors.
        pins = Self.decodeRecords(OmegaPinnedPlace.self, from: defaults.data(forKey: "omegaPinnedPlaces"))
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        bookmarks = Self.decodeRecords(LocationBookmark.self, from: defaults.data(forKey: "locationBookmarks"))
            .filter { CLLocationCoordinate2DIsValid($0.coordinate) }
        var recentKeys = Set<String>()
        var recentIDs = Set<UUID>()
        recents = Array(Self.decodeRecords(OmegaRecentActivity.self, from: defaults.data(forKey: "omegaRecentActivities"))
            .filter(\.isValid)
            .sorted { $0.occurredAt > $1.occurredAt }
            .filter { recentKeys.insert($0.deduplicationKey).inserted && recentIDs.insert($0.id).inserted }
            .prefix(Self.recentLimit))
        var savedIDs = Set<UUID>()
        savedRoutes = Self.decodeRecords(OmegaSavedRoute.self, from: defaults.data(forKey: "omegaSavedRoutes"))
            .filter(\.isValid)
            .sorted { $0.updatedAt > $1.updatedAt }
            .filter { savedIDs.insert($0.id).inserted }
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

    func removeBookmark(_ id: UUID) { bookmarks.removeAll { $0.id == id }; persist() }

    /// Call only after the device accepts a stationary spoof. Browsing and failed requests are not history.
    func recordSpot(_ place: SimulationStop, at date: Date = Date()) {
        var stop = OmegaStoredStop(place)
        stop.dwellSeconds = 0
        record(.init(kind: .place, stops: [stop], occurredAt: date))
    }

    /// Call only after playback starts successfully. No departure dates, ETA targets, or geometry are reused.
    func recordRoute(_ stops: [SimulationStop], name: String? = nil, at date: Date = Date()) {
        record(.init(kind: .route, name: Self.nonemptyName(name), stops: stops.map(OmegaStoredStop.init), occurredAt: date))
    }

    func renameRecent(_ id: UUID, name: String) {
        guard let name = Self.nonemptyName(name), let index = recents.firstIndex(where: { $0.id == id }) else { return }
        recents[index].name = name
        persist()
    }

    func removeRecent(_ id: UUID) { recents.removeAll { $0.id == id }; persist() }
    func clearRecents() { recents.removeAll(); persist() }

    @discardableResult
    func saveRoute(stops: [SimulationStop], name: String? = nil, replacing id: UUID? = nil) -> OmegaSavedRoute? {
        let stored = stops.map(OmegaStoredStop.init)
        guard stored.count >= 2, stored.allSatisfy(\.isValid) else { return nil }
        var route = OmegaSavedRoute(name: Self.nonemptyName(name) ?? stored.last!.title, stops: stored, updatedAt: Date())
        // Saving a route again updates its existing card, preserving its identity and chosen name.
        let index = id.flatMap { id in savedRoutes.firstIndex { $0.id == id } }
            ?? savedRoutes.firstIndex { $0.deduplicationKey == route.deduplicationKey }
        if let index {
            route.id = savedRoutes[index].id
            if Self.nonemptyName(name) == nil { route.name = savedRoutes[index].name }
            savedRoutes.remove(at: index)
        }
        savedRoutes.insert(route, at: 0)
        persist()
        return route
    }

    @discardableResult
    func saveRoute(_ recent: OmegaRecentActivity, name: String? = nil) -> OmegaSavedRoute? {
        guard recent.kind == .route, recent.isValid else { return nil }
        return saveRoute(stops: recent.simulationStops, name: Self.nonemptyName(name) ?? recent.name)
    }

    func renameSavedRoute(_ id: UUID, name: String) {
        guard let name = Self.nonemptyName(name), let index = savedRoutes.firstIndex(where: { $0.id == id }) else { return }
        savedRoutes[index].name = name
        persist()
    }

    func removeSavedRoute(_ id: UUID) { savedRoutes.removeAll { $0.id == id }; persist() }

    private func record(_ activity: OmegaRecentActivity) {
        guard activity.isValid else { return }
        var activity = activity
        if let previous = recents.first(where: { $0.deduplicationKey == activity.deduplicationKey }) {
            activity.id = previous.id
            activity.name = activity.name ?? previous.name
        }
        recents.removeAll { $0.id == activity.id }
        recents.append(activity)
        recents.sort { $0.occurredAt > $1.occurredAt }
        recents = Array(recents.prefix(Self.recentLimit))
        persist()
    }

    private static func nonemptyName(_ name: String?) -> String? {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }

    private static func decodeRecords<T: Decodable>(_ type: T.Type, from data: Data?) -> [T] {
        guard let data, let records = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return records.compactMap {
            guard JSONSerialization.isValidJSONObject($0), let data = try? JSONSerialization.data(withJSONObject: $0) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pins) { defaults.set(data, forKey: "omegaPinnedPlaces") }
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: "locationBookmarks") }
        if let data = try? JSONEncoder().encode(recents) { defaults.set(data, forKey: "omegaRecentActivities") }
        if let data = try? JSONEncoder().encode(savedRoutes) { defaults.set(data, forKey: "omegaSavedRoutes") }
    }
}
