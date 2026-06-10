// swift-tools-version: 5.9

import Foundation
import PackageDescription

// Apple platforms: pre-built xcframework binaryTargets hosted on
// GitHub Releases. Linux, Windows, and Android: compile the C sources
// directly via SPM, using the matching platform backend inside
// vendor/zenoh-pico. See Scripts/build-xcframework.sh for the macOS
// build helper.
//
// CycloneDDS on Linux resolves through pkg-config; on Apple it ships
// as a prebuilt xcframework. On Windows the DDS path opts in through a
// `CYCLONEDDS_DIR` env var pointing at a vcpkg-installed CycloneDDS
// tree (`vcpkg install cyclonedds:x64-windows`); the manifest then adds
// `-I<dir>/include` and `-L<dir>/lib` to CDDSBridge so `#include
// <dds/dds.h>` and `-lddsc` resolve. Without `CYCLONEDDS_DIR` the
// Windows build keeps the existing Zenoh-only carve-out. Android does
// not ship DDS at all — the entire DDS path (cCycloneDDS, CDDSBridge,
// SwiftROS2DDS, the SwiftROS2 umbrella, and the DDS/umbrella tests) is
// compiled out via the runtime `if canBuildDDS` gate around the
// targets/products additions further down.
//
// Cross-compilation target detection. Plain `#if os(...)` at manifest
// scope reflects the HOST, which breaks when cross-compiling from
// Linux to Android (`swift build --swift-sdk <android-triple>`): the
// Linux arm would be selected and the DDS path pulled in. CI exports
// `SWIFT_ROS2_TARGET_OS=android` for the Android matrix so the arm
// selection below matches the intended target. Target-scoped settings
// like `.when(platforms: [.android])` on cSettings stay correct
// regardless because SPM evaluates those against the target platform.
let targetOS: String = {
    // Explicit allow-list so typos or unexpected values fail fast here
    // instead of silently falling through to the Apple arm and quietly
    // re-enabling the DDS path.
    let allowed: Set<String> = ["linux", "windows", "android", "apple"]
    if let raw = Context.environment["SWIFT_ROS2_TARGET_OS"] {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalized.isEmpty {
            guard allowed.contains(normalized) else {
                let joined = allowed.sorted().joined(separator: ", ")
                fatalError("SWIFT_ROS2_TARGET_OS must be one of {\(joined)}; got '\(raw)'")
            }
            return normalized
        }
    }
    #if os(Linux)
        return "linux"
    #elseif os(Windows)
        return "windows"
    #elseif os(Android)
        return "android"
    #else
        return "apple"
    #endif
}()

let isLinuxBuild = targetOS == "linux"
let isWindowsBuild = targetOS == "windows"
let isAndroidBuild = targetOS == "android"

// Windows DDS opt-in. When `CYCLONEDDS_DIR` is set on a Windows build,
// the manifest pulls in the full DDS path (CCycloneDDS / CDDSBridge /
// SwiftROS2DDS / SwiftROS2 umbrella / examples / DDS tests) and wires
// `-I<dir>/include` + `-L<dir>/lib` into CDDSBridge so `#include
// <dds/dds.h>` and the `-lddsc` link emitted by the CCycloneDDS
// modulemap both resolve against the vcpkg-installed CycloneDDS tree.
// When unset, the Windows arm stays Zenoh-only — same shape as 0.5.0
// through 0.7.0.
let windowsCycloneDDSDir: String? = {
    guard isWindowsBuild else { return nil }
    guard let raw = Context.environment["CYCLONEDDS_DIR"] else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}()

// Whether the current target can build the CycloneDDS-based DDS path.
// Apple (binary xcframework) and Linux (pkg-config) always can; Windows
// can only when `CYCLONEDDS_DIR` is set; Android never can.
let canBuildDDS = !isAndroidBuild && (!isWindowsBuild || windowsCycloneDDSDir != nil)

let releaseBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/1.2.0"

// M0-only (native-rcl spike): opt-in via SWIFT_ROS2_ENABLE_RCL=1 so default
// consumers are unaffected. When set on an Apple build, the manifest adds a
// local path-based binaryTarget for the not-yet-released CRos2Jazzy
// xcframework (built by Scripts/build-ros2-xcframework.sh) plus an rcl_init
// smoke executable. Replaced by a URL+checksum binaryTarget in M3.
let enableRcl = Context.environment["SWIFT_ROS2_ENABLE_RCL"] == "1" && targetOS == "apple"

