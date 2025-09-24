# StraatScan: Object Detection iOS App

## Overview

This iOS application is designed to perform real-time object detection using the device's camera. It processes the captured video frames, identifies relevant objects using a CoreML model (YOLOv11), blurs potentially sensitive areas (like people or license plates if detected), draws bounding boxes around containers, and uploads the processed image along with metadata (including GPS coordinates) to Azure IoT Hub for further analysis or monitoring.

## Requirements

* Xcode 15 or later
* iOS 17.0 or later
* Azure CLI
* An Azure IoT Hub instance with a registered device.

## Setup Instructions

Follow these steps to set up the project for development:

### **Clone the Repository:**
```bash
git clone git@github.com:Computer-Vision-Team-Amsterdam/StraatScan.git
cd StraatScan
```

### **Secrets Configuration (`Secrets.xcconfig`)**

This project uses `.xcconfig` files to manage build-time secrets like the Azure IoT Hub Device ID and SAS Token, keeping them out of source control. You need to create a `Secrets.xcconfig` file.

1.  **Create the File:** In the source directory of the project (`StraatScan`, where the `Info.plist` file is), create a new file named `Secrets.xcconfig`. See `Secrets.xconfig.example` for an example.

1.  **Get Azure Credentials:**
    * **Device ID (`DEVICE_ID`):** Find the ID of the registered device within your Azure IoT Hub instance in the Azure Portal.
    * **Device Connection String:** Navigate to your IoT Hub in the Azure Portal, go to "Devices", select your target device, and find its "Primary Connection String" (or Secondary). You'll need this to generate the SAS token. **Do not put the connection string itself in the secrets file.**
    * **Generate SAS Token (`DEVICE_SAS_TOKEN`):**
      1.  Open your terminal or command prompt.
      1.  Make sure you have Azure CLI installed and are logged in (`az login`).
      1.  Run the following command, replacing `<Your_Device_Connection_String>` with the actual connection string copied from the Azure Portal:
          ```bash
          az iot hub generate-sas-token --connection-string '<Your_Device_Connection_String>'
          ```
      1.  This command will output a JSON object containing the SAS token (usually under the `sas` key). Copy the **full SAS token value** (it's typically quite long).
      1.  **Note**: By default, this token will expire after 1 hour. You can increase the validity using `--duration <seconds>`, e.g., `--duration 172800` for 48 hours (this is the maximum allowed). Be mindful of security implications for long-lived tokens.

1. **Populate `Secrets.xcconfig`:** Add the `DEVICE_ID` and `DEVICE_SAS_TOKEN` keys with the values obtained above:
   ```xcconfig
   // Secrets.xcconfig
   
   DEVICE_ID = Your_Device_ID_Here
   DEVICE_SAS_TOKEN = Your_Generated_SAS_Token_Here
   ```

*(Project Configuration Note: The project should already be configured to use `Debug.xcconfig` and `Release.xcconfig` (defined inside the `project.pbxproj`), which in turn `#include "Secrets.xcconfig"` to load these values at build time and inject them into the `Info.plist`.)*

### **Build & Run:**
* Open the `.xcodeproj` file in Xcode.
* Select your target device or simulator (e.g. iOS 18.6).
* Build and run the application (`Cmd + R`).

On the first launch after installing, the application should read the `DEVICE_ID` and `DEVICE_SAS_TOKEN` from the build configuration (via `Info.plist`), save them securely to the Keychain, and then use them for communication with Azure IoT Hub.

## **Distribution via TestFlight:**
* In Xcode, go to the `Product` menu and select `Archive`.
* Once the archive is built, select `Distribute` and choose `TestFlight`.
* Go to [App Store Connect](https://appstoreconnect.apple.com/), and navigate to the StraatScan app. Under `TestFlight`, find the latest release and add the `CVT` team as tester.
* The new version will now be available to install on the iPhone.
