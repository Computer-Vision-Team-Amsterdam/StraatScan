import SwiftUI

@main
struct Hackaton_OORApp: App {
    @StateObject private var iotManager = IoTDeviceManager()

    init() {
        UserDefaults.standard.register(defaults: [
            "detectContainers": true,
            "iouThreshold": 0.45,
            "confidenceThreshold": 0.25
        ])
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(iotManager)
                .onAppear {
                    iotManager.setupDeviceCredentials()
                }
        }
    }
}
