import AVFoundation
import UIKit
import Logging

// MARK: - Camera Error
enum CameraError: AppError {
    case accessDenied
    case videoInputFailed

    var title: String {
        switch self {
        case .accessDenied:
            return "Camera Access Denied"
        case .videoInputFailed:
            return "Camera Error"
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Camera access is disabled. Please enable it in your device Settings to continue."
        case .videoInputFailed:
            return "Failed to set up the camera's video input. Please check your camera and try again."
        }
    }

    var typeIdentifier: String {
        switch self {
        case .accessDenied:
            return "CameraError.accessDenied"
        case .videoInputFailed:
            return "CameraError.videoInputFailed"
        }
    }
}

// MARK: - Camera Manager
class CameraManager {

    // Add a logger for context, just like in our other classes.
    private static let logger = Logger(label: "com.yourapp.CameraManager")

    /// Checks the current camera authorization status and requests access if needed.
    /// If access is denied or restricted, it logs the error, which triggers the global alert.
    /// The completion returns true if access is authorized, or false otherwise.
    static func checkAndRequestPermissions(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if !granted {
                        logError(CameraError.accessDenied, logger)
                    }
                    completion(granted)
                }
            }

        case .authorized:
            completion(true)

        case .denied, .restricted:
            logError(CameraError.accessDenied, logger)
            completion(false)
            
        @unknown default:
            completion(false)
        }
    }
    
    /// Logs a video input failure error.
    static func logVideoInputError() {
        logError(CameraError.videoInputFailed, logger)
    }
}
