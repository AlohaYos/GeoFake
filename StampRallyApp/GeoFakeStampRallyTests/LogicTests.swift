import CoreLocation
import XCTest
@testable import GeoFakeStampRally

final class LogicTests: XCTestCase {
    private let spotID = UUID()

    private func stamp(_ id: UUID) -> Stamp {
        Stamp(spotID: id, spotName: "A", date: .now, movement: .walking)
    }

    func testOnFootGetsStamp() {
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .walking, collected: []), .stamp)
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .running, collected: []), .stamp)
    }

    func testCarIsRefused() {
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .driving, collected: []), .cameByCar)
        XCTAssertEqual(refusalText(.cameByCar), "You came by car. Walk in to get the stamp!")
    }

    func testOtherMovementsAreRefused() {
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .cycling, collected: []), .notOnFoot(.cycling))
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .stationary, collected: []), .notOnFoot(.stationary))
        XCTAssertEqual(decideStamp(spotID: spotID, movement: nil, collected: []), .notOnFoot(nil))
        XCTAssertEqual(refusalText(.notOnFoot(.cycling)), "You rode in. Walk in to get the stamp!")
        XCTAssertEqual(refusalText(.notOnFoot(nil)), "Walk in to get the stamp!")
        XCTAssertNil(refusalText(.stamp))
        XCTAssertNil(refusalText(.alreadyCollected))
    }

    func testEachSpotIsStampedOnce() {
        // Already stamped: nothing more, whichever way you arrive
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .walking, collected: [stamp(spotID)]), .alreadyCollected)
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .driving, collected: [stamp(spotID)]), .alreadyCollected)
        // A stamp from another spot does not count
        XCTAssertEqual(decideStamp(spotID: spotID, movement: .walking, collected: [stamp(UUID())]), .stamp)
    }

    func testMovementPriority() {
        // A car with someone walking inside is still a car
        XCTAssertEqual(Movement.from(automotive: true, cycling: false, running: false, walking: true, stationary: false), .driving)
        XCTAssertEqual(Movement.from(automotive: false, cycling: false, running: false, walking: true, stationary: true), .walking)
        XCTAssertNil(Movement.from(automotive: false, cycling: false, running: false, walking: false, stationary: false))
    }

    func testContainsAndArrivals() {
        let a = Spot(name: "A", latitude: 35.0, longitude: 139.0, radius: 100, symbol: "star.fill")
        let b = Spot(name: "B", latitude: 35.01, longitude: 139.0, radius: 100, symbol: "star.fill")
        // 0.0005 degrees of latitude is about 55 m; 0.002 is about 222 m
        XCTAssertTrue(a.contains(CLLocationCoordinate2D(latitude: 35.0005, longitude: 139.0)))
        XCTAssertFalse(a.contains(CLLocationCoordinate2D(latitude: 35.002, longitude: 139.0)))

        let inA = spotsContaining(CLLocationCoordinate2D(latitude: 35.0005, longitude: 139.0), in: [a, b])
        XCTAssertEqual(inA, [a.id])
        // Entering counts once; staying inside is not a new arrival
        XCTAssertEqual(arrivals(before: [], after: inA), [a.id])
        XCTAssertEqual(arrivals(before: inA, after: inA), [])
        // Leaving and coming back is a new arrival
        XCTAssertEqual(arrivals(before: [], after: [a.id, b.id]), [a.id, b.id])
    }

    func testProgressText() {
        XCTAssertEqual(progressText(collected: 2, total: 6), "2 of 6 stamps")
        XCTAssertEqual(progressText(collected: 6, total: 6), "All 6 stamps collected!")
        XCTAssertEqual(progressText(collected: 0, total: 0), "0 of 0 stamps")
    }

    func testStampRoundTrip() throws {
        let original = [stamp(spotID)]
        let decoded = try JSONDecoder().decode([Stamp].self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }
}
