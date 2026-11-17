import SwiftUI
import UserNotifications
#if DEBUG
import GeoFake
#endif

/// Shows the banner and sound even while the app is in front
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct GeoFakeArrivalApp: App {
    private static let notificationDelegate = NotificationDelegate()
    // For automated checks: -SampleTab spots / history opens that tab
    @State private var tab = UserDefaults.standard.string(forKey: "SampleTab") ?? "map"
    @State private var model = ArrivalModel()

    init() {
        // This is the only line GeoFake needs.
        // Everything else uses plain Core Location and Core Motion, and receives
        // the motion that GeoPlayer for Mac replays.
        #if DEBUG
        GeoFake.start()
        #endif
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                MapScreen().tabItem { Label("Map", systemImage: "map") }.tag("map")
                SpotsScreen().tabItem { Label("Spots", systemImage: "mappin.circle") }.tag("spots")
                HistoryScreen().tabItem { Label("History", systemImage: "clock") }.tag("history")
            }
            .environment(model)
            .task { model.start() }
        }
    }
}
