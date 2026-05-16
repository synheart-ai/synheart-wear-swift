import SwiftUI
import Combine
import SynheartWear

public struct ProviderDetailView: View {
    let entry: ProviderEntry
    @ObservedObject var demo: DemoViewModel

    @State private var bpm: Double?
    @State private var subscription: AnyCancellable?

    public var body: some View {
        VStack(spacing: 16) {
            Text(entry.title).font(.title2)
            Text(entry.status).foregroundColor(.secondary)

            if let bpm = bpm {
                Text("\(Int(bpm)) BPM").font(.system(size: 56, weight: .bold))
            } else {
                Text("— BPM").font(.system(size: 56, weight: .bold)).foregroundColor(.secondary)
            }

            Button(demo.isStreaming ? "Stop" : "Start stream") {
                if demo.isStreaming {
                    subscription?.cancel()
                    subscription = nil
                    demo.isStreaming = false
                    bpm = nil
                } else {
                    demo.isStreaming = true
                    subscription = demo.streamHR(for: entry.adapter)
                        .receive(on: DispatchQueue.main)
                        .sink(
                            receiveCompletion: { _ in
                                demo.isStreaming = false
                            },
                            receiveValue: { metrics in
                                bpm = metrics.getMetric(.hr)
                            }
                        )
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
    }
}
