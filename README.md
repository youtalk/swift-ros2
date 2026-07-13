# swift-ros2

[![Apple CI](https://img.shields.io/github/actions/workflow/status/youtalk/swift-ros2/ci.yml?branch=main&label=Apple)](https://github.com/youtalk/swift-ros2/actions/workflows/ci.yml)
[![Linux CI](https://img.shields.io/github/actions/workflow/status/youtalk/swift-ros2/ci.yml?branch=main&label=Linux)](https://github.com/youtalk/swift-ros2/actions/workflows/ci.yml)
[![Windows CI](https://img.shields.io/github/actions/workflow/status/youtalk/swift-ros2/ci.yml?branch=main&label=Windows)](https://github.com/youtalk/swift-ros2/actions/workflows/ci.yml)
[![Android CI](https://img.shields.io/github/actions/workflow/status/youtalk/swift-ros2/ci.yml?branch=main&label=Android)](https://github.com/youtalk/swift-ros2/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/youtalk/swift-ros2?label=release&sort=semver)](https://github.com/youtalk/swift-ros2/releases)
[![ROS 2](https://img.shields.io/badge/ROS%202-Humble%20%7C%20Jazzy%20%7C%20Kilted%20%7C%20Rolling-22314E.svg)](https://docs.ros.org)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![SPI Swift compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fyoutalk%2Fswift-ros2%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/youtalk/swift-ros2)
[![SPI platform compatibility](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fyoutalk%2Fswift-ros2%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/youtalk/swift-ros2)

Native Swift client library for ROS 2. Publish and subscribe to ROS 2 topics over **Zenoh** or **DDS** on every consumer device OS that runs Swift — through the **native RCL backend** (real `rcl` + `rmw_zenoh_cpp` / `rmw_cyclonedds_cpp`; Apple and Linux) or the original pure-Swift **wire path** (`zenoh-pico` / CycloneDDS, no `rcl`; all platforms, now deprecated — see below).

> The four CI badges above all reflect the same `ci.yml` workflow status (GitHub Actions does not expose per-matrix-job badges). Each label is the OS family that workflow exercises — when the badges are green, every Apple / Linux / Windows / Android matrix entry passed.

Shipping on the SemVer-stable **1.x** line (latest tag in the release badge above) — Apple xcframeworks (iOS / iPadOS / macOS / Mac Catalyst / visionOS), `zenoh-pico` source build on Linux / Windows / Android, `swift-ros2-gen` IDL → Swift code generator + SwiftPM build plugin.

## API stability

swift-ros2 1.0.0 inaugurates the [SemVer](https://semver.org/spec/v2.0.0.html) 1.x line: no minor or patch release on 1.x will break the public API. Breaking changes require a 2.0 bump.

The frozen public surface covers `ROS2Context`, `ROS2Node`, `ROS2Publisher`, `ROS2Subscription`, `ROS2Service`, `ROS2Client`, `ROS2ActionServer`, `ROS2ActionClient`, `QoSProfile`, `TransportConfig`, the concrete `ZenohClient` / `DDSClient`, and every `ROS2Message` / `ROS2ServiceType` / `ROS2Action` type. Internal plumbing (`TransportQoS`, `QoSPolicy`, `DDSBridge*`, `ZenohClientProtocol` / `DDSClientProtocol`, `EntityManager`, `GIDManager`, etc.) was pulled out of the public surface at the 1.0 cut — see [`MIGRATION.md`](MIGRATION.md) for the full list and migration recipes.

## Deprecation: the pure-Swift wire path

As of **1.3.0** the recommended runtime is the **native RCL backend** — it is the upstream ROS 2 stack, so type hashes, QoS semantics, the node graph, and introspection match upstream by construction. The pure-Swift wire path (constructing `SwiftROS2Zenoh.ZenohClient` / `SwiftROS2DDS.DDSClient` directly) is **deprecated and will be removed in 2.0.0**:

- The umbrella API is **unchanged and not deprecated**: `.zenoh(locator:)` / `.dds(...)` route to the RCL backend where available and to the wire path elsewhere. Most consumers need no change.
- The wire path **remains fully functional through 1.x** as the automatic fallback where RCL is not yet available (Android; visionOS zenoh; Windows) and as the golden-byte correctness oracle for the CDR/wire codecs.
- Nuance per build variant: in the Apple zenoh-rmw RCL variant the zenoh wire family is **physically absent** (zenoh-pico and the variant's bundled zenoh-c export the same C symbols and cannot co-link), not merely deprecated. On Linux RCL builds both stay linked; RCL is preferred at runtime.
- Direct constructions now emit a deprecation warning; see [`MIGRATION.md`](MIGRATION.md) for the migration recipe.

## Why

Bringing ROS 2 to a phone, headset, or laptop usually means cross-compiling `rcl` + `rclcpp` + a DDS implementation, fighting CMake on a non-Linux host, and shipping a 100+ MB toolchain. swift-ros2 sidesteps all of that by speaking the ROS 2 wire formats directly: a SwiftPM `.package(url:)` line on Apple targets, a single `apt install ros-<distro>-cyclonedds` on Linux, and a vanilla `swift build` on Windows / Android. The publisher / subscription API is Swift-native (`async`/`await`, `AsyncStream`, `Sendable`) and round-trip compatible with the `rmw_zenoh_cpp` and `rmw_cyclonedds_cpp` middlewares.

## Features

- **Dual transport, two backends.** `.zenoh(locator:)` and `.dds(...)` each resolve to the native RCL backend where it exists (upstream-identical type hashes, QoS, and node graph by construction) and to the pure-Swift wire path elsewhere. Switch transports with a single `TransportConfig` change; the public API is backend-agnostic.
- **No mandatory `rcl` toolchain.** Consumers never cross-compile `rcl` / `rclcpp` themselves: Apple targets download prebuilt xcframeworks (including the RCL variants), Linux uses a system ROS 2 install for RCL (`ROS2_RCL_PREFIX`), and the wire path needs no ROS 2 install at all (Windows resolves CycloneDDS through `vcpkg`; Android stays Zenoh-only for now).
- **Swift-native API.** `async`/`await` everywhere, `AsyncStream` subscriptions, `Sendable` conformance, structured concurrency, no opaque pointer juggling above the FFI seam.
- **Pre-built Apple binaries.** `CZenohPico.xcframework` + `CCycloneDDS.xcframework` are attached to every GitHub Release. `swift build` downloads them in seconds — no CMake, no local bootstrap, no Apple-side codesigning dance.
- **Source build everywhere else.** Linux, Windows, and Android compile `zenoh-pico` from `vendor/` via SwiftPM directly, each picking the matching backend (`unix` / `windows`). CycloneDDS comes from `pkg-config` on Linux and `vcpkg` on Windows. No vendored prebuilts needed.
- **Multi-distro wire format.** Humble, Jazzy, Kilted, Rolling. Select via `ROS2Distro` on `ROS2Context`; Zenoh defaults to Jazzy when unspecified. Schema differences (e.g. `sensor_msgs/Range` gaining `variance` after Humble) are gated automatically through `isLegacySchema`.
- **23 built-in message types** spanning `sensor_msgs`, `geometry_msgs`, `std_msgs`, `audio_common_msgs`, and `tf2_msgs`. Pure-Swift XCDR v1 encoder + decoder cover both the publish and subscribe paths.
- **Services** (Server / Client) — `rclcpp` / `rclpy`-shaped API with full Humble / Jazzy / Kilted / Rolling reach over Zenoh and DDS.
- **Actions** (Server / Client) — typed `ROS2ActionServer<H>` / `ROS2ActionClient<A>` with goal handles, feedback `AsyncStream`, status updates, and cancellation. Built-in `example_interfaces/action/Fibonacci`. `async`/`await` everywhere, no callback shims.
- **Code generation from `.msg` / `.srv` / `.action` IDL.** `swift-ros2-gen` CLI + SwiftPM build plugin emit `ROS2Message` / `ROS2ServiceType` / `ROS2Action` Swift conformances. Multi-distro merging branches on `isLegacySchema` for cross-distro field differences (e.g. `sensor_msgs/Range.variance`). Hash-oracle CI catches drift against live ROS 2.
- **Production-proven.** Extracted from [Conduit, powered by ROS](https://apps.apple.com/app/id6757171237) — used cumulatively by **10,000+ ROS developers worldwide** and a former **#4 in the App Store's Developer Tools category**. Conduit streams 12 sensor topics from iOS / iPadOS / macOS / visionOS at up to 100 Hz over the same swift-ros2 publish path documented below.

## Platforms

| Platform              | Minimum target                                 | Integration path                                    | Transports     | CI job per push                       | xcframework slices built at tag time |
|-----------------------|------------------------------------------------|-----------------------------------------------------|----------------|---------------------------------------|--------------------------------------|
| iOS / iPadOS          | 16.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `iphoneos` + `iphonesimulator`       |
| macOS                 | 13.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | `build-macos` (`swift build` + `swift test`) | `macosx`                             |
| Mac Catalyst          | 16.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `maccatalyst`                        |
| visionOS              | 1.0                                            | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `xros` + `xrsimulator`               |
| Linux                 | Ubuntu 22.04 / 24.04 (x86_64, aarch64)         | `zenoh-pico` source build + `pkg-config` for DDS    | Zenoh + DDS    | `build-linux` (×6: 3 distros × 2 arches)  | n/a (source build)                   |
| Windows               | Windows 10 / 11 (x86_64)                       | `zenoh-pico` source build (Winsock + Iphlpapi) + `vcpkg` for DDS | Zenoh + DDS    | `build-windows`                       | n/a (source build)                   |
| Android               | API 28+ (arm64-v8a, x86_64)                    | `zenoh-pico` source build (Bionic, unix backend)    | Zenoh only     | `build-android` (×2 ABIs)             | n/a (source build)                   |

The `build-macos` job runs `swift build` / `swift test` on `macos-26`, which compiles the Swift sources for the macOS host only — that proves the Swift code compiles against the Apple toolchain, but it does *not* drive `xcodebuild` against `iphoneos` / `iphonesimulator` / `maccatalyst` / `xros` / `xrsimulator` destinations. Those non-host Apple slices are built end-to-end only by the [`release-xcframework.yml`](.github/workflows/release-xcframework.yml) workflow at tag time, which produces the `CZenohPico.xcframework` + `CCycloneDDS.xcframework` zips attached to each GitHub release. Per-push runtime validation on iOS / visionOS / Mac Catalyst comes from [Conduit](https://apps.apple.com/app/id6757171237) — the 10K+ developer production user — rather than CI.

**Native RCL backend availability.** The native `rcl`/`rmw` backend (`SwiftROS2RCL`) is available on Apple platforms (prebuilt `CRos2Jazzy` / `CRos2JazzyZenoh` xcframeworks, rmw baked per build variant) and on Linux (system ROS 2 install, rmw selected at runtime from the transport type). **Windows RCL is deferred**: upstream `rmw_zenoh_cpp` has supported Windows since Dec 2024 ([ros2/rmw_zenoh#312](https://github.com/ros2/rmw_zenoh/pull/312)), but no official Jazzy Windows binary ships it (kilted/rolling `ros2.repos` only; the community RoboStack channel aside), swift-ros2's RCL layer is Jazzy-pinned, and Windows verification is CI-only. Windows RCL re-gates when an official Jazzy-compatible Windows binary path exists or the RCL layer supports Kilted. Android RCL (a full-`rcl` NDK cross-build) remains unsolved. Both platforms stay on the pure-Swift wire path.

Swift 5.9+ on Apple platforms; the CI matrix is unified on Swift 6.3.1 across macOS (Xcode 26.4.1), Linux, Windows, and Android (Android SDK from swift.org, matched against the host toolchain `swift sdk install` resolves).

## OS coverage at a glance

ROS 2 is increasingly running on consumer-grade endpoints: phones collecting sensor data, headsets running teleoperation UIs, laptops running rviz / Foxglove, SBCs inside robots. swift-ros2 ships on every major end-user device OS. By worldwide market share ([Statcounter, March 2026](https://gs.statcounter.com/os-market-share)):

| Device class | Covered                                          | Not covered                | Combined share covered             |
|--------------|--------------------------------------------------|----------------------------|------------------------------------|
| Mobile       | iOS 32.3%, Android 67.5%                         | (KaiOS / Samsung ≈ 0.2%)   | **≈ 99.7%** of the mobile market   |
| Desktop      | Windows 60.8%, macOS 14.8%, Linux 3.2%           | ChromeOS 1.6% (rest is Statcounter's "Unknown" bucket) | **≈ 78.7%** of the desktop market  |
| XR           | visionOS                                         | Meta Quest / Pico / OpenXR-on-Android-arm not yet supported | (small market today, Apple Vision Pro install base only) |
| All devices  | Android 37.9% + iOS 18.6% + Windows 26.3% + macOS 6.4% + Linux 1.4% | ChromeOS, KaiOS, etc.       | **≈ 90.7%** of identifiable share  |

In practice this means almost every consumer device that someone might want to attach to a ROS 2 graph — a phone publishing sensor data, a tablet running a teleoperation UI, a Windows or macOS laptop running rviz / Foxglove, a Linux SBC inside a robot — can publish and subscribe through the same SwiftPM-resolvable package.

## Installation

### Apple platforms (recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "1.0.0"),
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

`swift build` downloads the Apple xcframework binaries that `Package.swift` pins. (The pin lags one PR behind every tag — the URL + checksums are bumped in a follow-up "pin release URL + xcframework checksums" PR once `release-xcframework.yml` has attached the zips and the GitHub-hosted SHA-256s exist. Practically that means a consumer who pins `from: "X.Y.Z"` resolves to the X.Y.Z commit and downloads whatever binaries that commit's manifest was pointing at, which is usually the previous release's; tracking `main` always picks up the latest pinned URL.) The high-level API arrives via `import SwiftROS2`, which exposes `ROS2Context` / `ROS2Node` / `ROS2Publisher` / `ROS2Subscription` and transitively links `SwiftROS2Zenoh` + `SwiftROS2DDS`. Add `SwiftROS2Zenoh` / `SwiftROS2DDS` to your target dependencies only if you want to call `ZenohClient` / `DDSClient` by name (e.g. for custom session config or test mocks) — they are *depended on* by the umbrella but not `@_exported` from it.

### Linux

```bash
sudo apt install ros-jazzy-cyclonedds        # or ros-humble / ros-rolling
git clone --recursive https://github.com/youtalk/swift-ros2.git
cd swift-ros2
bash Scripts/build-linux-deps.sh             # verifies pkg-config finds CycloneDDS

# Re-export in the current shell — build-linux-deps.sh sets these only inside its own subprocess.
source /opt/ros/jazzy/setup.bash
export PKG_CONFIG_PATH=/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:$PKG_CONFIG_PATH

swift build
swift test                                    # 69 pass, 2 LINUX_IP-gated skips
```

### Windows

Windows supports both transports. Zenoh builds `vendor/zenoh-pico` from source (no extra setup); DDS resolves CycloneDDS through [vcpkg](https://vcpkg.io) — install the port once and point `CYCLONEDDS_DIR` at the install tree before `swift build`. Without `CYCLONEDDS_DIR`, the manifest stays Zenoh-only (same shape as 0.5.0–0.7.0).

```powershell
# One-time CycloneDDS install via vcpkg.
vcpkg install cyclonedds:x64-windows

# Each shell that runs `swift build` needs CYCLONEDDS_DIR pointed at the
# vcpkg install tree, plus bin/ on PATH so ddsc.dll resolves at runtime.
$env:CYCLONEDDS_DIR = "$env:VCPKG_ROOT\installed\x64-windows"
$env:Path = "$env:CYCLONEDDS_DIR\bin;$env:Path"
```

```swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "1.0.0"),
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

Requires Swift 6.3.1. No `setup.bash` or `PKG_CONFIG_PATH` step — `swift build` reads `CYCLONEDDS_DIR` and threads `-I<dir>/include` + `-L<dir>/lib` into CDDSBridge directly.

### Android (cross-compile from macOS or Linux)

Install the Swift 6.3.1 Android SDK from [swift.org/install/android](https://www.swift.org/install/android/) (point release matched to the host Swift toolchain — CI uses 6.3.1):

```bash
swift sdk install <android-sdk-url> --checksum <sha>
swift sdk list                                # should list aarch64-unknown-linux-android28 and x86_64-unknown-linux-android28
```

The Android SDK's `.artifactbundle` ships `swift-resources/` and `swift-android/scripts/setup-android-sdk.sh` but no prebuilt `ndk-sysroot/`. Install Android NDK ≥ r27 (we test against r27c) and run the bundled script once to symlink the NDK sysroot into place:

```bash
ANDROID_NDK_HOME=/path/to/ndk \
  ~/.config/swiftpm/swift-sdks/swift-*-android-*.artifactbundle/swift-android/scripts/setup-android-sdk.sh
```

Cross-compile:

```bash
SWIFT_ROS2_TARGET_OS=android swift build --swift-sdk aarch64-unknown-linux-android28
# or x86_64-unknown-linux-android28 for emulator targets
```

`SWIFT_ROS2_TARGET_OS=android` is required whenever the host OS differs from the target — both Linux → Android and macOS → Android. SwiftPM evaluates manifest-scope `#if os(...)` against the host, so without the override a Linux host would pull in the DDS path that isn't buildable for Android, and a macOS host would pick the Apple `binaryTarget` arm and never source-build `zenoh-pico` for Android at all. The variable is validated against an allow-list (`{android, apple, linux, windows}`) and any typo fails the manifest compile with a `fatalError` naming the offending value.

```swift
import SwiftROS2Zenoh    // the SwiftROS2 umbrella isn't built on Android — same carve-out as Windows
```

## Quick Start

> **Android note:** the examples below use the `SwiftROS2` umbrella, which is excluded on Android (Windows now ships the umbrella when `CYCLONEDDS_DIR` is set, see above). Use `SwiftROS2Zenoh.ZenohClient` directly on Android; the high-level `ROS2Context` / `ROS2Node` wrappers land there when DDS does (see [Roadmap](#roadmap)).

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
// Identical Node / Publisher / Subscription API from here on.
```

### Subscribe

```swift
let sub = try await node.createSubscription(Imu.self, topic: "imu")
for await msg in sub.messages {
    print("accel: \(msg.linearAcceleration)")
}
```

### Services (Server / Client)

`ROS2Service<S>` and `ROS2Client<S>` round-trip a typed request / response over either transport — the same code path works against `rmw_zenoh_cpp` (Zenoh queryables) and `rmw_cyclonedds_cpp` (DDS rq/rr topics). Built-in `std_srvs/srv/Trigger` is the smallest demo:

```swift
// Server — replies "ok" to every Trigger request.
let svc = try await node.createService(TriggerSrv.self, name: "/trigger") { _ in
    TriggerSrv.Response(success: true, message: "ok")
}

// Client — calls the service and prints the result.
let cli = try await node.createClient(TriggerSrv.self, name: "/trigger")
try await cli.waitForService(timeout: .seconds(5))
let resp = try await cli.call(.init(), timeout: .seconds(5))
print(resp.success, resp.message)
```

Failures (timeout, remote handler error, encoding / decoding) surface as `ServiceError` — pattern-match on `.timeout(_)`, `.handlerFailed(_)`, `.serviceUnavailable(_)`, `.taskCancelled`, etc.

### Parameters

Each `ROS2Node` exposes the standard six `rcl_interfaces` parameter services
under `<node_fqn>/<service>`, plus a `/parameter_events` publisher. Declare
parameters from Swift; remote tools (`ros2 param`, `rqt_param`) interoperate
unchanged.

```swift
let node = try await ctx.createNode(name: "talker")
_ = try await node.declareParameter(
    "rate", default: Int64(30),
    descriptor: ROS2ParameterDescriptor(
        name: "rate", type: .integer, integerRange: Int64(1)...Int64(120)))

_ = await node.setOnSetParametersCallback { proposed in
    // Inspect proposed changes; return .failure(reason:) to veto.
    .success()
}
```

From a second terminal:

```bash
ros2 param list /talker
ros2 param set  /talker rate 60
ros2 topic echo /parameter_events
```

A runnable demo lives in [`Sources/Examples/ParameterDemo`](Sources/Examples/ParameterDemo/main.swift) — try `swift run parameter-demo zenoh`.

To call a remote node's parameters from Swift:

```swift
let pc = try await node.createParameterClient(remoteNode: "/talker")
try await pc.waitForService(timeout: .seconds(2))
let values = try await pc.getParameters(["rate"])
```

### Runnable examples

End-to-end `talker` / `listener` demos modeled on `demo_nodes_cpp` — `swift run talker zenoh`, `swift run listener dds`, etc. — live under [`Sources/Examples/README.md`](Sources/Examples/README.md), with instructions for wiring them up to `ros2 topic echo` / `ros2 topic pub` on the ROS 2 side.

## Module layout

```
import SwiftROS2          // public API — re-exports CDR / Messages / Transport / Wire only
    ├── SwiftROS2CDR        — XCDR v1 encoder + decoder (pure Swift, no deps)
    ├── SwiftROS2Wire       — Zenoh / DDS wire codecs, ROS2Distro, TypeNameConverter
    ├── SwiftROS2Messages   — ROS2Message protocols + 23 built-in types
    └── SwiftROS2Transport  — TransportSession / TransportConfig / EntityManager / GIDManager

// Transport modules: depended on by SwiftROS2 (so the high-level
// ROS2Context / ROS2Node API works after `import SwiftROS2`), but
// NOT @_exported — import them explicitly to reach ZenohClient /
// DDSClient.
import SwiftROS2Zenoh      — ZenohClient (zenoh-pico FFI through CZenohBridge)
import SwiftROS2DDS        — DDSClient (CycloneDDS FFI through CDDSBridge)
```

The architecture is documented in more detail under [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

> **Link-only C targets.** `CZenohPico` and `CCycloneDDS` are link-only binary targets — they are consumed at the C level by `CZenohBridge` / `CDDSBridge` (with platform-specific preprocessor defines applied through `cSettings`) and **never `import`ed from Swift directly**. On Apple, `.xcframework`'s auto-synthesised modulemap means `import CZenohPico` happens to compile silently — but the equivalent on a future Linux `.artifactbundle` would not, so a CI lint (`grep -P '^import C(ZenohPico|CycloneDDS)\b'` over `Sources` and `Tests`) guards against any such import from leaking in. Reach the C bridges via `import SwiftROS2Zenoh` / `import SwiftROS2DDS`.

### Built-in message types

- **`sensor_msgs`** (13) — `BatteryState`, `CameraInfo`, `CompressedImage`, `FluidPressure`, `Illuminance`, `Image`, `Imu`, `Joy`, `MagneticField`, `NavSatFix`, `PointCloud2`, `Range`, `Temperature`
- **`geometry_msgs`** (3 publishable + utility types) — `PoseStamped`, `TransformStamped`, `TwistStamped`; sub-types `Vector3` / `Quaternion` / `Point` / `Pose` / `Twist` / `Transform`
- **`std_msgs`** (5) — `BoolMsg`, `EmptyMsg`, `Float64Msg`, `Int32Msg`, `StringMsg`; plus the universal `Header`
- **`audio_common_msgs`** (1) — `AudioData`
- **`tf2_msgs`** (1) — `TFMessage`

## Defining a custom message type

```swift
import SwiftROS2CDR
import SwiftROS2Messages

public struct MyMsg: ROS2Message {
    public static let typeInfo = ROS2MessageTypeInfo(
        typeName: "my_pkg/msg/MyMsg",
        typeHash: "RIHS01_…"      // get from `ros2 topic info /topic --verbose`
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

As of 0.9.0 the [`swift-ros2-gen`](#generate-swift-bindings-from-idl) code generator is the recommended way to produce these conformances — hand-written conformances like the example above become optional. The generator emits the same shape from `.msg` / `.srv` / `.action` files automatically; `RIHS01_*` type hashes are computed in-process from the parsed IDL, then optionally cross-checked against a live ROS 2 install via `--verify-hashes`.

## Generate Swift bindings from IDL

`swift-ros2-gen` reads ROS 2 `.msg` / `.srv` / `.action` IDL files and emits Swift sources that conform to `ROS2Message` / `ROS2ServiceType` / `ROS2Action`. The generator handles fixed and variable arrays, constants, default values, nested type references, and merges multi-distro inputs into a single Swift source that branches on `isLegacySchema` for fields that differ between Humble and Jazzy+.

### One-shot CLI

`sensor_msgs` types reference `std_msgs/Header`, `builtin_interfaces/Time`, and several `geometry_msgs` types — pass every transitively-referenced package on `--input` so nested-type resolution succeeds:

```bash
swift run swift-ros2-gen \
    --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
    --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
    --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
    --input "sensor_msgs=vendor/common_interfaces-humble/sensor_msgs@humble" \
    --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy" \
    --output Sources/MyMessages/Generated
```

Pass one `--input <pkg>=<path>@<distro>` per (package, distro) pair. The generator walks `msg/`, `srv/`, and `action/` subdirectories of each package automatically.

### SwiftPM build plugin

For projects that want generated bindings to stay in sync with their IDL on every build, opt the target into the `SwiftROS2GenPlugin`:

```swift
.target(
    name: "my_msgs",
    dependencies: [
        .product(name: "SwiftROS2", package: "swift-ros2"),
    ],
    plugins: [
        .plugin(name: "SwiftROS2GenPlugin", package: "swift-ros2"),
    ]
)
```

Drop the IDL into the target's directory under `msg/`, then build. There is no configuration file — the plugin walks `msg/` directly, hands every `.msg` to `swift-ros2-gen` with `<target-name>=<dir>@jazzy`, and writes the output under SwiftPM's per-target work directory. The target name becomes the ROS package segment in the generated `typeInfo.typeName`, so name the target snake_case / lowercase — `my_msgs`, not `MyMsgs`.

The plugin handles the single-package single-distro (jazzy) `.msg` case only. `.srv` and `.action` files in the target directory are skipped with a build warning. For multi-distro merging, multi-package builds, `.srv`, `.action`, or an explicit `--types` allow-list, invoke `swift run swift-ros2-gen` directly (`--help` lists every flag). A working setup lives at [`Sources/Examples/PluginSmoke/`](Sources/Examples/PluginSmoke).

### Verifying generated hashes against live ROS 2

The repo ships a hash-oracle CI job ([`.github/workflows/hash-oracle.yml`](.github/workflows/hash-oracle.yml), `verify-hash-oracle`, path-filtered to fire only when generator / generated-source / vendored-IDL paths change). It diffs each generated `RIHS01_*` against the canonical `share/<pkg>/{msg,srv,action}/<Type>.json` files inside an `osrf/ros:<distro>-desktop` Docker image — there is no recorded baseline shipped in the package; the oracle is the live image. Reproduce locally with the same command CI runs (`--verify-hashes` takes a Docker image as its value, and the verifier resolves nested-type references, so every transitively-referenced package must appear on `--input`):

```bash
swift run swift-ros2-gen --verify-hashes osrf/ros:jazzy-desktop \
    --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
    --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
    --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
    --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy"
```

## Versioning

Tags follow Apple-ecosystem bare semver (no `v` prefix): `0.2.0`, `1.0.0-rc.1`, etc. The [release workflow](.github/workflows/release-xcframework.yml) fires on any tag matching `[0-9]*.[0-9]*.[0-9]*` (optionally `-qualifier`), builds both xcframeworks for all six Apple slices (`iphoneos`, `iphonesimulator`, `macosx`, `maccatalyst`, `xros`, `xrsimulator`), and attaches them + `.checksum` files to the GitHub release named after the tag.

The `0.x` series was pre-1.0 by design — breaking API changes were allowed between minor versions while the public surface stabilized around Services (0.7.0), Actions (0.8.0), and `swift-ros2-gen` (0.9.0). With those milestones landed, 1.0.0 will freeze the public API surface; subsequent 1.x releases follow standard SemVer.

## Release history

Each release has a corresponding [GitHub release](https://github.com/youtalk/swift-ros2/releases) with auto-generated notes; the summaries below capture the headline change.

| Tag        | Date       | Headline                                                                                              |
|------------|------------|-------------------------------------------------------------------------------------------------------|
| **1.2.0**  | 2026-06-06 | **Source-timestamp publish overload** — additive `ROS2Publisher.publish(_:timestamp:sequenceNumber:)` lets callers stamp messages with the sensor-acquisition time and their own sequence number instead of the publish-time defaults; the existing `publish(_:)` is unchanged and delegates to the overload with the wall-clock timestamp + monotonic sequence (#117). |
| 1.1.1      | 2026-05-16 | **iOS `xcodebuild` fix for `SwiftROS2GenPlugin` consumers** — `xcodebuild` compiles a build-tool plugin's tool for the consuming target's destination platform, so any package that added `SwiftROS2GenPlugin` to a target could not be built for iOS / iOS Simulator. `swift-ros2-gen`'s `@main` entry point is moved off `main.swift` so the module compiles with `-parse-as-library`, and `SwiftROS2Gen`'s host-only `Process` / `Pipe` Docker path (`--verify-hashes`) is guarded behind `#if os(macOS) || os(Linux) || os(Windows)`. No public API or wire-format change; the prebuilt xcframeworks are unaffected (#113). |
| 1.1.0      | 2026-05-06 | **ROS 2 Parameter API** — every `ROS2Node` declares typed parameters with descriptors and ranges; the six standard `rcl_interfaces` services auto-register on `<node_fqn>/<service>`; `/parameter_events` publishes on every successful declare / set / undeclare; pre-set / on-set (with veto) / post-set callbacks; `ROS2ParameterClient` for remote nodes; new `QoSProfile.parameterEvents` preset. Wire-compatible with `ros2 param list/get/set/describe` over both `rmw_zenoh_cpp` and `rmw_cyclonedds_cpp`. 6 PR rollout (#102–#107). Purely additive — opt out per node via `ROS2NodeOptions(startParameterServices: false)`. |
| 1.0.0      | 2026-05-05 | **API stability promise (1.x SemVer freeze)** — six visibility-only demotions pull plumbing types out of the public API: `TransportQoS` / `QoSPolicy`, the DDS bridge config trio, `ZenohClientProtocol` / `DDSClientProtocol` and 10 related handle / sample / error types (with `TransportSession` / `TransportPublisher` / `TransportSubscriber` and the 4-arg `ROS2Context.init(... session:)` demoted as a knock-on), `EntityManager` / `GIDManager`, `ZenohTransportPublisher`, `DeclaredKeyExpr` / `ZenohSubscriber` / `LivelinessToken`. End-user types unchanged; `ZenohClient()` / `DDSClient()` remain `public`. See [`MIGRATION.md`](MIGRATION.md) for the full table. |
| 0.9.0      | 2026-05-04 | **`swift-ros2-gen`** — IDL → Swift code generator (CLI + SwiftPM build plugin) covering `.msg` / `.srv` / `.action`, multi-distro merging with `isLegacySchema` branches, and a `verify-hash-oracle` CI job that diffs generated `RIHS01_*` hashes against the canonical `share/<pkg>/{msg,srv,action}/<Type>.json` files inside an `osrf/ros:<distro>-desktop` Docker image. 8 PR rollout (Phase 1–8). |
| 0.8.0      | 2026-05-03 | **Actions + DDS on Windows** — typed `ROS2ActionServer<H>` / `ROS2ActionClient<A>` with `async`/`await`, feedback `AsyncStream`, status updates, cancellation; built-in `example_interfaces/action/Fibonacci`; full DDS path on Windows x86_64 via vcpkg (`CYCLONEDDS_DIR`). 6 PR rollout for Actions. |
| 0.7.0      | 2026-05-01 | **Services** — typed `ROS2Service<S>` / `ROS2Client<S>` over both Zenoh (queryable + `get`) and DDS (rq/rr topics + sample-identity prefix); built-in `std_srvs/srv/Trigger`; DocC catalog with getting-started articles; CI `docs-build` job; per-target line-coverage gate. |
| 0.6.0      | 2026-04-24 | **Android support** — arm64-v8a + x86_64 via the Swift 6.3.1 Android SDK; `zenoh-pico` source build with `ZENOH_ANDROID` (Bionic unix backend, vendored `pthread_cancel` / `_z_task_cancel` stubs); `SWIFT_ROS2_TARGET_OS` env override required for any cross-compile (allow-list-validated, fails the manifest compile on typos); `build-android` matrix (×2 ABIs) added to CI on `ubuntu-24.04` with NDK r27c. Zenoh only — DDS-on-Android tracked as future work. |
| 0.5.0      | 2026-04-24 | **Windows x86_64 support** — three-arm `Package.swift` platform split, `zenoh-pico` source build with `ZENOH_WINDOWS` and Winsock + Iphlpapi linkage, `build-windows` job on `windows-latest` (Swift 6.3.1). Zenoh only.                                                                                              |
| 0.4.0      | 2026-04-20 | **DDS subscriber** — `raw_cdr_serdata_from_ser` fragchain walk in `CDDSBridge`, `bridge_dds_reader_t` + listener callback, `DDSReaderHandle` / `createRawReader` / `destroyReader` on `DDSClientProtocol`, `DDSTransportSession.createSubscriber` wired through; `swift run listener dds` enabled. Minimal `talker` / `listener` example executables added. |
| 0.3.1      | 2026-04-19 | **Hardened CDR decoder** — bounds-checks untrusted sequence + string lengths before `reserveCapacity`; fails fast on malformed null-terminated strings instead of silently dropping bytes. |
| 0.3.0      | 2026-04-19 | **API rename (breaking)** — drop `Default` prefix from `ZenohClient` / `DDSClient`. CI matrix expanded to Linux arm64 + ROS 2 Rolling, plus Ubuntu 22.04 + ROS 2 Humble. |
| 0.2.0      | 2026-04-18 | **Initial public release** — Publisher + Subscriber core, pure-Swift XCDR v1 encoder/decoder, Jazzy + Humble wire codecs, dual-transport (Zenoh + DDS) FFI, Apple xcframeworks via GitHub Releases, Linux source build via SwiftPM. |

## Roadmap

Past releases shipped roughly one breaking platform / transport / API change per week. The list below is what's queued — concrete deliverables, not aspirational vapor.

### Near-term (next 1.x minor)

1.0.0 froze the public API; 1.1.0 added the Parameter API. Up next on the 1.x line — purely additive features that keep the surface frozen.

- **Expanded message catalog** — `nav_msgs`, `visualization_msgs`, `diagnostic_msgs`, more of `geometry_msgs`. Generated via `swift-ros2-gen` rather than hand-rolled.
- **TF / TF2** — `tf2_msgs` is already built-in (Phase 4); the missing piece is the runtime layer (`TransformBroadcaster`, `StaticTransformBroadcaster`, `Buffer` + `TransformListener`, lookup with timeout). API shape mirrors `tf2_ros` so robot code ports cleanly.
- **Logging / `/rosout`** — `Logger` API on `ROS2Node` (`info` / `warn` / `error` / `debug`) that publishes `rcl_interfaces/msg/Log` to `/rosout` with `rmw_qos_profile_rosout` semantics, and bridges Foundation's `os.Logger` so existing code lights up the bus for free.

### Medium-term

- **DDS on Android** — currently blocked on SwiftPM not orchestrating CycloneDDS's `ddsrt` CMake-configure-time header generation under the Android NDK toolchain. Likely path: a prebuilt `.artifactbundle` for Android, similar to the Apple xcframeworks but in SPM artifact-bundle format. (DDS on Windows landed in 0.8.0 via the `vcpkg` + `CYCLONEDDS_DIR` approach.)
- **XCDR2 wire format** — only XCDR v1 is implemented today. XCDR v2 is required for some Rolling-era message types. Additive (new init flag on `CDRDecoder`).
- **Lifecycle Node** — `LifecycleNode` with the standard nine-state machine and `lifecycle_msgs` services (`change_state`, `get_state`, `get_available_states`, `get_available_transitions`, `get_transition_graph`). Wire-compatible with `ros2 lifecycle list/set/get`.
- **Composition / intra-process** — same-process `Publisher` ↔ `Subscription` short-circuit (no serialize → wire → deserialize round-trip). Zenoh-side intra-session transport + DDS-side `iceoryx` / shared-memory transport.
- **Discovery control** — honor `ROS_AUTOMATIC_DISCOVERY_RANGE` (`OFF` / `LOCALHOST` / `SUBNET` / `SYSTEM_DEFAULT`) and `ROS_STATIC_PEERS` env vars on context init for `rclcpp` parity.

### Stretch

- **Linux static `.artifactbundle`** — replace the `pkg-config + setup.bash` dance with a self-contained download. Prototyped and rejected for 0.5.0; might revisit once the SPM + system-library story improves.
- **`watchOS` / `tvOS` xcframework slices** — would require `Z_FEATURE_LINK_TCP` validation under those SDKs and a `Sendable` audit for `WCSession`-style flows.
- **OpenXR-on-Android-arm bring-up** — extends the XR coverage row above beyond visionOS once a credible runtime exists for Quest / Pico headsets.
- **Bag (rosbag2) read/write** — `mcap` is pure C and the most tractable backend for a Swift binding; sqlite3 backend is a longer poll. Record / replay for offline data collection.
- **DDS Security** — auth / access-control / encryption via CycloneDDS's DDS Security plugins. Production deployments only; gated on real demand.
- **Action server fan-out** — `cancel_all_goals` / streaming `goal_status_array` accumulators that 0.8.0 punted on. Additive on top of the existing `ROS2ActionServer<H>`.
- **`xacro` / URDF parsing** — pure-Swift parser of the URDF subset Conduit-style apps actually need. No rendering, no kinematics — just the parse tree.

## Contributing

PRs welcome. The wire-format fixtures in [`Tests/SwiftROS2WireTests/`](Tests/SwiftROS2WireTests/) and the golden CDR tests in [`Tests/SwiftROS2CDRTests/`](Tests/SwiftROS2CDRTests/) are the canonical guardrails — keep them green. [`Tests/SwiftROS2IntegrationTests/`](Tests/SwiftROS2IntegrationTests/) boots a real ROS 2 subscriber on a Linux host; set `LINUX_IP=<host>` locally to exercise it.

Lint with `swift format lint --strict --configuration .swift-format Package.swift Sources Tests` before pushing — CI fails the lint step before any of the build matrices run.

## License

Apache License 2.0. See [LICENSE](LICENSE).
