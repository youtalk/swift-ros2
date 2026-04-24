# Windows support (0.5.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land native Zenoh + DDS support on Windows x86_64 in swift-ros2 0.5.0, distributed via pre-built `.artifactbundle` dependencies published to the existing GitHub Release, mirroring the Apple `.xcframework` model.

**Architecture:** `Package.swift` grows a three-arm platform split (`os(Linux)` / `os(Windows)` / else-Apple). Windows consumes `CZenohPico-windows-x86_64.artifactbundle.zip` and `CCycloneDDS-windows-x86_64.artifactbundle.zip` from each tag's GitHub Release. The release workflow gains two `windows-latest` jobs that CMake-build the native deps, assemble the artifact bundles, and upload them. A new `build-windows` CI job runs `swift build` + `swift test --parallel`. No Swift or C source changes beyond `Package.swift` platform gating.

**Tech Stack:** Swift 6.0.2 on Windows (MSVC ABI, x86_64-unknown-windows-msvc), SwiftPM `.binaryTarget` + `.artifactbundle`, CMake + MSBuild, GitHub Actions `windows-latest` runner, PowerShell for Windows build scripts.

**Spec:** `docs/superpowers/specs/2026-04-24-windows-support-design.md`

**Operating constraint:** The maintainer has no local Windows machine. Every task in Milestone 2 and later is verified by pushing to a branch and reading the GitHub Actions log. Write steps that are observable from logs (verbose CMake, `swift build -v`, explicit `dir` / `Get-ChildItem` calls after build steps) so diagnosis does not require local reproduction.

---

## File Structure

**Created:**
- `docs/superpowers/plans/2026-04-24-windows-support.md` — this plan (created by writing-plans skill, already present).
- `Scripts/Build-WindowsZenohPico.ps1` — PowerShell script that CMake-builds zenoh-pico on `windows-latest` and assembles the artifact bundle.
- `Scripts/Build-WindowsCycloneDDS.ps1` — same for CycloneDDS.
- `Scripts/windows-artifactbundle-info.json.template` — shared `info.json` template used by both scripts (with `@@NAME@@` / `@@VERSION@@` placeholders).
- `Tests/WindowsBundleSmoke/Package.swift` + `Tests/WindowsBundleSmoke/Sources/Smoke/main.swift` — minimal consumer package used in CI to validate that an artifact-bundle-based `.binaryTarget` actually resolves and links. Lives alongside the main package but is its own SwiftPM root.

**Modified:**
- `Package.swift` — three-arm `cZenohPico` / `cCycloneDDS` target factories + Windows `cSettings` / `linkerSettings` on `CZenohBridge`.
- `.github/workflows/ci.yml` — add `build-windows` job.
- `.github/workflows/release-xcframework.yml` — add `build-zenoh-pico-windows` and `build-cyclonedds-windows` jobs; extend the `publish` job's `gh release upload` list.
- `CLAUDE.md` — add "Windows" subsection under "Build & test commands" noting that local Windows builds are not supported; developers push and read CI logs.
- `README.md` — add Windows to the supported-platforms list (top of file).

**Unchanged (verified by the feasibility audit in the spec):**
- All `Sources/SwiftROS2*/` Swift code.
- All `Sources/C*/` C code. (If MSVC produces warnings-as-errors in release CI, address them inline during the M2/M3 tasks rather than preemptively.)

---

## Milestone 1 — Package.swift scaffolding (PR #1)

Goal: land the three-arm platform split with placeholder Windows URLs that never fire on Apple/Linux. Existing CI must stay green. No bundles exist yet, so the Windows `binaryTarget` URL is a dummy that never gets fetched because there is no Windows CI job yet.

### Task 1.1: Add Windows arm to `cZenohPico` in `Package.swift`

**Files:**
- Modify: `Package.swift:11-49`

- [ ] **Step 1: Replace the `cZenohPico` factory with the three-arm version**

Open `Package.swift` and replace the existing `cZenohPico` factory (lines 11–49) with:

```swift
let cZenohPico: Target = {
    #if os(Linux)
        return .target(
            name: "CZenohPico",
            path: "vendor/zenoh-pico",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE", "tests", "examples", "docs", "ci",
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
                .define("ZENOH_LINUX", to: "1"),
            ]
        )
    #elseif os(Windows)
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(xcframeworkBaseURL)/CZenohPico-windows-x86_64.artifactbundle.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    #else
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(xcframeworkBaseURL)/CZenohPico.xcframework.zip",
            checksum: "de7d7a02605234d364a464fb0169bc18efb46440976b8e8a26021eb416386c95"
        )
    #endif
}()
```

The all-zero checksum is an intentional placeholder. SwiftPM only resolves the Windows arm when compiling on Windows; on Apple / Linux it is never read. M2 replaces this with the real checksum after the first RC bundle is built.

- [ ] **Step 2: Verify Apple build still passes locally**

Run: `swift build`
Expected: build succeeds with no warnings about the Windows arm. SwiftPM should log nothing about `CZenohPico-windows-x86_64.artifactbundle.zip` because the Apple arm was selected.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: add Windows arm to CZenohPico target factory

Introduces the three-arm platform split for the zenoh-pico native
dependency. The Windows branch points at a placeholder URL with an
all-zero checksum; it is only evaluated when compiling on Windows
(no CI job wires this up yet), so Apple and Linux builds are
unaffected."
```

### Task 1.2: Add Windows arm to `cCycloneDDS` in `Package.swift`

**Files:**
- Modify: `Package.swift:51-65`

- [ ] **Step 1: Replace the `cCycloneDDS` factory with the three-arm version**

Replace the existing `cCycloneDDS` factory with:

```swift
let cCycloneDDS: Target = {
    #if os(Linux)
        return .systemLibrary(
            name: "CCycloneDDS",
            path: "Sources/CCycloneDDS",
            pkgConfig: "CycloneDDS"
        )
    #elseif os(Windows)
        return .binaryTarget(
            name: "CCycloneDDS",
            url: "\(xcframeworkBaseURL)/CCycloneDDS-windows-x86_64.artifactbundle.zip",
            checksum: "0000000000000000000000000000000000000000000000000000000000000000"
        )
    #else
        return .binaryTarget(
            name: "CCycloneDDS",
            url: "\(xcframeworkBaseURL)/CCycloneDDS.xcframework.zip",
            checksum: "bc72071590791fcb989a69af616c1da771f9c6d79b50de4381d8e95ce33fc8ad"
        )
    #endif
}()
```

- [ ] **Step 2: Verify Apple build still passes**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: add Windows arm to CCycloneDDS target factory

Parallel to the zenoh-pico change: introduce the Windows binaryTarget
arm with a placeholder URL and zero checksum. Apple and Linux remain
on their existing branches."
```

