//  SettingsView.swift
//  StikDebug
//
//  Created by Stephen on 3/27/25.

import SwiftUI
import UIKit

private enum SettingsLinks {
    static let githubStars = URL(string: "https://github.com/Omega-Omega-Omega/Omega-LocSim")!
    static let upstream = URL(string: "https://github.com/StikDebug/StikDebug")!
    static let pairingFileGuide = URL(string: "https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md")!
    static let localDevVPN = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let discord = URL(string: "https://discord.gg/qahjXNTDwS")!
}

struct SettingsView: View {
    var onClose: (() -> Void)? = nil

    init(onClose: (() -> Void)? = nil) { self.onClose = onClose }
    @AppStorage(UserDefaults.Keys.txmOverride) private var overrideTXMDetection = false
    @AppStorage(UserDefaults.Keys.confirmExternalJITRequests) private var confirmExternalJITRequests = true
    @AppStorage("routeSpeedUsesMPH") private var usesMPH = true
    @AppStorage("keepAliveAudio") private var keepAliveAudio = true
    @AppStorage("keepAliveLocation") private var keepAliveLocation = true
    @AppStorage(UserDefaults.Keys.targetDeviceIP) private var targetDeviceIP = DeviceConnectionContext.defaultTargetIPAddress
    @AppStorage("TunnelRemotePairingPort") private var remotePairingPortOverride = ""
    @AppStorage(UserDefaults.Keys.mallocDebug) private var mallocDebug = false

    private enum ConnectionField: Hashable {
        case address
        case port
    }

    @FocusState private var focusedConnectionField: ConnectionField?
    @State private var targetDeviceIPInput = ""
    @State private var remotePairingPortInput = ""
    @State private var automaticPortPlaceholder = "Discovering…"
    @State private var isShowingPairingFilePicker = false
    @State private var isImportingFile = false
    @State private var pairingImportMessage: (text: String, isError: Bool)?
    @State private var showDDIConfirmation = false
    @State private var isRedownloadingDDI = false
    @State private var ddiDownloadProgress: Double = 0.0
    @State private var ddiStatusMessage: String = ""
    @State private var ddiResultMessage: (text: String, isError: Bool)?

    private var appVersion: String {
        let marketingVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return marketingVersion
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    brandHeader
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                }

                Section {
                    sourceLink
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                }

                Section {
                    Picker("Measurement System", selection: $usesMPH) {
                        Text("US Imperial").tag(true)
                        Text("Metric").tag(false)
                    }
                } header: { Text("Units") } footer: {
                    Text(usesMPH ? "Distances in miles and feet. Speeds in mph." : "Distances in kilometers and meters. Speeds in km/h.")
                }

                Section("Pairing File") {
                    pairingImportButton
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)

