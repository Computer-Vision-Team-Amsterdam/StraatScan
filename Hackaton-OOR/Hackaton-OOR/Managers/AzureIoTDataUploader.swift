import Foundation
import Logging // For logging

// MARK: - Custom Error Enum
enum AzureIoTError: LocalizedError {
    case missingCredentials(String)
    case invalidURL(String)
    case requestEncodingError(Error)
    case networkError(Error)
    case invalidHTTPResponse
    case httpError(statusCode: Int, message: String)
    case responseDecodingError(Error, Data?)
    case blobUploadFailed(Error?)
    case notificationFailed(Error?)

    var errorDescription: String? {
        switch self {
        case .missingCredentials(let credentialName):
            return "Azure IoT Error: Missing required credential - \(credentialName)."
        case .invalidURL(let urlDescription):
            return "Azure IoT Error: Could not construct a valid URL for \(urlDescription)."
        case .requestEncodingError(let underlyingError):
            return "Azure IoT Error: Failed to encode request body - \(underlyingError.localizedDescription)."
        case .networkError(let underlyingError):
            return "Azure IoT Error: Network request failed - \(underlyingError.localizedDescription)."
        case .invalidHTTPResponse:
            return "Azure IoT Error: Received an invalid HTTP response."
        case .httpError(let statusCode, let message):
            return "Azure IoT Error: Request failed with HTTP status \(statusCode). \(message)"
        case .responseDecodingError(let underlyingError, _):
            return "Azure IoT Error: Failed to decode response - \(underlyingError.localizedDescription)."
        case .blobUploadFailed(let underlyingError):
            return "Azure IoT Error: Failed to upload data to blob storage. \(underlyingError?.localizedDescription ?? "")"
        case .notificationFailed(let underlyingError):
            return "Azure IoT Error: Failed to send upload notification to IoT Hub. \(underlyingError?.localizedDescription ?? "")"
        }
    }
}

// MARK: - Model Structures

/// Represents the response from the Azure IoT Hub when requesting file upload information.
struct FileUploadResponse: Codable {
    let correlationId: String
    let hostName: String
    let containerName: String
    let blobName: String
    let sasToken: String
}

/// Represents the notification payload sent to Azure IoT Hub after a file upload.
struct FileUploadNotification: Codable {
    let correlationId: String
    let isSuccess: Bool
    let statusCode: Int
    let statusDescription: String
}

// MARK: - Azure IoT Data Uploader

/// Handles uploading data to Azure IoT Hub using the file upload mechanism.
class AzureIoTDataUploader {
    private let host: String
    private let iotDeviceManager: IoTDeviceManager
    private let apiVersion: String = "2021-04-12"
    private let urlSession: URLSession
    private let logger: Logger

    /// Initializes the uploader with the Azure IoT Hub host and the device manager.
    /// - Parameters:
    ///   - host: The Azure IoT Hub host name (e.g., "your-hub.azure-devices.net").
    ///   - iotDeviceManager: An instance of the `IoTDeviceManager` holding credentials.
    ///   - urlSession: The URLSession instance to use for network requests (defaults to .shared).
    init(host: String, iotDeviceManager: IoTDeviceManager, urlSession: URLSession = .shared) {
        self.host = host
        self.iotDeviceManager = iotDeviceManager
        self.urlSession = urlSession
        self.logger = Logger(label: "nl.amsterdam.cvt.hackaton-ios.AzureIoTDataUploader")
        logger.info("AzureIoTDataUploader initialized for host: \(host)")
    }

    /// Uploads data to Azure IoT Hub using the file upload flow asynchronously.
    /// - Parameters:
    ///   - data: The data to upload.
    ///   - blobName: The desired name for the blob in Azure Storage.
    /// - Throws: An `AzureIoTError` if any part of the process fails.
    func uploadData(_ data: Data, blobName: String) async throws {
        logger.info("Starting data upload process for blob: \(blobName)")

        guard let deviceId = await iotDeviceManager.deviceId else {
            logger.error("Upload failed: Device ID is missing.")
            throw AzureIoTError.missingCredentials("Device ID")
        }
        guard let sasToken = await iotDeviceManager.deviceSasToken else {
            logger.error("Upload failed: SAS Token is missing.")
            throw AzureIoTError.missingCredentials("SAS Token")
        }

        var uploadInfo: FileUploadResponse
        do {
            logger.debug("Requesting file upload parameters...")
            uploadInfo = try await requestFileUpload(deviceId: deviceId, sasToken: sasToken, blobName: blobName)
            logger.info("Received file upload parameters. Correlation ID: \(uploadInfo.correlationId)")
        } catch let error as AzureIoTError {
            logger.error("Failed to request file upload parameters: \(error.localizedDescription)")
            throw error
        } catch {
            logger.error("An unexpected error occurred requesting file upload parameters: \(error.localizedDescription)")
            throw AzureIoTError.networkError(error)
        }

        do {
            logger.debug("Uploading data to blob storage...")
            try await uploadToBlob(data: data, uploadResponse: uploadInfo)
            logger.info("Successfully uploaded data to blob storage.")
        } catch let error as AzureIoTError {
            logger.error("Failed to upload data to blob storage: \(error.localizedDescription)")
            await notifyFileUploadAndLog(correlationId: uploadInfo.correlationId, deviceId: deviceId, sasToken: sasToken, isSuccess: false)
            throw AzureIoTError.blobUploadFailed(error)
        } catch {
             logger.error("An unexpected error occurred during blob upload: \(error.localizedDescription)")
             await notifyFileUploadAndLog(correlationId: uploadInfo.correlationId, deviceId: deviceId, sasToken: sasToken, isSuccess: false)
             throw AzureIoTError.blobUploadFailed(error)
        }

        logger.debug("Notifying IoT Hub of successful upload...")
        await notifyFileUploadAndLog(correlationId: uploadInfo.correlationId, deviceId: deviceId, sasToken: sasToken, isSuccess: true)
        logger.info("Upload process completed successfully for blob: \(blobName)")
    }

