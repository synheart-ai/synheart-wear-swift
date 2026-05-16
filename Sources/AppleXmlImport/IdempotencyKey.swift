// SPDX-License-Identifier: Apache-2.0
//
// SHA-256 idempotency key for backfill samples.
//
// See `docs/RFC-APPLE-XML-IMPORT.md` §6 in the synheart-wear repo
// for the canonical key recipe.

import Foundation
import CryptoKit

public enum IdempotencyKey {

    /// Compute the 32-byte SHA-256 idempotency key for a sample.
    ///
    /// The same sample (regardless of how it arrived — Apple XML,
    /// live HealthKit, vendor sync) hashes to the same key, so the
    /// runtime's `INSERT OR IGNORE` deduplicates naturally.
    public static func key(for sample: AppleHealthSample) -> Data {
        var hasher = SHA256()
        hasher.update(data: Data(sample.metric.rawValue.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(sample.source.utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(String(sample.startMs).utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(String(sample.endMs).utf8))
        hasher.update(data: Data("|".utf8))
        hasher.update(data: Data(canonicalValueString(sample.value).utf8))
        return Data(hasher.finalize())
    }

    /// Hex string for logs and debug. Avoid using this as the
    /// storage key — the `Data` form is half the bytes.
    public static func hexKey(for sample: AppleHealthSample) -> String {
        key(for: sample).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalValueString(_ v: AppleHealthSample.Value) -> String {
        switch v {
        case .quantity(let d):
            // Six decimal places matches the RFC and avoids
            // float-formatting drift between platforms.
            return String(format: "%.6f", d)
        case .sleepStage(let s):
            return s.rawValue
        }
    }
}
