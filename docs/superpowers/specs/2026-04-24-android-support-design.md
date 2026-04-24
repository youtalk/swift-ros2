# Android support for swift-ros2 — design

- **Date:** 2026-04-24
- **Target release:** 0.5.0 — first release after 0.4.0. Picks up the 0.5.0 slot after the Linux binary-distribution track (PR #32) was closed / rejected. Next release after Android ships will be 0.7.0 (Windows DDS support; 0.6.0 is skipped to keep the main-branch Windows-readme messaging that already targets 0.7.0).
- **Scope:** Android `arm64-v8a` + `x86_64`, minimum API 28, Swift 6.3+. `swift-ros2` compiles against the official swift.org Android SDK and can be consumed by any Android-target SwiftPM client. CI on GitHub Actions runs `swift build` for both ABIs and `swift test` on an x86_64 emulator.
- **Out of scope:** `armeabi-v7a` (32-bit ARM), API 24–27, LAN-gated integration tests, physical-device verification, Kotlin / JNI bridge layer, Android Studio / Gradle integration, **DDS on Android** (CycloneDDS carved out of Android scope, mirroring the Windows decision in M2 — `SwiftROS2Zenoh` is the only transport available on Android in 0.5.0).

## 1. Background

swift-ros2 ships on Apple (iOS / iPadOS / macOS / Mac Catalyst / visionOS), Linux (Ubuntu 22.04 / 24.04, x86_64 + aarch64), and Windows (x86_64; Zenoh only, merged in `8c55971`). Non-Apple platforms use a mixed native-dependency model: **`zenoh-pico` is compiled from source via SwiftPM** — Linux pulls in `vendor/zenoh-pico/src/system/unix/…`, Windows pulls in `vendor/zenoh-pico/src/system/windows/…`, each with the matching `ZENOH_<PLATFORM>` preprocessor define — while **CycloneDDS on Linux is resolved via `pkg-config` as a SwiftPM `.systemLibrary`**, and DDS is excluded entirely on Windows. The `.artifactbundle` route for non-Apple static libraries was explored in PR #32 (Linux binary distribution) and **rejected** on 2026-04-24 — Windows M2 had already pivoted back to source build for the same underlying SwiftPM-on-Windows rejection of C-library `.artifactbundle` inputs, and the Linux attempt surfaced additional cross-platform ergonomic issues (tracked in #26). Source-build remains the canonical non-Apple distribution path for vendored C code such as `zenoh-pico`.

On 2026-03-24 the Swift project shipped **Swift 6.3**, which includes the first official Swift SDK for Android. This closes the tooling gap. Android is the natural next platform, and the "source build from `vendor/zenoh-pico`" model already used on Linux and Windows is the lowest-risk way to bring Android in.

Unlike Conduit (the current production consumer), swift-ros2 Android support is pursued on its own merits: the library should cover Android for any future Kotlin/Swift-hybrid or Swift-only Android consumer.

## 2. Feasibility findings

Surveyed at commit `8c55971` (Windows M2 merged), plus the Swift 6.3 Android SDK docs, Android NDK r26, and `youtalk/zenoh-pico` fork (`swift-ros2-main`).

| Area | Result |
|---|---|
| Swift source platform imports (`import Darwin` / `import Glibc`) | None — `Sources/SwiftROS2*/` is pure Swift. |
| `GIDManager` random source | Already gated `#if canImport(Security)` with UUID fallback. Android takes the UUID path; no change. |
| `ZenohClient` logging | Already gated `#if canImport(os.log)`. Android skips os_log. |
| libdispatch on Android | Bundled with the Swift 6.3 Android SDK. |
| `CZenohBridge` C includes | Standard C + `zenoh-pico.h`. No POSIX syscall. |
| zenoh-pico `src/system/unix/` on Bionic | Uses POSIX sockets + pthread, both present in Bionic. Compiles with NDK out of the box. |
| zenoh-pico CMake / preprocessor Android branch | **Missing upstream and in `youtalk/zenoh-pico` fork.** The fork currently fatal-errors on `CMAKE_SYSTEM_NAME=Android`, and source-level backend gates (`#if defined(ZENOH_LINUX) || …`) do not list `ZENOH_ANDROID`. Fork patch required. |
| CycloneDDS on Android (NDK) | Upstream ships `ports/android/` with cross-compile instructions. SwiftPM cannot consume CycloneDDS from source, though — `ddsrt` generates feature-detection headers at CMake configure time that SPM cannot orchestrate (same reason Windows carved DDS out in M2). |
| SwiftPM `Platform.android` in `Package.swift` | Supported in Swift 6.3 — `.when(platforms: [.android])` works. `#if os(Android)` static branches also work. |
| Swift Android SDK ships NDK equivalent | Yes — the SDK includes the Android sysroot (Bionic headers + libc.so shim) and clang. Downstream consumers do NOT need a separate NDK install. `swift sdk install` + `swift build --swift-sdk …-android28` is sufficient. |

**Conclusion:** no Swift source patches required. Engineering scope:
- (a) `youtalk/zenoh-pico` fork adds `ZENOH_ANDROID` branches.
- (b) `Package.swift` grows a fourth `cZenohPico` arm for Android (source build, unix backend, `ZENOH_ANDROID` define) and the DDS-carve-out gate extends to include Android.
- (c) CI runs `swift build` for both ABIs + `swift test` on an x86_64 emulator.

No release-workflow changes. No artifact bundles. No bundle scripts. No checksum pinning for C dependency artifacts; the Swift Android SDK download in CI is URL + SHA-256 pinned (see §6).

## 3. Distribution strategy — source build (matches Linux + Windows)

Android compiles `vendor/zenoh-pico` from source through SwiftPM, the same way Linux and Windows already do. Consumers pay ~1 min of extra C-compile time on their first `swift build`; no NDK install, no bundle fetch, no checksum dance. This is also what we know works end-to-end in swift-ros2 as of `8c55971`.

Alternatives considered and rejected:

- **`.artifactbundle` via `.binaryTarget`.** Design Windows attempted in M1/M2 and rolled back from, and Linux attempted in PR #32 and was rejected. The two attempts together are sufficient evidence that this path is not currently viable for swift-ros2 on non-Apple SwiftPM; Android does not re-try it.
- **Source-build CycloneDDS on Android.** Blocked by the same `ddsrt` CMake-configure-time header generation issue that killed source-build CycloneDDS on Windows. Out of scope for 0.5.0; defer to a future dedicated "DDS on carved-out platforms" design.

## 4. `Package.swift` changes

### 4.1 `cZenohPico` fourth arm

Insert `#elseif os(Android)` between the existing Windows arm and the Apple `#else` arm. The arm is a near-clone of the Linux arm with three differences: (i) exclude `src/system/unix`'s peer `src/system/windows` (as Linux already does), (ii) keep `src/system/unix` (like Linux), (iii) define `ZENOH_ANDROID` instead of `ZENOH_LINUX`.

```swift
let cZenohPico: Target = {
    #if os(Linux)
        // unchanged
    #elseif os(Windows)
        // unchanged (compiles src/system/windows)
    #elseif os(Android)
        return .target(
            name: "CZenohPico",
            path: "vendor/zenoh-pico",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE", "tests", "examples", "docs", "ci",
                // Android uses the unix backend (Bionic is POSIX-ish);
                // exclude every other backend, same pattern as Linux.
                "src/system/arduino",
                "src/system/emscripten",
                "src/system/espidf",
                "src/system/freertos_plus_tcp",
                "src/system/mbed",
                "src/system/rpi_pico",
                "src/system/void",
                "src/system/windows",
                "src/system/zephyr",
                "src/system/flipper",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
                .define("ZENOH_ANDROID", to: "1"),
            ]
        )
    #else
        // unchanged (Apple xcframework)
    #endif
}()
```

### 4.2 DDS carve-out extended to Android

The existing `#if !os(Windows)` gate around `cCycloneDDS`, the DDS stack products/targets, umbrella `SwiftROS2`, examples, and DDS/umbrella tests becomes `#if !os(Windows) && !os(Android)`. Android consumers import `SwiftROS2Zenoh` directly, exactly like Windows consumers do today.

Four `#if !os(Windows)` sites in `Package.swift` (inspected at `8c55971`):

1. Around the `cCycloneDDS` `let` factory.
2. Around the `products.append(contentsOf: [.library(name: "SwiftROS2"), …])`.
3. Around the `targets.append(contentsOf: [cCycloneDDS, CDDSBridge, …, SwiftROS2IntegrationTests])`.
4. The block comment above (3) that notes Windows is excluded pending M3.

All four become `#if !os(Windows) && !os(Android)`. The block comment is updated to mention both.

### 4.3 `CZenohBridge` cSettings

Add a dedicated `ZENOH_ANDROID` define, even though `CZenohBridge` itself does not currently gate anything on it. Keeping the flag present maintains symmetry with the other three platform defines and gives future Bionic-specific code a clean branch.

```swift
cSettings: [
    .define("ZENOH_MACOS", to: "1", .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
    .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
    .define("ZENOH_WINDOWS", to: "1", .when(platforms: [.windows])),
    .define("ZENOH_ANDROID", to: "1", .when(platforms: [.android])),   // ← new
    .define("Z_FEATURE_LINK_TCP", to: "1"),
    .define("Z_FEATURE_LIVELINESS", to: "1"),
],
```

`linkerSettings` stays unchanged: Android's Bionic libc provides `socket` / `poll` / `pthread` directly.

### 4.4 Header comment

Replace the block comment at the top of `Package.swift` to list Android alongside Linux / Windows as source-build, and note that Android carves out DDS the same way Windows does.

## 5. Vendor fork — `youtalk/zenoh-pico` (`swift-ros2-main`)

Two patches, estimated at ~10–20 lines total.

### 5.1 `CMakeLists.txt`

Add an Android branch to the platform switch (near line 167 in today's file):

```cmake
if(CMAKE_SYSTEM_NAME MATCHES "Linux")
  pico_add_compile_definition(ZENOH_LINUX)
  # ... existing Linux handling
elseif(CMAKE_SYSTEM_NAME MATCHES "Android")
  pico_add_compile_definition(ZENOH_ANDROID)
elseif(CMAKE_SYSTEM_NAME MATCHES "BSD")
  pico_add_compile_definition(ZENOH_BSD)
# ...
```

Also extend the unix-backend-collection `elseif` further down to include Android (around line 352):

```cmake
elseif(CMAKE_SYSTEM_NAME MATCHES "Linux" OR CMAKE_SYSTEM_NAME MATCHES "Darwin" OR CMAKE_SYSTEM_NAME MATCHES "BSD" OR CMAKE_SYSTEM_NAME MATCHES "Android" OR POSIX_COMPATIBLE)
```

SwiftPM consumers of the fork do not invoke CMake — but downstream CMake consumers (and the swift-ros2 ecosystem in general) benefit from correct CMake behavior. The SwiftPM build route uses the source glob from `Package.swift`, which is where exclusion lives.

### 5.2 Source preprocessor gates

Where zenoh-pico selects the unix backend at C compile time via `#if defined(ZENOH_LINUX) || defined(ZENOH_MACOS) || defined(ZENOH_BSD)`, extend to include `|| defined(ZENOH_ANDROID)`. Grep uncovers 3–10 such sites in `include/zenoh-pico/system/` and `src/system/`. Add `ZENOH_ANDROID` to every gate that selects unix-backend behavior. Do **not** add it to Linux-specific gates (e.g., a glibc-only call) that have no Android business.

## 6. CI — `.github/workflows/ci.yml`

Two new jobs sit next to the existing `build-linux` matrix and `build-windows`.

### 6.1 `build-android` (matrix on ABI)

```yaml
build-android:
  name: Build Android (${{ matrix.abi }})
  runs-on: ubuntu-latest
  strategy:
    fail-fast: false
    matrix:
      include:
        - abi: arm64-v8a
          triple: aarch64-unknown-linux-android28
        - abi: x86_64
          triple: x86_64-unknown-linux-android28
  steps:
    - uses: actions/checkout@v4
      with: { submodules: recursive }
    - name: Install Swift 6.3
      # swift.org tarball, pinned to 6.3.x
    - name: Install Swift Android SDK
      run: swift sdk install <pinned-URL> --checksum <pinned-sha>
    - name: swift build
      run: swift build --swift-sdk ${{ matrix.triple }}
```

Both ABIs compile. No tests run in this job.

### 6.2 `test-android-x86_64` (emulator)

```yaml
test-android-x86_64:
  name: Test Android (x86_64 emulator)
  runs-on: ubuntu-latest
  steps:
    - checkout + Swift 6.3 + Swift Android SDK install
    - swift build --build-tests --swift-sdk x86_64-unknown-linux-android28
    - Enable KVM group perms
    - reactivecircus/android-emulator-runner@v2:
        api-level: 28
        arch: x86_64
        script: bash Scripts/run-android-tests.sh
```

`Scripts/run-android-tests.sh` discovers built test binaries under `.build/x86_64-unknown-linux-android28/debug/`, pushes them via `adb push` to `/data/local/tmp/swift-ros2-tests/` alongside the Swift Android runtime, runs each under `LD_LIBRARY_PATH`, and returns non-zero on any failure.

arm64-v8a is not tested at runtime — arm64 emulator on x86_64 host has no KVM acceleration and is impractically slow. arm64 is build-verified; runtime correctness is inferred from the shared pure-Swift + identical C layer.

## 7. Coverage summary

| Build target | CI build | CI unit test | Distribution | Transports available |
|---|---|---|---|---|
| Apple iOS / macOS / Catalyst / visionOS | ✓ | ✓ (macOS) | xcframework | Zenoh + DDS |
| Linux x86_64 / aarch64 | ✓ | ✓ | source (`.artifactbundle` attempt rejected in PR #32) | Zenoh + DDS |
| Windows x86_64 | ✓ | ✓ | source | Zenoh only |
| **Android arm64-v8a** | **✓ (new)** | — | **source (new)** | **Zenoh only** |
| **Android x86_64** | **✓ (new)** | **✓ emulator (new)** | **source (new)** | **Zenoh only** |

## 8. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Swift 6.3 Android SDK is new (2026-03-24 initial release). Patch versions may shift SDK layout or `swift-sdk` resolution. | Pin a specific 6.3.x URL + checksum in CI; bump deliberately behind a smoke-test PR. |
| zenoh-pico unix backend hits a Bionic-specific divergence (missing POSIX call, different errno). | Unit tests in the x86_64 emulator catch most regressions. Any needed divergence lives in an `#if defined(ZENOH_ANDROID)` branch in `src/system/unix/` on the fork. |
| Android emulator CI flakiness (well-known pain point). | `reactivecircus/android-emulator-runner@v2` is the de-facto standard and supports retry + caching. Start with `retry: 2`; escalate to a self-hosted runner if flakiness > 5 %. |
| SwiftPM `.when(platforms: [.android])` edge cases in Swift 6.3 toolchain releases. | Fall back to `#if os(Android)` static branches — the pattern the current Linux / Windows arms already use. |
| User expectation of DDS on Android. | README + release notes call out explicitly: Android (and Windows) is Zenoh-only. Include a "roadmap" line noting DDS-on-Android is blocked on the same CycloneDDS-via-SPM issue as Windows, and will be tackled in a future dedicated design. |
| Downstream consumers expecting an `.artifactbundle` distribution (to skip the C compile). | Source build is the path for every non-Apple platform in swift-ros2 (Linux, Windows, Android). If the upstream SwiftPM picture changes and consumption becomes reliable on non-Apple hosts, a future release can offer an optional pre-built distribution uniformly across all three platforms; until then all three share the same source-compile model. |

## 9. Release alignment

Confirmed release ordering:

| Version | Scope | Status |
|---|---|---|
| 0.4.0 | — | Released |
| 0.5.0 (old) | Linux binary distribution (`.artifactbundle`) | **Rejected** — PR #32 closed 2026-04-24. Source build remains the Linux path. |
| **0.5.0 (this spec)** | **Android support** — picks up the 0.5.0 slot that became free when PR #32 closed. | Design this document |
| 0.7.0 | Windows DDS support (deferred from Windows M2 by `#if !os(Windows)` gate) | Not designed yet; 0.6.0 is skipped to keep the main-branch README messaging that already advertises Windows DDS as 0.7.0. |

The Android 0.5.0 work touches:
- `Package.swift` — adds a fourth `cZenohPico` arm (new code, disjoint hunk), extends the DDS carve-out gate (one additional `&& !os(Android)` token).
- `vendor/zenoh-pico` submodule pointer — bumped to a new fork tip.
- `.github/workflows/ci.yml` — adds two jobs.
- `README.md` — adds an Android row to the platforms table.
- `Scripts/run-android-tests.sh` — new file.

It does **not** touch `.github/workflows/release-xcframework.yml`, `Scripts/build-*-bundle.sh`, or any release-tag packaging. No other tracks are in flight against these surfaces.

## 10. Implementation roadmap

1. **Fork patch** — `youtalk/zenoh-pico` gains `ZENOH_ANDROID` CMake branch + preprocessor-gate extensions. PR merges in the fork repo, submodule bumps in this repo.
2. **`Package.swift` four-arm split + DDS carve-out extension** — single PR.
3. **README update** + `Scripts/run-android-tests.sh`.
4. **CI jobs** — `build-android` (matrix) + `test-android-x86_64` (emulator). Uses Swift 6.3 Android SDK (pinned URL + checksum).
5. **Release** — cut 0.5.0 tag; existing release workflow publishes Apple xcframeworks (unchanged). README / roadmap reflect Android.

Four PRs total (fork PR + Package.swift PR + CI jobs PR + README/Scripts PR, though the last three could be bundled into one or two PRs depending on review appetite).

## 11. References

- [Swift 6.3 Released | Swift.org](https://www.swift.org/blog/swift-6.3-released/) — includes the Android SDK announcement.
- [Swift Android SDK installation](https://www.swift.org/install/android/) — `swift sdk install` flow.
- Windows M2 commit `8c55971` — precedent for source-build + DDS carve-out.
- PR #32 — the rejected Linux binary-distribution attempt. Captures the SwiftPM non-Apple `.artifactbundle` investigation that Android does not retry. The design doc never landed on `main` (PR was closed before merge).
- `eclipse-zenoh/roadmap` discussion #98 — cross-compile zenoh-pico for `aarch64-linux-android`.
- [reactivecircus/android-emulator-runner](https://github.com/ReactiveCircus/android-emulator-runner) — CI emulator action.
