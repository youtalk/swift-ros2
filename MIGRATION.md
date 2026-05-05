# Migration Guide

## Compatibility table

| From | To | Breaking changes |
|---|---|---|
| 0.6.0 | 0.6.1 | **One:** the placeholder `ROS2Service` protocol in `SwiftROS2Messages` was renamed to `ROS2ServiceType` so the umbrella's typed Service Server class can take the simpler `ROS2Service<S>` name in 0.7.0. |
| 0.6.x | 0.7.x | **One** if upgrading from 0.6.0 directly: the rename above. From 0.6.1 → 0.7.x there are no breaking changes — the Services API is purely additive. |
| 0.7.x | 0.8.0 | **None.** Actions are purely additive — `ROS2Action`, `ROS2ActionServer`, `ROS2ActionClient`, `ActionGoalHandle`, `ActionResult`, `ActionGoalStatus`, `ActionError` are new. `ROS2ActionTypeInfo` gained five optional hash fields with source-compatible defaults (Phase 1). |
| 0.8.x | 0.9.0 | **None.** `swift-ros2-gen` (CLI + SwiftPM build plugin + hash-oracle CI) is purely additive — no existing public API changed. |
| 0.9.x | 1.0.0 | **Six visibility-only changes** — plumbing types pulled out of the public surface (`TransportQoS`, `QoSPolicy`, `DDSBridge*`, `ZenohClientProtocol`/`DDSClientProtocol` + 10 related, `EntityManager`/`GIDManager` → `package`; `ZenohTransportPublisher`, `DeclaredKeyExpr`/`ZenohSubscriber`/`LivelinessToken` → `internal`). End-user APIs (`ROS2Context`, `ROS2Node`, `ROS2Publisher`, `ROS2Subscription`, `ROS2Service`, `ROS2Client`, `ROS2ActionServer`, `ROS2ActionClient`, `QoSProfile`, `TransportConfig`, all message types) are unchanged. |
| 1.0.x | 1.x   | **None guaranteed.** Minor releases on the 1.x line will not break public API. |

SwiftROS2 follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once 1.0.0 is cut. Breaking changes after 1.0 require a major bump.

---

## 0.6.0 → 0.6.1 / 0.7.0 — `ROS2Service` placeholder rename

The 0.6.0 line shipped a placeholder protocol named `ROS2Service` in `SwiftROS2Messages` (with no implementation). To make room for the typed Service Server class `ROS2Service<S>` in `SwiftROS2`, that placeholder was renamed to `ROS2ServiceType` in 0.6.1.

If your code conformed to the old name:

```swift
// before (0.6.0)
public enum MySrv: ROS2Service { ... }

// after (0.6.1+)
public enum MySrv: ROS2ServiceType { ... }
```

The shape of the protocol is unchanged — same `Request` / `Response` associated types, same `static var typeInfo: ROS2ServiceTypeInfo` requirement. The only thing that moved is the name. Conduit's `BuiltinServices/StdSrvs/Trigger.swift` was already on the new name; downstreams that referenced the placeholder need this one-line rename.

## 0.x → 0.7 — no breaking changes (other than the rename above)

0.7.x adds:
- **Services** (typed `ROS2Service<S>` / `ROS2Client<S>` over both Zenoh and DDS), `ServiceError`, `ROS2Node.createService` / `createClient`. New, additive — no existing API renamed or removed.
- DocC catalog and richer `///` comments.
- Per-target line-coverage gate in CI.
- `swift package diagnose-api-breaking-changes` on every PR.
- Internal refactors of the transport sessions (now also walk service servers / clients in `close()`).

No public type, function, protocol, or property already shipping in 0.6.1 is renamed, removed, or made `internal` in 0.7.x.

---

## 0.7 → 0.8 — Actions

0.8.0 ships the ROS 2 Actions umbrella — six PRs, every one of them additive. No existing public symbol was renamed, removed, or had its shape changed.

### Adding action support to existing code

If you have a Conduit-style app that already calls `node.createPublisher` / `createService`, the action surface follows the same pattern:

