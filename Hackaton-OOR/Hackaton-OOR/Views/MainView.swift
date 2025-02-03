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
    
    // Timer to update storage every 30 seconds.
    let storageTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Placeholder for future progress component
            Rectangle()
                .frame(height: 50)
                .foregroundColor(.clear)
            
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
                        ProgressView(value: 1.0)
                            .progressViewStyle(LinearProgressViewStyle(tint: .green))
                            .frame(width: 100)
                    }
                    
                    Divider()
                    
                    // Images Sent to Azure
                    HStack {
                        Text("All images sent to Azure")
                        Spacer()
                        Text("No connection")
                            .foregroundColor(.red)
                    }
                    
                    Divider()
                                        
                    // Buttons
                    HStack(spacing: 20) {
                        Button(action: {}) {
                            Text("Stop")
                        }
                        .buttonStyle(StopButtonStyle())
                        .disabled(true)
                        
                        Button(action: {
                            // Implement detect action
                        }) {
                            Text("Detect")
                        }
                        .buttonStyle(DetectButtonStyle())
                        .disabled(!locationManager.gpsAvailable)
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