// SWIFT_ROS2_RCL_RMW selects the rmw variant baked into the RCL binary
// target: "cyclonedds" (default) -> build/ros2/CRos2Jazzy.xcframework, or
// "zenoh" -> build/ros2zenoh/CRos2JazzyZenoh.xcframework (rmw_zenoh_cpp +
// fastrtps typesupport; build with
// `RMW_VARIANT=zenoh Scripts/build-ros2-xcframework.sh`). Both variants
// expose the identical rcl C API under the same module name, so every Swift
// target is variant-agnostic.
let rclRmwVariant: String = {
    let raw = Context.environment["SWIFT_ROS2_RCL_RMW"] ?? "cyclonedds"
    guard ["cyclonedds", "zenoh"].contains(raw) else {
        fatalError("SWIFT_ROS2_RCL_RMW must be 'cyclonedds' or 'zenoh'; got '\(raw)'")
    }
    return raw
}()

// zenoh-pico (the wire path) and zenoh-c (bundled inside CRos2JazzyZenoh)
// both export the standard zenoh C API, so they cannot link into one binary.
// Selecting the zenoh rmw variant therefore carves the zenoh-pico wire family
// (CZenohPico / CZenohBridge / SwiftROS2Zenoh + its tests) out of the build
// graph; the umbrella's `.zenoh` transport arm compiles out via
// `#if canImport(SwiftROS2Zenoh)` and throws unsupportedFeature at runtime.
let dropZenohWire = enableRcl && rclRmwVariant == "zenoh"

// Non-unix zenoh-pico platform backends shared between the Linux and
// Android arms — both use the unix backend inside `src/system/unix`.
let zenohPicoNonUnixBackends = [
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
]

let cZenohPico: Target = {
    if isLinuxBuild || isAndroidBuild {
        return .target(
            name: "CZenohPico",
            path: "vendor/zenoh-pico",
            exclude: zenohPicoNonUnixBackends,
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
                // Target-platform conditional — SPM evaluates against the
                // actual target triple, so this picks up ZENOH_ANDROID on
                // Android cross-builds even though the Linux host drove
                // the `isLinuxBuild || isAndroidBuild` arm selection.
                .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
                .define("ZENOH_ANDROID", to: "1", .when(platforms: [.android])),
            ]
        )
    } else if isWindowsBuild {
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
                "src/system/unix",
                "src/system/void",
                "src/system/zephyr",
                "src/system/flipper",
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
                .define("ZENOH_WINDOWS", to: "1"),
            ]
        )
    } else {
        // Apple: binary xcframework.
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(releaseBaseURL)/CZenohPico.xcframework.zip",
            checksum: "8b2f47804138a06bba449dc56a68b62b52c73bc0f1aa67bc52149184b1699d23"
        )
    }
}()

// Products and targets common to every supported platform (the Zenoh
// path and the pure-Swift layers).
var products: [Product] = [
    .library(name: "SwiftROS2CDR", targets: ["SwiftROS2CDR"]),
    .library(name: "SwiftROS2Messages", targets: ["SwiftROS2Messages"]),
    .library(name: "SwiftROS2Wire", targets: ["SwiftROS2Wire"]),
    .library(name: "SwiftROS2Transport", targets: ["SwiftROS2Transport"]),
    .library(name: "SwiftROS2Gen", targets: ["SwiftROS2Gen"]),
    .executable(name: "swift-ros2-gen", targets: ["swift-ros2-gen"]),
    .plugin(name: "SwiftROS2GenPlugin", targets: ["SwiftROS2GenPlugin"]),
]

