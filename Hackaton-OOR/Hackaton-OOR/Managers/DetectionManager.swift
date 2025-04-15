import Foundation
import AVFoundation
import CoreML
import Vision
import UIKit
import Logging

/// A singleton manager that encapsulates video capture and YOLO-based object detection.
class DetectionManager: NSObject, ObservableObject, VideoCaptureDelegate {
    // MARK: - Dependencies
    static let shared = DetectionManager()
    private var locationManager = LocationManager()
    private let iotManager = IoTDeviceManager()
    private var uploader: AzureIoTDataUploader?
    
    // MARK: - Private properties
    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.DetectionManager")
    
    /// Handles video capture from the device's camera.
    private var videoCapture: VideoCapture?
    
    /// The Vision request for performing object detection using the CoreML model.
    private var visionRequest: VNCoreMLRequest?
    
    /// The CoreML model used for object detection.
    private var mlModel: MLModel?
    
    /// The Vision model wrapper for the CoreML model.
    private var detector: VNCoreMLModel?
    
    /// Stores the last captured pixel buffer for saving or processing.
    private var lastPixelBufferForSaving: CVPixelBuffer?
    
    /// Timestamp of the last captured pixel buffer.
    private var lastPixelBufferTimestamp: TimeInterval?
    
    /// The current pixel buffer being processed.
    private var currentBuffer: CVPixelBuffer?
    
    /// The last known confidence threshold for object detection.
    private var lastConfidenceThreshold: Double
    
    /// The last known IoU threshold for object detection.
    private var lastIoUThreshold: Double
    
    /// The Azure IoT Hub host URL.
    private let iotHubHost: String
    
    /// Indicates whether the video capture has been successfully configured.
    private(set) var isConfigured: Bool = false
    
    // MARK: - Published properties
    
    /// The number of objects detected.
    @Published var objectsDetected = 0
    
    /// The total number of images processed.
    @Published var totalImages = 0
    
    /// The total number of images successfully delivered to Azure.
    @Published var imagesDelivered = 0
    
    /// The total number of minutes the detection has been running.
    @Published var minutesRunning = 0
    
    private var detectionTimer: Timer?
    
    // MARK: - Initialization
    
