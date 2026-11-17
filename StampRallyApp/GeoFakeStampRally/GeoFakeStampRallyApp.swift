import SwiftUI
#if DEBUG
import GeoFake
#endif

@main
struct GeoFakeStampRallyApp: App {
    // For automated checks: -SampleTab map opens that tab
    @State private var tab = UserDefaults.standard.string(forKey: "SampleTab") ?? "stamps"
    @State private var model = RallyModel()

    init() {
        // This is the only line GeoFake needs.
        // Everything else uses plain Core Location and Core Motion, and receives
        // the motion that GeoPlayer for Mac replays.
        #if DEBUG
        GeoFake.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                StampBookScreen().tabItem { Label("Stamps", systemImage: "seal") }.tag("stamps")
                MapScreen().tabItem { Label("Map", systemImage: "map") }.tag("map")
            }
            .overlay { ArrivalOverlay() }
            .environment(model)
            .task { model.start() }
        }
    }
}
