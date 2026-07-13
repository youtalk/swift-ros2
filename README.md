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

Native Swift client library for ROS 2. Publish and subscribe to ROS 2 topics over **Zenoh** or **DDS** on every consumer device OS that runs Swift — no `rcl` cross-compile, no bridge. A single `.package(url:)` on Apple, `apt install ros-<distro>-cyclonedds` on Linux, a vanilla `swift build` on Windows / Android. The API is Swift-native (`async`/`await`, `AsyncStream`, `Sendable`) and round-trip compatible with `rmw_zenoh_cpp` / `rmw_cyclonedds_cpp`.

Shipping on the SemVer-stable **1.x** line (latest tag in the release badge). Extracted from [Conduit, powered by ROS](https://apps.apple.com/app/id6757171237) — used cumulatively by **10,000+ ROS developers** and a former **#4** in the App Store's Developer Tools category.

## Quick Start

> **Android:** the umbrella is excluded on Android — use `SwiftROS2Zenoh.ZenohClient` directly until DDS (and the umbrella) land there.

```swift
import SwiftROS2

// Publish an IMU message over Zenoh.
let context = try await ROS2Context(
    transport: .zenoh(locator: "tcp/192.168.1.100:7447"), distro: .jazzy)
let node = try await context.createNode(name: "sensor_node", namespace: "/ios")
let pub = try await node.createPublisher(Imu.self, topic: "imu")
try pub.publish(Imu(
    header: Header.now(frameId: "imu_link"),
    linearAcceleration: Vector3(x: 0, y: 0, z: 9.81)))

// Same over DDS — identical Node / Publisher / Subscription API from here on.
let ddsContext = try await ROS2Context(transport: .ddsMulticast(domainId: 0))

// Subscribe.
let sub = try await node.createSubscription(Imu.self, topic: "imu")
for await msg in sub.messages { print("accel: \(msg.linearAcceleration)") }
```

### Services

`ROS2Service<S>` / `ROS2Client<S>` round-trip a typed request / response over either transport (Zenoh queryables or DDS rq/rr topics). Failures surface as `ServiceError` (`.timeout`, `.handlerFailed`, `.serviceUnavailable`, `.taskCancelled`, …).

```swift
let svc = try await node.createService(TriggerSrv.self, name: "/trigger") { _ in
    TriggerSrv.Response(success: true, message: "ok")
}
let cli = try await node.createClient(TriggerSrv.self, name: "/trigger")
try await cli.waitForService(timeout: .seconds(5))
let resp = try await cli.call(.init(), timeout: .seconds(5))
```

### Parameters, Actions, and runnable examples

Declare typed parameters (`node.declareParameter` + on-set veto callbacks; interoperates with `ros2 param list/set` and `/parameter_events`) and typed actions (`node.createActionServer` / `createActionClient` with goal handles and feedback `AsyncStream`). End-to-end `talker` / `listener` demos modeled on `demo_nodes_cpp` — `swift run talker zenoh`, `swift run listener dds`, `swift run parameter-demo zenoh` — live under [`Sources/Examples/README.md`](Sources/Examples/README.md).

## Backends: RCL (1.3.0+) and the wire path (deprecated, removed in 2.0.0)

Two backends sit behind one backend-agnostic umbrella API. `.zenoh(locator:)` / `.dds(...)` resolve automatically:

- **Native RCL backend** (recommended, default where available) — the real upstream stack (`rcl` + `rmw_zenoh_cpp` / `rmw_cyclonedds_cpp`), so type hashes, QoS semantics, the node graph, and introspection match upstream by construction. As of **1.3.0** it is available on **Apple** (prebuilt `CRos2Jazzy` / `CRos2JazzyZenoh` xcframeworks, one rmw baked per build variant, **on by default**) and **Linux** (system ROS 2 install via `ROS2_RCL_PREFIX`, rmw chosen at runtime from the transport type).
- **Pure-Swift wire path** (`zenoh-pico` / CycloneDDS, no `rcl`) — the original all-platforms backend. It remains the automatic fallback where RCL isn't available yet (Android; visionOS zenoh; Windows) and the golden-byte oracle for the CDR / wire codecs.

**The wire path is deprecated as of 1.3.0 and will be removed in 2.0.0.** Only *direct construction* of the wire clients is deprecated:

```swift
import SwiftROS2Zenoh
let client = ZenohClient()   // ⚠️ deprecated, removed in 2.0.0
import SwiftROS2DDS
let dds = DDSClient()        // ⚠️ deprecated, removed in 2.0.0
```

The umbrella API is **unchanged and not deprecated** — most consumers need no change:

```swift
let ctx = try await ROS2Context(transport: .zenoh(locator: "tcp/192.168.1.85:7447"))
```

If you only build `ZenohClient` / `DDSClient` to hand to `ROS2Context`, drop the explicit construction. If you use them standalone (raw key-expression puts, wire-level subscribers), plan the move to the umbrella API before 2.0.0 — the wire *runtime* path is removed there, while the CDR / wire codecs survive as golden-byte fixtures. Full recipes in [`MIGRATION.md`](MIGRATION.md).

> **Per-variant nuance.** In the Apple zenoh-rmw RCL variant (`SWIFT_ROS2_RCL_RMW=zenoh`) the zenoh wire family is *physically absent* (zenoh-pico and the bundled zenoh-c export the same C symbols and cannot co-link) — `ZenohClient` doesn't exist there at all. On Linux RCL builds both backends stay linked (rmw is a dlopen'd plugin); RCL is preferred at runtime. **Windows RCL is deferred** — no official Jazzy Windows binary ships `rmw_zenoh_cpp` and swift-ros2's RCL layer is Jazzy-pinned; re-gates on an official Jazzy binary or Kilted support. **Android RCL** (full-`rcl` NDK cross-build) remains unsolved.

