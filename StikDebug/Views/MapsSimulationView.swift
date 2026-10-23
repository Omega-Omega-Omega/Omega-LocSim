import SwiftUI
import MapKit
import UniformTypeIdentifiers

struct LocationSimulationView: View {
    @ObservedObject private var session = LocationSimulationSession.shared
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var sheetVisible = true
    @State private var detent: PresentationDetent = .height(290)
    @State private var query = ""
    @State private var results: [MKMapItem] = []
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
    @State private var bookmarks: [LocationBookmark] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var routeTask: Task<Void, Never>?
    @State private var planner = RoutePlanner()
    @State private var requestID = UUID()
    @State private var searchID = UUID()
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

    private enum RouteSearchTarget: Equatable {
        case startingLocation
        case replace(UUID)
        case addStop
    }

    private var route: PlannedRoute? { editing ? (preview ?? session.plannedRoute) : (session.plannedRoute ?? preview) }
    private var visibleStops: [SimulationStop] { stops.isEmpty ? (route?.stops ?? []) : stops }
    private var searchPrompt: String {
        switch searchTarget {
        case .startingLocation: return "Search starting location"
        case .replace: return "Search replacement stop"
        case .addStop: return "Search for a stop"
        case nil: return "Search Maps"
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
        Binding(get: { session.speedMetersPerSecond * (usesMPH ? 2.236936 : 3.6) },
                set: { session.speedMetersPerSecond = $0 / (usesMPH ? 2.236936 : 3.6) })
    }
    private var speedRange: ClosedRange<Double> {
        // Unit conversion must preserve speed, including values near either slider endpoint.
        min(1, speed.wrappedValue)...max(usesMPH ? 85 : 135, speed.wrappedValue)
    }
    private var tripIsVisible: Bool { session.plannedRoute != nil && !editing }
    private var playbackTitle: String {
        session.playbackState == .playing ? "Simulating" : session.playbackState == .arrived ? "Arrived" : "Paused"
    }
    private var speedLabel: String { "\(Int(speed.wrappedValue.rounded())) \(usesMPH ? "mph" : "km/h")" }
    private var compactDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 390 : 170) }
    private var previewDetent: PresentationDetent { .height(dynamicTypeSize.isAccessibilitySize ? 600 : 420) }
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
                        Button { imports = true } label: {
                            Label("Saved Places & Import", systemImage: "bookmark.fill")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
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
            .sheet(isPresented: $imports) {
                NavigationStack {
                    List {
                        Button("Import Coordinates") { imports = false; filePicker = true }
                        ForEach(bookmarks) { bookmark in
                            Button(bookmark.name) {
                                choose(SimulationStop(title: bookmark.name, coordinate: CLLocationCoordinate2D(latitude: bookmark.latitude, longitude: bookmark.longitude)))
                                imports = false
                            }
                        }
                    }.navigationTitle("Saved Places")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { imports = false } } }
                }
            }
            .fileImporter(isPresented: $filePicker, allowedContentTypes: CoordinateImportParser.supportedContentTypes) { result in
                do {
                    let url = try result.get()
                    let points = try CoordinateImportParser.parse(url: url)
                    if points.count == 1, let first = points.first {
                        choose(SimulationStop(title: url.deletingPathExtension().lastPathComponent, coordinate: first))
                    } else {
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
            if let data = UserDefaults.standard.data(forKey: "locationBookmarks"),
               let saved = try? JSONDecoder().decode([LocationBookmark].self, from: data) { bookmarks = saved }
            if FileManager.default.fileExists(atPath: PairingFileStore.prepareURL().path) { startTunnelInBackground() }
        }
        .onChange(of: query) { _, value in search(value) }
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

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(searchPrompt, text: $query)
                .submitLabel(.search).autocorrectionDisabled().focused($searchFocused)
                .accessibilityLabel(searchPrompt)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44) }
                    .accessibilityLabel("Clear search")
            }
        }.frame(minHeight: 44).padding(.horizontal, 13).padding(.vertical, 3)
            .omegaGlass(in: Capsule(), interactive: true)
    }
    private var searchResults: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                Button { choose(SimulationStop(title: item.name ?? "Place", coordinate: item.placemark.coordinate)) } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.circle.fill").font(.title).foregroundStyle(.red)
                        VStack(alignment: .leading) {
                            Text(item.name ?? "Place").foregroundStyle(.primary)
                            Text(item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }.padding(.vertical, 12)
                }
                Divider()
            }
        }
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
                Button {
                    bookmarks.append(LocationBookmark(name: place.title, latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
                    if let data = try? JSONEncoder().encode(bookmarks) { UserDefaults.standard.set(data, forKey: "locationBookmarks") }
                } label: { Image(systemName: "bookmark").font(.title3).frame(width: 44, height: 44) }
                    .accessibilityLabel("Save place")
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
            }
        }
    }
    private func previewSummary(_ preview: PlannedRoute) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(minutes(for: preview.distance)) min").font(.title2.bold())
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("\(arrivalTime(for: preview.distance, at: context.date)) ETA · \(distanceLabel(preview.distance))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Label("At \(speedLabel)", systemImage: "location.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                applyingRoute = true; searchFocused = false
                Task {
                    let didStart = await session.play(preview)
                    applyingRoute = false
                    if didStart {
                        cancelDraft(); showsSpeed = false; followsSimulation = true
                        if let point = session.coordinate { center(on: point) }
                        detent = compactDetent
                    }
                }
            } label: {
                VStack(spacing: 2) {
                    if applyingRoute { ProgressView().tint(.white) }
                    Text(editing ? "Apply" : "GO").font(.title3.bold())
                    if editing { Text("& Resume").font(.caption2.weight(.semibold)) }
                }.frame(minWidth: 56, minHeight: 56)
            }.buttonBorderShape(.roundedRectangle(radius: 20))
                .omegaGlassButton(prominent: true).tint(.green).disabled(applyingRoute)
                .accessibilityLabel(editing ? "Apply and resume route" : "Go, start simulation")
        }.padding(14).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 24))
    }
    private func stopRow(_ stop: SimulationStop, at index: Int) -> some View {
        let isStart = !needsStart && index == 0
        let firstMovableIndex = needsStart ? 0 : 1
        return HStack(spacing: 12) {
            Image(systemName: isStart ? "location.circle.fill" : "mappin.circle.fill")
                .font(.title2).foregroundStyle(isStart ? .blue : .orange).accessibilityHidden(true)
            Button { beginStopSearch(.replace(stop.id)) } label: {
                Text(stop.title).fontWeight(.medium).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }.foregroundStyle(.primary).disabled(editing && isStart)
                .accessibilityLabel(isStart ? "Starting location: \(stop.title)" : "Replace stop: \(stop.title)")
            if !isStart {
                Menu {
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
        detent = showsSpeed ? .large : (tripIsVisible ? compactDetent : previewDetent)
    }
    private var speedControl: some View {
        VStack {
            HStack {
                Text("Simulation speed").font(.subheadline.weight(.semibold)); Spacer()
                Text(speedLabel).font(.subheadline).monospacedDigit()
                Button(usesMPH ? "km/h" : "mph") { usesMPH.toggle() }.font(.caption).frame(minWidth: 44, minHeight: 44)
            }
            Slider(value: speed, in: speedRange, step: 1).accessibilityLabel("Simulation speed")
        }.padding(.horizontal, 14).padding(.bottom, 10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 22))
    }
    private var playbackBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: session.playbackState == .playing ? "location.north.circle.fill" : session.playbackState == .arrived ? "checkmark.circle.fill" : "pause.circle.fill")
                .font(.system(size: 36)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(playbackTitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Text(session.remainingStops.first?.title ?? session.plannedRoute?.stops.last?.title ?? "Route")
                    .font(.title3.bold()).lineLimit(2)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(18).frame(minHeight: 88)
            .omegaGlass(in: RoundedRectangle(cornerRadius: 30))
    }
    private var tripCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                tripMetric(session.playbackState == .paused ? "—" : arrivalTime(for: session.remainingDistance), label: "arrival")
                tripMetric("\(minutes(for: session.remainingDistance))", label: "min")
                tripMetric(String(format: "%.1f", session.remainingDistance / (usesMPH ? 1609.344 : 1000)), label: usesMPH ? "mi" : "km")
            }
            HStack(spacing: 8) {
                Button {
                    guard !preparingEdit else { return }
                    if session.playbackState == .playing { session.pausePlayback() } else { session.resumePlayback() }
                } label: {
                    Label(session.playbackState == .playing ? "Pause" : "Resume", systemImage: session.playbackState == .playing ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 32)
                }.omegaGlassButton(prominent: true).disabled(session.playbackState == .arrived || preparingEdit || concludingActionID != nil)
                Button { toggleSpeed() } label: {
                    Text(speedLabel).font(.subheadline.weight(.semibold)).frame(minHeight: 32)
                }.omegaGlassButton().accessibilityLabel("Change simulation speed, \(speedLabel)")
                Menu {
                    Button { editRoute() } label: { Label("Edit Route", systemImage: "pencil") }.disabled(preparingEdit || concludingActionID != nil)
                    Button(role: .destructive) { concludeRoute(restoring: false) } label: { Label("End Route", systemImage: "stop.fill") }
                    restoreButton
                    Button { setup = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis").font(.title3).frame(width: 32, height: 32) }
                    .omegaGlassButton().accessibilityLabel("Route controls: edit, end, restore and settings")
            }
            if showsSpeed { speedControl }
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
    private func minutes(for distance: Double) -> Int { Int(ceil(distance / max(0.1, session.speedMetersPerSecond) / 60)) }
    private func distanceLabel(_ distance: Double) -> String {
        String(format: "%.1f %@", distance / (usesMPH ? 1609.344 : 1000), usesMPH ? "mi" : "km")
    }
    private func arrivalTime(for distance: Double, at now: Date = .now) -> String {
        now.addingTimeInterval(distance / max(0.1, session.speedMetersPerSecond)).formatted(date: .omitted, time: .shortened)
    }
    private func choose(_ stop: SimulationStop) {
        guard !applyingRoute else { return }
        if !stops.isEmpty || editing || needsStart {
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
        searchTask?.cancel(); searchID = UUID()
        query = ""; results = []; searchTarget = target
        detent = .large; searchFocused = true
    }
    private func cancelStopSearch() {
        searchTask?.cancel(); searchID = UUID()
        query = ""; results = []; searchTarget = nil; searchFocused = false
    }
    private func cancelDraft() {
        routeTask?.cancel(); planner.cancel(); requestID = UUID(); loading = false
        editing = false; stops = []; preview = nil; needsStart = false; error = nil; showsSpeed = false
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
                let result = try await planner.calculate(stops: requestedStops)
                guard !Task.isCancelled, requestID == id else { return }
                preview = result; loading = false
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
    private func search(_ text: String) {
        searchTask?.cancel()
        let id = UUID(); searchID = id
        guard !text.isEmpty else { results = []; return }
        error = nil
        detent = .large
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(300))
                let request = MKLocalSearch.Request(); request.naturalLanguageQuery = text
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled, searchID == id else { return }
                results = response.mapItems
            } catch { if !Task.isCancelled, searchID == id { self.error = error.localizedDescription } }
        }
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
