// swift-tools-version: 5.9

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
// both platforms by the #if !os(Windows) && !os(Android) gate around
// the targets/products additions further down.
let releaseBaseURL = "https://github.com/youtalk/swift-ros2/releases/download/0.4.0"

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
        return .binaryTarget(
            name: "CZenohPico",
            url: "\(releaseBaseURL)/CZenohPico.xcframework.zip",
            checksum: "de7d7a02605234d364a464fb0169bc18efb46440976b8e8a26021eb416386c95"
        )
    #endif
}()

#if !os(Windows) && !os(Android)
    // The DDS path is compiled out on Windows and Android entirely, so
    // cCycloneDDS is not defined there — no closure evaluation, no stale
    // placeholder .binaryTarget construction. Android is carved out for
    // the same reason Windows is: SwiftPM cannot orchestrate CycloneDDS's
    // ddsrt CMake-configure-time header generation, and no usable
    // prebuilt .binaryTarget path exists yet.
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
                url: "\(releaseBaseURL)/CCycloneDDS.xcframework.zip",
                checksum: "bc72071590791fcb989a69af616c1da771f9c6d79b50de4381d8e95ce33fc8ad"
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
    // xcframework; Linux and Windows compile from source using the matching
    // platform backend inside vendor/zenoh-pico.
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
]

// DDS path + the SwiftROS2 umbrella + examples + umbrella-level tests.
// These are only included on platforms where CycloneDDS is consumable.
// Windows and Android do not build CycloneDDS from source (SPM cannot
// orchestrate the ddsrt CMake configure-time header generation), so
// both platforms import SwiftROS2Zenoh directly instead of the
// SwiftROS2 umbrella. DDS on Windows / Android is a future track.
#if !os(Windows) && !os(Android)
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
