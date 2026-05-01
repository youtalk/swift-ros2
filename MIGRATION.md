# Migration Guide

## Compatibility table

| From | To | Breaking changes |
|---|---|---|
| 0.6.x | 0.7.x | **None.** The 0.7.x line preserves the 0.6.x public API. |
| 0.7.x | 1.0.0 | Limited to the candidates below, decided after 0.7.0 ships based on a downstream survey. |
| 1.0.x | 1.x   | **None guaranteed.** Minor releases on the 1.x line will not break public API. |

SwiftROS2 follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) once 1.0.0 is cut. Breaking changes after 1.0 require a major bump.

---

## 0.x → 0.7 — no breaking changes

0.7.x adds:
- DocC catalog and richer `///` comments.
- Per-target line-coverage gate in CI.
- `swift package diagnose-api-breaking-changes` on every PR.
- Internal refactors of the transport sessions.

No public type, function, protocol, or property is renamed, removed, or made `internal`.

---

## 0.7 → 1.0 — candidate change list

> **Status:** the actual 1.0 break list is decided **after 0.7.0 ships**, based on a downstream-consumer survey (Conduit and any other known users). Each candidate below describes what *might* change, why it is being considered, and the recommended action you can take during 0.7.x to avoid surprise.

### Candidate 1 — `TransportQoS` and `QoSPolicy`

- **Current location:** `Sources/SwiftROS2Transport/TransportSession.swift` (`TransportQoS`); `Sources/SwiftROS2Wire/WireCodec.swift` (`QoSPolicy`).
- **Current declaration:** `public struct TransportQoS`, `public struct QoSPolicy`.
- **1.0 plan:** make both `internal`.
- **Rationale:** both are derived representations of `QoSProfile`. End users do not need to construct them directly. Three parallel public QoS types (profile / transport / wire) inflate the API surface for no functional gain.
- **Replacement:** `QoSProfile` (presets `.default`, `.sensorData`, `.reliableSensor`, `.latched`, `.servicesDefault`, or `init(reliability:durability:history:)`).
- **Impact surface:** code that constructs `TransportQoS(...)` or `QoSPolicy(...)` directly. Detect with `grep -rn "TransportQoS(\|QoSPolicy(" your-project/`.
- **Recommended action:** replace direct construction with `QoSProfile(...)`.
- **Compatibility shim?** Likely not — the migration is mechanical.

### Candidate 2 — `DDSBridgeQoSConfig`, `DDSBridgeDiscoveryConfig`, `DDSBridgeDiscoveryMode`

- **Current location:** `Sources/SwiftROS2Transport/DDSClientProtocol.swift`.
- **Current declaration:** `public struct DDSBridgeQoSConfig`, `public struct DDSBridgeDiscoveryConfig`, `public enum DDSBridgeDiscoveryMode`.
- **1.0 plan:** make `internal` (alongside Candidate 3).
- **Rationale:** these types only exist in the public API to appear in `DDSClientProtocol` parameters. `DDSBridgeDiscoveryMode` (Int32-raw) duplicates `TransportConfig.DDSDiscoveryMode` (String-raw) at the concept level.
- **Replacement:** `TransportConfig.DDSDiscoveryMode` and `DDSPeer` continue to be the public configuration surface.
- **Impact surface:** code that constructs `DDSBridgeQoSConfig(...)` or `DDSBridgeDiscoveryConfig(...)` directly. Grep for `DDSBridge`.
- **Recommended action:** replace direct construction with `TransportConfig.ddsMulticast(...)` / `TransportConfig.ddsUnicast(...)`.
- **Compatibility shim?** None planned.

### Candidate 3 — `ZenohClientProtocol`, `DDSClientProtocol`, and related public types

