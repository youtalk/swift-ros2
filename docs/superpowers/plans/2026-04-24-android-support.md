# Android support (0.5.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land native Zenoh support on Android `arm64-v8a` + `x86_64` (API 28+) in swift-ros2 0.5.0 using the same source-build model that Linux and Windows already use. DDS on Android is carved out in this release, mirroring the Windows M2 decision.

**Architecture:** `Package.swift` grows a fourth `cZenohPico` arm (`#elseif os(Android)`) that source-compiles `vendor/zenoh-pico` with the unix backend and a new `ZENOH_ANDROID` preprocessor define. The DDS carve-out gate extends from `#if !os(Windows)` to `#if !os(Windows) && !os(Android)`. No release-workflow changes. No artifact bundles. CI gains `build-android` (matrix on ABI) and `test-android-x86_64` (emulator) jobs. The `youtalk/zenoh-pico` fork gains a `ZENOH_ANDROID` CMake branch + preprocessor-gate extensions.

**Tech Stack:** Swift 6.3 on Android (official swift.org Android SDK released 2026-03-24, ships Bionic sysroot + clang — no separate NDK install required downstream), SwiftPM `.target` source build, GitHub Actions `ubuntu-latest` runner, `reactivecircus/android-emulator-runner@v2` for emulator tests.

**Spec:** `docs/superpowers/specs/2026-04-24-android-support-design.md`

**Operating constraint:** The maintainer works on macOS (Apple Silicon). Local `swift build --swift-sdk aarch64-unknown-linux-android28` is feasible once the Swift Android SDK is `swift sdk install`ed; emulator KVM acceleration requires a Linux host, so `swift test` runs only in CI. Write steps that are observable from CI logs (verbose `swift build -v`, explicit `ls -la` / `file(1)` calls) so diagnosis does not require local Android reproduction.

