import Foundation
import SwiftUI

struct LocationTestView: View {
    @StateObject private var locationManager = LocationManager()
    
    var body: some View {
        VStack {
            Image("logo_gemeente")
                .resizable()
                .aspectRatio(UIImage(named: "logo_gemeente")!.size, contentMode: .fit)
                .padding(.vertical, 50.0)
                
            Text("StraatScan!\n")
            
            if let coordinate = locationManager.lastKnownLocation {
                Text("GPS: \(String(format: "%f", coordinate.latitude)), \(String(format: "%f", coordinate.longitude))")
            } else {
                Text("Unknown Location")
            }
            
            if let accuracy = locationManager.lastAccuracy {
                Text("Accuracy: \(String(format: "%.1f", accuracy)) m")
            } else {
                Text("Unknown Accuracy")
            }
            
            if let heading = locationManager.lastHeading {
                Text("Heading: \(String(format: "%.1f", heading)) deg")
            } else {
                Text("Unknown Heading")
            }
            
            if let timestamp = locationManager.lastTimestamp {
                Text("Timestamp: \(timestamp)")
            } else {
                Text("Unknown Time")
            }
        }
        .padding()
    }
}

#Preview {
    LocationTestView()
}
