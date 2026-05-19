// SPDX-License-Identifier: Apache-2.0
//
// Historical HealthKit read contract. Consumed by
// `SynheartCore.Backfill.HealthKitRuntimeSink` in synheart-core-swift
// to seed the runtime SRM from Apple Health history at install / login.
//
// Parallels Flutter's `HealthAdapter.fetchSleepNights` /
// `fetchOvernightPhysiology` in synheart_wear, and the Kotlin
// `HealthHistoryReader` in synheart-wear-kotlin's
// `ai.synheart.wear.backfill` package — wear owns HealthKit SDK calls,
// core owns aggregation and runtime push.

import Foundation

/// Per-night sleep summary keyed by local wake-day (the day the sleep
/// session ended in the caller-supplied time zone).
///
/// - `totalAsleepMinutes` excludes AWAKE / IN-BED-WITHOUT-SLEEP stages
///   when stage data is present. Falls back to session duration when
///   stages are absent.
/// - `deepMinutes` / `remMinutes` are nil when the source didn't classify
///   stages (e.g. devices that only emit a sleep session without a
///   stage breakdown).
public struct SleepNightSummary: Equatable, Sendable {
    public let totalAsleepMinutes: Double
    public let deepMinutes: Double?
    public let remMinutes: Double?

    public init(totalAsleepMinutes: Double, deepMinutes: Double?, remMinutes: Double?) {
        self.totalAsleepMinutes = totalAsleepMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
    }
}

/// Per-night overnight physiology keyed by local wake-day.
///
/// HR and HRV-RMSSD are averaged over the sleep window(s) for that day.
/// A field is nil when no in-sleep samples were available — the runtime
/// treats nils as "missing for this day" rather than zero.
public struct OvernightPhysiologySummary: Equatable, Sendable {
    public let hrvRmssdMs: Double?
    public let restingHrBpm: Double?

    public init(hrvRmssdMs: Double?, restingHrBpm: Double?) {
        self.hrvRmssdMs = hrvRmssdMs
        self.restingHrBpm = restingHrBpm
    }
}

/// Reader contract for historical HealthKit data. Implemented by
/// `HealthKitHistoryReader`; abstracted so synheart-core-swift can
/// depend on the shape without importing HealthKit and so tests can
/// fake the reads.
///
/// Both fetch methods bucket by **local wake-day** (the day the sleep
/// session ended) using the caller-supplied `timeZone`. The key `Date`
/// represents midnight at the start of that wake-day in the requested
/// zone. An empty map is a valid "no data" response — callers should
/// not treat it as an error.
public protocol HealthHistoryReader: AnyObject, Sendable {
    /// True when HealthKit is available and the host has been granted
    /// the read authorizations the reader needs.
    func isAvailable() async -> Bool

    func fetchSleepNights(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [Date: SleepNightSummary]

    func fetchOvernightPhysiology(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [Date: OvernightPhysiologySummary]
}
