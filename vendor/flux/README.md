# Synheart Flux Native Libraries

This directory contains vendored Flux native binaries for iOS/macOS.

**Source:** https://github.com/synheart-ai/synheart-flux

## Structure

```
vendor/flux/
├── VERSION                    # Pinned Flux version (e.g., v0.1.0)
├── README.md                  # This file
└── ios/
    └── SynheartFlux.xcframework/
        ├── ios-arm64/
        ├── ios-arm64_x86_64-simulator/
        └── Info.plist
```

## Release Artifacts

Download from [Flux releases](https://github.com/synheart-ai/synheart-flux/releases):

| Artifact | Platform | Contents |
|----------|----------|----------|
| `synheart-flux-ios-xcframework.zip` | iOS | Universal XCFramework |

## Installation

### Manual Installation

1. Download `synheart-flux-ios-xcframework.zip` from the releases page
2. Extract to `vendor/flux/ios/`:
   ```bash
   unzip synheart-flux-ios-xcframework.zip -d vendor/flux/ios/
   ```

### Xcode Integration

1. Add `SynheartFlux.xcframework` to your Xcode project:
   - Drag and drop from `vendor/flux/ios/` into your project
   - Or: Project Settings → General → Frameworks, Libraries → Add `SynheartFlux.xcframework`

2. Ensure the framework is embedded and signed:
   - "Embed & Sign" in the Frameworks section

### Swift Package Manager

If using SPM, add the XCFramework as a binary target in Package.swift:

```swift
.binaryTarget(
    name: "SynheartFlux",
    path: "vendor/flux/ios/SynheartFlux.xcframework"
)
```

### CocoaPods

Add the vendored framework to your podspec:

```ruby
s.vendored_frameworks = 'vendor/flux/ios/SynheartFlux.xcframework'
```

## CI/CD Integration

On SDK release, CI should:

1. Read the Flux version from `VERSION`
2. Download Flux artifacts from GitHub Releases by tag
3. Place them into the appropriate directories
4. Build SDK artifacts
5. Publish SDK

Example CI script:

```bash
FLUX_VERSION=$(cat vendor/flux/VERSION)
FLUX_BASE_URL="https://github.com/synheart-ai/synheart-flux/releases/download/${FLUX_VERSION}"

# Download and extract iOS xcframework
curl -L "${FLUX_BASE_URL}/synheart-flux-ios-xcframework.zip" -o /tmp/flux-ios.zip
unzip -o /tmp/flux-ios.zip -d vendor/flux/ios/
```

## Versioning

When updating Flux:

1. Update the `VERSION` file with the new tag (e.g., `v0.2.0`)
2. CI will automatically fetch the new binaries on next release
3. Add to release notes: "Bundled Flux: vX.Y.Z"

## C FFI Function Mapping

The native library (`SynheartFlux.xcframework`) exports the following C functions:

| Function | Description |
|----------|-------------|
| `flux_whoop_to_hsi_daily` | Process WHOOP JSON to HSI (stateless) |
| `flux_garmin_to_hsi_daily` | Process Garmin JSON to HSI (stateless) |
| `flux_processor_new` | Create new stateful processor |
| `flux_processor_free` | Free processor |
| `flux_processor_process_whoop` | Process WHOOP with baselines |
| `flux_processor_process_garmin` | Process Garmin with baselines |
| `flux_processor_save_baselines` | Save baselines to JSON |
| `flux_processor_load_baselines` | Load baselines from JSON |
| `flux_free_string` | Free string returned by Flux |
| `flux_last_error` | Get last error message |

## Graceful Degradation

If the native library is not available at runtime:

- `FluxFfi.shared.isAvailable` returns `false`
- All processing methods return `nil`
- The SDK continues to function without Flux features
- Check `FluxFfi.shared.loadError` for details on why loading failed

## Current Implementation Note

The Wear SDK calls the **native Rust Flux library via C FFI** using Swift's dynamic library loading (`dlopen`).

- The Rust binaries are **not meant to be checked into git**. CI/CD should download
  them from Flux GitHub Releases (pinned by `vendor/flux/VERSION`) right before publishing.
- If the native binaries are missing at runtime, Flux will not be available (see
  `isFluxAvailable` / `fluxLoadError` in the public Flux API).
