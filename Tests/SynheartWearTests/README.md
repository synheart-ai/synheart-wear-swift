# Tests

Two test patterns coexist; pick the right one for what you're verifying.

## 1. Direct provider tests — fast unit tests

Most existing tests (`WhoopProviderTests`, `FitbitProviderTests`, `OuraProviderTests`, etc.) construct a provider with the public initializer and exercise its state transitions, OAuth flow shape, and local persistence directly. Fast, deterministic, no networking.

Use this pattern for:
- Provider state transitions (`isConnected()` before/after `connectWithCode`)
- OAuth flow shape (which API method is called, with what arguments)
- Local persistence (keychain writes)
- Error mapping that originates from the public API surface

## 2. `MockURLProtocol` — full-stack integration tests

`WhoopProviderMockServerTests` is the reference. Uses `MockURLProtocol` (declared in `NetworkClientTests.swift`) to register an in-process URLProtocol that intercepts every request a test-owned URLSession would normally send to the wire. This exercises the **complete** path: network → URLSession → JSON decode → SDK error mapping.

Use this pattern for:
- Real HTTP-status → `SynheartWearError` mapping (401 → `.tokenExpired`, 4xx, 5xx)
- Response-body decode against the actual `JSONDecoder`
- Header/auth handling that the `WearServiceAPI` struct hides
- Network failures (timeouts, malformed responses, dropped connections)

### Required test seams (already wired)

The pattern depends on three `internal` test-seam initializers:

```swift
// 1. URLSession injection on NetworkClient
NetworkClient(baseURL: ..., session: customSession, timeout: 3.0)

// 2. NetworkClient injection on WearServiceAPI
WearServiceAPI(networkClient: networkClient)

// 3. WearServiceAPI injection on each provider
WhoopProvider(appId: ..., baseUrl: ..., redirectUri: ..., api: api)
```

Plus a `simulateConnected(userId:)` on providers that lets a test jump past the OAuth handshake to data-fetching assertions.

### Wiring shape

```swift
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]   // intercept everything
config.timeoutIntervalForRequest = 3              // fail fast on misses
let session = URLSession(configuration: config)

let networkClient = NetworkClient(baseURL: baseURL, session: session, timeout: 3.0)
let api = WearServiceAPI(networkClient: networkClient)
let provider = WhoopProvider(appId: ..., baseUrl: baseURL, redirectUri: ..., api: api)
provider.simulateConnected(userId: "test-user")

MockURLProtocol.requestHandler = { request in
    let response = HTTPURLResponse(
        url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
    )!
    return (response, Data())
}

await XCTAssertThrowsAsync(try await provider.fetchSleep()) { error in
    if case SynheartWearError.tokenExpired = error { return }
    XCTFail(...)
}
```

### Lifecycle gotchas

- **Set a permissive default `requestHandler` in `setUp`** so housekeeping calls (e.g. `disconnect()` on the mock) don't trip MockURLProtocol's `XCTFail("Request handler not set")`. Override it with the specific response right before the assertion call.
- **In `tearDown`, drain provider state BEFORE clearing the handler** — otherwise `disconnect()`'s API call hits a not-set handler and XCTFails.

## Which to pick

| Question you're answering | Pattern |
|---|---|
| Does provider X transition state correctly? | Direct |
| Does HTTP 401 → expected `SynheartWearError`? | MockURLProtocol |
| Does provider parse this real JSON shape correctly? | MockURLProtocol |
| Does the OAuth flow store the right user_id in keychain? | Direct |
| Does provider survive a connection drop mid-stream? | MockURLProtocol |

When in doubt: start with direct for speed. Reach for MockURLProtocol when you specifically need to verify wire-level behavior.