var targets: [Target] = [
    // CDR serialization (pure Swift, no dependencies)
    .target(
        name: "SwiftROS2CDR",
        path: "Sources/SwiftROS2CDR"
    ),

    // Wire format codecs (no dependencies)
    .target(
        name: "SwiftROS2Wire",
        path: "Sources/SwiftROS2Wire"
    ),

    // Message protocols and built-in types. Generated messages with
    // distro-conditional `typeInfo(for:)` reach into `SwiftROS2Wire` for
    // `ROS2Distro`, so the dependency is declared explicitly even though
    // `SwiftROS2CDR` does not transitively need it.
    .target(
        name: "SwiftROS2Messages",
        dependencies: ["SwiftROS2CDR", "SwiftROS2Wire"],
        path: "Sources/SwiftROS2Messages"
    ),

    // Transport abstraction layer
    .target(
        name: "SwiftROS2Transport",
        dependencies: ["SwiftROS2CDR", "SwiftROS2Wire"],
        path: "Sources/SwiftROS2Transport"
    ),

    // Pure-Swift and Zenoh-path tests (available on every platform)
    .testTarget(
        name: "SwiftROS2CDRTests",
        dependencies: ["SwiftROS2CDR", "SwiftROS2Messages"],
        path: "Tests/SwiftROS2CDRTests"
    ),
    .testTarget(
        name: "SwiftROS2WireTests",
        dependencies: ["SwiftROS2Wire"],
        path: "Tests/SwiftROS2WireTests"
    ),
    .testTarget(
        name: "SwiftROS2TransportTests",
        dependencies: ["SwiftROS2Transport", "SwiftROS2Wire"],
        path: "Tests/SwiftROS2TransportTests"
    ),

    // Code generator library — IDL → Swift ROS2Message conformances.
    // SHA-256 (used by RIHS01) is implemented in pure Swift inside this
    // target so non-Apple CI matrix entries — Windows in particular —
    // don't pay the cost of compiling swift-crypto's BoringSSL on every
    // run. See Sources/SwiftROS2Gen/Hash/SHA256.swift.
    .target(
        name: "SwiftROS2Gen",
        dependencies: [],
        path: "Sources/SwiftROS2Gen"
    ),

    // CLI entry point for the code generator
    .executableTarget(
        name: "swift-ros2-gen",
        dependencies: [
            "SwiftROS2Gen",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ],
        path: "Sources/swift-ros2-gen"
    ),

    // Unit tests for the code generator
    .testTarget(
        name: "SwiftROS2GenTests",
        dependencies: ["SwiftROS2Gen"],
        path: "Tests/SwiftROS2GenTests",
        resources: [.copy("Resources")]
    ),

    // Hash-oracle corpus diff (env-gated). When
    // SWIFT_ROS2_GEN_HASH_ORACLE_IMAGE is unset every test row reports as
    // a skip (`#require` short-circuit), so the regular `swift test`
    // sweep stays unchanged for contributors without Docker. CI's
    // `.github/workflows/hash-oracle.yml` sets the env var to
    // `osrf/ros:<distro>-desktop` and exercises the full diff.
    .testTarget(
        name: "SwiftROS2GenHashOracleTests",
        dependencies: ["SwiftROS2Gen"],
        path: "Tests/SwiftROS2GenHashOracleTests",
        resources: [.copy("Resources")]
    ),

    // SwiftPM build-tool plugin — invokes swift-ros2-gen on a downstream
    // target's msg/ directory. Intentionally thin: handles only the
    // single-package single-distro (jazzy) common case. Multi-distro,
    // multi-package, .srv, and .action callers drop back to the CLI.
    .plugin(
        name: "SwiftROS2GenPlugin",
        capability: .buildTool(),
        dependencies: [
            .target(name: "swift-ros2-gen")
        ],
        path: "Plugins/SwiftROS2GenPlugin"
    ),

    // Smoke target proving end-to-end SwiftROS2GenPlugin invocation:
    // the plugin generates a Swift wrapper for `msg/Bool.msg` at build
    // time, and `main.swift` prints the resulting type's typeInfo.
    .executableTarget(
        name: "PluginSmoke",
        dependencies: ["SwiftROS2CDR", "SwiftROS2Messages"],
        path: "Sources/Examples/PluginSmoke",
        exclude: ["msg"],
        plugins: [
            .plugin(name: "SwiftROS2GenPlugin")
        ]
    ),

    // Unit tests for the SwiftROS2GenPlugin static naming helper. SwiftPM
    // does not expose plugin module sources to test targets, so the
    // helper is duplicated into the test file as a literal copy. If the
    // plugin's naming rule changes, both copies must change in lockstep.
    .testTarget(
        name: "SwiftROS2GenPluginTests",
        dependencies: [],
        path: "Tests/SwiftROS2GenPluginTests"
    ),
]