    // MARK: - Private Async Helper Functions

    /// Requests file upload information from Azure IoT Hub.
    private func requestFileUpload(deviceId: String, sasToken: String, blobName: String) async throws -> FileUploadResponse {
        logger.trace("Constructing URL for file upload request...")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/devices/\(deviceId)/files"
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]

        guard let url = components.url else {
            throw AzureIoTError.invalidURL("file upload request")
        }
        logger.trace("URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(sasToken, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let payload = ["blobName": blobName]
        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw AzureIoTError.requestEncodingError(error)
        }
        
        logger.trace("Sending file upload request...")
        let (data, _) = try await performRequest(request: request, description: "file upload request")

        do {
            let decoder = JSONDecoder()
            let uploadResponse = try decoder.decode(FileUploadResponse.self, from: data)
            return uploadResponse
        } catch {
            logger.error("Failed to decode FileUploadResponse. Data: \(String(data: data, encoding: .utf8) ?? "non-utf8 data")")
            throw AzureIoTError.responseDecodingError(error, data)
        }
    }

    /// Uploads data to the Azure Storage blob using the provided upload response.
    private func uploadToBlob(data: Data, uploadResponse: FileUploadResponse) async throws {
        logger.trace("Constructing URL for blob upload...")
        let blobUrlString = "https://\(uploadResponse.hostName)/\(uploadResponse.containerName)/\(uploadResponse.blobName)\(uploadResponse.sasToken)"

        guard let url = URL(string: blobUrlString) else {
            throw AzureIoTError.invalidURL("blob upload target")
        }
         logger.trace("Blob URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.addValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        request.addValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.addValue("\(data.count)", forHTTPHeaderField: "Content-Length")

        logger.trace("Uploading data to blob...")
        let (_, response) = try await urlSession.upload(for: request, from: data)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AzureIoTError.invalidHTTPResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
             logger.error("Blob upload HTTP error. Status: \(httpResponse.statusCode)")
            throw AzureIoTError.httpError(statusCode: httpResponse.statusCode, message: "Blob upload failed.")
        }
        logger.trace("Blob upload successful (HTTP \(httpResponse.statusCode)).")
    }

    /// Notifies Azure IoT Hub of the result of a file upload.
    private func notifyFileUpload(correlationId: String, deviceId: String, sasToken: String, isSuccess: Bool, statusCode: Int, statusDescription: String) async throws {
        logger.trace("Constructing URL for file upload notification...")
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/devices/\(deviceId)/files/notifications"
        components.queryItems = [URLQueryItem(name: "api-version", value: apiVersion)]

        guard let url = components.url else {
            throw AzureIoTError.invalidURL("file upload notification")
        }
        logger.trace("Notification URL: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue(sasToken, forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        struct NotificationPayload: Encodable {
             let correlationId: String
             let isSuccess: Bool
             let statusCode: Int
             let statusDescription: String
        }
        let payload = NotificationPayload(
            correlationId: correlationId,
            isSuccess: isSuccess,
            statusCode: statusCode,
            statusDescription: statusDescription
        )

        do {
            request.httpBody = try JSONEncoder().encode(payload)
        } catch {
            throw AzureIoTError.requestEncodingError(error)
        }

        logger.trace("Sending file upload notification...")
        let (_, _) = try await performRequest(request: request, description: "file upload notification")
        logger.trace("File upload notification sent successfully.")
    }

    /// Helper function to perform a URLRequest and handle common response/error checking.
    private func performRequest(request: URLRequest, description: String) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await urlSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                 logger.error("Invalid HTTP response received for \(description).")
                throw AzureIoTError.invalidHTTPResponse
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                 logger.error("\(description.capitalized) failed. Status: \(httpResponse.statusCode). Data: \(String(data: data, encoding: .utf8) ?? "non-utf8 data")")
                throw AzureIoTError.httpError(statusCode: httpResponse.statusCode, message: "\(description.capitalized) failed.")
            }

            return (data, httpResponse)
        } catch let error as AzureIoTError {
            throw error
        } catch {
             logger.error("Network error during \(description): \(error.localizedDescription)")
            throw AzureIoTError.networkError(error)
        }
    }
    
    /// Convenience wrapper for notifying IoT Hub that handles potential errors during notification itself.
    private func notifyFileUploadAndLog(correlationId: String, deviceId: String, sasToken: String, isSuccess: Bool) async {
         let statusCode = isSuccess ? 200 : 500
         let statusDescription = isSuccess ? "Success" : "Failure reported by client"
         do {
             try await notifyFileUpload(
                 correlationId: correlationId,
                 deviceId: deviceId,
                 sasToken: sasToken,
                 isSuccess: isSuccess,
                 statusCode: statusCode,
                 statusDescription: statusDescription
             )
         } catch {
             logger.error("Failed to send file upload notification to IoT Hub: \(error.localizedDescription)")
         }
     }
}
