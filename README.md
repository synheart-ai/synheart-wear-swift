# Synheart Wear - iOS SDK

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![iOS 13.0+](https://img.shields.io/badge/iOS-13.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![watchOS 6.0+](https://img.shields.io/badge/watchOS-6.0%2B-blue.svg)](https://developer.apple.com/watchos/)

**Unified wearable SDK for iOS** — Stream biometric data from Apple Watch, Fitbit, Garmin, Whoop, and other devices via HealthKit with a single standardized API.

## 🚀 Features

- **📱 HealthKit Integration**: Native iOS biometric data access from Apple Watch
- **⌚ Multi-Device Support**: Apple Watch, Fitbit, Garmin, Whoop (via HealthKit sync)
- **🔄 Real-Time Streaming**: Live HR and HRV data streams with Combine framework
- **📊 Unified Schema**: Consistent data format across all devices
- **🔒 Privacy-First**: Consent-based data access with encryption
- **💾 Local Storage**: Encrypted offline data persistence with Keychain
- **⚡ Swift Concurrency**: Modern async/await API

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
    baseUrl: URL(string: "https://api.wear.synheart.io")!, // Optional: defaults to production
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
    baseUrl: URL(string: "https://api.wear.synheart.io")!,
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
    baseUrl: URL(string: "https://api.wear.synheart.io")!,
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

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- **Main Repository (Source of Truth)**: [synheart-wear](https://github.com/synheart-ai/synheart-wear)
- **Documentation**: [RFC Documentation](https://github.com/synheart-ai/synheart-wear/blob/main/docs/RFC.md)
- **Data Schema**: [Metrics Schema](https://github.com/synheart-ai/synheart-wear/blob/main/schema/metrics.schema.json)
- **Flutter SDK**: [synheart-wear-flutter](https://github.com/synheart-ai/synheart-wear-flutter)
- **Android SDK**: [synheart-wear-android](https://github.com/synheart-ai/synheart-wear-android)
- **CLI Tool**: [synheart-wear-cli](https://github.com/synheart-ai/synheart-wear-cli)
- **Cloud Service**: [synheart-wear-service](https://github.com/synheart-ai/synheart-wear-service)
- **Synheart AI**: [synheart.ai](https://synheart.ai)
- **Issues**: [GitHub Issues](https://github.com/synheart-ai/synheart-wear-ios/issues)

## 👥 Authors

- **Israel Goytom** - *Initial work* - [@isrugeek](https://github.com/isrugeek)
- **Synheart AI Team** - *RFC Design & Architecture*

---

**Made with ❤️ by the Synheart AI Team**

*Technology with a heartbeat.*
