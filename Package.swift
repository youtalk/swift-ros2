// swift-tools-version: 5.9

import PackageDescription

// Apple platforms: pre-built xcframework binaryTargets hosted on
// GitHub Releases. Linux: compile the C sources directly via SPM (+ a
// system-installed libddsc via pkg-config). See Scripts/build-xcframework.sh
// for the macOS build helper that produces the Apple artifacts.
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.3.1"

let cZenohPico: Target = {
    #if os(Linux)
        return .target(
            name: "CZenohPico",
            path: "vendor/zenoh-pico",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE", "tests", "examples", "docs", "ci",
                // Non-Linux platform backends. SPM compiles everything under
                // `sources: ["src"]` unless excluded. zenoh-pico's CMake build
                // picks the right backend per platform; for SPM + Linux we hand-
                // pick src/system/unix and drop the rest.
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
    #else
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(xcframeworkBaseURL)/CZenohPico.xcframework.zip",
            checksum: "05a0735f448f0f0b189d8dcb5a5e305a4129af1a6963359cc393bf19457c23b2"
        )
    #endif
}()

let cCycloneDDS: Target = {
    #if os(Linux)
        return .systemLibrary(
            name: "CCycloneDDS",
            path: "Sources/CCycloneDDS",
            pkgConfig: "CycloneDDS"
        )
    #else
        return .binaryTarget(
            name: "CCycloneDDS",
            url: "\(xcframeworkBaseURL)/CCycloneDDS.xcframework.zip",
            checksum: "5d83fca379bc7440d4679e1b861cd6f8c136988a74e5748cb32e1bb860814629"
        )
    #endif
}()

let package = Package(
    name: "swift-ros2",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "SwiftROS2", targets: ["SwiftROS2"]),
        .library(name: "SwiftROS2CDR", targets: ["SwiftROS2CDR"]),
        .library(name: "SwiftROS2Messages", targets: ["SwiftROS2Messages"]),
        .library(name: "SwiftROS2Wire", targets: ["SwiftROS2Wire"]),
        .library(name: "SwiftROS2Transport", targets: ["SwiftROS2Transport"]),
        .library(name: "SwiftROS2Zenoh", targets: ["SwiftROS2Zenoh"]),
        .library(name: "SwiftROS2DDS", targets: ["SwiftROS2DDS"]),
    ],
    targets: [
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

        // Native C FFI: zenoh-pico + CycloneDDS. Apple platforms receive
        // pre-built xcframeworks; Linux compiles from source (zenoh-pico)
        // and links via pkg-config (CycloneDDS).
        cZenohPico,
        cCycloneDDS,

        // C bridges (Conduit-authored FFI shims that simplify the zenoh-pico
        // and CycloneDDS APIs for Swift callers).
        .target(
            name: "CZenohBridge",
            dependencies: ["CZenohPico"],
            path: "Sources/CZenohBridge",
            sources: ["zenoh_bridge.c"],
            publicHeadersPath: "include",
            cSettings: [
                .define("ZENOH_MACOS", to: "1", .when(platforms: [.macOS, .macCatalyst, .iOS, .visionOS])),
                .define("ZENOH_LINUX", to: "1", .when(platforms: [.linux])),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
            ]
        ),
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

        // Swift-facing Zenoh / DDS modules. Host ZenohClient / DDSClient,
        // the default implementations of the ZenohClientProtocol /
        // DDSClientProtocol seams defined in SwiftROS2Transport.
        .target(
            name: "SwiftROS2Zenoh",
            dependencies: ["CZenohBridge", "SwiftROS2Transport", "SwiftROS2Wire"],
            path: "Sources/SwiftROS2Zenoh"
        ),
        .target(
            name: "SwiftROS2DDS",
            dependencies: ["CDDSBridge", "SwiftROS2Transport", "SwiftROS2Wire"],
            path: "Sources/SwiftROS2DDS"
        ),

        // Public API: Context, Node, Publisher, Subscription
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

        // Tests
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
            name: "SwiftROS2Tests",
            dependencies: ["SwiftROS2", "SwiftROS2Messages", "SwiftROS2CDR"],
            path: "Tests/SwiftROS2Tests"
        ),
        .testTarget(
            name: "SwiftROS2ZenohTests",
            dependencies: ["SwiftROS2Zenoh"],
            path: "Tests/SwiftROS2ZenohTests"
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
    ]
)
