import Foundation
import AVFoundation
import CoreML
import Vision
import UIKit
import Logging

// Define the specific errors for the DetectionManager
enum DetectionError: AppError {
    case ioTHubHostMissing
    case modelLoadingFailed(Error)
    case modelMetadataInvalid(String)
    case visionRequestSetupFailed
    case videoCaptureSetupFailed
    case pixelBufferConversionFailed
    case pixelBufferMissing
    case documentsFolderNotFound
    case fileOperationFailed(String, Error)
    case uploaderNotInitialized
    case imageEncodingFailed
    case metadataSerializationFailed(Error)
    case visionRequestFailed(Error)

    var title: String {
        switch self {
        case .ioTHubHostMissing:
            return "Configuration Error"
        case .modelLoadingFailed, .modelMetadataInvalid, .visionRequestSetupFailed:
            return "Model Setup Error"
        case .videoCaptureSetupFailed:
            return "Camera Error"
        case .pixelBufferConversionFailed, .pixelBufferMissing, .imageEncodingFailed:
            return "Image Processing Error"
        case .documentsFolderNotFound, .fileOperationFailed:
            return "File System Error"
        case .uploaderNotInitialized:
            return "Network Error"
        case .metadataSerializationFailed:
            return "Data Error"
        case .visionRequestFailed:
            return "Detection Error"
        }
    }

    var errorDescription: String? {
        switch self {
        case .ioTHubHostMissing:
            return "The Azure IoT Hub host URL is missing from the app's configuration. Upload functionality is disabled."
        case .modelLoadingFailed(let underlyingError):
            return "Failed to load the CoreML model. The app cannot perform detections. Reason: \(underlyingError.localizedDescription)"
        case .modelMetadataInvalid(let reason):
            return "The CoreML model's metadata is invalid or missing required keys. Class names may not be available. Reason: \(reason)"
        case .visionRequestSetupFailed:
            return "Failed to create the Vision request from the CoreML model. Detection will not work."
        case .videoCaptureSetupFailed:
            return "Failed to initialize the video capture session. Please check camera permissions and try again."
        case .pixelBufferConversionFailed:
            return "Failed to convert a captured video frame into an image for processing."
        case .pixelBufferMissing:
            return "The system tried to process a frame, but the captured video buffer was missing."
        case .documentsFolderNotFound:
            return "Could not find or create the local 'Detections' folder to save files."
        case .fileOperationFailed(let operation, let underlyingError):
            return "A file system operation failed: \(operation). Reason: \(underlyingError.localizedDescription)"
        case .uploaderNotInitialized:
            return "The data uploader is not available. Files will be saved locally for later upload."
        case .imageEncodingFailed:
            return "Could not convert the processed image to JPEG data for uploading."
        case .metadataSerializationFailed(let underlyingError):
            return "Failed to serialize detection metadata to JSON format. Reason: \(underlyingError.localizedDescription)"
        case .visionRequestFailed(let underlyingError):
            return "The object detection request failed. Reason: \(underlyingError.localizedDescription)"
        }
    }

    var typeIdentifier: String {
        switch self {
        case .ioTHubHostMissing:
            return "DetectionError.ioTHubHostMissing"
        case .modelLoadingFailed:
            return "DetectionError.modelLoadingFailed"
        case .modelMetadataInvalid:
            return "DetectionError.modelMetadataInvalid"
        case .visionRequestSetupFailed:
            return "DetectionError.visionRequestSetupFailed"
        case .videoCaptureSetupFailed:
            return "DetectionError.videoCaptureSetupFailed"
        case .pixelBufferConversionFailed:
            return "DetectionError.pixelBufferConversionFailed"
        case .pixelBufferMissing:
            return "DetectionError.pixelBufferMissing"
        case .documentsFolderNotFound:
            return "DetectionError.documentsFolderNotFound"
        case .fileOperationFailed:
            return "DetectionError.fileOperationFailed"
        case .uploaderNotInitialized:
            return "DetectionError.uploaderNotInitialized"
        case .imageEncodingFailed:
            return "DetectionError.imageEncodingFailed"
        case .metadataSerializationFailed:
            return "DetectionError.metadataSerializationFailed"
        case .visionRequestFailed:
            return "DetectionError.visionRequestFailed"
        }
    }
}