## API stability

1.0.0 inaugurated the [SemVer](https://semver.org/spec/v2.0.0.html) 1.x line: no minor or patch release breaks the public API — breaking changes require a 2.0 bump. The frozen surface covers `ROS2Context`, `ROS2Node`, `ROS2Publisher`, `ROS2Subscription`, `ROS2Service`, `ROS2Client`, `ROS2ActionServer`, `ROS2ActionClient`, `QoSProfile`, `TransportConfig`, the concrete `ZenohClient` / `DDSClient`, and every `ROS2Message` / `ROS2ServiceType` / `ROS2Action` type. See [`MIGRATION.md`](MIGRATION.md) for the internal-plumbing demotions made at the 1.0 cut and the 2.0 wire-removal plan.

## Features

- **Dual transport, two backends, one API.** `.zenoh(locator:)` / `.dds(...)` resolve to the RCL backend where it exists and the wire path elsewhere. Switch transports with a single `TransportConfig` change.
- **No mandatory `rcl` toolchain.** Apple downloads prebuilt xcframeworks (including the RCL variants); Linux uses a system ROS 2 install for RCL; the wire path needs no ROS 2 install at all (Windows resolves CycloneDDS via `vcpkg`; Android is Zenoh-only).
- **Swift-native API.** `async`/`await` everywhere, `AsyncStream` subscriptions, `Sendable`, structured concurrency, no opaque pointer juggling above the FFI seam.
- **Multi-distro.** Humble, Jazzy, Kilted, Rolling — select via `ROS2Distro` (Zenoh defaults to Jazzy). Schema differences (e.g. `sensor_msgs/Range.variance`, added after Humble) are gated automatically via `isLegacySchema`.
- **23 built-in message types** across `sensor_msgs`, `geometry_msgs`, `std_msgs`, `audio_common_msgs`, `tf2_msgs`, on a pure-Swift XCDR v1 encoder + decoder.
- **Services & Actions** — `rclcpp` / `rclpy`-shaped `ROS2Service` / `ROS2Client` and typed `ROS2ActionServer<H>` / `ROS2ActionClient<A>` (goal handles, feedback `AsyncStream`, cancellation) over both transports, all distros.
- **Parameters** — every `ROS2Node` declares typed parameters with descriptors / ranges, auto-registers the six standard `rcl_interfaces` services, and publishes `/parameter_events`; interoperates with `ros2 param`.
- **Code generation from IDL.** `swift-ros2-gen` CLI + SwiftPM build plugin emit `ROS2Message` / `ROS2ServiceType` / `ROS2Action` conformances from `.msg` / `.srv` / `.action`, with multi-distro merging and a hash-oracle CI that catches drift against live ROS 2.

## Platforms

| Platform     | Minimum target                          | Integration path                                                | Transports   |
|--------------|-----------------------------------------|-----------------------------------------------------------------|--------------|
| iOS / iPadOS | 16.0                                    | `binaryTarget` xcframework                                       | Zenoh + DDS  |
| macOS        | 13.0                                    | `binaryTarget` xcframework                                       | Zenoh + DDS  |
| Mac Catalyst | 16.0                                    | `binaryTarget` xcframework                                       | Zenoh + DDS  |
| visionOS     | 1.0                                     | `binaryTarget` xcframework                                       | Zenoh + DDS  |
| Linux        | Ubuntu 22.04 / 24.04 (x86_64, aarch64)  | `zenoh-pico` source build + `pkg-config` for DDS                | Zenoh + DDS  |
| Windows      | Windows 10 / 11 (x86_64)                | `zenoh-pico` source build (Winsock) + `vcpkg` for DDS           | Zenoh + DDS  |
| Android      | API 28+ (arm64-v8a, x86_64)             | `zenoh-pico` source build (Bionic, unix backend)                | Zenoh only   |

Swift 5.9+ on Apple; the CI matrix is unified on Swift 6.3.1 across macOS (Xcode 26.4.1), Linux, Windows, and Android. By worldwide market share ([Statcounter, March 2026](https://gs.statcounter.com/os-market-share)) swift-ros2 covers **≈99.7%** of the mobile market and **≈90.7%** of identifiable device share — nearly every consumer device you might attach to a ROS 2 graph. Non-host Apple slices are built end-to-end by [`release-xcframework.yml`](.github/workflows/release-xcframework.yml) at tag time; per-push iOS / visionOS / Mac Catalyst runtime validation comes from Conduit rather than CI. Architecture: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Installation

### Apple (recommended)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "1.0.0"),
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "SwiftROS2", package: "swift-ros2"),
    ]),
]
```

`swift build` downloads the pinned xcframeworks in seconds — no CMake, no local bootstrap. `import SwiftROS2` exposes `ROS2Context` / `ROS2Node` / `ROS2Publisher` / `ROS2Subscription` and transitively links `SwiftROS2Zenoh` + `SwiftROS2DDS`; add those to your target dependencies only to name `ZenohClient` / `DDSClient` directly. (The URL pin lags one PR behind each tag — pinning `from: "X.Y.Z"` resolves to the X.Y.Z commit; tracking `main` always picks up the latest pinned binaries.)

### Linux

```bash
sudo apt install ros-jazzy-cyclonedds        # or ros-humble / ros-rolling
git clone --recursive https://github.com/youtalk/swift-ros2.git && cd swift-ros2
bash Scripts/build-linux-deps.sh             # verifies pkg-config finds CycloneDDS

