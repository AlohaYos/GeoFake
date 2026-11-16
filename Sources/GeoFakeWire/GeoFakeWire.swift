// 通信の約束（Mac と GeoFake の間。TCP の上に1行1つの JSON）。各行の形はこのファイルの型のとおり。
//
// - どの行も type 欄で種類を見分ける
// - 時刻は Unix 秒（1970-01-01T00:00:00Z からの秒、小数あり）
// - 知らない種類の行は読み飛ばす。知らない欄は無視する。欠けた欄・壊れた行で落ちない
//
// iOS では DEBUG のときだけ中身がある。Xcode は Swift Package を .o のまま開発者のアプリにリンクするので、
// 使っていなくても型の情報が丸ごと残る。開発者のアプリのリリースのビルドに通信の約束を残さないため
// （リリースのビルドを nm で確かめ、型の名前が残らないことを確認済み）。Mac 版（macOS）はいつでも使える。

#if os(macOS) || DEBUG
import Foundation

public enum GeoFakeWire {
    /// 約束の版。hello で相手に伝え、違えば Mac が画面に知らせる
    public static let protocolVersion = 1

    /// GeoFake が待ち受けるポートの幅。シミュレータは Mac の localhost を共有するので、空いている番号を使う
    public static let portRange: ClosedRange<UInt16> = 47800...47809

    /// 1行の長さの上限（バイト）。これを超えた行は捨てる
    public static let maxLineLength = 64 * 1024
}

// MARK: - 中身の型

/// GeoFake → Mac。つながった直後に1回送る
public struct WireHello: Codable, Sendable, Equatable {
    /// 約束の版
    public var protocolVersion: Int
    /// 開発者のアプリの Bundle ID
    public var bundleID: String
    /// GeoFake の版（例 3.0.0）
    public var geoFakeVersion: String
    /// シミュレータなら端末の UDID（SIMULATOR_UDID）。実機では書かない
    public var simulatorUDID: String?
    /// 端末の名前（画面に出す）
    public var deviceName: String?
    /// 待ち受けているポート
    public var port: UInt16?

    public init(
        protocolVersion: Int = GeoFakeWire.protocolVersion, bundleID: String, geoFakeVersion: String,
        simulatorUDID: String? = nil, deviceName: String? = nil, port: UInt16? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.bundleID = bundleID
        self.geoFakeVersion = geoFakeVersion
        self.simulatorUDID = simulatorUDID
        self.deviceName = deviceName
        self.port = port
    }

    /// この版の約束で話せる相手か
    public var isCompatible: Bool { protocolVersion == GeoFakeWire.protocolVersion }
}

/// Mac → GeoFake。方位
public struct WireHeading: Codable, Sendable, Equatable {
    /// 時刻（Unix 秒）
    public var t: Double
    /// 磁北からの方位（度、0〜360）
    public var mag: Double
    /// 真北からの方位（度）。無ければ GeoFake は負の値（CLHeading の「無い」）として渡す
    public var trueHeading: Double?
    /// 精度（度）
    public var acc: Double?

    enum CodingKeys: String, CodingKey {
        case t, mag, acc
        case trueHeading = "true"
    }

    public init(t: Double, mag: Double, trueHeading: Double? = nil, acc: Double? = nil) {
        self.t = t
        self.mag = mag
        self.trueHeading = trueHeading
        self.acc = acc
    }
}

/// モーションの旗（CMMotionActivity に合わせる）
public enum WireMotionFlag: String, Codable, Sendable, CaseIterable {
    case stationary, walking, running, automotive, cycling, unknown
}

/// モーションの確かさ
public enum WireConfidence: String, Codable, Sendable, CaseIterable {
    case low, medium, high
}

/// Mac → GeoFake。モーション
public struct WireMotion: Codable, Sendable, Equatable {
    /// 開始時刻（Unix 秒。CMMotionActivity.startDate）
    public var t: Double
    /// 立っている旗。空なら「どれでもない」
    public var kinds: [WireMotionFlag]
    /// 確かさ。欠けている・知らない値なら low
    public var conf: WireConfidence

