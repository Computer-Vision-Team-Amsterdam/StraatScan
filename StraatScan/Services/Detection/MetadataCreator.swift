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

struct ProjectInfo: Codable {
    let model_name: String
    let aml_model_version: Int
    let project_version: String
    let customer: String
}

struct MetadataOutput: Codable {
    let record_timestamp: String
    let gps_data: GPSDataOutput?
    let image_file_timestamp: String
    let image_file_name: String
    let detections: [DetectionOutput]
    let project: ProjectInfo?
}

struct RawMetaDataOutput: Codable {
    let record_timestamp: String
    let image_file_timestamp: String
    let gps_data: GPSDataOutput?
}

struct FullFrameMetadataOutput: Codable {
    let timestamp_start: String
    let timestamp_end: String
    let data_path: String
    let frames: [RawMetaDataOutput]
}

/// Formats a Date or Unix timestamp (Double) into ISO 8601 String (UTC, with microseconds).
private func formatTimestampToISO8601(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
    formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter.string(from: date)
}

/// Overload for TimeInterval (Unix timestamp).
private func formatTimestampToISO8601(_ timestamp: TimeInterval) -> String {
    let date = Date(timeIntervalSince1970: timestamp)
    return formatTimestampToISO8601(date)
}

struct MetadataCreator {
    private static let default_project_info = ProjectInfo(
        model_name: "yolov8m_1280_v2.2_curious_hill_12.pt",
        aml_model_version: 2,
        project_version: "StraatScan_v1.0",
        customer: "CVT"
    )
    
    /// Default object class ID for labels not found in the provided mapping.
    private static let unknownObjectClass = -1
    
    /// Default tracking ID if none is available.
    private static let defaultTrackingId = -1
    

    
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
        
        let recordTimestampString = formatTimestampToISO8601(Date())
        let imageTimestampString = formatTimestampToISO8601(imageTimestamp)
        let gpsData: GPSDataOutput?
        if let locData = locationData {
            gpsData = GPSDataOutput(
                latitude: locData.latitude,
                longitude: locData.longitude,
                coordinate_time_stamp: formatTimestampToISO8601(locData.timestamp),
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
            
            let x_center = prediction.boundingBox.origin.x + (prediction.boundingBox.width / 2)
            let y_center = 1 - (prediction.boundingBox.origin.y + (prediction.boundingBox.height / 2))

            let bbOutput = BoundingBoxOutput(
                x_center: x_center,
                y_center: y_center,
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
            detections: detections,
            project: MetadataCreator.default_project_info
        )
        
        return metadata
    }
}

class FullFrameMetadataCreator {
    private var startTimeStamp: TimeInterval
    private var metaDataList: [RawMetaDataOutput]
    private let maxLength: Int
    
    init() {
        let infoDict = Bundle.main.infoDictionary
        self.maxLength = Int(infoDict?["FullMetadataMaxLength"] as? String ?? "500") ?? 500
        self.startTimeStamp = -1
        self.metaDataList = []
    }
    
    private func reset() {
        self.startTimeStamp = -1
        self.metaDataList = []
    }
    
    func appendLocationData(imageTimeStamp: TimeInterval, locationData: LocationData?) -> Bool {
        if self.startTimeStamp == -1 {
            self.startTimeStamp = Date().timeIntervalSince1970
        }
        let recordTimestampString = formatTimestampToISO8601(Date())
        let imageTimestampString = formatTimestampToISO8601(imageTimeStamp)
        let gpsData: GPSDataOutput?
        if let locData = locationData {
            gpsData = GPSDataOutput(
                latitude: locData.latitude,
                longitude: locData.longitude,
                coordinate_time_stamp: formatTimestampToISO8601(locData.timestamp),
                accuracy: locData.accuracy
            )
        } else {
            gpsData = nil
        }
        let metaData = RawMetaDataOutput(
            record_timestamp: recordTimestampString,
            image_file_timestamp: imageTimestampString,
            gps_data: gpsData
        )
        self.metaDataList.append(metaData)
        
        if self.metaDataList.count >= self.maxLength {
            return false
        } else {
            return true
        }
    }
    
    func getFullMetaDataAndReset() -> FullFrameMetadataOutput? {
        if self.startTimeStamp == -1 {
            return nil
        }
        
        let startTimeString = formatTimestampToISO8601(self.startTimeStamp)
        let endTimeString = formatTimestampToISO8601(Date())
        let dataPath = "StraatScan"
        
        let fullMetaData = FullFrameMetadataOutput(
            timestamp_start: startTimeString,
            timestamp_end: endTimeString,
            data_path: dataPath,
            frames: self.metaDataList
        )
        
        self.reset()
        
        return fullMetaData
    }
    
}
