import SwiftUI

struct MainView: View {
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
                Text("OFF")
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // GPS Accuracy
            HStack {
                Text("GPS accuracy (m)")
                Spacer()
                Text("OFF")
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // Internet Connection
            HStack {
                Text("Internet connection")
                Spacer()
                Text("OFF")
                    .foregroundColor(.red)
            }
            
            Divider()
            
            // Storage Available
            HStack {
                Text("Storage available")
                Spacer()
                Text("128GB")
                    .foregroundColor(.green)
            }
            
            Divider()
            Spacer()
            
            ZStack(alignment: .bottom){
                VStack(alignment: .leading, spacing: 20) {
                    // Recorded Hours
                    HStack {
                        Text("Recorded hours")
                        Spacer()
                        Text("0:00")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Total Images
                    HStack {
                        Text("Total images")
                        Spacer()
                        Text("0")
                            .foregroundColor(.gray)
                    }
                    
                    Divider()
                    
                    // Objects Detected
                    HStack {
                        Text("Objects detected")
                        Spacer()
                        Text("0")
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
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .disabled(true)
                        
                        Button(action: {}) {
                            Text("Detect")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.2))
                                .cornerRadius(10)
                        }
                        .disabled(true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