```swift
let server = try await node.createActionServer(
    FibonacciAction.self,
    name: "/fibonacci",
    handler: MyHandler()  // an actor conforming to ActionServerHandler
)

let client = try await node.createActionClient(FibonacciAction.self, name: "/fibonacci")
try await client.waitForActionServer(timeout: .seconds(5))
let handle = try await client.sendGoal(FibonacciAction.Goal(order: 10))
let result = try await handle.result()
```

See the `Actions.md` DocC chapter for the full walk-through.

### `ROS2ActionTypeInfo`

The struct gained five optional `*TypeHash` fields for the synthesized wrapper messages. The existing 3-hash initializer is preserved unchanged; the new 8-hash initializer is a separate entry point. No callers need to change unless they want to opt into wire-correct synthesized hashes.

### Per-role QoS

`QoSProfile.actionDefault` is the new default for `createActionServer` / `createActionClient`. The transport layer applies a `transient_local / depth 1` override on the `_action/status` topic automatically.

### Naming note: `ActionGoalStatus` vs `GoalStatus`

The umbrella exposes ``ActionGoalStatus`` (an `Int8`-backed enum) for the status surface returned by `ActionResult` / `handle.statusUpdates`. The wire-level `GoalStatus` struct (the embedded CDR payload of `GoalStatusArray`) ships in `SwiftROS2Messages` and re-exports through the umbrella, so both names are visible — they are intentionally different shapes for different layers.

---

## 0.8 → 0.9 — `swift-ros2-gen`

0.9.0 ships the `swift-ros2-gen` code generator end-to-end: CLI (with `.msg` / `.srv` / `.action` support and multi-distro merging), a single-distro `.msg`-only SwiftPM build plugin, and a `verify-hash-oracle` CI job. Every change is additive — no existing public symbol was renamed, removed, or had its shape changed.

### Adding code generation to a downstream Apple project

```swift
// Package.swift — opt the target into the SwiftROS2Gen build plugin
.target(
    name: "my_msgs",  // snake_case / lowercase — becomes the ROS package segment in typeInfo.typeName
    dependencies: [
        .product(name: "SwiftROS2", package: "swift-ros2"),
    ],
    plugins: [
        .plugin(name: "SwiftROS2GenPlugin", package: "swift-ros2"),
    ]
),
```

There is no configuration file. Drop the `.msg` files into the target's directory under `msg/` and build — the plugin walks `msg/` directly, hands every file to `swift-ros2-gen` with `<target-name>=<dir>@jazzy`, and writes the generated Swift under SwiftPM's per-target work directory.

The plugin handles only the single-package single-distro (jazzy) `.msg` case. `.srv` and `.action` files in the target directory are skipped with a build warning. For multi-distro merging, multi-package builds, `.srv`, `.action`, or an explicit `--types` allow-list, invoke `swift run swift-ros2-gen` directly. A working setup lives at [`Sources/Examples/PluginSmoke/`](Sources/Examples/PluginSmoke).

### Verifying type hashes against a live ROS 2 install

`--verify-hashes` takes a Docker image as its argument value (the verifier shells into the image and reads canonical `share/<pkg>/{msg,srv,action}/<Type>.json` files). The verifier resolves nested-type references, so every transitively-referenced package must appear on `--input`:

```bash
swift run swift-ros2-gen --verify-hashes osrf/ros:jazzy-desktop \
    --input "builtin_interfaces=vendor/rcl_interfaces-jazzy/builtin_interfaces@jazzy" \
    --input "std_msgs=vendor/common_interfaces-jazzy/std_msgs@jazzy" \
    --input "geometry_msgs=vendor/common_interfaces-jazzy/geometry_msgs@jazzy" \
    --input "sensor_msgs=vendor/common_interfaces-jazzy/sensor_msgs@jazzy"
```

