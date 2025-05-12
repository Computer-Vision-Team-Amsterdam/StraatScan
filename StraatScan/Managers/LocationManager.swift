import Foundation
import CoreLocation
import Logging
import Combine
import SwiftUI

/// A manager for handling location updates and managing location-related permissions,
/// incorporating filtering and clearer state management.
final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    // MARK: - Published Properties
    /// The current authorization status for location services.
    @Published var authorizationStatus: CLAuthorizationStatus
    /// Indicates whether the manager is currently receiving location updates that meet the desired accuracy criteria.
    @Published var isReceivingLocationUpdates: Bool = false
    /// The last known location coordinates that passed filtering criteria.
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    /// The accuracy of the last known location.
    @Published var lastAccuracy: CLLocationAccuracy?
    /// The heading direction (course) of the last known location, if valid.
    @Published var lastHeading: CLLocationDirection?
    /// The timestamp of the last known location.
    @Published var lastTimestamp: TimeInterval?

    // MARK: - Private Properties
    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.LocationManager") // Use your app's bundle ID prefix
    /// The underlying CoreLocation manager instance.
    private let locationManager = CLLocationManager()

    // MARK: - Configuration Constants (Adjustable)
    /// The desired level of location accuracy.
    /// Note: `kCLLocationAccuracyBest` uses more battery. Consider alternatives if appropriate.
    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    /// The activity type hint for iOS optimizations.
    private let activityType: CLActivityType = .otherNavigation
    /// Maximum age of a location reading in seconds to be considered valid.
    private let maximumLocationAge: TimeInterval = 5.0
    /// Minimum horizontal accuracy in meters for a location reading to be considered valid.
    private let minimumHorizontalAccuracy: CLLocationAccuracy = 100.0
    /// Minimum speed in meters per second for the course (heading) to be considered valid.
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
            managerLogger.warning("Cannot start location updates: Not authorized (Status: \(status.rawValue)). Request authorization first.")
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
            managerLogger.warning("Location authorization status: restricted.")
        case .denied:
            managerLogger.warning("Location authorization status: denied.")
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
        managerLogger.error("Location Manager Error: \(error.localizedDescription)")

        DispatchQueue.main.async {
            self.isReceivingLocationUpdates = false
            self.lastAccuracy = nil

            if let clError = error as? CLError {
                 if clError.code == .denied {
                     self.managerLogger.warning("Location error was due to denial.")
                     self.updateAuthorizationStatus(.denied)
                 } else if clError.code == .locationUnknown {
                     self.managerLogger.warning("Location manager failed with 'location unknown'. May resolve automatically.")
                 } else if clError.code == .headingFailure {
                     self.managerLogger.warning("Heading updates failed.")
                 }
            }
        }
    }
}
