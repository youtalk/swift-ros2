import Testing

@testable import SwiftROS2Gen

@Suite("IRBuilder for .srv halves")
struct ServiceIRBuilderTests {
    @Test("synthesizes Request and Response MessageIRs with .srv kind and correct rosTypeName")
    func synthesizesHalves() throws {
        let svc = try Parser.parseService(
            source: """
                bool data
                ---
                bool success
                string message
                """,
            file: "std_srvs/srv/SetBool.srv",
            package: "std_srvs",
            typeName: "SetBool"
        )
        let request = IRBuilder.build(jazzy: svc.request, kind: .srv)
        let response = IRBuilder.build(jazzy: svc.response, kind: .srv)
        #expect(request.package == "std_srvs")
        #expect(request.typeName == "SetBool_Request")
        #expect(request.kind == .srv)
        #expect(request.rosTypeName == "std_srvs/srv/SetBool_Request")
        #expect(request.fields.map(\.swiftName) == ["data"])
        #expect(response.typeName == "SetBool_Response")
        #expect(response.kind == .srv)
        #expect(response.rosTypeName == "std_srvs/srv/SetBool_Response")
        #expect(response.fields.map(\.swiftName) == ["success", "message"])
    }

    @Test("empty service halves produce zero-field IRs that retain .srv kind")
    func emptyService() throws {
        let svc = try Parser.parseService(
            source: "---\n",
            file: "std_srvs/srv/Empty.srv",
            package: "std_srvs",
            typeName: "Empty"
        )
        let request = IRBuilder.build(jazzy: svc.request, kind: .srv)
        let response = IRBuilder.build(jazzy: svc.response, kind: .srv)
        #expect(request.fields.isEmpty)
        #expect(response.fields.isEmpty)
        #expect(request.kind == .srv)
        #expect(response.kind == .srv)
        #expect(request.rosTypeName == "std_srvs/srv/Empty_Request")
        #expect(response.rosTypeName == "std_srvs/srv/Empty_Response")
    }
}