/// A singleton manager that encapsulates video capture and YOLO-based object detection.
class DetectionManager: NSObject, ObservableObject, VideoCaptureDelegate {
    // MARK: - Dependencies
    static let shared = DetectionManager()
    private var locationManager = LocationManager()
    private let iotManager = IoTDeviceManager()
    private var uploader: AzureIoTDataUploader?
    
    // MARK: - Private properties
    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.straatscan.DetectionManager")
    
    /// Handles video capture from the device's camera.
    var videoCapture: VideoCapture?
    
    /// The Vision request for performing object detection using the CoreML model.
    private var visionRequest: VNCoreMLRequest?
    
    /// The CoreML model used for object detection.
    private var mlModel: MLModel?
    
    /// The Vision model wrapper for the CoreML model.
    private var detector: VNCoreMLModel?
    
    /// Map between labels codes and names
    private var modelLabelMapping: [String: Int] = [:]
    
    /// Stores the last captured pixel buffer for saving or processing.
    private var lastPixelBufferForSaving: CVPixelBuffer?
    
    /// Timestamp of the last captured pixel buffer.
    private var lastPixelBufferTimestamp: TimeInterval?
    
    /// The current pixel buffer being processed.
    private var currentBuffer: CVPixelBuffer?
    
    /// The Azure IoT Hub host URL.
    private let iotHubHost: String
    
    /// The confidence threshold for all model classes
    private let confidenceThreshold: Double
    
    /// The compression rate for captured frames
    private var frameCompressionQuality: Double
    
    /// The line width when plotting bounding boxes on frames
    private var containerBoxLineWidth: CGFloat
    
    /// Indicates whether the video capture has been successfully configured.
    private(set) var isConfigured: Bool = false
    
    private var fullMetaDataCreator: FullFrameMetadataCreator
    
    // MARK: - Published properties
    
    /// Indicates if a formal detection for uploading is in progress.
    @Published private(set) var isDetectingForUpload: Bool = false
    
    /// The number of objects detected.
    @Published var objectsDetected = 0
    
    /// The total number of images processed.
    @Published var totalImages = 0
    private var checkedImagesFromFolder: Bool = false
    
    /// The total number of images successfully delivered to Azure.
    @Published var imagesDelivered = 0
    
    /// The total number of minutes the detection has been running.
    @Published var minutesRunning = 0

    /// Snapshot of the drawBoundingBoxes setting at detection start.
    private var drawBoundingBoxes: Bool = false

    private var detectionTimer: Timer?
    
    /// The time interval between processed frames.
    private var lastFrameTime: TimeInterval = 0
    
