# swift-ros2

Native Swift client library for ROS 2. Publishes and subscribes over **Zenoh** (via zenoh-pico) or **DDS** (via CycloneDDS) without a bridge, without pulling in the full ROS 2 stack.

Shipping as **0.5.0** — pre-built xcframeworks on every Apple platform, pre-built static library bundles on Linux x86_64 + aarch64.

## Features

- **Dual transport out of the box.** `SwiftROS2Zenoh` talks to `rmw_zenoh_cpp`; `SwiftROS2DDS` talks to `rmw_cyclonedds_cpp`. Swap between them with a single config change.
- **No RCL dependency.** Everything happens at the wire level, so iOS, iPadOS, macOS, Mac Catalyst, visionOS, and Linux all share the same Swift API.
- **Swift-native API.** `async`/`await`, `AsyncStream` subscriptions, `Sendable` conformance, structured concurrency.
- **Pre-built binaries.** `CZenohPico` + `CCycloneDDS` attached to every GitHub Release as xcframeworks (Apple) and `.artifactbundle` static libraries (Linux) — `swift build` downloads them directly; no CMake, no local bootstrap.
- **Multi-distro wire format.** Humble, Jazzy, Kilted, Rolling. Select `wireMode` explicitly on the `TransportConfig`; when unspecified, Zenoh defaults to Jazzy.
- **20 built-in message types** across sensor_msgs, geometry_msgs, std_msgs, audio_common_msgs, and tf2_msgs. Pure-Swift XCDR v1 encoder + decoder covers both publish and subscribe.
- **Production proven.** Extracted from [Conduit](https://apps.apple.com/app/conduit-ros2-sensor-publisher/id6738043971), which pushes 12 sensor streams at up to 100 Hz.

## Platforms

| Platform      | Minimum deployment target | Integration path                              |
|---------------|---------------------------|-----------------------------------------------|
| iOS / iPadOS  | 16.0                      | `binaryTarget` xcframework (from release)     |
| macOS         | 13.0                      | `binaryTarget` xcframework                    |
| Mac Catalyst  | 16.0                      | `binaryTarget` xcframework                    |
| visionOS      | 1.0                       | `binaryTarget` xcframework                    |
| Linux         | Ubuntu 22.04 / 24.04 (x86_64, aarch64) | `.artifactbundle` static libraries (from release)     |

Swift 5.9+ on Apple platforms; Swift 6.2+ on Linux. CI runs `macos-15` (Apple Silicon, Xcode 16.2) plus a Swift 6.2 Linux matrix: Ubuntu 22.04, Ubuntu 24.04 × 2 (Jazzy + Rolling), exercised on x86_64.

## Installation

### Apple platforms (recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "0.5.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftROS2", package: "swift-ros2"),
        ]
    ),
]
```

That's it — `swift build` downloads the xcframeworks from the 0.5.0 release assets. `SwiftROS2` already links `SwiftROS2Zenoh` + `SwiftROS2DDS` transitively, so the high-level `ROS2Context` / `ROS2Node` API works out of the box. Add the transport-specific products only if you need `ZenohClient` / `DDSClient` directly (e.g. for custom session configuration or testing).

### Linux

swift-ros2 ships pre-built zenoh-pico and CycloneDDS static libraries on GitHub Release for `x86_64-unknown-linux-gnu` and `aarch64-unknown-linux-gnu` (Ubuntu 22.04 / glibc 2.35 baseline, forward-compatible with newer distros).

```swift
// Package.swift
.package(url: "https://github.com/youtalk/swift-ros2", from: "0.5.0")
```

```bash
swift build
swift test --parallel
```

No ROS 2 install is required to build swift-ros2 itself. To exchange messages with ROS 2 peers, ROS 2 must be installed on whichever host runs the matching subscriber — that is an independent concern.

## Quick Start

### Publish an IMU message over Zenoh

```swift
import SwiftROS2

let context = try await ROS2Context(
    transport: .zenoh(locator: "tcp/192.168.1.100:7447"),
    distro: .jazzy
)
let node = try await context.createNode(name: "sensor_node", namespace: "/ios")
let pub = try await node.createPublisher(Imu.self, topic: "imu")

