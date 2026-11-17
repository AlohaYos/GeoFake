// Pure logic: no Core Location monitoring, no UI. Covered by GeoFakeArrivalTests.

import CoreLocation
import CoreMotion
import Foundation

// MARK: Constants

/// Radius choices (meters) offered when adding or editing a spot
let radiusChoices: [Double] = [50, 100, 200, 500]
let defaultRadius: Double = 100
let maxHistory = 200

// MARK: Spot

struct Spot: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// Distance-based inside test. Used on the simulator, where CLMonitor cannot watch circles.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: CLLocation(latitude: latitude, longitude: longitude)) <= radius
    }
}

// MARK: Movement

enum Movement: String, Codable {
    case driving, cycling, running, walking, stationary

    /// nil when the flags say nothing useful (unknown). Same priority as the sample app.
    static func from(automotive: Bool, cycling: Bool, running: Bool, walking: Bool, stationary: Bool) -> Movement? {
        if automotive { return .driving }
        if cycling { return .cycling }
        if running { return .running }
        if walking { return .walking }
        if stationary { return .stationary }
        return nil
    }

    static func from(_ a: CMMotionActivity?) -> Movement? {
        guard let a else { return nil }
        return from(automotive: a.automotive, cycling: a.cycling, running: a.running, walking: a.walking, stationary: a.stationary)
    }

    var title: String {
        switch self {
        case .driving: "Driving"
        case .cycling: "Cycling"
        case .running: "Running"
        case .walking: "Walking"
        case .stationary: "Stationary"
        }
    }

    var symbol: String {
        switch self {
        case .driving: "car.fill"
        case .cycling: "bicycle"
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .stationary: "figure.stand"
        }
    }

    /// Ending that follows the spot name, e.g. "Arrived at Parking by car"
    fileprivate var how: String {
        switch self {
        case .driving: " by car"
        case .cycling: " by bike"
        case .running: " running"
        case .walking: " on foot"
        case .stationary: ""
        }
    }
}

// MARK: Notification text

/// "Arrived at Parking by car", "Left Cafe on foot". Without a known movement: "Arrived at Cafe".
func notificationText(spot: String, entered: Bool, movement: Movement?) -> String {
    (entered ? "Arrived at " : "Left ") + spot + (movement?.how ?? "")
}

// MARK: History

struct HistoryEntry: Identifiable {
    let id = UUID()
    let date: Date
    let spot: String
    let entered: Bool
    let movement: Movement?
}
