import Foundation
import CoreLocation
import Logging
import Combine
import SwiftUI

/// Defines user-facing errors related to location services.
enum LocationError: AppError {
    case accessDenied
    case failedToRetrieveLocation(Error)

    var title: String {
        switch self {
        case .accessDenied:
            return "Location Access Denied"
        case .failedToRetrieveLocation:
            return "Location Error"
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Location access is disabled or restricted. Please enable location access for this app in your device's Settings to use this feature."
        case .failedToRetrieveLocation(let underlyingError):
            return "The app failed to get your location. Please try again. (Reason: \(underlyingError.localizedDescription))"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .accessDenied:
            return "LocationError.accessDenied"
        case .failedToRetrieveLocation:
            return "LocationError.failedToRetrieveLocation"
        }
    }
}

/// A manager for handling location updates and managing location-related permissions,
/// incorporating filtering and clearer state management.
final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    // MARK: - Published Properties
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var isReceivingLocationUpdates: Bool = false
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var lastAccuracy: CLLocationAccuracy?
    @Published var lastHeading: CLLocationDirection?
    @Published var lastTimestamp: TimeInterval?

    // MARK: - Private Properties
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.LocationManager")
    private let locationManager = CLLocationManager()

    // MARK: - Configuration Constants
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let activityType: CLActivityType = .otherNavigation
    private let maximumLocationAge: TimeInterval = 5.0
    private let minimumHorizontalAccuracy: CLLocationAccuracy = 100.0
    private let minimumSpeedForCourse: CLLocationSpeed = 0.5

    // MARK: - Initialization
    override init() {
        _authorizationStatus = Published(initialValue: locationManager.authorizationStatus)
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = self.desiredAccuracy
        locationManager.activityType = self.activityType
        managerLogger.info("LocationManager initialized with desired accuracy: \(desiredAccuracy)")
    }

    // MARK: - Public Methods
    /// Starts location services if authorization allows.
    func startLocationUpdates() {
        let status = locationManager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            managerLogger.info("Starting location updates.")
            locationManager.startUpdatingLocation()
        } else {
            logError(LocationError.accessDenied, managerLogger)
        }
    }

    /// Stops location services.
    func stopLocationUpdates() {
        managerLogger.info("Stopping location updates.")
        locationManager.stopUpdatingLocation()
        DispatchQueue.main.async {
            self.isReceivingLocationUpdates = false
        }
    }

    /// Requests "When In Use" location authorization from the user.
    /// Call this when the feature needing location is first accessed.
    func requestAuthorization() {
        if locationManager.authorizationStatus == .notDetermined {
            managerLogger.info("Requesting When In Use location authorization.")
            locationManager.requestWhenInUseAuthorization()
        } else {
            managerLogger.debug("Authorization already determined (Status: \(locationManager.authorizationStatus.rawValue)).")
        }
    }

    // MARK: - Private Update Logic
    /// Updates the published properties with the latest valid location data.
    /// Ensures updates happen on the main thread.
    /// - Parameter location: The validated CLLocation object.
    private func updateWithValidatedLocation(_ location: CLLocation) {
        DispatchQueue.main.async {
            self.lastKnownLocation = location.coordinate
            self.lastAccuracy = location.horizontalAccuracy
            self.lastTimestamp = location.timestamp.timeIntervalSince1970
            self.isReceivingLocationUpdates = true

            if location.courseAccuracy >= 0 && location.speed >= self.minimumSpeedForCourse {
                self.lastHeading = location.course
            } else {
                self.lastHeading = nil
            }
        }
    }

    /// Updates the authorization status and handles logging.
    /// Ensures updates happen on the main thread.
    /// - Parameter status: The new CLAuthorizationStatus.
    private func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
            if status != .authorizedWhenInUse && status != .authorizedAlways {
                self.isReceivingLocationUpdates = false
            }
        }

        switch status {
        case .notDetermined:
            managerLogger.info("Location authorization status: notDetermined.")
        case .restricted:
            logError(LocationError.accessDenied, managerLogger)
        case .denied:
            logError(LocationError.accessDenied, managerLogger)
        case .authorizedAlways:
            managerLogger.info("Location authorization status: authorizedAlways.")
        case .authorizedWhenInUse:
            managerLogger.info("Location authorization status: authorizedWhenInUse.")
        @unknown default:
            managerLogger.error("Location authorization status: Unknown future case.")
        }
    }

    // MARK: - CLLocationManagerDelegate Methods
    /// Called when the location manager updates the location. Filters updates before processing.
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        managerLogger.trace("Received \(locations.count) location(s).")

        guard let latestLocation = locations.last else {
            managerLogger.trace("No locations received in update.")
            return
        }
        
        let locationAge = -latestLocation.timestamp.timeIntervalSinceNow
        guard locationAge < maximumLocationAge else {
            managerLogger.debug("Ignoring old location (\(String(format: "%.1f", locationAge))s ago).")
            return
        }
        guard latestLocation.horizontalAccuracy > 0 && latestLocation.horizontalAccuracy <= minimumHorizontalAccuracy else {
            managerLogger.debug("Ignoring location with poor horizontal accuracy: \(String(format: "%.1f", latestLocation.horizontalAccuracy))m.")
            DispatchQueue.main.async {
                self.isReceivingLocationUpdates = false
                self.lastAccuracy = latestLocation.horizontalAccuracy
            }
            return
        }

        managerLogger.debug("Valid location received. Accuracy: \(String(format: "%.1f", latestLocation.horizontalAccuracy))m")
        updateWithValidatedLocation(latestLocation)
    }

    /// Called when the authorization status changes. Uses the modern delegate method.
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)

        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            managerLogger.info("Authorization granted/changed, ensuring location updates are started.")
            locationManager.startUpdatingLocation()
        } else {
            managerLogger.warning("Authorization revoked or insufficient, stopping location updates.")
            locationManager.stopUpdatingLocation()
            DispatchQueue.main.async {
                self.isReceivingLocationUpdates = false
                self.lastKnownLocation = nil
                self.lastAccuracy = nil
                self.lastHeading = nil
                self.lastTimestamp = nil
            }
        }
    }

    /// Called when the location manager fails to retrieve a location.
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isReceivingLocationUpdates = false
            self.lastAccuracy = nil
        }
        
        if let clError = error as? CLError, clError.code == .locationUnknown {
            managerLogger.warning("Location manager failed with 'location unknown'. This may resolve automatically.")
            return
        }
        logError(LocationError.failedToRetrieveLocation(error), managerLogger)
    }
}
