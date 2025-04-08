//
//  ThresholdManager.swift
//  Hackaton-OOR
//
//  Created by Niek IJzerman on 05/02/2025.
//

import Foundation
import CoreML

class ThresholdManager {
    
    static let shared = ThresholdManager()
    
    private init() {}

    func getThresholdProvider() -> ThresholdProvider {
        return ThresholdProvider()
    }
}

class ThresholdProvider: MLFeatureProvider {
    var thresholds: [String: (iou: Double, confidence: Double)]

    var featureNames: Set<String> {
        var names = Set<String>()
        for key in thresholds.keys {
            names.insert("\(key)_iouThreshold")
            names.insert("\(key)_confidenceThreshold")
        }
        return names
    }

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

    static func getValidatedThreshold(forKey key: String, defaultValue: Double) -> Double {
        if let thresholdString = UserDefaults.standard.string(forKey: key),
           let value = Double(thresholdString) {
            if value >= 0.01 && value <= 1.0 {
                return value
            }
        }
        return defaultValue
    }

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
