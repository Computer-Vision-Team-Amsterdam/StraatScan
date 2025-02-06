import Foundation

// MARK: - Model Structures

struct FileUploadResponse: Codable {
    let correlationId: String
    let hostName: String
    let containerName: String
    let blobName: String
    let sasToken: String
}

struct FileUploadNotification: Codable {
    let correlationId: String
    let isSuccess: Bool
    let statusCode: Int
    let statusDescription: String
}

// MARK: - Azure IoT Data Uploader

class AzureIoTDataUploader {
    
    private let host: String         // e.g., "your-iothub.azure-devices.net"
    private let deviceId: String     // e.g., "iPad"
    private let sasToken: String     // Your Shared Access Signature for the device
    private let apiVersion: String = "2021-04-12"
    
    init(host: String, deviceId: String, sasToken: String) {
        self.host = host
        self.deviceId = deviceId
        self.sasToken = sasToken
    }
    
    func uploadData(_ data: Data, blobName: String, completion: @escaping (Error?) -> Void) {
        // Step 1: Request upload info from IoT Hub.
        requestFileUpload(blobName: blobName) { result in
            switch result {
            case .success(let uploadInfo):
                // Step 2: Upload data to Blob Storage.
                self.uploadToBlob(data: data, uploadResponse: uploadInfo) { result in
                    switch result {
                    case .success:
                        // Step 3: Notify IoT Hub that the upload succeeded.
                        self.notifyFileUpload(correlationId: uploadInfo.correlationId, isSuccess: true) { notifyError in
                            completion(notifyError)
                        }
                    case .failure(let uploadError):
                        // If the upload failed, notify IoT Hub accordingly.
                        self.notifyFileUpload(correlationId: uploadInfo.correlationId, isSuccess: false) { _ in
                            completion(uploadError)
                        }
                    }
                }
            case .failure(let error):
                completion(error)
            }
        }
    }
    
    private func requestFileUpload(blobName: String,
                                   completion: @escaping (Result<FileUploadResponse, Error>) -> Void) {
        guard let url = URL(string: "https://\(host)/devices/\(deviceId)/files?api-version=\(apiVersion)") else {
            completion(.failure(NSError(domain: "AzureIoTDataUploader",
                                        code: 0,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid URL for file upload request."])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(sasToken, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload = ["blobName": blobName]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(.failure(NSError(domain: "AzureIoTDataUploader",
                                            code: statusCode,
                                            userInfo: [NSLocalizedDescriptionKey: "File upload request failed with status code \(statusCode)."])))
                return
            }
            
            // Continue with JSON decoding…
            do {
                let decoder = JSONDecoder()
                let uploadResponse = try decoder.decode(FileUploadResponse.self, from: data!)
                completion(.success(uploadResponse))
            } catch {
                completion(.failure(error))
                print(error)
            }
        }.resume()

    }
    
    private func uploadToBlob(data: Data,
                              uploadResponse: FileUploadResponse,
                              completion: @escaping (Result<Void, Error>) -> Void) {
        let blobUrlString = "https://\(uploadResponse.hostName)/\(uploadResponse.containerName)/\(uploadResponse.blobName)\(uploadResponse.sasToken)"
        guard let url = URL(string: blobUrlString) else {
            completion(.failure(NSError(domain: "AzureIoTDataUploader",
                                        code: 0,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid blob URL."])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        
        URLSession.shared.uploadTask(with: request, from: data) { responseData, response, error in
            if let error = error {
                print("Upload task error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                let err = NSError(domain: "AzureIoTDataUploader",
                                  code: statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "Blob upload failed with status code \(statusCode)."])
                print("Blob upload failed: \(err.localizedDescription)")
                completion(.failure(err))
                return
            }
            completion(.success(()))
        }.resume()

    }
    
    private func notifyFileUpload(correlationId: String,
                                  isSuccess: Bool,
                                  completion: @escaping (Error?) -> Void) {
        guard let url = URL(string: "https://\(host)/devices/\(deviceId)/files/notifications?api-version=\(apiVersion)") else {
            completion(NSError(domain: "AzureIoTDataUploader",
                               code: 0,
                               userInfo: [NSLocalizedDescriptionKey: "Invalid URL for file upload notification."]))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(sasToken, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "correlationId": correlationId,
            "isSuccess": isSuccess,
            "statusCode": isSuccess ? 200 : 500,
            "statusDescription": isSuccess ? "Success" : "Failure"
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(error)
            return
        }
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                completion(error)
                return
            }
            guard let httpResp = response as? HTTPURLResponse,
                  (200...299).contains(httpResp.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                completion(NSError(domain: "AzureIoTDataUploader",
                                   code: statusCode,
                                   userInfo: [NSLocalizedDescriptionKey: "Notification failed with status code \(statusCode)."]))
                return
            }
            completion(nil)
        }.resume()
    }
}
