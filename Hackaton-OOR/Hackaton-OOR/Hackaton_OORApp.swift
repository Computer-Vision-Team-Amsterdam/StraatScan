//
//  Hackaton_OORApp.swift
//  Hackaton-OOR
//
//  Created by Sebastian Davrieux on 31/01/2025.
//

import SwiftUI

@main
struct Hackaton_OORApp: App {
    init() {
        UserDefaults.standard.register(defaults: [
            "detectContainers": true,
            "detectMobileToilets": true,
            "detectScaffoldings": true,
            "iouThreshold_container": 0.45,
            "confidenceThreshold_container": 0.25,
            "iouThreshold_mobiletoilet": 0.45,
            "confidenceThreshold_mobiletoilet": 0.25,
            "iouThreshold_scaffolding": 0.45,
            "confidenceThreshold_scaffolding": 0.25
        ])
    }
    
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}
