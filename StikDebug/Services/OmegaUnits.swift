import Foundation

/// One preference controls every distance and speed shown by Omega.
enum OmegaUnits {
    case imperial, metric

    init(usesMPH: Bool) { self = usesMPH ? .imperial : .metric }
    var speedSymbol: String { self == .imperial ? "mph" : "km/h" }
    var speedMultiplier: Double { self == .imperial ? 2.2369362920544 : 3.6 }
    var maximumSpeed: Double { self == .imperial ? 85 : 135 }

    func distance(_ meters: Double) -> (value: String, unit: String) {
        let meters = meters.isFinite ? max(0, meters) : 0
        if self == .imperial {
            let miles = meters / 1609.344
            if miles < 0.1 { return (String(Int((meters / 0.3048).rounded())), "ft") }
            return (String(format: "%.1f", miles), "mi")
        }
        if meters < 1000 { return (String(Int(meters.rounded())), "m") }
        return (String(format: "%.1f", meters / 1000), "km")
    }

    func distanceLabel(_ meters: Double) -> String {
        let parts = distance(meters)
        return "\(parts.value) \(parts.unit)"
    }
}
