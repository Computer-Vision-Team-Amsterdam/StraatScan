import Foundation
import Security
import Combine // Needed for ObservableObject
import SwiftUI // Needed for @Published and DispatchQueue.main
import Logging // For logging errors

/// An ObservableObject managing IoT device credentials and related state like errors.
@MainActor
class IoTDeviceManager: ObservableObject {

    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.IoTDeviceManager")
    
    /// Indicates whether an error alert should be shown to the user.
    @Published var showingCredentialAlert: Bool = false
    /// The message to display in the error alert.
    @Published var credentialAlertMessage: String = ""

    /// The current device ID read from Keychain. Published so UI could react if it changes.
    @Published private(set) var deviceId: String?
    /// The current SAS token read from Keychain. Published so UI could react if it changes.
    @Published private(set) var deviceSasToken: String?

    /// The key for storing the device ID in the Keychain.
    private let deviceIdKey = "DEVICE_ID" // Use your actual key
    /// The key for storing the SAS token in the Keychain.
    private let sasTokenKey = "DEVICE_SAS_TOKEN" // Use your actual key

    /// Initializes the manager and loads initial credentials from Keychain.
    init() {
        managerLogger.info("Initializing IoTDeviceManager.")
        self.deviceId = readFromKeychain(forKey: deviceIdKey)
        self.deviceSasToken = readFromKeychain(forKey: sasTokenKey)
        managerLogger.debug("Initial Device ID loaded: \(self.deviceId != nil ? "Found" : "Not Found")")
        managerLogger.debug("Initial SAS Token loaded: \(self.deviceSasToken != nil ? "Found" : "Not Found")")
    }

    /// Sets up the device credentials by reading required keys from the app's Info.plist
    /// and saving them securely to the Keychain if necessary.
    /// Updates published properties if credentials change or if errors occur.
    func setupDeviceCredentials() {
        managerLogger.info("Running device credential setup check...")

        guard let infoDict = getInfoDictionary() else {
            return
        }

        managerLogger.debug("Processing Device ID credential...")
        if let deviceIdError = checkAndProcessCredential(
            key: deviceIdKey,
            currentValue: self.deviceId,
            infoDict: infoDict
        ) {
            managerLogger.critical("Device ID setup failed: \(deviceIdError)")
            notifyUserOfCredentialError(message: deviceIdError + ". Please contact support.")
            return
        }

        managerLogger.debug("Processing SAS Token credential...")
        if let sasTokenError = checkAndProcessCredential(
            key: sasTokenKey,
            currentValue: self.deviceSasToken,
            infoDict: infoDict
        ) {
            managerLogger.critical("SAS Token setup failed: \(sasTokenError)")
            notifyUserOfCredentialError(message: sasTokenError + ". Please contact support.")
            return
        }
        managerLogger.info("Device credentials setup check completed successfully.")
    }

    /// Safely retrieves the application's Info.plist as a dictionary.
    /// Logs and notifies the user via published properties if retrieval fails.
    /// - Returns: The Info.plist dictionary, or `nil` if it cannot be accessed.
    private func getInfoDictionary() -> [String: Any]? {
        guard let infoDict = Bundle.main.infoDictionary else {
            let errorMessage = "Fatal Error: Could not read Info.plist dictionary."
            managerLogger.critical("\(errorMessage)")
            notifyUserOfCredentialError(message: errorMessage + " The application cannot start correctly. Please reinstall or contact support.")
            return nil
        }
        return infoDict
    }

