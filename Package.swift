// swift-tools-version: 5.9

import PackageDescription

// Apple + Linux: pre-built binaryTargets hosted on GitHub Releases
// (xcframeworks on Apple, .artifactbundle static libraries on Linux x86_64
// + aarch64). Windows: compiles C sources directly via SPM using the
// Windows backend inside vendor/zenoh-pico; DDS path is compiled out on
// Windows (M3 will settle that story). See Scripts/build-xcframework.sh
// for the Apple xcframework build helper and Scripts/build-linux-artifactbundle.sh
// + Scripts/merge-linux-artifactbundle.sh for the Linux side.
let artifactBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.5.0"

let cZenohPico: Target = {
    #if os(Linux)
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(artifactBaseURL)/CZenohPico-linux.artifactbundle.zip",
            checksum: "d39d3729ed7c0d539b62d59d8bb8dbc353b62338ebb47ad7e8cfa6594cc938a2"
        )
    #elseif os(Windows)
        return .target(
            name: "CZenohPico",
            path: "vendor/zenoh-pico",
            exclude: [
                "CMakeLists.txt", "README.md", "LICENSE", "tests", "examples", "docs", "ci",
                // Non-Windows platform backends — parallel to the Linux arm
                // above, just with src/system/unix excluded and
                // src/system/windows kept.
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
    #else
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(artifactBaseURL)/CZenohPico.xcframework.zip",
            checksum: "e55f70446c6f4c2dbf2bf9983996e6bbd901f4048a019fb76bd1b62db6e9bf1e"
        )
    #endif
}()

#if !os(Windows)
    // The DDS path is compiled out on Windows entirely, so cCycloneDDS
    // is not defined there — no closure evaluation, no stale placeholder
    // .binaryTarget construction.
    let cCycloneDDS: Target = {
        #if os(Linux)
            return .binaryTarget(
                name: "CCycloneDDS",
                url: "\(artifactBaseURL)/CCycloneDDS-linux.artifactbundle.zip",
                checksum: "790a02942c8b277001e499f40f21686d7e8f97270b1c004039f08ca844e095ad"
            )
        #else
            return .binaryTarget(
                name: "CCycloneDDS",
                url: "\(artifactBaseURL)/CCycloneDDS.xcframework.zip",
                checksum: "4e9d2ff8caacb64b64133b11e07b6a784966429b70826bdee02644e75fa14ca9"
            )
        #endif
    }()
#endif

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
    // xcframework; Linux receives a pre-built .artifactbundle; Windows
    // compiles from source using the Windows backend inside vendor/zenoh-pico.
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
]

// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable.
// Windows will join once M3 settles the DDS-on-Windows story; for now,
// Windows users should import SwiftROS2Zenoh directly instead of the
// SwiftROS2 umbrella.
#if !os(Windows)
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
#endif

let package = Package(
    name: "swift-ros2",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .macCatalyst(.v16),
        .visionOS(.v1),
    ],
    products: products,
    targets: targets
)
