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
}
