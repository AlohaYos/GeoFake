import CoreLocation
import XCTest
@testable import GeoFakeArrival

final class LogicTests: XCTestCase {
    func testNotificationText() {
        XCTAssertEqual(notificationText(spot: "Parking", entered: true, movement: .driving), "Arrived at Parking by car")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: true, movement: .walking), "Arrived at Cafe on foot")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: true, movement: .cycling), "Arrived at Cafe by bike")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: true, movement: .running), "Arrived at Cafe running")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: true, movement: .stationary), "Arrived at Cafe")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: true, movement: nil), "Arrived at Cafe")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: false, movement: .driving), "Left Cafe by car")
        XCTAssertEqual(notificationText(spot: "Cafe", entered: false, movement: nil), "Left Cafe")
    }

    func testMovementPriority() {
        XCTAssertEqual(Movement.from(automotive: true, cycling: false, running: false, walking: true, stationary: false), .driving)
        XCTAssertEqual(Movement.from(automotive: false, cycling: false, running: false, walking: true, stationary: true), .walking)
        XCTAssertNil(Movement.from(automotive: false, cycling: false, running: false, walking: false, stationary: false))
    }

    func testContains() {
        let spot = Spot(name: "A", latitude: 35.0, longitude: 139.0, radius: 100)
        // 0.0005 degrees of latitude is about 55 m; 0.002 is about 222 m
        XCTAssertTrue(spot.contains(CLLocationCoordinate2D(latitude: 35.0005, longitude: 139.0)))
        XCTAssertFalse(spot.contains(CLLocationCoordinate2D(latitude: 35.002, longitude: 139.0)))
    }
}
