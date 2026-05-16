import XCTest
@testable import SynheartWear

/// Reference test: exercises a cloud provider through the full
/// URLSession → JSON-decode → SDK-error-mapping stack against an
/// in-process MockURLProtocol. Validates real wire behavior —
/// not just the WearServiceAPI struct boundary the existing
/// WhoopProviderTests cover.
///
/// Use this pattern when you need to verify:
///   - HTTP-status → SynheartWearError mapping (401, 4xx, 5xx)
///   - Response-body decode against the real JSONDecoder
///   - Header/auth handling that the WearServiceAPI struct hides
///   - Network failures (timeouts, malformed responses, transport errors)
///
/// For pure provider-logic tests (state transitions, OAuth flow shape),
/// stick with the existing WhoopProviderTests + MockK-style pattern.
///
/// MockURLProtocol itself is declared in `NetworkClientTests.swift`.
final class WhoopProviderMockServerTests: XCTestCase {

    private var provider: WhoopProvider!
    private let testBaseURL = URL(string: "https://api.test.example")!
    private let testAppId = "test-app-mockserver"

    override func setUp() async throws {
        try await super.setUp()

        // Build a URLSession whose requests are intercepted by
        // MockURLProtocol. NetworkClient gains this session via the
        // `internal init(baseURL:session:)` test seam; WearServiceAPI
        // accepts the pre-built NetworkClient via `init(networkClient:)`;
        // WhoopProvider accepts the WearServiceAPI via its internal
        // test-seam init.
        //
        // IMPORTANT: keep this protocolClasses ASSIGNMENT (not insertion)
        // so MockURLProtocol is the only protocol on the session and
        // no real network call slips past. Use ephemeral to avoid
        // cache/cookie state bleed between tests.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 3
        let session = URLSession(configuration: config)

        let networkClient = NetworkClient(baseURL: testBaseURL, session: session, timeout: 3.0)
        let api = WearServiceAPI(networkClient: networkClient)

        // Permissive default handler so housekeeping calls
        // (disconnect on the mock) don't trip MockURLProtocol's
        // "Request handler not set" XCTFail. Tests override this
        // with a specific response right before the assertion call.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        provider = WhoopProvider(
            appId: testAppId,
            baseUrl: testBaseURL,
            redirectUri: "testapp://oauth/callback",
            api: api
        )
        // Jump straight to a connected state — we don't need to
        // exercise the OAuth handshake for a fetchSleep test.
        provider.simulateConnected(userId: "test-user-42")
    }

    override func tearDown() async throws {
        // Drain provider state under the permissive default handler
        // BEFORE clearing it, otherwise disconnect's API call trips
        // MockURLProtocol's not-set XCTFail.
        try? await provider?.disconnect()
        MockURLProtocol.requestHandler = nil
        provider = nil
        try await super.tearDown()
    }

    /// Reference test:
    ///   - Stub a 401 response from the (mocked) Wear Service
    ///   - Call WhoopProvider.fetchSleep through the full HTTP stack
    ///   - Verify the SDK surfaces SynheartWearError.tokenExpired
    ///     (NetworkClient maps 401 → .unauthorized;
    ///      convertNetworkError(_:) maps .unauthorized → .tokenExpired)
    func testFetchSleepWraps401IntoTokenExpired() async throws {
        // Stub 401 for the fetchSleep call.
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data())
        }

        do {
            _ = try await provider.fetchSleep()
            XCTFail("Expected SynheartWearError.tokenExpired on 401, got success")
        } catch let error as SynheartWearError {
            if case .tokenExpired = error {
                // Expected — 401 maps through NetworkError.unauthorized to .tokenExpired.
            } else {
                XCTFail("Expected SynheartWearError.tokenExpired, got: \(error)")
            }
        }
    }
}