    /// Checks a specific credential (Device ID or SAS Token) from Info.plist against Keychain,
    /// saves to Keychain if needed, and updates the corresponding published property.
    /// - Parameters:
    ///   - key: The Keychain key and Info.plist key for the credential.
    ///   - currentValue: The current value loaded from Keychain (held in the @Published property).
    ///   - infoDict: The Info.plist dictionary.
    /// - Returns: An optional String containing an error message if setup failed for this credential, otherwise `nil`.
    private func checkAndProcessCredential(key: String, currentValue: String?, infoDict: [String: Any]) -> String? {
        managerLogger.debug("Checking credential for key: \(key)...")

        guard let plistValue = infoDict[key] as? String, !plistValue.isEmpty else {
            let errorMessage: String
            if infoDict[key] == nil {
                errorMessage = "Configuration Error: Required credential '\(key)' is missing from Info.plist"
            } else if !(infoDict[key] is String) {
                errorMessage = "Configuration Error: Credential '\(key)' in Info.plist is not a String"
            } else {
                errorMessage = "Configuration Error: Credential '\(key)' in Info.plist is empty"
            }
            return errorMessage
        }

        if currentValue != plistValue {
            managerLogger.info("New value found for key '\(key)' in Info.plist. Updating Keychain.")
            if saveToKeychain(value: plistValue, forKey: key) {
                updatePublishedProperty(forKey: key, with: plistValue)
                managerLogger.info("Credential for key '\(key)' updated successfully in Keychain.")
                return nil
            } else {
                return "Failed to save credential '\(key)' to Keychain"
            }
        } else {
            managerLogger.info("Credential for key '\(key)' in Info.plist matches Keychain or is already set.")
            if currentValue == nil {
                 if let keychainValue = readFromKeychain(forKey: key) {
                      updatePublishedProperty(forKey: key, with: keychainValue)
                 }
            }
            return nil
        }
    }

    /// Updates the correct @Published property based on the provided key.
    /// Ensures the update happens on the main thread.
    /// - Parameters:
    ///   - key: The key indicating which property to update (`deviceIdKey` or `sasTokenKey`).
    ///   - value: The new value for the property.
    private func updatePublishedProperty(forKey key: String, with value: String) {
        switch key {
        case self.deviceIdKey:
            self.deviceId = value
        case self.sasTokenKey:
            self.deviceSasToken = value
        default:
            self.managerLogger.warning("Attempted to update unknown published property for key: \(key)")
        }
    }


    /// Updates the published properties to signal that an alert should be shown.
    /// Ensures UI updates happen on the main thread.
    /// - Parameter message: The error message to display.
    func notifyUserOfCredentialError(message: String) {
        self.credentialAlertMessage = message
        self.showingCredentialAlert = true
    }

    /// Saves a value to the Keychain for a given key.
    /// - Parameters:
    ///   - value: The value to save.
    ///   - key: The key under which the value will be stored.
    /// - Returns: `true` if saving was successful, `false` otherwise.
    private func saveToKeychain(value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            managerLogger.error("Failed to encode string to UTF8 data for Keychain key: \(key)")
            return false
        }

        let queryFind: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        var status = SecItemUpdate(queryFind as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            managerLogger.debug("Item not found for key '\(key)', attempting to add.")
            var newItemQuery = queryFind
            newItemQuery[kSecValueData as String] = data
            newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(newItemQuery as CFDictionary, nil)
        }

        if status == errSecSuccess {
             managerLogger.debug("Successfully saved value to Keychain for key: \(key)")
             return true
        } else {
             let errorDescription = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus: \(status)"
             managerLogger.error("Failed to save to Keychain for key '\(key)'. Status: \(errorDescription)")
             return false
        }
    }


    /// Reads a value from the Keychain for a given key.
    /// - Parameter key: The key for which the value will be retrieved.
    /// - Returns: The value associated with the key, or `nil` if no value is found or an error occurs.
    private func readFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?

        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            guard let data = dataTypeRef as? Data,
                  let value = String(data: data, encoding: .utf8) else {
                managerLogger.error("Failed to decode Keychain data for key '\(key)'")
                return nil
            }
            managerLogger.debug("Successfully read value from Keychain for key: \(key)")
            return value
        } else if status == errSecItemNotFound {
            managerLogger.debug("No item found in Keychain for key: \(key)")
            return nil
        } else {
            let errorDescription = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown OSStatus: \(status)"
            managerLogger.error("Failed to read from Keychain for key '\(key)'. Status: \(errorDescription)")
            return nil
        }
    }
}