### Task 1.3: Add Windows platform conditions to `CZenohBridge`

**Files:**
- Modify: `Package.swift:119-131` (the `CZenohBridge` target)

- [ ] **Step 1: Add `ZENOH_WINDOWS` define and Winsock linker settings**

In the `CZenohBridge` target definition, extend `cSettings` with the `ZENOH_WINDOWS` define and add a new `linkerSettings` array:

```swift
.target(
    name: "CZenohBridge",
    dependencies: ["CZenohPico"],
    path: "Sources/CZenohBridge",
    sources: ["zenoh_bridge.c"],
    publicHeadersPath: "include",
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
),
```

- [ ] **Step 2: Verify Apple build stays green**

Run: `swift build`
Expected: build succeeds. The `.when(platforms: [.windows])` conditions are no-ops on Apple.

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: gate CZenohBridge Windows defines and Winsock libraries

Adds ZENOH_WINDOWS to cSettings and links Ws2_32 / Iphlpapi on Windows
only. No behavior change on Apple or Linux — the .when(platforms:)
guards make these settings inert off-Windows."
```

### Task 1.4: Open PR, verify CI green, merge

- [ ] **Step 1: Push branch and open PR**

```bash
git push -u origin HEAD
gh pr create --title "build(m1): Package.swift Windows scaffolding" --body "$(cat <<'EOF'
## Summary
- Adds the third platform arm (Windows x86_64) to \`cZenohPico\` and \`cCycloneDDS\` target factories in \`Package.swift\`.
- Wires Winsock (\`Ws2_32\`, \`Iphlpapi\`) and \`ZENOH_WINDOWS\` onto \`CZenohBridge\` via \`.when(platforms: [.windows])\` guards.
- Windows \`binaryTarget\` URLs are placeholders with all-zero checksums. No Windows CI job yet, so these are never evaluated.

First PR of the Windows-support milestone sequence — see \`docs/superpowers/specs/2026-04-24-windows-support-design.md\` §7 M1.

## Test plan
- [x] \`swift build\` green on macOS locally.
- [ ] Existing \`build-macos\` / \`build-linux\` CI jobs stay green.
EOF
)"
```

- [ ] **Step 2: Wait for CI, merge when green**

Watch: `gh pr checks --watch`
Expected: `build-macos` and all `build-linux` matrix jobs green. No new Windows job exists yet.

- [ ] **Step 3: Merge with squash**

```bash
gh pr merge --squash --delete-branch
```

---

## Milestone 2 — zenoh-pico Windows artifactbundle (PR #2)

Goal: produce a valid `CZenohPico-windows-x86_64.artifactbundle.zip`, verify SwiftPM `.binaryTarget` can consume it, wire the first `build-windows` CI job, ship zenoh-pico on Windows. **This is also the validation gate for Risk §8.7** (does `.binaryTarget` for C libraries actually work on Windows?). If it does not, this milestone pivots to the source-build fallback described in that risk before M3 starts.

### Task 2.1: Add the shared `info.json` template

**Files:**
- Create: `Scripts/windows-artifactbundle-info.json.template`

- [ ] **Step 1: Create the template**

```json
{
    "schemaVersion": "1.0",
    "artifacts": {
        "@@NAME@@": {
            "type": "library",
            "version": "@@VERSION@@",
            "variants": [
                {
                    "path": "@@NAME@@-@@VERSION@@-windows/x86_64-unknown-windows-msvc",
                    "supportedTriples": ["x86_64-unknown-windows-msvc"]
                }
            ]
        }
    }
}
```

The two scripts (Tasks 2.2 and 3.1) substitute `@@NAME@@` with `CZenohPico` / `CCycloneDDS` and `@@VERSION@@` with the release tag (e.g. `0.5.0-rc.1`).

- [ ] **Step 2: Commit**

```bash
git add Scripts/windows-artifactbundle-info.json.template
git commit -m "build: add shared info.json template for Windows artifact bundles"
```

### Task 2.2: Add `Scripts/Build-WindowsZenohPico.ps1`

**Files:**
- Create: `Scripts/Build-WindowsZenohPico.ps1`

- [ ] **Step 1: Write the script**

```powershell
#Requires -Version 5.1
# Build zenoh-pico as a Windows x86_64 shared library and assemble
# the SwiftPM .artifactbundle expected by Package.swift's Windows arm.
#
# Usage (invoked by .github/workflows/release-xcframework.yml):
#   pwsh Scripts/Build-WindowsZenohPico.ps1 -Version 0.5.0-rc.1 -OutDir artifacts
#
# Produces:
#   $OutDir/CZenohPico-windows-x86_64.artifactbundle.zip
#   $OutDir/CZenohPico-windows-x86_64.artifactbundle.zip.checksum

param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$vendorDir = Join-Path $repoRoot 'vendor/zenoh-pico'
if (-not (Test-Path $vendorDir)) {
    throw "vendor/zenoh-pico missing. Run: git submodule update --init --recursive"
}

$buildDir = Join-Path $repoRoot 'build-windows/zenoh-pico'
$installDir = Join-Path $repoRoot 'build-windows/zenoh-pico-install'
Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $installDir -ErrorAction SilentlyContinue

Write-Host "::group::CMake configure"
cmake -S $vendorDir -B $buildDir `
    -G 'Visual Studio 17 2022' -A x64 `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=ON `
    -DZ_FEATURE_LINK_TCP=1 `
    -DZ_FEATURE_LIVELINESS=1 `
    -DBUILD_EXAMPLES=OFF `
    -DBUILD_TOOLS=OFF `
    -DBUILD_TESTING=OFF `
    -DCMAKE_INSTALL_PREFIX=$installDir
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
Write-Host "::endgroup::"

Write-Host "::group::CMake build"
cmake --build $buildDir --config Release --target install -- /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }
Write-Host "::endgroup::"

Write-Host "::group::Installed tree"
Get-ChildItem -Recurse $installDir | Select-Object -ExpandProperty FullName
Write-Host "::endgroup::"

# Assemble the artifact bundle.
$bundleName = 'CZenohPico-windows-x86_64.artifactbundle'
$bundleRoot = Join-Path (Resolve-Path $repoRoot) "build-windows/$bundleName"
$variantDir = Join-Path $bundleRoot "CZenohPico-$Version-windows/x86_64-unknown-windows-msvc"
Remove-Item -Recurse -Force $bundleRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $variantDir 'lib') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $variantDir 'include') | Out-Null

# Copy .lib, .dll, and public headers.
Copy-Item (Join-Path $installDir 'lib/zenohpico.lib') (Join-Path $variantDir 'lib/CZenohPico.lib')
Copy-Item (Join-Path $installDir 'bin/zenohpico.dll') (Join-Path $variantDir 'lib/CZenohPico.dll')
Copy-Item -Recurse (Join-Path $installDir 'include/zenoh-pico') (Join-Path $variantDir 'include/')
Copy-Item (Join-Path $installDir 'include/zenoh-pico.h') (Join-Path $variantDir 'include/')

# Render info.json from the template.
$tpl = Get-Content -Raw (Join-Path $repoRoot 'Scripts/windows-artifactbundle-info.json.template')
$info = $tpl.Replace('@@NAME@@', 'CZenohPico').Replace('@@VERSION@@', $Version)
Set-Content -Path (Join-Path $bundleRoot 'info.json') -Value $info -Encoding UTF8

Write-Host "::group::Bundle tree"
Get-ChildItem -Recurse $bundleRoot | Select-Object -ExpandProperty FullName
Write-Host "::endgroup::"

# Zip with the bundle directory as the top-level entry (SwiftPM requirement).
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipPath = Join-Path $OutDir "$bundleName.zip"
Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
Compress-Archive -Path $bundleRoot -DestinationPath $zipPath -CompressionLevel Optimal

# Emit sha256 checksum alongside the zip (matches xcframework workflow).
$hash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLower()
Set-Content -Path "$zipPath.checksum" -Value $hash -Encoding ASCII

Write-Host "Built $zipPath"
Write-Host "sha256: $hash"
```

