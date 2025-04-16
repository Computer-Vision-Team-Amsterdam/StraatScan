import SwiftUI
import CoreLocation
import Network
import AVFoundation

func getAvailableDiskSpace() -> Int {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory())
    do {
        let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage {
            // Convert bytes to GB
            return Int(available / (1024 * 1024 * 1024))
        }
    } catch {
        print("Error retrieving available disk space: \(error)")
    }
    return 0
}

struct MainView: View {
    @EnvironmentObject var iotManager: IoTDeviceManager
    @StateObject private var locationManager = LocationManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @ObservedObject private var detectionManager = DetectionManager.shared
    
    @State private var storageAvailable: Int = 0
    @State private var detectContainers: Bool = UserDefaults.standard.bool(forKey: "detectContainers")
    
    // States for bottom section (static/recording info)
    @State private var recordedHours: String = "0:00"
    @State private var totalImages: Int = 0
    
    // Detection-related states
    @State private var isDetecting: Bool = false
    @State private var showingStopConfirmation = false
    @State private var showCameraView: Bool = false
    @State private var isCameraAuthorized: Bool = false
    @State private var showCameraAccessDeniedAlert: Bool = false
    
    private var isLocationAuthorized: Bool {
        // Accesses the authorizationStatus published by the locationManager instance
        locationManager.authorizationStatus == .authorizedWhenInUse || locationManager.authorizationStatus == .authorizedAlways
    }
    
    // Timer to check storage periodically
    let storageTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()
    // Timer to attempt uploading stored files periodically (e.g., every 5 minutes)
    let deliverToAzureTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()
    
    var formattedTime: String {
        let totalSeconds = detectionManager.minutesRunning * 60
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(totalSeconds)) ?? "00:00"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isDetecting {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(1.5) // Increase the size of the circular indicator.
                        Text("Detecting...")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                }
                .frame(height: 90)
            } else {
                // Placeholder to maintain layout when not detecting.
                Rectangle()
                    .frame(height: 90)
                    .foregroundColor(.clear)
            }
            
            HStack {
                Text("Camera Preview")
                Spacer()
                Button(action: {
                    CameraManager.checkAndRequestCameraAccess { authorized in
                        isCameraAuthorized = authorized
                        if authorized {
                            showCameraView = true
                        } else {
                            showCameraAccessDeniedAlert = true
                        }
                    }
                }) {
                    Image(systemName: "camera.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundColor(isDetecting ? Color.gray : Color.blue)
                }
                .disabled(isDetecting)
            }
            
            Divider()
            
            // GPS Active
            HStack {
                Text("GPS Active")
                Spacer()
                let isActive = locationManager.isReceivingLocationUpdates
                Text(isActive ? "ACTIVE" : "INACTIVE")
                    .foregroundColor(isActive ? .green : .red)
            }
            
            Divider()
            
            // GPS Accuracy
            HStack {
                Text("GPS accuracy (m)")
                Spacer()
                if let accuracy = locationManager.lastAccuracy {
                    Text(String(format: "%.2f", accuracy)).foregroundColor(.green)
                } else {
                    Text("N/A").foregroundColor(.red)
                }
            }
            
            Divider()
            
            // Internet Connection
            HStack {
                Text("Internet connection")
                Spacer()
                Text(networkMonitor.internetAvailable ? "ON" : "OFF")
                    .foregroundColor(networkMonitor.internetAvailable ? .green : .red)
            }
            
            Divider()
            
            // Storage Available
            HStack {
                Text("Storage available")
                Spacer()
                Text("\(storageAvailable)GB")
                    .foregroundColor(.green)
            }
        
            Divider()
            
            ZStack(alignment: .bottom){
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Text("Detect containers")
                        Spacer()
                        Text(detectContainers ? "ON" : "OFF")
                            .foregroundColor(detectContainers ? .green : .red)
                    }
                    
                    Divider()
                    
                    // Recorded Hours
                    HStack {
                        Text("Recorded hours")
                        Spacer()
                        Text(formattedTime)
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Total Images
                    HStack {
                        Text("Total images")
                        Spacer()
                        Text("\(detectionManager.totalImages)")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Objects Detected
                    HStack {
                        Text("Objects detected")
                        Spacer()
                        Text("\(detectionManager.objectsDetected)")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Images Delivered
                    HStack {
                        Text("Images delivered")
                        Spacer()
                        Text("\(detectionManager.imagesDelivered)")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Images Delivered
                    HStack {
                        Text("Delivery progress")
                        Spacer()
                        ProgressView(value: Double(detectionManager.imagesDelivered), total: max(1.0, Double(detectionManager.totalImages)))
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 100)
                    }
                    
                    Divider()
                    
                    // Buttons
                    HStack(spacing: 20) {
                        Button(action: {
                            showingStopConfirmation = true
                        }) {
                            Text("Stop")
                        }
                        .buttonStyle(StopButtonStyle())
                        .disabled(!isDetecting)
                        .alert("Confirm Stop", isPresented: $showingStopConfirmation) {
                            Button("Stop", role: .destructive) {
                                isDetecting = false
                                detectionManager.stopDetection()
                                detectionManager.deliverFilesFromDocuments()
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Are you sure you want to stop? This will interrupt detection.")
                        }
                        
                        Button(action: {
                            if !isLocationAuthorized {
                                locationManager.requestAuthorization()
                            }
                            CameraManager.checkAndRequestCameraAccess { authorized in
                                isCameraAuthorized = authorized
                                if authorized {
                                    isDetecting = true
                                    detectionManager.startDetection()
                                } else {
                                    showCameraAccessDeniedAlert = true
                                }
                            }
                        }) {
                            Text("Detect")
                        }
                        .buttonStyle(DetectButtonStyle())
                        .disabled(isDetecting)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .onAppear {
            storageAvailable = getAvailableDiskSpace()
            detectionManager.deliverFilesFromDocuments()
            CameraManager.checkAndRequestCameraAccess { authorized in
                isCameraAuthorized = authorized
            }
        }
        .onReceive(storageTimer) { _ in
            storageAvailable = getAvailableDiskSpace()
        }
        .onReceive(deliverToAzureTimer) { _ in
            if !isDetecting {
                detectionManager.deliverFilesFromDocuments()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            detectContainers = UserDefaults.standard.bool(forKey: "detectContainers")
        }
        .alert("Credential Error", isPresented: $iotManager.showingCredentialAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(iotManager.credentialAlertMessage)
        }
        .fullScreenCover(isPresented: $showCameraView) {
            CameraViewContainer(isCameraPresented: $showCameraView)
        }
        .alert(isPresented: $showCameraAccessDeniedAlert) {
            CameraManager.showCameraAccessDeniedAlert()
        }
    }
}

struct DetectButtonStyle : ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(isEnabled
                        ? (configuration.isPressed ? Color.green.opacity(0.7) : Color.green.opacity(0.9))
                        : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

struct StopButtonStyle : ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(isEnabled
                        ? (configuration.isPressed ? Color.red.opacity(0.7) : Color.red.opacity(0.9))
                        : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(10)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
