import Foundation
import CoreML

/// A singleton manager for handling threshold settings used in object detection.
class ThresholdManager {

    /// Shared instance
    static let shared = ThresholdManager()

    /// Private initializer to enforce singleton usage.
    private init() {}

    /// Returns a `ThresholdProvider` reflecting the latest stored or plist‑based values.
    func getThresholdProvider() -> ThresholdProvider {
        ThresholdProvider(fromDefaults: true)
    }
}

/// A provider for IoU and confidence thresholds consumed by Core ML models.
class ThresholdProvider: MLFeatureProvider {

    // MARK: Public thresholds
    var iouThreshold: Double
    var confidenceThreshold: Double

    // MARK: MLFeatureProvider
    var featureNames: Set<String> { ["iouThreshold", "confidenceThreshold"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "iouThreshold":         return MLFeatureValue(double: iouThreshold)
        case "confidenceThreshold":  return MLFeatureValue(double: confidenceThreshold)
        default:                      return nil
        }
    }

    // MARK: Initialisers
    init(iouThreshold: Double = 0.45, confidenceThreshold: Double = 0.25) {
        self.iouThreshold = iouThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    /// Loads values from UserDefaults if present; otherwise falls back to Info.plist, then hard‑coded defaults.
    convenience init(fromDefaults: Bool) {
        let storedConf = UserDefaults.standard.double(forKey: "confidenceThreshold")
        let storedIou  = UserDefaults.standard.double(forKey: "iouThreshold")

        // Read fallback values from Info.plist.
        let plistConf = (Bundle.main.object(forInfoDictionaryKey: "ConfidenceThreshold") as? String)
            .flatMap(Double.init) ?? 0.25
        let plistIou  = (Bundle.main.object(forInfoDictionaryKey: "IoUThreshold") as? String)
            .flatMap(Double.init) ?? 0.45

        // If UserDefaults value is 0 (never set), use plist; else keep stored value.
        let finalConf = storedConf == 0 ? plistConf : storedConf
        let finalIou  = storedIou  == 0 ? plistIou  : storedIou

        self.init(iouThreshold: finalIou, confidenceThreshold: finalConf)
    }
}
