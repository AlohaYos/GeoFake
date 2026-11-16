// GeoFake の中身の試験。iOS シミュレータで回す（macOS では GeoFake が空なので何もしない）。
//   xcodebuild test -scheme GeoFake-Package -destination 'platform=iOS Simulator,id=<UDID>'
// 待ち受けはせず、差し替えだけを入れて、Mac から届いた行を直接渡す。

#if os(iOS) && DEBUG
import CoreLocation
import CoreMotion
import Foundation
import os
import Testing
import GeoFakeWire
@testable import GeoFake

private final class HeadingSpy: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var headings: [CLHeading] = []
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headings.append(newHeading)
    }
}

private final class ActivitySpy: @unchecked Sendable {
    var activities: [CMMotionActivity] = []
}

@MainActor
@Suite("GeoFake の受け渡し", .serialized)
struct GeoFakeDeliveryTests {
    init() {
        GFCore.shared.installHooks()
        GFCore.shared.receive(.stop(WireStop()), from: nil)
    }

    @Test("シミュレータでも headingAvailable と isActivityAvailable が true になる")
    func availability() {
        #expect(CLLocationManager.headingAvailable())
        #expect(CMMotionActivityManager.isActivityAvailable())
    }

    @Test("方位が delegate に届き、stop で本物に戻る")
    func headingDelivered() {
        let m = CLLocationManager()
        let spy = HeadingSpy()
        m.delegate = spy
        m.headingFilter = kCLHeadingFilterNone
        m.startUpdatingHeading()
        GFCore.shared.receive(.heading(WireHeading(t: 1_763_256_000.25, mag: 21.3, trueHeading: 28.9, acc: 15)), from: nil)
        #expect(spy.headings.count == 1)
        let h = spy.headings[0]
        #expect(h.magneticHeading == 21.3)
        #expect(h.trueHeading == 28.9)
        #expect(h.headingAccuracy == 15)
        #expect(h.timestamp == Date(timeIntervalSince1970: 1_763_256_000.25))
        #expect(GFCore.shared.drivingHeading)
        // 真北が無ければ負の値
        GFCore.shared.receive(.heading(WireHeading(t: 1_763_256_000.5, mag: 30)), from: nil)
        #expect(spy.headings.last?.trueHeading == -1)
        // stop(motion) では方位は止まらない
        GFCore.shared.receive(.stop(WireStop(targets: [.motion])), from: nil)
        #expect(GFCore.shared.drivingHeading)
        GFCore.shared.receive(.stop(WireStop(targets: [.heading])), from: nil)
        #expect(!GFCore.shared.drivingHeading)
        m.stopUpdatingHeading()
        // 止めた相手には届かない
        GFCore.shared.receive(.heading(WireHeading(t: 1, mag: 1)), from: nil)
        #expect(spy.headings.count == 2)
    }

    @Test("headingFilter を本物と同じに守る")
    func headingFilter() {
        let m = CLLocationManager()
        let spy = HeadingSpy()
        m.delegate = spy
        m.headingFilter = 10
        m.startUpdatingHeading()
        for mag in [0.0, 5.0, 12.0, 355.0, 340.0] {
            GFCore.shared.receive(.heading(WireHeading(t: 1, mag: mag)), from: nil)
        }
        // 0 → 5（差5、捨てる）→ 12（差12）→ 355（差17）→ 340（差15）
        #expect(spy.headings.map(\.magneticHeading) == [0, 12, 355, 340])
        m.stopUpdatingHeading()
    }

