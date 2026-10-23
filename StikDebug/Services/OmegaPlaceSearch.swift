import Combine
import MapKit

@MainActor
final class OmegaPlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published private(set) var suggestions: [MKLocalSearchCompletion] = []
    @Published private(set) var results: [MKMapItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var error: String?
    private let completer = MKLocalSearchCompleter()
    private var search: MKLocalSearch?
    private var debounce: Task<Void, Never>?
    private var requestID = UUID()
    private var query = ""
    private var isResolving = false
    private var region: MKCoordinateRegion?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ text: String, region: MKCoordinateRegion?) {
        cancel()
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.region = region
        guard !query.isEmpty else { return }
        isSearching = true
        let id = requestID
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, self.requestID == id else { return }
            if let region { self.completer.region = region }
            self.completer.queryFragment = self.query
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        Task { @MainActor [weak self] in
            guard let self, !self.query.isEmpty, !self.isResolving, completer.queryFragment == self.query else { return }
            self.suggestions = Array(completer.results.prefix(12))
            self.isSearching = false
            self.error = nil
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, !self.query.isEmpty, !self.isResolving, completer.queryFragment == self.query else { return }
            self.isSearching = false
            self.error = "Suggestions are unavailable. Tap Search to try this place."
        }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        let response = await perform(MKLocalSearch.Request(completion: completion))
        return response?.first
    }

    func submit() async {
        guard !query.isEmpty else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let items = await perform(request), !Task.isCancelled else { return }
        results = items
        suggestions = []
    }

    func cancel() {
        requestID = UUID()
        debounce?.cancel(); search?.cancel(); completer.cancel()
        suggestions = []; results = []; error = nil; isSearching = false
        query = ""; isResolving = false
    }

    private func perform(_ request: MKLocalSearch.Request) async -> [MKMapItem]? {
        search?.cancel(); completer.cancel(); debounce?.cancel()
        isResolving = true
        let id = UUID(); requestID = id
        if let region { request.region = region }
        let operation = MKLocalSearch(request: request)
        search = operation; isSearching = true; error = nil
        defer { if requestID == id { search = nil; isSearching = false; isResolving = false } }
        do {
            let response = try await operation.start()
            guard requestID == id, !Task.isCancelled else { return nil }
            if response.mapItems.isEmpty { error = "No places found. Try a nearby city or street address." }
            return response.mapItems
        } catch {
            guard requestID == id, !Task.isCancelled else { return nil }
            self.error = "Could not find this place. Check your connection and try again."
            return []
        }
    }
}