// zenoh-pico wire family — every platform EXCEPT the zenoh-rmw RCL variant
// (symbol collision with zenoh-c; see `dropZenohWire` above).
if !dropZenohWire {
    products.append(.library(name: "SwiftROS2Zenoh", targets: ["SwiftROS2Zenoh"]))
    targets.append(contentsOf: [
        // Native C FFI for zenoh-pico. Apple platforms receive the pre-built
        // xcframework; Linux, Windows, and Android compile from source using
        // the matching platform backend inside vendor/zenoh-pico.
        cZenohPico,

        // C bridge for zenoh-pico (Conduit-authored FFI shim).
        .target(
            name: "CZenohBridge",
            dependencies: ["CZenohPico"],
            path: "Sources/CZenohBridge",
            sources: ["zenoh_bridge.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define(
                    "ZENOH_MACOS", to: "1",
                    .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
                .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
                .define("ZENOH_WINDOWS", to: "1", .when(platforms: [.windows])),
                .define("ZENOH_ANDROID", to: "1", .when(platforms: [.android])),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
            ],
            linkerSettings: [
                .linkedLibrary("Ws2_32", .when(platforms: [.windows])),
                .linkedLibrary("Iphlpapi", .when(platforms: [.windows])),
            ]
        ),

        // Swift-facing Zenoh module — hosts ZenohClient, the default
        // implementation of ZenohClientProtocol defined in SwiftROS2Transport.
        .target(
            name: "SwiftROS2Zenoh",
            dependencies: ["CZenohBridge", "SwiftROS2Transport", "SwiftROS2Wire"],
            path: "Sources/SwiftROS2Zenoh"
        ),
        .testTarget(
            name: "SwiftROS2ZenohTests",
            dependencies: ["SwiftROS2Zenoh"],
            path: "Tests/SwiftROS2ZenohTests"
        ),
    ])
}

// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable
// (see `canBuildDDS` above): Apple via binary xcframework, Linux via
// pkg-config, Windows via vcpkg + `CYCLONEDDS_DIR`. Android does not
// ship DDS — `import SwiftROS2Zenoh` is the supported entry point
// there. Windows builds without `CYCLONEDDS_DIR` set keep the same
// Zenoh-only shape as 0.5.0 through 0.7.0.
if canBuildDDS {
    let cCycloneDDS: Target = {
        if isLinuxBuild {
            return .systemLibrary(
                name: "CCycloneDDS",
                path: "Sources/CCycloneDDS",
                pkgConfig: "CycloneDDS"
            )
        } else if isWindowsBuild {
            // Windows uses the same modulemap + shim.h as Linux, but
            // header / library search paths come from `CYCLONEDDS_DIR`
            // (vcpkg) injected onto CDDSBridge below — there is no
            // pkg-config in the picture.
            return .systemLibrary(
                name: "CCycloneDDS",
                path: "Sources/CCycloneDDS"
            )
        } else {
            return .binaryTarget(
                name: "CCycloneDDS",
                url: "\(releaseBaseURL)/CCycloneDDS.xcframework.zip",
                checksum: "36f30e40506b02cc994fc1f0e1f8f03c488d7bc6dc2e5aac37a919ccc9060d36"
            )
        }
    }()

    // CDDSBridge consumes `<dds/...>` headers via `#include` and links
    // `ddsc`. On Linux those flags come from pkg-config; on Apple they
    // come from the xcframework. On Windows the manifest threads
    // `-I<vcpkg>/include` + `-L<vcpkg>/lib` through `cSettings` /
    // `linkerSettings` keyed off `CYCLONEDDS_DIR`, plus an explicit
    // `.linkedLibrary("ddsc")` (the modulemap's `link "ddsc"` directive
    // only fires when something does `import CCycloneDDS` from Swift,
    // and nobody in this package does — CDDSBridge reaches CycloneDDS
    // through plain `#include`). The unsafeFlags are gated on
    // `isWindowsBuild` at manifest scope so non-Windows targets see no
    // unsafe flags — that keeps the package consumable as an external
    // SPM dependency on Apple/Linux.
    var ddsBridgeCSettings: [CSetting] = [.define("DDS_AVAILABLE", to: "1")]
    var ddsBridgeLinkerSettings: [LinkerSetting] = []
    if isWindowsBuild, let dir = windowsCycloneDDSDir {
        // Forward-slash the path so clang on Windows sees uniform
        // separators regardless of how `CYCLONEDDS_DIR` was exported.
        let normalizedDir = dir.replacingOccurrences(of: "\\", with: "/")
        ddsBridgeCSettings.append(.unsafeFlags(["-I\(normalizedDir)/include"]))
        // CycloneDDS's `dds/ddsrt/misc.h` defines `DDSRT_WARNING_MSVC_OFF(x)`
        // as `__pragma(warning(disable: ## x))`. The `##` token-paste
        // glues `:` and the warning number into `:4146`, which MSVC
        // accepts but clang rejects with `error: pasting formed ':4146',
        // an invalid preprocessing token [-Winvalid-token-paste]`.
        // Swift on Windows ships clang.exe, so the headers refuse to
        // parse without this suppression.
        ddsBridgeCSettings.append(.unsafeFlags(["-Wno-invalid-token-paste"]))
        ddsBridgeLinkerSettings.append(.unsafeFlags(["-L\(normalizedDir)/lib"]))
        ddsBridgeLinkerSettings.append(.linkedLibrary("ddsc"))
    }

    products.append(contentsOf: [
        .library(name: "SwiftROS2", targets: ["SwiftROS2"]),
        .library(name: "SwiftROS2DDS", targets: ["SwiftROS2DDS"]),
    ])

    targets.append(contentsOf: [
        cCycloneDDS,

        .target(
            name: "CDDSBridge",
            dependencies: ["CCycloneDDS"],
            path: "Sources/CDDSBridge",
            sources: ["dds_bridge.c", "raw_cdr_sertype.c", "raw_cdr_regression_bridge.c"],
            publicHeadersPath: "include",
            cSettings: ddsBridgeCSettings,
            linkerSettings: ddsBridgeLinkerSettings
        ),

        .target(
            name: "SwiftROS2DDS",
            dependencies: ["CDDSBridge", "SwiftROS2Transport", "SwiftROS2Wire"],
            path: "Sources/SwiftROS2DDS"
        ),

        // Public API umbrella: Context, Node, Publisher, Subscription
    ])

    var swiftROS2Deps: [Target.Dependency] = [
        "SwiftROS2Messages", "SwiftROS2Transport", "SwiftROS2Wire", "SwiftROS2DDS",
    ]
    if !dropZenohWire {
        swiftROS2Deps.append("SwiftROS2Zenoh")
    }
    var swiftROS2SwiftSettings: [SwiftSetting] = []
    if enableRcl {
        swiftROS2Deps.append("SwiftROS2RCL")
        swiftROS2SwiftSettings.append(.define("SWIFT_ROS2_RCL"))
    }

    var swiftROS2TestsSwiftSettings: [SwiftSetting] = []
    if enableRcl {
        swiftROS2TestsSwiftSettings.append(.define("SWIFT_ROS2_RCL"))
    }

    var integrationDeps: [Target.Dependency] = [
        "SwiftROS2", "SwiftROS2Messages", "SwiftROS2Transport",
    ]
    var integrationSwiftSettings: [SwiftSetting] = []
    if enableRcl {
        integrationDeps.append("SwiftROS2RCL")
        integrationSwiftSettings.append(.define("SWIFT_ROS2_RCL"))
    }

    targets.append(contentsOf: [
        .target(
            name: "SwiftROS2",
            dependencies: swiftROS2Deps,
            path: "Sources/SwiftROS2",
            swiftSettings: swiftROS2SwiftSettings
        ),

        // Example executables — minimal std_msgs/String talker + listener
        // demos in the shape of demo_nodes_cpp. Transport (zenoh or dds) is
        // picked by the first CLI argument so one binary covers both.
        .executableTarget(
            name: "talker",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/Talker"
        ),
        .executableTarget(
            name: "listener",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/Listener"
        ),
        .executableTarget(
            name: "srv-server",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/SrvServer"
        ),
        .executableTarget(
            name: "srv-client",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/SrvClient"
        ),
        .executableTarget(
            name: "action-server",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/ActionServer"
        ),
        .executableTarget(
            name: "action-client",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/ActionClient"
        ),
        .executableTarget(
            name: "parameter-demo",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/ParameterDemo"
        ),

        .testTarget(
            name: "SwiftROS2Tests",
            dependencies: ["SwiftROS2", "SwiftROS2Messages", "SwiftROS2CDR"],
            path: "Tests/SwiftROS2Tests",
            swiftSettings: swiftROS2TestsSwiftSettings
        ),
        .testTarget(
            name: "SwiftROS2DDSTests",
            dependencies: ["SwiftROS2DDS", "SwiftROS2Transport"],
            path: "Tests/SwiftROS2DDSTests"
        ),
        .testTarget(
            name: "SwiftROS2IntegrationTests",
            dependencies: integrationDeps,
            path: "Tests/SwiftROS2IntegrationTests",
            swiftSettings: integrationSwiftSettings
        ),
    ])
}