# Re-export in the current shell — build-linux-deps.sh sets these only in its subprocess.
source /opt/ros/jazzy/setup.bash
export PKG_CONFIG_PATH=/opt/ros/jazzy/lib/$(uname -m)-linux-gnu/pkgconfig:$PKG_CONFIG_PATH

swift build
swift test                                    # 69 pass, 2 LINUX_IP-gated skips
```

### Windows

Both transports. Zenoh builds from source with no extra setup; DDS resolves CycloneDDS through [vcpkg](https://vcpkg.io). Requires Swift 6.3.1. Without `CYCLONEDDS_DIR`, the manifest stays Zenoh-only.

```powershell
vcpkg install cyclonedds:x64-windows
$env:CYCLONEDDS_DIR = "$env:VCPKG_ROOT\installed\x64-windows"
$env:Path = "$env:CYCLONEDDS_DIR\bin;$env:Path"   # so ddsc.dll resolves at runtime
```

Then add the same `.package(url:)` dependency as Apple. `swift build` threads `-I<dir>/include` + `-L<dir>/lib` into CDDSBridge from `CYCLONEDDS_DIR` — no `setup.bash` / `PKG_CONFIG_PATH` step.

### Android (cross-compile from macOS or Linux)

Install the Swift 6.3.1 Android SDK from [swift.org/install/android](https://www.swift.org/install/android/), install Android NDK ≥ r27, then run the bundled `setup-android-sdk.sh` once to symlink the NDK sysroot into place (see [swift.org](https://www.swift.org/install/android/) for the exact incantation).

```bash
swift sdk install <android-sdk-url> --checksum <sha>
SWIFT_ROS2_TARGET_OS=android swift build --swift-sdk aarch64-unknown-linux-android28
# or x86_64-unknown-linux-android28 for emulator targets
```

`SWIFT_ROS2_TARGET_OS=android` is **required** for any cross-compile — SwiftPM evaluates manifest-scope `#if os(...)` against the host, so without it a Linux host pulls in the un-buildable DDS path and a macOS host never source-builds `zenoh-pico`. The value is allow-list-validated (`{android, apple, linux, windows}`); typos fail the manifest compile. The `SwiftROS2` umbrella isn't built on Android — `import SwiftROS2Zenoh` directly.