    /// Initializes the DetectionManager, loading the YOLO model and setting up video capture.
    override init() {
        // Fetch values from Info.plist
        let infoDict = Bundle.main.infoDictionary
        self.lastConfidenceThreshold = Double(infoDict?["ConfidenceThreshold"] as? String ?? "0.25") ?? 0.25
        self.lastIoUThreshold = Double(infoDict?["IoUThreshold"] as? String ?? "0.45") ?? 0.45
        self.iotHubHost = infoDict?["IoTHubHost"] as? String ?? "iothub-oor-ont-weu-itr-01.azure-devices.net"
        
        super.init()
        
        if !self.iotHubHost.isEmpty {
             self.uploader = AzureIoTDataUploader(host: self.iotHubHost, iotDeviceManager: self.iotManager)
        } else {
            // Log critical error if host is missing - uploader cannot function
            managerLogger.critical("IoTHubHost key is missing or empty in Info.plist. AzureIoTDataUploader cannot be initialized.")
            self.iotManager.notifyUserOfCredentialError(message: "IoT Hub configuration is missing. Upload functionality disabled.")
        }
        
        // 1. Load the YOLO model.
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .all
        
        do {
            // Replace `yolov8m` with the actual name of your generated model class.
            let loadedModel = try yolov8m(configuration: modelConfig).model
            self.mlModel = loadedModel
            let vnModel = try VNCoreMLModel(for: loadedModel)
            vnModel.featureProvider = ThresholdManager.shared.getThresholdProvider()
            self.detector = vnModel
        } catch {
            managerLogger.critical("Error loading model: \(error)")
        }
        
        // 2. Create the Vision request.
        if let detector = detector {
            visionRequest = VNCoreMLRequest(model: detector, completionHandler: { [weak self] request, error in
                self?.processObservations(for: request, error: error)
            })
            // Set the option for cropping/scaling (adjust as needed).
            visionRequest?.imageCropAndScaleOption = .scaleFill
        } else if self.mlModel != nil {
            managerLogger.critical("Error: Failed to create VNCoreMLModel from loaded MLModel.")
        } else {
            managerLogger.critical("Error: MLModel not loaded, cannot create Vision request.")
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
                self.managerLogger.critical("Video capture setup failed.")
                DispatchQueue.main.async {
                    self.iotManager.notifyUserOfCredentialError(message: "Failed to initialize video capture. Detection may not work.")
                }
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Starts the object detection process.
    /// Ensures the video capture is configured before starting.
    func startDetection() {
        guard isConfigured else {
            managerLogger.warning("Video capture not configured yet. Delaying startDetection()...")
            // Optionally, schedule a retry after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startDetection()
            }
            return
        }
        updateThresholdsIfNeeded()
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
        managerLogger.info("Detection stopped.")
        detectionTimer?.invalidate()
        detectionTimer = nil
    }
  
    // MARK: - Private Methods
    
    /// Updates the detection thresholds if they have been adjusted.
    private func updateThresholdsIfNeeded() {
        let tempProvider = ThresholdManager.shared.getThresholdProvider()
        let finalConf = tempProvider.confidenceThreshold
        let finalIoU = tempProvider.iouThreshold
        
        if finalConf != lastConfidenceThreshold || finalIoU != lastIoUThreshold {
            managerLogger.info("Updating thresholds: Confidence=\(finalConf), IoU=\(finalIoU)")
            detector?.featureProvider = tempProvider
            lastConfidenceThreshold = finalConf
            lastIoUThreshold = finalIoU
        }
    }
    
    // MARK: - VideoCaptureDelegate
    
    /// Processes each captured video frame for object detection.
    /// - Parameters:
    ///   - capture: The video capture instance.
    ///   - sampleBuffer: The captured video frame.
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame sampleBuffer: CMSampleBuffer) {
        // Only process if no other frame is currently being processed.
        if currentBuffer == nil, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
           let request = visionRequest {
            
            // Store the pixel buffer for later use (e.g., to convert to UIImage)
            currentBuffer = pixelBuffer
            self.lastPixelBufferForSaving = pixelBuffer
            self.lastPixelBufferTimestamp = NSDate().timeIntervalSince1970
            
            // Optionally, set the image orientation based on your needs.
            // Here we use .up for simplicity.
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                managerLogger.critical("Error performing Vision request: \(error)")
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
            managerLogger.critical("Vision request failed with error: \(error.localizedDescription)")
            return
        }

        guard let results = request.results as? [VNRecognizedObjectObservation], !results.isEmpty else {
            return
        }
        
        DispatchQueue.main.async(execute: {
            if let results = request.results as? [VNRecognizedObjectObservation] {
                // --- Step 1: Check if at least one "container" is detected.
                let containerDetected = results.contains { observation in
                    observation.labels.first?.identifier.lowercased() == "container"
                }
                
                // Only proceed if a container is detected.
                if containerDetected {
                    self.managerLogger.info("Container detected, processing frame...")
                    self.processDetectedFrame(results: results)
                }
            }
        })
    }
    
