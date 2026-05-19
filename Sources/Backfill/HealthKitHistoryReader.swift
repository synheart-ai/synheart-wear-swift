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
// to `.heartRate`, `.heartRateVariabilitySDNN`, and `.sleepAnalysis`
// up-front. The reader's `isAvailable()` returns true when HealthKit
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
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                bucket.asleep += mins
                bucket.deep = (bucket.deep ?? 0.0) + mins
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
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

    public func fetchOvernightPhysiology(
        start: Date,
        end: Date,
        timeZone: TimeZone
    ) async throws -> [Date: OvernightPhysiologySummary] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis),
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return [:]
        }

        let sleepSamples = try await categorySamples(type: sleepType, start: start, end: end)
        if sleepSamples.isEmpty { return [:] }

        // Restrict to actual-asleep windows (matches Flutter / Kotlin
        // "overnight only" semantic — in-bed-while-awake samples
        // shouldn't pull the average down).
        let asleepWindows = sleepSamples.filter { sample in
            switch sample.value {
            case HKCategoryValueSleepAnalysis.awake.rawValue,
                 HKCategoryValueSleepAnalysis.inBed.rawValue:
                return false
            default:
                return true
            }
        }
        if asleepWindows.isEmpty { return [:] }

        async let hrSamples = quantitySamples(type: hrType, start: start, end: end)
        async let hrvSamples = quantitySamples(type: hrvType, start: start, end: end)
        let hrPerMinute = HKUnit.count().unitDivided(by: HKUnit.minute())
        let ms = HKUnit.secondUnit(with: .milli)

        let hrPoints: [(Date, Double)] = try await hrSamples.map {
            ($0.startDate, $0.quantity.doubleValue(for: hrPerMinute))
        }
        let hrvPoints: [(Date, Double)] = try await hrvSamples.map {
            ($0.startDate, $0.quantity.doubleValue(for: ms))
        }

        var byDay: [Date: (hrSum: Double, hrN: Int, hrvSum: Double, hrvN: Int)] = [:]
        for window in asleepWindows {
            let wakeDay = startOfDay(for: window.endDate, in: timeZone)
            var acc = byDay[wakeDay] ?? (0.0, 0, 0.0, 0)
            for (t, bpm) in hrPoints where t >= window.startDate && t < window.endDate {
                acc.hrSum += bpm; acc.hrN += 1
            }
            for (t, rmssd) in hrvPoints where t >= window.startDate && t < window.endDate {
                acc.hrvSum += rmssd; acc.hrvN += 1
            }
            byDay[wakeDay] = acc
        }

        return byDay.mapValues { a in
            OvernightPhysiologySummary(
                hrvRmssdMs: a.hrvN > 0 ? a.hrvSum / Double(a.hrvN) : nil,
                restingHrBpm: a.hrN > 0 ? a.hrSum / Double(a.hrN) : nil
            )
        }
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
