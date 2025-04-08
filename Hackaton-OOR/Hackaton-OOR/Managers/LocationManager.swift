import Foundation
import CoreLocation

final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    
    @Published var gpsAvailable: Bool = false
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var lastAccuracy: CLLocationAccuracy?
    @Published var lastHeading: CLLocationDirection?
    @Published var lastTimestamp: TimeInterval?
    private var locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkLocationAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = CLActivityType.otherNavigation
        locationManager.startUpdatingLocation()
        
        if CLLocationManager.headingAvailable() {
            locationManager.startUpdatingHeading()
        } else {
            print("No compass available")
        }
    }
    
    func update(_ location: CLLocation?) {
        DispatchQueue.main.async {
            self.lastKnownLocation = location?.coordinate
            self.lastAccuracy = location?.horizontalAccuracy
            self.lastHeading = location?.course
            self.lastTimestamp = location?.timestamp.timeIntervalSince1970
            self.gpsAvailable = true
        }
    }
    
    func checkLocationAuthorization() {
        switch locationManager.authorizationStatus {
        case .notDetermined://The user did not choose allow or deny your app to get the location yet
            locationManager.requestWhenInUseAuthorization()
            
        case .restricted://The user cannot change this app’s status, possibly due to active restrictions such as parental controls being in place.
            print("Location restricted")
            
        case .denied://The user dennied your app to get location or disabled the services location or the phone is in airplane mode
            print("Location denied")
            
        case .authorizedAlways://This authorization allows you to use all location services and receive location events whether or not your app is in use.
            print("Location authorizedAlways")
            
        case .authorizedWhenInUse://This authorization allows you to use all location services and receive location events only when your app is in use
            print("Location authorized when in use")

        @unknown default:
            print("Location service disabled")
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let latestLocation = locations.last {
            update(latestLocation)
        }
    }
    
    // Update gpsAvailable when authorization status changes.
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        checkLocationAuthorization()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            DispatchQueue.main.async {
                self.gpsAvailable = true
            }
        } else {
            DispatchQueue.main.async {
                self.gpsAvailable = false
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.gpsAvailable = false
            self.lastAccuracy = nil
        }
    }
}
