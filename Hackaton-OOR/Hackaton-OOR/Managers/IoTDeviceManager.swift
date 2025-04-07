import Foundation
import Security

class IoTDeviceManager {
    static let shared = IoTDeviceManager()
    private let deviceIdKey = "device_id"
    private let deviceSasKey = "device_sas_token"

    var deviceId: String? {
        if let id = KeychainHelper.get(key: deviceIdKey) {
            return id
        } else if let id = Bundle.main.infoDictionary?["DEVICE_ID"] as? String {
            KeychainHelper.save(key: deviceIdKey, value: id)
            return id
        }
        return nil
    }

    var deviceSasToken: String? {
        if let token = KeychainHelper.get(key: deviceSasKey) {
            return token
        } else if let token = Bundle.main.infoDictionary?["DEVICE_SAS_TOKEN"] as? String {
            KeychainHelper.save(key: deviceSasKey, value: token)
            return token
        }
        return nil
    }

    func clearSecrets() {
        KeychainHelper.save(key: deviceIdKey, value: "")
        KeychainHelper.save(key: deviceSasKey, value: "")
    }
}
