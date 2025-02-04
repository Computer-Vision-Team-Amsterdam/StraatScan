//
//  FileManager.swift
//  Hackaton-OOR
//
//  Created by Daan Bloembergen on 04/02/2025.
//

import Foundation

func createFile(withText text: String, fileName: String) {
    // Get the URL for the app's Documents directory.
    guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        print("Documents directory not found!")
        return
    }

    // Create a file URL in the Documents directory.
    let fileURL = documentsDirectory.appendingPathComponent(fileName)

    // Convert the text to Data.
    guard let data = text.data(using: .utf8) else {
        print("Unable to convert text to data.")
        return
    }

    do {
        // Write the data to the file.
        try data.write(to: fileURL)
        print("File created successfully at: \(fileURL.path)")
    } catch {
        print("Error writing file: \(error)")
    }
}

// Example usage:
//createFile(withText: "Hello, Azure IoT!", fileName: "example.txt")

 
