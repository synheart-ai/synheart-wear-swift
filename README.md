# Synheart Wear - iOS SDK

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![iOS 13.0+](https://img.shields.io/badge/iOS-13.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![watchOS 6.0+](https://img.shields.io/badge/watchOS-6.0%2B-blue.svg)](https://developer.apple.com/watchos/)

**Unified wearable SDK for iOS** — Stream biometric data from Apple Watch, Fitbit, Garmin, Whoop, and other devices via HealthKit with a single standardized API.

## 🚀 Features

- **📱 HealthKit Integration**: Native iOS biometric data access from Apple Watch
- **⌚ Multi-Device Support**: Apple Watch, Fitbit, Garmin, Whoop (via HealthKit sync and cloud APIs)
- **☁️ Cloud Integration**: Direct API access to WHOOP via Wear Service
- **🔄 Real-Time Streaming**: Live HR and HRV data streams with Combine framework
- **📊 Unified Schema**: Consistent data format across all devices
- **🔒 Privacy-First**: Consent-based data access with encryption
- **💾 Local Storage**: Encrypted offline data persistence with Keychain
- **⚡ Swift Concurrency**: Modern async/await API
- **🔐 OAuth Support**: Secure OAuth 2.0 flow for cloud-based providers

## 📦 Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/synheart-ai/synheart-wear-ios.git", from: "0.1.0")
]
```

Or in Xcode:
1. File → Add Packages...
2. Enter: `https://github.com/synheart-ai/synheart-wear-ios.git`
3. Select version: `0.1.0` or later

### CocoaPods

Add to your `Podfile`:

```ruby
pod 'SynheartWear', '~> 0.1.0'
```

### Requirements

- **iOS**: 13.0+
- **watchOS**: 6.0+
- **macOS**: 13.0+ (Catalyst)
- **Swift**: 5.9+
- **Xcode**: 15.0+

## 🎯 Quick Start

### 1. Configure HealthKit Permissions

Add to your `Info.plist`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>We need access to your health data to provide personalized insights</string>
<key>NSHealthUpdateUsageDescription</key>
<string>We need to update your health data</string>
```

Add HealthKit capability in Xcode:
- Target → Signing & Capabilities → + Capability → HealthKit

### 2. Initialize the SDK

**For HealthKit only:**
```swift
import SynheartWear

let config = SynheartWearConfig(
    enabledAdapters: [.appleHealthKit],
    enableLocalCaching: true,
    enableEncryption: true,
    streamInterval: 3.0 // 3 seconds
)

let synheartWear = SynheartWear(config: config)
```

**For WHOOP integration:**
```swift
import SynheartWear

let config = SynheartWearConfig(
    enabledAdapters: [.appleHealthKit, .whoop],
    enableLocalCaching: true,
    enableEncryption: true,
    streamInterval: 3.0,
    baseUrl: URL(string: "https://synheart-wear-service-leatest.onrender.com")!, // Optional: defaults to production
    appId: "your-app-id", // Required for WHOOP
    redirectUri: "synheart://oauth/callback" // Optional: defaults to synheart://oauth/callback
)

