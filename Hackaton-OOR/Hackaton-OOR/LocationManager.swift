//
//  LocationManager.swift
//  Hackaton-OOR
//
//  Created by Daan Bloembergen on 03/02/2025.
//

import Foundation
import CoreLocation

final class LocationManager: NSObject, CLLocationManagerDelegate, ObservableObject {
    
    @Published var lastKnownLocation: CLLocationCoordinate2D?
    @Published var lastAccuracy: CLLocationAccuracy?
    @Published var lastHeading: CLLocationDirection?
    var manager = CLLocationManager()
    
    func setup() {
        manager.delegate = self
        
        checkLocationAuthorization()
        
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = CLActivityType.otherNavigation
        manager.startUpdatingLocation()
        
        // Check if heading data is available.
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        } else {
            print("No compass available")
            // Disable compass features.
        }
    }
    
    func update(_ location: CLLocation?) {
        lastKnownLocation = location?.coordinate
        lastAccuracy = location?.horizontalAccuracy
        lastHeading = location?.course
    }
    
    func checkLocationAuthorization() {
        switch manager.authorizationStatus {
        case .notDetermined://The user did not choose allow or deny your app to get the location yet
            manager.requestWhenInUseAuthorization()
            
        case .restricted://The user cannot change this app’s status, possibly due to active restrictions such as parental controls being in place.
            print("Location restricted")
            
        case .denied://The user dennied your app to get location or disabled the services location or the phone is in airplane mode
            print("Location denied")
            
        case .authorizedAlways://This authorization allows you to use all location services and receive location events whether or not your app is in use.
            print("Location authorizedAlways")
            
        case .authorizedWhenInUse://This authorization allows you to use all location services and receive location events only when your app is in use
            print("Location authorized when in use")
            update(manager.location)

        @unknown default:
            print("Location service disabled")
        
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {//Trigged every time authorization status changes
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        update(locations.first)
    }
}
