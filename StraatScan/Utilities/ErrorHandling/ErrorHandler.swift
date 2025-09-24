import UIKit
import os.log
import Logging

func logError(_ error: Error, _ logger: Logging.Logger, file: String = #file, function: String = #function, line: Int = #line) {
    let fileName = (file as NSString).lastPathComponent
    logger.error("ERROR: \(error.localizedDescription) in \(fileName):\(function) at line \(line)")

    // Display the error to the user
    ErrorHandler.shared.handle(error)
}

class ErrorHandler {
    static let shared = ErrorHandler()

    private var alertWindow: UIWindow?
    private var isAlertPresented = false
    private var errorQueue: [Error] = []
    private var displayedErrorTypes = Set<String>()
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.ErrorHandler")
    private var retryErrorPopup = false

    private init() {
        // Check when UI becomes active so any pending errors can be shown
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(tryShowPendingErrors),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    func handle(_ error: Error) {
        DispatchQueue.main.async {
            self.errorQueue.append(error)
            self.showNextErrorInQueue()
        }
    }

    private func showNextErrorInQueue() {
        guard !self.isAlertPresented else {
            return // Don't show overlapping alerts.
        }

        guard !errorQueue.isEmpty else { return }

        let nextError = errorQueue.first!
        if let appError = nextError as? AppError, displayedErrorTypes.contains(appError.typeIdentifier) {
            _ = errorQueue.removeFirst()
            showNextErrorInQueue()
            return
        }

        // Only proceed if we have a window scene
        if let windowScene = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .first as? UIWindowScene {
            
            _ = errorQueue.removeFirst()
            
            if let appError = nextError as? AppError {
                displayedErrorTypes.insert(appError.typeIdentifier)
            }
            
            self.isAlertPresented = true
            self.presentErrorAlert(for: nextError, in: windowScene)
        } else {
            // No window scene: keep in queue and retry later
            self.retryErrorPopup = true
        }
    }

    @objc private func tryShowPendingErrors() {
        if retryErrorPopup {
            retryErrorPopup = false
            showNextErrorInQueue()
        }
    }

    private func presentErrorAlert(for error: Error, in windowScene: UIWindowScene) {
        let title: String
        let message: String

        if let appError = error as? AppError {
            title = appError.title
            message = appError.localizedDescription
        } else {
            title = "An Unexpected Error Occurred"
            message = error.localizedDescription
        }

        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.dismissErrorAlert()
        }))

        if self.alertWindow == nil {
            self.alertWindow = UIWindow(windowScene: windowScene)
            self.alertWindow?.windowLevel = .alert + 1
            self.alertWindow?.rootViewController = UIViewController()
            self.alertWindow?.makeKeyAndVisible()
        }

        self.alertWindow?.rootViewController?.present(alertController, animated: true)
    }

    private func dismissErrorAlert() {
        self.alertWindow?.rootViewController?.dismiss(animated: true) {
            self.alertWindow?.isHidden = true
            self.alertWindow = nil
            self.isAlertPresented = false
            self.showNextErrorInQueue()
        }
    }

    public func clearErrorHistory() {
        displayedErrorTypes.removeAll()
        managerLogger.debug("Error history has been cleared.")
    }

    public func logErrorHistory() {
        managerLogger.error("Error history: \(displayedErrorTypes)")
    }
}