let synheartWear = SynheartWear(config: config)
```

### 3. Request Permissions

```swift
Task {
    do {
        // Initialize SDK
        try await synheartWear.initialize()

        // Request permissions
        let permissions = try await synheartWear.requestPermissions([
            .heartRate,
            .hrv,
            .steps,
            .calories
        ])

        if permissions[.heartRate] == true {
            print("Heart rate permission granted")
        }
    } catch {
        print("Failed to initialize: \(error)")
    }
}
```

### 4. Read Metrics

**Unified metrics from all sources:**
```swift
Task {
    do {
        // Automatically merges data from HealthKit + WHOOP (if connected)
        let metrics = try await synheartWear.readMetrics()

        print("Heart Rate: \(metrics.getMetric(.hr) ?? 0) bpm")
        print("HRV RMSSD: \(metrics.getMetric(.hrvRmssd) ?? 0) ms")
        print("Steps: \(metrics.getMetric(.steps) ?? 0)")
        print("Recovery Score: \(metrics.metrics["recovery_score"] ?? 0)")
        print("Source: \(metrics.source)") // e.g., "merged_apple_healthkit" or "whoop_recovery"
    } catch {
        print("Failed to read metrics: \(error)")
    }
}
```

**Provider-specific metrics:**
```swift
Task {
    do {
        // Fetch historical data from WHOOP
        let whoopData = try await synheartWear.readMetricsFromProvider(
            .whoop,
            start: Date().addingTimeInterval(-7 * 24 * 60 * 60), // Last 7 days
            end: Date(),
            limit: 25
        )
        
        for record in whoopData {
            print("Recovery: \(record.metrics["recovery_score"] ?? 0)")
        }
    } catch {
        print("Failed to read WHOOP data: \(error)")
    }
}
```

### 5. Stream Real-Time Data

```swift
// Stream heart rate data every 3 seconds
let hrCancellable = synheartWear.streamHR(interval: 3.0)
    .sink { completion in
        if case .failure(let error) = completion {
            print("Stream error: \(error)")
        }
    } receiveValue: { metrics in
        if let hr = metrics.getMetric(.hr) {
            print("Live HR: \(hr) bpm")
        }
    }

// Stream HRV data in 5-second windows
let hrvCancellable = synheartWear.streamHRV(window: 5.0)
    .sink { completion in
        if case .failure(let error) = completion {
            print("Stream error: \(error)")
        }
    } receiveValue: { metrics in
        if let rmssd = metrics.getMetric(.hrvRmssd),
           let sdnn = metrics.getMetric(.hrvSdnn) {
            print("HRV - RMSSD: \(rmssd) ms, SDNN: \(sdnn) ms")
        }
    }
```

### 6. Using Async/Await with AsyncStream

```swift
Task {
    for await metrics in synheartWear.streamHRAsync(interval: 3.0) {
        if let hr = metrics.getMetric(.hr) {
            print("Live HR: \(hr) bpm")
        }
    }
}
```

## 📊 Data Schema

All wearable data follows the **Synheart Data Schema v1.0**:

```swift
struct WearMetrics {
    let timestamp: Date
    let deviceId: String
    let source: String
    let metrics: [String: Double]
    let meta: [String: String]
    let rrIntervals: [Double]?
}
```

Example JSON output:

```json
{
  "timestamp": "2025-10-20T18:30:00Z",
  "device_id": "applewatch_1234",
  "source": "apple_healthkit",
  "metrics": {
    "hr": 72,
    "hrv_rmssd": 45,
    "hrv_sdnn": 62,
    "steps": 1045,
    "calories": 120.4
  },
  "meta": {
    "battery": "0.82",
    "synced": "true"
  }
}
```

### WHOOP Data Structure

WHOOP API responses use a nested `score` object structure. The SDK automatically extracts metrics from these nested objects:

**Recovery Data Structure:**
```json
{
  "records": [
    {
      "created_at": "2025-11-30T00:59:59.767Z",
      "score": {
        "recovery_score": 5,
        "hrv_rmssd_milli": 37.586693,
        "resting_heart_rate": 69,
        "skin_temp_celsius": 35.199665,
        "spo2_percentage": 95.125
      }
    }
  ]
}
```

**Sleep Data Structure:**
```json
{
  "records": [
    {
      "start": "2025-11-29T20:13:12.680Z",
      "end": "2025-11-29T22:55:13.090Z",
      "score": {
        "sleep_efficiency_percentage": 97.15766,
        "sleep_performance_percentage": 11,
        "stage_summary": {
          "total_rem_sleep_time_milli": 1891120,
          "total_slow_wave_sleep_time_milli": 3032060,
          "total_light_sleep_time_milli": 4340230
        }
      }
    }
  ]
}
```

**Workout Data Structure:**
```json
{
  "records": [
    {
      "start": "2025-11-29T09:15:00.190Z",
      "end": "2025-11-29T11:26:59.210Z",
      "sport_name": "activity",
      "score": {
        "strain": 12.9671955,
        "average_heart_rate": 123,
        "max_heart_rate": 161,
        "kilojoule": 3752.2947
      }
    }
  ]
}
```

The SDK automatically handles:
- ✅ Nested `score` object extraction
- ✅ Unit conversions (milliseconds → seconds, kilojoules → calories)
- ✅ Deeply nested structures (e.g., `score.stage_summary.total_rem_sleep_time_milli`)
- ✅ Null value handling
- ✅ Multiple field name variations (snake_case, camelCase)

## 🔧 API Reference

### Core Methods

| Method | Description |
|--------|-------------|
| `initialize() async throws` | Request permissions & setup adapters |
| `readMetrics(isRealTime:) async throws -> WearMetrics` | Get current biometric snapshot |
| `streamHR(interval:) -> AnyPublisher<WearMetrics, Error>` | Stream real-time heart rate |
| `streamHRV(window:) -> AnyPublisher<WearMetrics, Error>` | Stream HRV in configurable windows |
| `streamHRAsync(interval:) -> AsyncStream<WearMetrics>` | Async stream of HR data |
| `getCachedSessions(...) async throws -> [WearMetrics]` | Retrieve cached data |
| `clearOldCache(maxAge:) async throws` | Clean up old cached data |

### Permission Management

```swift
// Request specific permissions
let permissions = try await synheartWear.requestPermissions([
    .heartRate,
    .hrv,
    .steps
])

