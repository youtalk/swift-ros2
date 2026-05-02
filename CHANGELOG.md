# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.0] - 2026-05-01

### Added
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
- `ZenohTransportSession` and `DDSTransportSession` split into focused files.

### Notes
- No public API changes. The 0.7.0 line preserves the 0.6.x surface.

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
