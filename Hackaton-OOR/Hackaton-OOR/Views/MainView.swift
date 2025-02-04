import SwiftUI
import CoreLocation
import Network

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
    @State private var storageAvailable: Int = 0
    @State private var detectContainers: Bool = UserDefaults.standard.bool(forKey: "detectContainers")
    
    // States for bottom section (static/recording info)
    @State private var recordedHours: String = "0:00"
    @State private var totalImages: Int = 0
    @State private var objectsDetected: Int = 0
    
    // Detection-related states
    @State private var isDetecting: Bool = false
    @State private var imagesDelivered: Double = 0
    @State private var imagesToDeliver: Double = 10 // for simulation; replace with your actual value
    @State private var uploadInProgress: Bool = false
    @State private var showingStopConfirmation = false
    
    // Timer to update storage every 30 seconds.
    let storageTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    let detectionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect() // simulate progress every 1 sec

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isDetecting {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                            .scaleEffect(2.0) // Increase the size of the circular indicator.
                        Text("Detecting...")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
                }
            } else {
                // Placeholder to maintain layout when not detecting.
                Rectangle()
                    .frame(height: 90)
                    .foregroundColor(.clear)
            }
            
            // GPS Status
            HStack {
                Text("GPS")
                Spacer()
                Text(locationManager.gpsAvailable ? "ON" : "OFF")
                    .foregroundColor(locationManager.gpsAvailable ? .green : .red)
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
            Spacer()
            
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
                        Text(recordedHours)
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Total Images
                    HStack {
                        Text("Total images")
                        Spacer()
                        Text("\(totalImages)")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Objects Detected
                    HStack {
                        Text("Objects detected")
                        Spacer()
                        Text("\(objectsDetected)")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Images Delivered
                    HStack {
                        Text("Images delivered")
                        Spacer()
                        ProgressView(value: imagesDelivered, total: imagesToDeliver)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 100)
                    }
                    
                    Divider()
                    
                    // Images Sent to Azure
                    HStack {
                        Text(uploadInProgress ? "Upload in progress..." : "All images sent to Azure")
                        Spacer()
                        if uploadInProgress {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                        }
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
                                uploadInProgress = false
                                imagesDelivered = 0
                            }
                            Button("Cancel", role: .cancel) { }
                        } message: {
                            Text("Are you sure you want to stop? This will interrupt detection.")
                        }
                        
                        Button(action: {
                            isDetecting = true
                            uploadInProgress = true
                            imagesDelivered = 0
                            
                            let resourceURI = "iothub-oor-ont-weu-itr-01.azure-devices.net/devices/iPad"
                            let fileData = "Hello!!".data(using: .utf8)
                            let fileName = "hello.txt"
                            let containerName = "landingzone"
                            
//                            let sasToken = generateSasToken(resourceUri: resourceURI, key: "KEY", expiryInSeconds: 3600)
//                            print("SAS Token: \(sasToken ?? "No token available")")
                            let sasToken = "TOKEN"
                            
                            //NOTE: see https://learn.microsoft.com/en-us/azure/iot-hub/iot-hub-devguide-file-upload
                            createFileUploadSASURI(token: sasToken, resourceURI: resourceURI, fileName: fileName) { result in
                                switch result {
                                case .success(let jsonResponse):
                                    // Handle the JSON response
                                    print("JSON Response: \(jsonResponse)")
                                    let correlationId = jsonResponse["correlationId"]
                                    let sasURI = "https://\(jsonResponse["hostname"])/\(jsonResponse["containerName"])/\(jsonResponse["blobName"])\(jsonResponse["sasToken"])"
                                    print(sasURI)
                                    
                                    //TODO: not tested yet
                                    uploadFileToAzureBlob(fileData: fileData!, sasURI: sasURI) { success, error in
                                        if success {
                                            print("File uploaded successfully")
                                            //TODO: notify upload status
                                        } else {
                                            print("Failed to upload file: \(error?.localizedDescription ?? "Unknown error")")
                                        }
                                    }
                                case .failure(let error):
                                    // Handle the error
                                    print("Error: \(error.localizedDescription)")
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
            }
        }
        .padding()
        .onAppear {
            // Update storage available when the view appears.
            storageAvailable = getAvailableDiskSpace()
            
        }
        .onReceive(storageTimer) { _ in
            storageAvailable = getAvailableDiskSpace()
        }
        .onReceive(detectionTimer) { _ in
            if isDetecting {
                if imagesDelivered < imagesToDeliver {
                    imagesDelivered += 1
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            detectContainers = UserDefaults.standard.bool(forKey: "detectContainers")
            print("detectContainers updated: \(detectContainers)")
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
