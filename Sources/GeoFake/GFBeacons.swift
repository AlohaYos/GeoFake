// ビーコン。Mac から届いた beacon の行を、アプリの CLLocationManagerDelegate に渡す。状態はすべてメインスレッドで触る。
//
// | アプリが使う口 | GeoFake がすること |
// |---|---|
// | startRangingBeacons(satisfying:) | Mac が beacon を流している間、本物のレンジングを止め、1秒ごとに didRange(_:satisfying:) へ GFBeacon の配列を渡す（無ければ空の配列） |
// | startMonitoring(for: CLBeaconRegion) | 本物の監視はそのまま。合う偽のビーコンが現れたら didEnterRegion・didDetermineState(.inside)、消えたら didExitRegion・(.outside) |
// | requestState(for: CLBeaconRegion) | Mac が流している間は、偽のビーコンから決めた状態を返す |
// | CLMonitor（BeaconIdentityCondition） | 渡せない（CLMonitor の Event を外から作る公開の道が無い）。README に書く |
//
// - Mac は近いビーコンだけを毎秒送る。最後に届いてから goneAfter 秒たったビーコンは「居なくなった」とみなす
// - stop（beacon）か、値を流していたつながりが切れたら、偽のビーコンを全部消し（入っていた領域は退出を渡す）、本物のレンジングに戻す

#if os(iOS) && DEBUG
import CoreLocation
import Foundation
import GeoFakeWire

@MainActor
final class GFBeaconCenter {
    /// 最後に届いてから、この秒数たったビーコンは居なくなったとみなす
    static let goneAfter: TimeInterval = 3

    /// Mac がビーコンを流している間 true。この間は本物のレンジングを止めている
    private(set) var driving = false

    private struct Key: Hashable { let uuid: UUID; let major: Int; let minor: Int }
    private struct Seen { let beacon: WireBeacon; let at: Date }
    private var seen: [Key: Seen] = [:]

    private final class Ranging {
        weak var manager: CLLocationManager?
        var constraints: [CLBeaconIdentityConstraint] = []
        init(_ m: CLLocationManager) { manager = m }
    }
    private var ranging: [ObjectIdentifier: Ranging] = [:]

    private final class Monitored {
        weak var manager: CLLocationManager?
        let region: CLBeaconRegion
        /// 偽のビーコンから決めた状態（まだ決めていなければ unknown）
        var state: CLRegionState = .unknown
        init(_ m: CLLocationManager, _ r: CLBeaconRegion) { manager = m; region = r }
    }
    /// 鍵は manager と region.identifier
    private var monitored: [String: Monitored] = [:]

    private var timer: Timer?
    private let now: @MainActor () -> Date

    init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    // MARK: Mac から

    func receive(_ b: WireBeacon) {
        guard let uuid = UUID(uuidString: b.uuid) else {
            gfLog.debug("beacon の uuid が読めない: \(b.uuid)")
            return
        }
        if !driving { takeOver() }
        seen[Key(uuid: uuid, major: b.major, minor: b.minor)] = Seen(beacon: b, at: now())
        // 領域の入りはすぐ渡す（レンジングは1秒ごと）
        updateRegions()
    }

    /// 偽のビーコンをやめて本物に戻す
    func release(reason: String) {
        guard driving else { return }
        driving = false
        timer?.invalidate()
        timer = nil
        seen.removeAll()
        updateRegions()
        for r in ranging.values {
            guard let m = r.manager else { continue }
            for c in r.constraints { m.gfRealStartRangingBeacons(satisfying: c) }
        }
        gfLog.notice("ビーコンを本物に戻した（\(reason)）")
    }

