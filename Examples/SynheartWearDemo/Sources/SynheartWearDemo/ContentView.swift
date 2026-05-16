import SwiftUI
import SynheartWear

public struct ContentView: View {
    @ObservedObject var demo: DemoViewModel

    public init(demo: DemoViewModel) {
        self.demo = demo
    }

    public var body: some View {
        NavigationView {
            List(demo.providers) { entry in
                NavigationLink(entry.title) {
                    ProviderDetailView(entry: entry, demo: demo)
                }
            }
            .navigationTitle("Synheart Wear Demo")
        }
    }
}

public struct ProviderEntry: Identifiable {
    public let id = UUID()
    public let title: String
    public let adapter: DeviceAdapter
    public let status: String
}
