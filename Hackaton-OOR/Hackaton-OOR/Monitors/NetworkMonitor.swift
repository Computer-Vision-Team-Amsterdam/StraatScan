//
//  NetworkMonitor.swift
//  Hackaton-OOR
//
//  Created by Sebastian Davrieux on 03/02/2025.
//
import CoreLocation
import Network

class NetworkMonitor: ObservableObject {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    @Published var internetAvailable: Bool = false
    
    init() {
        monitor.pathUpdateHandler = { path in
            DispatchQueue.main.async {
                self.internetAvailable = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