    public init(t: Double, kinds: [WireMotionFlag], conf: WireConfidence = .low) {
        self.t = t
        self.kinds = WireMotionFlag.allCases.filter { Set(kinds).contains($0) }
        self.conf = conf
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawKinds = try c.decodeIfPresent([String].self, forKey: .kinds) ?? []
        let rawConf = try c.decodeIfPresent(String.self, forKey: .conf)
        self.init(
            t: try c.decode(Double.self, forKey: .t),
            kinds: rawKinds.compactMap(WireMotionFlag.init(rawValue:)),
            conf: rawConf.flatMap(WireConfidence.init(rawValue:)) ?? .low
        )
    }
}

/// ビーコンの近さ（CLProximity に合わせる）
public enum WireProximity: String, Codable, Sendable, CaseIterable {
    case unknown, immediate, near, far
}

/// Mac → GeoFake。ビーコン1つ（type が beacon の行。1行に1つ）
public struct WireBeacon: Codable, Sendable, Equatable {
    /// 時刻（Unix 秒）
    public var t: Double?
    public var uuid: String
    public var major: Int
    public var minor: Int
    /// 近さ。欠けている・知らない値なら unknown
    public var proximity: WireProximity
    /// 距離の目安（メートル）。分からなければ書かない
    public var accuracy: Double?
    /// 電波の強さ（dBm）。分からなければ 0
    public var rssi: Int

    public init(
        t: Double? = nil, uuid: String, major: Int, minor: Int,
        proximity: WireProximity = .unknown, accuracy: Double? = nil, rssi: Int = 0
    ) {
        self.t = t
        self.uuid = uuid
        self.major = major
        self.minor = minor
        self.proximity = proximity
        self.accuracy = accuracy.flatMap { $0 >= 0 ? $0 : nil }
        self.rssi = rssi
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawProximity = try c.decodeIfPresent(String.self, forKey: .proximity)
        self.init(
            t: try c.decodeIfPresent(Double.self, forKey: .t),
            uuid: try c.decode(String.self, forKey: .uuid),
            major: try c.decode(Int.self, forKey: .major),
            minor: try c.decode(Int.self, forKey: .minor),
            proximity: rawProximity.flatMap(WireProximity.init(rawValue:)) ?? .unknown,
            accuracy: try c.decodeIfPresent(Double.self, forKey: .accuracy),
            rssi: try c.decodeIfPresent(Int.self, forKey: .rssi) ?? 0
        )
    }
}

/// stop で止めるもの
public enum WireStopTarget: String, Codable, Sendable, CaseIterable {
    case heading, motion, beacon
}

/// Mac → GeoFake。偽の値をやめて本物に戻す
public struct WireStop: Codable, Sendable, Equatable {
    /// 止めるもの。nil なら全部
    public var targets: [WireStopTarget]?

    public init(targets: [WireStopTarget]? = nil) {
        self.targets = targets
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent([String].self, forKey: .targets)
        // 知らない名前は捨てる。知っている名前が1つも無ければ全部止める（本物に戻すほうが安全なため）
        let known = raw?.compactMap(WireStopTarget.init(rawValue:))
        self.init(targets: (known?.isEmpty ?? true) ? nil : known)
    }

    /// target を止めるか
    public func includes(_ target: WireStopTarget) -> Bool {
        targets?.contains(target) ?? true
    }
}

/// 双方。つながっているかの確認。pong は受けた ping の seq と t をそのまま返す
public struct WirePing: Codable, Sendable, Equatable {
    public var seq: Int
    /// ping を送った時刻（Unix 秒）
    public var t: Double

    public init(seq: Int, t: Double) {
        self.seq = seq
        self.t = t
    }
}

// MARK: - 行