// Check permission status
let status = synheartWear.getPermissionStatus()
print("HR permission: \(status[.heartRate] ?? false)")
```

### Local Storage

```swift
// Get cached sessions (last 7 days)
let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
let sessions = try await synheartWear.getCachedSessions(
    startDate: weekAgo,
    limit: 100
)

// Get cache statistics
let stats = try await synheartWear.getCacheStats()
print("Total sessions: \(stats["total_sessions"] ?? 0)")

// Clear old data (older than 30 days)
try await synheartWear.clearOldCache(maxAge: 30 * 24 * 60 * 60)
```

## ⌚ Supported Devices

| Device | Platform | Integration | Status |
|--------|----------|-------------|--------|
| Apple Watch | iOS | HealthKit | ✅ Ready |
| Fitbit | iOS | HealthKit Sync | ✅ Ready |
| Garmin | iOS | HealthKit Sync | 🔄 In Development |
| Whoop | iOS | REST API | ✅ Ready |
| Oura Ring | iOS | HealthKit Sync | ✅ Ready |

## 🔒 Privacy & Security

- **Consent-First Design**: Users must explicitly approve data access via HealthKit
- **Data Encryption**: AES-256-GCM encryption for local storage
- **Key Management**: Secure key storage in iOS Keychain
- **No Persistent IDs**: Anonymized UUIDs for experiments
- **Compliant**: Follows Synheart Data Governance Policy and Apple's HealthKit guidelines
- **Right to Forget**: Users can revoke permissions and delete encrypted data

## 🏗️ Architecture

```
┌─────────────────────────────┐
│   SynheartWear SDK          │
├─────────────────────────────┤
│   HealthKit Adapter         │
│   (Apple Watch, etc.)       │
├─────────────────────────────┤
│   Normalization Engine      │
│   (standard output schema)  │
├─────────────────────────────┤
│   Local Cache & Storage     │
│   (encrypted, Keychain)     │
└─────────────────────────────┘
```

## 🧪 Testing

```bash
# Run tests
swift test

# Run tests with coverage
swift test --enable-code-coverage

