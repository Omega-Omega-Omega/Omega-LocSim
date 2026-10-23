//
//  BackgroundLocationManager.swift
//  StikDebug
//

import CoreLocation
import UIKit

final class BackgroundLocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = BackgroundLocationManager()

    private let locationManager = CLLocationManager()
    private var isRunning = false
    private var activityCount = 0
    private var isRequestingAuthorization = false
    private var didRequestAlwaysUpgrade = false
    private var didShowAuthorizationAlert = false

    var isKeepingAlive: Bool { isRunning }
    var authorizationDescription: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways: return "Always"
        case .authorizedWhenInUse: return "While Using"
        case .notDetermined: return "Not Requested"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
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

    func requestAuthorizationIfNeeded() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            return
        case .authorizedWhenInUse:
            requestAlwaysUpgradeIfNeeded()
        case .notDetermined:
            guard !isRequestingAuthorization else { return }
            isRequestingAuthorization = true
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            restoreAudioFallback()
        @unknown default:
            restoreAudioFallback()
        }
    }

    private func requestAlwaysUpgradeIfNeeded() {
        guard !didRequestAlwaysUpgrade else { return }
        didRequestAlwaysUpgrade = true
        locationManager.requestAlwaysAuthorization()
    }

    private func refreshRunningState() {
        let shouldRun = activityCount > 0 && UserDefaults.standard.bool(forKey: "keepAliveLocation")
        guard shouldRun else {
            if isRunning { locationManager.stopUpdatingLocation() }
            isRunning = false
            return
        }

        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            // When-In-Use permission can continue a foreground-started location
            // session in the background. Never wait for an Always callback that
            // iOS may legitimately omit when an upgrade prompt is deferred.
            if !isRunning {
                locationManager.startUpdatingLocation()
                isRunning = true
            }
            if locationManager.authorizationStatus == .authorizedWhenInUse {
                requestAlwaysUpgradeIfNeeded()
            }
        case .notDetermined:
            requestAuthorizationIfNeeded()
        case .denied, .restricted:
            restoreAudioFallback()
        @unknown default:
            restoreAudioFallback()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isRequestingAuthorization = false
            didShowAuthorizationAlert = false
            refreshRunningState()
        case .denied, .restricted:
            let hadRequest = isRequestingAuthorization || activityCount > 0
            isRequestingAuthorization = false
            if hadRequest { restoreAudioFallback() }
        case .notDetermined:
            return
        @unknown default:
            isRequestingAuthorization = false
            if activityCount > 0 { restoreAudioFallback() }
        }
    }

    private func restoreAudioFallback() {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "keepAliveLocation")
        defaults.set(true, forKey: "keepAliveAudio")
        refreshRunningState()
        BackgroundAudioManager.shared.configurationDidChange()

        guard !didShowAuthorizationAlert else { return }
        didShowAuthorizationAlert = true
        showAlert(
            title: "Location Access Refused",
            message: "Location access was refused. Open Settings to enable it.",
            showOk: false,
            showTryAgain: true,
            primaryButtonText: "Settings"
        ) { openSettings in
            guard openSettings,
                  let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                return
            }
            UIApplication.shared.open(settingsURL)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location fixes may fail (e.g. no GPS indoors) — that's fine.
        // The manager just needs to be running, not actually fix a location.
    }
}
