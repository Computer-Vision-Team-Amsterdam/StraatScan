import SwiftUI

@main
struct StraatScanApp: App {
    @StateObject private var iotManager = IoTDeviceManager()

    init() {
        UserDefaults.standard.register(defaults: [
            "detectContainers": true,
            "detectMobileToilets": true,
            "detectScaffoldings": true,
            "drawBoundingBoxes": false,
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