Diffs each generated `RIHS01_*` against the canonical rosidl JSON inside the named Docker image — there is no recorded baseline shipped in the package. The matching CI job is `verify-hash-oracle` in [`hash-oracle.yml`](.github/workflows/hash-oracle.yml); it is path-filtered on pull requests (only fires when generator / generated-source / vendored-IDL paths change) and unconditionally on `main` pushes.

---

## 0.9 → 1.0 — actual change list

### Candidate 1 — `TransportQoS` and `QoSPolicy`

- **Current location:** `Sources/SwiftROS2Transport/TransportSession.swift` (`TransportQoS`); `Sources/SwiftROS2Wire/WireCodec.swift` (`QoSPolicy`).
- **Current declaration:** `public struct TransportQoS`, `public struct QoSPolicy`.
- **1.0 change:** demoted to `package` (Swift 5.9+ access modifier — invisible to downstream consumers, still reachable from the other targets and tests in this SPM package).
- **Rationale:** both are derived representations of `QoSProfile`. End users do not need to construct them directly. Three parallel public QoS types (profile / transport / wire) inflate the API surface for no functional gain.
- **Replacement:** `QoSProfile` (presets `.default`, `.sensorData`, `.reliableSensor`, `.latched`, `.servicesDefault`, or `init(reliability:durability:history:)`).
- **Impact surface:** code that constructs `TransportQoS(...)` or `QoSPolicy(...)` directly. Detect with `grep -rn "TransportQoS(\|QoSPolicy(" your-project/`.
- **Recommended action:** replace direct construction with `QoSProfile(...)`.

### Candidate 2 — `DDSBridgeQoSConfig`, `DDSBridgeDiscoveryConfig`, `DDSBridgeDiscoveryMode`

- **Current location:** `Sources/SwiftROS2Transport/DDSClientProtocol.swift`.
- **Current declaration:** `public struct DDSBridgeQoSConfig`, `public struct DDSBridgeDiscoveryConfig`, `public enum DDSBridgeDiscoveryMode`.
- **1.0 change:** demoted to `package` (Swift 5.9+ access modifier — invisible to downstream consumers, still reachable from the other targets and tests in this SPM package).
- **Rationale:** these types only exist in the public API to appear in `DDSClientProtocol` parameters. `DDSBridgeDiscoveryMode` (Int32-raw) duplicates `TransportConfig.DDSDiscoveryMode` (String-raw) at the concept level.
- **Replacement:** `TransportConfig.DDSDiscoveryMode` and `DDSPeer` continue to be the public configuration surface.
- **Impact surface:** code that constructs `DDSBridgeQoSConfig(...)` or `DDSBridgeDiscoveryConfig(...)` directly. Grep for `DDSBridge`.
- **Recommended action:** replace direct construction with `TransportConfig.ddsMulticast(...)` / `TransportConfig.ddsUnicast(...)`.

### Candidate 3 — `ZenohClientProtocol`, `DDSClientProtocol`, and related public types

- **Related types (10):** `ZenohKeyExprHandle`, `ZenohSubscriberHandle`, `ZenohLivelinessTokenHandle`, `ZenohQueryableHandle`, `ZenohQueryHandle`, `ZenohSample`, `ZenohError`, `DDSWriterHandle`, `DDSReaderHandle`, `DDSError`.
- **Current location:** `Sources/SwiftROS2Transport/{Zenoh,DDS}ClientProtocol.swift`.
- **1.0 change:** demoted to `package` (Swift 5.9+ access modifier — invisible to downstream consumers, still reachable from the other targets and tests in this SPM package).
- **Rationale:** these protocols exist so consumers can wrap the C bridge themselves and inject a custom client. In practice every known consumer uses the stock `ZenohClient()` / `DDSClient()` from `SwiftROS2Zenoh` / `SwiftROS2DDS` directly — both remain `public`. The implementation-injection seam is over-budget for the 1.0 freeze. As a knock-on effect, the cross-target plumbing that referenced these protocol types — `TransportSession` / `TransportPublisher` / `TransportSubscriber`, the `ROS2Context.init(... session:)` 4-arg initializer, and `*TransportSession` initializers — was demoted to `package` as well, since a `public` API can't take a `package` type as a parameter.
- **Replacement:** the high-level public API. Construct a context with `ROS2Context(transport: TransportConfig)` (which now picks the correct stock `ZenohClient` / `DDSClient` internally based on `TransportConfig.type`); use `ROS2Publisher` / `ROS2Subscription` / `ROS2Service` / `ROS2Client` / `ROS2ActionServer` / `ROS2ActionClient` from `node.create*`. The injection seam (`session:`-shaped initializers, `TransportSession` / `TransportPublisher` / `TransportSubscriber` protocols) is no longer reachable from outside the package.
- **Impact surface:** code that conforms to `ZenohClientProtocol` / `DDSClientProtocol` (custom wrappers), constructs a `*TransportSession` directly, or holds `any TransportPublisher` / `any TransportSubscriber`. Grep for `: ZenohClientProtocol\|: DDSClientProtocol\|TransportSession(\|any TransportPublisher\|any TransportSubscriber`.
- **Recommended action:** drop the custom conformance / direct session construction and use `ROS2Context(transport:)` plus `node.createPublisher(...)` / `createSubscription(...)` / `createService(...)` / etc.