## Module layout

```
import SwiftROS2          // public API — re-exports CDR / Messages / Transport / Wire
    ├── SwiftROS2CDR        — XCDR v1 encoder + decoder (pure Swift, no deps)
    ├── SwiftROS2Wire       — Zenoh / DDS wire codecs, ROS2Distro, TypeNameConverter
    ├── SwiftROS2Messages   — ROS2Message protocols + 23 built-in types
    └── SwiftROS2Transport  — TransportSession / TransportConfig / EntityManager / GIDManager

// Depended on by SwiftROS2 (so the high-level API works after `import SwiftROS2`),
// but NOT @_exported — import explicitly to reach ZenohClient / DDSClient.
import SwiftROS2Zenoh      — ZenohClient (zenoh-pico FFI through CZenohBridge)
import SwiftROS2DDS        — DDSClient (CycloneDDS FFI through CDDSBridge)
```

`CZenohPico` / `CCycloneDDS` are link-only C targets — consumed at the C level by `CZenohBridge` / `CDDSBridge` and **never `import`ed from Swift** (a CI lint guards against it). Reach the C bridges via `import SwiftROS2Zenoh` / `import SwiftROS2DDS`.

### Built-in message types

- **`sensor_msgs`** (13) — `BatteryState`, `CameraInfo`, `CompressedImage`, `FluidPressure`, `Illuminance`, `Image`, `Imu`, `Joy`, `MagneticField`, `NavSatFix`, `PointCloud2`, `Range`, `Temperature`
- **`geometry_msgs`** (3 publishable + utility types) — `PoseStamped`, `TransformStamped`, `TwistStamped`; sub-types `Vector3` / `Quaternion` / `Point` / `Pose` / `Twist` / `Transform`
- **`std_msgs`** (5) — `BoolMsg`, `EmptyMsg`, `Float64Msg`, `Int32Msg`, `StringMsg`; plus the universal `Header`
- **`audio_common_msgs`** (1) — `AudioData` · **`tf2_msgs`** (1) — `TFMessage`

## Code generation from IDL

`swift-ros2-gen` reads `.msg` / `.srv` / `.action` IDL and emits Swift `ROS2Message` / `ROS2ServiceType` / `ROS2Action` conformances — the recommended way to produce these since 0.9.0. Pass one `--input <pkg>=<path>@<distro>` per (package, distro) pair (every transitively-referenced package must appear so nested-type resolution succeeds); the generator merges multi-distro inputs into one Swift source that branches on `isLegacySchema`.

```bash
swift run swift-ros2-gen \
    --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
    --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
    --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
    --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy" \
    --output Sources/MyMessages/Generated
```

For always-in-sync bindings, add the `SwiftROS2GenPlugin` build plugin to a target (single-package, single-distro, `.msg`-only; name the target snake_case — it becomes the ROS package segment). A worked setup is at [`Sources/Examples/PluginSmoke/`](Sources/Examples/PluginSmoke). The [`verify-hash-oracle`](.github/workflows/hash-oracle.yml) CI job diffs each generated `RIHS01_*` hash against an `osrf/ros:<distro>-desktop` image; reproduce locally with `--verify-hashes osrf/ros:jazzy-desktop`.

Custom Conduit-style types are hand-written under `Sources/Messages/` with the same `ROS2Message` conformance (`typeInfo` + `encode(to:)` + `init(from:)`).

## Versioning

Tags follow Apple-ecosystem bare semver (no `v` prefix): `0.2.0`, `1.0.0-rc.1`, … The [release workflow](.github/workflows/release-xcframework.yml) fires on any tag matching `[0-9]*.[0-9]*.[0-9]*` (optionally `-qualifier`), builds both xcframeworks for all six Apple slices, and attaches them + `.checksum` files to the GitHub release. The pin URL + checksums are bumped in a follow-up PR (GitHub re-zips on upload, so server-side checksums must be re-computed with `swift package compute-checksum`).