**Release alignment:** Android picks up the **0.5.0** slot after the Linux binary-distribution track (PR #32) was closed / rejected on 2026-04-24. Next release after Android is **0.7.0 (Windows DDS support)** — 0.6.0 is skipped to keep the main-branch README messaging that already advertises Windows DDS as 0.7.0. Android 0.5.0 does NOT edit `.github/workflows/release-xcframework.yml` and does NOT produce artifact bundles; it only adds a new `cZenohPico` arm, extends the DDS carve-out gate, bumps the `vendor/zenoh-pico` submodule, and adds two CI jobs. Starting point is current `main` at commit `fda9d70` (Windows 0.7.0 README docs landed).

**Prior attempt (reference only):** A first-pass `.artifactbundle` design was drafted earlier in this session and reset after discovering (i) SwiftPM rejects C-library `.artifactbundle` on Windows (Windows M2 Risk §8.7), and (ii) the Linux binary-distribution attempt (PR #32) was rejected on the same grounds. The earlier attempt is preserved locally as `android-v1-attempt`; it is not part of this plan.

---

## File Structure

**Created:**
- `docs/superpowers/plans/2026-04-24-android-support.md` — this plan.
- `Scripts/run-android-tests.sh` — Bash helper that discovers `.build/x86_64-unknown-linux-android28/debug/*Tests` executables, pushes them (plus the Swift Android runtime `.so`s) to the running emulator via `adb`, runs each under `LD_LIBRARY_PATH`, and returns non-zero on any failure.

**Modified:**
- `Package.swift` — fourth `cZenohPico` arm (`#elseif os(Android)` source build, unix backend), DDS carve-out gate extension (`#if !os(Windows) && !os(Android)` in four sites), `CZenohBridge` cSettings gains `ZENOH_ANDROID` define, header block comment refreshed.
- `.github/workflows/ci.yml` — add `build-android` matrix job + `test-android-x86_64` emulator job.
- `README.md` — add Android row to the Platforms table; `Shipping as` banner refreshed at release time.
- `vendor/zenoh-pico` submodule pointer — bumped to the fork tip that contains the Android patches.

**Cross-repo (lives in `youtalk/zenoh-pico`, branch `swift-ros2-main`):**
- `CMakeLists.txt` — add `elseif(CMAKE_SYSTEM_NAME MATCHES "Android")` branch + extend the unix-backend-collection `elseif` to include Android.
- Source preprocessor gates in `include/zenoh-pico/system/` + `src/system/` — extend `#if defined(ZENOH_LINUX) || defined(ZENOH_MACOS) || …` to include `|| defined(ZENOH_ANDROID)` at every unix-backend-selection site.

**Unchanged:**
- All `Sources/SwiftROS2*/` Swift code.
- All `Sources/C*/` C code in this repo.
- `.github/workflows/release-xcframework.yml`.
- `Scripts/build-xcframework.sh` and other Apple-side helpers.

---

## Milestone 1 — `youtalk/zenoh-pico` fork patches (cross-repo, PR #1 in the fork repo)

Goal: extend the fork to recognize Android, reuse the unix backend via a new `ZENOH_ANDROID` preprocessor flag. All work happens in `youtalk/zenoh-pico`; this repo receives only a submodule pointer bump (Milestone 2).

### Task 1.1: Add `ZENOH_ANDROID` branch to fork `CMakeLists.txt`

**Files (in `youtalk/zenoh-pico` repo):**
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Clone the fork and create a feature branch**

```bash
cd /tmp
git clone --branch swift-ros2-main git@github.com:youtalk/zenoh-pico.git zenoh-pico-android
cd zenoh-pico-android
git checkout -b feat/android-support
```

- [ ] **Step 2: Add the Android branch to the platform switch**

Locate the block starting `if(CMAKE_SYSTEM_NAME MATCHES "Linux")` (around line 167). Add an `elseif` for Android immediately after the Linux handling, before the BSD branch:

```cmake
if(CMAKE_SYSTEM_NAME MATCHES "Linux")
  pico_add_compile_definition(ZENOH_LINUX)
  set(JNI_ON_LOAD 1)
elseif(CMAKE_SYSTEM_NAME MATCHES "Android")
  pico_add_compile_definition(ZENOH_ANDROID)
elseif(CMAKE_SYSTEM_NAME MATCHES "BSD")
  pico_add_compile_definition(ZENOH_BSD)
```

Do NOT copy the `set(JNI_ON_LOAD 1)` line into the Android branch — Android does not need the Linux JNI shim here.

- [ ] **Step 3: Extend the unix-backend source-collection block to include Android**

Further down (search for `CMAKE_SYSTEM_NAME MATCHES "Linux" OR CMAKE_SYSTEM_NAME MATCHES "Darwin"`), extend the match:

```cmake
elseif(CMAKE_SYSTEM_NAME MATCHES "Linux" OR CMAKE_SYSTEM_NAME MATCHES "Darwin" OR CMAKE_SYSTEM_NAME MATCHES "BSD" OR CMAKE_SYSTEM_NAME MATCHES "Android" OR POSIX_COMPATIBLE)
```

- [ ] **Step 4: Local dry-run — configure step only**

Install Android NDK r26+ on the developer machine if not present. Example (macOS):

```bash
brew install --cask android-ndk
export ANDROID_NDK_ROOT=/opt/homebrew/share/android-ndk
```

Configure zenoh-pico for Android arm64-v8a:

```bash
cd /tmp/zenoh-pico-android
mkdir -p build-android-arm64 && cd build-android-arm64
cmake \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a \
  -DANDROID_NATIVE_API_LEVEL=28 \
  -DBUILD_SHARED_LIBS=Off \
  ..
```

Expected: configure completes, no `FATAL_ERROR` about Android. The configure summary prints `-- Configuring for Android` and compile definitions include `ZENOH_ANDROID`.

- [ ] **Step 5: Build for both ABIs**

```bash
cd /tmp/zenoh-pico-android/build-android-arm64
cmake --build . --parallel
file libzenohpico.a

cd /tmp/zenoh-pico-android
mkdir -p build-android-x86_64 && cd build-android-x86_64
cmake \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=x86_64 \
  -DANDROID_NATIVE_API_LEVEL=28 \
  -DBUILD_SHARED_LIBS=Off \
  ..
cmake --build . --parallel
file libzenohpico.a
```

Expected: both produce a valid static archive. If either fails with undefined-symbol errors inside `src/system/unix/*.c`, proceed to Task 1.2; otherwise skip to Task 1.3.

### Task 1.2: Extend unix-backend preprocessor gates for Android

**Files (in `youtalk/zenoh-pico` repo):**
- Modify: site-specific `.h` / `.c` files under `include/zenoh-pico/system/` and `src/system/`.

- [ ] **Step 1: Locate the gates**

```bash
cd /tmp/zenoh-pico-android
grep -rn "defined(ZENOH_LINUX)\|defined(ZENOH_MACOS)\|defined(ZENOH_BSD)" include/ src/ | grep -v Binary
```

Note every `#if` / `#elif` that selects unix-backend behavior by listing these flags. Typical sites: `include/zenoh-pico/system/platform.h`, `src/system/platform.c`.

- [ ] **Step 2: Add `ZENOH_ANDROID` to each gate that selects unix-backend behavior**

For each site, transform:

```c
#if defined(ZENOH_LINUX) || defined(ZENOH_MACOS) || defined(ZENOH_BSD)
```

into:

```c
#if defined(ZENOH_LINUX) || defined(ZENOH_MACOS) || defined(ZENOH_BSD) || defined(ZENOH_ANDROID)
```

Do **not** add `ZENOH_ANDROID` to Linux-specific gates that have no business on Android (e.g., a glibc-only `syscall(SYS_…)` call).

- [ ] **Step 3: Rebuild both ABIs**

```bash
cd /tmp/zenoh-pico-android/build-android-arm64 && cmake --build . --parallel --clean-first
cd /tmp/zenoh-pico-android/build-android-x86_64 && cmake --build . --parallel --clean-first
```

Expected: clean builds succeed. No undefined-reference errors.

### Task 1.3: Commit, push, open fork PR

- [ ] **Step 1: Commit**

```bash
cd /tmp/zenoh-pico-android
git add CMakeLists.txt include/ src/
git commit -m "feat(android): add ZENOH_ANDROID platform support

Adds an Android branch to the CMakeLists platform switch and extends
unix-backend preprocessor gates to include ZENOH_ANDROID. The unix
backend works on Android's Bionic libc; this change is a CMake +
preprocessor-only extension with no new source files.

Verified by cross-compiling for both arm64-v8a and x86_64 with
Android NDK r26 targeting API 28."
```

- [ ] **Step 2: Push and open PR**

```bash
git push -u origin feat/android-support
gh pr create \
  --repo youtalk/zenoh-pico \
  --base swift-ros2-main \
  --title "feat(android): add ZENOH_ANDROID platform support" \
  --body "Introduces an Android branch in CMakeLists that selects the unix backend and a new ZENOH_ANDROID preprocessor flag. Extends unix-backend preprocessor gates in headers/sources to include ZENOH_ANDROID. Verified locally with NDK r26 for both arm64-v8a and x86_64."
```

- [ ] **Step 3: Review and merge**

Merge the fork PR.

---

## Milestone 2 — Submodule bump + `Package.swift` four-arm split + DDS carve-out (swift-ros2 PR #1)

Goal: land the Android source-build arm in `Package.swift`, extend the DDS carve-out gate to Android, bump the submodule to the fork tip. Apple / Linux / Windows behavior unchanged.

### Task 2.1: Bump `vendor/zenoh-pico` submodule

**Files:**
- Modify: `vendor/zenoh-pico` submodule pointer.

- [ ] **Step 1: Update the submodule**

```bash
cd vendor/zenoh-pico
git fetch origin swift-ros2-main
git checkout origin/swift-ros2-main
cd ../..
git add vendor/zenoh-pico
```

- [ ] **Step 2: Confirm Linux and Windows source builds still parse**

`swift package dump-package` parses `Package.swift` without touching C sources. Run:

```bash
swift package dump-package > /dev/null && echo OK
```

Expected: `OK`. Actual C compile happens in CI.

- [ ] **Step 3: Commit**

```bash
git commit -m "build(vendor): bump zenoh-pico to tip with ZENOH_ANDROID support

Pulls in the Android platform branch and unix-backend preprocessor
gate extensions merged in youtalk/zenoh-pico#<PR#>. Linux, Windows,
and Apple builds are unaffected; Android compiles against the unix
backend with ZENOH_ANDROID defined."
```

### Task 2.2: Add Android arm to `cZenohPico`

**Files:**
- Modify: `Package.swift` (insert new `#elseif os(Android)` branch in the `cZenohPico` factory).

- [ ] **Step 1: Insert the Android arm between the Windows arm and the `#else` Apple arm**

Open `Package.swift`. The `cZenohPico` factory currently has three arms: `#if os(Linux)`, `#elseif os(Windows)`, `#else`. Insert a new arm immediately before `#else`:

```swift
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
```

- [ ] **Step 2: Verify parse**

```bash
swift package dump-package > /dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: add Android arm to cZenohPico (source build, unix backend)

Matches the Linux / Windows source-build model introduced in Windows
M2 (commit 8c55971). Android compiles src/system/unix with
ZENOH_ANDROID defined; every other backend directory is excluded."
```

### Task 2.3: Extend DDS carve-out gate to Android

**Files:**
- Modify: `Package.swift` (four `#if !os(Windows)` sites).

- [ ] **Step 1: Update the four gate sites**

Locate each `#if !os(Windows)` in `Package.swift` and change it to `#if !os(Windows) && !os(Android)`. The four sites (as of commit `8c55971`):

1. Around the `cCycloneDDS` `let` factory (line ~87).
2. The block comment above the DDS-stack `append` block (line ~196).
3. The `#if !os(Windows)` around `products.append(contentsOf: […])` (line ~200).
4. Continuation of the same block enclosing the DDS `targets.append(contentsOf: [cCycloneDDS, …])` — it's one `#if !os(Windows) … #endif` wrapping both `products.append` and `targets.append`. Only the opening `#if` and closing `#endif` exist; the `#if` line is the one to change.

Do NOT change the `.when(platforms: [.windows])` clauses inside the `CZenohBridge` target — those are per-platform compile settings, not `#if` gates, and they correctly apply Windows-only behavior without affecting Android.

- [ ] **Step 2: Update the block comment**

Replace:

```swift
// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable.
// Windows will join once M3 settles the DDS-on-Windows story; for now,
// Windows users should import SwiftROS2Zenoh directly instead of the
// SwiftROS2 umbrella.
```

With:

```swift
// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable.
// Windows and Android do not build CycloneDDS from source (SPM cannot
// orchestrate the ddsrt CMake configure-time header generation), so
// both platforms import SwiftROS2Zenoh directly instead of the
// SwiftROS2 umbrella. DDS on Windows / Android is a future track.
```

- [ ] **Step 3: Verify parse**

```bash
swift package dump-package > /dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add Package.swift
git commit -m "build: carve DDS path out of Android scope

Extends the existing #if !os(Windows) gate to also exclude Android at
every site where cCycloneDDS / CDDSBridge / SwiftROS2DDS / SwiftROS2
umbrella / examples / DDS tests are conditionally added. Downstream
Android consumers import SwiftROS2Zenoh directly, matching the
Windows shape established in commit 8c55971.

CycloneDDS source-build via SwiftPM is blocked by the same ddsrt
configure-time code generation that killed the Windows DDS story in
M2; DDS on Android is a future track."
```

### Task 2.4: Add `ZENOH_ANDROID` define to `CZenohBridge`

**Files:**
- Modify: `Package.swift` (`CZenohBridge` target `cSettings`).

- [ ] **Step 1: Insert the new define**

Locate the `CZenohBridge` target. Its `cSettings` currently contains `ZENOH_MACOS` / `ZENOH_LINUX` / `ZENOH_WINDOWS` entries. Insert `ZENOH_ANDROID` alongside, before the `Z_FEATURE_*` entries:

```swift
cSettings: [
    .define("ZENOH_MACOS", to: "1", .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
    .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
    .define("ZENOH_WINDOWS", to: "1", .when(platforms: [.windows])),
    .define("ZENOH_ANDROID", to: "1", .when(platforms: [.android])),
    .define("Z_FEATURE_LINK_TCP", to: "1"),
    .define("Z_FEATURE_LIVELINESS", to: "1"),
],
```

`linkerSettings` stays unchanged.

- [ ] **Step 2: Verify parse**

```bash
swift package dump-package > /dev/null && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: gate CZenohBridge ZENOH_ANDROID define

Matches the ZENOH_MACOS / ZENOH_LINUX / ZENOH_WINDOWS symmetry. The
zenoh-pico fork extends unix-backend gates to include ZENOH_ANDROID;
this define is the downstream half of that contract. CZenohBridge
itself does not currently gate anything on the flag, but keeping the
symmetry leaves a clean place for future Bionic-specific branches."
```

### Task 2.5: Update `Package.swift` header comment

**Files:**
- Modify: `Package.swift:5-15`.

- [ ] **Step 1: Refresh the block comment**

Replace:

```swift
// Apple platforms: pre-built xcframework binaryTargets hosted on
// GitHub Releases. Linux and Windows: compile the C sources directly
// via SPM, using the matching platform backend inside vendor/zenoh-pico.
// See Scripts/build-xcframework.sh for the macOS build helper.
//
// CycloneDDS on Linux resolves through pkg-config; on Apple it ships
// as a prebuilt xcframework. Windows DDS support is not yet in this
// milestone — the entire DDS path (cCycloneDDS, CDDSBridge, SwiftROS2DDS,
// the SwiftROS2 umbrella, and the DDS/umbrella tests) is compiled out on
// Windows by the #if !os(Windows) gate around the targets/products
// additions further down.
```

With:

```swift
// Apple platforms: pre-built xcframework binaryTargets hosted on
// GitHub Releases. Linux, Windows, and Android: compile the C sources
// directly via SPM, using the matching platform backend inside
// vendor/zenoh-pico. See Scripts/build-xcframework.sh for the macOS
// build helper.
//
// CycloneDDS on Linux resolves through pkg-config; on Apple it ships
// as a prebuilt xcframework. Windows and Android do not ship DDS —
// the entire DDS path (cCycloneDDS, CDDSBridge, SwiftROS2DDS, the
// SwiftROS2 umbrella, and the DDS/umbrella tests) is compiled out on
// both platforms by the #if !os(Windows) && !os(Android) gate around
// the targets/products additions further down.
```

- [ ] **Step 2: Commit**

```bash
git add Package.swift
git commit -m "docs(build): update Package.swift comments for Android support"
```

### Task 2.6: Open swift-ros2 PR #1

- [ ] **Step 1: Push and open PR**

```bash
git push -u origin feat/android-support-m1
gh pr create \
  --title "build(android): source build + DDS carve-out" \
  --body "$(cat <<'EOF'
## Summary

- Bumps `vendor/zenoh-pico` submodule to the tip containing the
  `ZENOH_ANDROID` platform branch and unix-backend preprocessor
  gate extensions.
- Adds a fourth `cZenohPico` arm in `Package.swift`
  (`#elseif os(Android)`) that source-compiles zenoh-pico with the
  unix backend and defines `ZENOH_ANDROID`.
- Extends the DDS carve-out gate from `#if !os(Windows)` to
  `#if !os(Windows) && !os(Android)` at every site. Android consumers
  import `SwiftROS2Zenoh` directly; no `SwiftROS2` umbrella on Android.
  DDS on Android is blocked by the same `ddsrt` CMake-configure-time
  header generation issue that killed DDS on Windows in M2; deferred
  to a future dedicated design.
- Adds a `ZENOH_ANDROID` define to `CZenohBridge`'s `cSettings` for
  symmetry with the other three platform defines.
- Refreshes the `Package.swift` header block comment.

Apple / Linux / Windows builds are unaffected.

No release-workflow changes. No artifact bundles. The CI `build-android`
job is added in a follow-up PR.

Spec: `docs/superpowers/specs/2026-04-24-android-support-design.md`.
Plan: `docs/superpowers/plans/2026-04-24-android-support.md`.

## Test plan

- [x] `swift package dump-package` parses.
- [ ] CI `build-linux`, `build-macos`, `build-windows` stay green.
- [ ] Android CI jobs land in the follow-up PR.
EOF
)"
```

- [ ] **Step 2: Merge after green**

---

## Milestone 3 — CI jobs: `build-android` + `test-android-x86_64` (swift-ros2 PR #2)

Goal: add GitHub Actions jobs that compile swift-ros2 for both Android ABIs on every PR, and run the test suite inside an x86_64 Android emulator.

### Task 3.1: Write `Scripts/run-android-tests.sh`

**Files:**
- Create: `Scripts/run-android-tests.sh`.

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Discover swift-ros2 test executables built for Android x86_64, push
# them plus the Swift Android runtime to the running emulator via
# adb, run each under LD_LIBRARY_PATH, and exit non-zero on any
# failure.
#
# Run this inside reactivecircus/android-emulator-runner@v2's
# `script:` block after `swift build --build-tests --swift-sdk
# x86_64-unknown-linux-android28`.
set -euo pipefail

BUILD_DIR=".build/x86_64-unknown-linux-android28/debug"
REMOTE_DIR="/data/local/tmp/swift-ros2-tests"

if [[ ! -d "$BUILD_DIR" ]]; then
  echo "ERROR: $BUILD_DIR does not exist. Build with --build-tests first." >&2
  exit 2
fi

adb shell "rm -rf $REMOTE_DIR && mkdir -p $REMOTE_DIR/swift-runtime"

# Push the Swift Android runtime alongside the test binaries.
SWIFT_SDK_ROOT="$(swift sdk configuration show x86_64-unknown-linux-android28 2>/dev/null | awk -F': ' '/sdkRootPath/ {print $2}')" || true
if [[ -n "${SWIFT_SDK_ROOT:-}" && -d "$SWIFT_SDK_ROOT/usr/lib/swift/android" ]]; then
  adb push "$SWIFT_SDK_ROOT/usr/lib/swift/android/." "$REMOTE_DIR/swift-runtime/" >/dev/null
fi

# Push test binaries (XCTest bundles on Linux ship as plain executables
# under .build/<triple>/debug/<PackageName>PackageTests.xctest).
shopt -s nullglob
PUSHED=()
for BIN in "$BUILD_DIR"/*PackageTests.xctest "$BUILD_DIR"/*Tests.xctest; do
  [[ -f "$BIN" && -x "$BIN" ]] || continue
  BASENAME="$(basename "$BIN")"
  adb push "$BIN" "$REMOTE_DIR/$BASENAME" >/dev/null
  PUSHED+=("$BASENAME")
done

if (( ${#PUSHED[@]} == 0 )); then
  echo "ERROR: no *.xctest test binaries found under $BUILD_DIR" >&2
  exit 2
fi

# Run each test binary on the emulator; collect failures.
FAILED=()
for BIN in "${PUSHED[@]}"; do
  echo "::group::Running $BIN"
  if adb shell "chmod +x $REMOTE_DIR/$BIN && cd $REMOTE_DIR && LD_LIBRARY_PATH=$REMOTE_DIR/swift-runtime ./$BIN"; then
    :
  else
    FAILED+=("$BIN")
  fi
  echo "::endgroup::"
done

if (( ${#FAILED[@]} > 0 )); then
  echo "FAILED test binaries: ${FAILED[*]}" >&2
  exit 1
fi

echo "All test binaries passed."
```

- [ ] **Step 2: Make executable and commit**

```bash
chmod +x Scripts/run-android-tests.sh
git add Scripts/run-android-tests.sh
git commit -m "ci: add Scripts/run-android-tests.sh for emulator test run

Discovers *.xctest test binaries under .build/<android-triple>/debug/,
pushes them plus the Swift Android runtime (.so files) to the
emulator via adb, runs each under LD_LIBRARY_PATH, and returns
non-zero on any failure."
```

### Task 3.2: Add `build-android` matrix job to CI workflow

**Files:**
- Modify: `.github/workflows/ci.yml`.

- [ ] **Step 1: Append the new job**

Add this block after the existing `build-windows` job in `ci.yml`:

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
        with:
          submodules: recursive

      - name: Install Swift 6.3
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.3.1'

      - name: Install Swift Android SDK
        env:
          # Pin to the 6.3 Android SDK matching the toolchain above.
          # Substitute <pinned-url> and <pinned-sha> with the values
          # from swift.org/install/android/ at implementation time.
          SDK_URL: <pinned-url>
          SDK_CHECKSUM: <pinned-sha>
        run: |
          swift sdk install "$SDK_URL" --checksum "$SDK_CHECKSUM"
          swift sdk list

      - name: swift build
        run: swift build --swift-sdk ${{ matrix.triple }} -v
```

Replace `<pinned-url>` and `<pinned-sha>` with the real values from [swift.org/install/android/](https://www.swift.org/install/android/) at implementation time. Record the choice in a `# Swift 6.3.x Android SDK pinned 2026-MM-DD` comment above the step.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add build-android matrix job (arm64-v8a + x86_64)

Compiles swift-ros2 for both Android ABIs against the source-built
zenoh-pico (unix backend, ZENOH_ANDROID defined). Uses the official
Swift 6.3 Android SDK from swift.org, pinned to a specific version
at the SDK_URL / SDK_CHECKSUM env vars."
```

### Task 3.3: Add `test-android-x86_64` emulator job

**Files:**
- Modify: `.github/workflows/ci.yml`.

- [ ] **Step 1: Append the emulator job**

After `build-android`:

```yaml
  test-android-x86_64:
    name: Test Android (x86_64 emulator)
    runs-on: ubuntu-latest
    needs: build-android
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install Swift 6.3
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.3.1'

      - name: Install Swift Android SDK
        env:
          SDK_URL: <pinned-url>
          SDK_CHECKSUM: <pinned-sha>
        run: swift sdk install "$SDK_URL" --checksum "$SDK_CHECKSUM"

      - name: Build tests for Android x86_64
        run: swift build --build-tests --swift-sdk x86_64-unknown-linux-android28 -v

      - name: Enable KVM group perms
        run: |
          echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"' \
            | sudo tee /etc/udev/rules.d/99-kvm4all.rules
          sudo udevadm control --reload-rules
          sudo udevadm trigger --name-match=kvm

      - name: Run tests on Android x86_64 emulator
        uses: reactivecircus/android-emulator-runner@v2
        with:
          api-level: 28
          arch: x86_64
          target: default
          force-avd-creation: false
          emulator-options: -no-window -gpu swiftshader_indirect -noaudio -no-boot-anim -camera-back none
          disable-animations: true
          script: bash Scripts/run-android-tests.sh
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add test-android-x86_64 emulator job

Runs swift build --build-tests against the Android x86_64 target,
boots an API-28 x86_64 emulator under KVM on ubuntu-latest, and
executes Scripts/run-android-tests.sh inside the emulator-runner
action's script block.

arm64-v8a is not tested at runtime — arm64 emulator on x86_64 host
has no KVM acceleration and is impractically slow. arm64 Android is
build-verified only; runtime correctness is inferred from the shared
pure-Swift and identical C layer."
```

### Task 3.4: Open swift-ros2 PR #2

- [ ] **Step 1: Push and open PR**

```bash
git push -u origin feat/android-support-ci
gh pr create \
  --title "ci(android): build + emulator test jobs" \
  --body "$(cat <<'EOF'
## Summary

- Adds `build-android` matrix job (`arm64-v8a`, `x86_64`) that
  compiles `swift-ros2` against the official Swift 6.3 Android SDK.
- Adds `test-android-x86_64` job that boots an API-28 x86_64 emulator
  via `reactivecircus/android-emulator-runner@v2` and runs
  `Scripts/run-android-tests.sh` inside it.
- Adds `Scripts/run-android-tests.sh` — discovers `.xctest` binaries,
  pushes them + the Swift Android runtime to the emulator, runs each,
  exits non-zero on any failure.

Depends on swift-ros2 PR #1 (Package.swift four-arm split) being
merged first.

## Test plan

- [ ] `build-android (arm64-v8a)` green.
- [ ] `build-android (x86_64)` green.
- [ ] `test-android-x86_64` green over 5 consecutive runs
      (emulator stability check).
EOF
)"
```

- [ ] **Step 2: Stability check**

After merge, re-run the `test-android-x86_64` job 5 times (e.g., re-trigger via `gh workflow run ci.yml`). Record flake rate. If > 5 %, bump `retry: 2` on the emulator step or escalate to self-hosted runner.

---

## Milestone 4 — README + release (swift-ros2 PR #3)

Goal: document Android in `README.md`, cut the 0.5.0 tag, let the existing release workflow publish Apple xcframeworks (no Android bundles — Android is source-build).

### Task 4.1: Add Android row to the Platforms table

**Files:**
- Modify: `README.md`.

- [ ] **Step 1: Insert the Android row in the Platforms table**

Find the `## Platforms` table. After the Linux row (currently the last row at `8c55971`), add:

```markdown
| Android       | API 28 (Android 9) — arm64-v8a, x86_64 | zenoh-pico source build (Zenoh only; no DDS) |
```

- [ ] **Step 2: Update the Swift version note below the table**

Find the line beginning `Swift 5.9+ everywhere.` and extend it to mention Android:

```markdown
Swift 5.9+ on Apple / Linux / Windows; Android requires Swift 6.3+ and the official swift.org Android SDK. CI runs `macos-15` (Apple Silicon, Xcode 16.2) plus a Swift 6.0.2 Linux matrix: Humble on Ubuntu 22.04, Jazzy on Ubuntu 24.04, and Rolling on Ubuntu 24.04 — each exercised on both x86_64 and aarch64. Windows runs on `windows-latest` with Swift 6.3.1. Android runs on `ubuntu-latest` with Swift 6.3.1 (build for both ABIs; `swift test` on an x86_64 emulator).
```

- [ ] **Step 3: Add an Installation subsection for Android**

After the existing `### Linux` subsection under `## Installation`, add:

```markdown
### Android (cross-compile from macOS or Linux)

Install the Swift 6.3 Android SDK once (pick the version matching your
toolchain from [swift.org/install/android](https://www.swift.org/install/android/)):

```bash
swift sdk install <android-sdk-url> --checksum <sha>
```

Then cross-compile:

```bash
swift build --swift-sdk aarch64-unknown-linux-android28    # or x86_64-unknown-linux-android28
```

Only `SwiftROS2Zenoh` is available on Android in this release — DDS
support is deferred (see `docs/superpowers/specs/2026-04-24-android-support-design.md`
for the rationale). Import accordingly:

```swift
import SwiftROS2Zenoh   // instead of `import SwiftROS2`
```

`swift test` on Android requires an emulator and KVM acceleration (Linux host only). We run Android unit tests exclusively in CI.
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs(readme): add Android row to platforms + installation section

API 28 (Android 9), arm64-v8a + x86_64. Source build via Swift 6.3
Android SDK; only SwiftROS2Zenoh is available (DDS carved out).
Cross-compile instructions + link to swift.org/install/android for
the SDK pin."
```

### Task 4.2: Bump the README version banner at release time

**Files:**
- Modify: `README.md` (the `Shipping as **0.x.y**` line at the top).

- [ ] **Step 1: Update the version banner**

Find the line near the top of `README.md`:

```markdown
Shipping as **0.4.0** — pre-built xcframeworks on every Apple platform, source build on Linux.
```

Update to:

```markdown
Shipping as **0.5.0** — pre-built xcframeworks on every Apple platform, source build on Linux / Windows / Android. Zenoh-only on Windows and Android.
```

- [ ] **Step 2: Cut and push the tag**

Confirm no conflicting tag exists first:

```bash
gh release list
# Expect: 0.4.0 is the latest; no 0.5.0 tag yet.
```

Cut:

```bash
git tag 0.5.0
git push origin 0.5.0
```

- [ ] **Step 3: Watch the release workflow**

```bash
gh run watch
```

Expected: the existing release workflow publishes `CZenohPico.xcframework.zip` + `CCycloneDDS.xcframework.zip` + their `.checksum` files. No Linux, Windows, or Android bundles are expected — Linux binary distribution was rejected in PR #32, and Windows / Android both use source build.

- [ ] **Step 4: Commit the banner bump**

```bash
git add README.md
git commit -m "chore: ship 0.5.0

First swift-ros2 release with Android support (arm64-v8a + x86_64,
API 28+, source build via Swift 6.3 Android SDK, Zenoh only)."
```

### Task 4.3: Open swift-ros2 PR #3

- [ ] **Step 1: Push and open PR**

```bash
git push -u origin chore/release-0.5.0
gh pr create \
  --title "chore: ship 0.5.0 with Android support" \
  --body "$(cat <<'EOF'
## Summary

Cuts swift-ros2 0.5.0 — first release with Android support:

- Android `arm64-v8a` + `x86_64` (API 28+).
- Source build via Swift 6.3 Android SDK (no artifact bundles).
- `SwiftROS2Zenoh` only; DDS on Android deferred.

Updates `README.md` Platforms table, adds an Installation subsection
for Android, bumps the release banner to 0.5.0.

## Test plan

- [x] All Android CI jobs (`build-android`, `test-android-x86_64`)
      green on `main`.
- [x] Existing Apple / Linux / Windows CI green.
- [x] `0.5.0` release page shows the expected xcframework assets
      (no Android-specific assets expected).
EOF
)"
```

- [ ] **Step 2: Merge**

Release complete.

---

## Self-review — spec-to-plan coverage

| Spec section | Plan task(s) |
|---|---|
| §1 Background (Swift 6.3 Android SDK + source-build precedent) | Plan header (architecture + tech stack) |
| §2 Feasibility findings | Milestone 1 Task 1.1–1.2 (fork CMake + gates), Milestone 2 Task 2.2 (source-build arm), Milestone 3 Task 3.2 (Swift Android SDK install) |
| §3 Distribution strategy (source build, no bundles) | No release-workflow changes in this plan; Milestone 2 Task 2.2 is source build |
| §4.1 `cZenohPico` fourth arm | Task 2.2 |
| §4.2 DDS carve-out extension | Task 2.3 |
| §4.3 `CZenohBridge` `ZENOH_ANDROID` define | Task 2.4 |
| §4.4 Header block comment refresh | Task 2.5 |
| §5 Vendor fork CMake + preprocessor gates | Tasks 1.1, 1.2 |
| §6.1 `build-android` matrix CI job | Task 3.2 |
| §6.2 `test-android-x86_64` emulator job | Task 3.3 + `Scripts/run-android-tests.sh` in Task 3.1 |
| §7 Coverage summary | Implicitly satisfied by the milestone arc |
| §8 Risks (SDK volatility, Bionic divergence, emulator flakiness, SwiftPM platforms, DDS expectations) | Task 3.2 SDK pin note, Task 1.2 Bionic-divergence discovery via Milestone 3 emulator, Task 3.4 stability check, Task 2.3 comment + README note in Task 4.1 |
| §9 Release alignment | Task 4.2 tag cut, plan header "Release alignment" |
| §10 Implementation roadmap | All four milestones collectively |

**Placeholder scan:** `<pinned-url>`, `<pinned-sha>`, `<PR#>`, `<sha>`, `<android-sdk-url>` are the only placeholders. Each is a real value that only exists at implementation time (Swift 6.3 Android SDK URL pinned in CI, SHA of the downloaded tarball, cross-repo PR number from Task 1.3). No `TODO` / `implement later` / "similar to Task N".

**Type consistency:** `libzenohpico.a` only referenced in local build verification steps (not in Package.swift — source build produces SPM-managed `.a`s). `aarch64-unknown-linux-android28` / `x86_64-unknown-linux-android28` triples identical across all sites. `ZENOH_ANDROID` define name identical in Package.swift, fork CMake, fork source gates, CZenohBridge cSettings. `ANDROID_NDK_ROOT` env var only referenced in Milestone 1 (fork repo); swift-ros2 CI does not need NDK because the Swift Android SDK bundles the sysroot.

---

## Plan complete

Plan saved to `docs/superpowers/plans/2026-04-24-android-support.md`.

Two execution options:

1. **Subagent-Driven** — dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints.
