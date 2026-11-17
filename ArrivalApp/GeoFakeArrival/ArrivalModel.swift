// Ordinary Core Location / Core Motion / UserNotifications code. Nothing here knows about GeoFake.
//
// - Location:  CLLocationUpdate.liveUpdates()                 (replayed by GeoPlayer through the OS location simulation)
// - Enter/exit: CLMonitor circles on a device; a distance check on the simulator, which cannot monitor regions
// - Motion:    CMMotionActivityManager.startActivityUpdates()  (replayed by GeoFake)

import CoreLocation
import CoreMotion
import Foundation
import UserNotifications

@MainActor
@Observable
final class ArrivalModel {
    private(set) var spots: [Spot] = []
    private(set) var insideIDs: Set<UUID> = []
    private(set) var history: [HistoryEntry] = []
    private(set) var location: CLLocation?
    private(set) var movement: Movement?

    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var session: AnyObject?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var started = false

    private static var fileURL: URL {
        URL.documentsDirectory.appending(path: "spots.json")
    }

    func start() {
        guard !started else { return }
        started = true
        spots = (try? JSONDecoder().decode([Spot].self, from: Data(contentsOf: Self.fileURL))) ?? []

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        manager.requestWhenInUseAuthorization()
        // Since iOS 18, CLMonitor reports nothing unless a service session is held.
        if #available(iOS 18.0, *) { session = CLServiceSession(authorization: .whenInUse) }

        Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let loc = update.location else { continue }
                    location = loc
                    #if targetEnvironment(simulator)
                    checkByDistance()
                    #endif
                }
            } catch {
                print("Location updates stopped: \(error.localizedDescription)")
            }
        }

        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                MainActor.assumeIsolated { self?.movement = Movement.from(activity) }
            }
        }

        #if !targetEnvironment(simulator)
        Task { await startMonitor() }
        #endif
    }

    // MARK: Spots

    /// Adds a spot, or replaces the one with the same id
    func save(_ spot: Spot) {
        if let i = spots.firstIndex(where: { $0.id == spot.id }) { spots[i] = spot } else { spots.append(spot) }
        persist()
        #if targetEnvironment(simulator)
        checkByDistance()
        #else
        Task { await watch(spot) }
        #endif
    }

    func delete(_ spot: Spot) {
        spots.removeAll { $0.id == spot.id }
        insideIDs.remove(spot.id)
        persist()
        #if !targetEnvironment(simulator)
        Task { await monitor?.remove(spot.id.uuidString) }
        #endif
    }

    private func persist() {
        try? JSONEncoder().encode(spots).write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Enter / exit

    #if targetEnvironment(simulator)
    private func checkByDistance() {
        guard let c = location?.coordinate else { return }
        for spot in spots { setInside(spot.id, spot.contains(c)) }
    }
    #else
    private func startMonitor() async {
        let monitor = await CLMonitor("GeoFakeArrivalSpots")
        self.monitor = monitor
        for spot in spots { await watch(spot) }
        do {
            for try await event in await monitor.events {
                guard let id = UUID(uuidString: event.identifier) else { continue }
                switch event.state {
                case .satisfied: setInside(id, true)
                case .unsatisfied: setInside(id, false)
                default: break
                }
            }
        } catch {
            print("Monitoring stopped: \(error.localizedDescription)")
        }
    }

    private func watch(_ spot: Spot) async {
        guard let monitor else { return }
        await monitor.remove(spot.id.uuidString)
        let condition = CLMonitor.CircularGeographicCondition(center: spot.coordinate, radius: spot.radius)
        await monitor.add(condition, identifier: spot.id.uuidString, assuming: .unsatisfied)
    }
    #endif

    private func setInside(_ id: UUID, _ inside: Bool) {
        guard let spot = spots.first(where: { $0.id == id }) else { return }
        if inside, insideIDs.insert(id).inserted {
            record(spot, entered: true)
        } else if !inside, insideIDs.remove(id) != nil {
            record(spot, entered: false)
        }
    }

    /// Uses the movement at the moment of the crossing, for both the history and the notification
    private func record(_ spot: Spot, entered: Bool) {
        let now = movement
        history.insert(HistoryEntry(date: .now, spot: spot.name, entered: entered, movement: now), at: 0)
        if history.count > maxHistory { history.removeLast() }

        let content = UNMutableNotificationContent()
        content.title = notificationText(spot: spot.name, entered: entered, movement: now)
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
