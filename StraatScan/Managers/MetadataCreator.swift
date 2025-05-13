import Foundation
import Vision

struct LocationData {
    let latitude: Double
    let longitude: Double
    let timestamp: TimeInterval
    let accuracy: Double
}

struct GPSDataOutput: Codable {
    let latitude: Double
    let longitude: Double
    let coordinate_time_stamp: String
    let accuracy: Double
}

struct BoundingBoxOutput: Codable {
    let x_center: Double
    let y_center: Double
    let width: Double
    let height: Double
}

struct DetectionOutput: Codable {
    let object_class: Int
    let confidence: Double
    let tracking_id: Int
    let boundingBox: BoundingBoxOutput
}

struct MetadataOutput: Codable {
    let record_timestamp: String
    let gps_data: GPSDataOutput?
    let image_file_timestamp: String
    let image_file_name: String
    let detections: [DetectionOutput]
}


struct MetadataCreator {
    /// Default object class ID for labels not found in the provided mapping.
    private static let unknownObjectClass = -1
    
    /// Default tracking ID if none is available.
    private static let defaultTrackingId = -1
    
    /// Formats a Date or Unix timestamp (Double) into ISO 8601 String (UTC, with microseconds).
    private static func formatTimestampToISO8601(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    /// Overload for TimeInterval (Unix timestamp).
    private static func formatTimestampToISO8601(_ timestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: timestamp)
        return formatTimestampToISO8601(date)
    }
    
    /// Creates structured metadata from detection results and associated data.
    ///
    /// - Parameters:
    ///   - predictions: Array of Vision object observations.
    ///   - imageTimestamp: The timestamp (Unix epoch) of the captured image frame.
    ///   - locationData: Optional location data (lat, lon, timestamp, accuracy).
    ///   - imageFileName: The filename intended for the associated image.
    ///   - labelMapping: The mapping from lowercase label string to object class integer, derived from model metadata.
    /// - Returns: A `MetadataOutput` struct ready for encoding.
    func create(
        predictions: [VNRecognizedObjectObservation],
        imageTimestamp: TimeInterval,
        locationData: LocationData?,
        imageFileName: String,
        labelMapping: [String: Int]
    ) -> MetadataOutput {
        
        let recordTimestampString = MetadataCreator.formatTimestampToISO8601(Date())
        let imageTimestampString = MetadataCreator.formatTimestampToISO8601(imageTimestamp)
        let gpsData: GPSDataOutput?
        if let locData = locationData {
            gpsData = GPSDataOutput(
                latitude: locData.latitude,
                longitude: locData.longitude,
                coordinate_time_stamp: MetadataCreator.formatTimestampToISO8601(locData.timestamp),
                accuracy: locData.accuracy
            )
        } else {
            gpsData = nil
        }
        
        let detections: [DetectionOutput] = predictions.compactMap { prediction in
            guard let bestLabel = prediction.labels.first else {
                return nil
            }
            let labelIdentifier = bestLabel.identifier.lowercased()
            let confidence = Double(bestLabel.confidence)
            print(labelIdentifier)
            print(labelMapping)
            let objectClass = labelMapping[labelIdentifier] ?? MetadataCreator.unknownObjectClass
            
            let bbOutput = BoundingBoxOutput(
                x_center: prediction.boundingBox.origin.x,
                y_center: prediction.boundingBox.origin.y,
                width: prediction.boundingBox.width,
                height: prediction.boundingBox.height
            )
            
            return DetectionOutput(
                object_class: objectClass,
                confidence: confidence,
                tracking_id: MetadataCreator.defaultTrackingId,
                boundingBox: bbOutput
            )
        }
        
        let metadata = MetadataOutput(
            record_timestamp: recordTimestampString,
            gps_data: gpsData,
            image_file_timestamp: imageTimestampString,
            image_file_name: imageFileName,
            detections: detections
        )
        
        return metadata
    }
}
