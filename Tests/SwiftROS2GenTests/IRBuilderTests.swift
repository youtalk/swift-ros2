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

    @Test("translates fixed array IDL into FieldType.array")
    func translatesArray() {
        let idl = IDLFile(
            package: "unique_identifier_msgs",
            typeName: "UUID",
            fields: [
                IDLField(
                    name: "uuid",
                    type: .array(element: .primitive(.uint8), length: 16),
                    sourceLine: 1
                )
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].type == .array(element: .primitive(.uint8), length: 16))
    }

    @Test("parses int default into DefaultValue.int")
    func parsesIntDefault() {
        let idl = IDLFile(
            package: "fake_pkg",
            typeName: "Foo",
            fields: [
                IDLField(
                    name: "n",
                    type: .primitive(.int32),
                    defaultExpression: "42",
                    sourceLine: 1
                )
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].defaultValue == .int(42))
    }

    @Test("parses array default into DefaultValue.array")
    func parsesArrayDefault() {
        let idl = IDLFile(
            package: "fake_pkg",
            typeName: "Foo",
            fields: [
                IDLField(
                    name: "xyz",
                    type: .array(element: .primitive(.float64), length: 3),
                    defaultExpression: "[1.0, 2.0, 3.0]",
                    sourceLine: 1
                )
            ]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.fields[0].defaultValue == .array([.float(1.0), .float(2.0), .float(3.0)]))
    }

    @Test("validates constant int range and stores DefaultValue")
    func validatesConstantRange() throws {
        let idl = IDLFile(
            package: "action_msgs",
            typeName: "GoalStatus",
            fields: [],
            constants: [IDLConstant(name: "STATUS_UNKNOWN", type: .int8, value: "0", sourceLine: 1)]
        )
        let ir = IRBuilder.build(jazzy: idl)
        #expect(ir.constants[0].value == .int(0))
    }

    @Test("rejects out-of-range int constant")
    func rejectsOutOfRangeConstant() {
        let idl = IDLFile(
            package: "fake_pkg",
            typeName: "Foo",
            fields: [],
            constants: [IDLConstant(name: "TOO_BIG", type: .int8, value: "200", sourceLine: 1)]
        )
        do {
            _ = try IRBuilder.buildOrThrow(jazzy: idl)
            Issue.record("expected range-validation error")
        } catch let error as IRBuildError {
            #expect(error.message.contains("TOO_BIG"))
            #expect(error.message.contains("int8"))
        } catch {
            Issue.record("expected IRBuildError, got \(error)")
        }
    }
}