    /// The frame rate being used to process frames by the model.
    private lazy var frameRateFPS: Double = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "FrameRateFPS") as? String,
           let v = Double(s) {
            return v
        }
        return Bundle.main.object(forInfoDictionaryKey: "FrameRateFPS") as? Double ?? 2.0
    }()
    
    // MARK: - Initialization
    
    /// Initializes the DetectionManager, loading the YOLO model and setting up video capture.
    override init() {
        // Use centralized configuration from AppConfiguration.
        // Fetch values from Info.plist
        let infoDict = Bundle.main.infoDictionary
        self.iotHubHost = infoDict?["IoTHubHost"] as? String ?? "iothub-oor-ont-weu-itr-01.azure-devices.net"
        self.confidenceThreshold = Double(infoDict?["ConfidenceThreshold"] as? String ?? "0.45") ?? 0.45
        self.frameCompressionQuality = Double(infoDict?["FrameCompressionQuality"] as? String ?? "0.5") ?? 0.5
        self.containerBoxLineWidth = CGFloat((infoDict?["ContainerBoxLineWidth"] as? String).flatMap(Double.init) ?? 3)
        
        // Set up full frame metadata creator.
        fullMetaDataCreator = FullFrameMetadataCreator()
        
        super.init()
        
        if !self.iotHubHost.isEmpty {
            self.uploader = AzureIoTDataUploader(host: self.iotHubHost, iotDeviceManager: self.iotManager)
        } else {
            logError(DetectionError.ioTHubHostMissing, managerLogger)
        }
        
        // 1. Load the YOLO model.
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .all
        
        do {
            let loadedModel = try yolov8m(configuration: modelConfig).model
            self.mlModel = loadedModel
            let vnModel = try VNCoreMLModel(for: loadedModel)
            let thresholdProvider = try MLDictionaryFeatureProvider(dictionary: [
            "confidenceThreshold": MLFeatureValue(double: self.confidenceThreshold)
            ])
            print("Confidence threshold provider: \(thresholdProvider)")
            vnModel.featureProvider = thresholdProvider
            self.detector = vnModel
            
            guard let model = self.mlModel else {
                throw NSError(domain: "DetectionManagerError", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLModel is nil after loading."])
            }
            
            let metadata = model.modelDescription.metadata
            managerLogger.debug("Model metadata keys: \(metadata.keys)")
            
            if let creatorMetadataAny = metadata[MLModelMetadataKey.creatorDefinedKey],
               let creatorMetadataDict = creatorMetadataAny as? [String: Any],
               let namesString = creatorMetadataDict["names"] as? String {
                var names: [String] = []
                let trimmedContent = namesString.trimmingCharacters(in: CharacterSet(charactersIn: "{} "))
                
                if !trimmedContent.isEmpty {
                    let components = trimmedContent.split(separator: ",")
                    
                    names = components.compactMap { component -> String? in
                        guard let colonIndex = component.firstIndex(of: ":") else { return nil }
                        let valuePart = component[component.index(after: colonIndex)...]
                        let name = valuePart.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "'")))
                        return name.isEmpty ? nil : String(name)
                    }
                    if names.isEmpty {
                        logError(DetectionError.modelMetadataInvalid("Parsing 'names' string resulted in an empty array."), managerLogger)
                    } else {
                        var generatedMapping: [String: Int] = [:]
                        for (index, name) in names.enumerated() {
                            generatedMapping[name.lowercased()] = index
                        }
                        self.modelLabelMapping = generatedMapping
                        managerLogger.info("Successfully generated label mapping from model (\(self.modelLabelMapping.count) classes). Parsed names: \(names)")
                    }
                }
                
            } else {
                if metadata[MLModelMetadataKey.creatorDefinedKey] == nil {
                    logError(DetectionError.modelMetadataInvalid("Model metadata does not contain creatorDefinedKey"), managerLogger)
                } else if (metadata[MLModelMetadataKey.creatorDefinedKey] as? [String: Any]) == nil {
                    logError(DetectionError.modelMetadataInvalid("Value for creatorDefinedKey is not [String: Any]"), managerLogger)
                } else if (metadata[MLModelMetadataKey.creatorDefinedKey] as! [String: Any])["names"] == nil {
                    logError(DetectionError.modelMetadataInvalid("Creator metadata dictionary does not contain key 'names'."), managerLogger)
                } else if (metadata[MLModelMetadataKey.creatorDefinedKey] as! [String: Any])["names"] as? String == nil {
                    logError(DetectionError.modelMetadataInvalid("Value for key 'names' is not a String."), managerLogger)
                } else {
                    logError(DetectionError.modelMetadataInvalid("Could not extract 'names' string from model metadata for unknown reason."), managerLogger)
                }
            }
        } catch {
            logError(DetectionError.modelLoadingFailed(error), managerLogger)
        }
        
        // 2. Create the Vision request.
        if let detector = detector {
            visionRequest = VNCoreMLRequest(model: detector, completionHandler: { [weak self] request, error in
                self?.processObservations(for: request, error: error)
            })
            // Set the option for cropping/scaling (adjust as needed).
            visionRequest?.imageCropAndScaleOption = .scaleFill
        } else {
            logError(DetectionError.visionRequestSetupFailed, managerLogger)
        }
        
        // 3. Set up video capture.
        videoCapture = VideoCapture()
        videoCapture?.delegate = self
        // You can change the sessionPreset if needed.
        videoCapture?.setUp(sessionPreset: .hd1280x720) { success in
            if success {
                self.managerLogger.info("Video capture setup successful.")
                self.isConfigured = true
            } else {
                logError(DetectionError.videoCaptureSetupFailed, self.managerLogger)
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts the object detection process.
    /// Ensures the video capture is configured before starting.
    func startDetection() {
        self.drawBoundingBoxes = UserDefaults.standard.bool(forKey: "drawBoundingBoxes")
        print("drawBoundingBoxes: \(self.drawBoundingBoxes)")
        guard isConfigured else {
            managerLogger.warning("Video capture not configured yet. Delaying startDetection()...")
            // Optionally, schedule a retry after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIDevice.current.beginGeneratingDeviceOrientationNotifications()
                self.startDetection()
            }
            return
        }
        self.isDetectingForUpload = true
        videoCapture?.start()
        managerLogger.info("Detection started.")
        detectionTimer?.invalidate()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.minutesRunning += 1
            }
        }
    }
    
    /// Stops the object detection process and invalidates the detection timer.
    func stopDetection() {
        videoCapture?.stop()
        self.isDetectingForUpload = false
        managerLogger.info("Detection stopped.")
        self.writeFullFrameMetadata()
        detectionTimer?.invalidate()
        detectionTimer = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    /// Map UIDevice orientation → EXIF orientation for Vision
    private func exifOrientationForCurrentDevice() -> CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portrait:           return .up  // home button / gesture bar at bottom
        case .portraitUpsideDown: return .down    // home button / gesture bar at top
        case .landscapeLeft:      return .left   // home button on the right
        case .landscapeRight:     return .right  // home button on the left
        default:                  return .up   // assume portrait
        }
    }
    
    // MARK: - VideoCaptureDelegate
    
    /// Processes each captured video frame for object detection.
    /// - Parameters:
    ///   - capture: The video capture instance.
    ///   - sampleBuffer: The captured video frame.
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        // compute minimum seconds between frames and skip if too fast.
        let now = Date().timeIntervalSince1970
        let interval = 1.0 / frameRateFPS
        guard now - lastFrameTime >= interval else { return }
        lastFrameTime = now
        
        // Only process if no other frame is currently being processed.
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let request = visionRequest {
            
            // Store the pixel buffer for later use (e.g., to convert to UIImage)
            currentBuffer = pixelBuffer
            self.lastPixelBufferForSaving = pixelBuffer
            self.lastPixelBufferTimestamp = NSDate().timeIntervalSince1970
            
            let orientation = exifOrientationForCurrentDevice()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logError(DetectionError.visionRequestFailed(error), managerLogger)
            }
            // Reset the currentBuffer so that you can process the next frame.
            currentBuffer = nil
        }
    }
    
    // MARK: - Process Detection Results
    
    /// Processes the results of the Vision request.
    /// - Parameters:
    ///   - request: The Vision request containing detection results.
    ///   - error: An optional error if the request failed.
    func processObservations(for request: VNRequest, error: Error?) {
        if let error = error {
            logError(DetectionError.visionRequestFailed(error), managerLogger)
            return
        }
        
        self.appendRawMetaData()
        
        guard let results = request.results as? [VNRecognizedObjectObservation], !results.isEmpty else {
            return
        }
        
        DispatchQueue.main.async(execute: {
            if let results = request.results as? [VNRecognizedObjectObservation] {

                let targetClasses: [(name: String, enabled: Bool)] = [
                    ("container", UserDefaults.standard.bool(forKey: "detectContainers")),
                    ("mobile toilet", UserDefaults.standard.bool(forKey: "detectMobileToilets")),
                    ("scaffolding", UserDefaults.standard.bool(forKey: "detectScaffoldings"))
                ]

                // --- Step 1: Check if at least one enabled target is detected in the observations.
                let shouldProcess = targetClasses.contains { (objectName, isEnabled) in
                    return isEnabled && results.contains { observation in
                        if let label = observation.labels.first?.identifier.lowercased() {
                            return label == objectName
                        }
                        return false
                    }
                }
                if shouldProcess {
                    self.managerLogger.info("Object detected, processing frame...")
                    self.processDetectedFrame(results: results, targetClasses: targetClasses)
                }
            }
        })
    }
    
    /// Handles processing after a container has been detected in a frame.
    private func processDetectedFrame(results: [VNRecognizedObjectObservation], targetClasses: [(name: String, enabled: Bool)]) {
        guard let pixelBuffer = self.lastPixelBufferForSaving else {
            logError(DetectionError.pixelBufferMissing, managerLogger)
            return
        }
        
        // Convert buffer to image (can fail)
        guard var image = self.imageFromPixelBuffer(pixelBuffer: pixelBuffer) else {
            logError(DetectionError.pixelBufferConversionFailed, managerLogger)
            self.lastPixelBufferForSaving = nil // Clear buffer if conversion failed
            return
        }

        // --- Step 2: Identify sensitive objects and collect their bounding boxes.
        // Define your sensitive classes.
        let sensitiveClasses: Set<String> = ["person", "license plate"]
        var sensitiveBoxes = [CGRect]()
        var detectedBoxes: [String: [CGRect]] = [:]
        var detectionCounts: [String: Int] = [:]
        
        // For each observation that is sensitive, convert its normalized bounding box to image coordinates.
        // (Assume 'image' is created from your saved pixel buffer.)
        if let pixelBuffer = self.lastPixelBufferForSaving,
            var image = self.imageFromPixelBuffer(pixelBuffer: pixelBuffer) {
            
            let imageSize = image.size
            for observation in results {
                if let label = observation.labels.first?.identifier.lowercased() {
                    let normRect = observation.boundingBox
                    let rectInImage = VNImageRectForNormalizedRect(normRect, Int(imageSize.width), Int(imageSize.height))

                    if targetClasses.contains(where: { $0.enabled && $0.name == label }) {
                        detectedBoxes[label, default: []].append(rectInImage)
                        detectionCounts[label, default: 0] += 1
                    } else if sensitiveClasses.contains(label) {
                        sensitiveBoxes.append(rectInImage)
                    }
                }
            }

            let totalDetected = detectionCounts.values.reduce(0, +)
            DispatchQueue.main.async {
                self.objectsDetected += totalDetected
            }
            
            if !sensitiveBoxes.isEmpty,
                let imageWithBlackBoxes = self.coverSensitiveAreasWithBlackBox(in: image, boxes: sensitiveBoxes) {
                image = imageWithBlackBoxes
            }

            // If drawing bounding boxes is enabled, draw them on the image.
            if drawBoundingBoxes {
                let colors: [String: UIColor] = [
                    "container": .red,
                    "mobile toilet": .blue,
                    "scaffolding": .green
                ]
                image = self.drawSquaresAroundDetectedAreas(in: image, boxesPerObject: detectedBoxes, colors: colors)
            }
            
            // Get list of target class names
            var targetClassNames: [String] = []
            for (objectName, isEnabled) in targetClasses {
                if isEnabled {
                    targetClassNames.append(objectName)
                }
            }
            
            // filter predictions belonging to target classes
            var targetPredictions: [VNRecognizedObjectObservation] = []
            for prediction in results {
                guard let className = prediction.labels.first?.identifier.lowercased() else {
                    continue
                }
                if targetClassNames.contains(className) {
                    targetPredictions.append(prediction)
                }
            }
            
            self.deliverDetectionToAzure(image: image, predictions: targetPredictions)
            self.lastPixelBufferForSaving = nil
        }
    }
    
    /// Converts a pixel buffer to a UIImage.
    /// - Parameter pixelBuffer: The pixel buffer to convert.
    /// - Returns: A UIImage representation of the pixel buffer, or `nil` if conversion fails.
    func imageFromPixelBuffer(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            .oriented(exifOrientationForCurrentDevice())
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
    
    enum FileError: Error {
        case documentsFolderNotFound(String)
        case fileOperationFailed(String, Error)
    }
    
    /// Retrieves the "Detections" folder in the app's Documents directory.
    /// - Throws: An error if the folder cannot be located or created.
    /// - Returns: The URL of the "Detections" folder.
    func getDetectionsFolder() throws -> URL {
        // Locate the "Detections" folder in the app’s Documents directory.
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            let error = DetectionError.documentsFolderNotFound
            logError(error, managerLogger)
            throw error
        }
        let detectionsFolderURL = documentsURL.appendingPathComponent("Detections")
        
        // Ensure the "Detections" folder exists.
        if !FileManager.default.fileExists(atPath: detectionsFolderURL.path) {
            do {
                try FileManager.default.createDirectory(at: detectionsFolderURL, withIntermediateDirectories: true, attributes: nil)
                managerLogger.info("Created Detections folder at: \(detectionsFolderURL.path)")
            } catch let creationError {
                let error = DetectionError.fileOperationFailed("Create Detections folder", creationError)
                logError(error, managerLogger)
                throw error
            }
        }
        return detectionsFolderURL
    }
    
    private func appendRawMetaData() {
        let imageTimestamp = self.lastPixelBufferTimestamp ?? Date().timeIntervalSince1970
        
        var currentLocationData: LocationData? = nil
        if let lastKnownLocation = locationManager.lastKnownLocation,
           let timestamp = locationManager.lastTimestamp,
           let accuracy = locationManager.lastAccuracy {
            currentLocationData = LocationData(
                latitude: lastKnownLocation.latitude,
                longitude: lastKnownLocation.longitude,
                timestamp: timestamp,
                accuracy: accuracy
            )
        } else {
            managerLogger.warning("Location data unavailable for metadata.")
        }
        
        let store_ok = fullMetaDataCreator.appendLocationData(imageTimeStamp: imageTimestamp, locationData: currentLocationData)
        if !store_ok {
            self.writeFullFrameMetadata()
        }
    }
    
    func writeFullFrameMetadata() {
        guard let fullMetaDataObject = fullMetaDataCreator.getFullMetaDataAndReset() else {
            managerLogger.debug("No full frame metadata to write.")
            return
        }
        
        // Generate filename base
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let fileDateString = fileDateFormatter.string(from: Date())
        let fileNameBase = "raw_metadata_\(fileDateString)"
        
        // Genarate date subfolder name
        let folderDateFormatter = DateFormatter()
        folderDateFormatter.dateFormat = "yyyy-MM-dd"
        let folderName = folderDateFormatter.string(from: Date())
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(fullMetaDataObject)
            let blobName = "full_frame_metadata/\(folderName)/\(fileNameBase).json"
            
            guard let uploader = self.uploader else {
                logError(DetectionError.uploaderNotInitialized, managerLogger)
                saveFileLocally(data: jsonData, filename: blobName)
                return
            }
            
            Task {
                do {
                    managerLogger.info("Attempting to upload metadata: \(blobName)")
                    try await uploader.uploadData(jsonData, blobName: blobName)
                    managerLogger.info("Full frame metadata \(blobName) uploaded successfully!")
                } catch {
                    saveFileLocally(data: jsonData, filename: blobName)
                }
            }
        } catch {
            logError(DetectionError.metadataSerializationFailed(error), managerLogger)
        }
    }
    
    /// Delivers the detection results to Azure IoT Hub.
    /// - Parameters:
    ///   - image: The image containing the detection results.
    ///   - predictions: The list of detected objects.
    func deliverDetectionToAzure(image: UIImage, predictions: [VNRecognizedObjectObservation]) {
        managerLogger.info("Preparing detection data for Azure delivery...")
        DispatchQueue.main.async {
            self.totalImages += 1
        }
        
        // Generate filename base
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let fileDateString = fileDateFormatter.string(from: Date())
        let fileNameBase = "detection_\(fileDateString)"
        
        // Genarate date subfolder name
        let folderDateFormatter = DateFormatter()
        folderDateFormatter.dateFormat = "yyyy-MM-dd"
        let folderName = folderDateFormatter.string(from: Date())
        
        // --- Upload Image ---
        if let imageData = image.jpegData(compressionQuality: self.frameCompressionQuality) {
            let blobName = "images/\(folderName)/\(fileNameBase).jpg"
            
            guard let uploader = self.uploader else {
                logError(DetectionError.uploaderNotInitialized, managerLogger)
                saveFileLocally(data: imageData, filename: blobName)
                return
            }
            
            // Use Task to call the async upload function
            Task {
                do {
                    managerLogger.info("Attempting to upload image: \(blobName)")
                    try await uploader.uploadData(imageData, blobName: blobName)
                    DispatchQueue.main.async {
                        self.imagesDelivered += 1
                    }
                    managerLogger.info("Image \(blobName) uploaded successfully!")
                } catch {
                    saveFileLocally(data: imageData, filename: blobName)
                }
            }
        } else {
            logError(DetectionError.imageEncodingFailed, managerLogger)
        }
        
        // --- Upload Metadata ---
        let metadataCreator = MetadataCreator()
        let currentImageFileName = "\(fileNameBase).jpg" // Example
        
        var currentLocationData: LocationData? = nil
        if let lastKnownLocation = locationManager.lastKnownLocation,
           let timestamp = locationManager.lastTimestamp,
           let accuracy = locationManager.lastAccuracy {
            currentLocationData = LocationData(
                latitude: lastKnownLocation.latitude,
                longitude: lastKnownLocation.longitude,
                timestamp: timestamp,
                accuracy: accuracy
            )
        } else {
            managerLogger.warning("Location data unavailable for metadata.")
        }
        
        let metadataObject: MetadataOutput = metadataCreator.create(
            predictions: predictions,
            imageTimestamp: self.lastPixelBufferTimestamp ?? Date().timeIntervalSince1970,
            locationData: currentLocationData,
            imageFileName: currentImageFileName,
            labelMapping: self.modelLabelMapping
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(metadataObject)
            let blobName = "detection_metadata/\(folderName)/\(fileNameBase).json"
            
            Task {
                do {
                    managerLogger.info("Attempting to upload metadata: \(blobName)")
                    try await uploader?.uploadData(jsonData, blobName: blobName)
                    managerLogger.info("Metadata \(blobName) uploaded successfully!")
                } catch {
                    saveFileLocally(data: jsonData, filename: blobName)
                }
            }
        } catch {
            logError(DetectionError.metadataSerializationFailed(error), managerLogger)
        }
    }
    
    /// Saves data locally to the Detections folder.
    private func saveFileLocally(data: Data, filename: String) {
        do {
            let detectionsFolderURL = try self.getDetectionsFolder()
            let blobFileURL = URL(fileURLWithPath: detectionsFolderURL.path + "/" + filename)
            
            // Ensure the folder structure exists.
            let blobDirUrl = blobFileURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: blobDirUrl.path) {
                try FileManager.default.createDirectory(at: blobDirUrl, withIntermediateDirectories: true, attributes: nil)
                managerLogger.info("Created folder at: \(blobDirUrl.path)")
            }
            try data.write(to: blobFileURL)
            managerLogger.info("Saved file locally at \(blobFileURL.path)")
        } catch let error as FileError {
            logError(DetectionError.fileOperationFailed(filename, error), managerLogger)
        } catch {
            logError(DetectionError.fileOperationFailed(filename, error), managerLogger)
        }
    }
    
    /// Uploads any remaining files in the "Detections" folder to Azure IoT Hub.
    func deliverFilesFromDocuments() {
        guard let uploader = self.uploader else {
            logError(DetectionError.uploaderNotInitialized, managerLogger)
            return
        }
        
        do {
            let detectionsFolderURL = try self.getDetectionsFolder()

            var fileURLs = [URL]()
            if let enumerator = FileManager.default.enumerator(at: detectionsFolderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                for case let fileURL as URL in enumerator {
                    do {
                        let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
                        if fileAttributes.isRegularFile! {
                            fileURLs.append(fileURL)
                        }
                    } catch {
                        logError(DetectionError.fileOperationFailed(fileURL.path, error), managerLogger)
                    }
                }
            }
            
            if fileURLs.isEmpty {
                managerLogger.info("No pending files found in Detections folder.")
                return
            }
            
            managerLogger.info("Found \(fileURLs.count) pending files to upload.")
            if !checkedImagesFromFolder {
                DispatchQueue.main.async {
                    self.totalImages += fileURLs.count
                }
                checkedImagesFromFolder = true
            }
            
            Task { [weak self] in
                guard let self = self else { return }
                for fileURL in fileURLs {
                    do {
                        let baseFolderURL = try self.getDetectionsFolder()
                        guard let blobName = self.relativePath(to: fileURL, from: baseFolderURL) else {
                            self.managerLogger.critical("Failed to generate relative path to \(fileURL.path) from \(baseFolderURL.path).")
                            return
                        }
                        
                        let fileData = try Data(contentsOf: fileURL)
                        managerLogger.info("Attempting to upload stored file: \(blobName)")
                        try await uploader.uploadData(fileData, blobName: blobName)
                        managerLogger.info("Successfully uploaded stored file \(blobName). Deleting local copy.")
                        
                        try FileManager.default.removeItem(at: fileURL)
                        managerLogger.info("Deleted local file \(blobName)")
                        
                        DispatchQueue.main.async {
                            self.imagesDelivered += 1
                        }
                    } catch {
                        self.managerLogger.critical("Failed to process and clear stored file \(fileURL.path). It will be retried later.")
                    }
                }
                managerLogger.info("Finished processing stored files.")
            }
        } catch {
            managerLogger.critical("Unexpected error retrieving contents of Detections folder: \(error)")
        }
    }

    func relativePath(to path: URL, from base: URL) -> String? {
        // From https://stackoverflow.com/a/56054033
        
        // Ensure that both URLs represent files:
        guard path.isFileURL && base.isFileURL else {
            return nil
        }

        //this is the new part, clearly, need to use workBase in lower part
        var workBase = base
        if workBase.pathExtension != "" {
            workBase = workBase.deletingLastPathComponent()
        }

        // Remove/replace "." and "..", make paths absolute:
        let destComponents = path.standardized.resolvingSymlinksInPath().pathComponents
        let baseComponents = workBase.standardized.resolvingSymlinksInPath().pathComponents

        // Find number of common path components:
        var i = 0
        while i < destComponents.count &&
              i < baseComponents.count &&
              destComponents[i] == baseComponents[i] {
                i += 1
        }

        // Build relative path:
        var relComponents = Array(repeating: "..", count: baseComponents.count - i)
        relComponents.append(contentsOf: destComponents[i...])
        return relComponents.joined(separator: "/")
    }
    
    /// Covers sensitive areas in an image with black boxes.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - boxes: The bounding boxes of sensitive areas.
    /// - Returns: A new image with sensitive areas covered, or `nil` if processing fails.
    func coverSensitiveAreasWithBlackBox(in image: UIImage, boxes: [CGRect]) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        var outputImage = ciImage
        let context = CIContext(options: nil)
        
        for box in boxes {
            guard let colorFilter = CIFilter(name: "CIConstantColorGenerator") else { continue }
            let blackColor = CIColor(color: .black)
            colorFilter.setValue(blackColor, forKey: kCIInputColorKey)
            
            guard let fullBlackImage = colorFilter.outputImage?.cropped(to: box) else { continue }
            
            if let compositeFilter = CIFilter(name: "CISourceOverCompositing") {
                compositeFilter.setValue(fullBlackImage, forKey: kCIInputImageKey)
                compositeFilter.setValue(outputImage, forKey: kCIInputBackgroundImageKey)
                if let composited = compositeFilter.outputImage {
                    outputImage = composited
                }
            }
        }
        if let cgImage = context.createCGImage(outputImage, from: outputImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
    }
    
    /// Draws rectangles around container areas in an image.
    /// - Parameters:
    ///   - image: The image to process.
    ///   - boxes: The bounding boxes of container areas.
    ///   - color: The color of the rectangles (default is red).
    ///   - lineWidth: The width of the rectangle lines (default is 3.0).
    /// - Returns: A new image with rectangles drawn around container areas.
    func drawSquaresAroundDetectedAreas(
        in image: UIImage,
        boxesPerObject: [String: [CGRect]],
        colors: [String: UIColor],
        lineWidth: CGFloat? = nil
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        let stroke = lineWidth ?? containerBoxLineWidth
        return renderer.image { context in
            image.draw(at: .zero)
            
            for (label, boxes) in boxesPerObject {
                let color = colors[label] ?? .yellow // Default if label not found.
                context.cgContext.setStrokeColor(color.cgColor)
                context.cgContext.setLineWidth(3.0)
                
                for box in boxes {
                    // Adjust for coordinate system conversion.
                    let adjustedBox = CGRect(
                        x: box.origin.x,
                        y: image.size.height - box.origin.y - box.size.height,
                        width: box.size.width,
                        height: box.size.height
                    )
                    context.cgContext.stroke(adjustedBox)
                }
            }
        }
    }
}
