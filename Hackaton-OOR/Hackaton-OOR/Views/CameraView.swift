import SwiftUI
import UIKit
import AVFoundation
import Logging

// MARK: - Camera View Container with Exit Button
struct CameraViewContainer: View {
    @Binding var isCameraPresented: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraPreviewRepresentable()
                .edgesIgnoringSafeArea(.all)
            Button {
                isCameraPresented = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.white)
                    .padding()
            }
        }
    }
}

// MARK: - CameraPreviewRepresentable for the Camera Preview
struct CameraPreviewRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraPreviewController {
        CameraPreviewController()
    }
    
    func updateUIViewController(_ uiViewController: CameraPreviewController, context: Context) {}
}

// MARK: - UIKit Camera Preview Controller
class CameraPreviewController: UIViewController {
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private let logger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.CameraPreviewController")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Set up the capture session.
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            logger.error("Failed to get video device input.")
            CameraManager.presentVideoInputErrorAlert(on: self)
            return
        }
        captureSession.addInput(videoInput)
        
        // Set up the preview layer.
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(videoPreviewLayer)
        
        // Start running the session asynchronously.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer.frame = view.bounds
        updateVideoOrientation()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { _ in
            self.videoPreviewLayer.frame = self.view.bounds
            self.updateVideoOrientation()
        }
    }
    
    private func updateVideoOrientation() {
        guard let connection = videoPreviewLayer.connection else { return }
        
        let orientation = UIDevice.current.orientation
        
        switch orientation {
        case .portrait:
            connection.videoRotationAngle = 90
        case .portraitUpsideDown:
            connection.videoRotationAngle = 270
        case .landscapeLeft:
            connection.videoRotationAngle = 0
        case .landscapeRight:
            connection.videoRotationAngle = 180
        default:
            connection.videoRotationAngle = 90
        }
    }
}