# Build for iOS
swift build -c release
```

## 🔗 WHOOP Integration

### Data Extraction & Metric Mapping

The SDK automatically extracts metrics from WHOOP API responses, which use a nested `score` object structure. Here's how metrics are mapped:

#### Recovery Metrics

| SDK Metric Name | WHOOP API Field | Unit Conversion | Description |
|----------------|-----------------|-----------------|-------------|
| `recovery_score` | `score.recovery_score` | None | Recovery score (0-100) |
| `hrv_rmssd` | `score.hrv_rmssd_milli` | milliseconds → seconds | HRV RMSSD value |
| `rhr` | `score.resting_heart_rate` | None | Resting heart rate (bpm) |
| `hr` | `score.resting_heart_rate` | None | Heart rate (same as RHR) |
| `skin_temperature` | `score.skin_temp_celsius` | None | Skin temperature (°C) |
| `spo2` | `score.spo2_percentage` | None | Blood oxygen saturation (%) |

**Example:**
```swift
let recovery = try await whoopProvider.fetchRecovery()
for record in recovery {
    print("Recovery Score: \(record.metrics["recovery_score"] ?? 0)")
    print("HRV RMSSD: \(record.metrics["hrv_rmssd"] ?? 0) seconds")
    print("RHR: \(record.metrics["rhr"] ?? 0) bpm")
}
```

#### Sleep Metrics

| SDK Metric Name | WHOOP API Field | Unit Conversion | Description |
|----------------|-----------------|-----------------|-------------|
| `sleep_duration_hours` | Calculated from `start`/`end` or `score.stage_summary.total_in_bed_time_milli` | milliseconds → hours | Total sleep duration |
| `sleep_efficiency` | `score.sleep_efficiency_percentage` | None | Sleep efficiency (%) |
| `sleep_performance` | `score.sleep_performance_percentage` | None | Sleep performance (%) |
| `sleep_consistency` | `score.sleep_consistency_percentage` | None | Sleep consistency (%) |
| `respiratory_rate` | `score.respiratory_rate` | None | Respiratory rate (breaths/min) |
| `rem_duration_minutes` | `score.stage_summary.total_rem_sleep_time_milli` | milliseconds → minutes | REM sleep duration |
| `deep_duration_minutes` | `score.stage_summary.total_slow_wave_sleep_time_milli` | milliseconds → minutes | Deep sleep duration |
| `light_duration_minutes` | `score.stage_summary.total_light_sleep_time_milli` | milliseconds → minutes | Light sleep duration |
| `awake_duration_minutes` | `score.stage_summary.total_awake_time_milli` | milliseconds → minutes | Awake time during sleep |

**Meta Fields:**
- `nap`: "true" or "false" (indicates if this was a nap)

**Example:**
```swift
let sleep = try await whoopProvider.fetchSleep()
for record in sleep {
    print("Duration: \(record.metrics["sleep_duration_hours"] ?? 0) hours")
    print("Efficiency: \(record.metrics["sleep_efficiency"] ?? 0)%")
    print("REM: \(record.metrics["rem_duration_minutes"] ?? 0) minutes")
    print("Deep: \(record.metrics["deep_duration_minutes"] ?? 0) minutes")
    print("Is Nap: \(record.meta["nap"] ?? "false")")
}
```

#### Workout Metrics

| SDK Metric Name | WHOOP API Field | Unit Conversion | Description |
|----------------|-----------------|-----------------|-------------|
| `strain` | `score.strain` | None | Workout strain score |
| `hr` | `score.average_heart_rate` | None | Average heart rate (bpm) |
| `max_hr` | `score.max_heart_rate` | None | Maximum heart rate (bpm) |
| `calories` | `score.kilojoule` | kilojoules → calories | Energy burned (kcal) |
| `workout_duration_minutes` | Calculated from `start`/`end` | seconds → minutes | Workout duration |
| `distance` | `score.distance_meter` | None | Distance (meters) |
| `altitude_gain` | `score.altitude_gain_meter` | None | Altitude gain (meters) |

**Meta Fields:**
- `workout_type`: Sport/activity name (e.g., "activity", "functional-fitness", "stairmaster")
- `sport_id`: WHOOP sport ID

**Example:**
```swift
let workouts = try await whoopProvider.fetchWorkouts()
for record in workouts {
    print("Strain: \(record.metrics["strain"] ?? 0)")
    print("Avg HR: \(record.metrics["hr"] ?? 0) bpm")
    print("Calories: \(record.metrics["calories"] ?? 0) kcal")
    print("Type: \(record.meta["workout_type"] ?? "unknown")")
}
```

#### Cycle Metrics

| SDK Metric Name | WHOOP API Field | Description |
|----------------|-----------------|-------------|
| `cycle_day` | `day` or `cycle_day` | Day of the cycle |
| `strain` | `strain` or `score.strain` | Daily strain score |
| `recovery_score` | `recovery` or `score.recovery_score` | Recovery score |

**Meta Fields:**
- `cycle_id`: WHOOP cycle ID

**Note:** Cycle endpoint structure may vary. The SDK handles common field variations.

### Setup Deep Link Handling

The WHOOP provider uses OAuth flow which requires deep link handling in your app.

#### 1. Configure URL Scheme in Info.plist

Add to your `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>synheart</string>
        </array>
        <key>CFBundleURLName</key>
        <string>com.yourcompany.synheart</string>
    </dict>
