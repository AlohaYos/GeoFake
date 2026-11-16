// Ordinary Core Location / Core Motion code. Nothing here knows about GeoFake.
//
// - Location:  CLLocationUpdate.liveUpdates()                 (replayed by GeoPlayer through the OS location simulation)
// - Geofences: CLMonitor with three circles around a center  (the OS sees the replayed location, so it fires on a device)
// - Heading:   CLLocationManager.startUpdatingHeading()        (replayed by GeoFake)
// - Motion:    CMMotionActivityManager.startActivityUpdates()  (replayed by GeoFake)

import CoreLocation
import CoreMotion
import Foundation

struct LogLine: Identifiable {
    let id = UUID()
    let date: Date
    let symbol: String
    let text: String
}

struct Fence: Identifiable {
    let id: String
    let radius: CLLocationDistance
}

@MainActor
@Observable
final class SensorModel: NSObject, CLLocationManagerDelegate {
    static let fences = [Fence(id: "Nearby", radius: 100), Fence(id: "Block", radius: 500), Fence(id: "Town", radius: 1000)]

    private(set) var location: CLLocation?
    /// True heading if known, otherwise magnetic heading (degrees)
    private(set) var heading: Double?
    private(set) var activity: CMMotionActivity?
    private(set) var fenceCenter: CLLocationCoordinate2D?
    private(set) var insideFences: Set<String> = []
    private(set) var log: [LogLine] = []

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let motion = CMMotionActivityManager()
    @ObservationIgnored private var monitor: CLMonitor?
    @ObservationIgnored private var session: AnyObject?

    func start() {
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        // Since iOS 18, CLMonitor reports nothing ("unmonitored") unless a service session is held.
        if #available(iOS 18.0, *) { session = CLServiceSession(authorization: .whenInUse) }

        // Location
        Task {
            for try await update in CLLocationUpdate.liveUpdates() {
                guard let loc = update.location else { continue }
                location = loc
                if fenceCenter == nil { await setFenceCenter(loc.coordinate) }
                #if targetEnvironment(simulator)
                checkFencesByDistance(loc)
                #endif
            }
        }

        // Heading
        if CLLocationManager.headingAvailable() {
            manager.headingFilter = 1
            manager.startUpdatingHeading()
        }

        // Motion
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                guard let activity else { return }
                MainActor.assumeIsolated { self?.received(activity) }
            }
        }
    }

    // MARK: Geofences

    /// Puts the three fences around a new center (the first location, or the "Move fences here" button).
    func setFenceCenter(_ center: CLLocationCoordinate2D) async {
        fenceCenter = center
        insideFences = []
        add("mappin.and.ellipse", String(format: "Fences moved to %.5f, %.5f", center.latitude, center.longitude))
        #if !targetEnvironment(simulator)
        if monitor == nil {
            monitor = await CLMonitor("GeoFakeSampleFences")
            Task { await watchFences() }
        }
        guard let monitor else { return }
        for fence in Self.fences {
            await monitor.remove(fence.id)
            let condition = CLMonitor.CircularGeographicCondition(center: center, radius: fence.radius)
            await monitor.add(condition, identifier: fence.id, assuming: .unsatisfied)
        }
        #endif
    }

    private func watchFences() async {
        guard let monitor else { return }
        do {
            for try await event in await monitor.events {
                switch event.state {
                case .satisfied: setInside(event.identifier, true)
                case .unsatisfied: setInside(event.identifier, false)
                case .unmonitored: add("exclamationmark.triangle", "\(event.identifier) is not monitored\(Self.reason(event))")
                default: break
                }
            }
        } catch {
            add("exclamationmark.triangle", "Fence monitoring stopped: \(error.localizedDescription)")
        }
    }

    #if targetEnvironment(simulator)
    /// The simulator cannot monitor regions: CLMonitor reports "condition unsupported", and
    /// CLLocationManager.startMonitoring(for:) fails too. So on the simulator, compare the distance ourselves.
    private func checkFencesByDistance(_ loc: CLLocation) {
        guard let c = fenceCenter else { return }
        let d = loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
        for fence in Self.fences { setInside(fence.id, d <= fence.radius) }
    }
    #endif

    private func setInside(_ id: String, _ inside: Bool) {
        if inside, insideFences.insert(id).inserted {
            add("arrow.down.right.circle", "Entered \(id)")
        } else if !inside, insideFences.remove(id) != nil {
            add("arrow.up.left.circle", "Left \(id)")
        }
    }


    /// Why CLMonitor could not watch a condition (iOS 18 and later tell you)
    private static func reason(_ e: CLMonitor.Event) -> String {
        guard #available(iOS 18.0, *) else { return "" }
        let reasons: [(Bool, String)] = [
            (e.authorizationDenied, "location access denied"),
            (e.authorizationDeniedGlobally, "Location Services off"),
            (e.authorizationRestricted, "restricted"),
            (e.insufficientlyInUse, "app not in use"),
            (e.accuracyLimited, "precise location off"),
            (e.conditionUnsupported, "condition unsupported"),
            (e.conditionLimitExceeded, "too many conditions"),
            (e.persistenceUnavailable, "storage unavailable"),
            (e.serviceSessionRequired, "needs CLServiceSession"),
            (e.authorizationRequestInProgress, "waiting for permission"),
        ]
        let hits = reasons.filter(\.0).map(\.1)
        return hits.isEmpty ? "" : ": " + hits.joined(separator: ", ")
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let degrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        MainActor.assumeIsolated { heading = degrees }
    }

    // MARK: Motion

    private func received(_ a: CMMotionActivity) {
        activity = a
        add(Self.symbol(a), "\(Self.name(a))  (\(Self.confidence(a)) confidence)")
    }

    private func add(_ symbol: String, _ text: String) {
        log.insert(LogLine(date: .now, symbol: symbol, text: text), at: 0)
        if log.count > 200 { log.removeLast() }
    }

    static func name(_ a: CMMotionActivity?) -> String {
        guard let a else { return "—" }
        var names: [String] = []
        if a.automotive { names.append("Automotive") }
        if a.cycling { names.append("Cycling") }
        if a.running { names.append("Running") }
        if a.walking { names.append("Walking") }
        if a.stationary { names.append("Stationary") }
        if a.unknown { names.append("Unknown") }
        return names.isEmpty ? "None" : names.joined(separator: " + ")
    }

    static func symbol(_ a: CMMotionActivity?) -> String {
        guard let a else { return "questionmark" }
        if a.automotive { return "car.fill" }
        if a.cycling { return "bicycle" }
        if a.running { return "figure.run" }
        if a.walking { return "figure.walk" }
        if a.stationary { return "figure.stand" }
        return "questionmark"
    }

    static func confidence(_ a: CMMotionActivity) -> String {
        switch a.confidence {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        @unknown default: "?"
        }
    }
}
