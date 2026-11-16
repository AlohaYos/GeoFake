import SwiftUI
#if DEBUG
import GeoFake
#endif

@main
struct GeoFakeSampleApp: App {
    // For automated checks: -SampleTab beacons opens the Beacons tab
    @State private var tab = UserDefaults.standard.string(forKey: "SampleTab") ?? "map"

    init() {
        // This is the only line GeoFake needs.
        // Everything else uses plain Core Location and Core Motion, and receives
        // the heading and motion that GeoPlayer for Mac replays.
        #if DEBUG
        GeoFake.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                ContentView().tabItem { Label("Map", systemImage: "map") }.tag("map")
                BeaconView().tabItem { Label("Beacons", systemImage: "dot.radiowaves.left.and.right") }.tag("beacons")
            }
        }
    }
}
