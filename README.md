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

Native Swift client library for ROS 2. Publish and subscribe to ROS 2 topics over **Zenoh** (via `zenoh-pico`) or **DDS** (via CycloneDDS) — without a bridge, without `rcl` / `rclcpp`, on every consumer device OS that runs Swift.

> The four CI badges above all reflect the same `ci.yml` workflow status (GitHub Actions does not expose per-matrix-job badges). Each label is the OS family that workflow exercises — when the badges are green, every Apple / Linux / Windows / Android matrix entry passed.

Shipping as **0.6.0** — Apple xcframeworks (iOS / iPadOS / macOS / Mac Catalyst / visionOS), `zenoh-pico` source build on Linux / Windows / Android.

## Why

Bringing ROS 2 to a phone, headset, or laptop usually means cross-compiling `rcl` + `rclcpp` + a DDS implementation, fighting CMake on a non-Linux host, and shipping a 100+ MB toolchain. swift-ros2 sidesteps all of that by speaking the ROS 2 wire formats directly: a SwiftPM `.package(url:)` line on Apple targets, a single `apt install ros-<distro>-cyclonedds` on Linux, and a vanilla `swift build` on Windows / Android. The publisher / subscription API is Swift-native (`async`/`await`, `AsyncStream`, `Sendable`) and round-trip compatible with the `rmw_zenoh_cpp` and `rmw_cyclonedds_cpp` middlewares.

## Features

