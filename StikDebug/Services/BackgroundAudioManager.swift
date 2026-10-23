//
//  BackgroundAudioManager.swift
//  StikDebug
//

import AVFoundation
import Darwin

final class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()

    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var isRunning = false
    private var activityCount = 0
    private var healthCheckTimer: Timer?
    private var isInterrupted = false

    var isKeepingAlive: Bool { isRunning && engine.isRunning && player.isPlaying && !isInterrupted }

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }

    func configurationDidChange() {
        refreshRunningState()
    }

    func requestStart() {
        activityCount += 1
        refreshRunningState()
    }

    func requestStop() {
        activityCount = max(activityCount - 1, 0)
        refreshRunningState()
    }

    private func refreshRunningState() {
        let shouldRun = activityCount > 0 && UserDefaults.standard.bool(forKey: "keepAliveAudio")
        guard shouldRun != isRunning else {
            if shouldRun {
                recoverIfNeeded()
            }
            return
        }

        isRunning = shouldRun
        if shouldRun {
            startEngine()
            startHealthCheck()
        } else {
            healthCheckTimer?.invalidate()
            healthCheckTimer = nil
            player.stop()
            engine.stop()
            isInterrupted = false
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func startEngine() {
        do {
            engine.stop()
            player.stop()
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()

            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)

            engine.attach(player)
            // A fixed valid PCM format also works while the output route is
            // changing; the engine performs conversion to the hardware format.
            guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
                  let buffer = silenceBuffer(format: format) else {
                throw NSError(domain: "OmegaBackgroundAudio", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to prepare silent audio"])
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            try engine.start()
            player.play()
        } catch {
            LogManager.shared.addErrorLog("BackgroundAudioManager: \(error.localizedDescription)")
        }
    }

    private func silenceBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        // Explicitly clear every audio channel; newly allocated PCM memory must
        // never be assumed to contain silence.
        for audioBuffer in UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList) {
            if let data = audioBuffer.mData { memset(data, 0, Int(audioBuffer.mDataByteSize)) }
        }
        return buffer
    }

    // Recover a stopped player or engine without taking audio focus away from
    // phone calls and other active system interruptions.
    private func startHealthCheck() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.recoverIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }

    private func recoverIfNeeded() {
        guard isRunning, !isInterrupted, !engine.isRunning || !player.isPlaying else { return }
        if !engine.isRunning || player.engine == nil {
            // Configuration changes and failed session activation can discard
            // scheduled buffers; rebuild so recovery always schedules silence.
            startEngine()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            player.play()
        } catch {
            // The system still owns the session; retry on the next health check.
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isInterrupted = type == .began
            if type == .ended { self.recoverIfNeeded() }
        }
    }

    @objc private func handleEngineConfigurationChange() {
        DispatchQueue.main.async { [weak self] in self?.recoverIfNeeded() }
    }

    @objc private func handleMediaServicesReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.isInterrupted = false
            self.startEngine()
        }
    }
}
