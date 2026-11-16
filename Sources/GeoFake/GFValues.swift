// Mac から届いた値を持つ CLHeading・CMMotionActivity・CLBeacon のサブクラス。
// getter をすべて上書きし、親の内部の値（ivar）には頼らない。
// 親の copy は内部の値を写すので、copy は自分を返すように上書きする（値が変わらない物なので足りる）。

#if os(iOS) && DEBUG
import CoreLocation
import CoreMotion
import Foundation

final class GFHeading: CLHeading, @unchecked Sendable {
    private let gMagnetic: CLLocationDirection
    private let gTrue: CLLocationDirection
    private let gAccuracy: CLLocationDirection
    private let gTimestamp: Date

    init(magnetic: Double, trueHeading: Double, accuracy: Double, timestamp: Date) {
        gMagnetic = magnetic
        gTrue = trueHeading
        gAccuracy = accuracy
        gTimestamp = timestamp
        super.init()
    }

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        gMagnetic = coder.decodeDouble(forKey: "gf.magnetic")
        gTrue = coder.decodeDouble(forKey: "gf.true")
        gAccuracy = coder.decodeDouble(forKey: "gf.accuracy")
        gTimestamp = (coder.decodeObject(of: NSDate.self, forKey: "gf.timestamp") as Date?) ?? Date()
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        coder.encode(gMagnetic, forKey: "gf.magnetic")
        coder.encode(gTrue, forKey: "gf.true")
        coder.encode(gAccuracy, forKey: "gf.accuracy")
        coder.encode(gTimestamp as NSDate, forKey: "gf.timestamp")
    }

    override var magneticHeading: CLLocationDirection { gMagnetic }
    override var trueHeading: CLLocationDirection { gTrue }
    override var headingAccuracy: CLLocationDirection { gAccuracy }
    override var x: CLHeadingComponentValue { 0 }
    override var y: CLHeadingComponentValue { 0 }
    override var z: CLHeadingComponentValue { 0 }
    override var timestamp: Date { gTimestamp }

    // 本物の CLHeading の description の形に合わせる
    override var description: String {
        String(format: "magneticHeading %.2f trueHeading %.2f accuracy %.2f x %.3f y %.3f z %.3f @ %@",
               gMagnetic, gTrue, gAccuracy, 0.0, 0.0, 0.0, gTimestamp.description)
    }
    override var debugDescription: String { description }

    override func copy(with zone: NSZone? = nil) -> Any { self }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CLHeading else { return false }
        if o === self { return true }
        return o.magneticHeading == gMagnetic && o.trueHeading == gTrue
            && o.headingAccuracy == gAccuracy && o.timestamp == gTimestamp
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(gMagnetic); h.combine(gTrue); h.combine(gAccuracy); h.combine(gTimestamp)
        return h.finalize()
    }
}

final class GFMotionActivity: CMMotionActivity, @unchecked Sendable {
    struct Flags: Equatable {
        var unknown = false, stationary = false, walking = false
        var running = false, automotive = false, cycling = false
    }
    private let gFlags: Flags
    private let gConfidence: CMMotionActivityConfidence
    private let gStartDate: Date
    private let gTimestamp: TimeInterval

    init(flags: Flags, confidence: CMMotionActivityConfidence, startDate: Date, timestamp: TimeInterval) {
        gFlags = flags
        gConfidence = confidence
        gStartDate = startDate
        gTimestamp = timestamp
        super.init()
    }

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        gFlags = Flags(unknown: coder.decodeBool(forKey: "gf.unknown"),
                       stationary: coder.decodeBool(forKey: "gf.stationary"),
                       walking: coder.decodeBool(forKey: "gf.walking"),
                       running: coder.decodeBool(forKey: "gf.running"),
                       automotive: coder.decodeBool(forKey: "gf.automotive"),
                       cycling: coder.decodeBool(forKey: "gf.cycling"))
        gConfidence = CMMotionActivityConfidence(rawValue: coder.decodeInteger(forKey: "gf.confidence")) ?? .low
        gStartDate = (coder.decodeObject(of: NSDate.self, forKey: "gf.startDate") as Date?) ?? Date()
        gTimestamp = coder.decodeDouble(forKey: "gf.timestamp")
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        coder.encode(gFlags.unknown, forKey: "gf.unknown")
        coder.encode(gFlags.stationary, forKey: "gf.stationary")
        coder.encode(gFlags.walking, forKey: "gf.walking")
        coder.encode(gFlags.running, forKey: "gf.running")
        coder.encode(gFlags.automotive, forKey: "gf.automotive")
        coder.encode(gFlags.cycling, forKey: "gf.cycling")
        coder.encode(gConfidence.rawValue, forKey: "gf.confidence")
        coder.encode(gStartDate as NSDate, forKey: "gf.startDate")
        coder.encode(gTimestamp, forKey: "gf.timestamp")
    }

    override var unknown: Bool { gFlags.unknown }
    override var stationary: Bool { gFlags.stationary }
    override var walking: Bool { gFlags.walking }
    override var running: Bool { gFlags.running }
    override var automotive: Bool { gFlags.automotive }
    override var cycling: Bool { gFlags.cycling }
    override var confidence: CMMotionActivityConfidence { gConfidence }
    override var startDate: Date { gStartDate }
    override var timestamp: TimeInterval { gTimestamp }

    // 本物の CMMotionActivity の description の形に合わせる
    override var description: String {
        let f = gFlags
        return String(format: "<%@ %p> %@,activity confidence,%ld,unknown,%d,stationary,%d,walking,%d,running,%d,automotive,%d,cycling,%d",
                      NSStringFromClass(CMMotionActivity.self), unsafeBitCast(self, to: Int.self),
                      gStartDate.description, gConfidence.rawValue,
                      f.unknown ? 1 : 0, f.stationary ? 1 : 0, f.walking ? 1 : 0,
                      f.running ? 1 : 0, f.automotive ? 1 : 0, f.cycling ? 1 : 0)
    }
    override var debugDescription: String { description }

    override func copy(with zone: NSZone? = nil) -> Any { self }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CMMotionActivity else { return false }
        if o === self { return true }
        return o.unknown == gFlags.unknown && o.stationary == gFlags.stationary
            && o.walking == gFlags.walking && o.running == gFlags.running
            && o.automotive == gFlags.automotive && o.cycling == gFlags.cycling
            && o.confidence == gConfidence && o.startDate == gStartDate
            && o.timestamp == gTimestamp
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(gFlags.walking); h.combine(gFlags.automotive); h.combine(gFlags.stationary)
        h.combine(gConfidence.rawValue); h.combine(gStartDate)
        return h.finalize()
    }
}

