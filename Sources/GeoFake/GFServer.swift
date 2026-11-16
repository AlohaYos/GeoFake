// Mac からのつながりを待ち受ける。
//
// - 47800〜47809 のうち空いている番号で待ち受ける（シミュレータは Mac の localhost を共有するため）
// - ループバックだけで待ち受ける。実機は usbmux 越しに 127.0.0.1 から、シミュレータは Mac の localhost から来る
//   （Wi-Fi の同じ網から偽の値を流し込まれないようにするため）
// - つながったら hello を1回送る。ping には pong を返す
// - 裏に回ったら待ち受けとつながりを閉じ、前に出たら張り直す

#if os(iOS) && DEBUG
import Foundation
import GeoFakeWire
import Network
import UIKit

@MainActor
final class GFServer {
    weak var core: GFCore?

    private var listener: NWListener?
    private var port: UInt16?
    private var connections: [ObjectIdentifier: (conn: NWConnection, reader: WireLineReader)] = [:]

    func start() {
        guard listener == nil else { return }
        listen(on: GeoFakeWire.portRange.lowerBound)
    }

    func stop(reason: String) {
        listener?.cancel()
        listener = nil
        port = nil
        for (_, c) in connections { c.conn.cancel() }
        connections.removeAll()
        core?.allConnectionsClosed(reason: reason)
        gfLog.notice("待ち受けをやめた（\(reason)）")
    }

    private func listen(on p: UInt16) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = false
        params.requiredInterfaceType = .loopback
        guard let nwPort = NWEndpoint.Port(rawValue: p),
              let l = try? NWListener(using: params, on: nwPort) else {
            tryNext(after: p)
            return
        }
        listener = l
        l.stateUpdateHandler = { [weak self, weak l] state in
            MainActor.assumeIsolated {
                guard let self, let l, l === self.listener else { return }
                switch state {
                case .ready:
                    self.port = p
                    gfLog.notice("待ち受け中 port=\(p)")
                case .failed(let error):
                    gfLog.notice("port=\(p) で待ち受けられない: \(String(describing: error))")
                    l.cancel()
                    self.listener = nil
                    self.tryNext(after: p)
                default:
                    break
                }
            }
        }
        l.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated { self?.accept(c) }
        }
        l.start(queue: .main)
    }

    private func tryNext(after p: UInt16) {
        if p < GeoFakeWire.portRange.upperBound {
            listen(on: p + 1)
        } else {
            gfLog.error("47800〜47809 がすべて使われていて待ち受けられない")
        }
    }

    // MARK: つながり

    private func accept(_ c: NWConnection) {
        let id = ObjectIdentifier(c)
        connections[id] = (c, WireLineReader())
        gfLog.notice("つながった \(String(describing: c.endpoint))")
        c.start(queue: .main)
        send(.hello(makeHello()), on: c)
        receive(c)
    }

    private func makeHello() -> WireHello {
        let env = ProcessInfo.processInfo.environment
        return WireHello(bundleID: Bundle.main.bundleIdentifier ?? "",
                         geoFakeVersion: GeoFake.version,
                         simulatorUDID: env["SIMULATOR_UDID"],
                         deviceName: env["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name,
                         port: port)
    }

    private func receive(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            let box = GFUnchecked(value: (data, done, error))
            MainActor.assumeIsolated {
                guard let self else { return }
                let (data, done, error) = box.value
                if let data, !data.isEmpty { self.consume(data, from: c) }
                if done || error != nil {
                    self.close(c, reason: error.map { "\($0)" } ?? "切断")
                } else {
                    self.receive(c)
                }
            }
        }
    }

    private func consume(_ data: Data, from c: NWConnection) {
        let id = ObjectIdentifier(c)
        guard var entry = connections[id] else { return }
        let results = entry.reader.append(data)
        connections[id] = entry
        for r in results {
            switch r {
            case .message(.ping(let p)):
                send(.pong(p), on: c)
            case .message(let m):
                core?.receive(m, from: id)
            case .unknown(let type):
                gfLog.debug("知らない種類の行を読み飛ばした: \(type)")
            case .invalid(let reason):
                gfLog.debug("読めない行: \(reason)")
            }
        }
    }

    private func close(_ c: NWConnection, reason: String) {
        let id = ObjectIdentifier(c)
        c.cancel()
        guard connections.removeValue(forKey: id) != nil else { return }
        gfLog.notice("切れた（\(reason)）")
        core?.connectionClosed(id, reason: reason)
    }

    private func send(_ m: WireMessage, on c: NWConnection) {
        guard let data = try? WireCodec.encodeLine(m) else { return }
        c.send(content: data, completion: .contentProcessed { _ in })
    }
}
#endif