Note: the exact upstream install-tree filenames (`zenohpico.lib`, `zenohpico.dll`, `include/zenoh-pico.h`) are read off the Release CMake install. If the install step produces different names (it may prefix with `lib` on some configurations), adjust the `Copy-Item` block after observing the first CI run's `::group::Installed tree` output. This is expected iteration — not a plan defect.

- [ ] **Step 2: Commit**

```bash
git add Scripts/Build-WindowsZenohPico.ps1
git commit -m "build: add PowerShell script to produce Windows zenoh-pico artifact bundle

Invoked by the release workflow on windows-latest. Produces
CZenohPico-windows-x86_64.artifactbundle.zip plus a matching .checksum
file in the requested output directory. Logs the installed tree and the
final bundle tree as GitHub Actions groups so the remote CI run is
diagnosable without local reproduction (required — maintainer has no
local Windows environment)."
```

### Task 2.3: Add `build-zenoh-pico-windows` release-workflow job

**Files:**
- Modify: `.github/workflows/release-xcframework.yml`

- [ ] **Step 1: Insert the new job after the existing `build` matrix**

Add this job to `.github/workflows/release-xcframework.yml` between the `build` job and the `publish` job:

```yaml
  build-zenoh-pico-windows:
    name: Build CZenohPico-windows-x86_64.artifactbundle
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - name: CMake version
        run: cmake --version
      - name: Build
        shell: pwsh
        run: |
          $version = "${{ github.event.inputs.tag || github.ref_name }}"
          pwsh Scripts/Build-WindowsZenohPico.ps1 -Version $version -OutDir artifacts
      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: zenoh-pico-windows-artifactbundle
          path: |
            artifacts/*.zip
            artifacts/*.checksum
          if-no-files-found: error
          retention-days: 7
```

Also update the `publish` job's `gh release upload` command to include the new files:

```yaml
          gh release upload "$TAG" --repo "${{ github.repository }}" --clobber \
            upload/CZenohPico.xcframework.zip \
            upload/CZenohPico.xcframework.zip.checksum \
            upload/CCycloneDDS.xcframework.zip \
            upload/CCycloneDDS.xcframework.zip.checksum \
            upload/CZenohPico-windows-x86_64.artifactbundle.zip \
            upload/CZenohPico-windows-x86_64.artifactbundle.zip.checksum
```

And update the `publish` job's `needs:` to include the new job:

```yaml
  publish:
    name: Attach to release
    needs: [build, build-zenoh-pico-windows]
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release-xcframework.yml
git commit -m "ci(release): build CZenohPico Windows artifact bundle on release tags

Adds a windows-latest job that runs Build-WindowsZenohPico.ps1 and
uploads the resulting .artifactbundle.zip + .checksum. The publish job
now attaches the new files to the GitHub Release."
```

### Task 2.4: Trigger a test RC release (`0.5.0-rc.1`) to exercise the pipeline

- [ ] **Step 1: Push the feature branch**

```bash
git push -u origin HEAD
```

- [ ] **Step 2: Create and push the RC tag from this branch**

```bash
git tag 0.5.0-rc.1
git push origin 0.5.0-rc.1
```

This fires the release workflow. Do not merge the PR yet — the goal is to get a published bundle we can consume in Task 2.5.

- [ ] **Step 3: Watch the release workflow**

Run: `gh run watch --exit-status $(gh run list --workflow=release-xcframework.yml --branch=0.5.0-rc.1 --limit=1 --json databaseId --jq '.[0].databaseId')`
Expected: the macOS `build` matrix jobs and the new `build-zenoh-pico-windows` job all succeed. The `publish` job uploads files to release `0.5.0-rc.1`.

If `build-zenoh-pico-windows` fails, read the `::group::Installed tree` output in the log to identify the actual CMake install filenames and patch `Scripts/Build-WindowsZenohPico.ps1` accordingly. Push a fix commit, delete and re-push the tag (`git tag -d 0.5.0-rc.1 && git push --delete origin 0.5.0-rc.1 && git tag 0.5.0-rc.1 && git push origin 0.5.0-rc.1`), re-watch.

- [ ] **Step 4: Record the final checksum**

```bash
gh release view 0.5.0-rc.1 --json assets --jq '.assets[] | select(.name | endswith(".checksum")) | {name, url}'
curl -sSL "$(gh release view 0.5.0-rc.1 --json assets --jq '.assets[] | select(.name=="CZenohPico-windows-x86_64.artifactbundle.zip.checksum") | .url')"
```

Capture the sha256 value for Task 2.6.

### Task 2.5: Validate the artifact bundle with a smoke-test consumer

