import Foundation
import Testing

@testable import SwiftROS2Gen

@Suite("Pipeline end-to-end on Vendor std_srvs")
struct ServicePipelineEndToEndTests {
    @Test("generates the three std_srvs services from a curated fixture (srv-only package)")
    func generatesAllStdSrvs() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "std_srvs",
                withExtension: nil,
                subdirectory: "Resources/IDL"
            )
        )
        let files = try Pipeline.generateMulti([
            .init(
                input: PackageInput(name: "std_srvs", directory: fixtureURL, distro: "jazzy"),
                typesAllowList: ["Empty", "SetBool", "Trigger"]
            )
        ])
        let names = Set(files.map(\.relativePath))
        #expect(
            names
                == Set([
                    "StdSrvs/EmptyRequest.swift",
                    "StdSrvs/EmptyResponse.swift",
                    "StdSrvs/EmptySrv.swift",
                    "StdSrvs/SetBoolRequest.swift",
                    "StdSrvs/SetBoolResponse.swift",
                    "StdSrvs/SetBoolSrv.swift",
                    "StdSrvs/TriggerRequest.swift",
                    "StdSrvs/TriggerResponse.swift",
                    "StdSrvs/TriggerSrv.swift",
                ])
        )
    }

    @Test("Empty service halves emit a single 0x00 dummy byte for CycloneDDS compatibility")
    func emptyHalvesEmitDummyByte() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "std_srvs",
                withExtension: nil,
                subdirectory: "Resources/IDL"
            )
        )
        let files = try Pipeline.generateMulti([
            .init(
                input: PackageInput(name: "std_srvs", directory: fixtureURL, distro: "jazzy"),
                typesAllowList: ["Empty"]
            )
        ])
        let request = try #require(
            files.first { $0.relativePath == "StdSrvs/EmptyRequest.swift" }
        )
        #expect(request.contents.contains("encoder.writeUInt8(0)"))
        #expect(request.contents.contains("_ = try decoder.readUInt8()"))
        let response = try #require(
            files.first { $0.relativePath == "StdSrvs/EmptyResponse.swift" }
        )
        #expect(response.contents.contains("encoder.writeUInt8(0)"))
        #expect(response.contents.contains("_ = try decoder.readUInt8()"))
    }

    @Test("SetBool umbrella exposes Request / Response typealiases pointing at the structs")
    func setBoolUmbrellaShape() throws {
        let fixtureURL = try #require(
            Bundle.module.url(
                forResource: "std_srvs",
                withExtension: nil,
                subdirectory: "Resources/IDL"
            )
        )
        let files = try Pipeline.generateMulti([
            .init(
                input: PackageInput(name: "std_srvs", directory: fixtureURL, distro: "jazzy"),
                typesAllowList: ["SetBool"]
            )
        ])
        let umbrella = try #require(
            files.first { $0.relativePath == "StdSrvs/SetBoolSrv.swift" }
        )
        #expect(umbrella.contents.contains("public enum SetBoolSrv: ROS2ServiceType"))
        #expect(umbrella.contents.contains("public typealias Request = SetBoolRequest"))
        #expect(umbrella.contents.contains("public typealias Response = SetBoolResponse"))
        #expect(umbrella.contents.contains("serviceName: \"std_srvs/srv/SetBool\""))
        #expect(umbrella.contents.contains("requestTypeName: \"std_srvs/srv/SetBool_Request\""))
        #expect(umbrella.contents.contains("responseTypeName: \"std_srvs/srv/SetBool_Response\""))
    }
}