    private func takeOver() {
        driving = true
        for r in ranging.values {
            guard let m = r.manager else { continue }
            for c in r.constraints { m.gfRealStopRangingBeacons(satisfying: c) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        gfLog.notice("ビーコンを引き受けた（レンジング \(self.ranging.count)、監視 \(self.monitored.count)）")
    }

    /// 1秒ごと。居なくなったビーコンを消し、レンジングを渡し、領域の出入りを見る
    func tick() {
        let t = now()
        seen = seen.filter { t.timeIntervalSince($0.value.at) < Self.goneAfter }
        deliverRanging()
        updateRegions()
    }

    // MARK: 渡す

    private func current() -> [GFBeacon] {
        seen.map { key, s in
            let b = s.beacon
            let p: CLProximity = switch b.proximity {
            case .immediate: .immediate
            case .near: .near
            case .far: .far
            case .unknown: .unknown
            }
            return GFBeacon(uuid: key.uuid, major: key.major, minor: key.minor, proximity: p,
                            accuracy: b.accuracy ?? -1, rssi: b.rssi, timestamp: s.at)
        }
        .sorted { ($0.accuracy < 0 ? .infinity : $0.accuracy) < ($1.accuracy < 0 ? .infinity : $1.accuracy) }
    }

    private func deliverRanging() {
        ranging = ranging.filter { $0.value.manager != nil }
        let all = current()
        for r in ranging.values {
            guard let m = r.manager else { continue }
            for c in r.constraints {
                let matched = all.filter { Self.matches($0, c) }
                m.delegate?.locationManager?(m, didRange: matched, satisfying: c)
            }
        }
    }

    private func updateRegions() {
        monitored = monitored.filter { $0.value.manager != nil }
        let all = current()
        for mon in monitored.values {
            guard let m = mon.manager else { continue }
            let inside = all.contains { Self.matches($0, mon.region) }
            let state: CLRegionState = inside ? .inside : .outside
            guard state != mon.state else { continue }
            let was = mon.state
            mon.state = state
            // まだ決めていなかった領域が外なら、知らせない（本物も、外のまま入らなければ何も言わない）
            if was == .unknown && state == .outside { continue }
            m.delegate?.locationManager?(m, didDetermineState: state, for: mon.region)
            if state == .inside, mon.region.notifyOnEntry {
                m.delegate?.locationManager?(m, didEnterRegion: mon.region)
            } else if state == .outside, mon.region.notifyOnExit {
                m.delegate?.locationManager?(m, didExitRegion: mon.region)
            }
        }
    }

    static func matches(_ b: CLBeacon, _ c: CLBeaconIdentityConstraint) -> Bool {
        b.uuid == c.uuid
            && (c.major.map { b.major.uint16Value == $0 } ?? true)
            && (c.minor.map { b.minor.uint16Value == $0 } ?? true)
    }

    static func matches(_ b: CLBeacon, _ r: CLBeaconRegion) -> Bool {
        b.uuid == r.uuid
            && (r.major.map { b.major == $0 } ?? true)
            && (r.minor.map { b.minor == $0 } ?? true)
    }

    // MARK: 差し替えたメソッドから

    func appStartRanging(_ m: CLLocationManager, _ c: CLBeaconIdentityConstraint) {
        let r = ranging[ObjectIdentifier(m)] ?? Ranging(m)
        if !r.constraints.contains(c) { r.constraints.append(c) }
        ranging[ObjectIdentifier(m)] = r
        if !driving { m.gfRealStartRangingBeacons(satisfying: c) }
    }

    func appStopRanging(_ m: CLLocationManager, _ c: CLBeaconIdentityConstraint) {
        if let r = ranging[ObjectIdentifier(m)] {
            r.constraints.removeAll { $0 == c }
            if r.constraints.isEmpty { ranging.removeValue(forKey: ObjectIdentifier(m)) }
        }
        m.gfRealStopRangingBeacons(satisfying: c)
    }

    func appStartMonitoring(_ m: CLLocationManager, _ r: CLBeaconRegion) {
        let key = Self.key(m, r)
        monitored[key] = Monitored(m, r)
        if driving { updateRegions() }
    }

    func appStopMonitoring(_ m: CLLocationManager, _ r: CLRegion) {
        monitored.removeValue(forKey: Self.key(m, r))
    }

    /// requestState。Mac が流している間は偽の状態を返す。返したら true
    func appRequestState(_ m: CLLocationManager, _ r: CLBeaconRegion) -> Bool {
        guard driving else { return false }
        let inside = current().contains { Self.matches($0, r) }
        let state: CLRegionState = inside ? .inside : .outside
        if let mon = monitored[Self.key(m, r)] { mon.state = state }
        let box = GFUnchecked(value: (m, r))
        DispatchQueue.main.async {
            let (m, r) = box.value
            m.delegate?.locationManager?(m, didDetermineState: state, for: r)
        }
        return true
    }

    private static func key(_ m: CLLocationManager, _ r: CLRegion) -> String {
        "\(ObjectIdentifier(m).hashValue)|\(r.identifier)"
    }
}
#endif