</array>
```

#### 2. Handle Deep Links

**For SwiftUI apps:**

```swift
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }
    
    func handleDeepLink(_ url: URL) {
        if url.scheme == "synheart" && url.host == "oauth" && url.path == "/callback" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
            let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
            
            if let code = code, let state = state {
                // Pass to your provider instance
                Task {
                    try? await whoopProvider.connectWithCode(
                        code: code,
                        state: state,
                        redirectUri: url.absoluteString
                    )
                }
            }
        }
    }
}
```

**For UIKit apps:**

```swift
// In your AppDelegate or SceneDelegate
func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    if url.scheme == "synheart" && url.host == "oauth" && url.path == "/callback" {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let code = components?.queryItems?.first(where: { $0.name == "code" })?.value
        let state = components?.queryItems?.first(where: { $0.name == "state" })?.value
        
        if let code = code, let state = state {
            Task {
                try? await whoopProvider.connectWithCode(
                    code: code,
                    state: state,
                    redirectUri: url.absoluteString
                )
            }
        }
        return true
    }
    return false
}
```

#### 3. Connect to WHOOP

**Option 1: Using SynheartWear SDK (Recommended)**
```swift
import SynheartWear

// Configure SDK with WHOOP support
let config = SynheartWearConfig(
    enabledAdapters: [.whoop],
    appId: "your-app-id",
    baseUrl: URL(string: "https://synheart-wear-service-leatest.onrender.com")!,
    redirectUri: "synheart://oauth/callback"
)

let synheartWear = SynheartWear(config: config)

// Get WHOOP provider
let whoopProvider = try synheartWear.getProvider(.whoop) as! WhoopProvider
```

**Option 2: Direct provider initialization**
```swift
import SynheartWear

// Initialize WHOOP provider directly
let whoopProvider = WhoopProvider(
    appId: "your-app-id",
    baseUrl: URL(string: "https://synheart-wear-service-leatest.onrender.com")!,
    redirectUri: "synheart://oauth/callback"
)

// Start OAuth flow
Task {
    do {
        try await whoopProvider.connect()
        // Browser will open for user authorization
        // After user approves, deep link will be handled automatically
    } catch {
        print("Connection failed: \(error)")
    }
}

// Check connection status
if whoopProvider.isConnected() {
    let userId = whoopProvider.getUserId()
    print("Connected as user: \(userId ?? "unknown")")
}

// Disconnect
Task {
    try? await whoopProvider.disconnect()
}

