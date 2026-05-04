import Testing

@testable import SwiftROS2Gen

@Suite("IRBuilder — Phase 2 resolution")
struct IRBuilderTests {
    @Test("converts snake_case field names to camelCase")
    func convertsSnakeCase() {
        let idl = IDLFile(
            package: "std_msgs",
            typeName: "Bool",
            fields: [
                IDLField(name: "linear_acceleration_x", type: .primitive(.float64), sourceLine: 1),
                IDLField(name: "data", type: .primitive(.bool), sourceLine: 2),
                IDLField(name: "_leading_underscore", type: .primitive(.int32), sourceLine: 3),
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].swiftName == "linearAccelerationX")
        #expect(ir.fields[1].swiftName == "data")
        #expect(ir.fields[2].swiftName == "_leadingUnderscore")
        #expect(ir.rosTypeName == "std_msgs/msg/Bool")
    }

    @Test("resolves a same-package nested reference to the IDL's owning package")
    func resolvesSamePackage() {
        let idl = IDLFile(
            package: "geometry_msgs",
            typeName: "Twist",
            fields: [
                IDLField(name: "linear", type: .nested(package: nil, typeName: "Vector3"), sourceLine: 1),
                IDLField(name: "angular", type: .nested(package: nil, typeName: "Vector3"), sourceLine: 2),
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].type == .nested(package: "geometry_msgs", typeName: "Vector3"))
        #expect(ir.fields[1].type == .nested(package: "geometry_msgs", typeName: "Vector3"))
    }

    @Test("preserves cross-package references verbatim")
    func preservesCrossPackage() {
        let idl = IDLFile(
            package: "geometry_msgs",
            typeName: "PoseStamped",
            fields: [
                IDLField(name: "header", type: .nested(package: "std_msgs", typeName: "Header"), sourceLine: 1),
                IDLField(name: "pose", type: .nested(package: nil, typeName: "Pose"), sourceLine: 2),
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].type == .nested(package: "std_msgs", typeName: "Header"))
        #expect(ir.fields[1].type == .nested(package: "geometry_msgs", typeName: "Pose"))
    }
}
