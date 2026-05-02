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
// as a prebuilt xcframework. Windows and Android do not ship DDS —
// the entire DDS path (cCycloneDDS, CDDSBridge, SwiftROS2DDS, the
// SwiftROS2 umbrella, and the DDS/umbrella tests) is compiled out on
// both platforms via the runtime `if !isWindowsBuild && !isAndroidBuild`
// gate around the targets/products additions further down.
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

let releaseBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.7.0"

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
            checksum: "799a5a6b17b5392d6f7597b90ff1c06501fd0f10727a2e9e57aa493f2fa7c135"
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
    .library(name: "SwiftROS2Zenoh", targets: ["SwiftROS2Zenoh"]),
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

    // Message protocols and built-in types
    .target(
        name: "SwiftROS2Messages",
        dependencies: ["SwiftROS2CDR"],
        path: "Sources/SwiftROS2Messages"
    ),

    // Transport abstraction layer
    .target(
        name: "SwiftROS2Transport",
        dependencies: ["SwiftROS2CDR", "SwiftROS2Wire"],
        path: "Sources/SwiftROS2Transport"
    ),

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
            .define("ZENOH_MACOS", to: "1", .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
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

    // Pure-Swift and Zenoh-path tests (available on every platform)
    .testTarget(
        name: "SwiftROS2CDRTests",
        dependencies: ["SwiftROS2CDR"],
        path: "Tests/SwiftROS2CDRTests"
    ),
    .testTarget(
        name: "SwiftROS2WireTests",
        dependencies: ["SwiftROS2Wire"],
        path: "Tests/SwiftROS2WireTests"
    ),
    .testTarget(
        name: "SwiftROS2ZenohTests",
        dependencies: ["SwiftROS2Zenoh"],
        path: "Tests/SwiftROS2ZenohTests"
    ),
    .testTarget(
        name: "SwiftROS2TransportTests",
        dependencies: ["SwiftROS2Transport", "SwiftROS2Wire"],
        path: "Tests/SwiftROS2TransportTests"
    ),
]

// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable.
// Windows and Android do not build CycloneDDS from source (SPM cannot
// orchestrate the ddsrt CMake configure-time header generation), so
// both platforms import SwiftROS2Zenoh directly instead of the
// SwiftROS2 umbrella. DDS on Windows / Android is a future track.
if !isWindowsBuild && !isAndroidBuild {
    let cCycloneDDS: Target = {
        if isLinuxBuild {
            return .systemLibrary(
                name: "CCycloneDDS",
                path: "Sources/CCycloneDDS",
                pkgConfig: "CycloneDDS"
            )
        } else {
            return .binaryTarget(
                name: "CCycloneDDS",
                url: "\(releaseBaseURL)/CCycloneDDS.xcframework.zip",
                checksum: "113ce8a9b89428b15e738775b10fe043e90bca38e1738ac19020c6d610908803"
            )
        }
    }()

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
            cSettings: [
                .define("DDS_AVAILABLE", to: "1")
            ]
        ),

        .target(
            name: "SwiftROS2DDS",
            dependencies: ["CDDSBridge", "SwiftROS2Transport", "SwiftROS2Wire"],
            path: "Sources/SwiftROS2DDS"
        ),

        // Public API umbrella: Context, Node, Publisher, Subscription
        .target(
            name: "SwiftROS2",
            dependencies: [
                "SwiftROS2Messages",
                "SwiftROS2Transport",
                "SwiftROS2Wire",
                "SwiftROS2Zenoh",
                "SwiftROS2DDS",
            ],
            path: "Sources/SwiftROS2"
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

        .testTarget(
            name: "SwiftROS2Tests",
            dependencies: ["SwiftROS2", "SwiftROS2Messages", "SwiftROS2CDR"],
            path: "Tests/SwiftROS2Tests"
        ),
        .testTarget(
            name: "SwiftROS2DDSTests",
            dependencies: ["SwiftROS2DDS"],
            path: "Tests/SwiftROS2DDSTests"
        ),
        .testTarget(
            name: "SwiftROS2IntegrationTests",
            dependencies: ["SwiftROS2", "SwiftROS2Messages", "SwiftROS2Transport"],
            path: "Tests/SwiftROS2IntegrationTests"
        ),
    ])
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

let packageDependencies: [Package.Dependency] =
    isDocsBuild
    ? [.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.3.0")]
    : []

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
