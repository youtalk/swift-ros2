import Testing

@testable import SwiftROS2Gen

@Suite("PrimitiveType")
struct PrimitiveTypeTests {
    @Test("parses every ROS 2 primitive name")
    func parsesEveryPrimitive() {
        let pairs: [(String, PrimitiveType)] = [
            ("bool", .bool), ("byte", .byte), ("char", .char),
            ("int8", .int8), ("uint8", .uint8),
            ("int16", .int16), ("uint16", .uint16),
            ("int32", .int32), ("uint32", .uint32),
            ("int64", .int64), ("uint64", .uint64),
            ("float32", .float32), ("float64", .float64),
            ("string", .string), ("wstring", .wstring),
        ]
        for (raw, expected) in pairs {
            #expect(PrimitiveType(rawROS: raw) == expected, "mismatch for \(raw)")
        }
    }

    @Test("returns nil for non-primitive identifiers")
    func returnsNilForNonPrimitive() {
        #expect(PrimitiveType(rawROS: "Header") == nil)
        #expect(PrimitiveType(rawROS: "geometry_msgs/Vector3") == nil)
        #expect(PrimitiveType(rawROS: "") == nil)
    }
}

@Suite("IDLFile AST")
struct IDLFileTests {
    @Test("constructs and round-trips equality")
    func constructs() {
        let f = IDLField(name: "data", type: .primitive(.bool), sourceLine: 1)
        let file = IDLFile(package: "std_msgs", typeName: "Bool", fields: [f])
        #expect(file.fields.count == 1)
        #expect(file.fields[0].type == .primitive(.bool))
        #expect(file == IDLFile(package: "std_msgs", typeName: "Bool", fields: [f]))
    }
}

@Suite("IRBuilder")
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
        #expect(ir.fields[0].ros2Name == "linear_acceleration_x")
        #expect(ir.fields[0].swiftName == "linearAccelerationX")
        #expect(ir.fields[1].swiftName == "data")
        #expect(ir.fields[2].swiftName == "_leadingUnderscore")
        #expect(ir.package == "std_msgs")
        #expect(ir.typeName == "Bool")
        #expect(ir.rosTypeName == "std_msgs/msg/Bool")
    }
}

@Suite("Parser")
struct ParserTests {
    @Test("parses a single primitive field")
    func parsesSingleField() throws {
        let source = "bool data\n"
        let file = try Parser.parseMessage(
            source: source,
            file: "std_msgs/msg/Bool.msg",
            package: "std_msgs",
            typeName: "Bool"
        )
        #expect(file.package == "std_msgs")
        #expect(file.typeName == "Bool")
        #expect(file.fields.count == 1)
        #expect(file.fields[0].name == "data")
        #expect(file.fields[0].type == .primitive(.bool))
        #expect(file.fields[0].sourceLine == 1)
    }

    @Test("ignores comments and blank lines")
    func ignoresCommentsAndBlanks() throws {
        let source = """
            # This is a license header
            #
            # Multiple comment lines.

            bool data    # trailing comment

            """
        let file = try Parser.parseMessage(
            source: source,
            file: "Bool.msg",
            package: "std_msgs",
            typeName: "Bool"
        )
        #expect(file.fields.count == 1)
        #expect(file.fields[0].sourceLine == 5)
    }

    @Test("parses an empty .msg as zero-field message")
    func parsesEmptyFile() throws {
        let file = try Parser.parseMessage(
            source: "# only a comment\n",
            file: "Empty.msg",
            package: "std_msgs",
            typeName: "Empty"
        )
        #expect(file.fields.isEmpty)
    }

    @Test("rejects a non-primitive type with an actionable error")
    func rejectsNonPrimitive() {
        do {
            _ = try Parser.parseMessage(
                source: "Header header\n",
                file: "Foo.msg",
                package: "geometry_msgs",
                typeName: "Foo"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.line == 1)
            #expect(error.message.contains("Header"))
            #expect(error.message.contains("primitive"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }
}
