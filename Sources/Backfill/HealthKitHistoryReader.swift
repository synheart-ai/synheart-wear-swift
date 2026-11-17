// SPDX-License-Identifier: Apache-2.0
//
// HealthKit-backed `HealthHistoryReader` for iOS / watchOS.
//
// Designed to be created once and reused. Owns its own `HKHealthStore`
// — does not extract HealthKit calls from `SynheartWear`. That keeps
// the backfill path self-contained and lets apps use it without
// initializing the full `SynheartWear` machinery.
//
// Authorization is the caller's responsibility: request read access
// to `.heartRate`, `.restingHeartRate`, `.heartRateVariabilitySDNN`, and
// `.sleepAnalysis` up-front. The reader's `isAvailable()` returns true when HealthKit
// itself is available; per-type authorization is checked at read time
// (HealthKit returns empty results without throwing when read access
// is denied — by design, to avoid leaking presence/absence of data).

#if canImport(HealthKit)
import Foundation
import HealthKit

public final class HealthKitHistoryReader: HealthHistoryReader, @unchecked Sendable {

    private let healthStore: HKHealthStore

    public init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    public func isAvailable() async -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }

    // ────────────────────────────────────────────────────────────── //
    // Sleep                                                           //
    // ────────────────────────────────────────────────────────────── //

    // Sleep stages arrived in iOS 16 / watchOS 9 / macOS 13. Below that the
    // symbols do not exist and HealthKit never writes the values, so the
    // stage buckets stay nil and every asleep sample counts toward the total.
    private static let asleepDeepRaw: Int? = {
        if #available(iOS 16.0, watchOS 9.0, macOS 13.0, *) {
            return HKCategoryValueSleepAnalysis.asleepDeep.rawValue
        }
        return nil
    }()

    private static let asleepREMRaw: Int? = {
        if #available(iOS 16.0, watchOS 9.0, macOS 13.0, *) {
            return HKCategoryValueSleepAnalysis.asleepREM.rawValue
        }
        return nil
    }()

    public func fetchSleepNights(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [Date: SleepNightSummary] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return [:]
        }

        let samples = try await categorySamples(
            type: sleepType,
            start: start,
            end: end
        )
        if samples.isEmpty { return [:] }

        var byDay: [Date: (asleep: Double, deep: Double?, rem: Double?)] = [:]
        for sample in samples {
            let mins = sample.endDate.timeIntervalSince(sample.startDate) / 60.0
            let wakeDay = startOfDay(for: sample.endDate, in: timeZone)

            var bucket = byDay[wakeDay] ?? (asleep: 0.0, deep: nil, rem: nil)
            switch sample.value {
            // Awake / in-bed-without-sleep buckets do not count toward asleep.
            case HKCategoryValueSleepAnalysis.awake.rawValue,
                 HKCategoryValueSleepAnalysis.inBed.rawValue:
                break
            case let v where v == Self.asleepDeepRaw:
                bucket.asleep += mins
                bucket.deep = (bucket.deep ?? 0.0) + mins
            case let v where v == Self.asleepREMRaw:
                bucket.asleep += mins
                bucket.rem = (bucket.rem ?? 0.0) + mins
            default:
                // asleepCore, asleepUnspecified, plus legacy `.asleep` (iOS 15
                // and earlier) all count toward asleep without contributing
                // to a stage bucket.
                bucket.asleep += mins
            }
            byDay[wakeDay] = bucket
        }

        return byDay.mapValues { b in
            SleepNightSummary(
                totalAsleepMinutes: b.asleep,
                deepMinutes: b.deep,
                remMinutes: b.rem
            )
        }
    }

    // ────────────────────────────────────────────────────────────── //
    // Overnight HR + HRV                                              //
    // ────────────────────────────────────────────────────────────── //

    /// Overnight heart rate and HRV (SDNN) averaged over each night's asleep
    /// windows, plus the day's resting-heart-rate sample, keyed by local
    /// wake-day. Resting heart rate comes only from HealthKit's
    /// `.restingHeartRate`; a day without one has none, and a day with one
    /// but no sleep still gets an entry. Request read access to
    /// `.restingHeartRate` along with the other types.
    public func fetchOvernightPhysiology(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [Date: OvernightPhysiologySummary] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN),
              let restingType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            return [:]
        }
        let hrPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let ms = HKUnit.secondUnit(with: .milli)

        // Restrict to actual-asleep windows (matches Flutter / Kotlin
        // "overnight only" semantic — in-bed-while-awake samples
        // shouldn't pull the average down).
        let windows = try await categorySamples(type: sleepType, start: start, end: end)
            .filter { sample in
                switch sample.value {
                case HKCategoryValueSleepAnalysis.awake.rawValue,
                     HKCategoryValueSleepAnalysis.inBed.rawValue:
                    return false
                default:
                    return true
                }
            }
            .map { SleepWindow(start: $0.startDate, end: $0.endDate) }

        let resting: [(Date, Double)] = try await quantitySamples(type: restingType, start: start, end: end)
            .map { ($0.startDate, $0.quantity.doubleValue(for: hrPerMinute)) }
        if windows.isEmpty && resting.isEmpty { return [:] }

        // Without an asleep window there is nothing to average the samples over.
        var hrPoints: [(Date, Double)] = []
        var hrvPoints: [(Date, Double)] = []
        if !windows.isEmpty {
            async let hrSamples = quantitySamples(type: hrType, start: start, end: end)
            async let hrvSamples = quantitySamples(type: hrvType, start: start, end: end)
            hrPoints = try await hrSamples.map { ($0.startDate, $0.quantity.doubleValue(for: hrPerMinute)) }
            hrvPoints = try await hrvSamples.map { ($0.startDate, $0.quantity.doubleValue(for: ms)) }
        }

        return summarizeOvernight(
            windows: windows,
            heartRate: hrPoints,
            hrvSdnn: hrvPoints,
            restingHeartRate: resting,
            timeZone: timeZone
        )
    }

    // ────────────────────────────────────────────────────────────── //
    // HealthKit query helpers                                         //
    // ────────────────────────────────────────────────────────────── //

    private func categorySamples(
        type: HKCategoryType,
        start: Date,
        end: Date
    ) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func quantitySamples(
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error = error { cont.resume(throwing: error); return }
                cont.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            healthStore.execute(query)
        }
    }

    private func startOfDay(for date: Date, in timeZone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.startOfDay(for: date)
    }
}
#endif
