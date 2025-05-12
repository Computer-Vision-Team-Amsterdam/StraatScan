import Foundation
import CoreML

/// A singleton manager for handling threshold settings used in object detection.
class ThresholdManager {
    
    /// The shared instance of the `ThresholdManager`.
    static let shared = ThresholdManager()
    
    /// Private initializer to enforce singleton usage.
    private init() {}

    /// Retrieves a `ThresholdProvider` instance with the current threshold settings.
    /// - Returns: A `ThresholdProvider` configured with the current thresholds.
    func getThresholdProvider() -> ThresholdProvider {
        return ThresholdProvider(fromDefaults: true)
    }
}

/// A provider for threshold values used in object detection models.
class ThresholdProvider: MLFeatureProvider {
    
    /// The Intersection over Union (IoU) threshold for object detection.
    var iouThreshold: Double
    
    /// The confidence threshold for object detection.
    var confidenceThreshold: Double

    /// The set of feature names provided by this provider.
    var featureNames: Set<String> {
        return ["iouThreshold", "confidenceThreshold"]
    }

    /// Retrieves the feature value for a given feature name.
    /// - Parameter featureName: The name of the feature.
    /// - Returns: The feature value, or `nil` if the feature name is not recognized.
    func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "iouThreshold":
            return MLFeatureValue(double: iouThreshold)
        case "confidenceThreshold":
            return MLFeatureValue(double: confidenceThreshold)
        default:
            return nil
        }
    }

    /// Initializes a `ThresholdProvider` with specific IoU and confidence thresholds.
    /// - Parameters:
    ///   - iouThreshold: The IoU threshold (default is 0.45).
    ///   - confidenceThreshold: The confidence threshold (default is 0.25).
    init(iouThreshold: Double = 0.45, confidenceThreshold: Double = 0.25) {
        self.iouThreshold = iouThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    /// Initializes a `ThresholdProvider` using values stored in `UserDefaults`.
    /// If no values are stored, values from Info.plist are used, otherwise hard-coded defaults.
    /// - Parameter fromDefaults: A flag indicating whether to load thresholds from `UserDefaults`.
    convenience init(fromDefaults: Bool) {
        let storedConf = UserDefaults.standard.double(forKey: "confidenceThreshold")
        let storedIou = UserDefaults.standard.double(forKey: "iouThreshold")

        let infoDict = Bundle.main.infoDictionary
        let plistConf = Double(infoDict?["ConfidenceThreshold"] as? String ?? "0.25") ?? 0.25
        let plistIou = Double(infoDict?["IoUThreshold"]    as? String ?? "0.45") ?? 0.45

        let finalConf = storedConf == 0 ? plistConf : storedConf
        let finalIou = storedIou  == 0 ? plistIou  : storedIou

        self.init(iouThreshold: finalIou, confidenceThreshold: finalConf)
    }
}
