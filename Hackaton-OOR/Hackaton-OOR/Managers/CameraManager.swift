import AVFoundation
import SwiftUI

// MARK: - Camera Manager

class CameraManager {
    /// Checks the current camera authorization status and requests access if needed.
    /// The completion returns true if access is authorized, or false otherwise.
    static func checkAndRequestCameraAccess(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            // First time: request access.
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        @unknown default:
            completion(false)
        }
    }
    
    /// Returns an Alert to be shown when camera access is denied.
    static func showCameraAccessDeniedAlert() -> Alert {
        Alert(
            title: Text("Camera Access Denied"),
            message: Text("Camera access is disabled. Please enable camera access in Settings."),
            primaryButton: .default(Text("Open Settings"), action: {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }),
            secondaryButton: .cancel(Text("Cancel"))
        )
    }
    
    static func presentVideoInputErrorAlert(on viewController: UIViewController) {
        let alert = UIAlertController(
            title: "Camera Error",
            message: "Failed to set up video input. Please check your camera and try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        viewController.present(alert, animated: true, completion: nil)
    }
}
