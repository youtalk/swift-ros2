import Testing

@testable import SwiftROS2Gen

@Suite("Parser.parseService")
struct ServiceParserTests {
    @Test("parses a normal request/response service")
    func parsesSetBoolShape() throws {
        let source = """
            bool data
            ---
            bool success
            string message
            """
        let svc = try Parser.parseService(
            source: source,
            file: "std_srvs/srv/SetBool.srv",
            package: "std_srvs",
            typeName: "SetBool"
        )
        #expect(svc.package == "std_srvs")
        #expect(svc.typeName == "SetBool")
        #expect(svc.request.typeName == "SetBool_Request")
        #expect(svc.response.typeName == "SetBool_Response")
        #expect(svc.request.fields.count == 1)
        #expect(svc.request.fields[0].name == "data")
        #expect(svc.response.fields.count == 2)
        #expect(svc.response.fields.map(\.name) == ["success", "message"])
    }

    @Test("parses an empty/empty service (Empty.srv shape)")
    func parsesEmpty() throws {
        let svc = try Parser.parseService(
            source: "---\n",
            file: "std_srvs/srv/Empty.srv",
            package: "std_srvs",
            typeName: "Empty"
        )
        #expect(svc.request.fields.isEmpty)
        #expect(svc.response.fields.isEmpty)
        #expect(svc.request.constants.isEmpty)
        #expect(svc.response.constants.isEmpty)
    }

    @Test("parses an empty-request / non-empty-response service (Trigger.srv shape)")
    func parsesTrigger() throws {
        let source = """
            ---
            bool success
            string message
            """
        let svc = try Parser.parseService(
            source: source,
            file: "std_srvs/srv/Trigger.srv",
            package: "std_srvs",
            typeName: "Trigger"
        )
        #expect(svc.request.fields.isEmpty)
        #expect(svc.response.fields.count == 2)
        #expect(svc.response.fields.map(\.name) == ["success", "message"])
    }

    @Test("rejects a .srv with no '---' separator")
    func rejectsMissingSeparator() {
        do {
            _ = try Parser.parseService(
                source: "bool data\nbool success\n",
                file: "Bad.srv",
                package: "x",
                typeName: "Bad"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.message.contains("'---'"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }

    @Test("rejects a .srv with two or more '---' separators")
    func rejectsDuplicateSeparator() {
        do {
            _ = try Parser.parseService(
                source: "bool data\n---\nbool success\n---\nbool extra\n",
                file: "Bad.srv",
                package: "x",
                typeName: "Bad"
            )
            Issue.record("expected ParseError")
        } catch let error as ParseError {
            #expect(error.message.contains("---"))
        } catch {
            Issue.record("expected ParseError, got \(error)")
        }
    }

    @Test("a request half with constants and arrays parses end-to-end")
    func parsesRequestWithConstantsAndArrays() throws {
        let source = """
            uint8 SUCCESS = 0
            uint8 FAILURE = 1
            uint8 status
            float64[3] coords
            ---
            string message
            """
        let svc = try Parser.parseService(
            source: source,
            file: "Detailed.srv",
            package: "x",
            typeName: "Detailed"
        )
        #expect(svc.request.constants.count == 2)
        #expect(svc.request.constants.map(\.name) == ["SUCCESS", "FAILURE"])
        #expect(svc.request.fields.count == 2)
        #expect(svc.request.fields.map(\.name) == ["status", "coords"])
        #expect(svc.response.fields.count == 1)
    }
}
