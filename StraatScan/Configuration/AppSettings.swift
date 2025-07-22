import Foundation
import SwiftUI
import Combine
import Logging

/// An ObservableObject to manage and synchronize user-configurable settings from UserDefaults.
final class AppSettings: ObservableObject {
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.AppSettings")
    @Published var detectContainers: Bool
    @Published var detectMobileToilets: Bool
    @Published var detectScaffoldings: Bool
    @Published var drawBoundingBoxes: Bool
    
    private var cancellable: AnyCancellable?

    init() {
        self.detectContainers = UserDefaults.standard.bool(forKey: "detectContainers")
        self.detectMobileToilets = UserDefaults.standard.bool(forKey: "detectMobileToilets")
        self.detectScaffoldings = UserDefaults.standard.bool(forKey: "detectScaffoldings")
        self.drawBoundingBoxes = UserDefaults.standard.bool(forKey: "drawBoundingBoxes")
        
        cancellable = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { _ in
                self.managerLogger.debug("App became active. Refreshing settings from UserDefaults.")
                self.loadSettings()
            }
    }
    
    /// Reads the latest values from UserDefaults and updates the published properties.
    private func loadSettings() {
        detectContainers = UserDefaults.standard.bool(forKey: "detectContainers")
        detectMobileToilets = UserDefaults.standard.bool(forKey: "detectMobileToilets")
        detectScaffoldings = UserDefaults.standard.bool(forKey: "detectScaffoldings")
        drawBoundingBoxes = UserDefaults.standard.bool(forKey: "drawBoundingBoxes")
    }
}
