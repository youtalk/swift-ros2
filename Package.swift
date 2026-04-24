// swift-tools-version: 5.9

import PackageDescription

// All platforms: pre-built binaryTargets hosted on GitHub Releases.
// Apple platforms receive xcframeworks; Linux receives artifactbundles.
// See Scripts/build-xcframework.sh for the Apple xcframework build helper.
let artifactBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.5.0-rc.2"

let cZenohPico: Target = {
    #if os(Linux)
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(artifactBaseURL)/CZenohPico-linux.artifactbundle.zip",
            checksum: "091a9d48841223517e66e395f0b3651d16790044d3d839d611fde96be82f2401"
        )
    #else
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(artifactBaseURL)/CZenohPico.xcframework.zip",
            checksum: "0256d023bc1a4518ccb1d642251dfbcc1e3a9280f2d7c2c9ac3c9083cf914b97"
        )
    #endif
}()

let cCycloneDDS: Target = {
    #if os(Linux)
        return .binaryTarget(
            name: "CCycloneDDS",
            url: "\(artifactBaseURL)/CCycloneDDS-linux.artifactbundle.zip",
            checksum: "b5f3294090f75cbad10cfdbb741bf6c2753879e5979441afeb5721235c03bb0a"
        )
    #else
        return .binaryTarget(
            name: "CCycloneDDS",
            url: "\(artifactBaseURL)/CCycloneDDS.xcframework.zip",
            checksum: "7a6513a1c881968da091bb77a3a1d44f5fc014671e139a87c16950af32c0cc2b"
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

        // Native C FFI: zenoh-pico + CycloneDDS. All platforms receive
        // pre-built binaryTargets (xcframeworks on Apple, artifactbundles on Linux).
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