                    if isImportingFile {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Importing pairing file…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if let pairingImportMessage {
                        Label(
                            pairingImportMessage.text,
                            systemImage: pairingImportMessage.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(pairingImportMessage.isError ? .red : .green)
                    }
                }

                Section {
                    Toggle(isOn: $keepAliveAudio) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Silent Audio")
                            Text("Uses silent audio to support background simulation.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveAudio) { _, enabled in
                        handleAudioKeepAliveChange(enabled)
                    }

                    Toggle(isOn: $keepAliveLocation) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Background Location")
                            Text("Uses low-accuracy location to stay alive when an activity needs it.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onChange(of: keepAliveLocation) { _, enabled in
                        handleLocationKeepAliveChange(enabled)
                    }

                } header: {
                    Text("Background Keep-Alive")
                }

                Section("Advanced") {
                    HStack {
                        Text("Target Device IP")
                        Spacer()
                        TextField(DeviceConnectionContext.defaultTargetIPAddress, text: $targetDeviceIPInput)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .keyboardType(.decimalPad)
                            .focused($focusedConnectionField, equals: .address)
                            .frame(maxWidth: 160)
                    }
                    HStack {
                        Text("Remote Pairing Port")
                        Spacer()
                        TextField(automaticPortPlaceholder, text: $remotePairingPortInput)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .keyboardType(.numberPad)
                            .focused($focusedConnectionField, equals: .port)
                            .frame(maxWidth: 160)
                    }
                    Button { openAppFolder() } label: {
                        Label("App Folder", systemImage: "folder")
                    }.foregroundStyle(.primary)
                    Button { showDDIConfirmation = true } label: {
                        Label("Redownload DDI", systemImage: "arrow.down.circle")
                    }.foregroundStyle(.primary).disabled(isRedownloadingDDI)
                    if isRedownloadingDDI {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: ddiDownloadProgress, total: 1.0)
                            Text(ddiStatusMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let result = ddiResultMessage {
                        Text(result.text).font(.caption).foregroundStyle(result.isError ? .red : .green)
                    }
                }

                Section("Road Data") {
                    Link("© OpenStreetMap contributors", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    Link("Road Data Backup & Privacy", destination: URL(string: "https://overpass.private.coffee/")!)
                    Text("Mapped speed limits when available; estimates otherwise. Simulation only.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Help") {
                    Link(destination: SettingsLinks.pairingFileGuide) {
                        Label("Pairing File Guide", systemImage: "questionmark.circle")
                    }
                    Link(destination: SettingsLinks.localDevVPN) {
                        Label("Download LocalDevVPN", systemImage: "arrow.down.circle")
                    }
                    Link(destination: SettingsLinks.discord) {
                        Label("Discord Support", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                Section {
                    Text(versionFooter)
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Omega Settings")
            .toolbar {
                if let onClose {
                    ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(KeyboardTapDismissal())
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            targetDeviceIPInput = targetDeviceIP
            remotePairingPortInput = remotePairingPortOverride
        }
        .task {
            let result = await Task.detached {
                RemotePairingPortResolver.discover()
            }.value
            automaticPortPlaceholder = result.source == "Bonjour"
                ? "Bonjour (\(result.port))"
                : "Fallback (\(result.port))"
        }
        .onChange(of: focusedConnectionField) { _, field in
            if field == nil {
                applyConnectionSettings()
            }
        }
        .onDisappear {
            applyConnectionSettings()
        }
        .fileImporter(
            isPresented: $isShowingPairingFilePicker,
            allowedContentTypes: PairingFileStore.supportedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }

                let fileManager = FileManager.default
                isImportingFile = true
                pairingImportMessage = nil

                do {
                    try PairingFileStore.importFromPicker(url, fileManager: fileManager)
                    isImportingFile = false
                    pairingImportMessage = ("Imported successfully", false)
                    startTunnelInBackground()
                    schedulePairingStatusDismiss()
                } catch {
                    isImportingFile = false
                    pairingImportMessage = ("Import failed: \(error.localizedDescription)", true)
                    schedulePairingStatusDismiss()
                }
            case .failure(let error):
                isImportingFile = false
                pairingImportMessage = ("Import failed: \(error.localizedDescription)", true)
                schedulePairingStatusDismiss()
            }
        }
        .confirmationDialog("Redownload DDI Files?", isPresented: $showDDIConfirmation, titleVisibility: .visible) {
            Button("Redownload", role: .destructive) {
                redownloadDDIPressed()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Existing DDI files will be removed before downloading fresh copies.")
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            Image("OmegaLocSimBrand")
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityHidden(true)
            Text("Omega LocSim")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Link("Built on StikDebug", destination: SettingsLinks.upstream)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .modifier(SettingsGlassSurface())
    }

    @ViewBuilder
    private var sourceLink: some View {
        if #available(iOS 26.0, *) {
            sourceLinkContent.buttonStyle(.glass)
        } else {
            sourceLinkContent.buttonStyle(.bordered)
        }
    }

    private var sourceLinkContent: some View {
        Link(destination: SettingsLinks.githubStars) {
            Label("Omega Source", systemImage: "chevron.left.forwardslash.chevron.right")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .controlSize(.large)
    }

    @ViewBuilder
    private var pairingImportButton: some View {
        if #available(iOS 26.0, *) {
            pairingImportButtonContent.buttonStyle(.glassProminent)
        } else {
            pairingImportButtonContent.buttonStyle(.borderedProminent)
        }
    }

    private var pairingImportButtonContent: some View {
        Button { isShowingPairingFilePicker = true } label: {
            Label("Import Pairing File", systemImage: "doc.badge.plus")
                .frame(maxWidth: .infinity, minHeight: 48)
        }
        .controlSize(.large)
        .disabled(isImportingFile)
    }

    private func applyConnectionSettings() {
        let address = targetDeviceIPInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = remotePairingPortInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address != targetDeviceIP || port != remotePairingPortOverride else { return }
        targetDeviceIP = address
        remotePairingPortOverride = port
        TunnelManager.shared.restart()
    }

    private var versionFooter: String {
        let processInfo = ProcessInfo.processInfo
        let txmLabel: String
        if processInfo.isTXMOverridden {
            txmLabel = "TXM (Override)"
        } else {
            txmLabel = processInfo.hasTXM ? "TXM" : "Non TXM"
        }
        return "Version \(appVersion) • iOS \(UIDevice.current.systemVersion) • \(txmLabel)"
    }

    private func handleAudioKeepAliveChange(_ enabled: Bool) {
        if !enabled, !keepAliveLocation {
            keepAliveLocation = true
            BackgroundLocationManager.shared.requestAuthorizationIfNeeded()
        }
        BackgroundAudioManager.shared.configurationDidChange()
        BackgroundLocationManager.shared.configurationDidChange()
    }

    private func handleLocationKeepAliveChange(_ enabled: Bool) {
        if enabled {
            BackgroundLocationManager.shared.requestAuthorizationIfNeeded()
        } else if !keepAliveAudio {
            keepAliveAudio = true
        }
        BackgroundAudioManager.shared.configurationDidChange()
        BackgroundLocationManager.shared.configurationDidChange()
    }

    // MARK: - Business Logic

    private func openAppFolder() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let path = documentsURL.absoluteString.replacingOccurrences(of: "file://", with: "shareddocuments://")
        if let url = URL(string: path) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    private func redownloadDDIPressed() {
        guard !isRedownloadingDDI else { return }
        Task {
            await MainActor.run {
                isRedownloadingDDI = true
                ddiDownloadProgress = 0
                ddiStatusMessage = "Preparing download…"
                ddiResultMessage = nil
            }
            do {
                try await redownloadDDI { progress, status in
                    Task { @MainActor in
                        self.ddiDownloadProgress = progress
                        self.ddiStatusMessage = status
                    }
                }
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("DDI files refreshed successfully.", false)
                }
            } catch {
                await MainActor.run {
                    isRedownloadingDDI = false
                    ddiResultMessage = ("Failed to redownload DDI files: \(error.localizedDescription)", true)
                }
            }
        }
        scheduleDDIStatusDismiss()
    }

    private func schedulePairingStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isImportingFile {
                    pairingImportMessage = nil
                }
            }
        }
    }

    private func scheduleDDIStatusDismiss() {
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run {
                if !isRedownloadingDDI {
                    ddiResultMessage = nil
                }
            }
        }
    }
}

private struct SettingsGlassSurface: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if reduceTransparency {
            content.background(Color(uiColor: .secondarySystemGroupedBackground), in: shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

private struct KeyboardTapDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> DismissalView {
        DismissalView()
    }

    func updateUIView(_ uiView: DismissalView, context: Context) {}

    final class DismissalView: UIView, UIGestureRecognizerDelegate {
        private weak var attachedWindow: UIWindow?
        private lazy var tapRecognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            attachedWindow?.removeGestureRecognizer(tapRecognizer)
            attachedWindow = window
            window?.addGestureRecognizer(tapRecognizer)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView || current is UIInputView {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }
    }
}
