# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **ROS 2 Actions — type-system foundation (phase 1 of 6, targeting 0.8.0).** Pure type-system work; no wire / transport / API changes yet.
  - `ROS2ActionTypeInfo` extended with synthesized-wrapper hashes (`sendGoalRequestTypeHash`, `sendGoalResponseTypeHash`, `getResultRequestTypeHash`, `getResultResponseTypeHash`, `feedbackMessageTypeHash`). Source- and ABI-compatible: the original 3-hash initializer is preserved as an explicit overload; the 8-hash initializer is a separate entry point.
  - `BuiltinInterfacesTime` (`builtin_interfaces/msg/Time`) — spec-correct `int32 sec`, `uint32 nanosec`. Distinct from `Header` (which keeps its legacy `UInt32 sec`).
  - Top-level wire messages (publishable through `ROS2Publisher`, write their own encapsulation header inside `encode`): `action_msgs/msg/GoalStatusArray` and `action_msgs/srv/CancelGoal` request/response. The wrappers `ActionSendGoalRequest<Goal>`, `ActionSendGoalResponse`, `ActionGetResultRequest`, `ActionGetResultResponse<Result>`, `ActionFeedbackMessage<Feedback>` are also top-level (per-action `typeName` / `typeHash` is supplied by the action's `ROS2ActionTypeInfo` at publish/subscribe time).
  - Nested CDR payloads (conform to `CDRCodable` only — same convention as `Header` and `Vector3` — so `ROS2Publisher` cannot accept them and emit invalid header-less CDR): `unique_identifier_msgs/msg/UUID` (with `Foundation.UUID` bridge; 16-byte invariant enforced via `private(set)` storage), `action_msgs/msg/GoalInfo`, `action_msgs/msg/GoalStatus`. `GoalStatusCode` (Int8) and `CancelGoalReturnCode` (Int8) enums ship for symbolic-name access.
  - Built-in action: `example_interfaces/action/Fibonacci` for examples and integration tests.
  - All sequence decodes use the existing `CDRDecoder` bound (`maxSequenceElements = 64 MiB`) — the manual `[GoalInfo]` / `[GoalStatus]` walks now go through a new public `CDRDecoder.readSequenceCount()` helper rather than `readUInt32()` directly, so a malicious wire frame cannot drive a giant `reserveCapacity` before decoding fails.
  - All `RIHS01_*` hashes are recorded from a live ROS 2 Jazzy install — they are not invented. Wire codec, transport, server/client, and umbrella API land in subsequent phases.
- **ROS 2 Actions — wire codec (phase 2 of 6, targeting 0.8.0).** Pure wire-format work; transports / API still upcoming.
  - `ZenohWireCodec.ActionRole` enum (`sendGoal` / `cancelGoal` / `getResult` / `feedback` / `status`) and `ZenohWireCodec.makeActionKeyExpr(role:domainId:namespace:actionName:actionTypeName:roleTypeHash:)` — emits the `<domain>/<ns>/<action>/_action/<role>/<dds_role_type>/<hash>` key expression with the same hash-segment rules as the Pub/Sub and Service paths (Humble: `TypeHashNotSupported`; Jazzy+: omitted when `nil`).
  - `ZenohWireCodec.ActionEntityKind` (`actionServer = "SA"`, `actionClient = "CA"`) and `makeActionLivelinessToken(...)` — single-anchor discovery on the `send_goal` request type, mirroring the existing `SS` / `SC` Service liveliness shape.
  - `DDSWireCodec.ActionTopicNames` + `actionTopicNames(namespace:actionName:actionTypeName:)` — returns all 8 `rq/`, `rr/`, `rt/` topics paired with their DDS type names. `cancel_goal` request/response and `status` use fixed `action_msgs` types (lifted to `TypeNameConverter.cancelGoalRequestDDSTypeName` / `cancelGoalResponseDDSTypeName` / `goalStatusArrayDDSTypeName` constants so the two codecs share the source of truth); the remaining five (`SendGoal_Request`, `SendGoal_Response`, `GetResult_Request`, `GetResult_Response`, `FeedbackMessage`) derive per-action via the new `TypeNameConverter.toDDSActionRoleTypeName(_:role:suffix:)`. `ActionTopicNames` exposes a public memberwise initializer (parity with `ServiceTopicNames`) so test mocks downstream of `SwiftROS2Wire` can construct one directly.
  - 25 golden tests under `Tests/SwiftROS2WireTests/ActionWireTests.swift` cover every codec path, namespace handling, leading-slash normalization, and Humble-vs-Jazzy hash differences. They pin the generated key-expression / topic / liveliness-token strings; strings are anchored to the Phase 1 recordings, none invented.
- **ROS 2 Actions — transport-layer protocols (phase 3 of 6, targeting 0.8.0).** Pure protocol-shape work; concrete DDS / Zenoh impls land in Phases 4 / 5.
  - `TransportActionServer` / `TransportActionClient` protocols on `SwiftROS2Transport` carry the lifecycle (`name`, `isActive`, `close`) plus per-client `waitForActionServer` / `sendGoal` / `getResult` / `cancelGoal`. Method bodies are still raw CDR — the umbrella API in Phase 6 will type-erase.
  - `SendGoalAck` / `GetResultAck` / `CancelGoalAck` raw-CDR ack structs and `ActionStatusUpdate` per-goal-id status filter.
  - `ActionRoleTypeHashes` — eight optional hashes the umbrella API extracts from `ROS2ActionTypeInfo` and the transport feeds into the wire codec.
  - `TransportActionServerHandlers` — three closures (`onSendGoal`, `onCancelGoal`, `onGetResult`) the umbrella API supplies to wrap the user's typed `ActionServerHandler`.
  - `ActionPendingTable` actor coordinates per-goal `feedback` / `status` / `result` continuations. Handles the result-before-register race by caching the terminal value, finishes streams on terminal status (4/5/6), and drains every pending goal on `failAll`.
  - `TransportSession.createActionServer(...)` / `createActionClient(...)` requirements with `unsupportedFeature`-throwing default implementations so Phases 4 / 5 can land in either order.
  - `TransportError`: new `goalRejected`, `goalUnknown`, `actionServerUnavailable` cases.
  - 14 new transport-tests cover the actor's full state machine and the default-impl throws.
- **ROS 2 Actions — DDS transport (phase 4 of 6, targeting 0.8.0).**
  - `DDSTransportSession.createActionServer(...)` and `createActionClient(...)` overrides — full server / client over rmw_cyclonedds-style rq/rr/rt topics. Reuses the existing service-pair and pub/sub primitives; no new C-bridge surface.
  - `DDSTransportActionServerImpl`: 3 service-pair handlers (`send_goal`, `cancel_goal`, `get_result`) + 2 publishers (`feedback`, `status`). Status topic uses `transient_local` depth 1 (matches rclcpp). `publishFeedback(goalId:feedbackCDR:)` and `publishStatus(entries:)` are the server-to-stream entry points.
  - `DDSTransportActionClientImpl`: 3 service-pair clients + 2 subscribers, with goal_id filtering on the shared `feedback` and `status` topics — each incoming frame is decoded, the goal_id extracted, and the matching `ActionPendingTable` entry yielded.
  - `ActionFrameDecoder` (internal): pure CDR helpers for the synthesized wrapper frames (encode/decode for `SendGoal{Request,Response}`, `GetResult{Request,Response}`, `FeedbackMessage`, `GoalStatusArray`). 8 round-trip + bounds tests.
  - `MockDDSClient` (test scope): new `serviceReplyHandler` closure + `deliverRequestSample` / `deliverSubscriberSample` test helpers, lets DDS action tests drive end-to-end flows in-process.
  - 9 new transport-tests cover server-side dispatch, client-side acceptance / rejection / result / cancel, goal-id filtering, and close-walk lifecycle.
- **ROS 2 Actions — Zenoh transport (phase 5 of 6, targeting 0.8.0).**
  - `ZenohTransportSession.createActionServer(...)` and `createActionClient(...)` overrides — full server / client over Zenoh queryables (3 services), publishers (`feedback`, `status`), and `SA` / `CA` liveliness tokens. Reuses `ActionFrameDecoder` from Phase 4; no new C-bridge surface.
  - `ZenohTransportActionServerImpl`: 3 queryables for `send_goal` / `cancel_goal` / `get_result`, plus 2 publishers and a single `SA` liveliness anchor on the `send_goal` request type.
  - `ZenohTransportActionClientImpl`: 3 `get(...)` callers, 2 subscribers with goal-id filtering routed through `ActionPendingTable`, a `CA` liveliness token announcement, and `waitForActionServer` that polls the `send_goal` queryable with a 200ms `get` until any reply lands or `timeout` elapses (throws `TransportError.actionServerUnavailable` on miss).
  - `MockZenohClient` (test scope): new `getReplyHandler`, `putsByKey`, `declaredLivelinessTokens`, `deliverQuery`, and `deliverSubscriberSample` test helpers.
  - 8 new transport-tests cover server queryable dispatch, feedback / status publication + liveliness, client send_goal / get_result / status filtering, and `waitForActionServer` timeout.
- **DDS on Windows** — full DDS path (CCycloneDDS, CDDSBridge, SwiftROS2DDS, the SwiftROS2 umbrella, the talker / listener / srv-server / srv-client examples, and the DDS / umbrella tests) now ships on Windows x86_64 when `CYCLONEDDS_DIR` points at a `vcpkg install cyclonedds:x64-windows` tree. Package.swift threads `-I<dir>/include` and `-L<dir>/lib` into CDDSBridge so `#include <dds/dds.h>` and the `-lddsc` link from the CCycloneDDS modulemap resolve against the vcpkg layout. `build-windows` CI now installs the vcpkg port, exports `CYCLONEDDS_DIR`, and runs the full `swift build` + `swift test --parallel`. (#37)

### Changed
- `Package.swift` Windows arm: `if !isWindowsBuild && !isAndroidBuild` gate replaced with a `canBuildDDS` flag that honors `CYCLONEDDS_DIR`. Without `CYCLONEDDS_DIR` the Windows arm keeps the 0.5.0–0.7.0 Zenoh-only shape; with it set, the umbrella + DDS targets join the build graph alongside the existing Zenoh path.

## [0.7.0] - 2026-05-01

### Added
- **Services** — typed `ROS2Service<S>` / `ROS2Client<S>` on top of new `TransportService` / `TransportClient` protocols, with end-to-end Server / Client support over both Zenoh (queryable + `get`) and DDS (rq/rr topics + sample-identity prefix). `ROS2Node.createService(_:name:qos:handler:)` / `createClient(_:name:qos:)` are the public entry points; built-in `std_srvs/srv/Trigger` ships with the package.
- `ServiceError` — public enum covering `.timeout`, `.serviceUnavailable`, `.handlerFailed`, `.requestEncodingFailed`, `.responseDecodingFailed`, `.clientClosed`, `.serverClosed`, `.taskCancelled`, and `.transportError`. Maps lower-level `TransportError` variants automatically.
- `srv-server` / `srv-client` example executables (`swift run srv-server zenoh`, `swift run srv-client dds`, etc.) over `std_srvs/srv/Trigger`.
- Service round-trip integration tests for both Zenoh and DDS (LINUX_IP-gated, plus a same-process DDS loopback that runs unconditionally).
- `ZenohClientProtocol.declareQueryable` / `get` (with `ZenohQueryableHandle` / `ZenohQueryHandle`) and matching DDS rq/rr primitives on `DDSClientProtocol`. `ZenohError.queryReplyError(String)` carries remote-handler errors through to `ServiceError.handlerFailed`.
- `TransportError.requestTimeout(Duration)` / `.requestCancelled` / `.serviceHandlerFailed(String)` and `RMWRequestId` / `SampleIdentityPrefix` for service request / reply correlation on DDS.
- DocC catalog under the `SwiftROS2` umbrella with getting-started articles (Zenoh, DDS) and a wire-format reference.
- `CHANGELOG.md` and `MIGRATION.md` (the latter with the 0.7 → 1.0 candidate change list).
- `Scripts/check-docc-coverage.sh` enforcing `///` comments on every public declaration.
- `docs-build` CI job running `swift package generate-documentation` on every PR.
- Per-target line-coverage gate in CI (`Scripts/coverage-gate.sh`, thresholds in `Scripts/coverage-thresholds.txt`).
- Internal helpers `AttachmentBuilder` and `TransportQoSMapper` (extracted from transport sessions).
- Unit tests for `Node`, `Publisher`, `Subscription`, and `QoSProfile` via mock session.
- Unit tests for `EntityManager`, `GIDManager`, `TransportConfig`, and transport session via mock Zenoh / DDS clients.
- `swift package diagnose-api-breaking-changes 0.6.1` enforced on every PR.

### Changed
- `ZenohTransportSession` and `DDSTransportSession` split into focused files. Both now walk `serviceServers` / `serviceClients` alongside publishers in `close()`.
- `ROS2Node.destroy()` now walks publishers, subscriptions, services, and clients in one teardown pass.

## [0.6.1] - 2026-04-28

### Added
- Services type-system foundation (phase 1): `ROS2ServiceType`, `ROS2ServiceTypeInfo`, `ROS2Service` in `SwiftROS2Messages`.

### Fixed
- CycloneDDS 11 `radmin` header rename support (#55).

## [0.6.0] - 2026-04-25

### Added
- Android cross-compile support (arm64-v8a, x86_64) over Bionic via the unix backend.
- Manifest-scope four-arm split (apple / linux / windows / android) keyed on `SWIFT_ROS2_TARGET_OS`.
- Comprehensive README overhaul with platform/coverage tables and CI badges.
- zenoh-pico bumped to version with `ZENOH_ANDROID` support.

### Fixed
- Android cross-compile from Linux host.

## [0.5.0] - 2026-04-25

### Added
- Android CI matrix (`build-android` per ABI, `test-android-x86_64` emulator job).
- Package.swift four-arm platform split with DDS carved out for Windows and Android.
- Windows cross-compile documentation in README.

## [0.4.0] - 2026-04-21

### Added
- DDS Subscriber (raw CDR reader path).
- Minimal `talker` / `listener` demo executables with CLI transport switch.
- Windows zenoh-pico source build (`build-windows`); DDS family carved out for Windows.

### Fixed
- `ZENOH_MACOS` define missing for iOS and visionOS builds.

## [0.3.1] - 2026-04-19

### Fixed
- Bound untrusted CDR sequence/string lengths to prevent buffer overread (#17).

## [0.3.0] - 2026-04-19

### Changed
- Drop the `Default` prefix from `ZenohClient` / `DDSClient`.
- Make `ZenohClientProtocol` / `DDSClientProtocol` public for client injection.

### Added
- Linux arm64 runners and ROS 2 Rolling added to the build matrix.
- Ubuntu 22.04 + ROS 2 Humble added to the Linux build matrix.

## [0.2.0] - 2026-04-19

### Added
- Initial public release: Zenoh + DDS publishers and subscribers, CDR XCDR v1 codec, 23 built-in message types.
