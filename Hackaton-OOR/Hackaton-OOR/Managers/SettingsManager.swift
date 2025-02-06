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
        return ThresholdProvider(fromDefaults: true)
    }
}

class ThresholdProvider: MLFeatureProvider {
    var iouThreshold: Double
    var confidenceThreshold: Double

    var featureNames: Set<String> {
        return ["iouThreshold", "confidenceThreshold"]
    }

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

    init(iouThreshold: Double = 0.45, confidenceThreshold: Double = 0.25) {
        self.iouThreshold = iouThreshold
        self.confidenceThreshold = confidenceThreshold
    }

    convenience init(fromDefaults: Bool) {
        let storedConf = UserDefaults.standard.double(forKey: "confidenceThreshold")
        let storedIou = UserDefaults.standard.double(forKey: "iouThreshold")

        let finalConf = storedConf == 0 ? 0.25 : storedConf
        let finalIou = storedIou == 0 ? 0.45 : storedIou

        self.init(iouThreshold: finalIou, confidenceThreshold: finalConf)
    }
}
