// Ordinary Core Location / Core Motion code. Nothing here knows about GeoFake.
//
// - Location:  CLLocationUpdate.liveUpdates()                 (replayed by GeoPlayer through the OS location simulation)
// - Arrival:   CLMonitor circles on a device; a distance check on the simulator, which cannot monitor regions
// - Motion:    CMMotionActivityManager.startActivityUpdates()  (replayed by GeoFake)

import CoreLocation
import CoreMotion
import Foundation

/// The latest arrival, shown as a stamp animation or a "walk in" banner
struct RallyEvent: Identifiable, Equatable {
    let id = UUID()
    let spot: Spot
    let decision: StampDecision
    let movement: Movement?
}

@MainActor
@Observable
final class RallyModel {
    private(set) var spots: [Spot] = []
    private(set) var stamps: [Stamp] = []
    private(set) var insideIDs: Set<UUID> = []
    private(set) var location: CLLocation?
    private(set) var movement: Movement?
    private(set) var event: RallyEvent?

    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var session: AnyObject?
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var started = false

    private static var spotsURL: URL { URL.documentsDirectory.appending(path: "spots.json") }
    private static var stampsURL: URL { URL.documentsDirectory.appending(path: "stamps.json") }

    func start() {
        guard !started else { return }
        started = true
        spots = (try? JSONDecoder().decode([Spot].self, from: Data(contentsOf: Self.spotsURL))) ?? defaultSpots
        stamps = (try? JSONDecoder().decode([Stamp].self, from: Data(contentsOf: Self.stampsURL))) ?? []
        persistSpots()

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

    func stamp(for spot: Spot) -> Stamp? {
        stamps.first { $0.spotID == spot.id }
    }

    func add(_ spot: Spot) {
        spots.append(spot)
        persistSpots()
        #if targetEnvironment(simulator)
        checkByDistance()
        #else
        Task { await watch(spot) }
        #endif
    }

    func delete(_ spot: Spot) {
        spots.removeAll { $0.id == spot.id }
        stamps.removeAll { $0.spotID == spot.id }
        insideIDs.remove(spot.id)
        persistSpots()
        persistStamps()
        #if !targetEnvironment(simulator)
        Task { await monitor?.remove(spot.id.uuidString) }
        #endif
    }

    /// Empties the stamp book. Spots stay.
    func resetStamps() {
        stamps = []
        persistStamps()
    }

    private func persistSpots() {
        try? JSONEncoder().encode(spots).write(to: Self.spotsURL, options: .atomic)
    }

    private func persistStamps() {
        try? JSONEncoder().encode(stamps).write(to: Self.stampsURL, options: .atomic)
    }

    // MARK: Arrival

    #if targetEnvironment(simulator)
    private func checkByDistance() {
        guard let c = location?.coordinate else { return }
        let now = spotsContaining(c, in: spots)
        let entered = arrivals(before: insideIDs, after: now)
        insideIDs = now
        for id in entered { arrive(at: id) }
    }
    #else
    private func startMonitor() async {
        let monitor = await CLMonitor("GeoFakeStampRallySpots")
        self.monitor = monitor
        for spot in spots { await watch(spot) }
        do {
            for try await event in await monitor.events {
                guard let id = UUID(uuidString: event.identifier) else { continue }
                switch event.state {
                case .satisfied:
                    if insideIDs.insert(id).inserted { arrive(at: id) }
                case .unsatisfied:
                    insideIDs.remove(id)
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

    /// Clears the event once its animation or banner has been shown
    func dismiss(_ shown: RallyEvent) {
        if event?.id == shown.id { event = nil }
    }

    /// Uses the movement at the moment of the arrival
    private func arrive(at id: UUID) {
        guard let spot = spots.first(where: { $0.id == id }) else { return }
        let now = movement
        let decision = decideStamp(spotID: id, movement: now, collected: stamps)
        if decision == .stamp, let now {
            stamps.append(Stamp(spotID: id, spotName: spot.name, date: .now, movement: now))
            persistStamps()
        }
        if decision != .alreadyCollected {
            event = RallyEvent(spot: spot, decision: decision, movement: now)
        }
    }
}
