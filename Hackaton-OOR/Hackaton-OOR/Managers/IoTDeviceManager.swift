import Foundation
import Security

class IoTDeviceManager {
    static let shared = IoTDeviceManager()

    private let deviceIdKey = "DEVICE_ID"
    private let sasTokenKey = "DEVICE_SAS_TOKEN"

    var deviceId: String? {
        return readFromKeychain(forKey: deviceIdKey)
    }

    var deviceSasToken: String? {
        return readFromKeychain(forKey: sasTokenKey)
    }

    func setupDeviceCredentials() {
        if let deviceId = Bundle.main.infoDictionary?[deviceIdKey] as? String, !deviceId.isEmpty {
            saveToKeychain(value: deviceId, forKey: deviceIdKey)
        }
        if let token = Bundle.main.infoDictionary?[sasTokenKey] as? String, !token.isEmpty {
            saveToKeychain(value: token, forKey: sasTokenKey)
        }        
    }

    private func saveToKeychain(value: String, forKey key: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary) // Remove if already exists
        SecItemAdd(query as CFDictionary, nil)
    }

    private func readFromKeychain(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess,
           let data = dataTypeRef as? Data,
           let value = String(data: data, encoding: .utf8) {
            return value
        }

        return nil
    }
}