    @Test("モーションが handler に届く")
    func motionDelivered() {
        let m = CMMotionActivityManager()
        let spy = ActivitySpy()
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        // 本物と同じく、handler は渡したキュー（メインではない）の上で呼ばれる。
        // ここは @MainActor の中なので、@Sendable を付けないと handler がメインに縛られ、
        // 本物の CoreMotion でも Swift 6 の実行時の検査で落ちる（アプリ側の書き方の問題）
        let onQueue = OSAllocatedUnfairLock(initialState: [Bool]())
        m.startActivityUpdates(to: q) { @Sendable a in
            onQueue.withLock { $0.append(OperationQueue.current === q && !Thread.isMainThread) }
            if let a { spy.activities.append(a) }
        }
        GFCore.shared.receive(.motion(WireMotion(t: 1_763_256_001, kinds: [.walking, .automotive], conf: .medium)), from: nil)
        q.waitUntilAllOperationsAreFinished()
        #expect(onQueue.withLock { $0 } == [true])
        #expect(spy.activities.count == 1)
        let a = spy.activities[0]
        #expect(a.walking && a.automotive && !a.running && !a.stationary && !a.cycling && !a.unknown)
        #expect(a.confidence == .medium)
        #expect(a.startDate == Date(timeIntervalSince1970: 1_763_256_001))
        #expect(GFCore.shared.drivingMotion)
        m.stopActivityUpdates()
        GFCore.shared.receive(.stop(WireStop()), from: nil)
        #expect(!GFCore.shared.drivingMotion)
    }

    @Test("値を流していたつながりが切れたときだけ本物に戻る")
    func connectionClosed() {
        let driver = ObjectIdentifier(NSObject.self)
        let other = ObjectIdentifier(NSString.self)
        GFCore.shared.receive(.heading(WireHeading(t: 1, mag: 1)), from: driver)
        GFCore.shared.receive(.motion(WireMotion(t: 1, kinds: [.walking])), from: driver)
        GFCore.shared.connectionClosed(other, reason: "試験")
        #expect(GFCore.shared.drivingHeading && GFCore.shared.drivingMotion)
        GFCore.shared.connectionClosed(driver, reason: "試験")
        #expect(!GFCore.shared.drivingHeading && !GFCore.shared.drivingMotion)
    }
}

@Suite("偽の値のふるまい")
struct GeoFakeValueTests {
    @Test("CLHeading のサブクラス: copy・比較・hash・Set・アーカイブ")
    func heading() throws {
        let h = GFHeading(magnetic: 10, trueHeading: 17, accuracy: 5, timestamp: Date(timeIntervalSince1970: 100))
        let c = h.copy() as! CLHeading
        #expect(c.magneticHeading == 10)
        #expect(c.isEqual(h) && h.isEqual(c))
        #expect(c.hash == h.hash)
        #expect(Set<CLHeading>([h, c]).count == 1)
        #expect(h.description.hasPrefix("magneticHeading 10.00 trueHeading 17.00 accuracy 5.00"))
        let d = try NSKeyedArchiver.archivedData(withRootObject: h, requiringSecureCoding: true)
        let back = try NSKeyedUnarchiver.unarchivedObject(ofClass: CLHeading.self, from: d)
        #expect(back?.isEqual(h) == true)
    }

    @Test("CMMotionActivity のサブクラス: copy・比較・アーカイブ")
    func activity() throws {
        var f = GFMotionActivity.Flags()
        f.running = true
        let a = GFMotionActivity(flags: f, confidence: .high, startDate: Date(timeIntervalSince1970: 100), timestamp: 5)
        let c = a.copy() as! CMMotionActivity
        #expect(c.running && c.isEqual(a))
        #expect(Set<CMMotionActivity>([a, c]).count == 1)
        #expect(a.description.contains("running,1"))
        let d = try NSKeyedArchiver.archivedData(withRootObject: a, requiringSecureCoding: true)
        let back = try NSKeyedUnarchiver.unarchivedObject(ofClass: CMMotionActivity.self, from: d)
        #expect(back?.isEqual(a) == true)
    }
}

private final class BeaconSpy: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var ranged: [[CLBeacon]] = []
    var events: [String] = []
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                         satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        ranged.append(beacons)
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { events.append("enter:\(region.identifier)") }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { events.append("exit:\(region.identifier)") }
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        events.append("state:\(region.identifier):\(state.rawValue)")
    }
}

