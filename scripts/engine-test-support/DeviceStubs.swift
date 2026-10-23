import Foundation
// Only the injected test transport is used. Any real device call is a test failure.
enum DeviceConnectionContext { static let targetIPAddress = "test-only" }
enum PairingFileStore { static func prepareURL() -> URL { URL(fileURLWithPath: "/tmp/test-only") } }
enum LocationSimulationCommandQueue { static let shared = DispatchQueue(label: "test-device-queue") }
func simulate_location(_ ip: String, _ latitude: Double, _ longitude: Double, _ path: String) -> Int32 { fatalError("Unexpected real-device transport") }
func clear_simulated_location() -> Int32 { fatalError("Unexpected real-device transport") }
final class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()
    func requestStart() { fatalError("Unexpected background side effect") }
    func requestStop() { fatalError("Unexpected background side effect") }
}
final class BackgroundLocationManager {
    static let shared = BackgroundLocationManager()
    func requestStart() { fatalError("Unexpected background side effect") }
    func requestStop() { fatalError("Unexpected background side effect") }
}
