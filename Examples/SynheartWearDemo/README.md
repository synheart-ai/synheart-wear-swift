# SynheartWearDemo

A tiny SwiftUI iOS demo of the Synheart Wear SDK, wired to the parent
package via a relative SPM dependency (`path: "../.."`).

## Open

```sh
cd Examples/SynheartWearDemo
open Package.swift   # opens in Xcode
```

Then pick an iOS Simulator scheme and Run.

## What it does

- Lists the built-in providers (Whoop, Garmin, Fitbit, Oura, BLE HRM,
  Platform Health).
- Tapping a provider opens a detail screen with a "Start stream"
  button. BPM updates once per second.
- BLE HRM and Platform Health stream from the real SDK when
  available (BLE needs a paired sensor; HealthKit needs authorization).
- The cloud providers stream **synthetic** values (~70 BPM ± 5) since
  this demo doesn't carry real OAuth credentials. Wire them up by
  passing a real `appId` and following the OAuth flow described in
  `../../docs/PROVIDERS.md`.

## Build verification

```sh
swift package resolve     # works on macOS
swift build               # iOS-only target — use Xcode to build for device/sim
```

`swift build` from the host CLI may not produce an iOS app binary —
use Xcode for that. The package itself resolves and type-checks.
