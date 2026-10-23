import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct LocationSimulationView: View {
    @ObservedObject private var session = LocationSimulationSession.shared
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheetVisible = true
    @State private var detent: PresentationDetent = .height(290)
    @State private var query = ""
    @StateObject private var placeSearch = OmegaPlaceSearch()
    @StateObject private var library = OmegaPlaceLibrary()
    @State private var searchRegion: MKCoordinateRegion?
    @State private var selected: SimulationStop?
    @State private var stops: [SimulationStop] = []
    @State private var preview: PlannedRoute?
    @State private var editing = false
    @State private var loading = false
    @State private var error: String?
    @State private var simulationErrorMessage = ""
    @State private var showsSimulationError = false
    @State private var setup = false
    @State private var imports = false
    @State private var filePicker = false
    @State private var pinTarget: OmegaPinKind?
    @State private var replacingPinID: UUID?
    @State private var renamingPin: OmegaPinnedPlace?
    @State private var renamingBookmark: LocationBookmark?
    @State private var customPinPlace: SimulationStop?
    @State private var editedName = ""
    @State private var showsNameEditor = false
    @State private var showsTiming = false
    @State private var leaveLater = false
    @State private var departureDate = Date.now.addingTimeInterval(3600)
    @State private var dwellStopID: UUID?
    @State private var dwellMinutes = 0.0
    @State private var trafficNotice: String?
    @State private var plannedTrafficProbability: Double?
    @State private var plannedTrafficEnabled = false
    @State private var routeTask: Task<Void, Never>?
    @State private var metadataTask: Task<Void, Never>?
    @State private var metadataLoading = false
    @State private var metadataFailed = false
    @State private var metadataRequestID = UUID()
    @State private var planner = RoutePlanner()
    @State private var trafficPlanner = TrafficLightPlanner()
    @State private var requestID = UUID()
    @State private var searchTarget: RouteSearchTarget?
    @State private var needsStart = false
    @State private var applyingRoute = false
    @State private var preparingEdit = false
    @State private var editRequestID = UUID()
    @State private var concludingActionID: UUID?
    @State private var showsSpeed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var followsSimulation = false
    @State private var previousAcceptedCoordinate: CLLocationCoordinate2D?
    @State private var simulatedHeading = 0.0
    @State private var visibleMapHeading = 0.0
    @State private var mapSize = CGSize(width: 430, height: 932)
    @FocusState private var searchFocused: Bool
    @AppStorage("routeSpeedUsesMPH") private var usesMPH = true
    @AppStorage("omegaRedLightProbability") private var redLightProbability = 0.5
    @AppStorage("omegaMappedTrafficLights") private var mappedTrafficLights = true
    @AppStorage("omegaRoadMetadataAllowed") private var roadMetadataAllowed = false

    private enum RouteSearchTarget: Equatable {
        case startingLocation
        case replace(UUID)
        case addStop
    }

    private var route: PlannedRoute? { editing ? (preview ?? session.plannedRoute) : (session.plannedRoute ?? preview) }
    private var visibleStops: [SimulationStop] { stops.isEmpty ? (route?.stops ?? []) : stops }
    private var units: OmegaUnits { OmegaUnits(usesMPH: usesMPH) }
    private var searchPrompt: String {
        if let pinTarget { return "Find \(pinTarget == .custom ? "a pinned place" : pinTarget.title)" }
        switch searchTarget {
        case .startingLocation: return "Search starting location"
        case .replace: return "Search replacement stop"
        case .addStop: return "Search for a stop"
        case nil: return "Search Omega"
        }
    }
    private var routeEditorTitle: String {
        switch searchTarget {
        case .startingLocation: return "Starting Location"
        case .replace: return "Replace Stop"
        case .addStop: return "Add Stop"
        case nil: return editing ? "Edit Route" : "Directions"
        }
    }
    private var speed: Binding<Double> {
        Binding(get: { session.speedMetersPerSecond * units.speedMultiplier },
                set: { session.speedMetersPerSecond = $0 / units.speedMultiplier })
    }
    private var speedRange: ClosedRange<Double> {
        // Unit conversion must preserve speed, including values near either slider endpoint.
        min(1, speed.wrappedValue)...max(units.maximumSpeed, speed.wrappedValue)
    }
    private var tripIsVisible: Bool { session.plannedRoute != nil && !editing }
    private var playbackTitle: String {
        if session.playbackState == .paused { return "Paused" }
        if let wait = session.currentWait {
            switch wait.kind {
            case .departure: return "Leaving later"
            case .stop: return "Staying at stop"
            case .trafficLight: return "Red light"
            }
        }
        return session.playbackState == .playing ? "Simulating" : session.playbackState == .arrived ? "Arrived" : "Paused"
    }
    private var speedLabel: String {
        let value = tripIsVisible && session.useRoadSpeeds ? session.effectiveSpeedMetersPerSecond * units.speedMultiplier : speed.wrappedValue
        return "\(Int(value.rounded())) \(units.speedSymbol)"
    }
    private var compactDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 460 : session.currentWait != nil ? 245 : 185) }
    private var speedDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 650 : 400) }
    private var previewDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 680 : 530) }
    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                UserAnnotation()
                if let route {
                    MapPolyline(coordinates: route.coordinates).stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                    Marker(stop.title, systemImage: !needsStart && index == 0 ? "location.fill" : index == visibleStops.count - 1 ? "mappin" : "\(index).circle.fill", coordinate: stop.coordinate)
                        .tint(!needsStart && index == 0 ? .blue : index == visibleStops.count - 1 ? .red : .orange)
                }
                if let selected { Marker(selected.title, coordinate: selected.coordinate) }
                if let point = session.coordinate {
                    Annotation("Simulated location", coordinate: point) {
                        Image(systemName: "location.north.fill").font(.title2).foregroundStyle(.white)
                            .rotationEffect(.degrees(simulatedHeading - visibleMapHeading))
                            .padding(12).background(.blue, in: Circle()).shadow(radius: 4)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .continuous) { context in
                visibleMapHeading = context.camera.heading
                if camera.positionedByUser { followsSimulation = false }
            }
            .onMapCameraChange(frequency: .onEnd) { context in searchRegion = context.region }
            .onTapGesture { location in
                guard session.plannedRoute == nil || editing else { return }
                if let point = proxy.convert(location, from: .local) {
                    choose(SimulationStop(title: "Dropped Pin", coordinate: point))
                }
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    Button {
                        if let route, tripIsVisible { followsSimulation = false; fitRouteAboveCard(route) }
                        else { setup = true }
                    } label: { Image(systemName: tripIsVisible ? "point.topleft.down.to.point.bottomright.curvepath" : "person.crop.circle").frame(width: 48, height: 48) }
                        .accessibilityLabel(tripIsVisible ? "Show entire route" : "Omega LocSim settings")
                    Divider().frame(width: 30)
                    Button {
                        if let point = session.coordinate { followsSimulation = true; center(on: point) }
                        else { camera = .userLocation(fallback: .automatic) }
                    } label: { Image(systemName: followsSimulation ? "location.fill" : "location").frame(width: 48, height: 48) }
                        .accessibilityLabel("Recenter on simulated location")
                }.font(.title3).omegaGlass(in: RoundedRectangle(cornerRadius: 26), interactive: true)
                    .padding(.top, tripIsVisible ? 118 : 12).padding(.trailing, 16)
            }
        }
        .overlay(alignment: .top) {
            if tripIsVisible { playbackBanner.padding(.horizontal, 12).padding(.top, 8) }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { mapSize = $0 }
        .sheet(isPresented: $sheetVisible) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if tripIsVisible { tripCard }
                    else if !stops.isEmpty || editing || needsStart { routeEditor }
                    else if let selected { placeCard(selected) }
                    else {
                        HStack(spacing: 12) {
                            searchField
                            Button { setup = true } label: {
                                Image(systemName: "person.crop.circle.fill").font(.title).frame(width: 44, height: 44)
                            }.omegaGlass(in: Circle(), interactive: true).accessibilityLabel("Omega LocSim settings")
                        }
                        if query.isEmpty {
                            if let pinTarget {
                                HStack {
                                    Text("Choose a place for \(pinTarget.title). Search or tap the map.")
                                        .font(.callout).foregroundStyle(.secondary)
                                    Button("Cancel") { cancelPinSearch() }.frame(minHeight: 44)
                                }
                            } else { pinnedPlaces }
                        }
                    }
                    if !query.isEmpty { searchResults }
                    if (session.isActive || applyingRoute) && !tripIsVisible {
                        HStack {
                            if session.plannedRoute == nil { Label("Holding location", systemImage: "location.fill").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            restoreButton.font(.callout)
                        }
                    }
                    if let message = error ?? session.playbackError {
                        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.callout)
                    }
                }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: session.playbackError, initial: true) { _, message in
                guard let message else { return }
                simulationErrorMessage = message
                showsSimulationError = true
            }
            .alert("Simulation Unavailable", isPresented: $showsSimulationError) {
                Button("Settings") { setup = true }
                Button("OK", role: .cancel) { }
            } message: {
                Text(simulationErrorMessage)
            }
            .presentationDetents([compactDetent, previewDetent, speedDetent, .height(290), .medium, .large], selection: $detent)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(34)
            .presentationBackground {
                if reduceTransparency { Color(uiColor: .systemBackground) }
                else { Rectangle().fill(.clear).omegaGlass(in: RoundedRectangle(cornerRadius: 34)) }
            }
            .presentationBackgroundInteraction(.enabled)
            .interactiveDismissDisabled()
            .sheet(isPresented: $setup) {
                SettingsView(onClose: { setup = false })
            }
            .sheet(isPresented: $imports) { librarySheet }
            .sheet(isPresented: $showsTiming) { timingSheet }
            .sheet(isPresented: Binding(get: { dwellStopID != nil }, set: { if !$0 { dwellStopID = nil } })) { dwellSheet }
            .alert(customPinPlace != nil ? "Name Pinned Place" : "Rename Place", isPresented: $showsNameEditor) {
                TextField("Name", text: $editedName)
                Button("Cancel", role: .cancel) { clearNameEditor() }
                Button("Save") { saveNameEdit() }
            }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: CoordinateImportParser.supportedContentTypes) { result in
                do {
                    let url = try result.get()
                    let points = try CoordinateImportParser.parse(url: url)
                    if points.count == 1, let first = points.first {
                        choose(SimulationStop(title: url.deletingPathExtension().lastPathComponent, coordinate: first))
                    } else {
                        // An imported path owns the draft immediately. A previous
                        // MapKit or road-details task must not replace its geometry.
                        routeTask?.cancel(); planner.cancel(); requestID = UUID(); loading = false
                        metadataTask?.cancel(); metadataRequestID = UUID(); metadataLoading = false
                        trafficNotice = nil; metadataFailed = false; error = nil
                        let geometry = RouteGeometry(points)
                        preview = PlannedRoute(coordinates: points, stopDistances: [geometry.length], stops: [
                            SimulationStop(title: "Imported Start", coordinate: points[0]),
                            SimulationStop(title: "Imported End", coordinate: points[points.count - 1])
                        ])
                        stops = preview!.stops; selected = nil; needsStart = false; searchTarget = nil; detent = previewDetent
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
        .tint(colorScheme == .dark ? .cyan : .blue)
        .onAppear {
            if FileManager.default.fileExists(atPath: PairingFileStore.prepareURL().path) { startTunnelInBackground() }
        }
        .onChange(of: query) { _, value in
            placeSearch.update(value, region: searchRegion)
            if !value.isEmpty { detent = .large }
        }
        .onChange(of: session.currentWait != nil) { _, _ in
            if tripIsVisible, !showsSpeed { detent = compactDetent }
        }
        .onReceive(session.$coordinate) { point in
            if let point, let previous = previousAcceptedCoordinate, session.plannedRoute != nil,
               CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude)) > 0.5 {
                let radians = Double.pi / 180
                let a = previous.latitude * radians, b = point.latitude * radians
                let longitude = (point.longitude - previous.longitude) * radians
                simulatedHeading = atan2(sin(longitude) * cos(b), cos(a) * sin(b) - sin(a) * cos(b) * cos(longitude)) / radians
            }
            previousAcceptedCoordinate = point
            if followsSimulation, !editing, let point { center(on: point) }
        }
        .onChange(of: session.isActive) { _, active in
            if !active, editing { cancelDraft() }
        }
    }

    private var pinnedPlaces: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 18) {
                    ForEach([OmegaPinKind.home, .school, .work]) { kind in
                        pinButton(kind: kind, pin: library.pin(kind))
                    }
                    ForEach(library.pins.filter { $0.kind == .custom }) { pin in
                        pinButton(kind: .custom, pin: pin)
                    }
                }.padding(.horizontal, 4).padding(.vertical, 2)
            }.scrollIndicators(.hidden)
            Button { imports = true } label: {
                HStack {
                    Label("Library", systemImage: "bookmark.fill").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(library.bookmarks.count) places").font(.subheadline).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }.frame(minHeight: 44)
            }.foregroundStyle(.primary)
        }
    }

    private func pinButton(kind: OmegaPinKind, pin: OmegaPinnedPlace?) -> some View {
        Button {
            if let pin { choose(.init(title: pin.name, coordinate: pin.coordinate)) }
            else { beginPinSearch(kind) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.title3.weight(.semibold))
                    .foregroundStyle(pin == nil ? Color.secondary : Color.accentColor)
                    .frame(width: 52, height: 52).omegaGlass(in: Circle(), interactive: true)
                Text(pin?.name ?? kind.title).font(.caption.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                if pin == nil { Text("Add").font(.caption2).foregroundStyle(.secondary) }
            }.frame(width: 72).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(pin.map { "\($0.name), \($0.placeName)" } ?? "Add \(kind.title)")
            .contextMenu {
                if let pin {
                    Button { beginPinSearch(kind, replacing: pin.id) } label: { Label("Change Location", systemImage: "magnifyingglass") }
                    Button { beginRename(pin: pin) } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { library.removePin(pin.id) } label: { Label("Remove Pin", systemImage: "pin.slash") }
                }
            }
    }

    private var librarySheet: some View {
        NavigationStack {
            List {
                Section("Pinned") {
                    ForEach(library.pins) { pin in
                        Button { choose(.init(title: pin.name, coordinate: pin.coordinate)); imports = false } label: {
                            Label { VStack(alignment: .leading) { Text(pin.name); Text(pin.placeName).font(.caption).foregroundStyle(.secondary) } }
                                icon: { Image(systemName: pin.kind.symbol) }
                        }.foregroundStyle(.primary)
                            .swipeActions {
                                Button("Remove", role: .destructive) { library.removePin(pin.id) }
                                Button("Rename") { beginRename(pin: pin) }.tint(.blue)
                            }
                    }
                    Button { imports = false; beginPinSearch(.custom) } label: { Label("Add Pinned Place", systemImage: "plus") }
                }
                Section("Saved Places") {
                    if library.bookmarks.isEmpty { Text("Save a place from its place card.").foregroundStyle(.secondary) }
                    ForEach(library.bookmarks) { bookmark in
                        Button { choose(.init(title: bookmark.name, coordinate: bookmark.coordinate)); imports = false } label: {
                            Label(bookmark.name, systemImage: "bookmark")
                        }.foregroundStyle(.primary)
                            .swipeActions(edge: .leading) {
                                Button("Rename") { beginRename(bookmark: bookmark) }.tint(.blue)
                            }
                    }.onDelete(perform: library.removeBookmarks)
                }
                Section { Button { imports = false; filePicker = true } label: { Label("Import Coordinates", systemImage: "square.and.arrow.down") } }
            }.navigationTitle("Omega Library")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { imports = false } } }
        }
    }

    private var timingSheet: some View {
        NavigationStack {
            Form {
                if !editing {
                    Section {
                        Toggle("Leave Later", isOn: $leaveLater)
                            .onChange(of: leaveLater) { _, enabled in
                                if enabled, departureDate < .now { departureDate = .now.addingTimeInterval(3600) }
                            }
                        if leaveLater {
                            DatePicker("Departure", selection: $departureDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        }
                    } header: { Text("Departure") } footer: {
                        Text("Start the route to hold its starting location until departure. Leave Now skips the wait.")
                    }
                }
                Section {
                    Toggle("Mapped Road Details", isOn: $roadMetadataAllowed)
                    if roadMetadataAllowed {
                        Toggle("Traffic Lights", isOn: $mappedTrafficLights)
                    }
                    if roadMetadataAllowed && mappedTrafficLights {
                        HStack {
                            Text("Red-light probability")
                            Spacer()
                            Text("\(Int((redLightProbability * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $redLightProbability, in: 0...1, step: 0.01)
                            .accessibilityLabel("Red-light probability")
                            .accessibilityValue("\(Int((redLightProbability * 100).rounded())) percent")
                        Text("A simulated red light adds 5–90 seconds to your ETA. You can skip a light while waiting.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text("Traffic Lights") } footer: {
                    Text("Sends this route to OpenStreetMap to find road speeds and mapped lights. Coverage may be incomplete; missing speed limits use road-type estimates. Light colors are simulated.")
                }
                if let trafficNotice {
                    Section { Text(trafficNotice).font(.callout).foregroundStyle(.secondary) }
                }
                Section {
                    LabeledContent("Stay at each stop", value: "Stop options")
                } footer: { Text("Open a stop’s menu to set how long to stay. The final destination holds until you end or restore the route.") }
            }.navigationTitle("Route Timing").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showsTiming = false } } }
        }.onDisappear { refreshTrafficPlanIfNeeded() }
    }

    private var dwellSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Stay", selection: $dwellMinutes) {
                        Text("No delay").tag(0.0)
                        ForEach(Array(Set([1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240, 480, Int(dwellMinutes)])).filter { $0 > 0 }.sorted(), id: \.self) { minutes in
                            Text(waitLabel(Double(minutes * 60))).tag(Double(minutes))
                        }
                    }.pickerStyle(.wheel)
                    Stepper(value: $dwellMinutes, in: 0...1440, step: 1) {
                        LabeledContent("Minutes", value: "\(Int(dwellMinutes))")
                    }
                } footer: { Text("The route stays at this place before continuing. Leave Now skips the remaining delay.") }
            }.navigationTitle("Stay Duration").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dwellStopID = nil } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { saveDwell() } }
                }
        }
    }

    private func beginPinSearch(_ kind: OmegaPinKind, replacing id: UUID? = nil) {
        pinTarget = kind; replacingPinID = id; selected = nil
        cancelStopSearch(); detent = .large; searchFocused = true
    }
    private func cancelPinSearch() {
        pinTarget = nil; replacingPinID = nil; cancelStopSearch()
    }
    private func beginRename(pin: OmegaPinnedPlace? = nil, bookmark: LocationBookmark? = nil) {
        renamingPin = pin; renamingBookmark = bookmark; editedName = pin?.name ?? bookmark?.name ?? ""
        if imports {
            imports = false
            Task { try? await Task.sleep(for: .milliseconds(350)); showsNameEditor = true }
        } else { showsNameEditor = true }
    }
    private func clearNameEditor() { renamingPin = nil; renamingBookmark = nil; customPinPlace = nil; editedName = "" }
    private func saveNameEdit() {
        if let place = customPinPlace { library.savePin(kind: .custom, name: editedName, place: place) }
        if let pin = renamingPin { library.renamePin(pin.id, name: editedName) }
        if let bookmark = renamingBookmark { library.renameBookmark(bookmark.id, name: editedName) }
        clearNameEditor()
    }
    private func saveDwell() {
        guard let id = dwellStopID, let index = stops.firstIndex(where: { $0.id == id }) else { dwellStopID = nil; return }
        stops[index].dwellSeconds = dwellMinutes * 60
        if var route = preview { route.stops = stops; preview = route }
        dwellStopID = nil
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .submitLabel(.search).autocorrectionDisabled().focused($searchFocused)
                .accessibilityLabel(searchPrompt)
                .onSubmit { Task { await placeSearch.submit() } }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Clear search")
            }
        }.frame(minHeight: 44).padding(.horizontal, 13).padding(.vertical, 3)
            .omegaGlass(in: Capsule(), interactive: true)
    }
    private var searchResults: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(library.pins.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.placeName.localizedCaseInsensitiveContains(query) }) { pin in
                Button { choose(.init(title: pin.name, coordinate: pin.coordinate)) } label: {
                    searchRow(title: pin.name, subtitle: pin.placeName, symbol: pin.kind.symbol)
                }
                Divider().padding(.leading, 48)
            }
            ForEach(Array(placeSearch.suggestions.enumerated()), id: \.offset) { _, suggestion in
                Button {
                    Task {
                        if let item = await placeSearch.resolve(suggestion) {
                            choose(.init(title: item.name ?? suggestion.title, coordinate: item.placemark.coordinate))
                        }
                    }
                } label: { searchRow(title: suggestion.title, subtitle: suggestion.subtitle, symbol: "magnifyingglass") }
                .disabled(placeSearch.isSearching)
                Divider().padding(.leading, 48)
            }
            ForEach(Array(placeSearch.results.enumerated()), id: \.offset) { _, item in
                Button { choose(.init(title: item.name ?? "Place", coordinate: item.placemark.coordinate)) } label: {
                    searchRow(title: item.name ?? "Place", subtitle: item.placemark.title ?? "", symbol: "mappin")
                }
                Divider().padding(.leading, 48)
            }
            if placeSearch.isSearching {
                HStack(spacing: 10) { ProgressView(); Text("Finding places…").foregroundStyle(.secondary) }.padding(.vertical, 16)
            }
            if let message = placeSearch.error { Text(message).font(.callout).foregroundStyle(.secondary).padding(.vertical, 12) }
        }.buttonStyle(.plain)
    }

    private func searchRow(title: String, subtitle: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer(minLength: 0)
        }.frame(minHeight: 48).padding(.vertical, 6).contentShape(Rectangle()).multilineTextAlignment(.leading)
    }
    private func cardHeader(_ title: String, subtitle: String? = nil, close: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Menu {
                Button { setup = true } label: { Label("Settings", systemImage: "gearshape") }
                Button { imports = true } label: { Label("Saved Places & Import", systemImage: "bookmark") }
                    .disabled(session.plannedRoute != nil || !stops.isEmpty)
                if session.isActive || applyingRoute { restoreButton }
            } label: {
                Image(systemName: "ellipsis").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }.omegaGlass(in: Circle(), interactive: true).accessibilityLabel("Location options")
            VStack(spacing: 3) {
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity)
            Button(action: close) {
                Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }.foregroundStyle(.primary).omegaGlass(in: Circle(), interactive: true)
                .accessibilityLabel("Close \(title)").disabled(applyingRoute)
        }
    }
    private var restoreButton: some View {
        Button { concludeRoute(restoring: true) } label: {
            Label("Restore Real Location", systemImage: "location.slash")
        }.frame(minHeight: 44)
    }
    private func placeCard(_ place: SimulationStop) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(place.title, subtitle: "Selected place") { selected = nil }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { placeActions(place) }
                VStack(spacing: 10) { placeActions(place) }
            }
            HStack(spacing: 14) {
                Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Coordinates").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.5f, %.5f", place.coordinate.latitude, place.coordinate.longitude))
                        .font(.subheadline).monospacedDigit().textSelection(.enabled)
                }
                Spacer()
                Menu {
                    Button { library.saveBookmark(place) } label: { Label("Save to Library", systemImage: "bookmark") }
                    ForEach(OmegaPinKind.allCases.filter { $0 != .custom }) { kind in
                        Button { library.savePin(kind: kind, place: place) } label: { Label("Pin as \(kind.title)", systemImage: kind.symbol) }
                    }
                    Button {
                        customPinPlace = place; editedName = place.title; showsNameEditor = true
                    } label: { Label("Add Custom Pin", systemImage: "mappin.and.ellipse") }
                } label: {
                    Image(systemName: library.bookmarks.contains { abs($0.latitude - place.coordinate.latitude) < 0.000001 && abs($0.longitude - place.coordinate.longitude) < 0.000001 } ? "bookmark.fill" : "bookmark")
                        .font(.title3).frame(width: 44, height: 44)
                }.accessibilityLabel("Save or pin place")
            }.padding(12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
        }
    }
    @ViewBuilder private func placeActions(_ place: SimulationStop) -> some View {
        Button { directions(to: place) } label: {
            VStack(spacing: 4) { Image(systemName: "car.fill"); Text("Directions").fontWeight(.semibold) }
                .frame(maxWidth: .infinity, minHeight: 56)
        }.omegaGlassButton(prominent: true)
        Button { Task { await session.setStationary(place.coordinate) } } label: {
            VStack(spacing: 4) { Image(systemName: "location.fill"); Text("Set Location").fontWeight(.semibold) }
                .frame(maxWidth: .infinity, minHeight: 56)
        }.omegaGlassButton().disabled(session.isSendingLocation)
            .accessibilityLabel("Set Spoofed Location")
    }
    private var routeEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(routeEditorTitle) {
                if searchTarget != nil { cancelStopSearch() } else { cancelDraft() }
            }
            if searchTarget != nil {
                searchField.disabled(applyingRoute)
                Text("Search for a place or tap the map.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("Driving", systemImage: "car.fill").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button { toggleSpeed() } label: {
                        Label(speedLabel, systemImage: "speedometer").font(.subheadline.weight(.semibold))
                    }.frame(minHeight: 44).accessibilityLabel("Simulation speed, \(speedLabel)")
                }.padding(.horizontal, 12)
                    .background(.quaternary.opacity(0.35), in: Capsule())
                VStack(spacing: 0) {
                    if needsStart {
                        Button { beginStopSearch(.startingLocation) } label: {
                            Label("Choose Starting Location", systemImage: "location.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        }
                        Divider().padding(.leading, 32)
                    }
                    ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                        stopRow(stop, at: index)
                        Divider().padding(.leading, 32)
                    }
                    Button { beginStopSearch(.addStop) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle.fill").font(.title2)
                            Text("Add Stop").fontWeight(.semibold)
                            Spacer()
                        }.frame(minHeight: 48)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 24))
                    .disabled(applyingRoute)
                if showsSpeed { speedControl }
                Button { showsTiming = true } label: {
                    HStack {
                        Label(leaveLater && !editing ? departureDate.formatted(date: .abbreviated, time: .shortened) : "Leave Now", systemImage: "clock")
                        Spacer()
                        Text(roadMetadataAllowed && mappedTrafficLights ? "\(Int((redLightProbability * 100).rounded()))% red lights" : "Timing").foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }.font(.subheadline).frame(minHeight: 44)
                }.foregroundStyle(.primary)
                if let preview {
                    previewSummary(preview)
                    metadataStatus
                } else if loading {
                    HStack { ProgressView(); Text("Finding route…") }.frame(maxWidth: .infinity, minHeight: 64)
                } else if needsStart {
                    Text("Choose a starting location to see your route.").font(.callout).foregroundStyle(.secondary)
                } else if stops.count < 2 {
                    Text("Add a destination to see your route.").font(.callout).foregroundStyle(.secondary)
                } else if error != nil {
                    Button("Try Again") { calculate() }.omegaGlassButton().controlSize(.large)
                }
            }
        }
    }
    private func previewSummary(_ preview: PlannedRoute) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(durationMinutes(previewDuration(preview))) min").font(.title2.bold())
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("\(previewArrival(preview, at: context.date)) ETA · \(distanceLabel(preview.distance))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Text((session.useRoadSpeeds ? (preview.speedSegments.isEmpty ? "Fallback \(speedLabel)" : "Road speeds") : "At \(speedLabel)") + (preview.plannedDelaySeconds > 0 ? " · \(waitLabel(preview.plannedDelaySeconds)) stops" : ""))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                applyingRoute = true; searchFocused = false
                Task {
                    var scheduledRoute = preview
                    scheduledRoute.departureDate = !editing && leaveLater ? max(Date.now, departureDate) : nil
                    let didStart = await session.play(scheduledRoute, preservingCurrentWait: editing)
                    applyingRoute = false
                    if didStart {
                        if let enriched = self.preview, enriched.id == scheduledRoute.id { _ = session.applyRoadMetadata(enriched) }
                        cancelDraft(preserveRoadMetadata: true); showsSpeed = false; followsSimulation = true
                        if let point = session.coordinate { center(on: point) }
                        detent = compactDetent
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    if applyingRoute { ProgressView().tint(.white) }
                    Text(editing ? "Apply" : leaveLater ? "Start" : "GO").font(.title3.bold())
                    if editing { Text("& Resume").font(.caption2.weight(.semibold)) }
                }.frame(minWidth: 56, minHeight: 56)
            }.buttonBorderShape(.roundedRectangle(radius: 20))
                .omegaGlassButton(prominent: true).tint(.green).disabled(applyingRoute)
                .accessibilityLabel(editing ? "Apply and resume route" : leaveLater ? "Start scheduled route" : "Go, start simulation")
        }.padding(14).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 24))
    }
    private func stopRow(_ stop: SimulationStop, at index: Int) -> some View {
        let isStart = !needsStart && index == 0
        let firstMovableIndex = needsStart ? 0 : 1
        return HStack(spacing: 12) {
            Image(systemName: isStart ? "location.circle.fill" : "mappin.circle.fill")
                .font(.title2).foregroundStyle(isStart ? .blue : .orange).accessibilityHidden(true)
            Button { beginStopSearch(.replace(stop.id)) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stop.title).fontWeight(.medium)
                    if !isStart, index < stops.count - 1 {
                        Text(stop.dwellSeconds > 0 ? "Stay \(waitLabel(stop.dwellSeconds))" : "No stop delay")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.foregroundStyle(.primary).disabled(editing && isStart)
                .accessibilityLabel(isStart ? "Starting location: \(stop.title)" : "Replace stop: \(stop.title)")
            if !isStart {
                Menu {
                    if index < stops.count - 1 {
                        Button {
                            dwellStopID = stop.id; dwellMinutes = stop.dwellSeconds / 60
                        } label: { Label("Stay Duration", systemImage: "clock") }
                    }
                    Button { beginStopSearch(.replace(stop.id)) } label: { Label("Replace Stop", systemImage: "magnifyingglass") }
                    if index > firstMovableIndex {
                        Button { stops.swapAt(index, index - 1); invalidatePreview() } label: { Label("Move Up", systemImage: "arrow.up") }
                    }
                    if index < stops.count - 1 {
                        Button { stops.swapAt(index, index + 1); invalidatePreview() } label: { Label("Move Down", systemImage: "arrow.down") }
                    }
                    Button(role: .destructive) {
                        if searchTarget == .replace(stop.id) { cancelStopSearch() }
                        stops.remove(at: index); invalidatePreview()
                    } label: { Label("Remove Stop", systemImage: "minus.circle") }
                } label: { Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for \(stop.title)")
            }
        }
        .draggable(isStart ? "" : stop.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard !applyingRoute, index >= firstMovableIndex, let value = items.first,
                  let source = stops.firstIndex(where: { $0.id.uuidString == value }), source >= firstMovableIndex else { return false }
            let moved = stops.remove(at: source)
            stops.insert(moved, at: min(index, stops.count))
            invalidatePreview()
            return true
        }
    }
    private func toggleSpeed() {
        showsSpeed.toggle()
        detent = showsSpeed ? (tripIsVisible ? speedDetent : .large) : (tripIsVisible ? compactDetent : previewDetent)
    }
    private var speedControl: some View {
        VStack(spacing: 10) {
            Picker("Speed mode", selection: $session.useRoadSpeeds) {
                Text("Road Limits").tag(true)
                Text("Constant").tag(false)
            }.pickerStyle(.segmented).padding(.top, 12)
            HStack {
                Text(session.useRoadSpeeds ? "Fallback speed" : "Simulation speed").font(.subheadline.weight(.semibold)); Spacer()
                Text("\(Int(speed.wrappedValue.rounded())) \(units.speedSymbol)").font(.subheadline).monospacedDigit()
            }
            Slider(value: speed, in: speedRange, step: 1).accessibilityLabel("Simulation speed in \(units.speedSymbol)")
            HStack { Text("1 \(units.speedSymbol)"); Spacer(); Text("\(Int(speedRange.upperBound)) \(units.speedSymbol)") }
                .font(.caption).foregroundStyle(.secondary)
            if session.useRoadSpeeds {
                Text(roadMetadataAllowed ? "Uses mapped limits and road-type estimates. Fallback applies while details load or are unavailable." : "Enable Mapped Road Details in Route Timing to use road speeds. Fallback applies until then.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 14).padding(.bottom, 10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
    }
    private var playbackBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: session.currentWait != nil ? "clock.fill" : session.playbackState == .playing ? "location.north.circle.fill" : session.playbackState == .arrived ? "checkmark.circle.fill" : "pause.circle.fill")
                .font(.system(size: 36)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(playbackTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(playbackDestination)
                    .font(.title3.bold()).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).frame(minHeight: 88)
            .omegaGlass(in: RoundedRectangle(cornerRadius: 30))
    }
    private var tripCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                tripMetric(session.playbackState == .paused ? "—" : arrivalTime(duration: session.remainingDuration), label: "arrival")
                tripMetric("\(durationMinutes(session.remainingDuration))", label: "min")
                tripMetric(units.distance(session.remainingDistance).value, label: units.distance(session.remainingDistance).unit)
            }
            if let wait = session.currentWait {
                HStack {
                    Label(waitLabel(wait.remainingSeconds), systemImage: "clock").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Button(waitButtonTitle) { session.skipCurrentWait() }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .disabled(!session.canSkipWait || concludingActionID != nil)
                }.padding(.horizontal, 12).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 18))
            }
            HStack(spacing: 8) {
                Button {
                    guard !preparingEdit else { return }
                    if session.playbackState == .playing { session.pausePlayback() } else { session.resumePlayback() }
                } label: {
                    Label(session.playbackState == .playing ? "Pause" : "Resume", systemImage: session.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 36)
                }.omegaGlassButton(prominent: true).disabled(session.playbackState == .arrived || preparingEdit || concludingActionID != nil)
                Button { toggleSpeed() } label: {
                    Text(speedLabel).font(.subheadline.weight(.semibold)).frame(minHeight: 36)
                }.omegaGlassButton().accessibilityLabel("Change simulation speed, \(speedLabel)")
                Menu {
                    Button { editRoute() } label: { Label("Edit Route", systemImage: "pencil") }.disabled(preparingEdit || concludingActionID != nil)
                    Button(role: .destructive) { concludeRoute(restoring: false) } label: { Label("End Route", systemImage: "stop.fill") }
                    restoreButton
                    Button { setup = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 36, height: 36) }
                    .omegaGlassButton().accessibilityLabel("Route controls: edit, end, restore and settings")
            }
            if showsSpeed { speedControl; metadataStatus }
            if preparingEdit { ProgressView("Pausing at accepted location…").font(.caption) }
        }
    }
    private func concludeRoute(restoring: Bool) {
        let id = UUID(); concludingActionID = id
        editRequestID = UUID(); preparingEdit = false; showsSpeed = false
        if !restoring { cancelDraft() }
        Task {
            if restoring { await session.restoreRealLocation() }
            else { await session.endPlayback() }
            guard concludingActionID == id else { return }
            concludingActionID = nil
            if !session.isActive { cancelDraft() }
            detent = .height(290)
        }
    }
    private func editRoute() {
        guard concludingActionID == nil else { return }
        let id = UUID(); editRequestID = id
        preparingEdit = true; followsSimulation = false
        Task {
            let point = await session.pauseAndWait()
            guard editRequestID == id else { return }
            preparingEdit = false
            guard let point, session.plannedRoute != nil else { return }
            stops = [SimulationStop(title: "Simulated Location", coordinate: point)] + session.remainingStops
            editing = true; preview = nil; needsStart = false; showsSpeed = false; detent = .large
            cancelStopSearch(); invalidatePreview()
        }
    }
    private func tripMetric(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
    }
    private var playbackDestination: String {
        if let wait = session.currentWait {
            switch wait.kind {
            case .stop(let title): return title
            case .departure: return "Route starts in \(waitLabel(wait.remainingSeconds))"
            case .trafficLight: return "Continue in \(waitLabel(wait.remainingSeconds))"
            }
        }
        return session.remainingStops.first?.title ?? session.plannedRoute?.stops.last?.title ?? "Route"
    }
    private var waitButtonTitle: String {
        if case .trafficLight = session.currentWait?.kind { return "Skip Light" }
        return "Leave Now"
    }
    private func durationMinutes(_ duration: Double) -> Int { Int(ceil(max(0, duration) / 60)) }
    private func distanceLabel(_ distance: Double) -> String { units.distanceLabel(distance) }
    private func arrivalTime(duration: Double, at now: Date = .now) -> String {
        now.addingTimeInterval(max(0, duration)).formatted(date: .omitted, time: .shortened)
    }
    private func previewDuration(_ route: PlannedRoute) -> TimeInterval {
        route.duration(atSpeed: session.speedMetersPerSecond, useRoadSpeeds: session.useRoadSpeeds)
            + (editing ? session.currentWait?.remainingSeconds ?? 0 : 0)
    }
    private func previewArrival(_ preview: PlannedRoute, at now: Date) -> String {
        let departure = !editing && leaveLater ? max(now, departureDate) : now
        return arrivalTime(duration: previewDuration(preview), at: departure)
    }
    private func waitLabel(_ seconds: Double) -> String {
        let total = max(0, Int(ceil(seconds)))
        if total < 60 { return "\(total) sec" }
        if total < 3600 { return "\(total / 60) min" + (total % 60 > 0 ? " \(total % 60) sec" : "") }
        return "\(total / 3600) hr" + ((total % 3600) / 60 > 0 ? " \((total % 3600) / 60) min" : "")
    }
    private func choose(_ stop: SimulationStop) {
        guard !applyingRoute else { return }
        if let pinTarget {
            library.savePin(kind: pinTarget, name: library.pins.first(where: { $0.id == replacingPinID })?.name, place: stop, replacing: replacingPinID)
            cancelPinSearch(); selected = stop; detent = .height(290)
        } else if !stops.isEmpty || editing || needsStart {
            guard let searchTarget else { return }
            switch searchTarget {
            case .startingLocation:
                stops.insert(stop, at: 0); needsStart = false
            case .replace(let id):
                guard let index = stops.firstIndex(where: { $0.id == id }) else { return }
                stops[index].title = stop.title
                stops[index].coordinate = stop.coordinate
            case .addStop:
                stops.append(stop)
            }
            cancelStopSearch()
            invalidatePreview()
        } else {
            cancelStopSearch()
            selected = stop; detent = .height(290)
        }
        followsSimulation = false
        camera = .region(MKCoordinateRegion(center: stop.coordinate, latitudinalMeters: 2500, longitudinalMeters: 2500))
    }
    private func directions(to stop: SimulationStop) {
        selected = nil; preview = nil; followsSimulation = false
        if let point = session.coordinate {
            stops = [SimulationStop(title: "Simulated Location", coordinate: point), stop]
            needsStart = false; cancelStopSearch()
        } else {
            // A start is explicit: never assume a map camera center is the device location.
            stops = [stop]; needsStart = true; beginStopSearch(.startingLocation)
        }
        detent = .large
        invalidatePreview()
    }
    private func beginStopSearch(_ target: RouteSearchTarget) {
        placeSearch.cancel()
        query = ""; searchTarget = target
        detent = .large; searchFocused = true
    }
    private func cancelStopSearch() {
        placeSearch.cancel()
        query = ""; searchTarget = nil; searchFocused = false
    }
    private func cancelDraft(preserveRoadMetadata: Bool = false) {
        if !preserveRoadMetadata {
            metadataTask?.cancel(); metadataRequestID = UUID(); metadataLoading = false
            trafficNotice = nil; metadataFailed = false
        }
        routeTask?.cancel(); planner.cancel(); requestID = UUID(); loading = false
        editing = false; stops = []; preview = nil; needsStart = false; error = nil; showsSpeed = false; leaveLater = false
        cancelStopSearch()
    }
    private func center(on point: CLLocationCoordinate2D) {
        if tripIsVisible {
            camera = .camera(MapCamera(centerCoordinate: point, distance: 1100, heading: simulatedHeading, pitch: 48))
        } else {
            camera = .region(MKCoordinateRegion(center: point, latitudinalMeters: 1600, longitudinalMeters: 1600))
        }
    }
    private func invalidatePreview() {
        routeTask?.cancel(); planner.cancel(); requestID = UUID(); preview = nil; loading = false
        error = nil
        if stops.count >= 2, !needsStart { calculate() }
    }
    private func calculate() {
        guard stops.count >= 2, !needsStart else { return }
        routeTask?.cancel(); planner.cancel()
        let id = UUID(); requestID = id; loading = true; error = nil
        let requestedStops = stops
        routeTask = Task { @MainActor in
            do {
                var result = try await planner.calculate(stops: requestedStops)
                guard !Task.isCancelled, requestID == id else { return }
                result.stops = stops
                preview = result; loading = false; trafficNotice = nil
                loadRoadMetadata(for: result)
                error = nil
                fitRouteAboveCard(result)
                if !editing { detent = previewDetent }
            } catch {
                guard requestID == id else { return }; loading = false
                if !Task.isCancelled {
                    self.error = editing
                        ? "Could not calculate route. Your original route remains paused. Try again or change the stops. \(error.localizedDescription)"
                        : "Could not calculate route. Try again or change the stops. \(error.localizedDescription)"
                }
            }
        }
    }
    @ViewBuilder private var metadataStatus: some View {
        if metadataLoading {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading road details… ETA will update.") }
                .font(.caption).foregroundStyle(.secondary)
        } else if let trafficNotice {
            HStack(alignment: .firstTextBaseline) {
                Text(trafficNotice).font(.caption).foregroundStyle(.secondary)
                if metadataFailed {
                    Button("Retry") { if let route { loadRoadMetadata(for: route) } }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
        }
    }
    private func refreshTrafficPlanIfNeeded() {
        guard let preview else { return }
        if !roadMetadataAllowed {
            var route = preview; route.trafficLights = []; route.speedSegments = []; self.preview = route
            metadataTask?.cancel(); metadataRequestID = UUID(); metadataLoading = false; metadataFailed = false
            trafficNotice = nil; plannedTrafficEnabled = false; plannedTrafficProbability = nil
        } else if mappedTrafficLights != plannedTrafficEnabled || redLightProbability != plannedTrafficProbability || preview.speedSegments.isEmpty {
            loadRoadMetadata(for: preview)
        }
    }
    private func loadRoadMetadata(for route: PlannedRoute) {
        metadataTask?.cancel()
        let id = UUID(); metadataRequestID = id
        guard roadMetadataAllowed else { metadataLoading = false; return }
        let probability = redLightProbability
        let includesLights = mappedTrafficLights
        metadataLoading = true; metadataFailed = false; trafficNotice = nil
        metadataTask = Task { @MainActor in
            do {
                let enriched = try await trafficPlanner.enrich(route, probability: probability, includeTrafficLights: includesLights, onUpdate: { partial in
                    guard metadataRequestID == id else { return }
                    applyRoadDetails(partial, to: route.id)
                })
                guard !Task.isCancelled, metadataRequestID == id else { return }
                applyRoadDetails(enriched, to: route.id)
                metadataLoading = false
                plannedTrafficEnabled = includesLights; plannedTrafficProbability = probability
            } catch {
                guard !Task.isCancelled, metadataRequestID == id else { return }
                metadataLoading = false; metadataFailed = true
                let current = preview?.id == route.id ? preview : session.plannedRoute?.id == route.id ? session.plannedRoute : nil
                if let current, !current.speedSegments.isEmpty || !current.trafficLights.isEmpty {
                    trafficNotice = "Some road details are retained. Unloaded sections use fallback speed; traffic-light coverage is incomplete."
                } else {
                    trafficNotice = "Road details unavailable. Using fallback speed; traffic lights are not included."
                }
            }
        }
    }
    private func applyRoadDetails(_ result: TrafficLightPlanResult, to routeID: UUID) {
        var updated = result.route
        if let current = preview, current.id == routeID {
            updated.stops = current.stops; updated.departureDate = current.departureDate
            preview = updated
        }
        if session.plannedRoute?.id == routeID { _ = session.applyRoadMetadata(updated) }
        guard preview?.id == routeID || session.plannedRoute?.id == routeID else { return }
        trafficNotice = result.notice
    }
    private func fitRouteAboveCard(_ route: PlannedRoute) {
        let rect = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count).boundingMapRect
        let aspect = max(0.1, mapSize.width / max(1, mapSize.height))
        // Reserve space for the status area, marker labels, and the trip card.
        let topMargin = 0.10
        let availableFraction = 0.34
        let height = max(1, max(rect.height * 1.2 / availableFraction, rect.width * 1.2 / aspect))
        let width = height * aspect
        camera = .rect(MKMapRect(x: rect.midX - width / 2,
            y: rect.midY - (topMargin + availableFraction / 2) * height,
            width: width, height: height))
    }

}

// Native system glass adapts to light/dark appearance and accessibility settings.
private extension View {
    @ViewBuilder
    func omegaGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func omegaGlassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) }
            else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) }
            else { buttonStyle(.bordered) }
        }
    }
}
