import Foundation
import CryptoKit

// Define a type alias for the completion handler
typealias JSONCompletionHandler = (Result<[String: String], Error>) -> Void

func createFileUploadSASURI(token: String, resourceURI: String, fileName: String, completion: @escaping JSONCompletionHandler) {
    let json: [String: String] = ["blobName": fileName]
    let jsonData = try? JSONSerialization.data(withJSONObject: json)
    
    let url = URL(string: "https://\(resourceURI)/files?api-version=2021-04-12")!
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue(token, forHTTPHeaderField: "Authorization")
    request.httpMethod = "POST"
    request.httpBody = jsonData
    
    // Create a URLSession data task to perform the POST request
    let task = URLSession.shared.dataTask(with: request) { data, response, error in
        // Check for errors
        if let error = error {
            // Pass the error to the completion handler
            completion(.failure(error))
            return
        }
        
        // Check for valid response data
        guard let data = data else {
            let error = NSError(domain: "NoDataError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])
            completion(.failure(error))
            return
        }
        
        // Parse the JSON response
        do {
            if let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                // Pass the JSON response to the completion handler
                completion(.success(jsonResponse))
            } else {
                let error = NSError(domain: "InvalidJSONError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
                completion(.failure(error))
            }
        } catch let parsingError {
            // Pass the parsing error to the completion handler
            completion(.failure(parsingError))
        }
    }
    
    // Start the data task
    task.resume()
}

func uploadFileToAzureBlob(fileData: Data, sasURI: String, completion: @escaping (Bool, Error?) -> Void) {
    guard let url = URL(string: sasURI) else {
        let urlError = NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        completion(false, urlError)
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "PUT"
    // Specify the blob type (for block blobs).
    request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")

    let task = URLSession.shared.uploadTask(with: request, from: fileData) { data, response, error in
        // Debug prints.
        print("Response data: \(String(describing: data))")
        print("Response: \(String(describing: response))")
        print("Error: \(String(describing: error))")

        if let error = error {
            completion(false, error)
            return
        }

        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 {
            completion(true, nil)
        } else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let err = NSError(domain: "", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to upload file"])
            completion(false, err)
        }
    }

    task.resume()
}


/// Generates a SAS token for Azure (e.g. for IoT Hub or blob storage).
///
/// **Important:** Depending on the service you are targeting, the string-to-sign format may differ.
/// This version uses the format:
///     "<lowercased-resourceUri>\n<expiry>"
/// and then URL encodes both the resource URI (for the token’s `sr` field)
/// and the signature (for the `sig` field) using the URL query allowed character set.
///
/// - Parameters:
///   - resourceUri: The resource URI (for example, "your-iothub.azure-devices.net/devices/your-device").
///                (If using for blob storage, this should be the URL path of the blob.)
///   - key: The Base64-encoded key used to sign the string.
///   - expiryInSeconds: The lifetime of the token in seconds from now.
/// - Returns: A SAS token string, or nil if an error occurs.
func generateSasToken(resourceUri: String, key: String, expiryInSeconds: Int) -> String? {
    // Calculate expiry time (in seconds since 1970)
    let expiry = Int(Date().timeIntervalSince1970) + expiryInSeconds
    let expiryString = "\(expiry)"

    // For signing, Azure expects the resource URI in a canonical form.
    // Often this means lowercasing it.
    let canonicalResource = resourceUri.lowercased()

    // The string-to-sign is: "<canonicalResource>\n<expiry>"
    let stringToSign = "\(canonicalResource)\n\(expiryString)"
    guard let stringToSignData = stringToSign.data(using: .utf8) else {
        print("Failed to convert string to sign to data")
        return nil
    }

    // Decode the Base64-encoded key.
    guard let keyData = Data(base64Encoded: key) else {
        print("Failed to decode key from Base64")
        return nil
    }
    let symmetricKey = SymmetricKey(data: keyData)

    // Compute the HMAC-SHA256 hash.
    let signature = HMAC<SHA256>.authenticationCode(for: stringToSignData, using: symmetricKey)
    let signatureData = Data(signature)

    // Base64 encode the signature.
    let base64Signature = signatureData.base64EncodedString()

    // URL encode the signature using the URL query allowed set.
    guard let urlEncodedSignature = base64Signature.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        print("Failed to percent encode signature")
        return nil
    }

    // For the token’s "sr" field, URL encode the resource URI.
    guard let urlEncodedResourceUri = resourceUri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
        print("Failed to percent encode resource URI")
        return nil
    }

    // Construct the token.
    let token = "SharedAccessSignature sr=\(urlEncodedResourceUri)&sig=\(urlEncodedSignature)&se=\(expiryString)&skn=device"
    return token
}
