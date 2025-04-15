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
        return ThresholdProvider()
    }
}

/// A provider for threshold values used in object detection models.
class ThresholdProvider: MLFeatureProvider {
    var thresholds: [String: (iou: Double, confidence: Double)]

    /// The set of feature names provided by this provider.
    var featureNames: Set<String> {
        var names = Set<String>()
        for key in thresholds.keys {
            names.insert("\(key)_iouThreshold")
            names.insert("\(key)_confidenceThreshold")
        }
        return names
    }

    /// Retrieves the feature value for a given feature name.
    /// - Parameter featureName: The name of the feature.
    /// - Returns: The feature value, or `nil` if the feature name is not recognized.
    func featureValue(for featureName: String) -> MLFeatureValue? {
        // Expected format: "<object>_iouThreshold" or "<object>_confidenceThreshold"
        let components = featureName.split(separator: "_")
        guard components.count == 2,
              let values = thresholds[String(components[0])] else {
            return nil
        }
        if components[1] == "iouThreshold" {
            return MLFeatureValue(double: values.iou)
        } else if components[1] == "confidenceThreshold" {
            return MLFeatureValue(double: values.confidence)
        }
        return nil
    }

    /// Validates and retrieves a threshold value from UserDefaults.
    /// - Parameters:
    ///   - key: The key for the threshold value in UserDefaults.
    ///   - defaultValue: The default value to return if the stored value is invalid.
    /// - Returns: The validated threshold value.
    /// - Note: The value must be between 0.01 and 1.0, inclusive.
    static func getValidatedThreshold(forKey key: String, defaultValue: Double) -> Double {
        if let thresholdString = UserDefaults.standard.string(forKey: key),
           let value = Double(thresholdString) {
            if value >= 0.01 && value <= 1.0 {
                return value
            }
        }
        return defaultValue
    }

    /// Initializes the `ThresholdProvider` with default threshold values.
    /// The default values are set for "container", "mobile toilet", and "scaffolding".
    /// The default values are 0.45 for IoU and 0.25 for confidence.
    init() {
        let containerIoU = ThresholdProvider.getValidatedThreshold(forKey: "iouThreshold_container", defaultValue: 0.45)
        let containerConfidence = ThresholdProvider.getValidatedThreshold(forKey: "confidenceThreshold_container", defaultValue: 0.25)
        let mobileToiletIoU = ThresholdProvider.getValidatedThreshold(forKey: "iouThreshold_mobiletoilet", defaultValue: 0.45)
        let mobileToiletConfidence = ThresholdProvider.getValidatedThreshold(forKey: "confidenceThreshold_mobiletoilet", defaultValue: 0.25)
        let scaffoldingIoU = ThresholdProvider.getValidatedThreshold(forKey: "iouThreshold_scaffolding", defaultValue: 0.45)
        let scaffoldingConfidence = ThresholdProvider.getValidatedThreshold(forKey: "confidenceThreshold_scaffolding", defaultValue: 0.25)
        
        thresholds = [
            "container": (iou: containerIoU, confidence: containerConfidence),
            "mobile toilet": (iou: mobileToiletIoU, confidence: mobileToiletConfidence),
            "scaffolding": (iou: scaffoldingIoU, confidence: scaffoldingConfidence)
        ]
    }
}