- **Related types (8):** `ZenohKeyExprHandle`, `ZenohSubscriberHandle`, `ZenohLivelinessTokenHandle`, `ZenohSample`, `ZenohError`, `DDSWriterHandle`, `DDSReaderHandle`, `DDSError` plus the 3 in Candidate 2.
- **Current location:** `Sources/SwiftROS2Transport/{Zenoh,DDS}ClientProtocol.swift`.
- **1.0 plan:** make `internal`.
- **Rationale:** these protocols exist so consumers can wrap the C bridge themselves and inject a custom client. In practice Conduit uses `ZenohClient()` / `DDSClient()` from `SwiftROS2Zenoh` / `SwiftROS2DDS` directly. The implementation-injection seam is over-budget for an actual freeze.
- **Replacement:** stock `ZenohClient` / `DDSClient` for production use, plus an internal testing utility for unit tests.
- **Impact surface:** code that conforms to `ZenohClientProtocol` / `DDSClientProtocol` (custom wrappers). Grep for `: ZenohClientProtocol\|: DDSClientProtocol`.
- **Recommended action:** if you have a custom implementation, contact the maintainer during 0.7.x so the use case can be considered before the freeze.
- **Compatibility shim?** Decided during the 0.7.0 → 1.0.0 survey.

### Candidate 4 — `EntityManager`, `GIDManager`

- **Current location:** `Sources/SwiftROS2Transport/{EntityManager,GIDManager}.swift`.
- **Current declaration:** `public final class`.
- **1.0 plan:** make `internal`.
- **Rationale:** library-internal entity-id allocator and GID storage. No external construction required.
- **Replacement:** none required (`ROS2Context` and `ROS2Node` own these internally).
- **Impact surface:** code that constructs `EntityManager()` or `GIDManager()` directly.
- **Recommended action:** drop direct instantiation.
- **Compatibility shim?** None planned.

### Candidate 5 — `ZenohTransportPublisher` (concrete class)

- **Current location:** `Sources/SwiftROS2Transport/ZenohTransportSession+Publisher.swift`.
- **Current declaration:** `public final class ZenohTransportPublisher: TransportPublisher`.
- **1.0 plan:** make `internal`.
- **Rationale:** the protocol `TransportPublisher` already exists; the concrete class does not need to be public too.
- **Replacement:** the `TransportPublisher` protocol (which itself follows Candidate 3 if that group is also internalized).
- **Impact surface:** code that names `ZenohTransportPublisher` directly (e.g. as a stored type).
- **Recommended action:** replace with `any TransportPublisher`.
- **Compatibility shim?** None planned.

### Candidate 6 — `DeclaredKeyExpr`, `ZenohSubscriber`, `LivelinessToken`

- **Current location:** `Sources/SwiftROS2Zenoh/ZenohClient.swift`.
- **1.0 plan:** make `internal`.
- **Rationale:** internal concrete classes of `ZenohClient`. They should be accessed only through the corresponding handle protocols.
- **Replacement:** `ZenohKeyExprHandle`, `ZenohSubscriberHandle`, `ZenohLivelinessTokenHandle` (which themselves follow Candidate 3 if that group is also internalized).
- **Impact surface:** code that names these classes directly.
- **Recommended action:** drop direct references.
- **Compatibility shim?** None planned.

### Candidate 7 — Service / Action public declarations with no implementation

- **Targets:** `ROS2ServiceTypeInfo`, `ROS2ActionTypeInfo`, `ROS2Service`, `ROS2Action` in `SwiftROS2Messages`.
- **1.0 plan:** remove (or make `internal`).
- **Rationale:** placeholders with no implementation. Freezing them would constrain the eventual Service / Action API design.
- **Replacement:** none (the feature is not provided today).
- **Impact surface:** code that names these types or conforms to them.
- **Recommended action:** remove any references — they do not do anything yet.
- **Compatibility shim?** None.

---

## 1.0 → 1.x compatibility contract

After 1.0, no minor or patch release on the 1.x line will break the public API. Breaking changes require a major bump (2.0).
