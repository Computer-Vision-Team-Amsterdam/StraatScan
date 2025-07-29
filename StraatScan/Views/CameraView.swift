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
    private let logger = Logger(label: "nl.amsterdam.cvt.straatscan.CameraPreviewController")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        let detectionManager = DetectionManager.shared
        
        guard let previewLayer = detectionManager.videoCapture?.previewLayer else {
            logger.critical("Could not get previewLayer from DetectionManager. The video capture might not be configured.")
            // Use our global error handler to notify the user.
            CameraManager.logVideoInputError()
            return
        }
        
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        logger.info("CameraPreviewController successfully configured with DetectionManager's preview layer.")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        logger.info("Camera preview is appearing. Starting video session.")
        DetectionManager.shared.videoCapture?.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        logger.info("Camera preview is disappearing.")
        if !DetectionManager.shared.isDetectingForUpload {
            logger.info("Stopping video session as no detection is active.")
            DetectionManager.shared.videoCapture?.stop()
        } else {
            logger.info("Keeping video session running because a detection is active.")
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.layer.sublayers?.first?.frame = view.bounds
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate { _ in
            self.view.layer.sublayers?.first?.frame = self.view.bounds
        }
    }
}
