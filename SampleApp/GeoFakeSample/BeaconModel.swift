// Ordinary iBeacon code with CLLocationManager. Nothing here knows about GeoFake.
//
// - Ranging:    startRangingBeacons(satisfying:) -> locationManager(_:didRange:satisfying:) about once a second
// - Monitoring: startMonitoring(for: CLBeaconRegion) -> didEnterRegion / didExitRegion / didDetermineState
//
// GeoFake replays beacons placed in GeoPlayer for Mac to exactly these delegate calls.
// (CLMonitor's BeaconIdentityCondition can't be replayed, so this sample uses CLLocationManager.)

import CoreLocation
import Foundation

@MainActor
@Observable
final class BeaconModel: NSObject, CLLocationManagerDelegate {
    /// The UUID GeoPlayer for Mac uses for new beacons by default
    static let defaultUUID = "6B1E9C1A-3F4D-4E2B-9A7C-5D8E0F1A2B3C"

    struct Seen: Identifiable {
        var id: String { "\(major)-\(minor)" }
        let major: Int
        let minor: Int
        let proximity: CLProximity
        let accuracy: Double
        let rssi: Int
    }

    var uuidText = BeaconModel.defaultUUID
    private(set) var running = false
    private(set) var beacons: [Seen] = []
    private(set) var inside: Bool?
    private(set) var log: [LogLine] = []

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var constraint: CLBeaconIdentityConstraint?
    @ObservationIgnored private var region: CLBeaconRegion?

    override init() {
        super.init()
        manager.delegate = self
    }

    func start() {
        guard !running, let uuid = UUID(uuidString: uuidText.trimmingCharacters(in: .whitespaces)) else {
            add("exclamationmark.triangle", "Enter a valid UUID")
            return
        }
        manager.requestWhenInUseAuthorization()
        guard CLLocationManager.isRangingAvailable() else {
            add("exclamationmark.triangle", "Beacon ranging is not available on this device")
            return
        }
        let c = CLBeaconIdentityConstraint(uuid: uuid)
        let r = CLBeaconRegion(beaconIdentityConstraint: c, identifier: "GeoFakeSampleBeacons")
        r.notifyOnEntry = true
        r.notifyOnExit = true
        constraint = c
        region = r
        manager.startMonitoring(for: r)
        manager.startRangingBeacons(satisfying: c)
        running = true
        add("dot.radiowaves.left.and.right", "Looking for \(uuid.uuidString.prefix(8))…")
    }

    func stop() {
        if let constraint { manager.stopRangingBeacons(satisfying: constraint) }
        if let region { manager.stopMonitoring(for: region) }
        running = false
        beacons = []
        inside = nil
        add("stop.circle", "Stopped")
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                                     satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        let seen = beacons.map {
            Seen(major: $0.major.intValue, minor: $0.minor.intValue, proximity: $0.proximity,
                 accuracy: $0.accuracy, rssi: $0.rssi)
        }
        MainActor.assumeIsolated { self.beacons = seen }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        MainActor.assumeIsolated { inside = true; add("arrow.down.right.circle", "Entered the beacon region") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        MainActor.assumeIsolated { inside = false; add("arrow.up.left.circle", "Left the beacon region") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        MainActor.assumeIsolated {
            if state == .inside { inside = true } else if state == .outside { inside = false }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
                                     error: Error) {
        let m = error.localizedDescription
        MainActor.assumeIsolated { add("exclamationmark.triangle", "Ranging failed: \(m)") }
    }

    private func add(_ symbol: String, _ text: String) {
        log.insert(LogLine(date: .now, symbol: symbol, text: text), at: 0)
        if log.count > 100 { log.removeLast() }
    }

    static func name(_ p: CLProximity) -> String {
        switch p {
        case .immediate: "Immediate"
        case .near: "Near"
        case .far: "Far"
        default: "Unknown"
        }
    }
}