// Fetch data (with automatic token refresh)
Task {
    do {
        let recovery = try await whoopProvider.fetchRecovery(
            start: Date().addingTimeInterval(-7 * 24 * 60 * 60), // Last 7 days
            end: Date(),
            limit: 25
        )
        
        for record in recovery {
            print("Recovery: \(record.metrics)")
        }
    } catch SynheartWearError.tokenExpired {
        // Token expired and refresh failed - user needs to reconnect
        print("Session expired. Please reconnect your WHOOP account.")
        try? await whoopProvider.connect()
    } catch {
        print("Error fetching data: \(error)")
    }
}
```

### Token Refresh

The Wear Service automatically handles token refresh in the background. If a token expires:

1. **Automatic Refresh**: The Wear Service will attempt to refresh the token automatically
2. **If Refresh Fails**: The SDK will throw a `.tokenExpired` error
3. **Reconnection Required**: The user must call `connect()` again to re-authenticate

```swift
// Handle token expiration
do {
    let data = try await whoopProvider.fetchRecovery()
    // Use data...
} catch SynheartWearError.tokenExpired {
    // Token expired - reconnect
    try await whoopProvider.connect()
}
```

### Error Handling

The SDK provides comprehensive error handling for various scenarios:

```swift
do {
    let data = try await whoopProvider.fetchRecovery()
} catch SynheartWearError.notConnected {
    // User hasn't connected their account
    print("Please connect your WHOOP account first")
} catch SynheartWearError.tokenExpired {
    // Token expired - reconnect
    print("Session expired. Please reconnect.")
    try await whoopProvider.connect()
} catch SynheartWearError.authenticationFailed {
    // Authentication failed
    print("Authentication failed. Please try again.")
} catch SynheartWearError.rateLimitExceeded {
    // Too many requests
    print("Rate limit exceeded. Please try again later.")
} catch SynheartWearError.noConnection {
    // No internet connection
    print("No internet connection. Please check your network.")
} catch SynheartWearError.timeout {
    // Request timed out
    print("Request timed out. Please try again.")
} catch SynheartWearError.serverError(let code, let message) {
    // Server error
    print("Server error (\(code)): \(message ?? "Unknown error")")
} catch {
    // Other errors
    print("Error: \(error)")
}
```

**Graceful Disconnection**: The `disconnect()` method always clears local state, even if the server call fails (e.g., offline):

```swift
// Disconnect always succeeds locally, even if offline
try await whoopProvider.disconnect()
// Local state is cleared, connection is removed
```

### Custom Redirect URI

You can use a custom redirect URI:

```swift
let whoopProvider = WhoopProvider(
    appId: "your-app-id",
    redirectUri: "myapp://oauth/callback" // Custom deep link
)
```

**Important**: The redirect URI must:
- Match the scheme configured in your `Info.plist`
- Match the redirect URI configured in the Wear Service integration
- Be registered with WHOOP in their developer portal

## 📱 SwiftUI Example

```swift
import SwiftUI
import SynheartWear
import Combine

struct ContentView: View {
    @StateObject private var viewModel = HealthViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Heart Rate: \(viewModel.heartRate, specifier: "%.0f") bpm")
            Text("HRV RMSSD: \(viewModel.hrvRmssd, specifier: "%.0f") ms")
            Text("Steps: \(viewModel.steps, specifier: "%.0f")")

            Button("Start Streaming") {
                viewModel.startStreaming()
            }
        }
        .onAppear {
            viewModel.initialize()
        }
    }
}

class HealthViewModel: ObservableObject {
    @Published var heartRate: Double = 0
    @Published var hrvRmssd: Double = 0
    @Published var steps: Double = 0

    private let synheartWear = SynheartWear()
    private var cancellables = Set<AnyCancellable>()

    func initialize() {
        Task {
            try? await synheartWear.initialize()
            try? await synheartWear.requestPermissions([.heartRate, .hrv, .steps])
        }
    }

