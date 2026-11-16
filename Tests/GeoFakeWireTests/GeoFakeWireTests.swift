import Foundation
import Testing
@testable import GeoFakeWire

private let allMessages: [WireMessage] = [
    .hello(WireHello(bundleID: "com.example.app", geoFakeVersion: "3.0.0",
                     simulatorUDID: "8A6E3C1F-0000-4000-8000-000000000001", deviceName: "iPhone 17", port: 47801)),
    .hello(WireHello(bundleID: "com.example.app", geoFakeVersion: "3.0.0")),
    .heading(WireHeading(t: 1_763_256_000.25, mag: 21.3, trueHeading: 28.9, acc: 15)),
    .heading(WireHeading(t: 1_763_256_000.5, mag: 359.9)),
    .motion(WireMotion(t: 1_763_256_001, kinds: [.walking], conf: .high)),
    .motion(WireMotion(t: 1_763_256_002, kinds: [.automotive, .stationary], conf: .medium)),
    .motion(WireMotion(t: 1_763_256_003, kinds: [], conf: .low)),
    .beacon(WireBeacon(t: 1_763_256_004, uuid: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0", major: 1, minor: 2,
                       proximity: .near, accuracy: 1.5, rssi: -60)),
    .beacon(WireBeacon(uuid: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0", major: 65535, minor: 0)),
    .stop(WireStop()),
    .stop(WireStop(targets: [.heading, .beacon])),
    .ping(WirePing(seq: 7, t: 1_763_256_005.125)),
    .pong(WirePing(seq: 7, t: 1_763_256_005.125)),
]

private func decode(_ text: String) -> WireDecodeResult {
    WireCodec.decode(line: Data(text.utf8))
}

@Suite("通信の約束の往復")
struct WireRoundTripTests {
    @Test("全種類を書いて読み戻すと一致する", arguments: allMessages.indices)
    func roundTrip(_ index: Int) throws {
        let message = allMessages[index]
        let line = try WireCodec.encodeLine(message)
        #expect(line.last == 0x0A)
        #expect(line.dropLast().contains(0x0A) == false)
        #expect(WireCodec.decode(line: line) == .message(message))
        let text = String(decoding: line, as: UTF8.self)
        #expect(text.contains("\"type\":\"\(message.type)\""))
    }

    @Test("全種類を1つの流れにつなげても、1行ずつ読める")
    func stream() throws {
        var all = Data()
        for m in allMessages { all.append(try WireCodec.encodeLine(m)) }
        // 7バイトずつ切って届いたことにする
        var reader = WireLineReader()
        var results: [WireDecodeResult] = []
        var offset = 0
        while offset < all.count {
            let end = min(offset + 7, all.count)
            results += reader.append(all.subdata(in: offset..<end))
            offset = end
        }
        #expect(results == allMessages.map { .message($0) })
    }

    @Test("欄の名前と値の形が決めたとおり")
    func wireShape() throws {
        let heading = String(decoding: try WireCodec.encodeLine(.heading(WireHeading(t: 1, mag: 90, trueHeading: 95))), as: UTF8.self)
        #expect(heading == "{\"mag\":90,\"t\":1,\"true\":95,\"type\":\"heading\"}\n")
        let motion = String(decoding: try WireCodec.encodeLine(.motion(WireMotion(t: 1, kinds: [.running, .walking], conf: .high))), as: UTF8.self)
        #expect(motion == "{\"conf\":\"high\",\"kinds\":[\"walking\",\"running\"],\"t\":1,\"type\":\"motion\"}\n")
    }

    @Test("hello の版が違えば話せない相手")
    func compatibility() {
        #expect(WireHello(bundleID: "a", geoFakeVersion: "3").isCompatible)
        #expect(!WireHello(protocolVersion: 2, bundleID: "a", geoFakeVersion: "4").isCompatible)
    }
}

@Suite("欠けた欄・知らない種類で落ちない")
struct WireRobustnessTests {
    @Test("知らない種類の行は unknown として読み飛ばせる")
    func unknownType() {
        #expect(decode(#"{"type":"altitude","t":1,"meters":100}"#) == .unknown(type: "altitude"))
    }

    @Test("必須の欄が欠けた行は invalid になる")
    func missingRequired() {
        let lines = [
            #"{"type":"hello","bundleID":"a"}"#,
            #"{"type":"heading","t":1}"#,
            #"{"type":"motion","kinds":["walking"]}"#,
            #"{"type":"beacon","uuid":"x","major":1}"#,
            #"{"type":"ping","seq":1}"#,
            #"{"type":"pong"}"#,
            #"{"type":"heading","t":"きのう","mag":1}"#,
        ]
        for line in lines {
            guard case .invalid = decode(line) else {
                Issue.record("invalid にならない: \(line)")
                continue
            }
        }
    }

    @Test("JSON でない行・type の無い行・空の行は invalid")
    func notJSON() {
        for line in ["こんにちは", "{", #"{"t":1}"#, "[1,2]", "", #"{"type":5}"#] {
            guard case .invalid = decode(line) else {
                Issue.record("invalid にならない: \(line)")
                continue
            }
        }
    }

    @Test("任意の欄が欠けていれば既定の値、知らない欄は無視、知らない旗や値は捨てる")
    func defaultsAndExtras() {
        #expect(decode(#"{"type":"motion","t":1,"kinds":["walking","hovering"],"conf":"extreme","extra":true}"#)
                == .message(.motion(WireMotion(t: 1, kinds: [.walking], conf: .low))))
        #expect(decode(#"{"type":"motion","t":1}"#) == .message(.motion(WireMotion(t: 1, kinds: [], conf: .low))))
        #expect(decode(#"{"type":"beacon","uuid":"x","major":1,"minor":2,"proximity":"touching","accuracy":-1}"#)
                == .message(.beacon(WireBeacon(uuid: "x", major: 1, minor: 2, proximity: .unknown, accuracy: nil, rssi: 0))))
        #expect(decode(#"{"type":"stop"}"#) == .message(.stop(WireStop())))
        #expect(decode(#"{"type":"stop","targets":["motion","altitude"]}"#) == .message(.stop(WireStop(targets: [.motion]))))
        #expect(decode(#"{"type":"stop","targets":["altitude"]}"#) == .message(.stop(WireStop())))
        #expect(decode(#"{"type":"hello","protocolVersion":1,"bundleID":"a","geoFakeVersion":"3","future":{"x":1}}"#)
                == .message(.hello(WireHello(bundleID: "a", geoFakeVersion: "3"))))
    }

    @Test("stop の targets が無ければ全部止める")
    func stopTargets() {
        #expect(WireStop().includes(.beacon))
        #expect(WireStop(targets: [.heading]).includes(.heading))
        #expect(!WireStop(targets: [.heading]).includes(.motion))
    }

    @Test("読み手は空行・CRLF・壊れた行・知らない行を挟んでも、その後の行を読む")
    func readerKeepsGoing() throws {
        var text = "\r\n"
        text += "{壊れた\n"
        text += #"{"type":"weather","sunny":true}"# + "\r\n"
        text += String(decoding: try WireCodec.encodeLine(.ping(WirePing(seq: 1, t: 2))), as: UTF8.self)
        var reader = WireLineReader()
        let results = reader.append(Data(text.utf8))
        #expect(results.count == 3)
        #expect(results[1] == .unknown(type: "weather"))
        #expect(results[2] == .message(.ping(WirePing(seq: 1, t: 2))))
    }

    @Test("長すぎる行は捨て、次の改行の後から読み直す")
    func tooLong() throws {
        var reader = WireLineReader()
        let big = Data(repeating: 0x61, count: GeoFakeWire.maxLineLength + 10)
        var results = reader.append(big)
        #expect(results == [.invalid(reason: "行が長すぎる")])
        // 長い行の残りと改行、そのあとに正しい行
        results = reader.append(Data("aaaa\n".utf8) + (try WireCodec.encodeLine(.stop(WireStop()))))
        #expect(results == [.message(.stop(WireStop()))])
    }

    @Test("改行の来ない行は、来るまで待つ")
    func partialLine() {
        var reader = WireLineReader()
        #expect(reader.append(Data(#"{"type":"ping","seq":1,"#.utf8)).isEmpty)
        #expect(reader.append(Data(#""t":3}"#.utf8)).isEmpty)
        #expect(reader.append(Data("\n".utf8)) == [.message(.ping(WirePing(seq: 1, t: 3)))])
    }
}

@Suite("GeoFakeWire の決まった値")
struct GeoFakeWireConstantTests {
    @Test("版とポートの幅")
    func constants() {
        #expect(GeoFakeWire.protocolVersion == 1)
        #expect(GeoFakeWire.portRange == 47800...47809)
    }
}