final class GFBeacon: CLBeacon, @unchecked Sendable {
    private let gUUID: UUID
    private let gMajor: Int
    private let gMinor: Int
    private let gProximity: CLProximity
    private let gAccuracy: CLLocationAccuracy
    private let gRSSI: Int
    private let gTimestamp: Date

    init(uuid: UUID, major: Int, minor: Int, proximity: CLProximity, accuracy: Double, rssi: Int, timestamp: Date) {
        gUUID = uuid
        gMajor = major
        gMinor = minor
        gProximity = proximity
        gAccuracy = accuracy
        gRSSI = rssi
        gTimestamp = timestamp
        // 本物の CLBeacon は中身（_internal）を init(coder:) でしか作らず、無いまま解放すると落ちる（2026-11-16 試験で確認）。
        // 空の読み手を渡して、親に中身を作らせる。値はすべて上の getter が返す
        super.init(coder: Self.emptyCoder())!
    }

    private static func emptyCoder() -> NSCoder {
        let a = NSKeyedArchiver(requiringSecureCoding: false)
        a.finishEncoding()
        let u = try! NSKeyedUnarchiver(forReadingFrom: a.encodedData)
        u.requiresSecureCoding = false
        return u
    }

    override class var supportsSecureCoding: Bool { true }

    required init?(coder: NSCoder) {
        gUUID = (coder.decodeObject(of: NSUUID.self, forKey: "gf.uuid") as UUID?) ?? UUID()
        gMajor = coder.decodeInteger(forKey: "gf.major")
        gMinor = coder.decodeInteger(forKey: "gf.minor")
        gProximity = CLProximity(rawValue: coder.decodeInteger(forKey: "gf.proximity")) ?? .unknown
        gAccuracy = coder.decodeDouble(forKey: "gf.accuracy")
        gRSSI = coder.decodeInteger(forKey: "gf.rssi")
        gTimestamp = (coder.decodeObject(of: NSDate.self, forKey: "gf.timestamp") as Date?) ?? Date()
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        coder.encode(gUUID as NSUUID, forKey: "gf.uuid")
        coder.encode(gMajor, forKey: "gf.major")
        coder.encode(gMinor, forKey: "gf.minor")
        coder.encode(gProximity.rawValue, forKey: "gf.proximity")
        coder.encode(gAccuracy, forKey: "gf.accuracy")
        coder.encode(gRSSI, forKey: "gf.rssi")
        coder.encode(gTimestamp as NSDate, forKey: "gf.timestamp")
    }

    override var uuid: UUID { gUUID }
    @available(iOS, deprecated: 13.0)
    override var proximityUUID: UUID { gUUID }
    override var major: NSNumber { NSNumber(value: gMajor) }
    override var minor: NSNumber { NSNumber(value: gMinor) }
    override var proximity: CLProximity { gProximity }
    override var accuracy: CLLocationAccuracy { gAccuracy }
    override var rssi: Int { gRSSI }
    override var timestamp: Date { gTimestamp }

    // 本物の CLBeacon の description に近い形
    override var description: String {
        let p = switch gProximity {
        case .immediate: "Immediate"
        case .near: "Near"
        case .far: "Far"
        default: "Unknown"
        }
        return String(format: "CLBeacon (uuid:%@, major:%ld, minor:%ld, proximity:%@ +/- %.2fm, rssi:%ld, timestamp:%@)",
                      gUUID.uuidString, gMajor, gMinor, p, gAccuracy, gRSSI, gTimestamp.description)
    }
    override var debugDescription: String { description }

    override func copy(with zone: NSZone? = nil) -> Any { self }

    override func isEqual(_ object: Any?) -> Bool {
        guard let o = object as? CLBeacon else { return false }
        if o === self { return true }
        return o.uuid == gUUID && o.major.intValue == gMajor && o.minor.intValue == gMinor
            && o.proximity == gProximity && o.accuracy == gAccuracy && o.rssi == gRSSI && o.timestamp == gTimestamp
    }

    override var hash: Int {
        var h = Hasher()
        h.combine(gUUID); h.combine(gMajor); h.combine(gMinor); h.combine(gTimestamp)
        return h.finalize()
    }
}
#endif