    func startStreaming() {
        synheartWear.streamHR(interval: 3.0)
            .sink { _ in } receiveValue: { [weak self] metrics in
                self?.heartRate = metrics.getMetric(.hr) ?? 0
                self?.hrvRmssd = metrics.getMetric(.hrvRmssd) ?? 0
                self?.steps = metrics.getMetric(.steps) ?? 0
            }
            .store(in: &cancellables)
    }
}
```

## 🤝 Contributing

We welcome contributions! See the main repository's [Contributing Guidelines](https://github.com/synheart-ai/synheart-wear/blob/main/CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Main Repository (Source of Truth)**: [synheart-wear](https://github.com/synheart-ai/synheart-wear)
- **Documentation**: [RFC Documentation](https://github.com/synheart-ai/synheart-wear/blob/main/docs/RFC.md)
- **Data Schema**: [Metrics Schema](https://github.com/synheart-ai/synheart-wear/blob/main/schema/metrics.schema.json)
- **Flutter SDK**: [synheart-wear-flutter](https://github.com/synheart-ai/synheart-wear-flutter)
- **Android SDK**: [synheart-wear-android](https://github.com/synheart-ai/synheart-wear-android)
- **CLI Tool**: [synheart-wear-cli](https://github.com/synheart-ai/synheart-wear-cli)
- **Cloud Service**: [synheart-wear-service](https://github.com/synheart-ai/synheart-wear-service)
- **API Documentation**: [Swagger UI](https://synheart-wear-service-leatest.onrender.com/swagger/index.html)
- **Synheart AI**: [synheart.ai](https://synheart.ai)
- **Issues**: [GitHub Issues](https://github.com/synheart-ai/synheart-wear-ios/issues)

## 🔧 Troubleshooting

### Common Issues

#### OAuth Flow Issues

**Problem**: Deep link not opening app after OAuth approval
- **Solution**: 
  - Verify `Info.plist` has correct URL scheme configuration
  - Ensure redirect URI matches exactly (case-sensitive)
  - Check that redirect URI is registered with WHOOP developer portal
  - Verify app is installed and URL scheme is unique

**Problem**: "Authentication failed" error during `connectWithCode()`
- **Solution**:
  - State parameter mismatch - ensure you're using the same state from `connect()`
  - OAuth flow may have expired - restart the flow by calling `connect()` again
  - Check that code hasn't expired (OAuth codes expire quickly)

**Problem**: Browser doesn't open when calling `connect()`
- **Solution**:
  - Check network connection
  - Verify `appId` is correct
  - Check that base URL is accessible
  - Ensure app has proper permissions

#### Data Fetching Issues

**Problem**: "Not connected" error when fetching data
- **Solution**:
  - Verify `isConnected()` returns `true`
  - Check that OAuth flow completed successfully
  - Ensure `user_id` is stored (check Keychain)
  - Try disconnecting and reconnecting

**Problem**: "Token expired" error
- **Solution**:
  - Token refresh failed - user needs to reconnect
  - Call `connect()` again to re-authenticate
  - The Wear Service handles refresh automatically, but if it fails, reconnection is required

**Problem**: Empty data returned
- **Solution**:
  - Check date range - ensure data exists for the specified period
  - Verify user has data in their WHOOP account
  - Try a wider date range
  - Check that user has granted necessary permissions

**Problem**: Empty metrics dictionary (data fetched but metrics are empty)
- **Solution**:
  - This was fixed in recent updates - the SDK now properly extracts metrics from nested `score` objects
  - Ensure you're using the latest SDK version
  - Check that the API response contains a `score` object with nested metrics
  - Verify the data type matches (recovery, sleep, workout, cycle)
  - Check console logs for extraction warnings

**Problem**: Data format unexpected
- **Solution**:
  - Check `WearMetrics` structure - all data is normalized
  - Use `metrics` dictionary for numeric values
  - Use `meta` dictionary for string metadata
  - Check `source` field to identify data origin
  - WHOOP data uses nested `score` objects - the SDK handles this automatically

#### Network Issues

**Problem**: "No connection" error
- **Solution**:
  - Check internet connectivity
  - Verify base URL is correct and accessible
  - Check firewall/proxy settings
  - Test with: `curl https://synheart-wear-service-leatest.onrender.com/health`

**Problem**: "Timeout" error
- **Solution**:
  - Network may be slow - retry the request
  - Check server status
  - Increase timeout if needed (modify NetworkClient)

**Problem**: "Rate limit exceeded" error
- **Solution**:
  - Too many requests - wait before retrying
  - Implement exponential backoff
  - Reduce request frequency

#### Configuration Issues

**Problem**: "Provider not configured" error
- **Solution**:
  - Ensure `appId` is provided in `SynheartWearConfig`
  - Verify `.whoop` is in `enabledAdapters`
  - Check that provider is initialized before use

