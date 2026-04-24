// swift-tools-version: 5.9

import PackageDescription

// Apple platforms: pre-built xcframework binaryTargets hosted on
// GitHub Releases. Linux: compile the C sources directly via SPM (+ a
// system-installed libddsc via pkg-config). See Scripts/build-xcframework.sh
// for the macOS build helper that produces the Apple artifacts.
let xcframeworkBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.4.0"

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
                .define("ZENOH_WINDOWS", to: "1", .when(platforms: [.windows])),
                .define("Z_FEATURE_LINK_TCP", to: "1"),
                .define("Z_FEATURE_LIVELINESS", to: "1"),
            ],
            linkerSettings: [
                .linkedLibrary("Ws2_32", .when(platforms: [.windows])),
                .linkedLibrary("Iphlpapi", .when(platforms: [.windows])),
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
