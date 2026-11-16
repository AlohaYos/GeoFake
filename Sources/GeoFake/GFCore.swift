// GeoFake の中身。状態はすべてメインスレッドで触る。
//
// - アプリが方位・モーションを求めると（差し替えた start）、その相手を覚える
// - Mac から heading / motion が届くと、その種類の本物を止め（takeover）、偽の値を渡す
// - stop か、値を流していたつながりが切れると、本物の start を呼び直す（release）

#if os(iOS) && DEBUG
import CoreLocation
import CoreMotion
import Foundation
import GeoFakeWire
import os
import UIKit

let gfLog = Logger(subsystem: "GeoFake", category: "GeoFake")

@MainActor
final class GFCore {
    static let shared = GFCore()

    /// Mac が方位を流している間 true。この間は本物の方位を止めている
    private(set) var drivingHeading = false
    /// Mac がモーションを流している間 true
    private(set) var drivingMotion = false
    /// 値を流しているつながり。これが切れたら本物に戻す
    private var driver: ObjectIdentifier?

    private(set) var started = false
    private let server = GFServer()
    let beacons = GFBeaconCenter()

    // アプリが方位を求めている CLLocationManager（弱参照）
    private let headingManagers = NSHashTable<CLLocationManager>.weakObjects()
    private var lastDelivered: [ObjectIdentifier: Double] = [:]

    // アプリがモーションを求めている CMMotionActivityManager
    private final class ActivitySub {
        weak var manager: CMMotionActivityManager?
        let queue: OperationQueue
        let handler: CMMotionActivityHandler
        init(_ m: CMMotionActivityManager, _ q: OperationQueue, _ h: @escaping CMMotionActivityHandler) {
            manager = m; queue = q; handler = h
        }
    }
    private var activitySubs: [ObjectIdentifier: ActivitySub] = [:]

    // MARK: 起動

