import SwiftUI

@main
struct NoiseMonitorApp: App {
    @State private var hunter = NoiseHunter(spotStore: SpotStore())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(hunter)
                .fontDesign(.rounded)
                .tint(Theme.primary)
        }
    }
}

struct ContentView: View {
    @Environment(NoiseHunter.self) private var hunter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // 先只做监测。找噪音的页面（HuntView、SpotsView）留着，等监测做扎实了再放回来
        MonitorView()
            .task { await hunter.start() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: Task { await hunter.start() }
                case .background: hunter.stop()
                default: break
                }
            }
    }
}
