import Testing

@testable import SwiftROS2Gen

@Suite("RIHS01 golden hashes for std_msgs primitives")
struct HashGoldenTests {
    /// These hashes are copied verbatim from the existing
    /// `Sources/SwiftROS2Messages/BuiltinMessages/StdMsgs/StdMsgs.swift`,
    /// which were authored from `ros2 interface show --type-description-hashes`
    /// against ROS 2 jazzy. They are the source of truth for Phase 1.
    static let golden: [(typeName: String, primitive: PrimitiveType?, hash: String)] = [
        (
            "Bool", .bool,
            "RIHS01_feb91e995ff9ebd09c0cb3d2aed18b11077585839fb5db80193b62d74528f6c9"
        ),
        (
            "Empty", nil,
            "RIHS01_20b625256f32d5dbc0d04fee44f43c41e51c70d3502f84b4a08e7a9c26a96312"
        ),
        (
            "Float64", .float64,
            "RIHS01_705ba9c3d1a09df43737eb67095534de36fd426c0587779bda2bc51fe790182a"
        ),
        (
            "Int32", .int32,
            "RIHS01_b6578ded3c58c626cfe8d1a6fb6e04f706f97e9f03d2727c9ff4e74b1cef0deb"
        ),
        (
            "String", .string,
            "RIHS01_df668c740482bbd48fb39d76a70dfd4bd59db1288021743503259e948f6b1a18"
        ),
    ]

    @Test(
        "matches authored hash for every std_msgs primitive wrapper",
        arguments: golden
    )
    func matchesGolden(
        _ entry: (typeName: String, primitive: PrimitiveType?, hash: String)
    ) {
        let fields: [FieldIR]
        if let prim = entry.primitive {
            fields = [FieldIR(ros2Name: "data", swiftName: "data", type: .primitive(prim))]
        } else {
            fields = []
        }
        let ir = MessageIR(package: "std_msgs", typeName: entry.typeName, fields: fields)
        let hash = RIHS01.hash(ir)
        #expect(hash == entry.hash, "for std_msgs/\(entry.typeName)")
    }
}