let msg = Imu(
    header: Header.now(frameId: "imu_link"),
    linearAcceleration: Vector3(x: 0, y: 0, z: 9.81)
)
try pub.publish(msg)
```

### Same thing over DDS

```swift
import SwiftROS2

let context = try await ROS2Context(
    transport: .ddsMulticast(domainId: 0)
)
// Identical Node / Publisher API from here on.
```

### Subscribe

```swift
let sub = try await node.createSubscription(Imu.self, topic: "imu")
for await msg in sub.messages {
    print("accel: \(msg.linearAcceleration)")
}
```

### Runnable examples

For end-to-end `talker` / `listener` demos modeled on `demo_nodes_cpp` — `swift run talker_zenoh`, `swift run listener_dds`, etc., with instructions for wiring them up to `ros2 topic echo` — see [`Sources/Examples/README.md`](Sources/Examples/README.md).

## Module Layout

```
import SwiftROS2          // re-exports CDR / Messages / Transport / Wire
    ├── SwiftROS2CDR        — XCDR v1 encoder + decoder (pure Swift)
    ├── SwiftROS2Wire       — Zenoh/DDS wire codecs, Humble → Rolling
    ├── SwiftROS2Messages   — 20 built-in message types + ROS 2 protocols
    └── SwiftROS2Transport  — TransportSession / Publisher / Subscriber
                              abstractions + TransportConfig

// Transport-specific, opt-in:
import SwiftROS2Zenoh      — ZenohClient (zenoh-pico-backed)
import SwiftROS2DDS        — DDSClient (CycloneDDS-backed)
```

### Built-in message types

**sensor_msgs:** Imu, Image, CompressedImage, PointCloud2, NavSatFix, MagneticField, FluidPressure, Illuminance, Temperature, BatteryState, Joy, Range
**geometry_msgs:** Vector3, Quaternion, Point, Pose, Twist, Transform, PoseStamped, TwistStamped, TransformStamped
**std_msgs:** Header, String, Bool, Int32, Float64, Empty
**audio_common_msgs:** AudioData
**tf2_msgs:** TFMessage

## Defining a custom message type

```swift
import SwiftROS2CDR
import SwiftROS2Messages

public struct MyMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "my_pkg/msg/MyMsg",
        typeHash: "RIHS01_…"
    )

    public var header: Header
    public var value: Double

    public func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat64(value)
    }

    public init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.value = try decoder.readFloat64()
    }
}
```

## Versioning

Tags follow the Apple ecosystem convention of bare semver (no `v` prefix): `0.2.0`, `0.2.1`, `1.0.0-rc.1`, etc. The release workflow at `.github/workflows/release-xcframework.yml` fires on any tag matching `[0-9]*.[0-9]*.[0-9]*` (optionally followed by a `-qualifier`).

## Contributing

PRs welcome. The wire format fixtures in `Tests/SwiftROS2WireTests/` and the golden CDR tests in `Tests/SwiftROS2CDRTests/` are the canonical guardrails — keep them green. `Tests/SwiftROS2IntegrationTests/` boots a real ROS 2 subscriber on a Linux host; set `LINUX_IP=<host>` locally to run those two tests.

## Roadmap

- [x] 0.2.0: Publisher + Subscriber core, pure-Swift CDR, Jazzy/Humble wire codecs, Apple xcframework + Linux source build, dual-transport (Zenoh + DDS) FFI
- [x] 0.3.1: CDR decoder bounds + string null-terminator validation — rejects untrusted length prefixes before `reserveCapacity`, fails fast on malformed strings instead of silently dropping bytes.
- [x] 0.4.0: DDS subscriber support — `raw_cdr_serdata_from_ser` fragchain walk, `bridge_dds_reader_t` + listener callback, `DDSReaderHandle` / `createRawReader` / `destroyReader` on `DDSClientProtocol`, `DDSTransportSession.createSubscriber` wired through, `swift run listener dds` enabled.
- [ ] Services (request/reply) and Actions (goal/feedback/result)
- [ ] `swift-ros2-gen` code generator for `.msg` / `.srv` / `.action` files
- [ ] Expanded message catalog (nav_msgs, visualization_msgs, …)

## License

Apache License 2.0. See [LICENSE](LICENSE).
