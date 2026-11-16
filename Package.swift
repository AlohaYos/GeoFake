// swift-tools-version: 6.2
// GeoFake: 開発者のアプリに入れる Swift Package。外に配るのはこのフォルダの中身。

import PackageDescription

let package = Package(
    name: "GeoFake",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        // 開発者のアプリに入れる本体（iOS のみ。macOS では空になる）
        .library(name: "GeoFake", targets: ["GeoFake"]),
        // Mac と GeoFake の間の通信の約束。Mac 版もこれだけを使う
        .library(name: "GeoFakeWire", targets: ["GeoFakeWire"]),
    ],
    targets: [
        .target(name: "GeoFakeWire"),
        .target(name: "GeoFake", dependencies: ["GeoFakeWire"]),
        .testTarget(name: "GeoFakeWireTests", dependencies: ["GeoFakeWire"]),
        // iOS シミュレータで回す（macOS では中身が空）
        .testTarget(name: "GeoFakeTests", dependencies: ["GeoFake", "GeoFakeWire"]),
    ]
)
