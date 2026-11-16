# GeoFake

> GeoFake 3.0 is a complete rewrite in Swift and is not compatible with 1.x. If you want to keep using 1.x, point to the tag [`1.x-final`](https://github.com/AlohaYos/GeoFake/tree/1.x-final).

GeoFake is a small Swift package that lets [GeoPlayer for Mac](https://newtonjapan.com/geoplayer/) feed recorded **heading**, **motion activity** and **iBeacons** into your iOS app while you debug it. Your app keeps using the normal Core Location and Core Motion APIs; GeoFake hands the replayed values to the same delegate and handler.

Location itself is not GeoFake's job: GeoPlayer replays location through the OS (Xcode's location simulation, `simctl` / `devicectl`), so `CLLocationManager`, `MapKit` and everything else see it as real.

## Requirements

- iOS 17 or later
- Swift 6.2 toolchain (Xcode 26 or later)
- [GeoPlayer for Mac](https://newtonjapan.com/geoplayer/), which records and replays the values

## Setup

### 1. Add the package

In Xcode, choose File > Add Package Dependencies…, enter `https://github.com/AlohaYos/GeoFake`, and choose "Up to Next Major Version" from `3.0.0`. Link the `GeoFake` library to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/AlohaYos/GeoFake", from: "3.0.0"),
],
```

### 2. Call `GeoFake.start()` once

Call it early, for example in your `App` initializer or `application(_:didFinishLaunchingWithOptions:)`:

```swift
#if DEBUG
import GeoFake
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        GeoFake.start()
        #endif
    }
    // ...
}
```

That is the only line you need. Wrapping the import and the call in `#if DEBUG` is recommended (see "Release builds" below). Calling `start()` more than once does nothing.

### 3. Connect

- **Device**: connect the iPhone to the Mac with a USB cable and run your app from Xcode. GeoPlayer for Mac finds it over USB (usbmux). No Wi-Fi, no local network permission and no Info.plist changes are needed.
- **Simulator**: nothing to set up. The simulator shares the Mac's `localhost`, and GeoPlayer connects there. Several simulators can run at the same time.

Then pick your app in GeoPlayer for Mac and play a recording.

## What GeoFake delivers

| Data | How your app receives it | Notes |
|---|---|---|
| Heading | `CLLocationManagerDelegate.locationManager(_:didUpdateHeading:)` | Magnetic heading, true heading (negative when unknown), accuracy and timestamp from the recording. `headingFilter` is respected. |
| Motion activity | The handler passed to `CMMotionActivityManager.startActivityUpdates(to:withHandler:)` | stationary / walking / running / automotive / cycling / unknown, confidence and start date. The handler runs on the `OperationQueue` you passed, just like Core Motion. |
| Availability | `CLLocationManager.headingAvailable()` and `CMMotionActivityManager.isActivityAvailable()` return `true` | Also on the simulator, so code that checks availability first still runs. |
| iBeacon ranging | `locationManager(_:didRange:satisfying:)` for `startRangingBeacons(satisfying:)` | About once a second while GeoPlayer sends beacons, with UUID, major, minor, proximity, accuracy and RSSI. `CLLocationManager.isRangingAvailable()` returns `true`, also on the simulator. |
| iBeacon regions | `didEnterRegion`, `didExitRegion` and `didDetermineState` for `startMonitoring(for:)` with a `CLBeaconRegion`; `requestState(for:)` | A region is entered when a matching beacon appears and exited about 3 seconds after the last one disappears. Other region types (circular regions) are not touched. |

What GeoFake does **not** deliver:

| Data | Why |
|---|---|
| Altitude | The OS location simulation always reports altitude 0 (vertical accuracy fixed). GeoFake does not touch location, so recorded altitude is not replayed. |
| Raw sensors (accelerometer, gyro, magnetometer, pedometer) | Not recorded by GeoPlayer. |
| Motion authorization | `CMMotionActivityManager.authorizationStatus()` is not changed. If your app stops when motion access is denied, it will stop before receiving replayed values. |
| Beacons for `CLMonitor` | `CLMonitor.BeaconIdentityCondition` events can't be created from outside Core Location, so GeoFake can't deliver them. Use `CLLocationManager` ranging and `CLBeaconRegion` monitoring to test beacon features with GeoPlayer. |
| Beacons through the deprecated APIs | `startRangingBeacons(in:)` (iOS 7–13) is not replaced. Use `startRangingBeacons(satisfying:)`. |

### While GeoPlayer is connected

- When GeoPlayer starts sending heading or motion, GeoFake pauses the real updates of that kind, so real and replayed values never mix.
- When GeoPlayer sends stop, or the connection closes, GeoFake restarts the real updates you asked for.
- When your app goes to the background, GeoFake stops listening and closes the connection. When it comes back to the foreground, GeoFake listens again and GeoPlayer reconnects.

## Release builds

All of GeoFake's code is inside `#if DEBUG`. In a Release build, `GeoFake.start()` is an empty function and nothing else from GeoFake is compiled in: no method swizzling, no network listener, and no protocol types. (Checked with `nm` and `strings` on a stripped Release build of the sample app: no GeoFake symbols remain.)

Wrapping the import and the call in `#if DEBUG` as shown above also keeps the empty function out of your Release binary.

## Custom build configurations (Staging, etc.)

Xcode decides how to build Swift packages from the **name** of your build configuration, not from your app's build settings. A package gets `DEBUG` only when the configuration name contains `Debug`.

| Your configuration | GeoFake |
|---|---|
| `Debug` | Active |
| `Release` | Empty |
| `Staging` (even if it is a copy of Debug) | Empty — `GeoFake.start()` does nothing |
| `Debug-Staging` | Active |

If you want GeoFake in a custom configuration, include `Debug` in its name (for example rename `Staging` to `Debug-Staging`). Setting `DEBUG` in your app target's Active Compilation Conditions is not enough, because that setting does not reach package targets.

## How it works

- GeoFake listens on TCP port 47800–47809 (the first free one), on the loopback interface only, so nobody on the same Wi-Fi network can send values.
- It replaces `startUpdatingHeading`, `stopUpdatingHeading`, `headingAvailable`, `startActivityUpdates(to:withHandler:)`, `stopActivityUpdates`, `isActivityAvailable`, and for beacons `startRangingBeacons(satisfying:)`, `stopRangingBeacons(satisfying:)`, `startMonitoring(for:)`, `stopMonitoring(for:)`, `requestState(for:)`, `isRangingAvailable` and `isMonitoringAvailable(for:)`, using public Objective-C runtime functions. No private API is used.
- Values are delivered as subclasses of `CLHeading`, `CMMotionActivity` and `CLBeacon`. They support `copy()`, `isEqual(_:)`, `hash` and `NSSecureCoding` like the originals.
- The line protocol between the Mac and GeoFake lives in the `GeoFakeWire` library of this package.

## Sample app

The `SampleApp` folder of this repository holds GeoFake Sample, a small SwiftUI app that shows the replayed heading, motion activity and beacons, and tells you when you enter or leave circular fences. It refers to this package by a local path, so open `SampleApp/GeoFakeSample.xcodeproj`, choose your own team for signing if you run it on a device, and run it. The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `SampleApp/project.yml`.

## License

MIT. See [LICENSE](LICENSE).
