#if DEBUG
import Foundation
import Combine

/// Development-only, bounded evidence for device/background acceptance. No
/// coordinates, search strings, pairing records or credentials are recorded.
@MainActor
final class OmegaDiagnostics {
    static let shared = OmegaDiagnostics()
    private var subscription: AnyCancellable?
    private var timer: Timer?
    private var acceptedUpdates = 0
    private var scene = "active"
    private var samples: [[String: Any]] = []

    func start() {
        guard timer == nil else { return }
        subscription = LocationSimulationSession.shared.$coordinate.dropFirst().sink { [weak self] _ in
            self?.acceptedUpdates += 1
        }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.record() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        record()
    }

    func sceneChanged(_ value: String) { scene = value; record() }

    private func record() {
        let session = LocationSimulationSession.shared
        let sample: [String: Any] = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "uptime": ProcessInfo.processInfo.systemUptime,
            "scene": scene,
            "active": session.isActive,
            "playback": String(describing: session.playbackState),
            "acceptedUpdates": acceptedUpdates,
            "traveledMeters": session.traveled,
            "remainingMeters": session.remainingDistance,
            "waitSeconds": session.currentWait?.remainingSeconds ?? 0,
            "effectiveSpeedMPS": session.effectiveSpeedMetersPerSecond,
            "audioRunning": BackgroundAudioManager.shared.isKeepingAlive,
            "locationRunning": BackgroundLocationManager.shared.isKeepingAlive,
            "locationAuthorization": BackgroundLocationManager.shared.authorizationDescription,
            "hasError": session.playbackError != nil
        ]
        samples.append(sample)
        if samples.count > 200 { samples.removeFirst(samples.count - 200) }
        guard let data = try? JSONSerialization.data(withJSONObject: ["samples": samples], options: [.sortedKeys]) else { return }
        let url = URL.documentsDirectory.appendingPathComponent("omega-diagnostics.json")
        try? data.write(to: url, options: .atomic)
    }
}
#endif
