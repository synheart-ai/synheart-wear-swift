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
/// `overnightHrBpm` and HRV are averaged over the sleep window(s) for that
/// day. RMSSD and SDNN are different statistics and are never reported as
/// each other: HealthKit records SDNN only, so `HealthKitHistoryReader`
/// fills `hrvSdnnMs` and leaves `hrvRmssdMs` nil.
///
/// `restingHrBpm` is HealthKit's resting-heart-rate sample for the day (the
/// median when there are several). It is nil when there is none or read
/// access wasn't granted, and is never derived from the sleep samples.
/// Before 0.4.4 it carried the mean heart rate asleep, which is now
/// `overnightHrBpm`.
///
/// A field is nil when there was nothing to read — the runtime treats nils
/// as "missing for this day" rather than zero.
public struct OvernightPhysiologySummary: Equatable, Sendable {
    public let hrvRmssdMs: Double?
    public let hrvSdnnMs: Double?
    public let restingHrBpm: Double?
    public let overnightHrBpm: Double?

    public init(
        hrvRmssdMs: Double?,
        restingHrBpm: Double?,
        hrvSdnnMs: Double? = nil,
        overnightHrBpm: Double? = nil
    ) {
        self.hrvRmssdMs = hrvRmssdMs
        self.hrvSdnnMs = hrvSdnnMs
        self.restingHrBpm = restingHrBpm
        self.overnightHrBpm = overnightHrBpm
    }
}

/// One asleep span.
struct SleepWindow: Equatable {
    let start: Date
    let end: Date
}

/// Builds the per-day overnight summaries from raw samples.
///
/// Heart rate and HRV (SDNN) are averaged over the samples inside each
/// window and filed under the day the window ended in `timeZone`. Resting
/// heart rate is the median of that local day's resting-HR samples; a day
/// with one but no sleep still gets an entry.
func summarizeOvernight(
    windows: [SleepWindow],
    heartRate: [(Date, Double)],
    hrvSdnn: [(Date, Double)],
    restingHeartRate: [(Date, Double)],
    timeZone: TimeZone
) -> [Date: OvernightPhysiologySummary] {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = timeZone

    var byDay: [Date: (hrSum: Double, hrN: Int, hrvSum: Double, hrvN: Int)] = [:]
    for window in windows {
        let wakeDay = cal.startOfDay(for: window.end)
        var acc = byDay[wakeDay] ?? (0.0, 0, 0.0, 0)
        for (t, bpm) in heartRate where t >= window.start && t < window.end {
            acc.hrSum += bpm; acc.hrN += 1
        }
        for (t, sdnn) in hrvSdnn where t >= window.start && t < window.end {
            acc.hrvSum += sdnn; acc.hrvN += 1
        }
        byDay[wakeDay] = acc
    }

    var restingByDay: [Date: [Double]] = [:]
    for (t, bpm) in restingHeartRate where bpm > 0 {
        restingByDay[cal.startOfDay(for: t), default: []].append(bpm)
    }

    var out: [Date: OvernightPhysiologySummary] = [:]
    for day in Set(byDay.keys).union(restingByDay.keys) {
        let a = byDay[day]
        // HealthKit's HRV is SDNN; it must not reach an RMSSD baseline.
        out[day] = OvernightPhysiologySummary(
            hrvRmssdMs: nil,
            restingHrBpm: restingByDay[day].map(median),
            hrvSdnnMs: a.flatMap { $0.hrvN > 0 ? $0.hrvSum / Double($0.hrvN) : nil },
            overnightHrBpm: a.flatMap { $0.hrN > 0 ? $0.hrSum / Double($0.hrN) : nil }
        )
    }
    return out
}

private func median(_ values: [Double]) -> Double {
    let s = values.sorted()
    let mid = s.count / 2
    return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
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