## Release history

Each release has a [GitHub release](https://github.com/youtalk/swift-ros2/releases) with full notes; headlines below.

| Tag        | Date       | Headline                                                                                              |
|------------|------------|-------------------------------------------------------------------------------------------------------|
| **1.3.0**  | 2026-07-13 | **RCL everywhere; wire path deprecated.** Native `rcl` + `rmw_zenoh_cpp` / `rmw_cyclonedds_cpp` backend on Apple (default-on, per-variant xcframeworks) and Linux (system ROS 2). Direct `ZenohClient()` / `DDSClient()` construction is deprecated — **removed in 2.0.0**. Purely additive otherwise (#151–#174). |
| 1.2.0      | 2026-06-06 | **Source-timestamp publish overload** — additive `publish(_:timestamp:sequenceNumber:)` (#117). |
| 1.1.0      | 2026-05-06 | **Parameter API** — typed declares, the six `rcl_interfaces` services, `/parameter_events`, `ROS2ParameterClient` (#102–#107). |
| 1.0.0      | 2026-05-05 | **API stability promise (1.x SemVer freeze)** — plumbing types pulled out of the public surface; end-user types unchanged. |
| 0.9.0      | 2026-05-04 | **`swift-ros2-gen`** — IDL → Swift code generator (CLI + SwiftPM plugin) + `verify-hash-oracle` CI. |
| 0.8.0      | 2026-05-03 | **Actions + DDS on Windows** — typed `ROS2ActionServer` / `ROS2ActionClient`; CycloneDDS on Windows via vcpkg. |
| 0.7.0      | 2026-05-01 | **Services** — typed `ROS2Service` / `ROS2Client` over Zenoh and DDS. |
| 0.6.0      | 2026-04-24 | **Android** — arm64-v8a + x86_64 via the Swift Android SDK (Zenoh only). |
| 0.5.0      | 2026-04-24 | **Windows x86_64** — three-arm `Package.swift` split, `zenoh-pico` source build (Zenoh only). |
| 0.4.0      | 2026-04-20 | **DDS subscriber** — `CDDSBridge` fragchain reader; `swift run listener dds`. |
| 0.3.0      | 2026-04-19 | **API rename (breaking)** — drop `Default` prefix from `ZenohClient` / `DDSClient`; Linux arm64 + Rolling + Humble CI. |
| 0.2.0      | 2026-04-18 | **Initial public release** — Publisher + Subscriber, XCDR v1 codec, Jazzy + Humble wire, dual transport. |

## Roadmap

Concrete deliverables, not aspirational vapor.

**Near-term (additive, 1.x):** expanded message catalog (`nav_msgs`, `visualization_msgs`, `diagnostic_msgs`) via `swift-ros2-gen`; TF / TF2 runtime layer (`TransformBroadcaster`, `Buffer` + `TransformListener`, mirroring `tf2_ros`); logging / `/rosout` (`Logger` on `ROS2Node`, bridging `os.Logger`).

**Medium-term:** DDS on Android (blocked on `ddsrt`'s CMake-time header generation under the NDK; likely a prebuilt `.artifactbundle`); XCDR2 wire format; `LifecycleNode` (nine-state machine + `lifecycle_msgs`); composition / intra-process short-circuit; discovery control (`ROS_AUTOMATIC_DISCOVERY_RANGE`, `ROS_STATIC_PEERS`).

**Stretch:** Linux static `.artifactbundle`; `watchOS` / `tvOS` slices; OpenXR-on-Android for Quest / Pico; rosbag2 (`mcap`) read/write; DDS Security; action-server fan-out; a minimal `xacro` / URDF parser.

## Contributing

PRs welcome. The wire fixtures in [`Tests/SwiftROS2WireTests/`](Tests/SwiftROS2WireTests/) and golden CDR tests in [`Tests/SwiftROS2CDRTests/`](Tests/SwiftROS2CDRTests/) are the canonical guardrails — keep them green. [`Tests/SwiftROS2IntegrationTests/`](Tests/SwiftROS2IntegrationTests/) boots a real ROS 2 subscriber; set `LINUX_IP=<host>` to exercise it. Lint with `swift format lint --strict --configuration .swift-format Package.swift Sources Tests` before pushing — CI fails lint before any build matrix runs.

## License

Apache License 2.0. See [LICENSE](LICENSE).
