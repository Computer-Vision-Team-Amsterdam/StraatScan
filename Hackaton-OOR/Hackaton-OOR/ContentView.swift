//
//  ContentView.swift
//  Hackaton-OOR
//
//  Created by Sebastian Davrieux on 31/01/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image("logo_gemeente")
                .resizable()
                .aspectRatio(UIImage(named: "logo_gemeente")!.size, contentMode: .fit)
                .padding(.vertical, 50.0)
                
            Text("Hackaton-OOR!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
