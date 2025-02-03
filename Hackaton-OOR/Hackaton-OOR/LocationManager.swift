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
    
    
    func checkLocationAuthorization() {
        
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.startUpdatingLocation()
        
        // Check if heading data is available.
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
            print("Starting recording heading")
        } else {
            print("No compass available")
            // Disable compass features.
        }
        
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
            lastKnownLocation = manager.location?.coordinate
            
        @unknown default:
            print("Location service disabled")
        
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {//Trigged every time authorization status changes
        checkLocationAuthorization()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastKnownLocation = locations.first?.coordinate
        lastAccuracy = locations.first?.horizontalAccuracy
        lastHeading = locations.first?.course
        print(locations)
    }
}
