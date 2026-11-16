// 公開メソッドの差し替え（method_exchangeImplementations）。非公開 API は使わない。
// 差し替えたあとは gf_xxx を呼ぶと本物が動く。

#if os(iOS) && DEBUG
import CoreLocation
import CoreMotion
import Foundation
import ObjectiveC
import os

/// 送り先の型が Sendable でなくても、メインスレッドへ運ぶための入れ物
struct GFUnchecked<T>: @unchecked Sendable {
    let value: T
}

enum GFMain {
    /// メインスレッドで動かす。今メインなら、その場で動かす（順番を崩さないため）
    static func run(_ f: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { f() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { f() } }
        }
    }
}

/// start() 済みか。クラスメソッドの差し替え（どのスレッドからも呼ばれる）が見る
enum GFState {
    static let active = OSAllocatedUnfairLock(initialState: false)
    /// 本物のビーコンのレンジング・監視が使えるか（差し替える前に調べる。シミュレータでは false）
    static let realRanging = OSAllocatedUnfairLock(initialState: false)
    static let realBeaconMonitoring = OSAllocatedUnfairLock(initialState: false)
}

extension CLLocationManager {
    @objc dynamic func gf_startUpdatingHeading() {
        let m = GFUnchecked(value: self)
        GFMain.run { GFCore.shared.appStartHeading(m.value) }
    }

    @objc dynamic func gf_stopUpdatingHeading() {
        let m = GFUnchecked(value: self)
        GFMain.run { GFCore.shared.appStopHeading(m.value) }
    }

    @objc dynamic class func gf_headingAvailable() -> Bool {
        GFState.active.withLock { $0 } ? true : gf_headingAvailable()
    }

    // 本物を呼ぶ口（差し替えたあとは gf_ が本物）
    func gfRealStartUpdatingHeading() { gf_startUpdatingHeading() }
    func gfRealStopUpdatingHeading() { gf_stopUpdatingHeading() }

    // MARK: ビーコン（GFBeaconCenter）

    @objc(gf_startRangingBeaconsSatisfyingConstraint:) dynamic func gf_startRangingBeacons(satisfying c: CLBeaconIdentityConstraint) {
        let box = GFUnchecked(value: (self, c))
        GFMain.run { GFCore.shared.beacons.appStartRanging(box.value.0, box.value.1) }
    }

    @objc(gf_stopRangingBeaconsSatisfyingConstraint:) dynamic func gf_stopRangingBeacons(satisfying c: CLBeaconIdentityConstraint) {
        let box = GFUnchecked(value: (self, c))
        GFMain.run { GFCore.shared.beacons.appStopRanging(box.value.0, box.value.1) }
    }

    @objc(gf_startMonitoringForRegion:) dynamic func gf_startMonitoring(for region: CLRegion) {
        if let b = region as? CLBeaconRegion {
            let box = GFUnchecked(value: (self, b))
            GFMain.run { GFCore.shared.beacons.appStartMonitoring(box.value.0, box.value.1) }
            // 本物が使えない（シミュレータ）ときは本物を呼ばない（呼ぶと monitoringDidFail が届く）
            guard GFState.realBeaconMonitoring.withLock({ $0 }) else { return }
        }
        gf_startMonitoring(for: region)
    }

    @objc(gf_stopMonitoringForRegion:) dynamic func gf_stopMonitoring(for region: CLRegion) {
        if region is CLBeaconRegion {
            let box = GFUnchecked(value: (self, region))
            GFMain.run { GFCore.shared.beacons.appStopMonitoring(box.value.0, box.value.1) }
            guard GFState.realBeaconMonitoring.withLock({ $0 }) else { return }
        }
        gf_stopMonitoring(for: region)
    }

    @objc(gf_requestStateForRegion:) dynamic func gf_requestState(for region: CLRegion) {
        if let b = region as? CLBeaconRegion {
            let box = GFUnchecked(value: (self, b))
            let answered: Bool = Thread.isMainThread
                ? MainActor.assumeIsolated { GFCore.shared.beacons.appRequestState(box.value.0, box.value.1) } : false
            if answered { return }
            guard GFState.realBeaconMonitoring.withLock({ $0 }) else { return }
        }
        gf_requestState(for: region)
    }

