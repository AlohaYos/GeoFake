// Pure logic: no Core Location monitoring, no UI. Covered by GeoFakeStampRallyTests.

import CoreLocation
import CoreMotion
import Foundation

// MARK: Constants

/// Radius choices (meters) offered when adding a spot
let radiusChoices: [Double] = [50, 100, 150, 300]
let defaultRadius: Double = 150

/// Symbols offered when adding a spot
let symbolChoices = ["star.fill", "camera.fill", "fork.knife", "cup.and.saucer.fill", "tree.fill", "building.columns.fill"]

// MARK: Spot

struct Spot: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double
    var radius: Double
    var symbol: String

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    /// Distance-based inside test. Used on the simulator, where CLMonitor cannot watch circles.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return here.distance(from: CLLocation(latitude: latitude, longitude: longitude)) <= radius
    }
}

/// The rally the app starts with: sights around central Tokyo
let defaultSpots: [Spot] = [
    Spot(name: "Tokyo Station", latitude: 35.6812, longitude: 139.7671, radius: defaultRadius, symbol: "tram.fill"),
    Spot(name: "Imperial Palace", latitude: 35.6852, longitude: 139.7528, radius: defaultRadius, symbol: "crown.fill"),
    Spot(name: "Tokyo Tower", latitude: 35.6586, longitude: 139.7454, radius: defaultRadius, symbol: "antenna.radiowaves.left.and.right"),
    Spot(name: "Senso-ji", latitude: 35.7148, longitude: 139.7967, radius: defaultRadius, symbol: "building.columns.fill"),
    Spot(name: "Ueno Park", latitude: 35.7156, longitude: 139.7745, radius: defaultRadius, symbol: "tree.fill"),
    Spot(name: "Shibuya Crossing", latitude: 35.6595, longitude: 139.7005, radius: defaultRadius, symbol: "figure.walk"),
]

/// Spots whose circle the coordinate is in
func spotsContaining(_ coordinate: CLLocationCoordinate2D, in spots: [Spot]) -> Set<UUID> {
    Set(spots.filter { $0.contains(coordinate) }.map(\.id))
}

/// Spots that were not inside before and are inside now: the arrivals
func arrivals(before: Set<UUID>, after: Set<UUID>) -> Set<UUID> {
    after.subtracting(before)
}

// MARK: Movement

enum Movement: String, Codable {
    case driving, cycling, running, walking, stationary

    /// nil when the flags say nothing useful (unknown). Same priority as the other samples.
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

    /// Walking and running earn a stamp
    var isOnFoot: Bool { self == .walking || self == .running }

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
}

// MARK: Stamps

struct Stamp: Identifiable, Codable, Equatable {
    var id = UUID()
    var spotID: UUID
    var spotName: String
    var date: Date
    var movement: Movement
}

/// What happens when you arrive at a spot
enum StampDecision: Equatable {
    /// Arrived on foot (walking or running): stamp it
    case stamp
    /// This spot is already in the book. Each spot is stamped once.
    case alreadyCollected
    /// Arrived by car
    case cameByCar
    /// Arrived some other way: cycling, standing still, or motion unknown
    case notOnFoot(Movement?)
}

/// Decides the stamp for an arrival, using the movement at the moment you entered the circle
func decideStamp(spotID: UUID, movement: Movement?, collected: [Stamp]) -> StampDecision {
    if collected.contains(where: { $0.spotID == spotID }) { return .alreadyCollected }
    guard let movement else { return .notOnFoot(nil) }
    if movement.isOnFoot { return .stamp }
    if movement == .driving { return .cameByCar }
    return .notOnFoot(movement)
}

/// The message shown when a stamp is refused. nil when nothing needs to be said.
func refusalText(_ decision: StampDecision) -> String? {
    switch decision {
    case .stamp, .alreadyCollected: nil
    case .cameByCar: "You came by car. Walk in to get the stamp!"
    case .notOnFoot(.cycling): "You rode in. Walk in to get the stamp!"
    case .notOnFoot: "Walk in to get the stamp!"
    }
}

/// "3 of 6 stamps"
func progressText(collected: Int, total: Int) -> String {
    collected == total && total > 0 ? "All \(total) stamps collected!" : "\(collected) of \(total) stamps"
}