    /// Handles processing after a container has been detected in a frame.
    private func processDetectedFrame(results: [VNRecognizedObjectObservation]) {
        guard let pixelBuffer = self.lastPixelBufferForSaving else {
            managerLogger.critical("Error: Missing last pixel buffer for processing.")
            return
        }

        // Convert buffer to image (can fail)
        guard var image = self.imageFromPixelBuffer(pixelBuffer: pixelBuffer) else {
            managerLogger.critical("Error: Failed to convert pixel buffer to image.")
             self.lastPixelBufferForSaving = nil // Clear buffer if conversion failed
             return
        }

        let imageSize = image.size
        var sensitiveBoxes = [CGRect]()
        var containerBoxes = [CGRect]()

        for observation in results {
            if let label = observation.labels.first?.identifier.lowercased() {
                let normRect = observation.boundingBox
                let rectInImage = VNImageRectForNormalizedRect(normRect, Int(imageSize.width), Int(imageSize.height))

                if label == "container" {
                    self.objectsDetected += 1 // Increment on main thread
                    containerBoxes.append(rectInImage)
                } else if ["person", "license plate"].contains(label) { // Example sensitive classes
                    sensitiveBoxes.append(rectInImage)
                }
            }
        }

        if !sensitiveBoxes.isEmpty,
           let imageWithBlackBoxes = self.coverSensitiveAreasWithBlackBox(in: image, boxes: sensitiveBoxes) {
            image = imageWithBlackBoxes
        }
        image = self.drawSquaresAroundContainerAreas(in: image, boxes: containerBoxes)
        self.deliverDetectionToAzure(image: image, predictions: results)
        self.lastPixelBufferForSaving = nil
    }
    