    func start() {
        guard !started else { return }
        installHooks()
        server.core = self
        server.start()
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GFCore.shared.server.stop(reason: "background") }
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { GFCore.shared.server.start() }
        }
    }

    /// 差し替えだけを入れる（待ち受けはしない）。テストからも呼ぶ
    func installHooks() {
        guard !started else { return }
        started = true
        let realHeading = CLLocationManager.headingAvailable()
        let realActivity = CMMotionActivityManager.isActivityAvailable()
        let realRanging = CLLocationManager.isRangingAvailable()
        let realMonitoring = CLLocationManager.isMonitoringAvailable(for: CLBeaconRegion.self)
        GFState.realRanging.withLock { $0 = realRanging }
        GFState.realBeaconMonitoring.withLock { $0 = realMonitoring }
        GFState.active.withLock { $0 = true }
        let failed = GFSwizzle.installAll()
        if failed.isEmpty {
            gfLog.notice("差し替えた（本物の headingAvailable=\(realHeading) isActivityAvailable=\(realActivity) isRangingAvailable=\(realRanging)）")
        } else {
            gfLog.error("差し替えに失敗: \(failed.joined(separator: ", "))")
        }
    }

    // MARK: Mac から届いた行

    /// from: 届いたつながり（テストでは nil）
    func receive(_ message: WireMessage, from connection: ObjectIdentifier?) {
        switch message {
        case .heading(let h):
            driver = connection
            takeOverHeading()
            deliver(GFHeading(magnetic: h.mag, trueHeading: h.trueHeading ?? -1, accuracy: h.acc ?? 0,
                              timestamp: Date(timeIntervalSince1970: h.t)))
        case .motion(let m):
            driver = connection
            takeOverMotion()
            deliver(makeActivity(m))
        case .stop(let s):
            if s.includes(.heading) { releaseHeading(reason: "stop") }
            if s.includes(.motion) { releaseMotion(reason: "stop") }
            if s.includes(.beacon) { beacons.release(reason: "stop") }
            if !drivingHeading && !drivingMotion && !beacons.driving { driver = nil }
        case .beacon(let b):
            driver = connection
            beacons.receive(b)
        case .hello, .ping, .pong:
            break
        }
    }

    /// つながりが切れた
    func connectionClosed(_ connection: ObjectIdentifier, reason: String) {
        guard connection == driver else { return }
        driver = nil
        releaseHeading(reason: reason)
        releaseMotion(reason: reason)
        beacons.release(reason: reason)
    }

    /// 待ち受けをやめた（裏に回った）
    func allConnectionsClosed(reason: String) {
        driver = nil
        releaseHeading(reason: reason)
        releaseMotion(reason: reason)
        beacons.release(reason: reason)
    }

    private func makeActivity(_ m: WireMotion) -> GFMotionActivity {
        var f = GFMotionActivity.Flags()
        for k in m.kinds {
            switch k {
            case .stationary: f.stationary = true
            case .walking: f.walking = true
            case .running: f.running = true
            case .automotive: f.automotive = true
            case .cycling: f.cycling = true
            case .unknown: f.unknown = true
            }
        }
        let conf: CMMotionActivityConfidence = switch m.conf {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
        return GFMotionActivity(flags: f, confidence: conf, startDate: Date(timeIntervalSince1970: m.t),
                                timestamp: ProcessInfo.processInfo.systemUptime)
    }

    // MARK: 渡す

    private func deliver(_ h: GFHeading) {
        for m in headingManagers.allObjects {
            // headingFilter を本物と同じに守る
            let key = ObjectIdentifier(m)
            if m.headingFilter != kCLHeadingFilterNone, let last = lastDelivered[key] {
                var d = abs(h.magneticHeading - last).truncatingRemainder(dividingBy: 360)
                if d > 180 { d = 360 - d }
                if d < m.headingFilter { continue }
            }
            lastDelivered[key] = h.magneticHeading
            m.delegate?.locationManager?(m, didUpdateHeading: h)
        }
    }

    private func deliver(_ a: GFMotionActivity) {
        activitySubs = activitySubs.filter { $0.value.manager != nil }
        for s in activitySubs.values {
            let box = GFUnchecked(value: (s.handler, a))
            s.queue.addOperation { box.value.0(box.value.1) }
        }
    }

    // MARK: 本物との切り替え

    private func takeOverHeading() {
        guard !drivingHeading else { return }
        drivingHeading = true
        for m in headingManagers.allObjects { m.gfRealStopUpdatingHeading() }
        gfLog.notice("方位を引き受けた（相手 \(self.headingManagers.count)）")
    }

    private func takeOverMotion() {
        guard !drivingMotion else { return }
        drivingMotion = true
        for s in activitySubs.values { s.manager?.gfRealStopActivityUpdates() }
        gfLog.notice("モーションを引き受けた（相手 \(self.activitySubs.count)）")
    }

    private func releaseHeading(reason: String) {
        guard drivingHeading else { return }
        drivingHeading = false
        lastDelivered.removeAll()
        for m in headingManagers.allObjects { m.gfRealStartUpdatingHeading() }
        gfLog.notice("方位を本物に戻した（\(reason)）")
    }

    private func releaseMotion(reason: String) {
        guard drivingMotion else { return }
        drivingMotion = false
        activitySubs = activitySubs.filter { $0.value.manager != nil }
        for s in activitySubs.values {
            s.manager?.gfRealStartActivityUpdates(to: s.queue, handler: s.handler)
        }
        gfLog.notice("モーションを本物に戻した（\(reason)）")
    }

    // MARK: 差し替えたメソッドから呼ばれる

    func appStartHeading(_ m: CLLocationManager) {
        headingManagers.add(m)
        if !drivingHeading { m.gfRealStartUpdatingHeading() }
    }

    func appStopHeading(_ m: CLLocationManager) {
        headingManagers.remove(m)
        lastDelivered.removeValue(forKey: ObjectIdentifier(m))
        m.gfRealStopUpdatingHeading()
    }

    func appStartActivity(_ m: CMMotionActivityManager, queue: OperationQueue,
                          handler: @escaping CMMotionActivityHandler) {
        activitySubs[ObjectIdentifier(m)] = ActivitySub(m, queue, handler)
        if !drivingMotion { m.gfRealStartActivityUpdates(to: queue, handler: handler) }
    }

    func appStopActivity(_ m: CMMotionActivityManager) {
        activitySubs.removeValue(forKey: ObjectIdentifier(m))
        m.gfRealStopActivityUpdates()
    }
}
#endif
