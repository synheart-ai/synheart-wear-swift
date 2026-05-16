// SPDX-License-Identifier: Apache-2.0
//
// Public types for the Apple Health XML backfill import path.
//
// See docs/RFC-APPLE-XML-IMPORT.md in the synheart-wear repo for the
// motivation, scope, and pipeline overview.

import Foundation

// MARK: - Public types

/// A single sample parsed from `export.xml`. Crosses the boundary
/// from the Swift parser to the native runtime via FFI.
public struct AppleHealthSample: Equatable {
    public let metric: AppleHealthMetric
    public let source: String       // e.g. "Apple Watch", "iPhone"
    public let startMs: Int64       // unix epoch ms
    public let endMs: Int64
    public let value: Value

    public init(
        metric: AppleHealthMetric,
        source: String,
        startMs: Int64,
        endMs: Int64,
        value: Value
    ) {
        self.metric = metric
        self.source = source
        self.startMs = startMs
        self.endMs = endMs
        self.value = value
    }

    public enum Value: Equatable {
        case quantity(Double)
        case sleepStage(SleepStage)
    }
}

/// Subset of HealthKit identifiers we import in v1.
public enum AppleHealthMetric: String, CaseIterable {
    case heartRate = "heart_rate"
    case hrvSdnn = "hrv_sdnn"
    case steps = "steps"
    case calories = "calories"
    case spo2 = "spo2"
    case temperature = "temperature"
    case sleepStage = "sleep_stage"

    /// Map an Apple identifier string (the `type` attribute) to our
    /// metric type. Returns `nil` for identifiers we don't import in
    /// v1.
    static func fromAppleIdentifier(_ id: String) -> AppleHealthMetric? {
        switch id {
        case "HKQuantityTypeIdentifierHeartRate": return .heartRate
        case "HKQuantityTypeIdentifierHeartRateVariabilitySDNN": return .hrvSdnn
        case "HKQuantityTypeIdentifierStepCount": return .steps
        case "HKQuantityTypeIdentifierActiveEnergyBurned": return .calories
        case "HKQuantityTypeIdentifierOxygenSaturation": return .spo2
        case "HKQuantityTypeIdentifierBodyTemperature": return .temperature
        case "HKCategoryTypeIdentifierSleepAnalysis": return .sleepStage
        default: return nil
        }
    }
}

/// Sleep stage values. Apple has revised these enums multiple times;
/// we accept the union of known values.
public enum SleepStage: String, CaseIterable {
    case inBed
    case asleep        // generic / legacy / unspecified
    case awake
    case light         // AsleepCore
    case deep          // AsleepDeep
    case rem           // AsleepREM

    static func fromAppleValue(_ s: String) -> SleepStage? {
        switch s {
        case "HKCategoryValueSleepAnalysisInBed": return .inBed
        case "HKCategoryValueSleepAnalysisAsleep": return .asleep
        case "HKCategoryValueSleepAnalysisAsleepUnspecified": return .asleep
        case "HKCategoryValueSleepAnalysisAwake": return .awake
        case "HKCategoryValueSleepAnalysisAsleepCore": return .light
        case "HKCategoryValueSleepAnalysisAsleepDeep": return .deep
        case "HKCategoryValueSleepAnalysisAsleepREM": return .rem
        default: return nil
        }
    }
}

/// Result returned to the calling app at the end of an import.
public struct ImportResult: Equatable {
    public let importId: String
    public let totalSamples: Int
    public let inserted: Int
    public let skippedAsDuplicate: Int
    public let skippedAsUnknown: Int
    public let durationMs: Int

    public init(
        importId: String,
        totalSamples: Int,
        inserted: Int,
        skippedAsDuplicate: Int,
        skippedAsUnknown: Int,
        durationMs: Int
    ) {
        self.importId = importId
        self.totalSamples = totalSamples
        self.inserted = inserted
        self.skippedAsDuplicate = skippedAsDuplicate
        self.skippedAsUnknown = skippedAsUnknown
        self.durationMs = durationMs
    }
}

/// All errors thrown by the public import API.
public enum AppleHealthXmlError: Error, Equatable {
    case zipReadFailed(message: String)
    case xmlNotFound
    case parseFailed(line: Int, column: Int, message: String)
    case ingestFailed(message: String)
    case cancelled
}
