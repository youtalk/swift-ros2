import Testing

@testable import SwiftROS2Gen

@Suite("Generator distro lists")
struct DistroListTests {
    private func makeIDL(_ primitives: [(String, PrimitiveType)]) -> IDLFile {
        let fields = primitives.enumerated().map { index, pair in
            IDLField(name: pair.0, type: .primitive(pair.1), sourceLine: index + 1)
        }
        return IDLFile(package: "sensor_msgs", typeName: "Range", fields: fields)
    }

    @Test("distroOrder lists every supported distro, oldest first")
    func distroOrder() {
        #expect(IRBuilder.distroOrder == ["humble", "jazzy", "kilted", "lyrical", "rolling"])
    }

    @Test("modernDistros is every distro after Humble, Jazzy first")
    func modernDistros() {
        #expect(IRBuilder.modernDistros == ["jazzy", "kilted", "lyrical", "rolling"])
    }

    @Test("a humble + lyrical merge keeps the Lyrical IDL")
    func humbleLyricalMerge() throws {
        let humble = makeIDL([("min_range", .float32), ("max_range", .float32), ("range", .float32)])
        let lyrical = makeIDL([
            ("min_range", .float32), ("max_range", .float32), ("range", .float32), ("variance", .float32),
        ])
        let ir = try IRBuilder.build(perDistro: ["humble": humble, "lyrical": lyrical])
        #expect(ir.fields.map(\.ros2Name) == ["min_range", "max_range", "range", "variance"])
        #expect(ir.fields[3].availability == .onlyIn(["lyrical"]))
        #expect(ir.perDistroFieldPresence["lyrical"]?.count == 4)
    }

    @Test("a Lyrical-only field emits behind the modern-schema guard without trapping")
    func lyricalOnlyFieldEmits() {
        let field = FieldIR(
            ros2Name: "variance", swiftName: "variance", type: .primitive(.float32),
            availability: .onlyIn(["lyrical"]))
        #expect(SwiftEmitter.emitEncodeWithAvailability(field).contains("if !encoder.isLegacySchema {"))
        #expect(
            SwiftEmitter.emitDecodeWithAvailability(field, nestedNameOverrides: [:])
                .contains("decoder.isLegacySchema"))
    }

    @Test("the modern typeInfo arm lists Lyrical and falls back to a Lyrical-only hash")
    func typeInfoFactoryModernArm() {
        let ir = MessageIR(
            package: "demo_msgs", typeName: "Foo", fields: [],
            perDistroHashes: ["lyrical": "RIHS01_lyrical"], perDistroFieldPresence: [:])
        let out = SwiftEmitter.emitTypeInfoFactory(ir)
        #expect(out.contains("        case .jazzy, .kilted, .lyrical, .rolling:\n"))
        #expect(out.contains("typeHash: \"RIHS01_lyrical\""))
    }
}