**Problem**: Data not merging from multiple sources
- **Solution**:
  - Verify both adapters are in `enabledAdapters`
  - Check that WHOOP is connected (`isConnected()`)
  - Ensure HealthKit permissions are granted
  - Check `readMetrics()` source field - should be "merged_..."

### Debugging Tips

1. **Enable Logging**: Check console for warning messages
   ```swift
   // SDK logs warnings for failed data sources
   // Check console output for details
   // NetworkClient logs raw JSON responses for debugging
   ```

2. **Verify Connection State**:
   ```swift
   if let whoopProvider = try? synheartWear.getProvider(.whoop) as? WhoopProvider {
       print("Connected: \(whoopProvider.isConnected())")
       print("User ID: \(whoopProvider.getUserId() ?? "none")")
   }
   ```

3. **Inspect Metrics Extraction**:
   ```swift
   let recovery = try await whoopProvider.fetchRecovery()
   for record in recovery {
       print("Metrics keys: \(record.metrics.keys)")
       print("Meta keys: \(record.meta.keys)")
       print("Source: \(record.source)")
       print("Timestamp: \(record.timestamp)")
       
       // Check if metrics are populated
       if record.metrics.isEmpty {
           print("⚠️ Warning: Metrics dictionary is empty")
           print("This may indicate an extraction issue")
       }
   }
   ```

4. **Test API Connectivity**:
   ```bash
   # Test if service is accessible
   curl https://synheart-wear-service-leatest.onrender.com/health
   ```

5. **Check Swagger Documentation**:
   - Visit: https://synheart-wear-service-leatest.onrender.com/swagger/index.html
   - Verify endpoint paths and request/response formats
   - Review response structure to understand nested `score` objects

6. **Validate Configuration**:
   ```swift
   let config = SynheartWearConfig(
       enabledAdapters: [.whoop],
       appId: "your-app-id", // Must be set
       baseUrl: URL(string: "https://synheart-wear-service-leatest.onrender.com")!,
       redirectUri: "yourapp://oauth/callback" // Must match Info.plist
   )
   ```

7. **Debug Raw API Responses**:
   The SDK logs raw JSON responses to the console when fetching data. Look for:
   ```
   [NetworkClient] RAW JSON RESPONSE (Status: 200):
   [NetworkClient] Full Response Body: {...}
   ```
   This helps verify the API response structure and identify extraction issues.

### Getting Help

- **Check Documentation**: Review this README and API documentation
- **Swagger UI**: https://synheart-wear-service-leatest.onrender.com/swagger/index.html
- **GitHub Issues**: Report bugs or ask questions
- **Logs**: Check console output for detailed error messages

## 👥 Authors

- **Israel Goytom** - *Initial work* - [@isrugeek](https://github.com/isrugeek)
- **Synheart AI Team** - *RFC Design & Architecture*

---

## 📝 Recent Updates

### v0.1.1 - Metric Extraction Improvements

**Fixed Issues:**
- ✅ **Nested Score Object Extraction**: Fixed metric extraction from nested `score` objects in WHOOP API responses
- ✅ **Unit Conversions**: Properly converts milliseconds to seconds/minutes, kilojoules to calories
- ✅ **Deep Nesting Support**: Handles deeply nested structures like `score.stage_summary.total_rem_sleep_time_milli`
- ✅ **Null Value Handling**: Improved handling of null values in API responses
- ✅ **Enhanced Error Logging**: Added detailed logging of raw JSON responses for debugging

**Improvements:**
- Recovery metrics now properly extract from `score.recovery_score`, `score.hrv_rmssd_milli`, etc.
- Sleep metrics extract from `score.sleep_efficiency_percentage` and nested `stage_summary` objects
- Workout metrics extract from `score.strain`, `score.average_heart_rate`, `score.kilojoule`
- Timestamp extraction prioritizes `created_at` field (most common in WHOOP API)

**Breaking Changes:**
- None

**Migration Guide:**
- No migration needed - all changes are backward compatible
- Metrics that were previously empty should now be populated correctly

---

**Made with ❤️ by the Synheart AI Team**

*Technology with a heartbeat.*
