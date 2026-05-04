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

    @Test("constructs a nested field with same-package and cross-package references")
    func constructsNested() {
        let samePkg = IDLField(name: "linear", type: .nested(package: nil, typeName: "Vector3"), sourceLine: 1)
        let crossPkg = IDLField(
            name: "header",
            type: .nested(package: "std_msgs", typeName: "Header"),
            sourceLine: 2
        )
        let file = IDLFile(package: "geometry_msgs", typeName: "Twist", fields: [samePkg, crossPkg])
        #expect(file.fields[0].type == .nested(package: nil, typeName: "Vector3"))
        #expect(file.fields[1].type == .nested(package: "std_msgs", typeName: "Header"))
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
                source: "123bogus field\n",
                file: "Foo.msg",
                package: "geometry_msgs",
                typeName: "Foo"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.line == 1)
            #expect(error.message.contains("123bogus"))
            #expect(error.message.contains("unsupported type"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }

    @Test("parses a same-package nested field")
    func parsesSamePackageNested() throws {
        let source = "Vector3 linear\n"
        let file = try Parser.parseMessage(
            source: source, file: "Twist.msg", package: "geometry_msgs", typeName: "Twist"
        )
        #expect(file.fields.count == 1)
        #expect(file.fields[0].name == "linear")
        #expect(file.fields[0].type == .nested(package: nil, typeName: "Vector3"))
    }

    @Test("parses a cross-package nested field")
    func parsesCrossPackageNested() throws {
        let source = "std_msgs/Header header\n"
        let file = try Parser.parseMessage(
            source: source, file: "PoseStamped.msg", package: "geometry_msgs", typeName: "PoseStamped"
        )
        #expect(file.fields.count == 1)
        #expect(file.fields[0].type == .nested(package: "std_msgs", typeName: "Header"))
    }

    @Test("parses a builtin_interfaces/Time reference")
    func parsesBuiltinInterfacesTime() throws {
        let source = "builtin_interfaces/Time stamp\n"
        let file = try Parser.parseMessage(
            source: source, file: "Header.msg", package: "std_msgs", typeName: "Header"
        )
        #expect(file.fields[0].type == .nested(package: "builtin_interfaces", typeName: "Time"))
    }

    @Test("rejects a lower-case unknown identifier")
    func rejectsLowercaseUnknown() {
        do {
            _ = try Parser.parseMessage(
                source: "header header\n", file: "Foo.msg", package: "x", typeName: "Foo"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.message.contains("unsupported type"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }

    @Test("rejects an array suffix (Phase 3 territory)")
    func rejectsArraySuffix() {
        do {
            _ = try Parser.parseMessage(
                source: "Vector3[] points\n", file: "Polygon.msg", package: "geometry_msgs", typeName: "Polygon"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.message.contains("array"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }
}
