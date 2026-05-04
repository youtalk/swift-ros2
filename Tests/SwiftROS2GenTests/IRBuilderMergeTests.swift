import Testing

@testable import SwiftROS2Gen

@Suite("IRBuilder.build(perDistro:)")
struct IRBuilderMergeTests {
    /// Build an `IDLFile` containing the given primitive fields in source order.
    private func makeIDL(
        package: String,
        typeName: String,
        primitives: [(String, PrimitiveType)]
    ) -> IDLFile {
        let fields = primitives.enumerated().map { index, pair in
            IDLField(name: pair.0, type: .primitive(pair.1), sourceLine: index + 1)
        }
        return IDLFile(package: package, typeName: typeName, fields: fields)
    }

    @Test("field added in later distro is .onlyIn that distro and its successors")
    func fieldAddedInLaterDistro() throws {
        let humble = makeIDL(
            package: "sensor_msgs", typeName: "Range",
            primitives: [
                ("min_range", .float32), ("max_range", .float32), ("range", .float32),
            ])
        let jazzy = makeIDL(
            package: "sensor_msgs", typeName: "Range",
            primitives: [
                ("min_range", .float32), ("max_range", .float32), ("range", .float32),
                ("variance", .float32),
            ])
        let ir = try IRBuilder.build(perDistro: ["humble": humble, "jazzy": jazzy])
        #expect(ir.fields.count == 4)
        #expect(ir.fields.map(\.ros2Name) == ["min_range", "max_range", "range", "variance"])
        for i in 0..<3 {
            #expect(ir.fields[i].availability == .all, "field \(ir.fields[i].ros2Name)")
        }
        #expect(ir.fields[3].availability == .onlyIn(["jazzy"]))
        #expect(ir.perDistroFieldPresence["humble"] == ["min_range", "max_range", "range"])
        #expect(ir.perDistroFieldPresence["jazzy"]?.count == 4)
    }

    @Test("field removed in later distro is .onlyIn earlier distro")
    func fieldRemovedInLaterDistro() throws {
        let humble = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("a", .int32), ("legacy", .int32), ("b", .int32)])
        let jazzy = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("a", .int32), ("b", .int32)])
        let ir = try IRBuilder.build(perDistro: ["humble": humble, "jazzy": jazzy])
        #expect(ir.fields.map(\.ros2Name) == ["a", "legacy", "b"])
        #expect(ir.fields[0].availability == .all)
        #expect(ir.fields[1].availability == .onlyIn(["humble"]))
        #expect(ir.fields[2].availability == .all)
    }

    @Test("breaking type change throws conflictingFieldType")
    func breakingTypeChangeThrows() {
        let humble = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("payload", .int32)])
        let jazzy = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("payload", .int64)])
        do {
            _ = try IRBuilder.build(perDistro: ["humble": humble, "jazzy": jazzy])
            Issue.record("expected IRMergeError")
        } catch let error as IRMergeError {
            switch error.kind {
            case .conflictingFieldType(let name, let perDistroTypes):
                #expect(name == "payload")
                #expect(perDistroTypes["humble"] == .primitive(.int32))
                #expect(perDistroTypes["jazzy"] == .primitive(.int64))
            default:
                Issue.record("expected .conflictingFieldType, got \(error.kind)")
            }
        } catch {
            Issue.record("expected IRMergeError, got \(error)")
        }
    }

    @Test("reordered fields with no schema change merges without error")
    func reorderedFieldsMergeWithoutError() throws {
        let humble = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("a", .int32), ("b", .int32)])
        let jazzy = makeIDL(
            package: "demo_msgs", typeName: "Foo",
            primitives: [("b", .int32), ("a", .int32)])
        let ir = try IRBuilder.build(perDistro: ["humble": humble, "jazzy": jazzy])
        // Canonical order is "first distro wins for ordering". Humble walked first.
        #expect(ir.fields.map(\.ros2Name) == ["a", "b"])
        #expect(ir.fields.allSatisfy { $0.availability == .all })
    }
}