**Files:**
- Create: `Tests/WindowsBundleSmoke/Package.swift`
- Create: `Tests/WindowsBundleSmoke/Sources/Smoke/main.swift`

This consumer exists only to prove SwiftPM's `.binaryTarget` can resolve our artifact bundle on Windows. **This is Risk §8.7's validation gate.**

- [ ] **Step 1: Create the smoke package**

`Tests/WindowsBundleSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

// Standalone SwiftPM root used only by the Windows CI smoke job.
// Confirms that the released .artifactbundle is consumable via
// .binaryTarget before we commit the production URL to the main
// Package.swift.

let version = "0.5.0-rc.1"
let baseURL = "https://github.com/youtalk/swift-ros2/releases/download/\(version)"

let package = Package(
    name: "WindowsBundleSmoke",
    targets: [
        .binaryTarget(
            name: "CZenohPico",
            url: "\(baseURL)/CZenohPico-windows-x86_64.artifactbundle.zip",
            // Fill in from release artifact (Task 2.4 step 4).
            checksum: "REPLACE_WITH_ACTUAL_CHECKSUM"
        ),
        .executableTarget(
            name: "Smoke",
            dependencies: ["CZenohPico"],
            path: "Sources/Smoke"
        ),
    ]
)
```

`Tests/WindowsBundleSmoke/Sources/Smoke/main.swift`:

```swift
import CZenohPico

// Reference a zenoh-pico symbol so the import is not dead-code eliminated.
// z_sleep_ms is declared in zenoh-pico.h and available in every backend.
z_sleep_ms(0)
print("smoke ok")
```

- [ ] **Step 2: Fill in the real checksum from Task 2.4 step 4**

Edit `Tests/WindowsBundleSmoke/Package.swift` — replace `REPLACE_WITH_ACTUAL_CHECKSUM` with the sha256 captured above.

- [ ] **Step 3: Add a smoke job to the release workflow**

In `.github/workflows/release-xcframework.yml`, add this after `build-zenoh-pico-windows`:

```yaml
  smoke-zenoh-pico-windows:
    name: Smoke-test CZenohPico bundle on Windows
    needs: [build-zenoh-pico-windows]
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: compnerd/gha-setup-swift@main
        with:
          branch: swift-6.0.2-release
          tag: 6.0.2-RELEASE
      - name: Download bundle
        uses: actions/download-artifact@v4
        with:
          name: zenoh-pico-windows-artifactbundle
          path: Tests/WindowsBundleSmoke/artifacts
      - name: Build smoke consumer
        shell: pwsh
        working-directory: Tests/WindowsBundleSmoke
        run: swift build -v
      - name: Run smoke consumer
        shell: pwsh
        working-directory: Tests/WindowsBundleSmoke
        run: swift run Smoke
```

Add `smoke-zenoh-pico-windows` to the `publish` job's `needs:` so a broken bundle cannot be released:

```yaml
  publish:
    name: Attach to release
    needs: [build, build-zenoh-pico-windows, smoke-zenoh-pico-windows]
```

The smoke job fetches the bundle via `download-artifact` (same workflow run — no dependency on the release being published). When it runs on a tag push, the download happens before publish, so the validation is a true precondition.

- [ ] **Step 4: Commit**

```bash
git add Tests/WindowsBundleSmoke/ .github/workflows/release-xcframework.yml
git commit -m "ci(release): smoke-test CZenohPico Windows artifact bundle

Minimal standalone SwiftPM project that consumes the bundle via
.binaryTarget and links against a zenoh-pico symbol, proving end-to-end
that SwiftPM can resolve a .artifactbundle on windows-latest. Added as
a precondition to the publish job so a broken bundle cannot reach the
GitHub Release."
```

- [ ] **Step 5: Roll a new RC to exercise the smoke job**

```bash
git push origin HEAD
git tag -d 0.5.0-rc.1 2>/dev/null || true
git push --delete origin 0.5.0-rc.1 2>/dev/null || true
git tag 0.5.0-rc.1
git push origin 0.5.0-rc.1
```

Watch the run. Expected: `build-zenoh-pico-windows` → `smoke-zenoh-pico-windows` → `publish` all green.

**If the smoke job fails with a SwiftPM binaryTarget error** (schema mismatch, triple mismatch, unable to resolve), the validation gate has fired. Stop here. Switch to the source-build fallback from spec §8 risk 7: convert the Windows arm of `cZenohPico` in `Package.swift` from `.binaryTarget` to a `.target` over `vendor/zenoh-pico` with the `src/system/windows` sources included (similar to the existing Linux arm), drop the bundle scripts, and skip M3's equivalent bundle step for CycloneDDS — for CycloneDDS, fall back to requiring Windows users to set `CYCLONEDDS_DIR` and use `unsafeFlags` in Package.swift. Document the pivot in a new plan addendum.

### Task 2.6: Update main `Package.swift` with real 0.5.0-rc.1 URL + checksum

**Files:**
- Modify: `Package.swift` (the `cZenohPico` Windows arm added in Task 1.1)

- [ ] **Step 1: Swap the placeholder checksum**

Replace `"0000000000000000000000000000000000000000000000000000000000000000"` on the `cZenohPico` Windows arm with the sha256 captured in Task 2.4 step 4. The URL itself already points at `xcframeworkBaseURL`, which we will bump to `0.5.0-rc.1` temporarily:

At the top of `Package.swift` (line 9), change:
```swift
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.4.0"
```
to:
```swift
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.5.0-rc.1"
```

Also update the Apple xcframework checksums for the new tag — a 0.5.0-rc.1 release built from this branch also re-emits those zips with the same content but potentially different sha256 (GitHub re-zips on upload). Read from the release assets:

```bash
for f in CZenohPico.xcframework.zip.checksum CCycloneDDS.xcframework.zip.checksum CZenohPico-windows-x86_64.artifactbundle.zip.checksum; do
  echo "$f:"
  curl -sSL "$(gh release view 0.5.0-rc.1 --json assets --jq ".assets[] | select(.name==\"$f\") | .url")"
  echo
done
```

Apply each hash to the corresponding `checksum:` line in `Package.swift`.

- [ ] **Step 2: Verify Apple build still passes locally**

Run: `swift package reset && swift build`
Expected: SwiftPM refetches the 0.5.0-rc.1 Apple xcframeworks, build succeeds. (If the Apple xcframeworks in 0.5.0-rc.1 are binary-identical to 0.4.0 their checksums will still differ because GitHub re-zips.)

