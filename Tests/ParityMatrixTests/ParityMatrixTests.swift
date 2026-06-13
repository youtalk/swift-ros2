import Foundation
import XCTest

@testable import ParityMatrix

final class ParityMatrixTests: XCTestCase {
    private func loadSample() throws -> ParityMatrix {
        let url = Bundle.module.url(forResource: "sample-matrix", withExtension: "json")!
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ParityMatrix.self, from: data)
    }

    func testDecodeSample() throws {
        let matrix = try loadSample()
        XCTAssertEqual(matrix.schemaVersion, 1)
        XCTAssertEqual(matrix.capabilities.count, 2)
        let imu = matrix.capabilities[0]
        XCTAssertEqual(imu.id, "publish.typed.sensor_msgs/Imu")
        XCTAssertEqual(imu.rcl, .supported)
        XCTAssertEqual(imu.verification.correctness.verdict, .pending)
        XCTAssertEqual(matrix.capabilities[1].rcl, .pending)
        XCTAssertNil(matrix.capabilities[1].evidence)
    }

    func testRenderMarkdown() throws {
        let matrix = try loadSample()
        let md = matrix.renderMarkdown()
        XCTAssertTrue(md.hasPrefix("# Parity Matrix"))
        XCTAssertTrue(md.contains("| Capability | pure-Swift | RCL | Severity |"))
        XCTAssertTrue(md.contains("publish.typed.sensor_msgs/Imu"))
        XCTAssertTrue(md.contains("subscribe.serialized.sensor_msgs/Image"))
        // Deterministic: rendering twice yields identical output.
        XCTAssertEqual(md, matrix.renderMarkdown())
    }

    func testValidateRejectsDuplicateIDs() throws {
        var matrix = try loadSample()
        matrix.capabilities.append(matrix.capabilities[0])  // duplicate id
        XCTAssertThrowsError(try matrix.validate()) { error in
            XCTAssertTrue("\(error)".contains("duplicate capability id"))
        }
    }

    func testValidateAcceptsCleanMatrix() throws {
        let matrix = try loadSample()
        XCTAssertNoThrow(try matrix.validate())
    }
}