@MainActor
@Suite("GeoFake のビーコン", .serialized)
struct GeoFakeBeaconTests {
    static let uuid = UUID(uuidString: "6B1E9C1A-3F4D-4E2B-9A7C-5D8E0F1A2B3C")!
    init() { GFCore.shared.installHooks() }

    final class Clock { var t = Date(timeIntervalSince1970: 1_800_000_000) }

    @Test("シミュレータでも isRangingAvailable と CLBeaconRegion の監視が使えると返す")
    func availability() {
        #expect(CLLocationManager.isRangingAvailable())
        #expect(CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self))
    }

    @Test("beacon の行が didRange に GFBeacon で届き、合わないものは入らない。届かなくなれば空")
    func ranging() {
        let clock = Clock()
        let center = GFBeaconCenter(now: { clock.t })
        let m = CLLocationManager()
        let spy = BeaconSpy()
        m.delegate = spy
        let c = CLBeaconIdentityConstraint(uuid: Self.uuid, major: 1)
        center.appStartRanging(m, c)
        center.receive(WireBeacon(uuid: Self.uuid.uuidString, major: 1, minor: 7, proximity: .near, accuracy: 2.5, rssi: -70))
        center.receive(WireBeacon(uuid: Self.uuid.uuidString, major: 2, minor: 1, proximity: .far, accuracy: 9, rssi: -88))
        center.tick()
        let got = spy.ranged.last ?? []
        #expect(got.count == 1)
        #expect(got.first?.minor == 7 && got.first?.proximity == .near && got.first?.accuracy == 2.5 && got.first?.rssi == -70)
        #expect(got.first is GFBeacon)
        clock.t += GFBeaconCenter.goneAfter + 0.1
        center.tick()
        #expect(spy.ranged.last?.isEmpty == true)
        center.release(reason: "試験")
        #expect(!center.driving)
    }

    @Test("CLBeaconRegion の監視: 現れたら入る、居なくなったら出る。release でも出る")
    func regions() {
        let clock = Clock()
        let center = GFBeaconCenter(now: { clock.t })
        let m = CLLocationManager()
        let spy = BeaconSpy()
        m.delegate = spy
        let region = CLBeaconRegion(uuid: Self.uuid, major: 1, identifier: "shop")
        center.appStartMonitoring(m, region)
        center.receive(WireBeacon(uuid: Self.uuid.uuidString, major: 1, minor: 2, proximity: .immediate, accuracy: 0.3, rssi: -50))
        #expect(spy.events == ["state:shop:1", "enter:shop"])
        clock.t += GFBeaconCenter.goneAfter + 0.1
        center.tick()
        #expect(spy.events.suffix(2) == ["state:shop:2", "exit:shop"])
        center.receive(WireBeacon(uuid: Self.uuid.uuidString, major: 1, minor: 2))
        #expect(spy.events.last == "enter:shop")
        center.release(reason: "試験")
        #expect(spy.events.last == "exit:shop")
    }

    @Test("CLBeacon のサブクラス: copy・比較・アーカイブ・description")
    func beaconValue() throws {
        let b = GFBeacon(uuid: Self.uuid, major: 3, minor: 4, proximity: .far, accuracy: 12, rssi: -90,
                         timestamp: Date(timeIntervalSince1970: 100))
        let c = b.copy() as! CLBeacon
        #expect(c.isEqual(b) && c.major == 3)
        #expect(b.description.contains("major:3") && b.description.contains("Far"))
        let d = try NSKeyedArchiver.archivedData(withRootObject: b, requiringSecureCoding: true)
        let back = try NSKeyedUnarchiver.unarchivedObject(ofClass: CLBeacon.self, from: d)
        #expect(back?.isEqual(b) == true)
    }
}
#endif