/// 1行の種類と中身
public enum WireMessage: Sendable, Equatable {
    case hello(WireHello)
    case heading(WireHeading)
    case motion(WireMotion)
    case beacon(WireBeacon)
    case stop(WireStop)
    case ping(WirePing)
    case pong(WirePing)

    /// type 欄の値
    public var type: String {
        switch self {
        case .hello: "hello"
        case .heading: "heading"
        case .motion: "motion"
        case .beacon: "beacon"
        case .stop: "stop"
        case .ping: "ping"
        case .pong: "pong"
        }
    }
}

/// 1行を読んだ結果。読めなくても投げない
public enum WireDecodeResult: Sendable, Equatable {
    case message(WireMessage)
    /// 知らない種類の行（読み飛ばす）
    case unknown(type: String)
    /// 読めない行（JSON でない・type が無い・欠けた欄・長すぎる）
    case invalid(reason: String)
}

public enum WireCodec {
    private enum TypeKey: String, CodingKey { case type }

    private struct Tagged<Value: Encodable>: Encodable {
        let type: String
        let value: Value

        func encode(to encoder: any Encoder) throws {
            try value.encode(to: encoder)
            var c = encoder.container(keyedBy: TypeKey.self)
            try c.encode(type, forKey: .type)
        }
    }

    private struct TypeProbe: Decodable {
        let type: String
    }

    /// 1行分（最後に改行を付ける）。そのまま TCP に書けばよい
    public static func encodeLine(_ message: WireMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data: Data
        switch message {
        case .hello(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .heading(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .motion(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .beacon(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .stop(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .ping(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        case .pong(let v): data = try encoder.encode(Tagged(type: message.type, value: v))
        }
        data.append(0x0A)
        return data
    }

    /// 1行を読む（改行は付いていてもいなくてもよい）
    public static func decode(line: Data) -> WireDecodeResult {
        var bytes = line
        while let last = bytes.last, last == 0x0A || last == 0x0D { bytes.removeLast() }
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(TypeProbe.self, from: bytes) else {
            return .invalid(reason: "JSON でないか、type が無い")
        }
        do {
            switch probe.type {
            case "hello": return .message(.hello(try decoder.decode(WireHello.self, from: bytes)))
            case "heading": return .message(.heading(try decoder.decode(WireHeading.self, from: bytes)))
            case "motion": return .message(.motion(try decoder.decode(WireMotion.self, from: bytes)))
            case "beacon": return .message(.beacon(try decoder.decode(WireBeacon.self, from: bytes)))
            case "stop": return .message(.stop(try decoder.decode(WireStop.self, from: bytes)))
            case "ping": return .message(.ping(try decoder.decode(WirePing.self, from: bytes)))
            case "pong": return .message(.pong(try decoder.decode(WirePing.self, from: bytes)))
            default: return .unknown(type: probe.type)
            }
        } catch {
            return .invalid(reason: "\(probe.type) の欄が足りないか、型が違う")
        }
    }
}

/// TCP から届いた切れ端をためて、1行ずつ読む。1つのつながりに1つ持つ
public struct WireLineReader: Sendable {
    private var buffer = Data()
    /// 長すぎる行を捨てている最中（次の改行まで読み飛ばす）
    private var discarding = false

    public init() {}

    /// 届いた切れ端を足し、読み終えた行の結果を返す。空行は無視する
    public mutating func append(_ chunk: Data) -> [WireDecodeResult] {
        var results: [WireDecodeResult] = []
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            if discarding {
                discarding = false
                continue
            }
            let isBlank = line.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }
            if isBlank { continue }
            if line.count > GeoFakeWire.maxLineLength {
                results.append(.invalid(reason: "行が長すぎる"))
                continue
            }
            results.append(WireCodec.decode(line: Data(line)))
        }
        if buffer.count > GeoFakeWire.maxLineLength {
            buffer.removeAll()
            if !discarding { results.append(.invalid(reason: "行が長すぎる")) }
            discarding = true
        }
        return results
    }
}
#endif
