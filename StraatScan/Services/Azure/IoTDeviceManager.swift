import Foundation
import Security
import Combine // Needed for ObservableObject
import SwiftUI // Needed for @Published and DispatchQueue.main
import Logging // For logging errors

/// Defines user-facing errors related to app credentials and Keychain access.
enum CredentialError: AppError {
    case infoPlistUnreadable
    case credentialKeyMissing(String)
    case credentialKeyEmpty(String)
    case credentialKeyInvalidType(String)
    case keychainSaveFailed(key: String, status: String)
    case keychainReadFailed(key: String, status: String)
    case keychainDataEncodingFailed(String)
    case keychainDataDecodingFailed(String)

    var title: String {
        switch self {
        case .infoPlistUnreadable:
            return "Configuration Error"
        case .credentialKeyMissing, .credentialKeyEmpty, .credentialKeyInvalidType:
            return "Invalid Configuration"
        case .keychainSaveFailed, .keychainReadFailed, .keychainDataEncodingFailed, .keychainDataDecodingFailed:
            return "Security Error"
        }
    }

    var errorDescription: String? {
        switch self {
        case .infoPlistUnreadable:
            return "Fatal Error: Could not read the app's Info.plist. The application cannot start correctly."
        case .credentialKeyMissing(let key):
            return "A required credential key ('\(key)') is missing from the app's configuration."
        case .credentialKeyEmpty(let key):
            return "A required credential key ('\(key)') is present in the configuration but has no value."
        case .credentialKeyInvalidType(let key):
            return "A credential ('\(key)') in the configuration has an incorrect format."
        case .keychainSaveFailed(let key, let status):
            return "Failed to save a credential ('\(key)') to the secure Keychain. (Error: \(status))"
        case .keychainReadFailed(let key, let status):
            return "Failed to read a credential ('\(key)') from the secure Keychain. (Error: \(status))"
        case .keychainDataEncodingFailed(let key):
            return "Failed to encode credential data for '\(key)' before saving."
        case .keychainDataDecodingFailed(let key):
            return "Failed to decode credential data for '\(key)' after reading."
        }
    }

    var typeIdentifier: String {
        switch self {
        case .infoPlistUnreadable:
            return "CredentialError.infoPlistUnreadable"
        case .credentialKeyMissing:
            return "CredentialError.credentialKeyMissing"
        case .credentialKeyEmpty:
            return "CredentialError.credentialKeyEmpty"
        case .credentialKeyInvalidType:
            return "CredentialError.credentialKeyInvalidType"
        case .keychainSaveFailed:
            return "CredentialError.keychainSaveFailed"
        case .keychainReadFailed:
            return "CredentialError.keychainReadFailed"
        case .keychainDataEncodingFailed:
            return "CredentialError.keychainDataEncodingFailed"
        case .keychainDataDecodingFailed:
            return "CredentialError.keychainDataDecodingFailed"
        }
    }
}

/// An ObservableObject managing IoT device credentials.
class IoTDeviceManager: ObservableObject {
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.IoTDeviceManager")

    @Published private(set) var deviceId: String?
    @Published private(set) var deviceSasToken: String?

    private let deviceIdKey = "DEVICE_ID"
    private let sasTokenKey = "DEVICE_SAS_TOKEN"

    init() {
        managerLogger.info("Initializing IoTDeviceManager.")
        self.deviceId = try? readFromKeychain(forKey: deviceIdKey)
        self.deviceSasToken = try? readFromKeychain(forKey: sasTokenKey)
        managerLogger.debug("Initial Device ID loaded: \(self.deviceId != nil ? "Found" : "Not Found")")
        managerLogger.debug("Initial SAS Token loaded: \(self.deviceSasToken != nil ? "Found" : "Not Found")")
    }

    /// Sets up device credentials by reading from Info.plist and saving to Keychain.
    /// This is the main public function to call. It will log any errors using the global handler.
    func setupDeviceCredentials() {
        managerLogger.info("Running device credential setup check...")
        do {
            guard let infoDict = try getInfoDictionary() else { return }

            managerLogger.debug("Processing Device ID credential...")
            try checkAndProcessCredential(key: deviceIdKey, currentValue: self.deviceId, infoDict: infoDict)
            
            managerLogger.debug("Processing SAS Token credential...")
            try checkAndProcessCredential(key: sasTokenKey, currentValue: self.deviceSasToken, infoDict: infoDict)

            managerLogger.info("Device credentials setup check completed successfully.")
        } catch {
            logError(error, managerLogger)
        }
    }

    /// Retrieves the application's Info.plist dictionary. Throws an error on failure.
    private func getInfoDictionary() throws -> [String: Any]? {
        guard let infoDict = Bundle.main.infoDictionary else {
            throw CredentialError.infoPlistUnreadable
        }
        return infoDict
    }

    /// Checks a credential, updating the Keychain and published properties if necessary. Throws on failure.
    private func checkAndProcessCredential(key: String, currentValue: String?, infoDict: [String: Any]) throws {
        managerLogger.debug("Checking credential for key: \(key)...")

        guard let plistValue = infoDict[key] as? String, !plistValue.isEmpty else {
            if infoDict[key] == nil {
                throw CredentialError.credentialKeyMissing(key)
            } else if !(infoDict[key] is String) {
                throw CredentialError.credentialKeyInvalidType(key)
            } else {
                throw CredentialError.credentialKeyEmpty(key)
            }
        }

        if currentValue != plistValue {
            managerLogger.info("New value found for key '\(key)'. Updating Keychain.")
            try saveToKeychain(value: plistValue, forKey: key)
            updatePublishedProperty(forKey: key, with: plistValue)
            managerLogger.info("Credential for key '\(key)' updated successfully in Keychain.")
        } else {
            managerLogger.info("Credential for key '\(key)' matches.")
            if currentValue == nil, let keychainValue = try readFromKeychain(forKey: key) {
                updatePublishedProperty(forKey: key, with: keychainValue)
            }
        }
    }

    /// Updates the correct @Published property based on the provided key.
    private func updatePublishedProperty(forKey key: String, with value: String) {
        DispatchQueue.main.async {
            switch key {
            case self.deviceIdKey: self.deviceId = value
            case self.sasTokenKey: self.deviceSasToken = value
            default: self.managerLogger.warning("Attempted to update unknown published property for key: \(key)")
            }
        }
    }

    /// Saves a value to the Keychain. Throws an error on failure.
    private func saveToKeychain(value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw CredentialError.keychainDataEncodingFailed(key)
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            managerLogger.debug("Item not found for key '\(key)', attempting to add.")
            var newItemQuery = query
            newItemQuery[kSecValueData as String] = data
            newItemQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(newItemQuery as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            let errorDescription = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus: \(status)"
            throw CredentialError.keychainSaveFailed(key: key, status: errorDescription)
        }
        
        managerLogger.debug("Successfully saved value to Keychain for key: \(key)")
    }

    /// Reads a value from the Keychain. Throws on error, returns nil if not found.
    private func readFromKeychain(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess {
            guard let data = dataTypeRef as? Data, let value = String(data: data, encoding: .utf8) else {
                throw CredentialError.keychainDataDecodingFailed(key)
            }
            managerLogger.debug("Successfully read value from Keychain for key: \(key)")
            return value
        } else if status == errSecItemNotFound {
            managerLogger.debug("No item found in Keychain for key: \(key)")
            return nil
        } else {
            let errorDescription = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus: \(status)"
            throw CredentialError.keychainReadFailed(key: key, status: errorDescription)
        }
    }
}
