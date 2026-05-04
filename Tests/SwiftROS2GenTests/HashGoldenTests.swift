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

@Suite("RIHS01 golden hashes for nested types")
struct NestedHashGoldenTests {
    /// Authored from `osrf/ros:jazzy-desktop`
    /// (`/opt/ros/jazzy/share/<pkg>/msg/<Type>.json` `type_hashes[0].hash_string`).
    static let timeHash = "RIHS01_b106235e25a4c5ed35098aa0a61a3ee9c9b18d197f398b0e4206cea9acf9c197"
    static let durationHash =
        "RIHS01_e8d009f659816f758b75334ee1a9ca5b5c0b859843261f14c7f937349599d93b"
    static let headerHash =
        "RIHS01_f49fb3ae2cf070f793645ff749683ac6b06203e41c891e17701b1cb597ce6a01"
    static let vector3Hash =
        "RIHS01_cc12fe83e4c02719f1ce8070bfd14aecd40f75a96696a67a2a1f37f7dbb0765d"
    static let quaternionHash =
        "RIHS01_8a765f66778c8ff7c8ab94afcc590a2ed5325a1d9a076ffff38fbce36f458684"
    static let pointHash =
        "RIHS01_6963084842a9b04494d6b2941d11444708d892da2f4b09843b9c43f42a7f6881"
    static let poseHash =
        "RIHS01_d501954e9476cea2996984e812054b68026ae0bfae789d9a10b23daf35cc90fa"
    static let twistHash =
        "RIHS01_9c45bf16fe0983d80e3cfe750d6835843d265a9a6c46bd2e609fcddde6fb8d2a"
    static let transformHash =
        "RIHS01_beb83fbe698636351461f6f35d1abb20010c43d55374d81bd041f1ba2581fddc"

    static func registry() -> [String: MessageIR] {
        let time = MessageIR(
            package: "builtin_interfaces", typeName: "Time",
            fields: [
                FieldIR(ros2Name: "sec", swiftName: "sec", type: .primitive(.int32)),
                FieldIR(ros2Name: "nanosec", swiftName: "nanosec", type: .primitive(.uint32)),
            ]
        )
        let duration = MessageIR(
            package: "builtin_interfaces", typeName: "Duration",
            fields: [
                FieldIR(ros2Name: "sec", swiftName: "sec", type: .primitive(.int32)),
                FieldIR(ros2Name: "nanosec", swiftName: "nanosec", type: .primitive(.uint32)),
            ]
        )
        let vector3 = MessageIR(
            package: "geometry_msgs", typeName: "Vector3",
            fields: [
                FieldIR(ros2Name: "x", swiftName: "x", type: .primitive(.float64)),
                FieldIR(ros2Name: "y", swiftName: "y", type: .primitive(.float64)),
                FieldIR(ros2Name: "z", swiftName: "z", type: .primitive(.float64)),
            ]
        )
        let quaternion = MessageIR(
            package: "geometry_msgs", typeName: "Quaternion",
            fields: [
                FieldIR(ros2Name: "x", swiftName: "x", type: .primitive(.float64)),
                FieldIR(ros2Name: "y", swiftName: "y", type: .primitive(.float64)),
                FieldIR(ros2Name: "z", swiftName: "z", type: .primitive(.float64)),
                FieldIR(ros2Name: "w", swiftName: "w", type: .primitive(.float64)),
            ]
        )
        let point = MessageIR(
            package: "geometry_msgs", typeName: "Point",
            fields: [
                FieldIR(ros2Name: "x", swiftName: "x", type: .primitive(.float64)),
                FieldIR(ros2Name: "y", swiftName: "y", type: .primitive(.float64)),
                FieldIR(ros2Name: "z", swiftName: "z", type: .primitive(.float64)),
            ]
        )
        let pose = MessageIR(
            package: "geometry_msgs", typeName: "Pose",
            fields: [
                FieldIR(
                    ros2Name: "position", swiftName: "position",
                    type: .nested(package: "geometry_msgs", typeName: "Point")),
                FieldIR(
                    ros2Name: "orientation", swiftName: "orientation",
                    type: .nested(package: "geometry_msgs", typeName: "Quaternion")),
            ]
        )
        let twist = MessageIR(
            package: "geometry_msgs", typeName: "Twist",
            fields: [
                FieldIR(
                    ros2Name: "linear", swiftName: "linear",
                    type: .nested(package: "geometry_msgs", typeName: "Vector3")),
                FieldIR(
                    ros2Name: "angular", swiftName: "angular",
                    type: .nested(package: "geometry_msgs", typeName: "Vector3")),
            ]
        )
        let transform = MessageIR(
            package: "geometry_msgs", typeName: "Transform",
            fields: [
                FieldIR(
                    ros2Name: "translation", swiftName: "translation",
                    type: .nested(package: "geometry_msgs", typeName: "Vector3")),
                FieldIR(
                    ros2Name: "rotation", swiftName: "rotation",
                    type: .nested(package: "geometry_msgs", typeName: "Quaternion")),
            ]
        )
        let header = MessageIR(
            package: "std_msgs", typeName: "Header",
            fields: [
                FieldIR(
                    ros2Name: "stamp", swiftName: "stamp",
                    type: .nested(package: "builtin_interfaces", typeName: "Time")),
                FieldIR(ros2Name: "frame_id", swiftName: "frameId", type: .primitive(.string)),
            ]
        )
        return [
            time.rosTypeName: time,
            duration.rosTypeName: duration,
            vector3.rosTypeName: vector3,
            quaternion.rosTypeName: quaternion,
            point.rosTypeName: point,
            pose.rosTypeName: pose,
            twist.rosTypeName: twist,
            transform.rosTypeName: transform,
            header.rosTypeName: header,
        ]
    }

    @Test("Time has no nested deps") func time() {
        let reg = Self.registry()
        let ir = reg["builtin_interfaces/msg/Time"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.timeHash)
    }
    @Test("Duration has no nested deps") func duration() {
        let reg = Self.registry()
        let ir = reg["builtin_interfaces/msg/Duration"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.durationHash)
    }
    @Test("Vector3 has no nested deps") func vector3() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Vector3"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.vector3Hash)
    }
    @Test("Quaternion has no nested deps") func quaternion() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Quaternion"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.quaternionHash)
    }
    @Test("Point has no nested deps") func point() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Point"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.pointHash)
    }
    @Test("Pose references Point + Quaternion") func pose() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Pose"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.poseHash)
    }
    @Test("Twist references Vector3 twice (deduped)") func twist() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Twist"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.twistHash)
    }
    @Test("Transform references Vector3 + Quaternion") func transform() {
        let reg = Self.registry()
        let ir = reg["geometry_msgs/msg/Transform"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.transformHash)
    }
    @Test("Header references builtin_interfaces/Time across packages") func header() {
        let reg = Self.registry()
        let ir = reg["std_msgs/msg/Header"]!
        #expect(RIHS01.hash(ir, registry: reg) == Self.headerHash)
    }
}
