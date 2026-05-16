import Foundation
import Combine
import SynheartWear

/// Demo view-model that wraps the SynheartWear SDK behind a small
/// facade so the example UI runs without real OAuth credentials.
///
/// Streams emit a synthetic BPM value drifting around 70 unless real
/// sources are wired up (BLE HRM is the easiest one — connect a chest
/// strap and you'll see live values).
@MainActor
public class DemoViewModel: ObservableObject {
    @Published public var providers: [ProviderEntry] = []
    @Published public var isStreaming = false

    private var sdk: SynheartWear?

    public init() {}

    public func bootstrap() async {
        let config = SynheartWearConfig(
            enabledAdapters: [.platformHealth, .bleHrm],
            appId: "demo-app"
        )
        let sdk = SynheartWear(config: config)
        do {
            try await sdk.initialize()
        } catch {
            // HealthKit may not be available in simulator — keep going
        }
        self.sdk = sdk

        providers = [
            ProviderEntry(title: "Whoop",   adapter: .whoop,    status: "Mocked (set appId for real OAuth)"),
            ProviderEntry(title: "Garmin",  adapter: .garmin,   status: "Mocked"),
            ProviderEntry(title: "Fitbit",  adapter: .fitbit,   status: "Mocked"),
            ProviderEntry(title: "Oura",    adapter: .oura,     status: "Mocked"),
            ProviderEntry(title: "BLE HRM", adapter: .bleHrm,   status: sdk.bleHrm == nil ? "Disabled" : "Ready (scan first)"),
            ProviderEntry(title: "Platform Health", adapter: .platformHealth, status: "Reads from HealthKit when authorized"),
        ]
    }

    /// Stream HR for a given adapter. Returns a real publisher when the
    /// SDK supports it (BLE HRM, platformHealth) and a synthetic
    /// publisher otherwise.
    public func streamHR(for adapter: DeviceAdapter) -> AnyPublisher<WearMetrics, Error> {
        if adapter == .bleHrm || adapter == .platformHealth, let sdk = sdk {
            return sdk.streamHR(interval: 1.0)
        }
        return SyntheticHRPublisher().eraseToAnyPublisher()
    }
}

/// Emits a slowly drifting BPM (~70 ± 5) every second so the UI has
/// something to display without real device hardware or cloud creds.
struct SyntheticHRPublisher: Publisher {
    typealias Output = WearMetrics
    typealias Failure = Error

    func receive<S>(subscriber: S) where S: Subscriber, S.Input == Output, S.Failure == Failure {
        let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
        let synth = timer.map { _ -> WearMetrics in
            let bpm = 70.0 + Double.random(in: -5...5)
            return WearMetrics(
                timestamp: Date(),
                deviceId: "demo",
                source: "synthetic",
                metrics: ["hr": bpm]
            )
        }
        .setFailureType(to: Error.self)
        synth.subscribe(subscriber)
    }
}
