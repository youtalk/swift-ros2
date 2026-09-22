# Architecture

swift-ros2 is a native Swift client for ROS 2 with one public API
(`ROS2Context` / `ROS2Node` / `ROS2Publisher` / `ROS2Subscription`, plus
services, actions, and parameters) fronting **two backends**:

1. **Wire path** — a pure-Swift XCDR v1 codec plus Zenoh / DDS wire codecs,
   speaking directly to `rmw_zenoh_cpp` (via zenoh-pico) or
   `rmw_cyclonedds_cpp` (via CycloneDDS). No `rcl`/`rclcpp` in the process.
   2.0.0 removes the wire clients from the public API; the wire runtime
   remains the internal fallback where RCL is not available and is retired
   per platform in 2.x minors, non-breaking. Its clients (`ZenohClient`,
   `DDSClient`, the wire transport sessions) are `package`, and
   `SwiftROS2Zenoh` / `SwiftROS2DDS` are targets, not products. The CDR and
   wire codecs (`SwiftROS2CDR`, `SwiftROS2Wire`) stay public.
2. **RCL backend** — the real `rcl` + rmw stack, reached through the
   `CRclBridge` C shim. On Apple it is in the build graph by default since
   1.4.0 (opt out with `SWIFT_ROS2_DISABLE_RCL=1`); on Linux it is opt-in with
   `SWIFT_ROS2_ENABLE_RCL=1`. Windows and Android are wire-only.

`ROS2Context.makeDefaultSession(for:)` (`Sources/SwiftROS2/Context.swift`)
maps `TransportConfig.type` to a session, keyed on the build graph:

| Build graph | `.zenoh` | `.dds` | `.rcl` / `.rclUnicast` |
|---|---|---|---|
| Apple, default (RCL on, `cyclonedds` rmw) | wire | wire | RCL + `rmw_cyclonedds_cpp` |
| Apple, `SWIFT_ROS2_RCL_RMW=zenoh` | RCL + `rmw_zenoh_cpp` | wire | throws |
| Apple, `SWIFT_ROS2_DISABLE_RCL=1` | wire | wire | throws |
| Linux, default | wire | wire | throws |
| Linux, `SWIFT_ROS2_ENABLE_RCL=1` | RCL + `rmw_zenoh_cpp` | RCL + `rmw_cyclonedds_cpp` | RCL + `rmw_cyclonedds_cpp` |
| Windows | wire | wire with `CYCLONEDDS_DIR`, otherwise throws | throws |
| Android | wire | throws | throws |

"wire" is `ZenohTransportSession` / `DDSTransportSession`, "RCL" is
`RclTransportSession`, and "throws" is `TransportError.unsupportedFeature`.
Everything above the session seam — nodes, publishers, subscriptions,
services, actions, parameters — is shared.

## Target graph

    SwiftROS2 (umbrella: ROS2Context, ROS2Node, ROS2Publisher, ROS2Subscription,
     │         services / actions / parameters)
     ├── SwiftROS2Messages    — ROS2Message protocols + built-in types
     │    └── SwiftROS2CDR    — pure-Swift XCDR v1 encoder / decoder (no deps)
     ├── SwiftROS2Transport   — TransportSession seam, TransportConfig,
     │    │                     EntityManager, GIDManager, RclTransportSession
     │    └── SwiftROS2Wire   — Zenoh / DDS wire codecs, ROS2Distro (no deps)
     ├── SwiftROS2Zenoh ── CZenohBridge ── CZenohPico    (zenoh-pico FFI, internal)
     ├── SwiftROS2DDS   ── CDDSBridge   ── CCycloneDDS   (CycloneDDS FFI, internal)
     └── SwiftROS2RCL   ── CRclBridge   ── CRos2Jazzy    (rcl/rmw FFI; Apple default, Linux opt-in)

Tooling targets outside the runtime graph:

- `SwiftROS2Gen` + `swift-ros2-gen` + `SwiftROS2GenPlugin` — IDL → Swift code
  generator (CLI and SwiftPM build-tool plugin) with RIHS01 hash computation.
- `ParityMatrix` + `parity-tool` — the wire-vs-RCL parity matrix renderer
  behind [PARITY.md](PARITY.md).
- `SwiftROS2Bench` — internal benchmark / soak-analysis helpers (not a
  product).

`CZenohBridge`, `CDDSBridge`, and `CRclBridge` are swift-ros2–authored C shims
around the vendor APIs. `CZenohPico`, `CCycloneDDS`, and `CRos2Jazzy` are
link-only C targets — never `import`ed from Swift (a CI lint enforces this);
Swift reaches them through the bridge modules.

## Platform arms

`Package.swift` selects one of four arms via the `SWIFT_ROS2_TARGET_OS` env
override (allow-list `{apple, linux, windows, android}`, mandatory for
cross-compiles) or the host `#if os(...)` fallback:

| Arm | zenoh-pico | CycloneDDS | RCL |
|-----|------------|------------|-----|
| Apple | `binaryTarget` xcframework from the pinned GitHub release | `binaryTarget` xcframework | `binaryTarget` xcframework from the release URL (default; `SWIFT_ROS2_DISABLE_RCL=1` opts out) |
| Linux | source build of `vendor/zenoh-pico` (unix backend) | `systemLibrary` via `pkg-config` | system ROS 2 install (opt-in, `SWIFT_ROS2_ENABLE_RCL=1`) |
| Windows | source build (windows backend, Winsock + Iphlpapi) | `systemLibrary` via vcpkg (`CYCLONEDDS_DIR`; Zenoh-only when unset) | none |
| Android | source build (Bionic, unix backend) | none | none |

The `SwiftROS2` umbrella builds on every arm. `SwiftROS2DDS` exists only
where CycloneDDS is consumable; on Android (and Windows without
`CYCLONEDDS_DIR`) the umbrella is Zenoh-only and `.dds` transports throw
`TransportError.unsupportedFeature`. Consumers depend on the `SwiftROS2`
product on every arm — the wire targets are not products.

## RCL backend provisioning

On by default on Apple (since 1.4.0; `SWIFT_ROS2_DISABLE_RCL=1` opts out)
and opt-in on Linux (`SWIFT_ROS2_ENABLE_RCL=1`). The rmw selection differs per
platform:

- **Apple** — `CRos2Jazzy` is a URL-based `binaryTarget`: the prebuilt
  xcframework is a release artifact (built by `Scripts/build-ros2-xcframework.sh`
  in `release-xcframework.yml`) resolved from the pinned release URL +
  checksum. `SWIFT_ROS2_RCL_LOCAL=1` resolves it from a local `build/ros2*/`
  instead (CI and ROS 2 cross-build iteration). The rmw is **baked per build
  variant**, selected by `SWIFT_ROS2_RCL_RMW`: `cyclonedds` (default) →
  `CRos2Jazzy.xcframework`, `zenoh` → `CRos2JazzyZenoh.xcframework` (no
  visionOS slice). The zenoh variant bundles zenoh-c, which collides with
  zenoh-pico's C symbols, so that variant carves the zenoh-pico wire family
  out of the build graph and `.zenoh` configs are served by rcl +
  `rmw_zenoh_cpp` instead; `.rcl` / `.rclUnicast` throw there, since they
  target `rmw_cyclonedds_cpp`.
- **Linux** — `CRos2Jazzy` is a `systemLibrary` over the system ROS 2 install,
  located through `ROS2_RCL_PREFIX` (colon-separated ament prefix list,
  defaulting to `/opt/ros/${ROS_DISTRO:-jazzy}`). rcl has no pkg-config, so
  the manifest injects `-I`/`-L`/`-l` flags directly. The rmw is selected **at
  runtime, once per process**, from the transport type: `.zenoh` →
  `rmw_zenoh_cpp`, `.dds` / `.rcl` → `rmw_cyclonedds_cpp`. Because
  `RMW_IMPLEMENTATION` is process-global, one process serves one rmw — mixing
  `.zenoh` and `.dds` contexts in a Linux RCL process is unsupported (the wire
  path and Apple builds have no such restriction).

Per-backend behavioral parity is tracked feature-by-feature in
[PARITY.md](PARITY.md).

## Wire format contract (wire path)

The canonical guardrails are the golden tests under `Tests/SwiftROS2CDRTests/`
and `Tests/SwiftROS2WireTests/`. In brief:

- **Key expression** —
  `<domain>/<namespace>/<topic>/<dds_type_name>/<type_hash-or-TypeHashNotSupported>`,
  DDS type name in the `::msg::dds_::Type_` form. Humble always emits
  `TypeHashNotSupported`; Jazzy+ drops the segment when the hash is absent.
- **Attachment** (33 bytes) — `seq` (int64 LE) + `timestamp_ns` (int64 LE) +
  LEB128 byte `0x10` + 16-byte GID.
- **CDR** — XCDR v1, explicit little-endian, 4-byte encapsulation header
  `00 01 00 00`. Fixed-size arrays serialize without a length prefix;
  sequences carry a 4-byte `uint32` length prefix.

The RCL backend reuses the same `SwiftROS2CDR` encoder / decoder: messages
are serialized in Swift and handed to `rcl_publish_serialized_message`
(taken back via `rcl_take_serialized_message`), with `rosidl` typesupport
resolved per type when the rcl entities are created. The key-expression and
attachment rules above are wire-path-only — on the RCL backend the rmw owns
discovery and metadata.

See the [README](../README.md) for installation and per-platform build
instructions, and [MIGRATION.md](../MIGRATION.md) for the public API surface
boundary frozen at 1.0.