    @objc dynamic class func gf_isRangingAvailable() -> Bool {
        GFState.active.withLock { $0 } ? true : gf_isRangingAvailable()
    }

    @objc(gf_isMonitoringAvailableForClass:) dynamic class func gf_isMonitoringAvailable(for regionClass: AnyClass) -> Bool {
        if GFState.active.withLock({ $0 }), regionClass is CLBeaconRegion.Type { return true }
        return gf_isMonitoringAvailable(for: regionClass)
    }

    func gfRealStartRangingBeacons(satisfying c: CLBeaconIdentityConstraint) {
        guard GFState.realRanging.withLock({ $0 }) else { return }
        gf_startRangingBeacons(satisfying: c)
    }

    func gfRealStopRangingBeacons(satisfying c: CLBeaconIdentityConstraint) {
        guard GFState.realRanging.withLock({ $0 }) else { return }
        gf_stopRangingBeacons(satisfying: c)
    }
}

extension CMMotionActivityManager {
    @objc dynamic func gf_startActivityUpdates(to queue: OperationQueue,
                                               withHandler handler: @escaping CMMotionActivityHandler) {
        let box = GFUnchecked(value: (self, queue, handler))
        GFMain.run { GFCore.shared.appStartActivity(box.value.0, queue: box.value.1, handler: box.value.2) }
    }

    @objc dynamic func gf_stopActivityUpdates() {
        let m = GFUnchecked(value: self)
        GFMain.run { GFCore.shared.appStopActivity(m.value) }
    }

    @objc dynamic class func gf_isActivityAvailable() -> Bool {
        GFState.active.withLock { $0 } ? true : gf_isActivityAvailable()
    }

    func gfRealStartActivityUpdates(to queue: OperationQueue, handler: @escaping CMMotionActivityHandler) {
        gf_startActivityUpdates(to: queue, withHandler: handler)
    }
    func gfRealStopActivityUpdates() { gf_stopActivityUpdates() }
}

enum GFSwizzle {
    /// メソッドを差し替える（方位3・モーション3・ビーコン7）。戻り値は差し替えに失敗したメソッドの名前
    static func installAll() -> [String] {
        var failed: [String] = []
        func instance(_ cls: AnyClass, _ original: String, _ replacement: String) {
            guard let m1 = class_getInstanceMethod(cls, NSSelectorFromString(original)),
                  let m2 = class_getInstanceMethod(cls, NSSelectorFromString(replacement)) else {
                failed.append("-[\(cls) \(original)]")
                return
            }
            method_exchangeImplementations(m1, m2)
        }
        func klass(_ cls: AnyClass, _ original: String, _ replacement: String) {
            guard let m1 = class_getClassMethod(cls, NSSelectorFromString(original)),
                  let m2 = class_getClassMethod(cls, NSSelectorFromString(replacement)) else {
                failed.append("+[\(cls) \(original)]")
                return
            }
            method_exchangeImplementations(m1, m2)
        }
        let lm: AnyClass = CLLocationManager.self
        instance(lm, "startUpdatingHeading", "gf_startUpdatingHeading")
        instance(lm, "stopUpdatingHeading", "gf_stopUpdatingHeading")
        klass(lm, "headingAvailable", "gf_headingAvailable")
        instance(lm, "startRangingBeaconsSatisfyingConstraint:", "gf_startRangingBeaconsSatisfyingConstraint:")
        instance(lm, "stopRangingBeaconsSatisfyingConstraint:", "gf_stopRangingBeaconsSatisfyingConstraint:")
        instance(lm, "startMonitoringForRegion:", "gf_startMonitoringForRegion:")
        instance(lm, "stopMonitoringForRegion:", "gf_stopMonitoringForRegion:")
        instance(lm, "requestStateForRegion:", "gf_requestStateForRegion:")
        klass(lm, "isRangingAvailable", "gf_isRangingAvailable")
        klass(lm, "isMonitoringAvailableForClass:", "gf_isMonitoringAvailableForClass:")
        let am: AnyClass = CMMotionActivityManager.self
        instance(am, "startActivityUpdatesToQueue:withHandler:", "gf_startActivityUpdatesTo:withHandler:")
        instance(am, "stopActivityUpdates", "gf_stopActivityUpdates")
        klass(am, "isActivityAvailable", "gf_isActivityAvailable")
        return failed
    }
}
#endif
