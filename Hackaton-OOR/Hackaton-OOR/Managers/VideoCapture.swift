//  Ultralytics YOLO 🚀 - AGPL-3.0 License
//
//  Video Capture for Ultralytics YOLOv8 Preview on iOS
//  Part of the Ultralytics YOLO app, this file defines the VideoCapture class to interface with the device's camera,
//  facilitating real-time video capture and frame processing for YOLOv8 model previews.
//  Licensed under AGPL-3.0. For commercial use, refer to Ultralytics licensing: https://ultralytics.com/license
//  Access the source code: https://github.com/ultralytics/yolo-ios-app
//
//  This class encapsulates camera initialization, session management, and frame capture delegate callbacks.
//  It dynamically selects the best available camera device, configures video input and output, and manages
//  the capture session. It also provides methods to start and stop video capture and delivers captured frames
//  to a delegate implementing the VideoCaptureDelegate protocol.

import AVFoundation
import CoreVideo
import UIKit

// MARK: - VideoCaptureDelegate
public protocol VideoCaptureDelegate: AnyObject {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame: CMSampleBuffer)
}

// MARK: - Camera selector
func bestCaptureDevice(for position: AVCaptureDevice.Position) -> AVCaptureDevice {
    if position == .back {
        if UserDefaults.standard.bool(forKey: "use_telephoto"),
           let device = AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back) {
            return device
        } else if let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back) {
            return device
        } else if let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back) {
            return device
        } else {
            fatalError("Expected back camera device is not available.")
        }
    } else if position == .front {
        if let device = AVCaptureDevice.default(.builtInTrueDepthCamera, for: .video, position: .front) {
            return device
        } else if let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front) {
            return device
        } else {
            fatalError("Expected front camera device is not available.")
        }
    } else {
        fatalError("Unsupported camera position: \(position)")
    }
}

// MARK: - VideoCapture
public class VideoCapture: NSObject {
    public var previewLayer: AVCaptureVideoPreviewLayer?
    public weak var delegate: VideoCaptureDelegate?

    let captureDevice = bestCaptureDevice(for: .back)
    let captureSession = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    var cameraOutput = AVCapturePhotoOutput()
    let queue = DispatchQueue(label: "camera-queue")

    // MARK: Setup
    public func setUp(
        sessionPreset: AVCaptureSession.Preset? = nil,
        completion: @escaping (Bool) -> Void
    ) {
        queue.async {
            let chosenPreset: AVCaptureSession.Preset = {
                if let preset = sessionPreset {
                    return preset
                }
                if let cameraSessionPreset = Bundle.main.object(forInfoDictionaryKey: "CameraSessionPreset") as? String {
                    return AVCaptureSession.Preset(rawValue: cameraSessionPreset)
                }
                return .hd1280x720
            }()

            let success = self.setUpCamera(sessionPreset: chosenPreset)
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: Camera configuration
    private func setUpCamera(sessionPreset: AVCaptureSession.Preset) -> Bool {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = sessionPreset

        guard let videoInput = try? AVCaptureDeviceInput(device: captureDevice) else {
            return false
        }
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.videoGravity = .resizeAspectFill
        preview.connection?.videoRotationAngle = 90
        self.previewLayer = preview

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ]

        videoOutput.videoSettings = settings
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        if captureSession.canAddOutput(cameraOutput) {
            captureSession.addOutput(cameraOutput)
        }

        applyCurrentOrientation(to: videoOutput.connection(with: .video))
        if let vConn = videoOutput.connection(with: .video) {
            previewLayer?.connection?.videoRotationAngle = vConn.videoRotationAngle
        }

        do {
            try captureDevice.lockForConfiguration()

            captureDevice.focusMode = .continuousAutoFocus
            captureDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            captureDevice.exposureMode = .continuousAutoExposure
            captureDevice.unlockForConfiguration()
        } catch {
            print("Unable to configure the capture device.")
            return false
        }

        captureSession.commitConfiguration()
        return true
    }

    // MARK: Session control
    public func start() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    // Stops the video capture session.
    public func stop() {
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    // MARK: Orientation handling
    func updateVideoOrientation() {
        guard let connection = videoOutput.connection(with: .video) else { return }
        applyCurrentOrientation(to: connection)
        previewLayer?.connection?.videoRotationAngle = connection.videoRotationAngle

        if let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput {
            connection.isVideoMirrored = currentInput.device.position == .front
        }
    }

    private func applyCurrentOrientation(to connection: AVCaptureConnection?) {
        guard let conn = connection else { return }
        switch UIDevice.current.orientation {
        case .portrait:          conn.videoRotationAngle = 90
        case .portraitUpsideDown: conn.videoRotationAngle = 270
        case .landscapeLeft:     conn.videoRotationAngle = 180
        case .landscapeRight:    conn.videoRotationAngle = 0
        default:                 conn.videoRotationAngle = 90
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension VideoCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        delegate?.videoCapture(self, didCaptureVideoFrame: sampleBuffer)
    }

    public func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Optionally handle dropped frames, e.g., due to full buffer.
    }
}
