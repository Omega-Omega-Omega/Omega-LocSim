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
    @State private var hasPresentedRoutePreview = false
    @State private var error: String?
    @State private var simulationErrorMessage = ""
    @State private var showsSimulationError = false
    @State private var setup = false
    @State private var filePicker = false
    @State private var pinTarget: OmegaPinKind?
    @State private var replacingPinID: UUID?
    @State private var renamingPin: OmegaPinnedPlace?
    @State private var renamingBookmark: LocationBookmark?
    @State private var customPinPlace: SimulationStop?
    @State private var editedName = ""
    @State private var showsNameEditor = false
    @State private var leaveLater = false
    @State private var arriveBy = false
    @State private var arrivalDate = Date.now.addingTimeInterval(3600)
    @State private var editingRouteID: UUID?
    @State private var sheetScrollRequest = 0
    @State private var sheetScrollTarget = SheetScrollTarget.top
    @State private var librarySection: LibrarySection?
    @State private var namingRoute = false
    @State private var renamingRouteID: UUID?
    @State private var routeToSave: [SimulationStop] = []
    @State private var savedFeedback: String?
    @State private var removedStop: (stop: SimulationStop, index: Int)?
    @State private var departureDate = Date.now.addingTimeInterval(3600)
    @State private var dwellStopID: UUID?
    @State private var dwellMinutes = 0.0
    @State private var routeTask: Task<Void, Never>?
    @State private var roadMetadataRequests: [UUID: RoadMetadataRequest] = [:]
    @State private var planner = RoutePlanner()
    @State private var trafficPlanner = TrafficLightPlanner()
    @State private var requestID = UUID()
    @State private var searchTarget: RouteSearchTarget?
    @State private var needsStart = false
    @State private var applyingRoute = false
    @State private var concludingActionID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    // The moving route and an edit draft may load independently. Keeping each
    // request with its route prevents an edit or late response from stealing
    // the active route's work or showing another route's loading status.
    private struct RoadMetadataRequest {
        let id = UUID()
        let probability: Double
        let includesLights: Bool
        var task: Task<Void, Never>?
        var isLoading = true
        var failed = false
        var providerUnavailable = false
        var notice: String?
        var retryAt: Date?
    }

    private enum SheetScrollTarget: String {
        case top = "sheet-top"
        case options = "route-options"
    }

    private enum LibrarySection: String, CaseIterable, Identifiable {
        case places = "Places", recents = "Recents", routes = "Saved Routes"
        var id: String { rawValue }
    }

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
        case nil: return editing ? "Edit Route" : "Build Route"
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
    private var currentSpeedLabel: String {
        let moving = session.playbackState == .playing && session.currentWait == nil
        let value = moving ? session.effectiveSpeedMetersPerSecond * units.speedMultiplier : 0
        return "\(Int(max(0, value).rounded()))"
    }
    private var timingLabel: String {
        if arriveBy { return "Arrive by \(arrivalDate.formatted(date: .omitted, time: .shortened))" }
        if leaveLater && !editing { return "Leave at \(departureDate.formatted(date: .omitted, time: .shortened))" }
        return "Leave Now"
    }
    private var contentFill: Color { Color(uiColor: .secondarySystemGroupedBackground).opacity(reduceTransparency ? 1 : 0.68) }
    private var compactDetent: PresentationDetent {
        let base = dynamicTypeSize.isAccessibilitySize ? 460.0 : session.currentWait != nil ? 325.0 : 260.0
        return .height(base + (roadMetadataAllowed ? 56 : 0))
    }
    private var previewDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 680 : 530) }
    var body: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if session.coordinate == nil { UserAnnotation() }
                if let route {
                    MapPolyline(coordinates: route.coordinates).stroke(OmegaMapPalette.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                ForEach(Array(visibleStops.enumerated()), id: \.element.id) { index, stop in
                    if index != 0 || needsStart || session.plannedRoute == nil {
                        Marker(stop.title, systemImage: !needsStart && index == 0 ? "location.fill" : index == visibleStops.count - 1 ? "mappin" : "\(index).circle.fill", coordinate: stop.coordinate)
                            .tint(!needsStart && index == 0 ? OmegaMapPalette.blue : index == visibleStops.count - 1 ? .red : .orange)
                    }
                }
                if let selected { Marker(selected.title, coordinate: selected.coordinate) }
                if let point = session.coordinate {
                    Annotation("Simulated location", coordinate: point) {
                        OmegaHeadingDot(heading: simulatedHeading - visibleMapHeading)
                            .accessibilityLabel("Simulated location")
                            .accessibilityValue("Heading \(Int((simulatedHeading + 360).truncatingRemainder(dividingBy: 360))) degrees")
                    }.annotationTitles(.hidden)
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
            ScrollViewReader { scrollProxy in
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
                    if let savedFeedback {
                        Label(savedFeedback, systemImage: "checkmark.circle.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityElement(children: .combine)
                    }
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
                    .id(SheetScrollTarget.top.rawValue)
            }
            .onChange(of: sheetScrollRequest) { _, request in
                let target = sheetScrollTarget
                Task { @MainActor in
                    // Let the new trip/editor content and its detent finish replacing
                    // the old content before positioning the sheet. A newer request wins.
                    try? await Task.sleep(for: .milliseconds(300))
                    guard sheetScrollRequest == request else { return }
                    withAnimation(target == .top || reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(target.rawValue, anchor: .top)
                    }
                }
            }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { draftActionBar }
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
            .presentationDetents([compactDetent, previewDetent, .height(290), .medium, .large], selection: $detent)
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
            .sheet(item: $librarySection) { section in librarySheet(section) }
            .sheet(isPresented: Binding(get: { dwellStopID != nil }, set: { if !$0 { dwellStopID = nil } })) { dwellSheet }
            .alert(namingRoute ? "Save Route" : customPinPlace != nil ? "Name Pinned Place" : "Rename Place", isPresented: $showsNameEditor) {
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
                        error = nil
                        let geometry = RouteGeometry(points)
                        preview = PlannedRoute(coordinates: points, stopDistances: [geometry.length], stops: [
                            SimulationStop(title: "Imported Start", coordinate: points[0]),
                            SimulationStop(title: "Imported End", coordinate: points[points.count - 1])
                        ])
                        stops = preview!.stops; selected = nil; needsStart = false; searchTarget = nil; detent = previewDetent
                        hasPresentedRoutePreview = true
                        if let preview { loadRoadMetadata(for: preview) }
                    }
                } catch { self.error = error.localizedDescription }
            }
        }
        .tint(OmegaMapPalette.blue)
        .onAppear {
            if FileManager.default.fileExists(atPath: PairingFileStore.prepareURL().path) { startTunnelInBackground() }
            if let route = session.plannedRoute ?? preview { loadRoadMetadata(for: route) }
        }
        .onChange(of: session.plannedRoute?.id) { _, _ in
            pruneRoadMetadataRequests()
            if let activeRoute = session.plannedRoute { loadRoadMetadata(for: activeRoute) }
        }
        .onChange(of: session.playbackState == .arrived) { _, arrived in
            if arrived, let routeID = session.plannedRoute?.id { cancelRoadMetadata(for: routeID) }
        }
        .onChange(of: query) { _, value in
            placeSearch.update(value, region: searchRegion)
            if !value.isEmpty { detent = .large }
        }
        .onChange(of: tripIsVisible) { _, visible in
            if visible {
                syncActiveTiming()
                // Go, Apply Changes, and closing an edit all reveal the live trip.
                // Reset only on that transition, never for waits or metadata updates.
                requestSheetScroll(.top)
            }
        }
        .onChange(of: session.currentWait != nil) { _, _ in
            if tripIsVisible, detent != .large { detent = compactDetent }
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
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Places") { openLibrary(.places) }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach([OmegaPinKind.home, .work, .school]) { kind in
                            pinButton(kind: kind, pin: library.pin(kind))
                        }
                        ForEach(library.pins.filter { $0.kind == .custom }) { pin in
                            pinButton(kind: .custom, pin: pin)
                        }
                        Button { beginPinSearch(.custom) } label: {
                            VStack(spacing: 8) {
                                Image(systemName: "plus").font(.largeTitle.weight(.medium))
                                    .frame(width: 76, height: 76)
                                    .background(OmegaMapPalette.blue.opacity(0.12), in: Circle())
                                Text("Add").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("Place").font(.caption).foregroundStyle(.secondary)
                            }.frame(width: 80)
                        }.buttonStyle(.plain).accessibilityLabel("Add pinned place")
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden)
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Recents") { openLibrary(.recents) }
                if library.recents.isEmpty {
                    emptyCollection("Your recent locations and routes", detail: "Places you simulate and routes you start appear here.", symbol: "clock")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(library.recents.prefix(3).enumerated()), id: \.element.id) { index, recent in
                            recentRow(recent)
                            if index < min(3, library.recents.count) - 1 { Divider().padding(.leading, 60) }
                        }
                    }.padding(.horizontal, 14).background(contentFill, in: RoundedRectangle(cornerRadius: 24))
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Saved Routes") { openLibrary(.routes) }
                if library.savedRoutes.isEmpty {
                    Button { beginNewRoute() } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.title).frame(width: 52, height: 60)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Build a Route").font(.headline).foregroundStyle(.primary)
                                Text("Keep your regular trips in one place.").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(contentFill, in: RoundedRectangle(cornerRadius: 24))
                    }.buttonStyle(.plain)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 160), spacing: 12)], spacing: 12) {
                        ForEach(library.savedRoutes.prefix(4)) { saved in savedRouteCard(saved) }
                    }
                }
            }
        }.padding(.top, 6)
    }

    private func sectionHeading(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.title2.bold()).foregroundStyle(.primary)
                Image(systemName: "chevron.right").font(.body.weight(.semibold)).foregroundStyle(.tertiary)
                Spacer()
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Show all \(title.lowercased())")
    }

    private func emptyCollection(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary).frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(contentFill, in: RoundedRectangle(cornerRadius: 24))
    }

    private func pinButton(kind: OmegaPinKind, pin: OmegaPinnedPlace?) -> some View {
        let tint: Color = kind == .home ? OmegaMapPalette.blue : kind == .custom ? .purple : .brown
        return Button {
            if let pin { choose(.init(title: pin.name, coordinate: pin.coordinate)) }
            else { beginPinSearch(kind) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: kind.symbol).font(.largeTitle.weight(.semibold))
                    .foregroundStyle(pin == nil ? tint : .white)
                    .frame(width: 76, height: 76)
                    .background(pin == nil ? tint.opacity(0.12) : tint, in: Circle())
                Text(pin?.name ?? kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .lineLimit(2).multilineTextAlignment(.center)
                Text(pin.map { proximity(to: $0.coordinate) } ?? "Set Up")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(width: dynamicTypeSize.isAccessibilitySize ? 124 : 80).contentShape(Rectangle())
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

    private func proximity(to point: CLLocationCoordinate2D) -> String {
        guard let current = session.coordinate else { return "Pinned" }
        let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
        return distance < 100 ? "Close By" : distanceLabel(distance)
    }

    private func recentRow(_ recent: OmegaRecentActivity) -> some View {
        HStack(spacing: 8) {
            Button { openRecent(recent) } label: {
                HStack(spacing: 12) {
                    Image(systemName: recent.symbol).font(.headline).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(recent.kind == .route ? OmegaMapPalette.blue : Color.pink, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recent.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Text(recent.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(minHeight: 64).padding(.vertical, 6).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                Button { openRecent(recent) } label: { Label(recent.kind == .route ? "Build Route" : "View Place", systemImage: recent.symbol) }
                if recent.kind == .route {
                    Button { nameRoute(recent.simulationStops, name: recent.title) } label: { Label("Save Route", systemImage: "bookmark") }
                } else if let place = recent.place {
                    Button { library.saveBookmark(place); savedFeedback = "Place saved" } label: { Label("Save Place", systemImage: "bookmark") }
                }
                Button(role: .destructive) { library.removeRecent(recent.id) } label: { Label("Remove from Recents", systemImage: "trash") }
            } label: { Image(systemName: "ellipsis").font(.headline).frame(width: 44, height: 44) }
                .accessibilityLabel("Options for \(recent.title)")
        }
    }

    private func savedRouteCard(_ saved: OmegaSavedRoute) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.largeTitle).foregroundStyle(OmegaMapPalette.blue).accessibilityHidden(true)
                Spacer()
                Menu {
                    Button { loadRoute(saved.simulationStops) } label: { Label("Build Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                    Button { nameRoute(saved.simulationStops, name: saved.name, replacing: saved.id) } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { library.removeSavedRoute(saved.id) } label: { Label("Delete Route", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Options for \(saved.name)")
            }
            Button { loadRoute(saved.simulationStops) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(saved.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Text(saved.subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Build route, \(saved.name), \(saved.subtitle)")
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(contentFill, in: RoundedRectangle(cornerRadius: 24))
    }

    private func openLibrary(_ section: LibrarySection) { librarySection = section }
    private func openRecent(_ recent: OmegaRecentActivity) {
        librarySection = nil
        if recent.kind == .route { loadRoute(recent.simulationStops) }
        else if let place = recent.place { choose(place) }
    }
    private func loadRoute(_ values: [SimulationStop]) {
        guard session.plannedRoute == nil, values.count >= 2 else { return }
        cancelDraft(); librarySection = nil; selected = nil; stops = values
        followsSimulation = false; needsStart = false; detent = .large; calculate()
    }
    private func beginNewRoute() {
        guard session.plannedRoute == nil else { return }
        cancelDraft(); librarySection = nil; selected = nil; needsStart = true
        beginStopSearch(.startingLocation)
    }
    private func nameRoute(_ values: [SimulationStop], name: String? = nil, replacing id: UUID? = nil) {
        routeToSave = values; renamingRouteID = id; editedName = name ?? values.last?.title ?? "Route"
        namingRoute = true
        if librarySection != nil {
            librarySection = nil
            Task { try? await Task.sleep(for: .milliseconds(350)); showsNameEditor = true }
        } else { showsNameEditor = true }
    }

    private func librarySheet(_ section: LibrarySection) -> some View {
        NavigationStack {
            List {
                if section == .places {
                    Section("Pinned Places") {
                        ForEach(library.pins) { pin in
                            HStack(spacing: 12) {
                                Button { choose(.init(title: pin.name, coordinate: pin.coordinate)); librarySection = nil } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(pin.name).font(.headline)
                                            Text(pin.placeName).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    } icon: { Image(systemName: pin.kind.symbol).foregroundStyle(OmegaMapPalette.blue) }
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.foregroundStyle(.primary)
                                Menu {
                                    Button { librarySection = nil; beginPinSearch(pin.kind, replacing: pin.id) } label: { Label("Change Location", systemImage: "magnifyingglass") }
                                    Button { beginRename(pin: pin) } label: { Label("Rename", systemImage: "pencil") }
                                    Button(role: .destructive) { library.removePin(pin.id) } label: { Label("Remove Pin", systemImage: "pin.slash") }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Options for \(pin.name)")
                            }
                        }
                        Button { librarySection = nil; beginPinSearch(.custom) } label: { Label("Add Place", systemImage: "plus") }
                    }
                    Section("Saved Places") {
                        if library.bookmarks.isEmpty { Text("Save a place from its place card.").foregroundStyle(.secondary) }
                        ForEach(library.bookmarks) { bookmark in
                            HStack {
                                Button { choose(.init(title: bookmark.name, coordinate: bookmark.coordinate)); librarySection = nil } label: {
                                    Label(bookmark.name, systemImage: "bookmark.fill").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.foregroundStyle(.primary)
                                Button { beginRename(bookmark: bookmark) } label: { Image(systemName: "pencil").frame(width: 44, height: 44) }
                                    .accessibilityLabel("Rename \(bookmark.name)")
                            }
                        }.onDelete(perform: library.removeBookmarks)
                    }
                    Section { Button { librarySection = nil; filePicker = true } label: { Label("Import Coordinates", systemImage: "square.and.arrow.down") } }
                } else if section == .recents {
                    if library.recents.isEmpty { Text("Recent routes and simulated places will appear here.").foregroundStyle(.secondary) }
                    ForEach(library.recents) { recent in recentRow(recent) }
                } else {
                    Button { beginNewRoute() } label: { Label("Build Route", systemImage: "plus") }
                    if library.savedRoutes.isEmpty { Text("Save a route from its preview or from Recents.").foregroundStyle(.secondary) }
                    ForEach(library.savedRoutes) { saved in savedRouteCard(saved).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0)) }
                }
            }.buttonStyle(.borderless).navigationTitle(section.rawValue)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { librarySection = nil } } }
        }
    }

    private func routeOptions(active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider().padding(.top, 12)
            HStack {
                Text("Route Options").font(.title2.bold())
                Spacer()
                Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
            }.id("route-options").accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 14) {
                Text(active ? "Arrival Time" : "Schedule").font(.headline)
                Picker("Schedule", selection: Binding(get: {
                    arriveBy ? 2 : leaveLater ? 1 : 0
                }, set: { value in
                    arriveBy = value == 2; leaveLater = value == 1
                    if departureDate < .now { departureDate = .now.addingTimeInterval(3600) }
                    if arrivalDate < .now { arrivalDate = .now.addingTimeInterval(max(3600, session.remainingDuration)) }
                })) {
                    Text(active ? "No Arrival Target" : "Leave Now").tag(0)
                    if !editing && !active { Text("Leave Later").tag(1) }
                    Text("Arrive By").tag(2)
                }.pickerStyle(.menu).frame(minHeight: 44)
                if leaveLater && !editing && !active {
                    scheduleDatePicker("Departure", selection: $departureDate)
                    Text("Start the route to hold at its starting location. Leave Now skips the departure wait.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if arriveBy {
                    scheduleDatePicker("Arrival", selection: $arrivalDate)
                    Text("Omega skips only the red lights it needs to and adjusts simulated speed to meet this time. Stop stays remain part of your trip.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if session.playbackState == .paused && (editing || active) {
                        Text("Your route stays paused until you resume. Pauses or a lost connection can prevent an on-time arrival.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if active && arrivalDraftHasChanges {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 12) { arrivalActionButtons }
                    } else {
                        HStack(spacing: 12) { arrivalActionButtons }
                    }
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(contentFill, in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 14) {
                Text("Roads & Traffic Lights").font(.headline)
                Toggle("Mapped Road Details", isOn: $roadMetadataAllowed)
                    .onChange(of: roadMetadataAllowed) { _, _ in
                        refreshTrafficPlanIfNeeded()
                        if tripIsVisible, detent != .large { detent = compactDetent }
                    }
                if roadMetadataAllowed {
                    Toggle("Traffic Lights", isOn: $mappedTrafficLights)
                        .onChange(of: mappedTrafficLights) { _, _ in refreshTrafficPlanIfNeeded() }
                }
                if roadMetadataAllowed && mappedTrafficLights {
                    routeOptionValue("Red-light probability", value: "\(Int((redLightProbability * 100).rounded()))%")
                    Slider(value: $redLightProbability, in: 0...1, step: 0.01) { changing in
                        if !changing { refreshTrafficPlanIfNeeded() }
                    }.accessibilityLabel("Red-light probability")
                        .accessibilityValue("\(Int((redLightProbability * 100).rounded())) percent")
                    Text("Each simulated red light adds 5–90 seconds to your ETA. You can skip a light while waiting.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("Route coordinates are sent to OpenStreetMap road-data services. Missing limits use road-type estimates. Light colors are simulated.")
                    .font(.footnote).foregroundStyle(.secondary)
                metadataStatus
            }.padding(16).background(contentFill, in: RoundedRectangle(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 10) {
                Text("Speed").font(.headline)
                speedControl
            }
            Label("Set a stay duration from each stop’s options. The destination holds until you end or restore the route.", systemImage: "mappin.and.ellipse")
                .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 12)
        }.padding(.top, 8)
    }
    @ViewBuilder private func scheduleDatePicker(_ title: String, selection: Binding<Date>) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
                DatePicker(title, selection: selection, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact).labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            DatePicker(title, selection: selection, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.compact)
        }
    }
    @ViewBuilder private func routeOptionValue(_ label: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).fixedSize(horizontal: false, vertical: true)
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack {
                Text(label)
                Spacer()
                Text(value).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private var arrivalActionButtons: some View {
        Button("Cancel") { syncActiveTiming() }.frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.bordered)
        Button("Apply Arrival Time") { session.updateArrivalDate(arriveBy ? arrivalDate : nil) }
            .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.borderedProminent)
    }
    private var arrivalDraftHasChanges: Bool {
        (arriveBy ? arrivalDate : nil) != session.plannedRoute?.arrivalDate
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
        if librarySection != nil {
            librarySection = nil
            Task { try? await Task.sleep(for: .milliseconds(350)); showsNameEditor = true }
        } else { showsNameEditor = true }
    }
    private func clearNameEditor() {
        renamingPin = nil; renamingBookmark = nil; customPinPlace = nil; editedName = ""
        namingRoute = false; renamingRouteID = nil; routeToSave = []
    }
    private func saveNameEdit() {
        if namingRoute, library.saveRoute(stops: routeToSave, name: editedName, replacing: renamingRouteID) != nil {
            savedFeedback = "Route saved"
        }
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
                Button { openLibrary(.places) } label: { Label("Saved Places & Import", systemImage: "bookmark") }
                    .disabled(session.plannedRoute != nil || !stops.isEmpty)
                if session.isActive || applyingRoute { restoreButton }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
            }.omegaGlass(in: Circle(), interactive: true).accessibilityLabel("Location options")
            VStack(spacing: 3) {
                Text(title).font(.title3.bold()).multilineTextAlignment(.center)
                if let subtitle { Text(subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
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
                    Button { library.saveBookmark(place); savedFeedback = "Place saved" } label: { Label("Save Place", systemImage: "bookmark") }
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
            VStack(spacing: 4) { Image(systemName: "car.fill"); Text("Build Route").fontWeight(.semibold) }
                .frame(maxWidth: .infinity, minHeight: 56)
        }.omegaGlassButton(prominent: true)
        Button {
            Task {
                if await session.setStationary(place.coordinate) {
                    library.recordSpot(place)
                    savedFeedback = "Location set · saved to Recents"
                }
            }
        } label: {
            VStack(spacing: 4) { Image(systemName: "location.fill"); Text("Set Location").fontWeight(.semibold) }
                .frame(maxWidth: .infinity, minHeight: 56)
        }.omegaGlassButton().disabled(session.isSendingLocation)
            .accessibilityLabel("Set Spoofed Location")
    }
    private var routeEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(routeEditorTitle) {
                if searchTarget != nil { cancelStopSearch() }
                else {
                    let wasEditing = editing
                    cancelDraft(); detent = session.plannedRoute == nil ? .height(290) : compactDetent
                    if wasEditing, let activeRoute = session.plannedRoute { loadRoadMetadata(for: activeRoute) }
                }
            }
            if editing {
                HStack(spacing: 8) {
                    Image(systemName: session.playbackState == .arrived ? "checkmark.circle.fill" : session.playbackState == .playing ? "play.circle.fill" : "pause.circle.fill")
                    Text(session.playbackState == .arrived ? "Your route has finished." : session.playbackState == .playing ? "Your route keeps moving while you edit." : "Your route is paused.")
                        .font(.footnote)
                    Spacer(minLength: 0)
                    if session.playbackState != .arrived {
                        Button(session.playbackState == .playing ? "Pause" : "Resume") {
                            if session.playbackState == .playing { session.pausePlayback() } else { session.resumePlayback() }
                        }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
                            .disabled(applyingRoute)
                    }
                }.foregroundStyle(.secondary)
            }
            if searchTarget != nil {
                searchField.disabled(applyingRoute)
                Text("Search for a place or tap the map.").font(.callout).foregroundStyle(.secondary)
                if query.isEmpty {
                    ForEach(library.pins) { pin in
                        Button { choose(.init(title: pin.name, coordinate: pin.coordinate)) } label: {
                            searchRow(title: pin.name, subtitle: pin.placeName, symbol: pin.kind.symbol)
                        }.buttonStyle(.plain)
                    }
                }
            } else {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { routeMode; routeSpeedButton }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                    } else {
                        HStack { routeMode; Spacer(); routeSpeedButton }
                    }
                }.padding(.horizontal, 12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 22))
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
                if let removedStop {
                    HStack {
                        Text("Removed \(removedStop.stop.title)").font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                        Spacer()
                        Button("Undo") { undoRemoveStop() }.font(.footnote.weight(.semibold)).frame(minHeight: 44)
                    }
                }
                Button { openTiming(forActiveRoute: false) } label: {
                    HStack {
                        Label(timingLabel, systemImage: "clock")
                        Spacer()
                        Text("Options").foregroundStyle(.secondary)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }.font(.subheadline).frame(minHeight: 44)
                }.foregroundStyle(.primary)
                if let preview {
                    previewSummary(preview)
                } else if loading {
                    HStack { ProgressView(); Text("Finding route…") }.frame(maxWidth: .infinity, minHeight: 64)
                } else if needsStart {
                    Text("Choose a starting location to see your route.").font(.callout).foregroundStyle(.secondary)
                } else if stops.count < 2 {
                    Text("Add a destination to see your route.").font(.callout).foregroundStyle(.secondary)
                } else if error != nil {
                    Button("Try Again") { calculate() }.omegaGlassButton().controlSize(.large)
                }
                routeOptions(active: false).disabled(applyingRoute)
            }
        }
    }
    private var routeMode: some View {
        Label {
            Text("Driving").font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "car.fill").font(.system(size: 20, weight: .semibold)).accessibilityHidden(true)
        }
    }
    private var routeSpeedButton: some View {
        Button { toggleSpeed() } label: {
            Label {
                Text(speedLabel).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "speedometer").font(.system(size: 20, weight: .semibold)).accessibilityHidden(true)
            }
        }.frame(minHeight: 44).accessibilityLabel("Simulation speed, \(speedLabel)")
    }
    private func previewSummary(_ preview: PlannedRoute) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(durationMinutes(previewDuration(preview))) min estimate").font(.title.bold())
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("\(previewArrival(preview, at: context.date)) \(arriveBy ? "arrival" : "ETA") · \(distanceLabel(preview.distance))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text((session.useRoadSpeeds ? (preview.speedSegments.isEmpty ? "Fallback \(speedLabel)" : "Road speeds") : "At \(speedLabel)") + (preview.plannedDelaySeconds > 0 ? " · \(waitLabel(preview.plannedDelaySeconds)) stops" : ""))
                        .font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button { nameRoute(stops) } label: { Image(systemName: "bookmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Save this route")
            }
            compactMetadataStatus(for: preview)
        }.padding(16).background(contentFill, in: RoundedRectangle(cornerRadius: 24))
    }

    @ViewBuilder private var draftActionBar: some View {
        if let preview, !tripIsVisible, searchTarget == nil, !stops.isEmpty || editing {
            VStack(spacing: 8) {
                if editing {
                    Text("The final ETA is recalculated from your live position when you apply.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if arriveBy && !previewTiming(preview).feasible {
                    Label("Choose a later arrival or shorten your stays.", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Button { applyPreview(preview) } label: {
                    HStack(spacing: 8) {
                        if applyingRoute { ProgressView().tint(.white) }
                        else { Image(systemName: editing ? "checkmark" : "play.fill") }
                        Text(applyingRoute ? "Applying…" : editing ? "Apply Changes" : leaveLater ? "Start Scheduled Route" : "Go")
                            .font(.headline)
                    }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonBorderShape(.roundedRectangle(radius: 18))
                    .omegaGlassButton(prominent: true).tint(OmegaMapPalette.blue)
                    .disabled(applyingRoute || (!editing && arriveBy && !previewTiming(preview).feasible))
                    .accessibilityLabel(editing ? "Apply route changes and keep playback state" : leaveLater ? "Start scheduled route" : "Go, start simulation")
            }.padding(.horizontal, 16).padding(.vertical, 10)
                .background(.regularMaterial)
        }
    }

    private func applyPreview(_ preview: PlannedRoute) {
        guard !applyingRoute else { return }
        guard editing || !arriveBy || previewTiming(preview).feasible else {
            error = "Choose a later arrival time or shorten your stays before starting."
            return
        }
        applyingRoute = true; searchFocused = false
        let wasEditing = editing
        let originalID = editingRouteID
        Task {
            var scheduledRoute = preview
            scheduledRoute.departureDate = !wasEditing && leaveLater ? max(Date.now, departureDate) : nil
            scheduledRoute.arrivalDate = arriveBy ? arrivalDate : nil
            let didStart: Bool
            if wasEditing, let originalID {
                didStart = await session.applyEditedRoute(scheduledRoute, replacingRouteID: originalID)
            } else { didStart = await session.play(scheduledRoute) }
            applyingRoute = false
            if didStart {
                library.recordRoute(session.plannedRoute?.stops ?? scheduledRoute.stops)
                if !wasEditing, let enriched = self.preview, enriched.id == scheduledRoute.id { _ = session.applyRoadMetadata(enriched) }
                cancelDraft(); followsSimulation = true
                // A matching preview request continues after Go. Imported or
                // rebased routes also get a request if none exists yet.
                if let currentRoute = session.plannedRoute { loadRoadMetadata(for: currentRoute) }
                if let point = session.coordinate { center(on: point) }
                detent = compactDetent
            }
        }
    }

    private func stopRow(_ stop: SimulationStop, at index: Int) -> some View {
        let isStart = !needsStart && index == 0
        let firstMovableIndex = needsStart ? 0 : 1
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 12) {
                        stopSymbol(isStart: isStart, index: index).padding(.top, 7)
                        stopTitle(stop, isStart: isStart, index: index)
                    }
                    if !isStart {
                        HStack(spacing: 16) {
                            stopControls(stop, index: index, firstMovableIndex: firstMovableIndex)
                            Spacer(minLength: 0)
                        }.padding(.leading, 42)
                    }
                }.padding(.vertical, 12)
            } else {
                HStack(spacing: 8) {
                    stopSymbol(isStart: isStart, index: index)
                    stopTitle(stop, isStart: isStart, index: index)
                    if !isStart { stopControls(stop, index: index, firstMovableIndex: firstMovableIndex) }
                }
            }
        }
        .draggable(isStart ? "" : stop.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard !applyingRoute, index >= firstMovableIndex, let value = items.first,
                  let source = stops.firstIndex(where: { $0.id.uuidString == value }), source >= firstMovableIndex,
                  source != index else { return false }
            let moved = stops.remove(at: source)
            stops.insert(moved, at: min(index, stops.count))
            removedStop = nil; invalidatePreview(preservingSheet: true)
            return true
        }
    }
    private func stopSymbol(isStart: Bool, index: Int) -> some View {
        VStack(spacing: 3) {
            Image(systemName: isStart ? "location.circle.fill" : index == stops.count - 1 ? "mappin.circle.fill" : "circle.fill")
                .font(.system(size: isStart || index == stops.count - 1 ? 24 : 12))
                .foregroundStyle(isStart ? OmegaMapPalette.blue : Color.secondary)
            if index < stops.count - 1 { Rectangle().fill(.tertiary).frame(width: 2, height: 16) }
        }.frame(width: 30).accessibilityHidden(true)
    }
    private func stopTitle(_ stop: SimulationStop, isStart: Bool, index: Int) -> some View {
        Button { beginStopSearch(.replace(stop.id)) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title).font(.body.weight(.medium))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                if isStart {
                    Text(editing ? "Current simulated location" : "Starting location").font(.footnote).foregroundStyle(.secondary)
                } else if index < stops.count - 1 {
                    Text(stop.dwellSeconds > 0 ? "Stay \(waitLabel(stop.dwellSeconds))" : "No stop delay")
                        .font(.footnote).foregroundStyle(.secondary)
                } else { Text("Destination").font(.footnote).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.primary).disabled(editing && isStart)
            .accessibilityLabel(isStart ? "Starting location: \(stop.title)" : "Replace stop: \(stop.title)")
    }
    @ViewBuilder private func stopControls(_ stop: SimulationStop, index: Int, firstMovableIndex: Int) -> some View {
        Menu {
            if index < stops.count - 1 {
                Button { dwellStopID = stop.id; dwellMinutes = stop.dwellSeconds / 60 } label: { Label("Stay Duration", systemImage: "clock") }
            }
            Button { beginStopSearch(.replace(stop.id)) } label: { Label("Replace Stop", systemImage: "magnifyingglass") }
            if index > firstMovableIndex {
                Button { moveStop(stop.id, by: -1) } label: { Label("Move Up", systemImage: "arrow.up") }
            }
            if index < stops.count - 1 {
                Button { moveStop(stop.id, by: 1) } label: { Label("Move Down", systemImage: "arrow.down") }
            }
        } label: {
            Image(systemName: "line.3.horizontal").font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary).frame(width: 44, height: 44)
        }.accessibilityLabel("Reorder and options for \(stop.title)")
        Button(role: .destructive) { removeStop(stop.id) } label: {
            Image(systemName: "minus.circle.fill").font(.system(size: 22)).frame(width: 44, height: 44)
        }.buttonStyle(.plain).foregroundStyle(.red).accessibilityLabel("Remove \(stop.title)")
    }

    private func removeStop(_ id: UUID) {
        guard !applyingRoute, let index = stops.firstIndex(where: { $0.id == id }), needsStart || index > 0 else { return }
        if searchTarget == .replace(id) { cancelStopSearch() }
        removedStop = (stops.remove(at: index), index)
        invalidatePreview(preservingSheet: true)
    }
    private func undoRemoveStop() {
        guard let removedStop, !applyingRoute else { return }
        stops.insert(removedStop.stop, at: min(removedStop.index, stops.count))
        self.removedStop = nil; invalidatePreview(preservingSheet: true)
    }
    private func moveStop(_ id: UUID, by offset: Int) {
        guard !applyingRoute, let index = stops.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + offset
        guard destination >= (needsStart ? 0 : 1), stops.indices.contains(destination) else { return }
        stops.swapAt(index, destination); removedStop = nil; invalidatePreview(preservingSheet: true)
    }

    private func toggleSpeed() { openTiming(forActiveRoute: tripIsVisible) }
    private var speedControl: some View {
        VStack(spacing: 10) {
            Picker("Speed mode", selection: $session.useRoadSpeeds) {
                Text("Road Limits").tag(true)
                Text("Constant").tag(false)
            }.pickerStyle(.segmented).padding(.top, 12)
            routeOptionValue(session.useRoadSpeeds ? "Fallback speed" : "Simulation speed", value: "\(Int(speed.wrappedValue.rounded())) \(units.speedSymbol)")
                .font(.subheadline.weight(.semibold))
            Slider(value: speed, in: speedRange, step: 1).accessibilityLabel("Simulation speed in \(units.speedSymbol)")
            HStack { Text("1 \(units.speedSymbol)"); Spacer(); Text("\(Int(speedRange.upperBound)) \(units.speedSymbol)") }
                .font(.caption).foregroundStyle(.secondary)
            if session.useRoadSpeeds {
                Text(roadMetadataAllowed ? "Uses mapped limits and road-type estimates. Fallback applies while details load or are unavailable." : "Enable Mapped Road Details below in Route Options to use road speeds. Fallback applies until then.")
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
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 20) { tripMetrics }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) { tripMetrics }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) { tripMetrics }
                }
            }
            if let target = session.plannedRoute?.arrivalDate {
                Button { openTiming(forActiveRoute: true) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.badge.checkmark")
                        Text("Arrive by \(target.formatted(date: .omitted, time: .shortened))").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 0)
                        Image(systemName: "pencil").font(.caption)
                    }.frame(minHeight: 44)
                }.accessibilityLabel("Change arrival time, \(target.formatted(date: .omitted, time: .shortened))")
                if let adjustment = session.arrivalAdjustment {
                    if let warning = adjustment.warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else if adjustment.skippedTrafficLightCount > 0 || adjustment.speedMultiplier > 1.01 {
                        Text("Pace adjusted\(adjustment.skippedTrafficLightCount > 0 ? " · \(adjustment.skippedTrafficLightCount) lights made green" : "")")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if let wait = session.currentWait {
                HStack {
                    Label(waitLabel(wait.remainingSeconds), systemImage: "clock").font(.subheadline.weight(.semibold)).monospacedDigit()
                    Spacer()
                    Button(waitButtonTitle) { session.skipCurrentWait() }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                        .disabled(!session.canSkipWait || concludingActionID != nil)
                }.padding(.horizontal, 12).background(contentFill, in: RoundedRectangle(cornerRadius: 18))
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) { tripActions }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { tripActions }
                    VStack(spacing: 8) { tripActions }
                }
            }
            if let activeRoute = session.plannedRoute { compactMetadataStatus(for: activeRoute) }
            routeOptions(active: true)
        }
    }
    @ViewBuilder private var tripMetrics: some View {
        tripMetric(session.playbackState == .paused ? "—" : arrivalTime(duration: session.remainingDuration), label: "arrival")
        tripMetric("\(durationMinutes(session.remainingDuration))", label: "min")
        tripMetric(units.distance(session.remainingDistance).value, label: units.distance(session.remainingDistance).unit)
        tripMetric(currentSpeedLabel, label: units.speedSymbol, accessibility: "Current speed, \(currentSpeedLabel) \(units.speedSymbol)")
    }
    @ViewBuilder private var tripActions: some View {
        Button {
            if session.playbackState == .playing { session.pausePlayback() } else { session.resumePlayback() }
        } label: {
            Label(session.playbackState == .arrived ? "Arrived" : session.playbackState == .playing ? "Pause" : "Resume", systemImage: session.playbackState == .arrived ? "checkmark.circle.fill" : session.playbackState == .playing ? "pause.fill" : "play.fill")
                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.omegaGlassButton(prominent: true).disabled(session.playbackState == .arrived || concludingActionID != nil)
        Button { editRoute() } label: {
            Label("Edit Route", systemImage: "pencil").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
        }.omegaGlassButton().disabled(concludingActionID != nil)
        Menu {
            Button { openTiming(forActiveRoute: true) } label: { Label("Change Arrival Time", systemImage: "clock") }
            Button { toggleSpeed() } label: { Label("Speed Settings", systemImage: "speedometer") }
            Button { if let route = session.plannedRoute { nameRoute(route.stops) } } label: { Label("Save Route", systemImage: "bookmark") }
            Button(role: .destructive) { concludeRoute(restoring: false) } label: { Label("End Route", systemImage: "stop.fill") }
            restoreButton
            Button { setup = true } label: { Label("Settings", systemImage: "gearshape") }
        } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 44, height: 44) }
            .omegaGlassButton().accessibilityLabel("Route options")
    }
    private func openTiming(forActiveRoute: Bool) {
        if forActiveRoute && !arrivalDraftHasChanges { syncActiveTiming() }
        detent = .large; requestSheetScroll(.options)
    }
    private func requestSheetScroll(_ target: SheetScrollTarget) {
        sheetScrollTarget = target
        sheetScrollRequest += 1
    }
    private func syncActiveTiming() {
        arriveBy = session.plannedRoute?.arrivalDate != nil
        arrivalDate = session.plannedRoute?.arrivalDate ?? .now.addingTimeInterval(max(60, session.remainingDuration))
        leaveLater = false
    }
    private func concludeRoute(restoring: Bool) {
        let id = UUID(); concludingActionID = id
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
        guard concludingActionID == nil, let point = session.coordinate, let activeRoute = session.plannedRoute else { return }
        followsSimulation = false; editingRouteID = activeRoute.id
        stops = [SimulationStop(title: "Simulated Location", coordinate: point)] + session.remainingStops
        arriveBy = activeRoute.arrivalDate != nil
        arrivalDate = activeRoute.arrivalDate ?? .now.addingTimeInterval(max(60, session.remainingDuration))
        editing = true; preview = nil; needsStart = false; detent = .large
        removedStop = nil; cancelStopSearch(); invalidatePreview()
        requestSheetScroll(.top)
    }
    private func tripMetric(_ value: String, label: String, accessibility: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
            Text(label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
            .accessibilityLabel(accessibility ?? "\(value) \(label)")
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
    private func previewDuration(_ route: PlannedRoute) -> TimeInterval { previewTiming(route).duration }
    private func previewTiming(_ route: PlannedRoute, at now: Date = .now) -> (duration: TimeInterval, feasible: Bool) {
        let retained = editing ? session.currentWait : nil
        let retainedWait = retained?.remainingSeconds ?? 0
        guard arriveBy else {
            return (route.duration(atSpeed: session.speedMetersPerSecond, useRoadSpeeds: session.useRoadSpeeds) + retainedWait, true)
        }
        let profile = RouteSpeedProfile(segments: session.useRoadSpeeds ? route.speedSegments : [], length: route.distance)
        let travel: (Double) -> TimeInterval = { multiplier in
            profile.duration(from: 0, to: route.distance, fallbackSpeed: session.speedMetersPerSecond,
                             multiplier: multiplier, maximumSpeed: ArrivalAdjustment.maximumSpeedMetersPerSecond)
        }
        let events = route.timingEvents
        var lights = events.filter { $0.trafficLightID != nil }.map(\.seconds)
        let retainedRed = retained?.kind == .trafficLight
        if retainedRed { lights.append(retainedWait) }
        let fixedWait = events.filter { $0.trafficLightID == nil }.reduce(retainedRed ? 0 : retainedWait) { $0 + $1.seconds }
        // Initial estimate reserves a playback tick and a modest bridge response.
        // The engine replaces this estimate with measured latency when starting.
        let initialReserve: TimeInterval = !editing && route.distance > 0 ? 1.5 : 0
        let plan = ArrivalTimingPlan(availableSeconds: arrivalDate.timeIntervalSince(now) - initialReserve, fixedWaitSeconds: fixedWait,
                                    redLightSeconds: lights, travelDuration: travel)
        let lightWait = lights.enumerated().filter { !plan.skippedLightIndices.contains($0.offset) }.reduce(0) { $0 + $1.element }
        return (travel(plan.speedMultiplier) + fixedWait + lightWait + initialReserve, plan.isFeasible)
    }
    private func previewArrival(_ preview: PlannedRoute, at now: Date) -> String {
        if arriveBy { return arrivalDate.formatted(date: .omitted, time: .shortened) }
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
            invalidatePreview(preservingSheet: true)
        } else {
            cancelStopSearch()
            selected = stop; detent = .height(290)
        }
        savedFeedback = nil; followsSimulation = false
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
    private func cancelDraft() {
        routeTask?.cancel(); planner.cancel(); requestID = UUID(); loading = false
        editing = false; editingRouteID = nil; stops = []; preview = nil; needsStart = false; error = nil
        hasPresentedRoutePreview = false
        leaveLater = false; arriveBy = false; removedStop = nil
        cancelStopSearch()
        pruneRoadMetadataRequests()
    }
    private func center(on point: CLLocationCoordinate2D) {
        if tripIsVisible {
            camera = .camera(MapCamera(centerCoordinate: point, distance: 1100, heading: reduceMotion ? 0 : simulatedHeading, pitch: reduceMotion ? 0 : 48))
        } else {
            camera = .region(MKCoordinateRegion(center: point, latitudinalMeters: 1600, longitudinalMeters: 1600))
        }
    }
    private func invalidatePreview(preservingSheet: Bool = false) {
        // A preview can already be visible after importing/restoring a draft.
        // Treat explicit stop mutations as edits even if its first request is pending.
        if preservingSheet || preview != nil { hasPresentedRoutePreview = true }
        routeTask?.cancel(); planner.cancel(); requestID = UUID(); preview = nil; loading = false
        pruneRoadMetadataRequests()
        error = nil
        if stops.count >= 2, !needsStart { calculate() }
    }
    private func calculate() {
        guard stops.count >= 2, !needsStart else { return }
        routeTask?.cancel(); planner.cancel()
        let id = UUID(); requestID = id; loading = true; error = nil
        let requestedStops = stops
        let initialReveal = !hasPresentedRoutePreview
        let requestedDetent = detent
        routeTask = Task { @MainActor in
            do {
                var result = try await planner.calculate(stops: requestedStops)
                guard !Task.isCancelled, requestID == id else { return }
                result.stops = stops
                preview = result; loading = false
                loadRoadMetadata(for: result)
                error = nil
                fitRouteAboveCard(result)
                // Recalculating stops must not collapse or reposition an expanded editor.
                // Only the first reveal may choose a compact preview, and only if
                // the user has not changed the sheet size while the route loaded.
                if !editing, initialReveal, detent == requestedDetent { detent = previewDetent }
                hasPresentedRoutePreview = true
            } catch {
                guard requestID == id else { return }; loading = false
                if !Task.isCancelled {
                    self.error = editing
                        ? "Could not calculate route. Your original route is unchanged. Try again or change the stops. \(error.localizedDescription)"
                        : "Could not calculate route. Try again or change the stops. \(error.localizedDescription)"
                }
            }
        }
    }
    @ViewBuilder private func compactMetadataStatus(for route: PlannedRoute) -> some View {
        if roadMetadataAllowed, let request = roadMetadataRequests[route.id] {
            let status = request.isLoading
                ? (request.notice == nil ? "Loading road details…" : "Updating road details…")
                : request.failed
                    ? (request.retryAt != nil ? "Road details delayed · Retry scheduled" : request.providerUnavailable ? "Road-data servers unavailable" : "Road details unavailable")
                    : mappedTrafficLights ? "Road details updated · \(route.trafficLights.count) mapped lights" : "Road details updated"
            Button { openTiming(forActiveRoute: tripIsVisible) } label: {
                HStack(spacing: 8) {
                    if request.isLoading { ProgressView().controlSize(.small) }
                    else { Image(systemName: request.failed ? "clock.arrow.circlepath" : "checkmark.circle") }
                    Text(status).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.caption)
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("Road detail status, \(status)")
                .accessibilityHint("Opens route options.")
        }
    }
    private func metadataRetryStatus(_ retryAt: Date) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(ceil(retryAt.timeIntervalSince(context.date))))
            Text(seconds > 0 ? "Using fallback where needed. Retrying in \(seconds) seconds." : "Using fallback where needed. Retrying shortly…")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var metadataStatus: some View {
        if let route, let request = roadMetadataRequests[route.id] {
            VStack(alignment: .leading, spacing: 6) {
                if let notice = request.notice {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                if request.isLoading {
                    HStack(alignment: .top, spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(request.notice == nil
                             ? (session.plannedRoute?.id == route.id
                                ? "Loading road details. Continuing with fallback speed where needed."
                                : "Loading road details. You can start now using fallback speed.")
                             : "Updating remaining road details. New limits and lights apply as they arrive.")
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.caption).foregroundStyle(.secondary)
                } else if request.failed {
                    if let retryAt = request.retryAt {
                        metadataRetryStatus(retryAt)
                    }
                    Button("Retry Road Details") { loadRoadMetadata(for: route, force: true) }
                        .font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
        }
    }
    private func refreshTrafficPlanIfNeeded() {
        // These preferences are shared by the live route and its edit draft.
        // Turning a feature off must take effect on the moving route too.
        var routes = [UUID: PlannedRoute]()
        if let activeRoute = session.plannedRoute { routes[activeRoute.id] = activeRoute }
        if let preview { routes[preview.id] = preview }
        for var route in routes.values {
            if !roadMetadataAllowed || !mappedTrafficLights {
                route.trafficLights = []
                if !roadMetadataAllowed { route.speedSegments = [] }
                if preview?.id == route.id { preview = route }
                if session.plannedRoute?.id == route.id {
                    _ = session.applyRoadMetadata(route, clearCurrentTrafficLight: true)
                }
            }
            if roadMetadataAllowed { loadRoadMetadata(for: route) }
            else { cancelRoadMetadata(for: route.id) }
        }
        pruneRoadMetadataRequests()
    }
    private func cancelRoadMetadata(for routeID: UUID) {
        let request = roadMetadataRequests.removeValue(forKey: routeID)
        request?.task?.cancel()
    }
    private func canLoadRoadMetadata(for routeID: UUID) -> Bool {
        if session.plannedRoute?.id == routeID { return session.playbackState != .arrived }
        return preview?.id == routeID
    }
    private func pruneRoadMetadataRequests() {
        for routeID in Array(roadMetadataRequests.keys) where !canLoadRoadMetadata(for: routeID) {
            cancelRoadMetadata(for: routeID)
        }
    }
    private func loadRoadMetadata(for route: PlannedRoute, force: Bool = false, automaticRetryCount: Int = 0) {
        pruneRoadMetadataRequests()
        guard roadMetadataAllowed else { cancelRoadMetadata(for: route.id); return }
        guard canLoadRoadMetadata(for: route.id) else { return }
        let probability = redLightProbability
        let includesLights = mappedTrafficLights
        if !force, let existing = roadMetadataRequests[route.id],
           existing.probability == probability, existing.includesLights == includesLights {
            // Preserve in-flight work on Go and editor dismissal. An exhausted
            // preview gets a fresh attempt once it becomes the moving route.
            if !existing.failed || !existing.providerUnavailable || existing.task != nil || session.plannedRoute?.id != route.id { return }
        }
        let hasRetainedDetails = !route.speedSegments.isEmpty || !route.trafficLights.isEmpty
        let previousNotice = hasRetainedDetails ? roadMetadataRequests[route.id]?.notice : nil
        cancelRoadMetadata(for: route.id)
        let request = RoadMetadataRequest(probability: probability, includesLights: includesLights,
                                          notice: previousNotice)
        let id = request.id
        roadMetadataRequests[route.id] = request
        roadMetadataRequests[route.id]?.task = Task { @MainActor in
            do {
                let enriched = try await trafficPlanner.enrich(route, probability: probability, includeTrafficLights: includesLights, onUpdate: { partial in
                    guard !Task.isCancelled, roadMetadataRequests[route.id]?.id == id else { return }
                    applyRoadDetails(partial, to: route.id)
                })
                guard !Task.isCancelled, roadMetadataRequests[route.id]?.id == id else { return }
                applyRoadDetails(enriched, to: route.id)
                roadMetadataRequests[route.id]?.isLoading = false
                roadMetadataRequests[route.id]?.task = nil
            } catch {
                guard !Task.isCancelled, roadMetadataRequests[route.id]?.id == id else { return }
                guard canLoadRoadMetadata(for: route.id) else { cancelRoadMetadata(for: route.id); return }
                roadMetadataRequests[route.id]?.isLoading = false
                roadMetadataRequests[route.id]?.failed = true
                let current = preview?.id == route.id ? preview : session.plannedRoute?.id == route.id ? session.plannedRoute : nil
                let providerUnavailable = (error as? RoadMetadataError)?.retryAfter != nil
                roadMetadataRequests[route.id]?.providerUnavailable = providerUnavailable
                let failure = providerUnavailable ? "Road-data servers are busy or not responding. " : "Road details are unavailable. "
                if let current, !current.speedSegments.isEmpty || !current.trafficLights.isEmpty {
                    roadMetadataRequests[route.id]?.notice = failure + "Loaded details are retained. Unloaded sections use fallback speed; traffic-light coverage is incomplete."
                } else {
                    roadMetadataRequests[route.id]?.notice = failure + "Using fallback speed; traffic lights are not included."
                }
                // Preview retries are bounded. Once Go succeeds, keep recovering
                // in the background until arrival, End, or road details are off.
                guard providerUnavailable, session.plannedRoute?.id == route.id || automaticRetryCount < 2 else {
                    roadMetadataRequests[route.id]?.task = nil
                    return
                }
                let backoffs = [30.0, 60.0, 120.0, 300.0]
                let serverDelay = (error as? RoadMetadataError)?.retryAfter ?? 0
                let delay = max(backoffs[min(automaticRetryCount, backoffs.count - 1)],
                                serverDelay.isFinite ? max(0, serverDelay) : 0)
                roadMetadataRequests[route.id]?.retryAt = .now.addingTimeInterval(delay)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard !Task.isCancelled, roadMetadataRequests[route.id]?.id == id,
                      let current = preview?.id == route.id ? preview : session.plannedRoute?.id == route.id ? session.plannedRoute : nil else { return }
                loadRoadMetadata(for: current, force: true, automaticRetryCount: automaticRetryCount + 1)
            }
        }
    }
    private func applyRoadDetails(_ result: TrafficLightPlanResult, to routeID: UUID) {
        guard canLoadRoadMetadata(for: routeID) else { cancelRoadMetadata(for: routeID); return }
        var updated = result.route
        if let current = preview, current.id == routeID {
            updated.stops = current.stops; updated.departureDate = current.departureDate; updated.arrivalDate = current.arrivalDate
            preview = updated
        }
        if session.plannedRoute?.id == routeID { _ = session.applyRoadMetadata(updated) }
        guard preview?.id == routeID || session.plannedRoute?.id == routeID else { return }
        roadMetadataRequests[routeID]?.notice = result.notice
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

private enum OmegaMapPalette {
    // Deliberately keep Omega's deeper blue across iOS system tint revisions.
    static let blue = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 10.0 / 255, green: 132.0 / 255, blue: 1, alpha: 1)
            : UIColor(red: 0, green: 122.0 / 255, blue: 1, alpha: 1)
    })
}

private struct OmegaHeadingDot: View {
    let heading: Double
    var body: some View {
        ZStack {
            ZStack {
                OmegaHeadingCone()
                    .fill(LinearGradient(colors: [OmegaMapPalette.blue.opacity(0.02), OmegaMapPalette.blue.opacity(0.42)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 66, height: 52).offset(y: -24)
            }.frame(width: 76, height: 76).rotationEffect(.degrees(heading))
            Circle().fill(OmegaMapPalette.blue.opacity(0.12)).frame(width: 42, height: 42)
            Circle().fill(OmegaMapPalette.blue).frame(width: 24, height: 24)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        }.frame(width: 76, height: 76)
    }
}
private struct OmegaHeadingCone: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 10))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 10), control: CGPoint(x: rect.midX, y: rect.minY - 9))
        path.closeSubpath()
        return path
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