// M0-only native-rcl spike: local CRos2Jazzy xcframework + rcl_init smoke
// executable, gated behind SWIFT_ROS2_ENABLE_RCL=1 (Apple only).
//
if enableRcl {
    targets.append(
        .binaryTarget(
            name: "CRos2Jazzy",
            path: rclRmwVariant == "zenoh"
                ? "build/ros2zenoh/CRos2JazzyZenoh.xcframework"
                : "build/ros2/CRos2Jazzy.xcframework"
        ))
    // rmw_cyclonedds_cpp / rcpputils in CRos2Jazzy are C++, so every target
    // that links the merged archive needs the C++ runtime. The zenoh variant
    // additionally bundles zenoh-c's Rust staticlib, whose rustls/ring TLS,
    // network monitoring, and serialport (transport_serial feature) code
    // require these system frameworks at final link. Applied to CRclBridge
    // AND to targets that depend on CRos2Jazzy directly (rcl-smoke).
    let rclBridgeLinkerSettings: [LinkerSetting] =
        rclRmwVariant == "zenoh"
        ? [
            .linkedLibrary("c++"),
            .linkedFramework("Security"),
            .linkedFramework("SystemConfiguration"),
            .linkedFramework("CoreFoundation"),
            .linkedFramework("IOKit"),
        ]
        : [.linkedLibrary("c++")]
    targets.append(
        .executableTarget(
            name: "rcl-smoke",
            dependencies: ["CRos2Jazzy"],
            path: "Sources/Examples/RclSmoke",
            linkerSettings: rclBridgeLinkerSettings
        ))
    products.append(.executable(name: "rcl-smoke", targets: ["rcl-smoke"]))
    targets.append(
        .target(
            name: "CRclBridge",
            dependencies: ["CRos2Jazzy"],
            path: "Sources/CRclBridge",
            sources: ["rcl_bridge.c", "rcl_subscription.c", "Generated"],
            publicHeadersPath: "include",
            linkerSettings: rclBridgeLinkerSettings
        ))
    targets.append(
        .executableTarget(
            name: "crcl-smoke",
            dependencies: ["CRclBridge"],
            path: "Sources/Examples/CrclSmoke",
            linkerSettings: [.linkedLibrary("c++")]
        ))
    products.append(.executable(name: "crcl-smoke", targets: ["crcl-smoke"]))
    targets.append(
        .executableTarget(
            name: "crcl-golden",
            dependencies: ["SwiftROS2", "SwiftROS2RCL"],
            path: "Sources/Examples/CrclGolden",
            linkerSettings: [.linkedLibrary("c++")]
        ))
    products.append(.executable(name: "crcl-golden", targets: ["crcl-golden"]))
    targets.append(
        .executableTarget(
            name: "crcl-loopback",
            dependencies: ["SwiftROS2"],
            path: "Sources/Examples/CrclLoopback",
            linkerSettings: [.linkedLibrary("c++")]
        ))
    products.append(.executable(name: "crcl-loopback", targets: ["crcl-loopback"]))
    targets.append(
        .executableTarget(
            name: "rcl-bench",
            dependencies: ["SwiftROS2", "SwiftROS2RCL"],
            path: "Sources/Examples/RclBench",
            linkerSettings: [.linkedLibrary("c++")]
        ))
    products.append(.executable(name: "rcl-bench", targets: ["rcl-bench"]))
    targets.append(
        .target(
            name: "SwiftROS2RCL",
            dependencies: ["CRclBridge", "SwiftROS2Transport", "SwiftROS2Messages"],
            path: "Sources/SwiftROS2RCL"
        ))
    products.append(.library(name: "SwiftROS2RCL", targets: ["SwiftROS2RCL"]))
}

// Only pull in swift-docc-plugin when actually building documentation
// (env var `SWIFT_ROS2_DOCS_BUILD=1`). On Swift < 6.1, having the plugin
// active during `swift package diagnose-api-breaking-changes` clobbers
// the symbol-graph emission that the diagnose tool relies on, so every
// type reads as "removed" even when nothing changed. Gating the dep
// keeps `swift build`, `swift test`, and `diagnose-api-breaking-changes`
// unaffected; the docs-build CI job and the local docs script set the
// env var explicitly.
let isDocsBuild = ProcessInfo.processInfo.environment["SWIFT_ROS2_DOCS_BUILD"] == "1"

var packageDependencies: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
]
if isDocsBuild {
    packageDependencies.append(.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0"))
}

let package = Package(
    name: "swift-ros2",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .visionOS(.v1),
    ],
    products: products,
    dependencies: packageDependencies,
    targets: targets
)
