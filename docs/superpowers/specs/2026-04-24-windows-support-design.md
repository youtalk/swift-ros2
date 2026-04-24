# Windows support for swift-ros2 — design

- **Date:** 2026-04-24
- **Target release:** 0.5.0
- **Scope:** Full Zenoh + DDS support on Windows x86_64 (native Swift client), matching existing Apple / Linux coverage.
- **Out of scope:** Windows arm64 (reserved for a later release), MinGW toolchain (MSVC ABI only, matches official Swift on Windows).

## 1. Background

swift-ros2 today runs on Apple (iOS / iPadOS / macOS / Mac Catalyst / visionOS) and Linux (Ubuntu 22.04 / 24.04, x86_64 and aarch64). Apple consumes pre-built `CZenohPico.xcframework` + `CCycloneDDS.xcframework` via SPM `.binaryTarget`; Linux compiles zenoh-pico from the `vendor/zenoh-pico` submodule and resolves CycloneDDS through `pkg-config`. Swift itself has shipped a supported Windows toolchain (swift.org, `x86_64-unknown-windows-msvc`) since 5.3, and SwiftPM supports `.artifactbundle` binary targets on non-Apple platforms. Adding Windows is therefore primarily a packaging and CI exercise — the pure-Swift layers are already portable.

## 2. Feasibility findings

Surveyed the current repository at commit `32c5fbb` (0.4.0).

| Area | Result |
|---|---|
| `import Darwin` / `import Glibc` in Swift sources | **None** — the codebase has no direct platform-runtime imports. |
| `GIDManager` random source | Already gated `#if canImport(Security)` with UUID fallback — Windows falls through to UUID path automatically. |
| `ZenohClient` logging | Already gated `#if canImport(os.log)` — Windows skips os_log. |
| Dispatch usage (`ZenohTransportSession.DispatchQueue.global`) | libdispatch ships with the Swift Windows toolchain — portable. |
| `CZenohBridge` C includes | Standard C + `zenoh-pico.h` only. No POSIX API. |
| `CDDSBridge` C includes | Standard C + CycloneDDS public + internal headers. No POSIX API. |
| zenoh-pico Windows backend | `vendor/zenoh-pico/src/system/windows/{system.c,network.c}` ships upstream; currently excluded by the Linux branch of `Package.swift`. Uses `winsock2.h` / `iphlpapi.h` / `ntsecapi.h`; links `Ws2_32.lib` + `Iphlpapi.lib`; define `ZENOH_WINDOWS`. |
| CycloneDDS Windows support | Officially supported by Eclipse; builds with CMake + MSVC. `pkg-config` is not available on Windows, so the Linux `.systemLibrary` pattern cannot be reused verbatim. |

**Conclusion:** no Swift or C source patches are required beyond platform gating in `Package.swift`. All engineering effort is in (a) packaging and (b) CI.

## 3. Distribution strategy — Option B

Both native C dependencies ship as pre-built artifact bundles published on the existing GitHub Release, matching the approach already used for Apple `.xcframework`s.

Rationale:
- Consistent user experience across OS: `swift build` is enough everywhere.
- Encapsulates CycloneDDS's CMake complexity inside release CI instead of forcing it on every downstream build.
- Mirrors the existing `xcframeworkBaseURL` convention, so downstream consumers (Conduit, future Windows users) get a single versioned URL per dependency.

Alternatives considered and rejected:

- **Source build via SPM `.target`** — zenoh-pico would be straightforward (the backend sources exist), but CycloneDDS depends on generated `ddsrt` feature-detection headers produced by its CMake build. Replicating this in SwiftPM is a disproportionate undertaking.
- **System-installed via vcpkg** — splits the developer experience: Apple/Linux use submodules + one command, Windows would use a separate package manager. Worse UX with no offsetting benefit for this project.

## 4. Architecture changes

### 4.1 `Package.swift`

Extend the existing two-way split (Linux vs else) into three arms:

```swift
let cZenohPico: Target = {
    #if os(Linux)
        // unchanged: .target over vendor/zenoh-pico
    #elseif os(Windows)
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(xcframeworkBaseURL)/CZenohPico-windows-x86_64.artifactbundle.zip",
            checksum: "<computed after release zip upload>"
        )
    #else   // Apple
        // unchanged: .binaryTarget over .xcframework.zip
    #endif
}()
```

`cCycloneDDS` receives the same three-arm treatment with a parallel `CCycloneDDS-windows-x86_64.artifactbundle.zip` URL.

`CZenohBridge` gains Windows-specific settings:

```swift
cSettings: [
    .define("ZENOH_MACOS", to: "1", .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
    .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
    .define("ZENOH_WINDOWS", to: "1", .when(platforms: [.windows])),
    .define("Z_FEATURE_LINK_TCP", to: "1"),
    .define("Z_FEATURE_LIVELINESS", to: "1"),
],
linkerSettings: [
    .linkedLibrary("Ws2_32", .when(platforms: [.windows])),
    .linkedLibrary("Iphlpapi", .when(platforms: [.windows])),
]
```

The package-level `platforms:` array only declares Apple deployment targets; Linux and Windows use SwiftPM defaults, so it does not change.

### 4.2 Artifact bundle layout

SwiftPM's non-Apple `.binaryTarget` requires the `.artifactbundle` format. Each Windows dependency ships as:

```
CZenohPico-windows-x86_64.artifactbundle/
├── info.json
└── CZenohPico-0.5.0-windows/
    └── x86_64-unknown-windows-msvc/
        ├── lib/
        │   ├── CZenohPico.lib      # MSVC import library
        │   └── CZenohPico.dll      # runtime shared library
        └── include/
            └── zenoh-pico/...       # full public header tree
```

`CCycloneDDS-windows-x86_64.artifactbundle` has the identical shape. Its `include/` must carry the internal headers `CDDSBridge/raw_cdr_sertype.c` consumes:

- `dds/ddsi/q_radmin.h`
- `dds/ddsi/ddsi_sertype.h`
- `dds/ddsi/ddsi_serdata.h`
- `dds/ddsrt/heap.h`
- `dds/ddsrt/md5.h`

These are present in the upstream CycloneDDS install tree — the packaging step copies them explicitly.

The final Release asset is the `.artifactbundle` directory compressed as a zip whose top-level entry is the bundle root.

### 4.3 Release workflow (`.github/workflows/release-xcframework.yml`)

Add two Windows jobs alongside the existing macOS job:

- **`build-zenoh-pico-windows`** — `runs-on: windows-latest`
  - Checkout with `submodules: recursive`
  - CMake + MSBuild build of `vendor/zenoh-pico` in Release configuration with `BUILD_SHARED_LIBS=ON`, `Z_FEATURE_LINK_TCP=1`, `Z_FEATURE_LIVELINESS=1`
  - Assemble artifact bundle (copy `.lib`, `.dll`, and `include/zenoh-pico/`)
  - Emit `info.json`
  - Zip and upload via `actions/upload-artifact`

- **`build-cyclonedds-windows`** — `runs-on: windows-latest`
  - Fetch CycloneDDS at a pinned upstream tag (no submodule; only release CI needs the source)
  - CMake configure with `-DENABLE_SSL=OFF -DENABLE_SECURITY=OFF -DBUILD_IDLC=OFF -DBUILD_DDSPERF=OFF` (features unused by swift-ros2)
  - Build Release, install into a staging tree
  - Copy required public + internal headers into the bundle's `include/`
  - Zip and upload

- **`publish`** (existing, extended) — collect every artifact, compute each zip's SHA-256 for inclusion in the release notes, attach them all via `softprops/action-gh-release`.

### 4.4 CI workflow (`.github/workflows/ci.yml`)

Add a single `build-windows` job parallel to `build-macos` / `build-linux`:

```yaml
build-windows:
  runs-on: windows-latest
  steps:
    - uses: actions/checkout@v4
      with: { submodules: recursive }
    - uses: compnerd/gha-setup-swift@v0.2
      with:
        branch: swift-6.0.2-release
        tag: 6.0.2-RELEASE
    - run: swift build
    - run: swift test --parallel
```

The integration target `SwiftROS2IntegrationTests` skips itself when `LINUX_IP` is unset, so no additional guarding is needed to keep it out of Windows CI.

## 5. Development flow constraint

The maintainer does not have a local Windows development environment. All Windows build and test verification is performed exclusively through GitHub Actions. Concrete consequences for this project:

- Changes that touch the Windows path are validated by pushing a branch (or a short-lived draft tag like `0.5.0-rc.1`) and reading the `build-windows` / release workflow logs rather than running `swift build` locally.
- Iteration cadence is limited to CI turnaround time (single-digit minutes for `swift build`, longer for the release CI that builds native dependencies). Expect multiple CI cycles to shake out MSVC build issues.
- Debugging information lives in the Actions log; when a Windows failure is not reproducible elsewhere, add targeted `CMake --log-level=VERBOSE` or verbose `swift build -v` output to the relevant workflow step to capture diagnostics in-band rather than trying to reproduce locally.
- Release workflow jobs are the source of truth for the artifact bundles; developers should not be expected to produce Windows bundles by hand.

This constraint is why CI scope is intentionally kept at build + unit tests only (no localhost or LAN E2E). Expanding beyond that later is possible, but requires either self-hosted runners or carefully designed loopback harnesses that can be diagnosed from logs alone.

## 6. Source changes required

Based on the feasibility audit, the change set outside packaging is minimal:

1. `Package.swift` — three-arm platform split for `cZenohPico` and `cCycloneDDS`; additional `cSettings` / `linkerSettings` on `CZenohBridge` for Windows (see §4.1).
2. `Sources/CZenohBridge/zenoh_bridge.c` — if any GCC-specific attributes are in use (none identified today), gate them behind `#if defined(_MSC_VER)`. If no build error appears, nothing changes.
3. Documentation: `CLAUDE.md` gains a short "Windows" subsection under "Build & test commands" explaining that local Windows builds are not expected — point developers at CI logs.

All other Swift / C source remains untouched.

## 7. Milestones

| Phase | Deliverable | Verification |
|---|---|---|
| **M1 — `Package.swift` scaffolding** | Three-arm platform split with placeholder Windows `binaryTarget` URLs. | Existing macOS + Linux CI stays green. |
| **M2 — zenoh-pico Windows bundle** | `build-zenoh-pico-windows` job in release workflow. RC-tag produces a bundle. | On Windows CI, `swift build` reaches `SwiftROS2Zenoh`. |
| **M3 — CycloneDDS Windows bundle** | `build-cyclonedds-windows` job. Internal headers present. | On Windows CI, `swift build` reaches `SwiftROS2DDS`. |
| **M4 — Windows CI job + tests green** | `build-windows` job in `ci.yml`. Swift 6.0.2 pin. | All unit test targets pass on Windows. |
| **M5 — 0.5.0 release** | Tag `0.5.0`, Release carries Apple xcframeworks + Windows artifact bundles. `Package.swift` checksums finalized. | Conduit `deps/swift-ros2` can bump to 0.5.0 without regression. |

Each milestone is a separate PR.

## 8. Risks and open questions

1. **MSVC building zenoh-pico.** The Windows backend sources exist, but upstream CI emphasis is not MSVC. M2 is the first point where this is exercised. Fallback: build via `clang-cl` (the same MSVC-ABI clang driver that the Swift Windows toolchain already uses), or patch zenoh-pico locally in the release CI step (contribute upstream afterwards). Resolution target: M2.
2. **CycloneDDS shared vs static on Windows.** Shared libraries on Windows require `__declspec(dllimport)` / `dllexport` annotations on public symbols. If upstream CycloneDDS does not emit these cleanly, switch to `-DBUILD_SHARED_LIBS=OFF` and ship only a static `.lib` — the artifact bundle loses `CCycloneDDS.dll` but gains the side benefit of no DLL runtime search. Resolution target: M3.
3. **CycloneDDS internal header exposure.** `q_radmin.h` is an internal header whose layout may shift between Cyclone versions. Pin to a specific CycloneDDS tag in the release CI and document the pin in the workflow. Resolution target: M3.
4. **XCTest behavioral differences on Windows.** Known to exist but unlikely to be hit by the current unit tests (no subprocess spawning, no signal handling, no locale-sensitive formatting). If a divergence surfaces, gate the affected test with `#if !os(Windows)` and file a follow-up. Resolution target: M4.
5. **arm64 Windows.** Deliberately deferred. The artifact bundle's `info.json` reserves `aarch64-unknown-windows-msvc` as a future triple slot, so adding it later is additive.
6. **Bundle zip layout gotcha.** SwiftPM expects the zip's top-level entry to be the `.artifactbundle` directory. Misconstructed zips produce opaque errors. The release workflow's packaging step must be validated (unzip + `swift package compute-checksum` + a minimal consumer project that imports the bundle) during M2.
7. **`.binaryTarget` for C libraries on Windows is under-exercised.** SwiftPM's non-Apple binary-target support is best-documented for executables. For C libraries on Windows there is less community precedent; `info.json` schema and `type` field semantics must be validated empirically in M2 with a minimal consumer project. **Fallback if unworkable:** drop zenoh-pico back to the source-build `.target` path already used on Linux (the Windows backend sources are upstream; add a third arm to the `.target` exclude/include lists and a set of `Z_FEATURE_*` + `_WIN32_WINNT` defines). CycloneDDS source-build via SwiftPM remains infeasible; if `.binaryTarget` does not cover it, the fallback is to require Windows users to install CycloneDDS via a vendor-provided MSI or CMake install tree and switch to `unsafeFlags` for include / lib paths keyed off an environment variable — a clear UX regression relative to Apple, but contained to CycloneDDS alone. Resolution target: M2 (validated against a toy consumer project before investing in M3).

## 9. Coordination with downstream

Conduit pins `deps/swift-ros2` at `0.4.0` today. After 0.5.0 ships, Conduit can bump its submodule and — because the `Package.swift` Windows arm is additive — nothing in Conduit's existing Apple / Linux build path changes. Conduit itself does not need to target Windows for this release; swift-ros2's Windows support is a library-side capability that downstream projects opt into when they do.
