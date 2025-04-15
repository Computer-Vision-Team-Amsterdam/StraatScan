import SwiftUI
import AVFoundation
import Logging

/// A SwiftUI view that displays a live camera preview using the VideoCapture class.
struct CameraView: View {
    // Use an ObservableObject wrapper to manage the VideoCapture instance.
    @StateObject private var cameraManager = CameraManager()
    
    var body: some View {
        ZStack {
            // CameraPreview will wrap a UIView that shows the video preview.
            CameraPreview(videoCapture: cameraManager.videoCapture)
                .ignoresSafeArea()
            
            // (Optional) Add any overlay UI controls here
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        // Example action: stop the camera preview.
                        cameraManager.stopCapture()
                    }) {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: 60, height: 60)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
            }
        }
        .onAppear {
            cameraManager.startCapture()
        }
        .onDisappear {
            cameraManager.stopCapture()
        }
    }
}

/// A UIViewRepresentable that hosts the camera’s preview layer.
struct CameraPreview: UIViewRepresentable {
    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.CameraPreview")
    
    let videoCapture: VideoCapture
    
    func makeUIView(context: Context) -> UIView {
        // Create a plain UIView that will contain the camera preview.
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        // Set up the camera. The VideoCapture setUp method runs on a background queue.
        videoCapture.setUp { success in
            if success {
                DispatchQueue.main.async {
                    // Once setup is complete, ensure that the previewLayer is sized correctly.
                    if let previewLayer = videoCapture.previewLayer {
                        previewLayer.frame = view.bounds
                        previewLayer.videoGravity = .resizeAspectFill
                        // Add the preview layer to the view's layer hierarchy.
                        view.layer.insertSublayer(previewLayer, at: 0)
                    }
                }
            } else {
                self.managerLogger.critical("Failed to set up camera.")
            }
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update the preview layer's frame if the view’s size changes.
        if let previewLayer = videoCapture.previewLayer {
            previewLayer.frame = uiView.bounds
        }
        // Also update the video orientation when the view updates.
        videoCapture.updateVideoOrientation()
    }
}

/// An ObservableObject wrapper that manages the VideoCapture instance.
final class CameraManager: ObservableObject {
    /// Create a logger specific to this manager
    private let managerLogger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.CameraManager")
    
    let videoCapture = VideoCapture()
    
    /// Starts the camera capture session.
    func startCapture() {
        // Ensure the camera is set up before starting.
        videoCapture.setUp { success in
            if success {
                self.videoCapture.start()
            } else {
                self.managerLogger.critical("Camera setup failed.")
            }
        }
    }
    
    /// Stops the camera capture session.
    func stopCapture() {
        videoCapture.stop()
    }
}

struct CameraView_Previews: PreviewProvider {
    static var previews: some View {
        CameraView()
    }
}