- [ ] **Step 3: Commit**

```bash
git add Package.swift
git commit -m "build: pin binaryTarget checksums to 0.5.0-rc.1 bundles

Replaces the placeholder all-zero Windows checksum with the real
sha256 captured from the 0.5.0-rc.1 release assets. Also bumps
xcframeworkBaseURL + Apple xcframework checksums to match the
re-zipped assets in this release."
```

### Task 2.7: Add the `build-windows` CI job

**Files:**
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: Add the job**

After `build-linux` in `.github/workflows/ci.yml`, append:

```yaml
  build-windows:
    name: Build & Test (Windows x86_64)
    needs: [swift-format]
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: compnerd/gha-setup-swift@main
        with:
          branch: swift-6.0.2-release
          tag: 6.0.2-RELEASE
      - name: Swift version
        run: swift --version
      - name: Build
        run: swift build
      - name: Test
        run: swift test --parallel
```

`SwiftROS2IntegrationTests` skips on missing `LINUX_IP` already — no gating needed.

- [ ] **Step 2: Commit and push**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add Windows x86_64 build + test job

Builds with Swift 6.0.2 on windows-latest using the pinned
compnerd/gha-setup-swift action. Consumes the .binaryTarget artifact
bundles from the 0.5.0-rc.1 release. Runs swift test --parallel;
integration tests self-skip without LINUX_IP."
git push origin HEAD
```

- [ ] **Step 3: Watch CI**

Run: `gh pr checks --watch`
Expected: `build-windows` job passes. Any test that fails on Windows but passes on Apple/Linux must be triaged. Most likely candidates: path-separator-sensitive tests, XCTest behavioral edges. Gate any Windows-divergent test with `#if !os(Windows)` and file a follow-up issue in the PR description — do not skip silently.

### Task 2.8: Open PR #2, merge when green

- [ ] **Step 1: Open PR**

```bash
gh pr create --title "feat(windows-m2): ship zenoh-pico on Windows" --body "$(cat <<'EOF'
## Summary
- Adds the Windows zenoh-pico artifact bundle pipeline: PowerShell build script, release-workflow job, smoke-test consumer, and the \`build-windows\` CI job.
- Pins \`Package.swift\` to 0.5.0-rc.1 checksums.
- Validates spec §8 risk 7 (\`.binaryTarget\` + \`.artifactbundle\` for C libs on Windows works end-to-end).

## Test plan
- [x] 0.5.0-rc.1 release produced bundles successfully.
- [x] Smoke consumer built and ran on windows-latest.
- [x] \`build-windows\` CI job passes \`swift build\` + \`swift test --parallel\`.
- [x] Existing macOS / Linux CI stays green.

See \`docs/superpowers/specs/2026-04-24-windows-support-design.md\` §7 M2 and \`docs/superpowers/plans/2026-04-24-windows-support.md\` Milestone 2.
EOF
)"
```

- [ ] **Step 2: Merge**

```bash
gh pr merge --squash --delete-branch
```

---

## Milestone 3 — CycloneDDS Windows artifactbundle (PR #3)

Goal: repeat the M2 pipeline for CycloneDDS. Because M2 already validated the `.artifactbundle` path end-to-end, this milestone is mechanically similar but the CycloneDDS CMake configuration is more involved, and the bundle must include internal headers.

### Task 3.1: Add `Scripts/Build-WindowsCycloneDDS.ps1`

**Files:**
- Create: `Scripts/Build-WindowsCycloneDDS.ps1`

- [ ] **Step 1: Write the script**

```powershell
#Requires -Version 5.1
# Build CycloneDDS as a Windows x86_64 static library and assemble the
# SwiftPM .artifactbundle expected by Package.swift's Windows arm.
#
# CycloneDDS is *not* vendored as a submodule — this script fetches a
# pinned tag into a transient source tree, builds it, then copies the
# required public + internal headers into the bundle. Keeping CycloneDDS
# out of the submodule list avoids polluting normal clones (Apple and
# Linux never need it as source).
#
# Usage:
#   pwsh Scripts/Build-WindowsCycloneDDS.ps1 -Version 0.5.0-rc.1 -OutDir artifacts

param(
    [Parameter(Mandatory=$true)][string]$Version,
    [Parameter(Mandatory=$true)][string]$OutDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Pin to a specific CycloneDDS release tag. Match what ROS 2 Jazzy
# packages on Linux — today that is 0.10.x. Adjust if upstream moves.
$CycloneTag = '0.10.5'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$srcDir = Join-Path $repoRoot "build-windows/cyclonedds-src"
$buildDir = Join-Path $repoRoot "build-windows/cyclonedds-build"
$installDir = Join-Path $repoRoot "build-windows/cyclonedds-install"
foreach ($d in @($srcDir, $buildDir, $installDir)) {
    Remove-Item -Recurse -Force $d -ErrorAction SilentlyContinue
}

Write-Host "::group::Clone CycloneDDS $CycloneTag"
git clone --depth 1 --branch $CycloneTag `
    https://github.com/eclipse-cyclonedds/cyclonedds.git $srcDir
if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
Write-Host "::endgroup::"

Write-Host "::group::CMake configure"
cmake -S $srcDir -B $buildDir `
    -G 'Visual Studio 17 2022' -A x64 `
    -DCMAKE_BUILD_TYPE=Release `
    -DBUILD_SHARED_LIBS=OFF `
    -DENABLE_SSL=OFF `
    -DENABLE_SECURITY=OFF `
    -DBUILD_IDLC=OFF `
    -DBUILD_DDSPERF=OFF `
    -DBUILD_TESTING=OFF `
    -DBUILD_EXAMPLES=OFF `
    -DCMAKE_INSTALL_PREFIX=$installDir
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
Write-Host "::endgroup::"

Write-Host "::group::CMake build"
cmake --build $buildDir --config Release --target install -- /verbosity:minimal
if ($LASTEXITCODE -ne 0) { throw "CMake build failed" }
Write-Host "::endgroup::"

Write-Host "::group::Installed tree"
Get-ChildItem -Recurse $installDir | Select-Object -ExpandProperty FullName
Write-Host "::endgroup::"

# Assemble the artifact bundle.
$bundleName = 'CCycloneDDS-windows-x86_64.artifactbundle'
$bundleRoot = Join-Path (Resolve-Path $repoRoot) "build-windows/$bundleName"
$variantDir = Join-Path $bundleRoot "CCycloneDDS-$Version-windows/x86_64-unknown-windows-msvc"
Remove-Item -Recurse -Force $bundleRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $variantDir 'lib') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $variantDir 'include') | Out-Null