### Candidate 4 — `EntityManager`, `GIDManager`

- **Current location:** `Sources/SwiftROS2Transport/{EntityManager,GIDManager}.swift`.
- **Current declaration:** `public final class`.
- **1.0 change:** demoted to `package` (Swift 5.9+ access modifier — invisible to downstream consumers, still reachable from the other targets and tests in this SPM package).
- **Rationale:** library-internal entity-id allocator and GID storage. No external construction required.
- **Replacement:** none required (`ROS2Context` and `ROS2Node` own these internally).
- **Impact surface:** code that constructs `EntityManager()` or `GIDManager()` directly.
- **Recommended action:** drop direct instantiation.

### Candidate 5 — `ZenohTransportPublisher` (concrete class)

- **Current location:** `Sources/SwiftROS2Transport/ZenohTransportSession+Publisher.swift`.
- **Current declaration:** `public final class ZenohTransportPublisher: TransportPublisher`.
- **1.0 change:** demoted to `internal` (no cross-target references, so plain `internal` suffices).
- **Rationale:** the protocol `TransportPublisher` already exists, and the umbrella's `ROS2Publisher` is the supported public type that wraps it; the concrete Zenoh class never needed to be public.
- **Replacement:** the umbrella's public `ROS2Publisher`, returned by `node.createPublisher(...)`. The `TransportPublisher` protocol itself was also demoted to `package` (knock-on from Candidate 3) — downstream code can't name it from outside the SPM package.
- **Impact surface:** code that names `ZenohTransportPublisher` directly (e.g. as a stored type), or that holds `any TransportPublisher` from outside the package.
- **Recommended action:** replace with `ROS2Publisher` from `node.createPublisher(...)`.

### Candidate 6 — `DeclaredKeyExpr`, `ZenohSubscriber`, `LivelinessToken`

- **Current location:** `Sources/SwiftROS2Zenoh/ZenohClient.swift`.
- **1.0 change:** demoted to `internal` (no cross-target references, so plain `internal` suffices).
- **Rationale:** internal concrete classes of `ZenohClient`. They should be accessed only through the corresponding handle protocols.
- **Replacement:** `ZenohKeyExprHandle`, `ZenohSubscriberHandle`, `ZenohLivelinessTokenHandle` (which were themselves demoted to `package` in Candidate 3).
- **Impact surface:** code that names these classes directly.
- **Recommended action:** drop direct references.

> **Note:** the analogous Service placeholders (`ROS2ServiceTypeInfo`, `ROS2ServiceType`) were retained in 0.7.0 once the typed `ROS2Service<S>` / `ROS2Client<S>` umbrella landed — they are now real, implemented protocols, not placeholders.

---

## 1.0 → 1.x compatibility contract

After 1.0, no minor or patch release on the 1.x line will break the public API. Breaking changes require a major bump (2.0).
