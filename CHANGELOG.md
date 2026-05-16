# Changelog

All notable changes to this package will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-05-15

Adds Fitbit + Oura cloud providers to reach parity with the
Flutter / Kotlin siblings, contracts the public API surface for
long-term stability, and switches documentation to the central
Mintlify site.

### Added
- **FitbitProvider** and **OuraProvider** — cloud OAuth + data fetch
  via the Synheart Wear API, mirroring the Flutter SDK contract. Both
  conform to `WearableProvider`. New `.oura` case on `DeviceAdapter`;
  Fitbit was previously a placeholder. Wired into `SynheartWear` via
  `fitbit` / `oura` accessors and `getProvider(.fitbit|.oura)`.
- Generic vendor endpoints on `WearServiceAPI`:
  `initiateVendorOAuth`, `fetchVendorData`, `disconnectVendor`.
- README "Documentation" section links to the central Mintlify docs
  site at <https://docs.synheart.ai/synheart-wear/swift> — single
  source of truth shared with the Kotlin / Flutter siblings.

### Changed
- **Public API surface contracted** for first OSS release:
  `RamenClient`, `RamenConfig`, `RamenEvent`, `RamenConnectionState`,
  `RamenError`, `RamenErrorCode`, `RamenAckStatus` — all `internal`.
  `HeartRateParser` (BLE HRM impl detail) — `internal`. The Ramen
  facade is not yet wired through `SynheartWear`; ship it as part of
  a future push-streaming release rather than as public surface today.

### Fixed
- `NetworkClient` no longer dumps the full raw JSON response body of
  every API call to stdout via `print(...)`. The previous behavior
  exposed biometric values, vendor user IDs, and OAuth state in
  process logs of every consumer app — and was unconditional, with
  no debug flag. Decoding errors now surface a structured
  `DecodingError` description without including the response body.

### Removed
- Per-repo `docs/` scaffold (PROVIDERS, STREAMING, ARCHITECTURE,
  BLE_HRM, APPLE_HEALTH_XML). The same content lives in the central
  docs site; keeping a parallel copy here was a drift trap.

## [0.3.0] - 2026-05-07

OSS launch release. Adds Apple Health XML backfill import, renames
the platform-health adapter for clarity, and scrubs internal /
fabricated language from public docs.

### Added
- **Apple Health XML backfill** — new `AppleXmlImport` module with a
  streaming SAX parser (`AppleHealthXmlParser`), top-level
  orchestrator (`AppleHealthXmlImport`), and a SHA-256 idempotency
  key recipe (`IdempotencyKey`). Designed for multi-hundred-MB
  `export.xml` files without blowing past the 200 MB memory budget.
- Public types: `AppleHealthSample`, `AppleHealthMetric`,
  `AppleXmlIngestSink`.

### Breaking
- **`DeviceAdapter.appleHealthKit` renamed to
  `DeviceAdapter.platformHealth`.** The enum value has always covered
  both Apple HealthKit (iOS) and Health Connect (Android via the
  Flutter binding) — the new name reflects what it actually does.
  Update any `.appleHealthKit` reference in your code to
  `.platformHealth`.

### Changed
- README repo URLs corrected: `synheart-wear-swift` (was `-ios`),
  `synheart-edge-watch-ios` (was `synheart-wear-watch-ios`).
- Removed stale CocoaPods snippet (`pod 'SynheartWear', '~> 0.2.0'`)
  — there is no `.podspec` in the repo. Swift Package Manager is the
  supported install path.
- Removed invented `v0.1.1 - Metric Extraction Improvements` entry
  from "Recent Updates".
- Footer puffery removed.

[Unreleased]: https://github.com/synheart-ai/synheart-wear-swift/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/synheart-ai/synheart-wear-swift/releases/tag/v0.3.0
