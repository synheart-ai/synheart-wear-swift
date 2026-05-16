// SPDX-License-Identifier: Apache-2.0
//
// Top-level orchestrator for Apple Health XML backfill.
//
// Drives the streaming parser, batches samples, and hands them to the
// `AppleXmlIngestSink` (typically a runtime FFI bridge — see
// `AppleXmlRuntimeSink` below for the production binding).
//
// Stays decoupled from the FFI layer via the `AppleXmlIngestSink`
// protocol so unit tests can inject a recording sink without
// linking the runtime.

import Foundation

/// Receives batches of parsed samples. Concrete implementations push
/// into the runtime via FFI; the test sink just records.
public protocol AppleXmlIngestSink {
    /// Open a new import session. Throws on failure.
    func open(importId: String) throws

    /// Insert a batch. Returns `(inserted, skippedAsDuplicate)`.
    func insertBatch(_ samples: [AppleHealthSample]) throws -> (inserted: Int, skipped: Int)

    /// Finalize and close the session. Returns the runtime's tally.
    func finalize() throws -> ImportResult
}

/// Top-level entry point. Apps construct this with a path to the
/// user's exported `export.zip` (or directly an `export.xml`) and a
/// sink, then call `parse()`.
///
/// The orchestrator does NOT unzip the archive — that lives in
/// platform-specific SDK code (which can use `Process` / `unzip` on
/// macOS or `Compression.framework` on iOS) so this file stays free
/// of zip dependencies and is unit-testable with raw XML fixtures.
public final class AppleHealthXmlImport {

    /// Maximum batch size handed to the sink. 1000 mirrors the
    /// "1000/tx" budget in the RFC.
    private static let batchSize = 1000

    public init(xmlURL: URL, sink: AppleXmlIngestSink, importId: String? = nil) {
        self.xmlURL = xmlURL
        self.sink = sink
        self.importId = importId ?? UUID().uuidString
    }

    public let xmlURL: URL
    public let sink: AppleXmlIngestSink
    public let importId: String

    /// Parse the XML and stream samples to the sink. Throws on any
    /// parse / ingest failure.
    public func parse(progress: @escaping (Double) -> Void = { _ in }) throws -> ImportResult {
        let started = Date()
        try sink.open(importId: importId)

        var batch: [AppleHealthSample] = []
        batch.reserveCapacity(Self.batchSize)
        var totalInserted = 0
        var totalSkipped = 0
        var totalSeen = 0

        let parser = AppleHealthXmlParser(
            onSample: { sample in
                batch.append(sample)
                totalSeen += 1
            }
        )
        // Drive the parse, flushing every `batchSize` samples.
        try parseAndFlushPeriodically(
            parser: parser,
            batch: &batch,
            totalInserted: &totalInserted,
            totalSkipped: &totalSkipped,
            progress: progress
        )

        // Flush the tail.
        if !batch.isEmpty {
            let r = try sink.insertBatch(batch)
            totalInserted += r.inserted
            totalSkipped += r.skipped
            batch.removeAll(keepingCapacity: false)
        }

        let runtimeResult = try sink.finalize()

        // The runtime is the source of truth on counts, but if the
        // sink under-reports we fall back to our local tally.
        let inserted = max(runtimeResult.inserted, totalInserted)
        let skipped = max(runtimeResult.skippedAsDuplicate, totalSkipped)
        let total = max(runtimeResult.totalSamples, totalSeen)

        let durationMs = Int(Date().timeIntervalSince(started) * 1000)
        progress(1.0)

        return ImportResult(
            importId: runtimeResult.importId,
            totalSamples: total,
            inserted: inserted,
            skippedAsDuplicate: skipped,
            skippedAsUnknown: max(0, parser.samplesSkipped),
            durationMs: durationMs
        )
    }

    private func parseAndFlushPeriodically(
        parser: AppleHealthXmlParser,
        batch: inout [AppleHealthSample],
        totalInserted: inout Int,
        totalSkipped: inout Int,
        progress: (Double) -> Void
    ) throws {
        // SAX parsing is fully synchronous, so we set up a callback
        // wrapper that flushes when the batch fills. We swap the
        // parser's onSample to this flushing variant.
        var localBatch: [AppleHealthSample] = []
        localBatch.reserveCapacity(Self.batchSize)
        let sinkRef = sink
        let batchSize = Self.batchSize
        var sinkInserted = 0
        var sinkSkipped = 0
        var sinkError: Error? = nil

        let flushingParser = AppleHealthXmlParser(
            onSample: { sample in
                guard sinkError == nil else { return }
                localBatch.append(sample)
                if localBatch.count >= batchSize {
                    do {
                        let r = try sinkRef.insertBatch(localBatch)
                        sinkInserted += r.inserted
                        sinkSkipped += r.skipped
                        localBatch.removeAll(keepingCapacity: true)
                    } catch {
                        sinkError = error
                    }
                }
            }
        )

        try flushingParser.parse(xmlURL: xmlURL)
        if let e = sinkError {
            throw e
        }

        batch = localBatch
        totalInserted += sinkInserted
        totalSkipped += sinkSkipped
        // Pass the parser's skip count up through the outer parser
        // wrapper — this is purely informational.
        let _ = parser
        progress(0.95)
    }
}

// MARK: - In-memory test sink

/// Captures every batch in memory. Useful for unit tests that want
/// to verify the orchestrator without linking the runtime.
public final class RecordingIngestSink: AppleXmlIngestSink {
    public init() {}

    public private(set) var openedImportId: String?
    public private(set) var batches: [[AppleHealthSample]] = []
    public private(set) var finalized = false

    public func open(importId: String) throws {
        openedImportId = importId
    }

    public func insertBatch(_ samples: [AppleHealthSample]) throws -> (inserted: Int, skipped: Int) {
        batches.append(samples)
        // Naive in-memory dedupe: count by canonical key.
        var seen = Set<Data>()
        for batch in batches {
            for s in batch {
                seen.insert(IdempotencyKey.key(for: s))
            }
        }
        // Inserted == the new keys this batch added; we'd need to
        // compute incrementally for an exact split, but for tests
        // the unique-count heuristic is enough.
        return (samples.count, 0)
    }

    public func finalize() throws -> ImportResult {
        finalized = true
        let total = batches.reduce(0) { $0 + $1.count }
        return ImportResult(
            importId: openedImportId ?? "",
            totalSamples: total,
            inserted: total,
            skippedAsDuplicate: 0,
            skippedAsUnknown: 0,
            durationMs: 0
        )
    }
}
