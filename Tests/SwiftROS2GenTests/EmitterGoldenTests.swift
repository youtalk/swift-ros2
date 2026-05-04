import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("SwiftEmitter golden output")
struct EmitterGoldenTests {
    static let cases: [(typeName: String, primitive: PrimitiveType?, hash: String)] = [
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

    @Test("matches golden Swift output for every std_msgs primitive wrapper", arguments: cases)
    func matches(_ c: (typeName: String, primitive: PrimitiveType?, hash: String)) throws {
        let fields: [FieldIR] =
            c.primitive.map {
                [FieldIR(ros2Name: "data", swiftName: "data", type: .primitive($0))]
            } ?? []
        let ir = MessageIR(
            package: "std_msgs",
            typeName: c.typeName,
            fields: fields,
            perDistroHashes: ["jazzy": c.hash]
        )
        let actual = SwiftEmitter.emit(
            ir,
            sourceLabel: "common_interfaces-jazzy/std_msgs/msg/\(c.typeName).msg"
        )
        let goldenURL = try #require(
            Bundle.module.url(
                forResource: c.typeName,
                withExtension: "swift",
                subdirectory: "Resources/Golden"
            )
        )
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(actual == golden, "emit mismatch for std_msgs/\(c.typeName)")
    }
}
