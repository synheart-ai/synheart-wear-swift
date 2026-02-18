# Garmin Health SDK Integration Guide (Swift/iOS)

This guide explains how to integrate the Garmin Health SDK with Synheart Wear for real-time health data streaming from Garmin wearables on iOS.

## Prerequisites

### 1. Obtain a Garmin Health SDK License

The Garmin Health SDK is **not open source** and requires a commercial license from Garmin.

1. Contact Garmin Health to discuss licensing: https://developer.garmin.com/health-api/overview/
2. You will receive:
   - SDK license key(s) tied to your app's bundle ID
   - Access to the private GitHub repositories containing the SDK

### 2. GitHub Access Token

The iOS SDK is distributed via private GitHub repositories. You need a Personal Access Token with the following permissions:

- `read:packages`
- `repo`

Create one at: https://github.com/settings/tokens

---

## iOS Setup

### Option 1: Swift Package Manager (Recommended)

1. In Xcode, go to **File > Add Package Dependencies**
2. Enter: `https://github.com/garmin-health-sdk/ios-companion`
3. Authenticate with your GitHub credentials
4. Select the version and add the package to your target

### Option 2: Manual XCFramework Integration

1. **Download the SDK**

   Go to: https://github.com/garmin-health-sdk/ios-companion/releases

   Download the `Companion.xcframework-X.X.X.zip` file from the latest release.

2. **Extract and Copy**

   ```bash
   # Extract the downloaded file
   unzip Companion.xcframework-X.X.X.zip

   # Create the Frameworks directory
   mkdir -p Frameworks

   # Copy the XCFramework
   cp -R Companion.xcframework Frameworks/
   ```

3. **Link in Xcode**

   - Open your project in Xcode
   - Select your target > **General** > **Frameworks, Libraries, and Embedded Content**
   - Click **+** and add `Companion.xcframework` from `Frameworks/`
   - Set **Embed** to "Embed & Sign"

4. **If using CocoaPods**, update the podspec:

   ```ruby
   s.vendored_frameworks = 'Frameworks/Companion.xcframework'
   s.pod_target_xcconfig = {
     'DEFINES_MODULE' => 'YES',
     'OTHER_LDFLAGS' => '-weak_framework Companion',
   }
   ```

   Then run:

   ```bash
   pod deintegrate && pod install
   ```

---

## Building with Garmin RTS Support

The real-time streaming (RTS) code lives in a private companion repo and is linked at build time via `make`:

```bash
# Auto-detect companion access and build accordingly
make build

# Or explicitly:
make build-with-garmin     # requires companion repo access
make build-without-garmin  # stub-only (scanning/pairing throw SynheartWearError)
make check-garmin          # verify you have access
make clean-garmin          # remove .garmin/ and symlinks
```

Without the companion, `GarminHealth` methods like `pairDevice(_:)` and `startStreaming()` throw `SynheartWearError`. Cloud-based Garmin data via `GarminProvider` (OAuth + webhooks) works regardless.

---

## Swift Usage

Once the native SDK is configured and built with companion support, use `GarminHealth`:

```swift
import SynheartWear

// Create and initialize GarminHealth
let garmin = GarminHealth(licenseKey: "YOUR_LICENSE_KEY")
try await garmin.initialize()

// Scan for devices
try await garmin.startScanning(timeoutSeconds: 30)
for await devices in garmin.scannedDevicesStream() {
    for device in devices {
        print("Found: \(device.name) (\(device.identifier))")
    }
}

// Pair a device
let paired = try await garmin.pairDevice(scannedDevice)

// Monitor connection state
for await event in garmin.connectionStateStream() {
    print("Connection: \(event.state)")
}

// Start real-time streaming
try await garmin.startStreaming(device: paired)
for await metrics in garmin.realTimeStream() {
    print("Heart Rate: \(metrics.getMetric(.hr))")
}

// Read historical metrics
let metrics = try await garmin.readMetrics(
    startTime: startDate,
    endTime: endDate
)

// Wire into SynheartWear via config
let synheart = SynheartWear(
    config: SynheartWearConfig.withAdapters([.garmin]),
    garminHealth: garmin
)

// Clean up
garmin.dispose()
```

> **Note:** All `GarminHealth` methods use Swift async/await. Streams are exposed as `AsyncStream` types for use with `for await` loops.

---

## SDK Variant Comparison

| Feature | Companion SDK | Standard SDK |
|---------|--------------|--------------|
| Garmin Connect Mobile Required | No | Yes |
| Direct Bluetooth Connection | Yes | No |
| Works Offline | Yes | Yes |
| Real-time Data | Yes | Yes |
| Activity Sync | Via SDK | Via GCM |
| Platform | iOS, Android | Android only |

**Choose Companion SDK** if:
- Your users may not have Garmin Connect Mobile installed
- You need direct Bluetooth communication
- You're targeting iOS

**Choose Standard SDK** if:
- Your users will have Garmin Connect Mobile
- You want to leverage GCM's existing device connection

---

## Troubleshooting

### "No such module 'Companion'" Error

The XCFramework is not properly linked. Verify:

1. `Companion.xcframework` exists in `Frameworks/`
2. It is added to your target under **Frameworks, Libraries, and Embedded Content**
3. If using CocoaPods, run `pod deintegrate && pod install`

### "SDK not available" Error

This means the SDK binary is not linked. Verify:

1. The XCFramework is added via SPM (Option 1) or manually (Option 2)
2. You've done a clean build (**Product > Clean Build Folder**)

### "License invalid" Error

- Ensure your license key matches your app's bundle ID
- Contact Garmin support if the issue persists

### Bluetooth Permission Errors

Add to your `Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Required for Garmin device connection</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Required for Garmin device connection</string>
```

### Build Errors

**"Garmin Health SDK native binary not linked"**:
- The stub is active instead of the real implementation
- Run `make build-with-garmin` to link the companion code

**Linker errors with Companion framework**:
- Ensure the framework is set to "Embed & Sign" in Xcode
- Try `OTHER_LDFLAGS = -weak_framework Companion` in build settings

---

## Support

- **Garmin SDK Issues**: Contact Garmin Health SDK Support
- **SDK Issues**: https://github.com/synheart-ai/synheart-wear-swift/issues
- **SDK Documentation**: Available in the SDK release packages