    /// Converts a pixel buffer to a UIImage.
    /// - Parameter pixelBuffer: The pixel buffer to convert.
    /// - Returns: A UIImage representation of the pixel buffer, or `nil` if conversion fails.
    func imageFromPixelBuffer(pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
            return UIImage(cgImage: cgImage)
        }
        return nil
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
            let message = "Could not locate Documents folder."
            managerLogger.critical("\(message)")
            throw FileError.documentsFolderNotFound(message)
        }
        let detectionsFolderURL = documentsURL.appendingPathComponent("Detections")
        
        // Ensure the "Detections" folder exists.
        if !FileManager.default.fileExists(atPath: detectionsFolderURL.path) {
            do {
                try FileManager.default.createDirectory(at: detectionsFolderURL, withIntermediateDirectories: true, attributes: nil)
                managerLogger.info("Created Detections folder at: \(detectionsFolderURL.path)")
            } catch {
                managerLogger.critical("Error creating folder: \(error.localizedDescription)")
                throw FileError.documentsFolderNotFound("Error creating folder: \(error.localizedDescription)")
            }
        }
        return detectionsFolderURL
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmssSSS"
        let dateString = dateFormatter.string(from: Date())
        let fileNameBase = "detection_\(dateString)"

        // --- Upload Image ---
        if let imageData = image.jpegData(compressionQuality: 0.5) {
            let blobName = "\(fileNameBase).jpg"
            
            guard let uploader = self.uploader else {
                managerLogger.critical("Error: AzureIoTDataUploader not initialized. Cannot deliver detection.")
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
                    managerLogger.critical("Image upload failed for \(blobName): \(error.localizedDescription)")
                    saveFileLocally(data: imageData, filename: blobName)
                }
            }
        } else {
            managerLogger.critical("Error: Could not get JPEG data from processed image.")
        }

        // --- Upload Metadata ---
        let metadata = createMetadata(predictions: predictions, dateString: dateString)
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: metadata, options: .prettyPrinted)
            let blobName = "\(fileNameBase).json"
            
            // Use Task to call the async upload function
            Task {
                do {
                    managerLogger.info("Attempting to upload metadata: \(blobName)")
                    try await uploader?.uploadData(jsonData, blobName: blobName)
                    managerLogger.info("Metadata \(blobName) uploaded successfully!")
                } catch {
                    managerLogger.critical("Metadata upload failed for \(blobName): \(error.localizedDescription)")
                    saveFileLocally(data: jsonData, filename: blobName)
                }
            }
        } catch {
            managerLogger.critical("Error serializing metadata: \(error)")
        }
    }

    /// Creates the metadata dictionary for a detection event.
    private func createMetadata(predictions: [VNRecognizedObjectObservation], dateString: String) -> [String: Any] {
        var predictionsMetadata = [[String: Any]]()
        for prediction in predictions {
            if let bestLabel = prediction.labels.first?.identifier {
                let meta: [String: Any] = [
                    "label": bestLabel,
                    "confidence": prediction.labels.first?.confidence ?? 0,
                    "boundingBox": [
                        "x": prediction.boundingBox.origin.x,
                        "y": prediction.boundingBox.origin.y,
                        "width": prediction.boundingBox.size.width,
                        "height": prediction.boundingBox.size.height
                    ]
                ]
                predictionsMetadata.append(meta)
            }
        }

        var metadata: [String: Any] = [
            "date": dateString, // Use the consistent dateString
            "predictions": predictionsMetadata,
            // Include location data safely
            "latitude": locationManager.lastKnownLocation?.latitude as Any? ?? "",
            "longitude": locationManager.lastKnownLocation?.longitude as Any? ?? "",
            "image_timestamp": self.lastPixelBufferTimestamp as Any? ?? "",
            "gps_timestamp": locationManager.lastTimestamp as Any? ?? "",
            "gps_accuracy": locationManager.lastAccuracy as Any? ?? ""
        ]
        return metadata
    }

    /// Saves data locally to the Detections folder.
    private func saveFileLocally(data: Data, filename: String) {
        do {
            let detectionsFolderURL = try self.getDetectionsFolder()
            let fileURL = detectionsFolderURL.appendingPathComponent(filename)
            try data.write(to: fileURL)
            managerLogger.info("Saved file locally at \(fileURL.path)")
        } catch let error as FileError {
            managerLogger.critical("Error saving file \(filename) locally: \(error.localizedDescription)")
        } catch {
            managerLogger.critical("Unexpected error saving file \(filename) locally: \(error)")
        }
    }
    
    /// Uploads any remaining files in the "Detections" folder to Azure IoT Hub.
    func deliverFilesFromDocuments() {
        guard let uploader = self.uploader else {
            managerLogger.critical("Error: AzureIoTDataUploader not initialized. Cannot deliver stored files.")
             return
        }
        
        do {
            let detectionsFolderURL = try self.getDetectionsFolder()
            let fileURLs = try FileManager.default.contentsOfDirectory(at: detectionsFolderURL,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles])
            if fileURLs.isEmpty {
                managerLogger.info("No pending files found in Detections folder.")
                 return
            }
            
            managerLogger.info("Found \(fileURLs.count) pending files to upload.")
            DispatchQueue.main.async {
                self.totalImages += fileURLs.count
            }
            
            Task { [weak self] in
                guard let self = self else { return }
                for fileURL in fileURLs {
                    let blobName = fileURL.lastPathComponent
                    do {
                        let fileData = try Data(contentsOf: fileURL)
                        managerLogger.info("Attempting to upload stored file: \(blobName)")
                        try await uploader.uploadData(fileData, blobName: blobName)
                        managerLogger.info("Successfully uploaded stored file \(blobName). Deleting local copy.")

                        try FileManager.default.removeItem(at: fileURL)
                        managerLogger.info("Deleted local file \(blobName)")

                        DispatchQueue.main.async {
                            self.imagesDelivered += 1
                        }
                    } catch let error as AzureIoTError {
                        managerLogger.critical("Error uploading stored file \(blobName): \(error.localizedDescription)")
                    } catch {
                        managerLogger.critical("Error processing or uploading stored file \(blobName): \(error)")
                    }
                }
                managerLogger.info("Finished processing stored files.")
            }
        } catch let error as FileError {
            managerLogger.critical("Error accessing Detections folder: \(error.localizedDescription)")
        } catch {
            managerLogger.critical("Unexpected error retrieving contents of Detections folder: \(error)")
        }
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
    func drawSquaresAroundContainerAreas(
        in image: UIImage,
        boxes: [CGRect],
        color: UIColor = .red,
        lineWidth: CGFloat = 3.0
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: image.size)
        return renderer.image { context in
            image.draw(at: .zero)
            
            context.cgContext.setStrokeColor(color.cgColor)
            context.cgContext.setLineWidth(lineWidth)
            
            for box in boxes {
                // Convert the box from Vision's coordinate system (bottom-left origin)
                // to UIKit’s coordinate system (top-left origin)
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
