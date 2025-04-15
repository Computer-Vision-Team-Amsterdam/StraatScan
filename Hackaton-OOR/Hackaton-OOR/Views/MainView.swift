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
    @StateObject private var locationManager = LocationManager()
    @StateObject private var networkMonitor = NetworkMonitor()
    @ObservedObject private var detectionManager = DetectionManager()
    @State private var storageAvailable: Int = 0
    @State private var detectContainers: Bool = UserDefaults.standard.bool(forKey: "detectContainers")
    
    // States for bottom section (static/recording info)
    @State private var recordedHours: String = "0:00"
    @State private var totalImages: Int = 0
    
    // Detection-related states
    @State private var isDetecting: Bool = false
    @State private var imagesDelivered: Double = 0
    @State private var imagesToDeliver: Double = 10 // for simulation; replace with your actual value
    @State private var showingStopConfirmation = false
    @State private var showCameraView: Bool = false
    @State private var isCameraAuthorized: Bool = false
    @State private var showCameraAccessDeniedAlert: Bool = false
    
    let storageTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect()
    let deliverToAzureTimer = Timer.publish(every: 120, on: .main, in: .common).autoconnect() // simulate progress every 1 sec
    var formattedTime: String {
        let totalSeconds = detectionManager.minutesRunning * 60
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .positional    // This produces "HH:mm:ss"
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: TimeInterval(totalSeconds)) ?? "00:00"
    }
    // A helper function to create a UI row entry with a label and a value.
    private func infoRow(label: String, value: String, valueColor: Color = .gray) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Portrait mode
            if geometry.size.width <= geometry.size.height {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        // Reserve the layout with a transparent placeholder.
                        Color.clear.frame(height: 30)
                        
                        if isDetecting {
                            HStack {
                                Spacer()
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                                        .scaleEffect(1.5)
                                    Text("Detecting...")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                        .multilineTextAlignment(.center)
                                }
                                Spacer()
                            }
                        }
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
                    
                    // GPS Status
                    infoRow(label: "GPS",
                            value: locationManager.gpsAvailable ? "ON" : "OFF",
                            valueColor: locationManager.gpsAvailable ? .green : .red)
                    
                    Divider()
                    
                    // GPS Accuracy
                    infoRow(label: "GPS accuracy (m)",
                            value: locationManager.lastAccuracy.map { String(format: "%.2f", $0) } ?? "N/A",
                            valueColor: locationManager.lastAccuracy != nil ? .green : .red)
                    
                    Divider()
                    
                    // Internet Connection
                    infoRow(label: "Internet connection",
                            value: networkMonitor.internetAvailable ? "ON" : "OFF",
                            valueColor: networkMonitor.internetAvailable ? .green : .red)
                    
                    Divider()
                    
                    // Storage Available
                    infoRow(label: "Storage available",
                            value: "\(storageAvailable)GB",
                            valueColor: .green)
                    
                    Divider()
                    
                    // Detect containers
                    infoRow(label: "Detect containers",
                            value: detectContainers ? "ON" : "OFF",
                            valueColor: detectContainers ? .green : .red)
                    
                    Divider()
                    
                    Spacer()
                    
                    // Recorded Hours
                    infoRow(label: "Recorded hours",
                            value: formattedTime)
                    
                    Divider()
                    
                    // Total Images
                    infoRow(label: "Total images",
                            value: "\(detectionManager.totalImages)")
                    
                    Divider()
                    
                    // Objects Detected
                    infoRow(label: "Objects detected",
                            value: "\(detectionManager.objectsDetected)")
                    
                    Divider()
                    
                    // Images Delivered
                    infoRow(label: "Images delivered",
                            value: "\(detectionManager.imagesDelivered)")
                    
                    Divider()
                    
                    // Images Delivered
                    HStack {
                        Text("Delivery progress")
                        Spacer()
                        ProgressView(value: Double(detectionManager.imagesDelivered),
                                     total: Double(detectionManager.totalImages))
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
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Are you sure you want to stop? This will interrupt detection.")
                        }
                        
                        Button(action: {
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
                        .disabled(isDetecting || !locationManager.gpsAvailable)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding()
                
            } else {
                // Landscape mode
                HStack(spacing: 20) {
                    // Left column
                    VStack(alignment: .leading, spacing: 16) {

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

                        infoRow(label: "GPS",
                                value: locationManager.gpsAvailable ? "ON" : "OFF",
                                valueColor: locationManager.gpsAvailable ? .green : .red)
                        
                        Divider()
                        
                        infoRow(label: "GPS accuracy (m)",
                                value: locationManager.lastAccuracy.map { String(format: "%.2f", $0) } ?? "N/A",
                                valueColor: locationManager.lastAccuracy != nil ? .green : .red)
                        
                        Divider()
                        
                        infoRow(label: "Internet connection",
                                value: networkMonitor.internetAvailable ? "ON" : "OFF",
                                valueColor: networkMonitor.internetAvailable ? .green : .red)
                        
                        Divider()
                        
                        infoRow(label: "Storage available",
                                value: "\(storageAvailable)GB",
                                valueColor: .green)
                        
                        Divider()
                        
                        infoRow(label: "Detect containers",
                                value: detectContainers ? "ON" : "OFF",
                                valueColor: detectContainers ? .green : .red)
                        
                        HStack {
                            Spacer()
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
                                }
                                Button("Cancel", role: .cancel) { }
                            } message: {
                                Text("Are you sure you want to stop? This will interrupt detection.")
                            }
                        }
                    }
                    .padding()
                    
                    // Right column
                    VStack(alignment: .leading, spacing: 16) {
                        
                        infoRow(label: "Recorded hours",
                                value: formattedTime)
                        
                        Divider()
                        
                        infoRow(label: "Total images",
                                value: "\(detectionManager.totalImages)")
                        
                        Divider()
                        
                        infoRow(label: "Objects detected",
                                value: "\(detectionManager.objectsDetected)")
                        
                        Divider()
                        
                        infoRow(label: "Images delivered",
                                value: "\(detectionManager.imagesDelivered)")
                        
                        Divider()
                        
                        HStack {
                            Text("Delivery progress")
                            Spacer()
                            ProgressView(value: Double(detectionManager.imagesDelivered),
                                         total: Double(detectionManager.totalImages))
                                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                                .frame(width: 100)
                        }
                        
                        Divider()
                        
                        // Empty row to align infoRows across columns
                        infoRow(label: " ",
                                value: " ")
                        
                        Button(action: {
                            if !isDetecting {
                                CameraManager.checkAndRequestCameraAccess { authorized in
                                    isCameraAuthorized = authorized
                                    if authorized {
                                        DispatchQueue.main.async {
                                            isDetecting = true
                                            detectionManager.startDetection()
                                        }
                                    } else {
                                        showCameraAccessDeniedAlert = true
                                    }
                                }
                            }
                        }) {
                            if isDetecting {
                                HStack(spacing: 8) {
                                    Text("Detecting")
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.5)
                                }
                            } else {
                                Text("Detect")
                            }
                        }
                        .buttonStyle(DetectButtonStyle())
                        .disabled(isDetecting || !locationManager.gpsAvailable)
                    }
                }
                .padding()
            }
        }
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
            detectionManager.deliverFilesFromDocuments()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            detectContainers = UserDefaults.standard.bool(forKey: "detectContainers")
            print("detectContainers updated: \(detectContainers)")
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