# Public import library (static build — no DLL).
Copy-Item (Join-Path $installDir 'lib/ddsc.lib') (Join-Path $variantDir 'lib/CCycloneDDS.lib')

# Public headers.
Copy-Item -Recurse (Join-Path $installDir 'include/dds') (Join-Path $variantDir 'include/')

# Internal headers required by CDDSBridge/raw_cdr_sertype.c.
# Upstream install does not export these — copy from the build tree.
$internalSources = @{
    'include/dds/ddsi/q_radmin.h'       = 'src/core/ddsi/include/dds/ddsi/q_radmin.h'
    'include/dds/ddsi/ddsi_sertype.h'   = 'src/core/ddsi/include/dds/ddsi/ddsi_sertype.h'
    'include/dds/ddsi/ddsi_serdata.h'   = 'src/core/ddsi/include/dds/ddsi/ddsi_serdata.h'
    'include/dds/ddsrt/heap.h'          = 'src/ddsrt/include/dds/ddsrt/heap.h'
    'include/dds/ddsrt/md5.h'           = 'src/ddsrt/include/dds/ddsrt/md5.h'
}
foreach ($kv in $internalSources.GetEnumerator()) {
    $dst = Join-Path $variantDir $kv.Key
    $src = Join-Path $srcDir $kv.Value
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    if (Test-Path $src) {
        Copy-Item $src $dst
    } else {
        # Some versions of Cyclone relocate internal headers. Fall back
        # to scanning the source tree for a same-named file.
        $candidate = Get-ChildItem -Recurse $srcDir -Filter (Split-Path $src -Leaf) |
            Select-Object -First 1
        if ($null -eq $candidate) { throw "Missing internal header: $($kv.Value)" }
        Copy-Item $candidate.FullName $dst
    }
}

# Render info.json.
$tpl = Get-Content -Raw (Join-Path $repoRoot 'Scripts/windows-artifactbundle-info.json.template')
$info = $tpl.Replace('@@NAME@@', 'CCycloneDDS').Replace('@@VERSION@@', $Version)
Set-Content -Path (Join-Path $bundleRoot 'info.json') -Value $info -Encoding UTF8

Write-Host "::group::Bundle tree"
Get-ChildItem -Recurse $bundleRoot | Select-Object -ExpandProperty FullName
Write-Host "::endgroup::"

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$zipPath = Join-Path $OutDir "$bundleName.zip"
Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
Compress-Archive -Path $bundleRoot -DestinationPath $zipPath -CompressionLevel Optimal

$hash = (Get-FileHash -Algorithm SHA256 $zipPath).Hash.ToLower()
Set-Content -Path "$zipPath.checksum" -Value $hash -Encoding ASCII

Write-Host "Built $zipPath"
Write-Host "sha256: $hash"
```

Static linking (`BUILD_SHARED_LIBS=OFF`) is intentional — it eliminates runtime DLL search issues on Windows (spec §8 risk 2's fallback).

- [ ] **Step 2: Commit**

```bash
git add Scripts/Build-WindowsCycloneDDS.ps1
git commit -m "build: add PowerShell script to produce Windows CycloneDDS artifact bundle

