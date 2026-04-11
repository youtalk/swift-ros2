// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "rclswift",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "RclSwift", targets: ["RclSwift"]),
        .library(name: "RclSwiftCDR", targets: ["RclSwiftCDR"]),
        .library(name: "RclSwiftMessages", targets: ["RclSwiftMessages"]),
        .library(name: "RclSwiftWire", targets: ["RclSwiftWire"]),
        .library(name: "RclSwiftTransport", targets: ["RclSwiftTransport"]),
    ],
    targets: [
        // CDR serialization (pure Swift, no dependencies)
        .target(
            name: "RclSwiftCDR",
            path: "Sources/RclSwiftCDR"
        ),

        // Wire format codecs (no dependencies)
        .target(
            name: "RclSwiftWire",
            path: "Sources/RclSwiftWire"
        ),

        // Message protocols and built-in types
        .target(
            name: "RclSwiftMessages",
            dependencies: ["RclSwiftCDR"],
            path: "Sources/RclSwiftMessages"
        ),

        // Transport abstraction layer
        .target(
            name: "RclSwiftTransport",
            dependencies: ["RclSwiftCDR", "RclSwiftWire"],
            path: "Sources/RclSwiftTransport"
        ),

        // Public API: Context, Node, Publisher, Subscription
        .target(
            name: "RclSwift",
            dependencies: [
                "RclSwiftMessages",
                "RclSwiftTransport",
                "RclSwiftWire",
            ],
            path: "Sources/RclSwift"
        ),

        // Tests
        .testTarget(
            name: "RclSwiftCDRTests",
            dependencies: ["RclSwiftCDR"],
            path: "Tests/RclSwiftCDRTests"
        ),
        .testTarget(
            name: "RclSwiftWireTests",
            dependencies: ["RclSwiftWire"],
            path: "Tests/RclSwiftWireTests"
        ),
        .testTarget(
            name: "RclSwiftTests",
            dependencies: ["RclSwift", "RclSwiftMessages", "RclSwiftCDR"],
            path: "Tests/RclSwiftTests"
        ),
    ]
)
