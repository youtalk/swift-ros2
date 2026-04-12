# swift-ros2

Native Swift client library for ROS 2.

**swift-ros2** provides a Swift-native API for ROS 2 communication — publish, subscribe, services, and actions — over both **Zenoh** and **DDS** transports, without requiring the full ROS 2 stack.

## Features

- **Dual transport**: Zenoh (rmw_zenoh_cpp) + DDS (rmw_cyclonedds_cpp) from day one
- **No RCL dependency**: communicates at the transport level — works on iOS, visionOS, and macOS where installing ROS 2 is impractical
- **Swift-native API**: async/await, AsyncStream subscriptions, Sendable conformance, structured concurrency
- **ROS 2 distro support**: Humble, Jazzy, Kilted, Rolling with runtime wire format detection
- **20 built-in message types**: sensor_msgs, geometry_msgs, std_msgs, audio_common_msgs
- **Bidirectional CDR**: pure Swift XCDR v1 encoder + decoder for publish and subscribe
- **Production-proven**: extracted from [Conduit](https://apps.apple.com/app/conduit-ros2-sensor-publisher/id6738043971), a shipping iOS app that publishes 12 sensor types at up to 100 Hz

## Requirements

- Swift 5.9+
- iOS 16+ / macOS 13+ / visionOS 1+

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["SwiftROS2"]
    ),
]
```

## Quick Start

```swift
import SwiftROS2

// Create context with Zenoh transport
let ctx = try await ROS2Context(
    transport: .zenoh(locator: "tcp/192.168.1.1:7447"),
    session: myZenohSession
)

// Create a node
let node = try await ctx.createNode(name: "my_node", namespace: "/ios")

// Publish an IMU message
let pub = try await node.createPublisher(Imu.self, topic: "imu")
let msg = Imu(
    header: Header.now(frameId: "imu_link"),
    linearAcceleration: Vector3(x: 0.0, y: 0.0, z: 9.81)
)
try pub.publish(msg)

// Subscribe (AsyncStream)
let sub = try await node.createSubscription(Imu.self, topic: "imu")
for await message in sub.messages {
    print("Received: \(message.linearAcceleration)")
}
```

## Architecture

```
import SwiftROS2  (re-exports all modules)
    ├── SwiftROS2CDR        — XCDR v1 encoder + decoder (pure Swift)
    ├── SwiftROS2Wire       — Wire format codecs (Zenoh + DDS, Humble → Rolling)
    ├── SwiftROS2Messages   — Message protocols + 20 built-in types
    └── SwiftROS2Transport  — Transport abstraction (session, publisher, subscriber)
```

### Core API

| Type | Description |
|------|-------------|
| `ROS2Context` | Entry point; owns a transport session |
| `ROS2Node` | Creates publishers, subscribers, services, actions |
| `ROS2Publisher<M>` | Publishes messages of type M |
| `ROS2Subscription<M>` | Receives messages via `AsyncStream<M>` |

### Message Protocols

| Protocol | Description |
|----------|-------------|
| `CDREncodable` | Can be serialized to CDR |
| `CDRDecodable` | Can be deserialized from CDR |
| `ROS2MessageType` | Has `typeInfo` (type name + hash) |
| `ROS2Message` | `ROS2MessageType & CDRCodable` (both directions) |
| `ROS2Service` | Request/Response associated types |
| `ROS2Action` | Goal/Result/Feedback associated types |

### Built-in Message Types

**sensor_msgs**: Imu, Image, CompressedImage, PointCloud2, NavSatFix, MagneticField, FluidPressure, Illuminance, Temperature, BatteryState, Joy, Range

**geometry_msgs**: TwistStamped, PoseStamped, TransformStamped, Vector3, Quaternion, Pose, Twist, Transform, Point

**std_msgs**: String, Bool, Int32, Float64, Empty

**audio_common_msgs**: AudioData

## Defining Custom Messages

```swift
import SwiftROS2CDR
import SwiftROS2Messages

struct MyCustomMsg: ROS2Message {
    static let typeInfo = ROS2MessageTypeInfo(
        typeName: "my_pkg/msg/MyCustom",
        typeHash: "RIHS01_..."
    )

    var header: Header
    var value: Double

    func encode(to encoder: CDREncoder) throws {
        encoder.writeEncapsulationHeader()
        try header.encode(to: encoder)
        encoder.writeFloat64(value)
    }

    init(from decoder: CDRDecoder) throws {
        self.header = try Header(from: decoder)
        self.value = try decoder.readFloat64()
    }
}
```

## Roadmap

- [x] Phase 1: Publisher + Subscriber core with CDR encode/decode
- [ ] Phase 2: Service client/server (ROS 2 request/reply)
- [ ] Phase 3: Action client/server + `swift-ros2-gen` code generator
- [ ] Phase 4: Documentation, example apps, CI/CD, Linux support

## License

MIT License. See [LICENSE](LICENSE) for details.
