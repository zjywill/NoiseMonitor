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

enum AppTab: Hashable {
    case hunt
    case spots
}

struct ContentView: View {
    @Environment(NoiseHunter.self) private var hunter
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.hunt
    @State private var tabBarHeight: CGFloat = 0

    var body: some View {
        TabView(selection: $tab) {
            HuntView()
                .tag(AppTab.hunt)
                .toolbar(.hidden, for: .tabBar)
            SpotsView()
                .tag(AppTab.spots)
                .toolbar(.hidden, for: .tabBar)
        }
        .environment(\.tabBarInset, tabBarHeight)
        .overlay(alignment: .bottom) {
            StickerTabBar(
                items: [
                    .init(value: .hunt, title: "测量", systemImage: "waveform", color: Theme.primary),
                    .init(value: .spots, title: "位置对比", systemImage: "mappin.and.ellipse", color: Theme.orange),
                ],
                selection: $tab
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
        }
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
