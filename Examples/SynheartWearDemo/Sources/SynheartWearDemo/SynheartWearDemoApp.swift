import SwiftUI
import SynheartWear

#if os(iOS)
@main
struct SynheartWearDemoApp: App {
    @StateObject private var demo = DemoViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(demo: demo)
                .task {
                    await demo.bootstrap()
                }
        }
    }
}
#endif
