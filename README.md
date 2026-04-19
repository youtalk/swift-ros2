# swift-ros2

Native Swift client library for ROS 2. Publishes and subscribes over **Zenoh** (via zenoh-pico) or **DDS** (via CycloneDDS) without a bridge, without pulling in the full ROS 2 stack.

Shipping as **0.3.0** — pre-built xcframeworks on every Apple platform, source build on Linux.

## Features

- **Dual transport out of the box.** `SwiftROS2Zenoh` talks to `rmw_zenoh_cpp`; `SwiftROS2DDS` talks to `rmw_cyclonedds_cpp`. Swap between them with a single config change.
- **No RCL dependency.** Everything happens at the wire level, so iOS, iPadOS, macOS, Mac Catalyst, visionOS, and Linux all share the same Swift API.
- **Swift-native API.** `async`/`await`, `AsyncStream` subscriptions, `Sendable` conformance, structured concurrency.
- **Pre-built Apple binaries.** `CZenohPico.xcframework` + `CCycloneDDS.xcframework` attached to every GitHub Release — `swift build` downloads them directly; no CMake, no local bootstrap.
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
| Linux         | Ubuntu 22.04 / 24.04 (x86_64, aarch64) | zenoh-pico source build + CycloneDDS via `pkg-config` |

Swift 5.9+ everywhere. CI runs `macos-15` (Apple Silicon, Xcode 16.2) plus a Swift 6.0.2 Linux matrix: Humble on Ubuntu 22.04, Jazzy on Ubuntu 24.04, and Rolling on Ubuntu 24.04 — each exercised on both x86_64 and aarch64.

## Installation

### Apple platforms (recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "0.3.0"),
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

That's it — `swift build` downloads the xcframeworks from the 0.3.0 release assets. `SwiftROS2` already links `SwiftROS2Zenoh` + `SwiftROS2DDS` transitively, so the high-level `ROS2Context` / `ROS2Node` API works out of the box. Add the transport-specific products only if you need `ZenohClient` / `DDSClient` directly (e.g. for custom session configuration or testing).

### Linux

```bash
# Ubuntu 24.04
sudo apt install ros-jazzy-cyclonedds   # provides libddsc via pkg-config
git clone --recursive https://github.com/youtalk/swift-ros2.git
cd swift-ros2
bash Scripts/build-linux-deps.sh        # verifies pkg-config finds CycloneDDS

# Make pkg-config find CycloneDDS in the current shell. build-linux-deps.sh
# exports these variables only inside its own process, so they have to be
# re-exported here before `swift build` invokes the C toolchain.
source /opt/ros/jazzy/setup.bash
export PKG_CONFIG_PATH=/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:$PKG_CONFIG_PATH

swift build
swift test                               # 69 pass, 2 LINUX_IP-gated skips
```

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
- [x] 0.3.0: Drop `Default` prefix from `ZenohClient` / `DDSClient` — breaking API rename
- [ ] Services (request/reply) and Actions (goal/feedback/result)
- [ ] `swift-ros2-gen` code generator for `.msg` / `.srv` / `.action` files
- [ ] Expanded message catalog (nav_msgs, visualization_msgs, …)

## License

Apache License 2.0. See [LICENSE](LICENSE).
