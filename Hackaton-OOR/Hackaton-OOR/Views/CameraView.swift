import SwiftUI
import UIKit
import AVFoundation

// MARK: - Camera View Container with Exit Button
struct CameraViewContainer: View {
    @Binding var isCameraPresented: Bool
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            CameraViewControllerRepresentable()
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

// MARK: - UIViewControllerRepresentable for the Camera Preview
struct CameraViewControllerRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> CameraPreviewViewController {
        CameraPreviewViewController()
    }
    
    func updateUIViewController(_ uiViewController: CameraPreviewViewController, context: Context) {}
}

// MARK: - UIKit Camera Preview View Controller
class CameraPreviewViewController: UIViewController {
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            print("Failed to set up video input")
            return
        }
        captureSession.addInput(videoInput)
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(videoPreviewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        videoPreviewLayer.frame = view.bounds
        updateVideoOrientation()
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: { _ in
            self.videoPreviewLayer.frame = self.view.bounds
            self.updateVideoOrientation()
        })
    }
    
    private func updateVideoOrientation() {
        guard let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported else { return }
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
        connection.videoOrientation = orientation.avOrientation
    }
}

// MARK: - Orientation Mapping Extension
extension UIInterfaceOrientation {
    var avOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return .portrait
        }
    }
}
