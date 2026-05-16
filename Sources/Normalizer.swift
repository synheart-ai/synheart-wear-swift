import Foundation

/// Normalizes biometric data from multiple sources into unified format
class Normalizer {
    /// Merge snapshots from multiple adapters into a single unified snapshot
    func mergeSnapshots(_ snapshots: [WearMetrics]) -> WearMetrics {
        guard !snapshots.isEmpty else {
            return WearMetricsBuilder()
                .timestamp(Date())
                .deviceId("unknown")
                .source("none")
                .build()
        }

        guard snapshots.count > 1 else {
            return snapshots[0]
        }

        // Merge multiple snapshots
        var mergedMetrics: [String: Double] = [:]
        var mergedMeta: [String: String] = [:]
        var latestTimestamp = Date.distantPast
        var primarySource = ""
        var primaryDeviceId = ""

        for snapshot in snapshots {
            if snapshot.timestamp > latestTimestamp {
                latestTimestamp = snapshot.timestamp
                primarySource = snapshot.source
                primaryDeviceId = snapshot.deviceId
            }

            mergedMetrics.merge(snapshot.metrics) { _, new in new }
            mergedMeta.merge(snapshot.meta) { _, new in new }
        }

        return WearMetrics(
            timestamp: latestTimestamp,
            deviceId: primaryDeviceId,
            source: "merged_\(primarySource)",
            metrics: mergedMetrics,
            meta: mergedMeta
        )
    }

    /// Validate that metrics meet quality requirements
    func validateMetrics(_ metrics: WearMetrics) -> Bool {
        // Validate timestamp
        guard metrics.timestamp.timeIntervalSince1970 > 0 else { return false }

        // Validate device ID and source
        guard !metrics.deviceId.isEmpty, !metrics.source.isEmpty else { return false }

        // Validate HR if present
        if let hr = metrics.getMetric(.hr) {
            guard hr >= 30 && hr <= 220 else { return false }
        }

        // Validate HRV if present
        if let hrv = metrics.getMetric(.hrvRmssd) {
            guard hrv >= 0 && hrv <= 500 else { return false }
        }

        // Validate steps if present
        if let steps = metrics.getMetric(.steps) {
            guard steps >= 0 else { return false }
        }

        return true
    }

    /// Normalize HR value to standard range
    func normalizeHR(_ hr: Double) -> Double {
        return min(max(hr, 30.0), 220.0)
    }

    /// Normalize HRV value to standard range
    func normalizeHRV(_ hrv: Double) -> Double {
        return min(max(hrv, 0.0), 500.0)
    }
}
