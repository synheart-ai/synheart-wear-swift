// SPDX-License-Identifier: Apache-2.0
//
// Streaming SAX parser for Apple Health's `export.xml`.
//
// Why streaming: a 5-year export.xml can be 500MB+ unzipped. Loading
// it as a DOM blows past the 200MB memory budget quoted in the RFC.
//
// `XMLParser` is the Foundation wrapper around libxml2's SAX
// interface — it's available on every Apple platform (iOS, macOS,
// watchOS, tvOS) without a third-party dependency.

import Foundation

/// Parses `export.xml` and emits one `AppleHealthSample` per record
/// via the supplied closure. Returns the total number of records
/// observed in the file (including those we skipped as unknown).
public final class AppleHealthXmlParser: NSObject, XMLParserDelegate {

    /// Closure invoked for each successfully-mapped sample.
    public typealias SampleHandler = (AppleHealthSample) -> Void

    /// Closure invoked when an element was a known record type but
    /// could not be mapped (unknown sleep enum, missing required
    /// attribute). Useful for diagnostics; no obligation to act.
    public typealias UnknownHandler = (_ type: String, _ reason: String) -> Void

    private let onSample: SampleHandler
    private let onUnknown: UnknownHandler

    /// Total number of `<Record>` elements observed, including those
    /// we did not emit (unknown type, malformed, etc.).
    public private(set) var recordsSeen: Int = 0

    /// Number of records emitted to the sample handler.
    public private(set) var samplesEmitted: Int = 0

    /// Number of records skipped because the type was unknown or the
    /// record was malformed.
    public private(set) var samplesSkipped: Int = 0

    private var parseError: AppleHealthXmlError?

    /// ISO-8601-like formatter matching Apple's `2026-04-29 22:14:33 -0700`.
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    public init(
        onSample: @escaping SampleHandler,
        onUnknown: @escaping UnknownHandler = { _, _ in }
    ) {
        self.onSample = onSample
        self.onUnknown = onUnknown
        super.init()
    }

    /// Parse `xmlURL`. Returns when parsing completes (successfully
    /// or with an error). The parser is single-shot — create a new
    /// instance for each import.
    public func parse(xmlURL: URL) throws {
        guard let parser = XMLParser(contentsOf: xmlURL) else {
            throw AppleHealthXmlError.xmlNotFound
        }
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false

        let ok = parser.parse()
        if let err = parseError {
            throw err
        }
        if !ok, let nsError = parser.parserError {
            throw AppleHealthXmlError.parseFailed(
                line: parser.lineNumber,
                column: parser.columnNumber,
                message: nsError.localizedDescription
            )
        }
    }

    // MARK: - XMLParserDelegate

    public func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        guard elementName == "Record" else { return }
        recordsSeen += 1

        guard let typeStr = attributeDict["type"] else {
            samplesSkipped += 1
            onUnknown("<missing type>", "no type attribute")
            return
        }
        guard let metric = AppleHealthMetric.fromAppleIdentifier(typeStr) else {
            samplesSkipped += 1
            // Don't call onUnknown for every unmapped HK identifier —
            // most exports contain dozens of types we deliberately
            // ignore. Logging would be deafening.
            return
        }

        guard
            let startStr = attributeDict["startDate"],
            let endStr = attributeDict["endDate"],
            let startDate = dateFormatter.date(from: startStr),
            let endDate = dateFormatter.date(from: endStr)
        else {
            samplesSkipped += 1
            onUnknown(typeStr, "unparseable startDate/endDate")
            return
        }

        let startMs = Int64((startDate.timeIntervalSince1970 * 1000).rounded())
        let endMs = Int64((endDate.timeIntervalSince1970 * 1000).rounded())
        let source = attributeDict["sourceName"] ?? "unknown"

        let value: AppleHealthSample.Value
        switch metric {
        case .sleepStage:
            guard
                let raw = attributeDict["value"],
                let stage = SleepStage.fromAppleValue(raw)
            else {
                samplesSkipped += 1
                onUnknown(typeStr, "unknown sleep value: \(attributeDict["value"] ?? "<nil>")")
                return
            }
            value = .sleepStage(stage)
        default:
            guard
                let raw = attributeDict["value"],
                let v = Double(raw),
                v.isFinite
            else {
                samplesSkipped += 1
                onUnknown(typeStr, "unparseable numeric value: \(attributeDict["value"] ?? "<nil>")")
                return
            }
            value = .quantity(v)
        }

        let sample = AppleHealthSample(
            metric: metric,
            source: source,
            startMs: startMs,
            endMs: endMs,
            value: value
        )
        samplesEmitted += 1
        onSample(sample)
    }

    public func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        let nsErr = parseError as NSError
        self.parseError = .parseFailed(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: nsErr.localizedDescription
        )
    }
}