Clones CycloneDDS 0.10.5 transiently, builds as a static library, and
assembles the .artifactbundle with public headers plus the five internal
headers that CDDSBridge/raw_cdr_sertype.c depends on. Falls back to a
recursive file search if upstream relocates any internal header between
versions."
```

### Task 3.2: Add `build-cyclonedds-windows` and `smoke-cyclonedds-windows` jobs

**Files:**
- Modify: `.github/workflows/release-xcframework.yml`

- [ ] **Step 1: Add the build job**

After `build-zenoh-pico-windows`, append:

```yaml
  build-cyclonedds-windows:
    name: Build CCycloneDDS-windows-x86_64.artifactbundle
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        shell: pwsh
        run: |
          $version = "${{ github.event.inputs.tag || github.ref_name }}"
          pwsh Scripts/Build-WindowsCycloneDDS.ps1 -Version $version -OutDir artifacts
      - name: Upload build artifacts
        uses: actions/upload-artifact@v4
        with:
          name: cyclonedds-windows-artifactbundle
          path: |
            artifacts/*.zip
            artifacts/*.checksum
          if-no-files-found: error
          retention-days: 7
```

- [ ] **Step 2: Extend the smoke-test to cover CycloneDDS**

Rename the existing `smoke-zenoh-pico-windows` job to `smoke-windows` and make it validate both bundles in one go. Replace the job body with:

```yaml
  smoke-windows:
    name: Smoke-test Windows artifact bundles
    needs: [build-zenoh-pico-windows, build-cyclonedds-windows]
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: compnerd/gha-setup-swift@main
        with:
          branch: swift-6.0.2-release
          tag: 6.0.2-RELEASE
      - name: Download zenoh-pico bundle
        uses: actions/download-artifact@v4
        with:
          name: zenoh-pico-windows-artifactbundle
          path: Tests/WindowsBundleSmoke/artifacts
      - name: Download cyclonedds bundle
        uses: actions/download-artifact@v4
        with:
          name: cyclonedds-windows-artifactbundle
          path: Tests/WindowsBundleSmoke/artifacts
      - name: Build smoke consumer
        shell: pwsh
        working-directory: Tests/WindowsBundleSmoke
        run: swift build -v
      - name: Run smoke consumer
        shell: pwsh
        working-directory: Tests/WindowsBundleSmoke
        run: swift run Smoke
```

Update `publish.needs:` to:

```yaml
  publish:
    name: Attach to release
    needs: [build, build-zenoh-pico-windows, build-cyclonedds-windows, smoke-windows]
```

Extend `gh release upload` with the CycloneDDS bundle files:

```yaml
            upload/CCycloneDDS-windows-x86_64.artifactbundle.zip \
            upload/CCycloneDDS-windows-x86_64.artifactbundle.zip.checksum
```

- [ ] **Step 3: Extend the smoke consumer to import CycloneDDS**

Modify `Tests/WindowsBundleSmoke/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let version = "0.5.0-rc.2"
let baseURL = "https://github.com/youtalk/swift-ros2/releases/download/\(version)"

let package = Package(
    name: "WindowsBundleSmoke",
    targets: [
        .binaryTarget(
            name: "CZenohPico",
            url: "\(baseURL)/CZenohPico-windows-x86_64.artifactbundle.zip",
            checksum: "REPLACE_WITH_ZENOH_CHECKSUM"
        ),
        .binaryTarget(
            name: "CCycloneDDS",
            url: "\(baseURL)/CCycloneDDS-windows-x86_64.artifactbundle.zip",
            checksum: "REPLACE_WITH_CYCLONE_CHECKSUM"
        ),
        .executableTarget(
            name: "Smoke",
            dependencies: ["CZenohPico", "CCycloneDDS"],
            path: "Sources/Smoke"
        ),
    ]
)
```

Modify `Tests/WindowsBundleSmoke/Sources/Smoke/main.swift`:

```swift
import CZenohPico
import CCycloneDDS

z_sleep_ms(0)
let participant = dds_create_participant(DDS_DOMAIN_DEFAULT, nil, nil)
if participant > 0 { dds_delete(participant) }
print("smoke ok")
```

- [ ] **Step 4: Commit**

```bash
git add Scripts/ Tests/WindowsBundleSmoke/ .github/workflows/release-xcframework.yml
git commit -m "ci(release): build + smoke-test CycloneDDS Windows artifact bundle

Parallels the zenoh-pico pipeline from M2. Smoke consumer now imports
both modules and exercises a no-op CycloneDDS participant create/delete
to link against ddsc.lib. Static linking (no DLL) is intentional — avoids
Windows DLL search-path issues and matches the standalone-binary
deployment model of the example executables."
```

### Task 3.3: Roll `0.5.0-rc.2` and update checksums

- [ ] **Step 1: Push branch and tag**

```bash
git push -u origin HEAD
git tag 0.5.0-rc.2
git push origin 0.5.0-rc.2
```

- [ ] **Step 2: Watch release workflow**

Run: `gh run watch --exit-status $(gh run list --workflow=release-xcframework.yml --branch=0.5.0-rc.2 --limit=1 --json databaseId --jq '.[0].databaseId')`
Expected: all five jobs green (`build` matrix × 2, `build-zenoh-pico-windows`, `build-cyclonedds-windows`, `smoke-windows`, `publish`).

If `build-cyclonedds-windows` fails on a missing internal header, read the `::group::Installed tree` output plus the fallback log line ("Missing internal header: ...") to identify where Cyclone moved the file. Patch `Scripts/Build-WindowsCycloneDDS.ps1`'s `$internalSources` table, push, re-tag.

- [ ] **Step 3: Record all four new checksums**

```bash
for f in CZenohPico.xcframework.zip.checksum CCycloneDDS.xcframework.zip.checksum \
         CZenohPico-windows-x86_64.artifactbundle.zip.checksum \
         CCycloneDDS-windows-x86_64.artifactbundle.zip.checksum; do
  echo -n "$f: "
  curl -sSL "$(gh release view 0.5.0-rc.2 --json assets --jq ".assets[] | select(.name==\"$f\") | .url")"
  echo
done
```

- [ ] **Step 4: Update `Package.swift` to point at `0.5.0-rc.2`**

Change `xcframeworkBaseURL` to `https://github.com/youtalk/swift-ros2/releases/download/0.5.0-rc.2` and apply all four checksums to the corresponding `binaryTarget` declarations (two Apple arms for back-compat testing, two Windows arms).

Also update `Tests/WindowsBundleSmoke/Package.swift` `version` and both `REPLACE_WITH_*_CHECKSUM` placeholders with the actual hashes.

- [ ] **Step 5: Verify Windows CI passes with real CycloneDDS bundle**

```bash
git add Package.swift Tests/WindowsBundleSmoke/Package.swift
git commit -m "build: pin to 0.5.0-rc.2 bundles (adds CycloneDDS Windows)"
git push origin HEAD
gh pr checks --watch
```

Expected: `build-windows` now also pulls `CCycloneDDS-windows-x86_64.artifactbundle.zip`, compiles `SwiftROS2DDS` and `CDDSBridge`, runs `SwiftROS2DDSTests`.

### Task 3.4: Open PR #3, merge when green

- [ ] **Step 1: Open PR**

```bash
gh pr create --title "feat(windows-m3): ship CycloneDDS on Windows" --body "$(cat <<'EOF'
## Summary
- CycloneDDS artifact bundle pipeline, static build (no DLL search-path issues).
- Smoke consumer now imports both CZenohPico and CCycloneDDS.
- \`build-windows\` CI job green end-to-end, both modules linked.

## Test plan
- [x] 0.5.0-rc.2 release produced both bundles.
- [x] Smoke consumer runs on windows-latest.
- [x] \`build-windows\` CI runs the full unit suite (SwiftROS2CDRTests, SwiftROS2WireTests, SwiftROS2Tests, SwiftROS2ZenohTests, SwiftROS2DDSTests).

See spec §7 M3 and plan Milestone 3.
EOF
)"
```

- [ ] **Step 2: Merge**

```bash
gh pr merge --squash --delete-branch
```

---

## Milestone 4 — Windows test stabilization (PR #4, only if needed)

Goal: address any Windows-specific test failures surfaced by M2/M3 work. If `build-windows` was already fully green in M3, this milestone is a no-op — skip to M5.

### Task 4.1: Triage Windows-specific failures

- [ ] **Step 1: Enumerate failures**

Run: `gh run view --log $(gh run list --workflow=ci.yml --branch=main --limit=1 --json databaseId --jq '.[0].databaseId') | grep -A 3 "XCTest.*failed" | head -40`

For each failing test:
- Is it a genuine Windows behavioral difference (path separators, locale, timing)? Gate with `#if !os(Windows)`.
- Is it a real bug that also affects Apple/Linux but only surfaces under the Windows toolchain's stricter optimizer? Fix it.
- Is it flakiness? Re-run; only gate after three consecutive failures.

- [ ] **Step 2: Apply targeted fixes**

Each gate or fix gets its own focused commit:

```bash
git commit -m "test(SwiftROS2CDRTests): skip <TestName> on Windows

<Reason — e.g. CRLF line endings in the golden file differ on Windows;
filed follow-up #NN to normalize line endings in the golden source.>"
```

- [ ] **Step 3: Open PR only if changes were needed**

If no fixes were needed, delete the branch and move on to M5.

---

## Milestone 5 — 0.5.0 final release (PR #5)

Goal: promote the validated RC to `0.5.0`, refresh documentation, let downstream (Conduit) bump.

### Task 5.1: Update README and CLAUDE.md

**Files:**
- Modify: `README.md` (supported-platforms list near the top)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add Windows to README platform list**

Locate the "Platforms" or equivalent section in `README.md` and extend it. If the existing list reads:

```
- Apple (iOS 16+, iPadOS 16+, macOS 13+, Mac Catalyst 16+, visionOS 1+)
- Linux (Ubuntu 22.04 / 24.04, x86_64 + aarch64)
```

Change to:

```
- Apple (iOS 16+, iPadOS 16+, macOS 13+, Mac Catalyst 16+, visionOS 1+)
- Linux (Ubuntu 22.04 / 24.04, x86_64 + aarch64)
- Windows (Windows 10+, x86_64, MSVC ABI)
```

- [ ] **Step 2: Add "Windows" subsection to CLAUDE.md's "Build & test commands"**

Insert after the Linux subsection:

```markdown
### Windows

**Local Windows builds are not supported by this project.** The maintainer has no local Windows environment; all Windows validation is performed on GitHub Actions. To iterate on Windows changes, push to a branch and read the `build-windows` CI log (`.github/workflows/ci.yml`).

If you do have a local Windows machine and want to reproduce CI:

1. Install Swift 6.0.2 for Windows from https://www.swift.org/install/windows/.
2. Install Visual Studio 2022 Build Tools with the Windows 10 SDK.
3. `swift build` / `swift test --parallel` from a Developer PowerShell.

zenoh-pico and CycloneDDS are pulled from GitHub Release `.artifactbundle`s — there is no local CMake step.
```

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: announce Windows support and CI-only development flow"
```

### Task 5.2: Bump to `0.5.0` and cut the final release

- [ ] **Step 1: Update `xcframeworkBaseURL`**

In `Package.swift`, change:
```swift
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.5.0-rc.2"
```
to:
```swift
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.5.0"
```

Leave checksums as placeholders (zeroes on all four `binaryTarget`s) — they will be filled in after the 0.5.0 release builds.

- [ ] **Step 2: Commit, push, tag**

```bash
git add Package.swift
git commit -m "build: bump xcframeworkBaseURL to 0.5.0"
git push origin HEAD
gh pr create --title "release: 0.5.0" --body "$(cat <<'EOF'
## Summary
- Bumps \`xcframeworkBaseURL\` to the \`0.5.0\` release tag.
- Paired with README / CLAUDE.md updates announcing Windows x86_64 support.
- Checksums are refreshed in a follow-up PR after the release workflow attaches the bundles (GitHub re-zips on upload, so checksums can only be computed post-publish).

## Release notes
- Platforms: Apple (unchanged), Linux (unchanged), **Windows x86_64 (new)**.
- Windows consumes zenoh-pico + CycloneDDS via \`.binaryTarget\` \`.artifactbundle\` zips attached to this release.
- No API changes; downstream consumers pick up Windows support automatically when bumping.
EOF
)"

# Merge the PR first, then tag from main:
gh pr merge --squash
git checkout main
git pull --ff-only
git tag 0.5.0
git push origin 0.5.0
```

- [ ] **Step 3: Watch release workflow**

Run: `gh run watch --exit-status $(gh run list --workflow=release-xcframework.yml --branch=0.5.0 --limit=1 --json databaseId --jq '.[0].databaseId')`
Expected: all jobs green, four artifacts attached to release `0.5.0`.

- [ ] **Step 4: Backfill checksums**

```bash
for f in CZenohPico.xcframework.zip.checksum CCycloneDDS.xcframework.zip.checksum \
         CZenohPico-windows-x86_64.artifactbundle.zip.checksum \
         CCycloneDDS-windows-x86_64.artifactbundle.zip.checksum; do
  echo -n "$f: "
  curl -sSL "$(gh release view 0.5.0 --json assets --jq ".assets[] | select(.name==\"$f\") | .url")"
  echo
done
```

Apply each to `Package.swift`. Open a small follow-up PR "build: pin 0.5.0 checksums" and merge.

- [ ] **Step 5: Verify all CI green after checksum pin**

Run: `gh pr checks --watch`
Expected: `build-macos`, `build-linux` matrix, `build-windows` all green.

### Task 5.3: Downstream verification — Conduit can consume 0.5.0

- [ ] **Step 1: Update Conduit's `deps/swift-ros2` submodule**

```bash
cd /Users/yutaka.kondo/src/conduit
git checkout -b chore/bump-swift-ros2-0.5.0
cd deps/swift-ros2
git fetch origin
git checkout 0.5.0
cd ../..
git add deps/swift-ros2
git commit -m "chore: bump swift-ros2 to 0.5.0 (adds Windows support)"
```

- [ ] **Step 2: Verify Conduit still builds on Apple**

Run: `xcodebuild -project Conduit.xcodeproj -scheme Conduit -destination "platform=macOS,variant=Mac Catalyst,arch=arm64" -configuration Debug build CODE_SIGNING_ALLOWED=NO`
Expected: build succeeds. Conduit does not target Windows itself, so `.artifactbundle`s are not fetched; only Apple xcframeworks matter.

- [ ] **Step 3: Open Conduit PR, merge**

```bash
git push -u origin HEAD
gh pr create --title "chore: bump swift-ros2 to 0.5.0" --body "Pick up Windows support. No Conduit-side changes required."
gh pr merge --squash --delete-branch
```

---

## Execution notes

- **Branches:** one feature branch per PR (`feat/windows-m1-package-scaffold`, `feat/windows-m2-zenoh-bundle`, …). The current design-doc branch (`docs/windows-support-design`) is closed out by its own merge; milestone branches are cut off `main` after each prior PR merges.
- **RC tags:** `0.5.0-rc.1` (M2) and `0.5.0-rc.2` (M3) exercise the release pipeline without publishing a "final" release. They can be deleted from the remote after `0.5.0` ships if the tag clutter is unwanted (`gh release delete 0.5.0-rc.1 && git push --delete origin 0.5.0-rc.1`).
- **No local Windows:** every task past M1 ends with "push + read CI log". If a task says "run X locally" and X is Windows-specific, that is a plan bug — flag it.
- **Fallback gate:** Task 2.5 is the single point where the `.binaryTarget` + `.artifactbundle` path is proven. If it fails, pivot to the fallback described inline in that task before continuing to M3.
- **Conduit is downstream-only here.** Conduit's own Windows story is out of scope; that project does not currently compile on Windows (it uses iOS/macOS Apple frameworks), and enabling it is a separate design exercise.
