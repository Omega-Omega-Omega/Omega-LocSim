//
//  StikDebugApp.swift
//  StikDebug
//
//  Created by Stephen on 3/26/25.
//

import SwiftUI

@main
struct StikDebugApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var shouldAttemptTunnelReconnect = false

    init() {
        AppBootstrapper.configure()
    }

    var body: some Scene {
        WindowGroup {
            LocationSimulationView()
                .task {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--omega-approved-setup") {
                        for key in ["omegaRoadMetadataAllowed", "omegaMappedTrafficLights", "routeSpeedUsesMPH", "omegaUseRoadSpeeds", "keepAliveAudio", "keepAliveLocation"] {
                            UserDefaults.standard.set(true, forKey: key)
                        }
                        BackgroundLocationManager.shared.requestAuthorizationIfNeeded()
                    }
                    OmegaDiagnostics.shared.start()
                    #endif
                    await downloadMissingDeveloperDiskImageFiles()
                    #if DEBUG
                    await OmegaDeviceAcceptanceRunner.runIfRequested()
                    #endif
                }
                .onChange(of: scenePhase) { _, newPhase in
                    handleScenePhaseChange(newPhase)
                }
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        #if DEBUG
        OmegaDiagnostics.shared.sceneChanged(String(describing: newPhase))
        #endif
        switch newPhase {
        case .background:
            shouldAttemptTunnelReconnect = true
        case .active:
            if shouldAttemptTunnelReconnect {
                shouldAttemptTunnelReconnect = false
                startTunnelInBackground(showErrorUI: false)
            }
        default:
            break
        }
    }

    private func downloadMissingDeveloperDiskImageFiles() async {
        do {
            try await DeveloperDiskImageService.shared.downloadMissingFiles()
            MountingProgress.shared.pubMount()
        } catch {
            await MainActor.run {
                showAlert(
                    title: "An Error has Occurred",
                    message: "[Download DDI Error]: \(error.localizedDescription)",
                    showOk: true
                )
            }
        }
    }
}