- **Dual transport.** `SwiftROS2Zenoh` talks to `rmw_zenoh_cpp`; `SwiftROS2DDS` talks to `rmw_cyclonedds_cpp`. Switch transports with a single `TransportConfig` change.
- **No `rcl` dependency.** Wire-level publish / subscribe means no `rcl`, no `rclcpp`, no Python / colcon, no `rmw_*` shim layer — and no transitive build of FastDDS or CycloneDDS from source on the consumer side (Apple targets get xcframeworks; Linux gets a `pkg-config` lookup; Windows / Android stay Zenoh-only for now).
- **Swift-native API.** `async`/`await` everywhere, `AsyncStream` subscriptions, `Sendable` conformance, structured concurrency, no opaque pointer juggling above the FFI seam.
- **Pre-built Apple binaries.** `CZenohPico.xcframework` + `CCycloneDDS.xcframework` are attached to every GitHub Release. `swift build` downloads them in seconds — no CMake, no local bootstrap, no Apple-side codesigning dance.
- **Source build everywhere else.** Linux, Windows, and Android compile `zenoh-pico` from `vendor/` via SwiftPM directly, each picking the matching backend (`unix` / `windows`). CycloneDDS comes from `pkg-config` on Linux. No vendored prebuilts needed.
- **Multi-distro wire format.** Humble, Jazzy, Kilted, Rolling. Select via `ROS2Distro` on `ROS2Context`; Zenoh defaults to Jazzy when unspecified. Schema differences (e.g. `sensor_msgs/Range` gaining `variance` after Humble) are gated automatically through `isLegacySchema`.
- **23 built-in message types** spanning `sensor_msgs`, `geometry_msgs`, `std_msgs`, `audio_common_msgs`, and `tf2_msgs`. Pure-Swift XCDR v1 encoder + decoder cover both the publish and subscribe paths.
- **Production-proven.** Extracted from [Conduit, powered by ROS](https://apps.apple.com/app/id6757171237) — used cumulatively by **10,000+ ROS developers worldwide** and a former **#4 in the App Store's Developer Tools category**. Conduit streams 12 sensor topics from iOS / iPadOS / macOS / visionOS at up to 100 Hz over the same swift-ros2 publish path documented below.

## Platforms

| Platform              | Minimum target                                 | Integration path                                    | Transports     | CI job per push                       | xcframework slices built at tag time |
|-----------------------|------------------------------------------------|-----------------------------------------------------|----------------|---------------------------------------|--------------------------------------|
| iOS / iPadOS          | 16.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `iphoneos` + `iphonesimulator`       |
| macOS                 | 13.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | `build-macos` (`swift build` + `swift test`) | `macosx`                             |
| Mac Catalyst          | 16.0                                           | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `maccatalyst`                        |
| visionOS              | 1.0                                            | `binaryTarget` xcframework                          | Zenoh + DDS    | (covered by `build-macos` Swift compile) | `xros` + `xrsimulator`               |
| Linux                 | Ubuntu 22.04 / 24.04 (x86_64, aarch64)         | `zenoh-pico` source build + `pkg-config` for DDS    | Zenoh + DDS    | `build-linux` (×6: 3 distros × 2 arches)  | n/a (source build)                   |
| Windows               | Windows 10 / 11 (x86_64)                       | `zenoh-pico` source build (Winsock + Iphlpapi)      | Zenoh only     | `build-windows`                       | n/a (source build)                   |
| Android               | API 28+ (arm64-v8a, x86_64)                    | `zenoh-pico` source build (Bionic, unix backend)    | Zenoh only     | `build-android` (×2 ABIs)             | n/a (source build)                   |

The `build-macos` job runs `swift build` / `swift test` on `macos-15`, which compiles the Swift sources for the macOS host only — that proves the Swift code compiles against the Apple toolchain, but it does *not* drive `xcodebuild` against `iphoneos` / `iphonesimulator` / `maccatalyst` / `xros` / `xrsimulator` destinations. Those non-host Apple slices are built end-to-end only by the [`release-xcframework.yml`](.github/workflows/release-xcframework.yml) workflow at tag time, which produces the `CZenohPico.xcframework` + `CCycloneDDS.xcframework` zips attached to each GitHub release. Per-push runtime validation on iOS / visionOS / Mac Catalyst comes from [Conduit](https://apps.apple.com/app/id6757171237) — the 10K+ developer production user — rather than CI.

Swift 5.9+ on Apple platforms; Linux uses Swift 6.0.2; Windows requires Swift 6.3.1 (the bundled Windows SDK shim in 6.0.x assumes older Windows Kits headers than the current `windows-latest` image ships, failing with `could not build module 'ucrt'`); Android uses the Swift 6.3.1 Android SDK from swift.org (matched against the toolchain `swift sdk install` resolves).

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
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "0.6.0"),
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

Windows ships Zenoh only; the DDS path is currently excluded from the Windows build graph (SwiftPM cannot orchestrate CycloneDDS's `ddsrt` CMake configure-time header generation, and no usable prebuilt path exists yet — see [Roadmap](#roadmap)).

```swift
dependencies: [
    .package(url: "https://github.com/youtalk/swift-ros2.git", from: "0.6.0"),
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "SwiftROS2Zenoh", package: "swift-ros2"),    // umbrella isn't built on Windows
        ]
    ),
]
```

Requires Swift 6.3.1. No `setup.bash` or `PKG_CONFIG_PATH` step — `swift build` handles the `zenoh-pico` source build automatically.

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

> **Windows / Android note:** the examples below use the `SwiftROS2` umbrella, which is excluded from those platforms. Use `SwiftROS2Zenoh.ZenohClient` directly for the Zenoh path; the high-level `ROS2Context` / `ROS2Node` wrappers land on Windows and Android when DDS does (see [Roadmap](#roadmap)).

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

When the planned [`swift-ros2-gen`](#roadmap) code generator lands, hand-written conformances like this become optional — the generator will emit the same shape from `.msg` files automatically.

## Versioning

Tags follow Apple-ecosystem bare semver (no `v` prefix): `0.2.0`, `1.0.0-rc.1`, etc. The [release workflow](.github/workflows/release-xcframework.yml) fires on any tag matching `[0-9]*.[0-9]*.[0-9]*` (optionally `-qualifier`), builds both xcframeworks for all six Apple slices (`iphoneos`, `iphonesimulator`, `macosx`, `maccatalyst`, `xros`, `xrsimulator`), and attaches them + `.checksum` files to the GitHub release named after the tag.

The `0.x` series is pre-1.0 by design — breaking API changes are allowed between minor versions while the public surface stabilizes around the upcoming Services / Actions / `swift-ros2-gen` work (see [Roadmap](#roadmap)). 1.0.0 is gated on those landing.

## Release history

Each release has a corresponding [GitHub release](https://github.com/youtalk/swift-ros2/releases) with auto-generated notes; the summaries below capture the headline change.

| Tag        | Date       | Headline                                                                                              |
|------------|------------|-------------------------------------------------------------------------------------------------------|
| **0.6.0**  | 2026-04-24 | **Android support** — arm64-v8a + x86_64 via the Swift 6.3.1 Android SDK; `zenoh-pico` source build with `ZENOH_ANDROID` (Bionic unix backend, vendored `pthread_cancel` / `_z_task_cancel` stubs); `SWIFT_ROS2_TARGET_OS` env override required for any cross-compile (allow-list-validated, fails the manifest compile on typos); `build-android` matrix (×2 ABIs) added to CI on `ubuntu-24.04` with NDK r27c. Zenoh only — DDS-on-Android tracked as future work. |
| 0.5.0      | 2026-04-24 | **Windows x86_64 support** — three-arm `Package.swift` platform split, `zenoh-pico` source build with `ZENOH_WINDOWS` and Winsock + Iphlpapi linkage, `build-windows` job on `windows-latest` (Swift 6.3.1). Zenoh only.                                                                                              |
| 0.4.0      | 2026-04-20 | **DDS subscriber** — `raw_cdr_serdata_from_ser` fragchain walk in `CDDSBridge`, `bridge_dds_reader_t` + listener callback, `DDSReaderHandle` / `createRawReader` / `destroyReader` on `DDSClientProtocol`, `DDSTransportSession.createSubscriber` wired through; `swift run listener dds` enabled. Minimal `talker` / `listener` example executables added. |
| 0.3.1      | 2026-04-19 | **Hardened CDR decoder** — bounds-checks untrusted sequence + string lengths before `reserveCapacity`; fails fast on malformed null-terminated strings instead of silently dropping bytes. |
| 0.3.0      | 2026-04-19 | **API rename (breaking)** — drop `Default` prefix from `ZenohClient` / `DDSClient`. CI matrix expanded to Linux arm64 + ROS 2 Rolling, plus Ubuntu 22.04 + ROS 2 Humble. |
| 0.2.0      | 2026-04-18 | **Initial public release** — Publisher + Subscriber core, pure-Swift XCDR v1 encoder/decoder, Jazzy + Humble wire codecs, dual-transport (Zenoh + DDS) FFI, Apple xcframeworks via GitHub Releases, Linux source build via SwiftPM. |

## Roadmap

Past releases shipped roughly one breaking platform / transport / API change per week. The list below is what's queued — concrete deliverables, not aspirational vapor.

### Near-term (the 1.0.0 gate)

- **`swift-ros2-gen`** — code generator that takes `.msg` / `.srv` / `.action` files and emits `ROS2Message` / `ROS2Service` / `ROS2Action` Swift conformances. Goal: drop the hand-written `encode(to:)` / `init(from:)` ceremony required for every custom type today, and bring the catalog of built-in messages closer to what `rclcpp` ships out of the box.
- **Services (request / reply)** — Zenoh: composed over `z_query_*` queryables. DDS: composed over the request-reply pattern in CycloneDDS. Public API will mirror `rcl`'s shape (`createService(_:type:handler:)` / `createClient(_:type:).call(_:)`). Additive — won't break the existing publisher / subscription API.
- **Actions (goal / feedback / result)** — composed Services + Topics, mirroring `rcl_action`. Depends on Services landing first.
- **Expanded message catalog** — `nav_msgs`, `visualization_msgs`, `diagnostic_msgs`, more of `geometry_msgs`. Hand-rolled until `swift-ros2-gen` ships, generated after.

### Medium-term

- **DDS on Windows / Android** — currently blocked on SwiftPM not orchestrating CycloneDDS's `ddsrt` CMake-configure-time header generation. Likely path: prebuilt `.artifactbundle` distribution for both targets, similar to the Apple xcframeworks but in the SPM artifact-bundle format.
- **XCDR2 wire format** — only XCDR v1 is implemented today. XCDR v2 is required for some Rolling-era message types. Additive (new init flag on `CDRDecoder`).
- **Richer QoS profiles** — `.servicesDefault`, `.parameters`, `.systemDefault` to match `rcl`. Today any non-default QoS knob has to be set by hand on the underlying `TransportConfig`.

### Stretch

- **Linux static `.artifactbundle`** — replace the `pkg-config + setup.bash` dance with a self-contained download. Prototyped and rejected for 0.5.0; might revisit once the SPM + system-library story improves.
- **`watchOS` / `tvOS` xcframework slices** — would require `Z_FEATURE_LINK_TCP` validation under those SDKs and a `Sendable` audit for `WCSession`-style flows.
- **OpenXR-on-Android-arm bring-up** — extends the XR coverage row above beyond visionOS once a credible runtime exists for Quest / Pico headsets.

## Contributing

PRs welcome. The wire-format fixtures in [`Tests/SwiftROS2WireTests/`](Tests/SwiftROS2WireTests/) and the golden CDR tests in [`Tests/SwiftROS2CDRTests/`](Tests/SwiftROS2CDRTests/) are the canonical guardrails — keep them green. [`Tests/SwiftROS2IntegrationTests/`](Tests/SwiftROS2IntegrationTests/) boots a real ROS 2 subscriber on a Linux host; set `LINUX_IP=<host>` locally to exercise it.

Lint with `swift format lint --strict --configuration .swift-format Package.swift Sources Tests` before pushing — CI fails the lint step before any of the build matrices run.

## License

Apache License 2.0. See [LICENSE](LICENSE).
